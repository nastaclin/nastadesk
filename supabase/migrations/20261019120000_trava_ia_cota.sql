-- ===== TRAVA DE IA DO ROBÔ (cota mensal por plano + limite diário por telefone) =====
--
-- Objetivo: o custo de IA do chatbot nunca passar do valor da assinatura.
--
-- Definição combinada com o dono (2026-10-19):
--   1 "conversa de IA" = 1 paciente (conversa do WhatsApp) que usou a IA num dia
--   (dia no fuso de São Paulo). Todas as mensagens de IA desse paciente no mesmo
--   dia contam como 1 conversa.
--
-- Regras (todas configuráveis em admin_config.ia_limites, nada fixo no código):
--   • Profissional: até 1.500 conversas/mês OU R$ 70 de custo real no mês (o que
--     vier primeiro). Estourou → o robô responde só pelo menu (sem IA).
--   • Premium: ilimitado. Ao passar de 6.000 conversas ou R$ 120 de custo no mês
--     só gera alerta para o admin — nunca bloqueia.
--   • Limite diário por telefone: 15 mensagens à IA. Passou → atendente assume.
--   • A clínica é avisada em 80% e 100% da cota (1 alerta por marco por mês).
--
-- Tudo ADITIVO: 3 tabelas novas + 1 chave nova em admin_config + RPCs novas.
-- Nenhuma tabela existente muda. As tabelas novas não guardam telefone (usam o
-- conversa_id) e só a service_role escreve nelas.

-- ---------- 1. Contador por conversa e dia (é o que define "1 conversa") ----------
CREATE TABLE IF NOT EXISTS public.ia_conversas (
  clinica_id uuid NOT NULL REFERENCES public.clinicas(id) ON DELETE CASCADE,
  conversa_id uuid NOT NULL REFERENCES public.conversas(id) ON DELETE CASCADE,
  dia date NOT NULL,
  chamadas integer NOT NULL DEFAULT 0,
  criado_em timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (conversa_id, dia)
);
CREATE INDEX IF NOT EXISTS ia_conversas_clinica_dia_idx ON public.ia_conversas (clinica_id, dia DESC);

-- ---------- 2. Totais do mês por clínica (conversas, chamadas e custo real) ----------
-- Fica separado do contador diário de propósito: se uma conversa for apagada
-- (LGPD), o total do mês continua certo.
CREATE TABLE IF NOT EXISTS public.ia_cota_mensal (
  clinica_id uuid NOT NULL REFERENCES public.clinicas(id) ON DELETE CASCADE,
  mes date NOT NULL,                       -- 1º dia do mês
  conversas integer NOT NULL DEFAULT 0,
  chamadas integer NOT NULL DEFAULT 0,
  bloqueadas integer NOT NULL DEFAULT 0,   -- mensagens que caíram no "só menu"
  limite_diario integer NOT NULL DEFAULT 0, -- vezes que um telefone passou do limite do dia
  custo_usd numeric(12,6) NOT NULL DEFAULT 0,
  atualizado_em timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (clinica_id, mes)
);

-- ---------- 3. Marcos atingidos (1 por marco por mês, garantido pela PK) ----------
CREATE TABLE IF NOT EXISTS public.ia_cota_eventos (
  clinica_id uuid NOT NULL REFERENCES public.clinicas(id) ON DELETE CASCADE,
  mes date NOT NULL,
  marco text NOT NULL CHECK (marco IN ('80', '100', 'premium_teto')),
  detalhe jsonb NOT NULL DEFAULT '{}'::jsonb,
  criado_em timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (clinica_id, mes, marco)
);

-- ---------- RLS ----------
-- Escrita só pela service_role (webhook / admin-api), que ignora RLS.
-- A clínica pode LER o próprio total do mês (mesmo padrão de ia_uso).
ALTER TABLE public.ia_conversas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ia_cota_mensal ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ia_cota_eventos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ia_cota_mensal_da_clinica ON public.ia_cota_mensal;
CREATE POLICY ia_cota_mensal_da_clinica ON public.ia_cota_mensal
  FOR SELECT TO authenticated
  USING (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = (SELECT auth.uid())));

REVOKE ALL ON public.ia_conversas, public.ia_cota_eventos FROM anon, authenticated;
REVOKE ALL ON public.ia_cota_mensal FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.ia_cota_mensal FROM authenticated;

