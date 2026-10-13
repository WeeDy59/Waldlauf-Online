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
