-- ===== PACOTES DE SESSÕES =====
CREATE TABLE IF NOT EXISTS public.pacotes (
  id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  clinica_id uuid NOT NULL REFERENCES public.clinicas(id) ON DELETE CASCADE,
  paciente_id uuid NOT NULL REFERENCES public.pacientes(id) ON DELETE CASCADE,
  nome text NOT NULL,
  total_sessoes integer NOT NULL CHECK (total_sessoes > 0),
  sessoes_usadas integer NOT NULL DEFAULT 0,
  valor_total numeric(10,2),
  valor_pago numeric(10,2) DEFAULT 0,
  pagamento_status text NOT NULL DEFAULT 'pendente' CHECK (pagamento_status = ANY (ARRAY['pendente','pago'])),
  forma_pagamento text CHECK (forma_pagamento IS NULL OR forma_pagamento = ANY (ARRAY['dinheiro','pix','cartao_credito','cartao_debito','convenio','transferencia'])),
  pago_em timestamptz,
  validade date,
  status text NOT NULL DEFAULT 'ativo' CHECK (status = ANY (ARRAY['ativo','concluido','cancelado'])),
  observacoes text,
  criado_em timestamptz DEFAULT now()
);

ALTER TABLE public.pacotes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pacotes_da_clinica ON public.pacotes;
CREATE POLICY pacotes_da_clinica ON public.pacotes FOR ALL
  USING (clinica_id IN (SELECT id FROM public.clinicas WHERE user_id = auth.uid()));

CREATE INDEX IF NOT EXISTS pacotes_clinica_status_idx ON public.pacotes (clinica_id, status);
CREATE INDEX IF NOT EXISTS pacotes_paciente_idx ON public.pacotes (paciente_id);

-- Vínculo consulta -> pacote (uma sessão consumida)
ALTER TABLE public.consultas ADD COLUMN IF NOT EXISTS pacote_id uuid REFERENCES public.pacotes(id) ON DELETE SET NULL;

-- pagamento_status 'pacote' (consulta coberta por um pacote)
ALTER TABLE public.consultas DROP CONSTRAINT IF EXISTS consultas_pagamento_status_check;
ALTER TABLE public.consultas ADD CONSTRAINT consultas_pagamento_status_check
  CHECK (pagamento_status IS NULL OR pagamento_status = ANY (ARRAY['pendente','pago','isento','pacote']));

-- alertas tipo 'pacote' (pacote acabando)
ALTER TABLE public.alertas DROP CONSTRAINT IF EXISTS alertas_tipo_check;
ALTER TABLE public.alertas ADD CONSTRAINT alertas_tipo_check
  CHECK (tipo = ANY (ARRAY['cancelamento','novo_agendamento','sem_resposta','lista_espera','retorno','whatsapp','pacote']));

-- Recalcula sessões usadas e status do pacote
CREATE OR REPLACE FUNCTION public.recalcular_pacote(p_pacote_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_total int; v_usadas int; v_status text;
BEGIN
  IF p_pacote_id IS NULL THEN RETURN; END IF;
  SELECT total_sessoes, status INTO v_total, v_status FROM public.pacotes WHERE id = p_pacote_id;
  IF NOT FOUND THEN RETURN; END IF;
  SELECT count(*) INTO v_usadas FROM public.consultas
    WHERE pacote_id = p_pacote_id AND status <> 'cancelado';
  UPDATE public.pacotes SET
    sessoes_usadas = v_usadas,
    status = CASE WHEN status = 'cancelado' THEN 'cancelado'
                  WHEN v_usadas >= v_total THEN 'concluido'
                  ELSE 'ativo' END
  WHERE id = p_pacote_id;
END $$;
REVOKE EXECUTE ON FUNCTION public.recalcular_pacote(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.trg_pacote_consulta()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF TG_OP IN ('INSERT','UPDATE') AND NEW.pacote_id IS NOT NULL THEN
    PERFORM public.recalcular_pacote(NEW.pacote_id);
  END IF;
  IF TG_OP IN ('UPDATE','DELETE') AND OLD.pacote_id IS NOT NULL
     AND (TG_OP = 'DELETE' OR OLD.pacote_id IS DISTINCT FROM NEW.pacote_id) THEN
    PERFORM public.recalcular_pacote(OLD.pacote_id);
  END IF;
  RETURN COALESCE(NEW, OLD);
END $$;
REVOKE EXECUTE ON FUNCTION public.trg_pacote_consulta() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS on_consulta_pacote ON public.consultas;
CREATE TRIGGER on_consulta_pacote AFTER INSERT OR UPDATE OR DELETE ON public.consultas
  FOR EACH ROW EXECUTE FUNCTION public.trg_pacote_consulta();

-- Realtime
DO $$
BEGIN
  BEGIN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.pacotes';
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;
