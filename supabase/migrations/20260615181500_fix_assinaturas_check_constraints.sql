-- NastaDesk — Corrige as CHECK constraints da tabela assinaturas
-- A tabela foi criada antes da integração e tinha constraints desalinhadas do código:
--   * plano: só aceitava 'profissional'/'premium' (rejeitava 'basico', um plano pago).
--   * status: aceitava 'pausada' em vez de 'em_atraso' (usado pelo webhook na cobrança em atraso).
-- Sintoma em produção (silencioso, pois o insert não checava erro):
--   * Assinar a Básica nunca ativava o plano (insert falhava, webhook não achava a assinatura).
--   * Cobrança em atraso não era registrada (update para 'em_atraso' batia na constraint).

alter table public.assinaturas drop constraint if exists assinaturas_plano_check;
alter table public.assinaturas
  add constraint assinaturas_plano_check
  check (plano in ('basico', 'profissional', 'premium'));

alter table public.assinaturas drop constraint if exists assinaturas_status_check;
alter table public.assinaturas
  add constraint assinaturas_status_check
  check (status in ('pendente', 'ativa', 'em_atraso', 'cancelada'));
