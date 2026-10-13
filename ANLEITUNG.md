# Waldlauf online stellen

Damit kann jeder Waldlauf kostenlos im Browser spielen (Handy und PC, ohne App und ohne Anmeldung) und sich in der Weltrangliste mit allen anderen messen. Du brauchst dafür zwei kostenlose Konten: **Supabase** (für die Rangliste) und **GitHub** (für die Webseite). Rechne mit etwa 20 Minuten.

Im Paket:
- `index.html`: deine Website (Startseite mit „Jetzt spielen“, Tieren, Welten, Events und Musik)
- `spiel.html`: das komplette Spiel
- Ordner `img`: Bilder für die Website (komplett mit hochladen)
- `waldlauf-soundtrack.mp3`: deine Menümusik (muss neben `index.html` liegen)
- `forward-momentum.mp3`, `neon-runner.mp3`, `tropical-rush.mp3`, `arcade-frost.mp3`, `golden-sunset-run.mp3`, `treasure-hunt-groove.mp3`, `coin-collecting-groove.mp3`, `boosting-groove.mp3`: deine Lauf-Musik, läuft als Playlist während der Läufe (auch neben `index.html`)
- `supabase-setup.sql`: richtet die Datenbank für die Rangliste ein
- `supabase-update-02.sql`: Freunde, Freundes-Rangliste und Postfach
- `supabase-update-03.sql`: Rahmen, Avatarrahmen und Level in den Ranglisten
- `supabase-update-04.sql`: Cloud-Speicherstand (Fortschritt aufs neue Gerät mitnehmen)
- `supabase-update-05.sql`: Anti-Cheat für die Weltrangliste
- `supabase-update-06.sql`: Profil löschen (Online-Daten) und automatisches Aufräumen
- `supabase-update-07.sql`: Herausforderungen unter Freunden und Rudel (Clans)
- `supabase-update-08.sql`: Wochen-Rangliste und Freunde einladen
- `supabase-update-09.sql`: Waldtaler, Skins, Skin-Kisten, Markt und Tausch
- `supabase-update-10.sql`: Trade-up (10 Skins gegen 1 seltenen)
- `supabase-update-11.sql`: Spielmodi (Tagesstrecke, Duell, Live-Rennen), Sammelbuch, Skin-Rangliste, Wochen-Belohnungen, Profil-Schaufenster
- `supabase-alles-in-einem.sql`: **alle Datenbank-Schritte in einer Datei** (einfachster Weg, siehe Teil 1)
- `manifest.webmanifest`, `sw.js`, `icon-192.png`, `icon-512.png`: damit man Waldlauf als App installieren kann (mit hochladen)
- `OFL-Baloo2.txt`: Lizenz der eingebauten Schrift (mit hochladen)
- `ANLEITUNG.md`: diese Anleitung

---

## Teil 1: Rangliste einrichten (Supabase)

1. Geh auf **supabase.com** und registriere dich kostenlos (zum Beispiel mit deinem GitHub- oder Google-Konto).
2. Klick auf **New project**.
   - Name: `waldlauf`
   - Datenbank-Passwort: irgendein sicheres Passwort (gut aufheben, wird aber für das Spiel nicht gebraucht)
   - Region: **Frankfurt** (Central EU)
   - Tarif: **Free**
3. Warte etwa 1 bis 2 Minuten, bis das Projekt bereit ist.
4. Links im Menü auf **SQL Editor** gehen und dort ein neues Fenster öffnen.
5. Den kompletten Inhalt von `supabase-setup.sql` hineinkopieren und auf **Run** drücken. Es sollte „Success“ erscheinen. Danach in neuen Fenstern genauso `supabase-update-02.sql` dann `supabase-update-03.sql`, `supabase-update-04.sql`, `supabase-update-05.sql`, `supabase-update-06.sql`, `supabase-update-07.sql`, `supabase-update-08.sql`, `supabase-update-09.sql`, `supabase-update-10.sql` und `supabase-update-11.sql` ausführen (Freunde, Postfach, Rahmen in der Rangliste, Cloud-Speicher).
6. Links auf **Project Settings** (Zahnrad), dann **API** beziehungsweise **API Keys**. Dort zwei Werte kopieren:
   - die **Project URL** (sieht aus wie `https://abcdefgh.supabase.co`)
   - den **anon / public** Schlüssel oder den **publishable key**

   Diese beiden Werte sind dafür gedacht, öffentlich im Spiel zu stehen. Den **service_role** oder **secret** Schlüssel gibst du niemals heraus.

