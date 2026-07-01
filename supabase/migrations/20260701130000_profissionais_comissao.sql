-- ============================================================
-- REPASSE / COMISSÃO por profissional — FASE 2
-- 100% ADITIVO: só adiciona colunas opcionais em profissionais.
-- Nada existente é alterado. Sem repasse configurado = 0 (nada muda).
-- ============================================================

alter table public.profissionais
  add column if not exists comissao_tipo text not null default 'nenhuma',
  add column if not exists comissao_valor numeric(10,2);

alter table public.profissionais drop constraint if exists profissionais_comissao_tipo_check;
alter table public.profissionais add constraint profissionais_comissao_tipo_check
  check (comissao_tipo = any (array['nenhuma','percentual','valor']));
