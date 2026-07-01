-- ============================================================
-- FINANCEIRO COMPLETO (despesas/contas a pagar) + BASE FISCAL (NFS-e)
-- FASE 2 — financeiro + nota fiscal (fundação).
-- 100% ADITIVO: novas tabelas isoladas por clínica. Nada existente
-- é removido/alterado. O financeiro por consulta/mensalidade/repasse
-- continua idêntico. Clínica que não usar não vê diferença.
-- RLS no formato performático: (select auth.uid()) + TO authenticated.
-- ============================================================

-- ===== 1. DESPESAS / CONTAS A PAGAR (ledger por clínica) =====
-- Saídas de caixa da clínica (aluguel, materiais, salários, repasse,
-- impostos, etc.). Usado no Financeiro → Despesas, no Fluxo de caixa
-- e no DRE simples. Cada linha é uma conta a pagar de um mês.
create table if not exists public.despesas (
  id uuid primary key default extensions.uuid_generate_v4(),
  clinica_id uuid not null references public.clinicas(id) on delete cascade,
  descricao text not null,
  categoria text not null default 'outros',   -- rótulo livre p/ agrupar no DRE
  valor numeric(10,2) not null default 0,
  competencia date not null,                   -- 1º dia do mês de referência (YYYY-MM-01)
  vencimento date,
  status text not null default 'pendente',     -- pendente | pago
  forma_pagamento text,
  pago_em timestamptz,
  observacao text,
  criado_em timestamptz default now()
);

alter table public.despesas enable row level security;

drop policy if exists despesas_da_clinica on public.despesas;
create policy despesas_da_clinica on public.despesas for all
  to authenticated
  using (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())))
  with check (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())));

create index if not exists despesas_clinica_comp_idx on public.despesas (clinica_id, competencia, status);

alter table public.despesas drop constraint if exists despesas_status_check;
alter table public.despesas add constraint despesas_status_check
  check (status = any (array['pendente','pago']));

alter table public.despesas drop constraint if exists despesas_forma_check;
alter table public.despesas add constraint despesas_forma_check
  check (forma_pagamento is null or forma_pagamento = any
    (array['dinheiro','pix','cartao_credito','cartao_debito','transferencia','boleto']));

-- ===== 2. DADOS FISCAIS por clínica (fundação da NFS-e) =====
-- Guarda os dados fiscais que a NFS-e vai exigir (razão social, CNPJ,
-- regime, código de serviço, ISS...). Por ora é só cadastro: a emissão
-- real depende de um emissor externo + certificado A1 (etapa dedicada).
-- Um registro por clínica (unique).
create table if not exists public.config_fiscal (
  id uuid primary key default extensions.uuid_generate_v4(),
  clinica_id uuid not null unique references public.clinicas(id) on delete cascade,
  razao_social text,
  cnpj text,
  inscricao_municipal text,
  regime_tributario text,                      -- mei | simples_nacional | lucro_presumido | outro
  codigo_servico text,
  aliquota_iss numeric(5,2),
  iss_retido boolean not null default false,
  emissor text,                                -- plugnotas | focus | enotas | nfeio | outro (nullable)
  ativo boolean not null default false,        -- emissão automática ligada? (fica off até integrar)
  criado_em timestamptz default now(),
  atualizado_em timestamptz default now()
);

alter table public.config_fiscal enable row level security;

drop policy if exists config_fiscal_da_clinica on public.config_fiscal;
create policy config_fiscal_da_clinica on public.config_fiscal for all
  to authenticated
  using (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())))
  with check (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())));

create index if not exists config_fiscal_clinica_idx on public.config_fiscal (clinica_id);

alter table public.config_fiscal drop constraint if exists config_fiscal_regime_check;
alter table public.config_fiscal add constraint config_fiscal_regime_check
  check (regime_tributario is null or regime_tributario = any
    (array['mei','simples_nacional','lucro_presumido','lucro_real','outro']));

-- ===== 3. Realtime =====
do $$
begin
  begin execute 'alter publication supabase_realtime add table public.despesas'; exception when duplicate_object then null; end;
  begin execute 'alter publication supabase_realtime add table public.config_fiscal'; exception when duplicate_object then null; end;
end $$;
