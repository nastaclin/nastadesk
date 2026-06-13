// NastaDesk — Lembretes automáticos (chamado pelo cron a cada 10 min)
// Para cada clínica com WhatsApp conectado e lembrete automático ligado,
// envia lembrete de véspera (~24h antes) e pede confirmação por resposta.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const EVOLUTION_URL = (Deno.env.get("EVOLUTION_API_URL") || "").replace(/\/+$/, "");
const EVOLUTION_KEY = Deno.env.get("EVOLUTION_API_KEY") || "";
const TZ = "America/Sao_Paulo";

const db = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

function horaSP(iso: string) {
  return new Date(iso).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit", timeZone: TZ });
}
function dataSP(iso: string) {
  return new Date(iso).toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit", timeZone: TZ });
}

async function enviarTexto(instancia: string, telefone: string, texto: string) {
  try {
    await fetch(`${EVOLUTION_URL}/message/sendText/${instancia}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: EVOLUTION_KEY },
      body: JSON.stringify({ number: telefone, text: texto }),
    });
  } catch (e) { console.error("envio falhou", e); }
}

Deno.serve(async () => {
  if (!EVOLUTION_URL || !EVOLUTION_KEY) return new Response(JSON.stringify({ erro: "Evolution não configurada" }), { status: 200 });

  // Clínicas com WhatsApp conectado
  const { data: conexoes } = await db.from("whatsapp_conexoes").select("clinica_id, instancia, status").eq("status", "conectado");
  if (!conexoes?.length) return new Response(JSON.stringify({ ok: true, enviados: 0 }));

  const agora = new Date();
  const limite = new Date(agora.getTime() + 24 * 3600 * 1000); // janela: próximas 24h
  let enviados = 0;

  for (const cx of conexoes) {
    // config da clínica (lembrete ligado?)
    const { data: cfg } = await db.from("configuracoes").select("lembrete_auto, msg_lembrete_24h").eq("clinica_id", cx.clinica_id).maybeSingle();
    if (cfg && cfg.lembrete_auto === false) continue;

    const { data: cli } = await db.from("clinicas").select("nome, endereco").eq("id", cx.clinica_id).maybeSingle();

    // consultas nas próximas 24h, ainda ativas
    const { data: consultas } = await db.from("consultas")
      .select("id, data_hora, paciente_id, pacientes(nome, whatsapp)")
      .eq("clinica_id", cx.clinica_id)
      .in("status", ["agendado", "confirmado", "aguardando", "remarcado"])
      .gte("data_hora", agora.toISOString())
      .lte("data_hora", limite.toISOString());

    if (!consultas?.length) continue;

    // lembretes já enviados (evita duplicar)
    const ids = consultas.map((c: any) => c.id);
    const { data: jaEnviados } = await db.from("lembretes").select("consulta_id").eq("clinica_id", cx.clinica_id).eq("tipo", "24h").in("consulta_id", ids);
    const enviadosSet = new Set((jaEnviados || []).map((l: any) => l.consulta_id));

    for (const c of consultas as any[]) {
      if (enviadosSet.has(c.id)) continue;
      const wpp = (c.pacientes?.whatsapp || "").replace(/\D/g, "");
      if (!wpp) continue;
      const nome = (c.pacientes?.nome || "").split(" ")[0] || "";
      const base = (cfg?.msg_lembrete_24h || "Olá {nome}! Lembrete da sua consulta em {data} às {hora}.")
        .replaceAll("{nome}", nome)
        .replaceAll("{data}", dataSP(c.data_hora))
        .replaceAll("{hora}", horaSP(c.data_hora))
        .replaceAll("{clinica}", cli?.nome || "")
        .replaceAll("{endereco}", cli?.endereco || "");
      const msg = `${base}\n\nResponda:\n*1* ✅ Confirmar\n*2* 🔄 Remarcar\n*3* ❌ Cancelar`;

      await enviarTexto(cx.instancia, wpp, msg);

      // registra lembrete enviado
      await db.from("lembretes").upsert(
        { consulta_id: c.id, clinica_id: cx.clinica_id, tipo: "24h", status: "enviado", enviado_em: new Date().toISOString() },
        { onConflict: "consulta_id,tipo" },
      );

      // marca a conversa aguardando resposta de confirmação (se existir)
      await db.from("conversas").update({ estado: { aguardando: "confirmacao_lembrete", consulta_id: c.id } })
        .eq("clinica_id", cx.clinica_id)
        .filter("telefone", "ilike", `%${wpp.slice(-11)}%`);

      enviados++;
    }
  }

  return new Response(JSON.stringify({ ok: true, enviados }), { headers: { "Content-Type": "application/json" } });
});
