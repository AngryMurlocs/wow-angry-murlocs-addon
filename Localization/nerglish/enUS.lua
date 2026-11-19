-- Nerglish reaction pools (creative onomatopoeia; not canon translations).
-- Loaded after Localization/enUS.lua. Mirrors into AngryMurlocsLocaleEN.
local L = AngryMurlocsLocale
if type(L) ~= "table" then return end

local function Set(key, value)
  L[key] = value
  if type(AngryMurlocsLocaleEN) == "table" then
    AngryMurlocsLocaleEN[key] = value
  end
end

-- ===== Level-up =====
Set("NERGLISH_LVL_SUBTLE_1", "Mrrgl! {player} reached level {level}.")
Set("NERGLISH_LVL_SUBTLE_2", "Grgl! Another level for {player} ({level}).")
Set("NERGLISH_LVL_SUBTLE_3", "Blub! {player} grows stronger — level {level}.")
Set("NERGLISH_LVL_PLAYFUL_1", "MRRRGL! BLUBBLUB! {player} hits level {level}!")
Set("NERGLISH_LVL_PLAYFUL_2", "GLRGLRGL! Our friend {player} is now level {level}!")
Set("NERGLISH_LVL_PLAYFUL_3", "Mrrrgl-glub! {player} at level {level} — the murloc cheers!")

Set("NERGLISH_LVL_RARE_01", "Mrrgl! {player} reached level {level}! A fish as a reward!")
Set("NERGLISH_LVL_RARE_02", "Blrglblub! {player} is level {level}! Somersault time!")
Set("NERGLISH_LVL_RARE_03", "GLRGL! Another level for {player}! The pond grows with its heroes!")
Set("NERGLISH_LVL_RARE_04", "Mrrglgrgl! Level {level}! {player} is the biggest fish today!")
Set("NERGLISH_LVL_RARE_05", "Blub! {player} gets stronger. The Murloc is getting jealous!")
Set("NERGLISH_LVL_RARE_06", "MRRGL! Level {level}! {player} earns an imaginary fish medal!")
Set("NERGLISH_LVL_RARE_07", "Glubglub! {player} is level {level}! The Murloc tries to count along!")
Set("NERGLISH_LVL_RARE_08", "Brrgl! One more level! {player} makes the Murloc proud!")
Set("NERGLISH_LVL_RARE_09", "Mrrrgl! {player} reached level {level}! Smells like a feast!")
Set("NERGLISH_LVL_RARE_10", "Blrgl! {player} levels up! Victory-dance practice begins!")

Set("NERGLISH_LVL_LEGEND_11", "MRRRAAAGL! {player} is level {level} — the Murloc can't stop dancing!")
Set("NERGLISH_LVL_LEGEND_12", "GLRGLGRGL! {player} grew stronger. The fish of destiny foresaw this!")
Set("NERGLISH_LVL_LEGEND_13", "BLRGLBLUB! Level {level}! The Murloc awards {player} the golden bubble medal!")
Set("NERGLISH_LVL_LEGEND_14", "MRRRGL! {player} levels up — ten out of ten fish recommend this hero!")
Set("NERGLISH_LVL_LEGEND_15", "GRGLGRGL! The Murloc hugged a rock with joy. {player} is level {level}!")
Set("NERGLISH_LVL_LEGEND_16", "MRRRRGL! {player} is level {level}! The Murloc tried to cheer with a fish in his mouth!")

-- ===== Level milestone =====
Set("NERGLISH_LVL_M_SUBTLE_1", "Mrrgl! Milestone: {player} reached level {level}.")
Set("NERGLISH_LVL_M_SUBTLE_2", "Grgl! Nice round number — {player} is at {level}.")
Set("NERGLISH_LVL_M_SUBTLE_3", "Blub! Proud of {player}: level {level}.")
Set("NERGLISH_LVL_M_PLAYFUL_1", "MRRRRGL! {player} smashes level {level}!")
Set("NERGLISH_LVL_M_PLAYFUL_2", "BLUBBLUB! Milestone for {player} — level {level}!")
Set("NERGLISH_LVL_M_PLAYFUL_3", "Grglgrglgr! {player} at {level} — pond party!")

