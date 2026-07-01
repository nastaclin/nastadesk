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

> Documento de contexto mantido para continuidade entre chats. Última atualização: **2026-07-01**.

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
| `nfse` | Emissão de **NFS-e via PlugNotas** (TecnoSpeed). Chamada pelo painel com o JWT da clínica; valida a clínica, monta o payload a partir de `config_fiscal` + consulta + paciente, envia (`POST /nfse`), consulta a situação e grava em `notas_fiscais` (idempotente por consulta). Lê `PLUGNOTAS_API_KEY` do ambiente e é **fail-safe** (sem token → responde "não ligado", sem emitir nada). |
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
  **modalidade** (Fisio/Pilates/…) e **cobrança** (mensalidade fixa OU por sessão,
  com valor e dia de vencimento); importação/exportação por CSV.
- **Modalidades** — lista configurável de tipos de atendimento (Fisioterapia,
  Pilates, RPG…), com cor por modalidade. Vira etiqueta no paciente, na agenda do
  dia e no financeiro, e dá pra filtrar pacientes por modalidade. Gerenciada em
  Configurações → Modalidades (cada clínica já nasce com Fisioterapia + Pilates).
- **Profissionais** (multi-profissional) — lista configurável de quem atende
  (nome, registro/CREFITO opcional, cor), em Configurações → Profissionais. Vira
  etiqueta colorida na Agenda do dia (lista e "por salão") e na grade semanal,
  filtro por profissional na Agenda do dia, e um select opcional no agendamento
  (com reatribuição inline na agenda). **Aditivo:** clínica sem profissional
  cadastrado não vê diferença. *Sem login por profissional ainda* (é só "recurso"
  da agenda); login + papéis e repasse/comissão são etapas futuras.
- **Pacotes de sessões** — venda/controle de pacotes de sessões.
- **Financeiro** — **(a) por consulta** (inalterado): valor por consulta, registro
  de pagamento (Pix, cartão, dinheiro…), recibo em PDF, faturamento do mês;
  **(b) Mensalidades** (novo): cobrança recorrente por paciente (valor + dia de
  vencimento), controle **pago / pendente / vencido** mês a mês com histórico. A aba
  "Mensalidades" abre as cobranças do mês automaticamente e marca pago em 1 clique.
  **(c) Repasse** (novo): comissão por profissional (% do valor OU valor fixo por
  consulta), calculada sobre as consultas *atendidas* do mês, em Financeiro → Repasse.
  **(d) Despesas / Contas a pagar** (novo): lançar despesas (aluguel, materiais, salários,
  impostos…) com categoria, vencimento e status pago/pendente, marcando pago em 1 clique,
  em Financeiro → Despesas. Suporta **contas fixas (recorrentes)** — marca "repetir todo mês"
  e a conta abre sozinha todo mês (idempotente, padrão das mensalidades). **(e) Resumo** (novo):
  **fluxo de caixa** do mês (entradas − saídas) + **DRE simples** (receitas por origem − despesas
  por categoria = resultado), com **gráfico** entradas × saídas e **exportação em CSV**, em
  Financeiro → Resumo.
- **Nota fiscal (NFS-e)** — emissão de nota fiscal de serviço **via PlugNotas** (Edge Function
  `nfse`). Em Configurações → Nota fiscal a clínica guarda os **dados fiscais** (razão social,
  CNPJ, IM, regime, **código do serviço LC116**, ISS, CNAE, ambiente homologação/produção) e vê
  o **status do emissor**. Quando está tudo configurado, cada consulta paga (Financeiro →
  Consultas) ganha o botão **“+ NF-e”**: emite (assíncrono), acompanha a situação
  (⏳ processando → ✓ emitida) e abre o **PDF/XML**. **Fail-safe:** sem a chave do PlugNotas ou
  sem dados fiscais, o botão não emite — mostra o que falta. **Vai ao ar quando** a Nastaclin
  configurar a `PLUGNOTAS_API_KEY` e cada clínica tiver **CNPJ com NFS-e habilitada + certificado
  digital A1 + conta no PlugNotas**. Enquanto não, o comprovante segue sendo o **Recibo em PDF**.
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

