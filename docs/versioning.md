# AngryMurlocs: Versionierung

Diese Datei beschreibt die Regeln für Versionsnummern. Den Ablauf Schritt für Schritt beschreiben [AGENTS.md](../AGENTS.md) (für Agents) und [CONTRIBUTING.md](../CONTRIBUTING.md) (für Menschen).

Grundlagen: [SemVer 2.0.0](https://semver.org/spec/v2.0.0.html), [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).

## Addon-Version und Interface

| Feld | Bedeutung |
|------|-----------|
| `AngryMurlocs.toc` → `## Version:` | **Addon-Version** `X.Y.Z` |
| `AngryMurlocs.lua` → `GR.VERSION` | dieselbe Version zur Laufzeit (Anzeige, Versionshinweis an Gildenmitglieder) |
| `README.md` → `**Version:**` | dieselbe Version in der Doku |
| `CHANGELOG.md` → oberster `## X.Y.Z` | Changelog-Abschnitt des Release; darüber darf `## Unreleased` stehen |
| Git-Tag `vX.Y.Z` | annotierter Release-Marker; die Tag-Message ist der Changelog-Abschnitt |
| `## Interface:` in `.toc` | **Client-Interface** (Forever `16001`), keine Addon-Version |

`Tests/Version_test.lua` prüft, ob die vier Stellen übereinstimmen. Mit dem Argument `release` prüft es zusätzlich, dass kein `## Unreleased` mehr übrig ist.

Ein Tag ist eine Veröffentlichung: Der Push-Mirror bringt ihn zu GitHub, und CurseForge baut daraus ein Paket. Commits auf `main` ohne Tag veröffentlichen nichts.

## Welche Stufe?

Bewertet wird die Gesamtheit aller Änderungen seit dem letzten Tag. Pro Release wird die **höchste** nötige Stufe **einmal** angewendet.

| Stufe | Wann | Beispiele |
|-------|------|-----------|
| **patch** `X.Y.(Z+1)` | Bugfix, kleine Änderung, kleines neues Feature, Anpassung eines bestehenden Features | Toast-Text korrigiert, neue Sortierung in der Liste, Pin-Größe anpassbar |
| **minor** `X.(Y+1).0` | ganz großes neues Feature | neues Modul oder neues Fenster mit eigener Funktion, neues Gilden-Feature |
| **major** `(X+1).0.0` | großer Kompatibilitätsbruch | ältere Addon-Versionen in der Gilde können nicht mehr mit der neuen Daten austauschen (Protokoll), gespeicherte Daten werden inkompatibel oder gehen verloren, Slash-Befehle oder Privacy-Verhalten ändern sich grundlegend |

- Das gilt auch in der 0.x-Phase: Der nächste große Bruch macht aus `0.y.z` die Version `1.0.0`.
- Zahlen sind nicht auf 9 begrenzt (`0.9.0` → `0.10.0` ist gültig).
- Reine Doku-, Test-, CI- oder Umbau-Änderungen brauchen keine Version. Sie gehen ohne Tag auf `main` und reisen mit der nächsten Version mit.

## Was zum öffentlichen Vertrag gehört

Änderungen an diesen Punkten sind Kandidaten für **major**:

- Comm- und Protokoll-Format (Opcodes, Felder, Prefix `GildenRadar`), also der Datenaustausch mit älteren Versionen
- SavedVariables-Schema (`AngryMurlocsDB`) und zugesagte Migrationen
- Wanted-Zählregeln, Sync-Verhalten, Death-/Recap-Attribution
- Slash-Befehle und dokumentierte Bedienung
- Privacy-Schalter: was geteilt wird und was nicht

Kein Vertragsbruch sind reine Dateiaufteilungen, interne Umbauten und Änderungen nur an Doku oder Tests.

## Commits

Englisch, Form `type(scope): description`. Typen: `feat`, `fix`, `change`, `remove`, `docs`, `chore`, `ci`, `test`, `refactor`, `release`. Ein Vertragsbruch wird mit `!` markiert (`feat(sync)!: …`) und im Commit-Text kurz erklärt. Release-Commits heißen `release: X.Y.Z`.

Die Commit-Typen bestimmen die Version **nicht** automatisch. Die Stufe legt der Agent bzw. Mensch beim Release nach der Tabelle oben fest, und der User bestätigt sie vor dem Tag.
