-- Gera slug único a partir de um nome
CREATE OR REPLACE FUNCTION public.gerar_slug_unico(p_nome text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  base text;
  candidato text;
  n int := 1;
BEGIN
  base := lower(translate(coalesce(p_nome, 'clinica'),
    'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇñÑ',
    'aaaaaeeeeiiiiooooouuuucaaaaaeeeeiiiiooooouuuucnn'));
  base := regexp_replace(base, '[^a-z0-9]+', '-', 'g');
  base := regexp_replace(base, '(^-+|-+$)', '', 'g');
  IF base = '' OR base IS NULL THEN base := 'clinica'; END IF;
  candidato := base;
  WHILE EXISTS (SELECT 1 FROM public.clinicas WHERE slug = candidato) LOOP
    n := n + 1;
    candidato := base || '-' || n;
  END LOOP;
  RETURN candidato;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.gerar_slug_unico(text) FROM PUBLIC, anon, authenticated;

-- Atualiza o trigger de signup para já criar a clínica com slug
CREATE OR REPLACE FUNCTION public.criar_clinica_no_signup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.clinicas (user_id, nome, responsavel, whatsapp, plano, slug)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'nome_clinica', 'Minha Clínica'),
    COALESCE(NEW.raw_user_meta_data->>'responsavel', 'Responsável'),
    COALESCE(NEW.raw_user_meta_data->>'whatsapp', ''),
    'basico',
    public.gerar_slug_unico(COALESCE(NEW.raw_user_meta_data->>'nome_clinica', 'clinica'))
  );
  RETURN NEW;
END;
$$;
