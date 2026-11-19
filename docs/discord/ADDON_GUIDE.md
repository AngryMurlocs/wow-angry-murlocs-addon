# AngryMurlocs – Discord-Anleitung (Auszug)

**Version 0.11.24** (+ Entwicklungsstand: Murloc-Rufe Aus/Nerglish/Schmäh – Veröffentlichung nicht bestätigt).

## Todesmeldungen und Wanted

**Nutzen:** Gilden-Todes-Toasts und Wanted kommen aus geteilten Toden außerhalb von strukturiertem PvP.

**Grenze (0.11.22):** In **Schlachtfeldern und Arenen** gibt es **keine** Gilden-Todesmeldung (Toast/Feed). Wanted hat solche Tode schon vorher nie gezählt. Duell-Tode zählen weiter nicht für Wanted.

**Wo steuern:** `/am` → Einstellungen → Freigaben → **Gilden-Tode teilen** (steuert auch Wanted-Meldungen).

## Seltene Murloc-Rufe (Yell)

**Nutzen:** Gelegentlich **schreit** dein Charakter per **Yell (/y)** — bei Gilden-Tod, Level-Up, Wanted, PvP, Beute, Erfolgen u. a., manchmal auch zwischendurch. Toasts und Addon-Sync bleiben unverändert.

**Wo:** `/am` → Einstellungen → **Oberfläche** → **Murloc-Rufe**
- **Aus** (Standard) / **Nerglish** (klassische Laute) / **Schmäh** (österreichische Mischung)
- **Öffentlich testen (/y)** — Spieler in der Nähe hören mit; bei Aus testest du Nerglish

**Grenze:** Selten (Chance + Abklingzeit, max. wenige pro Stunde). Nur Yell in Hörweite, kein Gilden-Chat.

## Rezepte in Unterkategorien

**Nutzen:** Innerhalb eines Berufs siehst du die Rezepte nach WoW-Unterkategorien (z. B. Tränke, Elixiere), aufklappbar mit Anzahl.

**Wo:**
1. **Berufe → Übersicht** → Berufssymbol eines Mitglieds → Rezeptliste
2. **Berufe → Rezeptsuche** → Beruf anklicken (nicht die globale Textsuche)

**Bedienung:**
- Kategorien starten geschlossen. Klick auf die Zeile klappt auf/zu.
- Fußzeile: „X Rezepte · Y Kategorien“.
- Suche findet Treffer auch in geschlossenen Gruppen; Feld leeren stellt den vorherigen Aufklappzustand wieder her.
- Rezept öffnen → Detail wie bisher; **Zurück** behält Suche, Gruppen und Scrollposition.
- Rezepte ohne bekannte Kategorie: **Sonstiges**.
- Globale Suche (Text ohne gewählten Beruf) bleibt eine flache Trefferliste.

**Grenze:** Kategorie kommt aus WoW-Berufsdaten. Ohne auflösbaren Namen bleibt das Rezept unter Sonstiges, bis die Daten nachziehen.

## Protokoll (Status und Debug)

**Nutzen:** Erfassung und normale Aktualisierungsmeldungen zu Rezepten landen nicht mehr im Chat, sondern unter Einstellungen → **Protokoll**.

**Wo:** `/am` → Einstellungen → **Protokoll**
- **Status:** z. B. „Rezepte erfasst“, erfolgreiches Aktualisieren (nur diese Sitzung; Button **Status leeren**).
- **Debug:** lokale Diagnose an/aus (wie `/am diag`), Liste und Zähler nur auf deinem Rechner. Standard: aus.

**Grenze:** Fehler und nötige Aktionen (Beruf öffnen, API fehlt, …) bleiben im Chat. Nach `/reload` ist die Statusliste leer.
