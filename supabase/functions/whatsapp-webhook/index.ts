// NastaDesk — Webhook do WhatsApp (cérebro do chatbot)
// Recebe eventos da Evolution API, roda o bot híbrido (menus + IA Claude)
// e responde no WhatsApp. Multi-tenant: cada clínica tem sua instância.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const EVOLUTION_URL = (Deno.env.get("EVOLUTION_API_URL") || "").replace(/\/+$/, "");
const EVOLUTION_KEY = Deno.env.get("EVOLUTION_API_KEY") || "";
const ANTHROPIC_KEY = Deno.env.get("ANTHROPIC_API_KEY") || "";

const TZ = "America/Sao_Paulo";
const DIAS_SEMANA = ["dom", "seg", "ter", "qua", "qui", "sex", "sab"];
const NOMES_DIA = { dom: "domingo", seg: "segunda", ter: "terça", qua: "quarta", qui: "quinta", sex: "sexta", sab: "sábado" } as Record<string, string>;

const db = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

// ---------- Helpers de data (fuso de São Paulo) ----------
function hojeISO(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
}
function addDias(iso: string, n: number): string {
  const d = new Date(iso + "T12:00:00-03:00");
  d.setDate(d.getDate() + n);
  return new Intl.DateTimeFormat("en-CA", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit" }).format(d);
}
function diaSemanaDe(iso: string): string {
  const dow = new Date(iso + "T12:00:00-03:00").getDay();
  return DIAS_SEMANA[dow];
}
function fmtBR(iso: string): string {
  const [y, m, d] = iso.split("-");
  return `${d}/${m}/${y}`;
}
// Interpreta "hoje", "amanhã", dias da semana, DD/MM, DD/MM/AAAA -> ISO
function parseData(texto: string): string | null {
  const t = texto.toLowerCase().trim();
  const hoje = hojeISO();
  if (/\bhoje\b/.test(t)) return hoje;
  if (/\bamanh/.test(t)) return addDias(hoje, 1);
  if (/depois de amanh/.test(t)) return addDias(hoje, 2);
  const semana = [["domingo", "dom"], ["segunda", "seg"], ["terca", "ter"], ["terça", "ter"], ["quarta", "qua"], ["quinta", "qui"], ["sexta", "sex"], ["sabado", "sab"], ["sábado", "sab"]] as [string, string][];
  for (const [nome, cod] of semana) {
    if (t.includes(nome)) {
      for (let i = 0; i <= 7; i++) {
        const cand = addDias(hoje, i);
        if (diaSemanaDe(cand) === cod && i > 0) return cand;
      }
    }
  }
  const m = t.match(/(\d{1,2})\s*\/\s*(\d{1,2})(?:\s*\/\s*(\d{2,4}))?/);
  if (m) {
    const d = m[1].padStart(2, "0");
    const mo = m[2].padStart(2, "0");
    let y = m[3] || hoje.slice(0, 4);
    if (y.length === 2) y = "20" + y;
    const iso = `${y}-${mo}-${d}`;
    if (iso >= hoje) return iso;
    // se a data já passou neste ano, assume o próximo ano
    return `${parseInt(y) + 1}-${mo}-${d}`;
  }
  return null;
}

// ---------- Evolution API ----------
async function enviarTexto(instancia: string, telefone: string, texto: string) {
  if (!EVOLUTION_URL || !EVOLUTION_KEY) {
    console.error("Evolution API não configurada (EVOLUTION_API_URL / EVOLUTION_API_KEY)");
    return;
  }
  try {
    const r = await fetch(`${EVOLUTION_URL}/message/sendText/${instancia}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: EVOLUTION_KEY },
      body: JSON.stringify({ number: telefone, text: texto }),
    });
    if (!r.ok) console.error("Falha ao enviar WhatsApp:", r.status, await r.text());
  } catch (e) {
    console.error("Erro ao enviar WhatsApp:", e);
  }
}

// ---------- Claude (Messages API via fetch puro) ----------
async function chamarClaude(system: string, mensagens: { role: string; content: any }[], tools?: any[]): Promise<any> {
  if (!ANTHROPIC_KEY) return null;
  const body: any = {
    model: "claude-haiku-4-5",
    max_tokens: 512,
    system,
    messages: mensagens,
  };
  if (tools) {
    body.tools = tools;
    body.tool_choice = { type: "any" };
  }
  try {
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": ANTHROPIC_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify(body),
    });
    if (!r.ok) {
      console.error("Claude erro:", r.status, await r.text());
      return null;
    }
    return await r.json();
  } catch (e) {
    console.error("Claude exceção:", e);
    return null;
  }
}

// Registra o consumo de tokens da chamada ao Claude, por clínica, para o painel
// admin calcular o custo REAL da API. Tolerante a falhas de propósito: se a
// tabela ainda não existir ou a gravação falhar, apenas loga e segue — o bot
// nunca deve quebrar por causa do rastreio de custo.
async function registrarUsoIA(clinicaId: string, conversaId: string | null, resp: any) {
  try {
    const u = resp?.usage;
    if (!u) return;
    await db.from("ia_uso").insert({
      clinica_id: clinicaId,
      conversa_id: conversaId,
      modelo: resp?.model || "claude-haiku-4-5",
      input_tokens: u.input_tokens || 0,
      output_tokens: u.output_tokens || 0,
      cache_creation_input_tokens: u.cache_creation_input_tokens || 0,
      cache_read_input_tokens: u.cache_read_input_tokens || 0,
    });
  } catch (e) {
    console.error("Falha ao registrar uso de IA (ignorado):", e);
  }
}

// ---------- Persistência da conversa ----------
async function salvarMsg(conversaId: string, clinicaId: string, direcao: string, autor: string, conteudo: string, externaId?: string) {
  await db.from("mensagens").insert({ conversa_id: conversaId, clinica_id: clinicaId, direcao, autor, conteudo, msg_externa_id: externaId || null });
}
async function responder(conv: any, instancia: string, texto: string) {
  await enviarTexto(instancia, conv.telefone, texto);
  await salvarMsg(conv.id, conv.clinica_id, "saida", "bot", texto);
  await db.from("conversas").update({ ultima_msg: texto, ultima_msg_em: new Date().toISOString() }).eq("id", conv.id);
}
async function setEstado(convId: string, estado: any) {
  await db.from("conversas").update({ estado }).eq("id", convId);
}

const MENU = `Como posso te ajudar? Responda com o número:

*1* 📅 Agendar consulta
*2* ✅ Confirmar / cancelar consulta
*3* ❓ Dúvidas (horários, valores, endereço)
*4* 💬 Falar com um atendente`;

function textoSlots(slots: string[]): string {
  if (!slots.length) return "";
  return slots.slice(0, 12).map((s, i) => `*${i + 1}* — ${s}`).join("\n");
}

// ---------- Fluxo de agendamento (determinístico) ----------
async function iniciarAgendamento(conv: any, instancia: string, cli: any) {
  const nomeOk = conv.nome_contato && conv.nome_contato.length > 2;
  if (!nomeOk) {
    await setEstado(conv.id, { fluxo: "agendar", etapa: "nome" });
    await responder(conv, instancia, "Ótimo! Vamos agendar 📅\n\nPrimeiro, qual é o seu *nome completo*?");
  } else {
    await setEstado(conv.id, { fluxo: "agendar", etapa: "data", nome: conv.nome_contato });
    await responder(conv, instancia, `Perfeito, ${conv.nome_contato.split(" ")[0]}! Para que *dia* você quer agendar?\n\nPode escrever assim: _amanhã_, _sexta_, ou _25/12_.`);
  }
}

async function mostrarSlots(conv: any, instancia: string, cli: any, est: any, dataISO: string) {
  const { data: slotsJson } = await db.rpc("bot_slots_livres", { p_clinica_id: conv.clinica_id, p_data: dataISO });
  const slots: string[] = slotsJson || [];
  if (!slots.length) {
    await responder(conv, instancia, `Não há horários livres em ${fmtBR(dataISO)} 😕\nQuer tentar outro dia? (ex: _amanhã_, _segunda_, _30/12_)`);
    await setEstado(conv.id, { ...est, etapa: "data" });
    return;
  }
  await setEstado(conv.id, { ...est, etapa: "hora", data: dataISO, slots });
  await responder(conv, instancia, `Horários livres em *${fmtBR(dataISO)}* (${NOMES_DIA[diaSemanaDe(dataISO)]}):\n\n${textoSlots(slots)}\n\nResponda com o *número* do horário desejado.`);
}

async function handleAgendar(conv: any, instancia: string, cli: any, est: any, txt: string): Promise<void> {
  const tl = txt.toLowerCase().trim();
  if (/^(cancelar|sair|menu|voltar)$/.test(tl)) {
    await setEstado(conv.id, {});
    await responder(conv, instancia, "Tudo bem, cancelei o agendamento. " + MENU);
    return;
  }
  if (est.etapa === "nome") {
    const nome = txt.trim();
    if (nome.length < 3) { await responder(conv, instancia, "Pode me dizer seu nome completo, por favor?"); return; }
    await db.from("conversas").update({ nome_contato: nome }).eq("id", conv.id);
    await setEstado(conv.id, { fluxo: "agendar", etapa: "data", nome });
    await responder(conv, instancia, `Obrigado, ${nome.split(" ")[0]}! Para que *dia* você quer agendar?\n\nEx: _amanhã_, _sexta_, ou _25/12_.`);
    return;
  }
  if (est.etapa === "data") {
    const dataISO = parseData(txt);
    if (!dataISO) { await responder(conv, instancia, "Não entendi a data 🤔 Tente: _amanhã_, _sexta-feira_ ou _25/12_."); return; }
    await mostrarSlots(conv, instancia, cli, est, dataISO);
    return;
  }
  if (est.etapa === "hora") {
    const slots: string[] = est.slots || [];
    let escolhido: string | null = null;
    const num = parseInt(tl.replace(/\D/g, ""));
    if (tl.match(/^\d{1,2}$/) && num >= 1 && num <= slots.length) escolhido = slots[num - 1];
    else if (/^\d{1,2}:\d{2}$/.test(tl) && slots.includes(tl)) escolhido = tl;
    else if (/^\d{1,2}h?$/.test(tl)) { const h = tl.replace(/\D/g, "").padStart(2, "0") + ":00"; if (slots.includes(h)) escolhido = h; }
    if (!escolhido) { await responder(conv, instancia, `Escolha um dos horários pelo número:\n\n${textoSlots(slots)}`); return; }
    await setEstado(conv.id, { ...est, etapa: "queixa", hora: escolhido });
    await responder(conv, instancia, `Anotado: *${fmtBR(est.data)} às ${escolhido}* ✅\n\nPode me contar rapidamente o *motivo* da consulta? (ex: dor no joelho, avaliação). Se preferir, responda _pular_.`);
    return;
  }
  if (est.etapa === "queixa") {
    const queixa = /^(pular|nao|não|-)$/.test(tl) ? null : txt.trim();
    const res = await db.rpc("bot_agendar", {
      p_clinica_id: conv.clinica_id, p_telefone: conv.telefone,
      p_nome: est.nome || conv.nome_contato, p_data: est.data, p_hora: est.hora, p_queixa: queixa,
    });
    const r = res.data;
    await setEstado(conv.id, {});
    if (r && r.ok) {
      let msg = `🎉 Consulta agendada com sucesso!\n\n📅 *${r.data}* às *${r.hora}*\n🏥 ${r.clinica}`;
      if (r.endereco) msg += `\n📍 ${r.endereco}`;
      msg += `\n\nVocê receberá um lembrete antes. Até lá! 😊`;
      await responder(conv, instancia, msg);
    } else {
      await responder(conv, instancia, `Ops, não consegui concluir: ${(r && r.erro) || "tente novamente"}.\n\nQuer escolher outro horário? Responda *1* para agendar de novo.`);
    }
    return;
  }
  await setEstado(conv.id, {});
  await responder(conv, instancia, MENU);
}

// ---------- Fluxo confirmar/cancelar ----------
async function iniciarGerenciar(conv: any, instancia: string) {
  const res = await db.rpc("bot_proxima_consulta", { p_clinica_id: conv.clinica_id, p_telefone: conv.telefone });
  const c = res.data;
  if (!c) {
    await setEstado(conv.id, {});
    await responder(conv, instancia, "Não encontrei nenhuma consulta futura no seu número 🤔\n\nQuer *agendar* uma? Responda *1*.");
    return;
  }
  await setEstado(conv.id, { fluxo: "gerenciar", consulta_id: c.consulta_id });
  await responder(conv, instancia, `Encontrei sua consulta:\n\n📅 *${c.data} às ${c.hora}*\n\nO que deseja fazer?\n*1* ✅ Confirmar presença\n*2* 🔄 Remarcar\n*3* ❌ Cancelar`);
}

async function handleGerenciar(conv: any, instancia: string, cli: any, est: any, txt: string) {
  const tl = txt.toLowerCase().trim();
  if (/^(1|confirm)/.test(tl)) {
    await db.rpc("bot_set_status_consulta", { p_clinica_id: conv.clinica_id, p_consulta_id: est.consulta_id, p_status: "confirmado" });
    await setEstado(conv.id, {});
    await responder(conv, instancia, "Presença confirmada! ✅ Te esperamos. 😊");
  } else if (/^(2|remarc)/.test(tl)) {
    await db.rpc("bot_set_status_consulta", { p_clinica_id: conv.clinica_id, p_consulta_id: est.consulta_id, p_status: "cancelado" });
    await iniciarAgendamento(conv, instancia, cli);
  } else if (/^(3|cancel)/.test(tl)) {
    await db.rpc("bot_set_status_consulta", { p_clinica_id: conv.clinica_id, p_consulta_id: est.consulta_id, p_status: "cancelado" });
    await setEstado(conv.id, {});
    await responder(conv, instancia, "Consulta cancelada. Se precisar, é só chamar para reagendar. 🙏");
  } else {
    await responder(conv, instancia, "Responda *1* (confirmar), *2* (remarcar) ou *3* (cancelar).");
  }
}

// ---------- Handoff humano ----------
async function handoff(conv: any, instancia: string) {
  await db.from("conversas").update({ bot_ativo: false, estado: {} }).eq("id", conv.id);
  await db.from("alertas").insert({
    clinica_id: conv.clinica_id, tipo: "whatsapp",
    mensagem: `${conv.nome_contato || conv.telefone} pediu atendimento humano no WhatsApp`,
  });
  await responder(conv, instancia, "Beleza! 💬 Um atendente da clínica vai te responder por aqui em breve. Pode deixar sua mensagem.");
}

// ---------- IA: resposta de FAQ / roteamento de texto livre ----------
async function cerebroIA(conv: any, instancia: string, cli: any, cfg: any, txt: string) {
  // histórico recente para contexto
  const { data: hist } = await db.from("mensagens").select("autor,conteudo,direcao").eq("conversa_id", conv.id).order("criado_em", { ascending: false }).limit(8);
  const historico = (hist || []).reverse().map((m: any) => ({
    role: m.direcao === "entrada" ? "user" : "assistant",
    content: m.conteudo,
  }));

  const infoClinica = [
    `Clínica: ${cli.nome}`,
    cli.endereco ? `Endereço: ${cli.endereco}${cli.endereco_complemento ? " — " + cli.endereco_complemento : ""}` : "",
    cli.valor_consulta_padrao ? `Valor da consulta: R$ ${Number(cli.valor_consulta_padrao).toFixed(2)}` : "",
    `Dias de atendimento: ${(cli.dias_atendimento || []).map((d: string) => NOMES_DIA[d]).join(", ")}`,
    cfg?.bot_faq ? `\nInformações adicionais da clínica:\n${cfg.bot_faq}` : "",
  ].filter(Boolean).join("\n");

  const system = `Você é o assistente virtual de uma clínica no WhatsApp. Seja simpático, breve e use no máximo 2 emojis. Responda em português do Brasil.

${infoClinica}

Sua função:
- Responder dúvidas sobre a clínica (horários, valores, endereço, convênios, preparo) usando as informações acima. Se não souber, ofereça falar com um atendente.
- Identificar quando o paciente quer AGENDAR, CONFIRMAR/CANCELAR uma consulta, ou FALAR COM ATENDENTE, e chamar a ferramenta certa.
- Nunca invente horários ou preços que não estão acima.

Sempre chame exatamente UMA ferramenta.`;

  const tools = [
    { name: "responder", description: "Responder uma dúvida ou conversa do paciente com texto.", input_schema: { type: "object", properties: { mensagem: { type: "string", description: "A resposta a enviar ao paciente." } }, required: ["mensagem"] } },
    { name: "agendar_consulta", description: "O paciente quer marcar/agendar uma nova consulta.", input_schema: { type: "object", properties: {} } },
    { name: "minhas_consultas", description: "O paciente quer confirmar, remarcar ou cancelar uma consulta existente.", input_schema: { type: "object", properties: {} } },
    { name: "falar_com_atendente", description: "O paciente quer falar com uma pessoa/atendente humano, ou está com um problema que o bot não resolve.", input_schema: { type: "object", properties: {} } },
  ];

  const resp = await chamarClaude(system, [...historico, { role: "user", content: txt }], tools);
  if (resp && resp.usage) await registrarUsoIA(conv.clinica_id, conv.id, resp);
  if (!resp || !resp.content) {
    await responder(conv, instancia, "Desculpe, tive um problema. " + MENU);
    return;
  }
  const toolUse = resp.content.find((b: any) => b.type === "tool_use");
  if (!toolUse) {
    const t = resp.content.find((b: any) => b.type === "text");
    await responder(conv, instancia, (t && t.text) || MENU);
    return;
  }
  switch (toolUse.name) {
    case "agendar_consulta": await iniciarAgendamento(conv, instancia, cli); break;
    case "minhas_consultas": await iniciarGerenciar(conv, instancia); break;
    case "falar_com_atendente": await handoff(conv, instancia); break;
    default: await responder(conv, instancia, toolUse.input?.mensagem || MENU);
  }
}

// ---------- Roteador principal ----------
async function processar(conv: any, instancia: string, cli: any, cfg: any, txt: string) {
  const tl = txt.toLowerCase().trim();
  const est = conv.estado || {};

  // 1) Reposta a um lembrete automático
  if (est.aguardando === "confirmacao_lembrete") {
    if (/^(1|sim|confirm|ok|vou|👍)/.test(tl)) {
      await db.rpc("bot_set_status_consulta", { p_clinica_id: conv.clinica_id, p_consulta_id: est.consulta_id, p_status: "confirmado" });
      await setEstado(conv.id, {});
      await responder(conv, instancia, "Presença confirmada, obrigado! ✅ Até lá. 😊");
      return;
    }
    if (/^(3|cancel|nao|não)/.test(tl)) {
      await db.rpc("bot_set_status_consulta", { p_clinica_id: conv.clinica_id, p_consulta_id: est.consulta_id, p_status: "cancelado" });
      await setEstado(conv.id, {});
      await responder(conv, instancia, "Consulta cancelada. Quando quiser remarcar, é só chamar. 🙏");
      return;
    }
    if (/^(2|remarc)/.test(tl)) {
      await db.rpc("bot_set_status_consulta", { p_clinica_id: conv.clinica_id, p_consulta_id: est.consulta_id, p_status: "cancelado" });
      await iniciarAgendamento(conv, instancia, cli);
      return;
    }
    await setEstado(conv.id, {}); // resposta não relacionada: limpa e segue fluxo normal
  }

  // 2) Fluxos em andamento
  if (est.fluxo === "agendar") return handleAgendar(conv, instancia, cli, est, txt);
  if (est.fluxo === "gerenciar") return handleGerenciar(conv, instancia, cli, est, txt);

  // 3) Menu por número / palavra-chave
  if (/^1$/.test(tl) || /\b(agendar|marcar|nova consulta)\b/.test(tl)) return iniciarAgendamento(conv, instancia, cli);
  if (/^2$/.test(tl) || /\b(confirmar|remarcar|minha consulta|minhas consultas)\b/.test(tl)) return iniciarGerenciar(conv, instancia);
  if (/^4$/.test(tl) || /\b(atendente|humano|recep|secret|pessoa)\b/.test(tl)) return handoff(conv, instancia);
  if (/^3$/.test(tl)) return responder(conv, instancia, "Pode perguntar o que quiser sobre a clínica (horários, valores, endereço, convênios) que eu te respondo! 😊");
  if (/^(menu|oi|ol[áa]|bom dia|boa tarde|boa noite|in[ií]cio)\b/.test(tl)) return responder(conv, instancia, MENU);

  // 4) Texto livre -> IA (FAQ + roteamento)
  return cerebroIA(conv, instancia, cli, cfg, txt);
}

// ---------- HTTP entrypoint ----------
Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("ok");
  let payload: any;
  try { payload = await req.json(); } catch { return new Response("bad json", { status: 200 }); }

  const url = new URL(req.url);
  const token = url.searchParams.get("token");
  const evento = payload.event || payload.type;
  const instanciaEvt = payload.instance || payload.instanceName;

  // Resolve a clínica pelo token (preferido) ou pela instância
  let conexao: any = null;
  if (token) {
    const { data } = await db.from("whatsapp_conexoes").select("*").eq("webhook_token", token).maybeSingle();
    conexao = data;
  }
  if (!conexao && instanciaEvt) {
    const { data } = await db.from("whatsapp_conexoes").select("*").eq("instancia", instanciaEvt).maybeSingle();
    conexao = data;
  }
  if (!conexao) return new Response("ok"); // ignora silenciosamente eventos desconhecidos

  const instancia = conexao.instancia;

  // Atualiza status de conexão
  if (evento === "connection.update" || evento === "CONNECTION_UPDATE") {
    const state = payload.data?.state || payload.data?.connection;
    const novo = state === "open" ? "conectado" : state === "connecting" ? "conectando" : "desconectado";
    await db.from("whatsapp_conexoes").update({ status: novo, atualizado_em: new Date().toISOString() }).eq("id", conexao.id);
    return new Response("ok");
  }

  if (evento !== "messages.upsert" && evento !== "MESSAGES_UPSERT") return new Response("ok");

  // Normaliza mensagem (Evolution pode mandar array ou objeto único)
  const arr = Array.isArray(payload.data) ? payload.data : [payload.data];
  for (const data of arr) {
    if (!data || !data.key) continue;
    if (data.key.fromMe) continue; // ignora nossas próprias mensagens
    const jid = data.key.remoteJid || "";
    if (jid.endsWith("@g.us") || jid.includes("broadcast")) continue; // ignora grupos/status
    const telefone = jid.split("@")[0].replace(/\D/g, "");
    if (!telefone) continue;
    const texto = data.message?.conversation || data.message?.extendedTextMessage?.text || data.message?.imageMessage?.caption || "";
    if (!texto.trim()) {
      // mensagem sem texto (áudio/imagem/etc): registra e oferece atendente
      continue;
    }
    const externaId = data.key.id;
    const nome = data.pushName || null;

    // Carrega config da clínica
    const { data: cli } = await db.from("clinicas").select("*").eq("id", conexao.clinica_id).maybeSingle();
    if (!cli) continue;

    // Chatbot é exclusivo dos planos Profissional+ e exige a conta ativa.
    // No plano Básico o WhatsApp serve apenas para os lembretes manuais (via wa.me),
    // então o bot não recebe nem responde mensagens — evita custo de IA e respostas indevidas.
    const podeChatbot = cli.ativo === true && (cli.plano === "profissional" || cli.plano === "premium");
    if (!podeChatbot) continue;

    const { data: cfg } = await db.from("configuracoes").select("*").eq("clinica_id", conexao.clinica_id).maybeSingle();

    // Pega/cria conversa
    let { data: conv } = await db.from("conversas").select("*").eq("clinica_id", conexao.clinica_id).eq("telefone", telefone).maybeSingle();
    const primeiraVez = !conv;
    if (!conv) {
      const { data: nova } = await db.from("conversas").insert({
        clinica_id: conexao.clinica_id, telefone, nome_contato: nome, tipo: "lead",
      }).select("*").single();
      conv = nova;
      await db.from("alertas").insert({
        clinica_id: conexao.clinica_id, tipo: "whatsapp",
        mensagem: `Novo contato no WhatsApp: ${nome || telefone}`,
      });
    } else if (nome && !conv.nome_contato) {
      await db.from("conversas").update({ nome_contato: nome }).eq("id", conv.id);
      conv.nome_contato = nome;
    }

    // Dedup por id externo
    if (externaId) {
      const { data: dup } = await db.from("mensagens").select("id").eq("clinica_id", conexao.clinica_id).eq("msg_externa_id", externaId).maybeSingle();
      if (dup) continue;
    }

    // Salva a mensagem recebida e incrementa não lidas
    await salvarMsg(conv.id, conexao.clinica_id, "entrada", "contato", texto, externaId);
    await db.from("conversas").update({
      ultima_msg: texto, ultima_msg_em: new Date().toISOString(),
      nao_lidas: (conv.nao_lidas || 0) + 1,
    }).eq("id", conv.id);

    // Bot desligado globalmente ou para esta conversa, ou pausado -> só registra (atendente assume)
    const pausado = conv.bot_pausado_ate && new Date(conv.bot_pausado_ate) > new Date();
    if (cfg && cfg.bot_ativo === false) continue;
    if (conv.bot_ativo === false || pausado) continue;

    // Primeira mensagem de um lead novo: boas-vindas + menu
    if (primeiraVez) {
      const bv = (cfg?.bot_boasvindas || "Olá! 👋 Bem-vindo(a) à {clinica}.").replaceAll("{clinica}", cli.nome);
      await responder(conv, instancia, bv + "\n\n" + MENU);
      continue;
    }

    try {
      await processar(conv, instancia, cli, cfg, texto);
    } catch (e) {
      console.error("Erro no processamento do bot:", e);
    }
  }

  return new Response("ok");
});
