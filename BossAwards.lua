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
  -- Onyxia
  ["Onyxia"]                    = { ep = 10, zone = "Onyxia's Lair", id = 10184 },

  -- Molten Core
  ["Lucifron"]                  = { ep = 2, zone = "Molten Core" },
  ["Magmadar"]                  = { ep = 2, zone = "Molten Core" },
  ["Gehennas"]                  = { ep = 2, zone = "Molten Core" },
  ["Garr"]                      = { ep = 2, zone = "Molten Core" },
  ["Shazzrah"]                  = { ep = 2, zone = "Molten Core" },
  ["Baron Geddon"]              = { ep = 2, zone = "Molten Core" },
  ["Sulfuron Harbinger"]        = { ep = 2, zone = "Molten Core" },
  ["Golemagg the Incinerator"]  = { ep = 2, zone = "Molten Core" },
  ["Ragnaros"]                  = { ep = 2, zone = "Molten Core", id = 11502 },

  -- Blackwing Lair
  ["Razorgore the Untamed"]     = { ep = 4, zone = "Blackwing Lair" },
  ["Vaelastrasz the Corrupt"]   = { ep = 4, zone = "Blackwing Lair" },
  ["Broodlord Lashlayer"]       = { ep = 4, zone = "Blackwing Lair" },
  ["Firemaw"]                   = { ep = 4, zone = "Blackwing Lair" },
  ["Ebonroc"]                   = { ep = 4, zone = "Blackwing Lair" },
  ["Flamegor"]                  = { ep = 4, zone = "Blackwing Lair" },
  ["Chromaggus"]                = { ep = 4, zone = "Blackwing Lair" },
  ["Nefarian"]                  = { ep = 4, zone = "Blackwing Lair", id = 11583 },

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
}