- **2026-07-01** — **Fase 2 · NFS-e de verdade (emissão via PlugNotas) — construída e validada no sandbox.**
  Integração completa com o **PlugNotas** (TecnoSpeed), lida do **spec OpenAPI real** (não inventado).
  Migration `20260701160000_nfse.sql` **aplicada em produção**: `config_fiscal` ganhou `ambiente`
  (homologacao|producao), `cnae`, `codigo_tributacao_municipio`; e tabela nova **`notas_fiscais`**
  (ledger idempotente por consulta: status rascunho/processando/emitida/erro/cancelada, protocolo,
  número, links de PDF/XML). **Edge Function `nfse`** (deployada, `verify_jwt=true`, no `config.toml`):
  ações `config`/`emitir`/`consultar`; autentica pela clínica (padrão do `whatsapp-conexao`), monta o
  payload a partir de `config_fiscal`+consulta+paciente, envia `POST /nfse` (assíncrono), consulta por
  `idIntegracao/{cnpj}` e grava o resultado. **Fail-safe:** sem `PLUGNOTAS_API_KEY` responde "não ligado"
  e não emite nada. Front (`nastadesk/index.html`): Configurações → Nota fiscal virou tela real (dados
  fiscais + **status do emissor** ao vivo + passo a passo honesto do que a clínica precisa); Financeiro →
  Consultas ganhou o botão **“+ NF-e”** por consulta paga, com badges ⏳/✓/✗ e link do PDF. **Validado de
  verdade contra o sandbox do PlugNotas** (token público): emissão retornou `protocol`+`documents[0].id` e
  a consulta retornou `situacao: CONCLUIDO`, `numeroNfse: 9422`, PDF/XML — o parsing da função bate 100%.
  `node --check` + smoke no navegador OK. **Falta p/ emitir de verdade (fora do código, é da clínica/dono):**
  `PLUGNOTAS_API_KEY` no servidor + CNPJ com NFS-e habilitada + **certificado A1** + conta no PlugNotas.
  *Também falta:* deploy do front (merge na `main`). **Certificado/empresa cadastrados no painel do PlugNotas**
  (upload do A1 automático fica p/ etapa futura). Webhook de status do PlugNotas: futuro (hoje é por consulta).
- **2026-07-01** — **Fase 2 · Melhorias no financeiro: despesas recorrentes + gráfico e CSV no Resumo.**
  Aditivo. Migration `20260701150000_despesas_recorrentes.sql` **aplicada em produção**: tabela
  **`despesas_recorrentes`** (template de conta fixa) + `despesas.recorrencia_id` + índice único
  idempotente + RPC **`gerar_despesas_recorrentes(competencia)`** (padrão das mensalidades, nunca
  retroativo). Front: checkbox **"conta fixa — repetir todo mês"** no modal de despesa (cria o template e
  a 1ª ocorrência; excluir para a recorrência), etiqueta "mensal" na lista; e no **Resumo**, um **gráfico
  de barras** (entradas × saídas) + botão **Exportar CSV** (fluxo + DRE, separador `;`/vírgula p/ Excel BR).
  `node --check` + smoke no navegador (resumo 1.360/1.350/10; CSV `resumo-2026-07.csv`; conta fixa OK).
- **2026-07-01** — **Fase 2 · Financeiro completo (Despesas/Contas a pagar + Fluxo de caixa + DRE) + base da Nota fiscal (NFS-e).**
  Aditivo e seguro — só **tabelas novas isoladas por clínica**; o financeiro por consulta/mensalidade/repasse continua **idêntico**.
  Migration `20260701140000_despesas_fiscal.sql` **aplicada em produção**: tabela **`despesas`** (contas a pagar: descrição,
  categoria, valor, competência, vencimento, status pendente/pago, forma) e tabela **`config_fiscal`** (dados fiscais por clínica:
  razão social, CNPJ, IM, regime, código de serviço, alíquota ISS — **fundação da NFS-e**). Ambas com RLS performático
  (`(select auth.uid())` + `TO authenticated`). Front só em `nastadesk/index.html`: Financeiro ganhou **2 abas novas** —
  **Despesas** (lançar/editar/excluir contas, marcar pago em 1 clique, métricas pago/a pagar/vencidas) e **Resumo**
  (Fluxo de caixa + **DRE simples**: receitas por origem − despesas por categoria = resultado). Configurações ganhou a aba
  **Nota fiscal** (formulário de dados fiscais + aviso **honesto** de que a emissão automática está em preparação — por ora,
  o Recibo em PDF segue como comprovante). **Emissão real da NFS-e adiada de propósito:** exige emissor externo
  (PlugNotas/Focus NFe/eNotas/NFE.io) + certificado A1 + config municipal + segredos em Edge Function — será entrega dedicada
  quando o emissor for definido. Validado: `node --check` + smoke no navegador (despesas 300 pagas / 1.200 a pagar / 1.500 total;
  resumo entradas 1.360 − saídas 1.450 = saldo −90; DRE agrupa Aluguel 1.300 + Materiais 150; 0 erro de página).
  **Liberado a todos os planos** (padrão do dono). *Falta:* deploy do front (merge na `main` → Vercel) — a migration já está em
  produção e é aditiva (não afeta o front atual em `main`).
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

