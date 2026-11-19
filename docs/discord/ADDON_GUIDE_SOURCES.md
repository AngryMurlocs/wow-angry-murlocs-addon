# Discord-Anleitung – Quellen

| Feld | Wert |
| --- | --- |
| Datum | 2026-11-19 |
| Quelle | AngryMurlocs Release 0.11.22 |
| Basis | `v0.11.22` / main nach release: 0.11.22 |
| Status | Tag `v0.11.22` gesetzt; Mirror → GitHub → CurseForge-Build |
| Codebeleg | BG/Arena-Tod: `Modules/Death.lua` `BroadcastLocalDeath`; Wanted: `Core/WantedLogic.lua` `EvaluateDeath`; Protokoll: `Core/ActivityLog.lua`, Options Log |
| Tests | `luajit Tests/run_all.lua` (inkl. `DeathRegression_test`) |
| Client | Forever Ingame für BG-Tod offen |
| Offene Punkte | CLIENT_CHECKLIST: BG-Tod stumm |
