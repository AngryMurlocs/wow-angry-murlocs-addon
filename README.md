# AngryMurlocs

Gilden-Addon der **Angry Murlocs** für **World of Warcraft: Forever**. Es zeigt Gildenmitglieder als Murlocs auf der Weltkarte, sammelt die Berufe und Rezepte der Gilde, führt eine gemeinsame Wanted-Liste und meldet Tode und Level-ups der Gilde.

**Version:** 0.11.6

**Download:** [CurseForge](https://www.curseforge.com/wow/addons/angry-murlocs) · **Quellcode:** [GitHub](https://github.com/AngryMurlocs/wow-angry-murlocs-addon) · **Discord:** [discord.murlocs.eu](https://discord.murlocs.eu)

Was sich in jeder Version geändert hat, steht im [CHANGELOG](CHANGELOG.md).

## Installation

1. Über die CurseForge-App installieren, oder das ZIP von der [CurseForge-Seite](https://www.curseforge.com/wow/addons/angry-murlocs) laden und den Ordner `AngryMurlocs` nach `World of Warcraft\_forever_\Interface\AddOns\` kopieren.
2. WoW starten bzw. neu starten.
3. `/am` öffnet das Hauptfenster.

Die meisten Funktionen leben vom Austausch mit der Gilde. Je mehr Gildenmitglieder das Addon nutzen, desto mehr zeigt es. Das Addon weist im Chat darauf hin, wenn jemand in der Gilde eine neuere Version hat.

## Funktionen

### Gilde auf der Karte
- Gildenmitglieder erscheinen auf der Weltkarte als Murlocs in ihrer Klassenfarbe. Zur Wahl stehen Murloc-Köpfe, Ganzkörper oder Ringe, und die Größe ist einstellbar.
- Die Positionen werden alle paar Sekunden aktualisiert. Ohne neue Daten verblasst ein Pin langsam und verschwindet nach einer Minute.
- Stehen mehrere Spieler am selben Ort, rücken ihre Pins auseinander, statt sich zu verdecken.

### Berufe und Rezepte
- Liste aller Berufe in der Gilde mit Fertigkeitsstufe, Online-Status, Sortierung und Suche.
- Rezept-Katalog: Wer in der Gilde kann was herstellen, mit benötigten Materialien. Die Rezepte eines Mitglieds erscheinen, sobald es seinen Beruf einmal im Spiel geöffnet hat.
- Den Hersteller direkt anflüstern oder eine fertige Anfrage in den Chat übernehmen.

### Wanted-Liste
- Wird ein Gildenmitglied von einem Spieler der Gegenseite getötet, landet der Killer auf der Wanted-Liste der Gilde. Jeder weitere Kill erhöht sein Level, mit Rängen von **Markiert** bis **Gildenschreck**.
- Duelle, Schlachtfelder, Arenen sowie Tode durch Monster oder Umgebung zählen nie.
- Nimmst du einen gesuchten Spieler ins Ziel, erfährt die Gilde, wo er gesehen wurde. Sichtungen zeigen, wie frisch sie sind.
- Liste mit Seiten, Suche, Sortierung und Details zu jedem Eintrag.
- Die Liste gleicht sich beim Login automatisch mit der Gilde ab, oder jederzeit mit `/am sync`.

### Meldungen
- Tode und Level-ups in der Gilde erscheinen als Meldung im Murloc-Look. Sound, Größe, Dauer und Position sind einstellbar.
- Meldungen warten, bis du aus dem Kampf bist, und erscheinen nacheinander statt übereinander.

### Sprachen
Deutsch und Englisch, je nach Spielsprache.

## Befehle

| Befehl | Wirkung |
|--------|---------|
| `/am` | Hauptfenster öffnen oder schließen |
| `/am config` | Einstellungen (auch `options` / `settings`) |
| `/am wanted` | Wanted-Liste |
| `/am prof` | Berufsliste |
| `/am sync` | Gildendaten jetzt abgleichen |
| `/am map` | Kartenpins an/aus |
| `/am share on` / `off` | Eigene Position teilen an/aus |
| `/am prof share on` / `off` | Eigene Berufe teilen an/aus |
| `/am diag on` / `off` / `show` / `death` | Diagnose für Fehlersuche, bleibt auf deinem Rechner |
| `/am help` | Hilfe |

Weitere Kurzformen: `/angrymurlocs`, `/gr`. Minimap-Knopf: Linksklick öffnet das Hauptfenster, Rechtsklick die Einstellungen.

## Privatsphäre

Was das Addon mit der Gilde teilt, stellst du in den Einstellungen unter **Freigaben** ein, jeweils einzeln:

- deine Position auf der Karte (standardmäßig nicht im Kampf und nicht auf Schlachtfeldern)
- deine Tode (und damit, wer dich getötet hat)
- deine Berufe und Rezepte
- deine Wanted-Sichtungen
- deine Level-ups

Geteilt wird nur innerhalb deiner Gilde. Daten verschiedener Gilden und Realms bleiben getrennt.

## Grenzen auf WoW Forever

- Das Kampflog ist auf Forever für Addons gesperrt. Den Killer liest das Addon aus dem **Todesrückblick** (Death Recap) des Spiels. Ist dort kein Spieler eindeutig als Killer erkennbar, steht in der Meldung „Ursache unbekannt“, und auf der Wanted-Liste zählt nichts.
- Wer gerade im Ziel oder im Kampf war, gilt nie automatisch als Killer.
- Mit `/am diag death` siehst du, was das Spiel beim letzten Tod geliefert hat.

## Mitarbeiten

Ablauf, Einrichtung, Versionen und Releases: [CONTRIBUTING.md](CONTRIBUTING.md). Hinweise für KI-Agents wie Cursor oder Claude Code: [AGENTS.md](AGENTS.md).

Tests laufen ohne WoW mit LuaJIT, aus dem Repo-Root:

```
luajit Tests/run_all.lua
```

Was sich nur im Spiel prüfen lässt: [Tests/CLIENT_CHECKLIST.md](Tests/CLIENT_CHECKLIST.md).