- [ ] **Ativar "Leaked Password Protection"** no Supabase Auth (advisor confirmou OFF). ~1 clique no painel (Authentication → Policies).
- [ ] **Corrigir `cakto-webhook` (fail-open)** — em `nastadesk/supabase/functions/cakto-webhook/index.ts` (~linha 89) hoje `secretOk = !esperado || recebido === esperado`: se o secret não estiver configurado, aceita **qualquer** requisição (dá pra ativar/derrubar clínica com evento falso). Tornar **fail-closed** (secret obrigatório), validar **assinatura HMAC** do corpo, comparação constante-tempo, e **registrar a função no `config.toml`**.
- [ ] **Migration de performance RLS** — ~24 policies usam `auth.uid()` direto; trocar por `(select auth.uid())` (advisor `auth_rls_initplan`). Só reescreve as policies, sem mudar a lógica.
- [ ] **Remover policies permissivas duplicadas** — `pacientes`, `consultas`, `evolucoes` têm 2 policies de DELETE cada; `clinicas` tem 2 de SELECT (advisor `multiple_permissive_policies`). Consolidar em 1 por ação e escopar `TO authenticated`.
- [ ] **Criar índices nas FKs sem índice** (advisor `unindexed_foreign_keys`): `consultas.paciente_id`, `consultas.pacote_id`, `conversas.paciente_id`, `evolucoes.clinica_id`, `evolucoes.consulta_id`, `ia_uso.conversa_id`, `lembretes.clinica_id`.
- [ ] **Anti-abuso no agendamento público** — `agendar_online` (SECURITY DEFINER, aberto ao anon) não tem captcha nem rate-limit. Adicionar honeypot + hCaptcha em `agendar.html` e rate-limit por IP/WhatsApp.
- [ ] **(Opcional) Remover código morto do Mercado Pago** — só depois de confirmar 100% a migração p/ Cakto.

### 10.3 FASE 1 — Compliance / LGPD (semanas; destrava vendas)

> **Mais grave.** Dados de saúde = dado sensível (Art. 11 LGPD). A página pública
> `agendar.html` coleta nome + WhatsApp + "motivo da consulta" (queixa clínica)
> **sem aviso nem consentimento**.

- [ ] **Aviso de privacidade + termos de uso** — criar as páginas e linkar no cadastro do app e no formulário público de agendamento.
- [ ] **Consentimento com registro** — checkbox obrigatório no cadastro e no agendamento; gravar data/hora/versão do termo aceito (nova tabela `consentimentos`).
- [ ] **Portal do titular** — exportar e excluir todos os dados de um paciente (direito de acesso/eliminação).
- [ ] **Trilha de auditoria** — logar quem acessou/alterou ficha de paciente (tabela `auditoria` + gravação nos pontos de leitura/edição de prontuário).
- [ ] **2FA (TOTP)** para as clínicas — o Supabase Auth já suporta nativo; ativar + UI de setup.
- [ ] **DPA / contrato de operador** — modelo p/ os clientes (clínica = controladora; Nastaclin = operador).

### 10.4 FASE 2 — Paridade de mercado (o que toda concorrente tem)

