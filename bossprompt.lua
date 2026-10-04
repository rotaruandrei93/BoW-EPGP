-- bossprompt.lua
-- After a boss dies and ALL its (epic+) loot has been handed out, prompt the
-- master looter to award the preset EP for that boss (or award it automatically).
--
-- Load order in the .toc: BoW-EPGP.lua, ..., BossAwards.lua, bossprompt.lua
-- Saved variable (in the .toc): sepgp_bossaward_auto
-- WoW 1.12 / Lua 5.0 compatible.

local BA = {}
sepgp_bossaward = BA

local PENDING_TIMEOUT = 600   -- seconds a kill stays "waiting for loot"
local DEDUPE          = 300   -- ignore the same boss again for this long
local MIN_QUALITY     = 3     -- 3 = rare/blue and up counts as "loot to hand out"
local FIRE_DELAY      = 1.5   -- seconds after the last item before prompting

BA.pending   = nil   -- { key=, name=, ep=, time= }
BA.prompt    = nil   -- what the popup is currently asking about
BA.awarded   = {}    -- [key] = GetTime() when handled
BA.dead      = {}    -- [key] = { [bossName]=true } for multi-boss encounters
BA.slots     = {}    -- loot slots we are waiting on
BA.remaining = 0
BA.tracking  = false
BA.delay     = 0

local function say(msg)
  sepgp:defaultPrint(msg)
end

local function isML()
  return UnitInRaid("player") and sepgp:lootMaster() and CanEditOfficerNote()
end

local function encounterSize(key)
  local n = 0
  for name, e in pairs(SEPGP_BOSS_AWARDS) do
    if (e.encounter or name) == key then n = n + 1 end
  end
  return n
end

---------------------------------------------------------------------------
-- Hard mode detection (e.g. Solnius killed while Erennius is tanked)
-- Every second the ML looks at what the raid is targeting; a "partner" boss
-- that is alive and in combat is remembered for a few seconds.
---------------------------------------------------------------------------
local ENGAGED_WINDOW = 15   -- seconds a boss still counts as "fighting"
BA.engaged = {}             -- [bossName] = GetTime() last seen alive + in combat

local function pollEngaged()
  local watch = {}
  local any = false
  for _, e in pairs(SEPGP_BOSS_AWARDS) do
    if e.hard and e.hard.alive then
      watch[e.hard.alive] = true
      any = true
    end
  end
  if not any then return end
  local now = GetTime()
  for i = 1, GetNumRaidMembers() do
    local u = "raid" .. i .. "target"
    if UnitExists(u) then
      local n = UnitName(u)
      if n and watch[n] and (not UnitIsDead(u)) and UnitAffectingCombat(u) then
        BA.engaged[n] = now
      end
    end
  end
end

local pollFrame = CreateFrame("Frame")
pollFrame.t = 0
pollFrame:SetScript("OnUpdate", function()
  this.t = this.t + arg1
  if this.t < 1 then return end
  this.t = 0
  if isML() then pollEngaged() end
end)

-- EP (and display name) for a kill of boss `name`, honouring hard mode.
local function awardFor(name, e)
  if e.hard and e.hard.alive then
    local seen = BA.engaged[e.hard.alive]
    if seen and (GetTime() - seen) <= ENGAGED_WINDOW then
      return e.hard.ep, (e.encounter or name) .. " (Hard Mode)"
    end
  end
  return e.ep, (e.encounter or name)
end

---------------------------------------------------------------------------
-- Award / decline
---------------------------------------------------------------------------
function BA:Award(p)
  if not p then return end
  if p.test then
    say(string.format("(test) would award %d EP to the raid for %s.", p.ep, p.name))
    return
  end
  sepgp:award_raid_ep(p.ep)
  say(string.format("Boss kill: %s - awarded %d EP to the raid.", p.name, p.ep))
end

function BA:Decline(p)
  if not p then return end
  say(string.format("Boss kill: %s - EP award declined.", p.name))
end

