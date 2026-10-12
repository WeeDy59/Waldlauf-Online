-- Waldlauf Update 01: Länderflaggen in der Rangliste
-- Nur nötig, wenn du supabase-setup.sql schon VOR diesem Update ausgeführt hast.
-- Einmal im Supabase SQL Editor einfügen und auf Run drücken.

alter table public.runs add column if not exists flag text not null default '' check (char_length(flag) <= 2);
drop function if exists public.submit_run(text, text, text, int, int, int);
drop function if exists public.leaderboard(int, int, text);

-- Lauf eintragen (mit einfachen Plausibilitätsprüfungen)
create or replace function public.submit_run(
  p_player text, p_name text, p_avatar text, p_season int, p_meters int, p_coins int, p_flag text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare
  last_run timestamptz;
  cur_season int := floor(extract(epoch from (now() - timestamptz '2026-10-11 00:00:00+00')) / (90 * 86400))::int + 1;
begin
  if p_season <> cur_season and p_season <> cur_season - 1 then
    raise exception 'falsche Season';
  end if;
  if p_coins > p_meters then
    raise exception 'unplausibel';
  end if;
  select max(created_at) into last_run from runs where player = p_player;
  if last_run is not null and now() - last_run < interval '10 seconds' then
    raise exception 'zu schnell';
  end if;
  insert into runs (season, player, name, avatar, flag, meters, coins)
  values (p_season, p_player, left(coalesce(nullif(trim(p_name), ''), 'Spieler'), 16),
          left(coalesce(p_avatar, '🦊'), 16), upper(left(coalesce(p_flag, ''), 2)), p_meters, p_coins);
end $$;

-- Top-Liste einer Season (beste Strecke pro Spieler)
create or replace function public.leaderboard(p_season int, p_limit int default 50, p_player text default '')
returns table (name text, avatar text, flag text, best int, place bigint, is_me boolean)
language sql security definer set search_path = public stable as $$
  with b as (
    select distinct on (player) player, name, avatar, flag, meters as best
    from runs where season = p_season
    order by player, meters desc, created_at desc
  )
  select name, avatar, flag, best, rank() over (order by best desc) as place, (player = p_player) as is_me
  from b order by best desc limit least(greatest(p_limit, 1), 100);
$$;

-- Eigener Platz in einer Season
create or replace function public.my_place(p_season int, p_player text)
returns table (place bigint, total bigint, best int)
language sql security definer set search_path = public stable as $$
  with b as (select player, max(meters) as best from runs where season = p_season group by player),
       me as (select best from b where player = p_player)
  select (select count(*) + 1 from b where b.best > me.best), (select count(*) from b), me.best
  from me;
$$;

grant execute on function public.submit_run(text, text, text, int, int, int, text) to anon;
grant execute on function public.leaderboard(int, int, text) to anon;
grant execute on function public.my_place(int, text) to anon;
