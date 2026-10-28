-- awardwindow.lua
-- Shown on the master looter's screen when a bid countdown ends. It lives INSIDE
-- the bid popup (no second window) and follows the pfUI / default theme.
-- Chat gets the winner announcement; GP is charged ONLY when you click Award.
--   Award  = charge GP + normal announcements/trade tracking (same as before)
--   Reopen = reopen bidding for the same item (no points touched)
--   Cancel = close without awarding anything
-- Multi-copy drops ("x2" in the loot call) show one row per copy.
-- WoW 1.12 / Lua 5.0 compatible.

local BC = AceLibrary("Babble-Class-2.2")

local win = nil
local MAX_ROWS = 10

sepgp._awardInfo = nil

local function colorName(name, class)
  local hex = class and BC and BC:GetHexColor(class) or nil
  if hex then
    if string.len(hex) == 6 then hex = "ff" .. hex end
    return "|c" .. hex .. name .. "|r"
  end
  return "|cffFFFFFF" .. name .. "|r"
end

local function pr_sort(a, b)
  local pa, pb = (a[5] or 0), (b[5] or 0)
  if pa ~= pb then return pa > pb end
  return tostring(a[1]) < tostring(b[1])
end

-- Shuffle bids_tm once so the transmog order is fixed (same for chat, window and award)
local function shuffleTm()
  local t = sepgp.bids_tm
  for i = table.getn(t), 2, -1 do
    local j = math.random(1, i)
    t[i], t[j] = t[j], t[i]
  end
end

-- Works out who would win each copy (nothing is charged here).
local function buildPreview(copies)
  local item = sepgp.bid_item or {}
  local gp = item.price or 0
  local osgp = item.off_price or 0
  local list = {}
  local function add(src, spec, cost)
    local c = {}
    for i = 1, table.getn(src) do table.insert(c, src[i]) end
    table.sort(c, pr_sort)
    for i = 1, table.getn(c) do
      table.insert(list, { name = c[i][1], class = c[i][2], spec = spec, pr = c[i][5] or 0, gp = cost })
    end
  end
  add(sepgp.bids_main, "MS", gp)
  add(sepgp.bids_flex, "FLEX", gp)
  add(sepgp.bids_off, "OS", osgp)

  local tmWinner = nil
  if table.getn(sepgp.bids_tm) > 0 then
    if copies > 1 then
      shuffleTm()
    else
      tmWinner = sepgp:rollTmWinners()
    end
  end

  local rows = {}
  for k = 1, copies do
    local w = list[k]
    local mule = nil
    if copies > 1 then
      if sepgp.bids_tm[k] then mule = sepgp.bids_tm[k][1] end
    else
      mule = tmWinner
    end
    if w then
      table.insert(rows, { winner = w, mule = (w and mule) or nil })
    else
      table.insert(rows, { winner = nil, mule = (copies == 1) and mule or nil })
    end
  end
  return rows
end

-- Turns the preview rows into short lines for the window (kept narrow so the
-- popup keeps its normal width and everything stays centered).
local function buildLines(copies, rows)
  local lines = {}
  local gold = "|cffFFCC00"
  if copies > 1 then table.insert(lines, gold .. "Winners:|r") end
  for k = 1, table.getn(rows) do
    local r = rows[k]
    local pre = (copies > 1) and string.format("%d) ", k) or (gold .. "Winner:|r ")
    if r.winner then
      local w = r.winner
      table.insert(lines, string.format("%s%s - %s, PR %.2f, %d GP", pre, colorName(w.name, w.class), w.spec, w.pr, w.gp))
      if r.mule then table.insert(lines, string.format("|cff00ffffvia TM: %s|r", r.mule)) end
    elseif r.mule then
      table.insert(lines, string.format("%s|cff00ffff%s|r (TM)", pre, r.mule))
      table.insert(lines, "|cff999999no MS/FLEX/OS bids|r")
    else
      local none = (copies > 1) and string.format("%d) ", k) or ""
      local who, kind = sepgp:GetNoBidRecipient()
      if who then
        local desired = (sepgp_nobid_target == "banker") and "bank" or "DE"
        local warn = ""
        if kind ~= desired then warn = string.format(" |cffff9900[no %s set]|r", desired) end
        table.insert(lines, string.format("|cff999999%sNobody bid - goes to|r %s |cff999999(%s)|r%s", none, who, kind, warn))
      else
        table.insert(lines, "|cff999999" .. none .. "Nobody bid - set /banker or /deadd|r")
      end
    end
  end
  return lines
