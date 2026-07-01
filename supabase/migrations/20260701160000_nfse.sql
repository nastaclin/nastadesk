-- ============================================================
-- NFS-e via PlugNotas (TecnoSpeed) — FASE 2 · emissão de nota fiscal
-- 100% ADITIVO. Estende config_fiscal (campos que a emissão exige) e
-- cria o ledger notas_fiscais. A emissão real roda numa Edge Function
-- (nfse) que fala com o PlugNotas; aqui só o modelo de dados.
-- ============================================================

-- ===== 1. Campos extras em config_fiscal p/ a emissão =====
alter table public.config_fiscal
  add column if not exists ambiente text not null default 'homologacao',   -- homologacao | producao
  add column if not exists cnae text,
  add column if not exists codigo_tributacao_municipio text;

alter table public.config_fiscal drop constraint if exists config_fiscal_ambiente_check;
alter table public.config_fiscal add constraint config_fiscal_ambiente_check
  check (ambiente = any (array['homologacao','producao']));

-- ===== 2. LEDGER de notas fiscais emitidas =====
create table if not exists public.notas_fiscais (
  id uuid primary key default extensions.uuid_generate_v4(),
  clinica_id uuid not null references public.clinicas(id) on delete cascade,
  consulta_id uuid references public.consultas(id) on delete set null,
  paciente_id uuid references public.pacientes(id) on delete set null,
  id_integracao text not null,            -- idempotência (ex.: consulta-<uuid>)
  valor numeric(10,2),
  descricao text,
  status text not null default 'processando',  -- rascunho|processando|emitida|erro|cancelada|negada
  plugnotas_id text,
  protocolo text,
  numero text,
  link_pdf text,
  link_xml text,
  erro text,
  ambiente text not null default 'homologacao',
  criado_em timestamptz default now(),
  atualizado_em timestamptz default now(),
  unique (clinica_id, id_integracao)
);

alter table public.notas_fiscais enable row level security;

drop policy if exists notas_fiscais_da_clinica on public.notas_fiscais;
create policy notas_fiscais_da_clinica on public.notas_fiscais for all
  to authenticated
  using (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())))
  with check (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())));

create index if not exists notas_fiscais_clinica_idx on public.notas_fiscais (clinica_id, criado_em desc);
create index if not exists notas_fiscais_consulta_idx on public.notas_fiscais (consulta_id);

alter table public.notas_fiscais drop constraint if exists notas_fiscais_status_check;
alter table public.notas_fiscais add constraint notas_fiscais_status_check
  check (status = any (array['rascunho','processando','emitida','erro','cancelada','negada']));

-- ===== 3. Realtime =====
do $$
begin
  begin execute 'alter publication supabase_realtime add table public.notas_fiscais'; exception when duplicate_object then null; end;
end $$;
