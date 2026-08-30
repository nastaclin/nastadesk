-- NastaDesk — Assinatura trimestral/anual + Site da clínica + Cupons de parceiro
--
-- 100% ADITIVA e reversível: nenhuma tabela/coluna existente é alterada de forma
-- destrutiva, nenhum dado de cliente é tocado.
--
-- Resumo:
--   (1) assinaturas.periodo            -> 'mensal' | 'trimestral' | 'anual' (null = mensal legado)
--   (2) config_publica                 -> chave/valor PÚBLICO (links de checkout, WhatsApp do site,
--                                         preço do site). Leitura p/ anon+authenticated; escrita só service_role.
--   (3) sites                          -> o site que a Nastaclin faz para a clínica (status/url/valor).
--                                         Cliente só LÊ o próprio; quem escreve é o admin (service_role)
--                                         ou a RPC site_solicitar() (que só cria o pedido).
--   (4) cupons + cupom_usos            -> cupons de parceiro (desconto + comissão) e o registro de uso.
--                                         Tabelas FECHADAS (deny-all p/ anon/authenticated, como admin_config):
--                                         o cliente nunca lê o parceiro nem a comissão. O app fala com elas
--                                         apenas por 2 RPCs SECURITY DEFINER que devolvem só o desconto.
--   (5) nastadesk_preco(plano, periodo) -> tabela de preços NO SERVIDOR (o front não dita valor).

-- ============================================================
-- 1) PERÍODO DA ASSINATURA
-- ============================================================
alter table public.assinaturas
  add column if not exists periodo text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'assinaturas_periodo_check') then
    alter table public.assinaturas
      add constraint assinaturas_periodo_check
      check (periodo is null or periodo in ('mensal', 'trimestral', 'anual'));
  end if;
end $$;

comment on column public.assinaturas.periodo is
  'Periodicidade da cobrança. NULL = mensal (assinaturas antigas, anteriores a 2026-08-30).';

-- ============================================================
-- 2) TABELA DE PREÇOS (no servidor)
-- ============================================================
-- Mensal: 97 / 197 / 347. Trimestral: -10%. Anual: -20% (valores arredondados).
create or replace function public.nastadesk_preco(p_plano text, p_periodo text default 'mensal')
returns numeric
language sql
immutable
set search_path = public
as $$
  select case coalesce(p_periodo, 'mensal')
    when 'anual' then case p_plano
      when 'basico' then 931::numeric
      when 'profissional' then 1891::numeric
      when 'premium' then 3331::numeric end
    when 'trimestral' then case p_plano
      when 'basico' then 262::numeric
      when 'profissional' then 532::numeric
      when 'premium' then 937::numeric end
    else case p_plano
      when 'basico' then 97::numeric
      when 'profissional' then 197::numeric
      when 'premium' then 347::numeric end
  end;
$$;

-- Toda função nasce com EXECUTE para PUBLIC (e o anon herda de PUBLIC):
-- fechar PUBLIC é o que realmente bloqueia quem não está logado.
revoke execute on function public.nastadesk_preco(text, text) from public, anon;
grant execute on function public.nastadesk_preco(text, text) to authenticated;

comment on function public.nastadesk_preco(text, text) is
  'Preço oficial de cada plano por período. Fonte da verdade do valor no servidor (o front nunca dita preço).';

-- ============================================================
-- 3) CONFIG PÚBLICA (links de checkout, WhatsApp do site, preço do site)
-- ============================================================
-- Diferente de admin_config (que guarda SEGREDOS e é deny-all): aqui só entram
-- valores que já são públicos por natureza — links de checkout hospedado,
-- número de WhatsApp comercial e preço de tabela.
create table if not exists public.config_publica (
  chave text primary key,
  valor jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now()
);

alter table public.config_publica enable row level security;

drop policy if exists config_publica_leitura on public.config_publica;
create policy config_publica_leitura on public.config_publica
  for select to anon, authenticated using (true);

