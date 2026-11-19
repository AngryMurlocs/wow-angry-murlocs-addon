-- Nerglish-Reaktionspools (kreative Lautmalerei; keine kanonischen Übersetzungen).
if GetLocale and GetLocale() ~= "deDE" then return end
local L = AngryMurlocsLocale
if type(L) ~= "table" then return end

local function Set(key, value)
  L[key] = value
end

-- ===== Levelaufstieg =====
Set("NERGLISH_LVL_SUBTLE_1", "Mrrgl! {player} hat Stufe {level} erreicht.")
Set("NERGLISH_LVL_SUBTLE_2", "Grgl! Noch ein Level für {player} ({level}).")
Set("NERGLISH_LVL_SUBTLE_3", "Blub! {player} wird stärker — Stufe {level}.")
Set("NERGLISH_LVL_PLAYFUL_1", "MRRRGL! BLUBBLUB! {player} knackt Stufe {level}!")
Set("NERGLISH_LVL_PLAYFUL_2", "GLRGLRGL! Unser Freund {player} ist jetzt Stufe {level}!")
Set("NERGLISH_LVL_PLAYFUL_3", "Mrrrgl-glub! {player} auf Stufe {level} — der Murloc jubelt!")

Set("NERGLISH_LVL_RARE_01", "Mrrgl! {player} erreicht Stufe {level}! Ein Fisch zur Belohnung!")
Set("NERGLISH_LVL_RARE_02", "Blrglblub! {player} ist Stufe {level}! Purzelbaum-Zeit!")
Set("NERGLISH_LVL_RARE_03", "GLRGL! Noch ein Level für {player}! Der Teich wächst mit seinen Helden!")
Set("NERGLISH_LVL_RARE_04", "Mrrglgrgl! Stufe {level}! {player} ist heute der größte Fisch!")
Set("NERGLISH_LVL_RARE_05", "Blub! {player} wird stärker. Der Murloc wird langsam neidisch!")
Set("NERGLISH_LVL_RARE_06", "MRRGL! Stufe {level}! {player} bekommt einen imaginären Fischorden!")
Set("NERGLISH_LVL_RARE_07", "Glubglub! {player} ist auf Stufe {level}! Der Murloc versucht mitzuzählen!")
Set("NERGLISH_LVL_RARE_08", "Brrgl! Ein Level mehr! {player} macht den Murloc stolz!")
Set("NERGLISH_LVL_RARE_09", "Mrrrgl! {player} erreicht Stufe {level}! Das riecht nach einem Festmahl!")
Set("NERGLISH_LVL_RARE_10", "Blrgl! {player} steigt auf! Siegestanz-Übung beginnt!")

Set("NERGLISH_LVL_LEGEND_11", "MRRRAAAGL! {player} ist Stufe {level} — der Murloc kann nicht stillstehen!")
Set("NERGLISH_LVL_LEGEND_12", "GLRGLGRGL! {player} ist stärker geworden. Der Fisch des Schicksals wusste es!")
Set("NERGLISH_LVL_LEGEND_13", "BLRGLBLUB! Stufe {level}! Der Murloc verleiht {player} den goldenen Blubberorden!")
Set("NERGLISH_LVL_LEGEND_14", "MRRRGL! {player} steigt auf — zehn von zehn Fischen empfehlen diesen Helden!")
Set("NERGLISH_LVL_LEGEND_15", "GRGLGRGL! Der Murloc hat vor Freude einen Stein umarmt. {player} ist Stufe {level}!")
Set("NERGLISH_LVL_LEGEND_16", "MRRRRGL! {player} ist Stufe {level}! Der Murloc wollte jubeln — Fisch im Mund!")

-- ===== Level-Meilenstein =====
Set("NERGLISH_LVL_M_SUBTLE_1", "Mrrgl! Meilenstein: {player} erreicht Stufe {level}.")
Set("NERGLISH_LVL_M_SUBTLE_2", "Grgl! Runde Zahl — {player} steht bei {level}.")
Set("NERGLISH_LVL_M_SUBTLE_3", "Blub! Stolz auf {player}: Stufe {level}.")
Set("NERGLISH_LVL_M_PLAYFUL_1", "MRRRRGL! {player} knallt Stufe {level} rein!")
Set("NERGLISH_LVL_M_PLAYFUL_2", "BLUBBLUB! Meilenstein für {player} — Stufe {level}!")
Set("NERGLISH_LVL_M_PLAYFUL_3", "Grglgrglgr! {player} bei {level} — Fest im Teich!")

