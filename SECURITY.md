# Segurança do NastaDesk — Playbook AppSec

> Revisão de arquitetura de 2026-07-08 (complementa a varredura de 2026-07-07 —
> ver Histórico do CLAUDE.md). Vale para os 2 repos (`nastadesk` + `dashboard`),
> que compartilham o mesmo backend Supabase. **Mantenha este arquivo idêntico nos
> dois repos.**

## 0. Resumo executivo desta revisão

| Pilar | Estado | Ação |
|---|---|---|
| SQL dinâmico em PLpgSQL | ✅ Nenhum `EXECUTE` de runtime com input de usuário (só DDL de migration com `%I`) | Manter o padrão da seção 1.1 |
| RLS multi-tenant | ✅ Ativo nas 30 tabelas; isolamento validado com JWT simulado; privesc de `nastaclin_admins` corrigido em 2026-07-07 | Checklist de verificação na seção 1.2 |
| Criptografia de coluna (pgcrypto) | ⚠️ Não usada; ver análise honesta na seção 1.3 antes de adotar | Decisão do dono |
| XSS no front | ✅ Helper `esc()`/`escapeHtml()` aplicado consistentemente (1 sink menor corrigido em 2026-07-08: iniciais do avatar no portal) | CI `xss-audit` vigia regressão |
| Sessão/tokens | ⚠️ Token Supabase em `localStorage` (limitação da arquitetura sem servidor próprio — ver 2.2) | Mitigações listadas; 2FA já existe |
| Headers HTTP | ✅ Adicionados no `vercel.json` (nosniff, X-Frame-Options, HSTS, Referrer-Policy, Permissions-Policy); CSP enforce fica p/ depois de validar (2.3) | Draft pronto |
| CI de segurança | ✅ `.github/workflows/security.yml` (gitleaks + semgrep + auditoria XSS + node --check + npm audit condicional) | Roda em todo push/PR |
| Segredos hardcoded | ✅ Varredura limpa: só a chave `anon` (pública por design). service_role/Anthropic/Evolution/Cakto/hCaptcha estão em env das edge functions ou em `admin_config` (deny-all p/ navegador) | Checklist na seção 4 |

---

## 1. PLpgSQL / PostgreSQL

### 1.1 SQL dinâmico e SQL Injection

**Auditoria (2026-07-08):** todos os `EXECUTE` do repositório estão em
**migrations** (DDL: criar policy, publication) e interpolam apenas
**identificadores** com `format('%I', ...)` — nunca valor vindo de usuário.
As RPCs de runtime (`agendar_online`, `bot_*`, `paciente_*`, `gerar_mensalidades`,
`registrar_auditoria`) usam SQL **estático** com parâmetros — o planner já os
trata como dados, não como código. **Não há vetor de SQL Injection em PLpgSQL hoje.**

**Regra para código novo** (se algum dia precisar de SQL dinâmico de verdade):

```sql
-- ❌ NUNCA: concatenar valor na string
EXECUTE 'select * from pacientes where nome = ''' || p_nome || '''';

-- ✅ SEMPRE: valor via USING ($1, $2...), identificador via %I
EXECUTE format(
  'select count(*) from %I where clinica_id = $1 and nome ilike $2',
  p_tabela                      -- identificador: %I (quota e valida)
) USING p_clinica_id, p_nome;   -- valores: USING (parametrizado, nunca vira código)
```

- `%I` = identificador (tabela/coluna) — quota com aspas duplas.
- `%L` só como último recurso para literais; prefira `USING`.
- E toda função nova: `SET search_path = ''` (ou `public, pg_temp`) no cabeçalho —
  padrão já adotado após o hardening de 2026-07-07.

### 1.2 Row-Level Security (isolamento clínica A × clínica B)

**Já está ativo em todas as tabelas de dados** (padrão do projeto desde o início,
performático desde a Fase 0). O template canônico usado — e que deve ser copiado
para QUALQUER tabela nova — é:

```sql
-- 1) Toda tabela de dado de cliente tem clinica_id NOT NULL
create table public.nova_tabela (
  id uuid primary key default gen_random_uuid(),
  clinica_id uuid not null references public.clinicas(id) on delete cascade,
  ...
);

-- 2) Ligar RLS (sem policy = deny-all; as policies abrem só o necessário)
alter table public.nova_tabela enable row level security;

-- 3) Dono da clínica: tudo, escopado pelo dono do tenant
create policy nova_tabela_dono on public.nova_tabela
  for all to authenticated
  using (clinica_id in (select id from public.clinicas
                        where user_id = (select auth.uid())))
  with check (clinica_id in (select id from public.clinicas
                             where user_id = (select auth.uid())));

-- 4) Funcionário (recepção): via função SECURITY DEFINER que resolve o vínculo
create policy nova_tabela_membros on public.nova_tabela
  for all to authenticated
  using (clinica_id in (select public.clinica_ids_recepcao()))
  with check (clinica_id in (select public.clinica_ids_recepcao()));

-- 5) Papel profissional: SÓ se precisar, e só SELECT/verbos mínimos
--    (espelhar o padrão de consultas/pacientes/evolucoes da migration
--     20260704180000_portal_profissional_rls.sql)

-- 6) Índice em clinica_id (o RLS filtra por ela em toda query)
create index on public.nova_tabela (clinica_id);
```

**Três regras aprendidas neste projeto (não repetir os erros):**

1. **`FOR ALL` sem `WITH CHECK` é bomba armada.** No Postgres, INSERT/UPDATE sem
   `WITH CHECK` caem no `USING` — foi exatamente isso que permitia a
   auto-promoção a admin em `nastaclin_admins` (corrigido em
   `20260707154836_fix_nastaclin_admins_privesc.sql`). Toda policy de escrita
   tem que ter `WITH CHECK` explícito.
2. **Use `(select auth.uid())`, não `auth.uid()`** — avaliado 1× por query em
   vez de por linha (Fase 0, `20260702190000_rls_performance.sql`).
3. **RLS não substitui GRANT.** `anon` teve INSERT/UPDATE/DELETE revogados em
   todas as tabelas (2026-07-07) — defesa em profundidade caso alguma policy
   futura vaze.

**Verificação (rodar após qualquer migration; advisors do Supabase também):**

```sql
-- Tabela sem RLS ou sem policy = alarme
select c.relname,
       c.relrowsecurity as rls_on,
       count(p.polname)  as policies
from pg_class c
join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
left join pg_policy p on p.polrelid = c.oid
where c.relkind = 'r'
group by 1, 2
having not c.relrowsecurity or count(p.polname) = 0;

-- Policy de escrita sem WITH CHECK (o bug do nastaclin_admins)
select polrelid::regclass, polname, polcmd
from pg_policy
where polcmd in ('a','w','*') and polwithcheck is null;
```

E o teste funcional que já é praxe do projeto: simular JWT
(`set local request.jwt.claims = '{"sub":"<uuid>","role":"authenticated"}'` +
`set local role authenticated` dentro de `BEGIN...ROLLBACK`) e confirmar que o
dono da clínica A lê 0 linhas da clínica B.

### 1.3 pgcrypto para colunas ultra-sensíveis — análise honesta

`pgcrypto` já vem disponível no Supabase. **Mas atenção à arquitetura antes de
adotar:** o front fala **direto** com o Postgres (PostgREST + RLS). Se a chave de
criptografia ficar no banco (numa tabela ou GUC), quem obtiver acesso ao banco
obtém a chave junto — a criptografia viraria teatro. E a chave **nunca** pode ir
ao front. O desenho que faz sentido aqui:

- **Chave em variável de ambiente de Edge Function** (fora do banco);
- Leitura/escrita do campo criptografado **só via Edge Function** (o app não
  faz mais SELECT direto dessa coluna);
- Colunas candidatas: `pacientes.cpf`, `pacientes.anamnese` (dado de saúde
  Art. 11 LGPD). Trade-off real: perde busca/índice por CPF (o casamento por CPF
  do agendamento online teria que virar comparação de HMAC determinístico).

```sql
create extension if not exists pgcrypto;

-- Na Edge Function (Deno), a chave vem de Deno.env.get('COLUMN_KEY') e é
-- passada como parâmetro da RPC — jamais gravada no banco:
create or replace function public.cpf_criptografar(p_cpf text, p_key text)
returns bytea language sql
set search_path = ''
as $$ select extensions.pgp_sym_encrypt(p_cpf, p_key) $$;

create or replace function public.cpf_descriptografar(p_blob bytea, p_key text)
returns text language sql
set search_path = ''
as $$ select extensions.pgp_sym_decrypt(p_blob, p_key) $$;

-- Busca por igualdade sem descriptografar: índice sobre HMAC determinístico
alter table public.pacientes add column cpf_hmac bytea;
create index on public.pacientes (clinica_id, cpf_hmac);
-- cpf_hmac = extensions.hmac(cpf_normalizado, p_key_hmac, 'sha256')
```