-- ---------- Configuração (editável no painel admin) ----------
INSERT INTO public.admin_config (key, value)
VALUES ('ia_limites', '{
  "definicao": "conversa_dia",
  "limite_diario_telefone": 15,
  "alertas_pct": [80, 100],
  "planos": {
    "profissional": { "bloqueia": true,  "conversas_mes": 1500, "teto_custo_brl": 70 },
    "premium":      { "bloqueia": false, "conversas_mes": 6000, "teto_custo_brl": 120 }
  }
}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- Os preços do Claude ficam num lugar só: o card "API Claude / Anthropic" da
-- config de custos. Aqui só completamos os campos que faltam (não sobrescreve
-- nada que o admin já tenha editado).
UPDATE public.admin_config
SET value = jsonb_set(value, '{ferramentas}', (
      SELECT jsonb_agg(
        CASE WHEN f->>'id' = 'claude'
          THEN jsonb_build_object(
                 'modelo', 'uso_real_ia',
                 'preco_input_usd_milhao', 1.0,
                 'preco_output_usd_milhao', 5.0,
                 'preco_cache_escrita_usd_milhao', 1.25,
                 'preco_cache_leitura_usd_milhao', 0.10,
                 'cambio_brl', 5.40,
                 'nota', 'Bot de WhatsApp em Haiku 4.5. Custo REAL com base nos tokens consumidos por cada clínica no mês. Os mesmos preços valem para a trava de custo do robô.'
               ) || (f - 'valor')
               || CASE WHEN f->>'modelo' = 'uso_real_ia' THEN '{}'::jsonb ELSE jsonb_build_object(
                    'modelo', 'uso_real_ia',
                    'nota', 'Bot de WhatsApp em Haiku 4.5. Custo REAL com base nos tokens consumidos por cada clínica no mês. Os mesmos preços valem para a trava de custo do robô.') END
          ELSE f END
        ORDER BY ord)
      FROM jsonb_array_elements(value->'ferramentas') WITH ORDINALITY AS t(f, ord)
    )),
    updated_at = now()
WHERE key = 'custos' AND jsonb_typeof(value->'ferramentas') = 'array';

-- ---------- Helpers ----------
CREATE OR REPLACE FUNCTION public.ia__precos()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
    'in',  coalesce((f->>'preco_input_usd_milhao')::numeric, 1.0),
    'out', coalesce((f->>'preco_output_usd_milhao')::numeric, 5.0),
    'cw',  coalesce((f->>'preco_cache_escrita_usd_milhao')::numeric, 1.25),
    'cr',  coalesce((f->>'preco_cache_leitura_usd_milhao')::numeric, 0.10),
    'cambio', coalesce(nullif(f->>'cambio_brl', '')::numeric, 5.40)
  )
  FROM (SELECT 1) x
  LEFT JOIN LATERAL (
    SELECT f FROM public.admin_config c, jsonb_array_elements(c.value->'ferramentas') f
    WHERE c.key = 'custos' AND f->>'id' = 'claude' LIMIT 1
  ) y ON true;
$$;

-- Avalia os marcos do mês (80% / 100% / teto do Premium) e gera os alertas.
-- Uso da cota = o MAIOR entre % de conversas e % do teto de custo.
-- Precisa ser chamada com a linha de ia_cota_mensal já travada (FOR UPDATE).
CREATE OR REPLACE FUNCTION public.ia__avaliar_marcos(p_clinica_id uuid, p_mes date)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_cfg jsonb;
  v_plano text;
  v_pcfg jsonb;
  v_m public.ia_cota_mensal;
  v_cambio numeric;
  v_cota numeric;
  v_teto numeric;
  v_custo_brl numeric;
  v_pct numeric := 0;
  v_marco int;
  v_ok boolean;
  v_det jsonb;
