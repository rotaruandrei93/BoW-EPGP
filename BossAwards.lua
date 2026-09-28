-- BossAwards.lua
-- Preset EP awards per boss kill. EDIT THE NUMBERS TO MATCH YOUR GUILD.
--
-- Key   = boss name exactly as it appears in the combat log ("<name> dies.")
-- ep    = EP given to the raid on kill
-- id    = NPC id, informational only (the 1.12 combat log doesn't expose it)
-- zone  = informational only
-- encounter = optional. Bosses sharing the same encounter string count as ONE
--             kill; the prompt appears only after ALL of them have died
--             (Twin Emperors, Four Horsemen, Bug Trio...). Give them all the same ep.
--
-- Bosses that never "die" (e.g. Majordomo) can't be detected by the combat log;
-- use "/bossaward now" while targeting the corpse/chest owner, or add them and
-- rely on the loot-window fallback.

SEPGP_BOSS_AWARDS = {
  -- Molten Core
  ["Lucifron"]                  = { ep = 2, zone = "Molten Core", id = 12118 },
  ["Magmadar"]                  = { ep = 2, zone = "Molten Core", id = 11982 },
  ["Garr"]                      = { ep = 2, zone = "Molten Core", id = 12057 },
  ["Shazzrah"]                  = { ep = 2, zone = "Molten Core", id = 12264 },
  ["Baron Geddon"]              = { ep = 2, zone = "Molten Core", id = 12056 },
  ["Sulfuron Harbinger"]        = { ep = 2, zone = "Molten Core", id = 12098 },
  ["Golemagg the Incinerator"]  = { ep = 2, zone = "Molten Core", id = 11988 },
  ["Majordomo Executus"]        = { ep = 2, zone = "Molten Core", id = 12018 },
  ["Incindis"]                  = { ep = 2, zone = "Molten Core", id = 52145 },
  ["Basalthar & Smoldaris"]     = { ep = 2, zone = "Molten Core", encounter = "Basalthar & Smoldaris" },
  ["Sorcerer-Thane Thaurissan"] = { ep = 2, zone = "Molten Core", id = 57642 },
  ["Ragnaros"]                  = { ep = 2, zone = "Molten Core", id = 11502 },

  -- Onyxia
  ["Broodcommander Axelus"]     = { ep = 10, zone = "Onyxia's Lair", id = 49018 },
  ["Onyxia"]                    = { ep = 10, zone = "Onyxia's Lair", id = 10184 },

  -- Blackwing Lair
  ["Razorgore the Untamed"]     = { ep = 4, zone = "Blackwing Lair", id = 12435 },
  ["Vaelastrasz the Corrupt"]   = { ep = 4, zone = "Blackwing Lair", id = 13020 },
  ["Broodlord Lashlayer"]       = { ep = 4, zone = "Blackwing Lair", id = 12017 },
  ["Firemaw"]                   = { ep = 4, zone = "Blackwing Lair", id = 11983 },
  ["Ezzel Darkbrewer"]          = { ep = 4, zone = "Blackwing Lair", id = 65148 },
  ["Ebonroc"]                   = { ep = 4, zone = "Blackwing Lair", id = 14601 },
  ["Flamegor"]                  = { ep = 4, zone = "Blackwing Lair", id = 11981 },
  ["Chromaggus"]                = { ep = 4, zone = "Blackwing Lair", id = 14020 },
  ["Nefarian"]                  = { ep = 4, zone = "Blackwing Lair", id = 11583 },

  -- Emerald Sanctum
  ["Erennius"]                  = { ep = 10, zone = "Emerald Sanctum", id = 60747 },
  ["Solnius"]                   = { ep = 10, zone = "Emerald Sanctum", id = 60748 },

  -- Ahn'Qiraj 40
  ["The Prophet Skeram"]        = { ep = 20, zone = "Temple of Ahn'Qiraj" },
  ["Battleguard Sartura"]       = { ep = 20, zone = "Temple of Ahn'Qiraj" },
  ["Fankriss the Unyielding"]   = { ep = 20, zone = "Temple of Ahn'Qiraj" },
  ["Viscidus"]                  = { ep = 20, zone = "Temple of Ahn'Qiraj" },
  ["Princess Huhuran"]          = { ep = 20, zone = "Temple of Ahn'Qiraj" },
  ["Lord Kri"]                  = { ep = 20, zone = "Temple of Ahn'Qiraj", encounter = "Bug Trio" },
  ["Princess Yauj"]             = { ep = 20, zone = "Temple of Ahn'Qiraj", encounter = "Bug Trio" },
  ["Vem"]                       = { ep = 20, zone = "Temple of Ahn'Qiraj", encounter = "Bug Trio" },
  ["Emperor Vek'lor"]           = { ep = 25, zone = "Temple of Ahn'Qiraj", encounter = "Twin Emperors" },
  ["Emperor Vek'nilash"]        = { ep = 25, zone = "Temple of Ahn'Qiraj", encounter = "Twin Emperors" },
  ["Ouro"]                      = { ep = 25, zone = "Temple of Ahn'Qiraj" },
  ["C'Thun"]                    = { ep = 30, zone = "Temple of Ahn'Qiraj", id = 15727 },

  -- Timbermaw Hold
  ["Karrsh the Sentinel"]       = { ep = 2, zone = "Timbermaw Hold", id = 62934 },
  ["Kodiak & Rotgrowl"]         = { ep = 2, zone = "Timbermaw Hold", encounter = "Kodiak & Rotgrowl" },
  ["Ormanos the Cracked"]       = { ep = 2, zone = "Timbermaw Hold", id = 62935 },
  ["Archdruid Kronn"]           = { ep = 2, zone = "Timbermaw Hold", id = 62938 },
  ["Loktanag the Vile"]         = { ep = 2, zone = "Timbermaw Hold", id = 2139 },
  ["Trioch the Devourer"]       = { ep = 2, zone = "Timbermaw Hold", id = 62946 },
  ["Selenaxx Foulheart"]        = { ep = 2, zone = "Timbermaw Hold", id = 62940 },
  ["Chieftain Partath"]         = { ep = 2, zone = "Timbermaw Hold", id = 62941 },
  ["Ursol"]                     = { ep = 2, zone = "Timbermaw Hold", id = 62947 },

  -- Naxxramas
  ["Anub'Rekhan"]               = { ep = 25, zone = "Naxxramas" },
  ["Grand Widow Faerlina"]      = { ep = 25, zone = "Naxxramas" },
  ["Maexxna"]                   = { ep = 25, zone = "Naxxramas" },
  ["Noth the Plaguebringer"]    = { ep = 25, zone = "Naxxramas" },
  ["Heigan the Unclean"]        = { ep = 25, zone = "Naxxramas" },
  ["Loatheb"]                   = { ep = 25, zone = "Naxxramas" },
  ["Instructor Razuvious"]      = { ep = 25, zone = "Naxxramas" },
  ["Gothik the Harvester"]      = { ep = 25, zone = "Naxxramas" },
  ["Thane Korth'azz"]           = { ep = 25, zone = "Naxxramas", encounter = "Four Horsemen" },
  ["Lady Blaumeux"]             = { ep = 25, zone = "Naxxramas", encounter = "Four Horsemen" },
  ["Highlord Mograine"]         = { ep = 25, zone = "Naxxramas", encounter = "Four Horsemen" },
  ["Sir Zeliek"]                = { ep = 25, zone = "Naxxramas", encounter = "Four Horsemen" },
  ["Patchwerk"]                 = { ep = 25, zone = "Naxxramas" },
  ["Grobbulus"]                 = { ep = 25, zone = "Naxxramas" },
  ["Gluth"]                     = { ep = 25, zone = "Naxxramas" },
  ["Thaddius"]                  = { ep = 25, zone = "Naxxramas" },
  ["Sapphiron"]                 = { ep = 30, zone = "Naxxramas" },
  ["Kel'Thuzad"]                = { ep = 40, zone = "Naxxramas", id = 15990 },

  -- Upper Karazhan Tower / Kara40
  ["Keeper Gnarlmoon"]          = { ep = 2, zone = "Tower of Karazhan", id = 61939 },
  ["Ley-Watcher Incantagos"]    = { ep = 2, zone = "Tower of Karazhan", id = 61946 },
  ["Anomalus"]                  = { ep = 2, zone = "Tower of Karazhan", id = 61951 },
  ["Echo of Medivh"]            = { ep = 2, zone = "Tower of Karazhan", id = 61958 },
  ["Chess Event"]               = { ep = 2, zone = "Tower of Karazhan", encounter = "Chess Event" },
  ["Sanv Tas'dal"]              = { ep = 2, zone = "Tower of Karazhan", id = 59981 },
  ["Rupturan the Broken"]       = { ep = 2, zone = "Tower of Karazhan", id = 59961 },
  ["Kruul"]                     = { ep = 2, zone = "Tower of Karazhan", id = 59991 },
  ["Mephistroth"]               = { ep = 2, zone = "Tower of Karazhan", id = 93333 },

  --World Bosses
  ["Azuregos"]                  = { ep = 10, zone = "Azshara", id = 6109 },
  ["Lord Kazzak"]               = { ep = 10, zone = "Blasted Lands", id = 12397 },
  ["Emeriss"]                   = { ep = 10, zone = "Ashenvale", id = 14889 },
  ["Lethon"]                    = { ep = 10, zone = "The Hinterlands", id = 14888 },
  ["Taerar"]                    = { ep = 10, zone = "Ashenvale", id = 14890 },
  ["Ysondre"]                   = { ep = 10, zone = "Feralas", id = 14887 },
  ["Cla'ckora"]                 = { ep = 10, zone = "Azshara", id = 59963 },
  ["Concavius"]                 = { ep = 10, zone = "Desolace", id = 92213 },
  ["Dark Reaver of Karazhan"]   = { ep = 10, zone = "Deadwind Pass", id = 80936 },
  ["Ostarius of Uldum"]         = { ep = 10, zone = "Tanaris", id = 80935 },
  ["Nerubian Overseer"]         = { ep = 10, zone = "Eastern Plaguelands", id = 16184 },
  ["Father Lycan"]              = { ep = 10, zone = "Hyjal", id = 62059 },
}
