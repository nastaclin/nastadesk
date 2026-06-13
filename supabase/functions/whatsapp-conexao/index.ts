// NastaDesk — Gestão da conexão WhatsApp (criar instância, QR code, status)
// Chamado pelo painel com o JWT do usuário. Cada clínica conecta seu próprio número.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const EVOLUTION_URL = (Deno.env.get("EVOLUTION_API_URL") || "").replace(/\/+$/, "");
const EVOLUTION_KEY = Deno.env.get("EVOLUTION_API_KEY") || "";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: any, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

async function evo(path: string, method = "GET", body?: any) {
  const r = await fetch(`${EVOLUTION_URL}${path}`, {
    method,
    headers: { "Content-Type": "application/json", apikey: EVOLUTION_KEY },
    body: body ? JSON.stringify(body) : undefined,
  });
  const txt = await r.text();
  let data: any = null;
  try { data = txt ? JSON.parse(txt) : null; } catch { data = txt; }
  return { ok: r.ok, status: r.status, data };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (!EVOLUTION_URL || !EVOLUTION_KEY) return json({ erro: "Servidor WhatsApp (Evolution API) não configurado. Defina EVOLUTION_API_URL e EVOLUTION_API_KEY nas secrets do projeto." }, 400);

  // Autentica o usuário pelo JWT
  const authHeader = req.headers.get("Authorization") || "";
  const userClient = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return json({ erro: "Não autorizado" }, 401);

  const { data: clinica } = await admin.from("clinicas").select("id, nome").eq("user_id", user.id).maybeSingle();
  if (!clinica) return json({ erro: "Clínica não encontrada" }, 404);

  const { acao } = await req.json().catch(() => ({ acao: "" }));

  // Garante registro de conexão + nome de instância único
  let { data: conexao } = await admin.from("whatsapp_conexoes").select("*").eq("clinica_id", clinica.id).maybeSingle();
  if (!conexao) {
    const instancia = `nasta_${clinica.id.slice(0, 8)}`;
    const { data: nova } = await admin.from("whatsapp_conexoes").insert({ clinica_id: clinica.id, instancia }).select("*").single();
    conexao = nova;
  }
  const instancia = conexao.instancia;
  const webhookUrl = `${SUPABASE_URL}/functions/v1/whatsapp-webhook?token=${conexao.webhook_token}`;

  if (acao === "status") {
    const r = await evo(`/instance/connectionState/${instancia}`);
    const state = r.data?.instance?.state || r.data?.state;
    const novo = state === "open" ? "conectado" : state === "connecting" ? "conectando" : "desconectado";
    await admin.from("whatsapp_conexoes").update({ status: novo, atualizado_em: new Date().toISOString() }).eq("id", conexao.id);
    return json({ status: novo, instancia });
  }

  if (acao === "desconectar") {
    await evo(`/instance/logout/${instancia}`, "DELETE");
    await admin.from("whatsapp_conexoes").update({ status: "desconectado", numero: null }).eq("id", conexao.id);
    return json({ status: "desconectado" });
  }

  if (acao === "conectar") {
    // 1) cria a instância se ainda não existir (com webhook apontando pro nosso endpoint)
    const criar = await evo(`/instance/create`, "POST", {
      instanceName: instancia,
      integration: "WHATSAPP-BAILEYS",
      qrcode: true,
      webhook: {
        url: webhookUrl,
        webhook_by_events: false,
        events: ["MESSAGES_UPSERT", "CONNECTION_UPDATE"],
      },
    });

    // já existe? garante o webhook configurado
    if (!criar.ok) {
      await evo(`/webhook/set/${instancia}`, "POST", {
        webhook: { enabled: true, url: webhookUrl, events: ["MESSAGES_UPSERT", "CONNECTION_UPDATE"] },
      });
    }

    // 2) pega o QR code (na criação já vem; senão chama connect)
    let qr = criar.data?.qrcode?.base64 || criar.data?.base64 || null;
    if (!qr) {
      const conn = await evo(`/instance/connect/${instancia}`);
      qr = conn.data?.base64 || conn.data?.qrcode?.base64 || conn.data?.qrcode || null;
    }

    await admin.from("whatsapp_conexoes").update({ status: "conectando", atualizado_em: new Date().toISOString() }).eq("id", conexao.id);

    if (!qr) return json({ erro: "Não consegui gerar o QR Code. Tente novamente em alguns segundos.", instancia }, 200);
    const qrData = qr.startsWith("data:") ? qr : `data:image/png;base64,${qr}`;
    return json({ qrcode: qrData, instancia, status: "conectando" });
  }

  return json({ erro: "Ação inválida" }, 400);
});
