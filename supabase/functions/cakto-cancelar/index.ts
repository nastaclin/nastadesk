// =============================================================================
// cakto-cancelar — o dono da clínica cancela a assinatura dentro do NastaDesk e
// o cancelamento acontece direto na Cakto (API pública).
//
// Fluxo:
//   1. Valida o login (JWT do usuário) e confirma que ele é o DONO da clínica.
//   2. Pega a assinatura Cakto viva da clínica (tabela assinaturas).
//   3. Obtém token OAuth da Cakto (client_id/secret em secrets do Supabase).
//   4. Acha o id da assinatura na Cakto (provider_id; se não bater, busca pelo
//      e-mail do pagador) e chama POST /subscriptions/{id}/cancel/.
//   5. Marca a assinatura como 'cancelada' no NastaDesk SEM tirar o acesso:
//      a clínica usa até o fim do período já pago (proximo_pagamento).
//
// Secrets necessários (supabase secrets set ...):
//   CAKTO_CLIENT_ID, CAKTO_CLIENT_SECRET  — chave de API criada no painel da
//   Cakto com escopo "subscriptions" (read + write).
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY já existem.
//
// Docs Cakto: https://docs.cakto.com.br/api-reference/subscriptions/cancel.md
// =============================================================================
import { createClient } from 'npm:@supabase/supabase-js@2';

const CAKTO_API = 'https://api.cakto.com.br/public_api';
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const VIVAS_CAKTO = ['active', 'late', 'trial', 'paused'];

function resposta(corpo: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(corpo), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });
}

async function tokenCakto(): Promise<string> {
  const r = await fetch(`${CAKTO_API}/token/`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: Deno.env.get('CAKTO_CLIENT_ID') ?? '',
      client_secret: Deno.env.get('CAKTO_CLIENT_SECRET') ?? '',
    }),
  });
  if (!r.ok) throw new Error(`token Cakto ${r.status}`);
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

    // Só o dono cancela (clinicas.user_id = dono).
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

    if (sub.status !== 'canceled') {
      const r = await fetch(`${CAKTO_API}/subscriptions/${sub.id}/cancel/`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!r.ok) {
        const det = await r.json().catch(() => ({}));
        console.error('cakto cancel', r.status, det);
        return resposta({ ok: false, erro: 'A Cakto não aceitou o cancelamento agora.', fallback: true }, 502);
      }
    }

    // Acesso continua até o fim do período pago: só muda o status da assinatura.
    // O corte acontece quando proximo_pagamento passar (cron encerrar_assinaturas_canceladas);
    // o cakto-webhook v6 recebe o evento de cancelamento e também mantém o acesso até lá.
    const { error: errUpd } = await admin.from('assinaturas').update({
      status: 'cancelada',
      cancelada_em: new Date().toISOString(),
      atualizado_em: new Date().toISOString(),
    }).eq('id', ass.id);
    if (errUpd) console.error('assinaturas update', errUpd); // já cancelou na Cakto; o webhook sincroniza

    await admin.rpc('registrar_auditoria', {
      p_paciente_id: null, p_acao: 'cancelou_assinatura', p_detalhe: `cakto:${sub.id}`, p_user_agent: 'edge:cakto-cancelar',
    }).then(() => {}, () => {});

    return resposta({ ok: true, acesso_ate: ass.proximo_pagamento ?? null });
  } catch (e) {
    console.error('cakto-cancelar', e);
    return resposta({ ok: false, erro: 'Erro ao cancelar. Tente novamente.', fallback: true }, 500);
  }
});