Set("NERGLISH_LVL_M_RARE_01", "MRRRGL! {player} hat Stufe {level} erreicht! Der ganze Teich jubelt!")
Set("NERGLISH_LVL_M_RARE_02", "Blrglblub! Stufe {level}! Fisch fliegt vor Freude!")
Set("NERGLISH_LVL_M_RARE_03", "GLRGLGL! {player} wird immer mächtiger. Selbst die Krebse applaudieren!")
Set("NERGLISH_LVL_M_RARE_04", "Mrrrgl! Stufe {level}! Heute ist Fischfeiertag!")
Set("NERGLISH_LVL_M_RARE_05", "BRRGL! {player} erreicht Stufe {level}! Drei Blubberblasen für unseren Helden!")
Set("NERGLISH_LVL_M_RARE_06", "Mrrglgrgl! {player} hat Stufe {level} geknackt. Die Fische sind beeindruckt!")
Set("NERGLISH_LVL_M_RARE_07", "BLRGL! Der Murloc zählt nach … ja! {player} ist wirklich Stufe {level}!")
Set("NERGLISH_LVL_M_RARE_08", "Glubglub! {player} erreicht Stufe {level}. Großer Freudentanz!")
Set("NERGLISH_LVL_M_RARE_09", "Rwlglgl! Stufe {level}! Schönster Fisch aufgehoben!")
Set("NERGLISH_LVL_M_RARE_10", "MRRGL! {player} erklimmt Stufe {level}. Neuer Teich-Champion!")

Set("NERGLISH_LVL_M_LEGEND_11", "MRRRRGLGRGLGR! Stufe {level}! Weckt den Obermurloc — {player} hat es geschafft!")
Set("NERGLISH_LVL_M_LEGEND_12", "BLRGLGRGL! Der auserwählte Fisch erwacht — {player} erreicht Stufe {level}!")
Set("NERGLISH_LVL_M_LEGEND_13", "MRRRAAAGL! {player} ist Stufe {level}! Ein Fisch, zwei Fische, ein Festmahl!")
Set("NERGLISH_LVL_M_LEGEND_14", "GLRGLGLGL! {player} auf Stufe {level} — der Murloc schwimmt rückwärts vor Freude!")
Set("NERGLISH_LVL_M_LEGEND_15", "MRRRGL! Achtung Azeroth — {player} ist Stufe {level}! Der Teich ist nicht mehr sicher!")
Set("NERGLISH_LVL_M_LEGEND_16", "BRRRAAAGL! Der Rat der sieben Fische entscheidet: {player} ist Stufe {level} und verdient ein Festmahl!")

-- ===== Tod =====
Set("NERGLISH_DEATH_SUBTLE_1", "Mrrgl… {player} ist gefallen ({zone}).")
Set("NERGLISH_DEATH_SUBTLE_2", "Blub… Traurig: {player} in {zone}.")
Set("NERGLISH_DEATH_SUBTLE_3", "Grgl… {player} braucht Hilfe in {zone}.")
Set("NERGLISH_DEATH_PLAYFUL_1", "Mrrglgl… Oh nein, {player} in {zone}!")
Set("NERGLISH_DEATH_PLAYFUL_2", "Rwl… {player} machte Plitsch in {zone}.")
Set("NERGLISH_DEATH_PLAYFUL_3", "Blrgl… Der Teich trauert um {player} ({zone}).")

Set("NERGLISH_DEATH_RARE_01", "Blrrgl?! {player} ist gestorben! Fisch fällt vor Schreck!")
Set("NERGLISH_DEATH_RARE_02", "Mrrgl … {player} ist gefallen. Der Teich schweigt.")
Set("NERGLISH_DEATH_RARE_03", "BLRGL?! Wer hat {player} umgehauen? Der Murloc verlangt Antworten!")
Set("NERGLISH_DEATH_RARE_04", "Glub … glub … {player} ist tot. Nicht einmal der Fisch hat damit gerechnet.")
Set("NERGLISH_DEATH_RARE_05", "Mrrrgl?! {player}, aufstehen! Noch Fisch für dich!")
Set("NERGLISH_DEATH_RARE_06", "Blrgl … {player} ist gefallen. Imaginäre Kerze angezündet.")
Set("NERGLISH_DEATH_RARE_07", "GRGL?! {player} ist gestorben! Der Murloc versteckt sich.")
Set("NERGLISH_DEATH_RARE_08", "Mrrglblub … {player} liegt am Boden. Trostfisch bereit.")
Set("NERGLISH_DEATH_RARE_09", "Blrrgl! {player} ist gefallen. Das war definitiv nicht der Plan!")
Set("NERGLISH_DEATH_RARE_10", "Glrgl? {player} ist gestorben? Gerade wollte der Murloc gratulieren!")