BEGIN
  SELECT value INTO v_cfg FROM public.admin_config WHERE key = 'ia_limites';
  SELECT plano INTO v_plano FROM public.clinicas WHERE id = p_clinica_id;
  v_pcfg := v_cfg->'planos'->coalesce(v_plano, '');
  IF v_pcfg IS NULL THEN RETURN; END IF;

  SELECT * INTO v_m FROM public.ia_cota_mensal WHERE clinica_id = p_clinica_id AND mes = p_mes;
  IF NOT FOUND THEN RETURN; END IF;

  v_cambio := (public.ia__precos()->>'cambio')::numeric;
  v_custo_brl := v_m.custo_usd * v_cambio;
  v_cota := nullif(v_pcfg->>'conversas_mes', '')::numeric;
  v_teto := nullif(v_pcfg->>'teto_custo_brl', '')::numeric;
  IF v_cota > 0 THEN v_pct := greatest(v_pct, v_m.conversas * 100.0 / v_cota); END IF;
  IF v_teto > 0 THEN v_pct := greatest(v_pct, v_custo_brl * 100.0 / v_teto); END IF;
  v_det := jsonb_build_object('conversas', v_m.conversas, 'custo_brl', round(v_custo_brl, 2),
                              'cota', v_cota, 'teto_custo_brl', v_teto, 'pct', round(v_pct, 1));

  IF coalesce((v_pcfg->>'bloqueia')::boolean, false) THEN
    -- Plano com cota: avisa a CLÍNICA em cada marco.
    FOR v_marco IN SELECT (x)::int FROM jsonb_array_elements_text(coalesce(v_cfg->'alertas_pct', '[80,100]'::jsonb)) x ORDER BY 1 LOOP
      CONTINUE WHEN v_marco NOT IN (80, 100) OR v_pct < v_marco;
      INSERT INTO public.ia_cota_eventos (clinica_id, mes, marco, detalhe)
      VALUES (p_clinica_id, p_mes, v_marco::text, v_det)
      ON CONFLICT DO NOTHING
      RETURNING true INTO v_ok;
      IF v_ok THEN
        INSERT INTO public.alertas (clinica_id, tipo, mensagem) VALUES (p_clinica_id, 'whatsapp',
          CASE WHEN v_marco >= 100
            THEN '🤖 A cota de IA do robô deste mês acabou. Até o dia 1º ele responde pelo menu (agendar, confirmar e falar com atendente continuam funcionando). Quer IA ilimitada? Fale com a gente sobre o plano Premium.'
            ELSE '🤖 O robô do WhatsApp já usou 80% da cota de IA deste mês. Ao chegar em 100%, ele passa a responder só pelo menu até o dia 1º.'
          END);
      END IF;
      v_ok := NULL;
    END LOOP;
  ELSE
    -- Plano ilimitado (Premium): nunca bloqueia, só registra para o ADMIN.
    IF v_pct >= 100 THEN
      INSERT INTO public.ia_cota_eventos (clinica_id, mes, marco, detalhe)
      VALUES (p_clinica_id, p_mes, 'premium_teto', v_det)
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;
END;
$$;