Set("NERGLISH_LVL_M_RARE_01", "MRRRGL! {player} reached level {level}! The whole pond is cheering!")
Set("NERGLISH_LVL_M_RARE_02", "Blrglblub! Level {level}! Fish tossed sky-high!")
Set("NERGLISH_LVL_M_RARE_03", "GLRGLGL! {player} keeps getting stronger. Even the crabs applaud!")
Set("NERGLISH_LVL_M_RARE_04", "Mrrrgl! Level {level}! Today is a fish holiday!")
Set("NERGLISH_LVL_M_RARE_05", "BRRGL! {player} reached level {level}! Three bubbles for our hero!")
Set("NERGLISH_LVL_M_RARE_06", "Mrrglgrgl! {player} hit level {level}. The fish are impressed!")
Set("NERGLISH_LVL_M_RARE_07", "BLRGL! The Murloc recounts … yes! {player} really is level {level}!")
Set("NERGLISH_LVL_M_RARE_08", "Glubglub! {player} reached level {level}. Grand victory dance!")
Set("NERGLISH_LVL_M_RARE_09", "Rwlglgl! Level {level}! The Murloc saved his finest fish for this!")
Set("NERGLISH_LVL_M_RARE_10", "MRRGL! {player} reaches level {level}. New pond champion!")

Set("NERGLISH_LVL_M_LEGEND_11", "MRRRRGLGRGLGR! Level {level}! Wake the Elder Murloc — {player} did it!")
Set("NERGLISH_LVL_M_LEGEND_12", "BLRGLGRGL! The chosen fish awakens — {player} reached level {level}!")
Set("NERGLISH_LVL_M_LEGEND_13", "MRRRAAAGL! {player} is level {level}! One fish, two fish, an entire feast!")
Set("NERGLISH_LVL_M_LEGEND_14", "GLRGLGLGL! {player} hit level {level} — the Murloc is swimming backwards with joy!")
Set("NERGLISH_LVL_M_LEGEND_15", "MRRRGL! Beware Azeroth — {player} is level {level}! The pond is no longer safe!")
Set("NERGLISH_LVL_M_LEGEND_16", "BRRRAAAGL! The Council of Seven Fish decrees: {player} is level {level} and deserves a feast!")

-- ===== Death =====
Set("NERGLISH_DEATH_SUBTLE_1", "Mrrgl… {player} has fallen ({zone}).")
Set("NERGLISH_DEATH_SUBTLE_2", "Blub… Sad splash: {player} in {zone}.")
Set("NERGLISH_DEATH_SUBTLE_3", "Grgl… {player} needs help in {zone}.")
Set("NERGLISH_DEATH_PLAYFUL_1", "Mrrglgl… Oh no, {player} in {zone}!")
Set("NERGLISH_DEATH_PLAYFUL_2", "Rwl… {player} went splash in {zone}.")
Set("NERGLISH_DEATH_PLAYFUL_3", "Blrgl… The pond mourns {player} ({zone}).")

Set("NERGLISH_DEATH_RARE_01", "Blrrgl?! {player} died! The Murloc drops his fish in shock!")
Set("NERGLISH_DEATH_RARE_02", "Mrrgl … {player} has fallen. The pond falls silent.")
Set("NERGLISH_DEATH_RARE_03", "BLRGL?! Who took down {player}? The Murloc demands answers!")
Set("NERGLISH_DEATH_RARE_04", "Glub … glub … {player} is dead. Even the fish didn't see that coming.")
Set("NERGLISH_DEATH_RARE_05", "Mrrrgl?! {player}, get up! Still have fish for you!")
Set("NERGLISH_DEATH_RARE_06", "Blrgl … {player} has fallen. A little Murloc lights an imaginary candle.")
Set("NERGLISH_DEATH_RARE_07", "GRGL?! {player} died! The Murloc hides just to be safe.")
Set("NERGLISH_DEATH_RARE_08", "Mrrglblub … {player} is down. Comfort fish deployed.")
Set("NERGLISH_DEATH_RARE_09", "Blrrgl! {player} has fallen. That was definitely not the plan!")
Set("NERGLISH_DEATH_RARE_10", "Glrgl? {player} died? The Murloc was about to congratulate them!")

