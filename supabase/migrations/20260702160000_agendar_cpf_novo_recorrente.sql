-- ===== Agendamento online: CPF + novo/recorrente + possível duplicado =====
-- Aditivo e seguro. A coluna pacientes.cpf já existe.
-- (1) índice para busca por CPF; (2) validador de CPF (dígitos verificadores);
-- (3) agendar_online passa a receber p_cpf, casa o paciente por CPF (e por
--     WhatsApp como reforço, enriquecendo o CPF de cadastros antigos), avisa se
--     é paciente NOVO ou já cadastrado, e sinaliza possível cadastro duplicado.
-- O bot do WhatsApp usa outra RPC (bot_agendar) — não é afetado.

-- (1) Índice para casar paciente por CPF (por clínica)
CREATE INDEX IF NOT EXISTS idx_pacientes_clinica_cpf
  ON public.pacientes (clinica_id, cpf) WHERE cpf IS NOT NULL;

-- (2) Validação de CPF (formato + dígitos verificadores). IMMUTABLE, sem I/O.
CREATE OR REPLACE FUNCTION public.cpf_valido(p_cpf text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  d text;
  s int;
  r int;
  i int;
BEGIN
  d := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
  IF length(d) <> 11 THEN RETURN false; END IF;
  IF d ~ '^(.)\1{10}$' THEN RETURN false; END IF; -- todos os dígitos iguais
  -- 1º dígito verificador
  s := 0;
  FOR i IN 1..9 LOOP s := s + substr(d, i, 1)::int * (11 - i); END LOOP;
  r := 11 - (s % 11); IF r >= 10 THEN r := 0; END IF;
  IF r <> substr(d, 10, 1)::int THEN RETURN false; END IF;
  -- 2º dígito verificador
  s := 0;
  FOR i IN 1..10 LOOP s := s + substr(d, i, 1)::int * (12 - i); END LOOP;
  r := 11 - (s % 11); IF r >= 10 THEN r := 0; END IF;
  IF r <> substr(d, 11, 1)::int THEN RETURN false; END IF;
  RETURN true;
END;
$$;

-- (3) Nova versão de agendar_online (com p_cpf). Remove a assinatura antiga.
DROP FUNCTION IF EXISTS public.agendar_online(text, text, text, date, text, text);

CREATE OR REPLACE FUNCTION public.agendar_online(
  p_slug text, p_nome text, p_whatsapp text,
  p_data date, p_hora text, p_queixa text DEFAULT NULL, p_cpf text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cli RECORD;
  v_nome text := trim(coalesce(p_nome, ''));
  v_wpp text := regexp_replace(coalesce(p_whatsapp, ''), '\D', '', 'g');
  v_cpf text := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
  v_queixa text := nullif(trim(coalesce(p_queixa, '')), '');
  v_dia_cod text;
  v_ini time; v_fim time; v_hora time;
  v_ts timestamptz;
  v_agora_sp timestamp;
  v_paciente_id uuid;
  v_consulta_id uuid;
  v_min_desde_inicio int;
  v_novo boolean := false;
  v_prev int := 0;
  v_dup boolean := false;
  v_msg text;
BEGIN
  SELECT * INTO v_cli FROM public.clinicas c
  WHERE c.slug = p_slug AND coalesce(c.ativo, true) AND coalesce(c.agendamento_online, true);
  IF NOT FOUND THEN
    RETURN json_build_object('ok', false, 'erro', 'Agendamento online indisponível para esta clínica.');
  END IF;

  IF length(v_nome) < 3 OR length(v_nome) > 120 THEN
    RETURN json_build_object('ok', false, 'erro', 'Informe seu nome completo.');
  END IF;
  IF length(v_wpp) < 10 OR length(v_wpp) > 13 THEN
    RETURN json_build_object('ok', false, 'erro', 'Informe um WhatsApp válido com DDD.');
  END IF;
  IF NOT public.cpf_valido(v_cpf) THEN
    RETURN json_build_object('ok', false, 'erro', 'Informe um CPF válido.');
  END IF;
  IF v_queixa IS NOT NULL AND length(v_queixa) > 300 THEN
    RETURN json_build_object('ok', false, 'erro', 'Descrição muito longa.');
  END IF;
  BEGIN
    v_hora := p_hora::time;
  EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('ok', false, 'erro', 'Horário inválido.');
  END;

  v_agora_sp := (now() AT TIME ZONE 'America/Sao_Paulo');
  IF p_data < v_agora_sp::date OR p_data > v_agora_sp::date + 60 THEN
    RETURN json_build_object('ok', false, 'erro', 'Escolha uma data entre hoje e os próximos 60 dias.');
  END IF;

  v_dia_cod := (ARRAY['dom','seg','ter','qua','qui','sex','sab'])[extract(dow FROM p_data)::int + 1];
  IF NOT (v_dia_cod = ANY (coalesce(v_cli.dias_atendimento, ARRAY['seg','ter','qua','qui','sex']))) THEN
    RETURN json_build_object('ok', false, 'erro', 'A clínica não atende neste dia.');
  END IF;

  v_ini := coalesce((v_cli.horarios_por_dia -> v_dia_cod ->> 'inicio')::time, v_cli.horario_inicio, '08:00'::time);
  v_fim := coalesce((v_cli.horarios_por_dia -> v_dia_cod ->> 'fim')::time, v_cli.horario_fim, '18:00'::time);
  IF v_hora < v_ini OR v_hora >= v_fim THEN
    RETURN json_build_object('ok', false, 'erro', 'Horário fora do período de atendimento.');
  END IF;

  v_min_desde_inicio := (extract(hour FROM v_hora) * 60 + extract(minute FROM v_hora))::int
                      - (extract(hour FROM v_ini) * 60 + extract(minute FROM v_ini))::int;
  IF v_min_desde_inicio % coalesce(v_cli.intervalo_consulta, 60) <> 0 THEN
    RETURN json_build_object('ok', false, 'erro', 'Horário inválido para a agenda da clínica.');
  END IF;

  v_ts := (p_data::text || ' ' || to_char(v_hora, 'HH24:MI') || ':00')::timestamp AT TIME ZONE 'America/Sao_Paulo';
  IF v_ts <= now() THEN
    RETURN json_build_object('ok', false, 'erro', 'Este horário já passou. Escolha outro.');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.consultas co
    WHERE co.clinica_id = v_cli.id AND co.status <> 'cancelado' AND co.data_hora = v_ts
  ) THEN
    RETURN json_build_object('ok', false, 'erro', 'Este horário acabou de ser preenchido. Escolha outro.');
  END IF;

  -- Anti-abuso: máx. 3 agendamentos online por WhatsApp/dia nesta clínica
  IF (
    SELECT count(*) FROM public.consultas co
    JOIN public.pacientes pa ON pa.id = co.paciente_id
    WHERE co.clinica_id = v_cli.id AND co.origem = 'online'
      AND right(regexp_replace(coalesce(pa.whatsapp, ''), '\D', '', 'g'), 11) = right(v_wpp, 11)
      AND co.criado_em > now() - interval '24 hours'
  ) >= 3 THEN
    RETURN json_build_object('ok', false, 'erro', 'Limite de agendamentos atingido. Fale direto com a clínica.');
  END IF;

  -- Paciente: 1) casa por CPF (identidade forte); 2) se não achar, casa por
  -- WhatsApp SÓ se o cadastro não tiver CPF (mesma pessoa antiga → enriquece).
  SELECT pa.id INTO v_paciente_id FROM public.pacientes pa
  WHERE pa.clinica_id = v_cli.id
    AND regexp_replace(coalesce(pa.cpf, ''), '\D', '', 'g') = v_cpf
  LIMIT 1;

  IF v_paciente_id IS NULL THEN
    SELECT pa.id INTO v_paciente_id FROM public.pacientes pa
    WHERE pa.clinica_id = v_cli.id
      AND right(regexp_replace(coalesce(pa.whatsapp, ''), '\D', '', 'g'), 11) = right(v_wpp, 11)
      AND coalesce(nullif(regexp_replace(coalesce(pa.cpf, ''), '\D', '', 'g'), ''), '') = ''
    LIMIT 1;
    IF v_paciente_id IS NOT NULL THEN
      UPDATE public.pacientes SET cpf = v_cpf
      WHERE id = v_paciente_id
        AND coalesce(nullif(regexp_replace(coalesce(cpf, ''), '\D', '', 'g'), ''), '') = '';
    END IF;
  END IF;

  v_novo := v_paciente_id IS NULL;

  IF v_novo THEN
    -- Possível duplicado: já existe alguém com o mesmo nome (mas não casou por CPF/WhatsApp)
    SELECT EXISTS (
      SELECT 1 FROM public.pacientes pa
      WHERE pa.clinica_id = v_cli.id AND lower(trim(pa.nome)) = lower(trim(v_nome))
    ) INTO v_dup;

    INSERT INTO public.pacientes (clinica_id, nome, whatsapp, cpf, queixa_principal)
    VALUES (v_cli.id, v_nome, v_wpp, v_cpf, v_queixa)
    RETURNING id INTO v_paciente_id;
  ELSE
    SELECT count(*) INTO v_prev FROM public.consultas co
    WHERE co.paciente_id = v_paciente_id AND co.status <> 'cancelado';
  END IF;

  INSERT INTO public.consultas (clinica_id, paciente_id, data_hora, queixa, status, origem, valor)
  VALUES (v_cli.id, v_paciente_id, v_ts, v_queixa, 'agendado', 'online', v_cli.valor_consulta_padrao)
  RETURNING id INTO v_consulta_id;

  -- Alerta enriquecido: novo x já cadastrado (+ possível duplicado)
  v_msg := 'Agendamento online: ' || v_nome || ' — ' || to_char(p_data, 'DD/MM') || ' às ' || to_char(v_hora, 'HH24:MI');
  IF v_novo THEN
    v_msg := v_msg || ' · paciente NOVO';
    IF v_dup THEN
      v_msg := '⚠️ ' || v_msg || ' · possível cadastro duplicado (já existe alguém com esse nome)';
    END IF;
  ELSE
    v_msg := v_msg || ' · já cadastrado (' || v_prev || ' consulta' || CASE WHEN v_prev = 1 THEN '' ELSE 's' END || ')';
  END IF;

  INSERT INTO public.alertas (clinica_id, tipo, mensagem)
  VALUES (v_cli.id, 'novo_agendamento', v_msg);

  RETURN json_build_object(
    'ok', true,
    'consulta_id', v_consulta_id,
    'clinica', v_cli.nome,
    'endereco', v_cli.endereco,
    'data', to_char(p_data, 'DD/MM/YYYY'),
    'hora', to_char(v_hora, 'HH24:MI'),
    'novo', v_novo,
    'total_consultas', v_prev,
    'possivel_duplicado', v_dup
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.agendar_online(text, text, text, date, text, text, text) TO anon, authenticated;
