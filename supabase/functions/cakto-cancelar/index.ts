// =============================================================================
// cakto-cancelar — o dono da clínica cancela a assinatura dentro do NastaDesk e
// tudo acontece direto na Cakto (API pública), sem passar pelo suporte.
//
// v3 (2026-10-24): DIREITO DE ARREPENDIMENTO (CDC art. 49).
//   - Até 7 dias corridos da PRIMEIRA compra paga da assinatura: o cancelamento
//     vira REEMBOLSO integral (POST /orders/{id}/refund/). Na Cakto, reembolsar
//     devolve o dinheiro e encerra a assinatura; o acesso pago acaba na hora
//     (o cakto-webhook recebe "refund" e corta, preservando o teste grátis se houver).
//   - Depois disso: só CANCELA (POST /subscriptions/{id}/cancel/). Nada mais é
//     cobrado e a clínica usa até o fim do período já pago (proximo_pagamento);
//     quem corta depois é o pg_cron nastadesk-assinatura-expira.
//   - Renovações (2ª cobrança em diante) não têm arrependimento: só cancelam.
//
// Fluxo:
//   1. Valida o login (JWT do usuário) e confirma que ele é o DONO da clínica.
//   2. Pega a assinatura Cakto viva da clínica (tabela assinaturas).
//   3. Obtém token OAuth da Cakto (client_id/secret em secrets do Supabase).
//   4. Acha a assinatura na Cakto (provider_id; se não bater, busca pelo e-mail).
//   5. Reembolsa (dentro dos 7 dias) ou cancela, e atualiza a tabela assinaturas.
//
// Secrets necessários: CAKTO_CLIENT_ID, CAKTO_CLIENT_SECRET — chave de API criada
// no painel da Cakto com os escopos "subscriptions" e "orders" (leitura e escrita).
// SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY já existem.
//
// Docs Cakto: api-reference/subscriptions/cancel · api-reference/orders/refund
// =============================================================================
import { createClient } from 'npm:@supabase/supabase-js@2';

const CAKTO_API = 'https://api.cakto.com.br/public_api';
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const VIVAS_CAKTO = ['active', 'late', 'trial', 'paused'];
const PRAZO_ARREPENDIMENTO_MS = 7 * 24 * 60 * 60 * 1000;

function resposta(corpo: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(corpo), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });
}

