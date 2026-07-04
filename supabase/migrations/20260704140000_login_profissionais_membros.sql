-- ============================================================
-- LOGIN DE PROFISSIONAIS + PAPÉIS — FASE 2
-- 100% ADITIVO. Clínicas de login único não mudam nada: clinica_membros
-- nasce vazia → as políticas de membro não concedem acesso a ninguém até
-- o dono criar um funcionário. Isolamento entre clínicas validado com JWT
-- simulado (ROLLBACK): funcionário de A vê só A; usuário aleatório vê 0.
-- APLICADA EM PRODUÇÃO em 2026-07-04.
-- ============================================================

create table if not exists public.clinica_membros (
  id uuid primary key default extensions.uuid_generate_v4(),
  clinica_id uuid not null references public.clinicas(id) on delete cascade,
  user_id uuid not null,
  papel text not null check (papel in ('recepcao','profissional')),
  nome text,
  profissional_id uuid references public.profissionais(id) on delete set null,
  ativo boolean not null default true,
  criado_em timestamptz default now(),
  unique (user_id)
);
alter table public.clinica_membros enable row level security;

drop policy if exists membros_dono on public.clinica_membros;
create policy membros_dono on public.clinica_membros for all
  to authenticated
  using (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())))
  with check (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())));

drop policy if exists membros_self on public.clinica_membros;
create policy membros_self on public.clinica_membros for select
  to authenticated
  using (user_id = (select auth.uid()));

create index if not exists clinica_membros_clinica_idx on public.clinica_membros (clinica_id, ativo);

-- Resolve as clínicas em que o usuário é FUNCIONÁRIO ativo.
-- SECURITY DEFINER: lê clinica_membros sem cair no RLS da própria tabela
-- (senão a subconsulta usada dentro das policies voltaria vazia).
create or replace function public.clinica_ids_membro()
returns setof uuid language sql stable security definer set search_path = public as $$
  select clinica_id from public.clinica_membros where user_id = (select auth.uid()) and ativo
$$;
revoke all on function public.clinica_ids_membro() from public;
grant execute on function public.clinica_ids_membro() to authenticated;

-- Políticas ADITIVAS de membro (o dono mantém as policies antigas; o membro entra via OR).
do $$
declare t text;
begin
  foreach t in array array[
    'pacientes','consultas','evolucoes','modalidades','profissionais','salas',
    'mensalidades','pacotes','lembretes','conversas','mensagens','alertas',
    'configuracoes','despesas','whatsapp_conexoes'
  ] loop
    execute format('drop policy if exists %I on public.%I', t||'_membros', t);
    execute format(
      'create policy %I on public.%I for all to authenticated using (clinica_id in (select public.clinica_ids_membro())) with check (clinica_id in (select public.clinica_ids_membro()))',
      t||'_membros', t);
  end loop;
end $$;

-- O funcionário lê a própria clínica.
drop policy if exists clinicas_membro_ve on public.clinicas;
create policy clinicas_membro_ve on public.clinicas for select
  to authenticated
  using (id in (select public.clinica_ids_membro()));

do $$
begin
  begin execute 'alter publication supabase_realtime add table public.clinica_membros'; exception when duplicate_object then null; end;
end $$;
