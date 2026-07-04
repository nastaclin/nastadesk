-- ============================================================
-- RECIBO TURBINADO (sem CNPJ) — dados do emissor por clínica
-- 100% ADITIVO: 2 colunas nullable em clinicas. Nada existente é tocado.
-- Permite imprimir no Recibo de pagamento o CPF/CNPJ e o registro
-- profissional (CREFITO/CRM…) do emissor — útil p/ dedução de IR médico.
-- APLICADA EM PRODUÇÃO em 2026-07-04 (testada antes com ROLLBACK).
-- ============================================================
alter table public.clinicas add column if not exists recibo_cpf_cnpj text;
alter table public.clinicas add column if not exists recibo_registro text;
comment on column public.clinicas.recibo_cpf_cnpj is 'CPF (ou CNPJ) do emissor, impresso no recibo de pagamento';
comment on column public.clinicas.recibo_registro is 'Registro profissional (CREFITO/CRM/etc.) impresso no recibo';
