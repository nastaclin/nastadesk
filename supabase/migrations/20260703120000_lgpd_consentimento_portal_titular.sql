-- ============================================================
-- FASE 1 · LGPD — Consentimento com registro + Portal do titular
-- 100% ADITIVO. Nada existente é removido de forma destrutiva.
--   (1) Tabela `consentimentos` (registro de aceite: data/hora/versão/IP)
--       + RLS (dono da clínica lê os próprios; escrita só via funções DEFINER).
--   (2) criar_clinica_no_signup(): grava o consentimento do CADASTRO da clínica
--       (aceite de Termos + Política) a partir do metadata do signup.
--   (3) agendar_online(): passa a receber a versão do termo aceito + IP e grava
--       o consentimento do PACIENTE no agendamento online (dado de saúde, Art. 11).
--   (4) Portal do titular (RPCs SECURITY DEFINER, escopo por auth.uid()):
--       - paciente_anonimizar(): elimina os dados pessoais/sensíveis do paciente
--         mantendo o esqueleto financeiro de-identificado (eliminação LGPD segura).
--       - paciente_excluir(): exclusão total robusta (todas as tabelas filhas),
--         atômica — substitui o cascade manual do front (que falhava com FKs).
-- RLS no formato performático: (select auth.uid()) + TO authenticated.
-- ============================================================

-- ===== 1. REGISTRO DE CONSENTIMENTOS / EVENTOS LGPD =====
create table if not exists public.consentimentos (
  id uuid primary key default extensions.uuid_generate_v4(),
  contexto text not null check (contexto in ('cadastro_clinica','agendamento_online','portal_titular')),
  clinica_id uuid references public.clinicas(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,   -- titular = clínica (dono da conta)
  paciente_id uuid references public.pacientes(id) on delete set null, -- titular = paciente
  documentos text[] not null default '{}',                     -- ex.: ['termos','privacidade'] ou ['eliminacao']
  versao text not null,                                        -- versão/data do termo aceito
  identificador text,                                          -- e-mail (clínica) ou "CPF final XXXX" (paciente)
  nome text,
  ip text,
  user_agent text,
  criado_em timestamptz not null default now()
);

alter table public.consentimentos enable row level security;

-- O dono da clínica enxerga os registros da própria clínica / da própria conta.
-- Escrita NÃO tem policy → só as funções SECURITY DEFINER (signup/agendar/portal)
-- e o service_role (admin) conseguem inserir. Impede adulteração pelo navegador.
drop policy if exists consentimentos_select_dono on public.consentimentos;
create policy consentimentos_select_dono on public.consentimentos for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or clinica_id in (select id from public.clinicas where user_id = (select auth.uid()))
  );

create index if not exists consentimentos_clinica_idx on public.consentimentos (clinica_id, criado_em desc);
create index if not exists consentimentos_paciente_idx on public.consentimentos (paciente_id);

-- ===== 2. Consentimento no CADASTRO da clínica (via trigger de signup) =====
-- Mantém a criação da clínica idêntica e, se o metadata trouxer a versão do termo
-- aceito, grava o consentimento (aditivo: cadastros antigos sem isso não quebram).
create or replace function public.criar_clinica_no_signup()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_clinica_id uuid;
  v_consent_versao text;
begin
  insert into public.clinicas (user_id, nome, responsavel, whatsapp, plano, slug)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nome_clinica', 'Minha Clínica'),
    coalesce(new.raw_user_meta_data->>'responsavel', 'Responsável'),
    coalesce(new.raw_user_meta_data->>'whatsapp', ''),
    'basico',
    public.gerar_slug_unico(coalesce(new.raw_user_meta_data->>'nome_clinica', 'clinica'))
  )
  returning id into v_clinica_id;

  v_consent_versao := nullif(trim(coalesce(new.raw_user_meta_data->>'lgpd_consent_versao', '')), '');
  if v_consent_versao is not null then
    insert into public.consentimentos (contexto, clinica_id, user_id, documentos, versao, identificador, nome)
    values ('cadastro_clinica', v_clinica_id, new.id, array['termos','privacidade'],
            v_consent_versao, new.email, new.raw_user_meta_data->>'responsavel');
  end if;

  return new;
end;
$$;

-- ===== 3. Consentimento no AGENDAMENTO ONLINE (dentro da RPC pública) =====
-- Nova assinatura: acrescenta p_consent_versao e p_ip (ambos opcionais, com default).
-- Toda a validação de agenda continua idêntica; só acrescentamos o registro do
-- consentimento do paciente ao final (dado de saúde — Art. 11 LGPD).
drop function if exists public.agendar_online(text, text, text, date, text, text, text);

