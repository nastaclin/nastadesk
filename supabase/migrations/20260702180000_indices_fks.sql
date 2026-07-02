-- ===== Fase 0 · Índices em FKs sem índice (performance) =====
-- STATUS: ✅ APLICADA em produção (2026-07-02).
--
-- Origem: advisor de performance do Supabase (unindexed_foreign_keys). São FKs
-- sem índice de apoio — o índice acelera joins/filtros e as remoções em cascata.
-- 100% aditivo e idempotente: não altera dados nem comportamento, só cria índices.
-- (Um índice pode ser removido a qualquer momento sem perda de dado.)

CREATE INDEX IF NOT EXISTS idx_consultas_paciente ON public.consultas (paciente_id);
CREATE INDEX IF NOT EXISTS idx_consultas_pacote   ON public.consultas (pacote_id);
CREATE INDEX IF NOT EXISTS idx_conversas_paciente ON public.conversas (paciente_id);
CREATE INDEX IF NOT EXISTS idx_evolucoes_clinica  ON public.evolucoes (clinica_id);
CREATE INDEX IF NOT EXISTS idx_evolucoes_consulta ON public.evolucoes (consulta_id);
CREATE INDEX IF NOT EXISTS idx_ia_uso_conversa    ON public.ia_uso (conversa_id);
CREATE INDEX IF NOT EXISTS idx_lembretes_clinica  ON public.lembretes (clinica_id);
CREATE INDEX IF NOT EXISTS idx_notas_fiscais_paciente ON public.notas_fiscais (paciente_id);