async function tokenCakto(): Promise<string> {
  // trim: espaço/quebra de linha colados junto com a chave no painel do Supabase
  // fazem a Cakto responder 401 invalid_client.
  const clientId = (Deno.env.get('CAKTO_CLIENT_ID') ?? '').trim().replace(/^["']|["']$/g, '');
  const clientSecret = (Deno.env.get('CAKTO_CLIENT_SECRET') ?? '').trim().replace(/^["']|["']$/g, '');
  const r = await fetch(`${CAKTO_API}/token/`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: clientId, client_secret: clientSecret }),
  });
  if (!r.ok) {
    // Diagnóstico sem expor o segredo: início do client_id (não é secreto) e tamanhos.
    const det = await r.text().catch(() => '');
    // Nomes (nunca valores) das variáveis com "cakto" que a função enxerga: mostra
    // se o secret foi salvo com outro nome (minúscula, espaço, prefixo...).
    const nomes = Object.keys(Deno.env.toObject()).filter((k) => /cakto/i.test(k)).map((k) => JSON.stringify(k)).join(', ');
    console.error('token Cakto', r.status, det.slice(0, 200),
      `client_id=${clientId.slice(0, 6)}… (${clientId.length} car.) secret=${clientSecret.length} car.`,
      `variáveis com "cakto": [${nomes}]`);
    throw new Error(`token Cakto ${r.status}`);
  }
  const j = await r.json();
  return j.access_token;
}

// provider_id pode ser o id da assinatura ou de um pedido, dependendo de como
// o webhook gravou. Tenta direto; se não for assinatura, procura pelo e-mail.
async function acharAssinaturaCakto(token: string, providerId: string | null, email: string | null) {
  const h = { Authorization: `Bearer ${token}` };
  if (providerId) {
    const r = await fetch(`${CAKTO_API}/subscriptions/${encodeURIComponent(providerId)}/`, { headers: h });
    if (r.ok) return await r.json();
  }
  if (email) {
    const r = await fetch(`${CAKTO_API}/subscriptions/?search=${encodeURIComponent(email)}&limit=20`, { headers: h });
    if (r.ok) {
      const j = await r.json();
      const vivas = (j.results ?? []).filter((s: { status: string }) => VIVAS_CAKTO.includes(s.status));
      if (vivas.length === 1) return vivas[0];
      if (vivas.length > 1) throw new Error('mais de uma assinatura ativa com este e-mail');
    }
  }
  return null;
}

// A primeira compra paga da assinatura ainda está dentro dos 7 dias?
// Devolve o pedido a reembolsar, ou null (fora do prazo / já renovou / sem dado).
async function pedidoReembolsavel(token: string, sub: any): Promise<{ id: string; valor: number | null } | null> {
  const pagos = Number(sub.paid_payments_quantity ?? 0);
  if (pagos > 1) return null;                       // já renovou: arrependimento é só da contratação
  const pedidoId = sub.parent_order;
  if (!pedidoId) return null;
  const r = await fetch(`${CAKTO_API}/orders/${encodeURIComponent(pedidoId)}/`, { headers: { Authorization: `Bearer ${token}` } });
  if (!r.ok) return null;
  const pedido = await r.json();
  if (String(pedido.status ?? '').toLowerCase() !== 'paid') return null;
  const pagoEm = Date.parse(pedido.paidAt ?? '');
  if (isNaN(pagoEm) || Date.now() - pagoEm > PRAZO_ARREPENDIMENTO_MS) return null;
  const valor = Number(pedido.amount ?? pedido.baseAmount);
  return { id: pedidoId, valor: isNaN(valor) ? null : valor };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return resposta({ ok: false, erro: 'Método não permitido' }, 405);

  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const jwt = (req.headers.get('Authorization') ?? '').replace('Bearer ', '');
    const anon = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!);
    const { data: { user } } = await anon.auth.getUser(jwt);
    if (!user) return resposta({ ok: false, erro: 'Faça login novamente.' }, 401);

    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

    // Só o dono cancela (clinicas.user_id = dono; recepção/profissional ficam em clinica_membros).
    const { data: clinica } = await admin.from('clinicas').select('id, nome').eq('user_id', user.id).maybeSingle();
    if (!clinica) return resposta({ ok: false, erro: 'Só o responsável pela clínica pode cancelar a assinatura.' }, 403);

    const { data: ass } = await admin.from('assinaturas').select('*')
      .eq('clinica_id', clinica.id).eq('provedor', 'cakto')
      .in('status', ['ativa', 'em_atraso'])
      .order('criado_em', { ascending: false }).limit(1).maybeSingle();
    if (!ass) return resposta({ ok: false, erro: 'Não encontramos uma assinatura ativa para cancelar.' }, 404);

    const token = await tokenCakto();
    const sub = await acharAssinaturaCakto(token, ass.provider_id, ass.payer_email ?? user.email ?? null);
    if (!sub) return resposta({ ok: false, erro: 'Não localizamos a assinatura na Cakto.', fallback: true }, 404);

    const agora = new Date().toISOString();
    const h = { Authorization: `Bearer ${token}` };

    // ---- Dentro dos 7 dias: reembolso integral (direito de arrependimento) ----
    const reembolsavel = sub.status !== 'canceled' ? await pedidoReembolsavel(token, sub) : null;
    if (reembolsavel) {
      const r = await fetch(`${CAKTO_API}/orders/${encodeURIComponent(reembolsavel.id)}/refund/`, { method: 'POST', headers: h });
      if (!r.ok) {
        const det = await r.json().catch(() => ({}));
        console.error('cakto refund', r.status, det);
        return resposta({ ok: false, erro: 'A Cakto não aceitou o reembolso agora.', fallback: true }, 502);
      }
      // O reembolso já encerra a assinatura na Cakto; por garantia, pede o cancelamento
      // também (um 400 aqui só quer dizer que ela já estava cancelada).
      await fetch(`${CAKTO_API}/subscriptions/${sub.id}/cancel/`, { method: 'POST', headers: h }).catch(() => null);

      const { error: errUpd } = await admin.from('assinaturas').update({
        status: 'cancelada', cancelada_em: agora, atualizado_em: agora, proximo_pagamento: agora,
      }).eq('id', ass.id);
      if (errUpd) console.error('assinaturas update', errUpd); // o webhook "refund" sincroniza

      await admin.from('auditoria').insert({
        clinica_id: clinica.id, user_id: user.id, paciente_id: null,
        acao: 'reembolsou_assinatura', detalhe: `cakto:${sub.id} pedido:${reembolsavel.id} valor:${reembolsavel.valor ?? '-'}`, user_agent: 'edge:cakto-cancelar',
      }).then(() => {}, () => {});

      return resposta({ ok: true, reembolsado: true, valor: reembolsavel.valor });
    }

    // ---- Fora dos 7 dias: só cancela; o acesso vai até o fim do período pago ----
    if (sub.status !== 'canceled') {
      const r = await fetch(`${CAKTO_API}/subscriptions/${sub.id}/cancel/`, { method: 'POST', headers: h });
      if (!r.ok) {
        const det = await r.json().catch(() => ({}));
        console.error('cakto cancel', r.status, det);
        return resposta({ ok: false, erro: 'A Cakto não aceitou o cancelamento agora.', fallback: true }, 502);
      }
    }

    // Quem corta depois é o pg_cron nastadesk-assinatura-expira, quando
    // proximo_pagamento passar. O cakto-webhook v6 também não corta no cancelamento.
    const acessoAte: string | null = ass.proximo_pagamento ?? sub.next_payment_date ?? null;
    const { error: errUpd } = await admin.from('assinaturas').update({
      status: 'cancelada',
      cancelada_em: agora,
      atualizado_em: agora,
      proximo_pagamento: acessoAte,
    }).eq('id', ass.id);
    if (errUpd) console.error('assinaturas update', errUpd); // já cancelou na Cakto; o webhook sincroniza

    // Direto na tabela: a RPC registrar_auditoria depende de auth.uid(), que é nulo com a service_role.
    await admin.from('auditoria').insert({
      clinica_id: clinica.id, user_id: user.id, paciente_id: null,
      acao: 'cancelou_assinatura', detalhe: `cakto:${sub.id} acesso_ate:${acessoAte ?? '-'}`, user_agent: 'edge:cakto-cancelar',
    }).then(() => {}, () => {});

    return resposta({ ok: true, reembolsado: false, acesso_ate: acessoAte });
  } catch (e) {
    console.error('cakto-cancelar', e);
    return resposta({ ok: false, erro: 'Erro ao cancelar. Tente novamente.', fallback: true }, 500);
  }
});
