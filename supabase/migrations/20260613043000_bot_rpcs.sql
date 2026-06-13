-- ===== RPCs DO CHATBOT (executadas pelo edge function com service_role) =====
-- Toda a validação crítica (datas, horários livres, duplicidade) acontece aqui,
-- então mesmo que a IA escolha argumentos errados, o banco rejeita.

-- 1) Horários livres de uma data (gera a grade e remove os ocupados/passados)
CREATE OR REPLACE FUNCTION public.bot_slots_livres(p_clinica_id uuid, p_data date)
RETURNS json
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_cli RECORD;
  v_dia_cod text;
  v_ini time; v_fim time; v_passo int;
  v_slot time;
  v_ts timestamptz;
  v_agora timestamptz := now();
  v_out text[] := '{}';
BEGIN
  SELECT * INTO v_cli FROM public.clinicas WHERE id = p_clinica_id;
  IF NOT FOUND THEN RETURN '[]'::json; END IF;
  IF p_data < (v_agora AT TIME ZONE 'America/Sao_Paulo')::date
     OR p_data > (v_agora AT TIME ZONE 'America/Sao_Paulo')::date + 60 THEN
    RETURN '[]'::json;
  END IF;
  v_dia_cod := (ARRAY['dom','seg','ter','qua','qui','sex','sab'])[extract(dow FROM p_data)::int + 1];
  IF NOT (v_dia_cod = ANY (coalesce(v_cli.dias_atendimento, ARRAY['seg','ter','qua','qui','sex']))) THEN
    RETURN '[]'::json;
  END IF;
  v_ini := coalesce((v_cli.horarios_por_dia -> v_dia_cod ->> 'inicio')::time, v_cli.horario_inicio, '08:00');
  v_fim := coalesce((v_cli.horarios_por_dia -> v_dia_cod ->> 'fim')::time, v_cli.horario_fim, '18:00');
  v_passo := coalesce(v_cli.intervalo_consulta, 60);
  IF v_passo < 5 THEN v_passo := 60; END IF;
  v_slot := v_ini;
  WHILE v_slot < v_fim LOOP
    v_ts := (p_data::text || ' ' || to_char(v_slot,'HH24:MI') || ':00')::timestamp AT TIME ZONE 'America/Sao_Paulo';
    IF v_ts > v_agora AND NOT EXISTS (
      SELECT 1 FROM public.consultas co
      WHERE co.clinica_id = p_clinica_id AND co.status <> 'cancelado' AND co.data_hora = v_ts
    ) THEN
      v_out := array_append(v_out, to_char(v_slot,'HH24:MI'));
    END IF;
    v_slot := v_slot + make_interval(mins => v_passo);
  END LOOP;
  RETURN to_json(v_out);
END $$;

-- 2) Agendar consulta vinda do WhatsApp
CREATE OR REPLACE FUNCTION public.bot_agendar(
  p_clinica_id uuid, p_telefone text, p_nome text,
  p_data date, p_hora text, p_queixa text DEFAULT NULL
) RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_cli RECORD;
  v_wpp text := regexp_replace(coalesce(p_telefone,''),'\D','','g');
  v_nome text := nullif(trim(coalesce(p_nome,'')),'');
  v_queixa text := nullif(trim(coalesce(p_queixa,'')),'');
  v_hora time; v_ts timestamptz; v_pid uuid; v_cid uuid;