7. Öffne `index.html` in einem Texteditor und suche die Zeile:

   ```
   const ONLINE={url:'',key:''};
   ```

   Trag deine beiden Werte zwischen die Anführungszeichen ein, zum Beispiel:

   ```
   const ONLINE={url:'https://abcdefgh.supabase.co',key:'eyJhbGciOi...'};
   ```

   Am Handy ist das umständlich. Schick mir die URL und den öffentlichen Schlüssel einfach im Chat, dann baue ich sie dir ein und du bekommst die fertige `index.html` zurück.

---

## Teil 2: Spiel ins Netz stellen (GitHub Pages)

1. Geh auf **github.com** und registriere dich kostenlos. Dein Benutzername steht später in der Adresse des Spiels.
2. Oben rechts auf **+**, dann **New repository**.
   - Name: `waldlauf`
   - **Public** auswählen
   - auf **Create repository** klicken
3. Auf der neuen Seite auf **uploading an existing file** klicken, **alle Dateien und den Ordner `img`** hineinziehen beziehungsweise auswählen und unten auf **Commit changes** drücken.
4. Im Repository oben auf **Settings**, dann links auf **Pages**.
   - Bei „Source“: **Deploy from a branch**
   - Branch: **main**, Ordner: **/ (root)**, dann **Save**
5. Nach etwa einer Minute ist dein Spiel online unter:

   **`https://DEIN-BENUTZERNAME.github.io/waldlauf/`**

   Diesen Link kannst du an alle weitergeben. Auf dem Handy lässt sich die Seite über „Zum Startbildschirm hinzufügen“ wie eine App ablegen.

---

## Spiel weiter verbessern (mit Claude)

1. Schick mir deine aktuelle `index.html` im Chat und sag, was du ändern möchtest.
2. Ich gebe dir eine neue `index.html` zurück. Deine Online-Zeile mit URL und Schlüssel bleibt dabei erhalten.
3. Lade sie in GitHub hoch: im Repository **Add file**, dann **Upload files**, die neue `index.html` hineinziehen und **Commit changes**. Die alte Datei wird ersetzt, nach etwa einer Minute ist das Update für alle live.

Die Datenbank musst du dafür nicht anfassen. Nur wenn ein Update neue Online-Funktionen braucht, bekommst du von mir ein kleines Zusatz-Skript für den SQL Editor.

**Update 01 (Länderflaggen):** Hast du `supabase-setup.sql` schon ausgeführt, bevor es die Flaggen gab, führe einmal zusätzlich `supabase-update-01.sql` im SQL Editor aus. Richtest du die Datenbank gerade erst ein, reicht `supabase-setup.sql`, die Flaggen sind dort schon drin.

**Update 02 (Freunde und Postfach):** Damit Freundesuche, Anfragen, Freundes-Rangliste und Postfach-Nachrichten funktionieren, führe einmal `supabase-update-02.sql` im SQL Editor aus. Das gilt für alle, auch wenn du die Datenbank gerade erst einrichtest (nach `supabase-setup.sql`).

**Update 03 (Rahmen und Level in der Rangliste):** Danach einmal `supabase-update-03.sql` ausführen. Ohne dieses Update funktioniert alles weiter, andere Spieler erscheinen dann nur ohne Rahmen und mit Level 1.

