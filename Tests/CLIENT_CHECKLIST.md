# AngryMurlocs 0.9.0 — Client-Checkliste (WoW Forever)

Diese Punkte lassen sich nur im echten Client prüfen. Die Lua-Tests (`luajit Tests/run_all.lua`) simulieren Logik, Protokoll und mehrere Clients mit gestubbter WoW-API. Sie ersetzen keinen Ingame-Test.

Vorbereitung: Mindestens zwei Accounts oder zwei Gildenmitglieder mit 0.7+, ideal 0.8.1; optional ein drittes mit 0.6.1. Vorher SavedVariables sichern (`WTF\Account\<Account>\SavedVariables\AngryMurlocs.lua`). Auf allen Clients `/am diag on`.

Ergebnis je Punkt notieren: OK / Fehler + `/am diag show`-Auszug.

## 0. Laden und Migration

- [ ] Addon lädt ohne Lua-Fehler (BugSack). Chat zeigt „AngryMurlocs 0.9.0 loaded“.
- [ ] Bestehende Wanted-Einträge aus 0.6.1 sind noch da, mit demselben Level (Tooltip: „Altdaten aus 0.6.x“).
- [ ] Teilen-Einstellungen, Pin-Stil, Pin-Größe und Toast-Positionen sind unverändert.
- [ ] `/reload` zweimal: Level und Einträge bleiben gleich.

## 6. Viele Mitglieder loggen gleichzeitig ein

- [ ] 3+ Mitglieder loggen innerhalb weniger Sekunden ein. Nach ca. 30 s zeigt Tab „Allgemein“ bei allen „Wanted-Sync: vollständig …“ oder „Kein antwortendes Gildenmitglied“ (nur wenn sonst niemand 0.7+ hat).
- [ ] `/am diag show`: `sent_*`-Zähler steigen nicht weiter, wenn niemand etwas tut (keine Sync-Schleife). `queue=0` nach spätestens 2 Minuten.
- [ ] Ladebildschirm (Instanz betreten/verlassen) startet **keinen** neuen Wanted-Sync (Diag-Log zeigt kein neues `sync pending`).
- [ ] Sync-Button ist während des Syncs grau und danach wieder klickbar.
- [ ] Kein Disconnect und keine Chat-Drosselungsmeldung während des Syncs.

## 8. Sichtungs-Frische + Pin-Fading (0.8.0+)

- [ ] Wanted-Spieler anvisieren: Sichtung erscheint bei anderen mit Zone und Melder.
- [ ] Innerhalb ~60 s: Liste/Tooltip „frisch“ (+); nach 1–5 Min „aktuell“; nach 5+ Min „veraltet“ (*). Panel offen lassen — Markierung wechselt ohne Reload.
- [ ] Weltkarte: Gilden-Pin voll sichtbar; nach ~45 s ohne Update blasser; bei 60 s weg.
- [ ] Zwei Pins auf demselben Punkt: nebeneinander, Reihenfolge bleibt nach einem Update gleich. Drei als Dreieck, vier als Raster. Eine Reihe von Spielern entlang einer Straße bleibt auf den echten Positionen.
- [ ] Karte zoomen: die Gruppe bleibt zusammen und die Pins überdecken sich nicht neu. Hover hebt den Pin und zeigt die Frische-Zeile.
- [ ] Berufe: Online zuerst; Offline gedimmt mit ·; bei >40 Einträgen Seiten `<` `>` und Kopfzeile „Top 40 von N“.
- [ ] Mehrere Tode/Level-Ups schnell hintereinander: Toasts nacheinander (Tod vor Level), kein Überlappen, im Kampf Pause bis Kampfende.

## 11. Gilden-/Realmwechsel und gemischte Versionen

- [ ] Charakter in Gilde B einloggen: Gilde-A-Wanted-Einträge und Berufe erscheinen **nicht**.
- [ ] Zurück zu Gilde A: alte Einträge sind wieder da, nichts aus Gilde B ist hineingemischt.
- [ ] 0.6.1-Client meldet einen Tod/Clear: 0.7+-Clients ändern nichts. `/am diag show` zählt `legacy_ignored`.
- [ ] 0.7+-Sync-Anfrage wird von 0.6.1-Clients nicht beantwortet (erwartet).

## 12. Bestehende Funktionen

- [ ] Pin-Stile Heads / Body / Rings wechseln; Größenregler wirkt auf alle drei.
- [ ] Wanted-Suche, Sortierung (Gefahrenstufe / zuletzt gesehen), Seiten `<` `>`; Fußzeile „1–40 von N · Seite …“.
- [ ] Shift+Klick blendet nur lokal aus (anderer Client sieht den Eintrag weiter). Button „Ausgeblendete wieder anzeigen“ bzw. `/am wanted unhide all` bringt sie zurück.
- [ ] Minimap: Button ist Kind von `Minimap` (UI-Packs können ihn sammeln); Linksklick Hauptfenster, Rechtsklick Einstellungen; Ziehen verschiebt den Button.
- [ ] `/am config` öffnet Esc-Settings-Kategorie (Stub) wenn `Settings` API da; Button „Einstellungen öffnen“ → Addon-Tab.
- [ ] Optionen: Häkchen „Gilden-Tode teilen“ zeigt den Hinweistext; Ausschalten → eigener Tod erscheint bei anderen weder als Toast noch in Wanted; Positions-Pin zeigt keinen Tot-Status.
- [ ] `/am sync`, `/am diag show`, `/am diag off` funktionieren.

