# Waldlauf v0.78.1: Ursache vom dunkelgrünen Flackern behoben

Enthält alles aus 0.78. Falls du 0.78 noch nicht hochgeladen hast: einfach nur diese beiden Dateien nehmen.

## Hochladen (kein Supabase nötig)

1. GitHub-Repo **Waldlauf-Online** → **Add file → Upload files**
2. **spiel.html** und **sw.js** hineinziehen → **Commit changes**
3. 1–2 Minuten warten, Spiel neu laden (App ganz schließen und neu öffnen)

## Was behoben ist

- Dein Fehlerprotokoll hat die Ursache gezeigt: Ein Effekt hat in manchen Bildern versucht, einen Kreis mit **negativer Größe** zu zeichnen. Der Browser bricht dann das ganze Bild ab, und man sah kurz den dunkelgrünen Hintergrund.
- Jetzt werden solche Werte automatisch auf 0 gesetzt, für alle Kreise und Ellipsen im ganzen Spiel. Das Bild läuft einfach weiter.
- Den Schutz aus 0.76.1 gibt es zusätzlich weiterhin.
