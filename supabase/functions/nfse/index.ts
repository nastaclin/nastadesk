// NastaDesk — Emissão de NFS-e (Nota Fiscal de Serviço) via PlugNotas (TecnoSpeed).
// Chamado pelo painel com o JWT da clínica. Cada clínica emite as suas notas.
// A emissão é ASSÍNCRONA: enviamos e depois consultamos a situação.
//
// Pré-requisitos p/ emitir de verdade (fora do código):
//  1. Secret PLUGNOTAS_API_KEY definido no projeto Supabase.
//  2. A empresa da clínica cadastrada no PlugNotas com o certificado A1
//     (feito 1x no painel do PlugNotas) e a NFS-e habilitada no município.
//  3. Em Configurações → Nota fiscal: CNPJ, código do serviço (LC116) e ISS.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const PLUGNOTAS_KEY = Deno.env.get("PLUGNOTAS_API_KEY") || "";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

const soDigitos = (s: unknown) => String(s ?? "").replace(/\D+/g, "");

// Chamada à API do PlugNotas (homologação = sandbox; produção = api.plugnotas)
async function plug(path: string, method = "GET", body?: unknown, ambiente = "homologacao") {
  const base = ambiente === "producao"
    ? "https://api.plugnotas.com.br"
    : "https://api.sandbox.plugnotas.com.br";
  const r = await fetch(`${base}${path}`, {
    method,
    headers: { "Content-Type": "application/json", "X-API-KEY": PLUGNOTAS_KEY },
    body: body ? JSON.stringify(body) : undefined,
  });
  const txt = await r.text();
  let data: any = null;
  try { data = txt ? JSON.parse(txt) : null; } catch { data = txt; }
  return { ok: r.ok, status: r.status, data };
}

function extrairErro(d: any): string {
  try {
    if (!d) return "Erro desconhecido no emissor.";
    if (typeof d === "string") return d.slice(0, 400);
    if (d.error?.message) return String(d.error.message);
    if (Array.isArray(d.error)) return d.error.map((e: any) => e?.message || e).join("; ").slice(0, 400);
    if (d.message) return String(d.message);
    return JSON.stringify(d).slice(0, 400);
  } catch { return "Erro ao processar a resposta do emissor."; }
}

// Mapeia a "situacao" do PlugNotas para o nosso status simplificado.
function mapSituacao(sit: string, atual: string): string {
  const s = (sit || "").toString().toUpperCase();
  if (s.includes("CANCEL")) return "cancelada";
  if (s.includes("REJEIT") || s.includes("ERRO") || s.includes("NEGAD")) return "erro";
  if (s.includes("CONCLU") || s.includes("AUTORIZ") || s.includes("EMITID")) return "emitida";
  if (s.includes("PROCESS") || s.includes("ENVIO") || s.includes("LOTE")) return "processando";
  return atual;
}

