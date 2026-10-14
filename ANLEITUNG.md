# Waldlauf v0.81.1: Alpha-Tester-Belohnung

## 1. Supabase
Schon erledigt (Update 19 hat Claude ausgeführt, 20 Codes sind angelegt). Die Datei liegt nur zur Sicherheit bei.

## 2. GitHub
Hochladen: **spiel.html** und **sw.js** → Commit changes.

## Die Codes
Stehen in **ALPHA-CODES.txt** (nicht hochladen, nur für dich!). Jeder Code funktioniert genau einmal, und jeder Spieler kann nur einen Tester-Code einlösen.
Einlösen im Spiel: Einstellungen → Konto → Code einlösen.

Ein Code gibt:
- 🦖 Dino-Tal und 🌊 Tiefsee
- 🪙 10.000 Waldtaler
- 💰 50.000 Münzen
- α Alpha-Wappen neben dem Namen (Rangliste, Chat, Freunde, Profil)
- 🖼️ Profilrahmen „Alpha-Tester“ und Avatarrahmen „Alpha-Ring“ (blau-gold, animiert)
- 📌 Outfit „Alpha-Anstecker“

Prüfen, wer welchen Code benutzt hat (SQL Editor):
`select note, used_by is not null as benutzt, used_at from tester_codes order by note;`
