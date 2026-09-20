local T = AceLibrary("Tablet-2.0")
local D = AceLibrary("Dewdrop-2.0")
local C = AceLibrary("Crayon-2.0")

local BC = AceLibrary("Babble-Class-2.2")
local L = AceLibrary("AceLocale-2.2"):new("shootyepgp")

sepgp_bids = sepgp:NewModule("sepgp_bids", "AceDB-2.0", "AceEvent-2.0")

function sepgp_bids:OnEnable()
  if not T:IsRegistered("sepgp_bids") then
    T:Register("sepgp_bids",
      "children", function()
        T:SetTitle(L["shootyepgp bids"])
        self:OnTooltipUpdate()
      end,
      "showTitleWhenDetached", true,
      "showHintWhenDetached", true,
      "cantAttach", true,
      "menu", function()
        D:AddLine(
          "text", L["Refresh"],
          "tooltipText", L["Refresh window"],
          "func", function() sepgp_bids:Refresh() end
        )
      end      
    )
  end
  if not T:IsAttached("sepgp_bids") then
    T:Open("sepgp_bids")
  end
end

function sepgp_bids:OnDisable()
  T:Close("sepgp_bids")
end

function sepgp_bids:Refresh()
  T:Refresh("sepgp_bids")
  if not T:IsAttached("sepgp_bids") then
    self:setHideScript()
  end
end

function sepgp_bids:setHideScript()
  local i = 1
  local tablet = getglobal(string.format("Tablet20DetachedFrame%d",i))
  while (tablet) and i<100 do
    if tablet.owner ~= nil and tablet.owner == "sepgp_bids" then
      sepgp:make_escable(string.format("Tablet20DetachedFrame%d",i),"add")
      tablet:SetScript("OnHide",nil)
      tablet:SetScript("OnHide",function()
          if not T:IsAttached("sepgp_bids") then
            T:Attach("sepgp_bids")
            this:SetScript("OnHide",nil)
          end
        end)
      -- Add close button if not already present
      if not tablet.shootyCloseBtn then
        local btn = CreateFrame("Button", nil, tablet, "UIPanelCloseButton")
        btn:SetPoint("TOPRIGHT", tablet, "TOPRIGHT", 1, 1)
        btn:SetWidth(24)
        btn:SetHeight(24)
        btn:SetScript("OnClick", function()
          T:Attach("sepgp_bids")
        end)
        tablet.shootyCloseBtn = btn
      end
      break
    end
    i = i+1
    tablet = getglobal(string.format("Tablet20DetachedFrame%d",i))
  end
end

function sepgp_bids:Top()
  if T:IsRegistered("sepgp_bids") and (T.registry.sepgp_bids.tooltip) then
    T.registry.sepgp_bids.tooltip.scroll=0
  end  
end

function sepgp_bids:Toggle(forceShow)
  self:Top()
  if T:IsAttached("sepgp_bids") then
    T:Detach("sepgp_bids") -- show
    if (T:IsLocked("sepgp_bids")) then
      T:ToggleLocked("sepgp_bids")
    end
    self:setHideScript()
  else
    if (forceShow) then
      sepgp_bids:Refresh()
    else
      T:Attach("sepgp_bids") -- hide
    end
  end  
end

