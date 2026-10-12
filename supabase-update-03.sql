-- Waldlauf Update 03: Rahmen, Avatarrahmen und Level in den Ranglisten
-- Einmal im Supabase SQL Editor einfügen und auf Run drücken (nach Update 02).

alter table public.profiles add column if not exists pfr int not null default 0 check (pfr between 0 and 50);
alter table public.profiles add column if not exists afr int not null default 0 check (afr between 0 and 50);
alter table public.profiles add column if not exists lvl int not null default 1 check (lvl between 1 and 1000);

drop function if exists public.upsert_profile(text, text, text, text);
create or replace function public.upsert_profile(p_player text, p_name text, p_avatar text, p_flag text,
  p_pfr int default 0, p_afr int default 0, p_lvl int default 1)
returns text
language plpgsql security definer set search_path = public as $$
declare v text := wl_pub(p_player);
begin
  if char_length(p_player) not between 8 and 64 then raise exception 'ungueltig'; end if;
  insert into profiles (player, pub, name, avatar, flag, pfr, afr, lvl)
  values (p_player, v, left(coalesce(nullif(trim(p_name), ''), 'Spieler'), 16),
          left(coalesce(p_avatar, '🦊'), 16), upper(left(coalesce(p_flag, ''), 2)),
          least(greatest(coalesce(p_pfr, 0), 0), 50), least(greatest(coalesce(p_afr, 0), 0), 50), least(greatest(coalesce(p_lvl, 1), 1), 1000))
  on conflict (player) do update
    set name = excluded.name, avatar = excluded.avatar, flag = excluded.flag,
        pfr = excluded.pfr, afr = excluded.afr, lvl = excluded.lvl, updated_at = now();
  return v;
end $$;

drop function if exists public.leaderboard(int, int, text);
create or replace function public.leaderboard(p_season int, p_limit int default 50, p_player text default '')
returns table (name text, avatar text, flag text, best int, place bigint, is_me boolean, pub text, pfr int, afr int, lvl int)
language sql security definer set search_path = public stable as $$
  with b as (
    select distinct on (player) player, name, avatar, flag, meters as best
    from runs where season = p_season
    order by player, meters desc, created_at desc
  )
  select b.name, b.avatar, b.flag, b.best, rank() over (order by b.best desc) as place, (b.player = p_player) as is_me,
         wl_pub(b.player) as pub, coalesce(p.pfr, 0), coalesce(p.afr, 0), coalesce(p.lvl, 1)
  from b left join profiles p on p.player = b.player
  order by b.best desc limit least(greatest(p_limit, 1), 100);
$$;

drop function if exists public.friends_list(text, int);
create or replace function public.friends_list(p_player text, p_season int)
returns table (pub text, name text, avatar text, flag text, best int, rel text, pfr int, afr int, lvl int)
language sql security definer set search_path = public stable as $$
  select p.pub, p.name, p.avatar, p.flag,
         coalesce((select max(r.meters) from runs r where r.player = p.player and r.season = p_season), 0) as best,
         case when f.status = 'accepted' then 'friend' when f.a = p_player then 'out' else 'in' end as rel,
         p.pfr, p.afr, p.lvl
  from friends f join profiles p on p.player = case when f.a = p_player then f.b else f.a end
  where f.a = p_player or f.b = p_player
  order by rel, best desc
  limit 300;
$$;

drop function if exists public.search_players(text, text, int);
create or replace function public.search_players(p_player text, p_query text, p_season int)
returns table (pub text, name text, avatar text, flag text, best int, rel text, pfr int, afr int, lvl int)
language sql security definer set search_path = public stable as $$
  with q as (select lower(replace(replace(trim(leading '#' from trim(p_query)), '%', ''), '_', '')) as s)
  select p.pub, p.name, p.avatar, p.flag,
         coalesce((select max(r.meters) from runs r where r.player = p.player and r.season = p_season), 0),
         coalesce((select case when f.status = 'accepted' then 'friend' when f.a = p_player then 'out' else 'in' end
                   from friends f where (f.a = p_player and f.b = p.player) or (f.b = p_player and f.a = p.player) limit 1), ''),
         p.pfr, p.afr, p.lvl
  from profiles p, q
  where p.player <> p_player and char_length(q.s) >= 2
    and (lower(p.name) like '%' || q.s || '%' or p.pub = q.s)
  order by (lower(p.name) = q.s) desc, p.updated_at desc
  limit 20;
$$;

grant execute on function public.upsert_profile(text, text, text, text, int, int, int) to anon;
grant execute on function public.leaderboard(int, int, text) to anon;
grant execute on function public.friends_list(text, int) to anon;
grant execute on function public.search_players(text, text, int) to anon;
