-- ============================================================
-- FASE 3 — Diferenciação (2026-07-05)
--
-- 1. avaliacoes      → prontuário estruturado de fisio (EVA, goniometria,
--                      avaliação postural, testes funcionais) em JSONB.
-- 2. lista_espera    → fila de espera de pacientes por clínica.
-- 3. consultas.teleconsulta → flag de atendimento por vídeo (link Jitsi
--                      derivado do id da consulta, gerado no front).
-- 4. bucket 'exames' → anexos de exames do paciente no Storage (privado,
--                      10MB, pdf/imagem), caminho <clinica_id>/<paciente_id>/…
-- 5. LGPD            → paciente_anonimizar/paciente_excluir passam a limpar
--                      também avaliações e lista de espera (os ARQUIVOS de
--                      exames são apagados pelo front via Storage API — o
--                      Storage bloqueia delete direto via SQL).
--
-- 100% aditivo e reversível: nenhuma tabela existente muda (só 1 coluna
-- nova em consultas com default false). RLS no formato performático
-- ((select …) + TO authenticated), espelhando evolucoes:
--   dono → ALL · recepção → ALL · profissional → SELECT/INSERT só dos
--   pacientes dele · sem vínculo → nada · anon → nada.
-- ============================================================

-- ===== 1. AVALIAÇÕES (prontuário estruturado) =====

create table if not exists public.avaliacoes (
  id uuid primary key default gen_random_uuid(),
  clinica_id uuid not null references public.clinicas(id) on delete cascade,
  paciente_id uuid not null references public.pacientes(id) on delete cascade,
  profissional_id uuid references public.profissionais(id) on delete set null,
  tipo text not null check (tipo in ('eva','goniometria','postural','funcional')),
  dados jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now()
);

create index if not exists idx_avaliacoes_clinica on public.avaliacoes(clinica_id);
create index if not exists idx_avaliacoes_paciente on public.avaliacoes(paciente_id, criado_em desc);
create index if not exists idx_avaliacoes_profissional on public.avaliacoes(profissional_id);

alter table public.avaliacoes enable row level security;

-- Dono: tudo, escopo da própria clínica (mesmo formato das demais tabelas).
drop policy if exists avaliacoes_da_clinica on public.avaliacoes;
create policy avaliacoes_da_clinica on public.avaliacoes for all to authenticated
  using (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())))
  with check (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())));

-- Recepção: tudo, nas clínicas onde é recepção ativa.
drop policy if exists avaliacoes_membros on public.avaliacoes;
create policy avaliacoes_membros on public.avaliacoes for all to authenticated
  using (clinica_id in (select public.clinica_ids_recepcao()))
  with check (clinica_id in (select public.clinica_ids_recepcao()));

-- Profissional: lê e registra SÓ dos pacientes dele (igual evoluções).
-- Sem UPDATE/DELETE — histórico clínico não se apaga pelo portal.
drop policy if exists avaliacoes_prof_sel on public.avaliacoes;
create policy avaliacoes_prof_sel on public.avaliacoes for select to authenticated
  using (paciente_id in (select public.pacientes_do_profissional()));

drop policy if exists avaliacoes_prof_ins on public.avaliacoes;
create policy avaliacoes_prof_ins on public.avaliacoes for insert to authenticated
  with check (paciente_id in (select public.pacientes_do_profissional())
              and clinica_id in (select public.clinica_ids_membro()));

-- ===== 2. LISTA DE ESPERA =====

create table if not exists public.lista_espera (
  id uuid primary key default gen_random_uuid(),
  clinica_id uuid not null references public.clinicas(id) on delete cascade,
  paciente_id uuid references public.pacientes(id) on delete cascade,
  nome text,
  whatsapp text,
  modalidade_id uuid references public.modalidades(id) on delete set null,
  profissional_id uuid references public.profissionais(id) on delete set null,
  preferencia text,
  observacao text,
  status text not null default 'aguardando' check (status in ('aguardando','agendado','removido')),
  criado_em timestamptz not null default now(),
  -- precisa apontar um paciente OU ter um nome digitado
  constraint lista_espera_identificacao
    check (paciente_id is not null or nullif(trim(coalesce(nome,'')),'') is not null)
);

create index if not exists idx_lista_espera_clinica on public.lista_espera(clinica_id, status);
create index if not exists idx_lista_espera_paciente on public.lista_espera(paciente_id);
create index if not exists idx_lista_espera_modalidade on public.lista_espera(modalidade_id);
create index if not exists idx_lista_espera_profissional on public.lista_espera(profissional_id);

alter table public.lista_espera enable row level security;

drop policy if exists lista_espera_da_clinica on public.lista_espera;
create policy lista_espera_da_clinica on public.lista_espera for all to authenticated
  using (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())))
  with check (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())));

drop policy if exists lista_espera_membros on public.lista_espera;
create policy lista_espera_membros on public.lista_espera for all to authenticated
  using (clinica_id in (select public.clinica_ids_recepcao()))
  with check (clinica_id in (select public.clinica_ids_recepcao()));
-- (papel profissional: nenhum acesso — fila de espera é operação da recepção/dono)

-- ===== 3. TELECONSULTA =====

alter table public.consultas add column if not exists teleconsulta boolean not null default false;

-- ===== 4. STORAGE — bucket privado de exames =====

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('exames', 'exames', false, 10485760,
        array['application/pdf','image/jpeg','image/png','image/webp','image/heic','image/heif'])
on conflict (id) do nothing;

-- Caminho: <clinica_id>/<paciente_id>/<arquivo>.
-- Comparação por TEXTO (sem cast p/ uuid) para nunca estourar em path fora do padrão.
drop policy if exists exames_dono on storage.objects;
create policy exames_dono on storage.objects for all to authenticated
  using (bucket_id = 'exames' and (storage.foldername(name))[1] in
         (select id::text from public.clinicas where user_id = (select auth.uid())))
  with check (bucket_id = 'exames' and (storage.foldername(name))[1] in
         (select id::text from public.clinicas where user_id = (select auth.uid())));

