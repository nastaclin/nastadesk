-- 2026-10-24 — Clínica passa a guardar o e-mail do login (aplicada em produção, versão 20261024053400).
--
-- POR QUÊ: o gatilho de cadastro (criar_clinica_no_signup) nunca gravava clinicas.email,
-- e o cakto-webhook acha a clínica pelo e-mail do comprador. Resultado: NENHUM pagamento
-- pela Cakto liberava a clínica (as 7 clínicas do banco estavam com e-mail vazio).
-- Descoberto no teste real de assinatura (oferta de teste R$ 5) em 24/10/2026.
--
-- ADITIVA: trigger novo (só preenche e-mail VAZIO no INSERT, não sobrescreve) + backfill
-- só das linhas com e-mail vazio. Testada antes em transação desfeita (8/8).
-- Rollback: drop trigger if exists trg_clinicas_preencher_email on public.clinicas;
create or replace function public.clinicas_preencher_email()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  if new.email is null and new.user_id is not null then
    select u.email into new.email from auth.users u where u.id = new.user_id;
  end if;
  return new;
end;
$function$;

revoke all on function public.clinicas_preencher_email() from public, anon, authenticated;

drop trigger if exists trg_clinicas_preencher_email on public.clinicas;
create trigger trg_clinicas_preencher_email before insert on public.clinicas
  for each row execute function public.clinicas_preencher_email();

update public.clinicas c
   set email = u.email
  from auth.users u
 where u.id = c.user_id
   and c.email is null;
