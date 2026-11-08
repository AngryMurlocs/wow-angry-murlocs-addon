# AngryMurlocs

Gilden-Helfer für **WoW Forever** (Interface `16001`).

**Version:** 0.6.0  
**Projekt:** https://gitlab.ngit.ovh/murlocs/addon-angrymurlocs

## Features

- Gilden-Kartenpins mit **klassenbezogenen Mini-Murloc-Icons** (Zoom-feste Größe, Default **18**)
- Berufsliste der Gildenmitglieder (Gilden-Sync)
- Wanted-Liste (Spieler-Killer) inkl. **automatischer Sichtungen** beim Anwählen und **Voll-Sync** in der Gilde
- Todes-Toasts und Level-Up-Toasts (Gildenkanal; längere Standardzeiten)
- Deutsch / Englisch

Kommunikation über den Gilden-Addonkanal (Prefix `GildenRadar` für Kompatibilität). Lange Nachrichten werden fragmentiert. Wanted- und Berufsdaten sind nach **Gilde + Realm** getrennt.

## Installation

1. Release-ZIP entpacken (oder dieses Repo klonen).
2. Ordner `AngryMurlocs` nach  
   `World of Warcraft\_forever_\Interface\AddOns\` kopieren.
3. Spiel neu starten bzw. Addons neu laden (`/reload`).

**Upgrade von 0.5.x:** SavedVariables bleiben erhalten. Main/Craft-Module sind entfernt — alte SV-Keys liegen harmlos weiter; Tabs/Slash dafür gibt es nicht mehr. Pin-Größe wird von älteren Defaults (8/11/14) einmalig auf **18** migriert, sofern du sie nicht selbst geändert hast. Die flache Wanted-Liste aus 0.4.0 wird einmalig in den Guild-Scope migriert.

## Slash-Befehle

| Befehl | Wirkung |
|--------|---------|
| `/am` | Hauptfenster (Berufe + Navigation) |
| `/am help` | Hilfe |
| `/am config` | Einstellungen (`options` / `settings`) |
| `/am wanted` | Wanted-Liste / Sichtungen |
| `/am prof` | Berufsliste |
| `/am share on\|off` | Position teilen |
| `/am map` | Kartenpins an/aus |
| `/am prof share on\|off` | Berufe teilen |

Aliases: `/angrymurlocs`, `/gr`

## Bedienung

- **Kartenpins:** Klassen-Murlocs auf der Weltkarte; Größe in den Optionen (8–24). Kein Kreis-Rand, nur das Icon.
- **Berufe / Wanted:** Navigation wechselt Fenster exklusiv (kein Übereinanderlegen). Sync-Button bzw. Auto-Sync nach Ladebildschirm.
- **Wanted-Sichtung:** Wanted-Spieler ins Ziel nehmen → Auto-Meldung an die Gilde (Zone = Zone des Melders; Kill-Zähler unverändert; 60s Sendepause). Nach 30 Min als veraltet markiert, Eintrag bleibt. Entfernen nur per **Shift+Klick**.
- **Minimap:** Linksklick Wanted, Rechtsklick Hauptfenster.

## Einstellungen

Addon-Optionen: Teilen (inkl. Sichtungen / Sichtungs-Alerts), Pins (Anzeige + Größe), Toast-Layout und Dauer.

## Neu seit 0.6.0 (Kurz)

- Main/Twink und Handwerk entfernt
- Stabile Berufs- und Wanted-Syncs; pixelgenaue Listen
- Kein Self-Duplikat in der Berufsliste; Fenster überlappen nicht mehr

## Hinweis

Benötigt eine Gilde und Online-Gildenmitglieder mit demselben Addon für Sync-Features. Ältere Clients ignorieren unbekannte Nachrichtentypen (inkl. Legacy MAIN/CRAFT).

Siehe auch [CHANGELOG.md](CHANGELOG.md).
