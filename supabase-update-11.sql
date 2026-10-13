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
