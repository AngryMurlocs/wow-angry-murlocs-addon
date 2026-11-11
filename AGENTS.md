# AGENTS.md

Anleitung für KI-Coding-Agents und IDE-Assistenten (Claude Code, Codex, Cursor, Copilot u. a.) in diesem Repository.

AngryMurlocs ist ein WoW-Addon (Client **Forever**, `## Interface: 16001`) für die Gilde Angry Murlocs: Kartenpins, Berufe/Rezepte, Wanted-Liste (Kopfgeld), Tod-/Level-Up-Toasts. Die Projektdoku ist auf Deutsch. **Commits, MR-Titel und `CHANGELOG.md` sind auf Englisch.** Spieltexte gibt es auf Englisch und Deutsch. Ablauf für Menschen inklusive Einrichtung: `CONTRIBUTING.md`.

## Tests

Reine Lua-Logik wird ohne WoW-Client mit LuaJIT oder Lua 5.1 getestet, **immer aus dem Repo-Root** (die Tests laden Dateien über relative Pfade):

```
luajit Tests/run_all.lua          # alle Testdateien
luajit Tests/WantedLogic_test.lua # eine einzelne Testdatei
```

- Lokal ist evtl. kein Lua installiert (`brew install luajit`).
- Eine neue Testdatei muss in die `tests`-Liste in `Tests/run_all.lua` eingetragen werden. Der Runner wertet die Ausgabe aus: Jede Datei muss `0 failures` ausgeben und darf kein `FAIL` enthalten.
- Tests sind einfache Skripte mit eigenem `check(name, cond)`-Helfer, ohne Framework.
- `Tests/sim.lua` ist ein Simulator für mehrere Clients: Jeder Client lädt die echten `Core/`-Dateien per `setfenv` in eine eigene Umgebung. Uhr und Gilden-Addon-Kanal teilen sich alle Clients. WoW-APIs sind nur so weit nachgebaut, wie der Code sie braucht. Dateien in seiner `FILES`-Liste müssen in derselben Reihenfolge stehen wie in der TOC.
- `Tests/L10n_test.lua` prüft: Jeder `U.L("KEY")` in den TOC-Dateien muss in `enUS` **und** `deDE` existieren, mit denselben Formatplatzhaltern in derselben Reihenfolge.
- Was nur im Spiel prüfbar ist: `Tests/CLIENT_CHECKLIST.md`.

Es gibt keinen Build-Schritt. Gepackt wird über den BigWigs-Packager (`.pkgmeta`), sobald ein Tag gepusht wird. `Tests/`, `tools/` und die Doku landen nicht im Paket.

## Architektur

**Ladereihenfolge = TOC-Reihenfolge.** `Localization` → `Core/*` → `AngryMurlocs.lua` → `Modules/*`. Alle Dateien teilen sich die globale Tabelle `AngryMurlocs` (lokal meist `GR`) und die Hilfsfunktionen `GR.Util` (`U`). Eine neue Datei muss in `AngryMurlocs.toc` eingetragen werden. Falls sie aus Tests geladen wird, gehört sie auch in `Tests/sim.lua`.

**Rein vs. WoW-abhängig.** `Core/Protocol.lua`, `Core/WantedLogic.lua` und `Core/Queue.lua` verwenden keine WoW-APIs und sind dadurch per CLI testbar. Wenn Logik testbar sein soll, gehört sie in solche Dateien, nicht in `Modules/`.

**Modulsystem** (`AngryMurlocs.lua`): `GR:NewModule(name)` / `GR:GetModule(name)`. Bei `PLAYER_LOGIN` ruft `GR:EnableModules()` das `OnEnable` jedes Moduls in Registrierungsreihenfolge auf, jeweils in `pcall`. Module sprechen über einen internen Nachrichtenbus miteinander (`Core/Events.lua`: `GR:RegisterMessage`, `GR:SendMessage`, `GR:BindMessage(mod, …)`, damit `OnDisable` aufräumen kann), z. B. `PRIVACY_CHANGED`, `SHARE_POS_CHANGED`, `GUILD_UPDATE`.

**Netzwerk** (`Core/Comm.lua` + `Core/Queue.lua`): Addon-Nachrichten laufen über den Gildenkanal. Der Wire-Prefix bleibt aus Kompatibilitätsgründen **`GildenRadar`** (`GR.PREFIX`). Ausgehende Nachrichten gehen in eine Prioritäts-Queue (`kill > ctrl > data > pos`, mit Obergrenzen pro Priorität), die alle 0,5 s gedrosselt geleert wird. Empfangsseitig gibt es ein Rate-Limit, Fragmentierung (max. 250 Bytes) und `Comm:Allowed(category)`: Privacy-Schalter blockieren Kategorien beim Senden und entfernen sie aus der Queue.

