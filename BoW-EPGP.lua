sepgp = AceLibrary("AceAddon-2.0"):new("AceConsole-2.0", "AceHook-2.1", "AceDB-2.0", "AceDebug-2.0", "AceEvent-2.0", "AceModuleCore-2.0", "FuBarPlugin-2.0")
sepgp:SetModuleMixins("AceDebug-2.0")
local D = AceLibrary("Dewdrop-2.0")
local BZ = AceLibrary("Babble-Zone-2.2")
local C = AceLibrary("Crayon-2.0")
local BC = AceLibrary("Babble-Class-2.2")
local DF = AceLibrary("Deformat-2.0")
local G = AceLibrary("Gratuity-2.0")
local T = AceLibrary("Tablet-2.0")
local L = AceLibrary("AceLocale-2.2"):new("shootyepgp")
sepgp.VARS = {
  basegp = 10,
  minep = 0,
  baseaward_ep = 10,
  decay = 0.9,
  max = 1000,
  timeout = 60,
  minlevel = 55,
  bidtimer = 6,
  maxloglines = 500,
  prefix = "SEPGP_PREFIX",
  reservechan = "Reserves",
  reserveanswer = "^(%+)(%a*)$",
  bop = C:Red("BoP"),
  boe = C:Yellow("BoE"),
  nobind = C:White("NoBind"),
  msgp = "Mainspec GP",
  osgp = "Offspec GP",
  bankde = "Bank-D/E",
  tmgp = "Transmog (0 GP)",
  flexgp = "Flex GP",
  reminder = C:Red("Unassigned"),
}
sepgp.VARS.reservecall = string.format(L["{BoW-EPGP}Type \"+\" if on main, or \"+<YourMainName>\" (without quotes) if on alt within %dsec."],sepgp.VARS.timeout)
sepgp._playerName = (UnitName("player"))
local out = "|cff9664c8BoW-EPGP:|r %s"
local raidStatus,lastRaidStatus
local lastUpdate = 0
local needInit,needRefresh = true
local admin,sanitizeNote
local shooty_debugchat
local running_check,running_bid
local partyUnit,raidUnit = {},{}
local hexColorQuality = {}
local reserves_blacklist,bids_blacklist = {},{}
local bidlink = {
  ["ms"]="|cffFF3333|Hshootybid:1:$ML|h[MS]|h|r",
  ["flex"]="|cffFFAA00|Hshootybid:3:$ML|h[FLEX]|h|r",
  ["os"]="|cff009900|Hshootybid:2:$ML|h[OS]|h|r",
  ["tm"]="|cff00FFFF|Hshootybid:4:$ML|h[TM]|h|r",
  ["pass"]="|cff999999|Hshootybid:5:$ML|h[PASS]|h|r"
}
local options
do
  for i=1,40 do
    raidUnit[i] = "raid"..i
  end
  for i=1,4 do
    partyUnit[i] = "party"..i
  end
  for i=-1,6 do
    hexColorQuality[ITEM_QUALITY_COLORS[i].hex] = i
  end
end
local admincmd, membercmd = {type = "group", handler = sepgp, args = {
    bids = {
      type = "execute",
      name = L["Bids"],
      desc = "Print current bid status.",
      func = function()
        sepgp:printBidStatus()
      end,
      order = 1,
    },
    show = {
      type = "execute",
      name = L["Standings"],
      desc = L["Show Standings Table."],
      func = function()
        sepgp_standings:Toggle()
      end,
      order = 2,
    },    
    clearloot = {
      type = "execute",
      name = L["ClearLoot"],
      desc = L["Clear Loot Table."],
      func = function()
        sepgp_looted = {}
        sepgp_loot:Refresh()
        sepgp:defaultPrint(L["Loot info cleared"])
      end,
      order = 3,
    },
    clearlogs = {
      type = "execute",
      name = L["ClearLogs"],
      desc = L["Clear Logs Table."],
      func = function()
        sepgp_log = {}
        sepgp_logs:Refresh()
        sepgp:defaultPrint(L["Logs cleared"])
      end,
      order = 4,
    },
    progress = {
      type = "execute",
      name = L["Progress"],
      desc = L["Print Progress Multiplier."],
      func = function()
        sepgp:defaultPrint(sepgp_progress)
      end,
      order = 5,
    },
    setprogress = {
      type = "text",
      name = "Set Progress",
      desc = "Set raid progress tier. Valid: T1, T2, T2.5, T3",
      get = function() return sepgp_progress end,
      set = function(v)
        local valid = { ["T1"]=true, ["T2"]=true, ["T2.5"]=true, ["T3"]=true }
        local val = string.upper(v)
        if valid[val] then
          sepgp_progress = val
          sepgp:defaultPrint("Progress set to: " .. val)
          sepgp:refreshPRTablets()
          if (IsGuildLeader()) then
            sepgp:shareSettings(true)
          end
        else
          sepgp:defaultPrint("Invalid tier. Use: T1, T2, T2.5, or T3")
        end
      end,
      usage = "<T1|T2|T2.5|T3>",
      order = 6,
    },
    offspec = {
      type = "execute",
      name = L["Offspec"],
      desc = L["Print Offspec Price."],
      func = function()
        sepgp:defaultPrint(string.format("%s%%",sepgp_discount*100))
      end,
      order = 6,
    },    
    restart = {
      type = "execute",
      name = L["Restart"],
      desc = L["Restart BoW-EPGP if having startup problems."],
      func = function()
        sepgp:OnEnable()
        sepgp:defaultPrint(L["Restarted"])
      end,
      order = 7,
    },
    test = {
      type = "text",
      name = "Test Bid",
      desc = "Start a test bid cycle. Usage: /bowepgp test [gp_cost]",
      get = function() return "" end,
      set = function(v) sepgp:startTestBid(v) end,
      usage = "<gp_cost>",
      order = 8,
    },
    testend = {
      type = "execute",
      name = "End Test Bid",
      desc = "End a running test bid and announce results.",
      func = function() sepgp:endTestBid() end,
      order = 9,
    },
    -- 2026-04-06 v4.22: production parity with /bowepgp testend.
    -- Officers can manually end real bids and force the resolution
    -- popup, instead of waiting for the loot capture chain to fire it.
    ["end"] = {
      type = "execute",
      name = "End Bid",
      desc = "End the current bid cycle and force the resolution popup. Production version of /bowepgp testend.",
      func = function() sepgp:endBidNow() end,
      order = 9,
    },
    testbid = {
      type = "text",
      name = "Inject Test Bid",
      desc = "Inject a fake bid during test mode. Usage: /bowepgp testbid ms FakeName or /bowepgp testbid tm FakeName",
      get = function() return "" end,
      set = function(v) sepgp:injectTestBid(v) end,
      usage = "<keyword> <name>",
      order = 10,
    },
    delist = {
      type = "execute",
      name = "DE Roster List",
      desc = "Show all players on the disenchanter roster.",
      func = function() sepgp:deRosterList() end,
      order = 11,
    },
    extlist = {
      type = "execute",
      name = "External Mains List",
      desc = "List all external mains (players in other guilds) currently linked to a banker alt in this guild.",
      func = function() sepgp:externalMainsList() end,
      order = 12,
    },
    debuglog = {
      type = "execute",
      name = "Clear Debug Log",
      desc = "Clear the persistent debug log.",
      func = function()
        SEPGP_DEBUG_LOG = {}
        sepgp:defaultPrint("Debug log cleared.")
      end,
      order = 14,
    },
    testitem = {
      type = "text",
      name = "Test with Item ID",
      desc = "Start a test bid with a real item from prices.lua. Usage: /bowepgp testitem 21682",
      get = function() return "" end,
      set = function(v) sepgp:startTestWithItem(v) end,
      usage = "<itemId>",
      order = 15,
    },
    bid = {
      type = "execute",
      name = "Show Bid Window",
      desc = "Reopen the bid popup window if you closed it.",
      func = function()
        if sepgp.bid_item and (sepgp.bid_item.link or sepgp.bid_item.name) then
          sepgp:ShowBidPopup(
            sepgp.bid_item.linkFull,
            sepgp.bid_item.name,
            sepgp.bid_item.price or "?",
            sepgp_bid_popup_ml or sepgp._playerName
          )
        else
          sepgp:defaultPrint("No active bid to show.")
        end
      end,
      order = 11,
    },
  }},
{type = "group", handler = sepgp, args = {
    show = {
      type = "execute",
      name = L["Standings"],
      desc = L["Show Standings Table."],
      func = function()
        sepgp_standings:Toggle()
      end,
      order = 1,
    },
    progress = {
      type = "execute",
      name = L["Progress"],
      desc = L["Print Progress Multiplier."],
      func = function()
        sepgp:defaultPrint(sepgp_progress)
      end,
      order = 2,
    },
    offspec = {
      type = "execute",
      name = L["Offspec"],
      desc = L["Print Offspec Price."],
      func = function()
        sepgp:defaultPrint(string.format("%s%%",sepgp_discount*100))
      end,
      order = 3,
    },
    restart = {
      type = "execute",
      name = L["Restart"],
      desc = L["Restart BoW-EPGP if having startup problems."],
      func = function() 
        sepgp:OnEnable()
        sepgp:defaultPrint(L["Restarted"])
      end,
      order = 4,
    },    
  }}
  --[[{
    type = "execute",
    name = "Standings",
    desc = "Show Standings Table.",
    func = function()
      sepgp_standings:Toggle()
    end,
  }]]  
sepgp.cmdtable = function() 
  if (admin()) then
    return admincmd
  else
    return membercmd
  end
end
sepgp.reserves = {}
sepgp.bids_main,sepgp.bids_flex,sepgp.bids_off,sepgp.bids_tm,sepgp.bid_item = {},{},{},{},{}
sepgp.timer = CreateFrame("Frame")
sepgp.timer.cd_text = ""
sepgp.timer:Hide()
sepgp.timer:SetScript("OnUpdate",function() sepgp.OnUpdate(this,arg1) end)
sepgp.timer:SetScript("OnEvent",function() 
end)
sepgp.alts = {}

function sepgp:buildMenu()
  if not (options) then
    options = {
    type = "group",
    desc = string.format("BoW-EPGP v%s", sepgp._versionString or "?"),
    handler = self,
    args = { }
    }
    options.args["version"] = {
      type = "execute",
      name = "Version",
      desc = "Show addon version",
      order = 1,
      func = function() sepgp:defaultPrint(string.format("BoW-EPGP v%s", sepgp._versionString or "?")) end,
    }
    options.args["ep"] = {
      type = "group",
      name = L["+EPs to Member"],
      desc = L["Account EPs for member."],
      order = 10,
      hidden = function() return not (admin()) end,
    }
    options.args["ep_raid"] = {
      type = "text",
      name = L["+EPs to Raid"],
      desc = L["Award EPs to all raid members."],
      order = 20,
      get = "suggestedAwardEP",
      set = function(v) sepgp:award_raid_ep(tonumber(v)) end,
      usage = "<EP>",
      hidden = function() return not (admin()) end,
      validate = function(v)
        local n = tonumber(v)
        return n and n >= 0 and n < sepgp.VARS.max
      end
    }
    options.args["gp"] = {
      type = "group",
      name = L["+GPs to Member"],
      desc = L["Account GPs for member."],
      order = 30,
      hidden = function() return not (admin()) end,
    }
    options.args["ep_reserves"] = {
      type = "text",
      name = L["+EPs to Reserves"],
      desc = L["Award EPs to all active Reserves."],
      order = 40,
      get = "suggestedAwardEP",
      set = function(v) sepgp:award_reserve_ep(tonumber(v)) end,
      usage = "<EP>",
      hidden = function() return not (admin()) end,
      validate = function(v)
        local n = tonumber(v)
        return n and n >= 0 and n < sepgp.VARS.max
      end    
    }
    options.args["reserves"] = {
      type = "toggle",
      name = L["Enable Reserves"],
      desc = L["Participate in Standby Raiders List.\n|cffff0000Requires Main Character Name.|r"],
      order = 50,
      get = function() return (sepgp.reservesChannelID ~= nil) and (sepgp.reservesChannelID ~= 0) end,
      set = function(v) sepgp:reservesToggle(v) end,
      disabled = function() return (sepgp_main == nil) end
    }
    options.args["afkcheck_reserves"] = {
      type = "execute",
      name = L["AFK Check Reserves"],
      desc = L["AFK Check Reserves List"],
      order = 60,
      hidden = function() return not (admin()) end,
      func = function() sepgp:afkcheck_reserves() end
    }
    options.args["alts"] = {
      type = "toggle",
      name = L["Enable Alts"],
      desc = L["Allow Alts to use Main\'s EPGP."],
      order = 63,
      hidden = function() return not (admin()) end,
      disabled = function() return not (IsGuildLeader()) end,
      get = function() return not not sepgp_altspool end,
      set = function(v) 
        sepgp_altspool = not sepgp_altspool
        if (IsGuildLeader()) then
          sepgp:shareSettings(true)
        end
      end,
    }
    options.args["alts_percent"] = {
      type = "range",
      name = L["Alts EP %"],
      desc = L["Set the % EP Alts can earn."],
      order = 66,
      hidden = function() return (not sepgp_altspool) or (not IsGuildLeader()) end,
      get = function() return sepgp_altpercent end,
      set = function(v) 
        sepgp_altpercent = v
        if (IsGuildLeader()) then
          sepgp:shareSettings(true)
        end
      end,
      min = 0.5,
      max = 1,
      step = 0.05,
      isPercent = true
    }
    options.args["set_main"] = {
      type = "text",
      name = L["Set Main"],
      desc = L["Set your Main Character for Reserve List."],
      order = 70,
      usage = "<MainChar>",
      get = function() return sepgp_main end,
      set = function(v) sepgp_main = (sepgp:verifyGuildMember(v)) end,
    }    
    options.args["raid_only"] = {
      type = "toggle",
      name = L["Raid Only"],
      desc = L["Only show members in raid."],
      order = 80,
      get = function() return not not sepgp_raidonly end,
      set = function(v) 
        sepgp_raidonly = not sepgp_raidonly
        sepgp:SetRefresh(true)
      end,
    }
    options.args["progress_tier_header"] = {
      type = "header",
      name = string.format(L["Progress Setting: %s"],sepgp_progress),
      order = 85,
      hidden = function() return admin() end,
    }
    options.args["progress_tier"] = {
      type = "text",
      name = L["Raid Progress"],
      desc = L["Highest Tier the Guild is raiding.\nUsed to adjust GP Prices.\nUsed for suggested EP awards."],
      order = 90,
      hidden = function() return not (admin()) end,
      get = function() return sepgp_progress end,
      set = function(v) 
        sepgp_progress = v 
        sepgp:refreshPRTablets()
        if (IsGuildLeader()) then
          sepgp:shareSettings(true)
        end
      end,
      validate = { ["T3"]=L["4.Naxxramas"], ["T2.5"]=L["3.Temple of Ahn\'Qiraj"], ["T2"]=L["2.Blackwing Lair"], ["T1"]=L["1.Molten Core"]},
    }
    options.args["report_channel"] = {
      type = "text",
      name = L["Reporting channel"],
      desc = L["Channel used by reporting functions."],
      order = 95,
      hidden = function() return not (admin()) end,
      get = function() return sepgp_saychannel end,
      set = function(v) sepgp_saychannel = v end,
      validate = { "PARTY", "RAID", "GUILD", "OFFICER" },
    }    
    options.args["decay"] = {
      type = "execute",
      name = L["Decay EPGP"],
      desc = string.format(L["Decays all EPGP by %s%%"],(1-(sepgp_decay or sepgp.VARS.decay))*100),
      order = 100,
      hidden = function() return not (admin()) end,
      func = function() sepgp:decay_epgp_v3() end 
    }    
    options.args["set_decay"] = {
      type = "range",
      name = L["Set Decay %"],
      desc = L["Set Decay percentage (Admin only)."],
      order = 110,
      usage = "<Decay>",
      get = function() return (1.0-sepgp_decay) end,
      set = function(v) 
        sepgp_decay = (1 - v)
        options.args["decay"].desc = string.format(L["Decays all EPGP by %s%%"],(1-sepgp_decay)*100)
        if (IsGuildLeader()) then
          sepgp:shareSettings(true)
        end
      end,
      min = 0.01,
      max = 0.5,
      step = 0.01,
      bigStep = 0.05,
      isPercent = true,
      hidden = function() return not (admin()) end,    
    }
    options.args["set_discount_header"] = {
      type = "header",
      name = string.format(L["Offspec Price: %s%%"],sepgp_discount*100),
      order = 111,
      hidden = function() return admin() end,
    }
    options.args["set_discount"] = {
      type = "range",
      name = L["Offspec Price %"],
      desc = L["Set Offspec Items GP Percent."],
      order = 115,
      hidden = function() return not (admin()) end,
      get = function() return sepgp_discount end,
      set = function(v) 
        sepgp_discount = v
        if (IsGuildLeader()) then
          sepgp:shareSettings(true)
        end
      end,
      min = 0,
      max = 1,
      step = 0.05,
      isPercent = true
    }
    options.args["set_min_ep_header"] = {
      type = "header",
      name = string.format(L["Minimum EP: %s"],sepgp_minep),
      order = 117,
      hidden = function() return admin() end,
    }
    options.args["set_min_ep"] = {
      type = "text",
      name = L["Minimum EP"],
      desc = L["Set Minimum EP"],
      usage = "<minep>",
      order = 118,
      get = function() return sepgp_minep end,
      set = function(v) 
        sepgp_minep = tonumber(v)
        sepgp:refreshPRTablets()
        if (IsGuildLeader()) then
          sepgp:shareSettings(true)
        end        
      end,
      validate = function(v) 
        local n = tonumber(v)
        return n and n >= 0 and n <= sepgp.VARS.max
      end,
      hidden = function() return not admin() end,
    }
    options.args["set_bid_timer"] = {
      type = "range",
      name = "Bid Timer (seconds)",
      desc = "How many seconds the bid countdown runs before auto-resolving.",
      order = 119,
      get = function() return sepgp_bidtimer or sepgp.VARS.bidtimer end,
      set = function(v) sepgp_bidtimer = v end,
      min = 3,
      max = 30,
      step = 1,
      hidden = function() return not admin() end,
    }
    options.args["reset"] = {
     type = "execute",
     name = L["Reset EPGP"],
     desc = string.format(L["Resets everyone\'s EPGP to 0/%d (Admin only)."],sepgp.VARS.basegp),
     order = 120,
     hidden = function() return not (IsGuildLeader()) end,
     func = function() StaticPopup_Show("SHOOTY_EPGP_CONFIRM_RESET") end
    }
  end
  if (needInit) or (needRefresh) then
    local members = sepgp:buildRosterTable()
    self:debugPrint(string.format(L["Scanning %d members for EP/GP data. (%s)"],table.getn(members),(sepgp_raidonly and "Raid" or "Full")))
    options.args["ep"].args = sepgp:buildClassMemberTable(members,"ep")
    options.args["gp"].args = sepgp:buildClassMemberTable(members,"gp")
    if (needInit) then needInit = false end
    if (needRefresh) then needRefresh = false end
  end
  return options
end

function sepgp:OnInitialize() -- ADDON_LOADED (1) unless LoD
  if sepgp_saychannel == nil then sepgp_saychannel = "GUILD" end
  if sepgp_decay == nil then sepgp_decay = sepgp.VARS.decay end
  if sepgp_minep == nil then sepgp_minep = sepgp.VARS.minep end
  if sepgp_bidtimer == nil then sepgp_bidtimer = sepgp.VARS.bidtimer end
  if sepgp_progress == nil then sepgp_progress = "T3" end
  if sepgp_discount == nil then sepgp_discount = 0.25 end
  if sepgp_altspool == nil then sepgp_altspool = false end
  if sepgp_altpercent == nil then sepgp_altpercent = 1.0 end
  if sepgp_log == nil then sepgp_log = {} end
  if sepgp_looted == nil then sepgp_looted = {} end
  if sepgp_debug == nil then sepgp_debug = {} end
  self:RegisterDB("sepgp_fubar")
  self:RegisterDefaults("char",{})
  --table.insert(sepgp_debug,{[date("%b/%d %H:%M:%S")]="OnInitialize"})
end

function sepgp:OnEnable() -- PLAYER_LOGIN (2)
  --table.insert(sepgp_debug,{[date("%b/%d %H:%M:%S")]="OnEnable"})
  sepgp._playerLevel = UnitLevel("player")
  sepgp.extratip = (sepgp.extratip) or CreateFrame("GameTooltip","shootyepgp_tooltip",UIParent,"GameTooltipTemplate")
  sepgp_pfui.Register(sepgp.extratip, function() sepgp_pfui.SkinTooltip(sepgp.extratip) end)
  -- sepgp.name is the real addon folder name (AceAddon-2.0 sets it from
  -- the folder that was loaded), so this still resolves if the folder
  -- ever ends up with a different name than "BoW-EPGP".
  sepgp._versionString = GetAddOnMetadata(sepgp.name or "BoW-EPGP","Version") or GetAddOnMetadata("BoW-EPGP","Version") or "?"
  sepgp._websiteString = GetAddOnMetadata(sepgp.name or "BoW-EPGP","X-Website") or GetAddOnMetadata("BoW-EPGP","X-Website")

  -- Phase 1: Register standalone slash commands for DE roster (bypass AceConsole formatting)
  SLASH_SEPGP_DEADD1 = "/deadd"
  SlashCmdList["SEPGP_DEADD"] = function(msg)
    sepgp:deRosterAdd(msg)
  end
  SLASH_SEPGP_DEREMOVE1 = "/deremove"
  SlashCmdList["SEPGP_DEREMOVE"] = function(msg)
    sepgp:deRosterRemove(msg)
  end
  SLASH_SEPGP_DELIST1 = "/delist"
  SlashCmdList["SEPGP_DELIST"] = function(msg)
    sepgp:deRosterList()
  end
  
  if (IsInGuild()) then
    if (GetNumGuildMembers()==0) then
      GuildRoster()
    end
  end

  self:RegisterEvent("GUILD_ROSTER_UPDATE",function() 
      if (arg1) then -- member join /leave
        sepgp:SetRefresh(true)
      end
    end)
  self:RegisterEvent("RAID_ROSTER_UPDATE",function()
      sepgp:SetRefresh(true)
      sepgp:testLootPrompt()
    end)
  self:RegisterEvent("PARTY_MEMBERS_CHANGED",function()
      sepgp:SetRefresh(true)
      sepgp:testLootPrompt()
    end)
  self:RegisterEvent("PLAYER_ENTERING_WORLD",function()
      sepgp:SetRefresh(true)
      sepgp:testLootPrompt()
    end)
  if sepgp._playerLevel and sepgp._playerLevel < MAX_PLAYER_LEVEL then
    self:RegisterEvent("PLAYER_LEVEL_UP", function()
        if (arg1) then
          sepgp._playerLevel = tonumber(arg1)
          if sepgp._playerLevel == MAX_PLAYER_LEVEL then
            sepgp:UnregisterEvent("PLAYER_LEVEL_UP")
          end
          if sepgp._playerLevel and sepgp._playerLevel >= sepgp.VARS.minlevel then
            sepgp:testMain()
          end
        end
      end)
  end
  self:RegisterEvent("CHAT_MSG_RAID","captureLootCall")
  self:RegisterEvent("CHAT_MSG_RAID_LEADER","captureLootCall")
  self:RegisterEvent("CHAT_MSG_RAID_WARNING","captureLootCall")
  self:RegisterEvent("CHAT_MSG_WHISPER","captureBid")
  self:RegisterEvent("CHAT_MSG_LOOT","captureLoot")
  self:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED","tradeLoot")
  self:RegisterEvent("TRADE_ACCEPT_UPDATE","tradeLoot")
  -- Phase 5: Trade completion tracking
  self:RegisterEvent("TRADE_SHOW", function()
    if UnitExists("target") then
      local tradeName = UnitName("target") or UnitName("NPC") or "?"
      sepgp:writeDebugLog("TRADE_OPEN | target=" .. tradeName)
    end
  end)
  self:RegisterEvent("TRADE_CLOSED", function()
    sepgp:writeDebugLog("TRADE_CLOSED")
  end)
  -- Feature 3: Show epic+ loot when corpse is opened
  self:RegisterEvent("LOOT_OPENED","onLootOpened")

  if AceLibrary("AceEvent-2.0"):IsFullyInitialized() then
    self:AceEvent_FullyInitialized()
  else
    self:RegisterEvent("AceEvent_FullyInitialized")
  end
end

function sepgp:OnDisable()
  --table.insert(sepgp_debug,{[date("%b/%d %H:%M:%S")]="OnDisable"})
  self:UnregisterAllEvents()
end

