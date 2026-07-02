-- ============================================================
-- NFS-e: token do emissor POR CLÍNICA — FASE 2
-- Motivo: quem emite a nota é a clínica (prestadora), não a Nastaclin.
-- Assim cada clínica conecta a própria conta do Focus NFe (com o CNPJ
-- dela) colando o token — a Nastaclin não precisa de CNPJ nem fica no
-- meio da parte fiscal. O token fica protegido por RLS (só a própria
-- clínica e o service_role leem). A Edge Function usa o token da clínica
-- e, se não houver, cai no token global do ambiente (FOCUS_NFE_TOKEN_*).
-- 100% ADITIVO.
-- ============================================================

alter table public.config_fiscal
  add column if not exists emissor_token_homologacao text,
  add column if not exists emissor_token_producao text;
