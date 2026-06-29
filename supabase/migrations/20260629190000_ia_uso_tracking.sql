-- ===== RASTREIO DE USO DA IA (CLAUDE / ANTHROPIC) POR CLÍNICA =====
--
-- Registra o consumo de tokens de cada chamada ao Claude feita pelo chatbot
-- do WhatsApp, por clínica. Isso permite que o painel admin mostre o custo
-- REAL da API por cliente, em vez de uma estimativa fixa por clínica ativa.
--
-- Tabela puramente ADITIVA: não altera nenhuma tabela existente. Se ainda não
-- estiver criada, o webhook simplesmente ignora a gravação (try/catch) e o bot
-- segue respondendo normalmente.

CREATE TABLE IF NOT EXISTS public.ia_uso (
  id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  clinica_id uuid NOT NULL REFERENCES public.clinicas(id) ON DELETE CASCADE,
  conversa_id uuid REFERENCES public.conversas(id) ON DELETE SET NULL,
  modelo text NOT NULL DEFAULT 'claude-haiku-4-5',
  input_tokens integer NOT NULL DEFAULT 0,
  output_tokens integer NOT NULL DEFAULT 0,
  cache_creation_input_tokens integer NOT NULL DEFAULT 0,
  cache_read_input_tokens integer NOT NULL DEFAULT 0,
  criado_em timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.ia_uso ENABLE ROW LEVEL SECURITY;

-- A clínica pode ler o próprio uso (consistente com as demais tabelas).
-- A escrita é feita pela Edge Function com service_role, que ignora RLS.
DROP POLICY IF EXISTS ia_uso_da_clinica ON public.ia_uso;
CREATE POLICY ia_uso_da_clinica ON public.ia_uso
  FOR SELECT USING (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = auth.uid()));

CREATE INDEX IF NOT EXISTS ia_uso_clinica_data_idx ON public.ia_uso (clinica_id, criado_em DESC);
CREATE INDEX IF NOT EXISTS ia_uso_data_idx ON public.ia_uso (criado_em DESC);