function sepgp:AceEvent_FullyInitialized() -- SYNTHETIC EVENT, later than PLAYER_LOGIN, PLAYER_ENTERING_WORLD (3)
  --table.insert(sepgp_debug,{[date("%b/%d %H:%M:%S")]="AceEvent_FullyInitialized"})
  if self._hasInitFull then return end
  
  for i=1,NUM_CHAT_WINDOWS do
    local tab = getglobal("ChatFrame"..i.."Tab")
    local cf = getglobal("ChatFrame"..i)
    local tabName = tab:GetText()
    if tab ~= nil and (string.lower(tabName) == "debug") then
      shooty_debugchat = cf
      ChatFrame_RemoveAllMessageGroups(shooty_debugchat)
      shooty_debugchat:SetMaxLines(1024)
      break
    end
  end

  self:testMain()

  local delay = 2
  if self:IsEventRegistered("AceEvent_FullyInitialized") then
    self:UnregisterEvent("AceEvent_FullyInitialized")
    delay = 3
  end  
  if not self:IsEventScheduled("shootyepgpChannelInit") then
    self:ScheduleEvent("shootyepgpChannelInit",self.delayedInit,delay,self)
  end

  -- if pfUI loaded, skin the extra tooltip
  if not IsAddOnLoaded("pfUI-addonskins") then
    if (pfUI) and pfUI.api and pfUI.api.CreateBackdrop and pfUI_config and pfUI_config.tooltip and pfUI_config.tooltip.alpha then
      pfUI.api.CreateBackdrop(sepgp.extratip,nil,nil,tonumber(pfUI_config.tooltip.alpha))
    end
  end
  -- hook GiveMasterLoot to catch loot assign to members too far for chat parsing
  self:SecureHook("GiveMasterLoot")
  -- hook SetItemRef to parse our client bid links
  self:Hook("SetItemRef")
  -- hook tooltip to add our GP values
  self:TipHook()
  -- hook LootFrameItem_OnClick to add our own click handlers for bid calls
  self:SecureHook("LootFrameItem_OnClick")
  -- hook ContainerFrameItemButton_OnClick to add our own click handlers for bid calls
  self:Hook("ContainerFrameItemButton_OnClick")
  -- hook pfUI loot module :(
  if pfUI ~= nil and pfUI.loot ~= nil and type(pfUI.loot.UpdateLootFrame) == "function" then
    self:SecureHook(pfUI.loot, "UpdateLootFrame", "pfUI_UpdateLootFrame")
  end
  self._hasInitFull = true
end

sepgp._lastRosterRequest = false
function sepgp:OnMenuRequest()
  local now = GetTime()
  if not self._lastRosterRequest or (now - self._lastRosterRequest > 2) then
    self._lastRosterRequest = now
    self:SetRefresh(true)
    GuildRoster()
  end
  self._options = self:buildMenu()
  D:FeedAceOptionsTable(self._options)
end

function sepgp:TipHook()
  self:SecureHook(GameTooltip, "SetHyperlink", function(this, itemstring)
    sepgp:AddDataToTooltip(GameTooltip, nil, itemstring)
  end)
  self:SecureHook(GameTooltip, "SetBagItem", function(this, bag, slot)
    local itemLink = GetContainerItemLink(bag, slot)
    local ml_tip
    if (itemLink) then
      local is_master = (sepgp:lootMaster()) and true or nil
      local link_found, _, itemColor, itemString, itemName = string.find(itemLink, "^(|c%x+)|H(.+)|h(%[.+%])")
      if (link_found) then
        local bind = self:itemBinding(itemString) or ""
        ml_tip = is_master and bind == sepgp.VARS.boe
        if (ml_tip) then
          local frame = GetMouseFocus()
          if (frame) and (frame.IsFrameType ~= nil) and (frame:IsFrameType("Button"))  then
            if not (frame._hasExtraClicks) then
              frame:RegisterForClicks("LeftButtonUp","RightButtonUp","MiddleButtonUp")
              frame._hasExtraClicks = true              
            end
          end
        end
      end
    end
    sepgp:AddDataToTooltip(GameTooltip, itemLink, nil, ml_tip)
  end
  )
  self:SecureHook(GameTooltip, "SetLootItem", function(this, slot)
    local is_master = (sepgp:lootMaster()) and true or nil
    if (is_master) then
      local frame = GetMouseFocus()
      if (frame) and (frame.IsFrameType ~= nil) and (frame:IsFrameType("Button"))  then
        if not (frame._hasExtraClicks) then
          frame:RegisterForClicks("LeftButtonUp","RightButtonUp","MiddleButtonUp")
          frame._hasExtraClicks = true              
        end
      end
    end
    sepgp:AddDataToTooltip(GameTooltip, GetLootSlotLink(slot), nil, is_master)
  end
  )
  self:SecureHook(GameTooltip, "SetLootRollItem", function(this, id)
    sepgp:AddDataToTooltip(GameTooltip, GetLootRollItemLink(id))
  end
  ) 
  self:HookScript(GameTooltip, "OnHide", function()
    if sepgp.extratip:IsVisible() then sepgp.extratip:Hide() end
    self.hooks[GameTooltip]["OnHide"]()
  end
  )
  self:HookScript(ItemRefTooltip, "OnHide", function()
    if sepgp.extratip:IsVisible() then sepgp.extratip:Hide() end
    self.hooks[ItemRefTooltip]["OnHide"]()
  end
  )
  if (AtlasLootTooltip) then
    self:SecureHook(AtlasLootTooltip, "SetHyperlink", function(this, itemstring)
      sepgp:AddDataToTooltip(AtlasLootTooltip,nil,itemstring)
    end)
    self:HookScript(AtlasLootTooltip, "OnHide", function()
      if sepgp.extratip:IsVisible() then sepgp.extratip:Hide() end
      self.hooks[AtlasLootTooltip]["OnHide"]()
    end)
  end
end

function sepgp:delayedInit()
  --table.insert(sepgp_debug,{[date("%b/%d %H:%M:%S")]="delayedInit"})
  if (IsInGuild()) then
    local guildName = (GetGuildInfo("player"))
    if (guildName) and guildName ~= "" then
      sepgp_reservechannel = string.format("%sReserves",(string.gsub(guildName," ",""))) -- TODO: Check if channel names can have chinese characters
    end
  end
  if sepgp_reservechannel == nil then sepgp_reservechannel = sepgp.VARS.reservechan end  
  local reservesChannelID = tonumber((GetChannelName(sepgp_reservechannel)))
  if (reservesChannelID) and (reservesChannelID ~= 0) then
    self:reservesToggle(true)
  end
  -- migrate EPGP storage if needed
  self:parseVersion(sepgp._versionString)
  local major_ver = self._version.major
  -- 2026-04-02: Added nil check for migration function to prevent Lua error
  -- when a migration path doesn't exist (e.g. v3tov5 skipping v4). Previously
  -- crashed with "attempt to call field '?' (a nil value)" on guild leaders.
  if IsGuildLeader() and ( (sepgp_dbver == nil) or (major_ver > sepgp_dbver) ) then
    local migrationName = string.format("v%dtov%d",(sepgp_dbver or 2),major_ver)
    if sepgp[migrationName] then
      sepgp[migrationName](sepgp)
    else
      self:defaultPrint(string.format("BoW-EPGP: No migration needed (%s), updating dbver.", migrationName))
      sepgp_dbver = major_ver
    end
  end
  -- init options and comms
  self._options = self:buildMenu()
  self:RegisterChatCommand({"/bowepgp"},self.cmdtable())
  self:RegisterEvent("CHAT_MSG_ADDON","addonComms")  
  -- broadcast our version
  local addonMsg = string.format("VERSION;%s;%d",sepgp._versionString,major_ver)
  self:addonMessage(addonMsg,"GUILD")
  if (IsGuildLeader()) then
    self:shareSettings()
  end
  -- safe officer note setting when we are admin
  if (admin()) then
    if not self:IsHooked("GuildRosterSetOfficerNote") then
      self:Hook("GuildRosterSetOfficerNote")
    end
  end
  self:defaultPrint(string.format(L["v%s Loaded."],sepgp._versionString))
end

function sepgp:AddDataToTooltip(tooltip,itemlink,itemstring,is_master)
  local price
  if (itemstring) then
    price = sepgp_prices:GetPrice(itemstring,sepgp_progress)
  elseif (itemlink) then
    price = sepgp_prices:GetPrice(itemlink,sepgp_progress)
  end
  if not price then return end
  local line_limit, left1,right1
  if (is_master) then 
    line_limit = 27 
    left1,right1 = C:Yellow(L["Alt Click/RClick/MClick"]), C:Orange(L["Call for: MS/OS/Both"])
  else 
    line_limit = 28 
  end
  local ep,gp = (self:get_ep_v3(self._playerName) or 0), (self:get_gp_v3(self._playerName) or sepgp.VARS.basegp)
  local off_price = math.floor(price*sepgp_discount)
  local pr,new_pr,new_pr_off = ep/gp, ep/(gp+price), ep/(gp+off_price)
  local pr_delta = new_pr - pr
  local pr_delta_off = new_pr_off - pr
  local textRight = string.format(L["gp:|cff32cd32%d|r gp_os:|cff20b2aa%d|r"],price,off_price)
  local textRight2 = string.format(L["pr:|cffff0000%.02f|r(%.02f) pr_os:|cffff0000%.02f|r(%.02f)"],pr_delta,new_pr,pr_delta_off,new_pr_off)
  if (tooltip:NumLines() < line_limit) then
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine("|cff9664c8BoW-EPGP|r",textRight)
    tooltip:AddDoubleLine(" ",textRight2)
    if (is_master) then
      tooltip:AddDoubleLine(left1,right1)
    end
    tooltip:Show()
  else
    sepgp.extratip:ClearLines()
    sepgp.extratip:SetOwner(tooltip,"ANCHOR_NONE")
    sepgp.extratip:ClearAllPoints()
    if (EnhTooltip) and EnhancedTooltip:IsVisible() then
      sepgp.extratip:SetPoint("BOTTOMLEFT", tooltip, "TOPLEFT", 0, 5)
      sepgp.extratip:SetPoint("BOTTOMRIGHT", tooltip, "TOPRIGHT", 0, 5)          
    else
      sepgp.extratip:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT", 0, -5)
      sepgp.extratip:SetPoint("TOPRIGHT", tooltip, "BOTTOMRIGHT", 0, -5)
    end
    sepgp.extratip:SetText("|cff9664c8BoW-EPGP|r")
    sepgp.extratip:AddDoubleLine(" ",textRight)
    sepgp.extratip:AddDoubleLine(" ",textRight2)
    if (is_master) then
      sepgp.extratip:AddDoubleLine(left1,right1)
    end
    sepgp.extratip:Show()
  end
end

function sepgp:OnUpdate(elapsed)
  sepgp.timer.count_down = sepgp.timer.count_down - elapsed
  lastUpdate = lastUpdate + elapsed
  if sepgp.timer.count_down <= 0 then
    running_check = nil
    sepgp.timer:Hide()
    sepgp.timer.cd_text = L["|cffff0000Finished|r"]
    sepgp_reserves:Refresh()
  else
    sepgp.timer.cd_text = string.format(L["|cff00ff00%02d|r|cffffffffsec|r"],sepgp.timer.count_down)
  end
  if lastUpdate > 0.5 then
    lastUpdate = 0
    sepgp_reserves:Refresh()
  end
end

function sepgp:GuildRosterSetOfficerNote(index,note,fromAddon)
  if (fromAddon) then
    self.hooks["GuildRosterSetOfficerNote"](index,note)
  else
    local name, _, _, _, _, _, _, prevnote, _, _ = GetGuildRosterInfo(index)
    local _,_,_,oldepgp,_ = string.find(prevnote or "","(.*)({%d+:%d+})(.*)")
    local _,_,_,epgp,_ = string.find(note or "","(.*)({%d+:%d+})(.*)")
    if (sepgp_altspool) then
      local oldmain = self:parseAlt(name,prevnote)
      local main = self:parseAlt(name,note)
      if oldmain ~= nil then
        if main == nil or main ~= oldmain then 
          self:adminSay(string.format(L["Manually modified %s\'s note. Previous main was %s"],name,oldmain))
          self:defaultPrint(string.format(L["|cffff0000Manually modified %s\'s note. Previous main was %s|r"],name,oldmain))
        end
      end
    end    
    if oldepgp ~= nil then
      if epgp == nil or epgp ~= oldepgp then
        self:adminSay(string.format(L["Manually modified %s\'s note. EPGP was %s"],name,oldepgp))
        self:defaultPrint(string.format(L["|cffff0000Manually modified %s\'s note. EPGP was %s|r"],name,oldepgp))
      end
    end
    local safenote = string.gsub(note,"(.*)({%d+:%d+})(.*)",sanitizeNote)
    return self.hooks["GuildRosterSetOfficerNote"](index,safenote)    
  end
end

function sepgp:SetItemRef(link, name, button)
  if string.sub(link,1,9) == "shootybid" then
    local _,_,bid,masterlooter = string.find(link,"shootybid:(%d+):(%w+)")
    if bid == "1" then
      bid = "MS"
    elseif bid == "2" then
      bid = "OS"
    elseif bid == "3" then
      bid = "FLEX"
    elseif bid == "4" then
      bid = "TM"
    elseif bid == "5" then
      bid = "PASS"
    else
      bid = nil
    end
    if not self:inRaid(masterlooter) then
      masterlooter = nil
    end
    if (bid and masterlooter) then
      SendChatMessage(bid,"WHISPER",nil,masterlooter)
    end
    return
  end
  self.hooks["SetItemRef"](link, name, button)
  if (link and name and ItemRefTooltip) then
    if (strsub(link, 1, 4) == "item") then
      if (ItemRefTooltip:IsVisible()) then
        if (not DressUpFrame:IsVisible()) then
          self:AddDataToTooltip(ItemRefTooltip, link)
        end
        ItemRefTooltip.isDisplayDone = nil
      end
    end
  end
end

function sepgp:LootFrameItem_OnClick(button,data)
  if not IsAltKeyDown() then return end
  if not UnitInRaid("player") then return end
  if not (self:lootMaster()) then 
    self:defaultPrint(L["Need MasterLooter to perform Bid Calls!"])
    UIErrorsFrame:AddMessage(L["Need MasterLooter to perform Bid Calls!"],1,0,0)
    return 
  end
  local slot, quality
  if data ~= nil then
    slot,quality = data:GetID(), data.quality
  else
    slot = LootFrame.selectedSlot or 0
    quality = LootFrame.selectedQuality or -1
    if not (this._hasExtraClicks) then 
      this:RegisterForClicks("LeftButtonUp","RightButtonUp","MiddleButtonUp")
      this._hasExtraClicks = true
    end
  end
  if LootSlotIsItem(slot) and quality >= 3 then 
    local itemLink = GetLootSlotLink(slot)
    if (itemLink) then
      if button == "LeftButton" then
        self:widestAudience(string.format("Whisper %s MS, FLEX, OS, or TM for %s", sepgp._playerName, itemLink))
      elseif button == "RightButton" then
        self:widestAudience(string.format("Whisper %s OS for %s (offspec)", sepgp._playerName, itemLink))
      elseif button == "MiddleButton" then
        self:widestAudience(string.format("Whisper %s MS, FLEX, OS, or TM for %s", sepgp._playerName, itemLink))
      end
    end
  end
end

function sepgp:ContainerFrameItemButton_OnClick(button,ignoreModifiers)
  if not IsAltKeyDown() then
    return self.hooks["ContainerFrameItemButton_OnClick"](button,ignoreModifiers)
  end
  if not UnitInRaid("player") then
    return self.hooks["ContainerFrameItemButton_OnClick"](button,ignoreModifiers)
  end
  if not (self:lootMaster()) then
    self:defaultPrint(L["Need MasterLooter to perform Bid Calls!"])
    UIErrorsFrame:AddMessage(L["Need MasterLooter to perform Bid Calls!"],1,0,0)
    return self.hooks["ContainerFrameItemButton_OnClick"](button,ignoreModifiers)
  end
  if not (this._hasExtraClicks) then
    this:RegisterForClicks("LeftButtonUp","RightButtonUp","MiddleButtonUp")
    this._hasExtraClicks = true
  end
  local bag,slot = this:GetParent():GetID(), this:GetID()
  local itemLink = GetContainerItemLink(bag, slot)
  if (itemLink) then
    local link_found, _, itemColor, itemString, itemName = string.find(itemLink, "^(|c%x+)|H(.+)|h(%[.+%])")
    if (link_found) then
      local bind = self:itemBinding(itemString) or ""
      if (bind == self.VARS.boe) then
        if button == "LeftButton" then
          self:widestAudience(string.format("Whisper %s MS, FLEX, OS, or TM for %s", sepgp._playerName, itemLink))
          return
        elseif button == "RightButton" then
          self:widestAudience(string.format("Whisper %s OS for %s (offspec)", sepgp._playerName, itemLink))
          return
        elseif button == "MiddleButton" then
          self:widestAudience(string.format("Whisper %s MS, FLEX, OS, or TM for %s", sepgp._playerName, itemLink))
          return
        end
      end
    end
  end
  return self.hooks["ContainerFrameItemButton_OnClick"](button,ignoreModifiers)
end

function sepgp:pfUI_UpdateLootFrame()
  for slotid, pflootitem in pairs(pfUI.loot.slots) do
    if not self:IsHooked(pflootitem,"OnClick") then
      pflootitem:RegisterForClicks("LeftButtonUp","RightButtonUp","MiddleButtonUp")
      self:HookScript(pflootitem,"OnClick",function()
          self:LootFrameItem_OnClick(arg1,this)
          self.hooks[this]["OnClick"](this,arg1)
        end)
    end
  end
end

-------------------
-- Communication
-------------------
function sepgp:flashFrame(frame)
  local tabFlash = getglobal(frame:GetName().."TabFlash")
  if ( not frame.isDocked or (frame == SELECTED_DOCK_FRAME) or UIFrameIsFlashing(tabFlash) ) then
    return
  end
  tabFlash:Show()
  UIFrameFlash(tabFlash, 0.25, 0.25, 60, nil, 0.5, 0.5)
end

function sepgp:debugPrint(msg)
  if (shooty_debugchat) then
    shooty_debugchat:AddMessage(string.format(out,msg))
    self:flashFrame(shooty_debugchat)
  else
    self:defaultPrint(msg)
  end
end

function sepgp:defaultPrint(msg)
  if not DEFAULT_CHAT_FRAME:IsVisible() then
    FCF_SelectDockFrame(DEFAULT_CHAT_FRAME)
  end
  DEFAULT_CHAT_FRAME:AddMessage(string.format(out,msg))
end

function sepgp:bidPrint(link,masterlooter,need,greed,bid)
  local mslink = string.gsub(bidlink["ms"],"$ML",masterlooter)
  local flexlink = string.gsub(bidlink["flex"],"$ML",masterlooter)
  local oslink = string.gsub(bidlink["os"],"$ML",masterlooter)
  local tmlink = string.gsub(bidlink["tm"],"$ML",masterlooter)
  local passlink = string.gsub(bidlink["pass"],"$ML",masterlooter)
  local msg = string.format("Click to bid on %s: %s %s %s %s %s", link, mslink, flexlink, oslink, tmlink, passlink)
  local chatframe
  if (SELECTED_CHAT_FRAME) then
    chatframe = SELECTED_CHAT_FRAME
  else
    if not DEFAULT_CHAT_FRAME:IsVisible() then
      FCF_SelectDockFrame(DEFAULT_CHAT_FRAME)
    end
    chatframe = DEFAULT_CHAT_FRAME
  end
  if (chatframe) then
    chatframe:AddMessage(" ")
    chatframe:AddMessage(string.format(out,msg),NORMAL_FONT_COLOR.r,NORMAL_FONT_COLOR.g,NORMAL_FONT_COLOR.b)
  end
end

function sepgp:simpleSay(msg)
  SendChatMessage(string.format("BoW-EPGP: %s",msg), sepgp_saychannel)
end

function sepgp:adminSay(msg)
  -- Strip color codes to prevent ChatThrottleLib errors from aux-addons
  local cleanMsg = self:stripColors(msg)
  SendChatMessage(string.format("BoW-EPGP: %s", cleanMsg), "OFFICER")
end

function sepgp:widestAudience(msg)
  local channel = "SAY"
  if UnitInRaid("player") then
    if (IsRaidLeader() or IsRaidOfficer()) then
      channel = "RAID_WARNING"
    else
      channel = "RAID"
    end
  elseif UnitExists("party1") then
    channel = "PARTY"
  end
  SendChatMessage(msg, channel)
end

function sepgp:addonMessage(message,channel,sender)
  SendAddonMessage(self.VARS.prefix,message,channel,sender)
end

-- Bid sync (BID;...) is sent by the master looter / raid leader on the RAID
-- addon channel. Raiders from OTHER guilds (external mains) can't find that
-- sender in THEIR guild roster, so the plain guild check used to drop every
-- bid message and their bid window never opened. Accept the sender if they
-- are a guild member (old behaviour) OR hold authority in our raid: raid
-- leader, assistant, or the current master looter.
function sepgp:isBidSyncSender(sender)
  if not sender or sender == "" then return false end
  if self:verifyGuildMember(sender,true) then return true end
  for i=1,GetNumRaidMembers() do
    local name, rank = GetRaidRosterInfo(i)
    if name == sender then
      if rank and rank >= 1 then return true end -- 2 = leader, 1 = assistant
      break
    end
  end
  local method, partyID, raidID = GetLootMethod()
  if method == "master" and raidID and raidID > 0 then
    if UnitName("raid"..raidID) == sender then return true end
  end
  return false
end

function sepgp:addonComms(prefix,message,channel,sender)
  if prefix ~= self.VARS.prefix then return end -- we don't care for messages from other addons
  if sender == self._playerName then return end -- we don't care for messages from ourselves

  -- Feature 1: Handle bid sync messages from master looter (guild OR raid authority,
  -- so external-guild raiders get the bid window too)
  local bid_prefix = string.sub(message, 1, 4)
  if bid_prefix == "BID;" then
    if self:isBidSyncSender(sender) then
      self:handleBidSync(message, sender)
    end
    return
  end

  local name_g,class,rank = self:verifyGuildMember(sender,true)
  if not (name_g) then return end -- all other addon messages: guild members only

  local who,what,amount
  for name,epgp,change in string.gfind(message,"([^;]+);([^;]+);([^;]+)") do
    who=name
    what=epgp
    amount=tonumber(change)
  end
  if (who) and (what) and (amount) then
    local msg
    local for_main = (sepgp_main and (who == sepgp_main))
    if (who == self._playerName) or (for_main) then
      if what == "EP" then
        if amount < 0 then
          msg = string.format(L["You have received a %d EP penalty."],amount)
        else
          msg = string.format(L["You have been awarded %d EP."],amount)
        end
      elseif what == "GP" then
        msg = string.format(L["You have gained %d GP."],amount)
      end
    elseif who == "ALL" and what == "DECAY" then
      msg = string.format(L["%s%% decay to EP and GP."],amount)
    elseif who == "RAID" and what == "AWARD" then
      msg = string.format(L["%d EP awarded to Raid."],amount)
    elseif who == "RESERVES" and what == "AWARD" then
      msg = string.format(L["%d EP awarded to Reserves."],amount)
    elseif who == "VERSION" then
      local out_of_date, version_type = self:parseVersion(self._versionString,what)
      if (out_of_date) and self._newVersionNotification == nil then
        self._newVersionNotification = true -- only inform once per session
        self:defaultPrint(string.format(L["New %s version available: |cff00ff00%s|r"],version_type,what))
        self:defaultPrint(string.format(L["Visit %s to update."],self._websiteString))
      end
      if (IsGuildLeader()) then
        self:shareSettings()
      end
    elseif who == "SETTINGS" then
      for progress,discount,decay,minep,alts,altspct in string.gfind(what, "([^:]+):([^:]+):([^:]+):([^:]+):([^:]+):([^:]+)") do
        discount = tonumber(discount)
        decay = tonumber(decay)
        minep = tonumber(minep)
        alts = (alts == "true") and true or false
        altspct = tonumber(altspct)
        local settings_notice
        if progress and progress ~= sepgp_progress then
          sepgp_progress = progress
          settings_notice = L["New raid progress"]
        end
        if discount and discount ~= sepgp_discount then
          sepgp_discount = discount
          if (settings_notice) then
            settings_notice = settings_notice..L[", offspec price %"]
          else
            settings_notice = L["New offspec price %"]
          end
        end
        if minep and minep ~= sepgp_minep then
          sepgp_minep = minep
          settings_notice = L["New Minimum EP"]
          sepgp:refreshPRTablets()
        end
        if decay and decay ~= sepgp_decay then
          sepgp_decay = decay
          if (admin()) then
            if (settings_notice) then
              settings_notice = settings_notice..L[", decay %"]
            else
              settings_notice = L["New decay %"]
            end
          end
        end
        if alts ~= nil and alts ~= sepgp_altspool then
          sepgp_altspool = alts
          if (admin()) then
            if (settings_notice) then
              settings_notice = settings_notice..L[", alts"]
            else
              settings_notice = L["New Alts"]
            end
          end          
        end
        if altspct and altspct ~= sepgp_altpercent then
          sepgp_altpercent = altspct
          if (admin()) then
            if (settings_notice) then
              settings_notice = settings_notice..L[", alts ep %"]
            else
              settings_notice = L["New Alts EP %"]
            end
          end          
        end
        if (settings_notice) and settings_notice ~= "" then
          local sender_rank = string.format("%s(%s)",C:Colorize(BC:GetHexColor(class),sender),rank)
          settings_notice = settings_notice..string.format(L[" settings accepted from %s"],sender_rank)
          self:defaultPrint(settings_notice)
          self._options.args["progress_tier_header"].name = string.format(L["Progress Setting: %s"],sepgp_progress)
          self._options.args["set_discount_header"].name = string.format(L["Offspec Price: %s%%"],sepgp_discount*100)
          self._options.args["set_min_ep_header"].name = string.format(L["Minimum EP: %s"],sepgp_minep)
        end
      end
    end
    if msg and msg~="" then
      self:defaultPrint(msg)
      self:my_epgp(for_main)
    end
  end
end

function sepgp:shareSettings(force)
  local now = GetTime()
  if self._lastSettingsShare == nil or (now - self._lastSettingsShare > 30) or (force) then
    self._lastSettingsShare = now
    local addonMsg = string.format("SETTINGS;%s:%s:%s:%s:%s:%s;1",sepgp_progress,sepgp_discount,sepgp_decay,sepgp_minep,tostring(sepgp_altspool),sepgp_altpercent)
    self:addonMessage(addonMsg,"GUILD")
  end
end

function sepgp:refreshPRTablets()
  --if not T:IsAttached("sepgp_standings") then
  sepgp_standings:Refresh()
  --end
end

---------------------
-- EPGP Operations
---------------------
function sepgp:init_notes_v2(guild_index,note,officernote)
  if not tonumber(note) or (tonumber(note) < 0) then
    GuildRosterSetPublicNote(guild_index,0)
  end
  if not tonumber(officernote) or (tonumber(officernote) < sepgp.VARS.basegp) then
    GuildRosterSetOfficerNote(guild_index,sepgp.VARS.basegp,true)
  end
end

function sepgp:init_notes_v3(guild_index,name,officernote)
  local ep,gp = self:get_ep_v3(name,officernote), self:get_gp_v3(name,officernote)
  if not (ep and gp) then
    local initstring = string.format("{%d:%d}",0,sepgp.VARS.basegp)
    local newnote = string.format("%s%s",officernote,initstring)
    newnote = string.gsub(newnote,"(.*)({%d+:%d+})(.*)",sanitizeNote)
    officernote = newnote
  else
    officernote = string.gsub(officernote,"(.*)({%d+:%d+})(.*)",sanitizeNote)
  end
  GuildRosterSetOfficerNote(guild_index,officernote,true)
  return officernote
end

function sepgp:update_epgp_v3(ep,gp,guild_index,name,officernote,special_action)
  officernote = self:init_notes_v3(guild_index,name,officernote)
  local newnote
  if (ep) then
    ep = math.max(0,ep)
    newnote = string.gsub(officernote,"(.*{)(%d+)(:)(%d+)(}.*)",function(head,oldep,divider,oldgp,tail)
      return string.format("%s%s%s%s%s",head,ep,divider,oldgp,tail)
      end)
  end
  if (gp) then
    gp =  math.max(sepgp.VARS.basegp,gp)
    if (newnote) then
      newnote = string.gsub(newnote,"(.*{)(%d+)(:)(%d+)(}.*)",function(head,oldep,divider,oldgp,tail)
        return string.format("%s%s%s%s%s",head,oldep,divider,gp,tail)
        end)
    else
      newnote = string.gsub(officernote,"(.*{)(%d+)(:)(%d+)(}.*)",function(head,oldep,divider,oldgp,tail)
        return string.format("%s%s%s%s%s",head,oldep,divider,gp,tail)
        end)
    end
  end
  if (newnote) then
    GuildRosterSetOfficerNote(guild_index,newnote,true)
  end
end

function sepgp:update_ep_v2(getname,ep)
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    if (name==getname) then 
      self:init_notes_v2(i,note,officernote)
      GuildRosterSetPublicNote(i,ep)
    end
  end
end

function sepgp:update_ep_v3(getname,ep)
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    if (name==getname) then 
      self:update_epgp_v3(ep,nil,i,name,officernote)
    end
  end  
end

function sepgp:update_gp_v2(getname,gp)
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    if (name==getname) then 
      self:init_notes_v2(i,note,officernote)
      GuildRosterSetOfficerNote(i,gp,true) 
    end
  end
end

function sepgp:update_gp_v3(getname,gp)
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    if (name==getname) then 
      self:update_epgp_v3(nil,gp,i,name,officernote) 
    end
  end  
end

function sepgp:get_ep_v2(getname,note) -- gets ep by name or note
  if (note) then
    if tonumber(note)==nil then return 0 end
  end
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    if tonumber(note)==nil then note=0 end
    if (name==getname) then return tonumber(note) end
  end
  return(0)
end

function sepgp:get_ep_v3(getname,officernote) -- gets ep by name or note
  if (officernote) then
    local _,_,ep = string.find(officernote,".*{(%d+):%d+}.*")
    return tonumber(ep)
  end
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    if officernote then
      local _,_,ep = string.find(officernote,".*{(%d+):%d+}.*")
      if (name==getname) then return tonumber(ep) end
    elseif (name==getname) then
      return nil
    end
  end
  return
end

function sepgp:get_gp_v2(getname,officernote) -- gets gp by name or officernote
  if (officernote) then
    if tonumber(officernote)==nil then return sepgp.VARS.basegp end
  end
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    if tonumber(officernote)==nil then officernote=sepgp.VARS.basegp end
    if (name==getname) then return tonumber(officernote) end
  end
  return(sepgp.VARS.basegp)
end

function sepgp:get_gp_v3(getname,officernote) -- gets gp by name or officernote
  if (officernote) then
    local _,_,gp = string.find(officernote,".*{%d+:(%d+)}.*")
    return tonumber(gp)
  end
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    if officernote then
      local _,_,gp = string.find(officernote,".*{%d+:(%d+)}.*")
      if (name==getname) then return tonumber(gp) end
    elseif (name==getname) then
      return nil
    end
  end
  return
end

function sepgp:award_raid_ep(ep) -- awards ep to raid members in zone
  if GetNumRaidMembers()>0 then
    local awarded = {}
    for i = 1, GetNumRaidMembers(true) do
      local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i)
      if level >= sepgp.VARS.minlevel then
        self:givename_ep(name,ep)
        table.insert(awarded, name)
      end
    end
    self:simpleSay(string.format(L["Giving %d ep to all raidmembers"],ep))
    self:adminSay(string.format("[EPGP-AUDIT] %s awarded %d EP to %d raid members", UnitName("player"), ep, table.getn(awarded)))
    self:addToLog(string.format(L["Giving %d ep to all raidmembers"],ep))
    local addonMsg = string.format("RAID;AWARD;%s",ep)
    self:addonMessage(addonMsg,"RAID")
    self:refreshPRTablets()
  else UIErrorsFrame:AddMessage(L["You aren't in a raid dummy"],1,0,0)end
