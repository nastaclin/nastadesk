-- ===== SALAS / SALÕES DE ATENDIMENTO =====
-- Permite organizar os atendimentos por salão (sala), além de por data/horário.
-- Cada clínica cadastra seus salões e cada consulta pode (opcionalmente) ser
-- vinculada a um salão.

create table if not exists public.salas (
  id uuid primary key default extensions.uuid_generate_v4(),
  clinica_id uuid not null references public.clinicas(id) on delete cascade,
  nome text not null,
  ordem integer not null default 0,
  ativo boolean not null default true,
  criado_em timestamptz default now()
);

alter table public.salas enable row level security;

drop policy if exists salas_da_clinica on public.salas;
create policy salas_da_clinica on public.salas for all
  using (clinica_id in (select id from public.clinicas where user_id = auth.uid()))
  with check (clinica_id in (select id from public.clinicas where user_id = auth.uid()));

create index if not exists salas_clinica_idx on public.salas (clinica_id, ativo, ordem);

-- Vínculo consulta -> salão (opcional). Se o salão for removido, a consulta
-- apenas fica sem salão (não é apagada).
alter table public.consultas add column if not exists sala_id uuid references public.salas(id) on delete set null;
create index if not exists consultas_sala_idx on public.consultas (sala_id);

-- Realtime
do $$
begin
  begin
    execute 'alter publication supabase_realtime add table public.salas';
  exception when duplicate_object then null;
  end;
end $$;
