-- ontime.lua
-- On-time EP award, driven by the RaidCalendar addon.
--
-- When a raid on the RaidCalendar reaches its start time and you are the raid's
-- master looter (officer), a popup asks whether to give "on-time" EP to the
-- raiders who are standing in that raid's zone(s). The amount is the same as one
-- boss kill in that raid, read from BossAwards.lua (MC 2, BWL 4, ...).
--
-- Load order in the .toc: ... BossAwards.lua, bossprompt.lua, ontime.lua
-- Saved variable (in the .toc): sepgp_ontime_done
-- Needs the RaidCalendar addon (officer side only). WoW 1.12 / Lua 5.0 compatible.

local OT = {}
sepgp_ontime = OT

local PREFIX   = "BoWOnTime"
local GRACE    = 3600   -- still prompt up to this many seconds after the start time
local POLL     = 2      -- seconds between checks
local KEEP     = 7 * 86400

local BZ = AceLibrary and AceLibrary:HasInstance("Babble-Zone-2.2") and AceLibrary("Babble-Zone-2.2") or nil

---------------------------------------------------------------------------
-- RAID TABLE. EDIT THIS TO MATCH YOUR CALENDAR TITLES AND ZONES.
--
-- keys  = words/phrases looked for in the RaidCalendar title (whole words,
--         case-insensitive, apostrophes ignored). First raid in this list that
--         matches wins.
-- zone  = the zone name used in BossAwards.lua; the EP is the most common
--         "ep" among the bosses of that zone.
-- zones = where a raider must be standing at award time to count as on time
--         (the raid zone plus the usual meeting spot outside). Use
--         "/bowepgpontime check" to see the zone names the game reports.
---------------------------------------------------------------------------
SEPGP_ONTIME_RAIDS = {
  { keys = { "molten core", "mc" },
    zone = "Molten Core",
    zones = { "Molten Core", "Blackrock Mountain" } },

  { keys = { "onyxia", "ony" },
    zone = "Onyxia's Lair",
    zones = { "Onyxia's Lair", "Dustwallow Marsh" } },

  { keys = { "blackwing lair", "bwl" },
    zone = "Blackwing Lair",
    zones = { "Blackwing Lair", "Blackrock Mountain" } },

  { keys = { "emerald sanctum", "es" },
    zone = "Emerald Sanctum",
    zones = { "Emerald Sanctum", "Hyjal", "Mount Hyjal" } },

  { keys = { "temple of ahnqiraj", "ahnqiraj temple", "aq40", "aq 40", "taq" },
    zone = "Temple of Ahn'Qiraj",
    zones = { "Ahn'Qiraj", "Temple of Ahn'Qiraj", "Ahn'Qiraj Temple", "Silithus" } },

  { keys = { "naxxramas", "naxx" },
    zone = "Naxxramas",
    zones = { "Naxxramas", "Eastern Plaguelands" } },

  { keys = { "timbermaw hold", "timbermaw", "tmh" },
    zone = "Timbermaw Hold",
    zones = { "Timbermaw Hold", "Azshara", "Felwood", "Winterspring", "Moonglade" } },

  { keys = { "kara40", "kara 40", "karazhan 40", "upper karazhan", "upper kara", "tower of karazhan" },
    zone = "Tower of Karazhan",
    zones = { "Tower of Karazhan", "Karazhan", "Deadwind Pass" } },
}

OT.prompt = nil   -- what the popup is currently asking about
OT.done   = nil   -- alias of sepgp_ontime_done once loaded

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function say(msg)
  sepgp:defaultPrint(msg)
end

local function isML()
  return UnitInRaid("player") and sepgp:lootMaster() and CanEditOfficerNote()
end

local function flat(s)   -- "Ahn'Qiraj 40 - Tue!" -> " ahnqiraj 40 tue "
  s = string.lower(s or "")
  s = string.gsub(s, "'", "")
  s = string.gsub(s, "[^%w]", " ")
  return " " .. s .. " "
end