-- ---------- RPC 1: checa e conta ANTES de chamar a IA ----------
-- Retorna {status: 'ok' | 'cota_esgotada' | 'limite_diario', ...}.
-- Atômica: trava a linha do mês da clínica (FOR UPDATE), então duas mensagens
-- simultâneas nunca furam a cota.
CREATE OR REPLACE FUNCTION public.ia_checar_e_contar(p_clinica_id uuid, p_conversa_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_cfg jsonb;
  v_plano text;
  v_pcfg jsonb;
  v_dia date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_mes date := date_trunc('month', (now() AT TIME ZONE 'America/Sao_Paulo'))::date;
  v_lim_dia int;
  v_m public.ia_cota_mensal;
  v_chamadas int;
  v_cota numeric;
  v_teto numeric;
  v_custo_brl numeric;
BEGIN
  SELECT value INTO v_cfg FROM public.admin_config WHERE key = 'ia_limites';
  SELECT plano INTO v_plano FROM public.clinicas WHERE id = p_clinica_id;
  v_pcfg := v_cfg->'planos'->coalesce(v_plano, '');
  v_lim_dia := nullif(v_cfg->>'limite_diario_telefone', '')::int;

  INSERT INTO public.ia_cota_mensal (clinica_id, mes) VALUES (p_clinica_id, v_mes) ON CONFLICT DO NOTHING;
  SELECT * INTO v_m FROM public.ia_cota_mensal WHERE clinica_id = p_clinica_id AND mes = v_mes FOR UPDATE;

  SELECT chamadas INTO v_chamadas FROM public.ia_conversas
  WHERE conversa_id = p_conversa_id AND dia = v_dia FOR UPDATE;

  IF FOUND THEN
    -- Conversa do dia já aberta: não conta conversa nova, só a chamada.
    IF v_lim_dia > 0 AND v_chamadas >= v_lim_dia THEN
      UPDATE public.ia_cota_mensal SET limite_diario = limite_diario + 1, atualizado_em = now()
      WHERE clinica_id = p_clinica_id AND mes = v_mes;
      RETURN jsonb_build_object('status', 'limite_diario', 'chamadas_hoje', v_chamadas, 'limite', v_lim_dia);
    END IF;
    UPDATE public.ia_conversas SET chamadas = chamadas + 1, atualizado_em = now()
    WHERE conversa_id = p_conversa_id AND dia = v_dia;
    UPDATE public.ia_cota_mensal SET chamadas = chamadas + 1, atualizado_em = now()
    WHERE clinica_id = p_clinica_id AND mes = v_mes;
    RETURN jsonb_build_object('status', 'ok', 'nova_conversa', false, 'chamadas_hoje', v_chamadas + 1);
  END IF;

  -- Conversa nova no dia: é aqui que a cota do plano entra.
  IF coalesce((v_pcfg->>'bloqueia')::boolean, false) THEN
    v_cota := nullif(v_pcfg->>'conversas_mes', '')::numeric;
    v_teto := nullif(v_pcfg->>'teto_custo_brl', '')::numeric;
    v_custo_brl := v_m.custo_usd * (public.ia__precos()->>'cambio')::numeric;
    IF (v_cota > 0 AND v_m.conversas >= v_cota) OR (v_teto > 0 AND v_custo_brl >= v_teto) THEN
      UPDATE public.ia_cota_mensal SET bloqueadas = bloqueadas + 1, atualizado_em = now()
      WHERE clinica_id = p_clinica_id AND mes = v_mes;
      PERFORM public.ia__avaliar_marcos(p_clinica_id, v_mes);  -- garante o alerta de 100%
      RETURN jsonb_build_object('status', 'cota_esgotada',
        'motivo', CASE WHEN v_cota > 0 AND v_m.conversas >= v_cota THEN 'conversas' ELSE 'custo' END);
    END IF;
  END IF;

  INSERT INTO public.ia_conversas (clinica_id, conversa_id, dia, chamadas) VALUES (p_clinica_id, p_conversa_id, v_dia, 1);
  UPDATE public.ia_cota_mensal SET conversas = conversas + 1, chamadas = chamadas + 1, atualizado_em = now()
  WHERE clinica_id = p_clinica_id AND mes = v_mes;
  PERFORM public.ia__avaliar_marcos(p_clinica_id, v_mes);
  RETURN jsonb_build_object('status', 'ok', 'nova_conversa', true, 'chamadas_hoje', 1);
END;
$$;

-- ---------- RPC 2: registra os tokens DEPOIS da chamada (custo real) ----------
CREATE OR REPLACE FUNCTION public.ia_registrar_uso(
  p_clinica_id uuid, p_conversa_id uuid, p_modelo text,
  p_input int, p_output int, p_cache_escrita int, p_cache_leitura int
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_mes date := date_trunc('month', (now() AT TIME ZONE 'America/Sao_Paulo'))::date;
  v_p jsonb := public.ia__precos();
  v_usd numeric;
BEGIN
  INSERT INTO public.ia_uso (clinica_id, conversa_id, modelo, input_tokens, output_tokens,
                             cache_creation_input_tokens, cache_read_input_tokens)
  VALUES (p_clinica_id, p_conversa_id, coalesce(p_modelo, 'claude-haiku-4-5'),
          coalesce(p_input, 0), coalesce(p_output, 0), coalesce(p_cache_escrita, 0), coalesce(p_cache_leitura, 0));

  v_usd := (coalesce(p_input, 0)          * (v_p->>'in')::numeric
          + coalesce(p_output, 0)         * (v_p->>'out')::numeric
          + coalesce(p_cache_escrita, 0)  * (v_p->>'cw')::numeric
          + coalesce(p_cache_leitura, 0)  * (v_p->>'cr')::numeric) / 1e6;

  INSERT INTO public.ia_cota_mensal (clinica_id, mes) VALUES (p_clinica_id, v_mes) ON CONFLICT DO NOTHING;
  PERFORM 1 FROM public.ia_cota_mensal WHERE clinica_id = p_clinica_id AND mes = v_mes FOR UPDATE;
  UPDATE public.ia_cota_mensal SET custo_usd = custo_usd + v_usd, atualizado_em = now()
  WHERE clinica_id = p_clinica_id AND mes = v_mes;
  PERFORM public.ia__avaliar_marcos(p_clinica_id, v_mes);
  RETURN jsonb_build_object('custo_usd', v_usd);
END;
$$;

-- ---------- RPC 3: soma de tokens do mês por clínica (painel admin) ----------
-- Antes a admin-api somava as linhas de ia_uso no código — e a API do Supabase
-- devolve no máximo 1.000 linhas por consulta, então com uso real o custo do
-- painel ficaria subestimado em silêncio. A soma agora é feita no banco.
CREATE OR REPLACE FUNCTION public.admin_ia_uso_mes(p_inicio timestamptz)
RETURNS TABLE (clinica_id uuid, chamadas bigint, input_tokens bigint, output_tokens bigint,
               cache_creation_input_tokens bigint, cache_read_input_tokens bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT clinica_id, count(*), sum(input_tokens), sum(output_tokens),
         sum(cache_creation_input_tokens), sum(cache_read_input_tokens)
  FROM public.ia_uso WHERE criado_em >= p_inicio GROUP BY clinica_id;
$$;

-- Só a service_role chama (webhook / admin-api). Nada exposto para anon/authenticated.
REVOKE ALL ON FUNCTION public.admin_ia_uso_mes(timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_ia_uso_mes(timestamptz) TO service_role;
REVOKE ALL ON FUNCTION public.ia__precos() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ia__avaliar_marcos(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ia_checar_e_contar(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ia_registrar_uso(uuid, uuid, text, int, int, int, int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ia__precos() TO service_role;
GRANT EXECUTE ON FUNCTION public.ia__avaliar_marcos(uuid, date) TO service_role;
GRANT EXECUTE ON FUNCTION public.ia_checar_e_contar(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.ia_registrar_uso(uuid, uuid, text, int, int, int, int) TO service_role;
