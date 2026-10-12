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
