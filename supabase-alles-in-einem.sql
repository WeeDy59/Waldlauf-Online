-- WALDLAUF: KOMPLETTE DATENBANK IN EINEM SCHRITT
-- Alles markieren (Strg+A), kopieren (Strg+C), im Supabase SQL Editor einfügen (Strg+V) und auf Run drücken.
-- Man kann dieses Skript auch mehrmals ausführen, es macht nichts kaputt.


-- Alte Funktionen entfernen, damit das Skript auch über einen älteren Stand laufen kann (Daten bleiben erhalten)
do $$ declare r record; begin
  for r in select p.oid::regprocedure as f from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('ban_by_pub','challenge_done','challenge_send','clan_create','clan_info','clan_join','clan_kick','clan_leave','clan_top','delete_me','friend_remove','friend_request','friend_respond','friends_list','inbox_delete','inbox_list','inbox_read','leaderboard','load_backup','my_place','referral_claim','report_cheat','save_backup','search_players','start_run','submit_run','submit_run_v2','upsert_profile','weekly_top','wl_pub','market_browse','market_buy','market_cancel','market_sell','market_stats','skin_list','skin_open','skin_pub_list','skin_scrap','submit_run_v3','taler_daily','taler_daily_cleanup','taler_info','trade_answer','trade_list','trade_offer','wl_add','wl_cleanup','wl_event','wl_scrap_val','wl_skin_json','wl_var_r','wl_wallet','skin_tradeup','submit_run_v4','daily_top','duel_create','duel_list','live_create','live_join','live_start','live_leave','live_tick','skin_book_list','skin_book_claim','skin_top','weekly_claim','profile_set_card','profile_view','wl_today','chat_send','chat_list','chat_report','wl_clean','wl_drop_post','wl_skin_stamp','profile_set_img','avatar_imgs','avatar_report','dev_list','wl_dlc_price','dlc_buy','dlc_list','push_key','push_sub','push_unsub','push_add','push_daily','push_tg_taler','push_tg_trade','push_tg_inbox','push_tg_run','dlc_redeem','stat_inc','stat_hit','stats_overview','dino_week','dino_submit','dino_top','dino_claim','wl_del_extra')
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
alter table public.inbox add constraint inbox_kind_check check (kind in ('freq', 'facc', 'chal', 'chok', 'refb', 'trad', 'tok', 'mkt', 'duel', 'dueld'));

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
alter table public.inbox add constraint inbox_kind_check check (kind in ('freq', 'facc', 'chal', 'chok', 'refb', 'trad', 'tok', 'mkt', 'duel', 'dueld'));

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


-- ================= supabase-update-09.sql =================
-- Waldlauf Update 09: Waldtaler, Skins, Skin-Kisten, Markt und Tausch
-- Einmal im Supabase SQL Editor einfügen und auf Run drücken (nach Update 08).
-- Alles, was Wert hat (Waldtaler und Skins), liegt nur hier auf dem Server.
-- Das Spiel kann nichts davon selbst verändern, es fragt nur über die Funktionen unten an.

-- ---------- Tabellen
create table if not exists public.wallets (
  player     text primary key references public.profiles(player) on delete cascade,
  bal        bigint not null default 500 check (bal >= 0),
  day        date not null default (now() at time zone 'Europe/Berlin')::date,
  day_run    int not null default 0,
  last_daily date,
  created_at timestamptz not null default now()
);

