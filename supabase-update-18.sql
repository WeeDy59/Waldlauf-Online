-- ===== Waldlauf Update 18: Erweiterung „Tiefsee“ =====
-- Schaltet den Kauf der zweiten Erweiterung frei (Preis: 20.000 Waldtaler).
create or replace function public.wl_dlc_price(p_dlc text) returns int
language sql immutable as $$
  select case p_dlc when 'dino' then 20000 when 'sea' then 20000 else null end
$$;
revoke all on function public.wl_dlc_price(text) from public, anon, authenticated;

select 'fertig' as status, public.wl_dlc_price('sea') as preis_tiefsee;
