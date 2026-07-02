// NastaDesk — Emissão de NFS-e (Nota Fiscal de Serviço) via Focus NFe.
// Chamado pelo painel com o JWT da clínica. Cada clínica emite as suas notas.
// A emissão é ASSÍNCRONA: enviamos (POST /v2/nfse?ref=...) e depois
// consultamos a situação (GET /v2/nfse/{ref}).
//
// Pré-requisitos p/ emitir de verdade (fora do código):
//  1. Secrets FOCUS_NFE_TOKEN_HOMOLOGACAO e/ou FOCUS_NFE_TOKEN_PRODUCAO
//     no projeto Supabase (a conta Focus NFe dá um token por ambiente).
//  2. A empresa da clínica cadastrada no painel do Focus NFe com o
//     certificado A1 e a NFS-e habilitada no município.
//  3. Em Configurações → Nota fiscal: CNPJ, código do serviço (LC116),
//     ISS, código IBGE do município e regime tributário.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const TOKEN_HOMOLOG = Deno.env.get("FOCUS_NFE_TOKEN_HOMOLOGACAO") || "";
const TOKEN_PROD = Deno.env.get("FOCUS_NFE_TOKEN_PRODUCAO") || "";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

const soDigitos = (s: unknown) => String(s ?? "").replace(/\D+/g, "");

// Token e URL por ambiente (o Focus NFe usa um token e uma URL para cada)
const tokenPara = (ambiente: string) => (ambiente === "producao" ? TOKEN_PROD : TOKEN_HOMOLOG);
const basePara = (ambiente: string) =>
  ambiente === "producao" ? "https://api.focusnfe.com.br" : "https://homologacao.focusnfe.com.br";

// Chamada à API do Focus NFe (HTTP Basic: token como usuário, senha vazia)
async function focus(ambiente: string, path: string, method = "GET", body?: unknown) {
  const r = await fetch(`${basePara(ambiente)}${path}`, {
    method,
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Basic " + btoa(`${tokenPara(ambiente)}:`),
    },
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
    if (Array.isArray(d.erros)) {
      return d.erros.map((e: any) => [e?.mensagem || e, e?.correcao].filter(Boolean).join(" — ")).join("; ").slice(0, 400);
    }
    if (d.mensagem) return String(d.mensagem);
    if (d.mensagem_sefaz) return String(d.mensagem_sefaz);
    return JSON.stringify(d).slice(0, 400);
  } catch { return "Erro ao processar a resposta do emissor."; }
}

// Mapeia o "status" do Focus NFe para o nosso status simplificado.
// Valores do Focus: processando_autorizacao | autorizado | erro_autorizacao | cancelado
function mapStatus(st: string, atual: string): string {
  const s = (st || "").toString().toLowerCase();
  if (s.includes("cancel")) return "cancelada";
  if (s.includes("erro") || s.includes("denegad") || s.includes("rejeit")) return "erro";
  if (s.includes("autorizado") || s.includes("emitid") || s.includes("conclu")) return "emitida";
  if (s.includes("process")) return "processando";
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
  const temToken = !!tokenPara(ambiente);

  // ---- status do emissor (o front usa p/ decidir se mostra o botão emitir) ----
  if (acao === "config") {
    return json({
      tokenConfigurado: temToken,
      ambiente,
      cnpj: fiscal?.cnpj || null,
      pronto: !!(temToken && fiscal?.cnpj && fiscal?.codigo_servico && fiscal?.aliquota_iss != null && fiscal?.codigo_municipio),
    });
  }

  if (!temToken) {
    return json({
      erro: `Emissor de NFS-e ainda não está ligado (falta o token do Focus NFe para o ambiente de ${ambiente === "producao" ? "produção" : "homologação"}).`,
      code: "sem_token",
    }, 400);
  }

  // ---- emitir a NFS-e de uma consulta ----
  if (acao === "emitir") {
    const consultaId = body.consulta_id;
    if (!consultaId) return json({ erro: "consulta_id é obrigatório" }, 400);
    if (!fiscal?.cnpj) return json({ erro: "Preencha o CNPJ em Configurações → Nota fiscal antes de emitir.", code: "sem_fiscal" }, 400);
    if (!fiscal?.codigo_servico) return json({ erro: "Informe o código do serviço (LC116) em Configurações → Nota fiscal.", code: "sem_fiscal" }, 400);
    if (!fiscal?.codigo_municipio) return json({ erro: "Informe o código IBGE do município em Configurações → Nota fiscal.", code: "sem_fiscal" }, 400);

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

    const tomador: any = { razao_social: consulta.pacientes?.nome || "Consumidor" };
    if (cpfTomador) tomador.cpf = cpfTomador;

    const payload: any = {
      data_emissao: new Date().toISOString(),
      natureza_operacao: "1",
      optante_simples_nacional: ["mei", "simples_nacional"].includes(fiscal.regime_tributario || ""),
      prestador: {
        cnpj: soDigitos(fiscal.cnpj),
        codigo_municipio: soDigitos(fiscal.codigo_municipio),
      },
      tomador,
      servico: {
        aliquota: Number(fiscal.aliquota_iss) || 0,
        discriminacao,
        iss_retido: !!fiscal.iss_retido,
        item_lista_servico: fiscal.codigo_servico,
        valor_servicos: valor,
      },
    };
    if (fiscal.inscricao_municipal) payload.prestador.inscricao_municipal = fiscal.inscricao_municipal;
    if (fiscal.codigo_tributacao_municipio) payload.servico.codigo_tributario_municipio = fiscal.codigo_tributacao_municipio;

    const r = await focus(ambiente, `/v2/nfse?ref=${encodeURIComponent(idIntegracao)}`, "POST", payload);
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

    const nota = await upsertNota(existente, { ...base, status: "processando", erro: null });
    return json({ ok: true, nota });
  }

  // ---- consultar a situação de uma nota (emissão é assíncrona) ----
  if (acao === "consultar") {
    const { data: nota } = await admin.from("notas_fiscais")
      .select("*").eq("id", body.nota_id).eq("clinica_id", clinica.id).maybeSingle();
    if (!nota) return json({ erro: "Nota não encontrada" }, 404);

    const amb = nota.ambiente || ambiente;
    const r = await focus(amb, `/v2/nfse/${encodeURIComponent(nota.id_integracao)}`, "GET");
    const d = r.data;
    if (!r.ok || !d) return json({ nota, aviso: "Ainda sem retorno da prefeitura." });

    const status = mapStatus(d?.status, nota.status);
    const xml = d?.caminho_xml_nota_fiscal ? `${basePara(amb)}${d.caminho_xml_nota_fiscal}` : nota.link_xml;
    const upd: any = {
      status,
      emissor_id: d?.codigo_verificacao || nota.emissor_id,
      numero: d?.numero || nota.numero,
      link_pdf: d?.url_danfse || d?.url || nota.link_pdf,
      link_xml: xml,
      erro: status === "erro" ? extrairErro(d) : nota.erro,
      atualizado_em: new Date().toISOString(),
    };
    await admin.from("notas_fiscais").update(upd).eq("id", nota.id);
    return json({ nota: { ...nota, ...upd } });
  }

  return json({ erro: "Ação inválida" }, 400);
});