revoke insert, update, delete, truncate on public.config_publica from anon, authenticated;

comment on table public.config_publica is
  'Configuração PÚBLICA por chave (links de checkout da Cakto, WhatsApp do site, preço do site). Leitura livre; escrita só service_role (painel admin).';

-- Seeds (não sobrescrevem o que o admin já tiver salvo).
insert into public.config_publica (chave, valor) values
  ('checkout_links', jsonb_build_object(
    'mensal', jsonb_build_object(
      'basico', 'https://pay.cakto.com.br/ad8vfmf_949243',
      'profissional', 'https://pay.cakto.com.br/w3ryxws_949248',
      'premium', 'https://pay.cakto.com.br/cvv64ck_949254'),
    'trimestral', jsonb_build_object('basico', '', 'profissional', '', 'premium', ''),
    'anual', jsonb_build_object('basico', '', 'profissional', '', 'premium', '')
  )),
  ('site', jsonb_build_object(
    'whatsapp', '5521984072359',
    'preco', 500,
    'preco_trimestral', 250,
    'preco_anual', 0
  ))
on conflict (chave) do nothing;

-- ============================================================
-- 4) SITES (site institucional feito pela Nastaclin)
-- ============================================================
create table if not exists public.sites (
  id uuid primary key default gen_random_uuid(),
  clinica_id uuid not null unique references public.clinicas(id) on delete cascade,
  status text not null default 'solicitado'
    check (status in ('solicitado', 'em_producao', 'no_ar', 'cancelado')),
  url text,
  valor_cobrado numeric,
  valor_pago numeric,
  gratuito boolean not null default false,
  cupom_codigo text,
  observacao text,
  origem text not null default 'cliente' check (origem in ('cliente', 'admin')),
  solicitado_em timestamptz,
  entregue_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create index if not exists idx_sites_clinica on public.sites (clinica_id);
create index if not exists idx_sites_status on public.sites (status);

alter table public.sites enable row level security;

-- O dono da clínica só LÊ o próprio registro (para a tela mudar de "criar" para
-- "editar" site). Escrever é só do admin (service_role) ou da RPC site_solicitar().
drop policy if exists sites_dono_le on public.sites;
create policy sites_dono_le on public.sites
  for select to authenticated
  using (clinica_id in (select id from public.clinicas where user_id = (select auth.uid())));

revoke insert, update, delete, truncate on public.sites from anon, authenticated;

comment on table public.sites is
  'Site institucional que a Nastaclin faz para a clínica. O cliente só lê o próprio (RLS); status/url/valores são definidos pelo admin.';

-- ============================================================
-- 5) CUPONS DE PARCERIA
-- ============================================================
create table if not exists public.cupons (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  parceiro_nome text not null,
  parceiro_contato text,
  parceiro_chave_pix text,
  -- desconto dado ao CLIENTE
  tipo_desconto text not null default 'percentual' check (tipo_desconto in ('percentual', 'valor')),
  valor_desconto numeric not null check (valor_desconto > 0),
  duracao_meses int check (duracao_meses is null or duracao_meses > 0), -- null = para sempre
  aplica_em text not null default 'ambos' check (aplica_em in ('assinatura', 'site', 'ambos')),
  -- comissão paga ao PARCEIRO
  comissao_tipo text not null default 'percentual' check (comissao_tipo in ('percentual', 'valor', 'nenhuma')),
  comissao_valor numeric not null default 0 check (comissao_valor >= 0),
  comissao_recorrente boolean not null default false,
  -- controle
  ativo boolean not null default true,
  validade date,
  limite_usos int check (limite_usos is null or limite_usos > 0),
  observacao text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

comment on table public.cupons is
  'Cupons de parceiros que indicam o NastaDesk. FECHADA para anon/authenticated (o cliente nunca vê parceiro nem comissão); acesso só via service_role (painel admin) ou pelas RPCs cupom_validar/cupom_registrar_uso.';

-- Normaliza o código (sempre MAIÚSCULO, sem espaços) — evita "nasta10" ≠ "NASTA10".
create or replace function public.cupom_normalizar_codigo()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.codigo := upper(regexp_replace(coalesce(new.codigo, ''), '\s', '', 'g'));
  new.atualizado_em := now();
  return new;
end;
$$;

drop trigger if exists trg_cupom_normalizar on public.cupons;
create trigger trg_cupom_normalizar
  before insert or update on public.cupons
  for each row execute function public.cupom_normalizar_codigo();

create table if not exists public.cupom_usos (
  id uuid primary key default gen_random_uuid(),
  cupom_id uuid references public.cupons(id) on delete set null,
  codigo text not null,                      -- desnormalizado: o histórico sobrevive ao cupom
  clinica_id uuid references public.clinicas(id) on delete set null,
  clinica_nome text,
  email text,
  contexto text not null check (contexto in ('assinatura', 'site')),
  plano text,
  periodo text,
  valor_base numeric,
  valor_desconto numeric,
  valor_final numeric,
  comissao_prevista numeric,
  comissao_paga boolean not null default false,
  comissao_paga_em timestamptz,
  -- 'pendente' = cliente aplicou o cupom e foi ao checkout;
  -- 'confirmado' = pagamento confirmado (o cakto-webhook confirma).
  status text not null default 'pendente' check (status in ('pendente', 'confirmado', 'cancelado')),
  confirmado_em timestamptz,
  usado_em timestamptz not null default now(),
  competencia text not null,   -- 'YYYY-MM' (fuso de São Paulo) — é por aqui que o repasse do mês é somado
  ano int not null,
  mes int not null,
  dia int not null
);

-- Um cliente conta uma vez por cupom/contexto (clicar 2× não infla o repasse).
create unique index if not exists uq_cupom_usos_cliente
  on public.cupom_usos (cupom_id, clinica_id, contexto)
  where cupom_id is not null and clinica_id is not null;
create index if not exists idx_cupom_usos_competencia on public.cupom_usos (competencia);
create index if not exists idx_cupom_usos_cupom on public.cupom_usos (cupom_id);
create index if not exists idx_cupom_usos_clinica on public.cupom_usos (clinica_id);

alter table public.cupons enable row level security;
alter table public.cupom_usos enable row level security;
-- Sem policy = deny-all (mesmo padrão de admin_config). Nada de anon/authenticated aqui.
revoke all on public.cupons from anon, authenticated;
revoke all on public.cupom_usos from anon, authenticated;

comment on table public.cupom_usos is
  'Registro de uso de cupom (1 linha por cliente/cupom/contexto). competencia YYYY-MM é o que fecha o repasse do mês ao parceiro.';

-- ============================================================
-- 6) RPCs DO CLIENTE (as únicas portas para os cupons)
-- ============================================================

