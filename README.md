# AngryMurlocs

Gilden-Helfer für **WoW Forever** (Interface `16001`).

**Version:** 0.5.0  
**Projekt:** https://gitlab.ngit.ovh/murlocs/addon-angrymurlocs

## Features

- Gilden-Kartenpins (Position teilen)
- Berufsliste der Gildenmitglieder
- Wanted-Liste (Spieler-Killer) inkl. **automatischer Sichtungen** beim Anwählen
- Optional **Main/Twink-Zuordnung** (manuell, Gilden-Sync; Anzeige in Berufsliste + Pin-Tooltip)
- **Handwerksanfragen** in der Gilde (Item-Link, Menge, Material, Notiz, Vergabe)
- Todes-Toasts und Level-Up-Toasts (Gildenkanal)
- Deutsch / Englisch

Kommunikation über den Gilden-Addonkanal (Prefix `GildenRadar` für Kompatibilität). Lange Nachrichten werden fragmentiert; Item-Links werden pipe-sicher übertragen. Wanted-, Main- und Craft-Daten sind nach **Gilde + Realm** getrennt.

## Installation

1. Release-ZIP entpacken (oder dieses Repo klonen).
2. Ordner `AngryMurlocs` nach  
   `World of Warcraft\_forever_\Interface\AddOns\` kopieren.
3. Spiel neu starten bzw. Addons neu laden.

**Upgrade von 0.4.0:** SavedVariables bleiben erhalten. Die flache Wanted-Liste wird einmalig in den aktuellen Guild-Scope migriert.

## Slash-Befehle

| Befehl | Wirkung |
|--------|---------|
| `/am` | Hauptfenster (Berufe + Navigation) |
| `/am help` | Hilfe |
| `/am wanted` | Wanted-Liste / Sichtungen |
| `/am craft` | Handwerksanfragen |
| `/am main` | Main/Twink-Fenster |
| `/am main <Name>` | Main für diesen Charakter setzen |
| `/am main clear` | Main-Zuordnung entfernen |
| `/am prof` | Berufsliste |
| `/am share on\|off` | Position teilen |
| `/am map` | Kartenpins an/aus |
| `/am prof share on\|off` | Berufe teilen |

Aliases: `/angrymurlocs`, `/gr`

## Bedienung (neu in 0.5.0)

- **Wanted-Sichtung:** Wanted-Spieler ins Ziel nehmen → Auto-Meldung an die Gilde (Zone = Zone des Melders; Kill-Zähler unverändert; 60s Sendepause). Nach 30 Min als veraltet markiert, Eintrag bleibt. Entfernen nur per **Shift+Klick**.
- **Main/Twink:** Freiwillige Zuordnung; nur der eigene Charakter darf seine Map ändern/löschen.
- **Craft:** Gegenstand per Shift-Klick einfügen; Interessenten melden sich; nur der Auftraggeber vergibt und schließt ab. Keine automatische Rezeptprüfung.

## Einstellungen

Addon-Optionen: Teilen (inkl. Sichtungen / Sichtungs-Alerts), Pins, Toast-Layout.

## Hinweis

Benötigt eine Gilde und Online-Gildenmitglieder mit demselben Addon für Sync-Features. Ältere Clients ignorieren unbekannte Nachrichtentypen.

Siehe auch [CHANGELOG.md](CHANGELOG.md).
