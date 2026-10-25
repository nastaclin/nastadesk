-- =============================================================================
-- NastaDesk — Trava de IA: o teste grátis segue os limites do Profissional
--
-- Antes: o teste grátis nasce no plano Premium (cortesia com data), e o Premium
-- nunca bloqueia. Com anúncio no ar, várias clínicas em teste usariam a IA sem
-- teto mensal (só o limite diário por telefone valia).
-- Agora: enquanto a clínica está no teste grátis (cortesia COM data de
-- expiração e sem assinatura ativa/em atraso), a trava usa os limites de
-- admin_config.ia_limites.plano_teste_gratis (padrão: 'profissional').
-- O plano gravado na clínica NÃO muda: ela continua vendo tudo do Premium.
--
-- Não muda: cortesia sem data (dada pelo admin), clínica que já assinou
-- (mesmo ainda dentro do teste), Básico (continua sem robô).
-- Desligar: admin_config.ia_limites.plano_teste_gratis = '' (string vazia).
--
-- ROLLBACK: rodar de novo as definições de ia_checar_e_contar e
-- ia__avaliar_marcos de 20261019120000_trava_ia_cota.sql e
--   drop function if exists public.ia__plano_efetivo(uuid);
-- =============================================================================

-- 1) Plano que a trava usa ------------------------------------------------------
create or replace function public.ia__plano_efetivo(p_clinica_id uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when c.cortesia
     and c.cortesia_expira_em is not null
     and coalesce(cfg.plano_teste, 'profissional') <> ''
     and not exists (
       select 1 from public.assinaturas a
        where a.clinica_id = c.id and a.status in ('ativa', 'em_atraso'))
    then coalesce(cfg.plano_teste, 'profissional')
    else c.plano
  end
  from public.clinicas c
  left join lateral (
    select value->>'plano_teste_gratis' as plano_teste
      from public.admin_config where key = 'ia_limites'
  ) cfg on true
  where c.id = p_clinica_id;
$$;

-- 2) Checagem antes de cada chamada à IA (só troca a origem do plano) --------
CREATE OR REPLACE FUNCTION public.ia_checar_e_contar(p_clinica_id uuid, p_conversa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_cfg jsonb;
  v_plano text;
  v_pcfg jsonb;
  v_dia date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_mes date := date_trunc('month', (now() AT TIME ZONE 'America/Sao_Paulo'))::date;
  v_lim_dia int;
  v_m public.ia_cota_mensal;
  v_chamadas int;
  v_cota numeric;
  v_teto numeric;
  v_custo_brl numeric;
BEGIN
  SELECT value INTO v_cfg FROM public.admin_config WHERE key = 'ia_limites';
  v_plano := public.ia__plano_efetivo(p_clinica_id);
  v_pcfg := v_cfg->'planos'->coalesce(v_plano, '');
  v_lim_dia := nullif(v_cfg->>'limite_diario_telefone', '')::int;

  INSERT INTO public.ia_cota_mensal (clinica_id, mes) VALUES (p_clinica_id, v_mes) ON CONFLICT DO NOTHING;
  SELECT * INTO v_m FROM public.ia_cota_mensal WHERE clinica_id = p_clinica_id AND mes = v_mes FOR UPDATE;

  SELECT chamadas INTO v_chamadas FROM public.ia_conversas
  WHERE conversa_id = p_conversa_id AND dia = v_dia FOR UPDATE;

  IF FOUND THEN
    IF v_lim_dia > 0 AND v_chamadas >= v_lim_dia THEN
      UPDATE public.ia_cota_mensal SET limite_diario = limite_diario + 1, atualizado_em = now()
      WHERE clinica_id = p_clinica_id AND mes = v_mes;
      RETURN jsonb_build_object('status', 'limite_diario', 'chamadas_hoje', v_chamadas, 'limite', v_lim_dia);
    END IF;
    UPDATE public.ia_conversas SET chamadas = chamadas + 1, atualizado_em = now()
    WHERE conversa_id = p_conversa_id AND dia = v_dia;
    UPDATE public.ia_cota_mensal SET chamadas = chamadas + 1, atualizado_em = now()
    WHERE clinica_id = p_clinica_id AND mes = v_mes;
    RETURN jsonb_build_object('status', 'ok', 'nova_conversa', false, 'chamadas_hoje', v_chamadas + 1);
  END IF;

  IF coalesce((v_pcfg->>'bloqueia')::boolean, false) THEN
    v_cota := nullif(v_pcfg->>'conversas_mes', '')::numeric;
    v_teto := nullif(v_pcfg->>'teto_custo_brl', '')::numeric;
    v_custo_brl := v_m.custo_usd * (public.ia__precos()->>'cambio')::numeric;
    IF (v_cota > 0 AND v_m.conversas >= v_cota) OR (v_teto > 0 AND v_custo_brl >= v_teto) THEN
      UPDATE public.ia_cota_mensal SET bloqueadas = bloqueadas + 1, atualizado_em = now()
      WHERE clinica_id = p_clinica_id AND mes = v_mes;
      PERFORM public.ia__avaliar_marcos(p_clinica_id, v_mes);
      RETURN jsonb_build_object('status', 'cota_esgotada',
        'motivo', CASE WHEN v_cota > 0 AND v_m.conversas >= v_cota THEN 'conversas' ELSE 'custo' END);
    END IF;
  END IF;

  INSERT INTO public.ia_conversas (clinica_id, conversa_id, dia, chamadas) VALUES (p_clinica_id, p_conversa_id, v_dia, 1);
  UPDATE public.ia_cota_mensal SET conversas = conversas + 1, chamadas = chamadas + 1, atualizado_em = now()
  WHERE clinica_id = p_clinica_id AND mes = v_mes;
  PERFORM public.ia__avaliar_marcos(p_clinica_id, v_mes);
  RETURN jsonb_build_object('status', 'ok', 'nova_conversa', true, 'chamadas_hoje', 1);
END;
$function$;

-- 3) Avisos de 80% e 100% (plano efetivo + texto próprio do teste grátis) -----
CREATE OR REPLACE FUNCTION public.ia__avaliar_marcos(p_clinica_id uuid, p_mes date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_cfg jsonb;
  v_plano text;
  v_plano_real text;
  v_teste boolean;
  v_pcfg jsonb;
  v_m public.ia_cota_mensal;
  v_cambio numeric;
  v_cota numeric;
  v_teto numeric;
  v_custo_brl numeric;
  v_pct numeric := 0;
  v_marco int;
  v_ok boolean;
  v_det jsonb;
BEGIN
  SELECT value INTO v_cfg FROM public.admin_config WHERE key = 'ia_limites';
  SELECT plano INTO v_plano_real FROM public.clinicas WHERE id = p_clinica_id;
  v_plano := public.ia__plano_efetivo(p_clinica_id);
  v_teste := v_plano IS DISTINCT FROM v_plano_real;
  v_pcfg := v_cfg->'planos'->coalesce(v_plano, '');
  IF v_pcfg IS NULL THEN RETURN; END IF;

  SELECT * INTO v_m FROM public.ia_cota_mensal WHERE clinica_id = p_clinica_id AND mes = p_mes;
  IF NOT FOUND THEN RETURN; END IF;

  v_cambio := (public.ia__precos()->>'cambio')::numeric;
  v_custo_brl := v_m.custo_usd * v_cambio;
  v_cota := nullif(v_pcfg->>'conversas_mes', '')::numeric;
  v_teto := nullif(v_pcfg->>'teto_custo_brl', '')::numeric;
  IF v_cota > 0 THEN v_pct := greatest(v_pct, v_m.conversas * 100.0 / v_cota); END IF;
  IF v_teto > 0 THEN v_pct := greatest(v_pct, v_custo_brl * 100.0 / v_teto); END IF;
  v_det := jsonb_build_object('conversas', v_m.conversas, 'custo_brl', round(v_custo_brl, 2),
                              'cota', v_cota, 'teto_custo_brl', v_teto, 'pct', round(v_pct, 1),
                              'teste_gratis', v_teste);

  IF coalesce((v_pcfg->>'bloqueia')::boolean, false) THEN
    FOR v_marco IN SELECT (x)::int FROM jsonb_array_elements_text(coalesce(v_cfg->'alertas_pct', '[80,100]'::jsonb)) x ORDER BY 1 LOOP
      CONTINUE WHEN v_marco NOT IN (80, 100) OR v_pct < v_marco;
      INSERT INTO public.ia_cota_eventos (clinica_id, mes, marco, detalhe)
      VALUES (p_clinica_id, p_mes, v_marco::text, v_det)
      ON CONFLICT DO NOTHING
      RETURNING true INTO v_ok;
      IF v_ok THEN
        INSERT INTO public.alertas (clinica_id, tipo, mensagem) VALUES (p_clinica_id, 'whatsapp',
          CASE
            WHEN v_teste AND v_marco >= 100
              THEN '🤖 A cota de IA do robô no teste grátis acabou. Até o fim do teste ele responde pelo menu (agendar, confirmar e falar com atendente continuam funcionando). Assinando, a cota do seu plano começa a valer.'
            WHEN v_teste
              THEN '🤖 O robô do WhatsApp já usou 80% da cota de IA do teste grátis. Ao chegar em 100%, ele passa a responder só pelo menu até o fim do teste.'
            WHEN v_marco >= 100
              THEN '🤖 A cota de IA do robô deste mês acabou. Até o dia 1º ele responde pelo menu (agendar, confirmar e falar com atendente continuam funcionando). Quer IA ilimitada? Fale com a gente sobre o plano Premium.'
            ELSE '🤖 O robô do WhatsApp já usou 80% da cota de IA deste mês. Ao chegar em 100%, ele passa a responder só pelo menu até o dia 1º.'
          END);
      END IF;
      v_ok := NULL;
    END LOOP;
  ELSE
    IF v_pct >= 100 THEN
      INSERT INTO public.ia_cota_eventos (clinica_id, mes, marco, detalhe)
      VALUES (p_clinica_id, p_mes, 'premium_teto', v_det)
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;
END;
$function$;

-- 4) Configuração explícita (a função já assume 'profissional' se faltar) -----
update public.admin_config
   set value = value || jsonb_build_object('plano_teste_gratis', 'profissional')
 where key = 'ia_limites'
   and not (value ? 'plano_teste_gratis');

-- 5) Permissões: só o backend chama (igual às outras da trava) ---------------
revoke all on function public.ia__plano_efetivo(uuid)            from public, anon, authenticated;
revoke all on function public.ia_checar_e_contar(uuid, uuid)     from public, anon, authenticated;
revoke all on function public.ia__avaliar_marcos(uuid, date)     from public, anon, authenticated;
grant execute on function public.ia__plano_efetivo(uuid) to service_role;
