-- ============================================================================
-- Reposição de aulas com crédito (pilates) — regras escolhidas por cada clínica
-- 2026-10-24 · pedido do Eduardo (decisão: as 3 regras são da clínica)
--
-- 100% ADITIVA: 2 tabelas novas, 1 trigger novo em consultas (só DELETE e
-- UPDATE OF status, sem mexer em nada que já existe), RPCs novas.
-- Não altera colunas, constraints, policies nem funções existentes.
--
-- Como funciona:
--   • reposicao_config (1 linha por clínica): liga/desliga, antecedência mínima
--     do aviso (horas), validade do crédito (dias, contados da aula perdida),
--     quem remarca (só a recepção | também o aluno pelo /agendar), vagas por
--     horário (só para o aluno escolher sozinho) e quais modalidades geram crédito.
--     Lê: dono + recepção. Grava: só o dono.
--   • reposicao_creditos: 1 crédito por aula cancelada com aviso. Ninguém grava
--     direto pela API — só pelas RPCs abaixo (que validam as regras no servidor).
--   • O vencimento não precisa de cron: crédito 'disponivel' com expira_em no
--     passado é tratado como vencido em todas as consultas.
-- ============================================================================

-- ---------- 1. Configuração por clínica ----------
create table if not exists public.reposicao_config (
  clinica_id          uuid primary key references public.clinicas(id) on delete cascade,
  ativo               boolean not null default false,
  antecedencia_horas  integer not null default 3  check (antecedencia_horas between 0 and 168),
  validade_dias       integer not null default 30 check (validade_dias between 1 and 365),
  quem_remarca        text    not null default 'recepcao' check (quem_remarca in ('recepcao','aluno')),
  vagas_por_horario   integer not null default 1  check (vagas_por_horario between 1 and 50),
  modalidades         uuid[]  not null default '{}',
  atualizado_em       timestamptz not null default now()
);

alter table public.reposicao_config enable row level security;
revoke all on table public.reposicao_config from anon;
grant select, insert, update on table public.reposicao_config to authenticated;

create policy reposicao_config_dono_sel on public.reposicao_config
  for select to authenticated
  using (clinica_id in (select c.id from public.clinicas c where c.user_id = (select auth.uid())));
create policy reposicao_config_dono_ins on public.reposicao_config
  for insert to authenticated
  with check (clinica_id in (select c.id from public.clinicas c where c.user_id = (select auth.uid())));
create policy reposicao_config_dono_upd on public.reposicao_config
  for update to authenticated
  using (clinica_id in (select c.id from public.clinicas c where c.user_id = (select auth.uid())))
  with check (clinica_id in (select c.id from public.clinicas c where c.user_id = (select auth.uid())));
create policy reposicao_config_recepcao_sel on public.reposicao_config
  for select to authenticated
  using (clinica_id in (select public.clinica_ids_recepcao()));

-- ---------- 2. Créditos ----------
create table if not exists public.reposicao_creditos (
  id                     uuid primary key default gen_random_uuid(),
  clinica_id             uuid not null references public.clinicas(id) on delete cascade,
  paciente_id            uuid not null references public.pacientes(id) on delete cascade,
  consulta_origem_id     uuid references public.consultas(id) on delete set null,
  data_aula_origem       timestamptz not null,
  avisado_em             timestamptz not null,
  antecedencia_horas     numeric(7,1),          -- quanto o aluno avisou antes (registro)
  excecao                boolean not null default false, -- crédito dado fora da regra
  expira_em              timestamptz not null,
  status                 text not null default 'disponivel'
                         check (status in ('disponivel','usado','cancelado')),
  modalidade_id          uuid references public.modalidades(id) on delete set null,
  profissional_id        uuid references public.profissionais(id) on delete set null,
  sala_id                uuid references public.salas(id) on delete set null,
  valor_origem           numeric,
  pagamento_origem       text,
  consulta_reposicao_id  uuid references public.consultas(id) on delete set null,
  reposicoes_anteriores  uuid[] not null default '{}', -- reposições canceladas que devolveram o crédito
  usado_em               timestamptz,
  usado_por              text check (usado_por is null or usado_por in ('recepcao','aluno')),
  observacao             text,
  criado_por             uuid,
  criado_em              timestamptz not null default now()
);

