# E-mails do NastaDesk (Supabase Auth)

Os e-mails automáticos de conta (confirmação de cadastro e recuperação de senha) chegavam
**em inglês e assinados como "Supabase Auth"**. Estes templates resolvem o texto e a marca.

| Arquivo | Onde colar no Supabase | Assunto sugerido |
|---|---|---|
| `confirmacao-cadastro.html` | Authentication → Emails → Templates → **Confirm signup** | `Confirme seu e-mail — NastaDesk` |
| `recuperacao-senha.html` | Authentication → Emails → Templates → **Reset password** | `Redefinir sua senha — NastaDesk` |

Cole o arquivo **inteiro** no campo *Message body* e salve. As variáveis `{{ .ConfirmationURL }}`
e `{{ .Email }}` são preenchidas pelo Supabase — **não troque nem apague**.

A logo vem de `https://nastadesk.vercel.app/logo.png` (público, servido pela Vercel). Se um dia
o domínio mudar, atualize o `src` nos dois arquivos.

---

## Remetente "Nastaclin": SMTP próprio com Resend (decidido em 2026-08-30)

Trocar o texto **não** troca o remetente. Com o serviço de e-mail embutido do Supabase a
mensagem sempre sai como **"Supabase Auth"**, de um endereço da Supabase — não existe campo
para mudar isso. E não é só estética: o embutido é **limitado a poucos e-mails por hora** e a
documentação diz que **não é para produção** — com várias clínicas se cadastrando na mesma
hora, o e-mail de confirmação simplesmente não sai.

**Decisões do dono nesta data:** domínio **`nastadesk.com` / `nastadesk.com.br`** (o
`nastaclin.com` fica reservado para o site institucional da Nastaclin) e provedor **Resend**
(plano gratuito: 3.000 e-mails/mês, 100/dia — folgado para cadastro e recuperação de senha).

### Passo 1 — registrar o domínio

Conferido em 2026-08-30 no RDAP: `nastadesk.com`, `nastadesk.com.br`, `nastaclin.com` e
`nastaclin.com.br` estavam **todos livres**.

- **`.com.br`** → `registro.br`, ~R$ 40/ano, **registra no CPF** (não precisa de CNPJ).
- **`.com`** → qualquer registrador (Cloudflare, Namecheap, Registro.com), ~US$ 10–15/ano.

> Para o e-mail funcionar tanto faz `.com` ou `.com.br` — o que importa é **você controlar o
> DNS**. É por isso que não dá para usar o Gmail como remetente: sem acesso ao DNS do domínio
> não há como provar que o envio é seu, e desde 2024 Gmail/Yahoo rejeitam quem tenta.

### Passo 2 — criar a conta e adicionar o domínio no Resend

1. `resend.com` → criar conta gratuita.
2. **Domains → Add Domain** → digite `nastadesk.com.br` (o domínio raiz; é o que deixa o
   endereço bonito: `contato@nastadesk.com.br`).
3. O Resend mostra **3 a 4 registros DNS** para você criar no painel do domínio:
   - **MX** — caminho de retorno (bounces).
   - **TXT (SPF)** — autoriza o Resend a enviar em nome do domínio.
   - **TXT (DKIM)** — assinatura criptográfica; é o que prova que o e-mail é legítimo.
   - **TXT (DMARC)**, opcional mas recomendado — comece com `v=DMARC1; p=none;`.
   ⚠️ **Copie os valores exatamente como o Resend mostrar** — o DKIM é gerado por domínio,
   não existe valor "padrão".
4. No `registro.br`: **Painel → seu domínio → DNS → Editar zona**, cole os registros e salve.
   A propagação leva de minutos a algumas horas; o Resend marca o domínio como **Verified**.

### Passo 3 — gerar a chave e ligar no Supabase

1. Resend → **API Keys → Create API Key** (permissão *Sending access*). Copie a chave `re_...`
   — **ela só aparece uma vez**.
2. Supabase → **Authentication → Emails → SMTP Settings** → *Enable Custom SMTP*:

   | Campo | Valor |
   |---|---|
   | Sender name | `Nastaclin` |
   | Sender email | `contato@nastadesk.com.br` (ou `nao-responda@…`) |
   | Host | `smtp.resend.com` |
   | Port | `465` |
   | Username | `resend` |
   | Password | a chave `re_...` |

   *(Host/porta/usuário conferidos na documentação do Resend em 2026-08-30. As portas aceitas
   são 25, 465, 587, 2465 e 2587 — se a 465 der problema, tente a 587.)*

3. **Não esqueça deste passo:** Supabase → **Authentication → Rate Limits** → aumente
   **"Emails sent per hour"**. O teto baixo do serviço embutido **continua valendo** até você
   mexer aqui — configurar o SMTP sozinho não levanta o limite.

### Passo 4 — testar

Crie uma conta de teste no app com um e-mail seu e confira: remetente **Nastaclin**, texto em
português, logo aparecendo, e o botão levando ao `confirmado.html`. Depois apague o usuário de
teste em **Authentication → Users**.

> Se o e-mail cair no spam, quase sempre falta o **DMARC** ou o domínio ainda não está
> *Verified* no Resend.

### Depois (opcional, não é necessário para o e-mail)

Com o domínio na mão, dá para apontar `app.nastadesk.com.br` para a Vercel no lugar de
`nastadesk.vercel.app`. Se fizer isso, atualize **Authentication → URL Configuration**
(*Site URL* e *Redirect URLs*) no Supabase, senão o link de confirmação volta para o
endereço antigo.
