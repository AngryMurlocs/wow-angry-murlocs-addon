# Discord-Anleitung – Quellen

| Feld | Wert |
| --- | --- |
| Datum | 2026-11-21 |
| Quelle | AngryMurlocs Release 0.11.26 |
| Basis | `v0.11.26` / main nach release: 0.11.26 |
| Status | Tag `v0.11.26` gesetzt; Mirror → GitHub → CurseForge-Build |
| Codebeleg | Leerer Realm → Scope: `Core/Util.lua` CleanRealm/RealmKey/GetScopeDB; Boot `AngryMurlocs.lua` ArmRealmWait; Murloc-Rufe HW-Yell `Core/Nerglish.lua`, Bindings; Wanted/Toast/Rezepte/Map Fixes aus 0.11.26-Changelog |
| Tests | `luajit Tests/run_all.lua` (inkl. `PrivacyScope_test` empty-norm/boot-empty) |
| Client | Forever: Login mit verzögertem Realm; Outdoor-Yell + Tastenbelegung |
| Offene Punkte | CLIENT_CHECKLIST: leerer Realm am Login; Yell-Drossel / Idle im Spiel |