-- Resolve a clínica do DONO logado (as telas de plano/site são do dono).
create or replace function public.minha_clinica_dono()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.clinicas where user_id = auth.uid() limit 1;
$$;

revoke execute on function public.minha_clinica_dono() from public, anon;
grant execute on function public.minha_clinica_dono() to authenticated;

-- Núcleo compartilhado: acha o cupom válido e calcula o desconto.
-- Devolve APENAS o que o cliente pode ver (nunca parceiro nem comissão).
create or replace function public.cupom_calcular(
  p_codigo text,
  p_contexto text,
  p_plano text default null,
  p_periodo text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_cod text;
  c public.cupons%rowtype;
  v_usos int;
  v_base numeric;
  v_desc numeric;
  v_dur text;
begin
  v_cod := upper(regexp_replace(coalesce(p_codigo, ''), '\s', '', 'g'));
  if v_cod = '' then
    return jsonb_build_object('ok', false, 'erro', 'Digite um código de cupom.');
  end if;
  if coalesce(p_contexto, '') not in ('assinatura', 'site') then
    return jsonb_build_object('ok', false, 'erro', 'Contexto inválido.');
  end if;

  select * into c from public.cupons where codigo = v_cod;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'Cupom não encontrado.');
  end if;
  if not c.ativo then
    return jsonb_build_object('ok', false, 'erro', 'Este cupom não está mais ativo.');
  end if;
  if c.validade is not null and c.validade < (now() at time zone 'America/Sao_Paulo')::date then
    return jsonb_build_object('ok', false, 'erro', 'Este cupom expirou.');
  end if;
  if c.aplica_em <> 'ambos' and c.aplica_em <> p_contexto then
    return jsonb_build_object('ok', false, 'erro',
      case when c.aplica_em = 'site' then 'Este cupom vale só para o site.'
           else 'Este cupom vale só para a assinatura.' end);
  end if;
  if c.limite_usos is not null then
    select count(*) into v_usos from public.cupom_usos
     where cupom_id = c.id and status <> 'cancelado';
    if v_usos >= c.limite_usos then
      return jsonb_build_object('ok', false, 'erro', 'Este cupom atingiu o limite de usos.');
    end if;
  end if;

  -- Valor base SEMPRE do servidor.
  if p_contexto = 'assinatura' then
    v_base := public.nastadesk_preco(p_plano, coalesce(p_periodo, 'mensal'));
  else
    v_base := (select coalesce((valor->>'preco')::numeric, 500)
                 from public.config_publica where chave = 'site');
    -- Anual = site grátis; trimestral = metade. Nesses casos o cupom não tem o que descontar.
    if p_periodo = 'anual' then v_base := 0;
    elsif p_periodo = 'trimestral' then
      v_base := (select coalesce((valor->>'preco_trimestral')::numeric, v_base / 2)
                   from public.config_publica where chave = 'site');
    end if;
  end if;
  if v_base is null then
    return jsonb_build_object('ok', false, 'erro', 'Plano ou período inválido.');
  end if;

  if c.tipo_desconto = 'percentual' then
    v_desc := round(v_base * least(c.valor_desconto, 100) / 100, 2);
  else
    v_desc := least(c.valor_desconto, v_base);
  end if;

  v_dur := case
    when p_contexto = 'site' then 'no valor do site'
    when c.duracao_meses is null then 'em todas as cobranças'
    when c.duracao_meses = 1 then 'na primeira cobrança'
    else 'nas ' || c.duracao_meses || ' primeiras cobranças'
  end;

  return jsonb_build_object(
    'ok', true,
    'cupom_id', c.id,
    'codigo', c.codigo,
    'tipo_desconto', c.tipo_desconto,
    'valor_desconto', c.valor_desconto,
    'duracao_meses', c.duracao_meses,
    'duracao_texto', v_dur,
    'valor_base', v_base,
    'desconto', v_desc,
    'valor_final', greatest(v_base - v_desc, 0)
  );
