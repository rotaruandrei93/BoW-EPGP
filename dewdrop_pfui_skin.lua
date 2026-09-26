-------------------------------------------------------------------------
-- pfUI theming for Dewdrop-2.0 menus used by BoW-EPGP (the minimap-
-- button options menu and its submenus/slider/edit-box popups).
--
-- Dewdrop-2.0 is a SINGLE shared popup pool used by many addons, and
-- its level/slider/edit-box frames are created once ever and reused
-- forever after -- confirmed by reading AcquireLevel()/OpenSlider()/
-- OpenEditBox() in Libs\Dewdrop-2.0\Dewdrop-2.0.lua: each one only
-- calls SetBackdrop()/SetBackdropColor()/SetBackdropBorderColor()
-- inside an `if not <frame> then ... end` guard -- i.e. exactly once,
-- the very first time that particular level/popup is ever opened by
-- ANY addon. Whatever look is on it after that stays until something
-- else changes it -- which is exactly how BoW-EPGP's pfUI skin used to
-- bleed into aux/pfUI's own Dewdrop menus.
--
-- An earlier version tried to avoid touching the shared frames at all
-- by skinning a separate child overlay instead. That doesn't work: a
-- frame's own SetBackdrop() border/background is part of the frame
-- itself and always draws underneath a same-or-lower-level child, and
-- raising the child ABOVE that level to get on top of it also covers
-- the frame's own menu-item buttons/text (they sit at that same
-- level), hiding them completely. Confirmed by testing: the overlay
-- version showed no pfUI styling at all, just the plain default look.
--
-- So this reskins the real shared frames directly (in pfUI's "legacy"
-- mode, which rewrites SetBackdrop() in place -- the only mode that
-- visibly changed anything on this client), but:
--   1. only while the CURRENTLY OPEN Dewdrop menu belongs to BoW-EPGP
--      (Dewdrop:GetOpenedParent(), the one reliable ownership signal
--      Dewdrop-2.0 exposes)
--   2. restored back to Dewdrop-2.0's own stock backdrop/colors (the
--      exact values AcquireLevel()/OpenSlider()/OpenEditBox() set at
--      creation, copied verbatim below) the instant BoW-EPGP is no
--      longer the owner -- so whichever addon's menu opens next gets
--      the frame back in stock condition, not mid-BoW-skin.
--
-- The slider/edit-box POPUP HOST (the panel) follows the same
-- ownership-gated, restore-on-handoff rule as the dropdown levels
-- above. The Slider/EditBox WIDGET inside it is different: pfUI has to
-- call StripTextures() on it to make it look right, and that can't be
-- undone, so once BoW-EPGP skins it, it stays pfUI-styled for every
-- addon's slider/edit-box popups for the rest of the session. This was
-- left plain on purpose at first; skinning it anyway (accepting that
-- one-time, purely cosmetic, non-restorable bleed) was a deliberate
-- choice made later -- see skinPopupWidget() below.
-------------------------------------------------------------------------

-- Dewdrop-2.0's own default backdrop shape -- identical for every
-- level's backdrop child, the slider popup host, and the edit-box
-- popup host (all three use this exact table in the vendored
-- library). Hardcoded here rather than read back with
-- frame:GetBackdrop(), which this client's API may not actually have
-- (see tablet_pfui_skin.lua for the same reasoning -- this addon has
-- already hit one method, SetMouseMotionEnabled, that turned out not
-- to exist here despite looking plausible).
local STOCK_BACKDROP = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true,
  tileSize = 16,
  edgeSize = 16,
  insets = { left = 5, right = 5, top = 5, bottom = 5 },
}

local D
local skinned = {} -- frame -> true while our pfUI skin is currently applied