end

function sepgp:award_reserve_ep(ep) -- awards ep to reserve list
  if table.getn(sepgp.reserves) > 0 then
    local count = 0
    for i, reserve in ipairs(sepgp.reserves) do
      local name, class, rank, alt = unpack(reserve)
      self:givename_ep(name,ep)
      count = count + 1
    end
    self:simpleSay(string.format(L["Giving %d ep to active reserves"],ep))
    self:adminSay(string.format("[EPGP-AUDIT] %s awarded %d EP to %d reserves", UnitName("player"), ep, count))
    self:addToLog(string.format(L["Giving %d ep to active reserves"],ep))
    local addonMsg = string.format("RESERVES;AWARD;%s",ep)
    self:addonMessage(addonMsg,"GUILD")
    sepgp.reserves = {}
    reserves_blacklist = {}
    self:refreshPRTablets()
  end
end

function sepgp:givename_ep(getname,ep) -- awards ep to a single character
  if not (admin()) then return end
  local postfix, alt = ""
  local ext_orig
  local ext_alt = self:resolveExternalMain(getname)
  if (ext_alt) then
    ext_orig = getname
    getname = ext_alt
    postfix = string.format(" (banker alt for %s)",ext_orig)
  end
  if (sepgp_altspool) then
    local main = self:parseAlt(getname)
    if (main) then
      alt = getname
      getname = main
      ep = self:num_round(sepgp_altpercent*ep)
      postfix = string.format(L[", %s\'s Main."],alt)
    end
  end
  local oldep = (self:get_ep_v3(getname) or 0)
  local newep = ep + oldep
  self:update_ep_v3(getname,newep)
  self:debugPrint(string.format(L["Giving %d ep to %s%s."],ep,getname,postfix))
  if ep < 0 then -- inform admins and victim of penalties
    local msg = string.format(L["%s EP Penalty to %s%s."],ep,getname,postfix)
    self:adminSay(msg)
    self:addToLog(msg)
    local addonMsg = string.format("%s;%s;%s",getname,"EP",ep)
    self:addonMessage(addonMsg,"GUILD")
  end
end

-- Phase 1 fix: itemName parameter replaces bid_item global lookup.
-- All callers now pass the item name from their own data table, not from
-- the shared bid_item which gets overwritten when multiple items are looted.
-- Phase 3: Added routeInfo parameter for enhanced officer chat messages.
-- routeInfo is an optional string like "TM: Fieldwalker - Route: Fieldwalker(TM) -> Morow(MS)"
function sepgp:givename_gp(getname, gp, itemName, specType, routeInfo) -- assigns gp to a single character
  if not (admin()) then return end
  local postfix, alt = ""
  local ext_orig
  local ext_alt = self:resolveExternalMain(getname)
  if (ext_alt) then
    ext_orig = getname
    getname = ext_alt
    postfix = string.format(" (banker alt for %s)",ext_orig)
  end
  if (sepgp_altspool) then
    local main = self:parseAlt(getname)
    if (main) then
      alt = getname
      getname = main
      postfix = string.format(L[", %s\'s Main."],alt)
    end
  end
  local oldgp = (self:get_gp_v3(getname) or sepgp.VARS.basegp)
  local newgp = gp + oldgp
  self:update_gp_v3(getname,newgp)
  self:debugPrint(string.format(L["Giving %d gp to %s%s."],gp,getname,postfix))
  local msg = string.format(L["Awarding %d GP to %s%s. (Previous: %d, New: %d)"],gp,getname,postfix,oldgp,math.max(sepgp.VARS.basegp,newgp))
  -- Use passed itemName (from popup data), fall back to bid_item only as last resort
  local itemInfo = ""
  if itemName and itemName ~= "" then
    itemInfo = " for " .. itemName
  elseif sepgp.bid_item and sepgp.bid_item.name and sepgp.bid_item.name ~= "" then
    itemInfo = " for " .. sepgp.bid_item.name
  end
  local specInfo = ""
  if specType and specType ~= "" then
    specInfo = " (" .. specType .. ")"
  end
  -- Phase 3: Enhanced officer chat with route info
  local routeSuffix = ""
  if routeInfo and routeInfo ~= "" then
    routeSuffix = " - " .. routeInfo
  end
  self:adminSay(string.format("[EPGP-AUDIT] %s awarded %d GP to %s%s%s%s (was %d, now %d)%s", UnitName("player"), gp, getname, postfix, itemInfo, specInfo, oldgp, math.max(sepgp.VARS.basegp,newgp), routeSuffix))
  self:addToLog(msg)
  -- Debug log
  sepgp:writeDebugLog(string.format("GP_CHARGE | %s | +%d GP | %s | %s | was=%d now=%d | %s", getname, gp, specType or "?", itemName or "?", oldgp, math.max(sepgp.VARS.basegp, newgp), routeInfo or ""))
  local addonMsg = string.format("%s;%s;%s",getname,"GP",gp)
  self:addonMessage(addonMsg,"GUILD")
end

function sepgp:decay_epgp_v2() -- decays entire roster's ep and gp
  if not (admin()) then return end
  for i = 1, GetNumGuildMembers(1) do
    local name,_,_,_,class,_,ep,gp,_,_ = GetGuildRosterInfo(i)
    ep = tonumber(ep)
    gp = tonumber(gp)
    if ep == nil then 
    else 
      if gp == nil then
        local msg = string.format(L["%s\'s officernote is broken:%q"],name,tostring(gp))
        self:debugPrint(msg)
        self:adminSay(msg)
      else
        ep = math.max(0,self:num_round(ep*sepgp_decay))
    	  GuildRosterSetPublicNote(i,ep)
    	  gp = math.max(sepgp.VARS.basegp,self:num_round(gp*sepgp_decay))
    	  GuildRosterSetOfficerNote(i,gp,true)
      end
    end
  end
  local msg = string.format(L["All EP and GP decayed by %d%%"],(1-sepgp_decay)*100)
  self:simpleSay(msg)
  if not (sepgp_saychannel=="OFFICER") then self:adminSay(msg) end
  self:addToLog(msg)
end

function sepgp:decay_epgp_v3()
  if not (admin()) then return end
  for i = 1, GetNumGuildMembers(1) do
    local name,_,_,_,class,_,note,officernote,_,_ = GetGuildRosterInfo(i)
    local ep,gp = self:get_ep_v3(name,officernote), self:get_gp_v3(name,officernote)
    if (ep and gp) then
      ep = self:num_round(ep*sepgp_decay)
      gp = self:num_round(gp*sepgp_decay)
      self:update_epgp_v3(ep,gp,i,name,officernote)
    end
  end
  local msg = string.format(L["All EP and GP decayed by %s%%"],(1-sepgp_decay)*100)
  self:simpleSay(msg)
  if not (sepgp_saychannel=="OFFICER") then self:adminSay(msg) end
  self:adminSay(string.format("[EPGP-AUDIT] %s applied decay %s%%", UnitName("player"), (1-sepgp_decay)*100))
  local addonMsg = string.format("ALL;DECAY;%s",(1-(sepgp_decay or sepgp.VARS.decay))*100)
  self:addonMessage(addonMsg,"GUILD")
  self:addToLog(msg)
  self:refreshPRTablets()
end

function sepgp:gp_reset_v2()
  if (IsGuildLeader()) then
    for i = 1, GetNumGuildMembers(1) do
      GuildRosterSetOfficerNote(i, sepgp.VARS.basegp,true)
    end
    self:debugPrint(string.format(L["All GP has been reset to %d."],sepgp.VARS.basegp))
    self:adminSay(string.format("[EPGP-AUDIT] %s reset all GP to %d", UnitName("player"), sepgp.VARS.basegp))
    self:addToLog(string.format(L["All GP has been reset to %d."],sepgp.VARS.basegp))
  end
end

function sepgp:gp_reset_v3()
  if (IsGuildLeader()) then
    for i = 1, GetNumGuildMembers(1) do
      local name,_,_,_,class,_,note,officernote,_,_ = GetGuildRosterInfo(i)
      local ep,gp = self:get_ep_v3(name,officernote), self:get_gp_v3(name,officernote)
      if (ep and gp) then
        self:update_epgp_v3(0,sepgp.VARS.basegp,i,name,officernote)
      end
    end
    local msg = L["All EP and GP has been reset to 0/%d."]
    self:debugPrint(string.format(msg,sepgp.VARS.basegp))
    self:adminSay(string.format("[EPGP-AUDIT] %s reset all EP/GP to 0/%d", UnitName("player"), sepgp.VARS.basegp))
    self:addToLog(string.format(msg,sepgp.VARS.basegp))
  end
end

function sepgp:capcalc(ep,gp,gain)
  -- CAP_EP = EP_GAIN*DECAY/(1-DECAY) CAP_PR = CAP_EP/base_gp
  local pr = ep/gp
  local ep_decayed = self:num_round(ep*sepgp_decay)
  local gp_decayed = math.max(sepgp.VARS.basegp,self:num_round(gp*sepgp_decay))
  local pr_decay = tonumber(string.format("%.03f",pr))-tonumber(string.format("%.03f",ep_decayed/gp_decayed))
  if (pr_decay < 0.5) then 
    pr_decay = 0 
  else
    pr_decay = -tonumber(string.format("%.02f",pr_decay))
  end
  local cycle_gain = tonumber(gain)
  local cap_ep, cap_pr
  if (cycle_gain) then
    cap_ep = self:num_round(cycle_gain*sepgp_decay/(1-sepgp_decay))
    cap_pr = tonumber(string.format("%.03f",cap_ep/sepgp.VARS.basegp))
  end
  return pr_decay, cap_ep, cap_pr
end

function sepgp:my_epgp_announce(use_main)
  local ep,gp
  if (use_main) then
    ep,gp = (self:get_ep_v3(sepgp_main) or 0), (self:get_gp_v3(sepgp_main) or sepgp.VARS.basegp)
  else
    ep,gp = (self:get_ep_v3(self._playerName) or 0), (self:get_gp_v3(self._playerName) or sepgp.VARS.basegp)
  end
  local pr = ep/gp
  local msg = string.format(L["You now have: %d EP %d GP |cffffff00%.03f|r|cffff7f00PR|r."], ep,gp,pr)
  self:defaultPrint(msg)
  local pr_decay, cap_ep, cap_pr = self:capcalc(ep,gp)
  if pr_decay < 0 then
    msg = string.format(L["Close to EPGP Cap. Next Decay will change your |cffff7f00PR|r by |cffff0000%.4g|r."],pr_decay)
    self:defaultPrint(msg)
  end
end

function sepgp:my_epgp(use_main)
  GuildRoster()
  self:ScheduleEvent("shootyepgpRosterRefresh",self.my_epgp_announce,3,self,use_main)
end

---------
-- Menu
---------
sepgp.hasIcon = "Interface\\PetitionFrame\\GuildCharter-Icon"
sepgp.title = "BoW-EPGP"
sepgp.defaultMinimapPosition = 180
sepgp.defaultPosition = "RIGHT"
sepgp.cannotDetachTooltip = true
sepgp.tooltipHiddenWhenEmpty = false
sepgp.independentProfile = true

function sepgp:OnTooltipUpdate()
  local hint = L["|cffffff00Click|r to toggle Standings.%s \n|cffffff00Right-Click|r for Options."]
  if (admin()) then
    hint = string.format(hint,L[" \n|cffffff00Ctrl+Click|r to toggle Reserves. \n|cffffff00Shift+Click|r to toggle Loot. \n|cffffff00Ctrl+Alt+Click|r to toggle Alts. \n|cffffff00Ctrl+Shift+Click|r to toggle Logs."])
  else
    hint = string.format(hint,"")
  end
  T:SetHint(hint)
end

function sepgp:OnClick()
  local is_admin = admin()
  if (IsControlKeyDown() and IsShiftKeyDown() and is_admin) then
    sepgp_logs:Toggle()
  elseif (IsControlKeyDown() and IsAltKeyDown() and is_admin) then
    sepgp_alts:Toggle()
  elseif (IsControlKeyDown() and is_admin) then
    sepgp_reserves:Toggle()
  elseif (IsShiftKeyDown() and is_admin) then
    sepgp_loot:Toggle()      
  else
    sepgp_standings:Toggle()
  end
end

function sepgp:SetRefresh(flag)
  needRefresh = flag
  if (flag) then
    self:refreshPRTablets()
  end
end

function sepgp:buildRosterTable()
  local g, r = { }, { }
  local numGuildMembers = GetNumGuildMembers(1)
  self:buildExternalMainsTable()
  if (sepgp_raidonly) and GetNumRaidMembers() > 0 then
    for i = 1, GetNumRaidMembers(true) do
      local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i) 
      if (name) then
        r[name] = true
      end
    end
  end
  sepgp.alts = {}
  for i = 1, numGuildMembers do
    local member_name,_,_,level,class,_,note,officernote,_,_ = GetGuildRosterInfo(i)
    local main, main_class, main_rank = self:parseAlt(member_name,officernote)
    local is_raid_level = tonumber(level) and level >= sepgp.VARS.minlevel
    if (main) then
      if ((self._playerName) and (name == self._playerName)) then
        if (not sepgp_main) or (sepgp_main and sepgp_main ~= main) then
          sepgp_main = main
          self:defaultPrint(L["Your main has been set to %s"],sepgp_main)
        end
      end
      main = C:Colorize(BC:GetHexColor(main_class), main)
      sepgp.alts[main] = sepgp.alts[main] or {}
      sepgp.alts[main][member_name] = class
    end
    if (sepgp_raidonly) and next(r) then
      if r[member_name] and is_raid_level then
        table.insert(g,{["name"]=member_name,["class"]=class})
      end
    else
      if is_raid_level then
        table.insert(g,{["name"]=member_name,["class"]=class})
      end
    end    
  end
  for extname_lower, entry in pairs(sepgp.external_mains or {}) do
    if (sepgp_raidonly) and next(r) then
      if r[entry.ext_name] then
        table.insert(g,{["name"]=entry.ext_name,["class"]=entry.class})
      end
    else
      table.insert(g,{["name"]=entry.ext_name,["class"]=entry.class})
    end
  end
  return g
end

function sepgp:buildClassMemberTable(roster,epgp)
  local desc,usage
  if epgp == "ep" then
    desc = L["Account EPs to %s."]
    usage = "<EP>"
  elseif epgp == "gp" then
    desc = L["Account GPs to %s."]
    usage = "<GP>"
  end
  local c = { }
  for i,member in ipairs(roster) do
    local class,name = member.class, member.name
    if (class) and (c[class] == nil) then
      c[class] = { }
      c[class].type = "group"
      c[class].name = C:Colorize(BC:GetHexColor(class),class)
      c[class].desc = class .. " members"
      c[class].hidden = function() return not (admin()) end
      c[class].args = { }
    end
    if (name) and (c[class].args[name] == nil) then
      c[class].args[name] = { }
      c[class].args[name].type = "text"
      c[class].args[name].name = name
      c[class].args[name].desc = string.format(desc,name)
      c[class].args[name].usage = usage
      if epgp == "ep" then
        c[class].args[name].get = "suggestedAwardEP"
        c[class].args[name].set = function(v) sepgp:givename_ep(name, tonumber(v)) sepgp:refreshPRTablets() end
      elseif epgp == "gp" then
        c[class].args[name].get = false
        c[class].args[name].set = function(v) sepgp:givename_gp(name, tonumber(v)) sepgp:refreshPRTablets() end
      end
      c[class].args[name].validate = function(v) return (type(v) == "number" or tonumber(v)) and tonumber(v) < sepgp.VARS.max end
    end
  end
  return c
end

---------------
-- Alts
---------------
function sepgp:parseAlt(name,officernote)
  if (officernote) then
    local _,_,_,main,_ = string.find(officernote or "","(.*){([%a][%a]%a*)}(.*)")
    if type(main)=="string" and (string.len(main) < 13) then
      main = self:camelCase(main)
      local g_name, g_class, g_rank, g_officernote = self:verifyGuildMember(main)
      if (g_name) then
        return g_name, g_class, g_rank, g_officernote
      else
        return nil
      end
    else
      return nil
    end
  else
    for i=1,GetNumGuildMembers(1) do
      local g_name, _, _, _, g_class, _, g_note, g_officernote, _, _ = GetGuildRosterInfo(i)
      if (name == g_name) then
        return self:parseAlt(g_name, g_officernote)
      end
    end
  end
  return nil
end

---------------
-- External Mains (banker alts holding EPGP for players in other guilds)
---------------
-- Tag format: on a low-level "banker" alt that IS in this guild, add
-- {X:Name} to its officer note, alongside the normal {EP:GP} block, e.g.
--   {120:45}{X:Grimtooth}
-- "Grimtooth" is the real character name of the person's main, which
-- lives in a different guild. All EPGP for "Grimtooth" is then stored
-- and read from this alt's officer note.
function sepgp:parseExternalTag(officernote)
  if not officernote then return nil end
  local _,_,ext = string.find(officernote,"{X:([%a][%a]*)}")
  if ext then
    return self:camelCase(ext)
  end
  return nil
end

function sepgp:buildExternalMainsTable()
  local numGuildMembers = GetNumGuildMembers(1)
  if (numGuildMembers == 0) then
    -- Roster isn't loaded yet. Request it and leave the cache unset so the
    -- next lookup rebuilds, instead of caching an empty table for the
    -- whole session and silently failing every external main lookup.
    GuildRoster()
    sepgp.external_mains = nil
    sepgp.external_mains_reverse = nil
    return
  end
  sepgp.external_mains = {}
  sepgp.external_mains_reverse = {}
  for i = 1, numGuildMembers do
    local name, _, _, _, class, _, _, officernote, _, _ = GetGuildRosterInfo(i)
    local ext = self:parseExternalTag(officernote)
    if ext and name then
      sepgp.external_mains[string.lower(ext)] = {alt = name, class = class, officernote = officernote, ext_name = ext}
      sepgp.external_mains_reverse[name] = ext
    end
  end
end

-- Given a real character name (which may not be in this guild), returns
-- the in-guild "banker alt" name/class/officernote holding their EPGP,
-- or nil if `name` isn't a registered external main.
function sepgp:resolveExternalMain(name)
  if not name then return nil end
  if not sepgp.external_mains then self:buildExternalMainsTable() end
  if not sepgp.external_mains then return nil end
  local entry = sepgp.external_mains[string.lower(name)]
  if entry then
    return entry.alt, entry.class, entry.officernote
  end
  return nil
end

-- Returns the class for a looter name, whether they are a direct guild
-- member or a registered external main (EPGP held on an in-guild banker
-- alt). Second return is true when the name resolved as an external main.
-- Used by the loot capture chain so external mains are not dropped before
-- the award GP window is shown.
function sepgp:resolveLooterClass(name)
  if not name then return nil end
  local _, class = self:verifyGuildMember(name, true)
  if (class) then return class, false end
  local ext_alt, ext_class = self:resolveExternalMain(name)
  if (ext_alt) then return ext_class, true end
  return nil
end

function sepgp:externalMainsList()
  self:buildExternalMainsTable()
  local found = false
  self:defaultPrint("External mains linked to banker alts:")
  for extname, entry in pairs(sepgp.external_mains or {}) do
    found = true
    local ep = self:get_ep_v3(entry.alt, entry.officernote) or 0
    local gp = self:get_gp_v3(entry.alt, entry.officernote) or sepgp.VARS.basegp
    self:defaultPrint(string.format("  %s -> banker alt %s (EP %d, GP %d)", extname, entry.alt, ep, gp))
  end
  if not found then
    self:defaultPrint("  (none registered)")
  end
end

---------------
-- Reserves
---------------
function sepgp:reservesToggle(flag)
  local reservesChannelID = tonumber((GetChannelName(sepgp_reservechannel)))
  if (flag) then -- we want in
    if (reservesChannelID) and reservesChannelID ~= 0 then
      sepgp.reservesChannelID = reservesChannelID
      if not self:IsEventRegistered("CHAT_MSG_CHANNEL") then
        self:RegisterEvent("CHAT_MSG_CHANNEL","captureReserveChatter")
      end
      return true
    else
      self:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE","reservesChannelChange")
      JoinChannelByName(sepgp_reservechannel)
      return
    end
  else -- we want out
    if (reservesChannelID) and reservesChannelID ~= 0 then
      self:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE","reservesChannelChange")
      LeaveChannelByName(sepgp_reservechannel)
      return
    else
      if self:IsEventRegistered("CHAT_MSG_CHANNEL") then
        self:UnregisterEvent("CHAT_MSG_CHANNEL")
      end      
      return false
    end
  end
end

function sepgp:reservesChannelChange(msg,_,_,_,_,_,_,_,channel)
  if (msg) and (channel) and (channel == sepgp_reservechannel) then
    if msg == "YOU_JOINED" then
      sepgp.reservesChannelID = tonumber((GetChannelName(sepgp_reservechannel)))
      RemoveChatWindowChannel(DEFAULT_CHAT_FRAME:GetID(), sepgp_reservechannel)
      self:RegisterEvent("CHAT_MSG_CHANNEL","captureReserveChatter")
    elseif msg == "YOU_LEFT" then
      sepgp.reservesChannelID = nil 
      if self:IsEventRegistered("CHAT_MSG_CHANNEL") then
        self:UnregisterEvent("CHAT_MSG_CHANNEL")
      end
    end
    self:UnregisterEvent("CHAT_MSG_CHANNEL_NOTICE")
    D:Close()
  end
end

function sepgp:afkcheck_reserves()
  if (running_check) then return end
  if sepgp.reservesChannelID ~= nil and ((GetChannelName(sepgp.reservesChannelID)) == sepgp.reservesChannelID) then
    reserves_blacklist = {}
    sepgp.reserves = {}
    running_check = true
    sepgp.timer.count_down = sepgp.VARS.timeout
    sepgp.timer:Show()
    SendChatMessage(sepgp.VARS.reservecall,"CHANNEL",nil,sepgp.reservesChannelID)
    sepgp_reserves:Toggle(true)
  end
end

function sepgp:sendReserverResponce()
  if sepgp.reservesChannelID ~= nil then
    if (sepgp_main) then
      if sepgp_main == self._playerName then
        SendChatMessage("+","CHANNEL",nil,sepgp.reservesChannelID)
      else
        SendChatMessage(string.format("+%s",sepgp_main),"CHANNEL",nil,sepgp.reservesChannelID)
      end
    end
  end
end

function sepgp:captureReserveChatter(text, sender, _, _, _, _, _, _, channel)
  if not (channel) or not (channel == sepgp_reservechannel) then return end
  local reserve, reserve_class, reserve_rank, reserve_alt = nil,nil,nil,nil
  local r,_,rdy,name = string.find(text,sepgp.VARS.reserveanswer)
  if (r) and (running_check) then
    if (rdy) then
      if (name) and (name ~= "") then
        if (not self:inRaid(name)) then
          reserve, reserve_class, reserve_rank = self:verifyGuildMember(name)
          if reserve ~= sender then
            reserve_alt = sender
          end
        end
      else
        if (not self:inRaid(sender)) then
          reserve, reserve_class, reserve_rank = self:verifyGuildMember(sender)    
        end
      end
      if reserve and reserve_class and reserve_rank then
        if reserve_alt then
          if not reserves_blacklist[reserve_alt] then
            reserves_blacklist[reserve_alt] = true
            table.insert(sepgp.reserves,{reserve,reserve_class,reserve_rank,reserve_alt})
          else
            self:defaultPrint(string.format(L["|cffff0000%s|r trying to add %s to Reserves, but has already added a member. Discarding!"],reserve_alt,reserve))
          end
        else
          if not reserves_blacklist[reserve] then
            reserves_blacklist[reserve] = true
            table.insert(sepgp.reserves,{reserve,reserve_class,reserve_rank})
          else
            self:defaultPrint(string.format(L["|cffff0000%s|r has already been added to Reserves. Discarding!"],reserve))
          end
        end
      end
    end
    return
  end
  local q = string.find(text,L["^{BoW%-EPGP}Type"]) or string.find(text,"^{shootyepgp}")
  if (q) and not (running_check) then
    if --[[(not UnitInRaid("player")) or]] (not self:inRaid(sender)) then
      StaticPopup_Show("SHOOTY_EPGP_RESERVE_AFKCHECK_RESPONCE")
    end
  end
end