-- Roll TM bidders and announce result. Called when ANY winner is chosen.
-- 2026-04-06: Now delegates to sepgp:rollTmWinners() for the actual roll.
-- Previously this function had its own math.random calls separate from
-- analyzeLootResolution, producing inconsistent TM winner names between
-- raid chat and officer chat for the same bid. Now both code paths share
-- the same roll via the idempotent helper.
function sepgp_bids:rollAndAnnounceTM(gpWinner)
  local tm_count = table.getn(sepgp.bids_tm)
  if tm_count == 0 then return end

  -- Get the (possibly already-rolled) winners from the shared helper.
  -- Idempotent: if a previous call already rolled for this bid, returns same.
  sepgp:rollTmWinners()

  local tm_names = {}
  for i = 1, tm_count do
    table.insert(tm_names, string.format("[%d]:%s", i, sepgp.bids_tm[i][1]))
  end
  sepgp:widestAudience("[EPGP] TM Bidders: " .. table.concat(tm_names, ", "))

  if tm_count == 1 then
    sepgp:widestAudience(string.format("[EPGP] Transmog: %s wins (auto-win, 1 bidder) - 0 GP", sepgp.tm_winner))
  else
    -- Show assignments so raid can see who is what number
    local assignMsg = "[EPGP] TM Roll: "
    for i = 1, tm_count do
      if i > 1 then assignMsg = assignMsg .. ", " end
      assignMsg = assignMsg .. string.format("%s=#%d", sepgp.bids_tm[i][1], i)
    end
    sepgp:widestAudience(assignMsg)
    -- Find the index of tm_winner in bids_tm so the announcement matches reality
    local roll1Idx, roll2Idx
    for i = 1, tm_count do
      if sepgp.bids_tm[i][1] == sepgp.tm_winner then roll1Idx = i; break end
    end
    sepgp:widestAudience(string.format("[EPGP] Rolling 1-%d ... result: %d -> %s wins TM#1", tm_count, roll1Idx or 0, sepgp.tm_winner))
    if sepgp.tm_winner2 then
      -- Find tm_winner2's position in the remaining pool (1-indexed, excluding roll1)
      local remCount = tm_count - 1
      local pos = 0
      for i = 1, tm_count do
        if i ~= roll1Idx then
          pos = pos + 1
          if sepgp.bids_tm[i][1] == sepgp.tm_winner2 then roll2Idx = pos; break end
        end
      end
      sepgp:widestAudience(string.format("[EPGP] Rolling 1-%d (remaining) ... result: %d -> %s wins TM#2", remCount, roll2Idx or 0, sepgp.tm_winner2))
    end
    sepgp:widestAudience(string.format("[EPGP] Transmog winners: TM#1 %s, TM#2 %s - 0 GP", sepgp.tm_winner, sepgp.tm_winner2 or "none"))
  end

  if gpWinner then
    SendChatMessage(string.format("[EPGP] %s gets item (GP charged). %s gets transmog appearance - trade within 10 min.", gpWinner, sepgp.tm_winner), "RAID")
  end
end

-- Get the GP price and off-price stored on bid_item when bids were opened
function sepgp_bids:getBidPrice()
  -- Primary: stored directly on bid_item when captureLootCall opened bids
  if sepgp.bid_item and sepgp.bid_item.price and sepgp.bid_item.price > 0 then
    return sepgp.bid_item.price, sepgp.bid_item.off_price
  end
  -- Fallback: loot popup dialog data
  local dialog = StaticPopup_FindVisible("SHOOTY_EPGP_AUTO_GEARPOINTS")
  if dialog and dialog.data then
    local price = dialog.data[sepgp.loot_index.price]
    local off_price = dialog.data[sepgp.loot_index.off_price]
    if price and price > 0 then return price, off_price end
  end
  return nil, nil
end

-- 2026-04-02: Bid window ANNOUNCES the winner but does NOT charge GP.
-- WHY: The loot popup (SHOOTY_EPGP_AUTO_GEARPOINTS) is the single place
--   where GP gets charged. Previously the bid window also charged GP,
--   and then the loot popup appeared asking the officer to charge again.
--   Officers naturally clicked "Add MainSpec GP" on the popup because it
--   was asking them to, causing a double charge (Bambow: 2x 92 GP for
--   Desecrated Boots). Now the bid window only selects/announces the
--   winner, and the popup is the one and only charge point.
-- WHAT CHANGED: Removed sepgp:givename_gp calls from announceWinnerMS,
--   announceWinnerFLEX, and announceWinnerOS. These now only announce
--   the winner, roll TM, clear bids, and refresh standings.