**Update 04 (Cloud-Speicher):** Einmal `supabase-update-04.sql` ausführen. Danach können Spieler in den Einstellungen unter „Spielstand sichern“ einen geheimen Speichercode erstellen und ihren Fortschritt damit auf ein anderes Gerät holen. Gespeichert wird nur ein Hash des Codes, nie der Code selbst.

**Update 05 (Anti-Cheat):** Einmal `supabase-update-05.sql` ausführen und gleichzeitig die neue `index.html` hochladen (alte Spielversionen können danach keine Läufe mehr eintragen).
- Jeder Lauf holt sich beim Start ein Ticket vom Server. Beim Eintragen prüft die Datenbank, ob die Strecke zur echten vergangenen Zeit passt, ob die Münzen passen und ob das Ticket schon benutzt wurde.
- Abgelehnte Läufe und Manipulationen, die das Spiel selbst erkennt, landen in der Tabelle `cheat_log` (Table Editor). Dort siehst du Name, Grund und Meter.
- Spieler sperren: im SQL Editor `select ban_by_pub('#a1b2c3d4e5', 'Cheat');` mit der Freundes-ID des Spielers. Gesperrte Spieler verschwinden aus der Weltrangliste und können nichts mehr eintragen. Entsperren: in der Tabelle `banned` die Zeile löschen.

**Update 06 (Profil löschen):** Einmal `supabase-update-06.sql` ausführen. Danach löscht „Profil löschen“ in den Einstellungen auch alle Online-Daten des Spielers.

**Impressum und Datenschutz:** In der `index.html` steht die Zeile `const LEGAL={name:'',street:'',city:'',country:'Deutschland',email:''};`. Trag dort deine Angaben ein (oder schick sie Claude), dann erscheinen sie unter Einstellungen, „Rechtliches“.

**Fehler melden:** Spieler können in den Einstellungen „🐞 Fehler melden“ drücken. Die Meldung geht über den kostenlosen Dienst FormSubmit an deine E-Mail-Adresse. Bei der allerersten Meldung schickt FormSubmit dir eine Bestätigungs-E-Mail: Dort einmal auf „Activate Form“ klicken, erst danach kommen die Meldungen an (die erste Meldung geht dabei verloren, schick dir also am besten selbst eine Testmeldung). In der Bestätigungs-E-Mail bekommst du außerdem eine zufällige Adresse (zum Beispiel `a1b2c3...`), die du in der `index.html` statt deiner E-Mail bei `const BUGMAIL=` eintragen kannst, damit deine Adresse nicht im Quelltext steht.

---

**Update 07 (Herausforderungen und Rudel):** Einmal `supabase-update-07.sql` ausführen und die neue `index.html` plus `manifest.webmanifest`, `sw.js`, `icon-192.png` und `icon-512.png` hochladen. Danach können Spieler Freunde mit ⚔️ herausfordern und unter 👥 Freunde → 🐺 Rudel Rudel gründen. In den Einstellungen erscheint „Als App installieren“.

**Update 08 (Wochen-Rangliste und Einladungen):** Einmal `supabase-update-08.sql` ausführen und die neue `index.html` hochladen. Danach gibt es in der Rangliste den Tab „📅 Woche“, und Einladungslinks (👥 Freunde → 🎁 Freunde einladen) schenken beiden Spielern 2.000 Münzen.

**Update 09 (Skins, Markt und Tausch):** Einmal `supabase-update-09.sql` ausführen und die neue `spiel.html` plus `sw.js` hochladen. Danach gibt es im Hauptmenü den Knopf 🎨 Skins. Waldtaler und Skins liegen nur in der Datenbank, das Spiel selbst kann daran nichts verändern. Waldtaler gibt es für echte Online-Läufe (1 pro 50 m und 1 pro 10 Münzen, höchstens 800 am Tag), als Tagesbonus (60), beim Recyceln und bei Verkäufen. Jeder neue Spieler startet mit 500. Eine Skin-Kiste kostet 600, die Event-Kiste 900 (nur während eines Events). Der Markt behält 5 % jedes Verkaufs ein, damit nicht unendlich viele Taler entstehen. Wer Taler oder Skins von Spielern einsehen will: im **Table Editor** die Tabellen `wallets`, `skins`, `market`, `trades` und `taler_log`.