-- Dewdrop:GetOpenedParent() returns whatever object was passed as the
-- owning "parent" to Dewdrop:Open(...) for the currently open menu.
-- Two different call paths matter here:
--   1. BoW-EPGP's own minimap/FuBar options menu, which always opens
--      with sepgp.frame (FuBarPlugin-2.0's self:GetFrame()) as that
--      parent -- see the two Dewdrop:Open(...) call sites in
--      Libs\FuBarPlugin-2.0\FuBarPlugin-2.0.lua, both of which pass
--      self:GetFrame() (== sepgp.frame). sepgp.minimapFrame is checked
--      too as a fallback in case a future call path passes it
--      directly instead.
--   2. Tablet-2.0's own built-in right-click menu on a detached window
--      ("Lock" / "Background color" / "Size" / "Close menu" / etc,
--      registered via Dewdrop:Register(detached, ...) in
--      Libs\Tablet-2.0\Tablet-2.0.lua), which opens with the detached
--      Tablet20DetachedFrame<N> (or Tablet20Frame) itself as the
--      parent. Whether THAT belongs to BoW-EPGP is tracked the same
--      way tablet_pfui_skin.lua already tracks it: frame.owner, a
--      string starting with "sepgp" that BoW's own code sets when it
--      acquires the pooled frame.
local function isBoWOwner(owner)
  if type(owner) ~= "table" then return false end
  if sepgp then
    if owner == sepgp.frame then return true end
    if owner == sepgp.minimapFrame then return true end
  end
  if type(owner.owner) == "string" and string.find(owner.owner, "^sepgp") then
    return true
  end
  return false
end

local function restoreStock(frame)
  if not skinned[frame] then return end
  skinned[frame] = nil
  frame:SetBackdrop(STOCK_BACKDROP)
  frame:SetBackdropBorderColor(TOOLTIP_DEFAULT_COLOR.r, TOOLTIP_DEFAULT_COLOR.g, TOOLTIP_DEFAULT_COLOR.b)
  frame:SetBackdropColor(TOOLTIP_DEFAULT_BACKGROUND_COLOR.r, TOOLTIP_DEFAULT_BACKGROUND_COLOR.g, TOOLTIP_DEFAULT_BACKGROUND_COLOR.b)
end

local function restoreAll()
  for frame in pairs(skinned) do
    restoreStock(frame)
  end
end

local function isDewdropLevel(frame)
  return frame and frame:GetParent() == UIParent
     and frame:GetFrameStrata() == "FULLSCREEN_DIALOG"
     and type(frame.num) == "number"
     and frame.lastDirection ~= nil
end

-- Identifies the slider/edit-box popup HOST (sliderFrame/editBoxFrame),
-- not the Slider/EditBox widget inside it: frame.parent (set by
-- OpenSlider()/OpenEditBox() to the menu-item button that opened the
-- popup) is a button belonging to one of Dewdrop's own levels.
local function isDewdropPopupHost(frame)
  if not frame then return false end
  local opener = frame.parent
  if type(opener) ~= "table" or not opener.GetParent then return false end
  return isDewdropLevel(opener:GetParent())
end

-- The Slider/EditBox widget living INSIDE a popup host. Unlike the
-- host's own backdrop (restored to stock the moment BoW stops owning
-- it, see restoreStock() above), this is intentionally NOT restored:
-- the edit box's hand-placed border art gets hidden and the widget's own
-- backdrop/thumb are replaced, with no "put them back" step. So once
-- this runs, that shared widget stays pfUI-styled
-- for every addon that opens a Dewdrop slider/edit-box popup for the
-- rest of the session -- a deliberate, accepted trade-off (purely
-- cosmetic, not a settings/behavior leak) rather than a bug. Tracked
-- separately from `skinned` and never cleared, since re-running
-- the skin on it every scan would be pointless once
-- it's already done.
local widgetSkinned = {}