-- 2026-04-06 v4.22 HOTFIX: Bid window winner click now ALSO triggers the
-- Resolution Window popup directly. Previously the bid window only
-- announced the winner and waited for the loot capture chain
-- (CHAT_MSG_LOOT or GiveMasterLoot hook -> processLoot -> queueLootPopup
-- -> showNextLootPopup -> ShowResolutionWindow) to fire the popup. That
-- chain has been intermittently failing in production for reasons we
-- have not yet root-caused -- the popup simply does not appear, leaving
-- officers with no way to charge GP from the bid window flow.
--
-- The fix: when the officer clicks a winner in the bid window, build a
-- synthetic loot data record from sepgp.bid_item (which is populated
-- when the bid is opened) and call ShowResolutionWindow directly. This
-- bypasses queueLootPopup, the loot queue, and the loot capture chain
-- entirely -- same approach test mode uses (endTestBid).
--
-- IMPORTANT: ShowResolutionWindow must be called BEFORE clearBidsQuiet,
-- because analyzeLootResolution reads from sepgp.bids_main / bids_flex
-- / bids_off / bids_tm to determine the winner and build the plan.
-- After the plan is built it is copied into sepgp_resolution_plan, so
-- the subsequent clearBidsQuiet does not affect the popup state.
--
-- DUPLICATE PROTECTION: We mark sepgp._popupShownLinks[itemLink] with
-- the current GetTime(). processLoot checks this map and skips queueing
-- if it sees a recent entry for the same item link. This prevents the
-- loot capture chain from also firing a popup for the same item if and
-- when the officer assigns the loot via WoW's master loot UI.
local function triggerWinnerPopup(name)
  if not (sepgp.bid_item and sepgp.bid_item.linkFull) then
    sepgp:writeDebugLog("BID_WIN_DIRECT_POPUP | SKIP | no bid_item")
    return
  end
  local class = sepgp:resolveLooterClass(name)
  local color = "|cffFFFFFF" .. name .. "|r"
  if class then
    local hex = BC and BC:GetHexColor(class) or "ffFFFFFF"
    color = "|c" .. hex .. name .. "|r"
  end
  local data = {
    [sepgp.loot_index.time] = date("%H:%M"),
    [sepgp.loot_index.player] = name,
    [sepgp.loot_index.player_c] = color,
    [sepgp.loot_index.item] = sepgp.bid_item.linkFull,
    [sepgp.loot_index.bind] = sepgp.VARS.bop,
    [sepgp.loot_index.price] = sepgp.bid_item.price or 0,
    [sepgp.loot_index.off_price] = sepgp.bid_item.off_price or 0,
  }
  sepgp:writeDebugLog("BID_WIN_DIRECT_POPUP | " .. name .. " | " .. (sepgp.bid_item.linkFull or "?"))
  -- Mark this item link as recently shown so processLoot's loot capture
  -- path won't fire a duplicate popup if the officer also assigns the
  -- loot via WoW's master loot UI.
  sepgp._popupShownLinks = sepgp._popupShownLinks or {}
  sepgp._popupShownLinks[sepgp.bid_item.linkFull] = GetTime()
  sepgp:ShowResolutionWindow(data)
end

function sepgp_bids:announceWinnerMS(name, pr)
  sepgp:widestAudience(string.format(L["Winning Mainspec Bid: %s (%.03f PR)"],name,pr))
  triggerWinnerPopup(name)
  self:rollAndAnnounceTM(name)
  sepgp:clearBidsQuiet()
  sepgp:refreshPRTablets()
end

function sepgp_bids:announceWinnerFLEX(name, pr)
  sepgp:widestAudience(string.format("Winning Flex Bid: %s (%.03f PR)",name,pr))
  triggerWinnerPopup(name)
  self:rollAndAnnounceTM(name)
  sepgp:clearBidsQuiet()
  sepgp:refreshPRTablets()
end

function sepgp_bids:announceWinnerOS(name, pr)
  sepgp:widestAudience(string.format(L["Winning Offspec Bid: %s (%.03f PR)"],name,pr))
  triggerWinnerPopup(name)
  self:rollAndAnnounceTM(name)
  sepgp:clearBidsQuiet()
  sepgp:refreshPRTablets()
end

