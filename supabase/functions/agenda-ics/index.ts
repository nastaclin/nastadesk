// NastaDesk — agenda-ics
// Feed de calendário (ICS) para assinar a agenda da clínica no Google
// Agenda, Outlook ou Apple Calendar (integração SOMENTE-LEITURA, 1 via:
// NastaDesk → calendário externo).
//
// Segurança: verify_jwt=false (calendários externos não fazem login);
// o "segredo" é o clinicas.ics_token (uuid) na URL — mesmo modelo do
// "endereço secreto" do próprio Google Agenda. A clínica pode trocar o
// token a qualquer momento em Configurações → Integração de agenda
// (o link antigo morre na hora). Só GET; nada é gravado no banco.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Texto em campo ICS: escapa \ ; , e quebras de linha (RFC 5545)
function icsEsc(s: string): string {
  return String(s || "").replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\r?\n/g, "\\n");
}

// Dobra linhas em 75 octetos (RFC 5545 §3.1) — continuação começa com espaço
function fold(line: string): string {
  const bytes = new TextEncoder().encode(line);
  if (bytes.length <= 75) return line;
  const out: string[] = [];
  let cur = "";
  let curLen = 0;
  for (const ch of line) {
    const l = new TextEncoder().encode(ch).length;
    if (curLen + l > (out.length === 0 ? 75 : 74)) {
      out.push(cur);
      cur = ch; curLen = l;
    } else {
      cur += ch; curLen += l;
    }
  }
  if (cur) out.push(cur);
  return out.join("\r\n ");
}

function dtUtc(d: Date): string {
  return d.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
}

Deno.serve(async (req: Request) => {
  if (req.method !== "GET") return new Response("method not allowed", { status: 405 });

  const url = new URL(req.url);
  const token = (url.searchParams.get("token") || "").trim();
  if (!UUID_RE.test(token)) return new Response("not found", { status: 404 });

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: clinica } = await db
    .from("clinicas")
    .select("id, nome, endereco, intervalo_consulta, ativo")
    .eq("ics_token", token)
    .maybeSingle();
  if (!clinica || clinica.ativo !== true) return new Response("not found", { status: 404 });

  // Janela: 7 dias para trás até 60 dias para frente (canceladas ficam fora)
  const ini = new Date(Date.now() - 7 * 864e5);
  const fim = new Date(Date.now() + 60 * 864e5);
  const { data: consultas, error } = await db
    .from("consultas")
    .select("id, data_hora, status, teleconsulta, pacientes(nome), profissionais(nome), salas(nome), modalidades(nome)")
    .eq("clinica_id", clinica.id)
    .neq("status", "cancelado")
    .gte("data_hora", ini.toISOString())
    .lte("data_hora", fim.toISOString())
    .order("data_hora", { ascending: true })
    .limit(500);
  if (error) return new Response("erro", { status: 500 });

  const durMin = Number(clinica.intervalo_consulta) > 0 ? Number(clinica.intervalo_consulta) : 60;
  const agora = dtUtc(new Date());
  const linhas: string[] = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Nastaclin//NastaDesk//PT-BR",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    fold("X-WR-CALNAME:" + icsEsc("NastaDesk — " + (clinica.nome || "Agenda"))),
    "X-WR-TIMEZONE:America/Sao_Paulo",
  ];

  for (const c of consultas || []) {
    const iniEv = new Date(c.data_hora);
    const fimEv = new Date(iniEv.getTime() + durMin * 60000);
    const pac = (c as any).pacientes?.nome || "Paciente";
    const prof = (c as any).profissionais?.nome || "";
    const sala = (c as any).salas?.nome || "";
    const mod = (c as any).modalidades?.nome || "";
    const desc: string[] = [];
    if (mod) desc.push("Modalidade: " + mod);
    if (prof) desc.push("Profissional: " + prof);
    if (sala) desc.push("Sala: " + sala);
    if (c.status) desc.push("Status: " + c.status);
    if (c.teleconsulta) desc.push("Teleconsulta 📹: https://meet.jit.si/NastaDesk-" + String(c.id).replace(/-/g, "").slice(0, 20));
    linhas.push(
      "BEGIN:VEVENT",
      "UID:" + c.id + "@nastadesk",
      "DTSTAMP:" + agora,
      "DTSTART:" + dtUtc(iniEv),
      "DTEND:" + dtUtc(fimEv),
      fold("SUMMARY:" + icsEsc((c.teleconsulta ? "📹 " : "") + "Consulta: " + pac)),
      fold("DESCRIPTION:" + icsEsc(desc.join("\n"))),
      fold("LOCATION:" + icsEsc(c.teleconsulta ? "Teleconsulta (vídeo)" : (clinica.endereco || clinica.nome || ""))),
      "STATUS:CONFIRMED",
      "END:VEVENT",
    );
  }
  linhas.push("END:VCALENDAR");

  return new Response(linhas.join("\r\n") + "\r\n", {
    headers: {
      "Content-Type": "text/calendar; charset=utf-8",
      "Content-Disposition": 'inline; filename="nastadesk.ics"',
      "Cache-Control": "private, max-age=300",
    },
  });
});
