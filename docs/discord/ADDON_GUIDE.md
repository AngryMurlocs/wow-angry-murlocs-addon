# AngryMurlocs – Discord-Anleitung (Auszug Rezepte)

**Entwicklungsstand – Veröffentlichung nicht bestätigt.** Stand: Arbeitsbaum `feature/recipe-subcategories`, Addon-Basis 0.11.6 + Unreleased.

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

**Grenze:** Kategorie kommt aus WoW-Berufsdaten. Ohne auflösbaren Namen bleibt das Rezept unter Sonstiges, bis die Daten nachziehen. Client-Darstellung für diese Version noch nicht im Forever-Client abgehakt.
