# Discord-Anleitung – Quellen

| Feld | Wert |
| --- | --- |
| Datum | 2026-11-23 |
| Quelle | AngryMurlocs Release 0.11.31 |
| Basis | `v0.11.31` / main nach release: 0.11.31 |
| Status | Tag `v0.11.31` gesetzt; Mirror → GitHub → CurseForge-Build |
| Codebeleg | Berufe-Owner-Fold: `U.CharIdentity`, `Professions:PruneCharacterDuplicates` / `ResolveCacheOwner`; Katalog `ProfRecipes` CacheOwnerKey / MaxCatalogFloor; Changelog `## 0.11.31` |
| Tests | `luajit Tests/run_all.lua` (inkl. `ProfOwnerFold_test`) |
| Client | Forever: Berufe-Tab nach Update — keine Doppelzeilen |
| Offene Punkte | CLIENT_CHECKLIST Berufe-Pagination; Ingame-Check Doppelnamen nach Reload |
