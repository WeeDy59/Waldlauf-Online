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
