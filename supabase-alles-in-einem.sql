-- WALDLAUF: KOMPLETTE DATENBANK IN EINEM SCHRITT
-- Alles markieren (Strg+A), kopieren (Strg+C), im Supabase SQL Editor einfügen (Strg+V) und auf Run drücken.
-- Man kann dieses Skript auch mehrmals ausführen, es macht nichts kaputt.


-- Alte Funktionen entfernen, damit das Skript auch über einen älteren Stand laufen kann (Daten bleiben erhalten)
do $$ declare r record; begin
  for r in select p.oid::regprocedure as f from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('ban_by_pub','challenge_done','challenge_send','clan_create','clan_info','clan_join','clan_kick','clan_leave','clan_top','delete_me','friend_remove','friend_request','friend_respond','friends_list','inbox_delete','inbox_list','inbox_read','leaderboard','load_backup','my_place','referral_claim','report_cheat','save_backup','search_players','start_run','submit_run','submit_run_v2','upsert_profile','weekly_top','wl_pub')
  loop execute 'drop function if exists ' || r.f || ' cascade'; end loop;
end $$;

-- ================= supabase-setup.sql =================
-- Waldlauf: Online-Rangliste
-- Dieses Skript einmal im Supabase SQL Editor ausführen (siehe ANLEITUNG.md).
-- Spieler können nur über die drei Funktionen unten Läufe eintragen und lesen,
-- direkter Zugriff auf die Tabelle ist gesperrt.

create table if not exists public.runs (
  id         bigint generated always as identity primary key,
  season     int  not null check (season between 1 and 1000),
  player     text not null check (char_length(player) between 8 and 64),
  name       text not null check (char_length(name) between 1 and 16),
  avatar     text not null default '🦊' check (char_length(avatar) <= 16),
  flag       text not null default '' check (char_length(flag) <= 2),
  meters     int  not null check (meters between 0 and 100000),
  coins      int  not null default 0 check (coins between 0 and 20000),
  created_at timestamptz not null default now()
);

create index if not exists runs_season_meters on public.runs (season, meters desc);
create index if not exists runs_player_time   on public.runs (player, created_at desc);

alter table public.runs enable row level security;
revoke all on public.runs from anon, authenticated;

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


-- ================= supabase-update-01.sql =================
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


-- ================= supabase-update-02.sql =================
-- Waldlauf Update 02: Freunde, Freundes-Rangliste und Postfach
-- Einmal im Supabase SQL Editor einfügen und auf Run drücken.
-- Wer die Datenbank ganz neu einrichtet: erst supabase-setup.sql, dann dieses Skript.

create table if not exists public.profiles (
  player     text primary key check (char_length(player) between 8 and 64),
  pub        text unique not null,
  name       text not null default 'Spieler' check (char_length(name) between 1 and 16),
  avatar     text not null default '🦊' check (char_length(avatar) <= 16),
  flag       text not null default '' check (char_length(flag) <= 2),
  updated_at timestamptz not null default now()
);
create index if not exists profiles_lname on public.profiles (lower(name));

create table if not exists public.friends (
  a          text not null references public.profiles(player) on delete cascade,
  b          text not null references public.profiles(player) on delete cascade,
  status     text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  primary key (a, b),
  check (a <> b)
);
create index if not exists friends_b on public.friends (b);

create table if not exists public.inbox (
  id         bigint generated always as identity primary key,
  player     text not null references public.profiles(player) on delete cascade,
  kind       text not null check (kind in ('freq', 'facc')),
  from_pub   text not null,
  from_name  text not null,
  created_at timestamptz not null default now(),
  read       boolean not null default false
);
create index if not exists inbox_player on public.inbox (player, created_at desc);

alter table public.profiles enable row level security;
alter table public.friends  enable row level security;
alter table public.inbox    enable row level security;
revoke all on public.profiles, public.friends, public.inbox from anon, authenticated;

-- Öffentliche Spieler-ID (die geheime Geräte-ID bleibt geheim)
create or replace function public.wl_pub(p text) returns text
language sql immutable as $$ select left(md5('waldlauf:' || p), 10) $$;
revoke all on function public.wl_pub(text) from public, anon, authenticated;