drop policy if exists exames_recepcao on storage.objects;
create policy exames_recepcao on storage.objects for all to authenticated
  using (bucket_id = 'exames' and (storage.foldername(name))[1] in
         (select c::text from public.clinica_ids_recepcao() c))
  with check (bucket_id = 'exames' and (storage.foldername(name))[1] in
         (select c::text from public.clinica_ids_recepcao() c));

-- Profissional: SÓ leitura, e só dos exames dos pacientes que ele atende.
drop policy if exists exames_prof_sel on storage.objects;
create policy exames_prof_sel on storage.objects for select to authenticated
  using (bucket_id = 'exames' and (storage.foldername(name))[2] in
         (select p::text from public.pacientes_do_profissional() p));

-- ===== 5. LGPD — anonimização/exclusão limpam o prontuário novo =====
-- Mesmas funções de produção + 2 acréscimos cada: avaliacoes e lista_espera.
-- (Arquivos de exames: o front apaga via Storage API antes de chamar as RPCs.)

create or replace function public.paciente_anonimizar(p_paciente_id uuid)
returns json
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_clinica_id uuid;
begin
  select pa.clinica_id into v_clinica_id
  from public.pacientes pa
  join public.clinicas c on c.id = pa.clinica_id
  where pa.id = p_paciente_id and c.user_id = (select auth.uid());
  if v_clinica_id is null then
    return json_build_object('ok', false, 'erro', 'Paciente não encontrado ou sem permissão.');
  end if;

  update public.consultas
    set queixa = null, observacoes = null
    where paciente_id = p_paciente_id and clinica_id = v_clinica_id;

  delete from public.evolucoes where paciente_id = p_paciente_id and clinica_id = v_clinica_id;

  -- FASE 3: avaliações estruturadas e lista de espera também são dados de saúde/pessoais
  delete from public.avaliacoes  where paciente_id = p_paciente_id and clinica_id = v_clinica_id;
  delete from public.lista_espera where paciente_id = p_paciente_id and clinica_id = v_clinica_id;

  delete from public.mensagens where clinica_id = v_clinica_id
    and conversa_id in (select id from public.conversas where paciente_id = p_paciente_id and clinica_id = v_clinica_id);
  delete from public.conversas where paciente_id = p_paciente_id and clinica_id = v_clinica_id;

  -- Exames anexados (bucket 'exames'): o Storage BLOQUEIA delete direto via SQL
  -- ("Use the Storage API instead"), então quem apaga os arquivos é o FRONT,
  -- via Storage API, ANTES de chamar esta RPC (fail-closed na eliminação).

  update public.pacientes set
    nome = 'Paciente anonimizado (LGPD)',
    cpf = null, whatsapp = '', email = null, data_nascimento = null,
    endereco = null, genero = null, profissao = null, convenio = null,
    queixa_principal = null, historico_medico = null, medicamentos = null,
    alergias = null, foto_url = null, status = 'inativo',
    observacoes = 'Dados pessoais eliminados a pedido do titular (LGPD) em '
                  || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY')
  where id = p_paciente_id and clinica_id = v_clinica_id;

  insert into public.consentimentos (contexto, clinica_id, paciente_id, user_id, documentos, versao, identificador, nome)
  values ('portal_titular', v_clinica_id, p_paciente_id, (select auth.uid()),
          array['eliminacao'], 'anonimizacao', 'portal_titular', 'Paciente anonimizado (LGPD)');

  return json_build_object('ok', true);
end;
$function$;

create or replace function public.paciente_excluir(p_paciente_id uuid)
returns json
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_clinica_id uuid;
begin
  select pa.clinica_id into v_clinica_id
  from public.pacientes pa
  join public.clinicas c on c.id = pa.clinica_id
  where pa.id = p_paciente_id and c.user_id = (select auth.uid());
  if v_clinica_id is null then
    return json_build_object('ok', false, 'erro', 'Paciente não encontrado ou sem permissão.');
  end if;

  delete from public.mensagens where clinica_id = v_clinica_id
    and conversa_id in (select id from public.conversas where paciente_id = p_paciente_id and clinica_id = v_clinica_id);
  delete from public.conversas   where paciente_id = p_paciente_id and clinica_id = v_clinica_id;
  delete from public.lembretes   where clinica_id = v_clinica_id
    and consulta_id in (select id from public.consultas where paciente_id = p_paciente_id and clinica_id = v_clinica_id);
  delete from public.notas_fiscais where paciente_id = p_paciente_id and clinica_id = v_clinica_id;
  delete from public.evolucoes   where paciente_id = p_paciente_id and clinica_id = v_clinica_id;

  -- FASE 3: prontuário estruturado e fila de espera
  -- (exames do Storage: apagados pelo FRONT via Storage API antes desta RPC —
  --  o Storage bloqueia delete direto via SQL)
  delete from public.avaliacoes   where paciente_id = p_paciente_id and clinica_id = v_clinica_id;
  delete from public.lista_espera where paciente_id = p_paciente_id and clinica_id = v_clinica_id;

  delete from public.consultas   where paciente_id = p_paciente_id and clinica_id = v_clinica_id;
  delete from public.pacotes     where paciente_id = p_paciente_id and clinica_id = v_clinica_id;
  delete from public.mensalidades where paciente_id = p_paciente_id and clinica_id = v_clinica_id;
  delete from public.pacientes   where id = p_paciente_id and clinica_id = v_clinica_id;

  return json_build_object('ok', true);
end;
$function$;