create table if not exists public.skins (
  id         bigint generated always as identity primary key,
  owner      text not null references public.profiles(player) on delete cascade,
  animal     int not null check (animal between 0 and 99),
  variant    int not null check (variant between 0 and 99),
  seed       int not null check (seed between 0 and 999),
  glanz      real not null check (glanz between 0 and 1),
  zt         boolean not null default false,
  zm         bigint not null default 0,
  origin     text not null default 'kiste',
  listed     boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists skins_owner on public.skins (owner);

create table if not exists public.market (
  id         bigint generated always as identity primary key,
  skin       bigint not null unique references public.skins(id) on delete cascade,
  seller     text not null references public.profiles(player) on delete cascade,
  price      int not null check (price between 10 and 10000000),
  created_at timestamptz not null default now()
);
create index if not exists market_price on public.market (price);
create index if not exists market_time on public.market (created_at desc);

create table if not exists public.market_sales (
  id         bigint generated always as identity primary key,
  animal     int not null,
  variant    int not null,
  price      int not null,
  created_at timestamptz not null default now()
);
create index if not exists market_sales_av on public.market_sales (animal, variant, created_at desc);

create table if not exists public.trades (
  id         bigint generated always as identity primary key,
  a          text not null references public.profiles(player) on delete cascade,
  b          text not null references public.profiles(player) on delete cascade,
  a_skins    bigint[] not null default '{}',
  b_skins    bigint[] not null default '{}',
  a_taler    int not null default 0 check (a_taler between 0 and 10000000),
  b_taler    int not null default 0 check (b_taler between 0 and 10000000),
  status     text not null default 'offen' check (status in ('offen', 'ok', 'nein', 'zurueck', 'ungueltig')),
  created_at timestamptz not null default now(),
  done_at    timestamptz
);
create index if not exists trades_a on public.trades (a, created_at desc);
create index if not exists trades_b on public.trades (b, created_at desc);

create table if not exists public.taler_log (
  id         bigint generated always as identity primary key,
  player     text not null,
  delta      bigint not null,
  reason     text not null,
  created_at timestamptz not null default now()
);
create index if not exists taler_log_player on public.taler_log (player, created_at desc);

alter table public.wallets      enable row level security;
alter table public.skins        enable row level security;
alter table public.market       enable row level security;
alter table public.market_sales enable row level security;
alter table public.trades       enable row level security;
alter table public.taler_log    enable row level security;
revoke all on public.wallets, public.skins, public.market, public.market_sales, public.trades, public.taler_log from anon, authenticated;

alter table public.inbox drop constraint if exists inbox_kind_check;
alter table public.inbox add constraint inbox_kind_check check (kind in ('freq', 'facc', 'chal', 'chok', 'refb', 'trad', 'tok', 'mkt', 'duel', 'dueld'));

-- ---------- Hilfsfunktionen (nicht von außen aufrufbar)
-- Seltenheit einer Variante: 0 Gewöhnlich, 1 Selten, 2 Episch, 3 Legendär, 4 Mythisch
create or replace function public.wl_var_r(v int) returns int
language sql immutable as $$
  select case when v < 8 then 0 when v < 14 then 1 when v < 19 then 2 when v < 23 then 3 when v < 26 then 4
              when v in (26, 28, 30) then 2 else 3 end
$$;

-- Wert beim Recyceln
create or replace function public.wl_scrap_val(v int, zt boolean) returns int
language sql immutable as $$
  select ((array[40, 120, 400, 1500, 6000])[public.wl_var_r(v) + 1] * (case when zt then 1.5 else 1 end))::int
$$;

-- Welches Event läuft gerade? (gleiche Termine wie im Spiel)
create or replace function public.wl_event() returns text
language sql stable as $$
  select case
    when now() >= timestamptz '2026-10-11 00:00+00' and now() < timestamptz '2026-10-25 00:00+00' then 'hf'
    when now() >= timestamptz '2026-10-30 23:00+00' and now() < timestamptz '2026-11-13 23:00+00' then 'hw'
    when now() >= timestamptz '2026-12-13 23:00+00' and now() < timestamptz '2026-12-27 23:00+00' then 'wi'
    else null end
$$;

-- Konto holen (wird beim ersten Mal mit 500 Startalern angelegt), Tageszähler zurücksetzen
create or replace function public.wl_wallet(p_player text) returns public.wallets
language plpgsql security definer set search_path = public as $$
declare w wallets%rowtype; today date := (now() at time zone 'Europe/Berlin')::date;
begin
  if not exists (select 1 from profiles where player = p_player) then raise exception 'kein profil'; end if;
  insert into wallets (player) values (p_player) on conflict (player) do nothing;
  select * into w from wallets where player = p_player for update;
  if w.day <> today then
    update wallets set day = today, day_run = 0 where player = p_player returning * into w;
  end if;
  return w;
end $$;

create or replace function public.wl_add(p_player text, p_delta bigint, p_reason text) returns bigint
language plpgsql security definer set search_path = public as $$
declare b bigint;
begin
  update wallets set bal = bal + p_delta where player = p_player and bal + p_delta >= 0 returning bal into b;
  if b is null then raise exception 'zu wenig Waldtaler'; end if;
  insert into taler_log (player, delta, reason) values (p_player, p_delta, p_reason);
  return b;
end $$;

create or replace function public.wl_skin_json(s public.skins) returns jsonb
language sql immutable as $$
  select jsonb_build_object('id', s.id, 'animal', s.animal, 'variant', s.variant, 'seed', s.seed, 'glanz', s.glanz,
                            'zt', s.zt, 'zm', s.zm, 'origin', s.origin, 'listed', s.listed, 'created', s.created_at)
$$;

revoke all on function public.wl_var_r(int), public.wl_scrap_val(int, boolean), public.wl_event(),
  public.wl_wallet(text), public.wl_add(text, bigint, text), public.wl_skin_json(public.skins) from public, anon, authenticated;

-- ---------- Waldtaler
-- Kontostand und Tagesinfos
create or replace function public.taler_info(p_player text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare w wallets%rowtype; today date := (now() at time zone 'Europe/Berlin')::date;
begin
  w := wl_wallet(p_player);
  return jsonb_build_object('bal', w.bal, 'day_run', w.day_run, 'cap', 800, 'daily', w.last_daily is distinct from today,
    'event', wl_event(),
    'trades_in', (select count(*) from trades where b = p_player and status = 'offen'));
end $$;

-- Täglicher Online-Bonus
create or replace function public.taler_daily(p_player text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare w wallets%rowtype; today date := (now() at time zone 'Europe/Berlin')::date; b bigint;
begin
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  w := wl_wallet(p_player);
  if w.last_daily = today then return jsonb_build_object('got', 0, 'bal', w.bal); end if;
  update wallets set last_daily = today where player = p_player;
  b := wl_add(p_player, 60, 'tagesbonus');
  return jsonb_build_object('got', 60, 'bal', b);
end $$;

-- Lauf eintragen wie bisher, dazu Waldtaler gutschreiben und den Zähler eines Skins weiterzählen
create or replace function public.submit_run_v3(
  p_player text, p_name text, p_avatar text, p_season int, p_meters int, p_coins int, p_flag text,
  p_token uuid, p_dur int, p_skin bigint default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare r text; w wallets%rowtype; got int := 0; b bigint;
begin
  r := submit_run_v2(p_player, p_name, p_avatar, p_season, p_meters, p_coins, p_flag, p_token, p_dur);
  if r <> 'ok' then return jsonb_build_object('status', r); end if;
  if not exists (select 1 from profiles where player = p_player) then return jsonb_build_object('status', r); end if;
  w := wl_wallet(p_player);
  got := greatest(0, least(floor(p_meters / 50.0)::int + floor(least(p_coins, 20000) / 10.0)::int, 800 - w.day_run));
  b := w.bal;
  if got > 0 then
    update wallets set day_run = day_run + got where player = p_player;
    b := wl_add(p_player, got, 'lauf');
  end if;
  if p_skin is not null then
    update skins set zm = zm + least(p_meters, 100000) where id = p_skin and owner = p_player and zt;
  end if;
  return jsonb_build_object('status', r, 'taler', got, 'bal', b);
end $$;

-- ---------- Skins
-- Skin-Kiste öffnen. 0 = normale Kiste (600), 1 = Event-Kiste (900, nur während eines Events)
create or replace function public.skin_open(p_player text, p_crate int)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare w wallets%rowtype; ev text := wl_event(); price int; x numeric; rr int; v int; s skins%rowtype; b bigint;
begin
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  if p_crate not in (0, 1) then raise exception 'unbekannte Kiste'; end if;
  if p_crate = 1 and ev is null then raise exception 'gerade kein Event'; end if;
  if (select count(*) from skins where owner = p_player) >= 500 then raise exception 'Inventar voll'; end if;
  price := case when p_crate = 0 then 600 else 900 end;
  w := wl_wallet(p_player);
  b := wl_add(p_player, -price, 'kiste');
  x := random() * 100;
  if p_crate = 0 then
    rr := case when x < 70 then 0 when x < 90 then 1 when x < 97 then 2 when x < 99.5 then 3 else 4 end;
  else
    rr := case when x < 55 then 1 when x < 85 then 2 when x < 97 then 3 else 4 end;
  end if;
  v := case rr
    when 0 then 0 + floor(random() * 8)::int
    when 1 then 8 + floor(random() * 6)::int
    when 2 then 14 + floor(random() * 5)::int
    when 3 then 19 + floor(random() * 4)::int
    else 23 + floor(random() * 3)::int end;
  -- In der Event-Kiste ist jede zweite epische oder legendäre Variante die Event-Variante
  if p_crate = 1 and rr in (2, 3) and random() < 0.5 then
    v := case ev when 'hw' then 26 when 'wi' then 28 else 30 end + (rr - 2);
  end if;
  insert into skins (owner, animal, variant, seed, glanz, zt, origin)
  values (p_player, floor(random() * 36)::int, v, floor(random() * 1000)::int, round(random()::numeric, 4),
          random() < 0.10, case when p_crate = 1 then 'event-' || ev else 'kiste' end)
  returning * into s;
  return wl_skin_json(s) || jsonb_build_object('bal', b);
end $$;

-- Eigene Skins
create or replace function public.skin_list(p_player text)
returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(wl_skin_json(s) || jsonb_build_object('price', m.price, 'listing', m.id) order by s.id desc), '[]')
  from skins s left join market m on m.skin = s.id where s.owner = p_player;
$$;

-- Skins eines Freundes ansehen (nur echte Freunde, nur Skins, die nicht im Markt stehen)
create or replace function public.skin_pub_list(p_player text, p_pub text)
returns jsonb
language plpgsql security definer set search_path = public stable as $$
declare t text;
begin
  select player into t from profiles where pub = p_pub;
  if t is null then raise exception 'unbekannt'; end if;
  if not exists (select 1 from friends where status = 'accepted' and ((a = p_player and b = t) or (a = t and b = p_player))) then
    raise exception 'nur Freunde';
  end if;
  return (select coalesce(jsonb_agg(wl_skin_json(s) order by s.id desc), '[]') from skins s where s.owner = t and not s.listed);
end $$;

-- Skin recyceln: der Skin verschwindet, du bekommst Waldtaler
create or replace function public.skin_scrap(p_player text, p_skin bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare s skins%rowtype; val int; b bigint;
begin
  perform wl_wallet(p_player);
  select * into s from skins where id = p_skin and owner = p_player for update;
  if not found then raise exception 'nicht deiner'; end if;
  if s.listed then raise exception 'steht im Markt'; end if;
  val := wl_scrap_val(s.variant, s.zt);
  delete from skins where id = p_skin;
  b := wl_add(p_player, val, 'recycelt');
  return jsonb_build_object('got', val, 'bal', b);
end $$;

-- ---------- Markt
create or replace function public.market_sell(p_player text, p_skin bigint, p_price int)
returns bigint
language plpgsql security definer set search_path = public as $$
declare s skins%rowtype; mid bigint;
begin
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  if p_price < 10 or p_price > 10000000 then raise exception 'Preis 10 bis 10.000.000'; end if;
  select * into s from skins where id = p_skin and owner = p_player for update;
  if not found then raise exception 'nicht deiner'; end if;
  if s.listed then raise exception 'steht schon im Markt'; end if;
  if (select count(*) from market where seller = p_player) >= 20 then raise exception 'hoechstens 20 Angebote'; end if;
  update skins set listed = true where id = p_skin;
  insert into market (skin, seller, price) values (p_skin, p_player, p_price) returning id into mid;
  return mid;
end $$;

create or replace function public.market_cancel(p_player text, p_listing bigint)
returns void
language plpgsql security definer set search_path = public as $$
declare m market%rowtype;
begin
  select * into m from market where id = p_listing and seller = p_player for update;
  if not found then raise exception 'nicht dein Angebot'; end if;
  delete from market where id = p_listing;
  update skins set listed = false where id = m.skin;
end $$;

-- Markt durchsuchen. p_sort: 'neu', 'billig', 'teuer'
create or replace function public.market_browse(p_player text, p_animal int default null, p_rarity int default null,
  p_zt boolean default null, p_sort text default 'neu', p_offset int default 0)
returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(x.j), '[]') from (
    select wl_skin_json(s) || jsonb_build_object('listing', m.id, 'price', m.price, 'seller', coalesce(p.name, 'Spieler'),
             'seller_pub', p.pub, 'mine', m.seller = p_player, 'since', m.created_at) as j
    from market m join skins s on s.id = m.skin left join profiles p on p.player = m.seller
    where (p_animal is null or s.animal = p_animal)
      and (p_rarity is null or wl_var_r(s.variant) = p_rarity)
      and (p_zt is null or s.zt = p_zt)
    order by case when p_sort = 'billig' then m.price end asc,
             case when p_sort = 'teuer' then m.price end desc,
             m.created_at desc
    limit 30 offset greatest(0, least(coalesce(p_offset, 0), 3000))
  ) x;
$$;

-- Durchschnittspreis der letzten 30 Tage für eine Kombination aus Tier und Variante
create or replace function public.market_stats(p_animal int, p_variant int)
returns jsonb
language sql security definer set search_path = public stable as $$
  select jsonb_build_object('n', count(*), 'avg', coalesce(round(avg(price)), 0), 'min', coalesce(min(price), 0), 'max', coalesce(max(price), 0))
  from market_sales where animal = p_animal and variant = p_variant and created_at > now() - interval '30 days';
$$;

create or replace function public.market_buy(p_player text, p_listing bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m market%rowtype; s skins%rowtype; fee int; b bigint; buyer_name text; buyer_pub text;
begin
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  perform wl_wallet(p_player);
  select * into m from market where id = p_listing for update;
  if not found then raise exception 'schon verkauft'; end if;
  if m.seller = p_player then raise exception 'eigenes Angebot'; end if;
  if (select count(*) from skins where owner = p_player) >= 500 then raise exception 'Inventar voll'; end if;
  perform wl_wallet(m.seller);
  b := wl_add(p_player, -m.price, 'markt-kauf');
  fee := greatest(1, floor(m.price * 0.05)::int);
  perform wl_add(m.seller, m.price - fee, 'markt-verkauf');
  delete from market where id = p_listing;
  update skins set owner = p_player, listed = false where id = m.skin returning * into s;
  insert into market_sales (animal, variant, price) values (s.animal, s.variant, m.price);
  select name, pub into buyer_name, buyer_pub from profiles where player = p_player;
  insert into inbox (player, kind, from_pub, from_name, meters, note)
  values (m.seller, 'mkt', buyer_pub, coalesce(buyer_name, 'Spieler'), m.price, s.animal || ':' || s.variant);
  return wl_skin_json(s) || jsonb_build_object('bal', b);
end $$;

-- ---------- Tausch unter Freunden
create or replace function public.trade_offer(p_player text, p_pub text, p_my bigint[], p_their bigint[], p_my_taler int, p_their_taler int)
returns bigint
language plpgsql security definer set search_path = public as $$
declare t text; tid bigint; me profiles%rowtype;
begin
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  select * into me from profiles where player = p_player;
  if not found then raise exception 'kein profil'; end if;
  select player into t from profiles where pub = p_pub;
  if t is null or t = p_player then raise exception 'unbekannt'; end if;
  if not exists (select 1 from friends where status = 'accepted' and ((a = p_player and b = t) or (a = t and b = p_player))) then
    raise exception 'nur mit Freunden';
  end if;
  p_my := coalesce(p_my, '{}'); p_their := coalesce(p_their, '{}');
  if cardinality(p_my) > 8 or cardinality(p_their) > 8 then raise exception 'hoechstens 8 Skins pro Seite'; end if;
  if cardinality(p_my) + cardinality(p_their) = 0 then raise exception 'mindestens ein Skin'; end if;
  if coalesce(p_my_taler, 0) < 0 or coalesce(p_their_taler, 0) < 0 then raise exception 'ungueltig'; end if;
  if (select count(*) from skins where id = any(p_my) and owner = p_player and not listed) <> cardinality(p_my) then raise exception 'nicht alle Skins sind deine'; end if;
  if (select count(*) from skins where id = any(p_their) and owner = t and not listed) <> cardinality(p_their) then raise exception 'Skin nicht mehr da'; end if;
  if (select count(*) from trades where a = p_player and status = 'offen') >= 10 then raise exception 'hoechstens 10 offene Angebote'; end if;
  insert into trades (a, b, a_skins, b_skins, a_taler, b_taler) values (p_player, t, p_my, p_their, coalesce(p_my_taler, 0), coalesce(p_their_taler, 0))
  returning id into tid;
  insert into inbox (player, kind, from_pub, from_name) values (t, 'trad', me.pub, me.name);
  return tid;
end $$;

create or replace function public.trade_list(p_player text)
returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id, 'mine', t.a = p_player, 'status', t.status, 'created', t.created_at,
    'other', coalesce(case when t.a = p_player then pb.name else pa.name end, 'Spieler'),
    'other_pub', case when t.a = p_player then pb.pub else pa.pub end,
    'give', (select coalesce(jsonb_agg(wl_skin_json(s)), '[]') from skins s where s.id = any(case when t.a = p_player then t.a_skins else t.b_skins end)),
    'get', (select coalesce(jsonb_agg(wl_skin_json(s)), '[]') from skins s where s.id = any(case when t.a = p_player then t.b_skins else t.a_skins end)),
    'give_taler', case when t.a = p_player then t.a_taler else t.b_taler end,
    'get_taler', case when t.a = p_player then t.b_taler else t.a_taler end) order by t.created_at desc), '[]')
  from trades t left join profiles pa on pa.player = t.a left join profiles pb on pb.player = t.b
  where (t.a = p_player or t.b = p_player) and (t.status = 'offen' or t.done_at > now() - interval '7 days');
$$;

-- Annehmen (nur der Empfänger) oder ablehnen/zurückziehen (beide)
create or replace function public.trade_answer(p_player text, p_id bigint, p_accept boolean)
returns text
language plpgsql security definer set search_path = public as $$
declare t trades%rowtype; n int; ap profiles%rowtype; bp profiles%rowtype;
begin
  select * into t from trades where id = p_id and (a = p_player or b = p_player) for update;
  if not found then raise exception 'kein Tausch'; end if;
  if t.status <> 'offen' then return t.status; end if;
  if t.created_at < now() - interval '3 days' then
    update trades set status = 'ungueltig', done_at = now() where id = p_id; return 'ungueltig';
  end if;
  if not p_accept then
    update trades set status = case when p_player = t.a then 'zurueck' else 'nein' end, done_at = now() where id = p_id;
    return case when p_player = t.a then 'zurueck' else 'nein' end;
  end if;
  if p_player <> t.b then raise exception 'nur der Empfaenger kann annehmen'; end if;
  if exists (select 1 from banned where player in (t.a, t.b)) then raise exception 'gesperrt'; end if;
  perform 1 from skins where id = any(t.a_skins || t.b_skins) for update;
  select count(*) into n from skins where id = any(t.a_skins) and owner = t.a and not listed;
  if n <> cardinality(t.a_skins) then update trades set status = 'ungueltig', done_at = now() where id = p_id; return 'ungueltig'; end if;
  select count(*) into n from skins where id = any(t.b_skins) and owner = t.b and not listed;
  if n <> cardinality(t.b_skins) then update trades set status = 'ungueltig', done_at = now() where id = p_id; return 'ungueltig'; end if;
  perform wl_wallet(t.a); perform wl_wallet(t.b);
  if (select bal from wallets where player = t.a) < t.a_taler or (select bal from wallets where player = t.b) < t.b_taler then
    update trades set status = 'ungueltig', done_at = now() where id = p_id; return 'ungueltig';
  end if;
  if t.a_taler > 0 then perform wl_add(t.a, -t.a_taler, 'tausch'); perform wl_add(t.b, t.a_taler, 'tausch'); end if;
  if t.b_taler > 0 then perform wl_add(t.b, -t.b_taler, 'tausch'); perform wl_add(t.a, t.b_taler, 'tausch'); end if;
  update skins set owner = t.b where id = any(t.a_skins);
  update skins set owner = t.a where id = any(t.b_skins);
  update trades set status = 'ok', done_at = now() where id = p_id;
  select * into ap from profiles where player = t.a; select * into bp from profiles where player = t.b;
  insert into inbox (player, kind, from_pub, from_name) values (t.a, 'tok', bp.pub, bp.name);
  return 'ok';
end $$;

-- Alte Einträge aufräumen (läuft nebenbei mit)
create or replace function public.wl_cleanup() returns void
language sql security definer set search_path = public as $$
  delete from taler_log where created_at < now() - interval '90 days';
  delete from trades where status <> 'offen' and done_at < now() - interval '30 days';
  update trades set status = 'ungueltig', done_at = now() where status = 'offen' and created_at < now() - interval '3 days';
  delete from market_sales where created_at < now() - interval '90 days';
$$;
revoke all on function public.wl_cleanup() from public, anon, authenticated;

create or replace function public.taler_daily_cleanup(p_player text)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin perform wl_cleanup(); return taler_daily(p_player); end $$;

grant execute on function
  public.taler_info(text), public.taler_daily(text), public.taler_daily_cleanup(text),
  public.submit_run_v3(text, text, text, int, int, int, text, uuid, int, bigint),
  public.skin_open(text, int), public.skin_list(text), public.skin_pub_list(text, text), public.skin_scrap(text, bigint),
  public.market_sell(text, bigint, int), public.market_cancel(text, bigint),
  public.market_browse(text, int, int, boolean, text, int), public.market_stats(int, int), public.market_buy(text, bigint),
  public.trade_offer(text, text, bigint[], bigint[], int, int), public.trade_list(text), public.trade_answer(text, bigint, boolean)
to anon;


-- ================= supabase-update-10.sql =================
-- Waldlauf Update 10: Trade-up (10 Skins einer Seltenheit gegen 1 Skin der nächsten Stufe)
-- Einmal im Supabase SQL Editor einfügen und auf Run drücken (nach Update 09).

-- Regeln:
-- * genau 10 eigene Skins, alle gleiche Seltenheit (Gewöhnlich bis Legendär), keiner davon im Markt
-- * das neue Tier wird zufällig aus den Tieren der 10 Skins gezogen (je öfter ein Tier dabei ist, desto wahrscheinlicher)
-- * der Glanz ist der Durchschnitt der 10 Skins, leicht gestreut
-- * haben alle 10 einen Zähler, hat auch der neue einen, sonst wie immer 10 %
create or replace function public.skin_tradeup(p_player text, p_skins bigint[])
returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int; r int; r2 int; an int; gl numeric; zt_all boolean; v int; s skins%rowtype;
begin
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  perform wl_wallet(p_player);
  if p_skins is null or cardinality(p_skins) <> 10 then raise exception 'genau 10 Skins'; end if;
  if (select count(distinct x) from unnest(p_skins) x) <> 10 then raise exception 'genau 10 Skins'; end if;
  perform 1 from skins where id = any(p_skins) for update;
  select count(*), min(wl_var_r(variant)), max(wl_var_r(variant)), avg(glanz), bool_and(zt)
    into n, r, r2, gl, zt_all
  from skins where id = any(p_skins) and owner = p_player and not listed;
  if n <> 10 then raise exception 'nicht alle Skins sind frei'; end if;
  if r <> r2 then raise exception 'gleiche Seltenheit noetig'; end if;
  if r >= 4 then raise exception 'Mythisch geht nicht hoeher'; end if;
  select animal into an from skins where id = any(p_skins) order by random() limit 1;
  v := case r + 1
    when 1 then 8 + floor(random() * 6)::int
    when 2 then 14 + floor(random() * 5)::int
    when 3 then 19 + floor(random() * 4)::int
    else 23 + floor(random() * 3)::int end;
  delete from skins where id = any(p_skins);
  insert into skins (owner, animal, variant, seed, glanz, zt, origin)
  values (p_player, an, v, floor(random() * 1000)::int,
          round(greatest(0, least(1, gl + (random() - 0.5) * 0.2))::numeric, 4),
          zt_all or random() < 0.10, 'tradeup')
  returning * into s;
  insert into taler_log (player, delta, reason) values (p_player, 0, 'tradeup ' || (r + 1));
  return wl_skin_json(s);
end $$;

grant execute on function public.skin_tradeup(text, bigint[]) to anon;


-- ================= supabase-update-11.sql =================
-- Waldlauf Update 11: Spielmodi (Tagesstrecke, Duell, Live-Rennen), Skin-Sammelbuch,
-- Skin-Rangliste und Wochen-Belohnungen
-- Einmal im Supabase SQL Editor einfügen und auf Run drücken (nach Update 10).

-- ---------- Tabellen
alter table public.wallets add column if not exists free int not null default 0;

create table if not exists public.daily_runs (
  day        int not null,
  player     text not null references public.profiles(player) on delete cascade,
  meters     int not null,
  coins      int not null default 0,
  animal     int not null default 0,
  created_at timestamptz not null default now(),
  primary key (day, player)
);
create index if not exists daily_runs_top on public.daily_runs (day, meters desc);

create table if not exists public.duels (
  id         bigint generated always as identity primary key,
  a          text not null references public.profiles(player) on delete cascade,
  b          text not null references public.profiles(player) on delete cascade,
  seed       int not null,
  a_s        int[] not null default '{null,null,null}',
  b_s        int[] not null default '{null,null,null}',
  status     text not null default 'offen' check (status in ('offen', 'fertig', 'abgelaufen')),
  winner     text,
  created_at timestamptz not null default now(),
  done_at    timestamptz
);
create index if not exists duels_a on public.duels (a, created_at desc);
create index if not exists duels_b on public.duels (b, created_at desc);

create table if not exists public.live_rooms (
  code       text primary key,
  host       text not null references public.profiles(player) on delete cascade,
  seed       int not null,
  state      text not null default 'warten' check (state in ('warten', 'lauf', 'ende')),
  start_at   timestamptz,
  created_at timestamptz not null default now()
);
create table if not exists public.live_players (
  code       text not null references public.live_rooms(code) on delete cascade,
  player     text not null references public.profiles(player) on delete cascade,
  animal     int not null default 0,
  dist       real not null default 0,
  lane       real not null default 0,
  jh         real not null default 0,
  alive      boolean not null default true,
  upd        timestamptz not null default now(),
  primary key (code, player)
);

create table if not exists public.skin_book (
  player     text not null references public.profiles(player) on delete cascade,
  goal       text not null,
  created_at timestamptz not null default now(),
  primary key (player, goal)
);

create table if not exists public.weekly_claims (
  player     text not null references public.profiles(player) on delete cascade,
  week       date not null,
  place      int not null,
  created_at timestamptz not null default now(),
  primary key (player, week)
);

alter table public.daily_runs    enable row level security;
alter table public.duels         enable row level security;
alter table public.live_rooms    enable row level security;
alter table public.live_players  enable row level security;
alter table public.skin_book     enable row level security;
alter table public.weekly_claims enable row level security;
revoke all on public.daily_runs, public.duels, public.live_rooms, public.live_players, public.skin_book, public.weekly_claims from anon, authenticated;

alter table public.inbox drop constraint if exists inbox_kind_check;
alter table public.inbox add constraint inbox_kind_check check (kind in ('freq', 'facc', 'chal', 'chok', 'refb', 'trad', 'tok', 'mkt', 'duel', 'dueld'));

-- Heutiger Tag in Berlin als Zahl, zum Beispiel 20261013
create or replace function public.wl_today() returns int
language sql stable as $$ select to_char(now() at time zone 'Europe/Berlin', 'YYYYMMDD')::int $$;
revoke all on function public.wl_today() from public, anon, authenticated;

-- ---------- Lauf eintragen mit Spielmodus
-- p_mode: 'day' (p_ref = Tag, z.B. '20261013'), 'duel' (p_ref = Duell-Nummer, p_round 1 bis 3), sonst normal
create or replace function public.submit_run_v4(
  p_player text, p_name text, p_avatar text, p_season int, p_meters int, p_coins int, p_flag text,
  p_token uuid, p_dur int, p_skin bigint default null, p_mode text default null, p_ref text default null,
  p_round int default null, p_animal int default 0)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; d duels%rowtype; m int := least(greatest(p_meters, 0), 100000); wa int; wb int; i int; win text; me profiles%rowtype;
begin
  r := submit_run_v3(p_player, p_name, p_avatar, p_season, p_meters, p_coins, p_flag, p_token, p_dur, p_skin);
  if r->>'status' <> 'ok' then return r; end if;
  if p_mode = 'day' and p_ref = wl_today()::text then
    insert into daily_runs (day, player, meters, coins, animal) values (wl_today(), p_player, m, least(p_coins, 20000), coalesce(p_animal, 0))
    on conflict (day, player) do update set meters = excluded.meters, coins = excluded.coins, animal = excluded.animal, created_at = now()
    where daily_runs.meters < excluded.meters;
  elsif p_mode = 'duel' and p_round between 1 and 3 and p_ref ~ '^[0-9]+$' then
    select * into d from duels where id = p_ref::bigint and status = 'offen' and (a = p_player or b = p_player) for update;
    if found then
      if d.a = p_player and d.a_s[p_round] is null then update duels set a_s[p_round] = m where id = d.id;
      elsif d.b = p_player and d.b_s[p_round] is null then update duels set b_s[p_round] = m where id = d.id; end if;
      select * into d from duels where id = d.id;
      if d.a_s[1] is not null and d.a_s[2] is not null and d.a_s[3] is not null
         and d.b_s[1] is not null and d.b_s[2] is not null and d.b_s[3] is not null then
        wa := 0; wb := 0;
        for i in 1..3 loop
          if d.a_s[i] > d.b_s[i] then wa := wa + 1; elsif d.b_s[i] > d.a_s[i] then wb := wb + 1; end if;
        end loop;
        win := case when wa > wb then d.a when wb > wa then d.b else null end;
        update duels set status = 'fertig', winner = win, done_at = now() where id = d.id;
        if win is not null then perform wl_wallet(win); perform wl_add(win, 300, 'duell'); end if;
        select * into me from profiles where player = p_player;
        insert into inbox (player, kind, from_pub, from_name, note)
        values (case when d.a = p_player then d.b else d.a end, 'dueld', me.pub, me.name,
                case when win is null then 'unentschieden' when win = p_player then 'verloren' else 'gewonnen' end);
      end if;
      r := r || jsonb_build_object('duel', d.id);
    end if;
  end if;
  return r;
end $$;

-- ---------- Tagesstrecke
create or replace function public.daily_top(p_player text)
returns jsonb
language sql security definer set search_path = public stable as $$
  with x as (
    select row_number() over (order by d.meters desc, d.created_at) as place, d.player, d.meters, d.animal
    from daily_runs d where d.day = wl_today() and d.player not in (select player from banned)
  )
  select jsonb_build_object('day', wl_today(), 'n', (select count(*) from x),
    'top', coalesce((select jsonb_agg(jsonb_build_object('place', x.place, 'name', coalesce(p.name, 'Spieler'), 'avatar', coalesce(p.avatar, '🦊'),
             'flag', coalesce(p.flag, ''), 'meters', x.meters, 'animal', x.animal, 'me', x.player = p_player) order by x.place)
             from x left join profiles p on p.player = x.player where x.place <= 20 or x.player = p_player), '[]'));
$$;

-- ---------- Duell (Best of 3 auf derselben Strecke)
create or replace function public.duel_create(p_player text, p_pub text)
returns bigint
language plpgsql security definer set search_path = public as $$
declare t text; id bigint; me profiles%rowtype;
begin
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  select * into me from profiles where player = p_player;
  if not found then raise exception 'kein profil'; end if;
  select player into t from profiles where pub = p_pub;
  if t is null or t = p_player then raise exception 'unbekannt'; end if;
  if not exists (select 1 from friends where status = 'accepted' and ((a = p_player and b = t) or (a = t and b = p_player))) then
    raise exception 'nur mit Freunden';
  end if;
  if (select count(*) from duels where a = p_player and status = 'offen') >= 10 then raise exception 'hoechstens 10 offene Duelle'; end if;
  insert into duels (a, b, seed) values (p_player, t, floor(random() * 1000000)::int) returning duels.id into id;
  insert into inbox (player, kind, from_pub, from_name) values (t, 'duel', me.pub, me.name);
  return id;
end $$;

create or replace function public.duel_list(p_player text)
returns jsonb
language sql security definer set search_path = public as $$
  update duels set status = 'abgelaufen', done_at = now() where status = 'offen' and created_at < now() - interval '7 days' and (a = p_player or b = p_player);
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d.id, 'seed', d.seed, 'status', d.status, 'created', d.created_at,
    'other', coalesce(case when d.a = p_player then pb.name else pa.name end, 'Spieler'),
    'other_pub', case when d.a = p_player then pb.pub else pa.pub end,
    'mine', case when d.a = p_player then d.a_s else d.b_s end,
    'theirs', case when d.status = 'offen' then (select array_agg(case when x is null then null else -1 end) from unnest(case when d.a = p_player then d.b_s else d.a_s end) x)
                   else case when d.a = p_player then d.b_s else d.a_s end end,
    'won', case when d.winner is null then null else d.winner = p_player end) order by d.created_at desc), '[]')
  from duels d left join profiles pa on pa.player = d.a left join profiles pb on pb.player = d.b
  where (d.a = p_player or d.b = p_player) and (d.status = 'offen' or d.done_at > now() - interval '14 days');
