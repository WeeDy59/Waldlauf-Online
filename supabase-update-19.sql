-- ===== Waldlauf Update 19: Alpha-Tester-Codes =====
-- Jeder Code funktioniert genau einmal und pro Spieler nur einmal.
-- Belohnung: beide Erweiterungen, 10.000 Waldtaler und das Alpha-Wappen (Münzen, Rahmen und Anstecker gibt das Spiel selbst).
-- In der Datenbank steht nur ein Fingerabdruck (Hash) der Codes, nie die Codes selbst.

alter table public.profiles add column if not exists alpha boolean not null default false;

create table if not exists public.tester_codes (
  code_hash  text primary key,
  note       text not null default '',
  used_by    text,
  used_at    timestamptz,
  created_at timestamptz not null default now()
);
alter table public.tester_codes enable row level security;
revoke all on public.tester_codes from anon, authenticated;

create or replace function public.tester_redeem(p_player text, p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h text; r record; b bigint; c text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
begin
  if not exists (select 1 from profiles where player = p_player) then raise exception 'unbekannt'; end if;
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  if char_length(c) < 8 or char_length(c) > 40 then raise exception 'ungueltig'; end if;
  h := encode(sha256(convert_to('waldlauf-alpha:' || c, 'UTF8')), 'hex');
  select * into r from tester_codes where code_hash = h for update;
  if not found then raise exception 'ungueltig'; end if;
  if r.used_by is not null then
    if r.used_by = p_player then return jsonb_build_object('again', true); end if;
    raise exception 'benutzt';
  end if;
  if exists (select 1 from profiles where player = p_player and alpha) then raise exception 'schon alpha'; end if;
  update tester_codes set used_by = p_player, used_at = now() where code_hash = h;
  update profiles set alpha = true where player = p_player;
  insert into dlc_owned (player, dlc) values (p_player, 'dino') on conflict do nothing;
  insert into dlc_owned (player, dlc) values (p_player, 'sea') on conflict do nothing;
  perform wl_wallet(p_player);
  b := wl_add(p_player, 10000, 'alpha tester');
  return jsonb_build_object('ok', true, 'bal', b);
end $$;

create or replace function public.alpha_list() returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(pub), '[]') from profiles where alpha;
$$;

grant execute on function public.tester_redeem(text, text), public.alpha_list() to anon;

insert into public.tester_codes (code_hash, note) values
  ('d83fb57c3f98ff824bff761e73fe833da1a8d49049d630b19b631a13ee7702c0', 'Tester 01'),
  ('0df19dce33d5b9c9717905e1aa12a877743362af61b5c0cf7ef460f9ece47654', 'Tester 02'),
  ('8f77bae421d37634ba48dbb71fc74f5f461e274fbfc5ac63b539c7858ac03a53', 'Tester 03'),
  ('0b56bc1b5e29b3539a1e6d7d0e3c1a3a3cdc7c3ead1cc55cb99b705ea479f53f', 'Tester 04'),
  ('9a371675facc277f234855701c18597e0392b949c404f32174376d5ecb8e30dd', 'Tester 05'),
  ('cd0add2510eb431e7446191d1d4fe749d4a2f123ce3b917d29469039419d0b66', 'Tester 06'),
  ('f73e90e46f71238597afba0359a1989ea68c971d12d1ed5980f9b3bb806bf11c', 'Tester 07'),
  ('f42622f868d3318b42e41d4bdb5aae9d26f352d98ee0891328081df809a949b7', 'Tester 08'),
  ('7c56d7711af0913d29b28ab4d059d6d4a64206ed601cb2ef4dde923985230764', 'Tester 09'),
  ('9305fd7d34a87cada2ce75b68412937c2b9513a3432afeebca745f90a7fe5dc2', 'Tester 10'),
  ('193d07d0027e952dde71f29fc6059205663290dc065a697756e5a0d440424ec4', 'Tester 11'),
  ('be62a2a46c60be057ac2582c85c46f2ec776c610c630575d33080b56fb819a0d', 'Tester 12'),
  ('216ad9a1b0aa7f77d22c8b0c8498f5b04c4f178d2341a685264bf62b4db7a86f', 'Tester 13'),
  ('46bb5d6083d77c42c53efecdaeae0232df67c8f152b8c0a6d68f356b07683381', 'Tester 14'),
  ('a2edb5d9b8275bd6b29098b400305f51e1111739acb63ac6238020853510c1cd', 'Tester 15'),
  ('4b8b52a8cab3ca49db2bbcad5e39ce9bdd7e1b61e1fbf37bfc0cbaf2913e9260', 'Tester 16'),
  ('3b11c715bbbeb645b076a5856bc2cbc2ebedf1a223d3a283c996326f03be45e6', 'Tester 17'),
  ('5951b4ad4609c3b33520db1740be0192c5a548d9cbeb15495d4dc0008324db06', 'Tester 18'),
  ('55ea5c9b666e2fa8c551a2c8b53c34896d32b399b8f5ab4eb1a20ee03c7303e2', 'Tester 19'),
  ('72ee50b266dee6618508f3b918279f3e49eede8f30883dbc4e86e87a1b7193b0', 'Tester 20')
on conflict do nothing;

select 'fertig' as status, count(*) as codes from public.tester_codes;
