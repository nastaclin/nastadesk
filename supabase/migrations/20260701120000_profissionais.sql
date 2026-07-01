-- ============================================================
-- PROFISSIONAIS (multi-profissional) — FASE 2, item 1
-- 100% ADITIVO: nova tabela + coluna opcional em consultas.
-- Nada existente é removido ou alterado de forma destrutiva.
-- NÃO semeia dados: clínica sem profissional cadastrado não vê
-- diferença nenhuma (feature invisível até ser usada).
-- RLS já no formato performático: (select auth.uid()) + TO authenticated.
-- ============================================================

-- ===== 1. PROFISSIONAIS (lista configurável por clínica) =====
create table if not exists public.profissionais (
  id uuid primary key default extensions.uuid_generate_v4(),
  clinica_id uuid not null references public.clinicas(id) on delete cascade,
  nome text not null,
  registro text,                       -- CREFITO/CRM/etc. (opcional)
  cor text not null default '#0B6E4F',
  ordem integer not null default 0,
  ativo boolean not null default true,
  criado_em timestamptz default now()
);

alter table public.profissionais enable row level security;

drop policy if exists profissionais_da_clinica on public.profissionais;
create policy profissionais_da_clinica on public.profissionais for all
  to authenticated
  using (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())))
  with check (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())));

create index if not exists profissionais_clinica_idx on public.profissionais (clinica_id, ativo, ordem);

-- ===== 2. PROFISSIONAL na consulta (opcional, nullable) =====
alter table public.consultas
  add column if not exists profissional_id uuid references public.profissionais(id) on delete set null;
create index if not exists consultas_profissional_idx on public.consultas (profissional_id);

-- ===== 3. Realtime =====
do $$
begin
  begin execute 'alter publication supabase_realtime add table public.profissionais'; exception when duplicate_object then null; end;
end $$;