Set("NERGLISH_DEATH_LEGEND_11", "MRRRRGL?! {player} is dead?! Who broke my favorite hero?!")
Set("NERGLISH_DEATH_LEGEND_12", "BLRGL! Emergency! {player} has fallen — fetch the healing fish!")
Set("NERGLISH_DEATH_LEGEND_13", "MRRGL?! {player} died! The Murloc demands immediate resurrection!")
Set("NERGLISH_DEATH_LEGEND_14", "GLRGLGL?! {player} is dead! The Murloc swallowed his last fish in shock!")
Set("NERGLISH_DEATH_LEGEND_15", "BLRGLBLUB! {player} is down! Call a healer … and a cook!")
Set("NERGLISH_DEATH_LEGEND_16", "MRRRGLGRGL! {player} has fallen! Three days of mourning — or until rez!")

-- ===== Wanted sight (prefix cries only) =====
Set("NERGLISH_SIGHT_SUBTLE_1", "Mrrgl!")
Set("NERGLISH_SIGHT_SUBTLE_2", "Grgl!")
Set("NERGLISH_SIGHT_SUBTLE_3", "Rwl!")
Set("NERGLISH_SIGHT_PLAYFUL_1", "MRRRRGL!")
Set("NERGLISH_SIGHT_PLAYFUL_2", "Rwlrlrlrl!")
Set("NERGLISH_SIGHT_PLAYFUL_3", "Grglgrglgr!")

Set("NERGLISH_SIGHT_RARE_01", "GRRRGL! Enemy spotted!")
Set("NERGLISH_SIGHT_RARE_02", "MRRGL! The Murloc smells trouble!")
Set("NERGLISH_SIGHT_RARE_03", "BLRGL! Wrong pond, stranger!")
Set("NERGLISH_SIGHT_RARE_04", "GRGLGRGL! On your fins, warriors!")
Set("NERGLISH_SIGHT_RARE_05", "RWLGRGL! The Murloc bares his teeth!")
Set("NERGLISH_SIGHT_RARE_06", "MRRRAA! An enemy! Where's my spear?!")
Set("NERGLISH_SIGHT_RARE_07", "GLRGL! The pond is on high alert!")
Set("NERGLISH_SIGHT_RARE_08", "GRRRBLGL! Let the hunt begin!")
Set("NERGLISH_SIGHT_RARE_09", "MRRGL! Fishy feeling about this!")
Set("NERGLISH_SIGHT_RARE_10", "RWRWRGL! Warriors, get ready!")

Set("NERGLISH_SIGHT_LEGEND_11", "MRRRRGL! Pond alert — all Murlocs to the front!")
Set("NERGLISH_SIGHT_LEGEND_12", "GRRRGLGRGL! The fish war council demands revenge!")
Set("NERGLISH_SIGHT_LEGEND_13", "MRRRAAAGL! Spears, shields — and the big fish!")
Set("NERGLISH_SIGHT_LEGEND_14", "BLRGLGRGL! War paint licked on. Ready.")
Set("NERGLISH_SIGHT_LEGEND_15", "GRRRRGL! All fins attack — nobody threatens our pond!")
Set("NERGLISH_SIGHT_LEGEND_16", "MRRRGLGRGL! The Elder Murloc has spoken: show them your teeth!")
