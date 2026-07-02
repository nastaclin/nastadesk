// NastaDesk — Webhook da Cakto (assinaturas)
// Estrutura do payload (confirmada via evento de teste):
//   body.event   -> nome do evento (subscription_created/renewed/canceled/renewal_refused, etc.)
//   body.secret  -> secret configurado no webhook (validado)
//   body.data.customer.email      -> e-mail do comprador (mapeia a clínica)
//   body.data.baseAmount / amount -> valor (identifica o plano: 97/197/347)
//   body.data.subscription.id     -> id da assinatura recorrente (provider_id)
//   body.data.subscription.status -> active/canceled/...
// Segurança: valida o secret; mapeia por e-mail; NUNCA derruba clínica em cortesia.
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

const PRECO: Record<string, number> = { basico: 97, profissional: 197, premium: 347 };

function pick(obj: any, paths: string[]): any {
  for (const p of paths) {
    const v = p.split(".").reduce((o: any, k: string) => (o == null ? undefined : o[k]), obj);
    if (v !== undefined && v !== null && v !== "") return v;
  }
  return undefined;
}

function planoPorValor(v: any): string | null {
  const n = Math.round(Number(v) || 0);
  const map: Record<number, string> = { 97: "basico", 197: "profissional", 347: "premium", 9700: "basico", 19700: "profissional", 34700: "premium" };
  return map[n] || null;
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
      const plano = (await planoPorId(offerId, productId)) || planoPorValor(valor) || clinica.plano || "profissional";
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
      const patch: any = { clinica_id: clinica.id, plano, provedor: "cakto", provider_id: subId ? String(subId) : null, status: "ativa", em_atraso_desde: null, valor: PRECO[plano] ?? null, payer_email: email, atualizado_em: agora() };
      if (assId) await db.from("assinaturas").update(patch).eq("id", assId);
      else await db.from("assinaturas").insert(patch);
      console.log("CAKTO: liberado", email, plano);
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
      if (subId) {
        await db.from("assinaturas").update({ status: "cancelada", cancelada_em: agora(), atualizado_em: agora() }).eq("provedor", "cakto").eq("provider_id", String(subId));
      } else {
        await db.from("assinaturas").update({ status: "cancelada", cancelada_em: agora(), atualizado_em: agora() }).eq("provedor", "cakto").eq("clinica_id", clinica.id).in("status", ["ativa", "pendente", "em_atraso"]);
      }
      if (clinica.cortesia === true) {
        console.log("CAKTO: cortesia — acesso preservado", email);
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
