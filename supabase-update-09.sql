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
alter table public.inbox add constraint inbox_kind_check check (kind in ('freq', 'facc', 'chal', 'chok', 'refb', 'trad', 'tok', 'mkt'));

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