create or replace function public.agendar_online(
  p_slug text, p_nome text, p_whatsapp text,
  p_data date, p_hora text, p_queixa text DEFAULT NULL, p_cpf text DEFAULT NULL,
  p_consent_versao text DEFAULT NULL, p_ip text DEFAULT NULL
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

  -- Registro de consentimento do paciente (LGPD) — aditivo, tolerante a falha:
  -- não deixa de agendar se por algum motivo o registro falhar.
  IF nullif(trim(coalesce(p_consent_versao, '')), '') IS NOT NULL THEN
    BEGIN
      INSERT INTO public.consentimentos (contexto, clinica_id, paciente_id, documentos, versao, identificador, nome, ip)
      VALUES ('agendamento_online', v_cli.id, v_paciente_id, array['privacidade'],
              p_consent_versao, 'CPF final ' || right(v_cpf, 4), v_nome, nullif(trim(coalesce(p_ip, '')), ''));
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

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

GRANT EXECUTE ON FUNCTION public.agendar_online(text, text, text, date, text, text, text, text, text) TO anon, authenticated;

-- ===== 4. PORTAL DO TITULAR (LGPD) — operado pela clínica (controladora) =====
-- (a) ANONIMIZAR: elimina os dados pessoais e sensíveis do paciente, mas mantém
--     o "esqueleto" financeiro (consultas/mensalidades/pacotes/notas) de-identificado,
--     preservando as obrigações contábeis/fiscais da clínica (Art. 16, I LGPD).
--     Ação irreversível — o front confirma explicitamente antes de chamar.
create or replace function public.paciente_anonimizar(p_paciente_id uuid)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_clinica_id uuid;
begin
  select pa.clinica_id into v_clinica_id
  from public.pacientes pa
  join public.clinicas c on c.id = pa.clinica_id
  where pa.id = p_paciente_id and c.user_id = (select auth.uid());
  if v_clinica_id is null then
    return json_build_object('ok', false, 'erro', 'Paciente não encontrado ou sem permissão.');
  end if;

  -- Texto livre de saúde nas consultas → removido (mantém a linha p/ o financeiro).
  update public.consultas
    set queixa = null, observacoes = null
    where paciente_id = p_paciente_id and clinica_id = v_clinica_id;

  -- Evoluções clínicas = conteúdo puramente de saúde → eliminadas.
  delete from public.evolucoes where paciente_id = p_paciente_id and clinica_id = v_clinica_id;

  -- Conversas de WhatsApp (telefone + mensagens) = dado pessoal → eliminadas.
  delete from public.mensagens where clinica_id = v_clinica_id
    and conversa_id in (select id from public.conversas where paciente_id = p_paciente_id and clinica_id = v_clinica_id);
  delete from public.conversas where paciente_id = p_paciente_id and clinica_id = v_clinica_id;

  -- Ficha do paciente: remove todos os dados pessoais/sensíveis (mantém id +
  -- config de cobrança + estatísticas p/ o financeiro seguir consistente).
  update public.pacientes set
    nome = 'Paciente anonimizado (LGPD)',
    cpf = null, whatsapp = '', email = null, data_nascimento = null,
    endereco = null, genero = null, profissao = null, convenio = null,
    queixa_principal = null, historico_medico = null, medicamentos = null,
    alergias = null, foto_url = null, status = 'inativo',
    observacoes = 'Dados pessoais eliminados a pedido do titular (LGPD) em '
                  || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY')
  where id = p_paciente_id and clinica_id = v_clinica_id;

  -- Trilha do evento de eliminação.
  insert into public.consentimentos (contexto, clinica_id, paciente_id, user_id, documentos, versao, identificador, nome)
  values ('portal_titular', v_clinica_id, p_paciente_id, (select auth.uid()),
          array['eliminacao'], 'anonimizacao', 'portal_titular', 'Paciente anonimizado (LGPD)');

  return json_build_object('ok', true);
end;
$$;

revoke execute on function public.paciente_anonimizar(uuid) from public, anon;
grant execute on function public.paciente_anonimizar(uuid) to authenticated;

-- (b) EXCLUIR: exclusão total e robusta (todas as tabelas filhas), atômica.
--     Ordem respeita as FKs (consultas antes de pacotes; filhos de consultas antes).
create or replace function public.paciente_excluir(p_paciente_id uuid)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_clinica_id uuid;
begin
  select pa.clinica_id into v_clinica_id
  from public.pacientes pa
  join public.clinicas c on c.id = pa.clinica_id
  where pa.id = p_paciente_id and c.user_id = (select auth.uid());
  if v_clinica_id is null then
    return json_build_object('ok', false, 'erro', 'Paciente não encontrado ou sem permissão.');
  end if;

  delete from public.mensagens where clinica_id = v_clinica_id
    and conversa_id in (select id from public.conversas where paciente_id = p_paciente_id and clinica_id = v_clinica_id);
  delete from public.conversas   where paciente_id = p_paciente_id and clinica_id = v_clinica_id;
  delete from public.lembretes   where clinica_id = v_clinica_id
    and consulta_id in (select id from public.consultas where paciente_id = p_paciente_id and clinica_id = v_clinica_id);
  delete from public.notas_fiscais where paciente_id = p_paciente_id and clinica_id = v_clinica_id;
  delete from public.evolucoes   where paciente_id = p_paciente_id and clinica_id = v_clinica_id;
  delete from public.consultas   where paciente_id = p_paciente_id and clinica_id = v_clinica_id;
  delete from public.pacotes     where paciente_id = p_paciente_id and clinica_id = v_clinica_id;
  delete from public.mensalidades where paciente_id = p_paciente_id and clinica_id = v_clinica_id;
  delete from public.pacientes   where id = p_paciente_id and clinica_id = v_clinica_id;

  return json_build_object('ok', true);
end;
$$;

revoke execute on function public.paciente_excluir(uuid) from public, anon;
grant execute on function public.paciente_excluir(uuid) to authenticated;
