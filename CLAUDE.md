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

> Documento de contexto mantido para continuidade entre chats. Última atualização: **2026-10-24**.

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
  `index.html`. Hospedado na **Vercel**, publicado a cada push na `main` pelo
  workflow **`.github/workflows/deploy-vercel.yml`** (GitHub Actions → `vercel deploy --prod`).
  ⚠️ **A integração Git nativa da Vercel NÃO funciona mais** desde que os repos viraram
  privados (plano Hobby) — ela parou de publicar **em silêncio**; por isso o deploy passou
  para o workflow. O workflow depende do secret **`VERCEL_TOKEN`** em cada repositório.
  Quem serve o quê: `nastadesk.vercel.app` = projeto **`nastadeskexemplo`**;
  `nastaclin-admin.vercel.app` = projeto **`nastaclin-admin`** (o projeto chamado
  `nastaclin` aponta para o mesmo repo e está ocioso — não é ele que está no ar).
  O que cada site publica é filtrado pelo **`vercel.json`** (só `*.html`/`*.png`/`manifest.json`/`sw.js`,
  com catch-all para o `index.html`) + `.vercelignore` — **sem isso a Vercel serve o repositório
  inteiro** (foi o que aconteceu com o painel admin até 2026-08-30).
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
| `whatsapp-webhook` | Cérebro do chatbot. Recebe eventos da Evolution API, roda o bot (menus + IA) e responde. Registra o consumo de tokens da IA por clínica. **v8 (2026-10-19): trava de IA** — antes de cada chamada ao Claude checa a cota do plano e o limite diário do telefone (RPC `ia_checar_e_contar`); ver seção 6. |
| `whatsapp-enviar` | Envio de mensagens pelo WhatsApp. |
| `whatsapp-conexao` | Gerencia a conexão/instância da clínica na Evolution. |
| `lembretes-auto` | Lembretes automáticos (disparados por cron a cada 10 min). |
| `mercadopago-checkout` | Cria checkout de assinatura no Mercado Pago. *(sendo aposentada — migração p/ Cakto)* |
| `mercadopago-webhook` | Recebe eventos de cobrança do Mercado Pago. *(sendo aposentada — migração p/ Cakto)* |
| `cakto-webhook` | Recebe eventos da Cakto (compra aprovada, assinatura criada/renovada/cancelada, reembolso, chargeback) e libera/suspende o acesso da clínica. Mapeia o comprador pelo **e-mail**, identifica **plano E período** pelo **valor** (mensal 97/197/347 · trimestral 262/532/937 · anual 931/1891/3331, aceitando reais ou centavos), grava `assinaturas.periodo`, **confirma o cupom de parceiro** do cliente e **nunca derruba clínica em cortesia**. **v5 (períodos + cupom) deployada em 2026-08-30.** **v6 (2026-10-24):** cancelamento mantém o acesso até `proximo_pagamento` (corte pelo cron `nastadesk-assinatura-expira`); só reembolso/chargeback cortam na hora; `refund_requested` não mexe em nada; `subscription_late` vira `em_atraso`; grava `proximo_pagamento` (da Cakto ou hoje + período). |
| `cakto-cancelar` | *(v1 deployada em 2026-10-24, `verify_jwt=true`)* Botão "Cancelar assinatura" do app. Só o **dono** (JWT → `clinicas.user_id`); acha a assinatura na Cakto (`provider_id` ou busca pelo e-mail) e chama `POST /public_api/subscriptions/{id}/cancel/`; marca `assinaturas.status='cancelada'` + `cancelada_em` e guarda `proximo_pagamento` — **não** tira o acesso (quem corta é o cron `nastadesk-assinatura-expira`). Secrets `CAKTO_CLIENT_ID`/`CAKTO_CLIENT_SECRET`. Se falhar, o app oferece o portal da Cakto ou o WhatsApp. |
| `agendar-publico` | Porteiro anti-robô do agendamento online. Recebe o booking + token do hCaptcha, verifica o token no servidor (secret em `admin_config`) e, se válido, delega à RPC `agendar_online` — repassando também a **versão do consentimento LGPD + IP** para registro. `verify_jwt=false`. |
| `equipe-criar` | Cria o login de um funcionário da clínica. Só o **dono** chama (valida o JWT → `clinicas.user_id`), **trava por plano** (Profissional+), cria o usuário de auth (service_role, `user_metadata.tipo='membro'`) e vincula em `clinica_membros`. Para papel `profissional`, **exige e valida** o `profissional_id` (tem que ser da própria clínica) — é o vínculo que define o que a pessoa vê no portal. `verify_jwt=true`. **v2 (com essa validação de vínculo) deployada em produção em 2026-07-05.** |
| `equipe-remover` | Exclui o login de um funcionário. Só o **dono** chama; remove o vínculo em `clinica_membros` e apaga o usuário de auth (libera o email). `verify_jwt=true`. |
| `agenda-ics` | Feed de calendário **ICS** para assinar a agenda da clínica no Google Agenda/Outlook/Apple Calendar (só leitura, 1 via). Sem login (`verify_jwt=false`); o segredo é o `clinicas.ics_token` na URL (regenerável em Configurações → Agenda; o link antigo morre). Janela −7d/+60d, sem canceladas. |
| `admin-api` | Backend do painel admin. Valida que quem chama é o admin e só então lê todas as clínicas/assinaturas e roda ações administrativas com a service_role. **v6 (2026-08-30):** também serve e grava **cupons**, **usos de cupom**, **sites** e a **`config_publica`** (links de checkout por período + WhatsApp/preços do site + **login da conta de demonstração**). **v7 (2026-10-19):** serve a **trava de IA** (limites, totais por clínica/mês dos últimos 6 meses, marcos) e grava os limites (`salvar_ia_limites`); a soma de tokens do mês passou a ser feita no banco (RPC `admin_ia_uso_mes`). |

## 4. Funcionalidades do app (nastadesk)

- **Agenda do dia** — consultas em tempo real, status, métricas, mini-calendário.
- **Agendamentos** — grade semanal (desktop) e lista (mobile). **Clicar numa consulta
  (de qualquer dia) abre o modal de ações** *(2026-07-06)*: **Ver ficha do paciente /
  Remarcar / Excluir** — antes o clique só abria a ficha e excluir só dava na Agenda do
  dia. A **ficha do paciente** (aba Consultas) também ganhou botão **🗑 excluir** por
  consulta (a lista da ficha recarrega sozinha após excluir). Tudo passa pelo
  `excluirConsulta` de sempre (confirmação + escolha "só esta/série" p/ horário fixo).
- **Agendamento recorrente / horário fixo** *(2026-07-06)* — no modal **Nova consulta**,
  opção **"🔁 Repetir toda semana (horário fixo)"**: escolhe os **dias da semana**
  (seg/qua/sex…, já vem marcado o dia da data escolhida) e por **quantas semanas** (4/8/12/24)
  **ou até uma data específica**, com **preview ao vivo** ("Serão criadas N consultas…"); o sistema cria **todas as consultas
  de uma vez** — a clínica **não precisa recadastrar o paciente toda semana**. Todas as
  ocorrências ganham um **`serie_id`** comum (etiqueta **🔁 fixo** na agenda do dia, salões,
  grade semanal, lista mobile e ficha). **Idempotente:** pula horários que o paciente já tem
  (não duplica se rodar 2×) e nunca cria datas passadas. Ao **excluir** uma consulta da série,
  oferece **"só esta"** ou **"esta e as próximas"** (nunca mexe nas que já passaram). **Não vale**
  para sessão de **pacote** nem **lista de espera** (agendamento único). Como cada ocorrência é
  uma consulta normal, entra sozinha nos **lembretes**, no **feed ICS** e no **financeiro**.
  Coluna `consultas.serie_id` (nullable, aditiva). **Corrigir o horário da série** *(2026-07-06)*:
  o **Remarcar** de uma consulta com `serie_id` pergunta **"Só esta"** ou **"Esta e as
  próximas da série"** — no segundo modo, todas as consultas **futuras** da série se movem
  juntas pelo mesmo deslocamento (troca de horário E/OU de dia da semana); as que **já
  passaram e as canceladas não mudam**.
- **Aula/consulta experimental (agendar sem cadastro completo)** *(2026-07-06, pedido de
  cliente por áudio)* — no modal **Nova consulta**, link **"⭐ É aula experimental? Agende
  sem cadastro completo"** (também aparece nos resultados da busca de paciente): vira um
  **cadastro rápido** só com **nome + WhatsApp (opcional)** — cria o paciente mínimo na hora
  (a ficha pode ser completada depois se a pessoa fechar) e agenda a consulta com a flag
  **`consultas.experimental`** (boolean, aditiva). Etiqueta **⭐ experimental** na agenda do
  dia, salões, grade semanal, lista mobile e ficha. **Valor em branco → entra isenta (R$ 0,
  `pagamento_status='isento'`)** para não fabricar pendência no financeiro; preenchendo o
  valor, entra pendente normal. É sempre **agendamento único** (sem recorrência) e **não
  vale** nos fluxos de pacote/lista de espera (que exigem paciente já cadastrado).
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
- **Reposição de aulas com crédito (pilates)** *(2026-10-24 — migration `20261025015303_reposicao_aulas_creditos.sql`
  **aplicada em produção**; no ar na `main`)* — aluno que
  **avisa a falta com antecedência** ganha **1 crédito** para repor a aula. **Regras por clínica**
  em Configurações → **Reposição de aulas** (só o **dono** altera; tabela `reposicao_config`):
  liga/desliga (**nasce desligada**), **aviso mínimo** em horas (padrão 3h), **validade** em dias
  contados da data da aula (padrão 30), **quem marca** (só recepção — padrão — ou também o aluno
  pelo `/agendar`), **alunos por horário** (vagas da turma, só p/ o aluno marcar sozinho) e
  **modalidades** que valem (sugere as que têm "pilates" no nome). **Uso:** no menu de status
  da consulta e no modal de ações, **"🔄 Aluno avisou a falta"** → informa quando avisou →
  prévia (gera crédito / fora do prazo / modalidade fora / pacote) → a RPC
  `reposicao_registrar_falta` cancela a aula e cria o crédito (botão **"Dar crédito mesmo
  assim"** = exceção, fica marcada). Créditos aparecem na **ficha do aluno** (aba Consultas) e
  na lista **Créditos em aberto** da aba de config, com **Agendar** (RPC `reposicao_agendar`:
  data até o vencimento; aula original paga → reposição **isenta R$ 0**; pendente → a cobrança
  passa para a reposição) e **Anular**. Consulta de reposição leva a etiqueta **🔄 reposição**
  (`observacoes` começa com "🔄 Reposição"). **Sessão de pacote não gera crédito** (cancelar já
  devolve a sessão ao pacote). Se a reposição for cancelada/excluída, o crédito **volta**
  (gatilho em `consultas`); se a aula original "descancelar", o crédito é anulado. Vencimento é
  calculado (sem cron): `disponivel` com `expira_em` no passado = vencido. Tabela
  `reposicao_creditos` só é escrita pelas RPCs (RLS: dono/recepção leem; profissional não vê).
  **Aluno marcando sozinho** (`quem_remarca='aluno'`): o `/agendar/<slug>` mostra "Repor aula" →
  CPF + WhatsApp (os dois têm que bater com o cadastro) → dias só até o vencimento, horários
  escondidos só quando a turma lota → RPC pública `reposicao_publica_agendar` (usa o crédito
  que vence primeiro; alerta "🔄 Reposição marcada pelo aluno"). RPCs públicas:
  `reposicao_publica_info/creditos/lotados/agendar` (**sem hCaptcha** — ver follow-up no
  histórico). Sem a migration no banco, tudo fica escondido (front tolerante).
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
  aos dados certos; sem vínculo a pessoa não vê nenhum paciente). **Fase 3
  (2026-07-05):** o portal ganhou **Avaliações** (registrar/ler EVA, goniometria,
  postural e testes funcionais dos pacientes dele, com gráfico da dor — cada
  registro assinado com o `profissional_id` do vínculo; RLS: SELECT/INSERT, sem
  editar/apagar), **Exames** (só leitura, via URL assinada) e **teleconsulta**
  (badge 📹 + botão "Entrar na sala" nas consultas por vídeo).
- **Prontuário estruturado de fisio (Avaliações)** *(Fase 3, 2026-07-05)* — aba
  **Avaliações** na ficha do paciente, com 4 templates clínicos: **EVA de dor**
  (escala 0–10 com slider, local, observação e **gráfico de evolução da dor** —
  SVG inline, aparece a partir de 2 medições), **Goniometria** (medidas por
  articulação/movimento/lado com ADM ativa e passiva em graus, linhas dinâmicas),
  **Avaliação postural** (vistas anterior/lateral/posterior) e **Testes
  funcionais** (TUG, Sentar-levantar 30s, Caminhada 6min, Berg, dinamometria…
  com resultado + unidade). Tabela **`avaliacoes`** (tipo + `dados` JSONB),
  RLS espelhando `evolucoes`: dono/recepção tudo; **profissional lê e registra
  só dos pacientes dele, sem editar/apagar**. Registra na trilha de auditoria
  LGPD e entra na exportação de dados do titular.
- **Exames anexados** *(Fase 3, 2026-07-05)* — aba **Exames** na ficha: anexar
  PDF/imagem (JPG, PNG, WebP, HEIC) de até **10 MB** no bucket **privado**
  `exames` do Supabase Storage (caminho `clinica_id/paciente_id/…`; policies por
  papel: dono/recepção tudo, profissional **só leitura** dos pacientes dele,
  anon nada). Abrir/baixar via **URL assinada** (5 min). ⚠️ O Storage **bloqueia
  DELETE via SQL** — por isso quem apaga os arquivos é o **front via Storage
  API**: no "Eliminar dados pessoais"/"Excluir paciente", os exames saem
  **primeiro** e, se falhar, a operação **não segue** (fail-closed LGPD).
- **Teleconsulta** *(Fase 3, 2026-07-05)* — checkbox **"📹 Teleconsulta"** no
  agendamento; a consulta ganha badge nas agendas (dia/semana/mobile/ficha) e
  botões de **Entrar na sala** e **Enviar link ao paciente** (mensagem pronta no
  wa.me). A sala é **Jitsi Meet** (grátis, sem conta, sem servidor próprio), com
  nome derivado do id da consulta (`NastaDesk-<20 hex>` — não adivinhável).
  Coluna `consultas.teleconsulta` (boolean default false, aditiva). O Portal do
  Profissional também mostra o badge e entra na mesma sala.
- **Lista de espera** *(Fase 3, 2026-07-05)* — botão **"Lista de espera"** (com
  contador) na tela Agendamentos: fila de quem aguarda horário — paciente
  cadastrado OU só nome+WhatsApp, com preferência de horário, modalidade e
  profissional. Ações por pessoa: **WhatsApp** (1 clique), **Agendar** (abre o
  modal de consulta já preenchido e, ao salvar, **tira da fila sozinho**) e
  **Remover** (só marca `status='removido'` — nada é apagado). Tabela
  **`lista_espera`** (RLS: dono/recepção; profissional sem acesso).
- **Controle de estoque** *(Extras, 2026-07-06)* — seção **Estoque** na nav (dono +
  recepção; profissional não vê): itens com categoria/unidade/estoque mínimo,
  **Entrada/Saída com motivo** (o saldo é mantido por **trigger no banco** — o front
  só insere movimentos, preservando o histórico), etiqueta **"⚠ repor"** + badge na
  nav quando abaixo do mínimo, busca/filtro e arquivar (soft — nada apagado).
  Tabelas `estoque_itens` + `estoque_movimentos`.
- **NPS por WhatsApp** *(Extras, 2026-07-06)* — card no Relatório: **enviar pesquisa
  em 1 clique** (wa.me com mensagem editável; o envio é registrado antes de abrir o
  WhatsApp), registrar a **nota 0–10 + comentário** quando o paciente responde, e
  **score NPS do mês** (promotores − detratores) com breakdown. Tabela
  `nps_respostas` (LGPD: anonimizar/excluir paciente limpam o NPS dele).
- **Integração Google Agenda / Outlook** *(Extras, 2026-07-06)* — (a) botão **📅** em
  cada consulta (Agenda do dia e salões): adicionar no **Google Agenda**, **Outlook**
  ou **baixar .ics**; (b) **feed de assinatura ICS** (Configurações → Agenda): cola a
  URL no calendário e a agenda inteira sincroniza sozinha (edge `agenda-ics`, segredo
  `ics_token` regenerável).
- **Relatório exportável** *(Extras, 2026-07-06)* — no Relatório mensal: **⬇ CSV**
  (consultas do mês com paciente/status/modalidade/profissional/valor/pagamento +
  total recebido; abre no Excel/Planilhas) e **🖨 Imprimir/PDF** (CSS de impressão
  dedicado — imprime só o relatório, sem menus).
- **Documentos do paciente + modelos da clínica** *(2026-07-07, pedido de cliente por
  áudio)* — aba **Docs** na ficha do paciente: anexar a **via assinada** de documentos
  (📋 Regras do estúdio, 📝 Contrato de prestação, 📸 Consentimento de uso de imagem,
  📎 Outro) com **checklist assinado ✓ / pendente** por paciente; abrir por URL assinada
  (5 min) e excluir com confirmação. Em **Configurações → Documentos**, a clínica guarda
  os **modelos** (arquivos base para imprimir/enviar quando chega paciente novo).
  **Zero migration:** tudo no bucket privado `exames` já existente — documentos do
  paciente em `clinica_id/paciente_id/` com prefixo de nome `doc__<tipo>__` (a aba
  Exames filtra fora; a limpeza LGPD, que apaga o prefixo inteiro, **já cobre os
  documentos** fail-closed) e modelos em `clinica_id/_modelos/` (fora dos fluxos por
  paciente; policies por clínica já cobrem). Exportação LGPD lista
  `documentos_anexados` separado dos exames; auditoria: `anexou/baixou/excluiu_documento`.
