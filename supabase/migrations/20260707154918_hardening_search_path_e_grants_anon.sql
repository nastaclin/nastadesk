-- SEGURANCA (2026-07-07): endurecimento (defense-in-depth).
-- (1) cpf_valido sem search_path fixo (advisor 0011). Fixa para evitar sequestro de search_path.
alter function public.cpf_valido(text) set search_path = public, pg_temp;

-- (2) O papel anon tinha INSERT/UPDATE/DELETE/TRUNCATE em TODAS as tabelas do schema public.
-- Ja era bloqueado pela RLS (nenhuma policy concede escrita ao anon) e nao ha endpoint de
-- TRUNCATE via API, mas o grant era amplo demais. Os fluxos publicos (agendamento, confirmacao)
-- usam RPCs SECURITY DEFINER / edge functions com service_role -> nunca DML direto como anon.
-- Revoga a escrita do anon em todas as tabelas atuais. NAO mexe em 'authenticated' (o app logado
-- precisa de INSERT/UPDATE/DELETE, gated pela RLS) nem em 'service_role'.
do $$
declare r record;
begin
  for r in select tablename from pg_tables where schemaname='public' loop
    execute format('revoke insert, update, delete, truncate on public.%I from anon', r.tablename);
  end loop;
end $$;

-- Impede que tabelas NOVAS voltem a conceder escrita ao anon por padrao.
alter default privileges in schema public revoke insert, update, delete, truncate on tables from anon;
