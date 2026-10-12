-- Waldlauf Update 04: Cloud-Speicherstand (Fortschritt auf ein anderes Gerät mitnehmen)
-- Einmal im Supabase SQL Editor einfügen und auf Run drücken.

create table if not exists public.saves (
  code_hash  text primary key,
  data       jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.saves enable row level security;
revoke all on public.saves from anon, authenticated;

-- Speichern: der Code selbst wird nie gespeichert, nur sein Hash
create or replace function public.save_backup(p_code text, p_data jsonb)
returns timestamptz
language plpgsql security definer set search_path = public as $$
declare h text; t timestamptz := now();
begin
  if p_code is null or char_length(p_code) < 16 or char_length(p_code) > 64 then raise exception 'ungueltiger code'; end if;
  if pg_column_size(p_data) > 300000 then raise exception 'zu gross'; end if;
  h := encode(sha256(convert_to('waldlauf-save:' || upper(p_code), 'UTF8')), 'hex');
  if exists (select 1 from saves where code_hash = h and updated_at > now() - interval '5 seconds') then
    raise exception 'zu schnell';
  end if;
  insert into saves (code_hash, data, updated_at) values (h, p_data, t)
  on conflict (code_hash) do update set data = excluded.data, updated_at = t;
  return t;
end $$;

-- Laden
create or replace function public.load_backup(p_code text)
returns table (data jsonb, updated_at timestamptz)
language sql security definer set search_path = public stable as $$
  select s.data, s.updated_at from saves s
  where s.code_hash = encode(sha256(convert_to('waldlauf-save:' || upper(coalesce(p_code, '')), 'UTF8')), 'hex');
$$;

grant execute on function public.save_backup(text, jsonb) to anon;
grant execute on function public.load_backup(text) to anon;
