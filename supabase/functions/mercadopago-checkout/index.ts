// NastaDesk — Mercado Pago: cria/cancela assinatura recorrente (Checkout de Assinaturas)
// Chamado pelo painel (usuário logado). Cria uma "preapproval" mensal e devolve o init_point
// para o cliente concluir o pagamento. A ativação do plano acontece no webhook.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const MP_TOKEN = Deno.env.get("MERCADOPAGO_ACCESS_TOKEN") || "";

const PRECOS: Record<string, number> = { basico: 97, profissional: 197, premium: 347 };
const NOMES: Record<string, string> = { basico: "Básica", profissional: "Profissional", premium: "Premium" };

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: any, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

async function mpFetch(path: string, init: RequestInit = {}) {
  const r = await fetch(`https://api.mercadopago.com${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${MP_TOKEN}`, "Content-Type": "application/json", ...(init.headers || {}) },
  });
  const txt = await r.text();
  let body: any = null;
  try { body = txt ? JSON.parse(txt) : null; } catch { body = txt; }
  return { ok: r.ok, status: r.status, body };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (!MP_TOKEN) return json({ erro: "Pagamento ainda não configurado. Fale com o NastaDesk." }, 503);

  // Identifica o usuário logado e a clínica dele
  const authHeader = req.headers.get("Authorization") || "";
  const userClient = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return json({ erro: "Não autorizado" }, 401);

  const { data: clinica } = await admin.from("clinicas").select("id, nome, email, plano").eq("user_id", user.id).maybeSingle();
  if (!clinica) return json({ erro: "Clínica não encontrada" }, 404);

  const payload = await req.json().catch(() => ({}));
  const acao = payload.acao || "criar";

  // ---- Cancelar assinatura atual ----
  if (acao === "cancelar") {
    const { data: ass } = await admin
      .from("assinaturas").select("id, provider_id")
      .eq("clinica_id", clinica.id).in("status", ["ativa", "em_atraso", "pendente"])
      .order("criado_em", { ascending: false }).limit(1).maybeSingle();
    if (ass?.provider_id) {
      const r = await mpFetch(`/preapproval/${ass.provider_id}`, { method: "PUT", body: JSON.stringify({ status: "cancelled" }) });
      if (!r.ok) return json({ erro: "Falha ao cancelar no Mercado Pago", detalhe: r.body }, 502);
      await admin.from("assinaturas").update({ status: "cancelada", cancelada_em: new Date().toISOString(), atualizado_em: new Date().toISOString() }).eq("id", ass.id);
    }
    return json({ ok: true });
  }

  // ---- Criar assinatura (assinar / trocar de plano) ----
  const plano = payload.plano;
  if (!PRECOS[plano]) return json({ erro: "Plano inválido" }, 400);
  const origin = String(payload.origin || "").replace(/\/+$/, "") || "https://nastadesk.com";
  const email = clinica.email || user.email;
  if (!email) return json({ erro: "Cadastre um e-mail na clínica antes de assinar." }, 400);

  const body = {
    reason: `NastaDesk — Plano ${NOMES[plano]}`,
    external_reference: clinica.id,
    payer_email: email,
    back_url: `${origin}/?assinatura=sucesso`,
    notification_url: `${SUPABASE_URL}/functions/v1/mercadopago-webhook`,
    status: "pending",
    auto_recurring: {
      frequency: 1,
      frequency_type: "months",
      transaction_amount: PRECOS[plano],
      currency_id: "BRL",
    },
  };

  const r = await mpFetch("/preapproval", { method: "POST", body: JSON.stringify(body) });
  if (!r.ok || !r.body?.init_point) {
    console.error("Falha ao criar preapproval:", r.status, r.body);
    return json({ erro: "Não foi possível abrir o pagamento. Tente novamente em instantes.", detalhe: r.body }, 502);
  }

  await admin.from("assinaturas").insert({
    clinica_id: clinica.id,
    plano,
    provedor: "mercadopago",
    provider_id: r.body.id,
    status: "pendente",
    valor: PRECOS[plano],
    payer_email: email,
    init_point: r.body.init_point,
  });

  return json({ ok: true, init_point: r.body.init_point });
});