---------
-- Bids
---------
local lootCall = {}
lootCall.whisp = {
  "^(w)[%s%p%c]+.+",".+[%s%p%c]+(w)$",".+[%s%p%c]+(w)[%s%p%c]+.*",".*[%s%p%c]+(w)[%s%p%c]+.+",
  "^(whisper)[%s%p%c]+.+",".+[%s%p%c]+(whisper)$",".+[%s%p%c]+(whisper)[%s%p%c]+.*",".*[%s%p%c]+(whisper)[%s%p%c]+.+",
  ".+[%s%p%c]+(bid)[%s%p%c]*.*",".*[%s%p%c]*(bid)[%s%p%c]+.+"
}
lootCall.ms = {
  ".+(%+).*",".*(%+).+", 
  "^(ms)[%s%p%c]+.+",".+[%s%p%c]+(ms)$",".+[%s%p%c]+(ms)[%s%p%c]+.*",".*[%s%p%c]+(ms)[%s%p%c]+.+", 
  ".+(mainspec).*",".*(mainspec).+"
}
lootCall.os = {
  ".+(%-).*",".*(%-).+", 
  "^(os)[%s%p%c]+.+",".+[%s%p%c]+(os)$",".+[%s%p%c]+(os)[%s%p%c]+.*",".*[%s%p%c]+(os)[%s%p%c]+.+", 
  ".+(offspec).*",".*(offspec).+"
}
lootCall.bs = { -- blacklist
  "^(roll)[%s%p%c]+.+",".+[%s%p%c]+(roll)$",".*[%s%p%c]+(roll)[%s%p%c]+.*"
}
function sepgp:captureLootCall(text, sender)
  -- Skip our own [EPGP] announcements to prevent cascade: our RAID_WARNING
  -- messages contain |Hitem: links which would re-trigger this handler.
  if string.find(text, "^%[EPGP%]") then return end
  if not (string.find(text, "|Hitem:", 1, true)) then return end
  local linkstriptext, count = string.gsub(text,"|c%x+|H[eimt:%d]+|h%[[%w%s',%-]+%]|h|r"," ; ")
  if count > 1 then return end
  local lowtext = string.lower(linkstriptext)
  local whisperkw_found, mskw_found, oskw_found, link_found, blacklist_found
  for _,f in ipairs(lootCall.bs) do
    blacklist_found = string.find(lowtext,f)
    if (blacklist_found) then return end
  end
  local _, itemLink, itemColor, itemString, itemName
  for _,f in ipairs(lootCall.whisp) do
    whisperkw_found = string.find(lowtext,f)
    if (whisperkw_found) then break end
  end
  for _,f in ipairs(lootCall.ms) do
    mskw_found = string.find(lowtext,f)
    if (mskw_found) then break end
  end
  for _,f in ipairs(lootCall.os) do
    oskw_found = string.find(lowtext,f)
    if (oskw_found) then break end
  end
  if (whisperkw_found) or (mskw_found) or (oskw_found) then
    _,_,itemLink = string.find(text,"(|c%x+|H[eimt:%d]+|h%[[%w%s',%-]+%]|h|r)")
    if (itemLink) and (itemLink ~= "") then
      link_found, _, itemColor, itemString, itemName = string.find(itemLink, "^(|c%x+)|H(.+)|h(%[.+%])")
    end
    if (link_found) then
      local quality = hexColorQuality[itemColor] or -1
      if (quality >= 3) then
        if (IsRaidLeader() or self:lootMaster()) and (sender == self._playerName) then
          self:clearBids(true)
          sepgp.bid_item.link = itemString
          sepgp.bid_item.linkFull = itemLink
          sepgp.bid_item.name = string.format("%s%s|r",itemColor,itemName)
          -- Store prices on bid_item so the bid window can access them later
          local gp_cost = sepgp_prices:GetPrice(itemString, sepgp_progress)
          sepgp.bid_item.price = gp_cost
          sepgp.bid_item.off_price = gp_cost and math.floor(gp_cost * sepgp_discount) or nil
          self:ScheduleEvent("shootyepgpBidTimeout",self.clearBids,300,self)
          running_bid = true
          self:debugPrint("Capturing Bids for 5min.")
          -- Announce bid instructions to raid warning (use full hyperlink for clickable item)
          local item_display = sepgp.bid_item.linkFull or sepgp.bid_item.name or "Unknown"
          gp_cost = gp_cost or "?"
          SendChatMessage(string.format("[EPGP] Bids open: %s (GP: %s) - Whisper me MS, FLEX, OS, or TM to bid!", item_display, tostring(gp_cost)), "RAID_WARNING")
          -- Stagger message 2 to avoid WoW server-side chat throttle
          self:ScheduleEvent("shootyepgpBidMsg2", function()
            SendChatMessage("[EPGP] MS = Main Spec, FLEX = MS but willing to pass, OS = Off Spec, TM = Transmog (0 GP), PASS = withdraw current bid", "RAID")
          end, 1.5)
          -- Feature 1: Broadcast bid item and clear to raid
          self:addonMessage("BID;CLEAR;0", "RAID")
          -- Send item link info with ML name, GP cost, display name, and full link
          local bidName = sepgp.bid_item.name or ""
          local bidLink = sepgp.bid_item.linkFull or ""
          local item_msg = string.format("BID;ITEM;%s;%s;%s;%s;%s", itemString, self._playerName, tostring(gp_cost), bidName, bidLink)
          self:addonMessage(item_msg, "RAID")
          -- Show popup on ML's screen too
          self:ShowBidPopup(itemLink, sepgp.bid_item.name, gp_cost, self._playerName)
          -- Auto-start the countdown the moment bids open -- ML shouldn't
          -- have to click "Countdown" manually for the roll to begin.
          sepgp_bids:bidCountdown()
        end
        self:bidPrint(itemLink,sender,mskw_found,oskw_found,whisperkw_found)
      end
    end
  end
end

-- Bid keyword matching: exact match only after stripping spaces and lowercasing.
-- Case insensitive, space tolerant (e.g., "M S" or " ms " both match "ms").
-- Only these exact keywords register: ms, os, tm, flex, pass. All else silently ignored.
local function parseBidKeyword(text)
  if not text then return nil end
  local stripped = string.gsub(string.lower(text), "%s", "")
  if stripped == "ms" or stripped == "need" then return "ms"
  elseif stripped == "flex" then return "flex"
  elseif stripped == "os" or stripped == "greed" then return "os"
  elseif stripped == "tm" or stripped == "transmog" then return "tm"
  elseif stripped == "pass" then return "pass"
  else return nil end
end
function sepgp:captureBid(text, sender)
  if not (running_bid) then return end
  if not (IsRaidLeader() or self:lootMaster()) then return end
  if not sepgp.bid_item.link then return end

  local keyword = parseBidKeyword(text)
  if not keyword then return end -- silently ignore non-bid whispers

  -- Handle PASS: remove sender from all bid lists
  if keyword == "pass" then
    local function removeBid(list)
      for i = table.getn(list), 1, -1 do
        if list[i][1] == sender then
          table.remove(list, i)
        end
      end
    end
    removeBid(sepgp.bids_main)
    removeBid(sepgp.bids_flex)
    removeBid(sepgp.bids_off)
    removeBid(sepgp.bids_tm)
    bids_blacklist[sender] = nil -- allow re-bidding after pass
    self:addonMessage(string.format("BID;PASS;%s", sender), "RAID")
    self:UpdateBidPopupList()
    return
  end

  if not self:inRaid(sender) then return end
  if bids_blacklist[sender] ~= nil then return end -- already bid

  -- Handle TM: just name and class, no PR needed
  if keyword == "tm" then
    for i = 1, GetNumGuildMembers(1) do
      local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
      if name == sender then
        bids_blacklist[sender] = true
        table.insert(sepgp.bids_tm, {name, class})
        self:addonMessage(string.format("BID;TM;%s;%s", name, class), "RAID")
        self:UpdateBidPopupList()
        return
      end
    end
    -- sender isn't a direct guild member; check if they're a registered external main
    local ext_alt, ext_class = self:resolveExternalMain(sender)
    if (ext_alt) then
      bids_blacklist[sender] = true
      table.insert(sepgp.bids_tm, {sender, ext_class})
      self:addonMessage(string.format("BID;TM;%s;%s", sender, ext_class), "RAID")
      self:UpdateBidPopupList()
    end
    return
  end

  -- Handle MS, FLEX, OS: need PR data
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    if name == sender then
      local ep = (self:get_ep_v3(name, officernote) or 0)
      local gp = (self:get_gp_v3(name, officernote) or sepgp.VARS.basegp)
      local main_name
      if (sepgp_altspool) then
        local main, main_class, main_rank, main_offnote = self:parseAlt(name, officernote)
        if (main) then
          ep = (self:get_ep_v3(main, main_offnote) or 0)
          gp = (self:get_gp_v3(main, main_offnote) or sepgp.VARS.basegp)
          main_name = main
        end
      end
      bids_blacklist[sender] = true
      local entry
      if (sepgp_altspool) and (main_name) then
        entry = {name, class, ep, gp, ep/gp, main_name}
      else
        entry = {name, class, ep, gp, ep/gp}
      end

      local display_name = main_name and string.format("%s (%s's alt)", name, main_name) or name
      local pr_str = string.format("%.2f", ep/gp)

      if keyword == "ms" then
        table.insert(sepgp.bids_main, entry)
        local bid_msg = string.format("BID;MS;%s;%s;%d;%d;%s", name, class, ep, gp, pr_str)
        if main_name then bid_msg = bid_msg .. ";" .. main_name end
        self:addonMessage(bid_msg, "RAID")
      elseif keyword == "flex" then
        table.insert(sepgp.bids_flex, entry)
        local bid_msg = string.format("BID;FLEX;%s;%s;%d;%d;%s", name, class, ep, gp, pr_str)
        if main_name then bid_msg = bid_msg .. ";" .. main_name end
        self:addonMessage(bid_msg, "RAID")
      elseif keyword == "os" then
        table.insert(sepgp.bids_off, entry)
        local bid_msg = string.format("BID;OS;%s;%s;%d;%d;%s", name, class, ep, gp, pr_str)
        if main_name then bid_msg = bid_msg .. ";" .. main_name end
        self:addonMessage(bid_msg, "RAID")
      end
      self:UpdateBidPopupList()
      return
    end
  end

  -- sender isn't a direct guild member; check if they're a registered
  -- external main (their EPGP lives on a banker alt inside this guild)
  local ext_alt, ext_class, ext_officernote = self:resolveExternalMain(sender)
  if (ext_alt) then
    local ep = (self:get_ep_v3(ext_alt, ext_officernote) or 0)
    local gp = (self:get_gp_v3(ext_alt, ext_officernote) or sepgp.VARS.basegp)
    bids_blacklist[sender] = true
    local entry = {sender, ext_class, ep, gp, ep/gp}
    local pr_str = string.format("%.2f", ep/gp)
    if keyword == "ms" then
      table.insert(sepgp.bids_main, entry)
      local bid_msg = string.format("BID;MS;%s;%s;%d;%d;%s", sender, ext_class, ep, gp, pr_str)
      self:addonMessage(bid_msg, "RAID")
    elseif keyword == "flex" then
      table.insert(sepgp.bids_flex, entry)
      local bid_msg = string.format("BID;FLEX;%s;%s;%d;%d;%s", sender, ext_class, ep, gp, pr_str)
      self:addonMessage(bid_msg, "RAID")
    elseif keyword == "os" then
      table.insert(sepgp.bids_off, entry)
      local bid_msg = string.format("BID;OS;%s;%s;%d;%d;%s", sender, ext_class, ep, gp, pr_str)
      self:addonMessage(bid_msg, "RAID")
    end
    self:UpdateBidPopupList()
  end
end

-- Tell every raider's client to close the bid popup. Only the client that
-- ran the bid (master looter / raid leader) broadcasts; receivers handle
-- BID;CLEAR in handleBidSync (HideBidPopup + wipe local bid state).
function sepgp:broadcastBidClear()
  if GetNumRaidMembers() > 0 and (IsRaidLeader() or self:lootMaster()) then
    self:addonMessage("BID;CLEAR;0", "RAID")
  end
end

function sepgp:clearBids(reset)
  if reset~=nil then
    self:debugPrint(L["Clearing old Bids"])
  end
  -- Feature 2: Announce bid results before clearing (only if we have bids and are master looter)
  if (IsRaidLeader() or self:lootMaster()) then
    self:announceBidResults()
  end
  sepgp.bid_item = {}
  sepgp.bids_main = {}
  sepgp.bids_flex = {}
  sepgp.bids_off = {}
  sepgp.bids_tm = {}
  -- 2026-04-06: Clear TM roll state so the next bid item gets a fresh roll
  sepgp.tm_winner = nil
  sepgp.tm_winner2 = nil
  sepgp.tm_roll_id = nil
  bids_blacklist = {}
  if self:IsEventScheduled("shootyepgpBidTimeout") then
    self:CancelScheduledEvent("shootyepgpBidTimeout")
  end
  running_bid = false
  sepgp_bids._counterText = ""
  self:UpdateBidPopupList()
  self:HideBidPopup()
  self:broadcastBidClear()
end

-- /bowepgp bids: local-only status printout for the ML. The old bids window
-- showed this live in a Tablet frame; now everything below already gets
-- broadcast to raid chat as it happens (bid announcements, countdown ticks,
-- winner announcement), so this is just a manual "where do things stand
-- right now" check that only the caller sees.
function sepgp:printBidStatus()
  if not (sepgp.bid_item and (sepgp.bid_item.link or sepgp.bid_item.name)) then
    self:defaultPrint("No active bid.")
    return
  end
  self:defaultPrint(string.format("Current bid: %s (GP: %s)", sepgp.bid_item.name or "?", tostring(sepgp.bid_item.price or "?")))
  local function listBids(label, list)
    if table.getn(list) == 0 then return end
    local names = {}
    for i = 1, table.getn(list) do
      table.insert(names, list[i][1])
    end
    self:defaultPrint(string.format("%s: %s", label, table.concat(names, ", ")))
  end
  listBids("MS", sepgp.bids_main)
  listBids("FLEX", sepgp.bids_flex)
  listBids("OS", sepgp.bids_off)
  listBids("TM", sepgp.bids_tm)
  if table.getn(sepgp.bids_main) == 0 and table.getn(sepgp.bids_flex) == 0 and table.getn(sepgp.bids_off) == 0 and table.getn(sepgp.bids_tm) == 0 then
    self:defaultPrint("No bids yet.")
  end
end

---------------------------------
-- Feature 2: Bid Results Announce
---------------------------------
function sepgp:announceBidResults()
  local has_ms = table.getn(sepgp.bids_main) > 0
  local has_flex = table.getn(sepgp.bids_flex) > 0
  local has_os = table.getn(sepgp.bids_off) > 0
  local has_tm = table.getn(sepgp.bids_tm) > 0
  if (not has_ms) and (not has_flex) and (not has_os) and (not has_tm) then return end

  -- Sort bids by PR descending before announcing
  local pr_sort = function(a, b)
    return tonumber(a[5]) > tonumber(b[5])
  end

  if has_ms then
    table.sort(sepgp.bids_main, pr_sort)
    local ms_parts = {}
    for i = 1, table.getn(sepgp.bids_main) do
      local entry = sepgp.bids_main[i]
      local name = entry[1]
      local pr = entry[5]
      table.insert(ms_parts, string.format("%s (%.2f)", name, pr))
    end
    local ms_msg = "[EPGP] MS Bids: "
    local line = ms_msg
    for i = 1, table.getn(ms_parts) do
      local addition = ms_parts[i]
      if i > 1 then addition = ", " .. addition end
      if string.len(line) + string.len(addition) > 240 then
        self:widestAudience(line)
        line = "[EPGP] MS Bids (cont): " .. ms_parts[i]
      else
        line = line .. addition
      end
    end
    if line ~= ms_msg then
      self:widestAudience(line)
    end
  end

  if has_flex then
    table.sort(sepgp.bids_flex, pr_sort)
    local flex_parts = {}
    for i = 1, table.getn(sepgp.bids_flex) do
      local entry = sepgp.bids_flex[i]
      local name = entry[1]
      local pr = entry[5]
      table.insert(flex_parts, string.format("%s (%.2f)", name, pr))
    end
    local flex_msg = "[EPGP] FLEX Bids: "
    local line = flex_msg
    for i = 1, table.getn(flex_parts) do
      local addition = flex_parts[i]
      if i > 1 then addition = ", " .. addition end
      if string.len(line) + string.len(addition) > 240 then
        self:widestAudience(line)
        line = "[EPGP] FLEX Bids (cont): " .. flex_parts[i]
      else
        line = line .. addition
      end
    end
    if line ~= flex_msg then
      self:widestAudience(line)
    end
  end

  if has_os then
    table.sort(sepgp.bids_off, pr_sort)
    local os_parts = {}
    for i = 1, table.getn(sepgp.bids_off) do
      local entry = sepgp.bids_off[i]
      local name = entry[1]
      local pr = entry[5]
      table.insert(os_parts, string.format("%s (%.2f)", name, pr))
    end
    local os_msg = "[EPGP] OS Bids: "
    local line = os_msg
    for i = 1, table.getn(os_parts) do
      local addition = os_parts[i]
      if i > 1 then addition = ", " .. addition end
      if string.len(line) + string.len(addition) > 240 then
        self:widestAudience(line)
        line = "[EPGP] OS Bids (cont): " .. os_parts[i]
      else
        line = line .. addition
      end
    end
    if line ~= os_msg then
      self:widestAudience(line)
    end
  end

  -- TM roll (if any TM bids). 2026-04-06: Now uses shared rollTmWinners()
  -- helper. Previously this function had its own math.random calls separate
  -- from rollAndAnnounceTM and analyzeLootResolution.
  if has_tm then
    local tm_count = table.getn(sepgp.bids_tm)

    -- Get the (possibly already-rolled) winners from the shared helper.
    self:rollTmWinners()

    local tm_names = {}
    for i = 1, tm_count do
      table.insert(tm_names, string.format("[%d]:%s", i, sepgp.bids_tm[i][1]))
    end
    self:widestAudience("[EPGP] TM Bidders: " .. table.concat(tm_names, ", "))

    if tm_count == 1 then
      self:widestAudience(string.format("[EPGP] Transmog: %s wins (auto-win, 1 bidder)", sepgp.tm_winner))
    else
      -- Show assignments so raid can see who is what number
      local assignMsg = "[EPGP] TM Roll: "
      for i = 1, tm_count do
        if i > 1 then assignMsg = assignMsg .. ", " end
        assignMsg = assignMsg .. string.format("%s=#%d", sepgp.bids_tm[i][1], i)
      end
      self:widestAudience(assignMsg)
      -- Find tm_winner's position in bids_tm so the announcement matches reality
      local roll1Idx, roll2Idx
      for i = 1, tm_count do
        if sepgp.bids_tm[i][1] == sepgp.tm_winner then roll1Idx = i; break end
      end
      self:widestAudience(string.format("[EPGP] Rolling 1-%d ... result: %d -> %s wins TM#1", tm_count, roll1Idx or 0, sepgp.tm_winner))
      if sepgp.tm_winner2 then
        local remCount = tm_count - 1
        local pos = 0
        for i = 1, tm_count do
          if i ~= roll1Idx then
            pos = pos + 1
            if sepgp.bids_tm[i][1] == sepgp.tm_winner2 then roll2Idx = pos; break end
          end
        end
        self:widestAudience(string.format("[EPGP] Rolling 1-%d (remaining) ... result: %d -> %s wins TM#2", remCount, roll2Idx or 0, sepgp.tm_winner2))
      end
      self:widestAudience(string.format("[EPGP] Transmog winners: TM#1 %s, TM#2 %s - 0 GP", sepgp.tm_winner, sepgp.tm_winner2 or "none"))
    end
  end
end

----------------------------------------------
-- Winner announcement (single player to /raid)
----------------------------------------------
-- Phase 1 fix: itemDisplayName parameter replaces bid_item global lookup.
-- gpCharged (optional): the GP just awarded/charged for this item; when given,
-- it is shown in the raid announcement.
function sepgp:announceWinner(playerName, specType, itemDisplayName, gpCharged)
  if not UnitInRaid("player") then return end
  local ep = self:get_ep_v3(playerName) or 0
  local gp = self:get_gp_v3(playerName) or sepgp.VARS.basegp
  local pr = ep / gp
  -- Use passed itemDisplayName (now expected to be the real |Hitem:..|h
  -- link, not the color-only extractItemName output), fall back to
  -- bid_item.linkFull (also a real link) and only then the non-clickable
  -- bid_item.name as a last resort.
  local itemName = ""
  if itemDisplayName and itemDisplayName ~= "" then
    itemName = " " .. itemDisplayName
  elseif sepgp.bid_item and sepgp.bid_item.linkFull and sepgp.bid_item.linkFull ~= "" then
    itemName = " " .. sepgp.bid_item.linkFull
  elseif sepgp.bid_item and sepgp.bid_item.name and sepgp.bid_item.name ~= "" then
    itemName = " " .. sepgp.bid_item.name
  end
  -- Colored/bracketed item name (from extractItemName) is kept as-is now,
  -- so the item shows highlighted in raid chat just like the TRADE ALERT
  -- and bid-open messages do -- previously this stripped the color codes
  -- right before sending, so only this message came out plain.
  local gpText = ""
  local gpNum = tonumber(gpCharged)
  if gpNum then
    gpText = string.format(" - Awarded %d GP", gpNum)
  end
  local msg = string.format("[EPGP] %s won%s (%s)%s - PR: %.2f (EP: %d / GP: %d)", playerName, itemName, specType, gpText, pr, ep, gp)
  SendChatMessage(msg, "RAID")
  sepgp:writeDebugLog(string.format("ANNOUNCE | %s won%s (%s) GP=%s PR=%.2f", playerName, itemName, specType, tostring(gpNum), pr))
end

-- Clear bids without announcing results (used after GP is awarded and winner announced)
function sepgp:clearBidsQuiet()
  sepgp.bid_item = {}
  sepgp.bids_main = {}
  sepgp.bids_flex = {}
  sepgp.bids_off = {}
  sepgp.bids_tm = {}
  -- 2026-04-06: Clear TM roll state so the next bid item gets a fresh roll
  sepgp.tm_winner = nil
  sepgp.tm_winner2 = nil
  sepgp.tm_roll_id = nil
  bids_blacklist = {}
  if self:IsEventScheduled("shootyepgpBidTimeout") then
    self:CancelScheduledEvent("shootyepgpBidTimeout")
  end
  running_bid = false
  sepgp_bids._counterText = ""
  self:HideBidPopup()
  self:broadcastBidClear()
end

----------------------------------------------
-- Raider Bid Popup (shown to all raiders when ML opens bids)
----------------------------------------------
local sepgp_bid_popup = nil
local sepgp_bid_popup_ml = nil -- master looter name for whispers

function sepgp:CreateBidPopup()
  if sepgp_bid_popup then return sepgp_bid_popup end

  -- Layout constants (also used by LayoutBidPopup/UpdateBidPopupList below)
  sepgp.BID_POPUP_HEADER_H = 70   -- f TOP down to bottom of statusText
  sepgp.BID_POPUP_GAP = 6
  sepgp.BID_POPUP_BUTTONBAR_H = 30
  sepgp.BID_POPUP_DIVIDER_H = 2
  sepgp.BID_POPUP_ROW_H = 14
  sepgp.BID_POPUP_BOTTOM_PAD = 10
  sepgp.BID_POPUP_MIN_H_EXPANDED = 140
  sepgp.BID_POPUP_MIN_H_COLLAPSED = 90

  local f = CreateFrame("Frame", "SepgpBidPopup", UIParent)
  f:SetWidth(280)
  f:SetHeight(sepgp.BID_POPUP_MIN_H_EXPANDED)
  -- Moved down from -120 so it clears Blizzard's RaidWarningFrame /
  -- countdown text near the top-center of the screen.
  f:SetPoint("TOP", UIParent, "TOP", 0, -260)
  f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  })
  f:SetBackdropColor(0.1, 0.05, 0.15, 0.92)
  f:SetBackdropBorderColor(0.6, 0.4, 0.8, 0.8)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  f:SetFrameStrata("DIALOG")
  f:Hide()

  -- Title
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("TOP", f, "TOP", 0, -8)
  title:SetText("|cffFFCC00[EPGP] Bid on Loot|r")
  f.title = title

  -- Item text (clickable)
  local itemBtn = CreateFrame("Button", "SepgpBidPopupItem", f)
  itemBtn:SetPoint("TOP", title, "BOTTOM", 0, -6)
  itemBtn:SetWidth(260)
  itemBtn:SetHeight(20)
  local itemText = itemBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  itemText:SetAllPoints()
  itemText:SetText("")
  itemBtn.text = itemText
  itemBtn:SetScript("OnEnter", function()
    if f.itemLink then
      -- Extract bare link ref (item:ID:0:0:0) from full hyperlink.
      -- Native SetHyperlink rejects the full |c..|H..|h format ("unknown link type").
      local _, _, linkRef = string.find(f.itemLink, "|H([^|]+)|h")
      GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
      GameTooltip:SetHyperlink(linkRef or f.itemLink)
      GameTooltip:Show()
    end
  end)
  itemBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  itemBtn:SetScript("OnClick", function()
    if f.itemLink then
      if IsShiftKeyDown() and ChatFrameEditBox:IsVisible() then
        ChatFrameEditBox:Insert(f.itemLink)
      end
    end
  end)
  f.itemBtn = itemBtn

  -- GP cost line
  local gpText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  gpText:SetPoint("TOP", itemBtn, "BOTTOM", 0, -2)
  gpText:SetText("")
  gpText:SetTextColor(0.6, 0.8, 0.6)
  f.gpText = gpText

  -- Status text (shows your current bid). Wrapped in a button so, once the
  -- bid buttons are collapsed, clicking it brings them back to change your
  -- bid instead of having to close/reopen the whole popup.
  local statusBtn = CreateFrame("Button", nil, f)
  statusBtn:SetPoint("TOP", gpText, "BOTTOM", 0, -4)
  statusBtn:SetWidth(260)
  statusBtn:SetHeight(14)
  local statusText = statusBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  statusText:SetAllPoints()
  statusText:SetText("")
  statusText:SetTextColor(0.7, 0.7, 0.7)
  statusBtn.text = statusText
  statusBtn:SetScript("OnClick", function()
    if f.buttonBar and not f.buttonBar:IsShown() then
      f.buttonBar:Show()
      sepgp:LayoutBidPopup()
    end
  end)
  f.statusBtn = statusBtn
  f.statusText = statusText -- kept for backwards compatibility with existing callers

  -- Bid buttons, grouped in a single bar so they can be shown/hidden as one
  -- unit once the player has made a choice.
  local buttonBar = CreateFrame("Frame", nil, f)
  buttonBar:SetWidth(270)
  buttonBar:SetHeight(sepgp.BID_POPUP_BUTTONBAR_H)
  buttonBar:SetPoint("TOP", statusBtn, "BOTTOM", 0, -sepgp.BID_POPUP_GAP)
  f.buttonBar = buttonBar

  local btnWidth = 46
  local btnHeight = 22
  local buttons = {
    {label = "|cffFF3333MS|r", keyword = "MS", xoff = -108},
    {label = "|cffFFAA00FLEX|r", keyword = "FLEX", xoff = -54},
    {label = "|cff00CC00OS|r", keyword = "OS", xoff = 0},
    {label = "|cff00FFFFTM|r", keyword = "TM", xoff = 54},
    {label = "|cff999999PASS|r", keyword = "PASS", xoff = 108},
  }
  local bidButtons = {}

  for _, bdata in ipairs(buttons) do
    local btn = CreateFrame("Button", nil, buttonBar, "UIPanelButtonTemplate")
    btn:SetWidth(btnWidth)
    btn:SetHeight(btnHeight)
    btn:SetPoint("TOP", buttonBar, "TOP", bdata.xoff, 0)
    btn:SetText(bdata.keyword)
    btn.keyword = bdata.keyword
    btn:SetScript("OnClick", function()
      if sepgp_bid_popup_ml then
        -- If changing bid (not passing), auto-send PASS first to clear blacklist
        if this.keyword ~= "PASS" and f.currentBid and f.currentBid ~= this.keyword then
          SendChatMessage("PASS", "WHISPER", nil, sepgp_bid_popup_ml)
        end
        SendChatMessage(this.keyword, "WHISPER", nil, sepgp_bid_popup_ml)
        if this.keyword == "PASS" then
          f.statusText:SetText("|cff999999You withdrew your bid|r  |cff66aaff(click to change)|r")
          f.currentBid = nil
        else
          f.statusText:SetText("Your bid: |cffFFCC00" .. this.keyword .. "|r  |cff66aaff(click to change)|r")
          f.currentBid = this.keyword
        end
        -- Collapse the button row once a choice is made. The people who
        -- aren't interested can just close the window now; everyone else
        -- can keep watching who else bids, below, in the same window.
        f.buttonBar:Hide()
        sepgp:LayoutBidPopup()
      end
    end)
    table.insert(bidButtons, btn)
  end

  -- Divider between the buttons and the live "who bid what" list. Only
  -- shown while the button bar is shown, matching the mockup.
  local divider = f:CreateTexture(nil, "ARTWORK")
  divider:SetHeight(sepgp.BID_POPUP_DIVIDER_H)
  divider:SetWidth(260)
  -- Dark gray (same gray as the column separators in the list below).
  divider:SetTexture(0.15, 0.15, 0.15, 1)
  f.divider = divider

  -- Live list of who has bid what so far, pulled from the same
  -- sepgp.bids_main/flex/off/tm tables the officer bid window uses.
  f.listRows = {}
  f.listRowCount = 0

  -- Close button
  local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
  closeBtn:SetWidth(20)
  closeBtn:SetHeight(20)

  -- Re-skin with pfUI's border/buttons when pfUI is detected as enabled,
  -- instead of the default Blizzard tooltip look set up above.
  sepgp_pfui.Register(f, function()
    sepgp_pfui.SkinFrame(f)
    sepgp_pfui.SkinCloseButton(closeBtn, f, -2, -2)
    for _, btn in ipairs(bidButtons) do
      sepgp_pfui.SkinButton(btn)
    end
  end)

  sepgp_bid_popup = f
  return f