**Wanted** (Kernlogik, siehe Kopfkommentar `Core/WantedLogic.lua`):
- Jeder Eintrag hat einen Zähler pro Opfer (`origin`) plus einen eingefrorenen `legacy`-Wert aus 0.6.x. Level = `legacy + Σ origin.n`.
- Beim Mergen gilt `max(n)` pro Opfer. Live-Meldungen, Relays und Syncs sind dadurch idempotent.
- Die Regeln sind fest (`WantedLogic.GetFixedConfig()`), keine Benutzereinstellungen. Gespeicherte `autoWanted`-Werte werden ignoriert.
- Das Wire-Format v2 steht im Kopf von `Core/Protocol.lua` (`WK`, `SR`, `WSH`, `WS`, `WSE`).
- Den Killer bestimmt `Modules/Death.lua` über den Death Recap, weil CLEU auf Forever gesperrt ist. Fehlt ein Beleg, heißt das Ergebnis „unbekannt“, statt zu raten.

**SavedVariables** (`AngryMurlocsDB`): Defaults und Migrationen stehen in `AngryMurlocs.lua` (`SCHEMA = 2`). Gildendaten liegen in Scopes pro Gilde (`U.GuildScopeKey()`, `U.GetScopeDB()`). Wanted- und Berufe-Daten dürfen nicht zwischen Gilden durchsickern; `Tests/PrivacyScope_test.lua` prüft das.

**Lokalisierung:** `Localization/enUS.lua` definiert `AngryMurlocsLocale`. `deDE.lua` überschreibt Schlüssel nur bei `GetLocale() == "deDE"`. Zugriff erfolgt über `U.L("KEY")`. Neue Schlüssel immer in beiden Dateien anlegen.

## Repository & Veröffentlichung

- **origin** ist das private GitLab der Gilde. Dort wird gearbeitet: Branches, Merge Requests, Pipeline. Für MRs und Pipelines `glab` nutzen, nicht `gh`. Die GitLab-Adresse gehört in keine Datei im Repo, denn das Repo ist öffentlich gespiegelt.
- **GitHub** (öffentlich, nur lesen): https://github.com/AngryMurlocs/wow-angry-murlocs-addon. GitLab spiegelt per Push-Mirror nur geschützte Branches (`main`) und Tags dorthin. So ist der Code öffentlich, ohne dass jemand Zugriff auf das GitLab braucht. Auf GitHub wird nie direkt gearbeitet.
- **CurseForge** (öffentliche Addon-Seite): https://www.curseforge.com/wow/addons/angry-murlocs. CurseForge beobachtet das GitHub-Repo und baut **nur bei einem neuen Tag** ein Paket (BigWigs-Packager, `.pkgmeta`, Changelog aus `CHANGELOG.md`). Ein Push auf `main` ohne Tag veröffentlicht nichts.
- **Ein neuer Tag ist eine Veröffentlichung für alle Spieler.** Ein Tag wird nie ohne ausdrückliches Go des Users gesetzt, nie verschoben und nie gelöscht.

## Git-Workflow (gilt für jeden Agent: Claude, Cursor, …)

Mehrere Leute arbeiten parallel am Projekt. Der Agent erledigt Git selbst und entscheidet selbst über Branch-Namen und Zuschnitt der MRs. Ein Go vom User braucht es genau an zwei Stellen: **bevor etwas auf `main` landet** und **bevor ein Tag gesetzt wird**.

1. **Start:** `git fetch origin`, `git switch main`, `git pull --ff-only`. Dann einen Branch anlegen (`feature/…`, `fix/…`, `docs/…`, `release/X.Y.Z`). Nie direkt auf `main` committen.
2. **Commits:** möglichst viele kleine Commits, **auf Englisch**, im Format `type(scope): description` (scope optional). Erlaubte Typen: `feat`, `fix`, `change`, `remove`, `docs`, `chore`, `ci`, `test`, `refactor`, `release`. Ein Vertragsbruch (siehe Versionierung) wird mit `!` markiert, z. B. `feat(wanted)!: …`.
3. **Changelog:** Jede Änderung, die Spieler bemerken, bekommt eine Zeile unter `## Unreleased` ganz oben in `CHANGELOG.md` (anlegen, falls nicht vorhanden). Regeln dafür:
   - **Englisch**, kurz, aus Sicht der Spieler, ohne Fachbegriffe. Keine Dateinamen, Funktionen, Events, Opcodes, „sync protocol“, „SavedVariables“ o. Ä.
   - Nur das Nötigste: Mehrere Commits ergeben oft eine einzige Zeile.
   - Gut: `- Death toast no longer guesses the killer when it is unclear`. Schlecht: `- Death.lua: prefer lethal Recap hits over CLEU fallback`.
   - Doku, CI, Tests und reine Umbauten bekommen keine Zeile.