Set("NERGLISH_DEATH_LEGEND_11", "MRRRRGL?! {player} ist tot?! Wer hat meinen Lieblingshelden kaputt gemacht?!")
Set("NERGLISH_DEATH_LEGEND_12", "BLRGL! Notfall! {player} ist gefallen — holt den Heilfisch!")
Set("NERGLISH_DEATH_LEGEND_13", "MRRGL?! {player} ist gestorben! Der Murloc fordert sofortige Wiederauferstehung!")
Set("NERGLISH_DEATH_LEGEND_14", "GLRGLGL?! {player} ist tot! Letzter Fisch vor Schreck verschluckt!")
Set("NERGLISH_DEATH_LEGEND_15", "BLRGLBLUB! {player} liegt am Boden! Heiler … und einen Koch!")
Set("NERGLISH_DEATH_LEGEND_16", "MRRRGLGRGL! {player} ist gefallen! Drei Tage Trauer — oder bis zur Wiederbelebung!")

-- ===== Wanted-Sichtung (nur Präfixe) =====
Set("NERGLISH_SIGHT_SUBTLE_1", "Mrrgl!")
Set("NERGLISH_SIGHT_SUBTLE_2", "Grgl!")
Set("NERGLISH_SIGHT_SUBTLE_3", "Rwl!")
Set("NERGLISH_SIGHT_PLAYFUL_1", "MRRRRGL!")
Set("NERGLISH_SIGHT_PLAYFUL_2", "Rwlrlrlrl!")
Set("NERGLISH_SIGHT_PLAYFUL_3", "Grglgrglgr!")

Set("NERGLISH_SIGHT_RARE_01", "GRRRGL! Feind gesichtet!")
Set("NERGLISH_SIGHT_RARE_02", "MRRGL! Der Murloc wittert Ärger!")
Set("NERGLISH_SIGHT_RARE_03", "BLRGL! Falscher Teich, Fremder!")
Set("NERGLISH_SIGHT_RARE_04", "GRGLGRGL! Auf die Flossen, Krieger!")
Set("NERGLISH_SIGHT_RARE_05", "RWLGRGL! Der Murloc zeigt die Zähne!")
Set("NERGLISH_SIGHT_RARE_06", "MRRRAA! Ein Feind! Wo ist mein Speer?!")
Set("NERGLISH_SIGHT_RARE_07", "GLRGL! Der Teich ist in Alarmbereitschaft!")
Set("NERGLISH_SIGHT_RARE_08", "GRRRBLGL! Die Jagd kann beginnen!")
Set("NERGLISH_SIGHT_RARE_09", "MRRGL! Schlechter Fischverdacht!")
Set("NERGLISH_SIGHT_RARE_10", "RWRWRGL! Krieger, macht euch bereit!")

Set("NERGLISH_SIGHT_LEGEND_11", "MRRRRGL! Alarm im Teich — alle Murlocs an die Front!")
Set("NERGLISH_SIGHT_LEGEND_12", "GRRRGLGRGL! Der Kriegsrat der Fische fordert Rache!")
Set("NERGLISH_SIGHT_LEGEND_13", "MRRRAAAGL! Speere, Schilde — und den großen Fisch!")
Set("NERGLISH_SIGHT_LEGEND_14", "BLRGLGRGL! Kriegsbemalung aufgeleckt. Bereit.")
Set("NERGLISH_SIGHT_LEGEND_15", "GRRRRGL! Alle Flossen auf Angriff — niemand bedroht unseren Teich!")
Set("NERGLISH_SIGHT_LEGEND_16", "MRRRGLGRGL! Der Obermurloc hat gesprochen: zeigt ihnen die Zähne!")