end

-- Repositions the divider/button bar/list rows and resizes the window based
-- on whether the button bar is currently shown and how many bidders are
-- listed. Call after any change to f.buttonBar's visibility or to the row
-- list (UpdateBidPopupList calls this for you).
function sepgp:LayoutBidPopup()
  local f = sepgp_bid_popup
  if not f then return end

  local GAP = sepgp.BID_POPUP_GAP
  local ROW_H = sepgp.BID_POPUP_ROW_H
  local rowCount = f.listRowCount or 0
  local buttonsShown = f.buttonBar and f.buttonBar:IsShown()
  local listAnchorFrame, listAnchorOffset, listTopOffset

  -- The divider now stays visible in both states (previously it was hidden
  -- once the button bar collapsed after a bid) -- it just re-anchors to
  -- whatever is currently the bottom-most header element.
  if buttonsShown then
    f.divider:ClearAllPoints()
    f.divider:SetPoint("TOP", f.buttonBar, "BOTTOM", 0, -GAP)
    f.divider:Show()
    listAnchorFrame = f.divider
    listAnchorOffset = -GAP
    listTopOffset = sepgp.BID_POPUP_HEADER_H + GAP + sepgp.BID_POPUP_BUTTONBAR_H
      + GAP + sepgp.BID_POPUP_DIVIDER_H + GAP
  else
    f.divider:ClearAllPoints()
    f.divider:SetPoint("TOP", f.statusBtn, "BOTTOM", 0, -GAP)
    f.divider:Show()
    listAnchorFrame = f.divider
    listAnchorOffset = -GAP
    listTopOffset = sepgp.BID_POPUP_HEADER_H + GAP + sepgp.BID_POPUP_DIVIDER_H + GAP
  end

  local y = 0
  for i = 1, rowCount do
    local fs = f.listRows[i]
    fs:ClearAllPoints()
    -- Each row is a fixed-width container centered under the anchor, so the
    -- whole table stays centered in the popup.
    if i == 1 then
      fs:SetPoint("TOP", listAnchorFrame, "BOTTOM", 0, listAnchorOffset)
    else
      fs:SetPoint("TOP", f.listRows[i-1], "BOTTOM", 0, -2)
    end
    fs:Show()
  end
  for i = rowCount + 1, table.getn(f.listRows) do
    f.listRows[i]:Hide()
  end

  local minH = buttonsShown and sepgp.BID_POPUP_MIN_H_EXPANDED or sepgp.BID_POPUP_MIN_H_COLLAPSED
  local totalHeight = listTopOffset + (rowCount * ROW_H) + sepgp.BID_POPUP_BOTTOM_PAD
  if totalHeight < minH then totalHeight = minH end
  f:SetHeight(totalHeight)
end

-- Rebuilds the "who bid what" list inside the raider bid popup from the
-- current sepgp.bids_main/flex/off/tm tables. Safe to call any time these
-- tables change; it's a no-op if the popup hasn't been created yet.
function sepgp:UpdateBidPopupList()
  local f = sepgp_bid_popup
  if not f then return end

  -- One entry per bidder: {name, pr, spec}. Each value gets its own cell.
  local rows = {}
  local function addRows(list, spec, hasPR)
    for i = 1, table.getn(list) do
      local entry = list[i]
      local name, class = entry[1], entry[2]
      local coloredName = C:Colorize(BC:GetHexColor(class), name)
      local prText = ""
      if hasPR then
        prText = string.format("PR %.2f", entry[5] or 0)
      end
      table.insert(rows, {coloredName, prText, "|cffFFCC00" .. spec .. "|r"})
    end
  end
  addRows(sepgp.bids_main or {}, "MS", true)
  addRows(sepgp.bids_flex or {}, "FLEX", true)
  addRows(sepgp.bids_off or {}, "OS", true)
  addRows(sepgp.bids_tm or {}, "TM", false)

  -- Column widths (cells are centered inside their column). Total = 240.
  -- Must be EQUAL widths -- unequal columns (previously 110/80/50, then
  -- 100/80/60) keep the whole block off-center even though each cell's
  -- own text is centered inside it, because the column separators end up
  -- unevenly spaced around the window's true center line.
  local COL_NAME_W, COL_PR_W, COL_SPEC_W = 80, 80, 80

  local rowCount = table.getn(rows)
  for i = 1, rowCount do
    local row = f.listRows[i]
    if not row then
      row = CreateFrame("Frame", nil, f)
      row:SetWidth(COL_NAME_W + COL_PR_W + COL_SPEC_W)
      row:SetHeight(12)
      local function makeCell(xoff, width)
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cell:SetWidth(width)
        cell:SetHeight(12)
        cell:SetJustifyH("CENTER")
        cell:SetPoint("LEFT", row, "LEFT", xoff, 0)
        return cell
      end
      row.nameCell = makeCell(0, COL_NAME_W)
      row.prCell = makeCell(COL_NAME_W, COL_PR_W)
      row.specCell = makeCell(COL_NAME_W + COL_PR_W, COL_SPEC_W)

      -- Thin vertical separators between the Name/PR and PR/Spec columns,
      -- same dark gray as the header divider.
      local function makeColSep(xoff)
        local sep = row:CreateTexture(nil, "ARTWORK")
        sep:SetWidth(1)
        sep:SetHeight(12)
        sep:SetPoint("LEFT", row, "LEFT", xoff, 0)
        sep:SetTexture(0.15, 0.15, 0.15, 1)
        return sep
      end
      row.colSep1 = makeColSep(COL_NAME_W)
      row.colSep2 = makeColSep(COL_NAME_W + COL_PR_W)

      f.listRows[i] = row
    end
    row.nameCell:SetText(rows[i][1])
    row.prCell:SetText(rows[i][2])
    row.specCell:SetText(rows[i][3])
  end
  f.listRowCount = rowCount

  self:LayoutBidPopup()
end

function sepgp:ShowBidPopup(itemLink, itemName, gpCost, mlName)
  local f = self:CreateBidPopup()
  sepgp_bid_popup_ml = mlName
  f.itemLink = itemLink

  -- Set item text
  if itemName and itemName ~= "" then
    f.itemBtn.text:SetText(itemName)
  else
    f.itemBtn.text:SetText("|cffFF00FFUnknown Item|r")
  end

  -- Set GP cost
  if gpCost and gpCost ~= "" and gpCost ~= "?" then
    f.gpText:SetText("GP Cost: |cff50CD32" .. tostring(gpCost) .. "|r")
  else
    f.gpText:SetText("")
  end

  -- Reset status
  f.statusText:SetText("Whisper " .. (mlName or "ML") .. " or click a button")
  f.currentBid = nil

  -- A new item: re-show the button bar (in case it was collapsed for the
  -- previous item) and rebuild the who-bid-what list from scratch.
  f.buttonBar:Show()
  self:UpdateBidPopupList()

  f:Show()
end

function sepgp:HideBidPopup()
  if sepgp_bid_popup and sepgp_bid_popup:IsShown() then
    sepgp_bid_popup:Hide()
  end
  sepgp_bid_popup_ml = nil
end

--------------------------
-- Test Mode: Bid Testing
--------------------------
-- Test mode: simulates a loot drop for testing bid keywords
-- Usage: /bowepgp test [gp_cost] -- starts a fake bid cycle
function sepgp:startTestBid(gp_cost)
  if not UnitInRaid("player") then
    self:defaultPrint("Test mode requires being in a raid group.")
    return
  end
  if not (IsRaidLeader() or self:lootMaster()) then
    self:defaultPrint("Test mode requires raid leader or master looter.")
    return
  end
  local cost = tonumber(gp_cost) or 100
  -- Clear any existing bids
  self:clearBidsQuiet()
  -- Set up fake bid item
  sepgp.bid_item = {}
  sepgp.bid_item.link = "test-item"
  sepgp.bid_item.linkFull = "|cffa335ee|Hitem:0:0:0:0|h[Test Epic Item]|h|r"
  sepgp.bid_item.name = "|cffa335eeTest Epic Item|r"
  sepgp.test_gp_cost = cost
  -- Start bid timer
  self:ScheduleEvent("shootyepgpBidTimeout", self.clearBids, 300, self)
  running_bid = true
  self:debugPrint("TEST MODE: Capturing bids for 5min.")
  -- Send the 3 announcement messages
  SendChatMessage(string.format("[EPGP] TEST - Bids open: Test Epic Item (GP: %d) - Whisper me MS, FLEX, OS, or TM to bid!", cost), "RAID_WARNING")
  -- Stagger message 2 to avoid WoW server-side chat throttle
  self:ScheduleEvent("shootyepgpBidMsg2", function()
    SendChatMessage("[EPGP] MS = Main Spec, FLEX = MS but willing to pass, OS = Off Spec, TM = Transmog (0 GP), PASS = withdraw current bid", "RAID")
  end, 1.5)
  self:addonMessage("BID;CLEAR;0", "RAID")
  self:addonMessage(string.format("BID;ITEM;test-item;%s;%d", self._playerName, cost), "RAID")
  -- Show popup locally for testing
  self:ShowBidPopup(nil, "|cffa335ee[Test Epic Item]|r", cost, self._playerName)
  -- Auto-start the countdown, same as a real bid opening.
  sepgp_bids:bidCountdown()
  self:defaultPrint("Test bid started. Whisper MS, FLEX, OS, TM, or PASS to test. Use '/bowepgp testend' to end.")
end

-- 2026-04-06 v4.22: production parity with endTestBid. Officers can
-- manually end the current bid cycle and force the resolution popup
-- with /bowepgp end, instead of having to wait for the loot capture
-- chain (CHAT_MSG_LOOT or GiveMasterLoot hook) to fire the popup.
-- Mirrors endTestBid but reads bid_item from the real bid state
-- rather than test_gp_cost.
function sepgp:endBidNow()
  if not running_bid then
    self:defaultPrint("No bid running.")
    return
  end
  if not (sepgp.bid_item and sepgp.bid_item.linkFull) then
    self:defaultPrint("No bid item set. Cannot show resolution popup.")
    return
  end
  -- Announce final results
  self:announceBidResults()
  -- Cancel the timeout so clearBids doesn't re-announce later
  if self:IsEventScheduled("shootyepgpBidTimeout") then
    self:CancelScheduledEvent("shootyepgpBidTimeout")
  end
  -- Determine the looter from current bids (highest PR MS, then FLEX,
  -- then OS, then TM winner, then self as fallback)
  local looter_name = self._playerName
  if table.getn(sepgp.bids_main) > 0 then
    table.sort(sepgp.bids_main, function(a,b) return (a[5] or 0) > (b[5] or 0) end)
    looter_name = sepgp.bids_main[1][1]
  elseif table.getn(sepgp.bids_flex) > 0 then
    table.sort(sepgp.bids_flex, function(a,b) return (a[5] or 0) > (b[5] or 0) end)
    looter_name = sepgp.bids_flex[1][1]
  elseif table.getn(sepgp.bids_off) > 0 then
    table.sort(sepgp.bids_off, function(a,b) return (a[5] or 0) > (b[5] or 0) end)
    looter_name = sepgp.bids_off[1][1]
  elseif table.getn(sepgp.bids_tm) > 0 and sepgp.tm_winner then
    looter_name = sepgp.tm_winner
  end
  local class = self:resolveLooterClass(looter_name)
  local color = "|cffFFFFFF" .. looter_name .. "|r"
  if class then
    color = "|c" .. (BC and BC:GetHexColor(class) or "ffFFFFFF") .. looter_name .. "|r"
  end
  local data = {
    [self.loot_index.time] = date("%H:%M"),
    [self.loot_index.player] = looter_name,
    [self.loot_index.player_c] = color,
    [self.loot_index.item] = sepgp.bid_item.linkFull,
    [self.loot_index.bind] = self.VARS.bop,
    [self.loot_index.price] = sepgp.bid_item.price or 0,
    [self.loot_index.off_price] = sepgp.bid_item.off_price or 0,
  }
  self:writeDebugLog("PROD_END_BID | " .. looter_name .. " | " .. (sepgp.bid_item.linkFull or "?"))
  -- Mark the link so the loot capture chain won't fire a duplicate popup
  self._popupShownLinks = self._popupShownLinks or {}
  self._popupShownLinks[sepgp.bid_item.linkFull] = GetTime()
  self:AutoResolveLoot(data)
end

function sepgp:endTestBid()
  if not running_bid then
    self:defaultPrint("No test bid running.")
    return
  end
  -- Announce bid results first (MS/FLEX/OS by PR, TM by random roll)
  self:announceBidResults()
  -- Cancel bid timeout so clearBids doesn't re-announce results
  if self:IsEventScheduled("shootyepgpBidTimeout") then
    self:CancelScheduledEvent("shootyepgpBidTimeout")
  end

  -- Determine who "looted" the item for the dialog.
  -- In a real transmog scenario: TM winner receives item first (to equip for appearance).
  -- In a normal scenario: MS/FLEX/OS winner receives item directly.
  local cost = sepgp.test_gp_cost or 100
  local off_cost = math.floor(cost * (sepgp_discount or 0.25))
  local looter_name = sepgp._playerName -- fallback to self

  -- If TM bids exist, the TM winner is the looter (transmog mule)
  if table.getn(sepgp.bids_tm) > 0 and sepgp.tm_winner then
    looter_name = sepgp.tm_winner
  -- Otherwise the highest priority MS/FLEX/OS bidder is the looter
  elseif table.getn(sepgp.bids_main) > 0 then
    table.sort(sepgp.bids_main, function(a,b) return a[5] > b[5] end)
    looter_name = sepgp.bids_main[1][1]
  elseif table.getn(sepgp.bids_flex) > 0 then
    table.sort(sepgp.bids_flex, function(a,b) return a[5] > b[5] end)
    looter_name = sepgp.bids_flex[1][1]
  elseif table.getn(sepgp.bids_off) > 0 then
    table.sort(sepgp.bids_off, function(a,b) return a[5] > b[5] end)
    looter_name = sepgp.bids_off[1][1]
  end

  local looter_color = "|cffFFFFFF" .. looter_name .. "|r"
  local item_link = sepgp.bid_item.linkFull or "|cffa335ee[Test Epic Item]|r"
  local data = {
    [self.loot_index.time] = date("%H:%M"),
    [self.loot_index.player] = looter_name,
    [self.loot_index.player_c] = looter_color,
    [self.loot_index.item] = item_link,
    [self.loot_index.bind] = self.VARS.bop,
    [self.loot_index.price] = cost,
    [self.loot_index.off_price] = off_cost,
  }
  -- Phase 3: Use Resolution Window (fall back to StaticPopup if legacy flag set)
  if sepgp_useLegacyPopup then
    local dialog = StaticPopup_Show("SHOOTY_EPGP_AUTO_GEARPOINTS", looter_color, item_link, data)
    self:writeDebugLog("ENDTEST_DIALOG | dialog=" .. tostring(dialog) .. " | item_link=" .. tostring(item_link))
    if dialog then
      dialog.data = data
      sepgp:setupPopupTooltip(dialog)
    else
      self:writeDebugLog("ENDTEST_DIALOG | NIL - popup not created")
    end
    self:defaultPrint(string.format("Test resolution shown. Looter: %s. Review and Confirm & Charge.", looter_name))
  else
    self:AutoResolveLoot(data)
    self:writeDebugLog("ENDTEST_DIALOG | auto_resolved | item_link=" .. tostring(item_link))
  end
end

-- Inject a fake bid for test mode. Simulates another player bidding
-- without needing them in the raid. Usage: /bowepgp testbid ms SomeName
function sepgp:injectTestBid(input)
  if not running_bid then
    self:defaultPrint("No test bid running. Start one with /bowepgp test")
    return
  end
  -- Parse "keyword name" from input
  local keyword, name
  for k, n in string.gfind(input, "(%S+)%s+(%S+)") do
    keyword = k
    name = n
  end
  if not keyword or not name then
    self:defaultPrint("Usage: /bowepgp testbid ms PlayerName")
    return
  end
  local bid = parseBidKeyword(keyword)
  if not bid then
    self:defaultPrint("Invalid keyword. Use ms, flex, os, tm, or pass.")
    return
  end
  if bid == "pass" then
    -- Remove fake bids for this name
    local function removeBid(list)
      for i = table.getn(list), 1, -1 do
        if list[i][1] == name then table.remove(list, i) end
      end
    end
    removeBid(sepgp.bids_main)
    removeBid(sepgp.bids_flex)
    removeBid(sepgp.bids_off)
    removeBid(sepgp.bids_tm)
    bids_blacklist[name] = nil
    self:defaultPrint(string.format("Test: %s withdrew bid (PASS)", name))
    return
  end
  if bids_blacklist[name] then
    self:defaultPrint(string.format("Test: %s already bid. Use pass first to change.", name))
    return
  end
  bids_blacklist[name] = true
  -- Use fake EP/GP values for test
  local fake_ep = math.random(500, 5000)
  local fake_gp = math.random(100, 500)
  local fake_pr = fake_ep / fake_gp
  if bid == "tm" then
    table.insert(sepgp.bids_tm, {name, "Unknown"})
    self:defaultPrint(string.format("Test: %s bid TM (transmog)", name))
  elseif bid == "ms" then
    table.insert(sepgp.bids_main, {name, "Unknown", fake_ep, fake_gp, fake_pr})
    self:defaultPrint(string.format("Test: %s bid MS (PR %.2f)", name, fake_pr))
  elseif bid == "flex" then
    table.insert(sepgp.bids_flex, {name, "Unknown", fake_ep, fake_gp, fake_pr})
    self:defaultPrint(string.format("Test: %s bid FLEX (PR %.2f)", name, fake_pr))
  elseif bid == "os" then
    table.insert(sepgp.bids_off, {name, "Unknown", fake_ep, fake_gp, fake_pr})
    self:defaultPrint(string.format("Test: %s bid OS (PR %.2f)", name, fake_pr))
  end
end

----------------------------------------------
-- Phase 4: Enhanced Test Mode
----------------------------------------------
-- Test with a specific item ID from prices.lua.
-- Usage: /bowepgp testitem 21682  (Bile-Covered Gauntlets)
-- This creates a test bid with the real item name and GP cost.
function sepgp:startTestWithItem(itemIdStr)
  if not UnitInRaid("player") then
    self:defaultPrint("Test mode requires being in a raid group.")
    return
  end
  if not (IsRaidLeader() or self:lootMaster()) then
    self:defaultPrint("Test mode requires raid leader or master looter.")
    return
  end
  local itemId = tonumber(itemIdStr)
  if not itemId then
    self:defaultPrint("Usage: /bowepgp testitem <itemId>  (e.g. /bowepgp testitem 21682)")
    return
  end
  -- Look up price from prices.lua
  local itemString = string.format("item:%d:0:0:0:0:0:0:0", itemId)
  local price = sepgp_prices:GetPrice(itemString, sepgp_progress)
  if not price or price == 0 then
    self:defaultPrint(string.format("Item %d has no GP cost or 0 GP. Cannot test.", itemId))
    return
  end
  -- Try to get item info from client cache
  -- NOTE: In vanilla 1.12/TurtleWoW, GetItemInfo returns the item string as
  -- second value (e.g. "item:21682:0:0:0"), NOT a formatted hyperlink.
  -- We must build the hyperlink ourselves from the name.
  local itemName, itemStringRaw, itemQuality = GetItemInfo(itemId)
  local itemLink
  if itemName then
    -- Build proper hyperlink from name
    local colorCode = "|cffa335ee"  -- epic purple default
    if itemQuality == 3 then colorCode = "|cff0070dd"      -- rare blue
    elseif itemQuality == 2 then colorCode = "|cff1eff00"   -- uncommon green
    elseif itemQuality == 5 then colorCode = "|cffff8000"   -- legendary orange
    end
    itemLink = string.format("%s|Hitem:%d:0:0:0|h[%s]|h|r", colorCode, itemId, itemName)
  end
  if not itemName then
    -- Item not cached. Query server by creating a tooltip, then retry after delay.
    if not sepgp._testTooltip then
      sepgp._testTooltip = CreateFrame("GameTooltip", "SepgpTestItemTooltip", nil, "GameTooltipTemplate")
    end
    sepgp._testTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    sepgp._testTooltip:SetHyperlink("item:" .. itemId .. ":0:0:0")
    -- Read name from tooltip line 1
    local ttName = SepgpTestItemTooltipTextLeft1 and SepgpTestItemTooltipTextLeft1:GetText()
    if ttName and ttName ~= "" and ttName ~= "Retrieving item information" then
      itemName = ttName
    end
    if not itemName then
      -- Server hasn't responded yet. Schedule retry in 1 second.
      self:defaultPrint("Fetching item data from server... retrying in 1 second.")
      self:ScheduleEvent("sepgpTestItemRetry", function()
        sepgp:startTestWithItem(itemIdStr)
      end, 1)
      return
    end
    -- Build proper item link with real name (5-field vanilla format for clickable chat links)
    itemLink = string.format("|cffa335ee|Hitem:%d:0:0:0|h[%s]|h|r", itemId, itemName)
  end
  local off_price = math.floor(price * (sepgp_discount or 0.25))

  -- Clear any existing bids
  self:clearBidsQuiet()
  -- Set up bid item
  sepgp.bid_item = {}
  sepgp.bid_item.link = itemString
  sepgp.bid_item.linkFull = itemLink
  local extractedName = self:extractItemName(itemLink)
  self:writeDebugLog(string.format("TEST_EXTRACT | itemLink=%s | extracted=%s | itemName=%s", tostring(itemLink), tostring(extractedName), tostring(itemName)))
  sepgp.bid_item.name = extractedName or itemName
  sepgp.bid_item.price = price
  sepgp.bid_item.off_price = off_price
  sepgp.test_gp_cost = price

  -- Start bid timer
  self:ScheduleEvent("shootyepgpBidTimeout", self.clearBids, 300, self)
  running_bid = true

  -- Announce to raid (use full hyperlink for clickable item link in chat log)
  local displayName = sepgp.bid_item.name or itemName
  SendChatMessage(string.format("[EPGP] TEST - Bids open: %s (GP: %d / OS: %d) - Whisper me MS, FLEX, OS, or TM!", sepgp.bid_item.linkFull or displayName, price, off_price), "RAID_WARNING")
  self:ScheduleEvent("shootyepgpBidMsg2", function()
    SendChatMessage("[EPGP] MS = Main Spec, FLEX = MS but willing to pass, OS = Off Spec, TM = Transmog (0 GP), PASS = withdraw", "RAID")
  end, 1.5)
  self:addonMessage("BID;CLEAR;0", "RAID")
  local bidName = sepgp.bid_item.name or ""
  local bidLink = sepgp.bid_item.linkFull or ""
  self:addonMessage(string.format("BID;ITEM;%s;%s;%d;%s;%s", itemString, self._playerName, price, bidName, bidLink), "RAID")
  self:ShowBidPopup(itemLink, displayName, price, self._playerName)
  -- Auto-start the countdown, same as a real bid opening.
  sepgp_bids:bidCountdown()

  self:defaultPrint(string.format("Test started: %s (ID: %d, GP: %d, OS: %d)", displayName, itemId, price, off_price))
  self:defaultPrint("Use /bowepgp testbid ms|os|tm <Name> to simulate bids, /bowepgp testend to resolve.")
  self:writeDebugLog(string.format("TEST_START | itemId=%d | %s | price=%d | os=%d", itemId, displayName, price, off_price))
end

