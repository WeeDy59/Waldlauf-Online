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
