-- ============================================================
-- PORTAL DO PROFISSIONAL — RLS por papel (pedido do dono, 2026-07-04)
--
-- PROBLEMA: as políticas de membro (20260704140000) davam ao papel
-- 'profissional' o MESMO acesso de dados do dono/recepção: ALL nas 15
-- tabelas operacionais — inclusive ver TODOS os pacientes da clínica e
-- poder EXCLUIR pacientes/consultas. O front só escondia telas, o que
-- não protege nada (a API aceitava tudo).
--
-- O QUE MUDA (nada muda para o DONO; RECEPÇÃO mantém o acesso atual):
--   papel 'recepcao'     → igual antes: ALL nas 15 tabelas operacionais
--                          (as policies *_membros passam a valer SÓ p/ recepção).
--   papel 'profissional' → acesso mínimo, só o que ele atende:
--       consultas   : SELECT + UPDATE apenas das consultas DELE
--                     (profissional_id = vínculo do login). Sem INSERT/DELETE.
--       pacientes   : SELECT apenas de pacientes com consulta COM ELE.
--                     Sem UPDATE/DELETE/INSERT (ficha é só-leitura).
--       evolucoes   : SELECT + INSERT dos pacientes dele (continuidade
--                     clínica). Sem UPDATE/DELETE.
--       modalidades / profissionais / salas : SELECT (etiquetas da agenda).
--       clinicas    : SELECT (já existia — clinicas_membro_ve).
--       TODO O RESTO (mensalidades, pacotes, lembretes, conversas,
--       mensagens, alertas, configuracoes, despesas, whatsapp_conexoes):
--       NENHUM acesso.
--
-- Profissional sem vínculo (clinica_membros.profissional_id nulo) não vê
-- consulta/paciente nenhum (meu_profissional_id() devolve NULL → nada casa).
--
-- 100% reversível: só policies e funções; nenhum dado é tocado.
-- RLS no formato performático: (select ...) + TO authenticated.
-- ============================================================

-- ===== 1. Funções auxiliares (SECURITY DEFINER p/ não recursar no RLS) =====

-- Profissional vinculado ao login atual (NULL se o login não é papel profissional).
create or replace function public.meu_profissional_id()
returns uuid language sql stable security definer set search_path = public as $$
  select profissional_id from public.clinica_membros
  where user_id = (select auth.uid()) and ativo and papel = 'profissional'
  limit 1
$$;
revoke all on function public.meu_profissional_id() from public;
grant execute on function public.meu_profissional_id() to authenticated;

-- Clínicas onde o usuário é RECEPÇÃO ativa (escopo das policies *_membros).
create or replace function public.clinica_ids_recepcao()
returns setof uuid language sql stable security definer set search_path = public as $$
  select clinica_id from public.clinica_membros
  where user_id = (select auth.uid()) and ativo and papel = 'recepcao'
$$;
revoke all on function public.clinica_ids_recepcao() from public;
grant execute on function public.clinica_ids_recepcao() to authenticated;

-- Pacientes que o profissional logado atende (têm >=1 consulta com ele).
create or replace function public.pacientes_do_profissional()
returns setof uuid language sql stable security definer set search_path = public as $$
  select distinct c.paciente_id
  from public.consultas c
  join public.clinica_membros m
    on m.user_id = (select auth.uid()) and m.ativo
   and m.papel = 'profissional' and m.profissional_id is not null
  where c.profissional_id = m.profissional_id
    and c.paciente_id is not null
$$;
revoke all on function public.pacientes_do_profissional() from public;
grant execute on function public.pacientes_do_profissional() to authenticated;

-- ===== 2. Policies *_membros passam a valer SÓ para a RECEPÇÃO =====
-- (o dono continua nas policies antigas dele; o profissional entra nas
--  policies novas e restritas da seção 3)
do $$
declare t text;
begin
  foreach t in array array[
    'pacientes','consultas','evolucoes','modalidades','profissionais','salas',
    'mensalidades','pacotes','lembretes','conversas','mensagens','alertas',
    'configuracoes','despesas','whatsapp_conexoes'
  ] loop
    execute format('drop policy if exists %I on public.%I', t||'_membros', t);
    execute format(
      'create policy %I on public.%I for all to authenticated using (clinica_id in (select public.clinica_ids_recepcao())) with check (clinica_id in (select public.clinica_ids_recepcao()))',
      t||'_membros', t);
  end loop;
end $$;

-- ===== 3. Policies do papel PROFISSIONAL (mínimas) =====

-- Consultas: vê e atualiza SÓ as dele. O WITH CHECK impede reatribuir a
-- consulta para outro profissional / outra clínica. Sem INSERT nem DELETE.
drop policy if exists consultas_prof_sel on public.consultas;
create policy consultas_prof_sel on public.consultas for select
  to authenticated
  using (profissional_id is not null
         and profissional_id = (select public.meu_profissional_id()));

drop policy if exists consultas_prof_upd on public.consultas;
create policy consultas_prof_upd on public.consultas for update
  to authenticated
  using (profissional_id is not null
         and profissional_id = (select public.meu_profissional_id()))
  with check (profissional_id is not null
              and profissional_id = (select public.meu_profissional_id()));

-- Pacientes: SÓ leitura, SÓ de quem ele atende. (Ficha é read-only no portal;
-- alterações cadastrais continuam com dono/recepção.)
drop policy if exists pacientes_prof_sel on public.pacientes;
create policy pacientes_prof_sel on public.pacientes for select
  to authenticated
  using (id in (select public.pacientes_do_profissional()));

-- Evoluções: lê as dos pacientes dele (mesmo escritas por outros — continuidade
-- clínica) e registra novas. Sem editar/apagar histórico.
drop policy if exists evolucoes_prof_sel on public.evolucoes;
create policy evolucoes_prof_sel on public.evolucoes for select
  to authenticated
  using (paciente_id in (select public.pacientes_do_profissional()));

drop policy if exists evolucoes_prof_ins on public.evolucoes;
create policy evolucoes_prof_ins on public.evolucoes for insert
  to authenticated
  with check (
    paciente_id in (select public.pacientes_do_profissional())
    and clinica_id in (select public.clinica_ids_membro())
  );

-- Referências read-only para renderizar a agenda do portal (nomes/cores).
do $$
declare t text;
begin
  foreach t in array array['modalidades','profissionais','salas'] loop
    execute format('drop policy if exists %I on public.%I', t||'_prof_sel', t);
    execute format(
      'create policy %I on public.%I for select to authenticated using (clinica_id in (select public.clinica_ids_membro()))',
      t||'_prof_sel', t);
  end loop;
end $$;

-- ===== 4. Trilha de auditoria passa a registrar FUNCIONÁRIOS também =====
-- Antes a RPC só resolvia a clínica pelo DONO (funcionário não registrava).
-- Agora resolve dono OU membro ativo — o "quem" da trilha finalmente aponta
-- para a pessoa certa. Mesma assinatura; mesma tolerância a falha.
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
  -- Dono?
  select id into v_clinica_id
  from public.clinicas
  where user_id = (select auth.uid())
  limit 1;

  -- Funcionário (recepção/profissional)?
  if v_clinica_id is null then
    select clinica_id into v_clinica_id
    from public.clinica_membros
    where user_id = (select auth.uid()) and ativo
    limit 1;
  end if;

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
