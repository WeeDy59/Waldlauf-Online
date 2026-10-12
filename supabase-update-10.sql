-- Waldlauf Update 10: Trade-up (10 Skins einer Seltenheit gegen 1 Skin der nächsten Stufe)
-- Einmal im Supabase SQL Editor einfügen und auf Run drücken (nach Update 09).

-- Regeln:
-- * genau 10 eigene Skins, alle gleiche Seltenheit (Gewöhnlich bis Legendär), keiner davon im Markt
-- * das neue Tier wird zufällig aus den Tieren der 10 Skins gezogen (je öfter ein Tier dabei ist, desto wahrscheinlicher)
-- * der Glanz ist der Durchschnitt der 10 Skins, leicht gestreut
-- * haben alle 10 einen Zähler, hat auch der neue einen, sonst wie immer 10 %
create or replace function public.skin_tradeup(p_player text, p_skins bigint[])
returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int; r int; r2 int; an int; gl numeric; zt_all boolean; v int; s skins%rowtype;
begin
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  perform wl_wallet(p_player);
  if p_skins is null or cardinality(p_skins) <> 10 then raise exception 'genau 10 Skins'; end if;
  if (select count(distinct x) from unnest(p_skins) x) <> 10 then raise exception 'genau 10 Skins'; end if;
  perform 1 from skins where id = any(p_skins) for update;
  select count(*), min(wl_var_r(variant)), max(wl_var_r(variant)), avg(glanz), bool_and(zt)
    into n, r, r2, gl, zt_all
  from skins where id = any(p_skins) and owner = p_player and not listed;
  if n <> 10 then raise exception 'nicht alle Skins sind frei'; end if;
  if r <> r2 then raise exception 'gleiche Seltenheit noetig'; end if;
  if r >= 4 then raise exception 'Mythisch geht nicht hoeher'; end if;
  select animal into an from skins where id = any(p_skins) order by random() limit 1;
  v := case r + 1
    when 1 then 8 + floor(random() * 6)::int
    when 2 then 14 + floor(random() * 5)::int
    when 3 then 19 + floor(random() * 4)::int
    else 23 + floor(random() * 3)::int end;
  delete from skins where id = any(p_skins);
  insert into skins (owner, animal, variant, seed, glanz, zt, origin)
  values (p_player, an, v, floor(random() * 1000)::int,
          round(greatest(0, least(1, gl + (random() - 0.5) * 0.2))::numeric, 4),
          zt_all or random() < 0.10, 'tradeup')
  returning * into s;
  insert into taler_log (player, delta, reason) values (p_player, 0, 'tradeup ' || (r + 1));
  return wl_skin_json(s);
end $$;

grant execute on function public.skin_tradeup(text, bigint[]) to anon;
