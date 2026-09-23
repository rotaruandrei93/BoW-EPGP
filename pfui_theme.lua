-------------------------------------------------------------------------
-- pfUI theme integration
--
-- When the pfUI addon (https://github.com/brues-code/pfUI, and the
-- upstream shagu/pfUI it's forked from) is installed and enabled,
-- BoW-EPGP's custom windows (the bid popup, the loot display, the
-- standings export window, ...) re-skin themselves with pfUI's borders,
-- buttons and scrollbars instead of the default Blizzard tooltip
-- look, so they match the rest of a pfUI-themed UI.
--
-- pfUI support is entirely optional:
--  * every function here is a safe no-op when pfUI isn't loaded/enabled
--  * every pfUI API call is pcall-guarded, so a future pfUI update that
--    renames/removes a helper can't break BoW-EPGP's own frames -- run
--    "/sepgppfui debug" to see any errors that were swallowed
--  * this file has no dependency on the `sepgp` global or on load
--    order, so it can be loaded first in the .toc, before BoW-EPGP.lua
--    even exists -- important because some BoW-EPGP frames are created
--    at file scope (i.e. before we can be sure pfUI has finished
--    loading, depending on alphabetical addon load order)
--
-- Global: sepgp_pfui
-- Slash:  /sepgppfui        -- status + forces a re-theme, reporting errors
--         /sepgppfui debug  -- toggles verbose logging of every skin call
-------------------------------------------------------------------------

sepgp_pfui = sepgp_pfui or {}
sepgp_pfui.debug = false

local registered = {}
local lastErrors = {}

local function dprint(msg)
  if sepgp_pfui.debug then
    DEFAULT_CHAT_FRAME:AddMessage("|cff9664c8[pfUI theme]|r " .. tostring(msg))
  end
end

-- [ IsEnabled ]
-- pfUI publishes itself as a global frame named after its addon folder
-- (normally "pfUI"), with a `.api` table full of skinning helpers once
-- its own files have finished loading. Both must be present.
function sepgp_pfui.IsEnabled()
  return type(_G.pfUI) == "table" and type(_G.pfUI.api) == "table"
end

-- Runs pfUI.api[name](...). Never throws -- a future pfUI update that
-- renames/removes a helper, or a call made before pfUI has fully
-- initialized (its saved-variable config table isn't ready yet), can't
-- break BoW-EPGP's own windows. The failure is recorded (and, in debug
-- mode, printed) instead of silently vanishing.
local function callapi(name, ...)
  if not sepgp_pfui.IsEnabled() then
    lastErrors[name] = "pfUI not detected"
    return false
  end
  local fn = pfUI.api[name]
  if type(fn) ~= "function" then
    lastErrors[name] = "pfUI.api." .. name .. " does not exist"
    dprint(lastErrors[name])
    return false
  end
  local ok, err = pcall(fn, ...)
  if ok then
    lastErrors[name] = nil
    dprint(name .. " OK")
  else
    lastErrors[name] = err
    dprint(name .. " FAILED: " .. tostring(err))
  end
  return ok
end

