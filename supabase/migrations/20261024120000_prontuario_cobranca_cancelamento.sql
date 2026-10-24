-- =============================================================================
-- 2026-10-24 — Correções bloqueantes do checkup (antes dos anúncios)
--
--   A) Prontuário: autor + CREFITO em cada evolução/avaliação (COFFITO 414/2012,
--      art. 2º, par. único), evolução imutável e guarda mínima de 5 anos (art. 6º, I).
--   B) Cobrança: o dono da clínica NÃO consegue mais se dar plano/acesso pela API
--      (antes, um UPDATE em clinicas.ativo/plano/cortesia passava pelo RLS).
--   C) Cancelamento: quem cancela a assinatura usa até o fim do período pago;
--      o corte acontece pelo cron, não na hora do cancelamento.
--
-- 100% ADITIVA: só colunas, funções, triggers e um job de cron novos. Nada é
-- renomeado, apagado ou alterado em colunas, policies ou funções existentes.
-- Idempotente. Testada em produção dentro de transação desfeita (ver CLAUDE.md).
--
-- ROLLBACK (desfaz o comportamento sem perder dado):
--   drop trigger if exists trg_evolucoes_autor          on public.evolucoes;
--   drop trigger if exists trg_avaliacoes_autor         on public.avaliacoes;
--   drop trigger if exists trg_evolucoes_imutavel       on public.evolucoes;
--   drop trigger if exists trg_evolucoes_guarda         on public.evolucoes;
--   drop trigger if exists trg_avaliacoes_guarda        on public.avaliacoes;
--   drop trigger if exists trg_clinicas_campos_cobranca on public.clinicas;
--   select cron.unschedule('nastadesk-cancelamento-fim-periodo');
-- =============================================================================

-- ============================ A) PRONTUÁRIO ==================================

alter table public.evolucoes  add column if not exists autor_user_id   uuid;
alter table public.evolucoes  add column if not exists profissional_id uuid;
alter table public.evolucoes  add column if not exists autor_nome      text;
alter table public.evolucoes  add column if not exists autor_registro  text;

alter table public.avaliacoes add column if not exists autor_user_id   uuid;
alter table public.avaliacoes add column if not exists autor_nome      text;
alter table public.avaliacoes add column if not exists autor_registro  text;

-- Autor preenchido no servidor (o navegador não consegue forjar):
--   profissional vinculado ao login -> nome + registro do cadastro de profissionais
--   dono                             -> responsável + recibo_registro da clínica
--   recepção / outros                -> nome do membro ou e-mail do login
-- Qualquer falha na busca NUNCA impede salvar o registro.
create or replace function public.prontuario_preencher_autor()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_uid     uuid := auth.uid();
  v_prof_id uuid;
  v_nome    text;
  v_reg     text;
begin
  new.autor_user_id := v_uid;
  if v_uid is null then
    return new;  -- backend (service_role): mantém o que veio
  end if;

  begin
    select m.profissional_id, m.nome into v_prof_id, v_nome
      from public.clinica_membros m
     where m.user_id = v_uid and m.clinica_id = new.clinica_id and m.ativo
     limit 1;

    if v_prof_id is not null then
      select p.nome, p.registro into v_nome, v_reg
        from public.profissionais p where p.id = v_prof_id;
    elsif v_nome is null then
      select c.responsavel, c.recibo_registro into v_nome, v_reg
        from public.clinicas c where c.id = new.clinica_id and c.user_id = v_uid;
    end if;

    if coalesce(trim(v_nome), '') = '' then
      select u.email into v_nome from auth.users u where u.id = v_uid;
    end if;
  exception when others then
    null;
  end;

  new.profissional_id := coalesce(new.profissional_id, v_prof_id);
  new.autor_nome      := nullif(trim(v_nome), '');
  new.autor_registro  := nullif(trim(v_reg), '');
  return new;
end;
$function$;

drop trigger if exists trg_evolucoes_autor on public.evolucoes;
create trigger trg_evolucoes_autor before insert on public.evolucoes
  for each row execute function public.prontuario_preencher_autor();

drop trigger if exists trg_avaliacoes_autor on public.avaliacoes;
create trigger trg_avaliacoes_autor before insert on public.avaliacoes
  for each row execute function public.prontuario_preencher_autor();