$$;

-- ---------- Live-Rennen (bis zu 4 Spieler, gleiche Strecke, gleichzeitiger Start)
create or replace function public.live_create(p_player text, p_animal int)
returns text
language plpgsql security definer set search_path = public as $$
declare c text; n int := 0;
begin
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  if not exists (select 1 from profiles where player = p_player) then raise exception 'kein profil'; end if;
  delete from live_rooms where created_at < now() - interval '2 hours';
  delete from live_players where player = p_player;
  loop
    c := upper(substr(md5(random()::text), 1, 5));
    c := translate(c, '0O1I', 'XYZW');
    exit when not exists (select 1 from live_rooms where code = c);
    n := n + 1; if n > 20 then raise exception 'kein Code frei'; end if;
  end loop;
  insert into live_rooms (code, host, seed) values (c, p_player, floor(random() * 1000000)::int);
  insert into live_players (code, player, animal) values (c, p_player, coalesce(p_animal, 0));
  return c;
end $$;

create or replace function public.live_join(p_player text, p_code text, p_animal int)
returns text
language plpgsql security definer set search_path = public as $$
declare r live_rooms%rowtype;
begin
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  if not exists (select 1 from profiles where player = p_player) then raise exception 'kein profil'; end if;
  select * into r from live_rooms where code = upper(trim(p_code)) for update;
  if not found then raise exception 'Raum nicht gefunden'; end if;
  if r.state <> 'warten' then raise exception 'Rennen laeuft schon'; end if;
  if not exists (select 1 from live_players where code = r.code and player = p_player) then
    if (select count(*) from live_players where code = r.code) >= 4 then raise exception 'Raum ist voll'; end if;
    delete from live_players where player = p_player;
    insert into live_players (code, player, animal) values (r.code, p_player, coalesce(p_animal, 0));
  end if;
  return r.code;
