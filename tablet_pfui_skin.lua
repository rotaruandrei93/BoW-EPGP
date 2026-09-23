-------------------------------------------------------------------------
-- pfUI theming for Tablet-2.0 windows (standings/loot/reserves/logs/
-- alts) -- applied from OUTSIDE the vendored library.
--
-- Tablet-2.0 is shared by many addons and reuses the same
-- Tablet20Frame / Tablet20DetachedFrame<N> globals. A child overlay
-- can't be used to fake the skin without touching the shared frame:
-- Tablet-2.0's own SetBackdrop() border/background is part of the
-- frame itself, always drawn underneath a same-or-lower-level child --
-- and raising a child ABOVE that level to get on top of it also
-- covers the frame's own buttons/text, which live at that same level
-- too. Confirmed by testing: the overlay version showed no pfUI
-- styling at all, just the plain default look.
--
-- So this reskins the real shared frame directly (pfUI's own "legacy"
-- mode, needed anyway since Tablet-2.0 keeps calling its own
-- SetBackdropColor()/SetBackdropBorderColor() on it afterwards) -- but
-- restores it to Tablet-2.0's own stock backdrop (the exact table/
-- colors Tablet-2.0 itself sets when it first creates these frames --
-- see AcquireDetachedFrame() and the Tablet20Frame creation branch in
-- Libs\Tablet-2.0\Tablet-2.0.lua, copied verbatim below) the instant
-- the frame stops belonging to us, so whichever addon reuses the
-- pooled frame next gets it back in stock condition, not mid-BoW-skin.
-------------------------------------------------------------------------

-- Tablet-2.0's own default backdrop, copied verbatim from its frame
-- creation code so restoring it doesn't depend on a vanilla API
-- (frame:GetBackdrop()) this client may not actually have -- this
-- addon has already hit one method, SetMouseMotionEnabled, that
-- turned out not to exist here despite looking plausible.
local STOCK_BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8X8",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true,
  tileSize = 16,
  edgeSize = 16,
  insets = { left = 5, right = 5, top = 5, bottom = 5 },
}

local skinned = {}      -- frame -> true while our pfUI skin is currently applied
local closeButtons = {}

local function isOurs(frame)
  if not frame then return false end
  local owner = frame.owner
  if type(owner) == "string" then
    return string.find(owner, "^sepgp") ~= nil
  end
  -- The FuBar / minimap-button hover tooltip ("Hint: Click to toggle
  -- Standings...") isn't opened with one of our string owners like the
  -- standings/loot/... windows are: Tablet-2.0 sets its owner to the
  -- plugin's own icon frame (the minimap button, or the FuBar panel
  -- frame). That frame is the same ownership signal
  -- dewdrop_pfui_skin.lua uses for the options menu.
  if type(owner) == "table" and sepgp then
    return owner == sepgp.minimapFrame or owner == sepgp.frame
  end
  return false
end

local function restoreStock(frame)
  if not skinned[frame] then return end
  skinned[frame] = nil
  frame:SetBackdrop(STOCK_BACKDROP)
  frame:SetBackdropColor(frame.r or 0, frame.g or 0, frame.b or 0, frame.transparency or 0.75)
  frame:SetBackdropBorderColor(1, 1, 1, frame.transparency or 0.75)
end

-- Tablet-2.0's color picker / opacity slider (right-click a window ->
-- "Color") writes to frame.r/.g/.b/.transparency and calls
-- SetBackdropColor() itself. pfUI's legacy CreateBackdrop replaces the
-- backdrop *table* but doesn't know about that per-window tint, so
-- reapply it after every skin -- keeps a user's picked color showing
-- through the pfUI border instead of snapping back to pfUI's own
-- default color.
local function applyUserColors(frame)
  local r, g, b = frame.r or 0, frame.g or 0, frame.b or 0
  local a = frame.transparency or 0.75
  local custom = r ~= 0 or g ~= 0 or b ~= 0 or math.abs(a - 0.75) > 0.005
  if custom then
    frame:SetBackdropColor(r, g, b, a)
  end
end

local function updateCloseButton(frame)
  if not frame or frame == _G.Tablet20Frame then return end

  local btn = closeButtons[frame]
  if not btn then
    if not isOurs(frame) then return end
    btn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    btn:SetScript("OnClick", function() frame:Hide() end)
    sepgp_pfui.SkinCloseButton(btn, frame, -6, -6)
    closeButtons[frame] = btn
  end

  if isOurs(frame) then btn:Show() else btn:Hide() end
end

local function reskin(frame)
  if not frame then return end
  if isOurs(frame) then
    local ok = sepgp_pfui.SkinFrame(frame, nil, nil, true)
    if ok then
      skinned[frame] = true
      applyUserColors(frame)
    end
  else
    restoreStock(frame)
  end
  updateCloseButton(frame)
end

local function scan()
  local tooltip = _G.Tablet20Frame
  if tooltip then reskin(tooltip) end

  local i = 1
  while true do
    local frame = _G["Tablet20DetachedFrame" .. i]
    if not frame then break end
    reskin(frame)
    i = i + 1
  end
end

local poller = CreateFrame("Frame")
local nextReskin = 0
poller:SetScript("OnUpdate", function()
  scan()
  -- Self-heal against Tablet-2.0's own periodic/hover recoloring, same
  -- as before -- but only for frames that are actually ours right now.
  if GetTime() >= nextReskin then
    nextReskin = GetTime() + 1
    for frame in pairs(skinned) do
      if isOurs(frame) then
        sepgp_pfui.SkinFrame(frame, nil, nil, true)
        applyUserColors(frame)
      end
    end
  end
end)
