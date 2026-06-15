-- NastaDesk — Assinaturas (Mercado Pago)
-- Formaliza a tabela de assinaturas e os estados de cobrança.
-- A tabela já existe no banco; aqui garantimos colunas, índices e RLS de forma idempotente.

create table if not exists public.assinaturas (
  id uuid primary key default uuid_generate_v4(),
  clinica_id uuid not null references public.clinicas(id) on delete cascade,
  plano text not null,
  provedor text not null default 'mercadopago',
  provider_id text,
  status text not null default 'pendente',   -- pendente | ativa | em_atraso | cancelada
  valor numeric,
  payer_email text,
  criado_em timestamptz default now(),
  atualizado_em timestamptz default now()
);

-- Colunas novas para controle de cobrança/tolerância
alter table public.assinaturas add column if not exists init_point text;
alter table public.assinaturas add column if not exists proximo_pagamento timestamptz;
alter table public.assinaturas add column if not exists em_atraso_desde timestamptz;
alter table public.assinaturas add column if not exists cancelada_em timestamptz;

-- Um provider_id (id da assinatura no Mercado Pago) é único
create unique index if not exists assinaturas_provider_id_uidx
  on public.assinaturas(provider_id) where provider_id is not null;
create index if not exists assinaturas_clinica_idx on public.assinaturas(clinica_id);

alter table public.assinaturas enable row level security;

-- Leitura: a clínica vê apenas as suas próprias assinaturas.
-- (Escrita é feita só pelo service role nas Edge Functions de checkout/webhook.)
drop policy if exists assinaturas_da_clinica on public.assinaturas;
create policy assinaturas_da_clinica on public.assinaturas
  for select using (
    clinica_id in (select id from public.clinicas where user_id = auth.uid())
  );