-- The popup has an edit box pre-filled with the preset EP. "Award" (or Enter)
-- awards whatever number is in the box, so editing it = custom amount.
local function commitFromDialog(dialog)
  local p = BA.prompt
  if not p then return end
  local box = getglobal(dialog:GetName().."EditBox")
  local n = tonumber(box:GetText())
  local max = (sepgp.VARS and sepgp.VARS.max) or 1000
  if (not n) or n < 0 or n >= max or n ~= math.floor(n) then
    say(string.format("Invalid EP amount - enter a whole number from 0 to %d.", max - 1))
    p.time = GetTime()
    BA.prompt = nil
    BA.pending = p          -- re-show the prompt right after this one closes
    BA:Schedule(0.2)
    return
  end
  BA.prompt = nil
  p.ep = n
  BA:Award(p)
end

StaticPopupDialogs["SEPGP_BOSS_AWARD"] = {
  text = "|cffffd700BoW-|r|cff0070ddEPGP|r\n\n%s defeated.\nEP to award to the raid (edit for a custom amount):",
  button1 = "Award",
  button2 = "Decline",
  hasEditBox = 1,
  maxLetters = 4,
  OnShow = function()
    local box = getglobal(this:GetName().."EditBox")
    box:SetText(BA.prompt and tostring(BA.prompt.ep) or "")
    box:SetFocus()
    box:HighlightText()
  end,
  OnHide = function()
    if ChatFrameEditBox and ChatFrameEditBox:IsVisible() then
      ChatFrameEditBox:SetFocus()
    end
    getglobal(this:GetName().."EditBox"):SetText("")
  end,
  OnAccept = function()
    commitFromDialog(this:GetParent())
  end,
  OnCancel = function()
    local p = BA.prompt
    BA.prompt = nil
    BA:Decline(p)
  end,
  EditBoxOnEnterPressed = function()
    local dialog = this:GetParent()
    commitFromDialog(dialog)
    dialog:Hide()
  end,
  EditBoxOnEscapePressed = function()
    local p = BA.prompt
    BA.prompt = nil
    BA:Decline(p)
    this:GetParent():Hide()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

---------------------------------------------------------------------------
-- Fire: either popup or auto-award
---------------------------------------------------------------------------
function BA:Fire()
  local p = self.pending
  if not p then return end
  self.pending = nil
  self.tracking = false
  if (GetTime() - p.time) > PENDING_TIMEOUT then return end
  if not isML() then return end

  self.awarded[p.key] = GetTime()

  if sepgp_bossaward_auto and not p.test then
    self:Award(p)
  else
    self.prompt = p
    StaticPopup_Show("SEPGP_BOSS_AWARD", p.name, tostring(p.ep))
  end
end

local timer = CreateFrame("Frame")
timer:Hide()
timer:SetScript("OnUpdate", function()
  BA.delay = BA.delay - arg1
  if BA.delay <= 0 then
    timer:Hide()
    BA:Fire()
  end
end)

function BA:Schedule(d)
  self.delay = d
  timer:Show()
end

---------------------------------------------------------------------------
-- Boss death detection
---------------------------------------------------------------------------
function BA:OnBossDeath(name)
  self.engaged[name] = nil   -- dead bosses no longer count as "fighting"
  local e = SEPGP_BOSS_AWARDS[name]
  if not e then return end
  if not isML() then return end

  local key = e.encounter or name
  local now = GetTime()
  if self.awarded[key] and (now - self.awarded[key]) < DEDUPE then return end
  if self.pending and self.pending.key == key then return end

  self.dead[key] = self.dead[key] or {}
  self.dead[key][name] = true
  local count = 0
  for _ in pairs(self.dead[key]) do count = count + 1 end
  if count < encounterSize(key) then return end   -- wait for the rest of the encounter

  self.dead[key] = nil
  local ep, label = awardFor(name, e)
  self.pending = { key = key, name = label, ep = ep, time = now }
  self.tracking = false
end

---------------------------------------------------------------------------
-- Loot tracking: fire once every epic+ slot on the boss corpse is cleared
---------------------------------------------------------------------------
function BA:OnLootOpened()
  -- fallback: ML opens the corpse of a boss whose death message we missed
  local tname = UnitName("target")
  if tname and UnitIsDead("target") and SEPGP_BOSS_AWARDS[tname] then
    self:OnBossDeath(tname)
  end
  if not self.pending then return end

  -- ignore loot windows from other corpses (trash) while a boss is pending
  if tname and not SEPGP_BOSS_AWARDS[tname] then return end

  self.slots = {}
  self.remaining = 0
  self.tracking = true
  for i = 1, GetNumLootItems() do
    if LootSlotIsItem(i) then
      local _, _, _, quality = GetLootSlotInfo(i)
      if quality and quality >= MIN_QUALITY then
        self.slots[i] = true
        self.remaining = self.remaining + 1
      end
    end
  end
end

function BA:OnLootSlotCleared(slot)
  if not (self.pending and self.tracking) then return end
  if self.slots[slot] then
    self.slots[slot] = nil
    self.remaining = self.remaining - 1
    if self.remaining <= 0 then
      self:Schedule(FIRE_DELAY)
    end
  end
end

function BA:OnLootClosed()
  -- boss dropped nothing worth handing out (or it was all taken already)
  if self.pending and self.tracking and self.remaining <= 0 then
    self:Schedule(FIRE_DELAY)
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")
f:RegisterEvent("LOOT_OPENED")
f:RegisterEvent("LOOT_SLOT_CLEARED")
f:RegisterEvent("LOOT_CLOSED")
f:SetScript("OnEvent", function()
  if event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
    local _, _, name = string.find(arg1 or "", "^(.+) dies%.$")
    if name then BA:OnBossDeath(name) end
  elseif event == "LOOT_OPENED" then
    BA:OnLootOpened()
  elseif event == "LOOT_SLOT_CLEARED" then
    BA:OnLootSlotCleared(arg1)
  elseif event == "LOOT_CLOSED" then
    BA:OnLootClosed()
  end
end)

---------------------------------------------------------------------------
-- Slash command: /bowepgpboss
---------------------------------------------------------------------------
SLASH_SEPGPBOSSAWARD1 = "/bowepgpboss"
SlashCmdList["SEPGPBOSSAWARD"] = function(msg)
  msg = string.lower(msg or "")
  if not CanEditOfficerNote() then
    say("Boss EP commands are officers only.")
    return
  end
  if msg == "auto" then
    sepgp_bossaward_auto = true
    say("Boss EP: AUTO - EP is awarded without a prompt.")
  elseif msg == "popup" or msg == "manual" then
    sepgp_bossaward_auto = false
    say("Boss EP: PROMPT - master looter is asked before awarding.")
  elseif msg == "now" then
    -- manual trigger for the boss you are targeting
    local n = UnitName("target")
    local e = n and SEPGP_BOSS_AWARDS[n]
    if not e then say("Target a boss listed in BossAwards.lua first.") return end
    BA.awarded[e.encounter or n] = nil
    local ep, label = awardFor(n, e)
    BA.pending = { key = e.encounter or n, name = label, ep = ep, time = GetTime() }
    BA:Fire()
  elseif msg == "test" then
    BA.prompt = { key = "test", name = "Test Boss", ep = 10, test = true }
    StaticPopup_Show("SEPGP_BOSS_AWARD", "Test Boss", "10")
  else
    say("/bowepgpboss auto | popup | now | test   (currently: "
        .. (sepgp_bossaward_auto and "AUTO" or "PROMPT") .. ")")
  end
end

---------------------------------------------------------------------------
-- Add an on/off toggle to the existing FuBar/Dewdrop menu
---------------------------------------------------------------------------
local origBuildMenu = sepgp.buildMenu
sepgp.buildMenu = function(self)
  local opts = origBuildMenu(self)
  if opts and opts.args and not opts.args["bossaward_auto"] then
    opts.args["bossaward_auto"] = {
      type = "toggle",
      name = "Auto-award boss EP",
      desc = "Award the preset boss-kill EP automatically after loot, instead of showing a prompt.",
      order = 97,
      hidden = function() return not CanEditOfficerNote() end,
      get = function() return sepgp_bossaward_auto and true or false end,
      set = function(v) sepgp_bossaward_auto = v and true or false end,
    }
  end
  return opts
end
