-- ============================================================
-- NFS-e: troca de emissor PlugNotas → Focus NFe — FASE 2
-- Motivo: onboarding do PlugNotas travou (licença TecnoAccount) e
-- não há preço self-service; o Focus NFe tem conta auto-serviço,
-- homologação grátis ilimitada e preços publicados.
-- ADITIVO: 1 coluna nova + rename de coluna interna (tabela ainda
-- sem uso em produção — front não deployado).
-- ============================================================

-- Código IBGE do município do prestador (o Focus NFe exige na emissão)
alter table public.config_fiscal
  add column if not exists codigo_municipio text;

-- Nome neutro p/ o id da nota no emissor (era plugnotas_id)
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'notas_fiscais'
      and column_name = 'plugnotas_id'
  ) then
    alter table public.notas_fiscais rename column plugnotas_id to emissor_id;
  end if;
end $$;