--------------------------
-- Feature 1: Bid Sync
--------------------------
function sepgp:handleBidSync(message, sender)
  -- Parse BID messages: BID;TYPE;args...
  local parts = {}
  for part in string.gfind(message, "([^;]+)") do
    table.insert(parts, part)
  end
  if table.getn(parts) < 3 then return end

  local bid_type = parts[2] -- MS, OS, CLEAR, ITEM

  if bid_type == "CLEAR" then
    -- Only clear on non-ML clients; ML manages bid_item locally
    if not sepgp:lootMaster() then
      sepgp.bid_item = {}
      sepgp.bids_main = {}
      sepgp.bids_flex = {}
      sepgp.bids_off = {}
      sepgp.bids_tm = {}
      sepgp:HideBidPopup()
    end
    return
  end

  if bid_type == "ITEM" then
    -- ML already set bid_item locally; only process on non-ML clients
    if sepgp:lootMaster() then
      -- ML: just show the popup, don't overwrite bid_item (price would be lost)
      local mlName = parts[4] or sender
      local gpCost = parts[5] or "?"
      sepgp:ShowBidPopup(sepgp.bid_item and sepgp.bid_item.linkFull, sepgp.bid_item and sepgp.bid_item.name, gpCost, mlName)
      return
    end
    -- Format: BID;ITEM;itemString;mlName;gpCost;displayName;fullLink
    local itemString = parts[3]
    local mlName = parts[4] or sender
    local gpCost = parts[5] or "?"
    local mlDisplayName = parts[6]  -- transmitted from ML
    local mlFullLink = parts[7]     -- transmitted from ML
    if itemString and itemString ~= "" then
      sepgp.bid_item.link = itemString
      -- Store ML's transmitted price so bid window shows correct GP
      local mlPrice = tonumber(gpCost)
      if mlPrice then
        sepgp.bid_item.price = mlPrice
        sepgp.bid_item.off_price = math.floor(mlPrice * (sepgp_discount or 0.25))
      end
      -- Try to get the item name and color from the item cache
      local itemName, itemLink, itemQuality = GetItemInfo(itemString)
      if itemName and itemLink then
        sepgp.bid_item.linkFull = itemLink
        local _, _, itemColor, _, displayName = string.find(itemLink, "^(|c%x+)|H(.+)|h(%[.+%])")
        if itemColor and displayName then
          sepgp.bid_item.name = string.format("%s%s|r", itemColor, displayName)
        else
          sepgp.bid_item.name = itemName
        end
      else
        -- Item not in client cache. Use ML's transmitted name and link.
        if mlDisplayName and mlDisplayName ~= "" then
          sepgp.bid_item.name = mlDisplayName
        else
          sepgp.bid_item.name = itemString
        end
        if mlFullLink and mlFullLink ~= "" then
          sepgp.bid_item.linkFull = mlFullLink
          itemLink = mlFullLink
        else
          itemLink = nil
        end
      end
      -- The officer table stays master-looter-only now; non-ML raiders get
      -- the merged bid popup below instead.
      -- Show the raider bid popup with item, GP cost, and ML name
      sepgp:ShowBidPopup(itemLink or itemString, sepgp.bid_item.name, gpCost, mlName)
    end
    return
  end

  -- Handle PASS sync from master looter
  if bid_type == "PASS" then
    if self:lootMaster() then return end
    local pass_name = parts[3]
    if pass_name then
      local function removeBidSync(list)
        for i = table.getn(list), 1, -1 do
          if list[i][1] == pass_name then
            table.remove(list, i)
          end
        end
      end
      removeBidSync(sepgp.bids_main)
      removeBidSync(sepgp.bids_flex)
      removeBidSync(sepgp.bids_off)
      removeBidSync(sepgp.bids_tm)
      self:UpdateBidPopupList()
    end
    return
  end

  -- Handle TM sync (only name and class, no PR)
  if bid_type == "TM" and table.getn(parts) >= 4 then
    if self:lootMaster() then return end
    local bidder_name = parts[3]
    local bidder_class = parts[4]
    table.insert(sepgp.bids_tm, {bidder_name, bidder_class})
    self:UpdateBidPopupList()
    return
  end

  if (bid_type == "MS" or bid_type == "OS" or bid_type == "FLEX") and table.getn(parts) >= 7 then
    local bidder_name = parts[3]
    local bidder_class = parts[4]
    local bidder_ep = tonumber(parts[5]) or 0
    local bidder_gp = tonumber(parts[6]) or 0
    local bidder_pr = tonumber(parts[7]) or 0
    local bidder_main = parts[8] -- may be nil

    -- Don't duplicate if we already have this bid (master looter has it locally)
    if self:lootMaster() then return end

    local entry
    if bidder_main and bidder_main ~= "" then
      entry = {bidder_name, bidder_class, bidder_ep, bidder_gp, bidder_pr, bidder_main}
    else
      entry = {bidder_name, bidder_class, bidder_ep, bidder_gp, bidder_pr}
    end

    if bid_type == "MS" then
      table.insert(sepgp.bids_main, entry)
    elseif bid_type == "FLEX" then
      table.insert(sepgp.bids_flex, entry)
    else
      table.insert(sepgp.bids_off, entry)
    end
    self:UpdateBidPopupList()
    return
  end
end