- **Marca oficial (logo Nastaclin)** *(2026-08-30)* — o "N" provisório saiu; agora o app usa a
  **logo oficial NC/NASTACLIN** (`/logo.png`, gerada de `marketing/logo-mark.png`) no splash, no
  login, no onboarding, na sidebar, no cabeçalho do celular, no Portal do Profissional, na página
  pública de agendamento, no `confirmado.html`, nas páginas legais e no painel admin. Como a logo
  tem o "C" em verde escuro, sobre fundo verde ela vai numa **pastilha branca** (legibilidade).
  **Favicon e ícones do PWA** (192/512/apple-touch + versões *maskable*) regerados a partir dela;
  `sw.js` teve a versão de cache subida (`nastadesk-v2-2026-08-30`) para o ícone antigo não ficar preso.
- **Assinatura mensal, trimestral e anual** *(2026-08-30)* — a tela **Planos** e o **paywall** ganharam
  um seletor de período: **Mensal** · **Trimestral (-10%)** · **Anual (-20%)**. Preços por período —
  mensal 97/197/347, trimestral **262/532/937**, anual **931/1891/3331** — com "equivale a R$ X/mês" no
  card. Quem fecha **anual ganha o site da clínica de graça**; no **trimestral** o site sai **pela metade**
  (isso aparece como benefício dentro de cada card). Os links de checkout são **por plano × período** e
  ficam na tabela `config_publica` (o dono edita no painel admin, sem mexer no código); enquanto um
  período não tiver link cadastrado, o botão **avisa e oferece o WhatsApp** em vez de quebrar. Coluna
  aditiva `assinaturas.periodo` (null = mensal legado). ⚠️ **MRR no painel admin é mensalizado**
  (anual ÷ 12, trimestral ÷ 3) — uma venda anual não infla a métrica.
- **Site da clínica (Conta → Minha Clínica)** *(2026-08-30)* — card próprio explicando o serviço de
  **site institucional feito pela Nastaclin**: tabela de preços (**R$ 500** cheio · **R$ 250** no
  trimestral · **grátis** no anual), o que está incluso, e o **preço que vale para aquele cliente**
  conforme o período que ele assina. O botão **"🚀 Quero meu site"** registra o pedido
  (RPC `site_solicitar`) e abre o **WhatsApp com mensagem pronta**. Quando o site fica pronto, o admin
  marca **"No ar"** e **a tela do cliente muda sozinha** para **"Seu site"** com o endereço e o botão
  **"✏️ Quero mudar algo no site"** (outra mensagem pronta) — vale também para quem já tinha feito o
  site antes de assinar. Tabela `sites` (1 por clínica): o cliente **só lê** a própria linha (RLS);
  status/URL/valores são do admin. Estados: pedido enviado → em produção → no ar.
- **Cupom de desconto (parcerias)** *(2026-08-30)* — campo **"🎟️ Tenho um cupom"** nos Planos, no
  paywall e na área Site. O app **valida o código no servidor**, mostra o preço riscado com o desconto e
  **registra o uso** antes de mandar o cliente ao checkout (o código também vai na URL da Cakto). O
  desconto real sai na **Cakto** — o mesmo código precisa estar cadastrado lá. O cliente **nunca vê** o
  parceiro nem a comissão: as tabelas `cupons`/`cupom_usos` são **fechadas** (deny-all, como
  `admin_config`) e o app só conversa com elas por 2 RPCs `SECURITY DEFINER` que devolvem só o desconto.
  Quando o pagamento é confirmado, o `cakto-webhook` marca o uso como **confirmado** (é isso que vira
  comissão a pagar no painel).
- **Tela "confirme seu e-mail" no cadastro** *(2026-08-30)* — ao criar a conta, em vez de uma
  faixinha verde no topo (que muita gente não via, e por isso ficava sem confirmar), **a tela
  inteira muda**: ícone de envelope, o e-mail digitado em destaque, os 3 passos do que fazer,
  aviso de spam/Promoções, botão **"Abrir meu e-mail"** (aparece quando dá para saber o webmail:
  Gmail, Outlook, Yahoo, iCloud, UOL, Terra), **"Reenviar o e-mail de confirmação"** (com trava
  de 60s para não estourar o limite de envio) e "Voltar para o login". O formulário é limpo depois
  do cadastro.
- **E-mails de conta em português e com a marca** *(2026-08-30)* — templates prontos em
  `supabase/templates/` (`confirmacao-cadastro.html` e `recuperacao-senha.html`): layout da
  Nastaclin com a logo, texto em português, botão grande e link alternativo. **Remetente
  "Nastaclin":** decidido em 2026-08-30 usar **SMTP próprio na Resend** com o domínio
  **`nastadesk.com`/`.com.br`** (o `nastaclin.com` fica para o site institucional) — passo a
  passo completo no **`supabase/templates/README.md`**. ⚠️ Enquanto o SMTP não estiver ligado,
  o remetente continua "Supabase Auth" **e vale o teto de poucos e-mails por hora** do serviço
  embutido do Supabase (que a documentação diz não servir para produção).
- **Conta de demonstração (`MODO_DEMO`)** *(2026-08-30)* — um login que abre uma **clínica de
  exemplo cheia de dados** (agenda de hoje, 14 pacientes, ~310 consultas, financeiro, mensalidades,
  pacotes, despesas, estoque, NPS, conversas de WhatsApp, avaliações, lista de espera) para mandar
  a quem quer conhecer a ferramenta. **Nada toca o Supabase:** quando o login bate com
  `config_publica.demo`, o app troca o cliente do Supabase por um **cliente falso** que responde
  de um "banco" no **`sessionStorage`** do próprio navegador. Quem testa pode criar, editar e
  excluir à vontade; **ao fechar a aba/navegador tudo se apaga e a demonstração volta ao estado
  inicial** (tem também o botão "Recomeçar do zero" no banner). Detalhes na seção 11.
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
- **Declaração de comparecimento e atestado em 1 clique** *(2026-10-24)* — botões
  **📄 Declaração de comparecimento** e **🩺 Atestado** no modal de ações da consulta (grade
  semanal/lista) e **📄** em cada consulta da ficha do paciente. Abre o modal `modal-documento`
  (chegada/saída já preenchidas com o horário + `intervalo_consulta`; acompanhante opcional na
  declaração; no atestado, dias de afastamento, observações e **CID/CIF só com o checkbox de
  autorização do paciente** — dado sensível/LGPD) e gera uma página para **Imprimir/Salvar PDF**
  no mesmo visual do recibo. **Quem assina:** o profissional da consulta (nome + `profissionais.registro`)
  ou, sem profissional, o responsável + `clinicas.recibo_registro`. **Atestado sem CREFITO é
  bloqueado** (Resolução COFFITO 381/2010; o rodapé cita a resolução); a declaração sai só com o
  nome e um aviso. Avisa se a consulta não está "Atendido"/está cancelada. **Só leitura** — nada
  é gravado além da trilha de auditoria (`logAcesso` → `emitiu_declaracao`/`emitiu_atestado`).
  Funções: `abrirDocumentoConsulta`, `docAtualizarTipo`, `assinanteDocumento`, `gerarDocumentoConsulta`.
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
- **Interface responsiva / mobile-first** *(redesign 2026-07-07)* — o painel funciona como
  **aplicativo no celular** (não precisa mais do modo "site para computador"): **barra de
  navegação inferior** (Agenda/Semana/Lembretes/Pacientes/Financeiro/Mais), **cabeçalho fixo**
  com a marca + sino, **menu "Mais" e modais como bottom sheets**, **ficha do paciente e
  notificações em tela cheia**, inputs a 16px (sem zoom do iOS), alvos de toque grandes e
  safe-areas (notch). No desktop, a **sidebar** ganhou o selo da marca e destaque no item
  ativo. Visual modernizado **mantendo o verde Nastaclin + DM Sans/DM Serif** (sombras/raios
  refinados, botões com leve gradiente, fundo com brilho radial). O mesmo tratamento vale na
  **página pública de agendamento**, no **Portal do Profissional** e nas **páginas legais**.
  **É só front-end (CSS/HTML) — não muda dados, agenda, banco nem edge functions.**
- **Relatório mensal** — comparecimento, faturamento, origem dos agendamentos,
  formas de pagamento.
- **Chatbot de WhatsApp** — ver seção 6.
- **Conta** — onboarding guiado, recuperação de senha, configuração de horários
  e mensagens. **Privacidade e segurança** (em Minha Clínica): **verificação em duas
  etapas (2FA/TOTP)** opt-in (Supabase Auth nativo, com desafio no login) e **aceite
  do DPA** (contrato de operador — página `dpa.html`, registrado em `consentimentos`).

## 5. Planos, preços e acesso

### Preços por plano e período (atualizado 2026-08-30)

| Plano | Mensal | Trimestral (−10%) | Anual (−20%) | Observações |
|---|---|---|---|---|
| **Básica** | **R$ 97** | **R$ 262** (R$ 87/mês) | **R$ 931** (R$ 78/mês) | Gestão + lembretes manuais por WhatsApp. **Sem chatbot de IA. Sem multi-profissional/logins de equipe** (1 login, o dono). |
| **Profissional** | **R$ 197** | **R$ 532** (R$ 177/mês) | **R$ 1.891** (R$ 158/mês) | Inclui o **chatbot de WhatsApp com IA** + **vários profissionais e logins de equipe** (recepção/profissional). |
| **Premium** | **R$ 347** | **R$ 937** (R$ 312/mês) | **R$ 3.331** (R$ 278/mês) | Tudo do Profissional (tier mais alto). |

> **Fonte da verdade do preço é o BANCO** — a função `public.nastadesk_preco(plano, periodo)`.
> O front tem os mesmos números só para exibir; quem calcula desconto de cupom é o servidor.
> Ao mudar preço: atualizar **os 3 lugares** — `nastadesk_preco` (banco), `PRECOS_PERIODO`
> (`nastadesk/index.html`), `PRECO` (`cakto-webhook`) e `PRECOS_PERIODO_ADM` (`dashboard/index.html`).

**Brinde por período (o site da clínica):** anual → **site grátis**; trimestral → **site pela metade
(R$ 250)**; mensal → site por R$ 500. Os valores ficam em `config_publica.site` (editável no painel admin).

**Links de checkout:** um por **plano × período** em `config_publica.checkout_links` — **os 9 já
estão preenchidos e funcionando** (as 6 ofertas de trimestral/anual foram criadas na Cakto em
2026-08-30, ver Histórico). Para trocar um link, o caminho é **Painel admin → Configurações**
(não mexe no código). Se algum período ficar sem link, o botão avisa o cliente e oferece o
WhatsApp em vez de quebrar.

| Plano | Mensal | Trimestral (90 dias) | Anual (365 dias) |
|---|---|---|---|
| Básica | `ad8vfmf_949243` | `7u3jnuu` | `67d8hke` |
| Profissional | `w3ryxws_949248` | `k6xzi95` | `368fhmd` |
| Premium | `cvv64ck_949254` | `ixvgfda` | `3f9pcy6` |

> O link é `https://pay.cakto.com.br/<id da oferta>`. **O sufixo numérico dos links mensais
> (`_949243`) é decorativo** — o checkout resolve só pelo id da oferta (confirmado contra
> `api.cakto.com.br/api/product/checkout/<id>/`). Por isso as ofertas novas não têm sufixo.
> A **API pública da Cakto NÃO devolve a URL do checkout** em nenhum campo: para descobrir o
> link de uma oferta nova, monte a URL com o `id` que o `offers_create` devolve.
> ⚠️ `offers_create` **não tem idempotência** — repetir a chamada cria oferta duplicada.

### Cupons de parceria (2026-08-30)

O dono fecha parceria com quem indica o NastaDesk. Cada parceiro tem um **código próprio**:
- O cupom é cadastrado **em dois lugares**: na **Cakto** (é lá que o desconto sai no pagamento) e no
  **painel admin** (rastreio: parceiro, desconto, comissão, quantos usaram no mês).
- Desconto: **% ou R$**, com **duração** (só o 1º mês, N meses, ou para sempre) e escopo
  (**assinatura**, **site** ou ambos); dá para pôr **validade** e **limite de usos**.
- Comissão do parceiro: **% do que o cliente pagou** ou **R$ fixo por cliente**, com marcação de
  **recorrente**; o painel fecha por **mês (competência)** e tem botão **"Marcar pago"**.
- O uso nasce **pendente** e vira **confirmado** quando o `cakto-webhook` confirma o pagamento —
  então o "a repassar" só conta cliente que pagou de verdade.

### Regra de acesso (trial + paywall + cortesia) — atualizada 2026-07-06

- **Trial self-service (decisão do dono, 2026-07-06):** ao se cadastrar, a clínica
  ganha automaticamente **7 dias grátis no plano Premium** (`ativo=true`,
  `cortesia=true`, `cortesia_expira_em = now()+7d`, no gatilho de signup). O app
  mostra banner com os dias restantes; o cadastro anuncia "7 dias grátis, sem cartão".
