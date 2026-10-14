-- unitmenu.lua
-- "Set Banker" / "Set Disenchanter" in the right-click unit menu (player frame,
-- party/raid frames, raid roster). Picking one feeds BoW-EPGP directly:
--   Set Banker       -> /banker Name
--   Set Disenchanter -> adds Name to the DE roster and makes them the first choice
-- With pfUI (advanced loot menus on) pfUI's own two entries are used and we just
-- listen to the clicks; without pfUI the same two entries are added to the normal
-- Blizzard menu. Only shown to (and usable by) the raid leader, raid assistants and the
-- master looter, on group members.
-- WoW 1.12 / Lua 5.0 compatible.

local ACTION = {
  PF_BANKLOOTER = "bank",
  PF_DISENCHANTLOOTER = "de",
  SEPGP_BANKER = "bank",
  SEPGP_DE = "de",
}

-- our own entries AND pfUI's bank/DE entries (pfUI shows those to everyone)
local function isOurs(value)
  return value == "SEPGP_BANKER" or value == "SEPGP_DE"
      or value == "PF_BANKLOOTER" or value == "PF_DISENCHANTLOOTER"
end

-- ---- click handling (works for pfUI's entries and ours) ----
local origOnClick = UnitPopup_OnClick
if origOnClick then
  UnitPopup_OnClick = function()
    local button = this and this.value
    origOnClick()
    local kind = button and ACTION[button]
    if not kind then return end
    local frame = getglobal(UIDROPDOWNMENU_INIT_MENU)
    local name = frame and frame.name
    if not name or name == "" then return end
    if not sepgp:canManageLoot() then sepgp:denyLootManage() return end
    if kind == "bank" then
      sepgp:SetBanker(name)
    else
      if sepgp:deRosterAdd(name) then
        sepgp_de_primary = sepgp:normalizeName(name)
        sepgp:defaultPrint(string.format("%s is now the first-choice disenchanter.", sepgp_de_primary))
      end
    end
  end
end

-- ---- visibility: only ML / raid leader, only for people in the group ----
local origHide = UnitPopup_HideButtons
if origHide then
  UnitPopup_HideButtons = function()
    origHide()
    local frame = getglobal(UIDROPDOWNMENU_INIT_MENU)
    if not frame or not frame.which or not UnitPopupMenus[frame.which] then return end
    local unit = frame.unit
    for index, value in ipairs(UnitPopupMenus[frame.which]) do
      if isOurs(value) then
        if not sepgp:canManageLoot() then
          UnitPopupShown[index] = 0
        end
        if unit and UnitIsPlayer(unit) and not (UnitInRaid(unit) or (UnitInParty(unit) and UnitExists("party1"))) then
          UnitPopupShown[index] = 0
        end
      end
    end
  end
end

-- ---- add our entries to the normal menu (only when pfUI isn't providing them) ----
local function addAfter(menuName, after)
  local menu = UnitPopupMenus and UnitPopupMenus[menuName]
  if not menu then return end
  for i = 1, table.getn(menu) do
    if menu[i] == after then
      table.insert(menu, i + 1, "SEPGP_BANKER")
      table.insert(menu, i + 1, "SEPGP_DE")
      return
    end
  end
end

local injected = false
local function inject()
  if injected then return end
  injected = true
  if UnitPopupButtons["PF_BANKLOOTER"] then return end  -- pfUI already shows them
  UnitPopupButtons["SEPGP_BANKER"] = { text = "Set Banker", dist = 0 }
  UnitPopupButtons["SEPGP_DE"] = { text = "Set Disenchanter", dist = 0 }
  addAfter("SELF", "LOOT_PROMOTE")
  addAfter("PARTY", "LOOT_PROMOTE")
  addAfter("PLAYER", "RAID_TARGET_ICON")
  addAfter("RAID", "RAID_REMOVE")
end

-- pfUI loads after us, so wait a moment after login before checking for its entries
local waiter = CreateFrame("Frame")
waiter:RegisterEvent("PLAYER_ENTERING_WORLD")
waiter:SetScript("OnEvent", function()
  this.t = 0
  this:SetScript("OnUpdate", function()
    this.t = this.t + arg1
    if this.t > 3 then
      this:SetScript("OnUpdate", nil)
      inject()
    end
  end)
  this:UnregisterEvent("PLAYER_ENTERING_WORLD")
end)
