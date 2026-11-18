# AngryMurlocs – Discord-Anleitung (Auszug Rezepte / Protokoll)

**Version 0.11.21.**

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
