# Waldlauf v0.76.1: Fix für das dunkelgrüne Flackern

Falls du Update 0.76 noch nicht hochgeladen hast: zuerst update-0.76 (inklusive supabase-update-14.sql), dann dieses hier.

## Hochladen (kein Supabase nötig)

1. GitHub-Repo **Waldlauf-Online** → **Add file → Upload files**
2. **spiel.html** und **sw.js** hineinziehen
3. **Commit changes**, 1–2 Minuten warten, Spiel neu laden (App einmal ganz schließen und neu öffnen)

## Was behoben ist

- Wenn beim Zeichnen eines Bildes ein Fehler passierte, wurde die ganze Zeichenfläche gelöscht. Dann sah man für den Moment den dunkelgrünen Hintergrund der Seite. Jetzt bleibt das Bild stehen, und der Spieler ist in dem Moment kurz geschützt.
- Wenn das Handy der Grafik kurz den Speicher wegnimmt, hält das Spiel an, statt blind weiterzulaufen. Danach bist du 1,5 Sekunden geschützt.
- Spieler bekommen eine kurze Update-Nachricht mit 300 Münzen.
