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
