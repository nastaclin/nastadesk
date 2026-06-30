// NastaDesk — Webhook da Cakto (assinaturas)
// Recebe os eventos da Cakto e ativa/suspende o plano da clínica.
// - Mapeia o comprador -> clínica pelo E-MAIL (a clínica paga com o e-mail da conta).
// - Identifica o plano pelo VALOR (97 = Básica, 197 = Profissional, 347 = Premium).
// - É tolerante a falhas e NUNCA derruba o acesso de uma clínica em cortesia.
// - Loga o payload bruto para podermos conferir os nomes exatos dos campos no
//   primeiro "evento de teste" e ajustar com precisão.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const db = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
const agora = () => new Date().toISOString();

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const PRECO: Record<string, number> = { basico: 97, profissional: 197, premium: 347 };

// Lê o primeiro caminho que existir (ex.: "data.customer.email").
function pick(obj: any, paths: string[]): any {
  for (const p of paths) {
    const v = p.split(".").reduce((o: any, k: string) => (o == null ? undefined : o[k]), obj);
    if (v !== undefined && v !== null && v !== "") return v;
  }
  return undefined;
}

// Identifica o plano pelo valor pago. Aceita reais (97/197/347) ou centavos.
function planoPorValor(v: any): string | null {
  const n = Math.round(Number(v) || 0);
  const map: Record<number, string> = {
    97: "basico", 197: "profissional", 347: "premium",
    9700: "basico", 19700: "profissional", 34700: "premium",
  };
  return map[n] || null;
}

// Secret esperado: variável de ambiente CAKTO_WEBHOOK_SECRET ou admin_config.
async function segredoEsperado(): Promise<string> {
  const env = Deno.env.get("CAKTO_WEBHOOK_SECRET");
  if (env) return env;
  const { data } = await db.from("admin_config").select("value").eq("key", "cakto_webhook_secret").maybeSingle();
  const v: any = data?.value;
  return (v && (v.secret || v)) || "";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return new Response("ok", { headers: cors });

  let raw = "";
  try { raw = await req.text(); } catch { /* ignore */ }
  let body: any = null;
  try { body = raw ? JSON.parse(raw) : null; } catch { /* ignore */ }

  // Log para inspeção do payload (evento de teste). Truncado.
  console.log("CAKTO webhook:", (raw || "").slice(0, 4000));

  // ----- Verificação do secret (só bloqueia se já estiver configurado) -----
  const esperado = await segredoEsperado();
  if (esperado) {
    const recebido = pick(body, ["secret", "data.secret"]) ||
      req.headers.get("x-cakto-signature") || req.headers.get("authorization") || "";
    const limpo = String(recebido).replace(/^Bearer\s+/i, "");
    if (limpo !== esperado) {
      console.warn("CAKTO: secret inválido");
      return new Response("invalid secret", { status: 401, headers: cors });
    }
  }

  if (!body) return new Response("ok", { headers: cors });

  const evento = String(pick(body, ["event", "type", "data.event", "status", "data.status"]) || "").toLowerCase();
  const email = String(pick(body, [
    "data.customer.email", "customer.email", "data.customer_email", "customer_email",
    "data.buyer.email", "buyer.email", "email",
  ]) || "").trim().toLowerCase();
  const valor = pick(body, ["data.amount", "amount", "data.offer.price", "data.product.price", "data.total", "total", "price"]);
  const subId = pick(body, ["data.subscription.id", "subscription.id", "data.subscription_id", "subscription_id", "data.id", "id", "data.order.id"]);

  const planoValor = planoPorValor(valor);
  const libera = /approved|paid|aprovad|created|renewed|renovad|active|\bativa\b/.test(evento);
  const suspende = /cancel|refus|recus|refund|reembols|chargeback|expired|expirad/.test(evento);

  try {
    if (!email) { console.warn("CAKTO: payload sem e-mail; nada a fazer"); return new Response("ok", { headers: cors }); }

    const { data: clinica } = await db.from("clinicas")
      .select("id, plano, ativo, cortesia").ilike("email", email).maybeSingle();
    if (!clinica) { console.warn("CAKTO: e-mail não corresponde a nenhuma clínica:", email); return new Response("ok", { headers: cors }); }

    // ---- Libera acesso (compra aprovada / assinatura criada ou renovada) ----
    if (libera) {
      const plano = planoValor || clinica.plano || "profissional";
      await db.from("clinicas").update({ plano, ativo: true }).eq("id", clinica.id);

      // Acha a assinatura cakto existente (pelo id da Cakto, senão a ativa da clínica) para atualizar em vez de duplicar.
      let assId: string | null = null;
      if (subId) {
        const { data: ex } = await db.from("assinaturas").select("id").eq("provedor", "cakto").eq("provider_id", String(subId)).maybeSingle();
        assId = ex?.id || null;
      }
      if (!assId) {
        const { data: ex2 } = await db.from("assinaturas").select("id").eq("provedor", "cakto").eq("clinica_id", clinica.id)
          .in("status", ["ativa", "pendente", "em_atraso"]).order("criado_em", { ascending: false }).limit(1).maybeSingle();
        assId = ex2?.id || null;
      }

      const patch: any = {
        clinica_id: clinica.id, plano, provedor: "cakto",
        provider_id: subId ? String(subId) : null, status: "ativa",
        valor: PRECO[plano] ?? null, payer_email: email, atualizado_em: agora(),
      };
      if (assId) await db.from("assinaturas").update(patch).eq("id", assId);
      else await db.from("assinaturas").insert(patch);

      console.log("CAKTO: acesso liberado", email, plano);
      return new Response("ok", { headers: cors });
    }

    // ---- Suspende (cancelamento / reembolso / chargeback / renovação recusada) ----
    if (suspende) {
      if (subId) {
        await db.from("assinaturas").update({ status: "cancelada", cancelada_em: agora(), atualizado_em: agora() })
          .eq("provedor", "cakto").eq("provider_id", String(subId));
      } else {
        await db.from("assinaturas").update({ status: "cancelada", cancelada_em: agora(), atualizado_em: agora() })
          .eq("provedor", "cakto").eq("clinica_id", clinica.id).in("status", ["ativa", "pendente", "em_atraso"]);
      }

      // PROTEÇÃO: só suspende o acesso se NÃO estiver em cortesia e não houver outra assinatura ativa.
      if (clinica.cortesia === true) {
        console.log("CAKTO: clínica em cortesia — acesso preservado", email);
      } else {
        const { data: ativa } = await db.from("assinaturas").select("id").eq("clinica_id", clinica.id).eq("status", "ativa").maybeSingle();
        if (!ativa) await db.from("clinicas").update({ ativo: false }).eq("id", clinica.id);
      }
      return new Response("ok", { headers: cors });
    }

    console.log("CAKTO: evento sem ação:", evento);
    return new Response("ok", { headers: cors });
  } catch (e) {
    // 200 de propósito durante a fase de implantação, para a Cakto não reenviar em loop por erro nosso.
    console.error("CAKTO webhook erro:", e);
    return new Response("ok", { headers: cors });
  }
});
