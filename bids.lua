local C = AceLibrary("Crayon-2.0")

sepgp_bids = sepgp:NewModule("sepgp_bids", "AceDB-2.0", "AceEvent-2.0")

-- REDESIGN: the bid window (the "BoW-EPGP bids" Tablet popup that only
-- the master looter could see) has been removed entirely. It was purely a
-- display -- MS/FLEX/OS/TM bids were already broadcast to raid chat as they
-- came in (widestAudience), the countdown ticks are already announced to
-- raid chat (countdownCounter), and the winner/GP charge is already
-- announced via announceBidResults/analyzeLootResolution. The window added
-- nothing analyzeLootResolution didn't already decide on its own, and
-- nothing the raid couldn't already see in chat. sepgp_bids now exists only
-- to hold the countdown timer + auto-resolve trigger below; there is no
-- more Toggle/Refresh/OnTooltipUpdate/click-to-award UI on this module.

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

-- REDESIGN (RollFor-style auto resolution): starting the countdown IS
-- starting the roll -- when it hits 0, sepgp:AutoResolveLoot() (in
-- BoW-EPGP.lua) runs the exact same priority logic the old Resolution
-- Window used (analyzeLootResolution: MS > FLEX > OS, TM mule
-- routed/awarded first, DE fallback for unclaimed items), charges GP,
-- announces to raid/officer chat, and records loot history -- with no
-- popup and no window at all.
--
-- resolveActiveBid() builds a synthetic loot-data record from the active
-- bid item (sepgp.bid_item, populated when the bid was opened) and hands
-- it to AutoResolveLoot. It only carries item/price info -- the actual
-- winner (name, spec, GP, TM routing) is always decided by
-- analyzeLootResolution itself.
--
-- DUPLICATE PROTECTION: marks sepgp._popupShownLinks[itemLink] with the
-- current GetTime() so processLoot's loot capture path won't queue a
-- second resolution if the officer also master-loots via WoW's native UI.
local function resolveActiveBid()
  if not (sepgp.bid_item and sepgp.bid_item.linkFull) then
    sepgp:writeDebugLog("BID_AUTO_RESOLVE | SKIP | no bid_item")
    return
  end
  local itemLink = sepgp.bid_item.linkFull
  local data = {
    [sepgp.loot_index.time] = date("%H:%M"),
    [sepgp.loot_index.item] = itemLink,
    [sepgp.loot_index.bind] = sepgp.VARS.bop,
    [sepgp.loot_index.price] = sepgp.bid_item.price or 0,
    [sepgp.loot_index.off_price] = sepgp.bid_item.off_price or 0,
  }
  sepgp:writeDebugLog("BID_AUTO_RESOLVE | " .. itemLink)
  sepgp._popupShownLinks = sepgp._popupShownLinks or {}
  sepgp._popupShownLinks[itemLink] = GetTime()
  sepgp:AutoResolveLoot(data)
end

-- Only the final N seconds are announced to raid chat; the earlier ticks of
-- a long timer (30, 25, 20...) stay silent so chat isn't spammed.
local COUNTDOWN_ANNOUNCE_FROM = 5

function sepgp_bids:countdownCounter()
  self._counter = (self._counter or (sepgp_bidtimer or sepgp.VARS.bidtimer)) - 1
  if GetNumRaidMembers()>0 and self._counter > 0 and self._counter <= COUNTDOWN_ANNOUNCE_FROM then
    self._counterText = C:Yellow(tostring(self._counter))
    sepgp:widestAudience(tostring(self._counter))
    --SendChatMessage(tostring(self._counter),"RAID")
  end
end

-- reset=true: (re)starting a fresh countdown -- just reset the display.
-- reset=false/nil: either the timer ran out naturally, or a row click
-- ended it early -- either way, resolve the bid now.
function sepgp_bids:countdownFinish(reset)
  if self:IsEventScheduled("shootyepgpBidCountdown") then
    self:CancelScheduledEvent("shootyepgpBidCountdown")
  end
  if self:IsEventScheduled("shootyepgpBidCountdownFinish") then
    self:CancelScheduledEvent("shootyepgpBidCountdownFinish")
  end
  self._counter = sepgp_bidtimer or sepgp.VARS.bidtimer
  if (reset) then
    self._counterText = C:Green("Starting")
  else
    self._counterText = C:Red("Finished")
    resolveActiveBid()
  end
end

-- Duration is configurable: /sepgp config -> "Bid Timer (seconds)",
-- saved per-character as sepgp_bidtimer (defaults to sepgp.VARS.bidtimer).
-- Called automatically the moment bids open (see BoW-EPGP.lua) -- the ML
-- no longer has to trigger this by hand.
function sepgp_bids:bidCountdown()
  self:countdownFinish(true)
  local duration = sepgp_bidtimer or sepgp.VARS.bidtimer
  self:ScheduleRepeatingEvent("shootyepgpBidCountdown",self.countdownCounter,1,self)
  self:ScheduleEvent("shootyepgpBidCountdownFinish",self.countdownFinish,duration,self)
end

-- GLOBALS: sepgp_saychannel,sepgp_groupbyclass,sepgp_groupbyarmor,sepgp_groupbyrole,sepgp_raidonly,sepgp_decay,sepgp_minep,sepgp_reservechannel,sepgp_main,sepgp_progress,sepgp_discount,sepgp_log,sepgp_dbver,sepgp_looted
-- GLOBALS: sepgp,sepgp_prices,sepgp_standings,sepgp_bids,sepgp_loot,sepgp_reserves,sepgp_alts,sepgp_logs
