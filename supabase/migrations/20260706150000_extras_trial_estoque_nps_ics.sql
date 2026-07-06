-- ============================================================
-- EXTRAS (2026-07-06) — decididos pelo dono nesta data:
--
-- 1. TRIAL SELF-SERVICE (7 dias, plano Premium) no cadastro.
--    ⚠️ Também CORRIGE um bug: a migration 20260704160000 reescreveu o
--    gatilho de signup e perdeu o `ativo=false` do paywall — desde então
--    clínica nova entrava DE GRAÇA PARA SEMPRE (o default da coluna é
--    true). Agora o cadastro dá um teste grátis CONTROLADO: ativo=true +
--    cortesia=true + cortesia_expira_em = now()+7d + plano='premium'.
-- 2. CORTE AUTOMÁTICO de cortesia/trial vencido (decisão do dono:
--    vale para TODAS, inclusive as clínicas atuais com data marcada).
--    Função encerrar_cortesias_vencidas() + job pg_cron de hora em hora.
--    Guarda: NUNCA corta quem tem assinatura ativa/em_atraso (quem pagou
--    fica, mesmo que o flag de cortesia tenha sobrado ligado).
-- 3. ESTOQUE — estoque_itens + estoque_movimentos (saldo mantido por
--    trigger; front só insere movimento). RLS: dono/recepção; profissional nada.
-- 4. NPS — nps_respostas (envio 1-clique via wa.me + registro da nota
--    0..10). RLS: dono/recepção; profissional nada. LGPD: anonimizar/
--    excluir paciente limpam também o NPS dele.
-- 5. FEED ICS (Google Agenda/Outlook) — clinicas.ics_token (segredo do
--    link de assinatura do calendário; lido pela edge `agenda-ics`).
--
-- Aditivo e reversível, EXCETO o item 2 (corte), que é a decisão
-- explícita do dono de 2026-07-06.
-- ============================================================

-- ===== 5. TOKEN DO FEED ICS =====

alter table public.clinicas add column if not exists ics_token uuid unique default gen_random_uuid();
update public.clinicas set ics_token = gen_random_uuid() where ics_token is null;

-- ===== 3. ESTOQUE =====

create table if not exists public.estoque_itens (
  id uuid primary key default gen_random_uuid(),
  clinica_id uuid not null references public.clinicas(id) on delete cascade,
  nome text not null,
  categoria text,
  unidade text not null default 'un',
  quantidade numeric not null default 0,
  quantidade_minima numeric not null default 0,
  observacao text,
  ativo boolean not null default true,
  criado_em timestamptz not null default now()
);

create table if not exists public.estoque_movimentos (
  id uuid primary key default gen_random_uuid(),
  clinica_id uuid not null references public.clinicas(id) on delete cascade,
  item_id uuid not null references public.estoque_itens(id) on delete cascade,
  tipo text not null check (tipo in ('entrada','saida')),
  quantidade numeric not null check (quantidade > 0),
  motivo text,
  criado_em timestamptz not null default now()
);

create index if not exists idx_estoque_itens_clinica on public.estoque_itens(clinica_id);
create index if not exists idx_estoque_mov_clinica on public.estoque_movimentos(clinica_id);
create index if not exists idx_estoque_mov_item on public.estoque_movimentos(item_id, criado_em desc);

alter table public.estoque_itens enable row level security;
alter table public.estoque_movimentos enable row level security;

-- Dono: tudo, escopo da própria clínica (mesmo formato das demais tabelas).
drop policy if exists estoque_itens_da_clinica on public.estoque_itens;
create policy estoque_itens_da_clinica on public.estoque_itens for all to authenticated
  using (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())))
  with check (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())));

drop policy if exists estoque_itens_membros on public.estoque_itens;
create policy estoque_itens_membros on public.estoque_itens for all to authenticated
  using (clinica_id in (select public.clinica_ids_recepcao()))
  with check (clinica_id in (select public.clinica_ids_recepcao()));

drop policy if exists estoque_mov_da_clinica on public.estoque_movimentos;
create policy estoque_mov_da_clinica on public.estoque_movimentos for all to authenticated
  using (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())))
  with check (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())));

drop policy if exists estoque_mov_membros on public.estoque_movimentos;
create policy estoque_mov_membros on public.estoque_movimentos for all to authenticated
  using (clinica_id in (select public.clinica_ids_recepcao()))
  with check (clinica_id in (select public.clinica_ids_recepcao()));
-- (papel profissional: nenhum acesso — estoque é operação da recepção/dono)

-- Saldo do item mantido por trigger: o front SÓ insere movimentos (a
-- exclusão de movimento não é oferecida — correção se faz com movimento
-- inverso, preservando o histórico).
create or replace function public.estoque_aplicar_movimento()
returns trigger language plpgsql
set search_path to 'public', 'pg_temp'
as $$
begin
  update public.estoque_itens
     set quantidade = quantidade + case when new.tipo = 'entrada' then new.quantidade else -new.quantidade end
   where id = new.item_id and clinica_id = new.clinica_id;
  if not found then
    raise exception 'Item de estoque não encontrado nesta clínica';
  end if;
  return new;