end

local function chatText(k, copies, r)
  local prefix = (copies > 1) and string.format("%d) ", k) or ""
  if r.winner then
    local w = r.winner
    local txt = string.format("%s%s (%s, PR %.2f)", prefix, w.name, w.spec, w.pr)
    if r.mule then txt = txt .. string.format(" via TM %s", r.mule) end
    return txt
  end
  if r.mule then return string.format("%sTM only - %s", prefix, r.mule) end
  return prefix .. "no bids"
end

-- Countdown shown centered under the title of the bid popup (ML and raiders).
local timerFS, timerFrame
local timerEnd, timerActive = 0, false
local timerLastSec = nil   -- only rebuild the text when the displayed second changes

local function ensureTimer()
  if timerFS then return end
  local f = sepgp:CreateBidPopup()
  timerFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  timerFS:SetPoint("TOP", f.title, "BOTTOM", 0, -7)
  timerFS:SetText("")
  timerFrame = CreateFrame("Frame", nil, f)
  timerFrame:SetScript("OnUpdate", function()
    if not timerActive then return end
    local rem = timerEnd - GetTime()
    if rem < 0 then rem = 0 end
    local sec = math.ceil(rem)
    if sec ~= timerLastSec then
      timerLastSec = sec
      local color = "|cff50cd32"
      if sec <= 5 then color = "|cffff3333" elseif sec <= 10 then color = "|cffffcc00" end
      local m = math.floor(sec / 60)
      timerFS:SetText(string.format("%s%d:%02d|r", color, m, sec - m * 60))
    end
    if rem <= 0 then timerActive = false end
  end)
end

function sepgp:StartBidTimer(seconds)
  seconds = tonumber(seconds)
  if not seconds or seconds <= 0 then return end
  ensureTimer()
  timerEnd = GetTime() + seconds
  timerLastSec = nil
  timerActive = true
end

-- text (optional): shown instead of the time, e.g. "Closed"
function sepgp:StopBidTimer(text)
  timerActive = false
  timerLastSec = nil
  if timerFS then
    if text then timerFS:SetText("|cff999999" .. text .. "|r") else timerFS:SetText("") end
  end
end

-- The award controls are a section at the bottom of the bid popup.
local function buildSection()
  local f = sepgp:CreateBidPopup()
  local sec = CreateFrame("Frame", nil, f)
  sec:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 8)
  sec:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
  sec:SetHeight(100)
  sec:Hide()

  local line = sec:CreateTexture(nil, "ARTWORK")
  line:SetHeight(2)
  line:SetWidth(260)   -- same size as the divider above it in the bid popup
  line:SetPoint("TOP", sec, "TOP", 0, 0)
  line:SetTexture(0.15, 0.15, 0.15, 1)
  sec.line = line

  local label = CreateFrame("Frame", nil, sec)   -- invisible anchor for the rows
  label:SetWidth(1)
  label:SetHeight(1)
  label:SetPoint("TOP", sec, "TOP", 0, 0)
  sec.anchor = label

  sec.rows = {}
  for i = 1, MAX_ROWS do
    local fs = sec:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetJustifyH("CENTER")
    fs:SetWidth(270)
    fs:SetHeight(14)
    if i == 1 then
      fs:SetPoint("TOP", label, "BOTTOM", 0, -6)
    else
      fs:SetPoint("TOP", sec.rows[i - 1], "BOTTOM", 0, -2)
    end
    fs:Hide()
    sec.rows[i] = fs
  end

  local btns = {}
  local function mkBtn(text, x, handler)
    local b = CreateFrame("Button", nil, sec, "UIPanelButtonTemplate")
    b:SetWidth(78)
    b:SetHeight(22)
    b:SetPoint("BOTTOM", sec, "BOTTOM", x, 0)
    b:SetText(text)
    b:SetScript("OnClick", handler)
    table.insert(btns, b)
    return b
  end
  -- Bank / Disenchant selector (only shown when nobody bid)
  local function mkSel(text, x, target)
    local b = CreateFrame("Button", nil, sec, "UIPanelButtonTemplate")
    b:SetWidth(100)
    b:SetHeight(20)
    b:SetPoint("BOTTOM", sec, "BOTTOM", x, 28)
    b.label = text
    b.target = target
    b:SetText(text)
    b:SetScript("OnClick", function()
      sepgp_nobid_target = this.target
      if sepgp._awardInfo then sepgp:ShowAwardWindow(sepgp._awardInfo) end
    end)
    b:Hide()
    table.insert(btns, b)
    return b
  end
  sec.selBank = mkSel("Bank", -54, "banker")
  sec.selDE = mkSel("Disenchant", 54, "de")
  mkBtn("Award", -84, function() sepgp:AwardPendingLoot() end)
  mkBtn("Reopen", 0, function() sepgp:RebidPendingLoot() end)
  mkBtn("Cancel", 84, function() sepgp:SkipPendingLoot() end)

  -- pfUI theme for the buttons (default Blizzard look otherwise)
  sepgp_pfui.Register(sec, function()
    for _, b in ipairs(btns) do sepgp_pfui.SkinButton(b) end
  end)

  f.awardSection = sec
  return sec