## 13. UI-Redesign — Sichtprüfung (nur Client; Lua-Smoke deckt Layout nicht ab)

### Übersicht (General)

- [ ] Aktiver Tab: dunkler Hintergrund + grüne Unterstreichung, **nicht** ausgegraut wie deaktiviert.
- [ ] Kopf: Gildenname links, Version rechts; darunter kurzer Wanted-Abgleich-Status.
- [ ] Drei Statuskarten (Addon aktiv / Kartenpins / Wanted) mit Tooltips; Aktiv ≠ Gilden-Online.
- [ ] Schnellaktionen Position/Pins An/Aus farbig; Sync zeigt während Lauf „Abgleich läuft …“ und ist gesperrt.
- [ ] Aktivitätsliste scrollt bis 20 Ereignisse; Leerzustand verständlich; Format „Typ · Spieler · relative Zeit“.
- [ ] Aufklappbares „Details“: Freigaben, Hilfe, ohne Überlappung mit der Feed-Liste.
- [ ] DE- und EN-Texte: nichts abgeschnitten/überlappend.

### Berufe

- [ ] Zwei Filterzeilen: Suche, Beruf („Alle Berufe“), Mindestfertigkeit, „Nur kürzlich aktive“, Reset.
- [ ] Beruf gewählt + Min-Skill: nur dieser Beruf zählt (anderer Hochskill reicht nicht).
- [ ] Zeilenhöhe/Hover/Klassenfarbe nur beim Namen; Skill klar lesbar; lange Texte im Tooltip.
- [ ] Klick → Menü „Anflüstern“ öffnet Whisper.
- [ ] Sort-Labels „Kürzlich aktiv zuerst“ / „Name A–Z“; Fußzeile „1–40 von N · Seite …“; Pfeile am Rand disabled.
- [ ] Leer: Cache leer vs. keine Treffer (+ Reset-Aktion).

### Wanted

- [ ] Vier Spalten: Spieler · Gefahrenstufe (`N · Rang`, **kein** `Lv.N`) · Letzte Sichtung · Zone.
- [ ] Ohne Sichtung: „Noch nicht gesichtet“; mit Sichtung: Frisch/Aktuell/Veraltet + Alter (kein +/*).
- [ ] Warnfarben nur auf Gefahrenstufe und Sichtungsstatus.
- [ ] Klick öffnet Detailbereich unter der Liste (Liste schrumpft, keine Überlappung); Auswahl bleibt nach Refresh.
- [ ] Detail: Rang, Melder, Opfer, Quellen; Button „Nur bei mir ausblenden“.
- [ ] Filter „Nur Sichtungen der letzten 5 Minuten“; Sort Gefahrenstufe / Zuletzt gesehen.
- [ ] Lange Namen/Zonen gekürzt + Tooltip; >40 Einträge Seitenwechsel; eigene Leerzustände.

## Killer-Quelle + Death Recap (0.8.1)

Ziel: CLEU bleibt gesperrt; Recap `Player-*` darf Wanted zählen. Ziel/Angreifer allein nie.

1. `/am diag on` auf dem Opfer-Client.
2. Kontrolliert sterben: (a) durch einen feindlichen Spieler in der offenen Welt, (b) durch einen NPC, während ein feindlicher Spieler im Ziel ist, (c) durch Fallschaden, (d) im Duell.
3. Nach jedem Tod `/am diag death` und den Ausdruck sichern.
4. Auswerten:
   - Zeile `apis:` — ist `C_DeathInfo`, `C_DeathRecap` oder `GetDeathRecapLink` `true`?
   - Zeilen `recap:` / `recap[n]:` — nach PvP-Tod (a): steht ein Tätername (`source=…`, `guid=Player`)? Bei NPC+falsches Ziel (b): darf **nicht** der Spieler im Ziel als Recap-Source erscheinen.
   - Zeile `registered:` — welche Events ließen sich registrieren?
   - Erwartet bei (a) mit Recap `Player-*`: Wanted-Zähler + Spieler-Toast (0.8.1). Bei (b)/(c): Toast ohne Wanted-Credit bzw. Env; bei (d): ausgeschlossen.
   - Ziel/Angreifer ohne Recap-Player: kein Wanted (`unclear_killer` / `no_player`).
5. Ergebnis an die Entwicklung geben. Forever-Recap-Vollständigkeit bleibt **client-confirmed** erst nach diesem Check.
