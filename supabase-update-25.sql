-- Waldlauf Update 25: Waldhüpfer hat jetzt 12 Welten (Speedrun-Rangliste für Welt 7 bis 12)

alter table public.plat_runs drop constraint if exists plat_runs_world_check;
alter table public.plat_runs add constraint plat_runs_world_check check (world between 0 and 11);

-- Schutz wie bisher: schneller als mit Höchsttempo bis zur Fahne geht nicht, höchstens 60 Läufe pro Stunde
create or replace function public.plat_submit(p_player text, p_world int, p_ms int, p_animal int default 0) returns jsonb
language plpgsql security definer set search_path = public as $$
declare best int; rk int;
begin
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  if not exists (select 1 from profiles where player = p_player) then raise exception 'kein profil'; end if;
  if p_world not between 0 and 11 then raise exception 'welt'; end if;
  if p_ms < (23000 + p_world * 3600) or p_ms > 400000 then raise exception 'ungueltig'; end if;
  if (select count(*) from plat_log where player = p_player and created_at > now() - interval '1 hour') >= 60 then raise exception 'zu viele'; end if;
  insert into plat_log (player) values (p_player);
  delete from plat_log where created_at < now() - interval '1 day';
  insert into plat_runs (player, world, ms, animal) values (p_player, p_world, p_ms, coalesce(p_animal, 0))
  on conflict (player, world) do update set ms = excluded.ms, animal = excluded.animal, created_at = now()
  where plat_runs.ms > excluded.ms;
  select ms into best from plat_runs where player = p_player and world = p_world;
  select 1 + count(*) into rk from plat_runs where world = p_world and ms < best and player not in (select player from banned);
  return jsonb_build_object('best', best, 'rank', rk);
end $$;

grant execute on function public.plat_submit(text, int, int, int) to anon;

select 'fertig' as status;
