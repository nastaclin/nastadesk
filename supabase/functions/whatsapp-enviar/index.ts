// NastaDesk — Enviar mensagem pelo inbox do painel (atendente humano)
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const authHeader = req.headers.get("Authorization") || "";
  const userClient = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return json({ erro: "Não autorizado" }, 401);

  const { data: clinica } = await admin.from("clinicas").select("id").eq("user_id", user.id).maybeSingle();
  if (!clinica) return json({ erro: "Clínica não encontrada" }, 404);

  const { conversa_id, texto, pausar_bot } = await req.json().catch(() => ({}));
  if (!conversa_id || !texto?.trim()) return json({ erro: "Dados inválidos" }, 400);

  const { data: conv } = await admin.from("conversas").select("*").eq("id", conversa_id).eq("clinica_id", clinica.id).maybeSingle();
  if (!conv) return json({ erro: "Conversa não encontrada" }, 404);

  const { data: conexao } = await admin.from("whatsapp_conexoes").select("instancia, status").eq("clinica_id", clinica.id).maybeSingle();
  if (!conexao || conexao.status !== "conectado") return json({ erro: "WhatsApp não está conectado" }, 400);

  if (!EVOLUTION_URL || !EVOLUTION_KEY) return json({ erro: "Evolution API não configurada" }, 400);

  // Envia
  try {
    const r = await fetch(`${EVOLUTION_URL}/message/sendText/${conexao.instancia}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: EVOLUTION_KEY },
      body: JSON.stringify({ number: conv.telefone, text: texto }),
    });
    if (!r.ok) return json({ erro: "Falha ao enviar: " + (await r.text()) }, 502);
  } catch (e) {
    return json({ erro: "Erro ao enviar: " + e }, 502);
  }

  // Registra e (opcional) pausa o bot por 6h para esta conversa
  await admin.from("mensagens").insert({ conversa_id: conv.id, clinica_id: clinica.id, direcao: "saida", autor: "atendente", conteudo: texto });
  const update: any = { ultima_msg: texto, ultima_msg_em: new Date().toISOString(), nao_lidas: 0 };
  if (pausar_bot) update.bot_pausado_ate = new Date(Date.now() + 6 * 3600 * 1000).toISOString();
  await admin.from("conversas").update(update).eq("id", conv.id);

  return json({ ok: true });
});