create or replace function public.upsert_profile(p_player text, p_name text, p_avatar text, p_flag text)
returns text
language plpgsql security definer set search_path = public as $$
declare v text := wl_pub(p_player);
begin
  if char_length(p_player) not between 8 and 64 then raise exception 'ungueltig'; end if;
  insert into profiles (player, pub, name, avatar, flag)
  values (p_player, v, left(coalesce(nullif(trim(p_name), ''), 'Spieler'), 16),
          left(coalesce(p_avatar, '🦊'), 16), upper(left(coalesce(p_flag, ''), 2)))
  on conflict (player) do update
    set name = excluded.name, avatar = excluded.avatar, flag = excluded.flag, updated_at = now();
  return v;
end $$;

create or replace function public.search_players(p_player text, p_query text, p_season int)
returns table (pub text, name text, avatar text, flag text, best int, rel text)
language sql security definer set search_path = public stable as $$
  with q as (select lower(replace(replace(trim(leading '#' from trim(p_query)), '%', ''), '_', '')) as s)
  select p.pub, p.name, p.avatar, p.flag,
         coalesce((select max(r.meters) from runs r where r.player = p.player and r.season = p_season), 0),
         coalesce((select case when f.status = 'accepted' then 'friend' when f.a = p_player then 'out' else 'in' end
                   from friends f where (f.a = p_player and f.b = p.player) or (f.b = p_player and f.a = p.player) limit 1), '')
  from profiles p, q
  where p.player <> p_player and char_length(q.s) >= 2
    and (lower(p.name) like '%' || q.s || '%' or p.pub = q.s)
  order by (lower(p.name) = q.s) desc, p.updated_at desc
  limit 20;
$$;

create or replace function public.friend_request(p_player text, p_pub text)
returns text
language plpgsql security definer set search_path = public as $$
declare t text; me profiles%rowtype; n int;
begin
  select * into me from profiles where player = p_player;
  if not found then raise exception 'kein profil'; end if;
  select player into t from profiles where pub = p_pub;
  if t is null or t = p_player then raise exception 'nicht gefunden'; end if;
  if exists (select 1 from friends where a = t and b = p_player) then
    update friends set status = 'accepted' where a = t and b = p_player and status = 'pending';
    if found then insert into inbox (player, kind, from_pub, from_name) values (t, 'facc', me.pub, me.name); end if;
    delete from inbox where player = p_player and kind = 'freq' and from_pub = p_pub;
    return 'accepted';
  end if;
  if exists (select 1 from friends where a = p_player and b = t) then return 'exists'; end if;
  select count(*) into n from friends where a = p_player and created_at > now() - interval '1 hour';
  if n >= 30 then raise exception 'zu viele'; end if;
  select count(*) into n from friends where (a = p_player or b = p_player) and status = 'accepted';
  if n >= 200 then raise exception 'voll'; end if;
  insert into friends (a, b) values (p_player, t);
  insert into inbox (player, kind, from_pub, from_name) values (t, 'freq', me.pub, me.name);
  return 'sent';
end $$;

