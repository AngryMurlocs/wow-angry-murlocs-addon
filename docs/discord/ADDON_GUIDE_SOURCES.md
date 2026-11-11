# Discord-Anleitung – Quellen

| Feld | Wert |
| --- | --- |
| Datum | 2026-11-11 |
| Quelle | AngryMurlocs Arbeitsbaum `feature/recipe-subcategories` |
| Basis | main / 0.11.6 |
| Status | Entwicklungsstand – nicht veröffentlicht |
| Codebeleg | `Core/RecipeCategories.lua`, `Modules/ProfRecipePanel.lua`, `Modules/UI.lua`, `Modules/ProfRecipes.lua` (`ResolveRecipeCategory`, `PROFRC`) |
| Tests | `luajit Tests/run_all.lua` grün |
| Client | Forever Ingame **ungeprüft** (siehe `Tests/CLIENT_CHECKLIST.md` Abschnitt Rezept-Unterkategorien) |
| Offene Punkte | Live-Beleg categoryID+Name für fremde Rezepte ohne Berufsfenster |
