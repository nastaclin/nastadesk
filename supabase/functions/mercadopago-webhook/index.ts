// NastaDesk — Webhook do Mercado Pago
// Recebe as notificações do Mercado Pago e ativa/renova/cancela o plano da clínica.
// Fonte da verdade do status da assinatura (o redirect de volta é só UX).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const MP_TOKEN = Deno.env.get("MERCADOPAGO_ACCESS_TOKEN") || "";
const WEBHOOK_SECRET = Deno.env.get("MERCADOPAGO_WEBHOOK_SECRET") || "";

const db = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
const agora = () => new Date().toISOString();

async function mpGet(path: string) {
  try {
    const r = await fetch(`https://api.mercadopago.com${path}`, { headers: { Authorization: `Bearer ${MP_TOKEN}` } });
    const t = await r.text();
    return t ? JSON.parse(t) : null;
  } catch (_e) { return null; }
}

async function mpCancelar(preId: string) {
  try {
    await fetch(`https://api.mercadopago.com/preapproval/${preId}`, {
      method: "PUT",
      headers: { Authorization: `Bearer ${MP_TOKEN}`, "Content-Type": "application/json" },
      body: JSON.stringify({ status: "cancelled" }),
    });
  } catch (_e) { /* ignora */ }
}

// Valida a assinatura HMAC do Mercado Pago (header x-signature). Só valida se o secret estiver configurado.
async function assinaturaValida(req: Request, dataId: string): Promise<boolean> {
  if (!WEBHOOK_SECRET) return true; // ainda não configurado -> não bloqueia (ativar depois)
  const sig = req.headers.get("x-signature") || "";
  const reqId = req.headers.get("x-request-id") || "";
  const parts: Record<string, string> = {};
  for (const p of sig.split(",")) {
    const [k, v] = p.split("=").map((s) => s.trim());
    if (k && v) parts[k] = v;
  }
  const ts = parts["ts"], v1 = parts["v1"];
  if (!ts || !v1) return false;
  const manifest = `id:${dataId};request-id:${reqId};ts:${ts};`;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(WEBHOOK_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(manifest));
  const hex = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return hex === v1;
}

async function ativarPlano(clinicaId: string, plano: string) {
  await db.from("clinicas").update({ plano, ativo: true }).eq("id", clinicaId);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok");
  if (req.method !== "POST") return new Response("ok");

  const url = new URL(req.url);
  let topic = url.searchParams.get("type") || url.searchParams.get("topic") || "";
  let dataId = url.searchParams.get("data.id") || url.searchParams.get("id") || "";
  let body: any = null;
  try { body = await req.json(); } catch { /* pode vir só por querystring */ }
  if (body) {
    topic = body.type || body.topic || topic;
    dataId = (body.data && body.data.id) || body.id || dataId;
  }
  if (!dataId) return new Response("ok"); // nada a fazer

  if (!(await assinaturaValida(req, dataId))) return new Response("invalid signature", { status: 401 });

  try {
    // ----- Mudança de status da assinatura (preapproval) -----
    if (topic.includes("preapproval")) {
      const pre = await mpGet(`/preapproval/${dataId}`);
      if (!pre?.id) return new Response("ok");
      const clinicaId = pre.external_reference;
      const status = pre.status; // pending | authorized | paused | cancelled

      const patch: any = { atualizado_em: agora() };
      if (status === "authorized") {
        patch.status = "ativa";
        patch.em_atraso_desde = null;
        if (pre.next_payment_date) patch.proximo_pagamento = pre.next_payment_date;
      } else if (status === "paused") {
        patch.status = "em_atraso";
        patch.em_atraso_desde = agora();
      } else if (status === "cancelled") {
        patch.status = "cancelada";
        patch.cancelada_em = agora();
      } else {
        patch.status = "pendente";
      }
      await db.from("assinaturas").update(patch).eq("provider_id", pre.id);

      if (clinicaId && status === "authorized") {
        const { data: ass } = await db.from("assinaturas").select("plano").eq("provider_id", pre.id).maybeSingle();
        if (ass?.plano) await ativarPlano(clinicaId, ass.plano);

        // Troca de plano: encerra outras assinaturas ativas da mesma clínica
        const { data: outras } = await db.from("assinaturas")
          .select("id, provider_id").eq("clinica_id", clinicaId)
          .neq("provider_id", pre.id).in("status", ["ativa", "em_atraso", "pendente"]);
        for (const o of outras || []) {
          if (o.provider_id) await mpCancelar(o.provider_id);
          await db.from("assinaturas").update({ status: "cancelada", cancelada_em: agora(), atualizado_em: agora() }).eq("id", o.id);
        }
      }

      if (clinicaId && status === "cancelled") {
        // Só suspende o acesso se não restar nenhuma assinatura ativa
        const { data: ativa } = await db.from("assinaturas").select("id").eq("clinica_id", clinicaId).eq("status", "ativa").maybeSingle();
        if (!ativa) await db.from("clinicas").update({ ativo: false }).eq("id", clinicaId);
      }
      return new Response("ok");
    }

    // ----- Cobrança recorrente (authorized_payment) -----
    if (topic.includes("authorized_payment")) {
      const pay = await mpGet(`/authorized_payments/${dataId}`);
      const preId = pay?.preapproval_id;
      if (!preId) return new Response("ok");
      const { data: ass } = await db.from("assinaturas").select("id, clinica_id, plano").eq("provider_id", preId).maybeSingle();
      if (!ass) return new Response("ok");

      const payStatus = (pay?.payment && pay.payment.status) || pay?.status;
      const aprovado = payStatus === "approved" || pay?.status === "processed";
      const rejeitado = payStatus === "rejected" || pay?.status === "recycling";

      if (aprovado) {
        await db.from("assinaturas").update({ status: "ativa", em_atraso_desde: null, atualizado_em: agora() }).eq("id", ass.id);
        await ativarPlano(ass.clinica_id, ass.plano);
      } else if (rejeitado) {
        // Mantém o acesso durante a tolerância (o MP tenta de novo). O painel mostra o aviso.
        const { data: atual } = await db.from("assinaturas").select("em_atraso_desde").eq("id", ass.id).maybeSingle();
        await db.from("assinaturas").update({
          status: "em_atraso",
          em_atraso_desde: atual?.em_atraso_desde || agora(),
          atualizado_em: agora(),
        }).eq("id", ass.id);
      }
      return new Response("ok");
    }

    // Outros tópicos (payment avulso etc.) não são usados no fluxo de assinatura.
  } catch (e) {
    console.error("webhook mercadopago erro:", e);
  }
  return new Response("ok", { status: 200 });
});
