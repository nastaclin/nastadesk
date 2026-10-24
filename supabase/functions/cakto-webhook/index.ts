// NastaDesk — Webhook da Cakto (assinaturas)
// Estrutura do payload (confirmada via evento de teste):
//   body.event   -> nome do evento (subscription_created/renewed/canceled/renewal_refused, etc.)
//   body.secret  -> secret configurado no webhook (validado)
//   body.data.customer.email      -> e-mail do comprador (mapeia a clínica)
//   body.data.baseAmount / amount -> valor (identifica plano E período: mensal 97/197/347,
//                                    trimestral 262/532/937, anual 931/1891/3331)
//   body.data.subscription.id     -> id da assinatura recorrente (provider_id)
//   body.data.subscription.status -> active/canceled/...
// Segurança: valida o secret; mapeia por e-mail; NUNCA derruba clínica em cortesia.
// v6 (2026-10-24): grava proximo_pagamento ao liberar e, no cancelamento "puro",
// mantém o acesso até essa data (o cron encerrar_assinaturas_canceladas corta depois).
// Reembolso/chargeback continuam cortando na hora.
//
// O secret esperado e o mapa opcional de planos vêm de public.admin_config:
//   key 'cakto_webhook_secret' -> { "secret": "..." }
//   key 'cakto_planos'         -> { "<offer_id|product_id>": "basico|profissional|premium", ... }
// 'cakto_debug' guarda uma auditoria enxuta dos últimos eventos (sem PII além do e-mail).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const db = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
const agora = () => new Date().toISOString();