-- [ SkinFrame ]
-- Applies pfUI's backdrop (and optional drop shadow) to a frame,
-- replacing whatever plain SetBackdrop() it already has.
-- 'frame'   the frame to skin
-- 'inset'   optional custom border inset (nil = pfUI's own default)
-- 'shadow'  if true, also adds pfUI's backdrop shadow
-- 'transp'  optional panel opacity (0-1); only ever lowers pfUI's own
--           configured background alpha, never raises it
-- 'legacy'  if true, restyles the frame's OWN SetBackdrop() in place
--           instead of overlaying a separate child frame. Needed for
--           frames (like Tablet-2.0's) that keep calling their own
--           SetBackdropColor()/SetBackdropBorderColor() afterwards --
--           in the default (non-legacy) mode those calls would keep
--           hitting the now-cleared original backdrop instead of
--           pfUI's overlay, and silently do nothing.
function sepgp_pfui.SkinFrame(frame, inset, shadow, legacy, transp)
  if not frame then return false end
  local applied = callapi("CreateBackdrop", frame, inset, legacy, transp)
  if applied and shadow then
    callapi("CreateBackdropShadow", frame)
  end
  return applied
end

-- [ SkinButton ]
-- Skins a UIPanelButtonTemplate-style button.
function sepgp_pfui.SkinButton(button, r, g, b)
  return callapi("SkinButton", button, r, g, b)
end

-- [ SkinCloseButton ]
-- Skins a UIPanelCloseButton, optionally re-anchoring it.
function sepgp_pfui.SkinCloseButton(button, parentFrame, offsetX, offsetY)
  return callapi("SkinCloseButton", button, parentFrame, offsetX, offsetY)
end

-- [ SkinScrollbar ]
-- Skins the scrollbar spawned by UIPanelScrollFrameTemplate.
-- 'frame'  the ScrollBar frame itself (e.g. _G[scrollFrameName.."ScrollBar"])
function sepgp_pfui.SkinScrollbar(frame, always)
  return callapi("SkinScrollbar", frame, always)
end

-- [ StripTextures ]
-- Hides a frame's own hand-placed Blizzard border/background textures
-- (e.g. Dewdrop-2.0's EditBox popup, which draws its border as two
-- BACKGROUND-layer textures directly on the EditBox instead of using
-- SetBackdrop) so they stop covering up a backdrop skin applied
-- underneath them.
function sepgp_pfui.StripTextures(frame)
  return callapi("StripTextures", frame)
end

-- [ SkinTooltip ]
-- Skins a custom GameTooltip (one created via CreateFrame("GameTooltip",
-- ..., "GameTooltipTemplate"), like BoW-EPGP's item-comparison tooltip).
-- pfUI only auto-skins Blizzard's own named tooltips, not addon-created
-- ones, so this mirrors the same call pfUI-addonskinner's own shootyepgp
-- skin (github.com/jrc13245/pfUI-addonskinner) uses for this tooltip.
function sepgp_pfui.SkinTooltip(tooltip)
  if not tooltip then return false end
  local alpha
  if type(pfUI_config) == "table" and type(pfUI_config.tooltip) == "table" then
    alpha = tonumber(pfUI_config.tooltip.alpha)
  end
  return callapi("CreateBackdrop", tooltip, nil, nil, alpha)
end

-- [ GetLastError ]
-- Exposes the last recorded error/status for a given pfUI.api call name
-- (as set by callapi above), for other files' own diagnostic reporting
-- (e.g. dewdrop_pfui_skin.lua's on-demand dump) without needing their
-- own copy of the pcall-wrapping logic.
function sepgp_pfui.GetLastError(name)
  return lastErrors[name]
end

-- [ Register ]
-- Registers a window to be (re-)themed via `applyfunc` whenever pfUI's
-- availability may have changed. Needed for windows created at file
-- scope, since we can't be sure pfUI has already loaded at that point.
-- Applies immediately too, so lazily-created windows (built well after
-- login, e.g. on first use) pick up the theme on the spot.
-- 'frame'     the window (only used as a dedupe/identity key)
-- 'applyfunc' function() that (re-)applies the current theme to it;
--             must be safe to call more than once.
function sepgp_pfui.Register(frame, applyfunc)
  if not frame or not applyfunc then return end
  table.insert(registered, {frame = frame, apply = applyfunc})
  if sepgp_pfui.IsEnabled() then applyfunc() end
end

local function reapplyAll()
  if not sepgp_pfui.IsEnabled() then return end
  dprint("re-theming " .. table.getn(registered) .. " window(s)")
  for _, entry in ipairs(registered) do
    entry.apply()
  end
end
sepgp_pfui.ReapplyAll = reapplyAll

-- Re-themes every registered window once pfUI has actually finished
-- loading, in case BoW-EPGP's own files loaded first. ADDON_LOADED("pfUI")
-- alone is NOT reliable for this: it's broadcast to every frame that
-- registered for it, in registration order -- and because BoW-EPGP loads
-- before pfUI alphabetically, our watcher registers first and so can be
-- notified before pfUI's own ADDON_LOADED handler has actually finished
-- merging its saved-variable defaults, which the pfUI skin calls above
-- depend on.
--
-- VARIABLES_LOADED doesn't have that problem: it's a single, global
-- broadcast that only fires once every addon's saved variables (and thus
-- every addon's own ADDON_LOADED-driven setup, pfUI's included, since
-- that necessarily happens first) have finished loading -- this is the
-- same trigger pfUI's own addonskinner module
-- (github.com/jrc13245/pfUI-addonskinner) uses for exactly this reason.
-- PLAYER_LOGIN and a short poll afterwards are kept as extra safety nets.
local poll = CreateFrame("Frame")
local pollUntil, nextTick = 0, 0

-- Native Frame:HookScript() isn't available on this client (vanilla
-- 1.12 API, without ClassicAPI's compat shim), so both jobs live in a
-- single OnEvent handler instead of layering a second one on top.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:RegisterEvent("VARIABLES_LOADED")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" and arg1 ~= "pfUI" then return end
  if event == "VARIABLES_LOADED" or event == "PLAYER_LOGIN" then
    pollUntil = GetTime() + 10
    nextTick = 0
    poll:Show()
  end
  reapplyAll()
end)

poll:Hide()
poll:SetScript("OnUpdate", function()
  if GetTime() >= pollUntil then
    poll:Hide()
    return
  end
  if GetTime() < nextTick then return end
  nextTick = GetTime() + 1
  reapplyAll()
end)

-- [ Slash command ]
-- /sepgppfui        prints detection status and forces an immediate
--                   re-theme, reporting any error from the last attempt
--                   at each pfUI API call.
-- /sepgppfui debug  toggles verbose per-call logging.
-- /sepgppfui test   shows every registered window on screen for a visual
--                   check, without needing a live bid/loot/export event.
--                   Run it again to hide them.
-- /sepgppfui dewdrop  one-shot: reports right now, in chat, exactly what
--                   state the Dewdrop-2.0 slider/edit-box popups are in
--                   and whether skinning them just succeeded or failed --
--                   no debug toggle, no timing a menu staying open.
--                   (Defined in dewdrop_pfui_skin.lua; safe no-op here
--                   if that file hasn't loaded for some reason.)
SLASH_SEPGPPFUI1 = "/sepgppfui"
SlashCmdList["SEPGPPFUI"] = function(msg)
  msg = string.lower(msg or "")
  if msg == "debug" then
    sepgp_pfui.debug = not sepgp_pfui.debug
    DEFAULT_CHAT_FRAME:AddMessage("|cff9664c8[pfUI theme]|r debug logging " .. (sepgp_pfui.debug and "ON" or "OFF"))
    return
  end

  if msg == "dewdrop" then
    if sepgp_pfui.DewdropDiag then
      sepgp_pfui.DewdropDiag()
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cff9664c8[pfUI theme]|r dewdrop_pfui_skin.lua isn't loaded -- can't run this diagnostic.")
    end
    return
  end

  if msg == "test" then
    reapplyAll()
    for _, entry in ipairs(registered) do
      if entry.frame:IsShown() then entry.frame:Hide() else entry.frame:Show() end
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff9664c8[pfUI theme]|r toggled " .. table.getn(registered) .. " window(s) for a visual check.")
    return
  end

  DEFAULT_CHAT_FRAME:AddMessage("|cff9664c8[pfUI theme]|r pfUI addon loaded: " .. (IsAddOnLoaded and (IsAddOnLoaded("pfUI") and "yes" or "no") or "unknown"))
  DEFAULT_CHAT_FRAME:AddMessage("|cff9664c8[pfUI theme]|r _G.pfUI: " .. type(_G.pfUI) .. (type(_G.pfUI) == "table" and (_G.pfUI.api and ", .api present" or ", .api MISSING") or ""))
  DEFAULT_CHAT_FRAME:AddMessage("|cff9664c8[pfUI theme]|r registered windows: " .. table.getn(registered))

  reapplyAll()

  local any = false
  for name, err in pairs(lastErrors) do
    any = true
    DEFAULT_CHAT_FRAME:AddMessage("|cff9664c8[pfUI theme]|r " .. name .. " last error: " .. tostring(err))
  end
  if not any and sepgp_pfui.IsEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage("|cff9664c8[pfUI theme]|r all skin calls reported success.")
  end
end