function sepgp_bids:announceWinnerTM(name)
  -- TM-only winner (no MS/FLEX/OS bids exist)
  self:rollAndAnnounceTM(nil)
  -- Transmog bids cost 0 GP, no assignment needed
  sepgp:clearBidsQuiet()
  sepgp:refreshPRTablets()
end

function sepgp_bids:countdownCounter()
  self._counter = (self._counter or 6) - 1
  if GetNumRaidMembers()>0 and self._counter > 0 then
    self._counterText = C:Yellow(tostring(self._counter))
    sepgp:widestAudience(tostring(self._counter))
    --SendChatMessage(tostring(self._counter),"RAID")
    self:Refresh()
  end
end

function sepgp_bids:countdownFinish(reset)
  if self:IsEventScheduled("shootyepgpBidCountdown") then
    self:CancelScheduledEvent("shootyepgpBidCountdown")
  end
  self._counter = 6
  if (reset) then
    self._counterText = C:Green("Starting")
  else
    self._counterText = C:Red("Finished")
  end
  self:Refresh()
end

function sepgp_bids:bidCountdown()
  self:countdownFinish(true)
  self:ScheduleRepeatingEvent("shootyepgpBidCountdown",self.countdownCounter,1,self)
  self:ScheduleEvent("shootyepgpBidCountdownFinish",self.countdownFinish,6,self)
end

local pr_sorter_bids = function(a,b)
  if sepgp_minep > 0 then
    local a_over = a[3]-sepgp_minep >= 0
    local b_over = b[3]-sepgp_minep >= 0
    if a_over and b_over or (not a_over and not b_over) then
      if a[5] ~= b[5] then
        return tonumber(a[5]) > tonumber(b[5])
      else
        return tonumber(a[3]) > tonumber(b[3])
      end
    elseif a_over and (not b_over) then
      return true
    elseif b_over and (not a_over) then
      return false
    end
  else
    if a[5] ~= b[5] then
      return tonumber(a[5]) > tonumber(b[5])
    else
      return tonumber(a[3]) > tonumber(b[3])
    end
  end
end

function sepgp_bids:BuildBidsTable()
  -- {name,class,ep,gp,ep/gp[,main]}
  table.sort(sepgp.bids_main, pr_sorter_bids)
  table.sort(sepgp.bids_flex, pr_sorter_bids)
  table.sort(sepgp.bids_off, pr_sorter_bids)
  -- bids_tm doesn't need PR sort (random roll)
  return sepgp.bids_main, sepgp.bids_flex, sepgp.bids_off, sepgp.bids_tm
end

