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
- [ ] Wanted-Zeile: Name in Klassenfarbe (nach Target-Sichtung oder POS/Prof-Cache). Detail zeigt Kill, Sichtung, Quellen, Opfer.
- [ ] Minimap: Button ist Kind von `Minimap` (UI-Packs können ihn sammeln); Linksklick Hauptfenster, Rechtsklick Einstellungen; Ziehen verschiebt den Button.
- [ ] `/am config` öffnet Esc-Settings-Kategorie (Stub) wenn `Settings` API da; Button „Einstellungen öffnen“ → Addon-Tab.
- [ ] Optionen: Hinweis unter „Gilden-Tode teilen“ / Privacy überdeckt keine Checkboxen.
- [ ] General: Discord-Icon kopiert Invite (URL nicht dauerhaft sichtbar); Popup mit EditBox.
- [ ] Optionen: Häkchen „Gilden-Tode teilen“ zeigt den Hinweistext; Ausschalten → eigener Tod erscheint bei anderen weder als Toast noch in Wanted; Positions-Pin zeigt keinen Tot-Status.
- [ ] Optionen bei **640 × 460**: linke Seitenleiste flach (kein rotes Panel-Chrom), aktiver Eintrag grün; Abstand vor Oberfläche. Haupt-Tabs etwas größer. Seitentitel rechts; Oberfläche: kurze Labels, Hint eng am Reset, größere Lücke zur Minimap-Gruppe; „Position sperren“ ausgegraut wenn Button aus (SV bleibt). Notes/Pins/Resets in der rechten Breite ohne Overlap. Sound-Menü schließt bei Bereichswechsel/Fenster zu.
- [ ] Optionen Layout-Flow: Freigaben — Notes unter Checkboxen, keine Überlagerung; Karte — kleiner Abstand vor Pin-Kacheln, „Pin-Größe“+Slider darunter sichtbar.
- [ ] `/am sync`, `/am diag show`, `/am diag off` funktionieren.
- [ ] Admin-Tab: nur als Gildenlead/Offizier sichtbar; als Member fehlt der Button. Promote/Demote → Button erscheint/verschwindet (ggf. Roster kurz aktualisieren). Placeholder-Text im Tab.

## 13. UI-Redesign — Sichtprüfung (nur Client; Lua-Smoke deckt Layout nicht ab)

### Übersicht (General)

- [ ] Aktiver Tab: dunkler Hintergrund + grüne Unterstreichung, **nicht** ausgegraut wie deaktiviert.
- [ ] Kopf: Gildenname links, Version rechts; darunter kurzer Wanted-Abgleich-Status.
- [ ] Drei Statuskarten (Addon aktiv / Kartenpins / Wanted) mit Tooltips; Aktiv ≠ Gilden-Online.
- [ ] Schnellaktionen Position/Pins An/Aus farbig; Sync zeigt während Lauf „Abgleich läuft …“ und ist gesperrt.
- [ ] Aktivitätsliste scrollt bis 20 Ereignisse; Leerzustand verständlich; Format „Typ · Spieler · relative Zeit“.
- [ ] Aufklappbares „Details“: Freigaben, Hilfe, ohne Überlappung mit der Feed-Liste.
- [ ] DE- und EN-Texte: nichts abgeschnitten/überlappend.

### Berufe (Unterreiter)

- [ ] Unterreiter **Übersicht** / **Rezeptsuche** gleiche Position/Breite; Start = Übersicht.
- [ ] Übersicht: Suche, Beruf, Mindestfertigkeit, „Nur kürzlich aktive“, Reset, Sync erreichbar.
- [ ] Beruf gewählt + Min-Skill: nur dieser Beruf zählt.
- [ ] Zeile: Name Klassenfarbe; feste Berufsicons + Skill; Nebenberufe als Icons; Volltext im Tooltip.
- [ ] Klick **Icon** → Rezeptliste dieses Mitglieds; Klick **Name** → Anflüstern.
- [ ] Sort / Seitenfuß / Leerzustände wie zuvor.

### Rezept-Unterkategorien (Unreleased — Client noch ungeprüft)

Voraussetzung: Forever-Build + Locale notieren. Lua-Suite deckt Logik ab; Darstellung/Scroll hier bestätigen.

- [ ] Mitgliederkatalog: Beruf → geschlossene Kategorieköpfe mit Zähler; Aufklappen nur dieser Gruppe; Footer „X Rezepte · Y Kategorien“.
- [ ] Suche im Katalog findet Treffer aus geschlossenen Gruppen; Suche leeren stellt Aufklappzustand wieder her.
- [ ] Detail → Zurück: Gruppen + Scrollposition erhalten.
- [ ] Unten Gruppe schließen / Suche bei Scroll ändern: keine leeren Löcher, keine Geister-IDs.
- [ ] Rezeptsuche: Beruf wählen → gleiche Unterkategorien; zwei Hersteller → eine Rezeptzeile; globale Suche ohne Beruf bleibt flat + Rank.
- [ ] Wechsel Beruf-Kategorien ↔ globale Suche: kein State-Leak; Gildenwechsel leert Gruppenzustand.
- [ ] Kategorie-Nachzug verschiebt Rezept aus „Sonstiges“ ohne Mat-Request-Sturm.
- [ ] DE/EN Labels; UI-Skalierung; großer Katalog (Pool bleibt begrenzt).
- [ ] Eigenes + fremdes Rezept: `categoryID` + lokalisierter Name verfügbar (sonst Restfall dokumentieren).

### Rezeptsuche + Detail (gemeinsam)

Voraussetzung: Forever `C_TradeSkillUI` (Interface 16001). Nur erfasste Cache-Rezepte.

