-- ===== FINANCEIRO =====
ALTER TABLE public.consultas
  ADD COLUMN IF NOT EXISTS valor numeric(10,2),
  ADD COLUMN IF NOT EXISTS pagamento_status text DEFAULT 'pendente',
  ADD COLUMN IF NOT EXISTS forma_pagamento text,
  ADD COLUMN IF NOT EXISTS pago_em timestamptz;

ALTER TABLE public.consultas
  ADD CONSTRAINT consultas_pagamento_status_check
  CHECK (pagamento_status IS NULL OR pagamento_status = ANY (ARRAY['pendente','pago','isento']));

ALTER TABLE public.consultas
  ADD CONSTRAINT consultas_forma_pagamento_check
  CHECK (forma_pagamento IS NULL OR forma_pagamento = ANY (ARRAY['dinheiro','pix','cartao_credito','cartao_debito','convenio','transferencia']));

ALTER TABLE public.clinicas
  ADD COLUMN IF NOT EXISTS valor_consulta_padrao numeric(10,2),
  ADD COLUMN IF NOT EXISTS slug text,
  ADD COLUMN IF NOT EXISTS agendamento_online boolean DEFAULT true;

-- ===== AGENDAMENTO ONLINE: origem 'online' =====
ALTER TABLE public.consultas DROP CONSTRAINT IF EXISTS consultas_origem_check;
ALTER TABLE public.consultas
  ADD CONSTRAINT consultas_origem_check
  CHECK (origem = ANY (ARRAY['manual','whatsapp','instagram','online']));

-- Slug único (permite NULL enquanto não gerado)
CREATE UNIQUE INDEX IF NOT EXISTS clinicas_slug_key ON public.clinicas (slug) WHERE slug IS NOT NULL;

-- Gerar slug para clínicas existentes a partir do nome
DO $$
DECLARE
  r RECORD;
  base text;
  candidato text;
  n int;
BEGIN
  FOR r IN SELECT id, nome FROM public.clinicas WHERE slug IS NULL LOOP
    base := lower(translate(coalesce(r.nome, 'clinica'),
      'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇñÑ',
      'aaaaaeeeeiiiiooooouuuucaaaaaeeeeiiiiooooouuuucnn'));
    base := regexp_replace(base, '[^a-z0-9]+', '-', 'g');
    base := regexp_replace(base, '(^-+|-+$)', '', 'g');
    IF base = '' OR base IS NULL THEN base := 'clinica'; END IF;
    candidato := base;
    n := 1;
    WHILE EXISTS (SELECT 1 FROM public.clinicas WHERE slug = candidato AND id <> r.id) LOOP
      n := n + 1;
      candidato := base || '-' || n;
    END LOOP;
    UPDATE public.clinicas SET slug = candidato WHERE id = r.id;
  END LOOP;
END $$;

-- ===== LEMBRETES: evitar duplicidade por consulta/tipo =====
CREATE UNIQUE INDEX IF NOT EXISTS lembretes_consulta_tipo_key ON public.lembretes (consulta_id, tipo);

-- ===== CONTADORES DO PACIENTE (total_consultas / ultima_consulta) =====
CREATE OR REPLACE FUNCTION public.recalcular_stats_paciente(p_paciente_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE public.pacientes p SET
    total_consultas = (
      SELECT count(*) FROM public.consultas c
      WHERE c.paciente_id = p_paciente_id AND c.status <> 'cancelado'
    ),
    ultima_consulta = (
      SELECT max(c.data_hora AT TIME ZONE 'America/Sao_Paulo')::date
      FROM public.consultas c
      WHERE c.paciente_id = p_paciente_id AND c.status = 'atendido'
    )
  WHERE p.id = p_paciente_id;
$$;

REVOKE EXECUTE ON FUNCTION public.recalcular_stats_paciente(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.trg_stats_paciente()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP IN ('INSERT','UPDATE') AND NEW.paciente_id IS NOT NULL THEN
    PERFORM public.recalcular_stats_paciente(NEW.paciente_id);
  END IF;
  IF TG_OP IN ('DELETE','UPDATE') AND OLD.paciente_id IS NOT NULL
     AND (TG_OP = 'DELETE' OR OLD.paciente_id IS DISTINCT FROM NEW.paciente_id) THEN
    PERFORM public.recalcular_stats_paciente(OLD.paciente_id);
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.trg_stats_paciente() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS on_consulta_stats ON public.consultas;
CREATE TRIGGER on_consulta_stats
  AFTER INSERT OR UPDATE OR DELETE ON public.consultas
  FOR EACH ROW EXECUTE FUNCTION public.trg_stats_paciente();

-- Backfill dos contadores para os pacientes existentes
UPDATE public.pacientes p SET
  total_consultas = coalesce(s.total, 0),
  ultima_consulta = s.ultima
FROM (
  SELECT pc.id AS pid,
    (SELECT count(*) FROM public.consultas c WHERE c.paciente_id = pc.id AND c.status <> 'cancelado') AS total,
    (SELECT max(c.data_hora AT TIME ZONE 'America/Sao_Paulo')::date FROM public.consultas c WHERE c.paciente_id = pc.id AND c.status = 'atendido') AS ultima
  FROM public.pacientes pc
) s
WHERE p.id = s.pid;
