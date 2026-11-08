# AngryMurlocs

Gilden-Helfer für **WoW Forever** (Interface `16001`): Murloc-Kartenpins, Berufsliste, Wanted-Fahndung, Todes-/Level-Toasts — alles über den Gilden-Addonkanal.

**Version:** 0.8.1

## Features

- Gilden-Kartenpins mit **klassenbezogenen Mini-Murloc-Icons** (Zoom-feste Größe, Default **18**; Styles: Heads / Body / Rings; Ausfaden vor dem Verschwinden nach 60 s)
- Berufsliste mit Gilden-Sync, **Online** (Addon kürzlich gehört), Sortierung und Paging (Top 40 von N)
- Wanted-Liste mit Zählung **pro Opfer** (kein Doppelzählen über Live/Relay/Sync), Sync mit sichtbarem Status, lokales Ausblenden
- Wanted-**Sichtungen** beim Anwählen: Frische frisch (&lt;60 s) / aktuell (&lt;5 Min) / veraltet
- Todes- und Level-Up-Toasts (gemeinsame Queue, Cooldown, Kampf wartet)
- Privacy-Schalter (Position, Tod/Wanted, Berufe, Sichtungen, Level-Ups) und `/am diag` (nur lokal)
- Deutsch / Englisch

Kommunikation über den Gilden-Addonkanal (Prefix `GildenRadar` für Kompatibilität). Lange Nachrichten werden fragmentiert. Wanted- und Berufsdaten sind nach **Gilde + Realm** getrennt.

**Grenze Forever:** Der Kampflog ist gesperrt. Ziel/Angreifer zählen **nicht** als Killer — Auto-Wanted ist damit praktisch aus, bis eine verlässliche Quelle gefunden ist (`/am diag death`).

## Installation

1. Release-ZIP entpacken.
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
| `/am config` | Einstellungen (`options` / `settings`) |
| `/am wanted` | Wanted-Liste / Sichtungen |
| `/am wanted unhide all` | Lokal ausgeblendete Wanted-Einträge wieder zeigen |
| `/am sync` | Gildendaten jetzt abgleichen (Berufe + Wanted) |
| `/am prof` | Berufsliste |
| `/am share on\|off` | Position teilen |
| `/am map` | Kartenpins an/aus |
| `/am prof share on\|off` | Berufe teilen |
| `/am diag on\|off\|show\|death` | Lokale Diagnose (wird nicht gesendet) |

Aliases: `/angrymurlocs`, `/gr`

## Bedienung

- **Kartenpins:** Klassen-Murlocs auf der Weltkarte; Größe in den Optionen (8–24, gilt für Heads/Body/Rings). Style unter Opt → Map. Ohne Update ab ~45 s blasser, bei 60 s weg.
- **Berufe / Wanted:** Navigation wechselt Fenster exklusiv (kein Übereinanderlegen). Auto-Sync einmal pro Sitzung (Login/Reload) und bei Gildenwechsel; sonst Sync-Button bzw. `/am sync`. Status im Tab „Allgemein“ und im Wanted-Fenster.
- **Wanted-Zählung (feste Gilden-Regeln):** Jedes Opfer führt pro Killer einen eigenen Zähler; Level = Altdaten + Summe der Opferzähler. Pair-CD **10s** beim Opfer. Duell/BG/Arena/unbekannter Kontext zählen nie. Ränge Markiert→Gildenschreck. Kein Zeit-Expire; Safety-Cap **1000**.
- **Killer-Quelle auf Forever:** Der Kampflog ist dort gesperrt. Ziel oder angreifender Feind gelten **nicht** als Killer — solche Tode erscheinen als „Ursache unbekannt“ und zählen nicht. `/am diag death` hilft bei der Quellensuche.
- **Ausblenden:** Shift+Klick blendet **nur lokal** aus (nicht für die Gilde gelöscht). Steigt das Level, erscheint der Eintrag wieder. `/am wanted unhide all` macht alles rückgängig.
- **Liste:** Top 40 von N mit Seiten, Suche, Sortierung nach Level oder zuletzt gesehen. Tooltip zeigt Quellen und Datenalter.
- **Wanted-Sichtung:** Wanted-Spieler ins Ziel nehmen → Auto-Meldung an die Gilde (Zone = Zone des Melders; 60 s Sendepause). Frische: frisch / aktuell / veraltet (5+ Min).
- **Minimap:** Linksklick Hauptfenster, Rechtsklick Settings.
- **Ingame-Prüfung:** [Tests/CLIENT_CHECKLIST.md](Tests/CLIENT_CHECKLIST.md).

## Einstellungen

Addon-Optionen: Teilen, Pins (Anzeige + Größe + Style), Toast-Layout. Auto-Wanted-Regeln sind **fest im Addon** (keine Slider).

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

Siehe auch [CHANGELOG.md](CHANGELOG.md) und [DEV.md](DEV.md) (allgemeine WoW-Addon-Referenz).
