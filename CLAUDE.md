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

> Documento de contexto mantido para continuidade entre chats. Última atualização: **2026-06-30**.

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
| `admin-api` | Backend do painel admin. Valida que quem chama é o admin e só então lê todas as clínicas/assinaturas e roda ações administrativas com a service_role. |

## 4. Funcionalidades do app (nastadesk)

- **Agenda do dia** — consultas em tempo real, status, métricas, mini-calendário.
- **Agendamentos** — grade semanal (desktop) e lista (mobile); remarcar/excluir.
- **Agendamento online** — link público `/agendar/<slug>` para o paciente marcar
  sozinho, com QR Code. Usa RPCs públicas (`clinica_publica`, `horarios_ocupados`,
  `agendar_online`) que validam tudo no servidor.
- **Salas / salões de atendimento** — organizar consultas por sala, além de
  data/horário.
- **Lembretes WhatsApp** — mensagens prontas (confirmação, véspera, dia) com
  envio em 1 clique (via `wa.me`), além dos lembretes automáticos.
- **Pacientes** — ficha completa: anamnese, evoluções, histórico, convênio, CPF;
  importação/exportação por CSV.
- **Pacotes de sessões** — venda/controle de pacotes de sessões.
- **Financeiro** — valor por consulta, registro de pagamento (Pix, cartão,
  dinheiro…), recibo em PDF, faturamento do mês.
- **Relatório mensal** — comparecimento, faturamento, origem dos agendamentos,
  formas de pagamento.
- **Chatbot de WhatsApp** — ver seção 6.
- **Conta** — onboarding guiado, recuperação de senha, configuração de horários
  e mensagens.

## 5. Planos, preços e acesso

### Preços (assinatura mensal por clínica)

| Plano | Preço/mês | Observações |
|---|---|---|
| **Básica** | **R$ 97** | Gestão + lembretes manuais por WhatsApp. **Sem chatbot de IA.** |
| **Profissional** | **R$ 197** | Inclui o **chatbot de WhatsApp com IA**. |
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

---

### Como manter este arquivo (lembrete)

Sempre que terminarmos uma alteração: atualize a seção afetada, registre no
Histórico (seção 9) e replique a mudança no `CLAUDE.md` do outro repositório.
Mantenha os dois arquivos idênticos.
