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