- **Corte automático:** o job **pg_cron `nastadesk-cortesia-expira`** (de hora em
  hora) roda `encerrar_cortesias_vencidas()`: cortesia/trial com `cortesia_expira_em`
  no passado → `ativo=false` + `cortesia=false` (vira paywall "Seu teste grátis
  terminou"). **GUARDA: nunca corta clínica com assinatura `ativa`/`em_atraso`**
  (quem pagou não cai, mesmo com flag de cortesia sobrando). Cortesia **sem data**
  (null) nunca é cortada.
- O "porteiro" de acesso continua sendo o campo **`clinicas.ativo`**. Só com
  `ativo = true` a clínica usa o sistema.
- **Trava (2026-10-24, migration `20261024120000`):** o dono **não** consegue alterar
  `ativo`/`plano`/`cortesia`/`cortesia_expira_em` pela API (trigger
  `trg_clinicas_proteger_acesso`). Só webhook, admin-api e funções `admin_*`/`encerrar_*`.
- **Cancelou a assinatura?** O acesso vai até `assinaturas.proximo_pagamento`; o pg_cron
  **`nastadesk-assinatura-expira`** (minuto 17 de cada hora) desliga depois. Reembolso e
  chargeback cortam na hora.
- O acesso também é liberado de duas formas:
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
  na tabela `ia_uso` (ver seção 7) via RPC `ia_registrar_uso`, que também soma o
  custo do mês em `ia_cota_mensal`. O registro é tolerante a falhas: se a
  gravação falhar, o bot responde normalmente assim mesmo (e agora **loga** o
  erro — antes o `try/catch` não pegava nada, porque o supabase-js devolve
  `{ error }` em vez de lançar exceção).
- **Trava de IA** *(2026-10-19)* — impede o custo de IA passar do valor da assinatura.
  - **1 "conversa de IA" = 1 paciente (conversa) que usou a IA num dia** (fuso de SP).
    Decisão da Roberta. Todas as mensagens de IA desse paciente no dia contam 1.
  - **Profissional:** até **1.500 conversas/mês** OU **R$ 70 de custo real** no mês, o
    que vier primeiro. Estourou → para **conversa nova** o robô responde só com as
    infos básicas da clínica (endereço/valor/dias) + **menu** — agendar, confirmar e
    atendente continuam funcionando (não usam IA). Nunca deixa o paciente sem resposta.
    Por que o teto em R$: a cota em conversas sozinha não garante — no pior caso
    (FAQ enorme, todo mundo batendo o limite diário) 1.500 conversas custariam ~R$ 735.
  - **Premium:** ilimitado, como a página de planos promete. Acima de **6.000 conversas
    ou R$ 120** no mês só registra o marco **"Teto Premium"** para o admin; nunca bloqueia.
  - **Limite diário por telefone:** **15 mensagens à IA**. Passou → alerta para a clínica,
    resposta "vou chamar um atendente" e `conversas.bot_pausado_ate` = meia-noite (o robô
    pausa só para aquele contato até o dia seguinte; não desliga o bot da conversa).
  - **Avisos para a clínica** em **80% e 100%** da cota (tabela `alertas`, tipo `whatsapp`,
    1 por marco por mês — garantido pela PK de `ia_cota_eventos`). Uso da cota = o
    **maior** entre % de conversas e % do teto de custo.
  - **Tudo configurável** em `admin_config.ia_limites` (editável no painel → Trava de IA).
    Preços do Claude e câmbio usados pela trava vêm do card "API Claude" em
    `admin_config.custos` (um lugar só). O câmbio da trava é o **manual** (`cambio_brl`);
    o painel usa o ao vivo para exibir.
  - **Atômico:** `ia_checar_e_contar` trava a linha do mês da clínica (`FOR UPDATE`) —
    mensagens simultâneas não furam a cota. **Fail-open:** se a checagem der erro, o
    robô responde com IA normalmente.
  - Tabelas (migration `20261019120000_trava_ia_cota.sql`, no repo nastadesk):
    `ia_conversas` (conversa × dia → nº de chamadas; **não guarda telefone**),
    `ia_cota_mensal` (clínica × mês → conversas, chamadas, bloqueadas, limite_diario,
    custo_usd; a clínica pode **ler** a própria linha), `ia_cota_eventos` (marcos).
    RLS ligado nas 3; RPCs só para `service_role`.
  - Custo estimado (out/2026): ~R$ 0,013 por mensagem à IA; ~R$ 0,04 por conversa
    típica; ~R$ 60 para 1.500 conversas normais.

## 7. Painel admin (dashboard / nastaclin-admin)

Seções:
- **Visão geral** — clientes ativos, MRR (receita recorrente das assinaturas
  ativas), custos mensais e margem. ⚠️ **MRR mensalizado** desde 2026-08-30:
  assinatura anual conta `valor/12` e trimestral `valor/3` (uma venda anual de
  R$ 3.331 entra como ~R$ 278/mês, não R$ 3.331).
- **Clientes** — todas as clínicas com plano, status (Ativa / Cortesia / Sem
  plano / Suspensa), status da assinatura e receita/mês.
- **Assinaturas** — concede cortesia e remove acesso (via RPCs admin que só
  rodam com service_role, nunca pelo navegador).
- **Cupons** *(2026-08-30)* — criar/editar cupom de parceria (código, parceiro + contato +
  chave Pix, desconto % ou R$, duração, escopo assinatura/site/ambos, comissão % ou R$,
  recorrente, validade, limite de usos, observação). Cards do mês: cupons ativos, usos,
  **comissão a pagar** e **já repassado**. Tabela de **repasse por parceiro** com seletor de
  **mês (competência)** e botão **"Marcar pago"**; e a lista **"Quem usou cupom"** (cliente,
  cupom, o que comprou, quanto pagou, comissão, status) com **Confirmar/Cancelar** manual.
  Excluir cupom **não apaga o histórico** de uso (o código fica gravado no registro).
- **Sites** *(2026-08-30)* — todos os pedidos e sites entregues: status (Pedido / Em produção /
  No ar / Cancelado), endereço, data do pedido, valor cobrado e recebido, se foi cortesia e o
  cupom usado. Marcar **"No ar" + URL** é o que faz a tela do cliente virar "editar site".
  Dá para lançar um site **na mão** para quem fez o site antes de assinar.
- **Configurações** *(2026-08-30)* — os **9 links de checkout** (3 planos × 3 períodos), os dados
  do **site** (WhatsApp que recebe os pedidos + preços mensal/trimestral/anual) e o **login da conta
  de demonstração** (e-mail, senha, liga/desliga + **mensagem pronta para enviar**, com botão de
  copiar). Salva em `config_publica`; o app das clínicas lê de lá — **não precisa mexer no código
  para trocar link, número ou a senha da demonstração.**
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
- **Cache com preço próprio** *(2026-10-19)*: escrita US$ 1,25/1M e leitura US$ 0,10/1M
  (antes entravam como entrada normal). A soma de tokens é feita no banco
  (`admin_ia_uso_mes`) — a API do Supabase devolve no máximo 1.000 linhas, então
  somar no código subestimaria o custo em silêncio.

### Trava de IA (seção própria do painel, 2026-10-19)

Aba **"Trava de IA"**: seletor de mês (últimos 6), cards (custo de IA do mês, conversas,
custo médio por conversa, clínicas ≥ 80%), tabela **por clínica** (plano, conversas,
mensagens à IA, barra de **uso da cota**, custo em R$/US$, **receita mensalizada**,
**margem = receita − custo de IA**, situação Normal / Perto do limite / Só menu /
Acima do teto + contadores de "só menu" e limite diário), **formulário dos limites**
(salva em `admin_config.ia_limites`) e lista dos **marcos do mês**.

## 8. Estado atual / o que está no ar

- App das clínicas e painel admin **em produção** na Vercel, publicados pelo workflow
  `deploy-vercel.yml` (GitHub Actions). Em **2026-08-30** os 2 domínios voltaram a
  publicar e estão servindo a entrega daquele dia (logo oficial, períodos, Site, cupons)
  — conferido no ar. **Banco e edge functions** são deployados direto no Supabase, não
  passam pela Vercel.
- Backend Supabase em produção (uma instância compartilhada).
- **2 clínicas clientes** usando a ferramenta (na época deste registro).
- Rastreio de custo real da IA (`ia_uso` + registro no webhook + card no painel)
  **deployado e ativo** desde 2026-06-29.
- **Trava de IA** (cota por plano + limite diário + aba no painel): ver Histórico
  2026-10-19 para o estado do deploy.

## 9. Histórico de mudanças

> Adicione aqui toda alteração relevante (mais recente no topo).

- **2026-10-24 (9)** — **Reposição de aulas com crédito para pilates (regras configuráveis por clínica) — NO AR: migration APLICADA em produção e merge na `main` (com o OK do Eduardo).** *(Pedido do Eduardo.)*
  **Banco (migration `20261025015303_reposicao_aulas_creditos.sql`, só aditivo):** tabelas `reposicao_config` (1 linha por clínica; dono SELECT/INSERT/UPDATE, recepção só SELECT) e `reposicao_creditos` (dono/recepção SELECT; INSERT/UPDATE/DELETE revogados — escrita só por RPC); funções `reposicao_pode_gerir`, `reposicao_calcular_expira`; gatilho `trg_reposicao_consulta` em `consultas` (DELETE e UPDATE OF status: reposição cancelada/excluída devolve o crédito; aula original "descancelada" anula o crédito); RPCs autenticadas `reposicao_registrar_falta`, `reposicao_agendar`, `reposicao_cancelar_credito`; RPCs públicas (anon) `reposicao_publica_info`, `reposicao_publica_creditos`, `reposicao_publica_lotados`, `reposicao_publica_agendar` (+ `reposicao_publica_aluno` interna, sem grant). Nenhuma coluna/constraint de tabela existente muda. Coluna `reposicoes_anteriores` evita crédito em dobro (reposição cancelada pelo menu e depois "avisou a falta").
  **Teste em produção numa transação desfeita: 41/41** — fixtures de 2 clínicas e papéis simulados por JWT: regras de prazo/modalidade/pacote/exceção, crédito em dobro bloqueado, devolução pelo gatilho, isolamento entre clínicas (dono não grava config de outra), limites das regras, escrita direta na tabela bloqueada, anon sem leitura da tabela e o fluxo público. Conferido depois: **zero resíduo** (nenhuma tabela/função/gatilho/linha de teste ficou).
  **Front:** `index.html` (aba de config, "🔄 Aluno avisou a falta" no menu de status e no modal de ações, modais de falta e de agendar reposição, créditos na ficha, etiqueta 🔄 reposição, créditos no export LGPD, semente + RPCs simuladas no `MODO_DEMO`) e `agendar.html` (fluxo "Repor aula"). **Validado no navegador em modo demonstração** (salvar regras, falta fora do prazo → oferece exceção, falta no prazo → crédito + alerta, agendar reposição → isenta, cancelar a reposição → crédito volta, ficha com histórico/vencido; zero erro de JS) e o `/agendar` com RPCs simuladas (crédito, dias até o vencimento, lotados, confirmação).
  **Publicado (com o OK do Eduardo):** migration aplicada → os 41 testes rodados de novo contra o banco já com a migration, numa transação desfeita: **41/41, zero resíduo** → advisors sem achado novo além do padrão já aceito (RPCs públicas do `/agendar` e RPCs SECURITY DEFINER do painel; as 2 tabelas novas com RLS e policies) → merge na `main`. A função nasce **desligada** em toda clínica: só aparece quando o dono liga em Configurações → Reposição de aulas.
  **Follow-ups:** (a) as RPCs públicas de reposição (e a `agendar_online`, já hoje) são chamáveis direto pelo anon, **sem hCaptcha** — passar por uma edge com captcha; (b) a recepção não vê Configurações, então só enxerga créditos pela ficha do aluno — avaliar um botão "🔄 Reposições" em Agendamentos; (c) a demo usa status `faltou`, que não existe no banco.

- **2026-10-24 (8)** — **WhatsApp ignora grupos na Evolution + trava de IA re-testada + e-mail próprio em andamento.** *(Eduardo.)*
  **(1) `whatsapp-conexao` v11 (deployada):** no "Conectar", a instância é criada com `groupsIgnore: true` e, a cada conexão, a função chama `POST /settings/set/{instância}` com `groupsIgnore: true` (e `rejectCall/alwaysOnline/readMessages/readStatus/syncFullHistory: false`). **Por quê:** a Evolution mandava **toda mensagem de grupo** ao `whatsapp-webhook` (o código só descartava lá dentro) — cada uma é 1 chamada de Edge Function, e o Supabase Free tem **500 mil/mês**. É o equivalente no NastaDesk ao estouro do Upstash do robô do Avalia Aí (500 mil comandos/mês, painel recarregando a cada 20 s). Tolerante a falha (se a Evolution recusar, o QR segue; o webhook continua filtrando). Loga `whatsapp-conexao settings/set <instância> <status>`. ⚠️ **Falta confirmar o status 200 no log** depois do próximo "Conectar WhatsApp" (nenhuma clínica conectada hoje).
  **(2) Trava de IA re-testada em produção (transação desfeita, 8/8):** limite diário 15/telefone (todos os planos), Profissional barra em 1.500 conversas ou R$ 70 (câmbio manual 5,40), aviso em 80%, Premium só marca, Básico sem robô. ⚠️ Teste grátis = Premium → só o limite diário vale nos 7 dias (sugestão: trial seguir os limites do Profissional).
  **(3) Comparativo com o Avalia Aí:** o NastaDesk não usa Upstash/QStash; polling leve (sininho 60 s, QR 30×4 s, pagamento 6×5 s, admin câmbio 10 min); realtime é push.
  **(4) E-mail de cadastro:** o Eduardo comprou o domínio na GoDaddy e ligou no Resend; falta o SMTP no Supabase (remetente **Nastaclin**), subir o rate limit e colar os 2 templates. Passo a passo no Obsidian (`Eduardo/Projetos/NastaClin/NastaDesk - E-mail do cadastro (Resend)`).

- **2026-10-24 (7)** — **Teste grátis + assinatura cancelada: o corte agora respeita o período pago.** *(Eduardo; só banco.)*
  **Bug:** quem assinava **durante** o teste grátis (`cortesia=true`) e depois cancelava perdia os dias pagos — `encerrar_cortesias_vencidas()` (job `nastadesk-cortesia-expira`) cortava assim que o teste vencia, porque só poupava assinaturas `ativa`/`em_atraso`; e o `cakto-webhook` não corta clínica em cortesia, então ninguém mais segurava. Caminho comum: testa → assina → semanas depois cancela → cortado na hora.
  **Correção:** migration `20261024132856_cortesia_respeita_periodo_pago` (aplicada em produção) — a função também poupa assinatura `cancelada` com `proximo_pagamento` no futuro; quando o período acaba, o mesmo job corta. Reembolso grava `proximo_pagamento = agora`, então reembolsado continua sendo cortado.
  **Testes (transação desfeita, 7/7):** cancelou com 20 dias pagos → mantém; período acabou → corta; teste vencido sem pagar → corta (como antes); com assinatura ativa → não corta (como antes); reembolsado → corta; outras clínicas intactas; a conta de teste `lumxarashop` continua ativa. Conferido depois: regra nova no ar, job ativo, `authenticated` sem permissão de executar.

- **2026-10-24 (6)** — **✅ Cancelar com reembolso FUNCIONANDO em produção (teste real ponta a ponta aprovado).**
  **Causa do 401 persistente:** os secrets `CAKTO_CLIENT_ID`/`CAKTO_CLIENT_SECRET` **chegavam vazios** na função (o diagnóstico mostrou 0 caracteres) — não estavam salvos com esses nomes no projeto. O Eduardo apagou tudo, criou uma chave nova na Cakto com **Leitura + Escrita + Pedidos + Assinaturas** e cadastrou os 2 secrets pelo painel (Edge Functions → Secrets). Obs.: salvar secrets no painel **sobe a versão** da função sozinho (v5/v6 apareceram sem deploy nosso). `cakto-cancelar` está na **v7** (= repo `fe334c4`): `trim` dos secrets + diagnóstico do 401 que loga só o início do client_id, os tamanhos e os **nomes** das variáveis com "cakto" (nunca valores).
  **Teste real (conta de teste `lumxarashop`, assinatura de R$ 5,99 paga hoje):** clique em "Cancelar e reembolsar" → Cakto: pedido `refunded` (13:21 UTC), assinatura `canceled`, sem próxima cobrança → webhook recebeu `refund` (classe corta) → banco: assinatura `cancelada`, auditoria `reembolsou_assinatura` com valor 5.99 → clínica **continua ativa no teste grátis** (cortesia até 31/10), como esperado.
  **Limpeza:** oferta de teste `6btwpm2` **desativada** (status `disabled`, não apagada).

- **2026-10-24 (5)** — **Cancelar no app vira automático, com reembolso integral em até 7 dias (direito de arrependimento) — BRANCH `cancelar-com-reembolso`, ainda não publicada.** *(Pedido do Eduardo.)*
  **Por que o cancelamento falhou no teste:** a `cakto-cancelar` v2 recebeu **401 (`token Cakto 401`)** ao pedir o token: os secrets `CAKTO_CLIENT_ID`/`CAKTO_CLIENT_SECRET` cadastrados no Supabase **não são aceitos pela Cakto** (credencial inválida). O app caiu no plano B ("Não conseguimos cancelar automaticamente"). **Ação manual:** criar uma chave nova na Cakto com escopos **subscriptions + orders** (leitura e escrita — o reembolso usa `orders`) e recadastrar os 2 secrets.
  **Regra (Cakto + CDC art. 49):** na Cakto, *cancelar* só encerra as cobranças futuras (o assinante usa até o fim do ciclo) e *reembolsar* devolve o dinheiro, encerra a assinatura e corta o acesso na hora. O comprador já pode pedir reembolso em até 7 dias em reembolso.cakto.com.br.
  **`cakto-cancelar` v3 (no repo, NÃO deployada):** se a **primeira** compra paga da assinatura (`parent_order`, `paid_payments_quantity ≤ 1`) foi há **≤ 7 dias** → `POST /orders/{id}/refund/` (+ cancel por garantia), grava `cancelada` com `proximo_pagamento = agora`, auditoria `reembolsou_assinatura`, devolve `{ reembolsado: true, valor }`. Senão → só cancela, como antes (acesso até `proximo_pagamento`). O `cakto-webhook` v6 já trata o evento `refund` (corta, preservando cortesia/trial).
  **Front:** o modal de cancelar mostra "Cancelar e reembolsar" + texto dos 7 dias quando a assinatura tem < 7 dias (o servidor é quem decide de verdade); toast com o valor devolvido; recarrega a clínica depois. **Termos 1.2** (seção 4.4: cancelamento pelo próprio app, reembolso integral em 7 dias, sem reembolso proporcional depois) e `POLITICA_VERSAO` = 1.2.
  **Testes:** modo demo (texto dentro/fora dos 7 dias; resposta simulada de reembolso → toast "R$ 5,99 devolvido"); campos da Cakto conferidos na API com o pedido de teste real (`status` paid, `paidAt`, `amount` 5.99, `paid_payments_quantity` 1, `parent_order`).
  **Para publicar (na ordem):** nova chave da Cakto nos secrets → deploy da `cakto-cancelar` v3 → merge na `main` → teste com a assinatura de teste (`lumxarashop`, dentro dos 7 dias → deve devolver R$ 5,99) → desativar a oferta `6btwpm2`.

- **2026-10-24 (4)** — **🔴 Pagamento pela Cakto não liberava nenhuma clínica (corrigido) + aviso "use o mesmo e-mail" no checkout.** *(Eduardo, no teste real de assinatura.)*
  **Achado:** o Eduardo assinou uma **oferta de teste de R$ 5** (`6btwpm2`, criada no produto "Plano Básica" — a Cakto não aceita menos de R$ 5) com uma conta nova. A Cakto entregou `purchase_approved` e `subscription_created` (200), mas o webhook respondeu "e-mail sem clínica": **o gatilho de cadastro nunca gravava `clinicas.email`** e as **7 clínicas** do banco estavam com e-mail vazio. Ou seja, **nenhum pagamento pela Cakto teria liberado ninguém** desde a troca do Mercado Pago.
  **Banco (aplicado em produção, com o OK do Eduardo):** migration `20261024053400_clinicas_email_do_login` — trigger novo `trg_clinicas_preencher_email` (BEFORE INSERT: e-mail vazio recebe o e-mail do login; e-mail informado não é sobrescrito) + backfill das linhas vazias (7). Testada antes em transação desfeita (8/8: backfill = 7, nenhuma vazia, e-mail = login em todas, **nada além do e-mail mudou**, clínica nova nasce com e-mail, e-mail informado é mantido, a busca do webhook acha exatamente 1).
  **Liberação do teste:** o evento `subscription_created` foi **reenviado pela API da Cakto** → clínica de teste com assinatura `ativa` ligada à da Cakto (`provider_id` = id da assinatura), `proximo_pagamento` 24/11. ⚠️ Como R$ 5 não bate com nenhum preço, o webhook gravou `plano` = o da clínica (premium) e `valor` 347 — só cosmético no teste.
  **Front (branch `aviso-email-checkout`):** antes de abrir o checkout, um aviso mostra o e-mail da conta e explica que é por ele que a liberação é automática (o webhook mapeia por e-mail; trocar no checkout = não libera sozinho). `abrirModalConfirm` ganhou o 5º parâmetro opcional `{ positivo: true }` (botão verde em vez de vermelho). **Bug de camada corrigido:** confirmações abertas da tela de planos bloqueada (`#paywall-overlay`, z 99999) ficavam **por trás** dela — `#modal-confirm` agora tem z-index 100000.
  **Pendente:** teste do botão "Cancelar assinatura" com essa assinatura; desativar a oferta `6btwpm2` depois; bug do trial (quem assina no teste grátis e cancela depois que o teste venceu perde os dias pagos — `encerrar_cortesias_vencidas` ignora assinatura cancelada com período pago valendo; correção proposta, aguardando OK); replicar esta entrada no CLAUDE.md do `dashboard` no merge.

- **2026-10-24 (3)** — **Abas da ficha e de Configurações visíveis no computador, Termos 1.1 (WhatsApp não oficial) e fim da promessa de "contato em 24h".** *(Pedido da Roberta.)* Só front.
  **(1) Abas cortadas:** na ficha do paciente (painel de ~510px) **Docs e Anamnese** ficavam escondidas à direita e, como a barra de rolagem é oculta (`scrollbar-width:none`), com mouse não havia como chegar nelas; em Configurações (~1000px) **Salas, Modalidades, Profissionais e Documentos** idem. **Correção:** com mouse (`@media (hover:hover) and (pointer:fine)`) `.ficha-tabs` e `.cfg-tabs` (classe nova no container) **quebram linha** — tudo visível. No toque continua deslizando, com **esmaecido nas bordas** quando há abas escondidas (`abasFichaAtualizar()` liga `.mais-esq/.mais-dir`) e a aba tocada é **centralizada** (`fichaTab`; com fallback sem animação, porque `scroll smooth` pode congelar em segundo plano). Medido: 1022px → 0 abas escondidas (2 linhas) na ficha e em Configurações; 375px touch → Anamnese/Evolução/Dados ficam visíveis ao tocar.
  **(2) "A equipe entra em contato em até 24h":** removido do passo final do onboarding (era o único lugar). Agora: "Próximo passo: conecte seu WhatsApp — Configurações → WhatsApp & Chatbot → Conectar WhatsApp, escaneie o QR Code". **Decisão da Roberta: a equipe não entra em contato para ligar o robô; a conexão é self-service.**
  **(3) Termos de Uso 1.1:** item novo na seção 12 — integração de WhatsApp **não oficial**, risco de restrição/banimento do número pela Meta, isenção de responsabilidade e orientações (número dedicado, sem disparo em massa, aquecimento gradual). `POLITICA_VERSAO` do `index.html` → `'1.1 (2026-10-24)'` (novos cadastros registram a 1.1; o DPA não exige novo aceite porque `carregarStatusDpa` só confere se existe aceite). O `agendar.html` continua `1.0` de propósito: lá o aceite é do **paciente** sobre a Política de Privacidade, que não mudou. **Plano:** migrar para a API oficial da Meta só depois do lançamento e dos anúncios.
  **(4) Cancelamento:** a Roberta criou na Cakto a chave só com escopo de assinaturas e cadastrou `CAKTO_CLIENT_ID`/`CAKTO_CLIENT_SECRET` no Supabase. Teste ponta a ponta fica para a primeira assinatura real (hoje não há nenhuma assinatura Cakto no banco).
  **Pendente (decisão da Roberta):** trocar "Eduardo, pessoa física" por razão social + CNPJ nos Termos/Política/DPA — o CNPJ já existe; fazer depois.

- **2026-10-24 (2)** — **📄 Declaração de comparecimento + 🩺 atestado em 1 clique, e correção do selo de status por cima do nome na Agenda do Dia.** *(Feito com a Roberta.)* Branch `atestado-declaracao-e-ajuste-agenda`. **Só front** (`index.html`): nenhuma mudança de banco.
  **(1) Documentos:** ver seção 4 ("Declaração de comparecimento e atestado em 1 clique"). Era item de prioridade alta do checkup (todos os concorrentes têm).
  **(2) Bug da Agenda do Dia (~901–1280px):** com a coluna do calendário ao lado, a lista ficava estreita (~290px em tela de 960px) e os selects de sala/profissional vazavam por cima do selo de status e dos botões; o nome sumia. **Causa:** a linha horizontal só virava "card" pela largura da **tela** (≤900px). **Correção:** `#lista-consultas` virou *container* (`container-type: inline-size`) e, com a **lista** abaixo de 640px, cada consulta usa o mesmo card de 2 linhas do celular (`@container`). Medido em 375/960/1100/1280/1366/1920px: 0 sobreposição; ≥1366px continua em linha como antes.
  **Testes (modo demonstração, local):** botões no modal e na ficha (45/45); declaração com acompanhante; atestado com 3 dias, observações e CID autorizado; CID sem autorização bloqueado; atestado sem CREFITO bloqueado (declaração passa com aviso); saída antes da chegada bloqueada; aviso de consulta não atendida; layout no celular; console sem erros. O pop-up bloqueado mostra "Permita pop-ups…" e mantém o modal aberto, igual ao recibo.

- **2026-10-24** — **⚖️ Correções bloqueantes antes de voltar a anunciar (checkup de 23/10).** *(Feito com a Roberta.)* ✅ **ESTADO: APLICADO EM PRODUÇÃO em 2026-10-24.** Migrations `prontuario_autor_e_guarda` e `trava_plano_e_fim_do_periodo` (versões 20261024034911 e 20261024034933 no banco), `cakto-webhook` **v6**, `cakto-cancelar` **v1** e o front via merge na `main`.
  **O que entra:**
  (1) **Autor da evolução (COFFITO 414, art. 2º):** migration `20261023120000_prontuario_autor_e_guarda.sql` — colunas `autor_user_id`/`profissional_id`/`autor_nome`/`autor_registro` em `evolucoes` e `avaliacoes`, preenchidas por trigger no servidor (profissional vinculado → nome+registro do cadastro; dono → `responsavel`+`recibo_registro`; outros → e-mail); o navegador não consegue forjar. App mostra "✍️ Nome — CREFITO" e avisa se o CREFITO não está cadastrado.
  (2) **Guarda de 5 anos (art. 6º):** trigger barra `DELETE` de evolução/avaliação dentro do prazo (inclusive via `paciente_excluir`/`paciente_anonimizar` — a RPC volta inteira); evolução registrada não muda (correção = adendo). Tolerância de 24h. Saída do suporte: `set local nastadesk.permitir_exclusao_prontuario = 'on'`. ⚠️ Excluir uma **clínica inteira** com prontuário em guarda também é barrado (FK em cascata).
  (3) **Recibo:** texto não promete mais dedução no IR (Receita Saúde p/ autônomo, NFS-e p/ PJ).
  (4) **Cancelar em 1 clique:** edge nova `cakto-cancelar` (só o dono; cancela pela API da Cakto; acesso até `proximo_pagamento`; plano B = portal da Cakto ou WhatsApp). Precisa dos secrets `CAKTO_CLIENT_ID`/`CAKTO_CLIENT_SECRET` (escopo subscriptions).
  (5) **`cakto-webhook` v6:** cancelamento ≠ reembolso. `subscription_canceled` mantém o acesso até o fim do período pago; `refund`/`chargeback` cortam na hora (como antes); `refund_requested` não mexe em nada; `subscription_late` vira `em_atraso` (antes caía em "libera"). Passa a gravar `proximo_pagamento` (da Cakto ou hoje + período).
  (6) **🔴 Trava de plano (falha real achada em 24/10):** a policy `clinica_propria` (ALL) deixava o dono dar `UPDATE` em `ativo`/`plano`/`cortesia`/`cortesia_expira_em` pela API → Premium de graça. Migration `20261024120000_trava_plano_e_fim_do_periodo.sql`: trigger `trg_clinicas_proteger_acesso` mantém esses 4 campos quando quem escreve é `authenticated`/`anon` (webhook, admin-api e funções admin_* seguem gravando). Mesma migration: função `encerrar_assinaturas_vencidas()` + **pg_cron `nastadesk-assinatura-expira`** (minuto 17) que corta quem cancelou depois que o período pago acaba.
  (7) **`vercel.json`:** nosniff, Referrer-Policy, X-Frame-Options DENY (menos `/agendar`), CSP em Report-Only.
  **Conferido em produção (só leitura):** colunas batem com o schema; `'cancelada'` é aceito; 0 evoluções/avaliações hoje; nenhuma clínica seria cortada pelo job novo; o app nunca grava plano/ativo/cortesia pelo navegador; profissional não lê despesas/mensalidades/pacotes (RLS ok); webhook valida o secret (fail-closed). **Supabase no plano Free = sem backup.**
  **Teste (24/10, autorizado pela Roberta):** as 2 migrations rodaram no banco de produção dentro de transação desfeita, com login de dono e de profissional simulados por `request.jwt.claims` e `set local role authenticated`: **18/18 OK, nada gravado** (conferido depois). Cobriu: guarda vencida ou em vigor, alterar ou apagar bloqueado, tolerância de 24h, `paciente_excluir`/`paciente_anonimizar` barrados sem apagar pela metade, autor dono/profissional/forjado, flag de suporte, dono tentando se dar Premium, backend liberando, corte só após `proximo_pagamento`, cortesia e assinatura ativa preservadas, job agendado e insert direto nascendo sem acesso. Supabase continua no Free (decisão da Roberta) até ter clientes pagantes.
  ⚠️ **Branch `claude/correcoes-bloqueantes-checkup` (do Eduardo, 23/10) = SUBSTITUÍDA, NÃO aplicar nem dar merge.** Foi feita em paralelo a partir da mesma pasta do checkup. O front dela é idêntico ao que foi publicado. A migration dela (`prontuario_cobranca_cancelamento`) **nunca foi aplicada** (conferido no banco em 24/10) e duplicaria a trava (`trg_clinicas_campos_cobranca`) e o cron (`nastadesk-cancelamento-fim-periodo`). O que vale é o que está na `main`.
  ℹ️ **A integração Git nativa da Vercel voltou a publicar** desde que o repositório ficou público: o push na `main` gerou o deploy de produção, e o push de branch gerou preview automático. O workflow `deploy-vercel.yml` continua existindo.
  **Depois de aplicar:** os advisors de segurança não mostraram nada novo; o job novo rodou e não cortou ninguém; as 2 functions respondem (o `cakto-cancelar` recusa chamada sem login).
  **Pendente:** (a) criar na Cakto uma chave de API com escopo subscriptions e cadastrar os secrets `CAKTO_CLIENT_ID`/`CAKTO_CLIENT_SECRET` — sem isso, o botão Cancelar cai no plano B (portal/WhatsApp); (b) cadastrar o CREFITO dos profissionais e o `recibo_registro` do dono; (c) testar com login real: registrar evolução, tentar excluir paciente, abrir o modal de cancelar; (d) depois de alguns dias sem violação no console, trocar a CSP de Report-Only para valendo.

- **2026-10-19** — **🔒 Trava de IA do robô: cota mensal por plano + limite diário por telefone + aba "Trava de IA" no painel admin.** *(Pedido da Roberta, que assumiu a tarefa iniciada pelo Eduardo.)*
  **Por quê:** não havia trava nenhuma — o custo de IA de uma clínica podia passar do valor da assinatura.
  **Achado ao conferir `ia_uso` vazia:** o registro estava ligado, mas **o robô não rodou desde 16/06** (as 6 conexões de WhatsApp estão desconectadas; a tabela foi criada em 29/06). E havia um defeito escondido: o `try/catch` do registro nunca pegava erro, porque o supabase-js devolve `{ error }` em vez de lançar exceção — agora o erro é conferido e logado.
  **O que entrou:** migration `20261019120000_trava_ia_cota.sql` (3 tabelas novas com RLS, chave `admin_config.ia_limites`, preços de cache no card do Claude, RPCs `ia_checar_e_contar`, `ia_registrar_uso`, `admin_ia_uso_mes`, só `service_role`); `whatsapp-webhook` v8; `admin-api` v7; painel com a aba nova e preço de cache correto. Regras e números na **seção 6**.
  **Testes:** RPCs testadas em produção dentro de transação desfeita (nada gravado): limite diário, cota de conversas, teto de custo, Premium que só alerta, 1 alerta por marco, preço de cache, permissões e RLS; soma de 1.500 linhas na RPC do painel. Painel testado no navegador com dados simulados.
  **Pendente:** o robô só passa a contar quando as conexões de WhatsApp voltarem — conferir no painel o custo real das primeiras semanas e ajustar os limites se precisar.

- **2026-08-30** — **📮 Decidido o caminho do remetente "Nastaclin": domínio próprio + SMTP na Resend. Passo a passo escrito em `supabase/templates/README.md` (falta só o dono executar).**
  Continuação do item (2) da entrega anterior. O dono quis resolver o remetente porque o problema **não é só estético**: o serviço de e-mail embutido do Supabase é limitado a poucos e-mails por hora e a própria documentação diz que **não é para produção** — com várias clínicas se cadastrando na mesma hora, o e-mail de confirmação não sai e a pessoa não consegue ativar a conta.
  **Por que exige domínio:** trocar o remetente só é possível com **SMTP próprio**, e todo provedor exige **verificação por DNS** (SPF/DKIM) para provar que o envio é seu. Por isso **não dá para usar o Gmail** (`nastaclincont@gmail.com`) como remetente: sem controle do DNS não há como verificar, e desde 2024 as regras de remetente em massa do Gmail/Yahoo rejeitam esse tipo de envio.
  **Decisões do dono nesta data:** domínio **`nastadesk.com` / `nastadesk.com.br`** para o produto (o **`nastaclin.com` fica reservado para o site institucional** da Nastaclin) e provedor **Resend** (grátis: 3.000/mês, 100/dia).
  🔎 **Disponibilidade conferida no RDAP nesta data** (para não perder tempo depois): `nastadesk.com`, `nastadesk.com.br`, `nastaclin.com` e `nastaclin.com.br` estavam **todos livres**. `.com.br` sai ~R$ 40/ano no `registro.br` e **registra no CPF** — não precisa de CNPJ.
  **Dados de SMTP conferidos na documentação do Resend** (não chutados): host `smtp.resend.com`, portas 25/465/587/2465/2587, usuário `resend`, senha = a API key `re_...`.
  ⚠️ **Pegadinha que o passo a passo cobre:** ligar o SMTP **não levanta sozinho** o limite de envio — é preciso também aumentar **Authentication → Rate Limits → "Emails sent per hour"** no Supabase. E os valores de DKIM/SPF são **gerados por domínio** pela Resend: têm que ser copiados de lá, não existe valor padrão.
  ***FALTA (só o dono faz):*** registrar o domínio → adicionar no Resend e colar os registros DNS no `registro.br` → gerar a API key → preencher o SMTP no Supabase (com o nome do remetente **Nastaclin**) → subir o rate limit → testar um cadastro. Tudo detalhado no `README.md` da pasta de templates. *(Continua pendente também colar os 2 templates HTML em Authentication → Emails → Templates.)*

- **2026-08-30** — **✉️ Tela de "confirme seu e-mail" no cadastro + 📧 e-mails de conta em português com a marca + 🎬 CONTA DE DEMONSTRAÇÃO (clínica de exemplo que não salva nada). `admin-api` v6 deployada; `config_publica.demo` gravada em produção.**
  Três pedidos do dono numa entrega só.
  **(1) Cadastro: a tela muda, não é mais um avisinho.** O dono relatou que, ao criar a conta, só aparecia **uma faixa verde no topo** dizendo que o e-mail foi enviado — e muita gente não reparava, ficando sem confirmar a conta. Agora o formulário **some** e entra uma tela dedicada: envelope, o e-mail digitado em destaque, os **3 passos**, aviso de **spam/Promoções**, **"Abrir meu e-mail"** (detecta Gmail/Outlook/Yahoo/iCloud/UOL/Terra pelo domínio; some em domínio próprio), **"Reenviar o e-mail"** (`auth.resend`, com trava de **60s** para não estourar o limite de envio do servidor) e "Voltar para o login". O formulário é limpo depois do cadastro. **Nenhuma mudança de banco.**
  **(2) E-mails de conta (`supabase/templates/`).** Criados `confirmacao-cadastro.html` e `recuperacao-senha.html`: layout Nastaclin (topo verde, **logo em pastilha branca**), texto **todo em português**, botão grande + link alternativo, aviso de "não foi você?" e rodapé com privacidade/termos. Renderizados e conferidos visualmente. ⚠️ **O que eu NÃO consigo fazer daqui:** trocar o remetente **"Supabase Auth" → "Nastaclin"**. Com o serviço de e-mail embutido do Supabase **não existe campo** para isso — exige **SMTP próprio** (Resend/Brevo/SendGrid/SES) em `Authentication → Emails → SMTP Settings`. E não é só estética: a documentação diz que o serviço embutido é **limitado a poucos e-mails por hora** e **não é para produção** — com várias clínicas se cadastrando na mesma hora, o e-mail de confirmação **simplesmente não sai**. Passo a passo no `supabase/templates/README.md`.
  **(3) Conta de demonstração.** Login que abre uma clínica de exemplo cheia de dados, para mandar a quem quer conhecer a ferramenta. **Arquitetura escolhida: 100% no navegador** — quando o login bate com `config_publica.demo`, o app **troca o cliente do Supabase** por um cliente falso que responde de um "banco" no **`sessionStorage`**. Consequências (todas desejadas): **nenhum dado real é lido/gravado/apagado**, vários testadores ao mesmo tempo não se atrapalham, e **fechar o navegador redefine tudo** — que era exatamente o pedido. Detalhes técnicos, o que a semente contém e as 2 armadilhas (fuso e gerador aleatório) na **nova seção 11**.
  No **painel admin → Configurações**, card **"Conta de demonstração"**: e-mail, senha, liga/desliga e **mensagem pronta para enviar** com botão de copiar. `admin-api` passou a aceitar a chave `demo` em `salvar_config_publica`.
  ⚠️ **Erro meu no meio do caminho (registrado para não se repetir):** deployei a `admin-api` **v5 com um texto de placeholder no lugar do código** — a função ficou quebrada por **~1,5 minuto** até eu perceber e subir a **v6** com o arquivo real. Só o painel admin usa essa função e o dono não estava nele, então não houve impacto para cliente nenhum. **Lição: no `deploy_edge_function`, o conteúdo do arquivo tem que ir inline de verdade — não existe "ler do disco".** Depois do conserto, conferido ao vivo: 401 `no_token` / 401 `invalid_token` / 200 no preflight / 405 no GET (exatamente o que o código real produz).
  **Validado:** `node --check` nos fronts + **22/22 testes** da tela de confirmação (a tela troca, e-mail certo, 3 passos, atalho do webmail aparece/some, resend com `type=signup` + trava de 60s, volta ao login, campos limpos) + **57/57 testes da demonstração** (senha errada não entra; **zero chamadas ao Supabase depois de entrar**; as 11 telas abrem; agenda/pacientes/financeiro/relatório/estoque/conversas renderizam de verdade; histórico variado; dá para criar registros; sobrevive ao F5; **sessão nova começa zerada**) — rodados em **2 fusos** (São Paulo e Tóquio) + **56/56 no painel admin** + **57/57 na suíte antiga do app** (sem regressão) — **zero erro de JS**.
  ***FALTA (só o dono faz):*** **(a)** colar os 2 templates em **Supabase → Authentication → Emails → Templates**; **(b)** configurar **SMTP próprio** para o remetente virar **Nastaclin** (e destravar o limite de envio).

- **2026-08-30** — **🚨 DESCOBERTO: a Vercel parou de publicar EM SILÊNCIO em 08/07 (repo privado + plano Hobby) + 🔐 o painel admin estava servindo o repositório inteiro. Corrigidos os dois e **PUBLICADOS**: deploy agora é por GitHub Actions (secret `VERCEL_TOKEN` **de repositório**, não de organização); `dashboard` ganhou `vercel.json`.**
  **O sintoma:** merge feito na `main` dos 2 repos, push confirmado no GitHub — e os dois domínios continuavam servindo a versão de **julho**, sem erro nenhum. **A causa:** em **08/07/2026** os repos `nastaclin/nastadesk` e `nastaclin/dashboard` viraram **privados** (recomendação da varredura de segurança de 07/07). O time da Vercel é **Hobby**, e a partir daí a **integração Git nativa parou de criar deployment** — não de produção, não de preview, **nem de erro**. Provas: último deployment dos 2 projetos é de 08/07 e nos metadados dele os repos ainda constam `githubRepoVisibility: "public"`; os links Git na Vercel continuam configurados; outros projetos da mesma conta (org `edudusao`, públicos) deployaram normalmente em agosto.
  ❌ **Hipóteses testadas e DESCARTADAS** (para ninguém refazer): projeto pausado (`unpause_project` nos 2 — não era), `vercel.json` com auto-deploy desligado (`github.enabled`/`git.deploymentEnabled` não existem nos repos), conta bloqueada (outros projetos publicaram em agosto). ⚠️ **Pegadinha:** o campo `live: false` que o `get_project` devolve **não** quer dizer "pausado" — ele só indica que o **último** deployment não foi de produção (o projeto `uninter-lead-manager`, que deployou normal em agosto, também vem com `live:false`). Não perca tempo com ele.
  📌 **Nomes que confundem:** `nastadesk.vercel.app` é servido pelo projeto **`nastadeskexemplo`** — **não** pelo projeto chamado `nastaclin`, que aponta para o mesmo repositório e está ocioso desde junho. O painel admin é o projeto `nastaclin-admin`.
  **(1) Correção do deploy (decisão do dono nesta data, entre 3 opções): GitHub Actions + token**, mantendo os repos **privados** e **sem pagar o Vercel Pro.** Novo `.github/workflows/deploy-vercel.yml` nos 2 repos: a cada push na `main` (e no `workflow_dispatch`), instala a CLI da Vercel e roda `vercel deploy --prod` — que **envia os arquivos pela API** e por isso **não depende da integração Git quebrada**. Depois do deploy ele **confere que o domínio responde 200** e falha se não responder. Se o secret faltar, ele **para no primeiro passo com mensagem explicando** (nunca falha em silêncio — foi exatamente esse o problema original). `VERCEL_ORG_ID`/`VERCEL_PROJECT_ID` ficam no próprio workflow (não são segredo); só o token é secret.
  **(2) 🔐 Vazamento corrigido no painel admin.** O repo `dashboard` **não tinha `vercel.json`** — então a Vercel servia a **árvore inteira do repositório** em `nastaclin-admin.vercel.app`: **`/CLAUDE.md` (120 KB do documento interno) respondia 200**, assim como `/supabase/functions/admin-api/index.ts` (10 KB do código real), as **migrations SQL** e `/.claude/settings.json`. Tornar o repo privado em julho **não tirou isso do ar** (o site continuou servindo o que já tinha sido publicado). Nenhuma chave estava exposta (service_role/Anthropic/Evolution vêm de env nas edge functions), mas era o material interno aberto para quem soubesse a URL — incluindo o e-mail do admin no `admin-api`. **Corrigido:** `dashboard/vercel.json` agora publica **só `*.html` e `*.png`**, com catch-all para o `index.html` — **o mesmo padrão que já protegia o `nastadesk`** (por isso o app das clínicas nunca teve esse furo: lá `/supabase/...` sempre caiu no catch-all). Somado a isso, `.vercelignore` nos 2 repos impede até o **upload** de `supabase/`, `marketing/`, `.github/`, `.claude/` e `*.md`.
  **Validado:** YAML dos 2 workflows conferido (parser + execução real no GitHub); o run #1 dos 2 repos **falhou exatamente no passo "Conferir o token"** e pulou os demais — ou seja, o workflow está instalado e correto, só esperando o secret. Exposição do painel confirmada por `curl` antes da correção (200 em `/CLAUDE.md`, `/supabase/functions/admin-api/index.ts`, `/supabase/migrations/*.sql`, `/.claude/settings.json`).
  **✅ RESOLVIDO no mesmo dia:** o dono gerou o token e cadastrou o secret **`VERCEL_TOKEN`**; os 2 workflows rodaram (run #3, `workflow_dispatch`) e **publicaram**. ⚠️ **Pegadinha do GitHub que custou uma tentativa:** o secret **NÃO pode ser de organização** — no plano gratuito, secret de org só vale para repositório **público** (a opção "Private repositories" aparece cinza dizendo isso). Tem que ser **secret de repositório**, em `github.com/nastaclin/<repo>/settings/secrets/actions/new`, **nos 2 repos**. (Actions em si funciona normalmente nos repos privados — os runs rodaram em `ubuntu-latest` sem problema.)
  **Conferido no ar depois do deploy:** app com `periodo-btn`/`logo-marca`/`site-topo`/`cupom-box`, os 9 preços (262/532/937 e 931/1891/3331), o WhatsApp `5521984072359`, `/logo.png` (110 KB), `manifest.json` com os 4 ícones *maskable*, `sw.js` na versão `nastadesk-v2-2026-08-30`, e `/profissional`, `/agendar/<slug>` e as páginas legais respondendo 200; painel admin com `sec-cupons`/`sec-sites`/`sec-config` e o MRR mensalizado. **Vazamento fechado:** `/CLAUDE.md`, `/supabase/functions/admin-api/index.ts`, `/supabase/migrations/*.sql` e `/.claude/settings.json` no domínio do admin agora caem no catch-all (devolvem o `index.html`, não o arquivo).
  **Como conferir se publicou de verdade** (o merge sozinho não é prova): `curl -s https://nastadesk.vercel.app/ | grep -c periodo-btn` e `curl -s https://nastaclin-admin.vercel.app/ | grep -c sec-cupons` — **zero = a versão velha ainda está no ar.** E, depois da correção do vazamento, `curl -s -o /dev/null -w '%{size_download}' https://nastaclin-admin.vercel.app/CLAUDE.md` tem que devolver o tamanho do `index.html` (catch-all), não os 120 KB do documento.

- **2026-08-30** — **Merge na `main` dos 2 repos + as 6 ofertas de trimestral/anual CRIADAS na Cakto e os 9 links de checkout gravados em `config_publica`.** ⚠️ **O merge sozinho NÃO publicou** — ver a entrada de deploy acima. Fecha os 3 pendentes da entrega anterior (só (b), cadastrar cupom na Cakto, continua sendo por cupom, quando existir).
  **(1) Deploy.** `claude/nastadesk-tool-updates-68rej5` mergeada na `main` (fast-forward, 0 commits atrás) nos **dois** repos. ⚠️ **O push não publicou nada** — a Vercel não gerava deployment desde 08/07. Causa, correção e como conferir: **entrada de deploy acima.**
  **(2) Ofertas na Cakto (produção).** Criadas via API pública da Cakto (MCP `cakto-mcp`, escopos `products`/`offers`/`write`), espelhando o formato das mensais que já existiam (`type=subscription`, `intervalType=lifetime`, `interval=1`, `quantity_recurrences=-1`, `trial_days=0`, `max_retries=3`, `retry_interval=1`) e mudando só o preço e o **`recurrence_period`**: **90 dias** no trimestral, **365** no anual. Ficaram 3 produtos × 3 ofertas = **9 ofertas, sem duplicata** (conferido). Ids na tabela da seção 5.
  🔎 **Descobertas úteis para o próximo chat:** (a) a **API da Cakto não expõe a URL do checkout** — nem em `offers_retrieve` nem em `products_retrieve`; o link se monta como `https://pay.cakto.com.br/<offer_id>`; (b) **o sufixo `_949243` dos links antigos é decorativo** — provado chamando `api.cakto.com.br/api/product/checkout/<slug>/` com o id puro, com o sufixo certo e com um sufixo inventado (os 3 devolvem a mesma oferta; id inexistente dá 400); (c) o `offers_create` **exige `id` e `default` no corpo** (o schema marca os dois como `required` mesmo sendo readOnly), mas o **servidor ignora o `id` enviado** e gera o dele; (d) **não há idempotência** em `offers_create` — nunca repetir a chamada às cegas.
  **(3) `config_publica.checkout_links` preenchida** com os 9 links (os 3 mensais **intocados**, via `jsonb ||` só nas chaves `trimestral`/`anual`). O app das clínicas lê de lá — **nenhuma mudança de código foi necessária**.
  **Validado:** os **9 links resolvem no checkout real** com preço e recorrência corretos (Básica 262/931, Profissional 532/1.891, Premium 937/3.331; 90 e 365 dias; todas `active`), lidos **pela mesma rota que o app usa** (`config_publica` como `anon`) — isso independe do front, então **já vale hoje**. A publicação do front: ver a entrada de deploy acima.
  ***Falta (só o dono faz):*** cadastrar cada **cupom** também na Cakto com o mesmo código, quando fechar cada parceria — aqui é só o rastreio/comissão.

- **2026-08-30** — **🎨 Logo oficial + 💳 assinatura trimestral/anual + 🌐 área "Site" na Conta + 🎟️ cupons de parceria (com painel de repasse no admin). Migrations APLICADAS em produção; edges `cakto-webhook` (v5) e `admin-api` (v4) DEPLOYADAS. Branch `claude/nastadesk-tool-updates-68rej5` nos 2 repos (falta merge na `main` → Vercel).**
  Quatro pedidos do dono numa entrega só. **Decisões dele nesta data:** anual **−20%**, trimestral **−10%**; o cupom é cadastrado **também na Cakto** (é lá que o desconto sai) e o NastaDesk faz o rastreio; links de checkout de trimestral/anual **ainda não existem** → ficam **configuráveis no painel admin**; WhatsApp que recebe pedido de site: **(21) 98407-2359**.
  **(1) Logo oficial.** O placeholder "N" saiu de todo lugar. `logo.png` na raiz dos 2 repos (gerada de `marketing/logo-mark.png`, recortada e otimizada) + **ícones do PWA regerados** (192/512/apple-touch **+ 2 novos *maskable* full-bleed**, que é o formato certo p/ Android não cortar) e **favicon** em todas as páginas. Aplicada em: splash, login, onboarding, sidebar, cabeçalho do celular, `profissional.html`, `agendar.html`, `confirmado.html`, `privacidade/termos/dpa` e no **painel admin**. Sobre fundo verde ela vai numa **pastilha branca** (o "C" da logo é verde escuro e sumia). `sw.js` com versão de cache nova (`nastadesk-v2-2026-08-30`) para o ícone velho não ficar preso no celular de ninguém.
  **(2) Trimestral e anual.** Seletor de período na tela **Planos** e no **paywall** (Mensal · Trimestral −10% · Anual −20%), preço do período + "equivale a R$ X/mês", e o **brinde do site** anunciado dentro de cada card. **Preço é do servidor**: nova função `public.nastadesk_preco(plano, periodo)` — o front tem os números só para exibir. **`assinaturas.periodo`** (aditiva, null = mensal legado). **Links de checkout por plano × período** em `config_publica` (os 3 mensais já preenchidos com os que estavam no ar; trimestral/anual vazios → o botão avisa e oferece o WhatsApp em vez de quebrar). 🐛 **Bug evitado:** o `cakto-webhook` casava o plano só por 97/197/347 — uma compra anual (3.331) não casaria com nada e cairia no fallback **liberando o plano errado**; agora ele reconhece os 9 valores (em reais **ou centavos**, com 1 real de tolerância), grava o período e o valor certo. 🐛 **Corrigido também:** o MRR do painel somava o valor cru — uma assinatura anual inflaria a receita mensal em 12×; agora é **mensalizado**. E o card "Plano atual" não trava mais quem está no **teste grátis** (antes o botão do plano do trial vinha desabilitado — a pessoa não conseguia assinar o próprio plano).
  **(3) Área "Site" em Minha Clínica.** Card com a tabela **R$ 500 / R$ 250 (trimestral) / grátis (anual)**, destacando **o preço que vale para aquele cliente** conforme o período que ele assina. **"🚀 Quero meu site"** registra o pedido (`site_solicitar`) **antes** de abrir o WhatsApp com mensagem pronta (mesmo padrão do NPS, para o pedido não se perder). Tabela **`sites`** (1 por clínica): o cliente **só lê a própria linha** (RLS) — status/URL/valores são do admin. Quando o admin marca **"No ar" + URL**, **a tela do cliente vira sozinha** "Seu site" + **"✏️ Quero mudar algo no site"** (mensagem diferente, já com o endereço) — serve também para quem fez o site antes de assinar (o dono lança na mão pelo painel).
  **(4) Cupons de parceria.** Campo de cupom nos Planos, no paywall e no Site. O app **valida no servidor**, mostra o preço riscado e **registra o uso antes do checkout** (o código também vai na URL da Cakto). Tabelas **`cupons` + `cupom_usos`** são **fechadas** (deny-all, como `admin_config`): o cliente **nunca** vê parceiro nem comissão — só 2 RPCs `SECURITY DEFINER` que devolvem o desconto. O uso nasce **pendente** e o `cakto-webhook` marca **confirmado** quando o pagamento entra (tolerante a falha — nunca impede a liberação do acesso). No **painel admin**: seções novas **Cupons** (cadastro completo + fechamento de repasse por mês + "Marcar pago" + lista de quem usou), **Sites** e **Configurações** (os 9 links + WhatsApp/preços do site).
  🔐 **Achado de segurança corrigido na hora:** `revoke execute … from anon` **não basta** — no Postgres toda função nasce com EXECUTE para **PUBLIC**, e o `anon` herda de PUBLIC. Com isso um visitante **não logado** conseguia chamar `cupom_calcular` e **enumerar códigos de cupom** (descobrir se existe e qual desconto dá; parceiro/comissão nunca ficaram expostos). Migration `fecha_execute_public_nas_rpcs_de_cupom_e_site` **aplicada**: revoga de `public, anon` e concede só a `authenticated` nas 6 funções novas. **Confirmado pela API real:** anon → `42501 permission denied` em `cupom_validar`/`cupom_calcular`/`site_solicitar` e na tabela `cupons`; `config_publica` segue legível (é público de propósito) e o **booking público continua vivo**. *(Padrão a repetir em toda função nova: `revoke … from public, anon` + `grant … to authenticated`.)*
  **DB (aditivo, zero dado tocado):** migration `20260830120000_planos_periodos_site_cupons.sql` **APLICADA**, testada antes **com ROLLBACK contra os dados reais** (o teste pegou um bug de verdade: `ON CONFLICT` não casa com índice **parcial** sem repetir o predicado — corrigido). Checks: preços por período, código de cupom normalizado por trigger, cupom sem sessão recusado, desconto 90% de 3.331 = 2.997,90 → final 333,10 e comissão 20% = 66,62, **registrar 2× cria 1 linha só** (não infla repasse), cupom "só site" recusado em assinatura, site do anual = R$ 0, `site_solicitar` idempotente, **cliente não lê `cupons`/`cupom_usos`** (permission denied), **cliente não consegue marcar o próprio site como "no ar"** nem escrever em `config_publica`, e o dono vê só o site dele. **Zero resíduo** após o rollback (0 cupons / 0 usos / 0 sites).
  **Validado:** `node --check` nos 5 fronts + **57/57 testes de navegador no app das clínicas** (logo nos 5 pontos, preços dos 3 períodos, selos −10%/−20%, "equivale a R$/mês", brinde do site por período, link por período vindo da config, período sem link abre aviso, cupom inválido/válido, preço riscado 97→9,70, **registra o uso antes do checkout** e leva e-mail+cupom na URL, área Site nos 4 estados, cupom do site 500→50, pedido registrado antes do wa.me, **WhatsApp certo (5521984072359)**, site no ar vira "editar" com mensagem diferente, paywall com período+cupom, **sem ids duplicados no DOM**) + **48/48 no painel admin** (logo carregando de verdade, **MRR mensalizado 197+3331/12**, cupons: contadores do mês, a pagar 35,46 × já repassado 90, troca de mês recalcula, criar/editar com todos os campos, validação sem código não chama a API, marcar pago zera o "a pagar", sites: contadores/lista/editar/"no ar" exige URL, config: 9 links, link anual vazio, WhatsApp normalizado só com dígitos) + **17/17 testes unitários** do mapeamento valor→plano/período do webhook — **zero erro de JS** nas duas suítes. Edges testadas ao vivo (401 sem token / 401 token inválido / 200 no preflight / `cakto-webhook` 401 com secret errado). Advisors: só entram os avisos **do mesmo padrão intencional** já existente (DEFINER + `rls_enabled_no_policy` em `cupons`/`cupom_usos`, que é deny-all **de propósito**, igual `admin_config`).
  ***FALTA (só o dono faz):*** **(a)** criar as ofertas **trimestral e anual** na Cakto (6 links) e colá-las em **Painel admin → Configurações**; **(b)** cadastrar cada cupom **também na Cakto** com o mesmo código (aqui é só o rastreio/comissão); **(c)** merge da branch na `main` dos 2 repos (Vercel publica) — migrations e edges **já estão em produção** e são aditivas ao front atual.

- **2026-07-07** — **📱 REDESIGN RESPONSIVO / "app no celular" (pedido do dono: "melhora a interface para o celular, está muito ruim, parece que foi feito só pra computador; deixa bonita no celular E no computador; só front-end, nada que afete o sistema negativamente"). SÓ CSS/HTML (front) — zero mudança de lógica, banco, edge ou dados. Branch `claude/mobile-interface-redesign-id4m6g` (falta merge na `main`; falta replicar o registro no `CLAUDE.md` do `dashboard` — não estava no escopo desta sessão).**
  O dono relatava que **para usar no celular precisava ativar "site para computador"** no navegador — sinal clássico de página que estoura a largura do viewport. A causa raiz estava no `.main` (largura fixa da versão desktop) + linhas de consulta/financeiro que não quebravam, empurrando a página para ~957px num viewport de 390px. Feito, **aditivo e conservador** (nenhuma classe existente removida; nada que o JS lê foi alterado):
  **(1) Guardas de largura** — `html,body{overflow-x:clip}`, `.main{min-width:0}`, grids com `minmax(0,1fr)` e a linha de consulta do dia virou **grid de app** no mobile (nome + etiquetas quebram linha; status/ações numa faixa própria). Fim do scroll horizontal (validado: sobra ≤1px em **todas** as 11 seções).
  **(2) Navegação estilo aplicativo** — a **barra inferior** (que já existia) foi refinada (ícone com "pílula" verde no item ativo, badges reposicionados, `backdrop-blur`, safe-area), **cabeçalho fixo no topo** no celular com a marca + sino de notificações, e o **menu "Mais" virou bottom sheet** (folha que sobe de baixo). No desktop, a **sidebar** ganhou o selo "N" e barra de destaque no item ativo.
  **(3) Toque e leitura no celular** — **inputs a 16px** (o iOS não dá mais aquele zoom automático que "quebrava" a tela), alvos de toque ≥ ~44px, **modais viram bottom sheets** (com alça) em telas ≤640px, **ficha do paciente e notificações em tela cheia**, listas/abas/segmentos com rolagem lateral suave e safe-areas (`env(safe-area-inset-*)`) no topo/base.
  **(4) Modernização visual mantendo a marca** (decisão do dono: "manter o verde, modernizar") — mesmo verde Nastaclin + DM Sans/DM Serif; refinei sombras, raios, botões com leve gradiente, fundo com brilho radial sutil, `prefers-reduced-motion`, e um foco visível (acessibilidade). Aplicado também na **página pública de agendamento** (`agendar.html`: topo arredondado com selo, passos em "chip", botões maiores), **`confirmado.html`**, **Portal do Profissional** (`profissional.html`: card de saudação com gradiente, abas com blur, safe-areas) e **páginas legais** (`privacidade/termos/dpa`: topo arredondado + fundo consistente).
  **Segurança da mudança:** **nada de dado/agenda/financeiro/banco tocado** — é 100% camada de apresentação. Adicionado `viewport-fit=cover` nas páginas (para respeitar o notch). **Validado:** `node --check` nos 4 scripts inline (index/profissional/agendar/confirmado) + **39/39 testes de navegador** (Playwright, Supabase mockado, rede externa bloqueada): sem overflow horizontal em todas as seções (mobile e desktop), barra inferior aparece só no mobile e some no desktop, cabeçalho da marca aparece, menu "Mais"/modal/ficha abrem e fecham, input de busca a 16px, login/agendar/portal sem overflow — **zero erro de JS**. Screenshots antes/depois (mobile 390px + desktop 1440px) conferidos.
  ***Falta:*** merge do front na `main` (Vercel) — é só front, aditivo; nenhuma migration/edge envolvida. *Obs.: o PWA já existia (instalável); aqui foi só deixar a interface digna de app.*
- **2026-07-07** — **🔐 VARREDURA DE SEGURANÇA (pedido do dono: "olha tudo, GitHub/Vercel/Supabase, vê o que pode me causar problema, chaves expostas, dados públicos, formas de hackear"). 2 migrations de segurança APLICADAS em produção + edge `mercadopago-webhook` re-deployada fail-closed (v5). Branch `claude/security-audit-exposure-scan-81oo37` (falta merge; replicar no `dashboard`).**
  Auditoria dos 3 lados (código no GitHub, banco/edge no Supabase, hospedagem na Vercel). **Achado CRÍTICO (corrigido):** a policy `admin_proprio` de `public.nastaclin_admins` era `FOR ALL` com `USING (auth.uid()=user_id)` e **sem `WITH CHECK`** → no Postgres o INSERT cai no USING, então **qualquer usuário logado** (o trial self-service já dá conta logada) podia rodar UM `insert into nastaclin_admins(user_id) values (auth.uid())` e **virar admin global** — o edge `admin-api` confia nessa tabela (ver todas as clínicas/e-mails/assinaturas, conceder cortesia, **remover o acesso de qualquer clínica**). **Confirmado empiricamente com ROLLBACK** (o INSERT com user_id real de cliente passou; nada persistido). *Impacto limitado:* prontuários/pacientes de outras clínicas **não** ficavam legíveis por esse caminho (RLS de `pacientes`/`consultas` continua amarrada ao dono); e `admin_config` (secrets Cakto/hCaptcha) segue ilegível (RLS sem policy = deny-all). Mas era takeover do painel admin + poder de ligar/desligar acesso de clientes.
  **Correções aplicadas (aditivas/reversíveis, zero dado tocado):**
  **(1) Migration `20260707154836_fix_nastaclin_admins_privesc.sql`** — troca a policy por `FOR SELECT` (`auth.uid()=user_id`, o dono ainda vê a própria linha p/ o painel) e **revoga INSERT/UPDATE/DELETE/TRUNCATE de anon+authenticated** em `nastaclin_admins`. Gestão de admins só via service_role/SQL. **Re-testado:** a auto-promoção agora dá `42501 permission denied`; admin real ainda faz SELECT da própria linha (painel intacto).
  **(2) Migration `20260707154918_hardening_search_path_e_grants_anon.sql`** — (a) fixa `search_path` de `cpf_valido(text)` (limpa o advisor 0011); (b) **revoga INSERT/UPDATE/DELETE/TRUNCATE do papel `anon` em TODAS as tabelas** + `alter default privileges … revoke … from anon` (o anon tinha `ALL` amplo demais; já bloqueado pela RLS, mas era gordura). **NÃO** mexe em `authenticated` (app logado intacto: INSERT/UPDATE/DELETE em 30 tabelas + SELECT em 31, confirmado) nem em `service_role`. Fluxos públicos (`agendar.html`→edge `agendar-publico`; `confirmado.html`) usam RPCs `SECURITY DEFINER`/service_role — `anon` segue com EXECUTE em `clinica_publica`/`horarios_ocupados`/`agendar_online` (booking intacto, confirmado).
  **(3) Edge `mercadopago-webhook` v5 (fail-closed)** — era **fail-open**: `assinaturaValida` retornava `true` quando `MERCADOPAGO_WEBHOOK_SECRET` não estava setado, num endpoint público (`verify_jwt=false`) que mexe em `clinicas.ativo`/`assinaturas`. Trocado para **`return false`** (sem secret → 401). Risco real já era baixo (revalida status na API do MP), e o MP está aposentado (0 assinaturas MP `ativa`: 1 cancelada + 1 pendente stale). *Sobra:* `mercadopago-checkout` (exige login) e `mercadopago-webhook` são código morto — dá p/ remover no futuro.
  **O que está SÓLIDO (confirmado, não mexer):** RLS ativa nas 30 tabelas (anon lê **0** em tudo sensível); **nenhum segredo no código nem no histórico do git** (só a chave `anon`, pública por design — service_role/Anthropic/Evolution vêm de env nas edge functions); `admin-api` valida JWT+admin antes do service_role; RPCs `SECURITY DEFINER` escopadas por `auth.uid()` (`paciente_excluir`/`paciente_anonimizar`/`gerar_mensalidades` sem IDOR entre clínicas); RPCs admin/bot **não** executáveis por anon/authenticated; bucket `exames` **privado** (URL assinada); `cakto-webhook` e `agendar-publico` **fail-closed**; RPCs públicas de booking devolvem só dado não-sensível.
  **⚠️ AÇÕES QUE SÓ O DONO FAZ (fora do meu alcance):** (a) **tornar PRIVADOS os 2 repos do GitHub** `nastaclin/nastadesk` e `nastaclin/dashboard` — hoje **públicos** (não há segredo commitado, mas expõe a lógica do painel admin e o **e-mail do admin hardcoded** `em8090594@gmail.com` no `admin-api` do `dashboard`); (b) **ativar 2FA** na conta admin (o painel `nastaclin-admin.vercel.app` é publicamente acessível — a barreira é a senha dessa conta + o gate corrigido); (c) **"Leaked Password Protection"** exige Supabase Pro (adiado, já documentado). *NFS-e:* migrations `nfse`/`nfse_focus`/`despesas_fiscal` e a edge `nfse` (v4, `verify_jwt=true`, exige login) estão em produção, mas a **emissão foi deixada p/ depois de propósito** (dono sem CNPJ — ver seção 4/10.4); não é buraco aberto. `mp-debug` já está neutralizada (410).
- **2026-07-07** — **Documentos do paciente (regras assinadas / contrato / consentimento de imagem) + modelos da clínica (pedido de cliente por áudio). SEM migration; front MERGEADO na `main` (deploy) e CLAUDE.md replicado no `dashboard`.**
  Terceiro áudio da mesma clínica cliente: *"tem como adicionar alguma documentação? eu tenho as regras [do estúdio] que preciso que sejam lidas e assinadas, a mesma coisa com o consentimento de imagem, contrato com o paciente… os exames também conseguem colocar lá?"*. Exames **já existiam** (Fase 3); o que faltava era a documentação assinada. Feito, aditivo e **sem tocar no banco**:
  **(1) Ficha do paciente → aba "Docs"** — anexar a **via assinada** de documentos com tipo (📋 regras / 📝 contrato / 📸 consentimento de imagem / 📎 outro; PDF/imagem até 10 MB, mesmas validações dos exames), **checklist por paciente** ("Regras do estúdio: assinado ✓" × "pendente" para os 3 tipos padrão), abrir por **URL assinada** (5 min) e excluir com confirmação. Auditoria LGPD: `anexou_documento`/`baixou_documento`/`excluiu_documento` (a RPC `registrar_auditoria` aceita ação livre — sem CHECK, confirmado).
  **(2) Configurações → aba "Documentos" (Modelos)** — a clínica guarda os **arquivos base** (regras, contrato, consentimento) para abrir/imprimir/enviar quando chega paciente novo; upload/lista/abrir/excluir. O card explica o fluxo (modelo → paciente assina → anexa a via na ficha).
  **(3) Arquitetura (zero migration)** — tudo no **bucket privado `exames`** já existente: documentos do paciente ficam no MESMO prefixo `clinica_id/paciente_id/` com **prefixo de nome `doc__<tipo>__`** — as policies por clínica/papel valem sem mudança, a aba Exames **filtra fora** os `doc__` (e vice-versa), e a **limpeza LGPD (`apagarExamesPaciente`), que apaga o prefixo inteiro do paciente, já cobre os documentos fail-closed sem alteração**. Modelos ficam em `clinica_id/_modelos/` (pasta irmã — fora de qualquer fluxo por paciente; dono/recepção têm ALL por `foldername[1]=clinica_id`; profissional não acessa: policy dele exige `foldername[2]` = paciente dele). **Exportação do titular** ganhou `documentos_anexados` (separado de `exames_anexados`); textos de excluir/anonimizar paciente agora citam "exames e documentos".
  **Validado:** `node --check` + **62/62 testes de navegador** (Playwright, Supabase mockado com storage instrumentado): helpers de prefixo, aba Exames NÃO mostra documentos e vice-versa, checklist (2 assinados + 1 pendente), upload no caminho `clinica/paciente/doc__contrato__…` no bucket `exames`, validação sem arquivo não sobe nada, abrir usa URL assinada de 300s, excluir com confirmação remove o path certo, **limpeza LGPD apaga exames E documentos (3/3)**, modelos listam/sobem em `clinica/_modelos/`, abas novas abrem (cfgTab + fichaTab) — **zero erro de JS**. Screenshot da aba Docs conferido.
- **2026-07-06** — **Pedidos de cliente por áudio (2 áudios de WhatsApp): (a) corrigir o horário de um horário fixo inteiro pelo Remarcar; (b) agendar aula experimental sem cadastro completo. + Pedido do dono na sequência: (c) excluir consulta também pela aba Agendamentos e pela ficha do paciente. Migration APLICADA em produção; front MERGEADO na `main` (deploy autorizado pelo dono) e CLAUDE.md replicado no repo `dashboard`.**
  Uma clínica cliente mandou 2 áudios (transcritos nesta sessão): *"errei o horário de um paciente... é um horário fixo e não estou conseguindo mudar o horário / não está excluindo"* e *"tem como marcar a aula experimental na agenda ou sempre preciso fazer o cadastro do paciente?"*. Nenhuma das duas coisas existia. Feito, aditivo e conservador com os dados:
  **(1) Remarcar série de horário fixo (`index.html`)** — o modal **Remarcar** de uma consulta com `serie_id` agora mostra a escolha **"Só esta consulta"** (padrão; comportamento antigo intacto) × **"Esta e as próximas da série — corrigir o horário fixo"**: busca as ocorrências da série com `serie_id` + `gte data_hora` + `neq cancelado` (escopo `clinica_id`) e move **cada uma pelo mesmo deslocamento** (novo horário − horário da consulta escolhida), então serve tanto p/ trocar a hora (qua 9h→10h) quanto o dia da semana (qua→qui); status volta a `agendado`. **Nunca toca nas que já passaram nem nas canceladas**; delta zero não faz nada; só UPDATE de `data_hora`/`status` (nada apagado/criado). Sobre o *"não está excluindo"* dela: conferi as FKs de `consultas` em produção (`lembretes` CASCADE, `evolucoes`/`notas_fiscais` SET NULL) — o DELETE não é bloqueado pelo banco; a exclusão de série ("só esta"/"esta e as próximas") já existia no front e chegou à `main` hoje — o relato provavelmente foi de antes do deploy.
  **(2) Aula experimental sem cadastro completo** — **migration `20260706190000_consultas_experimental.sql` APLICADA em produção** (testada antes com ROLLBACK contra os dados reais — 350 consultas, zero marcada, zero resíduo): coluna **`consultas.experimental`** (boolean not null default false, aditiva; RLS de `consultas` é por `clinica_id`, agnóstica à coluna; advisors de segurança **sem regressão**). Front: link **⭐** no modal Nova consulta (e na lista de resultados da busca) abre o **cadastro rápido** (nome + WhatsApp opcional; aproveita o nome já digitado na busca); ao salvar, cria o paciente mínimo (`pacientes.whatsapp` é NOT NULL → vai `''` se vazio; `observacoes` explica a origem) e insere a consulta com `experimental=true`. **Valor em branco → `valor=0` + `pagamento_status='isento'`** (aula grátis não vira pendência no financeiro nem abre o modal de pagamento após "atendido"); valor preenchido → pendente normal. Etiqueta **⭐ experimental** (badge `tagExp`, âmbar) na agenda do dia, salões, grade semanal (pill + tooltip), lista mobile e ficha. Modo experimental **esconde a recorrência** (agendamento único) e é **bloqueado** nos fluxos de pacote/lista de espera; alerta do dashboard diz "Aula experimental agendada: <nome>".
  **(3) Excluir consulta pela aba Agendamentos + pela ficha do paciente (pedido do dono)** — antes só dava para excluir na Agenda do dia (e só navegando até o dia da consulta). Agora: **clicar numa consulta na grade semanal ou na lista mobile abre o modal "ações da consulta"** (`modal-consulta-acoes`: nome/data/status/etiquetas + botões **Ver ficha** / **Remarcar** / **Excluir**) — o clique antigo (abrir a ficha) continua a 1 toque pelo botão Ver ficha. Na **ficha do paciente** (aba Consultas), cada consulta ganhou botão **🗑** (`excluirConsultaFicha`), e a lista da ficha **recarrega sozinha** após excluir (novo callback opcional `aposExcluirConsulta` no `excluirConsulta`, respeitado também no fluxo de série). Todos os caminhos passam pelo `excluirConsulta` de sempre: confirmação obrigatória + escolha "só esta/esta e as próximas" quando é horário fixo.
  **Validado:** `node --check` + **46/46 testes de navegador** (Playwright, Supabase mockado, rede externa bloqueada): remarcar avulsa inalterada (1 update, sem opção de série), série "só esta" (1 update), série "esta e as próximas" (filtros serie_id/gte/neq-cancelado; 3 updates com delta exato +1h; troca de dia +24h; delta zero = zero updates; nenhum delete/insert), UI experimental (liga/desliga, aproveita nome da busca, recorrência some/volta, opção ⭐ na busca), validação bloqueia sem nome **sem tocar a rede**, salvar experimental (paciente mínimo com clinica_id certo, consulta experimental=true + paciente novo, isenta R$ 0 sem valor / pendente 50 com valor, sem serie_id, alerta certo), consulta normal **idêntica** (experimental=false, valor padrão, não cria paciente), pacote bloqueia o modo, modal de ações (abre com nome/status certos; Ver ficha/Remarcar/Excluir funcionam; excluir de série abre a escolha só esta/série), ficha (🗑 por consulta, confirmação, delete no id certo, lista recarregada) — **zero erro de JS**. Screenshots dos 3 modais conferidos.
- **2026-07-06** — **Agendamento recorrente / horário fixo (pedido de cliente por áudio). Migration APLICADA em produção; front na branch `claude/clinic-client-feature-rtl62b` dos 2 repos (falta merge na `main`).**
  Uma clínica cliente relatou (áudio) que pacientes com **horário fixo** (ex.: Pilates seg/qua/sex às 9h) exigiam **recadastro manual toda semana** — a ferramenta só criava consultas avulsas. Feito, **aditivo e conservador com os dados** (só INSERT de consultas, como o agendamento manual normal; nada apagado/embaralhado).
  **(1) DB — migration `20260706170000_consultas_serie_recorrente.sql` APLICADA em produção** (testada antes com **ROLLBACK** contra os dados reais — 2 linhas criadas com serie_id comum e **zero resíduo**): coluna **`consultas.serie_id`** (uuid, **nullable**, null = consulta avulsa) + índice parcial `idx_consultas_serie`. **Não altera RLS** (as policies de `consultas` são escopadas por `clinica_id`, agnósticas à coluna; INSERT em lote passa pela policy do dono/recepção que já existia). Advisors de segurança **sem regressão** (nenhuma função nova).
  **(2) Front (`nastadesk/index.html`)** — opção **"🔁 Repetir toda semana (horário fixo)"** no modal de nova consulta: **chips de dias da semana** (já marca o dia da data escolhida; multi-seleção seg/qua/sex…), **"repetir por" 4/8/12/24 semanas OU "até uma data específica"** (campo de data que aparece ao escolher esse modo; sugere +8 semanas e não deixa escolher antes da 1ª consulta) e **preview ao vivo** ("Serão criadas N consultas: … às HH:MM, de DD/MM a DD/MM"). `salvarConsulta` desvia para `salvarConsultaRecorrente`, que gera a série em **um único insert em lote** com `serie_id` compartilhado; **anti-duplicação** (busca o que o paciente já tem no período e **pula** horários ocupados → **idempotente** se rodar 2×), **nunca cria datas anteriores** à data inicial, **teto de 200** ocorrências por vez (o preview avisa quando bate no limite). **Etiqueta 🔁 fixo** na Agenda do dia, salões, grade semanal, lista mobile e ficha (`tagFixo`). **Excluir ciente da série:** consulta com `serie_id` abre modal com **"Só esta"** × **"Esta e as próximas"** (o delete filtra `serie_id` + `gte data_hora` — **não toca nas que já passaram**). **Escondido** nos fluxos de **pacote** e **lista de espera** (agendamento único — evita consumir sessões de pacote em lote). Como cada ocorrência é uma consulta normal, entra sozinha nos **lembretes**, no **feed ICS (`agenda-ics`)** e no **financeiro** (sem mudança nesses).
  **Validado:** `node --check` + **34/34 testes de navegador** (Playwright, Supabase mockado, rede externa bloqueada): geração de datas (dias/semanas, sem passado, ordem/únicas, 1ª data = data escolhida), **bulk insert com serie_id único** + valor/status/offset -03:00, **anti-duplicação** (cria 1 a menos quando o horário já existe), **avulsa inalterada** (objeto único, sem serie_id), badge `tagFixo`, **modal de série** + delete por `serie_id`/`gte`, avulsa não abre o modal de série, recorrência escondida em pacote/espera, **"até uma data"** (revela o campo, gera até a data inclusive, bloqueia data anterior à inicial), **teto de 200** respeitado, voltar a preset esconde o campo de data — **zero erro de JS**. Screenshots dos 2 modos conferidos.
  ***Falta:*** merge do front na `main` (Vercel) — a migration já está em produção e é **aditiva** (o front atual da `main` não é afetado). *Obs.: recurso é do painel (dono/recepção); o Portal do Profissional não cria recorrência (sem acesso), só enxerga as consultas normalmente.*
- **2026-07-06** — **EXTRAS (fecha os "Restam" da 10.5) · Integração Google Agenda/Outlook (feed ICS) + NPS por WhatsApp + Controle de estoque + Relatórios exportáveis + TRIAL self-service de 7 dias com corte automático. Migration + edge `agenda-ics` EM PRODUÇÃO; front na branch `claude/claude-md-tasks-b07n15` dos 2 repos (falta merge na `main`).**
  A pedido do dono ("pode fazer essa parte dos Extras"). **Decisões do dono nesta data:** trial de **7 dias** no plano **Premium**; corte automático de cortesia vencida **valendo as datas já marcadas** — ⚠️ **B&D (vence 06/07) e AC Fisioterapia (14/07) serão suspensas pelo cron se não assinarem** (para reverter: conceder cortesia de novo pelo painel admin).
  🐛 **Bug corrigido de brinde:** a migration `20260704160000` reescreveu `criar_clinica_no_signup` e **perdeu o `ativo=false` do paywall** — desde 04/07 clínica nova entrava **de graça para sempre** (default da coluna é true). Agora o cadastro dá um **trial controlado** (ativo+cortesia+7d+premium).
  **(1) DB — migration `20260706150000_extras_trial_estoque_nps_ics.sql` APLICADA em produção** (testada antes com ROLLBACK/asserts contra os dados reais): tabelas **`estoque_itens` + `estoque_movimentos`** (saldo mantido por **trigger** `estoque_aplicar_movimento` — o front só INSERE movimentos; RLS dono+recepção ALL, profissional nada); tabela **`nps_respostas`** (nota 0–10 com CHECK, null = aguardando resposta; RLS dono+recepção); coluna **`clinicas.ics_token`** (uuid unique, backfill nas 3 clínicas); **`paciente_anonimizar`/`paciente_excluir` estendidas** p/ limpar o NPS do paciente (LGPD); **gatilho de signup com trial**; função **`encerrar_cortesias_vencidas()`** (revoke de anon/authenticated; **guarda de assinatura ativa/em_atraso**) + **job pg_cron `nastadesk-cortesia-expira`** (minuto 7 de cada hora). Checks do ROLLBACK: saldo 10−3=7 via trigger; RLS (dono vê, usuário aleatório vê 0); signup simulado em auth.users criou clínica premium/7d/consentimento LGPD; corte derruba trial vencido; **guarda NÃO corta quem tem assinatura ativa**. Advisors de segurança **sem regressão**.
  **(2) Edge `agenda-ics` (v1, deployada, `verify_jwt=false`, no config.toml)** — feed **ICS (RFC 5545)** da agenda p/ assinar no Google Agenda/Outlook/Apple: janela −7/+60 dias, sem canceladas, evento com paciente/modalidade/profissional/sala/status, teleconsulta com link Jitsi, duração = `intervalo_consulta`. Segurança: token uuid na URL (mesmo modelo do "endereço secreto" do Google), 404 p/ token inválido/clínica inativa, 405 p/ não-GET, escaping + line folding RFC. **Validada com curl em produção** (404/405/ICS real ok).
  **(3) Front (`index.html`)** — **Estoque:** nova seção na nav (ícone caixa + badge de reposição), cards Itens/Repor, lista com busca e filtro "só em alerta", modal de item (categoria com sugestões, unidade, mínimo, qtd inicial vira movimento "Estoque inicial"), modais de Entrada/Saída com motivo + últimos 8 movimentos, saída maior que o saldo pede confirmação, **arquivar é soft** (ativo=false, histórico fica); papel profissional não vê (nav + RLS). **NPS:** card no Relatório com score do mês (promotores−detratores, colorido), breakdown 😍😐😞, modal "Enviar pesquisa" (lista pacientes com WhatsApp, msg editável com {nome}, **registra o envio ANTES de abrir o wa.me**), pendentes com select 0–10 + comentário + descartar, respostas do mês listadas. **Relatório exportável:** botões **⬇ CSV** (consultas do mês com joins, escaping correto de aspas/vírgulas, total recebido no rodapé, BOM p/ Excel) e **🖨 Imprimir/PDF** (`@media print` esconde navegação/botões e imprime só a seção ativa). **Agenda externa:** botão **📅** em cada consulta (agenda do dia + salões) abre menu Google Agenda / Outlook / baixar .ics (evento com duração da clínica, link Jitsi se teleconsulta) + atalho "Sincronizar tudo automaticamente"; card **"Integração com Google Agenda/Outlook"** em Configurações → Agenda (URL do feed, copiar, instruções por app, aviso de privacidade do link e **Gerar novo código secreto** — atualiza `ics_token` e mata o link antigo). **Trial:** banner fixo com dias restantes + "Assinar agora" (verde; âmbar a ≤2 dias; some p/ quem tem assinatura), paywall com caso novo **"Seu teste grátis terminou"** (dados continuam salvos), toast pós-onboarding com os dias, selo "✨ 7 dias grátis com tudo liberado — sem cartão" no cadastro.
  **Validado:** `node --check` + **35/35 testes de navegador** (Playwright, Supabase mockado, rede externa bloqueada): banner/paywall/selo do trial, estoque (lista, alerta, badge, insert com clinica_id, qtd inicial→movimento, validação bloqueia sem rede, saída), NPS (filtra sem-WhatsApp/inativos, registra envio antes do wa.me, score 25 no cenário 2/1/1, pendente com select), agenda externa (URLs Google/Outlook corretas com 60min + Jitsi, menu 📅, feed com token, regenerar troca token e atualiza o link), CSV (nome, escaping, total), gate por papel (profissional sem Estoque) — **zero erro de JS**.
  ***Falta:*** merge do front na `main` (Vercel) — migration e edge já estão em produção e são aditivas ao front atual. *Lembretes:* (a) o corte de cortesia **já está ativo** — B&D/AC caem quando a data passar (decisão do dono); (b) trial usa a mesma mecânica de cortesia — cortesia manual **sem data** segue eterna; (c) melhoria futura possível: NPS automático via bot (hoje o envio é 1-clique e o registro da nota é manual — não mexi no `whatsapp-webhook` de produção por segurança).
- **2026-07-05** — **FASE 3 (parte 1) · Prontuário estruturado de fisio + Anexos de exames + Teleconsulta + Lista de espera. Migration APLICADA em produção; front na branch `claude/phase-3-jjk0dk` dos 2 repos (falta merge na `main`).**
  A pedido do dono ("Agora vamos fazer a fase 3"). Entregues os itens viáveis da Fase 3; os 2 que dependem de decisão/cadastro do dono (assinatura digital ICP-Brasil e TISS) ficam documentados na seção 10.5.
  **(1) DB — migration `20260705200000_fase3_prontuario_teleconsulta_espera.sql` APLICADA em produção**, depois de **testar contra os dados reais com ROLLBACK** (22 checks com JWT simulado): tabela **`avaliacoes`** (tipo eva/goniometria/postural/funcional + `dados` JSONB; RLS espelhando `evolucoes` — dono ALL, recepção ALL, profissional SELECT/INSERT só dos pacientes dele, sem UPDATE/DELETE); tabela **`lista_espera`** (paciente cadastrado OU nome avulso; status aguardando/agendado/removido; RLS dono+recepção; profissional sem acesso); coluna **`consultas.teleconsulta`** (boolean default false); **bucket privado `exames`** no Storage (10 MB, pdf/jpg/png/webp/heic) com **policies por papel em `storage.objects`** (dono/recepção ALL por clínica; profissional SELECT só dos pacientes dele; caminho `clinica_id/paciente_id/…`, comparação por texto sem cast); **`paciente_anonimizar`/`paciente_excluir` estendidas** para limpar também `avaliacoes` e `lista_espera`. Isolamento validado: dono A não vê nada da clínica B (e vice-versa), usuário aleatório vê 0, profissional vê só o do paciente dele, insert p/ paciente de outro → 42501, delete como profissional → 0 linhas. Índices em todas as FKs novas; advisors de segurança **sem regressão** (os `multiple_permissive_policies` novos são o mesmo padrão intencional dono+membros das outras 15 tabelas).
  ⚠️ **Descoberta de arquitetura:** o Storage do Supabase **BLOQUEIA DELETE direto via SQL** em `storage.objects` ("Use the Storage API instead") — insert passa, delete não. Por isso as RPCs LGPD **não** apagam arquivos; quem apaga os exames é o **front via Storage API, ANTES de chamar a RPC, fail-closed** (se falhar, a eliminação/exclusão do paciente não segue). Testado no navegador nos dois fluxos.
  **(2) Prontuário estruturado (`index.html`)** — aba **Avaliações** na ficha: 4 templates (EVA com slider + cor por intensidade; goniometria com linhas dinâmicas articulação/movimento/lado/ADM ativa+passiva e datalists de sugestões; postural com 3 vistas; funcional com testes sugeridos TUG/Berg/6min/etc + resultado/unidade), select opcional de profissional, validação por tipo (não deixa salvar vazio), **gráfico SVG da evolução da dor (EVA)** a partir de 2 medições, histórico renderizado por tipo (tabela de goniometria etc.) e excluir com confirmação (só no painel; no portal não). Auditoria LGPD: `registrou_avaliacao`/`excluiu_avaliacao`.
  **(3) Exames (`index.html`)** — aba **Exames** na ficha: upload com sanitização de nome + validação de tamanho/tipo, listagem (nome/data/KB), abrir via **URL assinada** (5 min), excluir com confirmação. **Exportar dados do titular agora inclui avaliações + lista dos exames**; anonimizar/excluir apagam os exames primeiro (fail-closed, ver acima). Auditoria: `anexou_exame`/`baixou_exame`/`excluiu_exame`.
  **(4) Teleconsulta** — checkbox no modal de nova consulta → `consultas.teleconsulta`; badge **📹 vídeo** na agenda do dia (lista e salões), grade semanal (📹 no pill + tooltip), lista mobile e ficha; botões **Entrar na sala** e **Enviar link** (wa.me com mensagem pronta). Sala **Jitsi Meet** (grátis, sem conta): `https://meet.jit.si/NastaDesk-<20 hex do id>` — mesma regra no painel e no portal. Zero infra nova.
  **(5) Lista de espera** — botão com **contador** na topbar de Agendamentos; modal com a fila (tempo de espera, preferência, tags de modalidade/profissional), **WhatsApp em 1 clique**, **Agendar** (pré-seleciona paciente/modalidade/profissional no modal de consulta e, ao salvar, marca `status='agendado'` sozinho) e **Remover** (soft — nada apagado). Busca de paciente cadastrado OU entrada avulsa (nome+wpp); quem não tem cadastro ganha atalho p/ cadastrar.
  **(6) Portal do Profissional (`profissional.html`)** — **Avaliações** na ficha (registrar EVA/goniometria/postural/funcional com formulários inline; cada registro **assinado com o profissional do vínculo**; gráfico da dor; sem excluir nada), **Exames só leitura** (abrir via URL assinada) e **teleconsulta** (badge + Entrar na sala).
  **Validado:** `node --check` (2 páginas) + **78/78 testes de navegador** (Playwright, Supabase mockado, zero rede real): payloads de insert por tipo, validações bloqueiam SEM tocar a rede, gráfico com N pontos, upload sanitizado no caminho certo, URL assinada, **fail-closed do LGPD nos 2 fluxos**, teleconsulta true no insert + links Jitsi/wa.me, fila filtra por clínica+status, agendar-da-fila liga e desliga a entrada, portal assina avaliação com o prof do vínculo, portal segue **sem "R$" e sem DELETE** — **zero erro de JS**.
  ***Falta:*** merge do front na `main` (Vercel) — a migration já está em produção e é **aditiva** (o front atual da `main` não é afetado). *Não entram nesta parte (ver 10.5):* **assinatura digital ICP-Brasil** (exige certificado digital pago — decisão do dono) e **TISS/convênios** (exige credenciamento da clínica nos convênios; entrega dedicada).
- **2026-07-05** — **Fechadas as 2 pendências não-bloqueantes do Portal do Profissional (edge `equipe-criar` v2 + revogar `execute` do `anon`).** *(Feito por outro chat na branch `claude/portal-profissional-pendencias-akk6tg`; registro incorporado aqui porque aquela branch não chegou à `main`.)*
  Completa a entrega de 2026-07-05 anterior. **(1) Edge `equipe-criar` v2 deployada em produção** (o código com a validação de vínculo — `profissional_id` obrigatório e validado como da própria clínica para papel `profissional` — já estava no repo desde 2026-07-04; agora está ativa, versão 2). **(2) Revogado `execute` do `anon`** nas 3 funções auxiliares do portal — `meu_profissional_id()`, `clinica_ids_recepcao()`, `pacientes_do_profissional()` — mantendo `authenticated` intacto (confirmado por SQL antes/depois). Cosmético/padronização (essas funções já retornavam vazio para quem não estava logado), mas agora bate com o padrão da irmã `clinica_ids_membro()`. **Validado:** advisors de segurança sem warning novo; nenhuma migration nova (revoke direto, mudança de grant); nada de dado tocado. Com isso, o **Portal do Profissional está 100% concluído**, sem pendências. *(Reconfirmado nesta sessão da Fase 3: edge na v2 e `anon` sem EXECUTE nas 3 funções.)*
- **2026-07-05** — **Plugin de Claude Code "claude-mem" (thedotmack/claude-mem) habilitado para os dois repos, junto com o context-mode (configuração de ferramenta, não afeta o produto/clientes).**
  A pedido do dono, para tentar reduzir a dependência deste próprio CLAUDE.md como "memória manual" — o claude-mem captura o que o agente faz nas sessões, comprime com IA e injeta de volta o que for relevante nas sessões seguintes (memória automática entre sessões), complementando o context-mode (que ataca saída de ferramentas, não memória de negócio). Adicionado ao mesmo `.claude/settings.json` dos dois repos: marketplace `thedotmack/claude-mem` em `extraKnownMarketplaces` + `enabledPlugins: {"claude-mem@claude-mem": true}`. **Não testado ainda em uso real** — os dois plugins (context-mode + claude-mem) mexem em áreas parecidas (gestão de contexto), então vale observar nas próximas sessões se há atrito entre eles, e se dá para começar a enxugar o Histórico deste arquivo (seção 9) com o tempo. **Não mexe em nada do produto NastaDesk.**
- **2026-07-05** — **Plugin de Claude Code "context-mode" (mksglu/context-mode) habilitado para os dois repos (configuração de ferramenta, não afeta o produto/clientes).**
  A pedido do dono, para reduzir gasto de tokens/contexto nas sessões de chat que trabalham nestes repositórios. Criado `.claude/settings.json` em **`nastadesk`** e em **`dashboard`** (idênticos), registrando a marketplace `mksglu/context-mode` (`extraKnownMarketplaces`) e habilitando o plugin (`enabledPlugins: {"context-mode@context-mode": true}`). Isso faz o plugin ficar disponível automaticamente em futuras sessões de nuvem do Claude Code nestes projetos, sem precisar rodar `/plugin marketplace add`/`/plugin install` manualmente a cada sessão. **Não mexe em nada do produto NastaDesk** (agenda, pacientes, financeiro, banco) — é só configuração do assistente de código.
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
- [x] **Portal do Profissional + acesso restrito por papel** — FEITO e **em produção** (2026-07-05, fechado 100% em 2026-07-05). A pedido do dono: profissional NÃO vê todos os pacientes da clínica nem exclui nada; vê **só quem ele atende**. Front dedicado `profissional.html` (Hoje/Agenda/Meus pacientes, ficha read-only + evoluções, sem financeiro) + RLS por papel — migration `portal_profissional_rls` **APLICADA em produção** e validada com JWT simulado (profissional com vínculo vê só o dele; sem vínculo vê 0; recepção intacta; reatribuição bloqueada). Front **mergeado na `main`** (Vercel publicou; `nastadesk.vercel.app/profissional.html` no ar). Card "Logins da equipe" ganhou **vincular/editar profissional** de logins já criados. **Edge `equipe-criar` v2 (validação de vínculo no servidor) deployada** e **`execute` do `anon` revogado** em `meu_profissional_id`/`clinica_ids_recepcao`/`pacientes_do_profissional` (confirmado por SQL: `anon` sem EXECUTE, `authenticated` intacto; advisors sem regressão) — **0 pendências restantes.**
- [~] **Nota fiscal de serviço (NFS-e)** — ⚠️ **Emissão de NFS-e exige CNPJ** (ou inscrição municipal de autônomo) — é regra fiscal, nenhum emissor contorna. O **dono não tem CNPJ**, então a NFS-e via **Focus NFe** (que já está construída na branch `claude/financial-phase-2-8q575q`, tabelas `config_fiscal`/`notas_fiscais` no banco) **NÃO foi deployada**. Caminho fiscal atual **sem CNPJ = Recibo de pagamento em PDF** (já existe, botão na consulta paga). **Para ligar a NFS-e no futuro:** dono abre **MEI** (grátis → CNPJ) e configura o emissor. *Melhoria sugerida do recibo:* CREFITO/CPF do profissional (dedução IR médico) + recibo p/ mensalidade/pacote.
- [x] **Financeiro completo** — FEITO 2026-07-03 (deployado na `main`). Aba **Financeiro → Despesas**: contas a pagar por categoria (status paga/pendente/vencida em 1 clique, repetir nos próximos meses), **fluxo de caixa do mês** (Entradas/Saídas/Saldo), **DRE simples** por categoria e **export CSV**. Construído do zero em cima da `main` atual usando a tabela `despesas` que já estava em produção (schema `competencia`/`status`) — **não mergeei a branch `financial-phase-2`** (16 commits atrás; mergear apagaria LGPD/2FA/PWA). Já feito antes: **Repasse/comissão** (2026-07-01). *Falta (opcional):* despesas recorrentes "de verdade" (tabela `despesas_recorrentes` existe) e gráficos.
- [ ] **Pagamento self-service do paciente (Pix/checkout) com baixa automática** — ⏸️ **ADIADO a pedido do dono (2026-07-04): NÃO fazer agora; talvez no futuro. Ideia salva aqui.** Hoje o dono marca pago/pendente na mão (consulta, pacote ou mensalidade). Objetivo: o **paciente paga sozinho** (inclusive adiantado) e o status **atualiza automaticamente** no NastaDesk pro dono ver.
  - **Viável?** Sim. Caminho recomendado p/ Brasil: **Pix via um PSP com webhook** (ex.: Asaas, Efí/Gerencianet, Mercado Pago, Pagar.me) — sem taxa de cartão e confirmação na hora. Gera um Pix (copia-e-cola/QR) por cobrança; quando o paciente paga, o PSP chama uma **edge function** que dá **baixa automática** na cobrança (idempotente + HMAC), casando pelo id de referência.
  - **Por que é fase dedicada (não agora):** (1) cada clínica conecta a **própria conta** do PSP → a clínica recebe direto e a **Nastaclin não fica no meio do dinheiro** (evita virar "facilitador de pagamento"/peso regulatório); (2) reconciliação segura/idempotente; (3) **aditivo** — a baixa manual continua como fallback, sem tocar no financeiro atual; (4) LGPD/dados financeiros exigem cuidado.
  - **MVP sugerido:** começar por **mensalidades** (recorrente/previsível) OU por consulta, com **1 PSP via Pix**, link/QR por cobrança + webhook de baixa. **Boa ideia — recomendo fazer**, como entrega própria (concorrentes já oferecem link de pagamento ao paciente).
- [x] **PWA instalável** — FEITO 2026-07-03 (deploy na `main` em andamento). `manifest.json` + ícones PNG (192/512/apple-touch) + `sw.js` (service worker **network-first no HTML** — não congela a clínica numa versão velha; cache-first só nos ícones; não intercepta cross-origin). Metas de PWA no `<head>`, botão flutuante "Instalar app" (via `beforeinstallprompt`) e `vercel.json` ajustado p/ publicar os assets.

### 10.5 FASE 3 — Diferenciação (depois da paridade)

> ▶️ **Parte 1 entregue em 2026-07-05** (branch `claude/phase-3-jjk0dk`; migration já em
> produção; front aguarda merge na `main`). Detalhes no Histórico (seção 9).

- [x] **Prontuário estruturado de fisio** — FEITO 2026-07-05. Aba **Avaliações** na ficha (e no Portal do Profissional): templates de **EVA de dor** (0–10 + **gráfico de evolução**), **goniometria** (ADM ativa/passiva por articulação/movimento/lado), **avaliação postural** (3 vistas) e **testes funcionais** (TUG, Berg, 6min…). Tabela `avaliacoes` (JSONB) com RLS por papel espelhando `evolucoes`. **+ Anexos de exames**: aba **Exames** na ficha — PDF/imagem até 10 MB no bucket privado `exames` (Storage) com policies por clínica/papel, abrir por URL assinada; profissional só lê. LGPD: exportação inclui tudo; anonimizar/excluir limpam avaliações e apagam exames **fail-closed** (front via Storage API — o Storage bloqueia DELETE via SQL).
- [ ] **Assinatura digital (ICP-Brasil)** das evoluções/prontuário — ⏸️ **depende de decisão do dono:** exige **certificado digital ICP-Brasil pago** (e-CPF A1/A3 do profissional, ~R$ 100–300/ano cada) + integração com serviço de assinatura. Sem o certificado não há o que integrar. Quando o dono quiser: avaliar assinatura via plataforma (ex.: gov.br assinador é grátis p/ pessoa física, mas manual) ou API paga. *Alternativa leve já existente: trilha de auditoria LGPD registra quem/quando registrou cada evolução/avaliação.*
- [x] **Teleconsulta** — FEITO 2026-07-05. Checkbox no agendamento + badge 📹 nas agendas + **Entrar na sala** / **Enviar link ao paciente** (wa.me). Sala **Jitsi Meet** (grátis, sem conta, sem servidor) com nome não-adivinhável derivado do id da consulta. Também no Portal do Profissional. Coluna `consultas.teleconsulta` aditiva.
- [ ] **Convênios / TISS** — faturamento de guias/XML (hoje só há o campo "convênio"). **Entrega dedicada e grande** (padrão TISS/ANS, versões por convênio, credenciamento da clínica) — só vale começar quando alguma clínica cliente pedir de verdade.
- [x] **Extras** — ✅ **CONCLUÍDO 2026-07-06** (detalhes no Histórico): **integração Google Agenda/Outlook** (botão 📅 por consulta + feed ICS assinável via edge `agenda-ics`), **NPS por WhatsApp** (envio 1-clique + registro da nota + score no Relatório), **controle de estoque** (seção própria, saldo por trigger, alerta de reposição), **relatórios exportáveis** (CSV + Imprimir/PDF) e **trial self-service de 7 dias Premium no cadastro** (com corte automático via pg_cron + guarda p/ assinantes). Já feitos antes: lista de espera (2026-07-05) e Satisfação (pergunta no pagamento). *Sobra opcional:* NPS automático pelo bot (hoje o registro da nota é manual).

### 10.6 Evidências técnicas da auditoria (para não reinvestigar)

- **Advisor de segurança:** `auth_leaked_password_protection` **OFF**; `admin_config` com RLS sem policy (ok — fica só p/ service_role); `agendar_online` / `clinica_publica` / `horarios_ocupados` são SECURITY DEFINER expostos ao anon (**intencional** — booking público).
- **Advisor de performance:** `auth_rls_initplan` em ~24 policies; `multiple_permissive_policies` em `clinicas` / `consultas` / `pacientes` / `evolucoes`; `unindexed_foreign_keys` (lista na Fase 0); vários `unused_index` (base pequena ainda — ignorar por ora).
- **Nenhum RLS crítico desabilitado** — todas as tabelas de dados têm RLS + policy.
- **Front:** `nastadesk/index.html` ≈ 5.413 linhas / ~334 KB, arquivo único, **sem testes, sem CI, sem lint, sem monitor de erros**; 0 `aria-*`/`role=`; inputs sem `required`/`maxlength`; 0 PWA.
- **`cakto-webhook`:** fail-open no secret; sem HMAC; ausente do `config.toml`.
- **Pagamento mapeado por e-mail** é frágil (cliente paga com outro e-mail → não ativa) — prever tela admin de reconciliação.

---

## 11. Conta de demonstração (modo `MODO_DEMO`) — como funciona

Login que abre uma clínica de exemplo para mostrar a ferramenta funcionando. **Não existe
conta de verdade no Supabase** e **nenhum dado real é lido, gravado ou apagado.**

**Onde ficam as credenciais:** `config_publica.demo` = `{email, senha, ativo}` — o dono edita
em **Painel admin → Configurações → Conta de demonstração** (com mensagem pronta para copiar
e enviar). Padrão embutido no front, caso a chave suma: `demo@nastadesk.com.br` / `Demo@2026`.
⚠️ Essa senha é **pública por natureza** (o app precisa reconhecê-la, e `config_publica` é
legível por `anon`) — por isso ela **não dá acesso a nada**: **nunca reaproveitar** uma senha
de conta real.

**Como funciona (tudo em `nastadesk/index.html`, bloco "MODO DEMONSTRAÇÃO"):**
1. `fazerLogin` compara com `cfgDemo()` **antes** de chamar o Supabase. Se bater → `entrarModoDemo()`.
2. `db` (o cliente do supabase-js) é **substituído** por `demoCliente()` — por isso o `db` virou
   `let` em vez de `const`. Daí em diante **nenhuma chamada sai do navegador**.
3. `demoFrom()` imita o query builder do PostgREST: `select/insert/update/upsert/delete`,
   `eq/neq/gt/gte/lt/lte/in/is/not/ilike`, `order/limit/range`, `single/maybeSingle`,
   `count:'exact'`+`head` e os relacionamentos embutidos que o app pede
   (`*, pacientes(nome)`, `modalidades(nome)`, `profissionais(nome)`, `salas(...)`, `clinicas(*)`).
   O que não conhece devolve vazio em vez de quebrar.
4. Os dados vivem no **`sessionStorage`** (`nastadesk_demo_v1`). **Fechou a aba/navegador,
   acabou** — na próxima vez a semente é gerada de novo. Sobrevive ao F5 de propósito (senão
   a demonstração se perderia no meio). Botão **"Recomeçar do zero"** no banner verde do topo.
5. **Saídas para o mundo real são travadas**: `wa.me`, `api.whatsapp.com` e `pay.cakto.com.br`
   viram um aviso ("na conta real isso abriria de verdade"). Jitsi, Google Agenda e o recibo
   em PDF continuam funcionando, porque são inofensivos e mostram bem o produto.

**A semente (`demoSemente()`)** monta a clínica "Clínica Movimento (demonstração)" — plano
Premium com assinatura ativa (não cai no paywall), 3 profissionais, 4 modalidades, 3 salas,
14 pacientes, agenda de hoje com status variados, série de horário fixo, teleconsulta, aula
experimental, agendamento online, **10 semanas de histórico** (alimenta financeiro e relatório),
mensalidades, 3 pacotes, 7 despesas, estoque com 2 itens abaixo do mínimo, NPS (4 respondidos +
2 pendentes), 3 conversas de WhatsApp com o bot, avaliações (EVA em 4 pontos → o gráfico da dor
aparece), evoluções, lista de espera e alertas.

⚠️ **Duas armadilhas que já custaram bug aqui — não repetir:**
- **Fuso:** as datas da semente são montadas como `YYYY-MM-DDTHH:MM:00-03:00` (igual ao que o
  app grava) e o "hoje" sai de `Intl.DateTimeFormat` em `America/Sao_Paulo`. Usar
  `new Date()` + `setHours()` faz a agenda aparecer com **horário deslocado** no computador de
  quem testa (foi o que aconteceu: 07:00 virava 04:00).
- **Gerador aleatório:** usar `Math.imul` para manter a conta em 32 bits. A versão ingênua
  (`semente * 1103515245`) **estoura os 2^53 do JavaScript**, perde os bits baixos e passa a
  devolver sempre o mesmo resto — o efeito foi **quase todo o histórico nascer "cancelado"**,
  deixando financeiro e relatório vazios.

**Testes:** `scratchpad/teste_demo.js` (57 checks) — entra pela tela de login, confere que
**zero chamadas** vão ao Supabase depois de entrar, que as 11 telas abrem, que o histórico é
variado (status, profissionais, formas de pagamento), que dá para criar registros, que sobrevive
ao F5 e que **uma sessão nova do navegador começa zerada**. Roda em 2 fusos (São Paulo e Tóquio).

---

### Como manter este arquivo (lembrete)

Sempre que terminarmos uma alteração: atualize a seção afetada, registre no
Histórico (seção 9) e replique a mudança no `CLAUDE.md` do outro repositório.
Mantenha os dois arquivos idênticos.
