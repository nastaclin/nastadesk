-- 2026-10-24 — Teste grátis + assinatura cancelada: respeita o período pago
-- (aplicada em produção, versão 20261024132856).
--
-- POR QUÊ: quem assina DURANTE o teste grátis (cortesia=true) e depois cancela perdia
-- os dias pagos — encerrar_cortesias_vencidas() cortava assim que o teste vencia,
-- porque só poupava assinaturas 'ativa'/'em_atraso'. Agora também poupa assinatura
-- 'cancelada' com período pago ainda valendo (proximo_pagamento no futuro). Quando o
-- período acaba, o mesmo job corta normalmente. Reembolso grava proximo_pagamento =
-- agora, então quem foi reembolsado continua sendo cortado.
-- Testada antes em transação desfeita (7/7).
-- Rollback: recriar a função sem o segundo "not exists".
create or replace function public.encerrar_cortesias_vencidas()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_n integer;
begin
  update public.clinicas c
     set ativo = false,
         cortesia = false          -- deixa de ser "cortesia": vira suspensa/sem plano
     where c.ativo = true
       and c.cortesia = true
       and c.cortesia_expira_em is not null
       and c.cortesia_expira_em < now()
       -- quem PAGOU nunca é cortado por aqui
       and not exists (
         select 1 from public.assinaturas a
         where a.clinica_id = c.id and a.status in ('ativa','em_atraso')
       )
       -- 2026-10-24: quem assinou durante o teste e CANCELOU mantém o acesso até o
       -- fim do período já pago (o corte vem quando proximo_pagamento passar).
       and not exists (
         select 1 from public.assinaturas a
         where a.clinica_id = c.id and a.status = 'cancelada'
           and a.proximo_pagamento is not null and a.proximo_pagamento > now()
       );
  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

revoke execute on function public.encerrar_cortesias_vencidas() from public, anon, authenticated;
