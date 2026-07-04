// NastaDesk — Criar acesso (login) de funcionário da clínica.
// Fluxo:
//   1) Só o DONO da clínica pode chamar (valida o JWT → clinicas.user_id).
//   2) Trava por plano: exige Profissional ou Premium (feature "equipe").
//   3) Cria o usuário de auth (service role) e vincula em clinica_membros.
// O isolamento entre clínicas é garantido pelo RLS (a função clinica_ids_membro()
// só devolve a clínica do próprio funcionário). verify_jwt=true no config.toml.
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
  if (req.method !== "POST") return json({ error: "método não permitido" }, 405);

  // 1) Quem está chamando? Precisa ser o dono de uma clínica.
  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "não autenticado" }, 401);
  const { data: userData, error: userErr } = await db.auth.getUser(token);
  const caller = userData?.user;
  if (userErr || !caller) return json({ error: "sessão inválida" }, 401);

  const { data: clinica } = await db
    .from("clinicas")
    .select("id, plano")
    .eq("user_id", caller.id)
    .maybeSingle();
  if (!clinica) return json({ error: "apenas o dono da clínica pode criar acessos" }, 403);

  // 2) Trava por plano (feature "equipe" = Profissional ou Premium)
  if (!["profissional", "premium"].includes((clinica.plano || "").toLowerCase())) {
    return json({ error: "Logins de equipe estão disponíveis no plano Profissional ou Premium." }, 403);
  }

  // 3) Valida entrada
  let body: any;
  try { body = await req.json(); } catch { return json({ error: "corpo inválido" }, 400); }
  const nome = (body?.nome || "").toString().trim();
  const email = (body?.email || "").toString().trim().toLowerCase();
  const senha = (body?.senha || "").toString();
  const papel = (body?.papel || "").toString();
  const profissional_id = body?.profissional_id || null;

  if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "email inválido" }, 400);
  if (senha.length < 8) return json({ error: "a senha precisa ter ao menos 8 caracteres" }, 400);
  if (!["recepcao", "profissional"].includes(papel)) return json({ error: "papel inválido" }, 400);

  // Papel PROFISSIONAL entra num portal restrito: só vê as consultas e os
  // pacientes do profissional vinculado. Por isso o vínculo é OBRIGATÓRIO —
  // e precisa ser um profissional DA PRÓPRIA clínica (nunca de outra).
  if (papel === "profissional" && !profissional_id) {
    return json({ error: "Vincule o login a um profissional cadastrado (Configurações → Profissionais)." }, 400);
  }
  if (profissional_id) {
    const { data: prof } = await db
      .from("profissionais")
      .select("id")
      .eq("id", profissional_id)
      .eq("clinica_id", clinica.id)
      .maybeSingle();
    if (!prof) return json({ error: "profissional vinculado inválido" }, 400);
  }

  // 4) Cria o usuário de auth
  const { data: created, error: createErr } = await db.auth.admin.createUser({
    email,
    password: senha,
    email_confirm: true,
    user_metadata: { nome, tipo: "membro" },
  });
  if (createErr || !created?.user) {
    const msg = (createErr?.message || "").toLowerCase();
    if (msg.includes("already") || msg.includes("registered") || msg.includes("exists")) {
      return json({ error: "Já existe uma conta com esse email." }, 409);
    }
    return json({ error: "não foi possível criar o acesso" }, 400);
  }

  // 5) Vincula à clínica
  const { error: insErr } = await db.from("clinica_membros").insert({
    clinica_id: clinica.id,
    user_id: created.user.id,
    papel,
    nome: nome || null,
    profissional_id: profissional_id || null,
    ativo: true,
  });
  if (insErr) {
    // desfaz o usuário criado para não deixar órfão
    try { await db.auth.admin.deleteUser(created.user.id); } catch (_) {}
    return json({ error: "não foi possível vincular o acesso à clínica" }, 400);
  }

  return json({ ok: true });
});