- [ ] Rezeptsuche idle (leeres Feld / nur Leerzeichen, Alle Berufe): Crafting-Berufskategorien; keine Sammelberufe; Klick → Rezepte; Scroll/Filter-Reset beim Wechsel.
- [ ] Tippen (ohne Beruf): flache Trefferliste; Beruf gewählt: Unterkategorien mit Aufklappen; 3 Hersteller = 1 Rezeptzeile.
- [ ] Abdeckungszeile: „Rezeptdaten von X Charakteren · Y vollständige Berufskataloge“ (kein Gilden-Allwissen).
- [ ] Button **Rezeptdaten aktualisieren**: Status laden/fertig/Timeout; Tippen in Suche sendet **keine** Anfrage.
- [ ] Suche: „Healing Test“ findet „Test Healing Potion“; `item:118` / Itemlink; `recipe:ID`; Umlaute.
- [ ] Klick Treffer → Detail mit Herstellerwahl (Klassenfarbe, voller Name/Tooltip); Scan-Datum mit Tag+Uhr.
- [ ] Menge ± aktualisiert Benötigt/Fehlt/Summary; Beuteländerung bei offenem Detail aktualisiert Mats.
- [ ] Unbekannter Bestand ≠ 0; kein grünes „alles da“ bei unbekannten Mats.
- [ ] Anfrage: Entwurf wird bei Mengen-/Hersteller-/Materialwechsel **veraltet**; „Neu erstellen“ nötig; „In Flüsterchat“ gesperrt bis Rebuild.
- [ ] Chat-Ziel inkl. Realmbezug; bestehender Chat-Entwurf bleibt unberührt; kein Auto-Send.
- [ ] Neuer Katalog ohne Rezept → Anfrage gesperrt („kennt nicht mehr“); kein stiller Herstellerwechsel.
- [ ] Zurück stellt Suche/Filter/Scroll (bzw. Übersichtsliste) wieder her.
- [ ] Übersicht-Pfad: Icon → Liste → Detail; kein Scan → „Noch keine Rezeptdaten…“ (≠ „niemand in der Gilde“).
- [ ] Sammelberuf: verständlicher Leerzustand. DE-/EN-Lange Namen + UI-Skalierung >1 lesbar.

### Rezeptsuche — Zwei Gildenmitglieder (A teilt, B sucht)

Voraussetzung: Beide online in derselben Gilde; A hat Beruf mit bestätigtem Scan geteilt (`shareProfessions`).

1. **A:** Berufsfenster öffnen → Addon scannt → Katalog vollständig. Optional Filter leeren, „Rezepte aktualisieren“.
2. **B (frisch / ohne vorgefüllte Meta):** Berufe → Rezeptsuche → **Rezeptdaten aktualisieren** → Status beobachten (laden → fertig/Timeout).
3. **B:** Rezept per Namen suchen (nicht nur `#ID`). Detail öffnen: Zutaten/Ausgabe soweit verfügbar sichtbar.
4. **B:** Menge 1→2 bei offener Vorschau → Entwurf veraltet; „Neu erstellen“ → neuer Text; selbst in Flüsterchat übernehmen (A empfängt nichts automatisch).
5. **B:** Item in Beutel legen/entfernen bei offenem Detail → Need/Bag/Missing aktualisiert sich.
6. **A:** Rezept verlernen / leeren bestätigten Katalog pushen → bei B Anfrage für alte Kombi gesperrt.
7. Diag: `/am diag show` — `recv_PROFR` / ggf. Meta-Tags; keine Dauerschleife bei wiederholtem Klick (Cooldown).

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
   - Erwartet bei (a) mit aktuellem tödlichem Recap `Player-*`: Wanted-Zähler + Spieler-Toast. Bei (b)/(c): belegter Mob-/Umwelttod oder „Ursache unbekannt“, ohne Wanted-Credit; bei (d): ausgeschlossen.
   - Ziel/Angreifer ohne Recap-Player: kein Wanted (`unclear_killer` / `no_player`).
5. Ergebnis an die Entwicklung geben. Forever-Recap-Vollständigkeit bleibt **client-confirmed** erst nach diesem Check.

### Regression: Todesursachen im aktuellen Arbeitsstand

- [ ] Falltod nach Mobtreffern: Enthält der Recap `FALLING`, zeigt lokal und beim Gildenmitglied Fallschaden; ältere Mob-/Spielertreffer erhalten keinen Credit.
- [ ] Tödlicher Mobtreffer nach einem harmlosen Sprung: bleibt Mobtod. Ein frischer Bewegungshinweis darf den tödlichen Treffer nicht überschreiben.
- [ ] Kein verwertbarer Recap, feindlicher NPC im Ziel: „Ursache unbekannt“, kein erfundener Täter/Nahkampfangriff.
- [ ] Atemleiste starten, auftauchen und anschließend anders sterben: kein behauptetes Ertrinken. Ohne bestätigten Umweltschaden bleibt die Ursache unbekannt.
- [ ] Zauber/DoT/Fernkampf ohne `spellName`: nutzbare Zauber-ID auflösen oder unbekannten Angriff/Fernkampf anzeigen; kein erfundener Nahkampf.
- [ ] Direkt nach dem Tod Geist freilassen: ausstehende Zuordnung darf nicht verloren gehen. Wiederbelebung und Addon-Deaktivierung beenden dagegen ausstehende Versuche.
- [ ] Verzögert verfügbarer Recap: höchstens ein Todes-Toast/DEATH-Eintrag, mit Zone und Duell-/Instanzkontext vom Todeszeitpunkt.
- [ ] Alte Recap-Daten vom vorherigen Tod dürfen keinen neuen Wanted-Eintrag erzeugen. Tatsächliche Zeitstempel und Recap-Reihenfolge mit Client-Build dokumentieren.
