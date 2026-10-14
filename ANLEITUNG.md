# Waldlauf v0.78: Benachrichtigungen

Spieler können sich jetzt erinnern lassen, auch wenn das Spiel geschlossen ist:
- 🎁 Tagesbonus wartet (einmal am Tag gegen 18 Uhr, nur wenn noch nicht abgeholt)
- 🏪 Skin im Markt verkauft / 🔄 neues Tauschangebot
- 👋 Freundschaftsanfrage / 🤝 angenommen / 🏃 ein Freund hat deine Bestweite überholt

Jeder Spieler entscheidet selbst in den Einstellungen, was er bekommt. Gleiche Nachrichten höchstens alle 6 Stunden, maximal 12 am Tag.

Diesmal sind es **3 Schritte in Supabase** und dann GitHub. Das Ganze dauert ca. 10 Minuten.

## Schritt 1: Edge Function anlegen (verschickt die Nachrichten)

1. Supabase öffnen → links **Edge Functions** → **Deploy a new function** → **Via Editor**.
2. Als Namen genau **push-send** eingeben.
3. Den vorhandenen Beispiel-Code komplett löschen und den Inhalt der Datei **supabase-functions/push-send/index.ts** hineinkopieren.
4. **Deploy function** klicken. „Verify JWT“ bleibt an.

Du musst **keine** Schlüssel oder Secrets eintragen. Die Funktion legt sich ihr Schlüsselpaar beim ersten Start selbst in der Datenbank an.

## Schritt 2: SQL ausführen

1. **SQL Editor** → **New query** → Inhalt von **supabase-update-15.sql** einfügen → **Run**.
2. Zur Kontrolle in einer neuen Abfrage ausführen:

   ```sql
   select jobname, schedule from cron.job where jobname like 'waldlauf-push%';
   ```

   Es sollten **2 Zeilen** erscheinen (waldlauf-push-send und waldlauf-push-daily).
   Falls nicht: links **Database → Extensions**, dort **pg_cron** und **pg_net** einschalten und das SQL aus Schritt 2 nochmal ausführen.

## Schritt 3: Prüfen, ob alles läuft (nach 1–2 Minuten)

```sql
select length(pub) from push_vapid;
```

Erscheint die Zahl **87**, hat die Edge Function ihr Schlüsselpaar angelegt und alles ist bereit.
Bleibt das Ergebnis leer: unter **Edge Functions → push-send → Logs** nachsehen und mir den Fehler schicken.

## Schritt 4: GitHub

1. **spiel.html** und **sw.js** hochladen (Add file → Upload files → Commit changes).
2. 1–2 Minuten warten, Spiel neu laden (App ganz schließen und neu öffnen).

## Selbst testen

1. Im Spiel: **Einstellungen → Sprache und App → 🔔 Benachrichtigungen → Einschalten**, dann im Browser „Zulassen“.
2. Im SQL Editor eine Testnachricht an alle angemeldeten Geräte schicken (am Anfang bist das nur du):

   ```sql
   insert into push_queue (player, kind, title, body)
   select distinct player, 'bonus', '🔔 Test', 'Es klappt! Waldlauf kann dich jetzt erinnern.' from push_subs;
   ```

3. Innerhalb von etwa einer Minute kommt die Nachricht aufs Handy oder den PC.

## Gut zu wissen

- **Android, PC (Chrome, Edge, Firefox):** funktioniert direkt im Browser.
- **iPhone/iPad:** nur wenn Waldlauf über „Teilen → Zum Home-Bildschirm“ installiert ist (ab iOS 16.4). Das Spiel erklärt das an der Stelle selbst.
- Nach dem 3. Lauf fragt das Spiel einmal freundlich nach, ob es erinnern darf (danach höchstens alle 7 Tage, nie während des Intros).
- Die Datenschutzerklärung im Spiel hat einen neuen Abschnitt „Benachrichtigungen“.
- In supabase-alles-in-einem.sql ist Update 15 auch schon drin.