function sepgp_bids:OnTooltipUpdate()
  if not (sepgp.bid_item and sepgp.bid_item.link) then return end
  local link = sepgp.bid_item.link
  local itemName = sepgp.bid_item.name
  -- Use ML's transmitted price if available (synced via BID;ITEM addon message).
  -- Falls back to local calculation only if bid_item.price wasn't set.
  local price, offspec
  if sepgp.bid_item.price and sepgp.bid_item.price > 0 then
    price = sepgp.bid_item.price
    offspec = sepgp.bid_item.off_price or math.floor(price * sepgp_discount)
  else
    price = sepgp_prices:GetPrice(link, sepgp_progress)
    if not price then
      price = "<n/a>"
      offspec = "<n/a>"
    else
      offspec = math.floor(price * sepgp_discount)
    end
  end
  local bidcat = T:AddCategory(
      "columns", 3,
      "text", C:Orange("Bid Item"), "child_textR",    1, "child_textG",    1, "child_textB",    1, "child_justify",  "LEFT",
      "text2", C:Orange("GP Cost"),     "child_text2R", 50/255, "child_text2G", 205/255, "child_text2B", 50/255, "child_justify2", "RIGHT",
      "text3", C:Orange("OffSpec"),  "child_text3R", 32/255, "child_text3G", 178/255, "child_text3B", 170/255, "child_justify3", "RIGHT",
      "hideBlankLine", true
    )
  bidcat:AddLine(
      "text", itemName,
      "text2", price,
      "text3", offspec
    )
  local countdownHeader = T:AddCategory(
      "columns", 2,
      "text","","child_textR",  1, "child_textG",  1, "child_textB",  1,"child_justify", "LEFT",
      "text2","","child_text2R",  1, "child_text2G",  1, "child_text2B",  1,"child_justify2", "CENTER",
      "hideBlankLine", true
    )
  countdownHeader:AddLine(
      "text", C:Green("Countdown"),
      "text2", self._counterText,
      "func", "bidCountdown", "arg1", self
    )

  local bids_ms, bids_flex, bids_os, bids_tm = self:BuildBidsTable()

  -- MainSpec Bids section
  local maincatHeader = T:AddCategory(
      "columns", 1,
      "text", C:Gold("MainSpec Bids")
    ):AddLine("text","")
  local maincat = T:AddCategory(
      "columns", 5,
      "text",  C:Orange("Name"),   "child_textR",    1, "child_textG",    1, "child_textB",    1, "child_justify",  "LEFT",
      "text2", C:Orange("ep"),     "child_text2R",   1, "child_text2G",   1, "child_text2B",   1, "child_justify2", "RIGHT",
      "text3", C:Orange("gp"),     "child_text3R",   1, "child_text3G",   1, "child_text3B",   1, "child_justify3", "RIGHT",
      "text4", C:Orange("pr"),     "child_text4R",   1, "child_text4G",   1, "child_text4B",   0, "child_justify4", "RIGHT",
      "text5", C:Orange("Main"),     "child_text5R",   1, "child_text5G",   1, "child_text5B",   0, "child_justify5", "RIGHT",
      "hideBlankLine", true
    )
  for i = 1, table.getn(bids_ms) do
    local name, class, ep, gp, pr, main = unpack(bids_ms[i])
    local namedesc
    if (main) then
      namedesc = string.format("%s(%s)", C:Colorize(BC:GetHexColor(class), name), L["Alt"])
    else
      namedesc = C:Colorize(BC:GetHexColor(class), name)
    end
    local text2, text4
    if sepgp_minep > 0 and ep < sepgp_minep then
      text2 = C:Red(string.format("%.4g", ep))
      text4 = C:Red(string.format("%.4g", pr))
    else
      text2 = string.format("%.4g", ep)
      text4 = string.format("%.4g", pr)
    end
    maincat:AddLine(
      "text", namedesc,
      "text2", text2,
      "text3", string.format("%.4g", gp),
      "text4", text4,
      "text5", (main or ""),
      "func", "announceWinnerMS", "arg1", self, "arg2", name, "arg3", pr
    )
  end

  -- Flex Bids section
  local flexcatHeader = T:AddCategory(
      "columns", 1,
      "text", C:Green("Flex Bids")
    ):AddLine("text","")
  local flexcat = T:AddCategory(
      "columns", 5,
      "text",  C:Orange("Name"),   "child_textR",    1, "child_textG",    1, "child_textB",    1, "child_justify",  "LEFT",
      "text2", C:Orange("ep"),     "child_text2R",   1, "child_text2G",   1, "child_text2B",   1, "child_justify2", "RIGHT",
      "text3", C:Orange("gp"),     "child_text3R",   1, "child_text3G",   1, "child_text3B",   1, "child_justify3", "RIGHT",
      "text4", C:Orange("pr"),     "child_text4R",   1, "child_text4G",   1, "child_text4B",   0, "child_justify4", "RIGHT",
      "text5", C:Orange("Main"),     "child_text5R",   1, "child_text5G",   1, "child_text5B",   0, "child_justify5", "RIGHT",
      "hideBlankLine", true
    )
  for i = 1, table.getn(bids_flex) do
    local name, class, ep, gp, pr, main = unpack(bids_flex[i])
    local namedesc
    if (main) then
      namedesc = string.format("%s(%s)", C:Colorize(BC:GetHexColor(class), name), L["Alt"])
    else
      namedesc = C:Colorize(BC:GetHexColor(class), name)
    end
    local text2, text4
    if sepgp_minep > 0 and ep < sepgp_minep then
      text2 = C:Red(string.format("%.4g", ep))
      text4 = C:Red(string.format("%.4g", pr))
    else
      text2 = string.format("%.4g", ep)
      text4 = string.format("%.4g", pr)
    end
    flexcat:AddLine(
      "text", namedesc,
      "text2", text2,
      "text3", string.format("%.4g", gp),
      "text4", text4,
      "text5", (main or ""),
      "func", "announceWinnerFLEX", "arg1", self, "arg2", name, "arg3", pr
    )
  end

  -- OffSpec Bids section
  local offcatHeader = T:AddCategory(
      "columns", 1,
      "text", C:Silver("OffSpec Bids")
    ):AddLine("text","")
  local offcat = T:AddCategory(
      "columns", 5,
      "text",  C:Orange("Name"),   "child_textR",    1, "child_textG",    1, "child_textB",    1, "child_justify",  "LEFT",
      "text2", C:Orange("ep"),     "child_text2R",   1, "child_text2G",   1, "child_text2B",   1, "child_justify2", "RIGHT",
      "text3", C:Orange("gp"),     "child_text3R",   1, "child_text3G",   1, "child_text3B",   1, "child_justify3", "RIGHT",
      "text4", C:Orange("pr"),     "child_text4R",   1, "child_text4G",   1, "child_text4B",   0, "child_justify4", "RIGHT",
      "text5", C:Orange("Main"),     "child_text5R",   1, "child_text5G",   1, "child_text5B",   0, "child_justify5", "RIGHT",
      "hideBlankLine", true
    )
  for i = 1, table.getn(bids_os) do
    local name, class, ep, gp, pr, main = unpack(bids_os[i])
    local namedesc
    if (main) then
      namedesc = string.format("%s(%s)", C:Colorize(BC:GetHexColor(class), name), L["Alt"])
    else
      namedesc = C:Colorize(BC:GetHexColor(class), name)
    end
    local text2, text4
    if sepgp_minep > 0 and ep < sepgp_minep then
      text2 = C:Red(string.format("%.4g", ep))
      text4 = C:Red(string.format("%.4g", pr))
    else
      text2 = string.format("%.4g", ep)
      text4 = string.format("%.4g", pr)
    end
    offcat:AddLine(
      "text", namedesc,
      "text2", text2,
      "text3", string.format("%.4g", gp),
      "text4", text4,
      "text5", (main or ""),
      "func", "announceWinnerOS", "arg1", self, "arg2", name, "arg3", pr
    )
  end

  -- Transmog Bids section (name + class only, no EP/GP/PR)
  local tmcatHeader = T:AddCategory(
      "columns", 1,
      "text", "|cff00ffffTransmog Bids|r"
    ):AddLine("text","")
  local tmcat = T:AddCategory(
      "columns", 2,
      "text",  C:Orange("Name"),   "child_textR",    1, "child_textG",    1, "child_textB",    1, "child_justify",  "LEFT",
      "text2", C:Orange("Class"),  "child_text2R",   1, "child_text2G",   1, "child_text2B",   1, "child_justify2", "RIGHT",
      "hideBlankLine", true
    )
  for i = 1, table.getn(bids_tm) do
    local name = bids_tm[i][1]
    local class = bids_tm[i][2]
    local namedesc = C:Colorize(BC:GetHexColor(class), name)
    tmcat:AddLine(
      "text", namedesc,
      "text2", class,
      "func", "announceWinnerTM", "arg1", self, "arg2", name
    )
  end
end

-- GLOBALS: sepgp_saychannel,sepgp_groupbyclass,sepgp_groupbyarmor,sepgp_groupbyrole,sepgp_raidonly,sepgp_decay,sepgp_minep,sepgp_reservechannel,sepgp_main,sepgp_progress,sepgp_discount,sepgp_log,sepgp_dbver,sepgp_looted
-- GLOBALS: sepgp,sepgp_prices,sepgp_standings,sepgp_bids,sepgp_loot,sepgp_reserves,sepgp_alts,sepgp_logs
