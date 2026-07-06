-- Agendamento recorrente (horario fixo): agrupa as consultas de uma mesma serie.
-- 100% aditivo e reversivel: coluna nullable sem valor default (null = consulta avulsa).
-- Nao altera RLS (as policies de consultas sao escopadas por clinica_id, agnosticas a coluna).
alter table public.consultas add column if not exists serie_id uuid;

create index if not exists idx_consultas_serie
  on public.consultas(serie_id) where serie_id is not null;

comment on column public.consultas.serie_id is
  'Agrupa consultas criadas juntas como serie recorrente (horario fixo semanal). Null = consulta avulsa.';
