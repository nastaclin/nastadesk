-- ============================================================
-- MODALIDADES (Pilates/Fisio) + COBRANÇA POR PACIENTE (MENSALIDADES)
-- 100% ADITIVO: novas tabelas, colunas opcionais e RPCs.
-- Nada existente é removido ou alterado de forma destrutiva.
-- Clínicas que não usarem os recursos não veem diferença.
-- ============================================================

-- ===== 1. MODALIDADES (lista configurável por clínica) =====
create table if not exists public.modalidades (
  id uuid primary key default extensions.uuid_generate_v4(),
  clinica_id uuid not null references public.clinicas(id) on delete cascade,
  nome text not null,
  cor text not null default '#0B6E4F',
  ordem integer not null default 0,
  ativo boolean not null default true,
  criado_em timestamptz default now()
);

alter table public.modalidades enable row level security;

drop policy if exists modalidades_da_clinica on public.modalidades;
create policy modalidades_da_clinica on public.modalidades for all
  using (clinica_id in (select id from public.clinicas where user_id = auth.uid()))
  with check (clinica_id in (select id from public.clinicas where user_id = auth.uid()));

create index if not exists modalidades_clinica_idx on public.modalidades (clinica_id, ativo, ordem);

-- Semeia Fisioterapia + Pilates para cada clínica que ainda não tem modalidades
insert into public.modalidades (clinica_id, nome, cor, ordem)
select c.id, m.nome, m.cor, m.ordem
from public.clinicas c
cross join (values
  ('Fisioterapia', '#0B6E4F', 0),
  ('Pilates',      '#7B5CF0', 1)
) as m(nome, cor, ordem)
where not exists (select 1 from public.modalidades mm where mm.clinica_id = c.id);

-- ===== 2. MODALIDADE no paciente e na consulta (opcional) =====
alter table public.pacientes
  add column if not exists modalidade_id uuid references public.modalidades(id) on delete set null;
alter table public.consultas
  add column if not exists modalidade_id uuid references public.modalidades(id) on delete set null;
create index if not exists pacientes_modalidade_idx on public.pacientes (modalidade_id);
create index if not exists consultas_modalidade_idx on public.consultas (modalidade_id);

-- ===== 3. COBRANÇA por paciente (mensalidade fixa OU por sessão) =====
alter table public.pacientes
  add column if not exists cobranca_tipo text not null default 'nenhuma',
  add column if not exists cobranca_valor numeric(10,2),
  add column if not exists cobranca_dia_vencimento integer;

alter table public.pacientes drop constraint if exists pacientes_cobranca_tipo_check;
alter table public.pacientes add constraint pacientes_cobranca_tipo_check
  check (cobranca_tipo = any (array['nenhuma','mensalidade','sessao']));

alter table public.pacientes drop constraint if exists pacientes_cobranca_dia_check;
alter table public.pacientes add constraint pacientes_cobranca_dia_check
  check (cobranca_dia_vencimento is null or (cobranca_dia_vencimento between 1 and 31));

-- ===== 4. MENSALIDADES (ledger mês a mês por paciente) =====
create table if not exists public.mensalidades (
  id uuid primary key default extensions.uuid_generate_v4(),
  clinica_id uuid not null references public.clinicas(id) on delete cascade,
  paciente_id uuid not null references public.pacientes(id) on delete cascade,
  competencia date not null,            -- 1º dia do mês de referência (YYYY-MM-01)
  valor numeric(10,2),
  vencimento date,
  status text not null default 'pendente',
  forma_pagamento text,
  pago_em timestamptz,
  criado_em timestamptz default now(),
  unique (paciente_id, competencia)
);

alter table public.mensalidades enable row level security;

drop policy if exists mensalidades_da_clinica on public.mensalidades;
create policy mensalidades_da_clinica on public.mensalidades for all
  using (clinica_id in (select id from public.clinicas where user_id = auth.uid()))
  with check (clinica_id in (select id from public.clinicas where user_id = auth.uid()));

create index if not exists mensalidades_clinica_comp_idx on public.mensalidades (clinica_id, competencia);
create index if not exists mensalidades_paciente_idx on public.mensalidades (paciente_id);

alter table public.mensalidades drop constraint if exists mensalidades_status_check;
alter table public.mensalidades add constraint mensalidades_status_check
  check (status = any (array['pendente','pago','isento']));

alter table public.mensalidades drop constraint if exists mensalidades_forma_check;
alter table public.mensalidades add constraint mensalidades_forma_check
  check (forma_pagamento is null or forma_pagamento = any
    (array['dinheiro','pix','cartao_credito','cartao_debito','convenio','transferencia']));

-- ===== 5. RPC: abrir/gerar mensalidades do mês para a clínica do usuário =====
-- Idempotente (ON CONFLICT DO NOTHING). Só gera para o mês corrente ou futuro,
-- para nunca fabricar dívidas retroativas em meses já passados.
create or replace function public.gerar_mensalidades(p_competencia date)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_comp     date := date_trunc('month', p_competencia)::date;
  v_mes_atual date := date_trunc('month', (now() at time zone 'America/Sao_Paulo'))::date;
  v_ult_dia  int  := extract(day from (v_comp + interval '1 month - 1 day'))::int;
begin
  if v_comp < v_mes_atual then
    return;  -- não gera nada para meses passados (preserva histórico real)
  end if;

  insert into public.mensalidades (clinica_id, paciente_id, competencia, valor, vencimento, status)
  select p.clinica_id,
         p.id,
         v_comp,
         p.cobranca_valor,
         (v_comp + (least(coalesce(p.cobranca_dia_vencimento, 5), v_ult_dia) - 1) * interval '1 day')::date,
         'pendente'
  from public.pacientes p
  join public.clinicas c on c.id = p.clinica_id
  where c.user_id = auth.uid()
    and p.cobranca_tipo = 'mensalidade'
  on conflict (paciente_id, competencia) do nothing;
end;
$$;

revoke execute on function public.gerar_mensalidades(date) from public, anon;
grant execute on function public.gerar_mensalidades(date) to authenticated;

-- ===== 6. Realtime =====
do $$
begin
  begin execute 'alter publication supabase_realtime add table public.modalidades'; exception when duplicate_object then null; end;
  begin execute 'alter publication supabase_realtime add table public.mensalidades'; exception when duplicate_object then null; end;
end $$;
