-- =============================================================================
-- NastaDesk — Acesso à prova de "Premium de graça" + corte no fim do período pago
--
-- 1) Trava de plano: hoje a policy clinica_propria (ALL) deixa o dono fazer
--    UPDATE em qualquer coluna da própria clínica pela API REST — inclusive
--    ativo, plano, cortesia e cortesia_expira_em. Qualquer cliente com o próprio
--    token conseguia se dar Premium para sempre. O app NUNCA grava esses campos
--    pelo navegador (conferido em index.html/profissional.html em 2026-10-24):
--    quem grava é o cakto-webhook, o admin-api (service_role) e as funções
--    admin_* / encerrar_* (security definer, rodam como postgres).
--    A trigger só age quando quem está escrevendo é o papel da API
--    (authenticated/anon): mantém os valores antigos desses 4 campos e segue o
--    resto do UPDATE normalmente (nome, horários etc. continuam salvando).
--
-- 2) Fim do período: quem cancela a assinatura (cakto-cancelar ou portal da
--    Cakto) continua usando até proximo_pagamento. O job abaixo desliga o acesso
--    quando essa data passa. Mesmas guardas do encerrar_cortesias_vencidas:
--    nunca corta cortesia nem quem tem assinatura ativa/em_atraso.
--
-- 100% ADITIVA. Não apaga nem altera dado; não mexe em policy existente.
--
-- ROLLBACK (desfaz tudo):
--   drop trigger if exists trg_clinicas_proteger_acesso on public.clinicas;
--   select cron.unschedule('nastadesk-assinatura-expira');
--   (as funções podem ficar; sem trigger/job elas não fazem nada)
-- =============================================================================

-- 1) Trava dos campos de acesso -----------------------------------------------
create or replace function public.clinicas_proteger_campos_acesso()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- current_user = papel do Postgres que está executando. Pela API REST é
  -- 'authenticated' (logado) ou 'anon'. Dentro de função security definer é o
  -- dono da função (postgres); no admin-api/webhooks é service_role.
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    new.ativo              := old.ativo;
    new.plano              := old.plano;
    new.cortesia           := old.cortesia;
    new.cortesia_expira_em := old.cortesia_expira_em;
  else -- INSERT direto pela API (o app não faz; o cadastro usa o gatilho de signup)
    new.ativo              := false;
    new.cortesia           := false;
    new.cortesia_expira_em := null;
    new.plano              := 'basico';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_clinicas_proteger_acesso on public.clinicas;
create trigger trg_clinicas_proteger_acesso
  before insert or update on public.clinicas
  for each row execute function public.clinicas_proteger_campos_acesso();

-- 2) Corte quando o período pago de uma assinatura cancelada termina ----------
create or replace function public.encerrar_assinaturas_vencidas()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n integer;
begin
  update public.clinicas c
     set ativo = false
   where c.ativo = true
     and coalesce(c.cortesia, false) = false          -- cortesia é do admin, não mexe
     and not exists (                                  -- quem tem assinatura viva não cai
       select 1 from public.assinaturas a
        where a.clinica_id = c.id and a.status in ('ativa', 'em_atraso'))
     and exists (                                      -- cancelou na Cakto e o período pago acabou
       select 1 from public.assinaturas a
        where a.clinica_id = c.id
          and a.provedor = 'cakto'
          and a.status = 'cancelada'
          and a.cancelada_em is not null
          and coalesce(a.proximo_pagamento, a.cancelada_em) < now());
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all on function public.encerrar_assinaturas_vencidas()   from public, anon, authenticated;
revoke all on function public.clinicas_proteger_campos_acesso() from public, anon, authenticated;

-- De hora em hora (minuto 17, para não coincidir com nastadesk-cortesia-expira no minuto 7).
select cron.schedule('nastadesk-assinatura-expira', '17 * * * *', 'select public.encerrar_assinaturas_vencidas()');
