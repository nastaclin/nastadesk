-- ===== RPCs PÚBLICAS PARA AGENDAMENTO ONLINE =====
-- Expostas intencionalmente ao role anon; não revelam dados sensíveis
-- e validam todas as entradas no servidor.

-- 1) Dados públicos da clínica pelo slug
CREATE OR REPLACE FUNCTION public.clinica_publica(p_slug text)
RETURNS json
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT json_build_object(
    'nome', c.nome,
    'endereco', c.endereco,
    'endereco_complemento', c.endereco_complemento,
    'whatsapp', c.whatsapp,
    'dias_atendimento', c.dias_atendimento,
    'horarios_por_dia', c.horarios_por_dia,
    'horario_inicio', to_char(c.horario_inicio, 'HH24:MI'),
    'horario_fim', to_char(c.horario_fim, 'HH24:MI'),
    'intervalo_consulta', c.intervalo_consulta
  )
  FROM public.clinicas c
  WHERE c.slug = p_slug AND coalesce(c.ativo, true) AND coalesce(c.agendamento_online, true);
$$;

-- 2) Horários já ocupados em uma data (para o front esconder slots)
CREATE OR REPLACE FUNCTION public.horarios_ocupados(p_slug text, p_data date)
RETURNS json
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce(json_agg(to_char(co.data_hora AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI')), '[]'::json)
  FROM public.consultas co
  JOIN public.clinicas c ON c.id = co.clinica_id
  WHERE c.slug = p_slug
    AND coalesce(c.ativo, true) AND coalesce(c.agendamento_online, true)
    AND co.status <> 'cancelado'
    AND (co.data_hora AT TIME ZONE 'America/Sao_Paulo')::date = p_data;
$$;

-- 3) Criar agendamento online (validação completa no servidor)
CREATE OR REPLACE FUNCTION public.agendar_online(
  p_slug text, p_nome text, p_whatsapp text,
  p_data date, p_hora text, p_queixa text DEFAULT NULL
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
  v_queixa text := nullif(trim(coalesce(p_queixa, '')), '');
  v_dia_cod text;
  v_ini time; v_fim time; v_hora time;
  v_ts timestamptz;
  v_agora_sp timestamp;
  v_paciente_id uuid;
  v_consulta_id uuid;
  v_min_desde_inicio int;
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

  -- Paciente: reutilizar pelo WhatsApp, senão criar
  SELECT pa.id INTO v_paciente_id FROM public.pacientes pa
  WHERE pa.clinica_id = v_cli.id
    AND right(regexp_replace(coalesce(pa.whatsapp, ''), '\D', '', 'g'), 11) = right(v_wpp, 11)
  LIMIT 1;

  IF v_paciente_id IS NULL THEN
    INSERT INTO public.pacientes (clinica_id, nome, whatsapp, queixa_principal)
    VALUES (v_cli.id, v_nome, v_wpp, v_queixa)
    RETURNING id INTO v_paciente_id;
  END IF;

  INSERT INTO public.consultas (clinica_id, paciente_id, data_hora, queixa, status, origem, valor)
  VALUES (v_cli.id, v_paciente_id, v_ts, v_queixa, 'agendado', 'online', v_cli.valor_consulta_padrao)
  RETURNING id INTO v_consulta_id;

  INSERT INTO public.alertas (clinica_id, tipo, mensagem)
  VALUES (v_cli.id, 'novo_agendamento',
    'Agendamento online: ' || v_nome || ' — ' || to_char(p_data, 'DD/MM') || ' às ' || to_char(v_hora, 'HH24:MI'));

  RETURN json_build_object(
    'ok', true,
    'consulta_id', v_consulta_id,
    'clinica', v_cli.nome,
    'endereco', v_cli.endereco,
    'data', to_char(p_data, 'DD/MM/YYYY'),
    'hora', to_char(v_hora, 'HH24:MI')
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.clinica_publica(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.horarios_ocupados(text, date) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.agendar_online(text, text, text, date, text, text) TO anon, authenticated;