-- Slider widget: DON'T run StripTextures() on it. Dewdrop draws the
-- slider's track with SetBackdrop() (nothing hand-placed to strip), and
-- the ONLY texture region a Slider has is its thumb -- StripTextures()
-- blanks every region, so it was erasing the thumb. Instead: re-skin the
-- track backdrop (dark, same border as the edit box), give the thumb a
-- solid dark-gray block with an explicit size (a solid-color thumb has no native
-- texture size to fall back on), and make the min/max values at the top
-- and bottom white instead of Dewdrop's default green.
local function skinSliderWidget(slider, host)
  local ok = sepgp_pfui.SkinFrame(slider, nil, nil, true)
  if not ok then return false end
  pcall(function()
    -- Same near-black fill as the edit box; the border is left at
    -- pfUI's own border color (what SkinFrame just applied), which is
    -- exactly what the edit box uses, so the two match.
    slider:SetBackdropColor(0.03, 0.03, 0.03, 1)
    local thumb = slider:GetThumbTexture()
    if thumb then
      thumb:SetTexture(0.35, 0.35, 0.35, 1)
      thumb:SetWidth(slider:GetWidth())
      thumb:SetHeight(12)
      thumb:Show()
    end
    if host then
      if host.topText then host.topText:SetTextColor(1, 1, 1) end
      if host.bottomText then host.bottomText:SetTextColor(1, 1, 1) end
    end
  end)
  return true
end

-- Edit-box widget: styled like pfUI's own popup/dialog edit boxes
-- (skins/blizzard/popup_dialogs.lua and CreateQuestionDialog in the pfUI
-- repo): flat dark field with a thin border, 18px tall, the client's
-- native blinking caret.
--
-- DON'T run StripTextures() on it. That call blanks EVERY texture region
-- on the frame, and on this client the native text caret appears to be
-- one of them -- that is why the cursor never showed up, in any build,
-- while the field was skinned. Only Dewdrop's own hand-placed
-- UI-ChatInputBorder-Left/Right art needs hiding, so that's all this
-- touches (matched by texture path; everything else, caret included, is
-- left alone).
--
-- The border goes on the EditBox ITSELF (pfUI "legacy" backdrop) rather
-- than on a child overlay frame: OpenEditBox() re-sets the edit box's
-- frame level every time the popup opens, and a child overlay would be
-- left behind at a stale level (hidden under the panel, or double-drawn).
local function skinEditBoxWidget(box)
  pcall(function()
    local regions = { box:GetRegions() }
    for _, r in ipairs(regions) do
      if r.GetTexture and r.SetTexture then
        local tex = r:GetTexture()
        if type(tex) == "string" and string.find(string.lower(tex), "chatinputborder") then
          r:SetTexture(nil)
          r:Hide()
        end
      end
    end
  end)
  local ok = sepgp_pfui.SkinFrame(box, nil, nil, true)
  if not ok then return false end
  pcall(function()
    box:SetBackdropColor(0.03, 0.03, 0.03, 1)
    box:SetHeight(18)
    box:SetTextInsets(4, 4, 0, 0)
  end)
  return true
end

local function skinPopupWidget(host)
  if not host then return end
  local widget = host.slider or host.editBox
  if not widget or widgetSkinned[widget] then return end
  local ok
  if host.slider then
    ok = skinSliderWidget(widget, host)
  else
    ok = skinEditBoxWidget(widget)
  end
  if ok then widgetSkinned[widget] = true end
end

