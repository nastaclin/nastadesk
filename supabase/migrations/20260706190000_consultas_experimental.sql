-- Aula/consulta experimental: flag aditiva na consulta.
-- null/false = consulta normal; true = marcada como experimental no agendamento.
-- Nao altera RLS (policies de consultas sao escopadas por clinica_id, agnosticas a coluna).
alter table public.consultas add column if not exists experimental boolean not null default false;
