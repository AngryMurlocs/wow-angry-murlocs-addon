# Discord-Anleitung – Quellen

| Feld | Wert |
| --- | --- |
| Datum | 2026-11-19 |
| Quelle | AngryMurlocs Release 0.11.23 |
| Basis | `v0.11.23` / main nach release: 0.11.23 |
| Status | Tag `v0.11.23` gesetzt; Mirror → GitHub → CurseForge-Build |
| Codebeleg | Nerglish entfernt: `Modules/Death.lua` / `LevelUp.lua` / `Wanted.lua` / `Options.lua`; BG/Arena-Tod: `Modules/Death.lua` `BroadcastLocalDeath`; Wanted: `Core/WantedLogic.lua` `EvaluateDeath`; Protokoll: `Core/ActivityLog.lua`, Options Log |
| Tests | `luajit Tests/run_all.lua` (inkl. `DeathRegression_test`) |
| Client | Forever Ingame für BG-Tod offen |
| Offene Punkte | CLIENT_CHECKLIST: BG-Tod stumm |