-- Até quando o prontuário do paciente precisa ser guardado:
-- último registro clínico (evolução, avaliação ou consulta atendida) + 5 anos.
create or replace function public.prontuario_guarda_ate(p_paciente_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  select greatest(
    (select max(e.criado_em) from public.evolucoes  e where e.paciente_id = p_paciente_id),
    (select max(a.criado_em) from public.avaliacoes a where a.paciente_id = p_paciente_id),
    (select max(c.data_hora) from public.consultas  c where c.paciente_id = p_paciente_id and c.status = 'atendido')
  ) + interval '5 years';
$function$;

-- Evolução registrada não muda (correção = nova evolução, como adendo).
-- Exceções: guarda vencida (anonimização LGPD) ou suporte com a flag de sessão.
create or replace function public.evolucoes_imutavel()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_ate timestamptz;
begin
  if current_setting('nastadesk.permitir_alteracao_prontuario', true) = 'on' then
    return new;
  end if;
  if new.texto is not distinct from old.texto
     and new.criado_em is not distinct from old.criado_em
     and new.autor_user_id is not distinct from old.autor_user_id
     and new.autor_nome is not distinct from old.autor_nome
     and new.autor_registro is not distinct from old.autor_registro then
    return new;
  end if;
  v_ate := public.prontuario_guarda_ate(old.paciente_id);
  if v_ate is not null and v_ate > now() then
    raise exception 'Evolução já registrada não pode ser alterada (COFFITO 414/2012). Registre uma nova evolução como adendo.'
      using errcode = 'P0001';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_evolucoes_imutavel on public.evolucoes;
create trigger trg_evolucoes_imutavel before update on public.evolucoes
  for each row execute function public.evolucoes_imutavel();

-- Não apaga prontuário dentro do prazo de guarda — vale também para as RPCs
-- paciente_excluir / paciente_anonimizar (a transação inteira delas volta).
-- Tolerância: registro criado há menos de 24h (erro de digitação/cadastro).
create or replace function public.prontuario_bloquear_exclusao()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_ate timestamptz;
begin
  if current_setting('nastadesk.permitir_exclusao_prontuario', true) = 'on' then
    return old;
  end if;
  if old.criado_em > now() - interval '24 hours' then
    return old;
  end if;
  v_ate := public.prontuario_guarda_ate(old.paciente_id);
  if v_ate is not null and v_ate > now() then
    raise exception 'Prontuário em guarda obrigatória até % (COFFITO 414/2012, art. 6º). Use "Inativar" no paciente.',
      to_char(v_ate at time zone 'America/Sao_Paulo', 'DD/MM/YYYY')
      using errcode = 'P0001';
  end if;
  return old;
end;
$function$;

drop trigger if exists trg_evolucoes_guarda on public.evolucoes;
create trigger trg_evolucoes_guarda before delete on public.evolucoes
  for each row execute function public.prontuario_bloquear_exclusao();

drop trigger if exists trg_avaliacoes_guarda on public.avaliacoes;
create trigger trg_avaliacoes_guarda before delete on public.avaliacoes
  for each row execute function public.prontuario_bloquear_exclusao();

-- ============================ B) COBRANÇA ====================================
-- Campos que só o backend (webhook da Cakto, cron, painel admin via admin-api)
-- pode mudar. Pedido vindo de usuário logado comum (role 'authenticated') que
-- não é admin: os campos voltam ao valor antigo (no INSERT, ao valor seguro).
-- O app nunca envia esses campos, então nada muda para as clínicas.
create or replace function public.clinicas_proteger_campos_cobranca()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  if coalesce(auth.role(), '') <> 'authenticated' then
    return new;  -- service_role, cron, gatilho de signup: livres
  end if;
  if exists (select 1 from public.nastaclin_admins a where a.user_id = auth.uid()) then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    new.ativo              := old.ativo;
    new.plano              := old.plano;
    new.cortesia           := old.cortesia;
    new.cortesia_expira_em := old.cortesia_expira_em;
    new.user_id            := old.user_id;
  else
    new.ativo              := false;
    new.plano              := null;
    new.cortesia           := false;
    new.cortesia_expira_em := null;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_clinicas_campos_cobranca on public.clinicas;
create trigger trg_clinicas_campos_cobranca before insert or update on public.clinicas
  for each row execute function public.clinicas_proteger_campos_cobranca();

-- ============================ C) CANCELAMENTO ================================
-- O cakto-webhook (v6) passa a manter o acesso de quem cancelou até
-- assinaturas.proximo_pagamento. Este job corta quando o período pago termina.
-- Só toca clínicas cuja assinatura mais recente é uma 'cancelada' com
-- proximo_pagamento vencido; nunca corta cortesia nem quem tem outra assinatura viva.
create or replace function public.encerrar_assinaturas_canceladas()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_n integer;
begin
  update public.clinicas c
     set ativo = false
   where c.ativo = true
     and coalesce(c.cortesia, false) = false
     and not exists (
       select 1 from public.assinaturas a
        where a.clinica_id = c.id and a.status in ('ativa', 'em_atraso', 'pendente')
     )
     and exists (
       select 1 from public.assinaturas a
        where a.clinica_id = c.id
          and a.status = 'cancelada'
          and a.cancelada_em is not null
          and a.proximo_pagamento is not null
          and a.proximo_pagamento < now()
          and a.criado_em = (select max(a2.criado_em) from public.assinaturas a2 where a2.clinica_id = c.id)
     );
  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

-- Funções internas: não chamáveis pela API.
revoke all on function public.prontuario_preencher_autor()         from public, anon, authenticated;
revoke all on function public.evolucoes_imutavel()                 from public, anon, authenticated;
revoke all on function public.prontuario_bloquear_exclusao()       from public, anon, authenticated;
revoke all on function public.prontuario_guarda_ate(uuid)          from public, anon, authenticated;
revoke all on function public.clinicas_proteger_campos_cobranca()  from public, anon, authenticated;
revoke all on function public.encerrar_assinaturas_canceladas()    from public, anon, authenticated;

do $$
begin
  perform cron.unschedule('nastadesk-cancelamento-fim-periodo');
exception when others then
  null;
end $$;

select cron.schedule(
  'nastadesk-cancelamento-fim-periodo',
  '17 * * * *',
  $$select public.encerrar_assinaturas_canceladas()$$
);