- [x] **Multi-profissional (cadastro + agenda por profissional)** — FEITO em 2026-07-01 (aditivo, **sem login novo**; profissional é "recurso" da agenda). Tabela `profissionais` (nome, registro/CREFITO, cor, ordem, ativo) + `consultas.profissional_id` (nullable, FK on delete set null). Config → Profissionais (CRUD); etiqueta colorida + filtro por profissional na Agenda do dia; profissional na grade semanal (dot/cor + tooltip) e na lista mobile; select opcional no modal de agendamento; **reatribuição inline** na agenda (`mudarProfissionalConsulta`). RLS já no formato performático (`(select auth.uid())` + `TO authenticated`). **NÃO semeia dados** → clínica sem profissional não vê diferença. Migration `20260701120000_profissionais.sql` **aplicada em produção**; front só em `nastadesk/index.html` (o `dashboard` não muda). *Falta:* deploy do front (merge na `main`).
- [ ] **Login de profissionais + papéis de usuário** — cada profissional/recepção com login próprio e permissões (dono / recepção / profissional). Mexe em auth/RLS (mais delicado) — deixado para uma etapa 2, sob demanda.
- [ ] **Trava por plano do multi-profissional** — hoje liberado a todos os planos (pedido do dono); quando quiser, virar argumento de upgrade (o ponto de gate no front está preparado num único lugar).
- [x] **Nota fiscal de serviço (NFS-e)** — **FEITO em 2026-07-01** (emissor **PlugNotas**). Edge Function `nfse` (deploy + `config.toml`) + tabela `notas_fiscais` + tela de dados fiscais/status + botão "+ NF-e" nas consultas pagas. Integração **validada de verdade no sandbox** (emitida nº 9422, PDF/XML). **Para ligar em produção (não é código — é da clínica/dono):** `PLUGNOTAS_API_KEY` no servidor + CNPJ com NFS-e habilitada + **certificado A1** + conta no PlugNotas (cadastrar empresa/certificado no painel do PlugNotas). *Melhorias futuras:* upload do A1 pelo próprio app, webhook de status do PlugNotas, cancelamento pela tela.
- [x] **Financeiro completo** — contas a pagar/despesas, fluxo de caixa, DRE simples: **FEITO em 2026-07-01** (Financeiro → **Despesas** + **Resumo**; migration `20260701140000_despesas_fiscal.sql`, tabela `despesas`). Despesas com categoria/vencimento/status pago-pendente (marca pago em 1 clique); Resumo = fluxo de caixa (entradas − saídas) + DRE simples (receitas por origem − despesas por categoria). Não altera o financeiro por consulta/mensalidade/repasse. (✅ **Repasse/comissão por profissional** também já feito em 2026-07-01 — Financeiro → Repasse: % do valor ou R$/consulta, sobre as consultas atendidas do mês.) *Falta:* contas a pagar recorrentes automáticas (hoje cada mês é lançado à mão) — melhoria futura opcional.
- [ ] **Pagamento self-service do paciente (Pix/checkout) com baixa automática** — IDEIA discutida em 2026-07-01. Hoje o dono marca pago/pendente na mão (consulta, pacote ou mensalidade). Objetivo: o **paciente paga sozinho** (inclusive adiantado) e o status **atualiza automaticamente** no NastaDesk pro dono ver.
  - **Viável?** Sim. Caminho recomendado p/ Brasil: **Pix via um PSP com webhook** (ex.: Asaas, Efí/Gerencianet, Mercado Pago, Pagar.me) — sem taxa de cartão e confirmação na hora. Gera um Pix (copia-e-cola/QR) por cobrança; quando o paciente paga, o PSP chama uma **edge function** que dá **baixa automática** na cobrança (idempotente + HMAC), casando pelo id de referência.
  - **Por que é fase dedicada (não agora):** (1) cada clínica conecta a **própria conta** do PSP → a clínica recebe direto e a **Nastaclin não fica no meio do dinheiro** (evita virar "facilitador de pagamento"/peso regulatório); (2) reconciliação segura/idempotente; (3) **aditivo** — a baixa manual continua como fallback, sem tocar no financeiro atual; (4) LGPD/dados financeiros exigem cuidado.
  - **MVP sugerido:** começar por **mensalidades** (recorrente/previsível) OU por consulta, com **1 PSP via Pix**, link/QR por cobrança + webhook de baixa. **Boa ideia — recomendo fazer**, como entrega própria (concorrentes já oferecem link de pagamento ao paciente).
- [ ] **PWA instalável** — hoje 0 manifest / 0 service worker. Adicionar `manifest.json` + service worker (instalar no celular, ícone, offline básico).

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