end;
$$;

revoke execute on function public.cupom_calcular(text, text, text, text) from public, anon;
grant execute on function public.cupom_calcular(text, text, text, text) to authenticated;

-- Valida o cupom (sem registrar nada) — usado no botão "Aplicar".
create or replace function public.cupom_validar(
  p_codigo text,
  p_contexto text,
  p_plano text default null,
  p_periodo text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'erro', 'Faça login para usar um cupom.');
  end if;
  return public.cupom_calcular(p_codigo, p_contexto, p_plano, p_periodo);
end;
$$;

revoke execute on function public.cupom_validar(text, text, text, text) from public, anon;
grant execute on function public.cupom_validar(text, text, text, text) to authenticated;

-- Registra o uso do cupom pela clínica logada (chamado ao ir para o checkout /
-- ao pedir o site). Idempotente: 1 linha por clínica/cupom/contexto.
create or replace function public.cupom_registrar_uso(
  p_codigo text,
  p_contexto text,
  p_plano text default null,
  p_periodo text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v jsonb;
  c public.cupons%rowtype;
  v_clinica uuid;
  v_nome text;
  v_email text;
  v_comissao numeric := 0;
  v_final numeric;
  v_hoje timestamptz := now() at time zone 'America/Sao_Paulo';
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'erro', 'Faça login para usar um cupom.');
  end if;

  v := public.cupom_calcular(p_codigo, p_contexto, p_plano, p_periodo);
  if not coalesce((v->>'ok')::boolean, false) then
    return v;
  end if;

  select id, nome, email into v_clinica, v_nome, v_email
    from public.clinicas where user_id = auth.uid() limit 1;
  if v_clinica is null then
    return jsonb_build_object('ok', false, 'erro', 'Só o dono da conta pode aplicar cupom.');
  end if;

  select * into c from public.cupons where id = (v->>'cupom_id')::uuid;
  v_final := (v->>'valor_final')::numeric;

  if c.comissao_tipo = 'percentual' then
    v_comissao := round(v_final * c.comissao_valor / 100, 2);
  elsif c.comissao_tipo = 'valor' then
    v_comissao := c.comissao_valor;
  end if;

  insert into public.cupom_usos (
    cupom_id, codigo, clinica_id, clinica_nome, email, contexto, plano, periodo,
    valor_base, valor_desconto, valor_final, comissao_prevista,
    competencia, ano, mes, dia
  ) values (
    c.id, c.codigo, v_clinica, v_nome, v_email, p_contexto, p_plano, p_periodo,
    (v->>'valor_base')::numeric, (v->>'desconto')::numeric, v_final, v_comissao,
    to_char(v_hoje, 'YYYY-MM'),
    extract(year from v_hoje)::int, extract(month from v_hoje)::int, extract(day from v_hoje)::int
  )
  -- o índice é PARCIAL, então o ON CONFLICT precisa repetir o mesmo predicado
  on conflict (cupom_id, clinica_id, contexto)
    where cupom_id is not null and clinica_id is not null
  do update set
    plano = excluded.plano,
    periodo = excluded.periodo,
    valor_base = excluded.valor_base,
    valor_desconto = excluded.valor_desconto,
    valor_final = excluded.valor_final,
    comissao_prevista = excluded.comissao_prevista;

  return v || jsonb_build_object('registrado', true);
