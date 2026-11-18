# Discord-Anleitung – Quellen

| Feld | Wert |
| --- | --- |
| Datum | 2026-11-18 |
| Quelle | AngryMurlocs Arbeitsbaum `feature/options-activity-log` |
| Basis | origin/main 0.11.20 (`5547e81`) + Unreleased ActivityLog |
| Status | Entwicklungsstand – nicht veröffentlicht |
| Codebeleg | `Core/ActivityLog.lua`, `Core/Util.lua` (`U.Status`), `Modules/Options.lua` (Log), `Modules/ProfRecipes.lua` / `ProfRecipePanel.lua` (Routing), `Core/Diag.lua` |
| Tests | `luajit Tests/run_all.lua` (nach Umsetzung) |
| Client | Forever Ingame **ungeprüft** (siehe `Tests/CLIENT_CHECKLIST.md` Abschnitt Options → Log) |
| Offene Punkte | Ingame-Abnahme Status/Debug, sticky scroll, Diag-Flag über `/reload` |
