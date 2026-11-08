# AngryMurlocs 0.8.0 — Client-Checkliste (WoW Forever)

Diese Punkte lassen sich nur im echten Client prüfen. Die Lua-Tests (`luajit Tests/run_all.lua`) simulieren Logik, Protokoll und mehrere Clients mit gestubbter WoW-API. Sie ersetzen keinen Ingame-Test.

Vorbereitung: Mindestens zwei Accounts oder zwei Gildenmitglieder mit 0.7.0, optional ein drittes mit 0.6.1. Vorher SavedVariables sichern (`WTF\Account\<Account>\SavedVariables\AngryMurlocs.lua`). Auf allen Clients `/am diag on`.

Ergebnis je Punkt notieren: OK / Fehler + `/am diag show`-Auszug.

## 0. Laden und Migration

- [ ] Addon lädt ohne Lua-Fehler (BugSack). Chat zeigt „AngryMurlocs 0.8.0 loaded“.
- [ ] Bestehende Wanted-Einträge aus 0.6.1 sind noch da, mit demselben Level (Tooltip: „Altdaten aus 0.6.x“).
- [ ] Teilen-Einstellungen, Pin-Stil, Pin-Größe und Toast-Positionen sind unverändert.
- [ ] `/reload` zweimal: Level und Einträge bleiben gleich.

## 6. Viele Mitglieder loggen gleichzeitig ein

- [ ] 3+ Mitglieder loggen innerhalb weniger Sekunden ein. Nach ca. 30 s zeigt Tab „Allgemein“ bei allen „Wanted-Sync: vollständig …“ oder „Kein antwortendes Gildenmitglied“ (nur wenn sonst niemand 0.7 hat).
- [ ] `/am diag show`: `sent_*`-Zähler steigen nicht weiter, wenn niemand etwas tut (keine Sync-Schleife). `queue=0` nach spätestens 2 Minuten.
- [ ] Ladebildschirm (Instanz betreten/verlassen) startet **keinen** neuen Wanted-Sync (Diag-Log zeigt kein neues `sync pending`).
- [ ] Sync-Button ist während des Syncs grau und danach wieder klickbar.
- [ ] Kein Disconnect und keine Chat-Drosselungsmeldung während des Syncs.

## 8. Sichtungs-Frische + Pin-Fading (0.8.0)

- [ ] Wanted-Spieler anvisieren: Sichtung erscheint bei anderen mit Zone und Melder.
- [ ] Innerhalb ~60 s: Liste/Tooltip „frisch“ (+); nach 1–5 Min „aktuell“; nach 5+ Min „veraltet“ (*). Panel offen lassen — Markierung wechselt ohne Reload.
- [ ] Weltkarte: Gilden-Pin voll sichtbar; nach ~45 s ohne Update blasser; bei 60 s weg.
- [ ] Zwei Pins übereinander: neuerer oben; Hover hebt den Pin und zeigt Frische-Zeile.
- [ ] Berufe: Online zuerst; Offline gedimmt mit ·; bei >40 Einträgen Seiten `<` `>` und Kopfzeile „Top 40 von N“.
- [ ] Mehrere Tode/Level-Ups schnell hintereinander: Toasts nacheinander (Tod vor Level), kein Überlappen, im Kampf Pause bis Kampfende.

## 11. Gilden-/Realmwechsel und gemischte Versionen

- [ ] Charakter in Gilde B einloggen: Gilde-A-Wanted-Einträge und Berufe erscheinen **nicht**.
- [ ] Zurück zu Gilde A: alte Einträge sind wieder da, nichts aus Gilde B ist hineingemischt.
- [ ] 0.6.1-Client meldet einen Tod/Clear: 0.7.0-Clients ändern nichts. `/am diag show` zählt `legacy_ignored`.
- [ ] 0.7.0-Sync-Anfrage wird von 0.6.1-Clients nicht beantwortet (erwartet).

## 12. Bestehende Funktionen

- [ ] Pin-Stile Heads / Body / Rings wechseln; Größenregler wirkt auf alle drei.
- [ ] Wanted-Suche, Sortierung (Level / zuletzt gesehen), Seiten `<` `>`; Kopfzeile „Top 40 von N“ bei mehr als 40 Einträgen.
- [ ] Shift+Klick blendet nur lokal aus (anderer Client sieht den Eintrag weiter). `/am wanted unhide all` bringt ihn zurück.
- [ ] Minimap: Linksklick Hauptfenster, Rechtsklick Einstellungen; Ziehen verschiebt den Button.
- [ ] Optionen: Häkchen „Gilden-Tode teilen“ zeigt den Hinweistext; Ausschalten → eigener Tod erscheint bei anderen weder als Toast noch in Wanted; Positions-Pin zeigt keinen Tot-Status.
- [ ] `/am sync`, `/am diag show`, `/am diag off` funktionieren.

## Killer-Quelle (Diagnose)

Ziel: herausfinden, ob Forever eine verlässliche Täterquelle bietet. Bis dahin zählt **kein** Tod automatisch.

1. `/am diag on` auf dem Opfer-Client.
2. Kontrolliert sterben: (a) durch einen feindlichen Spieler in der offenen Welt, (b) durch einen NPC, während ein feindlicher Spieler im Ziel ist, (c) durch Fallschaden, (d) im Duell.
3. Nach jedem Tod `/am diag death` und den Ausdruck sichern.
4. Auswerten:
   - Zeile `apis:` — ist `C_DeathInfo` oder `GetDeathRecapLink` `true`?
   - Zeile `registered:` — welche Events ließen sich registrieren?
   - Zeilen `-x.xs EVENT ...` — enthält eines bei (a) den Täternamen und bei (b) **nicht** den Spieler im Ziel?
   - Erwartet für alle Fälle in 0.7.0: `-> unclear_killer`, `-> no_player` oder `-> excluded_duel`; kein neuer Wanted-Eintrag.
5. Ergebnis an die Entwicklung geben. Nur eine Quelle, die (a) richtig und (b) nicht falsch zuordnet, darf später `reliable = true` setzen.