local function matchRaid(title)
  local t = flat(title)
  for _, cfg in ipairs(SEPGP_ONTIME_RAIDS) do
    for _, key in ipairs(cfg.keys) do
      local k = string.gsub(flat(key), "^%s+", "")   -- keep trailing space as boundary
      if string.find(t, " " .. k, 1, true) then
        return cfg
      end
    end
  end
  return nil
end

-- One boss kill's worth of EP in this raid: the most common base "ep" in
-- BossAwards.lua for that zone (ties go to the lower number).
local function epFor(cfg)
  local count = {}
  for _, e in pairs(SEPGP_BOSS_AWARDS or {}) do
    if e.zone == cfg.zone and e.ep then
      count[e.ep] = (count[e.ep] or 0) + 1
    end
  end
  local best, bestN
  for ep, n in pairs(count) do
    if (not bestN) or n > bestN or (n == bestN and ep < best) then
      best, bestN = ep, n
    end
  end
  return best
end

local function normZone(z)
  if not z or z == "" then return nil end
  if BZ and BZ:HasReverseTranslation(z) then z = BZ:GetReverseTranslation(z) end
  return string.lower(z)
end

local function inZone(cfg, z)
  local nz = normZone(z)
  if not nz then return false end
  for _, zz in ipairs(cfg.zones) do
    if string.lower(zz) == nz then return true end
  end
  return false
end

local function zoneText(cfg)
  return table.concat(cfg.zones, " / ")
end

local function calendarEvents()
  if RaidCalendar and RaidCalendar.db and RaidCalendar.db.events then
    return RaidCalendar.db.events
  end
  return nil
end

local function markDone(id)
  sepgp_ontime_done = sepgp_ontime_done or {}
  sepgp_ontime_done[id] = time()
end

local function isDone(id)
  return sepgp_ontime_done and sepgp_ontime_done[id] and true or false
end

-- Nearest calendar raid (by start time) that matches the table.
-- `onlyDue` = only raids that have started and are still inside GRACE and not done.
local function findEvent(onlyDue)
  local events = calendarEvents()
  if not events then return nil end
  local now = time()
  local best, bestDiff
  for id, ev in pairs(events) do
    local st = tonumber(ev.startTime)
    if st then
      local cfg = matchRaid(ev.title)
      if cfg then
        local diff = st - now
        local ok
        if onlyDue then
          ok = (diff <= 0) and (-diff <= GRACE) and (not isDone(id))
        else
          ok = true
        end
        if ok then
          local ad = diff < 0 and -diff or diff
          if (not bestDiff) or ad < bestDiff then
            best, bestDiff = { id = id, ev = ev, cfg = cfg, start = st }, ad
          end
        end
      end
    end
  end
  return best
end

