# Mitarbeiten an AngryMurlocs

Diese Anleitung ist für alle, die am Addon mitarbeiten, egal ob mit Cursor, Claude Code oder ohne KI. Die verbindlichen Regeln für KI-Agents stehen in [AGENTS.md](AGENTS.md). Cursor und Claude Code lesen diese Datei automatisch.

## Wo was liegt

| Ort | Wofür |
|-----|-------|
| Privates GitLab der Gilde (`origin`) | Hier wird gearbeitet: Branches, Merge Requests, Pipeline |
| [GitHub](https://github.com/AngryMurlocs/wow-angry-murlocs-addon) | Öffentliche Kopie, nur lesen. GitLab spiegelt `main` und alle Tags automatisch dorthin. |
| [CurseForge](https://www.curseforge.com/wow/addons/angry-murlocs) | Öffentliche Addon-Seite. Baut aus jedem **neuen Tag** auf GitHub automatisch ein Paket für die Spieler. |

Wichtig:
- **Nur ein neuer Tag veröffentlicht etwas.** Commits und Merges auf `main` landen zwar auch auf GitHub, aber CurseForge baut erst bei einem Tag ein neues Paket.
- **`CHANGELOG.md` ist öffentlich.** Spieler lesen ihn auf CurseForge.

## Einmalige Einrichtung

1. **Git** mit eigenem Namen und eigener E-Mail:
   ```sh
   git config --global user.name "Dein Name"
   git config --global user.email "du@example.com"
   ```
2. **glab** (GitLab-CLI), damit der Agent Merge Requests anlegen und mergen kann. Installation: macOS `brew install glab`, Windows `winget install GLab.GLab`. Danach `glab auth login` ausführen, „GitLab Self-hosted“ wählen und die Adresse des Gilden-GitLab eintragen.
3. **LuaJIT** für die Tests: macOS `brew install luajit`, Windows z. B. `scoop install luajit`. Lua 5.1 geht auch. Die Pipeline führt die Tests bei jedem MR ohnehin aus.
4. **Alte lokale Cursor-Regeln löschen:** Wer noch eigene Release-Skills oder -Rules unter `.cursor/` hat (z. B. `angrymurlocs-release`, `release-tag-format`), löscht sie bitte. Sie beschreiben den alten Ablauf und widersprechen `AGENTS.md`.

## Ablauf in Kurzform

1. **Branch** von aktuellem `main` aus: `feature/…`, `fix/…`, `docs/…`. Nie direkt auf `main` arbeiten.
2. **Viele kleine Commits auf Englisch**, z. B. `fix(death): keep killer unknown without proof`.
   Typen: `feat`, `fix`, `change`, `remove`, `docs`, `chore`, `ci`, `test`, `refactor`, `release`.
3. **Changelog:** Was Spieler merken, kommt als kurze Zeile unter `## Unreleased` ganz oben in `CHANGELOG.md`.
4. **Merge Request nach `main`.** Die Pipeline führt die Tests aus und prüft den Titel.
5. **Go 1:** Jeder MR ist ein Sammel-MR. Bevor etwas auf `main` landet, zeigt der Agent die Commits, die mitgehen, und die neuen Changelog-Zeilen. Er fragt außerdem, ob du noch weitere Änderungen oder Wünsche hast, die mit hinein sollen. Gemergt wird erst nach deinem Ja, **ohne Squash**.
6. **Release** (neue Version), sobald es sich lohnt, siehe unten.

## WoW Forever

Das Addon läuft auf **WoW Forever**. Das ist technisch der Retail-Client, viele alte Classic-Funktionen gibt es dort nicht. Deshalb prüft `Tests/ForeverApi_test.lua` bei jedem Testlauf und in jeder Pipeline, ob alle genutzten WoW-Funktionen, Ereignisse, Frame-Vorlagen und Enum-Werte in Forever existieren. Grundlage ist eine Kopie der [Forever-Daten von Ketho](https://github.com/Ketho/BlizzardInterfaceResources/tree/forever) in `Tests/forever_api/`.

- **Test rot:** Die Funktion gibt es in Forever nicht, also eine Forever-Variante nutzen. Bewusste, abgesicherte Ausnahmen stehen mit Begründung in `Tests/forever_api/allowed_missing.txt`.
- **Pipeline-Job `test:forever-api-latest` gelb:** Blizzard hat etwas geändert. Die Kopie mit `luajit Tests/forever_api/update.lua` in einem eigenen MR aktualisieren.
- Details für Agents: [AGENTS.md](AGENTS.md), Abschnitt „WoW Forever: Kompatibilität“.

## Changelog schreiben

Der Changelog ist für Spieler, nicht für Entwickler:

- Englisch, kurz, verständlich, ohne Fachbegriffe, keine Dateinamen und keine Code-Begriffe
- Nur das Nötigste: Fünf Commits können eine einzige Zeile sein.
- Doku, Tests, CI und interne Umbauten kommen nicht hinein.

| Gut | Schlecht |
|-----|----------|
| `- Map pins no longer overlap when players stand together` | `- MapPins: cluster overlapping pins via grid bucket` |
| `- Death toast no longer guesses the killer when it is unclear` | `- Death.lua: prefer lethal Recap hits over CLEU fallback` |

## Versionen

| Stufe | Wann |
|-------|------|
| **patch** (0.11.0 → 0.11.1) | Bugfix, kleine Änderung, kleines Feature, Anpassung an etwas Bestehendem |
| **minor** (0.11.1 → 0.12.0) | ganz großes neues Feature |
| **major** (0.12.0 → 1.0.0) | großer Kompatibilitätsbruch, z. B. alte Addon-Versionen können nicht mehr mit der neuen Daten austauschen |

Die Versionsnummer steht an vier Stellen und muss überall gleich sein: in `AngryMurlocs.toc`, in `AngryMurlocs.lua` (`GR.VERSION`), in `README.md` und im obersten Abschnitt von `CHANGELOG.md`. `Tests/Version_test.lua` prüft das. Mehr dazu in [docs/versioning.md](docs/versioning.md).

## Release

1. Der Agent schlägt eine Version vor und erstellt einen MR `release: X.Y.Z`. Darin wird `## Unreleased` zu `## X.Y.Z`, und die Versionsnummer ist überall gesetzt.
2. **Go 2:** Er zeigt dir alle Commits seit der letzten Version, den neuen Changelog-Abschnitt und die neue Versionsnummer. Er fragt, ob noch etwas mit in das Release soll.
3. Nach deinem Ja merged er und setzt den Tag `vX.Y.Z`. Die Tag-Message ist der neue Changelog-Abschnitt.
4. GitLab spiegelt den Tag zu GitHub, CurseForge baut das Paket, und nach ein paar Minuten ist die Version auf der Addon-Seite.

Ein Tag wird nie verschoben oder gelöscht. Ist etwas schiefgegangen, kommt einfach die nächste Patch-Version.

## Einstellungen im GitLab-Projekt (einmalig, Maintainer)

- **Settings → Repository → Protected branches:** `main` geschützt. Merge erlaubt für Developer und Maintainer, Push für niemanden.
- **Settings → Repository → Protected tags:** `v*` geschützt. Anlegen erlaubt für alle, die releasen dürfen.
- **Settings → Merge requests:** „Squash commits when merging“ auf **Do not allow**. Merge-Methode bleibt „Merge commit“.
- **Settings → Repository → Mirroring repositories:** Push-Mirror zu GitHub mit „Mirror only protected branches“. Tags werden mitgespiegelt.
