-- ===== Waldlauf Update 15: Benachrichtigungen (Web-Push) =====
-- Spieler können sich erinnern lassen: Tagesbonus, Markt/Tausch, Freunde.
-- Verschickt werden die Nachrichten von der Edge Function "push-send".

create table if not exists public.push_subs (
  endpoint   text primary key check (char_length(endpoint) between 20 and 1000),
  player     text not null references public.profiles(player) on delete cascade,
  sub        jsonb not null,
  prefs      jsonb not null default '{"bonus":true,"handel":true,"freunde":true}',
  fails      int not null default 0,
  created_at timestamptz not null default now(),
  last_ok    timestamptz
);
create index if not exists push_subs_player on public.push_subs (player);

create table if not exists public.push_queue (
  id         bigint generated always as identity primary key,
  player     text not null,
  kind       text not null check (kind in ('bonus','handel','freunde')),
  title      text not null,
  body       text not null,
  created_at timestamptz not null default now(),
  sent_at    timestamptz
);
create index if not exists push_queue_open on public.push_queue (id) where sent_at is null;
create index if not exists push_queue_player on public.push_queue (player, created_at desc);

-- Schlüsselpaar für Web-Push. Wird von der Edge Function beim ersten Aufruf selbst erzeugt.
create table if not exists public.push_vapid (
  id   int primary key default 1 check (id = 1),
  pub  text not null,
  priv text not null
);

alter table public.push_subs  enable row level security;
alter table public.push_queue enable row level security;
alter table public.push_vapid enable row level security;
revoke all on public.push_subs, public.push_queue, public.push_vapid from anon, authenticated;

-- Öffentlicher Schlüssel für das Spiel (der private bleibt in der Datenbank)
create or replace function public.push_key() returns text
language sql security definer set search_path = public stable as $$
  select pub from push_vapid where id = 1;
$$;

