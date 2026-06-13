# Instalação fácil do servidor WhatsApp (sem terminal)

Este guia sobe o servidor Evolution **quase sem digitar comandos** — usando o
recurso de "script inicial" que o provedor de servidor roda sozinho ao criar a
máquina.

Tempo: ~20 minutos. Custo: ~R$30–40/mês (servidor). Há crédito grátis pra testar.

---

## Antes de começar: invente 2 senhas
Anote num lugar seguro (vai usar daqui a pouco):
- **CHAVE** (a "senha" do servidor WhatsApp) — algo grande, ex.: `nasta_9Kx2Lm8Qw4Vt7Yb3Rn6Zp`
- **SENHA_BANCO** — outra senha forte qualquer, ex.: `Banco_7Hn4Xs2Wq9`

---

## Passo 1 — Criar o servidor (VPS)
Recomendado: **DigitalOcean** (fácil e dá US$200 de crédito grátis por 60 dias).
Alternativa com servidor no Brasil (menos atraso): **Vultr**, região São Paulo.

1. Crie conta em **digitalocean.com** (precisa de cartão; o crédito cobre o teste)
2. Clique em **Create → Droplet**
3. Região: escolha a mais próxima (ex.: New York). Imagem: **Ubuntu** (deixe a padrão)
4. Plano: **Basic → Regular**, o de **US$6/mês** (1 GB) já funciona; 2 GB é mais folgado
5. Em **Authentication**, escolha **Password** e defina uma senha de root (anote)
6. Procure a seção **"Advanced options"** → marque **"Add Initial Scripts (user data)"**
7. **Cole o script abaixo** nessa caixa — mas antes **troque as 2 linhas** com a
   CHAVE e a SENHA_BANCO que você inventou:

```bash
#!/bin/bash
set -e
curl -fsSL https://get.docker.com | sh
mkdir -p /opt/evolution && cd /opt/evolution

cat > .env <<'ENV'
EVOLUTION_API_KEY=COLOQUE_AQUI_SUA_CHAVE
DB_PASSWORD=COLOQUE_AQUI_SUA_SENHA_BANCO
ENV

cat > docker-compose.yml <<'YAML'
services:
  evolution-api:
    image: atendai/evolution-api:v2.1.1
    restart: always
    ports: ["8080:8080"]
    env_file: .env
    environment:
      - SERVER_URL=http://localhost:8080
      - AUTHENTICATION_API_KEY=${EVOLUTION_API_KEY}
      - DATABASE_ENABLED=true
      - DATABASE_PROVIDER=postgresql
      - DATABASE_CONNECTION_URI=postgresql://evolution:${DB_PASSWORD}@postgres:5432/evolution
      - DATABASE_CONNECTION_CLIENT_NAME=evolution
      - DATABASE_SAVE_DATA_INSTANCE=true
      - DATABASE_SAVE_DATA_NEW_MESSAGE=true
      - DATABASE_SAVE_MESSAGE_UPDATE=true
      - DATABASE_SAVE_DATA_CONTACTS=true
      - DATABASE_SAVE_DATA_CHATS=true
      - CACHE_REDIS_ENABLED=true
      - CACHE_REDIS_URI=redis://redis:6379/6
      - CACHE_REDIS_PREFIX_KEY=evolution
      - CACHE_REDIS_SAVE_INSTANCES=true
      - CACHE_LOCAL_ENABLED=false
    depends_on: [postgres, redis]
    volumes: ["evolution_instances:/evolution/instances"]
  postgres:
    image: postgres:15-alpine
    restart: always
    env_file: .env
    environment:
      - POSTGRES_USER=evolution
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_DB=evolution
    volumes: ["postgres_data:/var/lib/postgresql/data"]
  redis:
    image: redis:7-alpine
    restart: always
    volumes: ["redis_data:/data"]
volumes:
  evolution_instances:
  postgres_data:
  redis_data:
YAML

docker compose up -d
```

8. Finalize em **Create Droplet** e aguarde ~1 min até o servidor aparecer
9. **Copie o IP** do servidor (algo como `164.92.10.55`)

---

## Passo 2 — Conferir se subiu (~3 a 5 min depois)
No navegador, abra:  **http://SEU_IP:8080**
(ex.: `http://164.92.10.55:8080`)

Se aparecer um texto/JSON tipo *"Welcome to the Evolution API"*, **funcionou!** 🎉
(Se der erro, espere mais 2 min — ele ainda está instalando — e recarregue.)

---

## Passo 3 — Ligar no NastaDesk (Supabase)
No Supabase → Edge Functions → Secrets, preencha:
- `EVOLUTION_API_URL` = `http://SEU_IP:8080`
- `EVOLUTION_API_KEY` = a **CHAVE** que você inventou

Pronto. Agora é só publicar as funções (passo 3 do guia principal) e conectar o
WhatsApp pelo painel.

---

## Importante (para quando for vender pra valer)
Esta instalação simples usa `http` (sem cadeado). Funciona perfeitamente para
testar e começar. Quando for escalar/vender, troque para **HTTPS com domínio** —
já existe o arquivo `docker-compose.yml` (com Caddy) pronto pra isso nesta pasta.
É só apontar um subdomínio (ex.: `whats.suaclinica.com.br`) para o IP do servidor.
