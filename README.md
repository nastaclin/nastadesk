# NastaDesk

Painel web de gestão para clínicas de fisioterapia.
by [Nastaclin](https://nastaclin.vercel.app)

## Funcionalidades

- **Agenda do dia** — consultas em tempo real, status, métricas e mini-calendário
- **Agendamentos** — grade semanal (desktop) e lista (mobile), remarcação e exclusão
- **Agendamento online** — link público (`/agendar/<slug>`) para o paciente marcar sozinho, com QR Code
- **Lembretes WhatsApp** — mensagens personalizadas prontas (confirmação, véspera e dia) com envio em 1 clique
- **Pacientes** — ficha completa com anamnese, evoluções, histórico de consultas e convênio
- **Financeiro** — valor por consulta, registro de pagamento (Pix, cartão, dinheiro...), recibo em PDF e faturamento do mês
- **Relatório mensal** — comparecimento, faturamento, origem dos agendamentos e formas de pagamento
- **Conta** — onboarding guiado, recuperação de senha, configurações de horários e mensagens

## Stack

- HTML/CSS/JS puro (sem build)
- Supabase (banco de dados, autenticação e RPCs públicas para o agendamento online)
- Vercel (hospedagem; rotas em `vercel.json`)

## Estrutura

| Arquivo | Descrição |
|---|---|
| `index.html` | Painel da clínica (app completo) |
| `agendar.html` | Página pública de agendamento (`/agendar/<slug>`) |
| `supabase/migrations/` | Histórico das migrações aplicadas no banco |
| `vercel.json` | Rotas da Vercel |

## Banco de dados

Tabelas principais: `clinicas`, `pacientes`, `consultas`, `evolucoes`, `configuracoes`, `alertas`, `lembretes`.

O agendamento online usa três funções RPC com `SECURITY DEFINER` expostas ao role `anon`
(`clinica_publica`, `horarios_ocupados`, `agendar_online`) — toda a validação acontece no servidor.