4. **Prüfen:** `luajit Tests/run_all.lua` muss grün sein.
5. **MR nach `main`:** Vorher `git fetch origin` und `git merge origin/main` (bei Änderungen erneut testen). Danach `git push -u origin HEAD` und `glab mr create --target-branch main --title "<type>: <English title>" --fill --remove-source-branch --yes`. Die Pipeline prüft Tests und Titelformat und muss grün werden.
6. **Go 1, Merge:** Jeder MR ist ein **Sammel-MR**: Der Branch nimmt so lange weitere Commits auf, bis der User mergen will. Das dem User immer ausdrücklich sagen. Dann zeigen, **welche Commits mitgehen** (`git log --oneline origin/main..HEAD`) und **welche Changelog-Zeilen neu sind**, und **fragen, ob er noch weitere Änderungen oder Wünsche für diesen MR hat**. Hat er welche, kommen sie als weitere Commits in denselben MR, danach folgt eine neue Vorschau. Erst nach seinem ausdrücklichen Ja zum Merge mergen: `glab mr merge --yes`, **ohne Squash**, damit jeder Commit erhalten bleibt. Danach `git switch main`, `git pull --ff-only` und den lokalen Branch mit `git branch -d` löschen.
7. **Wenn etwas fehlschlägt:** nicht mergen und nicht taggen. Die Arbeit bleibt auf dem Branch. Dem User verständlich erklären, was fehlt.

Ohne Tag ist `main` unveröffentlicht. Doku-, CI- oder Test-Änderungen gehen deshalb ganz normal (mit Go) nach `main`, ohne Version.

## Versionierung

Details: `docs/versioning.md`. Die Version wird nach der Gesamtheit aller Änderungen seit dem letzten Tag bestimmt, nicht pro Commit:

| Stufe | Wann | Beispiel |
|-------|------|----------|
| **patch** `X.Y.(Z+1)` | Bugfix, kleine Änderung, kleines Feature, Anpassung eines bestehenden Features | 0.11.0 → 0.11.1 |
| **minor** `X.(Y+1).0` | ganz großes neues Feature | 0.11.3 → 0.12.0 |
| **major** `(X+1).0.0` | großer Kompatibilitätsbruch, z. B. ältere Addon-Versionen in der Gilde können nicht mehr mit der neuen Daten austauschen, oder gespeicherte Daten gehen verloren bzw. werden inkompatibel | 0.12.0 → 1.0.0 |

`## Interface:` in der TOC ist die Client-Version, nicht die Addon-Version.

## Release (neue Version für CurseForge)

Der Agent entscheidet, wann eine Version sinnvoll ist, und schlägt sie dem User vor. Bei einem kleinen Fix darf das Release im selben MR wie der Fix passieren; der MR heißt dann `release: X.Y.Z`.

1. Auf einem Branch (z. B. `release/X.Y.Z`, ab aktuellem `main`) die Stufe nach der Tabelle oben bestimmen. Grundlage sind `## Unreleased` und `git log --oneline <letzter Tag>..origin/main`. Den letzten Tag liefert `git describe --tags --abbrev=0 origin/main`.
2. In `CHANGELOG.md` `## Unreleased` in `## X.Y.Z` umbenennen. Die Version in allen vier Stellen setzen: `## Version:` in `AngryMurlocs.toc`, `GR.VERSION` in `AngryMurlocs.lua`, `**Version:**` in `README.md` und den Changelog-Abschnitt.
3. `luajit Tests/run_all.lua` und `luajit Tests/Version_test.lua release` müssen grün sein. Dann committen (`release: X.Y.Z`), pushen und den MR `release: X.Y.Z` erstellen. Die Pipeline prüft zusätzlich, ob der Titel zur Version passt und ob der Tag noch frei ist.
4. **Go 2, Vorschau:** Dem User zeigen:
   - alle Commits seit dem letzten Tag, die mitgehen
   - den neuen Changelog-Abschnitt, genau so, wie er veröffentlicht wird
   - die neue Versionsnummer und die gewählte Stufe mit kurzer Begründung

   Auch hier sagen, dass es ein Sammel-MR ist, und fragen, ob noch weitere Änderungen mit in dieses Release sollen. Erst nach seinem ausdrücklichen Ja weitermachen.
5. Den MR mergen (ohne Squash, siehe Schritt 6 oben), dann `git switch main` und `git pull --ff-only`.
6. Annotierten Tag setzen. Die Tag-Message ist der neue Changelog-Abschnitt. Getaggt wird der Merge des Release-MR. Hat in der Zwischenzeit jemand anderes gemergt, ist `HEAD` nicht mehr dieser Merge. Dann die SHA des Release-Merges statt `HEAD` nehmen:
   ```sh
   V=X.Y.Z
   luajit Tests/Version_test.lua release
   { echo "AngryMurlocs $V"; echo; awk -v v="## $V" '$0==v{f=1;next} /^## /{f=0} f' CHANGELOG.md | sed '/^$/d'; } > /tmp/tagmsg.txt
   git tag -a "v$V" -F /tmp/tagmsg.txt HEAD
   git push origin "v$V"
   ```
   Unter Windows in der Git Bash ausführen, die mit Git für Windows installiert wird.
7. Dem User mitteilen: Der Tag ist gesetzt, der Mirror bringt ihn zu GitHub und CurseForge baut daraus das Paket. Das dauert ein paar Minuten.

`DEV.md` ist eine allgemeine deutschsprachige Referenz zur WoW-Addon-Entwicklung (TOC, Events, Secure Templates/Combat Lockdown, Unterschiede zwischen den Clients). Sie ist nicht projektspezifisch.