end

function sepgp:HideAwardWindow()
  sepgp._awardInfo = nil
  local f = sepgp.CreateBidPopup and sepgp:CreateBidPopup()
  if f and f.awardSection and f.awardSection:IsShown() then
    f.awardSection:Hide()
    sepgp:LayoutBidPopup()
  end
end

function sepgp:ShowAwardWindow(info)
  local f = sepgp:CreateBidPopup()
  local sec = f.awardSection or buildSection()
  local lines = buildLines(info.copies, info.rows)
  local n = table.getn(lines)
  for i = 1, MAX_ROWS do
    if i <= n then
      sec.rows[i]:SetText(lines[i])
      sec.rows[i]:Show()
    else
      sec.rows[i]:Hide()
    end
  end
  -- one separator is enough: only draw ours when the bid list is between the lines
  if (f.listRowCount or 0) > 0 then sec.line:Show() else sec.line:Hide() end
  local off = ((f.listRowCount or 0) > 0) and 8 or 4   -- gap above the text
  sec.rows[1]:ClearAllPoints()
  sec.rows[1]:SetPoint("TOP", sec.anchor, "BOTTOM", 0, -off)
  -- Bank / Disenchant choice when at least one copy has no bidder at all
  local needSel = false
  for k = 1, table.getn(info.rows) do
    if (not info.rows[k].winner) and (not info.rows[k].mule) then needSel = true end
  end
  if needSel then
    local bankSel = (sepgp_nobid_target == "banker")
    sec.selBank:SetText(bankSel and "|cff50cd32[Bank]|r" or "Bank")
    sec.selDE:SetText(bankSel and "Disenchant" or "|cff50cd32[Disenchant]|r")
    sec.selBank:Show()
    sec.selDE:Show()
  else
    sec.selBank:Hide()
    sec.selDE:Hide()
  end
  sec:SetHeight(off + n * 16 + 32 + (needSel and 26 or 0))   -- ~12 gap below the text
  f.buttonBar:Hide()
  f.statusText:SetText("|cff999999Bidding closed|r")
  sec:Show()
  sepgp:LayoutBidPopup()
  f:SetFrameStrata("FULLSCREEN_DIALOG")   -- always above the loot window and other frames
  f:Show()
  f:Raise()
end