------------------------------
-- Feature 3: Loot Display
------------------------------
-- Create the loot display frame
sepgp._lootDisplayFrame = CreateFrame("Frame", "ShootyEPGP_LootDisplay", UIParent)
sepgp._lootDisplayFrame:SetWidth(320)
sepgp._lootDisplayFrame:SetHeight(40)
sepgp._lootDisplayFrame:SetPoint("TOP", UIParent, "TOP", 0, -120)
sepgp._lootDisplayFrame:SetFrameStrata("HIGH")
sepgp._lootDisplayFrame:SetMovable(true)
sepgp._lootDisplayFrame:EnableMouse(true)
sepgp._lootDisplayFrame:RegisterForDrag("LeftButton")
sepgp._lootDisplayFrame:SetScript("OnDragStart", function() this:StartMoving() end)
sepgp._lootDisplayFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
sepgp._lootDisplayFrame:SetBackdrop({
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
sepgp._lootDisplayFrame:SetBackdropColor(0, 0, 0, 0.85)
sepgp._lootDisplayFrame:SetBackdropBorderColor(0.6, 0.2, 0.9, 0.8)
sepgp._lootDisplayFrame:Hide()

-- Title bar
sepgp._lootDisplayFrame.title = sepgp._lootDisplayFrame:CreateFontString(nil, "OVERLAY")
sepgp._lootDisplayFrame.title:SetFont("Fonts\\FRIZQT__.TTF", 11)
sepgp._lootDisplayFrame.title:SetPoint("TOP", sepgp._lootDisplayFrame, "TOP", 0, -8)
sepgp._lootDisplayFrame.title:SetTextColor(1, 0.82, 0)
sepgp._lootDisplayFrame.title:SetText("EPGP Loot Drops")

-- Close button
sepgp._lootDisplayFrame.close = CreateFrame("Button", nil, sepgp._lootDisplayFrame, "UIPanelCloseButton")
sepgp._lootDisplayFrame.close:SetWidth(20)
sepgp._lootDisplayFrame.close:SetHeight(20)
sepgp._lootDisplayFrame.close:SetPoint("TOPRIGHT", sepgp._lootDisplayFrame, "TOPRIGHT", -2, -2)

-- Re-skin with pfUI's border/close button when pfUI is detected as
-- enabled, instead of the default Blizzard tooltip look set up above.
-- Registered (not just called once) because this frame is built at file
-- load time, before we can be sure pfUI has already finished loading.
sepgp_pfui.Register(sepgp._lootDisplayFrame, function()
  sepgp_pfui.SkinFrame(sepgp._lootDisplayFrame)
  sepgp_pfui.SkinCloseButton(sepgp._lootDisplayFrame.close, sepgp._lootDisplayFrame, -2, -2)
end)

-- Item lines storage
sepgp._lootDisplayLines = {}

function sepgp:onLootOpened()
  if not UnitInRaid("player") then return end
  if not (self:lootMaster() and admin()) then return end

  local epic_items = {}
  local num_slots = GetNumLootItems()
  if not num_slots or num_slots == 0 then return end

  for slot = 1, num_slots do
    if LootSlotIsItem(slot) then
      local texture, itemname, quantity, quality = GetLootSlotInfo(slot)
      -- quality >= 4 is epic (purple), 3 is rare (blue) - show epic+
      if quality and quality >= 4 then
        local itemLink = GetLootSlotLink(slot)
        if itemLink then
          local price
          -- Extract item string for price lookup (Lua 5.0 compatible)
          local _, _, itemString = string.find(itemLink, "|H(item:[%d:]+)|h")
          if itemString then
            price = sepgp_prices:GetPrice(itemString, sepgp_progress)
          end
          table.insert(epic_items, {
            link = itemLink,
            name = itemname,
            quality = quality,
            texture = texture,
            price = price,
            slot = slot
          })
        end
      end
    end
  end

  if table.getn(epic_items) == 0 then
    self._lootDisplayFrame:Hide()
    return
  end

  -- Clear old item lines
  for i = 1, table.getn(self._lootDisplayLines) do
    if self._lootDisplayLines[i] then
      self._lootDisplayLines[i]:Hide()
    end
  end
  self._lootDisplayLines = {}

  -- Build the display
  local line_height = 18
  local padding_top = 24
  local padding_bottom = 8
  local frame_height = padding_top + (table.getn(epic_items) * line_height) + padding_bottom

  self._lootDisplayFrame:SetHeight(frame_height)

  for i = 1, table.getn(epic_items) do
    local item = epic_items[i]
    local line = self._lootDisplayFrame:CreateFontString(nil, "OVERLAY")
    line:SetFont("Fonts\\FRIZQT__.TTF", 11)
    line:SetPoint("TOPLEFT", self._lootDisplayFrame, "TOPLEFT", 10, -(padding_top + (i-1) * line_height))
    line:SetPoint("RIGHT", self._lootDisplayFrame, "RIGHT", -10, 0)
    line:SetJustifyH("LEFT")

    local price_text = ""
    if item.price and item.price > 0 then
      local off_price = math.floor(item.price * (sepgp_discount or 0.5))
      price_text = string.format("  |cff32CD32GP:%d|r |cff20B2AAOS:%d|r", item.price, off_price)
    end
    line:SetText(string.format("%s%s", item.link, price_text))
    line:Show()
    table.insert(self._lootDisplayLines, line)
  end

  self._lootDisplayFrame:Show()

  -- Broadcast loot list + GP costs to raid warning so all raiders can see
  if table.getn(epic_items) > 0 then
    SendChatMessage("[EPGP] === Boss Loot ===", "RAID_WARNING")
    for i = 1, table.getn(epic_items) do
      local item = epic_items[i]
      local cost_str = ""
      if item.price and item.price > 0 then
        local off_price = math.floor(item.price * (sepgp_discount or 0.5))
        cost_str = string.format(" - GP: %d (OS: %d)", item.price, off_price)
      end
      SendChatMessage(string.format("[EPGP] %s%s", item.name, cost_str), "RAID_WARNING")
    end
  end

  -- Auto-hide after 30 seconds
  if self:IsEventScheduled("shootyepgpLootDisplayHide") then
    self:CancelScheduledEvent("shootyepgpLootDisplayHide")
  end
  self:ScheduleEvent("shootyepgpLootDisplayHide", function()
    sepgp._lootDisplayFrame:Hide()
  end, 30)
end

----------------------------------------------
-- Phase 1: Utility Functions
----------------------------------------------

-- Extract displayable item name from an item link string.
-- Input:  "|cffa335ee|Hitem:21682:0:0:0|h[Bile-Covered Gauntlets]|h|r"
-- Output: "|cffa335ee[Bile-Covered Gauntlets]|r"
function sepgp:extractItemName(itemLink)
  if not itemLink or itemLink == "" then return nil end
  local _, _, color, name = string.find(itemLink, "(|c%x+).-(%[.+%])")
  if color and name then
    return color .. name .. "|r"
  end
  return itemLink
end

-- Persistent debug log. Writes to SEPGP_DEBUG_LOG SavedVariable.
-- Survives /reload and logout. Check WTF/Account/<acct>/SavedVariables/BoW-EPGP.lua
function sepgp:writeDebugLog(msg)
  if not SEPGP_DEBUG_LOG then SEPGP_DEBUG_LOG = {} end
  local timestamp = date("%Y-%m-%d %H:%M:%S")
  table.insert(SEPGP_DEBUG_LOG, timestamp .. " | " .. msg)
  -- Cap at 2000 entries to prevent SavedVariables bloat
  while table.getn(SEPGP_DEBUG_LOG) > 2000 do
    table.remove(SEPGP_DEBUG_LOG, 1)
  end
end

-- DE Roster: tracks which raid members can disenchant.
-- Stored in sepgp_de_roster SavedVariable (per-character).
-- Usage: /bowepgp de add Fieldwalker
--        /bowepgp de remove Fieldwalker
--        /bowepgp de list
if not sepgp_de_roster then sepgp_de_roster = {} end

-- Strip WoW color codes from a string for clean chat messages
function sepgp:stripColors(str)
  if not str then return "" end
  str = string.gsub(str, "|c%x%x%x%x%x%x%x%x", "")
  str = string.gsub(str, "|r", "")
  str = string.gsub(str, "|H[^|]*|h", "")
  str = string.gsub(str, "|h", "")
  return str
end

-- Normalize player name: first letter uppercase, rest lowercase (WoW standard)
function sepgp:normalizeName(name)
  if not name or name == "" then return nil end
  name = string.gsub(name, "^%s+", "")
  name = string.gsub(name, "%s+$", "")
  if name == "" then return nil end
  return string.upper(string.sub(name, 1, 1)) .. string.lower(string.sub(name, 2))
end

function sepgp:deRosterAdd(name)
  name = self:normalizeName(name)
  if not name then
    self:defaultPrint("Usage: /deadd PlayerName")
    return
  end
  -- Remove any case variants first to prevent duplicates
  self:deRosterClean(name)
  sepgp_de_roster[name] = true
  self:defaultPrint(string.format("Added %s to DE roster.", name))
  self:writeDebugLog("DE_ROSTER_ADD | " .. name)
end

function sepgp:deRosterRemove(name)
  name = self:normalizeName(name)
  if not name then
    self:defaultPrint("Usage: /deremove PlayerName")
    return
  end
  -- Remove all case variants
  self:deRosterClean(name)
  self:defaultPrint(string.format("Removed %s from DE roster.", name))
  self:writeDebugLog("DE_ROSTER_REMOVE | " .. name)
end

-- Remove all case variants of a name from the roster
function sepgp:deRosterClean(normalized)
  local lower = string.lower(normalized)
  local toRemove = {}
  for existing, _ in pairs(sepgp_de_roster) do
    if string.lower(existing) == lower then
      table.insert(toRemove, existing)
    end
  end
  for _, key in ipairs(toRemove) do
    sepgp_de_roster[key] = nil
  end
end

function sepgp:deRosterList()
  local names = {}
  for name, _ in pairs(sepgp_de_roster) do
    table.insert(names, name)
  end
  if table.getn(names) == 0 then
    self:defaultPrint("DE roster is empty. Use /deadd PlayerName")
  else
    self:defaultPrint("DE roster: " .. table.concat(names, ", "))
  end
end

function sepgp:isDisenchanter(name)
  if not name then return false end
  local normalized = self:normalizeName(name)
  return sepgp_de_roster[name] == true or (normalized and sepgp_de_roster[normalized] == true)
end

-- Set up item tooltip hover on a StaticPopup dialog frame.
-- Must be called AFTER dialog.data is assigned.
function sepgp:setupPopupTooltip(dialog)
  if not dialog or not dialog.data then return end
  local itemLink = dialog.data[sepgp.loot_index.item]
  if not itemLink then return end
  -- Create a transparent Button overlay on the popup text area.
  -- This is exactly how the bid popup does it (line 2304-2318):
  -- a Button frame catches OnEnter/OnLeave and shows GameTooltip.
  if not dialog._sepgpTooltipBtn then
    local btn = CreateFrame("Button", nil, dialog)
    -- Single anchor + explicit size. Two-point anchoring (TOPLEFT+BOTTOMRIGHT)
    -- to a FontString yields zero-size buttons in vanilla 1.12 because the
    -- layout engine hasn't computed FontString bounds yet. This matches the
    -- working bid popup pattern (line 2304): one anchor + SetWidth/SetHeight.
    local textRegion = getglobal(dialog:GetName() .. "Text")
    if textRegion then
      btn:SetPoint("CENTER", textRegion, "CENTER", 0, 0)
    else
      btn:SetPoint("TOP", dialog, "TOP", 0, -10)
    end
    btn:SetWidth(250)
    btn:SetHeight(40)
    btn:SetFrameLevel(dialog:GetFrameLevel() + 10)
    btn:SetScript("OnEnter", function()
      if this._itemLink then
        -- Extract bare link ref (item:ID:0:0:0) from full hyperlink.
        -- Native SetHyperlink rejects the full |c..|H..|h format ("unknown link type").
        local _, _, linkRef = string.find(this._itemLink, "|H([^|]+)|h")
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(linkRef or this._itemLink)
        GameTooltip:Show()
      end
    end)
    btn:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    dialog._sepgpTooltipBtn = btn
  end
  dialog._sepgpTooltipBtn._itemLink = itemLink
  dialog._sepgpTooltipBtn:Show()
  self:writeDebugLog("POPUP_TOOLTIP | " .. tostring(itemLink))
end

----------------------------------------------
-- Phase 4: Fully Automatic Loot Resolution (no popup, no manual confirm)
----------------------------------------------
-- AutoResolveLoot(data) is the single entry point: pre-computes the
-- resolution plan (analyzeLootResolution: MS > FLEX > OS, TM mule
-- routed/awarded first, DE fallback for unclaimed items) and immediately
-- executes it -- GP charge, winner announce, TM roll, DE assignment,
-- raid chat, officer chat, loot history, advance queue. No frame, no
-- Confirm/Remind Later/Cancel buttons -- there is nothing left to confirm.
-- Callers: sepgp_bids's countdown (bids.lua), endBidNow, endTestBid, and
-- showNextLootPopup (organic loot captured via WoW's master loot UI).
local sepgp_resolution_data = nil
local sepgp_resolution_plan = nil

-- 2026-04-06: Shared TM roll function. Single source of truth for TM winners.
-- Idempotent: if winners are already rolled for the current bid_item.link,
-- returns them unchanged. Otherwise rolls fresh, stores in sepgp.tm_winner /
-- sepgp.tm_winner2 / sepgp.tm_roll_id, and returns them.
--
-- WHY: Previously rollAndAnnounceTM (bids.lua) and analyzeLootResolution
-- both rolled independently with separate math.random calls, producing
-- different TM winners between raid chat and officer chat for the same bid.
-- This function makes both code paths use one and only one roll.
--
-- The roll is tied to bid_item.link via tm_roll_id so a new bid invalidates
-- the previous roll automatically.
function sepgp:rollTmWinners()
  local tmCount = table.getn(self.bids_tm)
  if tmCount == 0 then
    self.tm_winner = nil
    self.tm_winner2 = nil
    self.tm_roll_id = nil
    return nil, nil
  end

  local currentRollId = (self.bid_item and self.bid_item.link) or "no-bid"
  -- If already rolled for this bid AND winner count matches what we'd produce, reuse.
  if self.tm_winner and self.tm_roll_id == currentRollId then
    -- For 1 bidder: tm_winner2 must be nil. For 2+ bidders: tm_winner2 must be set.
    if (tmCount == 1 and self.tm_winner2 == nil) or
       (tmCount >= 2 and self.tm_winner2 ~= nil) then
      return self.tm_winner, self.tm_winner2
    end
  end

  -- Fresh roll
  if tmCount == 1 then
    self.tm_winner = self.bids_tm[1][1]
    self.tm_winner2 = nil
  else
    local roll1 = math.random(1, tmCount)
    self.tm_winner = self.bids_tm[roll1][1]
    local remaining = {}
    for i = 1, tmCount do
      if i ~= roll1 then table.insert(remaining, self.bids_tm[i]) end
    end
    if table.getn(remaining) > 0 then
      local roll2 = math.random(1, table.getn(remaining))
      self.tm_winner2 = remaining[roll2][1]
    else
      self.tm_winner2 = nil
    end
  end

  -- 2026-04-06: DE-aware swap. If this is a TM-only scenario (no MS/FLEX/OS
  -- winner) AND tm_winner is a disenchanter while tm_winner2 isn't, swap them
  -- so the DE-capable player ends up LAST in the chain. Doing the swap here
  -- (instead of only in analyzeLootResolution) ensures the raid chat
  -- announcements show the SAME order as the officer chat post-confirm.
  self.tm_swapped = false
  local hasGpWinner = (table.getn(self.bids_main) > 0) or
                      (table.getn(self.bids_flex) > 0) or
                      (table.getn(self.bids_off) > 0)
  if not hasGpWinner and self.tm_winner and self.tm_winner2 then
    local w1De = self:isDisenchanter(self.tm_winner)
    local w2De = self:isDisenchanter(self.tm_winner2)
    if w1De and not w2De then
      local tmp = self.tm_winner
      self.tm_winner = self.tm_winner2
      self.tm_winner2 = tmp
      self.tm_swapped = true
      self:writeDebugLog("TM_ROLL | SWAPPED for DE: " .. self.tm_winner2 .. " moved to last")
    end
  end

  self.tm_roll_id = currentRollId
  self:writeDebugLog(string.format("TM_ROLL | id=%s | tm1=%s | tm2=%s",
    tostring(currentRollId), tostring(self.tm_winner), tostring(self.tm_winner2)))
  return self.tm_winner, self.tm_winner2
end

-- Compute resolution plan from current bid state + popup data.
-- Returns a table describing who wins, GP cost, TM chain, DE, warnings.
function sepgp:analyzeLootResolution(data)
  local plan = {
    itemLink = data[self.loot_index.item],
    itemDisplayName = self:extractItemName(data[self.loot_index.item]),
    gpCost = data[self.loot_index.price] or 0,
    osPrice = data[self.loot_index.off_price] or 0,
    bidsMs = {},    -- sorted copies
    bidsFlex = {},
    bidsOs = {},
    bidsTm = {},
    winner = nil,   -- {name, specType, gpCost}
    tm1 = nil,      -- first TM winner (gets from ML, transmogs)
    tm2 = nil,      -- second TM winner (gets trade, optional)
    route = {},     -- array of step strings
    warnings = {},
    swapped = false,
    noDE = false,
    scenario = "",  -- description tag for debug log
  }

  -- Shallow-copy bid arrays
  for i = 1, table.getn(self.bids_main) do table.insert(plan.bidsMs, self.bids_main[i]) end
  for i = 1, table.getn(self.bids_flex) do table.insert(plan.bidsFlex, self.bids_flex[i]) end
  for i = 1, table.getn(self.bids_off) do table.insert(plan.bidsOs, self.bids_off[i]) end
  for i = 1, table.getn(self.bids_tm) do table.insert(plan.bidsTm, self.bids_tm[i]) end

  -- Sort by PR (index 5) descending
  local pr_sort = function(a, b) return (a[5] or 0) > (b[5] or 0) end
  table.sort(plan.bidsMs, pr_sort)
  table.sort(plan.bidsFlex, pr_sort)
  table.sort(plan.bidsOs, pr_sort)

  -- Determine the GP winner (MS > FLEX > OS)
  if table.getn(plan.bidsMs) > 0 then
    plan.winner = { name = plan.bidsMs[1][1], specType = "MS", gpCost = plan.gpCost, pr = plan.bidsMs[1][5] }
  elseif table.getn(plan.bidsFlex) > 0 then
    plan.winner = { name = plan.bidsFlex[1][1], specType = "FLEX", gpCost = plan.gpCost, pr = plan.bidsFlex[1][5] }
  elseif table.getn(plan.bidsOs) > 0 then
    plan.winner = { name = plan.bidsOs[1][1], specType = "OS", gpCost = plan.osPrice, pr = plan.bidsOs[1][5] }
  end

  -- 2026-04-06: Use shared rollTmWinners() for single source of truth.
  -- Previously this had its own math.random calls separate from rollAndAnnounceTM,
  -- producing inconsistent TM winner names between raid chat and officer chat.
  local tmCount = table.getn(plan.bidsTm)
  if tmCount > 0 then
    self:rollTmWinners()
    plan.tm1 = self.tm_winner
    plan.tm2 = self.tm_winner2
  end

  -- Build item route based on scenario
  if plan.winner and plan.tm1 then
    -- Scenario: MS/FLEX/OS winner + TM mule
    plan.scenario = "WINNER+TM"
    table.insert(plan.route, "1. Master loot to: " .. plan.tm1 .. " (TM - 0 GP)")
    table.insert(plan.route, "2. " .. plan.tm1 .. " transmogs, trades to " .. plan.winner.name)
    table.insert(plan.route, ">> " .. plan.winner.name .. " receives item (" .. plan.winner.specType .. " - " .. plan.winner.gpCost .. " GP)")
  elseif plan.winner and not plan.tm1 then
    -- Scenario: Direct MS/FLEX/OS winner, no TM
    plan.scenario = "WINNER_NOTM"
    table.insert(plan.route, "1. Master loot to: " .. plan.winner.name .. " (" .. plan.winner.specType .. " - " .. plan.winner.gpCost .. " GP)")
  elseif not plan.winner and plan.tm1 and plan.tm2 then
    -- Scenario: TM only, 2 bidders
    -- 2026-04-06: rollTmWinners() now does the DE-swap internally so the raid
    -- chat announcements and the officer chat post-confirm see the same order.
    -- plan.tm1 and plan.tm2 here are already in final (post-swap) order.
    plan.scenario = "TM2"
    local tm1 = plan.tm1
    local tm2 = plan.tm2
    local tm1De = self:isDisenchanter(tm1)
    local tm2De = self:isDisenchanter(tm2)
    if self.tm_swapped then
      plan.swapped = true
      table.insert(plan.warnings, "ORDER SWAPPED: " .. tm2 .. " has DE, moved to last position")
    end
    table.insert(plan.route, "1. Master loot to: " .. tm1 .. " (TM - 0 GP)")
    table.insert(plan.route, "2. " .. tm1 .. " transmogs, trades to " .. tm2)
    if tm2De then
      table.insert(plan.route, ">> " .. tm2 .. " transmogs, disenchants after [DE]")
    else
      table.insert(plan.route, ">> " .. tm2 .. " transmogs, item destroyed (no DE available)")
      plan.noDE = true
      table.insert(plan.warnings, "NO DE: No disenchanter in chain. Item will be lost.")
    end
  elseif not plan.winner and plan.tm1 and not plan.tm2 then
    -- Scenario: TM only, 1 bidder
    plan.scenario = "TM1"
    local tm1 = plan.tm1
    if self:isDisenchanter(tm1) then
      table.insert(plan.route, "1. Master loot to: " .. tm1 .. " (TM - 0 GP)")
      table.insert(plan.route, ">> " .. tm1 .. " transmogs, disenchants after [DE]")
    else
      -- Find a DE player from roster to trade to
      local dePlayer = nil
      if sepgp_de_roster then
        for name, v in pairs(sepgp_de_roster) do
          if v == true and name ~= tm1 then
            dePlayer = name
            break
          end
        end
      end
      if dePlayer then
        table.insert(plan.route, "1. Master loot to: " .. tm1 .. " (TM - 0 GP)")
        table.insert(plan.route, "2. " .. tm1 .. " transmogs, trades to " .. dePlayer .. " [DE]")
        table.insert(plan.route, ">> " .. dePlayer .. " disenchants")
        plan.dePlayer = dePlayer
      else
        table.insert(plan.route, "1. Master loot to: " .. tm1 .. " (TM - 0 GP)")
        table.insert(plan.route, ">> " .. tm1 .. " transmogs (no DE assigned)")
        plan.noDE = true
        table.insert(plan.warnings, "NO DE: No disenchanter available. Assign one via /deadd.")
      end
    end
  else
    -- Scenario: No bids at all, straight DE
    plan.scenario = "NOBIDS_DE"
    -- Find a DE player from roster
    local dePlayer = nil
    if sepgp_de_roster then
      for name, v in pairs(sepgp_de_roster) do
        if v == true then
          dePlayer = name
          break
        end
      end
    end
    if dePlayer then
      table.insert(plan.route, "1. Master loot to: " .. dePlayer .. " [DE]")
      table.insert(plan.route, ">> " .. dePlayer .. " disenchants")
      plan.dePlayer = dePlayer
    else
      table.insert(plan.route, "1. No disenchanter assigned. Click Cancel and assign one.")
      plan.noDE = true
      table.insert(plan.warnings, "NO DE: Add a disenchanter via /deadd before resolving.")
    end
  end

  return plan
end


-- Build the item's loot-data record, run analyzeLootResolution on it, and
-- resolve it immediately via ResolveLootConfirm. data only needs to carry
-- item/price info (time, item, bind, price, off_price) -- ResolveLootConfirm
-- fills in the looter name/color from the plan's actual winner once it's
-- computed, so it's always accurate even though nothing was "clicked".
function sepgp:AutoResolveLoot(data)
  if not data then return end
  if data._gp_charged then return end
  sepgp_resolution_data = data
  sepgp_resolution_plan = self:analyzeLootResolution(data)
  self:ResolveLootConfirm()
end

-- Execute the resolution: GP charge, winner announce, raid/officer chat,
-- advance queue. Uses the plan AutoResolveLoot just computed.
function sepgp:ResolveLootConfirm()
  local data = sepgp_resolution_data
  local plan = sepgp_resolution_plan
  if not data or not plan then return end
  if data._gp_charged then
    self:defaultPrint("This item has already been resolved.")
    return
  end

  -- No name was clicked to get here -- fill in the loot-history "Looter"
  -- fields from the plan's real winner (or TM mule / DE player / self as
  -- last resort) so the history entry still shows someone sensible.
  if not data[self.loot_index.player] or data[self.loot_index.player] == "" then
    local looter = (plan.winner and plan.winner.name) or plan.tm1 or plan.dePlayer or self._playerName
    local class = self:resolveLooterClass(looter)
    local color = "|cffFFFFFF" .. looter .. "|r"
    if class then
      local BC = AceLibrary("Babble-Class-2.2")
      color = "|c" .. (BC and BC:GetHexColor(class) or "ffFFFFFF") .. looter .. "|r"
    end
    data[self.loot_index.player] = looter
    data[self.loot_index.player_c] = color
  end

  local itemDisplayName = plan.itemDisplayName
  local officer = UnitName("player")

  -- Cancel bid timer
  if self:IsEventScheduled("shootyepgpBidTimeout") then
    self:CancelScheduledEvent("shootyepgpBidTimeout")
  end

  if plan.winner then
    -- Scenario: WINNER (+optional TM mule)
    local winnerName = plan.winner.name
    local specType = plan.winner.specType  -- "MS", "FLEX", or "OS"
    local specTypeFull = specType
    if specType == "MS" then specTypeFull = "Main Spec"
    elseif specType == "OS" then specTypeFull = "Off Spec"
    elseif specType == "FLEX" then specTypeFull = "Flex" end
    local gpCost = plan.winner.gpCost

    local routeInfo = nil
    if plan.tm1 then
      routeInfo = string.format("TM: %s - Route: %s(TM) -> %s(%s)", plan.tm1, plan.tm1, winnerName, specType)
    end

    -- Charge GP (writes officer note + sends [EPGP-AUDIT] to officer chat)
    self:givename_gp(winnerName, gpCost, itemDisplayName, specTypeFull, routeInfo)
    data._gp_charged = true

    -- Announce winner to /raid. Use plan.itemLink (the real |Hitem:..|h
    -- hyperlink) here, not itemDisplayName -- extractItemName() strips the
    -- |H..|h markup along with keeping the color, so itemDisplayName is
    -- colored text but not an actual clickable/hoverable item link.
    self:announceWinner(winnerName, specTypeFull, plan.itemLink or itemDisplayName, gpCost)

    -- Trade instruction if TM mule is involved
    if plan.tm1 then
      SendChatMessage(string.format("[EPGP] Transmog: %s - Trade to %s (%s, %d GP) within 10 min", plan.tm1, winnerName, specType, gpCost), "RAID")
      -- Track pending trade
      self._pendingTrades = self._pendingTrades or {}
      table.insert(self._pendingTrades, {
        from = plan.tm1, to = winnerName, item = itemDisplayName,
        time = GetTime(), specType = specType,
      })
      self:ScheduleEvent("sepgpTradeTimeout_" .. plan.tm1 .. winnerName, function()
        sepgp:defaultPrint(string.format("|cffFF0000[TRADE ALERT]|r %s has not traded %s to %s! (10 min timeout)", plan.tm1, itemDisplayName or "item", winnerName))
        sepgp:adminSay(string.format("[EPGP] TRADE TIMEOUT: %s -> %s for %s (10 min expired)", plan.tm1, winnerName, itemDisplayName or "?"))
      end, 600)
    end

    data[self.loot_index.action] = (specType == "MS" and self.VARS.msgp) or (specType == "OS" and self.VARS.osgp) or self.VARS.flexgp
    self:writeDebugLog(string.format("RESOLUTION_CONFIRM | WINNER | %s | %s | %d GP | %s | tm=%s",
      winnerName, specType, gpCost, itemDisplayName or "?", plan.tm1 or "none"))

  elseif plan.tm1 and plan.tm2 then
    -- Scenario: TM2 (two TM winners, no GP)
    data._gp_charged = true
    local tm1 = plan.tm1
    local tm2 = plan.tm2
    local tm2De = self:isDisenchanter(tm2)
    local deTag = tm2De and (" - DE: " .. tm2) or ""
    local raidMsg, auditMsg
    if tm2De then
      raidMsg = string.format("[EPGP] Transmog (0 GP): %s -> trades to %s (TM+DE)", tm1, tm2)
      auditMsg = string.format("[EPGP-AUDIT] %s: %s (0 GP) - TM: %s, %s%s - Route: %s(TM) -> %s(TM+DE)",
        officer, itemDisplayName or "?", tm1, tm2, deTag, tm1, tm2)
    else
      raidMsg = string.format("[EPGP] Transmog (0 GP): %s -> trades to %s (NO DE)", tm1, tm2)
      auditMsg = string.format("[EPGP-AUDIT] %s: %s (0 GP) - TM: %s, %s - Route: %s(TM) -> %s(TM) - NO DE",
        officer, itemDisplayName or "?", tm1, tm2, tm1, tm2)
    end
    SendChatMessage(raidMsg, "RAID")
    self:adminSay(auditMsg)
    data[self.loot_index.action] = self.VARS.tmgp
    self:writeDebugLog(string.format("RESOLUTION_CONFIRM | TM2 | tm1=%s tm2=%s de=%s swapped=%s | %s",
      tm1, tm2, tostring(tm2De), tostring(plan.swapped), itemDisplayName or "?"))

  elseif plan.tm1 and not plan.tm2 then
    -- Scenario: TM1 (one TM winner)
    data._gp_charged = true
    local tm1 = plan.tm1
    if self:isDisenchanter(tm1) then
      -- Self-DE
      SendChatMessage(string.format("[EPGP] Transmog (0 GP): %s (TM+DE)", tm1), "RAID")
      self:adminSay(string.format("[EPGP-AUDIT] %s: %s (0 GP) - TM+DE: %s", officer, itemDisplayName or "?", tm1))
      self:writeDebugLog(string.format("RESOLUTION_CONFIRM | TM1_SELFDE | %s | %s", tm1, itemDisplayName or "?"))
    elseif plan.dePlayer then
      -- Trade to DE player
      SendChatMessage(string.format("[EPGP] Transmog (0 GP): %s -> trade to %s for DE", tm1, plan.dePlayer), "RAID")
      self:adminSay(string.format("[EPGP-AUDIT] %s: %s (0 GP) - TM: %s - DE: %s - Route: %s(TM) -> %s(DE)",
        officer, itemDisplayName or "?", tm1, plan.dePlayer, tm1, plan.dePlayer))
      -- Track pending trade
      self._pendingTrades = self._pendingTrades or {}
      table.insert(self._pendingTrades, { from = tm1, to = plan.dePlayer, item = itemDisplayName, time = GetTime(), specType = "DE" })
      self:ScheduleEvent("sepgpTradeTimeout_" .. tm1 .. plan.dePlayer, function()
        sepgp:defaultPrint(string.format("|cffFF0000[TRADE ALERT]|r %s has not traded %s to %s for DE! (10 min timeout)", tm1, itemDisplayName or "item", plan.dePlayer))
        sepgp:adminSay(string.format("[EPGP] TRADE TIMEOUT: %s -> %s for DE of %s (10 min expired)", tm1, plan.dePlayer, itemDisplayName or "?"))
      end, 600)
      self:writeDebugLog(string.format("RESOLUTION_CONFIRM | TM1_DETRADE | %s -> %s | %s", tm1, plan.dePlayer, itemDisplayName or "?"))
    else
      -- No DE assigned
      SendChatMessage(string.format("[EPGP] Transmog only (0 GP) - %s", tm1), "RAID")
      self:adminSay(string.format("[EPGP-AUDIT] %s: %s (0 GP) - TM: %s (no DE assigned)", officer, itemDisplayName or "?", tm1))
      self:writeDebugLog(string.format("RESOLUTION_CONFIRM | TM1_NODE | %s | %s", tm1, itemDisplayName or "?"))
    end
    data[self.loot_index.action] = self.VARS.tmgp

  else
    -- Scenario: No bids, straight to DE (or bank)
    data._gp_charged = true
    if plan.dePlayer then
      SendChatMessage(string.format("[EPGP] No bids - Bank/DE: %s", plan.dePlayer), "RAID")
      self:adminSay(string.format("[EPGP-AUDIT] %s: %s -> DE (%s)", officer, itemDisplayName or "?", plan.dePlayer))
      self:writeDebugLog(string.format("RESOLUTION_CONFIRM | NOBIDS_DE | %s | %s", plan.dePlayer, itemDisplayName or "?"))
    else
      self:adminSay(string.format("[EPGP-AUDIT] %s: %s -> Bank (no bids, no DE)", officer, itemDisplayName or "?"))
      self:writeDebugLog(string.format("RESOLUTION_CONFIRM | NOBIDS_BANK | %s", itemDisplayName or "?"))
    end
    data[self.loot_index.action] = self.VARS.bankde
  end

  -- Clear bids and advance queue
  self:clearBidsQuiet()
  self:refreshPRTablets()
  local update = data[self.loot_index.update] ~= nil
  -- 2026-04-07 v4.23: Trace log immediately before addOrUpdateLoot so we
  -- can verify the flow reaches this point if loot history comes up empty.
  self:writeDebugLog(string.format("RESOLUTION_CONFIRM_INSERT | %s | action=%s | sepgp_looted size before=%d",
    data[self.loot_index.item] or "?",
    tostring(data[self.loot_index.action] or "?"),
    table.getn(sepgp_looted or {})))
  self:addOrUpdateLoot(data, update)
  self:writeDebugLog(string.format("RESOLUTION_CONFIRM_INSERTED | %s | sepgp_looted size after=%d",
    data[self.loot_index.item] or "?",
    table.getn(sepgp_looted or {})))
  sepgp_resolution_data = nil
  sepgp_resolution_plan = nil
  self:advanceLootQueue()
  sepgp_loot:Refresh()
end

----------------
-- Loot Tracker
----------------
-- /script DEFAULT_CHAT_FRAME:AddMessage("\124cffa335ee\124Hitem:16864:0:0:0:0:0:0:0:0\124h[Belt of Might]\124h\124r");
-- test: "You receive loot: \124cffa335ee\124Hitem:16866:0:0:0\124h[Helm of Might]\124h\124r."
-- test: /run sepgp:captureLoot("Raerlas receives loot: \124cffa335ee\124Hitem:16846:0:0:0\124h[Giantstalker's Helmet]\124h\124r.")
-- test: /run sepgp:captureLoot("You receive loot: \124cffa335ee\124Hitem:16864:0:0:0\124h[Belt of Might]\124h\124r.")
sepgp.loot_index = {
  time=1,
  player=2,
  player_c=3,
  item=4,
  bind=5,
  price=6,
  off_price=7,
  action=8,
  update=9
}
function sepgp:captureLoot(message)
  if not (UnitInRaid("player") and self:lootMaster() and admin()) then return end
  local who,what,amount,player,itemLink
  who,what,amount = DF:Deformat(message,LOOT_ITEM_MULTIPLE)
  if (amount) then -- skip multiples / stacks
  else
    player, itemLink = DF:Deformat(message,LOOT_ITEM)
  end
  who,what,amount = YOU, DF:Deformat(message,LOOT_ITEM_SELF_MULTIPLE)
  if (amount) then -- skip multiples / stacks
  else
    if not (player and itemLink) then
      player, itemLink = YOU, DF:Deformat(message,LOOT_ITEM_SELF)
    end
  end
  if not (player and itemLink) then return end
  self:processLoot(player,itemLink,"chat")
end

function sepgp:GiveMasterLoot(slot, index)
  if LootSlotIsItem(slot) then
    local texture, itemname, quantity, quality = GetLootSlotInfo(slot)
    if quantity == 1 and quality >= 3 then -- not a stack and rare or higher
      local itemLink = GetLootSlotLink(slot)
      local player = GetMasterLootCandidate(index)
      if not (player and itemLink) then return end
      self:processLoot(player,itemLink,"masterloot")
    end
  end
end

function sepgp:findLootReminder(itemLink)
  for i,data in ipairs(sepgp_looted) do
    if data[self.loot_index.item] == itemLink and data[self.loot_index.action] == self.VARS.reminder then
      return data
    end
  end
end

function sepgp:tradeLoot(playerState,targetState)
  if not (UnitInRaid("player") and self:lootMaster() and admin()) then return end
  if (playerState ~= nil and targetState ~= nil) and playerState == 1 and targetState == 1 then
    local itemLink
    for id=1,MAX_TRADABLE_ITEMS do
      itemLink = GetTradePlayerItemLink(id)
      if (itemLink) then
        break  
      end
    end
    if (itemLink) then
      local link_found, _, itemColor, itemString, itemName = string.find(itemLink, "^(|c%x+)|H(.+)|h(%[.+%])")
      if (link_found) then
        local price = sepgp_prices:GetPrice(itemString,sepgp_progress)
        if not (price) or price == 0 then
          return
        end
        local bind = self:itemBinding(itemString)
        if (not bind) or (bind ~= self.VARS.boe) then return end
        if UnitExists("target") and UnitIsPlayer("target") and UnitCanCooperate("player","target") and (not UnitIsUnit("player","target")) then
          local tradeTarget = UnitName("target")
          local class = self:resolveLooterClass(tradeTarget)
          if not (class) then return end
          local target_color = C:Colorize(BC:GetHexColor(class),tradeTarget)
          local timestamp = date("%b/%d %H:%M:%S")
          local data = self:findLootReminder(itemLink)
          if (data) then
            data[self.loot_index.time] = timestamp
            data[self.loot_index.player] = tradeTarget
            data[self.loot_index.player_c] = target_color
            data[self.loot_index.update] = 1
            local dialog = StaticPopup_Show("SHOOTY_EPGP_AUTO_GEARPOINTS",data[self.loot_index.player_c],data[self.loot_index.item],data)
            if (dialog) then
              dialog.data = data
      sepgp:setupPopupTooltip(dialog)
            end
          end
        end
      end
    end
  end
end

sepgp.item_bind_patterns = {
  CRAFT = "("..ITEM_SPELL_TRIGGER_ONUSE..")",
  BOP = "("..ITEM_BIND_ON_PICKUP..")",
  QUEST = "("..ITEM_BIND_QUEST..")",
  BOU = "("..ITEM_BIND_ON_EQUIP..")",
  BOE = "("..ITEM_BIND_ON_USE..")"
}
function sepgp:itemBinding(item)
  G:SetHyperlink(item)
  if G:Find(self.item_bind_patterns.CRAFT,2,4,nil,true) then
  else
    if G:Find(self.item_bind_patterns.BOP,2,4,nil,true) then
      return sepgp.VARS.bop
    elseif G:Find(self.item_bind_patterns.QUEST,2,4,nil,true) then
      return sepgp.VARS.bop
    elseif G:Find(self.item_bind_patterns.BOE,2,4,nil,true) then
      return sepgp.VARS.boe
    elseif G:Find(self.item_bind_patterns.BOU,2,4,nil,true) then
      return sepgp.VARS.boe
    else
      return sepgp.VARS.nobind
    end
  end
  return
end

function sepgp:addOrUpdateLoot(data,update)
  if not (update) then
    table.insert(sepgp_looted,data)
  end
end

function sepgp:testLootPrompt()
  raidStatus = UnitInRaid("player") and true or false
  if lastRaidStatus == nil then
    lastRaidStatus = raidStatus
  end
  if (raidStatus == false) and (lastRaidStatus == true) then
    local hasLoot = table.getn(sepgp_looted)
    local dialog = StaticPopup_FindVisible("SHOOTY_EPGP_CLEAR_LOOT")
    if (not (dialog)) and (hasLoot > 0) then
      StaticPopup_Show("SHOOTY_EPGP_CLEAR_LOOT",hasLoot)
    end
  end
  lastRaidStatus = raidStatus
end

------------
-- Logging
------------
function sepgp:addToLog(line,skipTime)
  local over = table.getn(sepgp_log)-sepgp.VARS.maxloglines+1
  if over > 0 then
    for i=1,over do
      table.remove(sepgp_log,1)
    end
  end
  local timestamp
  if (skipTime) then
    timestamp = ""
  else
    timestamp = date("%b/%d %H:%M:%S")
  end
  table.insert(sepgp_log,{timestamp,line})
end

------------
-- Utility 
------------
function sepgp:num_round(i)
  return math.floor(i+0.5)
end

function sepgp:strsplit(delimiter, subject)
  local delimiter, fields = delimiter or ":", {}
  local pattern = string.format("([^%s]+)", delimiter)
  string.gsub(subject, pattern, function(c) fields[table.getn(fields)+1] = c end)
  return unpack(fields)
end

function sepgp:processLootDupe(player,itemName,source)
  local now = GetTime()
  local player_name = player == YOU and self._playerName or player
  local player_item = string.format("%s%s",player_name,itemName)
  if ((self._lastPlayerItem) and self._lastPlayerItem == player_item)
  and ((self._lastPlayerItemTime) and (now - self._lastPlayerItemTime) < 3)
  and ((self._lastPlayerItemSource) and self._lastPlayerItemSource ~= source) then
    return true, player_item, now
  end
  return false, player_item, now
end

function sepgp:processLoot(player,itemLink,source)
  local link_found, _, itemColor, itemString, itemName = string.find(itemLink, "^(|c%x+)|H(.+)|h(%[.+%])")
  if link_found then
    -- 2026-04-06 v4.22: skip queueing if a popup was already shown for
    -- this exact item link via the bid window winner click within the
    -- last 60 seconds. Prevents the loot capture chain from creating a
    -- duplicate popup when the officer assigns the loot via WoW's
    -- master loot UI after already triggering the popup from bids.
    if self._popupShownLinks and self._popupShownLinks[itemLink] then
      local age = GetTime() - self._popupShownLinks[itemLink]
      if age < 60 then
        self:writeDebugLog(string.format("PROCESS_LOOT_SKIP_DUPE | %s | already shown via bid window %.1fs ago", itemLink, age))
        return
      end
    end
    local dupe, player_item, now = self:processLootDupe(player,itemName,source)
    if dupe then
      return
    end
    local bind = self:itemBinding(itemString)
    if not (bind) then return end
    local price = sepgp_prices:GetPrice(itemString,sepgp_progress)
    if (not (price)) or (price == 0) then
      return
    end
    local class,_
    if player == YOU then player = self._playerName end
    if player == self._playerName then 
      class = UnitClass("player") -- localized
    else
      class = self:resolveLooterClass(player) -- localized
    end
    if not (class) then return end
    self._lastPlayerItem, self._lastPlayerItemTime, self._lastPlayerItemSource = player_item, now, source
    -- Ensure bid_item is populated so the bid window path can find the price
    if not sepgp.bid_item then sepgp.bid_item = {} end
    if not sepgp.bid_item.link then
      sepgp.bid_item.link = itemString
      sepgp.bid_item.linkFull = itemLink
      sepgp.bid_item.name = string.format("%s%s|r", itemColor, itemName)
    end
    -- Always store/update the price on bid_item
    sepgp.bid_item.price = price
    sepgp.bid_item.off_price = math.floor(price * sepgp_discount)
    local player_color = C:Colorize(BC:GetHexColor(class),player)
    local off_price = math.floor(price*sepgp_discount)
    local quality = hexColorQuality[itemColor] or -1
    local timestamp = date("%b/%d %H:%M:%S")
    local data = {[self.loot_index.time]=timestamp,[self.loot_index.player]=player,[self.loot_index.player_c]=player_color,[self.loot_index.item]=itemLink,[self.loot_index.bind]=bind,[self.loot_index.price]=price,[self.loot_index.off_price]=off_price}
    self:writeDebugLog(string.format("PROCESS_LOOT | %s | %s | price=%s | os=%s | source=%s", player, itemLink or "?", tostring(price), tostring(off_price), source or "?"))
    -- Phase 2: Queue loot instead of showing popup immediately.
    -- Each item gets its own self-contained data entry. No globals overwritten.
    self:queueLootPopup(data)
  end
end

----------------------------------------------
-- Phase 2: Loot Queue System
----------------------------------------------
-- FIFO queue for loot popups. Each item's data is self-contained.
-- Popups process one at a time. Next popup shows when current is resolved.
sepgp._lootQueue = {}
sepgp._lootQueueActive = false

function sepgp:queueLootPopup(data)
  table.insert(self._lootQueue, data)
  self:writeDebugLog(string.format("QUEUE_ADD | %s | %s | queue_size=%d", data[self.loot_index.player], data[self.loot_index.item] or "?", table.getn(self._lootQueue)))
  -- If no popup is currently active, show the first queued item
  if not self._lootQueueActive then
    self:showNextLootPopup()
  end
end

function sepgp:showNextLootPopup()
  if table.getn(self._lootQueue) == 0 then
    self._lootQueueActive = false
    return
  end
  local data = self._lootQueue[1]
  table.remove(self._lootQueue, 1)
  self._lootQueueActive = true
  self:writeDebugLog(string.format("QUEUE_SHOW | %s | %s | remaining=%d", data[self.loot_index.player], data[self.loot_index.item] or "?", table.getn(self._lootQueue)))
  -- Phase 4: Auto-resolve immediately, no popup. Fall back to the legacy
  -- StaticPopup only if that compatibility flag is explicitly set.
  if sepgp_useLegacyPopup then
    local dialog = StaticPopup_Show("SHOOTY_EPGP_AUTO_GEARPOINTS", data[self.loot_index.player_c], data[self.loot_index.item], data)
    if dialog then
      dialog.data = data
      sepgp:setupPopupTooltip(dialog)
    end
  else
    self:AutoResolveLoot(data)
  end
end

-- Called after any resolution (auto or legacy popup) to advance the queue.
-- Idempotent -- cancels any existing pending schedule before scheduling a
-- new one, so calling it more than once for the same item is harmless.
function sepgp:advanceLootQueue()
  self._lootQueueActive = false
  if self:IsEventScheduled("sepgpLootQueueNext") then
    self:CancelScheduledEvent("sepgpLootQueueNext")
  end
  if table.getn(self._lootQueue) > 0 then
    -- Small delay so the previous popup fully closes before the next opens
    self:ScheduleEvent("sepgpLootQueueNext", self.showNextLootPopup, 0.3, self)
  end
end

function sepgp:verifyGuildMember(name,silent)
  for i=1,GetNumGuildMembers(1) do
    local g_name, g_rank, g_rankIndex, g_level, g_class, g_zone, g_note, g_officernote, g_online = GetGuildRosterInfo(i)
    if (string.lower(name) == string.lower(g_name)) and (tonumber(g_level) >= sepgp.VARS.minlevel) then 
    -- == MAX_PLAYER_LEVEL]]
      return g_name, g_class, g_rank, g_officernote
    end
  end
  if (name) and name ~= "" and not (silent) then
    self:defaultPrint(string.format(L["%s not found in the guild or not max level!"],name))
  end
  return
end

function sepgp:inRaid(name)
  for i=1,GetNumRaidMembers() do
    if name == (UnitName(raidUnit[i])) then
      return true
    end
  end
  return false
end

function sepgp:lootMaster()
  local method, lootmasterID = GetLootMethod()
  if method == "master" and lootmasterID == 0 then
    return true
  else
    return false
  end
end

function sepgp:testMain()
  if (sepgp_main == nil) or (sepgp_main == "") then
    if (IsInGuild()) then
      StaticPopup_Show("SHOOTY_EPGP_SET_MAIN")
    end
  end
end

function sepgp:make_escable(framename,operation)
  local found
  for i,f in ipairs(UISpecialFrames) do
    if f==framename then
      found = i
    end
  end
  if not found and operation=="add" then
    table.insert(UISpecialFrames,framename)
  elseif found and operation=="remove" then
    table.remove(UISpecialFrames,found)
  end
end

local raidZones = {[L["Molten Core"]]="T1",[L["Onyxia\'s Lair"]]="T1.5",[L["Blackwing Lair"]]="T2",[L["Ahn\'Qiraj"]]="T2.5",[L["Naxxramas"]]="T3"}
local zone_multipliers = {
  ["T3"] =   {["T3"]=1,["T2.5"]=0.75,["T2"]=0.5,["T1.5"]=0.25,["T1"]=0.25},
  ["T2.5"] = {["T3"]=1,["T2.5"]=1,   ["T2"]=0.7,["T1.5"]=0.4, ["T1"]=0.4},
  ["T2"] =   {["T3"]=1,["T2.5"]=1,   ["T2"]=1,  ["T1.5"]=0.5, ["T1"]=0.5},
  ["T1"] =   {["T3"]=1,["T2.5"]=1,   ["T2"]=1,  ["T1.5"]=1,   ["T1"]=1}
}
function sepgp:suggestedAwardEP()
  local currentTier, zoneEN, zoneLoc, checkTier, multiplier
  local inInstance, instanceType = IsInInstance()
  if (inInstance == nil) or (instanceType ~= nil and instanceType == "none") then
    currentTier = "T1.5"   
  end
  if (inInstance) and (instanceType == "raid") then
    zoneLoc = GetRealZoneText()
    if (BZ:HasReverseTranslation(zoneLoc)) then
      zoneEN = BZ:GetReverseTranslation(zoneLoc)
      checkTier = raidZones[zoneEN]
      if (checkTier) then
        currentTier = checkTier
      end
    end
  end
  if not currentTier then 
    return sepgp.VARS.baseaward_ep
  else
    multiplier = zone_multipliers[sepgp_progress][currentTier]
  end
  if (multiplier) then
    return multiplier*sepgp.VARS.baseaward_ep
  else
    return sepgp.VARS.baseaward_ep
  end
end

