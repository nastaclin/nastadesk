-- =============================================================================
-- NastaDesk — Prontuário: autor da evolução (COFFITO 414/2012, art. 2º par. único)
-- e guarda mínima de 5 anos (COFFITO 414/2012, art. 6º, I)
--
-- 100% ADITIVA: só adiciona colunas, funções e triggers novos. Não renomeia,
-- não apaga e não altera nenhuma coluna, policy de RLS ou função existente.
-- Idempotente: pode rodar mais de uma vez.
--
-- ANTES DE RODAR EM PRODUÇÃO: aplicar numa branch do Supabase e rodar o
-- arquivo de teste (20261023_prontuario_teste.sql). Conferir os nomes de coluna
-- marcados com "CONFERIR" contra o schema real (escritos a partir do código do app).
--
-- ROLLBACK (desfaz tudo sem perder dado):
--   drop trigger if exists trg_evolucoes_autor        on public.evolucoes;
--   drop trigger if exists trg_avaliacoes_autor       on public.avaliacoes;
--   drop trigger if exists trg_evolucoes_imutavel     on public.evolucoes;
--   drop trigger if exists trg_evolucoes_guarda       on public.evolucoes;
--   drop trigger if exists trg_avaliacoes_guarda      on public.avaliacoes;
--   (as colunas novas podem ficar; o app funciona com ou sem elas)
-- =============================================================================

-- 1) Colunas de autoria --------------------------------------------------------
alter table public.evolucoes  add column if not exists autor_user_id  uuid;
alter table public.evolucoes  add column if not exists profissional_id uuid;
alter table public.evolucoes  add column if not exists autor_nome     text;
alter table public.evolucoes  add column if not exists autor_registro text;

alter table public.avaliacoes add column if not exists autor_user_id  uuid;
alter table public.avaliacoes add column if not exists profissional_id uuid;  -- já existe: no-op
alter table public.avaliacoes add column if not exists autor_nome     text;
alter table public.avaliacoes add column if not exists autor_registro text;

-- 2) Preenche o autor no servidor (o navegador não consegue forjar) -----------
-- Profissional vinculado ao login  -> nome + registro do cadastro de profissionais
-- Dono da clínica                  -> responsável + recibo_registro da clínica
-- Outros (recepção)                -> e-mail do login
-- Qualquer falha na busca NUNCA impede salvar a evolução.
create or replace function public.prontuario_preencher_autor()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_prof_id uuid;
  v_nome    text;
  v_reg     text;
begin
  new.autor_user_id := v_uid;
  if v_uid is null then
    return new;  -- inserido pelo backend (service_role): mantém o que veio
  end if;

  begin
    -- CONFERIR: clinica_membros(user_id, clinica_id, profissional_id, ativo)
    select m.profissional_id into v_prof_id
      from public.clinica_membros m
     where m.user_id = v_uid
       and m.clinica_id = new.clinica_id
       and coalesce(m.ativo, true)
     limit 1;

    if v_prof_id is not null then
      select p.nome, p.registro into v_nome, v_reg
        from public.profissionais p
       where p.id = v_prof_id;
    else
      -- CONFERIR: clinicas(user_id = dono, responsavel, recibo_registro)
      select c.responsavel, c.recibo_registro into v_nome, v_reg
        from public.clinicas c
       where c.id = new.clinica_id
         and c.user_id = v_uid;
    end if;

    if coalesce(trim(v_nome), '') = '' then
      select u.email into v_nome from auth.users u where u.id = v_uid;
    end if;
  exception when others then
    null;
  end;

  new.profissional_id := coalesce(new.profissional_id, v_prof_id);
  new.autor_nome      := nullif(trim(v_nome), '');
  new.autor_registro  := nullif(trim(v_reg), '');
  return new;
end;
$$;

drop trigger if exists trg_evolucoes_autor on public.evolucoes;
create trigger trg_evolucoes_autor
  before insert on public.evolucoes
  for each row execute function public.prontuario_preencher_autor();