-- Called by bids.lua when the countdown ends (or /bowepgp end).
function sepgp:OnBidCountdownEnd()
  if not (self.bid_item and self.bid_item.linkFull) then return end
  -- already pending: just bring the window back
  if self._bidsLocked and self._awardInfo then
    self:ShowAwardWindow(self._awardInfo)
    return
  end
  self._bidsLocked = true
  self._awaitingAward = true
  self:StopBidTimer("Closed")
  self:addonMessage("BID;CLOSED;0", "RAID")
  if self:IsEventScheduled("shootyepgpBidTimeout") then
    self:CancelScheduledEvent("shootyepgpBidTimeout")
  end

  local item = self.bid_item
  local copies = tonumber(item.copies) or 1
  local rows = buildPreview(copies)

  local data = {
    [self.loot_index.time] = date("%H:%M"),
    [self.loot_index.item] = item.linkFull,
    [self.loot_index.bind] = self.VARS.bop,
    [self.loot_index.price] = item.price or 0,
    [self.loot_index.off_price] = item.off_price or 0,
  }
  -- Keep the loot-capture chain from also resolving this item on its own
  self._popupShownLinks = self._popupShownLinks or {}
  self._popupShownLinks[item.linkFull] = GetTime()

  self._awardInfo = { data = data, copies = copies, rows = rows, itemLink = item.linkFull, fixedOrder = (copies > 1) }

  -- Chat announcement (no GP charged yet)
  local hasAny = false
  local parts = {}
  for k = 1, table.getn(rows) do
    if rows[k].winner then hasAny = true end
    table.insert(parts, chatText(k, copies, rows[k]))
  end
  if copies > 1 then
    self:widestAudience(string.format("[EPGP] Winners (x%d) %s: %s", copies, item.linkFull, table.concat(parts, ", ")))
  elseif hasAny then
    self:widestAudience(string.format("[EPGP] Winner %s: %s", item.linkFull, parts[1]))
  elseif rows[1] and rows[1].mule then
    self:widestAudience(string.format("[EPGP] No MS/FLEX/OS bids on %s - TM winner: %s", item.linkFull, rows[1].mule))
  else
    self:widestAudience(string.format("[EPGP] No GP bids on %s", item.linkFull))
  end

  self:writeDebugLog("AWARD_WINDOW | " .. tostring(item.linkFull) .. " | copies=" .. tostring(copies))
  self:ShowAwardWindow(self._awardInfo)
end

local function stillPending()
  local info = sepgp._awardInfo
  if info and sepgp._bidsLocked and sepgp.bid_item and sepgp.bid_item.linkFull == info.itemLink then
    return info
  end
  sepgp:defaultPrint("This item was already resolved or cancelled.")
  sepgp:HideAwardWindow()
  return nil
end

function sepgp:AwardPendingLoot()
  if self._awardBusy then return end   -- still waiting for the game to confirm a give
  local info = stillPending()
  if not info then return end
  self._popupShownLinks = self._popupShownLinks or {}
  self._popupShownLinks[info.itemLink] = GetTime()
  self._usedSlots = {}
  self._awardBusy = true
  self:ResolveMultiLoot(info.data, info.copies, info.fixedOrder, function(done)
    sepgp._awardBusy = nil
    if done >= info.copies then
      sepgp:HideAwardWindow()   -- all delivered; bids already cleared
      return
    end
    -- Something failed (message already printed). Window stays open for a retry.
    if done > 0 and sepgp._awardInfo then
      for i = 1, done do table.remove(info.rows, 1) end
      info.copies = info.copies - done
      sepgp:ShowAwardWindow(info)
    end
    sepgp:defaultPrint("GP was NOT charged for the undelivered item(s). Fix the problem, then click Award again (or Reopen / Cancel).")
  end)
end

function sepgp:RebidPendingLoot()
  local info = stillPending()
  if not info then return end
  local bi = self.bid_item
  local keep = { link = bi.link, linkFull = bi.linkFull, name = bi.name, price = bi.price, copies = bi.copies }
  self:clearBidsQuiet()   -- wipes bids + hides window, touches no points
  self:startBidRound(keep.link, keep.linkFull, keep.name, keep.price, keep.copies, true)
end

function sepgp:SkipPendingLoot()
  local info = stillPending()
  if not info then return end
  local link = info.itemLink
  self:clearBidsQuiet()
  self:widestAudience(string.format("[EPGP] Bid cancelled: %s", link))
  self:defaultPrint("Bid cancelled - no GP charged.")
end

-- GLOBALS: sepgp
