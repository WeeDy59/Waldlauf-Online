# Waldlauf v0.79.1: T-Rex als Verfolger, Riesenschlange, Einmal-Codes

Enthält alles aus 0.79 (Dino-Tal 2.0). Wenn du 0.79 noch nicht hochgeladen hast, nimm einfach diese Dateien.

## Supabase

Schon erledigt (Update 16 und der Verlosungs-Code sind eingerichtet). Die Datei supabase-update-16.sql liegt nur zur Sicherheit bei.

## GitHub

1. **spiel.html**, **sw.js**, **index.html**, **en.html** hochladen → **Commit changes**
2. 1–2 Minuten warten, Spiel neu laden (App ganz schließen und neu öffnen)

## Was neu ist im Dino-Tal

- 🦖 **T-Rex statt Jäger:** Unten im Bild verfolgt dich ein T-Rex. Wenn deine Spur rot leuchtet, schickt er dir ein **klapperndes Gebiss** hinterher. Oben links steht „🦖 T-Rex“ statt „Gewehr“.
- 🐍 **Riesenschlange:** Kommt von der Seite und schlängelt sich über **alle 3 Spuren**. Drüberspringen!
- 🦅 **Flugsaurier** statt Langhals: fliegt tief über eine Spur, unten durchrutschen.

## Einmal-Codes zum Verlosen

- Im Spiel: **Einstellungen → Code einlösen**.
- Jeder Code funktioniert **genau einmal**. Danach bekommt jeder andere „Dieser Code wurde schon eingelöst“.
- Wer das Dino-Tal schon hat, verbraucht den Code nicht und bekommt den Hinweis, ihn weiterzugeben.
- In der Datenbank steht nur ein Fingerabdruck (Hash) des Codes, der Code selbst steht nirgends (auch nicht in den Dateien auf GitHub).
- Prüfen, ob der Code schon eingelöst wurde (SQL Editor):
  ```sql
  select note, used_by is not null as benutzt, used_at from dlc_codes;
  ```
- Für weitere Codes einfach Claude fragen.
