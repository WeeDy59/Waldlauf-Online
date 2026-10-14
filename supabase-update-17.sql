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