-- Panel opacity: the main menu (Dewdrop level 1) is drawn SOLID, using
-- pfUI's own background color at full alpha; every submenu level and the
-- slider / edit-box popups are translucent at 0.75, the same value
-- pfUI's skin uses for Blizzard's popup dialogs (it only ever LOWERS
-- pfUI's configured alpha, never raises it).
local PANEL_ALPHA = 0.75

local function makeSolid(frame)
  pcall(function()
    local r, g, b = pfUI.api.GetStringColor(pfUI_config.appearance.border.background)
    frame:SetBackdropColor(tonumber(r), tonumber(g), tonumber(b), 1)
  end)
end

local function skinFrame(frame)
  if not frame or skinned[frame] then return end
  local parent = frame:GetParent()
  local isMainMenu = parent and parent ~= UIParent and parent.num == 1
  local ok = sepgp_pfui.SkinFrame(frame, nil, nil, true, (not isMainMenu) and PANEL_ALPHA or nil)
  if ok then
    skinned[frame] = true
    if isMainMenu then makeSolid(frame) end
    if isDewdropPopupHost(frame) then
      skinPopupWidget(frame)
    end
  end
end

-- Finding the frames to skin, without a per-open (or per-tick) walk of
-- every frame in the client.
--
-- Dewdrop creates each of its level / slider-popup / edit-box-popup
-- frames once, lazily, and reuses them forever. EnumerateFrames() hands
-- back frames in creation order and can RESUME from any frame you give
-- it, so instead of re-walking the whole client every time a menu opens
-- (what caused the FPS drop, and what made the first open after a
-- login/reload lag behind with the old look), this:
--   * ingests the client's existing frames once, a few hundred per tick,
--     shortly after login (nobody sees or feels it), and afterwards only
--     ever looks at frames created since the last look -- normally none,
--     which is one cheap call;
--   * keeps a short list of the Dewdrop frames it found (`targets`);
--     skinning on menu open / hover is just a loop over that handful;
--   * installs an OnShow on each of those pooled frames (only where the
--     frame has none of its own) so a re-shown level/popup is skinned in
--     the same call that shows it, before it can be drawn -- and a
--     brand-new frame is picked up on the very next tick;
--   * still runs one full walk every couple of seconds while our menu is
--     open, purely as a safety net in case this client doesn't list
--     frames in creation order.
local CATCHUP_BUDGET = 300  -- frames examined per tick while catching up
local IDLE_INTERVAL = 0.5   -- seconds between "anything new?" checks
local SAFETY_INTERVAL = 2   -- seconds between safety full walks (menu open)

local targets = {}   -- ordered list of frames to skin
local isTarget = {}  -- frame -> true
local hooked = {}    -- frame -> true once we've tried to hook its OnShow
local lastFrame      -- where the incremental EnumerateFrames() walk stopped
local caughtUp = false
local nextIdleWalk = 0
local nextSafetyWalk = 0
local wasOwner = false
local scan

local function onDewdropShow()
  if D then scan() end
end

local function hookShow(frame)
  if hooked[frame] then return end
  hooked[frame] = true
  pcall(function()
    if not frame:GetScript("OnShow") then
      frame:SetScript("OnShow", onDewdropShow)
    end
  end)
end

local function addTarget(frame, shower)
  if not isTarget[frame] then
    isTarget[frame] = true
    table.insert(targets, frame)
  end
  hookShow(shower)
end

-- EnumerateFrames() can hand back objects that don't support the full
-- widget API on this client (e.g. an internal/engine object that isn't
-- a real Lua-side Frame) -- calling GetObjectType()/GetParent() on one
-- of those throws "attempt to call method '...' (a nil value)" even
-- though `frame` itself isn't nil. pcall guards against that and just
-- skips the object instead of tainting the whole walk() loop.
local function visit(frame)
  if isTarget[frame] then return end
  pcall(function()
    if frame:GetObjectType() ~= "Frame" then return end
    local parent = frame:GetParent()
    if parent and isDewdropLevel(parent) then
      addTarget(frame, parent)   -- a level's backdrop child
    elseif isDewdropPopupHost(frame) then
      addTarget(frame, frame)    -- slider / edit-box popup panel
    end
  end)
end

-- EnumerateFrames(after) can hard-error on this client ("Couldn't find
-- 'this' in current object") instead of returning nil, when `after` is
-- a frame handle that's since been invalidated/destroyed. pcall guards
-- every call; on failure we return nil (treated the same as "no more
-- frames for now") and the caller resets its resume point so it starts
-- clean again instead of hitting the same bad handle every tick.
local function safeNextFrame(after)
  local ok, frame = pcall(EnumerateFrames, after)
  if ok then return frame end
  return nil, true -- second value: the handle itself was bad
end

-- Looks at frames created since the last call, at most `budget` of them.
-- Returns true once it has reached the end of the client's frame list.
local function walk(budget)
  local frame, badHandle = safeNextFrame(lastFrame)
  if badHandle then
    lastFrame = nil
    return false
  end
  local n = 0
  while frame do
    visit(frame)
    lastFrame = frame
    n = n + 1
    if n >= budget then return false end
    local nextFrame
    nextFrame, badHandle = safeNextFrame(frame)
    if badHandle then
      lastFrame = nil
      return false
    end
    frame = nextFrame
  end
  return true
end

local function fullWalk()
  local frame = safeNextFrame(nil)
  while frame do
    visit(frame)
    local badHandle
    frame, badHandle = safeNextFrame(frame)
    if badHandle then return end
  end
end

local function skinTargets()
  for i = 1, table.getn(targets) do
    local frame = targets[i]
    if not skinned[frame] then skinFrame(frame) end
  end
end

function scan()
  local opened = D:GetOpenedParent()

  if not isBoWOwner(opened) then
    if wasOwner then
      -- Ownership just left us. Put back stock Dewdrop styling on
      -- anything we'd previously skinned, so it's clean for whoever
      -- uses it next. Cheap: only iterates frames we've skinned.
      restoreAll()
      wasOwner = false
    end
    -- Idle: keep the target list current in the background -- a chunk
    -- per tick while catching up after login, then just a cheap check
    -- twice a second.
    local now = GetTime()
    if now >= nextIdleWalk then
      nextIdleWalk = now + (caughtUp and IDLE_INTERVAL or 0)
      caughtUp = walk(caughtUp and 1000000000 or CATCHUP_BUDGET)
    end
    return
  end

  local now = GetTime()
  if not wasOwner then
    wasOwner = true
    nextSafetyWalk = now + SAFETY_INTERVAL
  end

  -- Our menu is open: pick up anything created since the last look
  -- (finishing the initial catch-up in one go if the player beat it),
  -- then skin the handful of known frames. No throttle -- this is a
  -- near-empty walk plus a short loop -- so a new submenu or popup is
  -- skinned the tick it appears.
  walk(1000000000)
  caughtUp = true
  skinTargets()

  if now >= nextSafetyWalk then
    nextSafetyWalk = now + SAFETY_INTERVAL
    fullWalk()
    skinTargets()
  end
end

local poller = CreateFrame("Frame")
poller:SetScript("OnUpdate", function()
  if not D then
    if AceLibrary and AceLibrary:HasInstance("Dewdrop-2.0") then
      D = AceLibrary("Dewdrop-2.0")
    else
      return
    end
  end
  scan()
end)

function sepgp_pfui.DewdropDiag()
  DEFAULT_CHAT_FRAME:AddMessage("|cff9664c8[pfUI theme]|r [dewdrop] direct-skin, ownership-gated, stock-restore-on-handoff")
  DEFAULT_CHAT_FRAME:AddMessage("|cff9664c8[pfUI theme]|r [dewdrop] AceLibrary(\"Dewdrop-2.0\") acquired: " .. tostring(D ~= nil))
  if D then
    DEFAULT_CHAT_FRAME:AddMessage("|cff9664c8[pfUI theme]|r [dewdrop] opened parent: " .. tostring(D:GetOpenedParent()))
  end
  DEFAULT_CHAT_FRAME:AddMessage("|cff9664c8[pfUI theme]|r [dewdrop] known dewdrop frame(s): " .. table.getn(targets) .. ", initial frame catch-up done: " .. tostring(caughtUp))
  local n = 0
  for _ in pairs(skinned) do n = n + 1 end
  DEFAULT_CHAT_FRAME:AddMessage("|cff9664c8[pfUI theme]|r [dewdrop] currently skinned frame(s): " .. n)
  local w = 0
  for _ in pairs(widgetSkinned) do w = w + 1 end
  DEFAULT_CHAT_FRAME:AddMessage("|cff9664c8[pfUI theme]|r [dewdrop] slider/editbox widget(s) permanently skinned this session: " .. w)
end
