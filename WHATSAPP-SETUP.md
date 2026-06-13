# NastaDesk — Guia de ativação do WhatsApp

São 4 passos. Os passos 1, 2 e 3 são em painéis (sem terminal). O passo 4 é o
único que precisa de um servidor — e os arquivos prontos estão na pasta
`evolution/`.

---

## 1) Chave da Anthropic (a inteligência do bot)
1. Acesse **console.anthropic.com** → crie conta / login
2. **API Keys** → **Create Key** → copie a chave (`sk-ant-...`)
3. Em **Billing**, adicione créditos (com o modelo Haiku, cada conversa custa centavos)

## 2) Secrets no Supabase
Dashboard → **Edge Functions → Secrets** → **Add new secret** (3 vezes):

| Nome | Valor |
|------|-------|
| `ANTHROPIC_API_KEY` | a chave do passo 1 |
| `EVOLUTION_API_URL` | `https://SEU_DOMINIO` (vem do passo 4) |
| `EVOLUTION_API_KEY` | a chave que você definir no passo 4 |

## 3) Publicar as 4 Edge Functions
**Pelo terminal (1 comando):**
```bash
supabase login
supabase link --project-ref zrkadblxozddreiwruhv
supabase functions deploy
```
O `supabase/config.toml` já define o "Verify JWT" certo de cada função.

**Ou pelo navegador:** Dashboard → Edge Functions → Create function → cole o
código de cada pasta em `supabase/functions/`. Em `whatsapp-webhook` e
`lembretes-auto`, **desligue** "Verify JWT".

## 4) Servidor Evolution API
Um único servidor atende todas as clínicas. O software é gratuito; você paga só
a hospedagem. Arquivos prontos em `evolution/`.

### Opção A — Você (ou alguém) num VPS com Docker
1. Alugue um VPS (Hetzner, Contabo, DigitalOcean...) — qualquer um com 2 GB RAM serve
2. Aponte um domínio (ex.: `whats.suaclinica.com.br`) para o IP do VPS (registro DNS tipo A)
3. Copie a pasta `evolution/` para o servidor
4. Renomeie `.env.example` → `.env` e preencha os 3 valores
5. Rode: `docker compose up -d`
6. Sua URL fica `https://SEU_DOMINIO` e a chave é a `EVOLUTION_API_KEY` do `.env`
7. Volte ao passo 2 e cole esses dois valores no Supabase

### Opção B — Contratar um freelancer (1h de serviço)
Em Workana / 99freelas / Fiverr, procure "instalar Evolution API em VPS".
Entregue a pasta `evolution/` pronta — o serviço fica rápido e é uma vez só.

### Opção C — Provedor gerenciado de Evolution
Serviços que hospedam o Evolution por você e entregam URL + chave prontas.
Mais caro, porém zero configuração.

---

## Depois de tudo pronto
No painel: **Configurações → WhatsApp & Chatbot → Conectar WhatsApp** → escaneie
o QR Code com o WhatsApp da clínica. O bot começa a responder na hora. 🎉
