-- Endurecimento das funções de trigger existentes (alertas do advisor)
ALTER FUNCTION public.criar_clinica_no_signup() SET search_path = public, pg_temp;
ALTER FUNCTION public.criar_config_na_clinica() SET search_path = public, pg_temp;
-- Triggers não exigem EXECUTE em tempo de execução, então é seguro revogar
REVOKE EXECUTE ON FUNCTION public.criar_clinica_no_signup() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.criar_config_na_clinica() FROM PUBLIC, anon, authenticated;

-- Índices de performance para as consultas mais frequentes do app
CREATE INDEX IF NOT EXISTS consultas_clinica_data_idx ON public.consultas (clinica_id, data_hora);
CREATE INDEX IF NOT EXISTS pacientes_clinica_nome_idx ON public.pacientes (clinica_id, nome);
CREATE INDEX IF NOT EXISTS alertas_clinica_lido_idx ON public.alertas (clinica_id, lido, criado_em DESC);
CREATE INDEX IF NOT EXISTS evolucoes_paciente_idx ON public.evolucoes (paciente_id, criado_em DESC);