create or replace function public.push_sub(p_player text, p_sub jsonb, p_prefs jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ep text := p_sub->>'endpoint'; pr jsonb;
begin
  if not exists (select 1 from profiles where player = p_player) then raise exception 'unbekannt'; end if;
  if exists (select 1 from banned where player = p_player) then raise exception 'gesperrt'; end if;
  if ep is null or ep !~ '^https://' or char_length(ep) > 1000 or p_sub->'keys'->>'p256dh' is null or p_sub->'keys'->>'auth' is null then raise exception 'ungueltig'; end if;
  pr := jsonb_build_object('bonus', coalesce((p_prefs->>'bonus')::boolean, true),
                           'handel', coalesce((p_prefs->>'handel')::boolean, true),
                           'freunde', coalesce((p_prefs->>'freunde')::boolean, true));
  -- höchstens 5 Geräte pro Spieler
  delete from push_subs where player = p_player and endpoint <> ep and endpoint not in
    (select endpoint from push_subs where player = p_player and endpoint <> ep order by created_at desc limit 4);
  insert into push_subs (endpoint, player, sub, prefs) values (ep, p_player, p_sub, pr)
  on conflict (endpoint) do update set player = excluded.player, sub = excluded.sub, prefs = excluded.prefs, fails = 0;
  return pr;
end $$;

create or replace function public.push_unsub(p_player text, p_endpoint text) returns void
language sql security definer set search_path = public as $$
  delete from push_subs where player = p_player and endpoint = p_endpoint;
$$;

-- Nachricht in die Warteschlange (nur wenn der Spieler Push hat; gleiche Nachricht höchstens alle 6 Stunden)
create or replace function public.push_add(p_player text, p_kind text, p_title text, p_body text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from push_subs where player = p_player and coalesce((prefs->>p_kind)::boolean, true)) then return; end if;
  if exists (select 1 from push_queue where player = p_player and kind = p_kind and title = left(p_title, 80) and body = left(p_body, 200) and created_at > now() - interval '6 hours') then return; end if;
  if (select count(*) from push_queue where player = p_player and created_at > now() - interval '1 day') >= 12 then return; end if;
  insert into push_queue (player, kind, title, body) values (p_player, p_kind, left(p_title, 80), left(p_body, 200));
end $$;

-- Markt: Skin verkauft
create or replace function public.push_tg_taler() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.reason = 'markt-verkauf' then
    perform push_add(new.player, 'handel', '🏪 Dein Skin wurde verkauft!', 'Du hast ' || replace(to_char(new.delta, 'FM999,999,999'), ',', '.') || ' Waldtaler bekommen. Schau im Skin-Shop vorbei.');
  end if;
  return null;
exception when others then return null;
end $$;
drop trigger if exists push_taler on public.taler_log;
create trigger push_taler after insert on public.taler_log for each row execute function public.push_tg_taler();

-- Tausch: neues Angebot
create or replace function public.push_tg_trade() returns trigger
language plpgsql security definer set search_path = public as $$
declare nm text;
begin
  if new.status = 'offen' then
    select name into nm from profiles where player = new.a;
    perform push_add(new.b, 'handel', '🔄 Neues Tauschangebot', coalesce(nm, 'Jemand') || ' möchte mit dir Skins tauschen.');
  end if;
  return null;
exception when others then return null;
end $$;
drop trigger if exists push_trade on public.trades;
create trigger push_trade after insert on public.trades for each row execute function public.push_tg_trade();

-- Freunde: Anfrage
create or replace function public.push_tg_inbox() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind = 'freq' then
    perform push_add(new.player, 'freunde', '👋 Freundschaftsanfrage', new.from_name || ' möchte mit dir befreundet sein.');
  elsif new.kind = 'facc' then
    perform push_add(new.player, 'freunde', '🤝 Neuer Freund', new.from_name || ' hat deine Anfrage angenommen.');
  end if;
  return null;
exception when others then return null;
end $$;
drop trigger if exists push_inbox on public.inbox;
create trigger push_inbox after insert on public.inbox for each row execute function public.push_tg_inbox();

-- Freunde: Bestweite überholt (nur wenn man vorher dahinter lag)
create or replace function public.push_tg_run() returns trigger
language plpgsql security definer set search_path = public as $$
declare prev int; f record;
begin
  if new.meters < 300 then return null; end if;
  select coalesce(max(meters), 0) into prev from runs where season = new.season and player = new.player and id <> new.id;
  if new.meters <= prev then return null; end if;
  for f in
    select x.fr, (select max(meters) from runs r where r.season = new.season and r.player = x.fr) as best
    from (select case when a = new.player then b else a end as fr from friends
          where status = 'accepted' and (a = new.player or b = new.player) limit 100) x
  loop
    if f.best is not null and f.best >= 100 and prev <= f.best and new.meters > f.best then
      perform push_add(f.fr, 'freunde', '🏃 ' || new.name || ' hat dich überholt!',
        new.name || ' ist ' || replace(to_char(new.meters, 'FM999,999,999'), ',', '.') || ' m gelaufen, deine Bestweite sind ' || replace(to_char(f.best, 'FM999,999,999'), ',', '.') || ' m. Hol sie dir zurück!');
    end if;
  end loop;
  return null;
exception when others then return null;
end $$;
drop trigger if exists push_run on public.runs;
create trigger push_run after insert on public.runs for each row execute function public.push_tg_run();

-- Täglich: Tagesbonus wartet (für alle, die ihn heute noch nicht abgeholt haben)
create or replace function public.push_daily() returns int
language plpgsql security definer set search_path = public as $$
declare n int := 0; p record; d date := (now() at time zone 'Europe/Berlin')::date;
begin
  for p in select distinct s.player from push_subs s left join wallets w on w.player = s.player
           where coalesce((s.prefs->>'bonus')::boolean, true) and (w.last_daily is null or w.last_daily < d)
  loop
    perform push_add(p.player, 'bonus', '🎁 Dein Tagesbonus wartet!', '60 Waldtaler liegen für dich bereit. Und vielleicht knackst du heute deine Bestweite? 🦊');
    n := n + 1;
  end loop;
  delete from push_queue where created_at < now() - interval '14 days';
  return n;
end $$;

revoke execute on function public.push_add(text, text, text, text), public.push_daily(),
  public.push_tg_taler(), public.push_tg_trade(), public.push_tg_inbox(), public.push_tg_run() from public, anon, authenticated;
grant execute on function public.push_key(), public.push_sub(text, jsonb, jsonb), public.push_unsub(text, text) to anon;

-- Zeitpläne (pg_cron + pg_net). Jede Minute verschickt die Edge Function die Warteschlange,
-- jeden Tag um 18 Uhr (Sommerzeit, im Winter 17 Uhr) kommt die Tagesbonus-Erinnerung.
do $do$
begin
  create extension if not exists pg_cron;
  create extension if not exists pg_net with schema extensions;
  perform cron.unschedule(jobid) from cron.job where jobname in ('waldlauf-push-send', 'waldlauf-push-daily');
  perform cron.schedule('waldlauf-push-send', '* * * * *', $job$
    select net.http_post(
      url := 'https://jvupgazchuggeizfdvcl.supabase.co/functions/v1/push-send',
      headers := jsonb_build_object('Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp2dXBnYXpjaHVnZ2VpemZkdmNsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE4MzY0ODksImV4cCI6MjEwNzQxMjQ4OX0.abBB7jlgNrOm0oRgPMGPJ2tLvT0_VUlm6K26RD69bLw'),
      body := '{}'::jsonb)
    where exists (select 1 from public.push_queue where sent_at is null)
       or not exists (select 1 from public.push_vapid);
  $job$);
  perform cron.schedule('waldlauf-push-daily', '0 16 * * *', 'select public.push_daily()');
exception when others then
  raise notice 'Zeitpläne nicht angelegt (pg_cron/pg_net fehlen?): %', sqlerrm;
end $do$;