end $$;

create or replace function public.live_start(p_player text, p_code text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update live_rooms set state = 'lauf', start_at = now() + interval '5 seconds'
  where code = upper(p_code) and host = p_player and state = 'warten';
  if not found then raise exception 'nur der Gastgeber kann starten'; end if;
  update live_players set dist = 0, lane = 0, jh = 0, alive = true, upd = now() where code = upper(p_code);
end $$;

create or replace function public.live_leave(p_player text, p_code text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from live_players where code = upper(p_code) and player = p_player;
  delete from live_rooms where code = upper(p_code) and not exists (select 1 from live_players where code = upper(p_code));
end $$;

-- Eigene Position melden und alle anderen abholen (wird im Rennen etwa zweimal pro Sekunde aufgerufen)
create or replace function public.live_tick(p_player text, p_code text, p_dist real, p_lane real, p_jh real, p_alive boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare r live_rooms%rowtype;
begin
  select * into r from live_rooms where code = upper(p_code);
  if not found then raise exception 'Raum nicht gefunden'; end if;
  if r.state = 'lauf' and now() >= r.start_at then
    update live_players set dist = greatest(dist, least(p_dist, extract(epoch from (now() - r.start_at)) * 40 + 30)),
      lane = greatest(-1, least(1, p_lane)), jh = greatest(0, least(3, p_jh)), alive = alive and p_alive, upd = now()
    where code = r.code and player = p_player;
    if not exists (select 1 from live_players where code = r.code and alive and upd > now() - interval '20 seconds') then
      update live_rooms set state = 'ende' where code = r.code;
      r.state := 'ende';
    end if;
  else
    update live_players set upd = now() where code = r.code and player = p_player;
  end if;
  return jsonb_build_object('state', r.state, 'seed', r.seed, 'host', r.host = p_player, 'code', r.code,
    'start_in', case when r.start_at is null then null else round(extract(epoch from (r.start_at - now())) * 1000) end,
    'players', (select coalesce(jsonb_agg(jsonb_build_object('pub', p.pub, 'name', coalesce(p.name, 'Spieler'), 'animal', l.animal,
               'dist', l.dist, 'lane', l.lane, 'jh', l.jh, 'alive', l.alive and l.upd > now() - interval '20 seconds', 'me', l.player = p_player)
               order by l.dist desc), '[]') from live_players l left join profiles p on p.player = l.player where l.code = r.code));
end $$;

-- ---------- Skin-Sammelbuch
create or replace function public.skin_book_list(p_player text)
returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(goal), '[]') from skin_book where player = p_player;
$$;

create or replace function public.skin_book_claim(p_player text, p_goal text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare ok boolean := false; val int; b bigint;
begin
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  perform wl_wallet(p_player);
  if exists (select 1 from skin_book where player = p_player and goal = p_goal) then raise exception 'schon abgeholt'; end if;
  val := case p_goal when 'first' then 200 when 'sel10' then 400 when 'epic' then 300 when 'leg' then 800 when 'myth' then 2500
    when 'gold3' then 1000 when 'all0' then 600 when 'all1' then 1200 when 'all2' then 2500 when 'zt3' then 500
    when 'ani5' then 700 when 'proto' then 1500 when 'zoo' then 1500 when 'ev' then 800 else null end;
  if val is null then raise exception 'unbekanntes Ziel'; end if;
  ok := case p_goal
    when 'first' then (select count(*) >= 5 from skins where owner = p_player)
    when 'sel10' then (select count(*) >= 10 from skins where owner = p_player and wl_var_r(variant) = 1)
    when 'epic'  then exists (select 1 from skins where owner = p_player and wl_var_r(variant) = 2)
    when 'leg'   then exists (select 1 from skins where owner = p_player and wl_var_r(variant) = 3)
    when 'myth'  then exists (select 1 from skins where owner = p_player and wl_var_r(variant) = 4)
    when 'gold3' then (select count(*) >= 3 from skins where owner = p_player and variant = 19)
    when 'all0'  then (select count(distinct variant) = 8 from skins where owner = p_player and variant between 0 and 7)
    when 'all1'  then (select count(distinct variant) = 6 from skins where owner = p_player and variant between 8 and 13)
    when 'all2'  then (select count(distinct variant) = 5 from skins where owner = p_player and variant between 14 and 18)
    when 'zt3'   then (select count(*) >= 3 from skins where owner = p_player and zt)
    when 'ani5'  then exists (select 1 from skins where owner = p_player group by animal having count(distinct variant) >= 5)
    when 'proto' then exists (select 1 from skins where owner = p_player and (seed < 5 or seed = 777))
    when 'zoo'   then (select count(distinct animal) >= 20 from skins where owner = p_player)
    when 'ev'    then exists (select 1 from skins where owner = p_player and variant >= 26)
    else false end;
  if not ok then raise exception 'Ziel noch nicht erreicht'; end if;
  insert into skin_book (player, goal) values (p_player, p_goal);
  b := wl_add(p_player, val, 'sammelbuch');
  return jsonb_build_object('got', val, 'bal', b);
end $$;

-- Skin-Rangliste: Sammelwert = Summe der Recycling-Werte aller Skins
create or replace function public.skin_top(p_player text)
returns jsonb
language sql security definer set search_path = public stable as $$
  with v as (
    select owner, sum(wl_scrap_val(variant, zt)) as val, count(*) as n from skins
    where owner not in (select player from banned) group by owner
  ), x as (select row_number() over (order by val desc, n desc) as place, owner, val, n from v)
  select coalesce(jsonb_agg(jsonb_build_object('place', x.place, 'name', coalesce(p.name, 'Spieler'), 'avatar', coalesce(p.avatar, '🦊'),
         'flag', coalesce(p.flag, ''), 'val', x.val, 'n', x.n, 'me', x.owner = p_player) order by x.place), '[]')
  from x left join profiles p on p.player = x.owner where x.place <= 30 or x.owner = p_player;
$$;

-- ---------- Wochen-Belohnungen für die beste Läufe der letzten Woche (Montag bis Sonntag, Berliner Zeit)
-- p_take = false: nur nachsehen, true: abholen
create or replace function public.weekly_claim(p_player text, p_take boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare wk date := (date_trunc('week', now() at time zone 'Europe/Berlin') - interval '7 days')::date;
  t0 timestamptz; t1 timestamptz; pl int; cr int; tl int; b bigint;
begin
  t0 := (wk::timestamp) at time zone 'Europe/Berlin'; t1 := ((wk + 7)::timestamp) at time zone 'Europe/Berlin';
  if exists (select 1 from weekly_claims where player = p_player and week = wk) then
    return jsonb_build_object('week', wk, 'claimed', true);
  end if;
  with bst as (select player, max(meters) m from runs where created_at >= t0 and created_at < t1 and player not in (select player from banned) group by player),
       x as (select player, rank() over (order by m desc) as place from bst)
  select place into pl from x where player = p_player;
  if pl is null or pl > 100 then return jsonb_build_object('week', wk, 'place', pl, 'crates', 0, 'taler', 0); end if;
  cr := case when pl = 1 then 5 when pl <= 3 then 4 when pl <= 10 then 3 when pl <= 50 then 2 else 1 end;
  tl := case when pl = 1 then 2000 when pl <= 3 then 1000 when pl <= 10 then 500 else 0 end;
  if not p_take then return jsonb_build_object('week', wk, 'place', pl, 'crates', cr, 'taler', tl, 'claimed', false); end if;
  perform wl_wallet(p_player);
  insert into weekly_claims (player, week, place) values (p_player, wk, pl);
  update wallets set free = free + cr where player = p_player;
  b := case when tl > 0 then wl_add(p_player, tl, 'woche') else (select bal from wallets where player = p_player) end;
  return jsonb_build_object('week', wk, 'place', pl, 'crates', cr, 'taler', tl, 'claimed', true, 'bal', b);
end $$;

-- Kontostand jetzt mit Gratis-Kisten
create or replace function public.taler_info(p_player text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare w wallets%rowtype; today date := (now() at time zone 'Europe/Berlin')::date;
begin
  w := wl_wallet(p_player);
  return jsonb_build_object('bal', w.bal, 'day_run', w.day_run, 'cap', 800, 'daily', w.last_daily is distinct from today,
    'event', wl_event(), 'free', w.free,
    'trades_in', (select count(*) from trades where b = p_player and status = 'offen'),
    'duels', (select count(*) from duels where status = 'offen' and ((a = p_player and a_s[3] is null) or (b = p_player and b_s[3] is null))));
end $$;

-- Skin-Kiste öffnen. 0 = normale Kiste (600), 1 = Event-Kiste (900), 2 = Gratis-Kiste aus der Wochen-Belohnung
create or replace function public.skin_open(p_player text, p_crate int)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare w wallets%rowtype; ev text := wl_event(); price int; x numeric; rr int; v int; s skins%rowtype; b bigint;
begin
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  if p_crate not in (0, 1, 2) then raise exception 'unbekannte Kiste'; end if;
  if p_crate = 1 and ev is null then raise exception 'gerade kein Event'; end if;
  if (select count(*) from skins where owner = p_player) >= 500 then raise exception 'Inventar voll'; end if;
  w := wl_wallet(p_player);
  if p_crate = 2 then
    if w.free < 1 then raise exception 'keine Gratis-Kiste'; end if;
    update wallets set free = free - 1 where player = p_player;
    b := w.bal;
  else
    price := case when p_crate = 0 then 600 else 900 end;
    b := wl_add(p_player, -price, 'kiste');
  end if;
  x := random() * 100;
  if p_crate <> 1 then
    rr := case when x < 70 then 0 when x < 90 then 1 when x < 97 then 2 when x < 99.5 then 3 else 4 end;
  else
    rr := case when x < 55 then 1 when x < 85 then 2 when x < 97 then 3 else 4 end;
  end if;
  v := case rr
    when 0 then 0 + floor(random() * 8)::int
    when 1 then 8 + floor(random() * 6)::int
    when 2 then 14 + floor(random() * 5)::int
    when 3 then 19 + floor(random() * 4)::int
    else 23 + floor(random() * 3)::int end;
  if p_crate = 1 and rr in (2, 3) and random() < 0.5 then
    v := case ev when 'hw' then 26 when 'wi' then 28 else 30 end + (rr - 2);
  end if;
  insert into skins (owner, animal, variant, seed, glanz, zt, origin)
  values (p_player, floor(random() * 36)::int, v, floor(random() * 1000)::int, round(random()::numeric, 4),
          random() < 0.10, case when p_crate = 1 then 'event-' || ev when p_crate = 2 then 'woche' else 'kiste' end)
  returning * into s;
  return wl_skin_json(s) || jsonb_build_object('bal', b, 'free', (select free from wallets where player = p_player));
end $$;

grant execute on function
  public.submit_run_v4(text, text, text, int, int, int, text, uuid, int, bigint, text, text, int, int),
  public.daily_top(text), public.duel_create(text, text), public.duel_list(text),
  public.live_create(text, int), public.live_join(text, text, int), public.live_start(text, text), public.live_leave(text, text),
  public.live_tick(text, text, real, real, real, boolean),
  public.skin_book_list(text), public.skin_book_claim(text, text), public.skin_top(text), public.weekly_claim(text, boolean),
  public.taler_info(text), public.skin_open(text, int)
to anon;

-- ---------- Profil-Schaufenster: Info-Text und bis zu 4 ausgestellte Skins
alter table public.profiles add column if not exists bio text not null default '' check (char_length(bio) <= 120);
alter table public.profiles add column if not exists showcase bigint[] not null default '{}';

create or replace function public.profile_set_card(p_player text, p_bio text, p_skins bigint[])
returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not exists (select 1 from profiles where player = p_player) then raise exception 'kein profil'; end if;
  p_skins := coalesce(p_skins, '{}');
  if cardinality(p_skins) > 4 then raise exception 'hoechstens 4 Skins'; end if;
  select count(*) into n from skins where id = any(p_skins) and owner = p_player;
  if n <> cardinality(p_skins) then raise exception 'nicht alle Skins sind deine'; end if;
  update profiles set bio = left(regexp_replace(coalesce(p_bio, ''), '[\r\n\t]+', ' ', 'g'), 120), showcase = p_skins
  where player = p_player;
end $$;

create or replace function public.profile_view(p_player text, p_pub text)
returns jsonb
language sql security definer set search_path = public stable as $$
  select jsonb_build_object('bio', p.bio,
    'showcase', (select coalesce(jsonb_agg(wl_skin_json(s) order by array_position(p.showcase, s.id)), '[]') from skins s where s.id = any(p.showcase) and s.owner = p.player),
    'skins', (select count(*) from skins where owner = p.player),
    'val', (select coalesce(sum(wl_scrap_val(variant, zt)), 0) from skins where owner = p.player),
    'clan', (select c.tag from clan_members m join clans c on c.id = m.clan where m.player = p.player limit 1),
    'daily', (select meters from daily_runs where day = wl_today() and player = p.player),
    'me', p.player = p_player)
  from profiles p where p.pub = p_pub;
$$;

grant execute on function public.profile_set_card(text, text, bigint[]), public.profile_view(text, text) to anon;


-- ================= supabase-update-12.sql =================
-- Waldlauf Update 12: Weltchat mit Live-Drops
-- Einmal im Supabase SQL Editor einfügen und auf Run drücken (nach Update 11).

create table if not exists public.chat (
  id         bigint generated always as identity primary key,
  player     text references public.profiles(player) on delete cascade,
  kind       text not null default 'msg' check (kind in ('msg', 'drop')),
  text       text not null default '' check (char_length(text) <= 140),
  data       jsonb,
  hidden     boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists chat_time on public.chat (created_at desc);
create index if not exists chat_player on public.chat (player, created_at desc);

create table if not exists public.chat_reports (
  msg        bigint not null references public.chat(id) on delete cascade,
  player     text not null references public.profiles(player) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (msg, player)
);

alter table public.chat         enable row level security;
alter table public.chat_reports enable row level security;
revoke all on public.chat, public.chat_reports from anon, authenticated;

-- Einfacher Wortfilter: Schimpfwörter werden zu Sternchen, Links werden entfernt
create or replace function public.wl_clean(t text) returns text
language plpgsql immutable as $$
declare w text; r text := t;
begin
  r := regexp_replace(r, '[\r\n\t]+', ' ', 'g');
  r := regexp_replace(r, '(https?://|www\.)\S+', '[Link entfernt]', 'gi');
  r := regexp_replace(r, '\S+\.(com|de|net|org|io|gg|xyz|ru|tk)(/\S*)?', '[Link entfernt]', 'gi');
  foreach w in array array['arschloch','hurensohn','hure','fotze','wichser','missgeburt','spast','spasti','behindert','schlampe','nutte','fick','ficken','fuck','fucking','shit','bitch','cunt','nigger','neger','nazi','hitler','schwuchtel','kanake','vergewaltig'] loop
    r := regexp_replace(r, '(?i)' || w, repeat('*', char_length(w)), 'g');
  end loop;
  return trim(r);
end $$;
revoke all on function public.wl_clean(text) from public, anon, authenticated;

-- Nachricht schicken: höchstens eine alle 3 Sekunden und 15 pro Minute
create or replace function public.chat_send(p_player text, p_text text)
returns bigint
language plpgsql security definer set search_path = public as $$
declare t text := left(coalesce(p_text, ''), 140); id bigint; n int;
begin
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  if not exists (select 1 from profiles where player = p_player) then raise exception 'kein profil'; end if;
  t := wl_clean(t);
  if char_length(t) < 1 then raise exception 'leer'; end if;
  if exists (select 1 from chat where player = p_player and kind = 'msg' and created_at > now() - interval '3 seconds') then raise exception 'zu schnell'; end if;
  select count(*) into n from chat where player = p_player and kind = 'msg' and created_at > now() - interval '1 minute';
  if n >= 15 then raise exception 'zu schnell'; end if;
  -- Zehnmal hintereinander dieselbe Nachricht geht nicht
  if exists (select 1 from chat where player = p_player and kind = 'msg' and text = t and created_at > now() - interval '30 seconds') then raise exception 'doppelt'; end if;
  insert into chat (player, kind, text) values (p_player, 'msg', t) returning chat.id into id;
  delete from chat where created_at < now() - interval '3 days';
  return id;
end $$;

-- Neue Einträge abholen. p_after = höchste bekannte Nummer (0 = die letzten 60)
create or replace function public.chat_list(p_player text, p_after bigint default 0)
returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(x.j order by x.id), '[]') from (
    select c.id, jsonb_build_object('id', c.id, 'kind', c.kind, 'text', c.text, 'data', c.data, 't', c.created_at,
      'pub', p.pub, 'name', coalesce(p.name, 'Spieler'), 'avatar', coalesce(p.avatar, '🦊'), 'flag', coalesce(p.flag, ''),
      'me', c.player = p_player) as j
    from chat c left join profiles p on p.player = c.player
    where not c.hidden and c.id > coalesce(p_after, 0) and c.created_at > now() - interval '3 days'
      and (c.player is null or c.player not in (select player from banned))
    order by c.id desc limit 60
  ) x;
$$;

-- Nachricht melden. Ab 3 Meldungen von verschiedenen Spielern wird sie ausgeblendet.
create or replace function public.chat_report(p_player text, p_msg bigint)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from profiles where player = p_player) then raise exception 'kein profil'; end if;
  insert into chat_reports (msg, player) values (p_msg, p_player) on conflict do nothing;
  update chat set hidden = true where id = p_msg and (select count(*) from chat_reports where msg = p_msg) >= 3;
end $$;

-- Live-Drops: Jeder epische, legendäre oder mythische Skin aus Kisten und Trade-ups landet automatisch im Chat
create or replace function public.wl_drop_post() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if wl_var_r(new.variant) >= 2 and (new.origin like 'kiste%' or new.origin like 'event-%' or new.origin in ('woche', 'tradeup')) then
    insert into chat (player, kind, data) values (new.owner, 'drop', jsonb_build_object(
      'animal', new.animal, 'variant', new.variant, 'seed', new.seed, 'glanz', new.glanz, 'zt', new.zt, 'skin', new.id, 'origin', new.origin));
  end if;
  return new;
end $$;
drop trigger if exists skins_drop_post on public.skins;
create trigger skins_drop_post after insert on public.skins for each row execute function public.wl_drop_post();

grant execute on function public.chat_send(text, text), public.chat_list(text, bigint), public.chat_report(text, bigint) to anon;

-- ---------- Rangliste zeigt jetzt immer den aktuellen Namen, Avatar und die Flagge aus dem Profil
-- (vorher stand dort der Name vom Zeitpunkt des besten Laufs, oft noch „Spieler“)
create or replace function public.leaderboard(p_season int, p_limit int default 50, p_player text default '')
returns table (name text, avatar text, flag text, best int, place bigint, is_me boolean, pub text, pfr int, afr int, lvl int)
language sql security definer set search_path = public stable as $$
  with b as (
    select distinct on (player) player, name, avatar, flag, meters as best
    from runs where season = p_season and player not in (select player from banned)
    order by player, meters desc, created_at desc
  )
  select coalesce(p.name, b.name), coalesce(p.avatar, b.avatar), coalesce(p.flag, b.flag), b.best,
         rank() over (order by b.best desc) as place, (b.player = p_player) as is_me,
         wl_pub(b.player) as pub, coalesce(p.pfr, 0), coalesce(p.afr, 0), coalesce(p.lvl, 1)
  from b left join profiles p on p.player = b.player
  order by b.best desc limit least(greatest(p_limit, 1), 100);
$$;
grant execute on function public.leaderboard(int, int, text) to anon;

-- ---------- Profilansicht liefert jetzt auch Name, Avatar, Bestweite und Level
-- (damit man Profile auch aus dem Chat heraus vollständig ansehen kann)
create or replace function public.profile_view(p_player text, p_pub text)
returns jsonb
language sql security definer set search_path = public stable as $$
  select jsonb_build_object('bio', p.bio, 'name', p.name, 'avatar', p.avatar, 'flag', p.flag, 'pfr', p.pfr, 'afr', p.afr, 'lvl', p.lvl,
    'best', (select max(meters) from runs where player = p.player and season = (select max(season) from runs)),
    'showcase', (select coalesce(jsonb_agg(wl_skin_json(s) order by array_position(p.showcase, s.id)), '[]') from skins s where s.id = any(p.showcase) and s.owner = p.player),
    'skins', (select count(*) from skins where owner = p.player),
    'val', (select coalesce(sum(wl_scrap_val(variant, zt)), 0) from skins where owner = p.player),
    'clan', (select c.tag from clan_members m join clans c on c.id = m.clan where m.player = p.player limit 1),
    'daily', (select meters from daily_runs where day = wl_today() and player = p.player),
    'me', p.player = p_player)
  from profiles p where p.pub = p_pub;
$$;
grant execute on function public.profile_view(text, text) to anon;


-- ================= supabase-update-13.sql =================
-- Waldlauf Update 13: Jeder Skin merkt sich für immer, wer ihn gezogen hat
-- Einmal im Supabase SQL Editor einfügen und auf Run drücken (nach Update 12).

alter table public.skins add column if not exists finder text;          -- wer ihn gezogen hat (bleibt für immer)
alter table public.skins add column if not exists finder_name text;     -- Name zum Zeitpunkt des Ziehens (falls das Profil gelöscht wird)
alter table public.skins add column if not exists moves int not null default 0;  -- wie oft er den Besitzer gewechselt hat

-- Bereits vorhandene Skins: der jetzige Besitzer gilt als Finder
update public.skins s set finder = s.owner, finder_name = coalesce(p.name, 'Spieler')
from public.profiles p where p.player = s.owner and s.finder is null;
update public.skins set finder = owner where finder is null;

-- Neue Skins: Finder automatisch eintragen, Besitzerwechsel automatisch zählen
create or replace function public.wl_skin_stamp() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.finder := coalesce(new.finder, new.owner);
    new.finder_name := coalesce(new.finder_name, (select name from profiles where player = new.owner), 'Spieler');
    new.moves := 0;
  elsif new.owner <> old.owner then
    new.moves := old.moves + 1;
    new.finder := old.finder;
    new.finder_name := old.finder_name;
  else
    new.finder := old.finder;
    new.finder_name := old.finder_name;
    new.moves := old.moves;
  end if;
  return new;
end $$;
drop trigger if exists skins_stamp on public.skins;
create trigger skins_stamp before insert or update on public.skins for each row execute function public.wl_skin_stamp();

-- Skin-Daten jetzt mit Finder (aktueller Name, sonst der gemerkte) und Anzahl der Besitzerwechsel
create or replace function public.wl_skin_json(s public.skins) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', s.id, 'animal', s.animal, 'variant', s.variant, 'seed', s.seed, 'glanz', s.glanz,
    'zt', s.zt, 'zm', s.zm, 'origin', s.origin, 'listed', s.listed, 'created', s.created_at, 'moves', s.moves,
    'finder', coalesce((select name from profiles where player = s.finder), s.finder_name, 'Spieler'),
    'finder_pub', (select pub from profiles where player = s.finder))
$$;
revoke all on function public.wl_skin_json(public.skins) from public, anon, authenticated;

-- ---------- Eigene Profilbilder, DEV-Wappen und Rahmen im Chat
alter table public.profiles add column if not exists img text check (img is null or char_length(img) <= 24000);
alter table public.profiles add column if not exists img_block boolean not null default false;
alter table public.profiles add column if not exists dev boolean not null default false;

create table if not exists public.img_reports (
  pub        text not null,
  player     text not null references public.profiles(player) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (pub, player)
);
alter table public.img_reports enable row level security;
revoke all on public.img_reports from anon, authenticated;

-- Eigenes Bild hochladen (kleines JPEG oder WebP, höchstens etwa 18 KB). p_img = null löscht das Bild.
create or replace function public.profile_set_img(p_player text, p_img text)
returns void
language plpgsql security definer set search_path = public as $$
declare pr profiles%rowtype;
begin
  select * into pr from profiles where player = p_player;
  if not found then raise exception 'kein profil'; end if;
  if p_img is null then update profiles set img = null where player = p_player; return; end if;
  if pr.img_block then raise exception 'Bild gesperrt'; end if;
  if char_length(p_img) > 24000 then raise exception 'Bild zu gross'; end if;
  if p_img !~ '^data:image/(jpeg|webp|png);base64,[A-Za-z0-9+/=]+$' then raise exception 'kein Bild'; end if;
  update profiles set img = p_img where player = p_player;
  delete from img_reports where pub = pr.pub;
end $$;

-- Bilder für mehrere Spieler auf einmal holen
create or replace function public.avatar_imgs(p_pubs text[])
returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_object_agg(pub, img), '{}') from (
    select pub, img from profiles where pub = any(p_pubs[1:60]) and img is not null and not img_block
  ) x;
$$;

-- Bild melden. Ab 3 Meldungen verschwindet es und der Spieler kann kein neues mehr hochladen.
create or replace function public.avatar_report(p_player text, p_pub text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from profiles where player = p_player) then raise exception 'kein profil'; end if;
  insert into img_reports (pub, player) values (p_pub, p_player) on conflict do nothing;
  if (select count(*) from img_reports where pub = p_pub) >= 3 then
    update profiles set img = null, img_block = true where pub = p_pub;
  end if;
end $$;

-- Wer das DEV-Wappen tragen darf (wird nur von dir im SQL Editor gesetzt, siehe ANLEITUNG.md)
create or replace function public.dev_list()
returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(pub), '[]') from profiles where dev;
$$;

-- Chat jetzt mit Profil- und Avatarrahmen
create or replace function public.chat_list(p_player text, p_after bigint default 0)
returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(x.j order by x.id), '[]') from (
    select c.id, jsonb_build_object('id', c.id, 'kind', c.kind, 'text', c.text, 'data', c.data, 't', c.created_at,
      'pub', p.pub, 'name', coalesce(p.name, 'Spieler'), 'avatar', coalesce(p.avatar, '🦊'), 'flag', coalesce(p.flag, ''),
      'pfr', coalesce(p.pfr, 0), 'afr', coalesce(p.afr, 0), 'me', c.player = p_player) as j
    from chat c left join profiles p on p.player = c.player
    where not c.hidden and c.id > coalesce(p_after, 0) and c.created_at > now() - interval '3 days'
      and (c.player is null or c.player not in (select player from banned))
    order by c.id desc limit 60
  ) x;