create or replace function public.friend_respond(p_player text, p_pub text, p_accept boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare t text; me profiles%rowtype;
begin
  select * into me from profiles where player = p_player;
  select player into t from profiles where pub = p_pub;
  if t is null or me.player is null then return; end if;
  if p_accept then
    update friends set status = 'accepted' where a = t and b = p_player and status = 'pending';
    if found then insert into inbox (player, kind, from_pub, from_name) values (t, 'facc', me.pub, me.name); end if;
  else
    delete from friends where a = t and b = p_player and status = 'pending';
  end if;
  delete from inbox where player = p_player and kind = 'freq' and from_pub = p_pub;
end $$;

create or replace function public.friend_remove(p_player text, p_pub text)
returns void
language plpgsql security definer set search_path = public as $$
declare t text;
begin
  select player into t from profiles where pub = p_pub;
  if t is null then return; end if;
  delete from friends where (a = p_player and b = t) or (a = t and b = p_player);
  delete from inbox where player = t and kind = 'freq' and from_pub = wl_pub(p_player);
end $$;

create or replace function public.friends_list(p_player text, p_season int)
returns table (pub text, name text, avatar text, flag text, best int, rel text)
language sql security definer set search_path = public stable as $$
  select p.pub, p.name, p.avatar, p.flag,
         coalesce((select max(r.meters) from runs r where r.player = p.player and r.season = p_season), 0) as best,
         case when f.status = 'accepted' then 'friend' when f.a = p_player then 'out' else 'in' end as rel
  from friends f join profiles p on p.player = case when f.a = p_player then f.b else f.a end
  where f.a = p_player or f.b = p_player
  order by rel, best desc
  limit 300;
$$;

create or replace function public.inbox_list(p_player text)
returns table (id bigint, kind text, from_pub text, from_name text, created_at timestamptz, read boolean)
language sql security definer set search_path = public stable as $$
  select id, kind, from_pub, from_name, created_at, read from inbox
  where player = p_player order by created_at desc limit 50;
$$;

create or replace function public.inbox_read(p_player text)
returns void
language sql security definer set search_path = public as $$
  update inbox set read = true where player = p_player and not read;
$$;

create or replace function public.inbox_delete(p_player text, p_id bigint)
returns void
language sql security definer set search_path = public as $$
  delete from inbox where player = p_player and id = p_id;
$$;

-- Rangliste liefert jetzt zusätzlich die öffentliche ID (für "Freund hinzufügen")
drop function if exists public.leaderboard(int, int, text);
create or replace function public.leaderboard(p_season int, p_limit int default 50, p_player text default '')
returns table (name text, avatar text, flag text, best int, place bigint, is_me boolean, pub text)
language sql security definer set search_path = public stable as $$
  with b as (
    select distinct on (player) player, name, avatar, flag, meters as best
    from runs where season = p_season
    order by player, meters desc, created_at desc
  )
  select name, avatar, flag, best, rank() over (order by best desc) as place, (player = p_player) as is_me, wl_pub(player) as pub
  from b order by best desc limit least(greatest(p_limit, 1), 100);
$$;

grant execute on function public.upsert_profile(text, text, text, text) to anon;
grant execute on function public.search_players(text, text, int) to anon;
grant execute on function public.friend_request(text, text) to anon;
grant execute on function public.friend_respond(text, text, boolean) to anon;
grant execute on function public.friend_remove(text, text) to anon;
grant execute on function public.friends_list(text, int) to anon;
grant execute on function public.inbox_list(text) to anon;
grant execute on function public.inbox_read(text) to anon;
grant execute on function public.inbox_delete(text, bigint) to anon;
grant execute on function public.leaderboard(int, int, text) to anon;


-- ================= supabase-update-03.sql =================
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


-- ================= supabase-update-04.sql =================
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


-- ================= supabase-update-05.sql =================
-- Waldlauf Update 05: Anti-Cheat für die Weltrangliste
-- Einmal im Supabase SQL Editor einfügen und auf Run drücken (nach Update 03).
-- Jeder Lauf braucht jetzt ein Lauf-Ticket vom Server. Die echte Zeit zwischen Ticket und Ergebnis
-- muss zur Strecke passen, deshalb lassen sich keine Fantasie-Meter mehr eintragen.

create table if not exists public.run_tokens (
  token      uuid primary key default gen_random_uuid(),
  player     text not null,
  created_at timestamptz not null default now(),
  used       boolean not null default false
);
create index if not exists run_tokens_player on public.run_tokens (player, created_at desc);

create table if not exists public.banned (
  player     text primary key,
  reason     text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.cheat_log (
  id         bigint generated always as identity primary key,
  player     text not null,
  name       text not null default '',
  reason     text not null,
  meters     int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.run_tokens enable row level security;
alter table public.banned     enable row level security;
alter table public.cheat_log  enable row level security;
revoke all on public.run_tokens, public.banned, public.cheat_log from anon, authenticated;

-- Lauf-Ticket holen (beim Start eines Laufs)
create or replace function public.start_run(p_player text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare t uuid; n int;
begin
  if char_length(p_player) not between 8 and 64 then raise exception 'ungueltig'; end if;
  select count(*) into n from run_tokens where player = p_player and created_at > now() - interval '1 minute';
  if n >= 12 then raise exception 'zu viele'; end if;
  delete from run_tokens where created_at < now() - interval '1 day';
  insert into run_tokens (player) values (p_player) returning token into t;
  return t;
end $$;

-- Lauf eintragen mit Prüfungen
drop function if exists public.submit_run_v2(text, text, text, int, int, int, text, uuid, int);
create or replace function public.submit_run_v2(
  p_player text, p_name text, p_avatar text, p_season int, p_meters int, p_coins int, p_flag text,
  p_token uuid, p_dur int)
returns text
language plpgsql security definer set search_path = public as $$
declare
  tk run_tokens%rowtype;
  real_s numeric;
  cur_season int := floor(extract(epoch from (now() - timestamptz '2026-10-11 00:00:00+00')) / (90 * 86400))::int + 1;
  why text := null;
begin
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  if p_season <> cur_season and p_season <> cur_season - 1 then raise exception 'falsche Season'; end if;
  select * into tk from run_tokens where token = p_token and player = p_player for update;
  if not found then raise exception 'kein Ticket'; end if;
  if tk.used then raise exception 'Ticket benutzt'; end if;
  update run_tokens set used = true where token = p_token;
  real_s := extract(epoch from (now() - tk.created_at));
  -- Höchsttempo im Spiel liegt bei etwa 34 m/s, mit Apfel-Turbo kurz darüber
  if p_meters > real_s * 40 + 60 then why := 'zu schnell fuer die echte Zeit'; end if;
  if p_dur is null or p_meters > (p_dur / 1000.0) * 40 + 60 then why := coalesce(why, 'zu schnell fuer die Laufzeit'); end if;
  if p_dur > (real_s + 30) * 1000 then why := coalesce(why, 'Laufzeit laenger als echte Zeit'); end if;
  if p_coins > p_meters * 0.6 + 20 then why := coalesce(why, 'zu viele Muenzen'); end if;
  if real_s > 6 * 3600 then why := coalesce(why, 'Ticket zu alt'); end if;
  if why is not null then
    insert into cheat_log (player, name, reason, meters) values (p_player, left(coalesce(p_name, ''), 16), why, p_meters);
    return 'abgelehnt';
  end if;
  insert into runs (season, player, name, avatar, flag, meters, coins)
  values (p_season, p_player, left(coalesce(nullif(trim(p_name), ''), 'Spieler'), 16),
          left(coalesce(p_avatar, '🦊'), 16), upper(left(coalesce(p_flag, ''), 2)), least(p_meters, 100000), least(p_coins, 20000));
  return 'ok';
end $$;

-- Vom Spiel erkannte Manipulation melden
create or replace function public.report_cheat(p_player text, p_name text, p_reason text, p_meters int)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from cheat_log where player = p_player and created_at > now() - interval '1 hour') >= 20 then return; end if;
  insert into cheat_log (player, name, reason, meters)
  values (left(p_player, 64), left(coalesce(p_name, ''), 16), left(coalesce(p_reason, ''), 80), coalesce(p_meters, 0));
end $$;

-- Rangliste und eigener Platz ohne gesperrte Spieler
drop function if exists public.leaderboard(int, int, text);
create or replace function public.leaderboard(p_season int, p_limit int default 50, p_player text default '')
returns table (name text, avatar text, flag text, best int, place bigint, is_me boolean, pub text, pfr int, afr int, lvl int)
language sql security definer set search_path = public stable as $$
  with b as (
    select distinct on (player) player, name, avatar, flag, meters as best
    from runs where season = p_season and player not in (select player from banned)
    order by player, meters desc, created_at desc
  )
  select b.name, b.avatar, b.flag, b.best, rank() over (order by b.best desc) as place, (b.player = p_player) as is_me,
         wl_pub(b.player) as pub, coalesce(p.pfr, 0), coalesce(p.afr, 0), coalesce(p.lvl, 1)
  from b left join profiles p on p.player = b.player
  order by b.best desc limit least(greatest(p_limit, 1), 100);
$$;

create or replace function public.my_place(p_season int, p_player text)
returns table (place bigint, total bigint, best int)
language sql security definer set search_path = public stable as $$
  with b as (select player, max(meters) as best from runs
             where season = p_season and player not in (select player from banned) group by player),
       me as (select best from b where player = p_player)
  select (select count(*) + 1 from b where b.best > me.best), (select count(*) from b), me.best
  from me;
$$;

-- Admin: Spieler sperren per öffentlicher Freundes-ID (im SQL Editor ausführen)
create or replace function public.ban_by_pub(p_pub text, p_reason text default '')
returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into banned (player, reason)
  select player, coalesce(p_reason, '') from profiles where pub = trim(leading '#' from p_pub)
  on conflict (player) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.ban_by_pub(text, text) from public, anon, authenticated;

-- Der alte Weg ohne Ticket wird für Spieler geschlossen
revoke execute on function public.submit_run(text, text, text, int, int, int, text) from anon, public;

grant execute on function public.start_run(text) to anon;
grant execute on function public.submit_run_v2(text, text, text, int, int, int, text, uuid, int) to anon;
grant execute on function public.report_cheat(text, text, text, int) to anon;
grant execute on function public.leaderboard(int, int, text) to anon;
grant execute on function public.my_place(int, text) to anon;


-- ================= supabase-update-06.sql =================
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


-- ================= supabase-update-07.sql =================
-- Waldlauf Update 07: Herausforderungen unter Freunden und Rudel (Clans)
-- Einmal im Supabase SQL Editor einfügen und auf Run drücken (nach Update 01 bis 06).

-- ---------- Herausforderungen über das Postfach
alter table public.inbox add column if not exists meters int;
alter table public.inbox add column if not exists note text;
alter table public.inbox drop constraint if exists inbox_kind_check;
alter table public.inbox add constraint inbox_kind_check check (kind in ('freq', 'facc', 'chal', 'chok'));

drop function if exists public.inbox_list(text);
create function public.inbox_list(p_player text)
returns table (id bigint, kind text, from_pub text, from_name text, created_at timestamptz, read boolean, meters int, note text)
language sql security definer set search_path = public stable as $$
  select id, kind, from_pub, from_name, created_at, read, meters, note from inbox
  where player = p_player order by created_at desc limit 50;
$$;

-- Herausforderung an einen Freund schicken (nur echte Freunde, nur eigene echte Bestweite)
create or replace function public.challenge_send(p_player text, p_pub text, p_meters int, p_animal text)
returns text
language plpgsql security definer set search_path = public as $$
declare t text; me profiles%rowtype; n int; v_best int;
begin
  select * into me from profiles where player = p_player;
  if not found then raise exception 'kein profil'; end if;
  select player into t from profiles where pub = p_pub;
  if t is null or t = p_player then raise exception 'nicht gefunden'; end if;
  if not exists (select 1 from friends where status = 'accepted' and ((a = p_player and b = t) or (a = t and b = p_player))) then
    raise exception 'kein freund';
  end if;
  select coalesce(max(meters), 0) into v_best from runs where player = p_player;
  if p_meters is null or p_meters < 100 or p_meters > v_best then raise exception 'ungueltig'; end if;
  select count(*) into n from inbox where from_pub = me.pub and kind = 'chal' and created_at > now() - interval '1 day';
  if n >= 20 then raise exception 'zu viele'; end if;
  delete from inbox where player = t and kind = 'chal' and from_pub = me.pub;
  insert into inbox (player, kind, from_pub, from_name, meters, note)
  values (t, 'chal', me.pub, me.name, p_meters, left(coalesce(p_animal, ''), 16));
  return 'sent';
end $$;

-- Herausforderung geschafft: Herausforderer bekommt Bescheid
create or replace function public.challenge_done(p_player text, p_pub text, p_meters int)
returns void
language plpgsql security definer set search_path = public as $$
declare t text; me profiles%rowtype; v_best int;
begin
  select * into me from profiles where player = p_player;
  select player into t from profiles where pub = p_pub;
  if t is null or me.player is null then return; end if;
  select coalesce(max(meters), 0) into v_best from runs where player = p_player and created_at > now() - interval '1 hour';
  if p_meters > v_best + 5 then return; end if;
  insert into inbox (player, kind, from_pub, from_name, meters) values (t, 'chok', me.pub, me.name, p_meters);
end $$;

-- ---------- Rudel (Clans)
create table if not exists public.clans (
  id         bigint generated always as identity primary key,
  name       text not null check (char_length(name) between 3 and 20),
  tag        text not null check (char_length(tag) between 2 and 4),
  emblem     text not null default '🐺' check (char_length(emblem) <= 8),
  code       text unique not null,
  owner      text not null references public.profiles(player) on delete cascade,
  created_at timestamptz not null default now()
);
create unique index if not exists clans_lname on public.clans (lower(name));

create table if not exists public.clan_members (
  player    text primary key references public.profiles(player) on delete cascade,
  clan      bigint not null references public.clans(id) on delete cascade,
  joined_at timestamptz not null default now()
);
create index if not exists clan_members_clan on public.clan_members (clan);

alter table public.clans enable row level security;
alter table public.clan_members enable row level security;
revoke all on public.clans, public.clan_members from anon, authenticated;

create or replace function public.clan_create(p_player text, p_name text, p_tag text, p_emblem text)
returns text
language plpgsql security definer set search_path = public as $$
declare c text; i bigint;
begin
  if not exists (select 1 from profiles where player = p_player) then raise exception 'kein profil'; end if;
  if exists (select 1 from clan_members where player = p_player) then raise exception 'schon im rudel'; end if;
  if exists (select 1 from clans where lower(name) = lower(trim(p_name))) then raise exception 'name vergeben'; end if;
  c := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  insert into clans (name, tag, emblem, code, owner)
  values (trim(p_name), upper(trim(p_tag)), left(coalesce(p_emblem, '🐺'), 8), c, p_player) returning id into i;
  insert into clan_members (player, clan) values (p_player, i);
  return c;
end $$;

create or replace function public.clan_join(p_player text, p_code text)
returns text
language plpgsql security definer set search_path = public as $$
declare i bigint; n int;
begin
  if not exists (select 1 from profiles where player = p_player) then raise exception 'kein profil'; end if;
  if exists (select 1 from clan_members where player = p_player) then raise exception 'schon im rudel'; end if;
  select id into i from clans where code = upper(trim(p_code));
  if i is null then raise exception 'nicht gefunden'; end if;
  select count(*) into n from clan_members where clan = i;
  if n >= 30 then raise exception 'voll'; end if;
  insert into clan_members (player, clan) values (p_player, i);
  return 'ok';
end $$;

create or replace function public.clan_leave(p_player text)
returns void
language plpgsql security definer set search_path = public as $$
declare i bigint; nxt text;
begin
  select clan into i from clan_members where player = p_player;
  if i is null then return; end if;
  delete from clan_members where player = p_player;
  if exists (select 1 from clans where id = i and owner = p_player) then
    select player into nxt from clan_members where clan = i order by joined_at limit 1;
    if nxt is null then delete from clans where id = i;
    else update clans set owner = nxt where id = i; end if;
  end if;
end $$;

create or replace function public.clan_kick(p_player text, p_pub text)
returns void
language plpgsql security definer set search_path = public as $$
declare i bigint; t text;
begin
  select id into i from clans where owner = p_player;
  select player into t from profiles where pub = p_pub;
  if i is null or t is null or t = p_player then return; end if;
  delete from clan_members where player = t and clan = i;
end $$;

-- Eigenes Rudel mit allen Mitgliedern und ihrer Season-Bestweite
create or replace function public.clan_info(p_player text, p_season int)
returns table (name text, tag text, emblem text, code text, mine boolean, pub text, pname text, avatar text, flag text, best int, lvl int, boss boolean)
language sql security definer set search_path = public stable as $$
  select c.name, c.tag, c.emblem, c.code, p.player = p_player, p.pub, p.name, p.avatar, p.flag,
         coalesce((select max(r.meters) from runs r where r.player = p.player and r.season = p_season), 0),
         coalesce(p.lvl, 1), c.owner = p.player
  from clan_members me
  join clans c on c.id = me.clan
  join clan_members m on m.clan = c.id
  join profiles p on p.player = m.player
  where me.player = p_player
  order by 10 desc;
$$;

-- Beste Rudel der Season (Summe der Bestweiten aller Mitglieder)
create or replace function public.clan_top(p_season int)
returns table (name text, tag text, emblem text, members int, score bigint)
language sql security definer set search_path = public stable as $$
  select c.name, c.tag, c.emblem, count(m.player)::int,
         coalesce(sum((select max(r.meters) from runs r where r.player = m.player and r.season = p_season)), 0)::bigint as score
  from clans c join clan_members m on m.clan = c.id
  where m.player not in (select player from banned)
  group by c.id order by score desc limit 50;
$$;

grant execute on function public.inbox_list(text), public.challenge_send(text, text, int, text), public.challenge_done(text, text, int),
  public.clan_create(text, text, text, text), public.clan_join(text, text), public.clan_leave(text), public.clan_kick(text, text),
  public.clan_info(text, int), public.clan_top(int) to anon;


-- ================= supabase-update-08.sql =================
-- Waldlauf Update 08: Wochen-Rangliste und Freunde einladen
-- Einmal im Supabase SQL Editor einfügen und auf Run drücken (nach Update 07).

-- ---------- Wochen-Rangliste: beste Läufe seit Montag
create or replace function public.weekly_top(p_since timestamptz, p_limit int, p_player text)
returns table (place bigint, pub text, name text, avatar text, flag text, best int, pfr int, afr int, lvl int, is_me boolean)
language sql security definer set search_path = public stable as $$
  with b as (
    select distinct on (r.player) r.player, r.meters
    from runs r
    where r.created_at >= greatest(p_since, now() - interval '8 days')
      and r.player not in (select player from banned)
    order by r.player, r.meters desc, r.created_at
  ), x as (
    select row_number() over (order by b.meters desc) as place, b.player, b.meters from b
  )
  select x.place, p.pub, coalesce(p.name, 'Spieler'), coalesce(p.avatar, '🦊'), coalesce(p.flag, ''), x.meters,
         coalesce(p.pfr, 0), coalesce(p.afr, 0), coalesce(p.lvl, 1), x.player = p_player
  from x left join profiles p on p.player = x.player
  where x.place <= least(greatest(coalesce(p_limit, 50), 1), 100) or x.player = p_player
  order by x.place;
$$;

-- ---------- Freunde einladen
create table if not exists public.referrals (
  player     text primary key references public.profiles(player) on delete cascade,
  ref        text not null,
  created_at timestamptz not null default now()
);
alter table public.referrals enable row level security;
revoke all on public.referrals from anon, authenticated;

alter table public.inbox drop constraint if exists inbox_kind_check;
alter table public.inbox add constraint inbox_kind_check check (kind in ('freq', 'facc', 'chal', 'chok', 'refb'));

-- Neuer Spieler meldet, wer ihn eingeladen hat. Klappt nur einmal pro Spieler und nur für neue Profile.
create or replace function public.referral_claim(p_player text, p_ref_pub text)
returns text
language plpgsql security definer set search_path = public as $$
declare me profiles%rowtype; t text; n int;
begin
  select * into me from profiles where player = p_player;
  if not found then raise exception 'kein profil'; end if;
  if exists (select 1 from referrals where player = p_player) then return 'schon'; end if;
  select player into t from profiles where pub = p_ref_pub;
  if t is null or t = p_player then return 'ungueltig'; end if;
  select count(*) into n from runs where player = p_player;
  if n > 30 then return 'zu alt'; end if;
  select count(*) into n from referrals where ref = p_ref_pub and created_at > now() - interval '1 day';
  if n >= 20 then return 'zu viele'; end if;
  insert into referrals (player, ref) values (p_player, p_ref_pub);
  insert into inbox (player, kind, from_pub, from_name) values (t, 'refb', me.pub, me.name);
  return 'ok';
end $$;

grant execute on function public.weekly_top(timestamptz, int, text), public.referral_claim(text, text) to anon;

