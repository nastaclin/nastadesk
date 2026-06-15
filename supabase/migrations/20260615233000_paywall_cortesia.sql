-- NastaDesk — Paywall no cadastro + cortesia (acesso grátis controlado)
-- Mudança de regra de negócio:
--   Antes: ao se cadastrar, a clínica nascia no plano 'basico' com ativo=true (entrava de graça).
--   Agora: a clínica nasce SEM plano (plano = NULL) e BLOQUEADA (ativo = false).
--          O cliente só entra na plataforma depois de escolher um plano e pagar,
--          ou de receber acesso de cortesia pelo painel admin.

-- 'plano' deixa de ser obrigatório: NULL = "sem plano" (cliente ainda não assinou)
alter table public.clinicas alter column plano drop not null;
alter table public.clinicas alter column plano drop default;

-- Cortesia: acesso liberado manualmente (trial/parcerias), sem pagamento no Mercado Pago.
-- cortesia_expira_em é apenas informativo (ex.: trial de 7 dias) — o controle final é o campo 'ativo'.
alter table public.clinicas add column if not exists cortesia boolean not null default false;
alter table public.clinicas add column if not exists cortesia_expira_em timestamptz;

-- Novo signup: cria a clínica SEM plano e bloqueada até pagar/receber cortesia.
create or replace function public.criar_clinica_no_signup()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.clinicas (user_id, nome, responsavel, whatsapp, plano, ativo, slug)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nome_clinica', 'Minha Clínica'),
    coalesce(new.raw_user_meta_data->>'responsavel', 'Responsável'),
    coalesce(new.raw_user_meta_data->>'whatsapp', ''),
    null,    -- sem plano até escolher/pagar
    false,   -- sem acesso até pagar (ou cortesia)
    public.gerar_slug_unico(coalesce(new.raw_user_meta_data->>'nome_clinica', 'clinica'))
  );
  return new;
end;
$$;

-- ===== RPCs administrativas (uso pelo painel admin via service_role) =====

-- Concede acesso de cortesia: define o plano, libera o acesso e, opcionalmente, uma data de expiração.
create or replace function public.admin_conceder_cortesia(p_clinica_id uuid, p_plano text default 'premium', p_dias integer default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_plano not in ('basico','profissional','premium') then
    raise exception 'plano inválido: %', p_plano;
  end if;
  update public.clinicas
     set plano = p_plano,
         ativo = true,
         cortesia = true,
         cortesia_expira_em = case when p_dias is null then null else now() + make_interval(days => p_dias) end
   where id = p_clinica_id;
end;
$$;

-- Remove o acesso (encerra a cortesia ou bloqueia a conta).
create or replace function public.admin_remover_acesso(p_clinica_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.clinicas
     set ativo = false,
         cortesia = false,
         cortesia_expira_em = null
   where id = p_clinica_id;
end;
$$;

-- Apenas o service_role (painel admin) pode executar estas RPCs.
revoke execute on function public.admin_conceder_cortesia(uuid, text, integer) from public, anon, authenticated;
revoke execute on function public.admin_remover_acesso(uuid) from public, anon, authenticated;
grant execute on function public.admin_conceder_cortesia(uuid, text, integer) to service_role;
grant execute on function public.admin_remover_acesso(uuid) to service_role;