---------------------------------------------------------------------------
-- Award (only raiders standing in the raid's zones)
---------------------------------------------------------------------------
function OT:Award(p)
  if not p then return end
  if p.test then
    say(string.format("(test) would award %d EP on-time for %s.", p.ep, p.title))
    return
  end
  if GetNumRaidMembers() == 0 then
    say("On-time EP: you are not in a raid.")
    return
  end

  local given, skipped = 0, {}
  for i = 1, GetNumRaidMembers() do
    local name, rank, subgroup, level, class, fileName, zone, online = GetRaidRosterInfo(i)
    if name then
      if online and level and level >= sepgp.VARS.minlevel and inZone(p.cfg, zone) then
        sepgp:givename_ep(name, p.ep)
        given = given + 1
      else
        table.insert(skipped, name .. " (" .. ((online and zone) or "offline") .. ")")
      end
    end
  end

  local line = string.format("On-time EP: %d EP to %d raiders in %s (%s).", p.ep, given, zoneText(p.cfg), p.title)
  sepgp:simpleSay(line)
  sepgp:adminSay(string.format("[EPGP-AUDIT] %s awarded %d on-time EP to %d raiders (%s)", UnitName("player"), p.ep, given, p.title))
  sepgp:addToLog(line)
  sepgp:addonMessage(string.format("RAID;AWARD;%s", p.ep), "RAID")
  sepgp:refreshPRTablets()

  if table.getn(skipped) > 0 then
    say(string.format("Not in %s, no on-time EP: %s", zoneText(p.cfg), table.concat(skipped, ", ")))
  end
end

function OT:Decline(p)
  if not p then return end
  say(string.format("On-time EP for %s declined. (/bowepgpontime now to open it again)", p.title))
end

local function commitFromDialog(dialog)
  local p = OT.prompt
  if not p then return end
  local box = getglobal(dialog:GetName() .. "EditBox")
  local n = tonumber(box:GetText())
  local max = (sepgp.VARS and sepgp.VARS.max) or 1000
  if (not n) or n < 0 or n >= max or n ~= math.floor(n) then
    say(string.format("Invalid EP amount - enter a whole number from 0 to %d.", max - 1))
    OT.prompt = nil
    OT.again = p       -- re-show right after this one closes
    return
  end
  OT.prompt = nil
  p.ep = n
  OT:Award(p)
end

StaticPopupDialogs["SEPGP_ONTIME_AWARD"] = {
  text = "|cffffd700BoW-|r|cff0070ddEPGP|r\n\nOn-time EP for %s\nRaiders in: %s\nEP to award (edit for a custom amount):",
  button1 = "Award",
  button2 = "Cancel",
  hasEditBox = 1,
  maxLetters = 4,
  OnShow = function()
    local box = getglobal(this:GetName() .. "EditBox")
    box:SetText(OT.prompt and tostring(OT.prompt.ep) or "")
    box:SetFocus()
    box:HighlightText()
  end,
  OnHide = function()
    if ChatFrameEditBox and ChatFrameEditBox:IsVisible() then
      ChatFrameEditBox:SetFocus()
    end
    getglobal(this:GetName() .. "EditBox"):SetText("")
  end,
  OnAccept = function()
    commitFromDialog(this:GetParent())
  end,
  OnCancel = function()
    local p = OT.prompt
    OT.prompt = nil
    OT:Decline(p)
  end,
  EditBoxOnEnterPressed = function()
    local dialog = this:GetParent()
    commitFromDialog(dialog)
    dialog:Hide()
  end,
  EditBoxOnEscapePressed = function()
    local p = OT.prompt
    OT.prompt = nil
    OT:Decline(p)
    this:GetParent():Hide()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

function OT:Show(p)
  self.prompt = p
  StaticPopup_Show("SEPGP_ONTIME_AWARD", p.title, zoneText(p.cfg))
end

---------------------------------------------------------------------------
-- Poll the calendar
---------------------------------------------------------------------------
function OT:Check()
  if self.prompt then return end
  if self.again then
    local p = self.again
    self.again = nil
    self:Show(p)
    return
  end
  if not isML() then return end
  local f = findEvent(true)
  if not f then return end
  local ep = epFor(f.cfg)
  if not ep then return end

  -- one award per calendar raid, even across ML changes (see CHAT_MSG_ADDON below)
  markDone(f.id)
  SendAddonMessage(PREFIX, "DONE;" .. f.id, "RAID")

  local p = { id = f.id, title = f.ev.title or "Raid", cfg = f.cfg, ep = ep }
  if sepgp_ontime_auto then
    self:Award(p)   -- auto mode: no popup, pays the default amount right away
  else
    self:Show(p)
  end
end

local pollFrame = CreateFrame("Frame")
pollFrame.t = 0
pollFrame:SetScript("OnUpdate", function()
  this.t = this.t + arg1
  if this.t < POLL then return end
  this.t = 0
  OT:Check()
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  if event == "CHAT_MSG_ADDON" then
    if arg1 == PREFIX and arg4 ~= UnitName("player") then
      local _, _, id = string.find(arg2 or "", "^DONE;(.+)$")
      if id then markDone(id) end
    end
  elseif event == "PLAYER_LOGIN" then
    -- forget old entries
    sepgp_ontime_done = sepgp_ontime_done or {}
    local now = time()
    for id, t in pairs(sepgp_ontime_done) do
      if type(t) ~= "number" or (now - t) > KEEP then sepgp_ontime_done[id] = nil end
    end
  end
end)

---------------------------------------------------------------------------
-- Slash command: /bowepgpontime
---------------------------------------------------------------------------
local function fmtDiff(d)
  local sign = d < 0 and "-" or ""
  if d < 0 then d = -d end
  return string.format("%s%dh%02dm", sign, math.floor(d / 3600), math.floor(math.mod(d, 3600) / 60))
end

SLASH_SEPGPONTIME1 = "/bowepgpontime"
SlashCmdList["SEPGPONTIME"] = function(msg)
  msg = string.lower(msg or "")
  if not CanEditOfficerNote() then
    say("On-time EP commands are officers only.")
    return
  end

  if msg == "now" then
    if not UnitInRaid("player") then say("Join the raid first.") return end
    local f = findEvent(false)
    if not f then say("No matching raid found in RaidCalendar (see /bowepgpontime status).") return end
    local ep = epFor(f.cfg)
    if not ep then say("No boss EP found in BossAwards.lua for " .. f.cfg.zone .. ".") return end
    if OT.prompt then return end
    markDone(f.id)
    OT:Show({ id = f.id, title = f.ev.title or "Raid", cfg = f.cfg, ep = ep })

  elseif msg == "check" then
    local f = findEvent(false)
    if not f then say("No matching raid found in RaidCalendar.") return end
    say(string.format("%s -> zones: %s", f.ev.title or "?", zoneText(f.cfg)))
    for i = 1, GetNumRaidMembers() do
      local name, _, _, level, _, _, zone, online = GetRaidRosterInfo(i)
      if name then
        local ok = online and level and level >= sepgp.VARS.minlevel and inZone(f.cfg, zone)
        say(string.format("  %s: %s%s", name, tostring(zone), ok and "" or "   <-- would NOT get EP"))
      end
    end

  elseif msg == "auto" then
    sepgp_ontime_auto = not sepgp_ontime_auto
    say("On-time EP auto-award: " .. (sepgp_ontime_auto and "ON (pays the default amount at start time, no popup)" or "OFF (popup asks first)"))

  elseif msg == "reset" then
    sepgp_ontime_done = {}
    say("On-time EP: all raids marked as not yet awarded.")

  elseif msg == "test" then
    OT.prompt = { id = "test", title = "Test Raid", cfg = SEPGP_ONTIME_RAIDS[1], ep = 2, test = true }
    StaticPopup_Show("SEPGP_ONTIME_AWARD", "Test Raid", zoneText(SEPGP_ONTIME_RAIDS[1]))

  elseif msg == "status" or msg == "" then
    local events = calendarEvents()
    if not events then
      say("RaidCalendar is not loaded or has no data. Install it and run /rc refresh.")
      return
    end
    local now = time()
    local shown = 0
    for id, e in pairs(events) do
      local st = tonumber(e.startTime)
      local cfg = st and matchRaid(e.title)
      if cfg and (st - now) > -86400 and (st - now) < 7 * 86400 then
        shown = shown + 1
        say(string.format("%s | in %s | %s | %s EP | %s", e.title or "?", fmtDiff(st - now), cfg.zone,
          tostring(epFor(cfg) or "none"), isDone(id) and "already handled" or ((st - now) < -GRACE and "expired" or "pending")))
      end
    end
    if shown == 0 then say("No matching raids in the next 7 days.") end
    say("/bowepgpontime now | check | auto | reset | test     (auto: " .. (sepgp_ontime_auto and "on" or "off") .. ", ML: " .. (isML() and "yes" or "no") .. ")")
  else
    say("/bowepgpontime status | now | check | auto | reset | test")
  end
end

OT.Command = SlashCmdList["SEPGPONTIME"]  -- used by the minimap menu
