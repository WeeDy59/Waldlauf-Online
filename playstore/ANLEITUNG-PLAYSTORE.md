# Waldlauf in den Google Play Store bringen

Alles in diesem Ordner ist schon fertig. Nächsten Monat brauchst du nur noch das Entwicklerkonto.

## Was in diesem Ordner liegt

| Datei | Wofür |
|---|---|
| `icon-512.png` | App-Symbol (512 × 512, PNG) |
| `feature-graphic-de.png` / `-en.png` | Banner oben im Store (1024 × 500) |
| `screenshots-de/1–6.png` / `screenshots-en/1–6.png` | Handy-Screenshots (1080 × 1920) mit Beschriftung |
| `STORE-TEXTE.md` | Name, Kurz- und Langbeschreibung auf Deutsch und Englisch, Antworten für die Formulare |

Datenschutz-Link für den Store: **https://weedy59.github.io/Waldlauf-Online/datenschutz.html** (ist im Update 0.80 dabei)

## Ablauf (ca. 1–2 Stunden Arbeit, plus Wartezeiten)

1. **Entwicklerkonto anlegen:** play.google.com/console → als „Privatperson“ registrieren, einmalige Gebühr bezahlen, Ausweis-Prüfung abwarten (kann ein paar Tage dauern).
2. **App-Paket erstellen (ohne Programmieren):**
   - Geh auf **pwabuilder.com**, gib `https://weedy59.github.io/Waldlauf-Online/spiel.html` ein und klicke „Package for stores“ → **Android** → „Generate“.
   - Package ID z. B. `io.github.weedy59.waldlauf`, App-Name „Waldlauf“.
   - Du bekommst eine ZIP mit einer **.aab-Datei** (für Google Play), einem **Signatur-Schlüssel** (gut aufbewahren, nie verlieren!) und einer Datei **assetlinks.json**.
3. **assetlinks.json hochladen:** Damit die App ohne Browser-Leiste läuft, muss die Datei unter `https://weedy59.github.io/.well-known/assetlinks.json` liegen. Dafür brauchst du auf GitHub ein zweites Repo mit dem Namen **weedy59.github.io** und darin den Ordner `.well-known` mit der Datei. Schick mir die Datei, dann helfe ich dir dabei.
4. **App in der Play Console anlegen:** Texte aus `STORE-TEXTE.md` einfügen, Bilder hochladen, Formulare ausfüllen (Antworten stehen auch in `STORE-TEXTE.md`).
5. **Geschlossener Test (Pflicht für neue Privat-Konten):** Google verlangt vor der Veröffentlichung einen geschlossenen Test mit **mindestens 12 Testern über 14 Tage**. Tipp: Freunde, Familie und TikTok-Follower als Tester einladen (die brauchen nur ein Google-Konto).
6. Danach **Produktionszugriff beantragen** und veröffentlichen.

Updates laufen danach automatisch: Was du auf GitHub hochlädst, ist sofort auch in der App, weil die App deine Webseite anzeigt.

## Hinweis zu deinen persönlichen Daten

Google zeigt im Store den Entwicklernamen und eine **Kontakt-E-Mail öffentlich** an. Wenn du deine private Adresse schützen willst, leg dir dafür eine eigene E-Mail an (z. B. waldlauf.support@…). Eine Postanschrift wird bei kostenlosen Apps ohne Käufe normalerweise nicht öffentlich angezeigt, prüfe das aber beim Anlegen des Kontos.
