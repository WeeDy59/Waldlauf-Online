-- ===== Waldlauf Update 16: Einmal-Codes für Erweiterungen (z. B. zum Verlosen) =====
-- Im Spiel unter Einstellungen → Code einlösen. Jeder Code funktioniert genau einmal.
-- In der Datenbank steht nur ein Fingerabdruck (Hash) des Codes, nie der Code selbst.

create table if not exists public.dlc_codes (
  code_hash  text primary key,
  dlc        text not null,
  note       text not null default '',
  used_by    text,
  used_at    timestamptz,
  created_at timestamptz not null default now()
);
alter table public.dlc_codes enable row level security;
revoke all on public.dlc_codes from anon, authenticated;

create or replace function public.dlc_redeem(p_player text, p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h text; r record; c text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
begin
  if not exists (select 1 from profiles where player = p_player) then raise exception 'unbekannt'; end if;
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  if char_length(c) < 8 or char_length(c) > 40 then raise exception 'ungueltig'; end if;
  h := encode(sha256(convert_to('waldlauf-dlc:' || c, 'UTF8')), 'hex');
  select * into r from dlc_codes where code_hash = h for update;
  if not found then raise exception 'ungueltig'; end if;
  if r.used_by is not null then
    if r.used_by = p_player then return jsonb_build_object('dlc', r.dlc, 'again', true); end if;
    raise exception 'benutzt';
  end if;
  if exists (select 1 from dlc_owned where player = p_player and dlc = r.dlc) then raise exception 'schon gekauft'; end if;
  update dlc_codes set used_by = p_player, used_at = now() where code_hash = h;
  insert into dlc_owned (player, dlc) values (p_player, r.dlc) on conflict do nothing;
  return jsonb_build_object('dlc', r.dlc);
end $$;

grant execute on function public.dlc_redeem(text, text) to anon;

-- Neuen Code anlegen (Beispiel, Code bitte selbst ausdenken oder von Claude erzeugen lassen):
-- insert into dlc_codes (code_hash, dlc, note)
-- values (encode(sha256(convert_to('waldlauf-dlc:' || 'MEINCODE1234', 'UTF8')), 'hex'), 'dino', 'Verlosung');
-- Prüfen, ob ein Code schon benutzt wurde:
-- select note, used_by is not null as benutzt, used_at from dlc_codes;