function sepgp:parseVersion(version,otherVersion)
  if not sepgp._version then sepgp._version = {} end
  for major,minor,patch in string.gfind(version,"(%d+)[^%d]?(%d*)[^%d]?(%d*)") do
    sepgp._version.major = tonumber(major)
    sepgp._version.minor = tonumber(minor)
    sepgp._version.patch = tonumber(patch)
  end
  if (otherVersion) then
    if not sepgp._otherversion then sepgp._otherversion = {} end
    for major,minor,patch in string.gfind(otherVersion,"(%d+)[^%d]?(%d*)[^%d]?(%d*)") do
      sepgp._otherversion.major = tonumber(major)
      sepgp._otherversion.minor = tonumber(minor)
      sepgp._otherversion.patch = tonumber(patch)      
    end
    if (sepgp._otherversion.major ~= nil and sepgp._version.major ~= nil) then
      if (sepgp._otherversion.major < sepgp._version.major) then -- we are newer
        return
      elseif (sepgp._otherversion.major > sepgp._version.major) then -- they are newer
        return true, "major"        
      else -- tied on major, go minor
        if (sepgp._otherversion.minor ~= nil and sepgp._version.minor ~= nil) then
          if (sepgp._otherversion.minor < sepgp._version.minor) then -- we are newer
            return
          elseif (sepgp._otherversion.minor > sepgp._version.minor) then -- they are newer
            return true, "minor"
          else -- tied on minor, go patch
            if (sepgp._otherversion.patch ~= nil and sepgp._version.patch ~= nil) then
              if (sepgp._otherversion.patch < sepgp._version.patch) then -- we are newer
                return
              elseif (sepgp._otherversion.patch > sepgp._version.patch) then -- they are newwer
                return true, "patch"
              end
            elseif (sepgp._otherversion.patch ~= nil and sepgp._version.patch == nil) then -- they are newer
              return true, "patch"
            end
          end    
        elseif (sepgp._otherversion.minor ~= nil and sepgp._version.minor == nil) then -- they are newer
          return true, "minor"
        end
      end
    end
  end
end

function sepgp:camelCase(word)
  return string.gsub(word,"(%a)([%w_']*)",function(head,tail) 
    return string.format("%s%s",string.upper(head),string.lower(tail)) 
    end)
end

admin = function()
  return (CanEditOfficerNote() --[[and CanEditPublicNote()]])
end

sanitizeNote = function(prefix,epgp,postfix)
  -- reserve 12 chars for the epgp pattern {xxxxx:yyyy} max public/officernote = 31
  local remainder = string.format("%s%s",prefix,postfix)
  local clip = math.min(31-12,string.len(remainder))
  local prepend = string.sub(remainder,1,clip)
  return string.format("%s%s",prepend,epgp)
end

-------------
-- Dialogs
-------------
StaticPopupDialogs["SHOOTY_EPGP_CLEAR_LOOT"] = {
  text = L["There are %d loot drops stored. It is recommended to clear loot info before a new raid. Do you want to clear it now?"],
  button1 = TEXT(YES),
  button2 = L["Show me"],
  OnAccept = function()
    sepgp_looted = {}
    sepgp:defaultPrint(L["Loot info cleared"])
  end,
  OnCancel = function(_,reason)
    if reason == "clicked" then
      sepgp_loot:Toggle(true)
      sepgp:defaultPrint(L["Loot info can be cleared at any time from the Tablet context menu or '/bowepgp clearloot' command"])
    end
  end,
  timeout = 0,
  whileDead = 1,
  exclusive = 0,
  hideOnEscape = 1
}
StaticPopupDialogs["SHOOTY_EPGP_SET_MAIN"] = {
  text = L["Set your main to be able to participate in Reserve List EPGP Checks."],
  button1 = TEXT(ACCEPT),
  button2 = TEXT(CANCEL),
  hasEditBox = 1,
  maxLetters = 12,
  OnAccept = function()
    local editBox = getglobal(this:GetParent():GetName().."EditBox")
    local name = sepgp:camelCase(editBox:GetText())
    sepgp_main = sepgp:verifyGuildMember(name)
  end,
  OnShow = function()
    getglobal(this:GetName().."EditBox"):SetText(sepgp_main or "")
    getglobal(this:GetName().."EditBox"):SetFocus()
  end,
  OnHide = function()
    if ( ChatFrameEditBox:IsVisible() ) then
      ChatFrameEditBox:SetFocus()
    end
    getglobal(this:GetName().."EditBox"):SetText("")
  end,
  EditBoxOnEnterPressed = function()
    local editBox = getglobal(this:GetParent():GetName().."EditBox")
    sepgp_main = sepgp:verifyGuildMember(editBox:GetText())
    this:GetParent():Hide()
  end,
  EditBoxOnEscapePressed = function()
    this:GetParent():Hide()
  end,
  timeout = 0,
  exclusive = 1,
  whileDead = 1,
  hideOnEscape = 1  
}
StaticPopupDialogs["SHOOTY_EPGP_RESERVE_AFKCHECK_RESPONCE"] = {
  text = " ",
  button1 = TEXT(YES),
  button2 = TEXT(NO),
  OnShow = function()
    this._timeout = sepgp.VARS.timeout-1
  end,
  OnUpdate = function(elapsed,dialog)
    this._timeout = this._timeout - elapsed
    getglobal(dialog:GetName().."Text"):SetText(string.format(L["Reserves AFKCheck. Are you available? |cff00ff00%0d|rsec."],this._timeout))
    if (this._timeout<=0) then
      this._timeout = 0
      dialog:Hide()
    end
  end,
  OnAccept = function()
    this._timeout = 0
    sepgp:sendReserverResponce()
  end,
  timeout = 0,--sepgp.VARS.timeout,
  exclusive = 1,
  showAlert = 1,
  whileDead = 1,
  hideOnEscape = 1  
}
StaticPopupDialogs["SHOOTY_EPGP_CONFIRM_RESET"] = {
  text = L["|cffff0000Are you sure you want to Reset ALL EPGP?|r"],
  button1 = TEXT(OKAY),
  button2 = TEXT(CANCEL),
  OnAccept = function()
    sepgp:gp_reset_v3()
  end,
  timeout = 0,
  whileDead = 1,
  exclusive = 1,
  showAlert = 1,
  hideOnEscape = 1
}

-- 2026-04-02: Guard flag prevents double-click on loot popup menu items.
-- WHY: The loot popup is the SOLE place where GP is charged (bid window only
--   announces winners). Each popup's data table carries a _gp_charged flag
--   to prevent double-charging. Set AFTER GP is applied so errors before
--   that point allow retry. Per-data flag means reopening the menu or
--   erroring in a later step (announceWinner, SendChatMessage) never blocks
--   subsequent clicks.

local sepgp_auto_gp_menu = {
  --{text = "Choose an Action", isTitle = true},
  {text = L["Add MainSpec GP"], func = function()
    local dialog = StaticPopup_FindVisible("SHOOTY_EPGP_AUTO_GEARPOINTS")
    if not dialog or not dialog.data then return end
    local data = dialog.data
    sepgp:writeDebugLog("MS_CLICK | charged=" .. tostring(data._gp_charged) .. " | admin=" .. tostring(admin()))
    if data._gp_charged then return end
    if (dialog) then
      local price = data[sepgp.loot_index.price]
      -- If MS bids exist, charge the top MS bidder (not the looter/TM holder)
      local actual_name
      if table.getn(sepgp.bids_main) > 0 then
        table.sort(sepgp.bids_main, function(a,b) return a[5] > b[5] end)
        actual_name = sepgp.bids_main[1][1]
      else
        local player = data[sepgp.loot_index.player]
        actual_name = (player==YOU and sepgp._playerName or player)
      end
      local itemLink = data[sepgp.loot_index.item]
      local itemDisplayName = sepgp:extractItemName(itemLink)
      -- Build routeInfo if TM bids exist (paper trail for officer chat)
      -- 2026-04-06: Use shared rollTmWinners() helper instead of inline math.random
      local routeInfo = nil
      if table.getn(sepgp.bids_tm) > 0 then
        sepgp:rollTmWinners()
        local tm_name = sepgp.tm_winner
        routeInfo = string.format("TM: %s - Route: %s(TM) -> %s(MS)", tm_name, tm_name, actual_name)
      end
      sepgp:givename_gp(actual_name, price, itemDisplayName, "MS", routeInfo)
      data._gp_charged = true
      -- Cancel the 5-min bid timeout so it doesn't re-announce all bids
      if sepgp:IsEventScheduled("shootyepgpBidTimeout") then
        sepgp:CancelScheduledEvent("shootyepgpBidTimeout")
      end
      -- Announce winner to /raid with the real item link (clickable/hoverable),
      -- not itemDisplayName -- extractItemName() strips the |H..|h hyperlink
      -- markup, leaving colored text that isn't an actual item link.
      sepgp:announceWinner(actual_name, "MS", itemLink, price)
      -- Clear bids without re-announcing (bids resolved)
      sepgp:clearBidsQuiet()
      sepgp:refreshPRTablets()
      data[sepgp.loot_index.action] = sepgp.VARS.msgp
      local update = data[sepgp.loot_index.update] ~= nil
      sepgp:addOrUpdateLoot(data,update)
      StaticPopup_Hide("SHOOTY_EPGP_AUTO_GEARPOINTS")
      sepgp:advanceLootQueue()
      sepgp_loot:Refresh()
      sepgp:writeDebugLog(string.format("POPUP_ACTION | MS | %s | %d GP | %s | %s", actual_name, price, itemDisplayName or "?", routeInfo or "no TM"))
    end
  end},
  {text = L["Add OffSpec GP"], func = function()
    local dialog = StaticPopup_FindVisible("SHOOTY_EPGP_AUTO_GEARPOINTS")
    if not dialog or not dialog.data then return end
    local data = dialog.data
    if data._gp_charged then return end
    if (dialog) then
      local off_price = data[sepgp.loot_index.off_price]
      -- If OS bids exist, charge the top OS bidder (not the looter/TM holder)
      local actual_name
      if table.getn(sepgp.bids_off) > 0 then
        table.sort(sepgp.bids_off, function(a,b) return a[5] > b[5] end)
        actual_name = sepgp.bids_off[1][1]
      elseif table.getn(sepgp.bids_flex) > 0 then
        table.sort(sepgp.bids_flex, function(a,b) return a[5] > b[5] end)
        actual_name = sepgp.bids_flex[1][1]
      else
        local player = data[sepgp.loot_index.player]
        actual_name = (player==YOU and sepgp._playerName or player)
      end
      local itemLink = data[sepgp.loot_index.item]
      local itemDisplayName = sepgp:extractItemName(itemLink)
      -- Build routeInfo if TM bids exist (paper trail for officer chat)
      -- 2026-04-06: Use shared rollTmWinners() helper instead of inline math.random
      local routeInfo = nil
      if table.getn(sepgp.bids_tm) > 0 then
        sepgp:rollTmWinners()
        local tm_name = sepgp.tm_winner
        routeInfo = string.format("TM: %s - Route: %s(TM) -> %s(OS)", tm_name, tm_name, actual_name)
      end
      sepgp:givename_gp(actual_name, off_price, itemDisplayName, "OS", routeInfo)
      data._gp_charged = true
      -- Cancel the 5-min bid timeout so it doesn't re-announce all bids
      if sepgp:IsEventScheduled("shootyepgpBidTimeout") then
        sepgp:CancelScheduledEvent("shootyepgpBidTimeout")
      end
      -- Announce winner to /raid with the real item link (clickable/hoverable),
      -- not itemDisplayName -- extractItemName() strips the |H..|h hyperlink
      -- markup, leaving colored text that isn't an actual item link.
      sepgp:announceWinner(actual_name, "OS", itemLink, off_price)
      -- Clear bids without re-announcing (bids resolved)
      sepgp:clearBidsQuiet()
      sepgp:refreshPRTablets()
      data[sepgp.loot_index.action] = sepgp.VARS.osgp
      local update = data[sepgp.loot_index.update] ~= nil
      sepgp:addOrUpdateLoot(data,update)
      StaticPopup_Hide("SHOOTY_EPGP_AUTO_GEARPOINTS")
      sepgp:advanceLootQueue()
      sepgp_loot:Refresh()
      sepgp:writeDebugLog(string.format("POPUP_ACTION | OS | %s | %d GP | %s | %s", actual_name, off_price, itemDisplayName or "?", routeInfo or "no TM"))
    end
  end},
  {text = "Transmog (0 GP)", func = function()
    local dialog = StaticPopup_FindVisible("SHOOTY_EPGP_AUTO_GEARPOINTS")
    if not dialog or not dialog.data then return end
    local data = dialog.data
    if data._gp_charged then return end
    if (dialog) then
      -- Transmog: the loot holder is NOT the real winner.
      -- If there's an MS/FLEX/OS winner, charge THEM the GP.
      -- The transmog holder (who looted the item) pays 0 GP.
      local tm_holder = data[sepgp.loot_index.player]
      if tm_holder == YOU then tm_holder = sepgp._playerName end

      -- Find the MS/FLEX/OS winner (highest priority bidder)
      local real_winner = nil
      local spec_type = nil
      local gp_cost = 0
      if table.getn(sepgp.bids_main) > 0 then
        table.sort(sepgp.bids_main, function(a,b) return a[5] > b[5] end)
        real_winner = sepgp.bids_main[1][1]
        spec_type = "Main Spec"
        gp_cost = data[sepgp.loot_index.price] or 0
      elseif table.getn(sepgp.bids_flex) > 0 then
        table.sort(sepgp.bids_flex, function(a,b) return a[5] > b[5] end)
        real_winner = sepgp.bids_flex[1][1]
        spec_type = "Flex"
        gp_cost = data[sepgp.loot_index.price] or 0
      elseif table.getn(sepgp.bids_off) > 0 then
        table.sort(sepgp.bids_off, function(a,b) return a[5] > b[5] end)
        real_winner = sepgp.bids_off[1][1]
        spec_type = "Off Spec"
        gp_cost = data[sepgp.loot_index.off_price] or 0
      end

      local itemLink = data[sepgp.loot_index.item]
      local itemDisplayName = sepgp:extractItemName(itemLink)

      if real_winner and gp_cost > 0 then
        -- Phase 3: Build route string for enhanced officer chat
        local routeInfo = string.format("TM: %s - Route: %s(TM) -> %s(%s)", tm_holder, tm_holder, real_winner, spec_type)
        sepgp:givename_gp(real_winner, gp_cost, itemDisplayName, spec_type, routeInfo)
        data._gp_charged = true
        -- Announce with the real item link (clickable/hoverable), not
        -- itemDisplayName -- extractItemName() strips the |H..|h hyperlink
        -- markup, leaving colored text that isn't an actual item link.
        sepgp:announceWinner(real_winner, spec_type, itemLink, gp_cost)
        -- Use dash instead of pipe to avoid ChatThrottleLib "invalid escape code" from aux-addons
        SendChatMessage(string.format("[EPGP] Transmog: %s - Trade to %s (%s, %d GP) within 10 min", tm_holder, real_winner, spec_type, gp_cost), "RAID")
        sepgp:writeDebugLog(string.format("TM_RAID_MSG | holder=%s winner=%s spec=%s gp=%d", tm_holder, real_winner, spec_type, gp_cost))
        -- Phase 5: Track pending trade
        sepgp._pendingTrades = sepgp._pendingTrades or {}
        table.insert(sepgp._pendingTrades, {
          from = tm_holder,
          to = real_winner,
          item = itemDisplayName,
          time = GetTime(),
          specType = spec_type,
        })
        -- Schedule 10-minute trade timeout alert
        sepgp:ScheduleEvent("sepgpTradeTimeout_" .. tm_holder .. real_winner, function()
          sepgp:defaultPrint(string.format("|cffFF0000[TRADE ALERT]|r %s has not traded %s to %s! (10 min timeout)", tm_holder, itemDisplayName or "item", real_winner))
          sepgp:adminSay(string.format("[EPGP] TRADE TIMEOUT: %s -> %s for %s (10 min expired)", tm_holder, real_winner, itemDisplayName or "?"))
          sepgp:writeDebugLog(string.format("TRADE_TIMEOUT | %s -> %s | %s", tm_holder, real_winner, itemDisplayName or "?"))
        end, 600)
        sepgp:writeDebugLog(string.format("POPUP_ACTION | TM+%s | holder=%s | winner=%s | %d GP | %s | %s", spec_type, tm_holder, real_winner, gp_cost, itemDisplayName or "?", routeInfo))
      else
        -- TM only (no MS/FLEX/OS bids). Handle all TM+DE scenarios.
        data._gp_charged = true
        local tm_count = table.getn(sepgp.bids_tm)

        if tm_count >= 2 and sepgp.tm_winner2 then
          -- 2+ TM bidders: TM#1 transmogs, trades to TM#2
          local tm1 = sepgp.tm_winner or tm_holder
          local tm2_name = sepgp.tm_winner2

          -- Check DE capability and swap if needed
          local tm1_de = sepgp:isDisenchanter(tm1)
          local tm2_de = sepgp:isDisenchanter(tm2_name)
          local swapped = false
          if tm1_de and not tm2_de then
            -- Swap: DE-capable player should be last in chain
            tm1, tm2_name = tm2_name, tm1
            tm1_de, tm2_de = tm2_de, tm1_de
            swapped = true
          end

          local deTag = ""
          local raidMsg
          local auditMsg
          if tm2_de then
            deTag = string.format(" - DE: %s", tm2_name)
            raidMsg = string.format("[EPGP] Transmog (0 GP): %s -> trades to %s (TM+DE)", tm1, tm2_name)
            auditMsg = string.format("[EPGP-AUDIT] %s: %s (0 GP) - TM: %s, %s%s - Route: %s(TM) -> %s(TM+DE)", UnitName("player"), itemDisplayName or "?", tm1, tm2_name, deTag, tm1, tm2_name)
          elseif tm1_de then
            -- shouldn't happen after swap, but safety
            deTag = string.format(" - DE: %s", tm1)
            raidMsg = string.format("[EPGP] Transmog (0 GP): %s (TM+DE) -> trades to %s", tm1, tm2_name)
            auditMsg = string.format("[EPGP-AUDIT] %s: %s (0 GP) - TM: %s, %s%s - Route: %s(TM+DE) -> %s(TM)", UnitName("player"), itemDisplayName or "?", tm1, tm2_name, deTag, tm1, tm2_name)
          else
            -- Neither can DE
            raidMsg = string.format("[EPGP] Transmog (0 GP): %s -> trades to %s (NO DE available)", tm1, tm2_name)
            auditMsg = string.format("[EPGP-AUDIT] %s: %s (0 GP) - TM: %s, %s - Route: %s(TM) -> %s(TM) - NO DE", UnitName("player"), itemDisplayName or "?", tm1, tm2_name, tm1, tm2_name)
            sepgp:defaultPrint("|cffFF0000[WARNING]|r No disenchanter in TM chain for " .. (itemDisplayName or "item"))
          end
          if swapped then
            sepgp:defaultPrint(string.format("|cffFFFF00[SWAP]|r TM order swapped: %s has DE, moved to last position", tm2_name))
          end
          SendChatMessage(raidMsg, "RAID")
          sepgp:adminSay(auditMsg)
          sepgp:writeDebugLog(string.format("POPUP_ACTION | TM_ONLY_2 | tm1=%s | tm2=%s | de=%s | swapped=%s | %s", tm1, tm2_name, tostring(tm2_de or tm1_de), tostring(swapped), itemDisplayName or "?"))

        elseif tm_count == 1 or tm_holder then
          -- 1 TM bidder
          local tm_name = tm_holder
          local tm_is_de = sepgp:isDisenchanter(tm_name)

          if tm_is_de then
            -- Self-DE: TM winner transmogs and disenchants
            SendChatMessage(string.format("[EPGP] Transmog (0 GP): %s (TM+DE)", tm_name), "RAID")
            sepgp:adminSay(string.format("[EPGP-AUDIT] %s: %s (0 GP) - TM+DE: %s", UnitName("player"), itemDisplayName or "?", tm_name))
          else
            -- Find a DE player from roster to trade to
            local de_player = nil
            if sepgp_de_roster then
              for name, v in pairs(sepgp_de_roster) do
                if v == true and name ~= tm_name then
                  de_player = name
                  break
                end
              end
            end
            if de_player then
              SendChatMessage(string.format("[EPGP] Transmog (0 GP): %s -> trade to %s for DE", tm_name, de_player), "RAID")
              sepgp:adminSay(string.format("[EPGP-AUDIT] %s: %s (0 GP) - TM: %s - DE: %s - Route: %s(TM) -> %s(DE)", UnitName("player"), itemDisplayName or "?", tm_name, de_player, tm_name, de_player))
              -- Track pending trade
              sepgp._pendingTrades = sepgp._pendingTrades or {}
              table.insert(sepgp._pendingTrades, { from = tm_name, to = de_player, item = itemDisplayName, time = GetTime(), specType = "DE" })
              sepgp:ScheduleEvent("sepgpTradeTimeout_" .. tm_name .. de_player, function()
                sepgp:defaultPrint(string.format("|cffFF0000[TRADE ALERT]|r %s has not traded %s to %s for DE! (10 min timeout)", tm_name, itemDisplayName or "item", de_player))
                sepgp:adminSay(string.format("[EPGP] TRADE TIMEOUT: %s -> %s for DE of %s (10 min expired)", tm_name, de_player, itemDisplayName or "?"))
              end, 600)
            else
              SendChatMessage(string.format("[EPGP] Transmog only (0 GP) - %s", tm_name), "RAID")
              sepgp:adminSay(string.format("[EPGP-AUDIT] %s: %s (0 GP) - TM: %s (no DE assigned)", UnitName("player"), itemDisplayName or "?", tm_name))
            end
          end
          sepgp:writeDebugLog(string.format("POPUP_ACTION | TM_ONLY_1 | holder=%s | de=%s | %s", tm_name, tostring(tm_is_de), itemDisplayName or "?"))

        else
          -- Fallback: no TM info at all
          SendChatMessage(string.format("[EPGP] Transmog only (0 GP) - %s", tm_holder), "RAID")
          sepgp:adminSay(string.format("[EPGP-AUDIT] %s: %s (0 GP) - TM: %s", UnitName("player"), itemDisplayName or "?", tm_holder))
          sepgp:writeDebugLog(string.format("POPUP_ACTION | TM_ONLY_FALLBACK | holder=%s | %s", tm_holder, itemDisplayName or "?"))
        end
      end

      -- Cancel timer and clear bids
      if sepgp:IsEventScheduled("shootyepgpBidTimeout") then
        sepgp:CancelScheduledEvent("shootyepgpBidTimeout")
      end
      sepgp:clearBidsQuiet()
      sepgp:refreshPRTablets()
      data[sepgp.loot_index.action] = sepgp.VARS.tmgp
      local update = data[sepgp.loot_index.update] ~= nil
      sepgp:addOrUpdateLoot(data,update)
      StaticPopup_Hide("SHOOTY_EPGP_AUTO_GEARPOINTS")
      sepgp:advanceLootQueue()
      sepgp_loot:Refresh()
    end
  end},
  {text = L["Bank or D/E"], func = function()
    local dialog = StaticPopup_FindVisible("SHOOTY_EPGP_AUTO_GEARPOINTS")
    if (dialog) then
      local data = dialog.data
      local itemLink = data[sepgp.loot_index.item]
      local itemDisplayName = sepgp:extractItemName(itemLink)
      local player = data[sepgp.loot_index.player]
      if player == YOU then player = sepgp._playerName end
      -- Cancel bid timer and clear bids (item is done)
      if sepgp:IsEventScheduled("shootyepgpBidTimeout") then
        sepgp:CancelScheduledEvent("shootyepgpBidTimeout")
      end
      running_bid = false
      sepgp:clearBidsQuiet()
      data[sepgp.loot_index.action] = sepgp.VARS.bankde
      local update = data[sepgp.loot_index.update] ~= nil
      sepgp:addOrUpdateLoot(data,update)
      -- Phase 3: Post DE to officer chat for tracking
      sepgp:adminSay(string.format("[EPGP-AUDIT] %s: %s -> DE (%s)", UnitName("player"), itemDisplayName or "?", player))
      StaticPopup_Hide("SHOOTY_EPGP_AUTO_GEARPOINTS")
      sepgp:advanceLootQueue()
      sepgp_loot:Refresh()
      sepgp:writeDebugLog(string.format("POPUP_ACTION | BANK_DE | %s | %s", player, itemDisplayName or "?"))
    end
  end}
}
StaticPopupDialogs["SHOOTY_EPGP_AUTO_GEARPOINTS"] = {
  text = L["%s looted %s. What do you want to do?"],
  button1 = L["GP Actions"],
  button2 = L["Remind me Later"],
  OnAccept = function()
    -- Guard is per-data (_gp_charged), no global reset needed
    sepgp:EasyMenu(sepgp_auto_gp_menu, sepgp._menuFrame, this, 0, 0, "MENU", 1)
    return true
  end,
  OnCancel = function(data,reason)
    if reason == "override" or reason == "clicked" then
      -- Cancel bid timer so stale announcements don't fire
      if sepgp:IsEventScheduled("shootyepgpBidTimeout") then
        sepgp:CancelScheduledEvent("shootyepgpBidTimeout")
      end
      running_bid = false
      data[sepgp.loot_index.action] = sepgp.VARS.reminder
      local update = data[sepgp.loot_index.update] ~= nil
      sepgp:addOrUpdateLoot(data,update)
      sepgp_loot:Refresh()
      sepgp:writeDebugLog("POPUP_ACTION | REMIND_LATER | " .. (data[sepgp.loot_index.item] or "?"))
      sepgp:advanceLootQueue()
      return
    elseif reason == "timeout" then
      return
    end
  end,
  OnShow = function()
    -- Guard is per-data (_gp_charged), no global reset needed
    sepgp._menuFrame = sepgp._menuFrame or CreateFrame("Frame", "sepgp_auto_gp_menuframe", UIParent, "UIDropDownMenuTemplate")
  end,
  OnHide = function()
    CloseDropDownMenus()
  end,
  timeout = 0,
  exclusive = 1,
  whileDead = 1,
  hideOnEscape = 1
}
function sepgp:EasyMenu_Initialize(level, menuList)
  for i, info in ipairs(menuList) do
    if (info.text) then
      info.index = i
      UIDropDownMenu_AddButton( info, level )
    end
  end
end
function sepgp:EasyMenu(menuList, menuFrame, anchor, x, y, displayMode, level)
  if ( displayMode == "MENU" ) then
    menuFrame.displayMode = displayMode
  end
  UIDropDownMenu_Initialize(menuFrame, function() sepgp:EasyMenu_Initialize(level, menuList) end, displayMode, level)
  ToggleDropDownMenu(1, nil, menuFrame, anchor, x, y)
end

-- GLOBALS: sepgp_saychannel,sepgp_groupbyclass,sepgp_groupbyarmor,sepgp_groupbyrole,sepgp_raidonly,sepgp_decay,sepgp_minep,sepgp_bidtimer,sepgp_reservechannel,sepgp_main,sepgp_progress,sepgp_discount,sepgp_altspool,sepgp_altpercent,sepgp_log,sepgp_dbver,sepgp_looted,sepgp_debug,sepgp_fubar
-- GLOBALS: sepgp,sepgp_prices,sepgp_standings,sepgp_bids,sepgp_loot,sepgp_reserves,sepgp_alts,sepgp_logs
