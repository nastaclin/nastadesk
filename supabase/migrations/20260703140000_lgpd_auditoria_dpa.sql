-- ============================================================
-- FASE 1 · LGPD (parte 2) — Trilha de auditoria + aceite de DPA
-- 100% ADITIVO. Nada existente é removido de forma destrutiva.
--   (1) Tabela `auditoria` (quem/quando/o quê no acesso e edição de fichas
--       de paciente) + RLS (dono da clínica lê os próprios registros;
--       escrita só via função DEFINER — impede adulteração pelo navegador).
--   (2) registrar_auditoria(): grava o evento com escopo por auth.uid().
--       Tolerante: se não houver clínica/paciente válido, apenas não registra
--       (nunca lança erro que atrapalhe a navegação).
--   (3) Estende o CHECK de `consentimentos.contexto` p/ aceitar 'dpa' e cria
--       registrar_aceite_dpa(): registra o aceite do Acordo de Tratamento de
--       Dados (DPA / contrato de operador) pela clínica (controladora).
-- RLS no formato performático: (select auth.uid()) + TO authenticated.
-- ============================================================

-- ===== 1. TRILHA DE AUDITORIA =====
create table if not exists public.auditoria (
  id uuid primary key default extensions.uuid_generate_v4(),
  clinica_id uuid references public.clinicas(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  paciente_id uuid references public.pacientes(id) on delete set null, -- sobrevive à exclusão do paciente
  acao text not null,          -- ex.: 'visualizou_ficha', 'editou_ficha', 'registrou_evolucao', 'exportou_dados'
  detalhe text,                -- descrição curta e opcional (sem dado sensível)
  user_agent text,
  criado_em timestamptz not null default now()
);

alter table public.auditoria enable row level security;

-- O dono da clínica enxerga os registros da própria clínica / da própria conta.
-- Escrita NÃO tem policy → só a função SECURITY DEFINER e o service_role inserem.
drop policy if exists auditoria_select_dono on public.auditoria;
create policy auditoria_select_dono on public.auditoria for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or clinica_id in (select id from public.clinicas where user_id = (select auth.uid()))
  );

create index if not exists auditoria_clinica_idx on public.auditoria (clinica_id, criado_em desc);
create index if not exists auditoria_paciente_idx on public.auditoria (paciente_id, criado_em desc);

-- ===== 2. registrar_auditoria() =====
create or replace function public.registrar_auditoria(
  p_paciente_id uuid,
  p_acao text,
  p_detalhe text DEFAULT NULL,
  p_user_agent text DEFAULT NULL
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_clinica_id uuid;
begin
  -- Resolve a clínica do usuário logado (a partir do auth.uid()).
  select id into v_clinica_id
  from public.clinicas
  where user_id = (select auth.uid())
  limit 1;

  if v_clinica_id is null then
    return; -- sem clínica → não registra (tolerante)
  end if;

  -- Se veio paciente, confirma que é da própria clínica (defesa contra id forjado).
  if p_paciente_id is not null then
    if not exists (
      select 1 from public.pacientes
      where id = p_paciente_id and clinica_id = v_clinica_id
    ) then
      return;
    end if;
  end if;

  insert into public.auditoria (clinica_id, user_id, paciente_id, acao, detalhe, user_agent)
  values (
    v_clinica_id,
    (select auth.uid()),
    p_paciente_id,
    left(coalesce(nullif(trim(p_acao), ''), 'acao'), 60),
    left(p_detalhe, 300),
    left(p_user_agent, 300)
  );
end;
$$;

revoke execute on function public.registrar_auditoria(uuid, text, text, text) from public, anon;
grant execute on function public.registrar_auditoria(uuid, text, text, text) to authenticated;

-- ===== 3. ACEITE DO DPA (contrato de operador) =====
-- Estende o CHECK de contexto (aditivo — os valores antigos continuam válidos).
alter table public.consentimentos drop constraint if exists consentimentos_contexto_check;
alter table public.consentimentos add constraint consentimentos_contexto_check
  check (contexto in ('cadastro_clinica','agendamento_online','portal_titular','dpa'));

-- registrar_aceite_dpa(): grava o aceite do DPA pela clínica (controladora).
-- A tabela consentimentos não tem policy de INSERT → só esta função DEFINER e o
-- service_role conseguem inserir (o dono lê o próprio pela policy de SELECT).
create or replace function public.registrar_aceite_dpa(p_versao text DEFAULT NULL)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_clinica_id uuid;
  v_responsavel text;
  v_email text;
begin
  select c.id, c.responsavel into v_clinica_id, v_responsavel
  from public.clinicas c
  where c.user_id = (select auth.uid())
  limit 1;

  if v_clinica_id is null then
    return json_build_object('ok', false, 'erro', 'Clínica não encontrada.');
  end if;

  select email into v_email from auth.users where id = (select auth.uid());

  insert into public.consentimentos (contexto, clinica_id, user_id, documentos, versao, identificador, nome)
  values ('dpa', v_clinica_id, (select auth.uid()), array['dpa','operador'],
          coalesce(nullif(trim(p_versao), ''), '1.0'), v_email, v_responsavel);

  return json_build_object('ok', true);
end;
$$;

revoke execute on function public.registrar_aceite_dpa(text) from public, anon;
grant execute on function public.registrar_aceite_dpa(text) to authenticated;