$$;

grant execute on function public.profile_set_img(text, text), public.avatar_imgs(text[]), public.avatar_report(text, text), public.dev_list(), public.chat_list(text, bigint) to anon;

-- Profilansicht sagt jetzt auch, ob es ein eigenes Bild gibt (für „Bild melden“)
create or replace function public.profile_view(p_player text, p_pub text)
returns jsonb
language sql security definer set search_path = public stable as $$
  select jsonb_build_object('bio', p.bio, 'name', p.name, 'avatar', p.avatar, 'flag', p.flag, 'pfr', p.pfr, 'afr', p.afr, 'lvl', p.lvl,
    'img', p.img is not null and not p.img_block, 'dev', p.dev,
    'best', (select max(meters) from runs where player = p.player and season = (select max(season) from runs)),
    'showcase', (select coalesce(jsonb_agg(wl_skin_json(s) order by array_position(p.showcase, s.id)), '[]') from skins s where s.id = any(p.showcase) and s.owner = p.player),
    'skins', (select count(*) from skins where owner = p.player),
    'val', (select coalesce(sum(wl_scrap_val(variant, zt)), 0) from skins where owner = p.player),
    'clan', (select c.tag from clan_members m join clans c on c.id = m.clan where m.player = p.player limit 1),
    'daily', (select meters from daily_runs where day = wl_today() and player = p.player),
    'me', p.player = p_player)
  from profiles p where p.pub = p_pub;
