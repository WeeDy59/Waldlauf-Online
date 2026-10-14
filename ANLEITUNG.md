# Waldlauf v0.80: Clips, Dino-Rangliste, Statistik, Vibration, Play-Store-Paket

Enthält alles aus 0.79 und 0.79.1.

## 1. Supabase: supabase-update-17.sql ausführen

SQL Editor → New query → Inhalt von **supabase-update-17.sql** einfügen → **Run** (bei der Warnung „Potential issue“ auf **Run query** klicken). Ganz unten erscheint eine Zeile mit deinem Entwickler-Namen.
(Falls Claude das schon für dich gemacht hat, kannst du diesen Schritt überspringen. Doppelt ausführen schadet nicht.)

## 2. GitHub

Hochladen: **spiel.html**, **sw.js**, **index.html**, **en.html**, **datenschutz.html**, **manifest.webmanifest** → Commit changes.
Den Ordner **playstore** NICHT hochladen, der ist nur für dich (für nächsten Monat).

## Was neu ist

- 🎬 **Clip teilen:** Das Spiel nimmt automatisch die letzten Sekunden jedes Laufs auf (mit Waldlauf-Logo und Link). Nach dem Lauf: „🎬 Clip teilen“ → direkt zu TikTok, WhatsApp usw. oder als Video speichern. In den Einstellungen abschaltbar.
- 🦖 **Dino-Wochenrangliste:** Im Shop unter Erweiterungen. Jeden Montag bekommen die besten 3 Dino-Läufer der Vorwoche 3.000 / 1.500 / 750 Waldtaler (automatisch beim nächsten Öffnen). Geschützt gegen Schummeln: Die Weite wird mit der echten Laufzeit verglichen.
- 📊 **Statistik nur für dich:** Einstellungen → Hilfe und Rechtliches → „📊 Statistik (nur Entwickler)“. Zeigt Spieler pro Tag, neue Spieler, wie viele wiederkommen, wo die Läufe enden, beliebteste Tiere, Spielmodi und Geräte. Der Knopf erscheint nur bei Profilen mit DEV-Wappen.
- 📳 **Vibration** bei Treffern, Bernstein, Extras, Ultra-Drops und dem T-Rex-Biss (Android; abschaltbar).
- ⚡ **Schnellerer Start:** Die Musik lädt erst, wenn sie gebraucht wird. Ruckelt das Spiel auf einem Handy, stellt es die Grafik automatisch auf „Schnell“ (nur, wenn der Spieler das nicht selbst eingestellt hat).
- 🔒 **Datenschutz:** Neue Seite datenschutz.html (wird für den Play Store gebraucht) und ein neuer Abschnitt zur anonymen Statistik. Beim Konto-Löschen werden jetzt auch Statistik, Rangliste und Erweiterungen gelöscht.

## Play Store (nächsten Monat)

Im Ordner **playstore** liegt alles fertig: Icon, Banner, 6 Screenshots (Deutsch und Englisch), Store-Texte und eine Schritt-für-Schritt-Anleitung (ANLEITUNG-PLAYSTORE.md).