create unique index if not exists reposicao_creditos_origem_uniq
  on public.reposicao_creditos (consulta_origem_id) where consulta_origem_id is not null;
create index if not exists reposicao_creditos_paciente_idx
  on public.reposicao_creditos (clinica_id, paciente_id, status);
create index if not exists reposicao_creditos_reposicao_idx
  on public.reposicao_creditos (consulta_reposicao_id) where consulta_reposicao_id is not null;

alter table public.reposicao_creditos enable row level security;
revoke all on table public.reposicao_creditos from anon;
revoke insert, update, delete on table public.reposicao_creditos from authenticated;
grant select on table public.reposicao_creditos to authenticated;

create policy reposicao_creditos_dono_sel on public.reposicao_creditos
  for select to authenticated
  using (clinica_id in (select c.id from public.clinicas c where c.user_id = (select auth.uid())));
create policy reposicao_creditos_recepcao_sel on public.reposicao_creditos
  for select to authenticated
  using (clinica_id in (select public.clinica_ids_recepcao()));
-- profissional: sem acesso (como financeiro/pacotes). Escrita: só pelas RPCs.

-- ---------- 3. Helpers ----------
-- Dono ou recepção da clínica?
create or replace function public.reposicao_pode_gerir(p_clinica_id uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (select 1 from public.clinicas c where c.id = p_clinica_id and c.user_id = (select auth.uid()))
      or p_clinica_id in (select public.clinica_ids_recepcao());
$$;
revoke all on function public.reposicao_pode_gerir(uuid) from public, anon;
grant execute on function public.reposicao_pode_gerir(uuid) to authenticated;

-- Fim do dia (São Paulo) N dias depois de uma data/hora
create or replace function public.reposicao_calcular_expira(p_data_aula timestamptz, p_dias integer)
returns timestamptz
language sql stable
set search_path = public, pg_temp
as $$
  select (((p_data_aula at time zone 'America/Sao_Paulo')::date + p_dias)::timestamp
          + interval '23 hours 59 minutes 59 seconds') at time zone 'America/Sao_Paulo';
$$;

-- ---------- 4. Trigger em consultas: mantém o crédito coerente ----------
--  • aula de REPOSIÇÃO excluída ou cancelada → o crédito volta a ficar disponível
--    (com o mesmo vencimento);
--  • aula de ORIGEM "descancelada" (voltou para a agenda) → o crédito disponível
--    é anulado (o aluno recuperou a aula; não pode ficar com as duas).
--  As RPCs abaixo ligam `nastadesk.reposicao_rpc` para decidir sozinhas.
create or replace function public.trg_reposicao_consulta()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if coalesce(current_setting('nastadesk.reposicao_rpc', true), '') = 'on' then
    return coalesce(new, old);
  end if;

  if tg_op = 'DELETE' then
    update public.reposicao_creditos
       set status = 'disponivel', reposicoes_anteriores = array_append(reposicoes_anteriores, consulta_reposicao_id),
           consulta_reposicao_id = null, usado_em = null, usado_por = null
     where consulta_reposicao_id = old.id and status = 'usado'
       and old.status is distinct from 'cancelado';  -- reposição já cancelada fora do prazo: crédito fica gasto
    return old;
  end if;

  -- UPDATE OF status
  if new.status = 'cancelado' and old.status is distinct from 'cancelado' then
    update public.reposicao_creditos
       set status = 'disponivel', reposicoes_anteriores = array_append(reposicoes_anteriores, consulta_reposicao_id),
           consulta_reposicao_id = null, usado_em = null, usado_por = null
     where consulta_reposicao_id = new.id and status = 'usado';
  elsif old.status = 'cancelado' and new.status is distinct from 'cancelado' then
    update public.reposicao_creditos
       set status = 'cancelado',
           observacao = coalesce(observacao || ' · ', '') || 'Anulado: a aula original voltou para a agenda'
     where consulta_origem_id = new.id and status = 'disponivel';
  end if;
  return new;
end;
$$;
revoke all on function public.trg_reposicao_consulta() from public, anon, authenticated;

drop trigger if exists on_consulta_reposicao_del on public.consultas;
create trigger on_consulta_reposicao_del
  before delete on public.consultas
  for each row execute function public.trg_reposicao_consulta();
drop trigger if exists on_consulta_reposicao_status on public.consultas;
create trigger on_consulta_reposicao_status
  after update of status on public.consultas
  for each row execute function public.trg_reposicao_consulta();

-- ---------- 5. RPC: aluno avisou a falta (painel: dono/recepção) ----------
-- Cancela a aula e, se a regra da clínica permitir (ou p_forcar = exceção), gera
-- o crédito. Se a aula já era uma reposição, devolve o crédito original em vez de
-- criar outro (dentro do prazo) ou o consome (fora do prazo).
create or replace function public.reposicao_registrar_falta(
  p_consulta_id uuid,
  p_avisado_em  timestamptz default null,
  p_forcar      boolean default false,
  p_observacao  text default null
) returns json
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_c        public.consultas%rowtype;
  v_cfg      public.reposicao_config%rowtype;
  v_aviso    timestamptz := coalesce(p_avisado_em, now());
  v_horas    numeric;
  v_mod      uuid;
  v_mod_ok   boolean;
  v_no_prazo boolean;
  v_cred_rep public.reposicao_creditos%rowtype;
  v_expira   timestamptz;
  v_id       uuid;
  v_nome     text;
begin
  select * into v_c from public.consultas where id = p_consulta_id for update;
  if not found or not public.reposicao_pode_gerir(v_c.clinica_id) then
    return json_build_object('ok', false, 'erro', 'Consulta não encontrada ou sem permissão.');
  end if;

  select * into v_cfg from public.reposicao_config where clinica_id = v_c.clinica_id;
  if not found or not v_cfg.ativo then
    return json_build_object('ok', false, 'erro', 'A reposição de aulas está desligada nesta clínica (Configurações → Reposição de aulas).');
  end if;

  if v_aviso > now() + interval '5 minutes' then
    return json_build_object('ok', false, 'erro', 'A hora do aviso não pode estar no futuro.');
  end if;

  if exists (select 1 from public.reposicao_creditos where consulta_origem_id = v_c.id) then
    return json_build_object('ok', false, 'erro', 'Esta aula já gerou um crédito de reposição.');
  end if;

  v_horas := round((extract(epoch from (v_c.data_hora - v_aviso)) / 3600.0)::numeric, 1);
  v_no_prazo := v_aviso < v_c.data_hora and v_horas >= v_cfg.antecedencia_horas;
  select nome into v_nome from public.pacientes where id = v_c.paciente_id;

  perform set_config('nastadesk.reposicao_rpc', 'on', true);

  -- A aula era uma REPOSIÇÃO? Então não cria crédito novo.
  select * into v_cred_rep from public.reposicao_creditos
   where consulta_reposicao_id = v_c.id and status = 'usado' for update;
  if found then
    if v_c.status is distinct from 'cancelado' then
      update public.consultas set status = 'cancelado' where id = v_c.id;
    end if;
    if v_no_prazo or p_forcar then
      update public.reposicao_creditos
         set status = 'disponivel', reposicoes_anteriores = array_append(reposicoes_anteriores, consulta_reposicao_id),
           consulta_reposicao_id = null, usado_em = null, usado_por = null
       where id = v_cred_rep.id;
      perform set_config('nastadesk.reposicao_rpc', '', true);
      return json_build_object('ok', true, 'credito', true, 'devolvido', true,
        'credito_id', v_cred_rep.id, 'expira_em', v_cred_rep.expira_em, 'horas', v_horas,
        'regra_horas', v_cfg.antecedencia_horas, 'excecao', (not v_no_prazo));
    end if;
    perform set_config('nastadesk.reposicao_rpc', '', true);
    return json_build_object('ok', true, 'credito', false, 'motivo', 'fora_do_prazo', 'era_reposicao', true,
      'horas', v_horas, 'regra_horas', v_cfg.antecedencia_horas);
  end if;
  -- Reposição que já foi cancelada antes (o crédito já voltou): não gera outro.
  if exists (select 1 from public.reposicao_creditos where clinica_id = v_c.clinica_id and v_c.id = any (reposicoes_anteriores)) then
    perform set_config('nastadesk.reposicao_rpc', '', true);
    return json_build_object('ok', false, 'erro', 'Esta aula era uma reposição e o crédito já voltou para o aluno.');
  end if;

  if v_c.pacote_id is not null then
    -- Sessão de pacote: cancelar já devolve a sessão ao pacote (regra de sempre).
    if v_c.status is distinct from 'cancelado' then
      update public.consultas set status = 'cancelado' where id = v_c.id;
    end if;
    perform set_config('nastadesk.reposicao_rpc', '', true);
    return json_build_object('ok', true, 'credito', false, 'motivo', 'pacote',
      'horas', v_horas, 'regra_horas', v_cfg.antecedencia_horas);
  end if;

  v_mod := coalesce(v_c.modalidade_id, (select modalidade_id from public.pacientes where id = v_c.paciente_id));
  v_mod_ok := coalesce(v_mod = any (v_cfg.modalidades), false);
  if not v_mod_ok and not p_forcar then
    if v_c.status is distinct from 'cancelado' then
      update public.consultas set status = 'cancelado' where id = v_c.id;
    end if;
    perform set_config('nastadesk.reposicao_rpc', '', true);
    return json_build_object('ok', true, 'credito', false, 'motivo', 'modalidade',
      'horas', v_horas, 'regra_horas', v_cfg.antecedencia_horas);
  end if;

  if not v_no_prazo and not p_forcar then
    if v_c.status is distinct from 'cancelado' then
      update public.consultas set status = 'cancelado' where id = v_c.id;
    end if;
    perform set_config('nastadesk.reposicao_rpc', '', true);
    return json_build_object('ok', true, 'credito', false, 'motivo', 'fora_do_prazo',
      'horas', v_horas, 'regra_horas', v_cfg.antecedencia_horas);
  end if;

  if v_c.status is distinct from 'cancelado' then
    update public.consultas set status = 'cancelado' where id = v_c.id;
  end if;

  v_expira := public.reposicao_calcular_expira(v_c.data_hora, v_cfg.validade_dias);
  insert into public.reposicao_creditos (
    clinica_id, paciente_id, consulta_origem_id, data_aula_origem, avisado_em, antecedencia_horas,
    excecao, expira_em, modalidade_id, profissional_id, sala_id, valor_origem, pagamento_origem,
    observacao, criado_por)
  values (
    v_c.clinica_id, v_c.paciente_id, v_c.id, v_c.data_hora, v_aviso, v_horas,
    (not v_no_prazo) or (not v_mod_ok), v_expira, v_mod, v_c.profissional_id, v_c.sala_id,
    v_c.valor, v_c.pagamento_status, nullif(trim(coalesce(p_observacao, '')), ''), (select auth.uid()))
  returning id into v_id;

  insert into public.alertas (clinica_id, tipo, mensagem)
  values (v_c.clinica_id, 'cancelamento',
    '🔄 Falta avisada: ' || coalesce(v_nome, 'aluno') || ' ganhou 1 crédito de reposição (vale até '
    || to_char(v_expira at time zone 'America/Sao_Paulo', 'DD/MM') || ')');

  perform set_config('nastadesk.reposicao_rpc', '', true);
  return json_build_object('ok', true, 'credito', true, 'credito_id', v_id, 'expira_em', v_expira,
    'horas', v_horas, 'regra_horas', v_cfg.antecedencia_horas, 'excecao', ((not v_no_prazo) or (not v_mod_ok)));
end;
$$;
revoke all on function public.reposicao_registrar_falta(uuid, timestamptz, boolean, text) from public, anon;
grant execute on function public.reposicao_registrar_falta(uuid, timestamptz, boolean, text) to authenticated;

-- ---------- 6. RPC: recepção agenda a reposição ----------
create or replace function public.reposicao_agendar(
  p_credito_id      uuid,
  p_data_hora       timestamptz,
  p_profissional_id uuid default null,
  p_sala_id         uuid default null
) returns json
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_cr  public.reposicao_creditos%rowtype;
  v_id  uuid;
  v_valor numeric;
  v_pag text;
begin
  select * into v_cr from public.reposicao_creditos where id = p_credito_id for update;
  if not found or not public.reposicao_pode_gerir(v_cr.clinica_id) then
    return json_build_object('ok', false, 'erro', 'Crédito não encontrado ou sem permissão.');
  end if;
  if v_cr.status <> 'disponivel' then
    return json_build_object('ok', false, 'erro', 'Este crédito já foi usado ou cancelado.');
  end if;
  if v_cr.expira_em < now() then
    return json_build_object('ok', false, 'erro', 'Este crédito venceu em ' || to_char(v_cr.expira_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') || '.');
  end if;
  if p_data_hora is null or p_data_hora < now() - interval '1 hour' then
    return json_build_object('ok', false, 'erro', 'Escolha uma data e horário futuros.');
  end if;
  if p_data_hora > v_cr.expira_em then
    return json_build_object('ok', false, 'erro', 'A reposição precisa ser até ' || to_char(v_cr.expira_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') || ' (validade do crédito).');
  end if;
  if p_profissional_id is not null and not exists (select 1 from public.profissionais where id = p_profissional_id and clinica_id = v_cr.clinica_id) then
    return json_build_object('ok', false, 'erro', 'Profissional inválido.');
  end if;
  if p_sala_id is not null and not exists (select 1 from public.salas where id = p_sala_id and clinica_id = v_cr.clinica_id) then
    return json_build_object('ok', false, 'erro', 'Sala inválida.');
  end if;

  -- Aula já paga → reposição sai isenta; pendente → a cobrança passa para a reposição.
  if v_cr.pagamento_origem = 'pago' then v_valor := 0; v_pag := 'isento';
  else v_valor := v_cr.valor_origem; v_pag := coalesce(v_cr.pagamento_origem, 'pendente'); end if;
  if v_pag not in ('pendente','pago','isento','pacote') then v_pag := 'pendente'; end if;

  perform set_config('nastadesk.reposicao_rpc', 'on', true);
  insert into public.consultas (clinica_id, paciente_id, data_hora, status, origem, valor, pagamento_status,
                                modalidade_id, profissional_id, sala_id, observacoes)
  values (v_cr.clinica_id, v_cr.paciente_id, p_data_hora, 'agendado', 'manual', v_valor, v_pag,
          v_cr.modalidade_id, coalesce(p_profissional_id, v_cr.profissional_id), coalesce(p_sala_id, v_cr.sala_id),
          '🔄 Reposição da aula de ' || to_char(v_cr.data_aula_origem at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'))
  returning id into v_id;

  update public.reposicao_creditos
     set status = 'usado', consulta_reposicao_id = v_id, usado_em = now(), usado_por = 'recepcao'
   where id = v_cr.id;
  perform set_config('nastadesk.reposicao_rpc', '', true);

  return json_build_object('ok', true, 'consulta_id', v_id);
end;
$$;
revoke all on function public.reposicao_agendar(uuid, timestamptz, uuid, uuid) from public, anon;
grant execute on function public.reposicao_agendar(uuid, timestamptz, uuid, uuid) to authenticated;

-- ---------- 7. RPC: anular um crédito (dono/recepção) ----------
create or replace function public.reposicao_cancelar_credito(p_credito_id uuid, p_motivo text default null)
returns json
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_cr public.reposicao_creditos%rowtype;
begin
  select * into v_cr from public.reposicao_creditos where id = p_credito_id for update;
  if not found or not public.reposicao_pode_gerir(v_cr.clinica_id) then
    return json_build_object('ok', false, 'erro', 'Crédito não encontrado ou sem permissão.');
  end if;
  if v_cr.status <> 'disponivel' then
    return json_build_object('ok', false, 'erro', 'Só dá para anular um crédito disponível.');
  end if;
  update public.reposicao_creditos
     set status = 'cancelado',
         observacao = coalesce(observacao || ' · ', '') || 'Anulado pela clínica'
                      || coalesce(': ' || nullif(trim(coalesce(p_motivo, '')), ''), '')
   where id = v_cr.id;
  return json_build_object('ok', true);
end;
$$;
revoke all on function public.reposicao_cancelar_credito(uuid, text) from public, anon;
grant execute on function public.reposicao_cancelar_credito(uuid, text) to authenticated;

-- ---------- 8. Agendamento online: o próprio aluno remarca (só se a clínica deixar) ----------
-- Clínica oferece? (o /agendar mostra o botão "Tenho crédito de reposição")
create or replace function public.reposicao_publica_info(p_slug text)
returns json
language sql stable security definer
set search_path = public, pg_temp
as $$
  select json_build_object('ativo', coalesce(r.ativo and r.quem_remarca = 'aluno', false))
    from public.clinicas c
    left join public.reposicao_config r on r.clinica_id = c.id
   where c.slug = p_slug and coalesce(c.ativo, true) and coalesce(c.agendamento_online, true);
$$;

-- Acha o aluno por CPF + WhatsApp (os dois têm que bater) — uso interno
create or replace function public.reposicao_publica_aluno(p_clinica_id uuid, p_cpf text, p_whatsapp text)
returns uuid
language sql stable security definer
set search_path = public, pg_temp
as $$
  select pa.id from public.pacientes pa
   where pa.clinica_id = p_clinica_id
     and length(regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g')) = 11
     and length(regexp_replace(coalesce(p_whatsapp, ''), '\D', '', 'g')) >= 10
     and regexp_replace(coalesce(pa.cpf, ''), '\D', '', 'g') = regexp_replace(p_cpf, '\D', '', 'g')
     and right(regexp_replace(coalesce(pa.whatsapp, ''), '\D', '', 'g'), 11)
         = right(regexp_replace(p_whatsapp, '\D', '', 'g'), 11)
   limit 1;
$$;
revoke all on function public.reposicao_publica_aluno(uuid, text, text) from public, anon, authenticated;

-- Quantos créditos o aluno tem (não devolve nome nem nada da ficha)
create or replace function public.reposicao_publica_creditos(p_slug text, p_cpf text, p_whatsapp text)
returns json
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare v_cli uuid; v_pac uuid; v_qtd int; v_exp timestamptz;
begin
  select c.id into v_cli from public.clinicas c
    join public.reposicao_config r on r.clinica_id = c.id
   where c.slug = p_slug and coalesce(c.ativo, true) and coalesce(c.agendamento_online, true)
     and r.ativo and r.quem_remarca = 'aluno';
  if v_cli is null then
    return json_build_object('ok', false, 'erro', 'Esta clínica não oferece remarcação online de reposição.');
  end if;
  v_pac := public.reposicao_publica_aluno(v_cli, p_cpf, p_whatsapp);
  if v_pac is not null then
    select count(*), min(expira_em) into v_qtd, v_exp from public.reposicao_creditos
     where clinica_id = v_cli and paciente_id = v_pac and status = 'disponivel' and expira_em >= now();
  end if;
  if v_pac is null or coalesce(v_qtd, 0) = 0 then
    return json_build_object('ok', false, 'erro', 'Não encontramos crédito de reposição para este CPF e WhatsApp. Confira os dados ou fale com a clínica.');
  end if;
  return json_build_object('ok', true, 'creditos', v_qtd,
    'expira_em', to_char(v_exp at time zone 'America/Sao_Paulo', 'YYYY-MM-DD'),
    'expira_fmt', to_char(v_exp at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'));
end;
$$;

-- Horários LOTADOS de um dia, pela regra de vagas da reposição
create or replace function public.reposicao_publica_lotados(p_slug text, p_data date)
returns json
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(json_agg(h), '[]'::json) from (
    select to_char(co.data_hora at time zone 'America/Sao_Paulo', 'HH24:MI') h
      from public.consultas co
      join public.clinicas c on c.id = co.clinica_id
      join public.reposicao_config r on r.clinica_id = c.id
     where c.slug = p_slug and coalesce(c.ativo, true) and coalesce(c.agendamento_online, true)
       and r.ativo and r.quem_remarca = 'aluno'
       and co.status <> 'cancelado'
       and (co.data_hora at time zone 'America/Sao_Paulo')::date = p_data
     group by 1, r.vagas_por_horario
    having count(*) >= r.vagas_por_horario
  ) t;
$$;

-- O aluno escolhe dia/horário e usa o crédito que vence primeiro
create or replace function public.reposicao_publica_agendar(
  p_slug text, p_cpf text, p_whatsapp text, p_data date, p_hora text
) returns json
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_cli   public.clinicas%rowtype;
  v_cfg   public.reposicao_config%rowtype;
  v_pac   uuid;
  v_nome  text;
  v_cr    public.reposicao_creditos%rowtype;
  v_hora  time; v_ini time; v_fim time;
  v_dia   text;
  v_ts    timestamptz;
  v_agora date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ocup  int;
  v_id    uuid;
  v_valor numeric; v_pag text;
begin
  select * into v_cli from public.clinicas c
   where c.slug = p_slug and coalesce(c.ativo, true) and coalesce(c.agendamento_online, true);
  if not found then
    return json_build_object('ok', false, 'erro', 'Agendamento online indisponível para esta clínica.');
  end if;
  select * into v_cfg from public.reposicao_config where clinica_id = v_cli.id;
  if not found or not v_cfg.ativo or v_cfg.quem_remarca <> 'aluno' then
    return json_build_object('ok', false, 'erro', 'Esta clínica não oferece remarcação online de reposição.');
  end if;

  v_pac := public.reposicao_publica_aluno(v_cli.id, p_cpf, p_whatsapp);
  if v_pac is null then
    return json_build_object('ok', false, 'erro', 'Não encontramos crédito de reposição para este CPF e WhatsApp.');
  end if;

  begin v_hora := p_hora::time;
  exception when others then return json_build_object('ok', false, 'erro', 'Horário inválido.'); end;

  if p_data < v_agora or p_data > v_agora + 60 then
    return json_build_object('ok', false, 'erro', 'Escolha uma data entre hoje e os próximos 60 dias.');
  end if;
  v_dia := (array['dom','seg','ter','qua','qui','sex','sab'])[extract(dow from p_data)::int + 1];
  if not (v_dia = any (coalesce(v_cli.dias_atendimento, array['seg','ter','qua','qui','sex']))) then
    return json_build_object('ok', false, 'erro', 'A clínica não atende neste dia.');
  end if;
  v_ini := coalesce((v_cli.horarios_por_dia -> v_dia ->> 'inicio')::time, v_cli.horario_inicio, '08:00'::time);
  v_fim := coalesce((v_cli.horarios_por_dia -> v_dia ->> 'fim')::time, v_cli.horario_fim, '18:00'::time);
  if v_hora < v_ini or v_hora >= v_fim then
    return json_build_object('ok', false, 'erro', 'Horário fora do período de atendimento.');
  end if;
  if ((extract(hour from v_hora) * 60 + extract(minute from v_hora))::int
      - (extract(hour from v_ini) * 60 + extract(minute from v_ini))::int) % coalesce(v_cli.intervalo_consulta, 60) <> 0 then
    return json_build_object('ok', false, 'erro', 'Horário inválido para a agenda da clínica.');
  end if;
  v_ts := (p_data::text || ' ' || to_char(v_hora, 'HH24:MI') || ':00')::timestamp at time zone 'America/Sao_Paulo';
  if v_ts <= now() then
    return json_build_object('ok', false, 'erro', 'Este horário já passou. Escolha outro.');
  end if;

  -- crédito que vence primeiro e ainda cobre a data escolhida
  select * into v_cr from public.reposicao_creditos
   where clinica_id = v_cli.id and paciente_id = v_pac and status = 'disponivel'
     and expira_em >= now() and expira_em >= v_ts
   order by expira_em
   limit 1 for update;
  if not found then
    if exists (select 1 from public.reposicao_creditos
                where clinica_id = v_cli.id and paciente_id = v_pac and status = 'disponivel' and expira_em >= now()) then
      return json_build_object('ok', false, 'erro', 'Seu crédito vence antes desta data. Escolha um dia até '
        || (select to_char(max(expira_em) at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') from public.reposicao_creditos
             where clinica_id = v_cli.id and paciente_id = v_pac and status = 'disponivel' and expira_em >= now()) || '.');
    end if;
    return json_build_object('ok', false, 'erro', 'Não encontramos crédito de reposição para este CPF e WhatsApp.');
  end if;

  -- vagas do horário (trava por clínica+horário para dois alunos não pegarem a última vaga juntos)
  perform pg_advisory_xact_lock(hashtext(v_cli.id::text || v_ts::text));
  select count(*) into v_ocup from public.consultas
   where clinica_id = v_cli.id and status <> 'cancelado' and data_hora = v_ts;
  if v_ocup >= v_cfg.vagas_por_horario then
    return json_build_object('ok', false, 'erro', 'Este horário está lotado. Escolha outro.');
  end if;
  if exists (select 1 from public.consultas where paciente_id = v_pac and status <> 'cancelado' and data_hora = v_ts) then
    return json_build_object('ok', false, 'erro', 'Você já tem aula neste horário.');
  end if;

  if v_cr.pagamento_origem = 'pago' then v_valor := 0; v_pag := 'isento';
  else v_valor := v_cr.valor_origem; v_pag := coalesce(v_cr.pagamento_origem, 'pendente'); end if;
  if v_pag not in ('pendente','pago','isento','pacote') then v_pag := 'pendente'; end if;

  perform set_config('nastadesk.reposicao_rpc', 'on', true);
  insert into public.consultas (clinica_id, paciente_id, data_hora, status, origem, valor, pagamento_status,
                                modalidade_id, profissional_id, sala_id, observacoes)
  values (v_cli.id, v_pac, v_ts, 'agendado', 'online', v_valor, v_pag,
          v_cr.modalidade_id, v_cr.profissional_id, v_cr.sala_id,
          '🔄 Reposição (marcada pelo aluno) da aula de ' || to_char(v_cr.data_aula_origem at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'))
  returning id into v_id;
  update public.reposicao_creditos
     set status = 'usado', consulta_reposicao_id = v_id, usado_em = now(), usado_por = 'aluno'
   where id = v_cr.id;
  perform set_config('nastadesk.reposicao_rpc', '', true);

  select nome into v_nome from public.pacientes where id = v_pac;
  insert into public.alertas (clinica_id, tipo, mensagem)
  values (v_cli.id, 'novo_agendamento',
    '🔄 Reposição marcada pelo aluno: ' || coalesce(v_nome, 'aluno') || ' — ' || to_char(p_data, 'DD/MM') || ' às ' || to_char(v_hora, 'HH24:MI'));

  return json_build_object('ok', true, 'consulta_id', v_id, 'clinica', v_cli.nome, 'endereco', v_cli.endereco,
    'data', to_char(p_data, 'DD/MM/YYYY'), 'hora', to_char(v_hora, 'HH24:MI'));
end;
$$;

revoke all on function public.reposicao_publica_info(text) from public;
revoke all on function public.reposicao_publica_creditos(text, text, text) from public;
revoke all on function public.reposicao_publica_lotados(text, date) from public;
revoke all on function public.reposicao_publica_agendar(text, text, text, date, text) from public;
grant execute on function public.reposicao_publica_info(text) to anon, authenticated;
grant execute on function public.reposicao_publica_creditos(text, text, text) to anon, authenticated;
grant execute on function public.reposicao_publica_lotados(text, date) to anon, authenticated;
grant execute on function public.reposicao_publica_agendar(text, text, text, date, text) to anon, authenticated;