$$;
grant execute on function public.profile_view(text, text) to anon;

-- ===== Update 14: Erweiterungen (DLC) =====
-- Waldlauf Update 14: Erweiterungen (DLC) mit Waldtalern kaufen
-- Einmal im Supabase SQL Editor einfügen und auf Run drücken (nach Update 13).

create table if not exists public.dlc_owned (
  player     text not null references public.profiles(player) on delete cascade,
  dlc        text not null,
  created_at timestamptz not null default now(),
  primary key (player, dlc)
);
alter table public.dlc_owned enable row level security;
revoke all on public.dlc_owned from anon, authenticated;

-- Preise der Erweiterungen (nur hier auf dem Server, damit niemand sie ändern kann)
create or replace function public.wl_dlc_price(p_dlc text) returns int
language sql immutable as $$
  select case p_dlc when 'dino' then 20000 else null end
$$;
revoke all on function public.wl_dlc_price(text) from public, anon, authenticated;

-- Erweiterung kaufen: zieht die Waldtaler ab und schaltet sie für immer frei
create or replace function public.dlc_buy(p_player text, p_dlc text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare price int := wl_dlc_price(p_dlc); w wallets%rowtype; b bigint;
begin
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  if price is null then raise exception 'unbekannte Erweiterung'; end if;
  w := wl_wallet(p_player);
  if exists (select 1 from dlc_owned where player = p_player and dlc = p_dlc) then raise exception 'schon gekauft'; end if;
  b := wl_add(p_player, -price, 'dlc ' || p_dlc);
  insert into dlc_owned (player, dlc) values (p_player, p_dlc);
  return jsonb_build_object('dlc', p_dlc, 'bal', b);
end $$;

-- Welche Erweiterungen gehören mir? (auch für ein neues Gerät)
create or replace function public.dlc_list(p_player text)
returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(dlc order by created_at), '[]') from dlc_owned where player = p_player;
$$;

