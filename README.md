# AngryMurlocs

Gilden-Helfer für **WoW Forever** (Interface `16001`): Murloc-Kartenpins, Berufsliste, Wanted-Fahndung, Todes-/Level-Toasts — alles über den Gilden-Addonkanal.

**Version:** 0.11.1

**Download:** [CurseForge](https://www.curseforge.com/wow/addons/angry-murlocs) · **Quellcode:** [GitHub](https://github.com/AngryMurlocs/wow-angry-murlocs-addon)

## Features

- Gilden-Kartenpins mit **klassenbezogenen Murloc-Köpfen** (Zoom-feste Größe, Default **18**; Styles: Heads / Body / Rings; Ausfaden vor dem Verschwinden nach 60 s). Mehrere Spieler auf einem Punkt stehen nebeneinander statt übereinander.
- Berufsliste mit Gilden-Sync, **Online** (Addon kürzlich gehört), Sortierung und Paging (Top 40 von N)
- Wanted-Liste mit Zählung **pro Opfer** (kein Doppelzählen über Live/Relay/Sync), Sync mit sichtbarem Status, lokales Ausblenden
- Wanted-**Sichtungen** beim Anwählen: Frische frisch (&lt;60 s) / aktuell (&lt;5 Min) / veraltet
- Todes- und Level-Up-Toasts (gemeinsame Queue, Cooldown, Kampf wartet)
- Privacy-Schalter (Position, Tod/Wanted, Berufe, Sichtungen, Level-Ups) und `/am diag` (nur lokal)
- Deutsch / Englisch

Kommunikation über den Gilden-Addonkanal (Prefix `GildenRadar` für Kompatibilität). Lange Nachrichten werden fragmentiert. Wanted- und Berufsdaten sind nach **Gilde + Realm** getrennt.

**Grenze Forever:** Der Kampflog (CLEU) ist gesperrt. Ziel/Angreifer zählen **nicht** als Killer. Ab **0.8.1** kann Death Recap bei `Player-*`-GUID Wanted + Toast setzen; Mob/Umgebung nur Toast ohne Wanted-Credit. Recap-Qualität auf Forever: bitte mit `/am diag death` prüfen — nicht als immer zuverlässig annehmen.

## Installation

1. Über [CurseForge](https://www.curseforge.com/wow/addons/angry-murlocs) installieren (CurseForge-App) oder das Release-ZIP von dort entpacken.
2. Ordner `AngryMurlocs` nach  
   `World of Warcraft\_forever_\Interface\AddOns\` kopieren.
3. Spiel neu starten bzw. Addons neu laden (`/reload`).

**Upgrade von 0.5.x:** SavedVariables bleiben erhalten. Main/Craft-Module sind entfernt — alte SV-Keys liegen harmlos weiter; Tabs/Slash dafür gibt es nicht mehr. Pin-Größe wird von älteren Defaults (8/11/14) einmalig auf **18** migriert, sofern du sie nicht selbst geändert hast. Die flache Wanted-Liste aus 0.4.0 wird einmalig in den Guild-Scope migriert.

**Upgrade auf 0.7.0 / 0.8.0:** SavedVariables-Schema **2** (seit 0.7.0). Bestehende Wanted-Level bleiben als Altdaten (`legacy`) erhalten. 0.8.0 ändert nur UI/Frische/Toasts/Berufe-Liste — kein neues Schema. 0.6.x und 0.7+ tauschen keine Wanted-Daten aus — alle Gildenmitglieder sollten aktualisieren. Details und Grenzen: [CHANGELOG.md](CHANGELOG.md).

## Slash-Befehle

| Befehl | Wirkung |
|--------|---------|
| `/am` | Hauptfenster (Berufe + Navigation) |
| `/am help` | Hilfe |
| `/am config` | Esc-Settings (Stub) bzw. Addon-Tab; Alias `options` / `settings` |
| `/am wanted` | Wanted-Liste / Sichtungen |
| `/am sync` | Gildendaten jetzt abgleichen (Berufe + Wanted) |
| `/am prof` | Berufsliste |
| `/am share on\|off` | Position teilen |
| `/am map` | Kartenpins an/aus |
| `/am prof share on\|off` | Berufe teilen |
| `/am diag on\|off\|show\|death` | Lokale Diagnose (wird nicht gesendet) |

Aliases: `/angrymurlocs`, `/gr`

## Bedienung

- **Kartenpins:** Klassen-Murlocs auf der Weltkarte; Größe in den Optionen (8–24, gilt für Heads/Body/Rings). Style unter Opt → Map. Ohne Update ab ~45 s blasser, bei 60 s weg. Liegen mehrere auf einem Haufen, rücken sie auseinander (2 nebeneinander, 3 Dreieck, 4 Raster, 5 als 2 über 3, ab 6 einer in der Mitte). Eine Reihe bleibt an den echten Positionen.
- **Berufe / Wanted:** Navigation wechselt Fenster exklusiv (kein Übereinanderlegen). Auto-Sync einmal pro Sitzung (Login/Reload) und bei Gildenwechsel; sonst Sync-Button bzw. `/am sync`. Status im Tab „Allgemein“ und im Wanted-Fenster.
- **Wanted-Zählung (feste Gilden-Regeln):** Jedes Opfer führt pro Killer einen eigenen Zähler; Level = Altdaten + Summe der Opferzähler. Pair-CD **10s** beim Opfer. Duell/BG/Arena/unbekannter Kontext zählen nie. Ränge Markiert→Gildenschreck. Kein Zeit-Expire; Safety-Cap **1000**.
- **Killer-Quelle auf Forever:** CLEU gesperrt; Ziel/Angreifer gelten nicht als Killer. Death Recap mit `Player-*` kann Wanted zählen. Tödliche Treffer haben Vorrang vor älteren Treffern; ausdrücklich nicht tödliche Treffer und unvollständige Quellen bleiben „Ursache unbekannt“. Fehlt der Recap zunächst, wartet das Addon höchstens eine Sekunde auf die Daten. Sprungbewegung oder ein Atembalken allein beweisen keinen Fall-/Ertrinkungstod. `/am diag death` zur Prüfung.
- **Liste:** Top 40 von N mit Seiten, Suche, Sortierung nach Level oder zuletzt gesehen. Klick öffnet Details (Kill, Sichtung, Quellen, Opferzähler).
- **Wanted-Sichtung:** Wanted-Spieler ins Ziel nehmen → Auto-Meldung an die Gilde (Zone = Zone des Melders; 60 s Sendepause). Frische: frisch / aktuell / veraltet (5+ Min).
- **Minimap:** Linksklick Hauptfenster, Rechtsklick Settings.
- **Ingame-Prüfung:** [Tests/CLIENT_CHECKLIST.md](Tests/CLIENT_CHECKLIST.md).

## Einstellungen

Addon-Optionen (Seitenleiste): Freigaben, Karte, Level-Up / Tod / Sichtungen, Oberfläche (Hauptfenster + Minimap). Auto-Wanted-Regeln sind **fest im Addon** (keine Slider).

## Neu in 0.9.0 (Kurz)

- Neue Klassen-Köpfe für die Kartenpins
- Überlappende Pins bilden eine feste Gruppe statt sich zu verdecken

## Neu in 0.8.0 (Kurz)

- Sichtungs-Frische: frisch (&lt;60 s) / aktuell (&lt;5 Min) / veraltet
- Pin-Ausfaden in den letzten 15 s vor dem Verschwinden; Hover hebt den Pin
- Berufe: Online (Addon gehört), Sortierung, Paging Top 40 von N
- Gemeinsame Toast-Queue (Tod vor Level-Up, Cooldown, Kampf wartet)

## Neu in 0.7.0 (Kurz)

- Ehrliche Wanted-Zählung pro Opfer, keine Ziel-Beschuldigung
- Sync mit einem Antwortenden, Seiten, Status und Sperre
- Lokales Ausblenden statt Löschen
- Privacy: eigene Tode nur bei „Gilden-Tode teilen“, Berufe-Cache pro Gilde
- `/am diag` für lokale Diagnose

## Tests (Entwicklung)

Reine Lua-Logik wird ohne Client mit LuaJIT/Lua 5.1 getestet, aus dem Repo-Root:

```
luajit Tests/run_all.lua
```

Ingame-Punkte: [Tests/CLIENT_CHECKLIST.md](Tests/CLIENT_CHECKLIST.md). `Tests/` wird nicht mit verpackt (siehe [.pkgmeta](.pkgmeta)).

## Hinweis

Benötigt eine Gilde und Online-Gildenmitglieder mit demselben Addon (**0.7+**, ideal **0.8.0**) für Sync-Features. Ältere Clients ignorieren unbekannte Nachrichtentypen; 0.7+ ignoriert die Wanted-Nachrichten von 0.6.x.

Siehe auch [CHANGELOG.md](CHANGELOG.md), [CONTRIBUTING.md](CONTRIBUTING.md) (Mitarbeiten, Ablauf, Releases) und [DEV.md](DEV.md) (allgemeine WoW-Addon-Referenz).
