-- ============================================================
-- FIX: signup NÃO cria clínica para FUNCIONÁRIO (login de equipe)
-- Sem isto, o gatilho on_auth_user_created criava uma clínica vazia para
-- o funcionário (via equipe-criar), que então virava "dono" dela e caía
-- no onboarding. A edge equipe-criar marca user_metadata.tipo='membro';
-- o gatilho passa a pular a criação nesse caso. Cadastro comum (dono) fica
-- IDÊNTICO. APLICADA EM PRODUÇÃO em 2026-07-04 (+ limpeza das clínicas
-- órfãs vazias já criadas para funcionários de teste).
-- ============================================================
create or replace function public.criar_clinica_no_signup()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_clinica_id uuid;
  v_consent_versao text;
begin
  -- Funcionário criado via equipe-criar: não cria clínica nenhuma.
  if coalesce(new.raw_user_meta_data->>'tipo','') = 'membro' then
    return new;
  end if;

  insert into public.clinicas (user_id, nome, responsavel, whatsapp, plano, slug)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nome_clinica', 'Minha Clínica'),
    coalesce(new.raw_user_meta_data->>'responsavel', 'Responsável'),
    coalesce(new.raw_user_meta_data->>'whatsapp', ''),
    'basico',
    public.gerar_slug_unico(coalesce(new.raw_user_meta_data->>'nome_clinica', 'clinica'))
  )
  returning id into v_clinica_id;

  v_consent_versao := nullif(trim(coalesce(new.raw_user_meta_data->>'lgpd_consent_versao', '')), '');
  if v_consent_versao is not null then
    insert into public.consentimentos (contexto, clinica_id, user_id, documentos, versao, identificador, nome)
    values ('cadastro_clinica', v_clinica_id, new.id, array['termos','privacidade'],
            v_consent_versao, new.email, new.raw_user_meta_data->>'responsavel');
  end if;

  return new;
end;
$function$;
