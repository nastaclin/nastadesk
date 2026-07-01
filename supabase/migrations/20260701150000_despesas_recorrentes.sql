-- ============================================================
-- DESPESAS RECORRENTES (contas fixas que repetem todo mês) — FASE 2
-- 100% ADITIVO. Espelha o padrão idempotente das mensalidades:
-- template + RPC que "abre" a conta do mês (nunca retroativo, sem duplicar).
-- ============================================================

-- ===== 1. TEMPLATE de despesa recorrente (conta fixa) =====
create table if not exists public.despesas_recorrentes (
  id uuid primary key default extensions.uuid_generate_v4(),
  clinica_id uuid not null references public.clinicas(id) on delete cascade,
  descricao text not null,
  categoria text not null default 'outros',
  valor numeric(10,2) not null default 0,
  dia_vencimento integer,                      -- dia do mês (1..31); default 5 se null
  ativo boolean not null default true,
  criado_em timestamptz default now()
);

alter table public.despesas_recorrentes enable row level security;

drop policy if exists despesas_recorrentes_da_clinica on public.despesas_recorrentes;
create policy despesas_recorrentes_da_clinica on public.despesas_recorrentes for all
  to authenticated
  using (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())))
  with check (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())));

create index if not exists despesas_recorrentes_clinica_idx on public.despesas_recorrentes (clinica_id, ativo);

alter table public.despesas_recorrentes drop constraint if exists despesas_recorrentes_dia_check;
alter table public.despesas_recorrentes add constraint despesas_recorrentes_dia_check
  check (dia_vencimento is null or (dia_vencimento between 1 and 31));

-- ===== 2. Vincula a despesa gerada ao seu template (opcional) =====
alter table public.despesas
  add column if not exists recorrencia_id uuid references public.despesas_recorrentes(id) on delete set null;

-- Uma despesa por template por mês (idempotência). NULLs não conflitam,
-- então despesas avulsas (sem template) não são afetadas.
create unique index if not exists despesas_recorrencia_comp_uidx
  on public.despesas (recorrencia_id, competencia)
  where recorrencia_id is not null;

-- ===== 3. RPC: abrir as contas fixas do mês (idempotente, nunca retroativo) =====
create or replace function public.gerar_despesas_recorrentes(p_competencia date)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_comp      date := date_trunc('month', p_competencia)::date;
  v_mes_atual date := date_trunc('month', (now() at time zone 'America/Sao_Paulo'))::date;
  v_ult_dia   int  := extract(day from (v_comp + interval '1 month - 1 day'))::int;
begin
  if v_comp < v_mes_atual then
    return;  -- não fabrica contas em meses passados
  end if;

  insert into public.despesas (clinica_id, descricao, categoria, valor, competencia, vencimento, status, recorrencia_id)
  select r.clinica_id,
         r.descricao,
         r.categoria,
         r.valor,
         v_comp,
         (v_comp + (least(coalesce(r.dia_vencimento, 5), v_ult_dia) - 1) * interval '1 day')::date,
         'pendente',
         r.id
  from public.despesas_recorrentes r
  join public.clinicas c on c.id = r.clinica_id
  where c.user_id = (select auth.uid())
    and r.ativo = true
  on conflict (recorrencia_id, competencia) where recorrencia_id is not null do nothing;
end;
$$;

revoke execute on function public.gerar_despesas_recorrentes(date) from public, anon;
grant execute on function public.gerar_despesas_recorrentes(date) to authenticated;

-- ===== 4. Realtime =====
do $$
begin
  begin execute 'alter publication supabase_realtime add table public.despesas_recorrentes'; exception when duplicate_object then null; end;
end $$;
