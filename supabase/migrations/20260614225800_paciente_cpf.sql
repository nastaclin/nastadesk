-- ===== CPF / IDENTIFICAÇÃO DE PACIENTES =====
ALTER TABLE public.pacientes ADD COLUMN IF NOT EXISTS cpf text;

-- CPF único por clínica (quando preenchido) — evita pacientes duplicados
CREATE UNIQUE INDEX IF NOT EXISTS pacientes_clinica_cpf_key
  ON public.pacientes (clinica_id, cpf)
  WHERE cpf IS NOT NULL AND cpf <> '';

-- Índice de busca por nome (já existe pacientes_clinica_nome_idx) + cpf
CREATE INDEX IF NOT EXISTS pacientes_clinica_cpf_idx ON public.pacientes (clinica_id, cpf);
