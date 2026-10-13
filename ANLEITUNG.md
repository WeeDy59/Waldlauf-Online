# Waldlauf v0.76: Erweiterungen und das Dino-Tal

## 1. Supabase (zuerst!)

1. Öffne Supabase → **SQL Editor** → **New query**.
2. Kopiere den kompletten Inhalt von **supabase-update-14.sql** hinein und klicke auf **Run**.
3. Es sollte „Success“ erscheinen. Das legt die Tabelle für gekaufte Erweiterungen und die Kauf-Funktionen an.

(Die Datei supabase-alles-in-einem.sql enthält Update 14 jetzt auch, falls du mal alles neu aufsetzen musst.)

## 2. GitHub

1. Repo **Waldlauf-Online** → **Add file → Upload files**.
2. Ziehe hinein: **spiel.html**, **sw.js**, **index.html**, **en.html**
3. Ziehe den Ordner **img** mit hinein (neu: s-dino.jpg, a36.png, a37.png, a38.png).
4. **Commit changes**, 1–2 Minuten warten, neu laden.

## Was ist neu

- Shop → **🧩 Erweiterungen**: Neue Welten mit eigenen Tieren und Outfits, nur mit Waldtalern.
- **Dino-Tal** für 20.000 Waldtaler:
  - Eigene Welt mit Vulkan, Farnwäldern, Dino-Knochen und Nestern.
  - 3 Tiere: T-Rex, Triceratops und Pteranodon (kann fliegen), jedes mit eigener Fähigkeit.
  - 5 exklusive Outfits: Dino-Kapuze, Zahnkette, Dino-Ei-Rucksack, Knochenkeule, Vulkan-Aura.
  - Der T-Rex jagt dich alle 1.500 m als Boss.
- Jeder Spieler hat **einen gratis Probelauf** im Dino-Tal.
- Gekauft wird auf dem Server. Wer das Spiel neu installiert, bekommt seine Erweiterungen automatisch zurück.
- Tiefsee, Weltraum und Märchenwald stehen als „Bald da“ im Shop.
- Alle Spieler bekommen eine Update-Nachricht mit 1.000 Münzen ins Postfach.
- Website: neuer Bereich „Das Dino-Tal wartet auf dich“ (Deutsch und Englisch).

Zum Preis: Mit Läufen verdient man höchstens 800 Waldtaler am Tag, dazu 60 als Tagesbonus und etwas aus Wochen-Belohnung, Duellen und Skin-Buch. 20.000 heißt also gut 3 Wochen fleißiges Spielen (weniger, wenn man Skins auf dem Markt verkauft). Der Preis steht in der Datenbank (wl_dlc_price) und im Spiel und lässt sich schnell ändern.