// Comparação de segredos em tempo constante (evita timing attack).
// Usa "double HMAC" com chave aleatória: também não vaza o comprimento do segredo.
async function segredoConfere(recebido: string, esperado: string): Promise<boolean> {
  if (!esperado) return false; // fail-closed: sem segredo configurado, nada passa
  try {
    const chave = crypto.getRandomValues(new Uint8Array(32));
    const k = await crypto.subtle.importKey("raw", chave, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
    const enc = new TextEncoder();
    const a = new Uint8Array(await crypto.subtle.sign("HMAC", k, enc.encode(recebido)));
    const b = new Uint8Array(await crypto.subtle.sign("HMAC", k, enc.encode(esperado)));
    let diff = 0;
    for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
    return diff === 0;
  } catch {
    return false;
  }
}

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Preço oficial por plano × período (espelha public.nastadesk_preco no banco).
// Mensal 97/197/347 · Trimestral -10% · Anual -20% (arredondado).
const PRECO: Record<string, Record<string, number>> = {
  mensal: { basico: 97, profissional: 197, premium: 347 },
  trimestral: { basico: 262, profissional: 532, premium: 937 },
  anual: { basico: 931, profissional: 1891, premium: 3331 },
};

function pick(obj: any, paths: string[]): any {
  for (const p of paths) {
    const v = p.split(".").reduce((o: any, k: string) => (o == null ? undefined : o[k]), obj);
    if (v !== undefined && v !== null && v !== "") return v;
  }
  return undefined;
}

// Descobre plano E período pelo valor pago. Aceita reais e centavos.
// Sem isto, uma compra anual (ex.: 3331) não casaria com nenhum plano e cairia
// no fallback — liberando o plano errado para quem nunca teve plano.
function planoEPeriodoPorValor(v: any): { plano: string; periodo: string } | null {
  const n = Number(v) || 0;
  const candidatos = [Math.round(n), Math.round(n / 100)]; // reais ou centavos
  for (const alvo of candidatos) {
    if (!alvo) continue;
    for (const periodo of ["mensal", "trimestral", "anual"]) {
      for (const [plano, preco] of Object.entries(PRECO[periodo])) {
        if (Math.abs(alvo - preco) <= 1) return { plano, periodo }; // tolera 1 real de arredondamento
      }
    }
  }
  return null;
}

// Período pelo valor quando o plano veio pelo id da oferta (admin_config.cakto_planos).
function periodoPorValor(v: any, plano: string): string {
  const n = Number(v) || 0;
  for (const alvo of [Math.round(n), Math.round(n / 100)]) {
    if (!alvo) continue;
    for (const periodo of ["mensal", "trimestral", "anual"]) {
      const preco = PRECO[periodo][plano];
      if (preco && Math.abs(alvo - preco) <= 1) return periodo;
    }
  }
  return "mensal";
}

// Fim do período pago a partir de agora (fallback quando a Cakto não manda a data).
function fimDoPeriodo(periodo: string): string {
  const d = new Date();
  if (periodo === "anual") d.setFullYear(d.getFullYear() + 1);
  else if (periodo === "trimestral") d.setMonth(d.getMonth() + 3);
  else d.setMonth(d.getMonth() + 1);
  return d.toISOString();
}

async function segredoEsperado(): Promise<string> {
  const env = Deno.env.get("CAKTO_WEBHOOK_SECRET");
  if (env) return env;
  const { data } = await db.from("admin_config").select("value").eq("key", "cakto_webhook_secret").maybeSingle();
  const v: any = data?.value;
  return (v && (v.secret || v)) || "";
}

async function planoPorId(offerId: any, productId: any): Promise<string | null> {
  try {
    const { data } = await db.from("admin_config").select("value").eq("key", "cakto_planos").maybeSingle();
    const m: any = data?.value || {};
    return (offerId && m[offerId]) || (productId && m[productId]) || null;
  } catch { return null; }
}

async function auditar(rec: any) {
  try {
    const { data: cur } = await db.from("admin_config").select("value").eq("key", "cakto_debug").maybeSingle();
    const arr = Array.isArray((cur?.value as any)?.eventos) ? (cur!.value as any).eventos : [];
    arr.unshift(rec);
    await db.from("admin_config").upsert({ key: "cakto_debug", value: { eventos: arr.slice(0, 20) }, updated_at: agora() });
  } catch (_e) { /* auditoria nunca quebra o fluxo */ }
}

// Cupom de parceiro: o cliente aplica o cupom ANTES de ir ao checkout (fica
// "pendente"). Quando o pagamento é confirmado aqui, marcamos como "confirmado"
// — é isso que vira comissão a pagar no painel admin. Tolerante a falha: um erro
// aqui NUNCA pode impedir a liberação do acesso da clínica.
async function confirmarCupom(clinicaId: string) {
  try {
    await db.from("cupom_usos")
      .update({ status: "confirmado", confirmado_em: agora() })
      .eq("clinica_id", clinicaId)
      .eq("contexto", "assinatura")
      .eq("status", "pendente");
  } catch (e) { console.warn("CAKTO: nao consegui confirmar cupom:", e); }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return new Response("ok", { headers: cors });

  let raw = "";
  try { raw = await req.text(); } catch { /* ignore */ }
  let body: any = null;
  try { body = raw ? JSON.parse(raw) : null; } catch { /* ignore */ }

  const evento = String((body && (body.event || body.type)) || "").toLowerCase();
  const email = String(pick(body, ["data.customer.email", "data.subscription.customer.email", "data.customer_email", "customer.email", "email"]) || "").trim().toLowerCase();
  const offerId = pick(body, ["data.offer.id", "data.subscription.offer"]);
  const productId = pick(body, ["data.product.id", "data.subscription.product"]);
  const valor = pick(body, ["data.baseAmount", "data.subscription.amount", "data.amount", "data.offer.price"]);
  const subId = pick(body, ["data.subscription.id", "data.subscription_id", "data.id"]);
  const payStatus = String(pick(body, ["data.status"]) || "").toLowerCase();
  const subStatus = String(pick(body, ["data.subscription.status"]) || "").toLowerCase();

  const esperado = await segredoEsperado();
  const recebidoSecret = String(pick(body, ["secret", "data.secret"]) || req.headers.get("x-cakto-signature") || req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  // fail-closed: exige segredo configurado E idêntico (comparação em tempo constante)
  const secretConfigurado = !!esperado;
  const secretOk = await segredoConfere(recebidoSecret, esperado);

  const corta = /cancel|refund|reembols|charge|estorn/.test(evento) || /cancel|refund|charge/.test(subStatus);
  const atraso = !corta && /refus|recus|atras/.test(evento);
  const libera = !corta && !atraso && (/created|renew|renov|approved|aprovad|paid|pago|active|ativ/.test(evento) || payStatus === "paid" || subStatus === "active");

  await auditar({ ts: agora(), event: evento, email, valor, sub_id: subId ? String(subId) : null, secret_ok: secretOk, classe: corta ? "corta" : atraso ? "atraso" : libera ? "libera" : "nenhuma" });

  if (!secretConfigurado) {
    console.error("CAKTO: segredo do webhook NÃO configurado — recusando por segurança (fail-closed). Defina admin_config.cakto_webhook_secret ou a env CAKTO_WEBHOOK_SECRET.");
    return new Response("webhook secret not configured", { status: 503, headers: cors });
  }
  if (!secretOk) { console.warn("CAKTO: secret inválido"); return new Response("invalid secret", { status: 401, headers: cors }); }
  if (!body || !email) return new Response("ok", { headers: cors });

  try {
    const { data: clinica } = await db.from("clinicas").select("id, plano, ativo, cortesia").ilike("email", email).maybeSingle();
    if (!clinica) { console.warn("CAKTO: e-mail sem clínica:", email); return new Response("ok", { headers: cors }); }

    if (libera) {
      const porValor = planoEPeriodoPorValor(valor);
      const planoPorOferta = await planoPorId(offerId, productId);
      const plano = planoPorOferta || porValor?.plano || clinica.plano || "profissional";
      const periodo = planoPorOferta ? periodoPorValor(valor, plano) : (porValor?.periodo || "mensal");
      await db.from("clinicas").update({ plano, ativo: true }).eq("id", clinica.id);
      let assId: string | null = null;
      if (subId) {
        const { data: ex } = await db.from("assinaturas").select("id").eq("provedor", "cakto").eq("provider_id", String(subId)).maybeSingle();
        assId = ex?.id || null;
      }
      if (!assId) {
        const { data: ex2 } = await db.from("assinaturas").select("id").eq("provedor", "cakto").eq("clinica_id", clinica.id).in("status", ["ativa", "pendente", "em_atraso"]).order("criado_em", { ascending: false }).limit(1).maybeSingle();
        assId = ex2?.id || null;
      }
      // v6: guarda até quando está pago — quem cancela usa até essa data (o corte
      // é feito pelo cron encerrar_assinaturas_canceladas). Usa a data da Cakto
      // quando vier no payload; senão, agora + duração do período.
      const proxCakto = pick(body, ["data.subscription.next_payment_date", "data.subscription.nextPaymentDate", "data.next_payment_date"]);
      const proximo = proxCakto && !isNaN(Date.parse(String(proxCakto)))
        ? new Date(String(proxCakto)).toISOString()
        : fimDoPeriodo(periodo);
      const patch: any = { clinica_id: clinica.id, plano, periodo, provedor: "cakto", provider_id: subId ? String(subId) : null, status: "ativa", em_atraso_desde: null, valor: PRECO[periodo]?.[plano] ?? null, payer_email: email, proximo_pagamento: proximo, atualizado_em: agora() };
      if (assId) await db.from("assinaturas").update(patch).eq("id", assId);
      else await db.from("assinaturas").insert(patch);
      await confirmarCupom(clinica.id);
      console.log("CAKTO: liberado", email, plano, periodo);
      return new Response("ok", { headers: cors });
    }

    if (atraso) {
      if (subId) {
        const { data: ex } = await db.from("assinaturas").select("id, em_atraso_desde").eq("provedor", "cakto").eq("provider_id", String(subId)).maybeSingle();
        if (ex) await db.from("assinaturas").update({ status: "em_atraso", em_atraso_desde: ex.em_atraso_desde || agora(), atualizado_em: agora() }).eq("id", ex.id);
      }
      // NÃO mexe no acesso: a Cakto ainda tenta cobrar de novo. Só corta no cancelamento.
      console.log("CAKTO: renovação recusada (em atraso, acesso mantido)", email);
      return new Response("ok", { headers: cors });
    }

    if (corta) {
      // v6: cancelamento "puro" (o cliente parou de pagar daqui pra frente) mantém o
      // acesso até o fim do período já pago. Reembolso/chargeback cortam na hora.
      const soCancelamento = /cancel/.test(evento) && !/refund|reembols|charge|estorn/.test(evento);
      let pagoAte: string | null = null;
      {
        let q = db.from("assinaturas").select("proximo_pagamento").eq("provedor", "cakto");
        q = subId ? q.eq("provider_id", String(subId)) : q.eq("clinica_id", clinica.id).in("status", ["ativa", "pendente", "em_atraso"]);
        const { data: atual } = await q.order("criado_em", { ascending: false }).limit(1).maybeSingle();
        pagoAte = (atual as any)?.proximo_pagamento || null;
      }
      if (subId) {
        await db.from("assinaturas").update({ status: "cancelada", cancelada_em: agora(), atualizado_em: agora() }).eq("provedor", "cakto").eq("provider_id", String(subId));
      } else {
        await db.from("assinaturas").update({ status: "cancelada", cancelada_em: agora(), atualizado_em: agora() }).eq("provedor", "cakto").eq("clinica_id", clinica.id).in("status", ["ativa", "pendente", "em_atraso"]);
      }
      if (clinica.cortesia === true) {
        console.log("CAKTO: cortesia — acesso preservado", email);
      } else if (soCancelamento && pagoAte && new Date(pagoAte) > new Date()) {
        console.log("CAKTO: cancelado — acesso mantido até o fim do período pago", email, pagoAte);
      } else {
        const { data: ativa } = await db.from("assinaturas").select("id").eq("clinica_id", clinica.id).eq("status", "ativa").maybeSingle();
        if (!ativa) await db.from("clinicas").update({ ativo: false }).eq("id", clinica.id);
      }
      console.log("CAKTO: cancelado/reembolso/chargeback", email);
      return new Response("ok", { headers: cors });
    }

    console.log("CAKTO: evento sem ação:", evento);
    return new Response("ok", { headers: cors });
  } catch (e) {
    console.error("CAKTO webhook erro:", e);
    return new Response("ok", { headers: cors });
  }
});