**Recomendação:** hoje o risco residual é baixo (RLS sólida + criptografia at
rest do Supabase + bucket privado). Só vale pagar o custo de complexidade se
(a) alguma clínica/contrato exigir criptografia por coluna, ou (b) o projeto for
para plano Pro e quiser defesa contra vazamento de backup. Se for fazer, é uma
migração **aditiva** (coluna nova + backfill + só depois desligar a antiga) —
nunca converter in-place. **Não implementar sem decisão do dono.**

---

## 2. Front-end (HTML/JS sem build + TypeScript nas Edge Functions)

### 2.1 XSS — o contrato do projeto

O front injeta HTML com template literals + `innerHTML` (~170 usos). O contrato,
já seguido no código e agora vigiado pelo CI (`xss-audit`):

1. **TODO dado que veio de usuário/banco passa por `esc()`** (`index.html`,
   `agendar.html`, `profissional.html`) **ou `escapeHtml()`** (`dashboard`)
   antes de entrar em qualquer template que vá para `innerHTML` /
   `insertAdjacentHTML` / `outerHTML` / `document.write`. Isso inclui campos
   "inocentes": nome, whatsapp, observações, convênio, categoria de estoque,
   comentário de NPS, motivo de despesa — inclusive **derivados** (iniciais,
   substrings): em 2026-07-08 corrigimos `iniciaisDe(p.nome)` no portal por isso.
2. **Atributos de evento** (`onclick="fn('${x}')"`) só recebem **ids gerados
   pelo banco (uuid)** ou constantes — nunca texto livre. Se precisar passar
   texto, use `data-*` + `dataset` no handler.
3. **Preferir `textContent`** quando não há markup (já é o padrão em toasts,
   labels e afins — 168 usos).
4. **URLs**: interpolar com `encodeURIComponent(...)` (padrão já usado em
   `wa.me`, QR e ICS).
5. O painel admin **não é exceção**: nome de clínica é input de cliente — um
   nome malicioso executando no `nastaclin-admin` seria XSS na sessão do admin.
   O `dashboard` já escapa com `escapeHtml()`; manter.

### 2.2 Sessão e tokens — a resposta honesta sobre HttpOnly/Secure/SameSite

A autenticação é **Supabase Auth via supabase-js**, que guarda o JWT (access +
refresh token) em **`localStorage`** — não em cookie. Portanto **as flags
HttpOnly/Secure/SameSite não se aplicam a esta arquitetura**: não existe
servidor próprio para setar cookie de sessão (o front é estático na Vercel).
Colocar o token em cookie HttpOnly exigiria uma camada servidor (BFF/proxy) que
o produto não tem — e não recomendo criar uma só para isso agora.

O que isso significa e como mitigamos:

- **Risco:** XSS bem-sucedido rouba o token do `localStorage`. Logo, a defesa
  nº 1 de sessão aqui É a disciplina anti-XSS da seção 2.1 + CI.
- **Mitigações ativas:** access token de curta duração com refresh rotativo
  (padrão Supabase); **2FA TOTP** opt-in (existe desde 2026-07-03 — ativar na
  conta admin!); senha forte forçada; headers da seção 2.3.
- **CSRF:** não aplicável ao modelo token-em-header (`Authorization: Bearer`) —
  cookie é que é enviado automaticamente pelo navegador, header não. Os webhooks
  públicos (Cakto) validam secret fail-closed.
- **Se um dia houver camada servidor**, o padrão correto é:
  `Set-Cookie: sb-token=...; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=3600`
  (`SameSite=Strict` para o painel admin).

### 2.3 Headers HTTP (aplicado) + CSP (draft, ativar depois de validar)

Aplicado no `vercel.json` dos dois sites (rota `continue: true` no topo, padrão
do config legado com `routes`):

- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY` (nenhuma página é embutida em iframe — anti-clickjacking)
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy: geolocation=(), microphone=(), camera=(), payment=()`
  (Jitsi abre em aba própria de meet.jit.si — não é afetado)
- `Strict-Transport-Security: max-age=31536000; includeSubDomains`

**CSP — NÃO aplicada ainda de propósito.** O front é um monólito com script/style
inline (exige `'unsafe-inline'`) e qualquer origem esquecida quebraria fluxo de
cliente (regra de ouro). Draft para ativar numa entrega dedicada, primeiro em
`Content-Security-Policy-Report-Only`, validando com a suíte Playwright:

```
default-src 'self';
script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://js.hcaptcha.com https://*.hcaptcha.com;
style-src 'self' 'unsafe-inline' https://fonts.googleapis.com;
font-src https://fonts.gstatic.com;
img-src 'self' data: blob: https://api.qrserver.com;
connect-src 'self' https://*.supabase.co wss://*.supabase.co https://*.hcaptcha.com;
frame-src https://*.hcaptcha.com;
base-uri 'self'; form-action 'self'; frame-ancestors 'none'; object-src 'none'
```

(Mesmo com `'unsafe-inline'`, a CSP já bloqueia exfiltração via `connect-src` e
script externo injetado — vale a entrega.)

---

## 3. Automação de segurança no GitHub

`.github/workflows/security.yml` (idêntico nos 2 repos) roda em todo push na
`main`, em todo PR e manualmente:

| Job | Ferramenta | O que pega | Política |
|---|---|---|---|
| `secret-scan` | **gitleaks** (binário pinado v8.21.2) | credencial/chave no working tree **e no histórico do git** (`fetch-depth: 0`) | falha em qualquer achado |
| `sast` | **semgrep** `p/security-audit` | SAST das edge functions (TS/Deno), SQL, JS | falha em severidade ERROR (validado: repo atual = 0) |
| `xss-audit` | script próprio `.github/scripts/xss_audit.py` | interpolação nova sem `esc()`/`escapeHtml()` perto de sink de HTML | falha em achado fora do baseline (`.github/xss-baseline.json`) |
| `js-syntax` | `.github/scripts/check_inline_js.py` + `node --check` | erro de sintaxe nos `<script>` inline (o front não tem build que pegaria isso) | falha em erro |
| `dep-audit` | **npm audit** `--audit-level=high` | vulnerabilidade em dependência JS/TS | hoje é no-op (não há `package.json` — front sem build); liga sozinho se um entrar |

Complementos fora do Actions (1 clique, feitos pelo dono no GitHub →
Settings → Code security): **Secret scanning + Push protection** e **Dependabot
alerts** — grátis (em repo público, e nos privados conforme o plano).

---

## 4. Gestão de segredos — checklist

**Estado (varreduras de 2026-07-07 e 2026-07-08):** nenhum segredo hardcoded no
código nem no histórico do git. O único material no front é a chave **`anon`**
do Supabase — **pública por design** (a segurança é o RLS + Auth, não o sigilo
da chave). Não confundir com a `service_role`, que nunca pode aparecer no front.

Checklist permanente:

- [x] `service_role` **só** em env de Edge Function (`Deno.env.get(...)`), nunca no repo.
- [x] Chaves Anthropic/Evolution em env das Edge Functions.
- [x] Secrets de webhook (Cakto/hCaptcha) em `admin_config` — tabela com RLS
      **sem policy = deny-all** para navegador; só service_role lê.
- [x] Webhooks públicos **fail-closed**: sem secret configurado → recusa
      (`cakto-webhook` v4, `mercadopago-webhook` v5).
- [x] gitleaks no CI (working tree + histórico) a cada push/PR.
- [ ] **Dono:** ativar Push Protection no GitHub (bloqueia o push que contém segredo).
- [ ] **Dono:** tornar os 2 repos **privados** (recomendação em aberto desde 2026-07-07).
- [ ] **Dono:** ativar o **2FA** (já existe no app) na própria conta admin.
- [ ] **Se um segredo vazar:** rotacionar na origem (Supabase/Anthropic/Evolution/
      Cakto) **imediatamente** — remover do git não basta (histórico/forks/caches);
      depois limpar histórico com `git filter-repo` e forçar push.
- [ ] **Nunca** colocar segredo em: front (`*.html`), `config.toml`, migrations,
      CLAUDE.md/SECURITY.md, mensagens de commit.

---

## 5. Plano de ação (ordem recomendada)

1. **Feito nesta entrega:** CI de segurança nos 2 repos + headers HTTP no Vercel
   + fix do escape das iniciais no portal + este playbook.
2. **Dono (5 min cada):** repos privados · Push Protection + Dependabot alerts ·
   2FA na conta admin.
3. **Próxima entrega dedicada:** CSP em Report-Only → validar com a suíte
   Playwright → enforce.
4. **Sob demanda/contrato:** pgcrypto em `pacientes.cpf`/`anamnese` via Edge
   Function (seção 1.3) — decisão do dono.
5. **Contínuo:** toda tabela nova nasce com o template RLS da seção 1.2; toda
   função nova com `SET search_path` e escrita com `WITH CHECK`; todo dado novo
   renderizado passa por `esc()` (o CI vigia).
