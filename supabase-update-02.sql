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