async function upsertNota(existente: any, row: any) {
  if (existente) {
    const { data } = await admin.from("notas_fiscais").update(row).eq("id", existente.id).select().single();
    return data;
  }
  const { data } = await admin.from("notas_fiscais").insert(row).select().single();
  return data;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  // Autentica pelo JWT e resolve a clínica do usuário
  const authHeader = req.headers.get("Authorization") || "";
  const userClient = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return json({ erro: "Não autorizado" }, 401);

  const { data: clinica } = await admin.from("clinicas").select("id, nome, responsavel").eq("user_id", user.id).maybeSingle();
  if (!clinica) return json({ erro: "Clínica não encontrada" }, 404);

  const body = await req.json().catch(() => ({} as any));
  const acao = body.acao || "";

  const { data: fiscal } = await admin.from("config_fiscal").select("*").eq("clinica_id", clinica.id).maybeSingle();
  const ambiente = fiscal?.ambiente || "homologacao";

  // ---- status do emissor (o front usa p/ decidir se mostra o botão emitir) ----
  if (acao === "config") {
    return json({
      tokenConfigurado: !!PLUGNOTAS_KEY,
      ambiente,
      cnpj: fiscal?.cnpj || null,
      pronto: !!(PLUGNOTAS_KEY && fiscal?.cnpj && fiscal?.codigo_servico && fiscal?.aliquota_iss != null),
    });
  }

  if (!PLUGNOTAS_KEY) {
    return json({ erro: "Emissor de NFS-e ainda não está ligado (falta a chave do PlugNotas no servidor).", code: "sem_token" }, 400);
  }

  // ---- emitir a NFS-e de uma consulta ----
  if (acao === "emitir") {
    const consultaId = body.consulta_id;
    if (!consultaId) return json({ erro: "consulta_id é obrigatório" }, 400);
    if (!fiscal?.cnpj) return json({ erro: "Preencha o CNPJ em Configurações → Nota fiscal antes de emitir.", code: "sem_fiscal" }, 400);
    if (!fiscal?.codigo_servico) return json({ erro: "Informe o código do serviço (LC116) em Configurações → Nota fiscal.", code: "sem_fiscal" }, 400);

    const { data: consulta } = await admin
      .from("consultas").select("*, pacientes(nome, cpf)")
      .eq("id", consultaId).eq("clinica_id", clinica.id).maybeSingle();
    if (!consulta) return json({ erro: "Consulta não encontrada" }, 404);

    const valor = Number(consulta.valor) || 0;
    if (valor <= 0) return json({ erro: "A consulta não tem valor definido para emitir a nota." }, 400);

    const idIntegracao = `consulta-${consultaId}`;
    const { data: existente } = await admin.from("notas_fiscais")
      .select("*").eq("clinica_id", clinica.id).eq("id_integracao", idIntegracao).maybeSingle();
    if (existente && (existente.status === "processando" || existente.status === "emitida")) {
      return json({ ok: true, nota: existente, jaExistia: true });
    }

    const dataConsulta = new Date(consulta.data_hora).toLocaleDateString("pt-BR", { timeZone: "America/Sao_Paulo" });
    const discriminacao = `Sessão de fisioterapia realizada em ${dataConsulta}.`;
    const cpfTomador = soDigitos(consulta.pacientes?.cpf);

    const servico: any = {
      codigo: fiscal.codigo_servico,
      discriminacao,
      iss: { aliquota: Number(fiscal.aliquota_iss) || 0, tipoTributacao: 6 },
      valor: { servico: valor },
    };
    if (fiscal.codigo_tributacao_municipio) servico.codigoTributacao = fiscal.codigo_tributacao_municipio;
    if (fiscal.cnae) servico.cnae = fiscal.cnae;

    const tomador: any = { razaoSocial: consulta.pacientes?.nome || "Consumidor" };
    if (cpfTomador) tomador.cpfCnpj = cpfTomador;

    const payload = [{
      idIntegracao,
      prestador: { cpfCnpj: soDigitos(fiscal.cnpj) },
      tomador,
      servico: [servico],
    }];

    const r = await plug("/nfse", "POST", payload, ambiente);
    const base = {
      clinica_id: clinica.id, consulta_id: consultaId, paciente_id: consulta.paciente_id,
      id_integracao: idIntegracao, valor, descricao: discriminacao, ambiente,
      atualizado_em: new Date().toISOString(),
    };

    if (!r.ok) {
      const msg = extrairErro(r.data);
      const nota = await upsertNota(existente, { ...base, status: "erro", erro: msg });
      return json({ ok: false, erro: msg, nota }, 200);
    }

    const protocolo = r.data?.protocol || null;
    const plugId = Array.isArray(r.data?.documents) ? r.data.documents[0]?.id : (r.data?.documents?.id || null);
    const nota = await upsertNota(existente, { ...base, status: "processando", protocolo, plugnotas_id: plugId, erro: null });
    return json({ ok: true, nota });
  }

  // ---- consultar a situação de uma nota (emissão é assíncrona) ----
  if (acao === "consultar") {
    const { data: nota } = await admin.from("notas_fiscais")
      .select("*").eq("id", body.nota_id).eq("clinica_id", clinica.id).maybeSingle();
    if (!nota) return json({ erro: "Nota não encontrada" }, 404);

    const cnpj = soDigitos(fiscal?.cnpj);
    const r = await plug(`/nfse/consultar/${encodeURIComponent(nota.id_integracao)}/${cnpj}`, "GET", undefined, nota.ambiente);
    const d = Array.isArray(r.data) ? r.data[0] : r.data;
    if (!r.ok || !d) return json({ nota, aviso: "Ainda sem retorno da prefeitura." });

    const status = mapSituacao(d?.situacao, nota.status);
    const upd: any = {
      status,
      plugnotas_id: d?.id || nota.plugnotas_id,
      numero: d?.numeroNfse || nota.numero,
      link_pdf: d?.pdf || nota.link_pdf,
      link_xml: d?.xml || nota.link_xml,
      erro: status === "erro" ? (d?.mensagem || extrairErro(d)) : nota.erro,
      atualizado_em: new Date().toISOString(),
    };
    await admin.from("notas_fiscais").update(upd).eq("id", nota.id);
    return json({ nota: { ...nota, ...upd } });
  }

  return json({ erro: "Ação inválida" }, 400);
});