end $$;

drop trigger if exists trg_estoque_mov on public.estoque_movimentos;
create trigger trg_estoque_mov after insert on public.estoque_movimentos
  for each row execute function public.estoque_aplicar_movimento();

-- ===== 4. NPS =====

create table if not exists public.nps_respostas (
  id uuid primary key default gen_random_uuid(),
  clinica_id uuid not null references public.clinicas(id) on delete cascade,
  paciente_id uuid references public.pacientes(id) on delete cascade,
  nome text,
  nota integer check (nota between 0 and 10),  -- null = pesquisa enviada, aguardando resposta
  comentario text,
  canal text not null default 'whatsapp',
  enviado_em timestamptz not null default now(),
  respondido_em timestamptz,
  criado_em timestamptz not null default now()
);

create index if not exists idx_nps_clinica on public.nps_respostas(clinica_id, criado_em desc);
create index if not exists idx_nps_paciente on public.nps_respostas(paciente_id);

alter table public.nps_respostas enable row level security;

drop policy if exists nps_da_clinica on public.nps_respostas;
create policy nps_da_clinica on public.nps_respostas for all to authenticated
  using (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())))
  with check (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())));

drop policy if exists nps_membros on public.nps_respostas;
create policy nps_membros on public.nps_respostas for all to authenticated
  using (clinica_id in (select public.clinica_ids_recepcao()))
  with check (clinica_id in (select public.clinica_ids_recepcao()));
-- (papel profissional: nenhum acesso — NPS é gestão da clínica)

-- LGPD: eliminar/excluir paciente limpa também as respostas de NPS dele.
-- (Reescreve as duas RPCs a partir da versão de produção da Fase 3,
--  acrescentando só a linha do NPS.)
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

  -- EXTRAS 2026-07-06: respostas de NPS são opinião identificável do titular
  delete from public.nps_respostas where paciente_id = p_paciente_id and clinica_id = v_clinica_id;

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

  -- EXTRAS 2026-07-06: respostas de NPS
  delete from public.nps_respostas where paciente_id = p_paciente_id and clinica_id = v_clinica_id;

  delete from public.consultas   where paciente_id = p_paciente_id and clinica_id = v_clinica_id;
  delete from public.pacotes     where paciente_id = p_paciente_id and clinica_id = v_clinica_id;
  delete from public.mensalidades where paciente_id = p_paciente_id and clinica_id = v_clinica_id;
  delete from public.pacientes   where id = p_paciente_id and clinica_id = v_clinica_id;

  return json_build_object('ok', true);
end;
$function$;

-- ===== 1. TRIAL SELF-SERVICE NO CADASTRO (7 dias · Premium) =====

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

  -- TRIAL SELF-SERVICE (decisão do dono, 2026-07-06): clínica nova entra
  -- direto com 7 dias grátis no Premium (ativo=true + cortesia com data).
  -- O corte na data é do job 'nastadesk-cortesia-expira'; assinar pela
  -- Cakto cria assinatura ativa e a clínica nunca mais é cortada por aqui.
  insert into public.clinicas (user_id, nome, responsavel, whatsapp, plano, slug,
                               ativo, cortesia, cortesia_expira_em)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nome_clinica', 'Minha Clínica'),
    coalesce(new.raw_user_meta_data->>'responsavel', 'Responsável'),
    coalesce(new.raw_user_meta_data->>'whatsapp', ''),
    'premium',
    public.gerar_slug_unico(coalesce(new.raw_user_meta_data->>'nome_clinica', 'clinica')),
    true,
    true,
    now() + interval '7 days'
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

-- ===== 2. CORTE AUTOMÁTICO DE CORTESIA/TRIAL VENCIDO =====

create or replace function public.encerrar_cortesias_vencidas()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_n integer;
begin
  update public.clinicas c
     set ativo = false,
         cortesia = false          -- deixa de ser "cortesia": vira suspensa/sem plano
     where c.ativo = true
       and c.cortesia = true
       and c.cortesia_expira_em is not null
       and c.cortesia_expira_em < now()
       -- quem PAGOU nunca é cortado por aqui (mesmo com flag de cortesia sobrando)
       and not exists (
         select 1 from public.assinaturas a
         where a.clinica_id = c.id and a.status in ('ativa','em_atraso')
       );
  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

revoke execute on function public.encerrar_cortesias_vencidas() from public, anon, authenticated;

-- Job de hora em hora (idempotente: remove agendamento anterior se existir).
do $$
begin
  perform cron.unschedule('nastadesk-cortesia-expira');
exception when others then
  null; -- ainda não existia
end $$;

select cron.schedule(
  'nastadesk-cortesia-expira',
  '7 * * * *',
  $$select public.encerrar_cortesias_vencidas()$$
);