end;
$$;

revoke execute on function public.cupom_registrar_uso(text, text, text, text) from public, anon;
grant execute on function public.cupom_registrar_uso(text, text, text, text) to authenticated;

-- Cria o PEDIDO de site da clínica logada. Só cria (nunca muda status/url/valor:
-- isso é do admin). Idempotente — se já existe registro, devolve o que existe.
create or replace function public.site_solicitar(p_cupom text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_clinica uuid;
  s public.sites%rowtype;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'erro', 'Faça login.');
  end if;
  select id into v_clinica from public.clinicas where user_id = auth.uid() limit 1;
  if v_clinica is null then
    return jsonb_build_object('ok', false, 'erro', 'Só o dono da conta pode pedir o site.');
  end if;

  select * into s from public.sites where clinica_id = v_clinica;
  if found then
    return jsonb_build_object('ok', true, 'ja_existia', true, 'status', s.status);
  end if;

  insert into public.sites (clinica_id, status, origem, solicitado_em, cupom_codigo)
  values (v_clinica, 'solicitado', 'cliente', now(),
          nullif(upper(regexp_replace(coalesce(p_cupom, ''), '\s', '', 'g')), ''))
  on conflict (clinica_id) do nothing;

  return jsonb_build_object('ok', true, 'ja_existia', false, 'status', 'solicitado');
end;
$$;

revoke execute on function public.site_solicitar(text) from public, anon;
grant execute on function public.site_solicitar(text) to authenticated;
