-- SEGURANCA (2026-07-07): fecha escalonamento de privilegio critico.
-- A policy antiga "admin_proprio" era FOR ALL com USING (auth.uid()=user_id) e SEM WITH CHECK.
-- No Postgres, sem WITH CHECK o INSERT passa a ser validado pelo USING -> qualquer usuario
-- logado (o trial self-service ja da uma conta logada) conseguia inserir uma linha com o
-- proprio user_id e virar admin global (o edge admin-api confia nesta tabela para liberar o
-- painel administrativo: ver todas as clinicas/assinaturas e conceder/remover acesso).
-- Confirmado empiricamente com teste rolled-back.
-- Correcao: nastaclin_admins vira SELECT-only para o proprio usuario; nenhum INSERT/UPDATE/DELETE
-- por anon/authenticated. A lista de admins passa a ser gerida so via service_role (admin-api) / SQL.

drop policy if exists admin_proprio on public.nastaclin_admins;

create policy nastaclin_admins_ve_proprio
  on public.nastaclin_admins
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

revoke insert, update, delete, truncate on public.nastaclin_admins from anon, authenticated;
