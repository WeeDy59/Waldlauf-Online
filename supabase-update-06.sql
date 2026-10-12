-- Waldlauf Update 06: Online-Daten löschen (Recht auf Löschung)
-- Einmal im Supabase SQL Editor einfügen und auf Run drücken (nach Update 05).

create or replace function public.delete_me(p_player text, p_code text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if char_length(p_player) not between 8 and 64 then raise exception 'ungueltig'; end if;
  delete from runs where player = p_player;
  delete from run_tokens where player = p_player;
  delete from inbox where from_pub = wl_pub(p_player);
  delete from profiles where player = p_player;   -- Freunde und Postfach werden mitgelöscht
  if coalesce(p_code, '') <> '' then
    delete from saves where code_hash = encode(sha256(convert_to('waldlauf-save:' || upper(p_code), 'UTF8')), 'hex');
  end if;
end $$;

grant execute on function public.delete_me(text, text) to anon;

-- Anti-Cheat-Protokoll nach 90 Tagen automatisch löschen (passiert nebenbei bei jedem Laufstart)
create or replace function public.start_run(p_player text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare t uuid; n int;
begin
  if char_length(p_player) not between 8 and 64 then raise exception 'ungueltig'; end if;
  select count(*) into n from run_tokens where player = p_player and created_at > now() - interval '1 minute';
  if n >= 12 then raise exception 'zu viele'; end if;
  delete from run_tokens where created_at < now() - interval '1 day';
  delete from cheat_log where created_at < now() - interval '90 days';
  insert into run_tokens (player) values (p_player) returning token into t;
  return t;
end $$;
grant execute on function public.start_run(text) to anon;