**Update 10 (Trade-up):** Einmal `supabase-update-10.sql` ausführen und die neue `spiel.html` plus `sw.js` hochladen. Danach gibt es unter 🎨 Skins → Inventar den Knopf ⬆️ Trade-up: 10 Skins derselben Seltenheit werden gegen 1 Skin der nächsten Stufe getauscht. Das Spiel schreibt außerdem kurze Grafik-Aussetzer mit, sie stehen dann im Fehlerbericht unter „Fehler melden“.

**Update 11 (Spielmodi und Profil):** Einmal `supabase-update-11.sql` ausführen und die neue `spiel.html` plus `sw.js` hochladen. Danach gibt es im Hauptmenü 🎮 Modi: Tagesstrecke mit eigener Tages-Rangliste, Abenteuer mit 30 Leveln, Sprint, Hardcore, Duell (Best of 3 gegen Freunde, Sieger bekommt 300 Waldtaler) und Live-Rennen mit bis zu 4 Spielern über einen Raum-Code. Unter 🎨 Skins → 🏆 Buch gibt es das Sammelbuch und die Skin-Rangliste. Die besten 100 der Wochen-Rangliste holen sich montags Gratis-Kisten ab. Im Profil gibt es den Tab 🪪 Schaufenster mit Info-Text und bis zu 4 ausgestellten Skins, die andere sehen, wenn sie auf das Profil tippen. Die Infotexte der Spieler findest du in Supabase in der Tabelle `profiles`, Spalte `bio`, und kannst sie dort bei Bedarf leeren.

**Website (ab Version 0.65):** `index.html` ist jetzt die Startseite, das Spiel liegt in `spiel.html`. Lade beide, den Ordner `img` und alle anderen Dateien hoch. Trag in der `index.html` unten im Skript dieselben Werte wie im Spiel ein: bei `LEGAL` deine Impressum-Angaben und bei `ONLINE` die Supabase-Adresse und den öffentlichen Schlüssel. Dann zeigt die Website auch die Live-Rangliste.

## Gut zu wissen

- **Fortschritt sichern:** Level, Münzen, Outfits und Event-Fortschritt liegen im Browser des Spielers. Mit dem Cloud-Speichercode (Update 04) oder der Spielstand-Datei aus den Einstellungen nimmt man alles auf ein anderes Gerät mit.
- **Schummeln:** Mit Update 05 prüft die Datenbank jeden Lauf gegen die echte Zeit, und das Spiel erkennt typische Manipulationen. Einen völlig schummelsicheren Schutz gibt es bei reinen Browser-Spielen aber nicht. Auffällige Einträge löschst du in Supabase unter **Table Editor**, Tabelle `runs`, und schaust in `cheat_log` nach Verdächtigen.
- **Namen:** Spieler wählen ihren Namen frei. Unpassende Namen löschst du im **Table Editor** in den Tabellen `runs` und `profiles`.
- **Freunde:** Jeder Spieler hat eine öffentliche Freundes-ID (zum Beispiel `#a1b2c3d4e5`). Die geheime Geräte-ID wird nie angezeigt, deshalb kann niemand im Namen anderer Anfragen verschicken. Pro Stunde sind höchstens 30 Anfragen möglich, pro Spieler bis zu 200 Freunde.
- **Pausierte Datenbank:** Kostenlose Supabase-Projekte werden pausiert, wenn eine Woche lang niemand spielt. Dann zeigt das Spiel „Weltrangliste nicht erreichbar“. In Supabase reicht ein Klick auf **Restore project**.
- **Seasons und Events:** Season 01 und das Herzensfest starten am 11.10.2026. Die Weltrangliste wechselt automatisch alle 90 Tage. Für neue Events sag mir einfach Bescheid.