drop trigger if exists trg_avaliacoes_autor on public.avaliacoes;
create trigger trg_avaliacoes_autor
  before insert on public.avaliacoes
  for each row execute function public.prontuario_preencher_autor();

-- 3) Até quando o prontuário do paciente precisa ser guardado ------------------
-- Último registro clínico (evolução, avaliação ou consulta atendida) + 5 anos.
-- null = paciente sem registro clínico (pode excluir).
create or replace function public.prontuario_guarda_ate(p_paciente_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
  select greatest(
    (select max(e.criado_em) from public.evolucoes  e where e.paciente_id = p_paciente_id),
    (select max(a.criado_em) from public.avaliacoes a where a.paciente_id = p_paciente_id),
    (select max(c.data_hora) from public.consultas  c where c.paciente_id = p_paciente_id and c.status = 'atendido')
  ) + interval '5 years';
$$;

-- 4) Evolução registrada não muda (correção = nova evolução/adendo) -----------
-- Exceções: prazo de guarda vencido (anonimização LGPD) ou suporte com a flag
-- de sessão nastadesk.permitir_alteracao_prontuario = 'on'.
create or replace function public.evolucoes_imutavel()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ate timestamptz;
begin
  if current_setting('nastadesk.permitir_alteracao_prontuario', true) = 'on' then
    return new;
  end if;
  if new.texto          is not distinct from old.texto
     and new.criado_em  is not distinct from old.criado_em
     and new.autor_user_id  is not distinct from old.autor_user_id
     and new.autor_nome     is not distinct from old.autor_nome
     and new.autor_registro is not distinct from old.autor_registro then
    return new;  -- não mexeu no conteúdo clínico
  end if;
  v_ate := public.prontuario_guarda_ate(old.paciente_id);
  if v_ate is not null and v_ate > now() then
    raise exception 'Evolução já registrada não pode ser alterada (COFFITO 414/2012). Registre uma nova evolução como adendo.'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_evolucoes_imutavel on public.evolucoes;
create trigger trg_evolucoes_imutavel
  before update on public.evolucoes
  for each row execute function public.evolucoes_imutavel();

-- 5) Não apaga prontuário dentro do prazo de guarda ----------------------------
-- Vale também para exclusões em cascata (paciente_excluir / paciente_anonimizar):
-- a RPC falha com a mensagem abaixo e nada é apagado (a transação inteira volta).
-- Tolerância: registro criado há menos de 24h pode ser apagado (erro de digitação,
-- paciente cadastrado por engano no mesmo dia).
create or replace function public.prontuario_bloquear_exclusao()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ate timestamptz;
begin
  if current_setting('nastadesk.permitir_exclusao_prontuario', true) = 'on' then
    return old;
  end if;
  if old.criado_em > now() - interval '24 hours' then
    return old;
  end if;
  v_ate := public.prontuario_guarda_ate(old.paciente_id);
  if v_ate is not null and v_ate > now() then
    raise exception 'Prontuário em guarda obrigatória até % (COFFITO 414/2012, art. 6º). Use "Inativar" no paciente.',
      to_char(v_ate at time zone 'America/Sao_Paulo', 'DD/MM/YYYY')
      using errcode = 'P0001';
  end if;
  return old;
end;
$$;

drop trigger if exists trg_evolucoes_guarda on public.evolucoes;
create trigger trg_evolucoes_guarda
  before delete on public.evolucoes
  for each row execute function public.prontuario_bloquear_exclusao();

drop trigger if exists trg_avaliacoes_guarda on public.avaliacoes;
create trigger trg_avaliacoes_guarda
  before delete on public.avaliacoes
  for each row execute function public.prontuario_bloquear_exclusao();

-- As funções de trigger não precisam ser chamáveis pela API.
revoke all on function public.prontuario_preencher_autor()   from public, anon, authenticated;
revoke all on function public.evolucoes_imutavel()           from public, anon, authenticated;
revoke all on function public.prontuario_bloquear_exclusao() from public, anon, authenticated;
revoke all on function public.prontuario_guarda_ate(uuid)    from public, anon, authenticated;
