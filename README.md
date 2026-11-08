# AngryMurlocs

Gilden-Helfer für **WoW Forever** (Interface `16001`).

**Version:** 0.5.7  
**Projekt:** https://gitlab.ngit.ovh/murlocs/addon-angrymurlocs

## Features

- Gilden-Kartenpins mit **klassenbezogenen Mini-Murloc-Icons** (Zoom-feste Größe, Default **18**)
- Berufsliste der Gildenmitglieder
- Wanted-Liste (Spieler-Killer) inkl. **automatischer Sichtungen** beim Anwählen
- Optional **Main/Twink-Zuordnung** (manuell, Gilden-Sync; Anzeige in Berufsliste + Pin-Tooltip)
- **Handwerksanfragen** in der Gilde (Item-Link, Menge, Material, Notiz, Vergabe)
- Todes-Toasts und Level-Up-Toasts (Gildenkanal; längere Standardzeiten)
- Deutsch / Englisch

Kommunikation über den Gilden-Addonkanal (Prefix `GildenRadar` für Kompatibilität). Lange Nachrichten werden fragmentiert; Item-Links werden pipe-sicher übertragen. Wanted-, Main- und Craft-Daten sind nach **Gilde + Realm** getrennt.

## Installation

1. Release-ZIP entpacken (oder dieses Repo klonen).
2. Ordner `AngryMurlocs` nach  
   `World of Warcraft\_forever_\Interface\AddOns\` kopieren.
3. Spiel neu starten bzw. Addons neu laden.

**Upgrade:** SavedVariables bleiben erhalten. Pin-Größe wird von älteren Defaults (8/11/14) einmalig auf **18** migriert, sofern du sie nicht selbst geändert hast. Die flache Wanted-Liste aus 0.4.0 wird einmalig in den Guild-Scope migriert.

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

## Bedienung

- **Kartenpins:** Klassen-Murlocs auf der Weltkarte; Größe in den Optionen (8–24). Kein Kreis-Rand, nur das Icon.
- **Wanted-Sichtung:** Wanted-Spieler ins Ziel nehmen → Auto-Meldung an die Gilde (Zone = Zone des Melders; Kill-Zähler unverändert; 60s Sendepause). Nach 30 Min als veraltet markiert, Eintrag bleibt. Entfernen nur per **Shift+Klick**.
- **Main/Twink:** Freiwillige Zuordnung; nur der eigene Charakter darf seine Map ändern/löschen.
- **Craft:** Gegenstand per Shift-Klick einfügen; Interessenten melden sich; nur der Auftraggeber vergibt und schließt ab. Keine automatische Rezeptprüfung.

## Einstellungen

Addon-Optionen: Teilen (inkl. Sichtungen / Sichtungs-Alerts), Pins (Anzeige + Größe), Toast-Layout und Dauer.

## Neu seit 0.5.0 (Kurz)

- Klassen-Murloc-Pins statt generischer Marker; Zoom bleibt stabil
- Pin-Default-Größe 18; unsichtbare Pins durch WoW-kompatible TGAs behoben (0.5.7)
- Längere Toast-Defaults (Level-Up 8s, Tod 10s)

## Hinweis

Benötigt eine Gilde und Online-Gildenmitglieder mit demselben Addon für Sync-Features. Ältere Clients ignorieren unbekannte Nachrichtentypen.

Siehe auch [CHANGELOG.md](CHANGELOG.md).