grant execute on function public.dlc_buy(text, text), public.dlc_list(text) to anon;

-- ===== Update 15: Benachrichtigungen =====
-- ===== Waldlauf Update 15: Benachrichtigungen (Web-Push) =====
-- Spieler können sich erinnern lassen: Tagesbonus, Markt/Tausch, Freunde.
-- Verschickt werden die Nachrichten von der Edge Function "push-send".

create table if not exists public.push_subs (
  endpoint   text primary key check (char_length(endpoint) between 20 and 1000),
  player     text not null references public.profiles(player) on delete cascade,
  sub        jsonb not null,
  prefs      jsonb not null default '{"bonus":true,"handel":true,"freunde":true}',
  fails      int not null default 0,
  created_at timestamptz not null default now(),
  last_ok    timestamptz
);
create index if not exists push_subs_player on public.push_subs (player);

create table if not exists public.push_queue (
  id         bigint generated always as identity primary key,
  player     text not null,
  kind       text not null check (kind in ('bonus','handel','freunde')),
  title      text not null,
  body       text not null,
  created_at timestamptz not null default now(),
  sent_at    timestamptz
);
create index if not exists push_queue_open on public.push_queue (id) where sent_at is null;
create index if not exists push_queue_player on public.push_queue (player, created_at desc);

-- Schlüsselpaar für Web-Push. Wird von der Edge Function beim ersten Aufruf selbst erzeugt.
create table if not exists public.push_vapid (
  id   int primary key default 1 check (id = 1),
  pub  text not null,
  priv text not null
);

alter table public.push_subs  enable row level security;
alter table public.push_queue enable row level security;
alter table public.push_vapid enable row level security;
revoke all on public.push_subs, public.push_queue, public.push_vapid from anon, authenticated;

-- Öffentlicher Schlüssel für das Spiel (der private bleibt in der Datenbank)
create or replace function public.push_key() returns text
language sql security definer set search_path = public stable as $$
  select pub from push_vapid where id = 1;
$$;

