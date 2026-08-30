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

## ⚠️ O remetente "Nastaclin" exige SMTP próprio

Trocar o texto **não** troca o remetente. Com o serviço de e-mail embutido do Supabase, a
mensagem sempre sai como **"Supabase Auth"**, de um endereço da Supabase — não há campo para
mudar isso. Para aparecer **Nastaclin**, é preciso configurar um **SMTP próprio** em
`Authentication → Emails → SMTP Settings`:

- **Sender name:** `Nastaclin`
- **Sender email:** um endereço de um domínio que você controle (ex.: `contato@nastaclin.com.br`)
- **Host / Port / User / Password:** os dados do provedor escolhido

Provedores com plano gratuito que servem bem para este volume: **Resend**, **Brevo**,
**SendGrid**, **AWS SES**. Em todos é preciso **verificar o domínio** (uns registros DNS de
SPF/DKIM) — é isso que faz o e-mail chegar na caixa de entrada em vez do spam.

### Não é só estética — é um risco de venda

O serviço embutido do Supabase é **limitado a poucos e-mails por hora** e a documentação diz
explicitamente que ele **não é para produção** ("availability is on a best-effort basis").
Se várias clínicas se cadastrarem na mesma hora, **os e-mails de confirmação simplesmente não
saem** e a pessoa fica sem conseguir ativar a conta. O SMTP próprio remove esse teto.
