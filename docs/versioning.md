# AngryMurlocs — Versionierung

Projektkonvention für SemVer in der **0.x**-Phase und für Release-Analyse.
Operativer Tag/Push-Flow: Skill `angrymurlocs-release`, Rule `release-tag-format`.

Grundlagen: [SemVer 2.0.0](https://semver.org/spec/v2.0.0.html),
[Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).

## Addon-Version vs Interface

| Feld | Bedeutung |
|------|-----------|
| `AngryMurlocs.toc` → `## Version:` | **Addon-Version** `X.Y.Z` |
| `AngryMurlocs.lua` → `GR.VERSION` | Laufzeit-Anzeige derselben Addon-Version |
| `README.md` → `**Version:**` | Doku derselben Addon-Version |
| `CHANGELOG.md` → top `## X.Y.Z` | Changelog-Abschnitt für Release/Tag |
| Git-Tag `vX.Y.Z` | Annotated Release-Marker (CF triggert auf Tag-Push) |
| `## Interface:` in `.toc` | **Client-Interface** (z. B. Forever `16001`) — **keine** Addon-Versionsnummer |

Ein Git-Tag allein beweist keine CurseForge-Veröffentlichung; CF folgt dem Tag-Push über den Packager.

## Öffentlicher Vertrag

Zum öffentlichen Vertrag zählen (Änderungen hier können patch/minor/breaking auslösen):

- Slash-Befehle und dokumentierte Bedienung (README)
- Privacy-Schalter und was geteilt / nicht geteilt wird
- Wanted-Zählregeln, Sync-Verhalten, Death-/Recap-Attribution
- Comm-/Protocol-Wire (Opcodes, Schema)
- SavedVariables-Schema und zugesagte Migrationen
- Sichtbare UI-/Minimap-/Settings-Bedienung, soweit dokumentiert oder spielerrelevant

Zählen **nicht** automatisch als Vertragsbruch:

- Reine Modul-Dateisplits / interne Enable-Hygiene
- Docs-/Test-only ohne Verhaltensänderung
- `.cursor` / Tools / interne Skill-Dateien

## Zwei Klassifizierungen

### A — Inhaltstyp

`fix` | `feat` | `perf` | `refactor` | `docs` | `test` | `build` | `ci` | `chore` | `style`

Zusatzflags (unabhängig): `security`, `deprecation`, `breaking`.

Commit-Form: `type(scope): Beschreibung`. Vertragsbruch: `type(scope)!: …` und/oder `BREAKING CHANGE:` im Body.

### B — Release-Auswirkung

`none` | `patch` | `minor` | `major`

- `none`: kein Versionsbump (reine Docs/Tests/interne Wartung ohne Publish-Effekt)
- Pro Release die **höchste** erforderliche Stufe **einmal** anwenden (nicht pro Commit)
- Zahlen sind nicht auf 9 begrenzt (`0.9.0` → `0.10.0` ist gültig)

## 0.x-Projektregel (verbindliche Konvention)

SemVer behandelt 0.y.z als Anfangsentwicklung ohne stabile öffentliche API. Für AngryMurlocs gilt:

| Fall | Angewendeter Zahlen-Bump | Technische Auswirkung |
|------|--------------------------|------------------------|
| Kompatible Fehlerkorrektur | `0.y.(z+1)` → **patch** | patch |
| Neue sichtbare Funktion / kompatible Erweiterung | `0.(y+1).0` → **minor** | minor |
| Vertragsbruch | `0.(y+1).0` → **minor** | **major** notieren + Flag `breaking` + Migration erläutern |
| Erste stabile Freigabe | bewusst **`1.0.0`** | eigener Auftrag, keine Auto-Erhöhung wegen Breaking |

Damit bleibt in 0.x die technische Stufe `major` vom angewendeten Bump `minor` getrennt. Tools, die Breaking in 0.x automatisch auf `1.0.0` setzen, weichen von dieser Projektregel ab.

Ab **1.0.0** (wenn bewusst eingeführt): klassisches SemVer — patch / minor / major wie Spec.

## Vorabversionen

Nur bei Bedarf / bestehender Praxis: `X.Y.Z-alpha.N`, `-beta.N`, `-rc.N` (SemVer-Pre-Release).
Abschluss der Vorabphase: dieselbe Zielnummer ohne Pre-Release freigeben — **nicht** nochmals erhöhen.

## Versionsquellen und Konsistenz

Vor einem Release müssen übereinstimmen:

1. `## Version:` in `AngryMurlocs.toc`
2. `GR.VERSION` in `AngryMurlocs.lua`
3. `**Version:**` in `README.md`
4. Top-`## X.Y.Z` in `CHANGELOG.md`
5. Annotated Tag `vX.Y.Z` (nach Tag-Schritt)

Hilfsskript (reine Mechanik, keine Diff-Klassifikation):

```powershell
powershell -NoProfile -File tools/next-version.ps1 -Bump patch
powershell -NoProfile -File tools/next-version.ps1 -Bump minor
```

## Betriebsarten (Skill)

1. **Analyse** (Default): nur lesen; Änderungstabelle; empfohlene nächste Version; kein Bump.
2. **Vorbereitung**: bei explizitem Auftrag TOC/Lua/README/CHANGELOG anpassen und prüfen.
3. **Veröffentlichen**: annotated Tag + SSH-Push — eigener Auftrag (siehe `angrymurlocs-release`).

Vergleichsbasis für Analyse auf `main`: letzter Release-Commit `Release AngryMurlocs X.Y.Z.` und/oder annotated Tag `vX.Y.Z` dieses Addons. Numerisch höchster Tag eines anderen Kontexts ist irrelevant (Einzelpaket). Bei widersprüchlichen Quellen: Unsicherheit ausweisen, keine Historie erfinden.
