// NastaDesk — Excluir o acesso (login) de um funcionário da clínica.
// Só o DONO da clínica pode chamar (valida o JWT → clinicas.user_id) e só
// pode excluir membros da PRÓPRIA clínica. Remove o vínculo em clinica_membros
// e apaga o usuário de auth (libera o email para reuso). verify_jwt=true.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const db = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (obj: unknown, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "metodo nao permitido" }, 405);

  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "nao autenticado" }, 401);
  const { data: userData, error: userErr } = await db.auth.getUser(token);
  const caller = userData?.user;
  if (userErr || !caller) return json({ error: "sessao invalida" }, 401);

  const { data: clinica } = await db.from("clinicas").select("id").eq("user_id", caller.id).maybeSingle();
  if (!clinica) return json({ error: "apenas o dono da clinica pode remover acessos" }, 403);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "corpo invalido" }, 400); }
  const membroId = (body?.membro_id || "").toString();
  if (!membroId) return json({ error: "membro nao informado" }, 400);

  // O membro precisa ser da clínica de quem chama.
  const { data: membro } = await db.from("clinica_membros")
    .select("id, user_id, clinica_id").eq("id", membroId).maybeSingle();
  if (!membro || membro.clinica_id !== clinica.id) return json({ error: "acesso nao encontrado" }, 404);

  // Remove o vínculo primeiro (corta o acesso mesmo se a exclusão do auth falhar).
  const { error: delErr } = await db.from("clinica_membros").delete().eq("id", membro.id);
  if (delErr) return json({ error: "nao foi possivel excluir o acesso" }, 400);

  // Apaga o usuário de auth (libera o email). Best-effort.
  try { await db.auth.admin.deleteUser(membro.user_id); } catch (_) { /* vínculo já removido; acesso já cortado */ }

  return json({ ok: true });
});
