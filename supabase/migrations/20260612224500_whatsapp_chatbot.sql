-- ===== WHATSAPP MULTI-TENANT + CHATBOT =====

-- 1) Conexão WhatsApp por clínica (Evolution API, 1 instância por clínica)
CREATE TABLE IF NOT EXISTS public.whatsapp_conexoes (
  id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  clinica_id uuid NOT NULL UNIQUE REFERENCES public.clinicas(id) ON DELETE CASCADE,
  instancia text NOT NULL UNIQUE,
  webhook_token uuid NOT NULL DEFAULT extensions.uuid_generate_v4(),
  status text NOT NULL DEFAULT 'desconectado' CHECK (status IN ('desconectado','conectando','conectado')),
  numero text,
  atualizado_em timestamptz DEFAULT now(),
  criado_em timestamptz DEFAULT now()
);

ALTER TABLE public.whatsapp_conexoes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS whatsapp_conexoes_da_clinica ON public.whatsapp_conexoes;
CREATE POLICY whatsapp_conexoes_da_clinica ON public.whatsapp_conexoes
  FOR ALL USING (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = auth.uid()));

-- 2) Conversas (1 por contato por clínica)
CREATE TABLE IF NOT EXISTS public.conversas (
  id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  clinica_id uuid NOT NULL REFERENCES public.clinicas(id) ON DELETE CASCADE,
  telefone text NOT NULL,
  nome_contato text,
  paciente_id uuid REFERENCES public.pacientes(id) ON DELETE SET NULL,
  tipo text NOT NULL DEFAULT 'lead' CHECK (tipo IN ('lead','paciente')),
  interesse text,
  bot_ativo boolean NOT NULL DEFAULT true,
  bot_pausado_ate timestamptz,
  estado jsonb NOT NULL DEFAULT '{}'::jsonb,
  nao_lidas integer NOT NULL DEFAULT 0,
  ultima_msg text,
  ultima_msg_em timestamptz DEFAULT now(),
  criado_em timestamptz DEFAULT now(),
  UNIQUE (clinica_id, telefone)
);

ALTER TABLE public.conversas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS conversas_da_clinica ON public.conversas;
CREATE POLICY conversas_da_clinica ON public.conversas
  FOR ALL USING (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = auth.uid()));

CREATE INDEX IF NOT EXISTS conversas_clinica_ultima_idx ON public.conversas (clinica_id, ultima_msg_em DESC);

-- 3) Mensagens
CREATE TABLE IF NOT EXISTS public.mensagens (
  id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  conversa_id uuid NOT NULL REFERENCES public.conversas(id) ON DELETE CASCADE,
  clinica_id uuid NOT NULL REFERENCES public.clinicas(id) ON DELETE CASCADE,
  direcao text NOT NULL CHECK (direcao IN ('entrada','saida')),
  autor text NOT NULL CHECK (autor IN ('contato','bot','atendente')),
  conteudo text NOT NULL,
  msg_externa_id text,
  criado_em timestamptz DEFAULT now()
);

ALTER TABLE public.mensagens ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS mensagens_da_clinica ON public.mensagens;
CREATE POLICY mensagens_da_clinica ON public.mensagens
  FOR ALL USING (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = auth.uid()));

CREATE INDEX IF NOT EXISTS mensagens_conversa_idx ON public.mensagens (conversa_id, criado_em);
CREATE INDEX IF NOT EXISTS mensagens_externa_idx ON public.mensagens (clinica_id, msg_externa_id) WHERE msg_externa_id IS NOT NULL;

-- 4) Configurações do chatbot por clínica
ALTER TABLE public.configuracoes
  ADD COLUMN IF NOT EXISTS bot_ativo boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS bot_boasvindas text DEFAULT 'Olá! 👋 Bem-vindo(a) à {clinica}. Sou o assistente virtual e posso agendar sua consulta, tirar dúvidas e muito mais.',
  ADD COLUMN IF NOT EXISTS bot_faq text,
  ADD COLUMN IF NOT EXISTS lembrete_auto boolean DEFAULT true;

-- 5) Alertas: novo tipo 'whatsapp' (leads, pedidos de atendente)
ALTER TABLE public.alertas DROP CONSTRAINT IF EXISTS alertas_tipo_check;
ALTER TABLE public.alertas ADD CONSTRAINT alertas_tipo_check
  CHECK (tipo = ANY (ARRAY['cancelamento','novo_agendamento','sem_resposta','lista_espera','retorno','whatsapp']));

-- 6) Realtime para o inbox (e tabelas que o painel já assina)
DO $$
DECLARE t text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
  FOREACH t IN ARRAY ARRAY['consultas','alertas','conversas','mensagens','whatsapp_conexoes'] LOOP
    BEGIN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
  END LOOP;
END $$;

-- 7) Lembretes automáticos: cron a cada 10 minutos chama a edge function
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

DO $$
BEGIN
  PERFORM cron.unschedule('nastadesk-lembretes-auto');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'nastadesk-lembretes-auto',
  '*/10 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://zrkadblxozddreiwruhv.supabase.co/functions/v1/lembretes-auto',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inpya2FkYmx4b3pkZHJlaXdydWh2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA5NjA4MjEsImV4cCI6MjA5NjUzNjgyMX0.BQkXr831MlctUk-FhfEYkrgs6Amdpho5yDWcR3BtXok'
    ),
    body := '{}'::jsonb
  );
  $$
);
