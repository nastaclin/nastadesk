-- ===== Fase 0 · Performance de RLS (auth_rls_initplan + multiple_permissive) =====
-- Reescreve as policies que usavam auth.uid() direto (reavaliado por linha) para
-- (select auth.uid()) (avaliado uma vez) e escopa TO authenticated. A LÓGICA é
-- IDÊNTICA — muda só desempenho. Remove 3 policies de DELETE redundantes (a policy
-- ALL da mesma tabela já cobre DELETE com a mesma condição).
--
-- NÃO tocamos nas policies que já estão no formato bom (config_fiscal, despesas,
-- despesas_recorrentes, notas_fiscais, profissionais).
--
-- Contexto de dados conferido antes: evolucoes tem 0 linhas (0 com clinica_id nulo),
-- então dropar a policy de DELETE por paciente é seguro (a ALL por clinica_id cobre).

-- Helper de leitura mental: expr padrão da "clínica dona":
--   clinica_id IN (SELECT id FROM clinicas WHERE user_id = (select auth.uid()))

-- alertas
DROP POLICY IF EXISTS "alertas_da_clinica" ON public.alertas;
CREATE POLICY "alertas_da_clinica" ON public.alertas FOR ALL TO authenticated
  USING (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = (select auth.uid())));

-- assinaturas (SELECT)
DROP POLICY IF EXISTS "assinaturas_da_clinica" ON public.assinaturas;
CREATE POLICY "assinaturas_da_clinica" ON public.assinaturas FOR SELECT TO authenticated
  USING (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = (select auth.uid())));

-- clinicas: dona (ALL) + admin vê todas (SELECT)
DROP POLICY IF EXISTS "clinica_propria" ON public.clinicas;
CREATE POLICY "clinica_propria" ON public.clinicas FOR ALL TO authenticated
  USING ((select auth.uid()) = user_id);
DROP POLICY IF EXISTS "admin_ve_todas_clinicas" ON public.clinicas;
CREATE POLICY "admin_ve_todas_clinicas" ON public.clinicas FOR SELECT TO authenticated
  USING (((select auth.uid()) IN (SELECT user_id FROM public.nastaclin_admins))
         OR ((select auth.uid()) = user_id));

-- configuracoes
DROP POLICY IF EXISTS "configuracoes_da_clinica" ON public.configuracoes;
CREATE POLICY "configuracoes_da_clinica" ON public.configuracoes FOR ALL TO authenticated
  USING (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = (select auth.uid())));

-- consultas (+ remove DELETE redundante)
DROP POLICY IF EXISTS "consultas_da_clinica" ON public.consultas;
CREATE POLICY "consultas_da_clinica" ON public.consultas FOR ALL TO authenticated
  USING (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = (select auth.uid())));
DROP POLICY IF EXISTS "Clinica pode deletar suas consultas" ON public.consultas;

-- conversas
DROP POLICY IF EXISTS "conversas_da_clinica" ON public.conversas;
CREATE POLICY "conversas_da_clinica" ON public.conversas FOR ALL TO authenticated
  USING (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = (select auth.uid())));

-- evolucoes (+ remove DELETE redundante por paciente)
DROP POLICY IF EXISTS "evolucoes_da_clinica" ON public.evolucoes;
CREATE POLICY "evolucoes_da_clinica" ON public.evolucoes FOR ALL TO authenticated
  USING (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = (select auth.uid())));
DROP POLICY IF EXISTS "Clinica pode deletar suas evolucoes" ON public.evolucoes;

-- ia_uso (SELECT)
DROP POLICY IF EXISTS "ia_uso_da_clinica" ON public.ia_uso;
CREATE POLICY "ia_uso_da_clinica" ON public.ia_uso FOR SELECT TO authenticated
  USING (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = (select auth.uid())));

-- lembretes
DROP POLICY IF EXISTS "lembretes_da_clinica" ON public.lembretes;
CREATE POLICY "lembretes_da_clinica" ON public.lembretes FOR ALL TO authenticated
  USING (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = (select auth.uid())));

-- mensagens
DROP POLICY IF EXISTS "mensagens_da_clinica" ON public.mensagens;
CREATE POLICY "mensagens_da_clinica" ON public.mensagens FOR ALL TO authenticated
  USING (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = (select auth.uid())));

-- mensalidades (tem WITH CHECK)
DROP POLICY IF EXISTS "mensalidades_da_clinica" ON public.mensalidades;
CREATE POLICY "mensalidades_da_clinica" ON public.mensalidades FOR ALL TO authenticated
  USING (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = (select auth.uid())))
  WITH CHECK (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = (select auth.uid())));

-- modalidades (tem WITH CHECK)
DROP POLICY IF EXISTS "modalidades_da_clinica" ON public.modalidades;
CREATE POLICY "modalidades_da_clinica" ON public.modalidades FOR ALL TO authenticated
  USING (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = (select auth.uid())))
  WITH CHECK (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = (select auth.uid())));

-- nastaclin_admins (próprio)
DROP POLICY IF EXISTS "admin_proprio" ON public.nastaclin_admins;
CREATE POLICY "admin_proprio" ON public.nastaclin_admins FOR ALL TO authenticated
  USING ((select auth.uid()) = user_id);

-- pacientes (+ remove DELETE redundante)
DROP POLICY IF EXISTS "pacientes_da_clinica" ON public.pacientes;
CREATE POLICY "pacientes_da_clinica" ON public.pacientes FOR ALL TO authenticated
  USING (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = (select auth.uid())));
DROP POLICY IF EXISTS "Clinica pode deletar seus pacientes" ON public.pacientes;

-- pacotes
DROP POLICY IF EXISTS "pacotes_da_clinica" ON public.pacotes;
CREATE POLICY "pacotes_da_clinica" ON public.pacotes FOR ALL TO authenticated
  USING (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = (select auth.uid())));

-- salas (tem WITH CHECK)
DROP POLICY IF EXISTS "salas_da_clinica" ON public.salas;
CREATE POLICY "salas_da_clinica" ON public.salas FOR ALL TO authenticated
  USING (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = (select auth.uid())))
  WITH CHECK (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = (select auth.uid())));

-- whatsapp_conexoes
DROP POLICY IF EXISTS "whatsapp_conexoes_da_clinica" ON public.whatsapp_conexoes;
CREATE POLICY "whatsapp_conexoes_da_clinica" ON public.whatsapp_conexoes FOR ALL TO authenticated
  USING (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = (select auth.uid())));
