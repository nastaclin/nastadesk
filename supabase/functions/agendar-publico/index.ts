// NastaDesk — Agendamento público com verificação hCaptcha (anti-robô)
// Fluxo: agendar.html envia o booking + o token do hCaptcha para cá.
//   1) Verificamos o token no servidor (secret NUNCA vai pro front).
//   2) Se válido, delegamos TODA a validação de agenda para a RPC agendar_online
//      (datas, horários livres, duplicidade, rate-limit por WhatsApp) — a RPC
//      continua intocada; esta função é só o "porteiro" anti-abuso na frente.
// Fail-closed: sem secret configurado ou token inválido, NÃO agenda.
//
// O secret do hCaptcha vem de public.admin_config (key 'hcaptcha_secret' ->
// { "secret": "..." }) ou da env HCAPTCHA_SECRET. O site key é público (fica no front).
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

async function hcaptchaSecret(): Promise<string> {
  const env = Deno.env.get("HCAPTCHA_SECRET");
  if (env) return env;
  const { data } = await db.from("admin_config").select("value").eq("key", "hcaptcha_secret").maybeSingle();
  const v: any = data?.value;
  return (v && (v.secret || v)) || "";
}

async function verificaHcaptcha(token: string, ip: string | null): Promise<boolean> {
  if (!token) return false;
  const secret = await hcaptchaSecret();
  if (!secret) {
    console.error("AGENDAR: HCAPTCHA_SECRET não configurado — recusando (fail-closed).");
    return false;
  }
  try {
    const form = new URLSearchParams();
    form.set("secret", secret);
    form.set("response", token);
    if (ip) form.set("remoteip", ip);
    const r = await fetch("https://api.hcaptcha.com/siteverify", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: form.toString(),
    });
    const out: any = await r.json().catch(() => null);
    return out?.success === true;
  } catch (e) {
    console.error("AGENDAR: erro ao verificar hCaptcha:", e);
    return false;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, erro: "Método não permitido." }, 405);

  let body: any = null;
  try { body = await req.json(); } catch { /* ignore */ }
  if (!body) return json({ ok: false, erro: "Requisição inválida." }, 400);

  const token = String(body.hcaptcha_token || body.captcha || "");
  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || null;

  if (!(await verificaHcaptcha(token, ip))) {
    return json({ ok: false, erro: "Não foi possível confirmar que você não é um robô. Recarregue a página e tente de novo." });
  }

  // Captcha ok → delega para a RPC existente (SECURITY DEFINER, valida tudo no banco).
  try {
    const { data, error } = await db.rpc("agendar_online", {
      p_slug: String(body.p_slug || body.slug || ""),
      p_nome: String(body.p_nome || body.nome || ""),
      p_whatsapp: String(body.p_whatsapp || body.whatsapp || ""),
      p_data: String(body.p_data || body.data || ""),
      p_hora: String(body.p_hora || body.hora || ""),
      p_queixa: body.p_queixa ?? body.queixa ?? null,
      p_cpf: body.p_cpf ?? body.cpf ?? null,
      // LGPD: versão do termo aceito pelo paciente + IP, para registro do consentimento
      p_consent_versao: body.p_consent_versao ?? body.consent_versao ?? null,
      p_ip: ip,
    });
    if (error) {
      console.error("AGENDAR: erro na RPC agendar_online:", error.message);
      return json({ ok: false, erro: "Não foi possível concluir o agendamento. Tente novamente." });
    }
    return json(data ?? { ok: false, erro: "Resposta vazia do servidor." });
  } catch (e) {
    console.error("AGENDAR: exceção:", e);
    return json({ ok: false, erro: "Não foi possível concluir o agendamento. Tente novamente." });
  }
});
