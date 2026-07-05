<!--
═══════════════════════════════════════════════════════════════════════════
🔒 SEÇÃO FIXA — NÃO ALTERAR (LER PRIMEIRO)
═══════════════════════════════════════════════════════════════════════════

Para o assistente (Claude) que abrir este repositório:

Este arquivo é a MEMÓRIA / CONTEXTO PERMANENTE da ferramenta. Ele existe porque
o dono troca de conversa de tempos em tempos (o chat fica pesado), e cada chat
novo começa "do zero". Em vez de o dono ter que reexplicar o que é a ferramenta,
pra que serve e como ela funciona toda vez, este arquivo guarda TUDO isso.

Então, ao iniciar qualquer trabalho aqui:
  1. LEIA este arquivo inteiro antes de mexer em qualquer coisa. Ele te dá todo
     o contexto que um chat anterior já tinha.
  2. Existe uma cópia IDÊNTICA deste arquivo nos dois repositórios da ferramenta:
        • nastadesk  (o app das clínicas)
        • dashboard  (o painel admin "nastaclin-admin")
     Os dois descrevem o sistema inteiro de propósito.
  3. SEMPRE QUE FIZER QUALQUER ALTERAÇÃO na ferramenta (código, banco, deploy,
     preços, regras de negócio, features), ATUALIZE este arquivo na mesma hora:
        • ajuste a seção correspondente abaixo;
        • adicione uma linha no "Histórico de mudanças";
        • replique a mesma atualização no CLAUDE.md do OUTRO repositório, para os
          dois ficarem sempre iguais.
  4. NÃO coloque dados sensíveis aqui (IDs de projeto, e-mails, tokens, chaves,
     segredos). Este arquivo fica versionado no repositório.

Tudo que está ABAIXO desta seção fixa é "vivo" — pode e deve ser atualizado.
Esta seção fixa (entre os marcadores 🔒) NÃO deve ser alterada.
═══════════════════════════════════════════════════════════════════════════
-->

# NastaDesk — Contexto da ferramenta

> Documento de contexto mantido para continuidade entre chats. Última atualização: **2026-07-04**.

