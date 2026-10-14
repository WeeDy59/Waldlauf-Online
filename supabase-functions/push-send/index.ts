// Waldlauf: verschickt die Benachrichtigungen aus der Tabelle push_queue.
// Wird jede Minute von pg_cron aufgerufen. Legt beim ersten Start selbst das Schlüsselpaar an.
import webpush from "npm:web-push@3.6.7";
import postgres from "npm:postgres@3.4.4";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 2, prepare: false });
const SITE = "https://weedy59.github.io/Waldlauf-Online/";

async function keys() {
  let [k] = await sql`select pub, priv from public.push_vapid where id = 1`;
  if (!k) {
    const v = webpush.generateVAPIDKeys();
    await sql`insert into public.push_vapid (id, pub, priv) values (1, ${v.publicKey}, ${v.privateKey}) on conflict (id) do nothing`;
    [k] = await sql`select pub, priv from public.push_vapid where id = 1`;
  }
  return k;
}

Deno.serve(async () => {
  try {
    const k = await keys();
    webpush.setVapidDetails(SITE, k.pub, k.priv);
    const rows = await sql`
      update public.push_queue set sent_at = now()
      where id in (select id from public.push_queue where sent_at is null order by id limit 200 for update skip locked)
      returning id, player, kind, title, body`;
    let sent = 0, gone = 0, failed = 0;
    for (const r of rows) {
      const subs = await sql`select endpoint, sub from public.push_subs
        where player = ${r.player} and coalesce((prefs->>${r.kind})::boolean, true)`;
      const payload = JSON.stringify({ title: r.title, body: r.body, tag: "waldlauf-" + r.kind, url: "spiel.html" });
      for (const s of subs) {
        try {
          await webpush.sendNotification(s.sub, payload, { TTL: 60 * 60 * 12, urgency: "normal" });
          sent++;
          await sql`update public.push_subs set fails = 0, last_ok = now() where endpoint = ${s.endpoint}`;
        } catch (e) {
          const code = (e as { statusCode?: number }).statusCode ?? 0;
          if (code === 404 || code === 410) {
            gone++;
            await sql`delete from public.push_subs where endpoint = ${s.endpoint}`;
          } else {
            failed++;
            await sql`update public.push_subs set fails = fails + 1 where endpoint = ${s.endpoint}`;
            await sql`delete from public.push_subs where endpoint = ${s.endpoint} and fails >= 10`;
          }
        }
      }
    }
    return Response.json({ queued: rows.length, sent, gone, failed });
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 500 });
  }
});