BEGIN
  SELECT * INTO v_cli FROM public.clinicas WHERE id = p_clinica_id;
  IF NOT FOUND THEN RETURN json_build_object('ok',false,'erro','Clínica não encontrada'); END IF;
  BEGIN v_hora := p_hora::time; EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('ok',false,'erro','Horário inválido'); END;
  v_ts := (p_data::text||' '||to_char(v_hora,'HH24:MI')||':00')::timestamp AT TIME ZONE 'America/Sao_Paulo';
  IF v_ts <= now() THEN RETURN json_build_object('ok',false,'erro','Esse horário já passou. Escolha outro.'); END IF;
  IF EXISTS (SELECT 1 FROM public.consultas WHERE clinica_id=p_clinica_id AND status<>'cancelado' AND data_hora=v_ts) THEN
    RETURN json_build_object('ok',false,'erro','Esse horário acabou de ser preenchido. Escolha outro.');
  END IF;
  SELECT id INTO v_pid FROM public.pacientes
   WHERE clinica_id=p_clinica_id
     AND right(regexp_replace(coalesce(whatsapp,''),'\D','','g'),11)=right(v_wpp,11) LIMIT 1;
  IF v_pid IS NULL THEN
    INSERT INTO public.pacientes (clinica_id, nome, whatsapp, queixa_principal)
    VALUES (p_clinica_id, coalesce(v_nome,'Contato WhatsApp'), v_wpp, v_queixa)
    RETURNING id INTO v_pid;
  ELSIF v_nome IS NOT NULL THEN
    UPDATE public.pacientes SET nome=v_nome
     WHERE id=v_pid AND (nome IS NULL OR nome='' OR nome='Contato WhatsApp');
  END IF;
  INSERT INTO public.consultas (clinica_id,paciente_id,data_hora,queixa,status,origem,valor,pagamento_status)
  VALUES (p_clinica_id,v_pid,v_ts,v_queixa,'agendado','whatsapp',v_cli.valor_consulta_padrao,'pendente')
  RETURNING id INTO v_cid;
  UPDATE public.conversas SET paciente_id=v_pid, tipo='paciente'
   WHERE clinica_id=p_clinica_id
     AND right(regexp_replace(telefone,'\D','','g'),11)=right(v_wpp,11);
  INSERT INTO public.alertas (clinica_id,tipo,mensagem)
  VALUES (p_clinica_id,'novo_agendamento',
    'Agendamento via WhatsApp: '||coalesce(v_nome,v_wpp)||' — '||to_char(p_data,'DD/MM')||' às '||to_char(v_hora,'HH24:MI'));
  RETURN json_build_object('ok',true,'consulta_id',v_cid,
    'data',to_char(p_data,'DD/MM/YYYY'),'hora',to_char(v_hora,'HH24:MI'),
    'clinica',v_cli.nome,'endereco',v_cli.endereco);
END $$;

-- 3) Próxima consulta futura do contato
CREATE OR REPLACE FUNCTION public.bot_proxima_consulta(p_clinica_id uuid, p_telefone text)
RETURNS json LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT json_build_object(
    'consulta_id',c.id,
    'data',to_char(c.data_hora AT TIME ZONE 'America/Sao_Paulo','DD/MM/YYYY'),
    'hora',to_char(c.data_hora AT TIME ZONE 'America/Sao_Paulo','HH24:MI'),
    'status',c.status)
  FROM public.consultas c JOIN public.pacientes p ON p.id=c.paciente_id
  WHERE c.clinica_id=p_clinica_id
    AND right(regexp_replace(coalesce(p.whatsapp,''),'\D','','g'),11)=right(regexp_replace(coalesce(p_telefone,''),'\D','','g'),11)
    AND c.status IN ('agendado','confirmado','aguardando','remarcado') AND c.data_hora > now()
  ORDER BY c.data_hora LIMIT 1;
$$;

-- 4) Confirmar/cancelar uma consulta (valida que pertence à clínica)
CREATE OR REPLACE FUNCTION public.bot_set_status_consulta(p_clinica_id uuid, p_consulta_id uuid, p_status text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_rows int;
BEGIN
  IF p_status NOT IN ('confirmado','cancelado') THEN RETURN json_build_object('ok',false); END IF;
  UPDATE public.consultas SET status=p_status WHERE id=p_consulta_id AND clinica_id=p_clinica_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows > 0 AND p_status='cancelado' THEN
    INSERT INTO public.alertas (clinica_id,tipo,mensagem)
    SELECT p_clinica_id,'cancelamento',
      'Consulta cancelada via WhatsApp em '||to_char(data_hora AT TIME ZONE 'America/Sao_Paulo','DD/MM HH24:MI')
    FROM public.consultas WHERE id=p_consulta_id;
  END IF;
  RETURN json_build_object('ok', v_rows > 0);
END $$;

-- Permissões: apenas service_role (o edge function). Nunca anon/authenticated direto.
REVOKE EXECUTE ON FUNCTION public.bot_slots_livres(uuid,date) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bot_agendar(uuid,text,text,date,text,text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bot_proxima_consulta(uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bot_set_status_consulta(uuid,uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bot_slots_livres(uuid,date) TO service_role;
GRANT EXECUTE ON FUNCTION public.bot_agendar(uuid,text,text,date,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.bot_proxima_consulta(uuid,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.bot_set_status_consulta(uuid,uuid,text) TO service_role;