> ⭐ **COMO O DONO GOSTA DE TRABALHAR (ler sempre, vale para qualquer chat):**
> - **Pode deixar as melhorias APARENTES para os clientes.** A intenção é que eles
>   percebam que tem gente de verdade trabalhando no produto por eles — que há
>   "seres humanos por trás". **Não precisa esconder** as mudanças ("clínica não vê
>   diferença" não é uma meta; é só uma garantia de segurança quando aplicável).
> - **Liberdade total no visual/UI:** pode alterar layout, textos, telas, estilo,
>   cores, adicionar telas/avisos. Ouse no visual.
> - **NUNCA faça nada que prejudique os clientes.** Especialmente: **não** mexer na
>   agenda a ponto de embaralhar/perder horários; **não** vazar/expor dados de um
>   cliente para outro; **não** excluir/perder dados, pacientes, consultas ou
>   qualquer coisa que já é deles. Mudança em dado só se for **aditiva e reversível**.
> - **Regra de ouro:** _ouse no visual, seja conservador com os dados._ Se algo tem
>   risco de vazar/apagar/embaralhar dado de cliente, **pare e pergunte antes.**

> 📌 **REGRA OBRIGATÓRIA DE REGISTRO (o dono pediu explicitamente em 2026-07-03):**
> **TUDO que você fizer na ferramenta tem que ser registrado NESTE arquivo** — é
> aqui que o dono e os próximos chats descobrem o que existe. Não confie na memória:
> **se não está escrito aqui, para os outros chats é como se não existisse.**
> - **No começo de QUALQUER trabalho:** leia este arquivo inteiro (é o mapa do que já
>   existe) e, se for mexer em algo grande, **confira também as branches remotas e o
>   banco de produção** — porque um chat pode ter feito algo e esquecido de anotar.
> - **Ao terminar QUALQUER coisa** (código, banco/migration, edge function, deploy,
>   preço, regra): atualize a seção certa + adicione linha no Histórico (seção 9) +
>   **replique no CLAUDE.md do outro repo** (têm que ficar idênticos).
> - **Registre até o que NÃO foi deployado ainda** (tabela criada no banco, feature
>   numa branch, migration aplicada). ⚠️ **Foi exatamente isso que deu errado:** a
>   branch `financial-phase-2` criou tabelas fiscais/financeiras no banco de produção
>   e **não anotou aqui** → um chat seguinte quase construiu tudo duplicado. Nunca mais.

## 1. Visão geral

**NastaDesk** é um SaaS (software por assinatura) de **gestão para clínicas**, com
foco em **clínicas de fisioterapia**. É um painel web onde a clínica organiza
agenda, pacientes, financeiro e atendimento por WhatsApp.

- Marca / criadora: **Nastaclin**.
- Modelo de negócio: **assinatura mensal** por clínica (multi-tenant — cada
  clínica tem seus próprios dados, isolados das outras).
- Dois públicos / dois produtos (ver seção 2).

## 2. Os dois produtos / repositórios

A ferramenta é composta por **dois sites**, que conversam com o **mesmo backend**:

| Repositório | É | URL pública | Quem usa |
|---|---|---|---|
| **nastadesk** | O **app das clínicas** (painel da clínica + página pública de agendamento) | `nastadesk.vercel.app` | As clínicas clientes |
| **dashboard** | O **painel administrativo** ("nastaclin-admin") | `nastaclin-admin.vercel.app` | Só o dono (admin) |

> Importante: o **painel admin é só do dono** — nenhuma clínica/cliente acessa
> ele. Mudanças no `dashboard` não afetam os clientes. Já o `nastadesk` é o que
> os clientes usam de verdade — mexer ali exige cuidado.

## 3. Stack / arquitetura

- **Front-end:** HTML/CSS/JS puro, sem build. Cada site é basicamente um
  `index.html`. Hospedado na **Vercel** (deploy automático a partir do branch
  `main` de cada repositório).
- **Back-end:** **Supabase** (Postgres + Auth + Edge Functions), uma **única
  instância compartilhada** pelos dois sites.
- **WhatsApp:** integração via **Evolution API** (uma instância por clínica).
- **IA do chatbot:** **Claude (Anthropic)**, modelo **Haiku 4.5**, chamado pela
  Edge Function do webhook do WhatsApp.
- **Pagamentos / assinaturas:** **Cakto** (assinatura mensal, checkout hospedado por plano + webhook `cakto-webhook`). O **Mercado Pago foi substituído** e está **dormindo**: as funções continuam no código, mas o app não cria mais cobranças no MP. Mapeamento comprador→clínica é **por e-mail**; o secret do webhook fica em `admin_config` (`cakto_webhook_secret`).
- Segredos (chaves de API etc.) ficam em **variáveis de ambiente** das Edge
  Functions — nunca no front.

### Edge Functions (no Supabase)

| Função | Papel |
|---|---|
| `whatsapp-webhook` | Cérebro do chatbot. Recebe eventos da Evolution API, roda o bot (menus + IA) e responde. Registra o consumo de tokens da IA por clínica. |
| `whatsapp-enviar` | Envio de mensagens pelo WhatsApp. |
| `whatsapp-conexao` | Gerencia a conexão/instância da clínica na Evolution. |
| `lembretes-auto` | Lembretes automáticos (disparados por cron a cada 10 min). |
| `mercadopago-checkout` | Cria checkout de assinatura no Mercado Pago. *(sendo aposentada — migração p/ Cakto)* |
| `mercadopago-webhook` | Recebe eventos de cobrança do Mercado Pago. *(sendo aposentada — migração p/ Cakto)* |
| `cakto-webhook` | Recebe eventos da Cakto (compra aprovada, assinatura criada/renovada/cancelada, reembolso, chargeback) e libera/suspende o acesso da clínica. Mapeia o comprador pelo **e-mail**, identifica o plano pelo **valor** (97/197/347) e **nunca derruba clínica em cortesia**. |
| `agendar-publico` | Porteiro anti-robô do agendamento online. Recebe o booking + token do hCaptcha, verifica o token no servidor (secret em `admin_config`) e, se válido, delega à RPC `agendar_online` — repassando também a **versão do consentimento LGPD + IP** para registro. `verify_jwt=false`. |
| `equipe-criar` | Cria o login de um funcionário da clínica. Só o **dono** chama (valida o JWT → `clinicas.user_id`), **trava por plano** (Profissional+), cria o usuário de auth (service_role, `user_metadata.tipo='membro'`) e vincula em `clinica_membros`. Para papel `profissional`, **exige e valida** o `profissional_id` (tem que ser da própria clínica) — é o vínculo que define o que a pessoa vê no portal. `verify_jwt=true`. *(v2 com essa validação de vínculo ainda NÃO redeployada — ver Histórico 2026-07-05; o front já exige o vínculo, então não é brecha.)* |
| `equipe-remover` | Exclui o login de um funcionário. Só o **dono** chama; remove o vínculo em `clinica_membros` e apaga o usuário de auth (libera o email). `verify_jwt=true`. |
| `admin-api` | Backend do painel admin. Valida que quem chama é o admin e só então lê todas as clínicas/assinaturas e roda ações administrativas com a service_role. |

## 4. Funcionalidades do app (nastadesk)

- **Agenda do dia** — consultas em tempo real, status, métricas, mini-calendário.
- **Agendamentos** — grade semanal (desktop) e lista (mobile); remarcar/excluir.
- **Agendamento online** — link público `/agendar/<slug>` para o paciente marcar
  sozinho, com QR Code. Coleta nome, WhatsApp e **CPF** (obrigatório, validado com
  dígitos verificadores); passa pelo **hCaptcha** (edge function `agendar-publico`)
  e usa RPCs públicas (`clinica_publica`, `horarios_ocupados`, `agendar_online`) que
  validam tudo no servidor. O paciente é **casado por CPF** (evita duplicados) e a
  clínica vê se é **novo ou recorrente** (etiqueta na agenda + alerta), com aviso de
  **possível cadastro duplicado**. Exige **consentimento LGPD** (checkbox obrigatório,
  registrado na tabela `consentimentos` com data/hora/versão/IP).
- **Salas / salões de atendimento** — organizar consultas por sala, além de
  data/horário.
- **Lembretes WhatsApp** — mensagens prontas (confirmação, véspera, dia) com
  envio em 1 clique (via `wa.me`), além dos lembretes automáticos.
- **Pacientes** — ficha completa: anamnese, evoluções, histórico, convênio, CPF;
  **modalidade** (Fisio/Pilates/…) e **cobrança** (mensalidade fixa OU por sessão,
  com valor e dia de vencimento); importação/exportação por CSV. **Portal do titular
  (LGPD)** na ficha: exportar todos os dados do paciente (JSON) e eliminar os dados
  pessoais mantendo o financeiro de-identificado; **trilha de auditoria** (registro
  de acessos LGPD: quando a ficha é aberta/editada/exportada/eliminada).
- **Modalidades** — lista configurável de tipos de atendimento (Fisioterapia,
  Pilates, RPG…), com cor por modalidade. Vira etiqueta no paciente, na agenda do
  dia e no financeiro, e dá pra filtrar pacientes por modalidade. Gerenciada em
  Configurações → Modalidades (cada clínica já nasce com Fisioterapia + Pilates).
- **Profissionais + logins de equipe** (multi-profissional) — **recurso do plano
  Profissional+** (no Básico a aba fica escondida). Lista configurável de quem atende
  (nome, registro/CREFITO, cor), em Configurações → Profissionais: etiqueta colorida na
  Agenda do dia e na grade semanal, filtro por profissional, select no agendamento e
  reatribuição inline. **Logins da equipe:** o dono cria acessos (email+senha) com papel
  **Recepção** (usa o painel: agenda/pacientes/financeiro/lembretes) ou **Profissional**
  (usa o **Portal do Profissional** — ver abaixo). Cada funcionário entra com o próprio
  login e vê **só os dados da clínica dele** (RLS + `clinica_ids_membro()`). Tabela
  `clinica_membros` + edge function `equipe-criar` (só o dono cria; trava por plano no
  servidor; papel profissional exige vínculo com um profissional cadastrado).
  **Aditivo:** clínica sem funcionário cadastrado não vê diferença.
- **Portal do Profissional** (`profissional.html`, rota `/profissional`) — front
  **separado e restrito** para o papel `profissional` (o login desse papel é
  redirecionado para lá; recepção/dono continuam no painel). O profissional vê
  **apenas as próprias consultas e os pacientes que ele atende**: abas **Hoje**
  (status Confirmar/Chegou/Atendido/Cancelar), **Agenda** (14 dias) e **Meus
  pacientes** (busca), ficha do paciente **somente leitura** + **evoluções**
  (ler/registrar), trilha de auditoria LGPD e realtime. **Sem financeiro, sem
  valores, sem excluir nada.** A garantia real é no **banco** (RLS por papel —
  migration `20260704180000_portal_profissional_rls.sql`): consultas SELECT/UPDATE
  só as dele; pacientes SELECT-only de quem tem consulta com ele; evoluções
  SELECT/INSERT; modalidades/profissionais/salas SELECT; **nenhum acesso** a
  mensalidades/pacotes/despesas/conversas/mensagens/lembretes/alertas/
  configurações/whatsapp; **nenhum DELETE**. **A migration já está APLICADA em
  produção e o front no ar** (ver Histórico 2026-07-05). No card "Logins da equipe"
  o dono vincula/edita o profissional de cada login (o vínculo é o que liga o portal
  aos dados certos; sem vínculo a pessoa não vê nenhum paciente).
- **Pacotes de sessões** — venda/controle de pacotes de sessões.
- **Financeiro** — **(a) por consulta** (inalterado): valor por consulta, registro
  de pagamento (Pix, cartão, dinheiro…), recibo em PDF, faturamento do mês;
  **(b) Mensalidades** (novo): cobrança recorrente por paciente (valor + dia de
  vencimento), controle **pago / pendente / vencido** mês a mês com histórico. A aba
  "Mensalidades" abre as cobranças do mês automaticamente e marca pago em 1 clique.
  **(c) Repasse** (novo): comissão por profissional (% do valor OU valor fixo por
  consulta), calculada sobre as consultas *atendidas* do mês, em Financeiro → Repasse.
  **(d) Despesas / contas a pagar + fluxo de caixa + DRE** (novo): aba **Financeiro →
  Despesas** — cadastro de despesas por categoria (aluguel, luz, materiais…), com
  vencimento, status **paga/pendente/vencida** (1 clique) e opção de **repetir nos
  próximos meses**; cards de **Entradas / Saídas / Saldo do mês (caixa) / A pagar**;
  **Resumo do mês (DRE simples)** — entradas − despesas por categoria = resultado; e
  **export CSV**. Usa a tabela `despesas` que já existia em produção (schema
  `competencia` + `status`). O financeiro por consulta/mensalidade/repasse é inalterado.
- **Nota fiscal / recibo** — **Recibo de pagamento em PDF** (botão na consulta,
  **mensalidade e pacote** pagos) — **não exige CNPJ**, serve para pessoa física/autônomo.
  O recibo mostra os **dados do emissor** (CPF/CNPJ + registro profissional CREFITO/CRM,
  editáveis em **Minha Clínica → Dados para o recibo**, guardados em `clinicas.recibo_cpf_cnpj`
  e `clinicas.recibo_registro`), o **CPF do paciente** e uma nota de que **serve para dedução
  no Imposto de Renda** (despesa médica) do paciente. A **NFS-e** (nota fiscal eletrônica de
  verdade) exige **CNPJ** (ou inscrição municipal de autônomo) — por isso fica como recurso
  **opcional/futuro** para clínicas que tenham CNPJ/MEI; o dono hoje **não tem CNPJ**, então o
  caminho é o **recibo**. (Tabelas `config_fiscal`/`notas_fiscais` existem no banco, mas a
  emissão via Focus NFe **não foi deployada** — depende de CNPJ.)
- **App instalável (PWA)** — o `nastadesk` é um **PWA**: dá pra "instalar" no celular
  (ícone na tela inicial, abre em tela cheia) e no desktop. `manifest.json` + ícones +
  service worker com estratégia **network-first no HTML** (online sempre pega a versão
  nova; cache só como rede de segurança offline — não "congela" a clínica numa versão
  velha). Botão flutuante **"Instalar app"** aparece quando o navegador sinaliza que é
  instalável.
- **Relatório mensal** — comparecimento, faturamento, origem dos agendamentos,
  formas de pagamento.
- **Chatbot de WhatsApp** — ver seção 6.
- **Conta** — onboarding guiado, recuperação de senha, configuração de horários
  e mensagens. **Privacidade e segurança** (em Minha Clínica): **verificação em duas
  etapas (2FA/TOTP)** opt-in (Supabase Auth nativo, com desafio no login) e **aceite
  do DPA** (contrato de operador — página `dpa.html`, registrado em `consentimentos`).

## 5. Planos, preços e acesso

### Preços (assinatura mensal por clínica)

| Plano | Preço/mês | Observações |
|---|---|---|
| **Básica** | **R$ 97** | Gestão + lembretes manuais por WhatsApp. **Sem chatbot de IA. Sem multi-profissional/logins de equipe** (1 login, o dono). |
| **Profissional** | **R$ 197** | Inclui o **chatbot de WhatsApp com IA** + **vários profissionais e logins de equipe** (recepção/profissional). |
| **Premium** | **R$ 347** | Tudo do Profissional (tier mais alto). |

### Regra de acesso (paywall + cortesia)

- Ao se cadastrar, a clínica **NÃO entra de graça automaticamente** (paywall no
  cadastro).
- O "porteiro" de acesso é o campo **`clinicas.ativo`**. Só com `ativo = true` a
  clínica usa o sistema.
- O acesso é liberado de duas formas:
  - **Cortesia** — o admin concede acesso grátis controlado (pode ter data de
    expiração, `cortesia_expira_em`). Feito pelo painel admin.
  - **Assinatura paga** — via **Cakto** (botões "Assinar/Upgrade" abrem o checkout
    da Cakto com o e-mail da conta pré-preenchido; o `cakto-webhook` libera o acesso).
- O admin também pode **remover acesso** pelo painel.

## 6. Chatbot de WhatsApp (detalhe)

- **Exclusivo dos planos Profissional e Premium**, e exige `ativo = true`. No
  plano Básica o WhatsApp serve **só** para os lembretes manuais (via `wa.me`) —
  o bot não recebe nem responde, evitando custo de IA.
- **Multi-tenant:** cada clínica tem sua instância na Evolution API; o webhook
  resolve a clínica pelo `webhook_token` (ou pela instância).
- **Bot híbrido:** primeiro tenta menus determinísticos e palavras-chave
  (1 = agendar, 2 = confirmar/cancelar, 3 = dúvidas, 4 = atendente). Texto livre
  cai na **IA (Claude Haiku 4.5)**, que responde dúvidas (FAQ da clínica) e
  decide a intenção via *tool use* (agendar / minhas consultas / falar com
  atendente / responder).
- **Segurança de dados:** as RPCs do bot (`bot_slots_livres`, `bot_agendar`,
  `bot_proxima_consulta`, etc.) validam datas, horários livres e duplicidade no
  banco — mesmo que a IA escolha argumentos errados, o banco rejeita.
- **Custo da IA:** cada chamada ao Claude grava o consumo de tokens por clínica
  na tabela `ia_uso` (ver seção 7). O registro é tolerante a falhas: se a
  gravação falhar, o bot responde normalmente assim mesmo.

## 7. Painel admin (dashboard / nastaclin-admin)

Seções:
- **Visão geral** — clientes ativos, MRR (receita recorrente das assinaturas
  ativas), custos mensais e margem.
- **Clientes** — todas as clínicas com plano, status (Ativa / Cortesia / Sem
  plano / Suspensa), status da assinatura e receita/mês.
- **Assinaturas** — concede cortesia e remove acesso (via RPCs admin que só
  rodam com service_role, nunca pelo navegador).
- **Custos** — quanto o dono gasta por mês com o "stack", conforme o nº de
  clínicas ativas. Cada ferramenta tem um modelo de cálculo, editável:

  | Ferramenta | Modelo de custo |
  |---|---|
  | Supabase | fixo (hoje desativado / free tier) |
  | Vercel | fixo (hoje desativado / Hobby) |
  | Mercado Pago | % sobre a receita (taxa ~4,98%) |
  | Servidor Evolution/WhatsApp (DigitalOcean) | faixas por nº de clínicas (RAM cresce com a base) |
  | **API Claude / Anthropic** | **uso REAL por cliente** (ver abaixo) |

### Custo real da API Claude por cliente

O card "API Claude / Anthropic" mostra o **gasto real**, não uma estimativa:
- Lê a tabela `ia_uso` (consumo de tokens por clínica no mês corrente) e calcula
  o custo: Haiku 4.5 a **US$ 1 / 1M tokens de entrada** e **US$ 5 / 1M de saída**.
- Converte para R$ usando **câmbio US$→R$ ao vivo** (a `admin-api` busca a cotação
  em fontes gratuitas em cascata: AwesomeAPI → open.er-api → Frankfurter, com
  cache de 10 min; o painel atualiza a cada 10 min). Há um câmbio manual de
  fallback caso todas as fontes falhem.
- Mostra, por cliente: tokens de entrada/saída, custo em US$ e em R$ no mês.
- **Não há histórico anterior** ao início do rastreio (deploy em 2026-06-29): o
  gasto real só conta a partir daí.

## 8. Estado atual / o que está no ar

- App das clínicas e painel admin **em produção** na Vercel.
- Backend Supabase em produção (uma instância compartilhada).
- **2 clínicas clientes** usando a ferramenta (na época deste registro).
- Rastreio de custo real da IA (`ia_uso` + registro no webhook + card no painel)
  **deployado e ativo** desde 2026-06-29.

## 9. Histórico de mudanças

> Adicione aqui toda alteração relevante (mais recente no topo).

- **2026-07-05** — **Portal do Profissional em PRODUÇÃO (migration aplicada + front no ar) + botão de vincular profissional aos logins.**
  Fechei o que faltava da entrega de 2026-07-04 (o dono vinculou os conectores Supabase/Vercel). **(1) Migration `portal_profissional_rls` APLICADA no Supabase de produção** (`apply_migration`), depois de **testar com JWT simulado + ROLLBACK** contra os dados reais: profissional **com vínculo** vê só os 2 pacientes/2 consultas dele (a clínica tem 5/10) e **0** em financeiro/despesas/conversas/config; profissional **sem vínculo** vê **0**; **recepção** continua vendo tudo (5/10); **reatribuir** consulta p/ outro profissional é **bloqueado** (RLS 42501); mudar status da própria consulta é permitido. Advisors de segurança **sem regressão** (só os WARNs pré-existentes de funções DEFINER + o "leaked password" que exige Pro). **(2) Front mergeado na `main`** dos 2 repos (fast-forward) → Vercel publicou; confirmado que `nastadesk.vercel.app/profissional.html` está no ar. **(3) Novo: botão vincular/editar profissional** no card "Logins da equipe" (`vincularMembro` — o dono edita `clinica_membros.profissional_id` direto pelo navegador via RLS, sem edge). Resolve os **logins de profissional que ficaram sem vínculo** (após a migration eles não veem paciente até serem vinculados — comportamento correto). **Validado:** `node --check` + **51 testes de navegador** (40 da suíte do portal + 11 do novo botão), zero erro de JS. **(4) Pendências não-bloqueantes** (o conector Supabase caiu no meio e não voltou de forma estável): re-deploy da edge **`equipe-criar` v2** (validação de vínculo no servidor — o front já exige, então não é brecha) e **revogar `execute` do `anon`** em `meu_profissional_id`/`clinica_ids_recepcao`/`pacientes_do_profissional` (cosmético — retornam vazio p/ não-logado, não vazam nada; a irmã `clinica_ids_membro` não tem grant p/ anon, é só padronizar).
- **2026-07-04** — **Portal do Profissional + RLS restrito por papel (profissional passa a ver SÓ o que é dele).** ⚠️ **NADA disto está em produção ainda — esta sessão não tinha acesso ao Supabase/MCP. Ver o "Falta" no fim (a MIGRATION É O ITEM DE SEGURANÇA).**
  A pedido do dono: *"o profissional consegue ver os clientes que a clínica tem, consegue excluir clientes… quero que vejam apenas as pessoas que eles vão atender; monte um front-end diferente para os profissionais."* De fato, as policies de membro (20260704140000) davam ao papel `profissional` **ALL nas 15 tabelas** — via API dava para ver TODOS os pacientes e até excluir; o front só escondia telas. Entregue nesta sessão (branch `claude/professional-access-limits-bzloau` dos 2 repos):
  **(1) DB — migration `20260704180000_portal_profissional_rls.sql` (arquivo no repo; ⚠️ NÃO aplicada em produção):** as policies `*_membros` passam a valer **só para a recepção** (nova `clinica_ids_recepcao()` — recepção fica exatamente como era; dono intocado). O papel `profissional` ganha policies mínimas: `consultas` **SELECT/UPDATE só as dele** (nova `meu_profissional_id()`; WITH CHECK impede reatribuir p/ outro profissional/clínica; sem INSERT/DELETE), `pacientes` **SELECT-only** de quem tem consulta com ele (nova `pacientes_do_profissional()`), `evolucoes` SELECT/INSERT dos pacientes dele (sem editar/apagar histórico), `modalidades`/`profissionais`/`salas` SELECT; **resto (financeiro, conversas, mensagens, lembretes, alertas, configuracoes, despesas, whatsapp_conexoes): nenhum acesso. Nenhum DELETE em nada.** Profissional sem vínculo (`profissional_id` nulo) não vê nada. Bônus: `registrar_auditoria` agora resolve **dono OU membro** → a trilha LGPD passa a registrar o funcionário certo (antes só registrava o dono). 100% aditivo/reversível (só policies e funções; zero dado tocado).
  **(2) Front novo `profissional.html` — "Portal do Profissional"** (rota `/profissional` no `vercel.json`): página própria no visual da marca, mobile-first. Cartão de boas-vindas com nome/CREFITO/cor, abas **Hoje** (consultas dele com Confirmar/Chegou/Atendido ✓/Cancelar — cancelar pede confirmação e NÃO exclui), **Agenda** (próximos 14 dias agrupados por dia) e **Meus pacientes** (busca); ficha em slide-over **somente leitura** (aviso explícito) + histórico das consultas dele + **evoluções** (ler/registrar); auditoria fire-and-forget (`visualizou_ficha`/`registrou_evolucao`); realtime só das consultas dele; sem sessão → volta pro login; papel errado → volta pro index. Queries todas com `.eq('profissional_id', …)` (cinto e suspensório — a garantia é o RLS).
  **(3) `index.html`:** login com papel `profissional` **redireciona para o portal** (recepção/dono seguem no painel); card "Logins da equipe" reescrito (explica o portal e o acesso restrito) com **vínculo obrigatório** ao criar papel Profissional (hint dinâmico `atualizarHintEquipe()` + validação no `criarAcessoEquipe`).
  **(4) Edge `equipe-criar` (⚠️ v2 NÃO deployada):** exige `profissional_id` para papel profissional e **valida que pertence à própria clínica**.
  **Validado:** `node --check` (2 páginas) + **40/40 testes de navegador** (Playwright, Supabase mockado, zero rede real): sem sessão/recepção não entram no portal; sem vínculo vê aviso e faz zero query; TODAS as queries de consultas filtram por profissional_id; ficha sem inputs; evolução insere com clinica+paciente certos; update de status filtra id+profissional_id; **zero DELETE e zero "R$" no portal**; index redireciona profissional (e o portal abre em seguida), recepção fica e mantém Financeiro; gate do vínculo bloqueia SEM chamar a edge — **zero erro de JS**.
  ***Falta (fazer nesta ordem):*** **(a) APLICAR a migration `20260704180000` no Supabase — até lá o papel profissional CONTINUA com acesso total via API** (o portal sozinho é só visual); **(b)** re-deployar a edge **`equipe-criar`**; **(c)** merge do front na `main` (Vercel). *Obs.: profissionais já criados sem vínculo param de ver dados após a migration — vincular pelo card Logins da equipe.*
- **2026-07-04** — **Fix do login de profissionais (3 ajustes a pedido do dono após testar): funcionário caía no onboarding; botão ativar/desativar pouco clicável; faltava excluir.**
  **(1) Bug do onboarding (raiz + blindagem):** o gatilho `on_auth_user_created`/`criar_clinica_no_signup` criava uma **clínica vazia para todo usuário novo** — inclusive o funcionário criado via `equipe-criar` — que então virava "dono" dela e caía na tela de configurar clínica. **Corrigido:** migration `20260704160000_signup_nao_cria_clinica_para_membro.sql` (o gatilho **pula a criação** quando `user_metadata.tipo='membro'`; cadastro de dono comum fica idêntico) **+ limpeza das 2 clínicas órfãs vazias** já criadas (guarda: só apaga sem pacientes/consultas). **Blindagem no front:** `carregarDados` agora resolve **funcionário ANTES de dono** (mesmo que exista clínica órfã, cai na clínica certa) e `carregarInfoClinica` respeita o papel no rótulo do topo (não sobrepõe com "Plano X"). **(2) Botão claro:** a lista de "Logins da equipe" trocou a pílula por um botão **Desativar/Reativar** de verdade + status "● ativo/desativado". **(3) Excluir:** novo botão de lixeira + edge function **`equipe-remover`** (`verify_jwt=true`, só o dono; apaga o vínculo e o usuário de auth, liberando o email). **Validado:** `node --check` + **23/23 testes de navegador** (funcionário com clínica órfã NÃO vê onboarding e cai na clínica certa com papel Recepção; botões Desativar/Excluir presentes; excluir aciona a função; dono/recepção/profissional e gate por plano seguem ok) — **zero erro de JS**. Migration do gatilho e a edge `equipe-remover` **já em produção**.
- **2026-07-04** — **Fase 2 · Login de profissionais + papéis + trava por plano (Profissional+). Pix self-service ADIADO (ideia salva).**
  A pedido do dono: fechar a Fase 2 (login de profissionais) e **mudar o multi-profissional para Profissional+** (não mais liberado a todos). **Pix self-service: NÃO agora** — adiado, ideia salva na seção 10.4.
  **(1) DB (aditivo, aplicado em produção — isolamento validado com JWT simulado + ROLLBACK):** migration `20260704140000_login_profissionais_membros.sql` — tabela **`clinica_membros`** (clinica, user, papel recepcao/profissional, profissional_id opcional, ativo, unique(user_id)); função **`clinica_ids_membro()`** (SECURITY DEFINER — resolve as clínicas do funcionário sem cair no RLS da própria tabela); **políticas de membro ADITIVAS** (o dono mantém as policies antigas; o membro entra via OR) em 15 tabelas operacionais (pacientes, consultas, evolucoes, modalidades, profissionais, salas, mensalidades, pacotes, lembretes, conversas, mensagens, alertas, configuracoes, despesas, whatsapp_conexoes) + SELECT em `clinicas`. **`clinica_membros` nasce vazia → clínica atual não muda NADA.** Teste: funcionário de A vê os 5 pacientes de A e **0** de B; usuário aleatório vê **0**; dono continua igual. Advisors sem regressão crítica (a função nova cai só no mesmo aviso das outras DEFINER intencionais).
  **(2) Edge function `equipe-criar`** (`verify_jwt=true`): só o **dono** cria; **trava por plano no servidor** (recusa Básico); cria o usuário de auth (service role, `email_confirm`) e vincula em `clinica_membros`; desfaz o usuário se o vínculo falhar. *(Deploy do edge pode ter ficado pendente por instabilidade do MCP nesta sessão — conferir `list_edge_functions`; o código está no repo em `supabase/functions/equipe-criar/`.)*
  **(3) Front (`nastadesk/index.html`):** resolução da clínica no login **dono OU funcionário** (`carregarDados` tenta dono; se não, resolve via `clinica_membros`), globais `meuPapel`/`meuProfissionalId`, **gate de navegação por papel** (`gatearPorPapel` — recepção esconde Planos/Config/Minha Clínica; profissional esconde também Financeiro/Relatório/Conversas), e card **"Logins da equipe"** em Config → Profissionais (criar acesso + ativar/desativar). **Trava por plano:** feature `equipe` nos `PLANOS` (Básico não; Profissional/Premium sim) — no Básico a aba Config → Profissionais fica escondida. **Validado:** `node --check` + **17/17 testes de navegador** (dono vê tudo; recepção esconde Planos/Config/Perfil e mantém Financeiro; profissional esconde Financeiro/Relatório; Básico esconde a aba Profissionais; criar acesso limpa o form) — **zero erro de JS**. *Falta:* deploy do front na `main` (+ confirmar o deploy do edge `equipe-criar`).
- **2026-07-04** — **Recibo turbinado (sem CNPJ): dados do emissor (CPF + CREFITO), CPF do paciente, nota de IR e recibo p/ mensalidade e pacote.**
  A pedido do dono ("muda o sistema de notas fiscais — Focus exige CNPJ e eu não tenho"). Como NFS-e de verdade **exige CNPJ** (regra fiscal, sem contorno), o caminho sem CNPJ é o **Recibo**, agora enriquecido. **(1) Migration** `20260704120000_recibo_dados_emissor.sql` **aplicada em produção** (testada antes com ROLLBACK): 2 colunas nullable em `clinicas` — `recibo_cpf_cnpj` e `recibo_registro`. 100% aditiva. **(2) UI** — card **"Dados para o recibo"** em Minha Clínica (CPF/CNPJ do emissor + registro profissional CREFITO/CRM), com `salvarDadosRecibo()`/carregamento no perfil. **(3) Recibo** refatorado num gerador único `_abrirRecibo(dados)`: cabeçalho do emissor com **CPF/CNPJ + registro**, "Recebi de <paciente> (CPF …)", **nota de dedução no IR** (aparece só quando há CPF/CNPJ do emissor), assinatura com os dados. Novos botões de recibo em **mensalidade paga** (`gerarReciboMensalidade`) e **pacote pago** (`gerarReciboPacote`), além da consulta (`gerarRecibo`). CPF do paciente incluído nos selects de consultas/mensalidades/pacotes. **Validado:** `node --check` + **22/22 testes de navegador** (Playwright, Supabase mockado): recibo de consulta/mensalidade/pacote com CPF+registro do emissor e CPF do paciente, nota de IR presente/ausente conforme o CPF do emissor, e o form de Minha Clínica carrega/salva — **zero erro de JS**. *Falta:* deploy do front na `main`.
- **2026-07-03** — **Fase 2 · Paridade de mercado: PWA + Financeiro completo (Despesas/caixa/DRE) reconstruído na `main`. NFS-e → recibo (dono sem CNPJ).**
  Três frentes, tudo **deployado na `main`** (a pedido do dono: "faz o deploy de tudo").
  **(1) PWA instalável — DEPLOYADO** (PR #14). `manifest.json` + ícones PNG (192/512 + apple-touch 180, "N" branco em quadrado verde) + `sw.js` **network-first no HTML** (online sempre pega a versão nova — não congela a clínica; cache-first só nos ícones; não intercepta cross-origin; cache versionado). Metas de PWA no `<head>`, botão flutuante "Instalar app" (`beforeinstallprompt`) e **`vercel.json` corrigido** (publicava só `*.html`; add `manifest.json`/`sw.js`/`*.png`).
  **(2) Financeiro completo (Despesas + fluxo de caixa + DRE) — CONSTRUÍDO NA `main`, NÃO mergeei a branch velha.** Descobri que **as tabelas `despesas`/`despesas_recorrentes`/`config_fiscal`/`notas_fiscais` já existiam em produção** (criadas pela branch `claude/financial-phase-2-8q575q`, que **não registrou aqui** — daí a regra nova no topo). Essa branch está **16 commits atrás** da `main` e edita o mesmo `index.html`; **mergear ela apagaria da produção o LGPD/2FA/consentimento/CPF/hCaptcha/PWA** — inaceitável. Então **reconstruí o financeiro do zero em cima da `main` atual**, usando a tabela `despesas` que já está no banco (schema real: `competencia NOT NULL`, `status` pendente/pago). Entregue: 4ª aba **Financeiro → Despesas** (cards Entradas/Saídas/Saldo-caixa/A pagar; lista com categoria + status paga/pendente/vencida em 1 clique; modal criar/editar/excluir com "repetir nos próximos meses"; **DRE simples** por categoria; **export CSV**). **Nenhuma migration nova** (tabela já existe) e **nada apagado no banco**. A branch `financial-phase-2` fica como **referência/abandonada** (o front dela não sobe — conflitaria).
  **(3) NFS-e → recibo (sem CNPJ).** A emissão de NFS-e da branch antiga usa **Focus NFe, que exige CNPJ para criar conta** — e o **dono não tem CNPJ**. **Fato:** emitir NFS-e de verdade **exige CNPJ** (ou inscrição municipal de autônomo) — nenhum emissor contorna isso (é regra fiscal, não limitação de fornecedor). Então **NÃO deployei a NFS-e/Focus**; o caminho fiscal sem CNPJ é o **Recibo de pagamento em PDF** (já existe no app, botão na consulta paga). Recomendação registrada: se o dono quiser emitir nota de verdade, abrir **MEI** (grátis, dá CNPJ) — aí a NFS-e (que já tem tabelas no banco) pode ser ligada numa entrega futura. *Melhoria futura sugerida:* enriquecer o recibo (CREFITO/CPF do profissional p/ dedução de IR médico; recibo p/ mensalidade/pacote).
  **Validado:** `node --check` + **22/22 testes de navegador** (Playwright, Supabase mockado): aba Despesas, matemática do caixa (entradas 980 / saídas / saldo / a pagar), DRE (resultado do mês), toggle pago 1 clique, modais criar/editar/excluir — **zero erro de JS**. **Deploy:** PWA já na `main` (PR #14); financeiro na `main` no PR seguinte; painel admin (dashboard) também publicado.
- **2026-07-03** — **Fase 1 · LGPD (parte 2 — CONCLUI A FASE 1): Trilha de auditoria + 2FA (TOTP) + DPA como documento separado.**
  Os 3 itens que faltavam da Fase 1, de uma vez. **(1) Trilha de auditoria** — migration `20260703140000_lgpd_auditoria_dpa.sql` **aplicada em produção**: tabela **`auditoria`** (clinica/user/paciente, ação, data/hora, user-agent; RLS **só-leitura p/ o dono**, escrita só via função DEFINER — impede adulteração pelo navegador) + RPC **`registrar_auditoria`** (escopo por `auth.uid()`, valida que o paciente é da própria clínica; **tolerante a falha** — nunca trava a navegação). O front (`nastadesk/index.html`) registra, **fire-and-forget**, quando a ficha é **aberta / editada / evolução registrada / dados exportados / dados eliminados**, e exibe o **"Registro de acessos (LGPD)"** dentro da ficha (aba Dados). **(2) 2FA (TOTP)** — **opt-in**, Supabase Auth nativo. Card **"Privacidade e segurança"** em Minha Clínica: ativar (QR Code + chave + código de 6 dígitos), desativar, e **desafio no login** (modal `modal-mfa-login`) para quem tem 2FA ativa. **Seguro por construção:** conta **SEM** 2FA nunca é afetada (`getAuthenticatorAssuranceLevel` → `nextLevel === currentLevel === 'aal1'`) e **qualquer erro na checagem cai no fluxo normal** (jamais bloqueia login). Limpa fatores não-verificados pendentes antes de reenrolar. *Depende de "Enable MFA/TOTP" no Auth do Supabase — ligado por padrão.* **(3) DPA** — nova página **`dpa.html`** (Acordo de Tratamento de Dados / cláusulas de operador, no visual da marca, **imprimível**), linkada nos Termos §6, no rodapé de login e em Minha Clínica; **aceite específico** gravado em `consentimentos` (novo contexto `'dpa'`, via RPC **`registrar_aceite_dpa`**; CHECK do contexto **estendido de forma aditiva**). **Validado:** migration testada em produção **com ROLLBACK** (auditoria válida=1, forjada=0, dpa=1 → **zero resíduo**); advisors de segurança **sem regressão** (as 2 RPCs novas caem só no mesmo aviso das demais DEFINER intencionais, escopadas por `auth.uid()`); `node --check` + **6/6 testes de navegador** (Playwright, supabase mockado): sem-2FA entra / com-2FA desafia / verificação entra / enroll mostra QR+chave / confirma ativa / status renderiza — **zero erro de JS**. **✅ FASE 1 (LGPD) CONCLUÍDA.** *Falta:* deploy do front (merge na `main` → Vercel; a migration já está em produção e é aditiva).
- **2026-07-03** — **Fase 1 · LGPD (parte 1): Política de Privacidade + Termos de Uso + consentimento com registro + Portal do titular.**
  Os 3 primeiros itens da Fase 1, de uma vez. **(1) Páginas legais** `privacidade.html` e `termos.html` (novas, no visual da marca): Política de Privacidade e Termos de Uso completos, orientados à LGPD — papéis (clínica = controladora dos dados dos pacientes; Nastaclin = operadora; e controladora dos dados da conta), dados coletados (incl. dados de saúde Art. 11), bases legais, lista de suboperadores (Supabase/Vercel/Anthropic/Evolution/Cakto/hCaptcha/Google) com finalidade, transferência internacional (Art. 33), retenção, direitos do titular (Art. 18), seção de DPA/cláusulas de operador nos Termos, planos/preços, WhatsApp+IA ("a IA pode errar; não dá orientação clínica"). ✅ **Placeholders preenchidos (2026-07-03):** o dono **não tem CNPJ/empresa formal** — as páginas foram preenchidas na versão **pessoa física** (nome do dono + cidade/UF + e-mail de contato, sob a marca Nastaclin; CPF e endereço residencial **não** publicados por privacidade do próprio dono). *Recomendação registrada:* avaliar abrir **MEI** no futuro (não trava o lançamento). Versão dos termos: **1.0 (2026-07-03)** (constante `POLITICA_VERSAO` nos 2 fronts — ao mudar o texto, suba a versão). **(2) Consentimento com registro** — migration `20260703120000_lgpd_consentimento_portal_titular.sql` **aplicada em produção**: tabela **`consentimentos`** (contexto, clinica/user/paciente, documentos, **versão, data/hora, IP**; RLS só-leitura p/ o dono — escrita apenas via funções DEFINER). Checkbox **obrigatório** no cadastro (`fazerCadastro` envia `lgpd_consent_versao` no metadata → trigger `criar_clinica_no_signup` grava) e no agendamento público (`agendar.html` → edge `agendar-publico` v3 repassa versão+IP → RPC `agendar_online` grava com CPF mascarado "CPF final XXXX"; registro tolerante a falha — não derruba o agendamento). Links legais no login, no cadastro e no rodapé do agendamento. **(3) Portal do titular** — na ficha do paciente (aba Dados), bloco "Privacidade do paciente (LGPD)": **Exportar dados** (JSON com paciente+consultas+evoluções+pacotes+mensalidades+consentimentos — acesso/portabilidade) e **Eliminar dados pessoais** (RPC **`paciente_anonimizar`**: apaga nome/CPF/contato/anamnese/evoluções/conversas, mantém o esqueleto financeiro de-identificado + grava evento na trilha). Bônus: **`paciente_excluir`** (RPC atômica cobrindo TODAS as tabelas filhas) — o "Excluir" antigo do front falhava se o paciente tivesse pacotes/mensalidades/notas (FK sem cascade). **Validado:** RPC testada em produção **com ROLLBACK** (consentimento gravado com versão+IP; zero resíduo); RPCs do portal recusam sem `auth.uid()`; advisors de segurança sem regressão; `node --check` + **30/30 testes de navegador** (Playwright, tudo mockado): gate de consentimento nos 2 fluxos (sem aceite → bloqueia SEM chamar rede), versão enviada no body/metadata, export baixa JSON, anonimizar/excluir confirmam e chamam as RPCs certas, páginas legais renderizam. **Restam da Fase 1:** trilha de auditoria de acesso a prontuário, 2FA (TOTP) e DPA como documento separado (a essência já está na seção 6 dos Termos).
- **2026-07-02** — **Senha forte no cadastro/alteração/recuperação (front) — alternativa grátis ao "leaked password" (que exige Pro).**
  O "Prevent use of leaked passwords" do Supabase **só existe no plano Pro** (print do dono). No lugar, de graça: o dono ativou no Supabase Auth **Password requirements = minúscula + MAIÚSCULA + número + símbolo**, e o **front** (`nastadesk/index.html`) passou a **validar a força da senha** nos 3 fluxos — cadastro (`fazerCadastro`), alterar senha (`alterarSenha`) e recuperação (`salvarNovaSenhaRecovery`): mínimo **8** + as 4 classes, com **dica ao vivo** (✓/○, função `atualizarReqSenha`) no cadastro e mensagem clara quando falta algo (evita o erro genérico do servidor). Validado: `node --check` + teste de navegador (hint 1/5 × 5/5, bloqueia senha fraca **sem** chamar `signUp`, passa com senha forte; zero erro de JS). **Próxima entrega decidida pelo dono: Fase 1 (LGPD) em um chat dedicado.**
- **2026-07-02** — **Fase 0 · Performance do banco: índices em FKs + RLS `(select auth.uid())` + limpeza de policies duplicadas.**
  Correções mecânicas de performance, **sem mudar comportamento**. (1) **Índices** nas FKs sem índice (migration `20260702180000_indices_fks.sql`): `consultas.paciente_id/pacote_id`, `conversas.paciente_id`, `evolucoes.clinica_id/consulta_id`, `ia_uso.conversa_id`, `lembretes.clinica_id`, `notas_fiscais.paciente_id`. (2) **RLS performático** (migration `20260702190000_rls_performance.sql`): ~21 policies reescritas de `auth.uid()` (reavaliado por linha) para `(select auth.uid())` (avaliado 1×) + escopo `TO authenticated` — **lógica idêntica**. (3) **Policies duplicadas**: removidas as 3 de DELETE redundantes (`pacientes`/`consultas`/`evolucoes`); a de `clinicas` (SELECT dono + admin) foi **mantida de propósito**. **Validado:** advisors `auth_rls_initplan` e `unindexed_foreign_keys` **zerados**; **teste funcional de isolamento com JWT simulado** — dono vê só o dele (5 pacientes / 10 consultas), usuário aleatório vê **0**. Tudo aplicado em produção numa transação (tudo-ou-nada). **Sobra da Fase 0:** só o **"Leaked Password Protection"** (1 clique no painel do Supabase — Auth → Policies; não dá pra fazer por código) e a remoção opcional do código morto do Mercado Pago.
- **2026-07-02** — **Agendamento online: CPF obrigatório + identifica paciente NOVO × recorrente + aviso de possível duplicado.**
  A pedido do dono ("como saber se o cliente já é cadastrado ou novo?"). (1) **Campo CPF** (obrigatório, com máscara e **validação dos dígitos verificadores** no front E no banco) na `agendar.html`. (2) A RPC **`agendar_online`** passou a receber `p_cpf` e **casa o paciente por CPF** (identidade forte); se não achar por CPF, casa por WhatsApp **só se o cadastro não tiver CPF** (mesma pessoa antiga → **enriquece** o CPF, sem duplicar). Migration `20260702160000_agendar_cpf_novo_recorrente.sql` **aplicada em produção** (índice `pacientes(clinica_id,cpf)` + função `cpf_valido()` + nova versão da RPC). O **bot usa `bot_agendar`** — não afetado. (3) O **alerta de novo agendamento** agora diz **paciente NOVO** ou **já cadastrado (N consultas)** e marca **⚠️ possível cadastro duplicado** (mesmo nome, CPF/telefone diferente). (4) **Agenda do dia:** etiqueta **"1ª vez" / "recorrente"** ao lado do `online` (usa `pacientes.total_consultas`, mantido pelo trigger `on_consulta_stats`). (5) Edge function `agendar-publico` repassa o CPF (v2). **Validado:** teste da RPC em produção **com ROLLBACK** (CPF inválido rejeitado; novo/recorrente/duplicado corretos; **zero dado deixado**) + teste de navegador (máscara, honeypot, CPF inválido, gate do captcha e sucesso enviando CPF+token). *Obs.:* CPF é **obrigatório** no online — dá pra deixar opcional num único ponto se o dono quiser.
- **2026-07-02** — **hCaptcha no agendamento público + deploy do front na `main` (Fase 0 concluída).**
  Fechou o último item aberto do anti-abuso. (1) Novo edge function **`agendar-publico`** (deployado, v1, `verify_jwt=false`): recebe o booking + o token do hCaptcha, **verifica o token no servidor** (secret em `admin_config.hcaptcha_secret`, **nunca no front**) e só então delega à RPC **`agendar_online`** (intocada — toda a validação de agenda/rate-limit continua nela). (2) `agendar.html` ganhou o **widget hCaptcha visível** (site key público) e passou a chamar a edge function em vez da RPC direto; **fail-closed** (sem token válido, não agenda). Registrado no `config.toml`. (3) **Validação:** curl no endpoint (token inválido/ausente → bloqueado sem agendar; GET → 405) + **teste de navegador** (Playwright) cobrindo honeypot, gate do captcha e caminho de sucesso, com a edge function **mockada** → zero agendamento real; zero erro de JS. (4) **Deploy:** front das features de 30/06–01/07 (Modalidades, Mensalidades, Multi-profissional, Repasse) + honeypot + hCaptcha **mergeado na `main`** (Vercel publica) a pedido do dono. *Opcional futuro:* rate-limit por IP (a edge function já enxerga o IP).
- **2026-07-02** — **Fase 0 · Segurança: `cakto-webhook` fail-closed + honeypot no agendamento + PR de deploy do front.**
  (1) **`cakto-webhook` endurecido e re-deployado (v4, produção).** Era **fail-open**: `secretOk = !esperado || recebido === esperado` — sem secret configurado, aceitava **qualquer** requisição (dava pra ativar/derrubar clínica com evento falso). Agora **fail-closed** (secret obrigatório; sem secret → HTTP 503) + **comparação em tempo constante** (double-HMAC com chave aleatória, não vaza nem o comprimento) + função **registrada no `config.toml`** (`verify_jwt=false`). Contexto de produção conferido antes: secret **já configurado** e **0 assinaturas Cakto ativas** (3 clínicas, todas em cortesia) → mudança segura. Testado no endpoint: secret errado → 401, GET → 200. *Obs.:* a Cakto usa **secret compartilhado no corpo**, não HMAC-do-corpo — por isso validamos o secret em tempo constante (não uma assinatura HMAC). (2) **Anti-abuso no agendamento público:** **honeypot** anti-bot em `agendar.html` (campo oculto; se preenchido, bloqueia sem tocar no banco). Descoberto que a RPC `agendar_online` **já tinha rate-limit** por WhatsApp (3/dia por clínica) — roadmap estava desatualizado. **hCaptcha** fica de follow-up (precisa da conta/chaves do dono). (3) **Deploy do front (item A):** as features de 30/06–01/07 (Modalidades, Mensalidades, Multi-profissional, Repasse) estavam commitadas na branch mas **nunca chegaram ao `main`** (a Vercel publica de `main`) → aberto **PR** para publicar. As migrations dessas features já estão em produção (aditivas), então o merge só sobe o front.
- **2026-07-01** — **Ficha do paciente: profissional + modalidade nas Consultas (fix de UX) + fix da aba Profissionais.**
  (1) A aba **Configurações → Profissionais** abria em branco — `cfgTab` tinha uma lista fixa de
  abas sem `'profissionais'`, então o painel (que começa `display:none`) nunca era exibido.
  Corrigido (adicionado à lista) + teste passou a **simular o clique** na aba (não só chamar o render).
  (2) A aba **Consultas** da ficha lateral do paciente não mostrava o profissional em lugar nenhum;
  agora cada consulta exibe **etiqueta de modalidade e de profissional**. Aditivo, sem tocar em dados.
  Validado no navegador. (3) Registrada na seção 10.4 a ideia de **pagamento self-service do paciente
  (Pix/checkout com baixa automática)** — com análise de viabilidade — para uma fase futura dedicada.
- **2026-07-01** — **Fase 2 · Repasse/comissão por profissional (Financeiro → Repasse).**
  Aditivo. Migration `20260701130000_profissionais_comissao.sql` **aplicada em produção**:
  colunas `profissionais.comissao_tipo` (`nenhuma`|`percentual`|`valor`) + `comissao_valor`
  (nullable) com CHECK. Front: **3ª aba no Financeiro** (Consultas | Mensalidades | **Repasse**)
  que lista, por profissional, nº de consultas **atendidas** no mês, valor gerado e o repasse
  (% do valor ou R$/consulta, configurável e salvo automático) + total do mês. **Não altera** o
  financeiro por consulta/mensalidade. Validado (node --check + smoke no navegador: 50% de 300 = 150,
  R$40×2 = 80, total 230). **Trava por plano:** decisão do dono = **liberado a todos** (gate ainda
  preparado). **Login de profissionais + papéis: adiado de propósito** — mexe em auth/RLS (risco de
  vazamento/lockout entre clínicas); será entrega dedicada, testada e com deploy à parte.
- **2026-07-01** — **Fase 2 · item 1: Multi-profissional (cadastro + agenda por profissional).**
  Aditivo e seguro, **sem login novo** (profissional é "recurso" da agenda, não
  mexe em auth/RLS). (1) Migration `20260701120000_profissionais.sql` **aplicada no
  Supabase (produção)**: tabela `profissionais` (nome, registro, cor, ordem, ativo)
  com RLS `TO authenticated` + `(select auth.uid())` (formato performático da Fase 0),
  índice, e coluna **`consultas.profissional_id`** nullable (FK `on delete set null`)
  + índice; **nada semeado** → clínica sem profissional não vê diferença. (2) Front
  só em `nastadesk/index.html`: aba **Configurações → Profissionais** (CRUD espelhando
  Modalidades), **etiqueta colorida** na Agenda do dia (lista e "por salão"), **filtro
  por profissional** (chips) na Agenda do dia, profissional na **grade semanal**
  (dot/cor + tooltip) e na lista mobile, **select opcional** no modal de agendamento,
  e **reatribuição inline** na agenda. Validado: `node --check` + smoke test no
  navegador (funções OK; clínica sem profissional = zero mudança). **Repasse/comissão**
  e **trava por plano** ficaram p/ etapas seguintes (gate preparado; liberado a todos
  por ora, a pedido do dono). *Falta:* deploy do front (merge na `main` → Vercel) — a
  migration já está em produção e é aditiva (não afeta o front atual em `main`).
- **2026-07-01** — **Auditoria "100% profissional" + roadmap por fases (só docs).**
  Análise minuciosa dos 2 repos (código real, não só este arquivo), dos edge
  functions e dos **advisors de segurança/performance do Supabase** (banco de
  produção). Resultado e plano de ação registrados na **nova seção 10** (fases
  0→3, cada uma tocável em um chat separado). **Nenhuma mudança de código/banco
  nesta etapa** — só documentação. Achados-chave: LGPD ausente (dado sensível de
  saúde coletado na `agendar.html` sem consentimento), sem 2FA, `cakto-webhook`
  fail-open, RLS com `auth.uid()` sem `(select …)`, FKs sem índice, policies
  permissivas duplicadas, sem multi-profissional, sem NF-e/contas a pagar/
  prontuário estruturado. Base já forte: RLS em todas as tabelas, `admin-api`
  correta, chatbot IA. **Próximo passo sugerido:** Fase 0 (quick wins).
- **2026-06-30** — **Modalidades (Fisio/Pilates) + cobrança por paciente (mensalidades).**
  Pedido de uma clínica cliente (faz Fisio e Pilates e precisava diferenciar, além de
  controlar valor/dia de pagamento/pago por paciente). Feito, **tudo aditivo e opcional**:
  (1) tabela **`modalidades`** (lista configurável por clínica, em Configurações →
  Modalidades; semeada com Fisioterapia + Pilates p/ todas as clínicas); (2)
  `pacientes.modalidade_id` e `consultas.modalidade_id` — etiqueta colorida na lista de
  pacientes, na agenda do dia e no financeiro, filtro por modalidade, e select no modal
  de agendamento (já vem preenchido com a modalidade do paciente); (3) cobrança por
  paciente: `pacientes.cobranca_tipo` (`nenhuma` | `mensalidade` | `sessao`),
  `cobranca_valor`, `cobranca_dia_vencimento`; (4) tabela **`mensalidades`** (ledger mês a
  mês, único por paciente/competência) + RPC **`gerar_mensalidades(competencia)`**
  (SECURITY DEFINER, idempotente, escopo por `auth.uid()`, só gera p/ mês corrente/futuro —
  nunca fabrica dívida retroativa); (5) Financeiro ganhou seletor **Consultas |
  Mensalidades** — a aba de mensalidades abre as cobranças do mês sozinha, mostra
  recebido/a receber/mensalistas, marca pago em 1 clique (com forma opcional) e destaca
  vencidas. **O financeiro por consulta continua idêntico**; clínicas sem modalidade/
  mensalidade não veem diferença. Migração `20260630120000_modalidades_mensalidades.sql`
  **aplicada no Supabase**. Mudança de front só no `nastadesk/index.html` (o `dashboard`
  não muda; só este `CLAUDE.md`). *Falta:* deploy do front (merge na `main` → Vercel).
- **2026-06-30** — **Migração de pagamento Mercado Pago → Cakto (concluída).** Como
  as 3 clínicas estão em cortesia e ninguém estava pagando, a troca foi segura.
  Feito: (1) Edge Function **`cakto-webhook`** criada, deployada e validada — lê o
  payload real da Cakto (`body.event`, `body.data.customer.email`, valor, id da
  assinatura), libera/suspende o acesso, **protege cortesia** e verifica o secret
  (guardado em `admin_config.cakto_webhook_secret`); (2) os botões "Assinar/Upgrade"
  do app agora abrem os **links de checkout da Cakto** (e-mail pré-preenchido p/ o
  webhook casar); (3) "Cancelar assinatura" da Cakto orienta pelo portal/suporte
  (cancelamento do MP legado mantido); (4) **Mercado Pago dormindo** — funções
  mantidas, mas o app não cria mais cobranças nele. Planos/preços inalterados
  (Básica 97 / Profissional 197 / Premium 347). *Obs.:* mapeamento por e-mail — a
  clínica deve pagar com o mesmo e-mail da conta. Falta só o teste end-to-end com
  um pagamento real (eventos de teste da Cakto usam e-mail fictício e não ativam
  nada). Opcional: mapear plano por ID do produto/oferta (hoje é pelo valor).
- **2026-06-29** — Card "API Claude / Anthropic" do painel passou de estimativa
  fixa (~R$3/clínica) para **custo real por cliente** baseado em tokens; criada a
  tabela `ia_uso`; `whatsapp-webhook` passou a registrar consumo por clínica;
  `admin-api` agrega o uso do mês e busca **câmbio US$→R$ ao vivo**. Deploy feito
  (migração + Edge Functions + front). Criado este `CLAUDE.md` nos dois repos.

## 10. Roadmap "100% profissional" — plano por fases (auditoria 2026-07-01)

> **O que é isto:** plano mestre para levar a ferramenta a um nível 100%
> profissional. Nasceu de uma auditoria minuciosa em 2026-07-01 — leitura do
> código real dos dois repos, dos edge functions, e dos **advisors de segurança
> e performance do Supabase** (banco de produção).
>
> **Como usar entre chats:** cada fase abaixo é independente e pode ser feita em
> um chat separado. Ao começar uma fase, leia a fase inteira + a seção de
> "Evidências" (10.6). Ao concluir um item, marque `[x]`, adicione linha no
> Histórico (seção 9) e replique no `CLAUDE.md` do outro repo. **Não há dados
> sensíveis aqui de propósito** (a seção fixa proíbe): IDs de projeto, e-mails,
> tokens e segredos ficam no Supabase/Vercel, nunca neste arquivo.

### 10.0 Scorecard inicial (2026-07-01)

| Área | Nota | Resumo |
|---|---|---|
| Arquitetura backend (Supabase/RLS) | 8/10 | Sólida; RLS em todas as tabelas; `admin-api` exemplar |
| Núcleo (agenda/pacientes/financeiro) | 7/10 | Cobre o dia a dia; falta profundidade |
| Chatbot IA / WhatsApp | 8/10 | Diferencial real vs. concorrentes |
| **Compliance / LGPD** | **2/10** | **Quase inexistente — maior risco legal** |
| Segurança (hardening) | 6/10 | Boa base, brechas evitáveis |
| Multi-usuário / multi-profissional | 2/10 | **Não existe — barra clínicas com +1 profissional** |
| Fiscal (NF-e, contas a pagar, DRE) | 3/10 | Só faturamento; sem nota fiscal nem despesas |
| UX / Acessibilidade | 5/10 | Bonito, mas 0 acessibilidade e validação fraca |
| Qualidade de código / manutenção | 4/10 | Monólito ~5.400 linhas, sem testes/CI |

### 10.1 O que já está bom (NÃO mexer sem motivo)

- Isolamento multi-tenant com **RLS ativo em todas as tabelas de dados**.
- **`admin-api`**: valida JWT → confirma admin → só então usa `service_role`.
- Chatbot híbrido (menu determinístico + IA com *tool use* + RPCs que validam no banco).
- Rastreio de **custo real de IA por cliente** com câmbio ao vivo.
- Mensalidades idempotentes, sem dívida retroativa.

### 10.2 FASE 0 — Quick wins de segurança/performance (dias, baixo risco)

> Correções mecânicas e seguras. **Fazer primeiro.** Não mudam comportamento visível.

- [~] **"Leaked Password Protection"** — ⚠️ **EXIGE plano Pro do Supabase** (confirmado 2026-07-02 pelo print do dono: *"available on Pro Plans and up"*). **Adiado de propósito** — não vale pagar só por isso. **No lugar (grátis), FEITO 2026-07-02:** o dono ativou no painel **Password requirements = minúscula + MAIÚSCULA + número + símbolo**, e o **front passou a validar a força da senha** nos 3 fluxos (cadastro, alterar senha, recuperação) com **dica ao vivo** e aviso claro. Só o "leaked password" (HaveIBeenPwned) — que exige Pro — fica pendente.
- [x] **Corrigir `cakto-webhook` (fail-open)** — FEITO 2026-07-02. Agora **fail-closed** (secret obrigatório; sem secret configurado → HTTP 503), **comparação em tempo constante** (double-HMAC com chave aleatória — não vaza nem o comprimento) e a função **registrada no `config.toml`** (`verify_jwt=false`). Re-deployada em produção (v4) e testada (secret errado → 401). *Obs.:* a Cakto usa **secret compartilhado no corpo** (`body.secret`), **não** HMAC-do-corpo — por isso validamos o secret em tempo constante em vez de uma assinatura HMAC.
- [x] **Migration de performance RLS** — FEITO 2026-07-02 (`20260702190000_rls_performance.sql`). ~21 policies reescritas de `auth.uid()` → `(select auth.uid())` + `TO authenticated` (advisor `auth_rls_initplan` **zerado**). **Lógica idêntica**; **testado com JWT simulado**: dono da clínica vê só os dados dele (5 pac / 10 cons), usuário aleatório vê **zero**.
- [x] **Remover policies permissivas duplicadas** — FEITO 2026-07-02. Removidas as **3 policies de DELETE redundantes** (`pacientes`, `consultas`, `evolucoes`) — a policy `ALL` já cobre DELETE com a mesma condição. Restou **1** `multiple_permissive` em `clinicas` (SELECT: `clinica_propria` + `admin_ve_todas_clinicas`), **mantida de propósito** (é o admin que vê todas as clínicas).
- [x] **Criar índices nas FKs sem índice** — FEITO 2026-07-02 (`20260702180000_indices_fks.sql`). Índices em `consultas.paciente_id/pacote_id`, `conversas.paciente_id`, `evolucoes.clinica_id/consulta_id`, `ia_uso.conversa_id`, `lembretes.clinica_id` **+ `notas_fiscais.paciente_id`**. Advisor `unindexed_foreign_keys` **zerado**.
- [x] **Anti-abuso no agendamento público** — FEITO 2026-07-02. **honeypot** em `agendar.html` (campo oculto), **rate-limit por WhatsApp** já existia na RPC (3/dia), e agora **hCaptcha** via edge function **`agendar-publico`** (verifica o token no servidor e delega à RPC `agendar_online`, que segue intocada). Secret em `admin_config.hcaptcha_secret` (nunca no front); site key público no widget. *Opcional futuro:* rate-limit por IP (a edge function já enxerga o IP — é só plugar).
- [ ] **(Opcional) Remover código morto do Mercado Pago** — só depois de confirmar 100% a migração p/ Cakto.

### 10.3 FASE 1 — Compliance / LGPD (semanas; destrava vendas)

> **Mais grave.** Dados de saúde = dado sensível (Art. 11 LGPD). A página pública
> `agendar.html` coleta nome + WhatsApp + CPF + "motivo da consulta" (queixa clínica)
> **sem aviso nem consentimento**.
>
> ▶️ **DECISÃO (2026-07-02):** o dono vai tocar a **Fase 1 (LGPD) em um chat dedicado.**
> Começar por: aviso de privacidade + termos + **consentimento com registro** (checkbox
> obrigatório no cadastro e no agendamento público, gravando data/hora/versão do termo).
>
> ✅ **CONCLUÍDA em 2026-07-03** — todos os 6 itens entregues (detalhes no Histórico,
> seção 9): parte 1 (privacidade + termos + consentimento + portal do titular) e
> parte 2 (trilha de auditoria + 2FA/TOTP + DPA separado). Placeholders de
> `privacidade.html`/`termos.html` **preenchidos** (versão pessoa física — dono sem
> CNPJ). Ao alterar o texto dos termos, **subir a `POLITICA_VERSAO`** (constante nos 2
> fronts) para os novos aceites registrarem a versão nova. **Falta só o deploy do
> front na `main`** (Vercel); as migrations já estão em produção e são aditivas.

- [x] **Aviso de privacidade + termos de uso** — FEITO 2026-07-03. Páginas `privacidade.html` + `termos.html` (texto LGPD completo: papéis controladora/operadora, dados sensíveis Art. 11, suboperadores, Art. 33, retenção, Art. 18, DPA embutido nos Termos, planos/preços, IA). Linkadas no login, no cadastro e no agendamento público. **Placeholders preenchidos** (versão pessoa física — dono sem CNPJ; nome + cidade/UF + e-mail, sob a marca Nastaclin).
- [x] **Consentimento com registro** — FEITO 2026-07-03. Tabela **`consentimentos`** (data/hora, **versão do termo**, IP, identificador mascarado; RLS só-leitura p/ o dono, escrita só via funções DEFINER) — migration `20260703120000_lgpd_consentimento_portal_titular.sql` **em produção**. Checkbox **obrigatório** no cadastro (metadata `lgpd_consent_versao` → trigger de signup grava) e no agendamento público (edge `agendar-publico` v3 repassa versão+IP → `agendar_online` grava; tolerante a falha). Versão atual: `POLITICA_VERSAO = '1.0 (2026-07-03)'`.
- [x] **Portal do titular** — FEITO 2026-07-03. Na ficha do paciente (aba Dados): **Exportar dados** (JSON completo — acesso/portabilidade) e **Eliminar dados pessoais** (RPC `paciente_anonimizar`, escopo por `auth.uid()`: apaga dados pessoais/sensíveis + conversas, mantém financeiro de-identificado, grava evento). Bônus: `paciente_excluir` (exclusão total atômica; corrige o Excluir antigo que falhava com pacotes/mensalidades/notas).
- [x] **Trilha de auditoria** — FEITO 2026-07-03. Tabela **`auditoria`** + RPC **`registrar_auditoria`** (DEFINER, escopo por `auth.uid()`, valida paciente da própria clínica, tolerante a falha) — migration `20260703140000_lgpd_auditoria_dpa.sql` **em produção**. Front registra **fire-and-forget** o acesso/edição/exportação/eliminação da ficha e exibe o **"Registro de acessos (LGPD)"** na ficha. RLS só-leitura p/ o dono. *(Como não há login por profissional ainda, o "quem" é sempre a conta da clínica; a trilha já registra o "quando/o quê" e fica pronta para quando os logins por profissional chegarem.)*
- [x] **2FA (TOTP)** — FEITO 2026-07-03. **Opt-in**, Supabase Auth nativo. UI em Minha Clínica → Privacidade e segurança (ativar com QR+chave+código, desativar) + **desafio no login**. **Seguro por construção:** conta sem 2FA nunca é afetada; erro na checagem cai no fluxo normal (nunca bloqueia). Depende de "Enable MFA/TOTP" no Auth do Supabase (ligado por padrão).
- [x] **DPA / contrato de operador** — FEITO 2026-07-03. Documento separado **`dpa.html`** (imprimível), linkado nos Termos §6/login/Minha Clínica, com **aceite específico** gravado em `consentimentos` (contexto `'dpa'` via RPC `registrar_aceite_dpa`). A essência já estava nos Termos §6; agora há o instrumento separado e o aceite registrado.

### 10.4 FASE 2 — Paridade de mercado (o que toda concorrente tem)

- [x] **Multi-profissional (cadastro + agenda por profissional)** — FEITO em 2026-07-01 (aditivo, **sem login novo**; profissional é "recurso" da agenda). Tabela `profissionais` (nome, registro/CREFITO, cor, ordem, ativo) + `consultas.profissional_id` (nullable, FK on delete set null). Config → Profissionais (CRUD); etiqueta colorida + filtro por profissional na Agenda do dia; profissional na grade semanal (dot/cor + tooltip) e na lista mobile; select opcional no modal de agendamento; **reatribuição inline** na agenda (`mudarProfissionalConsulta`). RLS já no formato performático (`(select auth.uid())` + `TO authenticated`). **NÃO semeia dados** → clínica sem profissional não vê diferença. Migration `20260701120000_profissionais.sql` **aplicada em produção**; front só em `nastadesk/index.html` (o `dashboard` não muda). *Falta:* deploy do front (merge na `main`).
- [x] **Login de profissionais + papéis de usuário** — FEITO 2026-07-04. Cada funcionário entra com **email+senha próprios**, vê **só os dados da própria clínica** (isolamento validado com JWT simulado) e tem permissões por papel: **Recepção** (agenda/pacientes/financeiro/lembretes) ou **Profissional** (agenda/pacientes; sem financeiro). Tabela **`clinica_membros`** + função `clinica_ids_membro()` (SECURITY DEFINER) + **políticas de membro ADITIVAS** (o dono continua com as policies antigas; o membro entra via OR) em 15 tabelas operacionais. Edge function **`equipe-criar`** (só o dono cria; trava por plano no servidor). Front: resolução de clínica no login (dono OU membro), gate de nav por papel, e card **"Logins da equipe"** em Config → Profissionais. Migration `20260704140000_login_profissionais_membros.sql` **aplicada em produção** (aditiva; `clinica_membros` nasce vazia → clínica atual não muda nada).
- [x] **Trava por plano do multi-profissional** — FEITO 2026-07-04 (a pedido do dono, **mudou**: agora é **Profissional+**, não mais liberado a todos). Feature `equipe` nos planos (Básico não; Profissional/Premium sim). No Básico, a aba **Config → Profissionais** (e os logins de equipe) fica escondida. Gate no front (`recursoLiberado('equipe')`) e **também no servidor** (a edge `equipe-criar` recusa plano Básico).
- [x] **Portal do Profissional + acesso restrito por papel** — FEITO e **em produção** (2026-07-05). A pedido do dono: profissional NÃO vê todos os pacientes da clínica nem exclui nada; vê **só quem ele atende**. Front dedicado `profissional.html` (Hoje/Agenda/Meus pacientes, ficha read-only + evoluções, sem financeiro) + RLS por papel — migration `portal_profissional_rls` **APLICADA em produção** e validada com JWT simulado (profissional com vínculo vê só o dele; sem vínculo vê 0; recepção intacta; reatribuição bloqueada). Front **mergeado na `main`** (Vercel publicou; `nastadesk.vercel.app/profissional.html` no ar). Card "Logins da equipe" ganhou **vincular/editar profissional** de logins já criados. *Pendências não-bloqueantes (conector Supabase instável na sessão):* re-deploy da edge `equipe-criar` v2 (o front já exige vínculo) e revogar `execute` do `anon` em 3 funções auxiliares (cosmético; não vazam nada).
- [~] **Nota fiscal de serviço (NFS-e)** — ⚠️ **Emissão de NFS-e exige CNPJ** (ou inscrição municipal de autônomo) — é regra fiscal, nenhum emissor contorna. O **dono não tem CNPJ**, então a NFS-e via **Focus NFe** (que já está construída na branch `claude/financial-phase-2-8q575q`, tabelas `config_fiscal`/`notas_fiscais` no banco) **NÃO foi deployada**. Caminho fiscal atual **sem CNPJ = Recibo de pagamento em PDF** (já existe, botão na consulta paga). **Para ligar a NFS-e no futuro:** dono abre **MEI** (grátis → CNPJ) e configura o emissor. *Melhoria sugerida do recibo:* CREFITO/CPF do profissional (dedução IR médico) + recibo p/ mensalidade/pacote.
- [x] **Financeiro completo** — FEITO 2026-07-03 (deployado na `main`). Aba **Financeiro → Despesas**: contas a pagar por categoria (status paga/pendente/vencida em 1 clique, repetir nos próximos meses), **fluxo de caixa do mês** (Entradas/Saídas/Saldo), **DRE simples** por categoria e **export CSV**. Construído do zero em cima da `main` atual usando a tabela `despesas` que já estava em produção (schema `competencia`/`status`) — **não mergeei a branch `financial-phase-2`** (16 commits atrás; mergear apagaria LGPD/2FA/PWA). Já feito antes: **Repasse/comissão** (2026-07-01). *Falta (opcional):* despesas recorrentes "de verdade" (tabela `despesas_recorrentes` existe) e gráficos.
- [ ] **Pagamento self-service do paciente (Pix/checkout) com baixa automática** — ⏸️ **ADIADO a pedido do dono (2026-07-04): NÃO fazer agora; talvez no futuro. Ideia salva aqui.** Hoje o dono marca pago/pendente na mão (consulta, pacote ou mensalidade). Objetivo: o **paciente paga sozinho** (inclusive adiantado) e o status **atualiza automaticamente** no NastaDesk pro dono ver.
  - **Viável?** Sim. Caminho recomendado p/ Brasil: **Pix via um PSP com webhook** (ex.: Asaas, Efí/Gerencianet, Mercado Pago, Pagar.me) — sem taxa de cartão e confirmação na hora. Gera um Pix (copia-e-cola/QR) por cobrança; quando o paciente paga, o PSP chama uma **edge function** que dá **baixa automática** na cobrança (idempotente + HMAC), casando pelo id de referência.
  - **Por que é fase dedicada (não agora):** (1) cada clínica conecta a **própria conta** do PSP → a clínica recebe direto e a **Nastaclin não fica no meio do dinheiro** (evita virar "facilitador de pagamento"/peso regulatório); (2) reconciliação segura/idempotente; (3) **aditivo** — a baixa manual continua como fallback, sem tocar no financeiro atual; (4) LGPD/dados financeiros exigem cuidado.
  - **MVP sugerido:** começar por **mensalidades** (recorrente/previsível) OU por consulta, com **1 PSP via Pix**, link/QR por cobrança + webhook de baixa. **Boa ideia — recomendo fazer**, como entrega própria (concorrentes já oferecem link de pagamento ao paciente).
- [x] **PWA instalável** — FEITO 2026-07-03 (deploy na `main` em andamento). `manifest.json` + ícones PNG (192/512/apple-touch) + `sw.js` (service worker **network-first no HTML** — não congela a clínica numa versão velha; cache-first só nos ícones; não intercepta cross-origin). Metas de PWA no `<head>`, botão flutuante "Instalar app" (via `beforeinstallprompt`) e `vercel.json` ajustado p/ publicar os assets.

### 10.5 FASE 3 — Diferenciação (depois da paridade)

- [ ] **Prontuário estruturado de fisio** — templates clínicos (EVA de dor, goniometria, avaliação postural, testes funcionais) + anexos de exames.
- [ ] **Assinatura digital (ICP-Brasil)** das evoluções/prontuário.
- [ ] **Teleconsulta** — sala de vídeo integrada.
- [ ] **Convênios / TISS** — faturamento de guias/XML (hoje só há o campo "convênio").
- [ ] **Extras** — lista/fila de espera, integração Google Agenda/Outlook, NPS/satisfação, estoque, relatórios/BI exportáveis, trial self-service no cadastro.

### 10.6 Evidências técnicas da auditoria (para não reinvestigar)

- **Advisor de segurança:** `auth_leaked_password_protection` **OFF**; `admin_config` com RLS sem policy (ok — fica só p/ service_role); `agendar_online` / `clinica_publica` / `horarios_ocupados` são SECURITY DEFINER expostos ao anon (**intencional** — booking público).
- **Advisor de performance:** `auth_rls_initplan` em ~24 policies; `multiple_permissive_policies` em `clinicas` / `consultas` / `pacientes` / `evolucoes`; `unindexed_foreign_keys` (lista na Fase 0); vários `unused_index` (base pequena ainda — ignorar por ora).
- **Nenhum RLS crítico desabilitado** — todas as tabelas de dados têm RLS + policy.
- **Front:** `nastadesk/index.html` ≈ 5.413 linhas / ~334 KB, arquivo único, **sem testes, sem CI, sem lint, sem monitor de erros**; 0 `aria-*`/`role=`; inputs sem `required`/`maxlength`; 0 PWA.
- **`cakto-webhook`:** fail-open no secret; sem HMAC; ausente do `config.toml`.
- **Pagamento mapeado por e-mail** é frágil (cliente paga com outro e-mail → não ativa) — prever tela admin de reconciliação.

---

### Como manter este arquivo (lembrete)

Sempre que terminarmos uma alteração: atualize a seção afetada, registre no
Histórico (seção 9) e replique a mudança no `CLAUDE.md` do outro repositório.
Mantenha os dois arquivos idênticos.