create or replace function public.push_sub(p_player text, p_sub jsonb, p_prefs jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ep text := p_sub->>'endpoint'; pr jsonb;
begin
  if not exists (select 1 from profiles where player = p_player) then raise exception 'unbekannt'; end if;
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  if ep is null or ep !~ '^https://' or char_length(ep) > 1000 or p_sub->'keys'->>'p256dh' is null or p_sub->'keys'->>'auth' is null then raise exception 'ungueltig'; end if;
  pr := jsonb_build_object('bonus', coalesce((p_prefs->>'bonus')::boolean, true),
                           'handel', coalesce((p_prefs->>'handel')::boolean, true),
                           'freunde', coalesce((p_prefs->>'freunde')::boolean, true));
  -- höchstens 5 Geräte pro Spieler
  delete from push_subs where player = p_player and endpoint <> ep and endpoint not in
    (select endpoint from push_subs where player = p_player and endpoint <> ep order by created_at desc limit 4);
  insert into push_subs (endpoint, player, sub, prefs) values (ep, p_player, p_sub, pr)
  on conflict (endpoint) do update set player = excluded.player, sub = excluded.sub, prefs = excluded.prefs, fails = 0;
  return pr;
end $$;

create or replace function public.push_unsub(p_player text, p_endpoint text) returns void
language sql security definer set search_path = public as $$
  delete from push_subs where player = p_player and endpoint = p_endpoint;
$$;

-- Nachricht in die Warteschlange (nur wenn der Spieler Push hat; gleiche Nachricht höchstens alle 6 Stunden)
create or replace function public.push_add(p_player text, p_kind text, p_title text, p_body text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from push_subs where player = p_player and coalesce((prefs->>p_kind)::boolean, true)) then return; end if;
  if exists (select 1 from push_queue where player = p_player and kind = p_kind and title = left(p_title, 80) and body = left(p_body, 200) and created_at > now() - interval '6 hours') then return; end if;
  if (select count(*) from push_queue where player = p_player and created_at > now() - interval '1 day') >= 12 then return; end if;
  insert into push_queue (player, kind, title, body) values (p_player, p_kind, left(p_title, 80), left(p_body, 200));
end $$;

-- Markt: Skin verkauft
create or replace function public.push_tg_taler() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.reason = 'markt-verkauf' then
    perform push_add(new.player, 'handel', '🏪 Dein Skin wurde verkauft!', 'Du hast ' || replace(to_char(new.delta, 'FM999,999,999'), ',', '.') || ' Waldtaler bekommen. Schau im Skin-Shop vorbei.');
  end if;
  return null;
exception when others then return null;
end $$;
drop trigger if exists push_taler on public.taler_log;
create trigger push_taler after insert on public.taler_log for each row execute function public.push_tg_taler();

-- Tausch: neues Angebot
create or replace function public.push_tg_trade() returns trigger
language plpgsql security definer set search_path = public as $$
declare nm text;
begin
  if new.status = 'offen' then
    select name into nm from profiles where player = new.a;
    perform push_add(new.b, 'handel', '🔄 Neues Tauschangebot', coalesce(nm, 'Jemand') || ' möchte mit dir Skins tauschen.');
  end if;
  return null;
exception when others then return null;
end $$;
drop trigger if exists push_trade on public.trades;
create trigger push_trade after insert on public.trades for each row execute function public.push_tg_trade();

-- Freunde: Anfrage
create or replace function public.push_tg_inbox() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind = 'freq' then
    perform push_add(new.player, 'freunde', '👋 Freundschaftsanfrage', new.from_name || ' möchte mit dir befreundet sein.');
  elsif new.kind = 'facc' then
    perform push_add(new.player, 'freunde', '🤝 Neuer Freund', new.from_name || ' hat deine Anfrage angenommen.');
  end if;
  return null;
exception when others then return null;
end $$;
drop trigger if exists push_inbox on public.inbox;
create trigger push_inbox after insert on public.inbox for each row execute function public.push_tg_inbox();

-- Freunde: Bestweite überholt (nur wenn man vorher dahinter lag)
create or replace function public.push_tg_run() returns trigger
language plpgsql security definer set search_path = public as $$
declare prev int; f record;
begin
  if new.meters < 300 then return null; end if;
  select coalesce(max(meters), 0) into prev from runs where season = new.season and player = new.player and id <> new.id;
  if new.meters <= prev then return null; end if;
  for f in
    select x.fr, (select max(meters) from runs r where r.season = new.season and r.player = x.fr) as best
    from (select case when a = new.player then b else a end as fr from friends
          where status = 'accepted' and (a = new.player or b = new.player) limit 100) x
  loop
    if f.best is not null and f.best >= 100 and prev <= f.best and new.meters > f.best then
      perform push_add(f.fr, 'freunde', '🏃 ' || new.name || ' hat dich überholt!',
        new.name || ' ist ' || replace(to_char(new.meters, 'FM999,999,999'), ',', '.') || ' m gelaufen, deine Bestweite sind ' || replace(to_char(f.best, 'FM999,999,999'), ',', '.') || ' m. Hol sie dir zurück!');
    end if;
  end loop;
  return null;
exception when others then return null;
end $$;
drop trigger if exists push_run on public.runs;
create trigger push_run after insert on public.runs for each row execute function public.push_tg_run();

-- Täglich: Tagesbonus wartet (für alle, die ihn heute noch nicht abgeholt haben)
create or replace function public.push_daily() returns int
language plpgsql security definer set search_path = public as $$
declare n int := 0; p record; d date := (now() at time zone 'Europe/Berlin')::date;
begin
  for p in select distinct s.player from push_subs s left join wallets w on w.player = s.player
           where coalesce((s.prefs->>'bonus')::boolean, true) and (w.last_daily is null or w.last_daily < d)
  loop
    perform push_add(p.player, 'bonus', '🎁 Dein Tagesbonus wartet!', '60 Waldtaler liegen für dich bereit. Und vielleicht knackst du heute deine Bestweite? 🦊');
    n := n + 1;
  end loop;
  delete from push_queue where created_at < now() - interval '14 days';
  return n;
end $$;

revoke execute on function public.push_add(text, text, text, text), public.push_daily(),
  public.push_tg_taler(), public.push_tg_trade(), public.push_tg_inbox(), public.push_tg_run() from public, anon, authenticated;
grant execute on function public.push_key(), public.push_sub(text, jsonb, jsonb), public.push_unsub(text, text) to anon;

-- Zeitpläne (pg_cron + pg_net). Jede Minute verschickt die Edge Function die Warteschlange,
-- jeden Tag um 18 Uhr (Sommerzeit, im Winter 17 Uhr) kommt die Tagesbonus-Erinnerung.
do $do$
begin
  create extension if not exists pg_cron;
  create extension if not exists pg_net with schema extensions;
  perform cron.unschedule(jobid) from cron.job where jobname in ('waldlauf-push-send', 'waldlauf-push-daily');
  perform cron.schedule('waldlauf-push-send', '* * * * *', $job$
    select net.http_post(
      url := 'https://jvupgazchuggeizfdvcl.supabase.co/functions/v1/push-send',
      headers := jsonb_build_object('Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp2dXBnYXpjaHVnZ2VpemZkdmNsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE4MzY0ODksImV4cCI6MjEwNzQxMjQ4OX0.abBB7jlgNrOm0oRgPMGPJ2tLvT0_VUlm6K26RD69bLw'),
      body := '{}'::jsonb)
    where exists (select 1 from public.push_queue where sent_at is null)
       or not exists (select 1 from public.push_vapid);
  $job$);
  perform cron.schedule('waldlauf-push-daily', '0 16 * * *', 'select public.push_daily()');
exception when others then
  raise notice 'Zeitpläne nicht angelegt (pg_cron/pg_net fehlen?): %', sqlerrm;
end $do$;

-- ===== Update 16: Einmal-Codes =====
-- ===== Waldlauf Update 16: Einmal-Codes für Erweiterungen (z. B. zum Verlosen) =====
-- Im Spiel unter Einstellungen → Code einlösen. Jeder Code funktioniert genau einmal.
-- In der Datenbank steht nur ein Fingerabdruck (Hash) des Codes, nie der Code selbst.

create table if not exists public.dlc_codes (
  code_hash  text primary key,
  dlc        text not null,
  note       text not null default '',
  used_by    text,
  used_at    timestamptz,
  created_at timestamptz not null default now()
);
alter table public.dlc_codes enable row level security;
revoke all on public.dlc_codes from anon, authenticated;

create or replace function public.dlc_redeem(p_player text, p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h text; r record; c text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
begin
  if not exists (select 1 from profiles where player = p_player) then raise exception 'unbekannt'; end if;
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  if char_length(c) < 8 or char_length(c) > 40 then raise exception 'ungueltig'; end if;
  h := encode(sha256(convert_to('waldlauf-dlc:' || c, 'UTF8')), 'hex');
  select * into r from dlc_codes where code_hash = h for update;
  if not found then raise exception 'ungueltig'; end if;
  if r.used_by is not null then
    if r.used_by = p_player then return jsonb_build_object('dlc', r.dlc, 'again', true); end if;
    raise exception 'benutzt';
  end if;
  if exists (select 1 from dlc_owned where player = p_player and dlc = r.dlc) then raise exception 'schon gekauft'; end if;
  update dlc_codes set used_by = p_player, used_at = now() where code_hash = h;
  insert into dlc_owned (player, dlc) values (p_player, r.dlc) on conflict do nothing;
  return jsonb_build_object('dlc', r.dlc);
end $$;

grant execute on function public.dlc_redeem(text, text) to anon;

-- Neuen Code anlegen (Beispiel, Code bitte selbst ausdenken oder von Claude erzeugen lassen):
-- insert into dlc_codes (code_hash, dlc, note)
-- values (encode(sha256(convert_to('waldlauf-dlc:' || 'MEINCODE1234', 'UTF8')), 'hex'), 'dino', 'Verlosung');
-- Prüfen, ob ein Code schon benutzt wurde:
-- select note, used_by is not null as benutzt, used_at from dlc_codes;

-- ===== Update 17: Statistik und Dino-Rangliste =====
-- ===== Waldlauf Update 17: Anonyme Statistik + Dino-Wochenrangliste =====

-- ---------- Statistik (nur Zahlen, keine Namen; sehen kann sie nur ein Entwickler-Profil)
create table if not exists public.pstats (
  player    text primary key,
  first_day date not null,
  last_day  date not null,
  days      int not null default 1,
  runs      int not null default 0,
  best      int not null default 0
);
create index if not exists pstats_first on public.pstats (first_day);
create index if not exists pstats_last on public.pstats (last_day);
create table if not exists public.stat_day (
  day date not null,
  k   text not null,
  n   bigint not null default 0,
  primary key (day, k)
);
alter table public.pstats   enable row level security;
alter table public.stat_day enable row level security;
revoke all on public.pstats, public.stat_day from anon, authenticated;

create or replace function public.stat_inc(p_day date, p_k text, p_n bigint) returns void
language sql security definer set search_path = public as $$
  insert into stat_day (day, k, n) values (p_day, left(p_k, 40), p_n)
  on conflict (day, k) do update set n = stat_day.n + excluded.n;
$$;

create or replace function public.stat_hit(p_player text, p_kind text, p_world int, p_animal int, p_mode text, p_meters int, p_plat text) returns void
language plpgsql security definer set search_path = public as $$
declare d date := (now() at time zone 'Europe/Berlin')::date; o pstats%rowtype; fresh boolean := false; newday boolean := false; m int := greatest(0, least(coalesce(p_meters, 0), 100000));
begin
  if p_player is null or char_length(p_player) not between 8 and 64 then return; end if;
  if p_kind not in ('open', 'run') then return; end if;
  select * into o from pstats where player = p_player for update;
  if not found then
    insert into pstats (player, first_day, last_day) values (p_player, d, d) on conflict do nothing;
    fresh := true; newday := true;
  elsif o.last_day < d then
    update pstats set last_day = d, days = days + 1 where player = p_player;
    newday := true;
  end if;
  if fresh then perform stat_inc(d, 'new', 1); end if;
  if newday then
    perform stat_inc(d, 'dau', 1);
    perform stat_inc(d, 'p_' || coalesce(nullif(regexp_replace(coalesce(p_plat, ''), '[^a-z-]', '', 'g'), ''), 'x'), 1);
    if not fresh and o.last_day = d - 1 then perform stat_inc(d, 'back1', 1); end if;
  end if;
  if p_kind = 'run' then
    if (select n from stat_day where day = d and k = 'runs') > 200000 then return; end if;
    update pstats set runs = runs + 1, best = greatest(best, m) where player = p_player;
    perform stat_inc(d, 'runs', 1);
    perform stat_inc(d, 'msum', m);
    if p_world between 0 and 40 then perform stat_inc(d, 'w' || p_world, 1); end if;
    if p_animal between 0 and 99 then perform stat_inc(d, 'a' || p_animal, 1); end if;
    perform stat_inc(d, 'm_' || coalesce(nullif(regexp_replace(coalesce(p_mode, ''), '[^a-z]', '', 'g'), ''), 'n'), 1);
  end if;
end $$;

create or replace function public.stats_overview(p_player text) returns jsonb
language plpgsql security definer set search_path = public stable as $$
declare d date := (now() at time zone 'Europe/Berlin')::date;
begin
  if not exists (select 1 from profiles where player = p_player and dev) then raise exception 'nur entwickler'; end if;
  return jsonb_build_object(
    'days', (select coalesce(jsonb_agg(x order by x.day), '[]') from (
        select g.day::date as day,
          coalesce((select n from stat_day s where s.day = g.day and k = 'dau'), 0) as dau,
          coalesce((select n from stat_day s where s.day = g.day and k = 'new'), 0) as new,
          coalesce((select n from stat_day s where s.day = g.day and k = 'runs'), 0) as runs,
          coalesce((select n from stat_day s where s.day = g.day and k = 'back1'), 0) as back1,
          coalesce((select n from stat_day s where s.day = g.day and k = 'msum'), 0) as msum
        from generate_series(d - 13, d, interval '1 day') g(day)) x),
    'total', (select count(*) from pstats),
    'active7', (select count(*) from pstats where last_day >= d - 6),
    'returning', (select count(*) from pstats where days >= 2),
    'ret_new14', (select jsonb_build_object('n', count(*), 'back', count(*) filter (where days >= 2)) from pstats where first_day between d - 14 and d - 1),
    'avg_runs', (select round(avg(runs)::numeric, 1) from pstats where runs > 0),
    'worlds', (select coalesce(jsonb_object_agg(k, n), '{}') from (select k, sum(n) n from stat_day where day >= d - 6 and k ~ '^w[0-9]+$' group by k) x),
    'animals', (select coalesce(jsonb_object_agg(k, n), '{}') from (select k, sum(n) n from stat_day where day >= d - 6 and k ~ '^a[0-9]+$' group by k order by 2 desc limit 12) x),
    'modes', (select coalesce(jsonb_object_agg(k, n), '{}') from (select k, sum(n) n from stat_day where day >= d - 6 and k like 'm\_%' group by k) x),
    'plats', (select coalesce(jsonb_object_agg(k, n), '{}') from (select k, sum(n) n from stat_day where day >= d - 6 and k like 'p\_%' group by k) x),
    'dino_owners', (select count(*) from dlc_owned where dlc = 'dino'),
    'push_users', (select count(distinct player) from push_subs)
  );
end $$;

-- ---------- Dino-Wochenrangliste
create table if not exists public.dino_runs (
  token      uuid primary key,
  player     text not null,
  week       date not null,
  meters     int not null,
  created_at timestamptz not null default now()
);
create index if not exists dino_runs_week on public.dino_runs (week, meters desc);
create table if not exists public.dino_claims (
  player text not null,
  week   date not null,
  place  int not null,
  taler  int not null,
  created_at timestamptz not null default now(),
  primary key (player, week)
);
alter table public.dino_runs   enable row level security;
alter table public.dino_claims enable row level security;
revoke all on public.dino_runs, public.dino_claims from anon, authenticated;

create or replace function public.dino_week(p_at timestamptz) returns date
language sql immutable as $$ select date_trunc('week', p_at at time zone 'Europe/Berlin')::date $$;

create or replace function public.dino_submit(p_player text, p_token uuid, p_meters int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t0 timestamptz; secs numeric; w date := dino_week(now()); best int; rk int;
begin
  if not exists (select 1 from dlc_owned where player = p_player and dlc = 'dino') then raise exception 'kein dlc'; end if;
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  select created_at into t0 from run_tokens where token = p_token and player = p_player;
  if not found then raise exception 'token'; end if;
  secs := extract(epoch from now() - t0);
  if secs > 3 * 3600 then raise exception 'token'; end if;
  if p_meters < 1 or p_meters > secs * 32 + 50 then raise exception 'zu schnell'; end if;
  insert into dino_runs (token, player, week, meters) values (p_token, p_player, w, least(p_meters, 100000)) on conflict do nothing;
  select max(meters) into best from dino_runs where player = p_player and week = w;
  select 1 + count(*) into rk from (select player, max(meters) m from dino_runs where week = w group by player) x where x.m > best;
  return jsonb_build_object('best', best, 'rank', rk);
end $$;

create or replace function public.dino_top(p_player text) returns jsonb
language sql security definer set search_path = public stable as $$
  with w as (select dino_week(now()) as wk),
  b as (select r.player, max(r.meters) m from dino_runs r, w where r.week = w.wk group by r.player),
  rk as (select b.player, b.m, rank() over (order by b.m desc) as place from b)
  select jsonb_build_object(
    'week', (select wk from w),
    'top', coalesce((select jsonb_agg(jsonb_build_object('place', rk.place, 'name', p.name, 'pub', p.pub, 'flag', p.flag, 'm', rk.m, 'me', rk.player = p_player) order by rk.place)
                     from rk join profiles p on p.player = rk.player where rk.place <= 10), '[]'),
    'me', (select jsonb_build_object('place', place, 'm', m) from rk where player = p_player));
$$;

-- Preise für die letzte Woche abholen: Platz 1: 3.000, Platz 2: 1.500, Platz 3: 750 Waldtaler
create or replace function public.dino_claim(p_player text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare lw date := dino_week(now()) - 7; pl int; tl int; b bigint;
begin
  if exists (select 1 from dino_claims where player = p_player and week = lw) then return jsonb_build_object('taler', 0); end if;
  select place into pl from (select player, rank() over (order by max(meters) desc) place from dino_runs where week = lw group by player) x where x.player = p_player;
  if pl is null or pl > 3 then return jsonb_build_object('taler', 0); end if;
  tl := case pl when 1 then 3000 when 2 then 1500 else 750 end;
  insert into dino_claims (player, week, place, taler) values (p_player, lw, pl, tl);
  perform wl_wallet(p_player);
  b := wl_add(p_player, tl, 'dino-woche');
  delete from dino_runs where week < lw - 28;
  return jsonb_build_object('taler', tl, 'place', pl, 'bal', b);
end $$;

revoke execute on function public.stat_inc(date, text, bigint) from public, anon, authenticated;
grant execute on function public.stat_hit(text, text, int, int, text, int, text), public.stats_overview(text),
  public.dino_submit(text, uuid, int), public.dino_top(text), public.dino_claim(text) to anon;

-- ---------- Beim Löschen eines Profils (Einstellungen → Konto löschen) auch die neuen Daten entfernen
create or replace function public.wl_del_extra() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from pstats where player = old.player;
  delete from dino_runs where player = old.player;
  delete from dino_claims where player = old.player;
  delete from push_queue where player = old.player;
  delete from dlc_owned where player = old.player;
  return null;
exception when others then return null;
end $$;
drop trigger if exists wl_del_extra on public.profiles;
create trigger wl_del_extra after delete on public.profiles for each row execute function public.wl_del_extra();

