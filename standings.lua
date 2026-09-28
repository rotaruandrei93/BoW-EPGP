local T = AceLibrary("Tablet-2.0")
local D = AceLibrary("Dewdrop-2.0")
local C = AceLibrary("Crayon-2.0")

local BC = AceLibrary("Babble-Class-2.2")
local L = AceLibrary("AceLocale-2.2"):new("shootyepgp")
local _G = getfenv(0)

-- forward declaration: the real definition lives with the table-look code
-- near the bottom of the file; OnTooltipUpdate calls it so the look is
-- hooked into the window before Tablet shows it for the first time
local hookStandingsTip

-- a single blank line sits between the window title and the table; the
-- table-look code (near the bottom of the file) resizes it to TITLE_GAP so
-- the actual gap is fixed and predictable no matter what Tablet or pfUI do
-- to line spacing
local TITLE_SPACER_LINES = 1

-- Dewdrop-2.0's right-click menu is its own top-level frame, not a child of
-- the Tablet standings window -- closing the window while that menu is
-- still open leaves it floating on screen with nothing to anchor to, which
-- also seems to be what leaves the standings window's own overlay skin not
-- coming back correctly next time it's opened. Force it closed any time we
-- close (or are about to close) the standings window ourselves.
local function closeSepgpMenu()
  if D and D.Close then
    pcall(D.Close, D)
  end
end

sepgp_standings = sepgp:NewModule("sepgp_standings", "AceDB-2.0")
local groupings = {
  "sepgp_groupbyclass",
  "sepgp_groupbyarmor",
  "sepgp_groupbyrole",
}
local PLATE, MAIL, LEATHER, CLOTH = 4,3,2,1
local DPS, CASTER, HEALER, TANK = 4,3,2,1
local class_to_armor = {
  PALADIN = PLATE,
  WARRIOR = PLATE,
  HUNTER = MAIL,
  SHAMAN = MAIL,
  DRUID = LEATHER,
  ROGUE = LEATHER,
  MAGE = CLOTH,
  PRIEST = CLOTH,
  WARLOCK = CLOTH,
}
local armor_text = {
  [CLOTH] = L["CLOTH"],
  [LEATHER] = L["LEATHER"],
  [MAIL] = L["MAIL"],
  [PLATE] = L["PLATE"],
}
local class_to_role = {
  PALADIN = {HEALER,DPS,TANK,CASTER},
  PRIEST = {HEALER,CASTER},
  DRUID = {HEALER,TANK,DPS,CASTER},
  SHAMAN = {HEALER,DPS,CASTER},
  MAGE = {CASTER},
  WARLOCK = {CASTER},
  ROGUE = {DPS},
  HUNTER = {DPS},
  WARRIOR = {TANK,DPS},
}
local role_text = {
  [TANK] = L["TANK"],
  [HEALER] = L["HEALER"],
  [CASTER] = L["CASTER"],
  [DPS] = L["PHYS DPS"],
}
local shooty_export = CreateFrame("Frame", "shooty_exportframe", UIParent)
shooty_export:SetWidth(250)
shooty_export:SetHeight(150)
shooty_export:SetPoint('TOP', UIParent, 'TOP', 0,-80)
shooty_export:SetFrameStrata('DIALOG')
shooty_export:Hide()
shooty_export:SetBackdrop({
  bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
  edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
  tile = true,
  tileSize = 16,
  edgeSize = 16,
  insets = {left = 5, right = 5, top = 5, bottom = 5}
  })
shooty_export:SetBackdropBorderColor(TOOLTIP_DEFAULT_COLOR.r, TOOLTIP_DEFAULT_COLOR.g, TOOLTIP_DEFAULT_COLOR.b)
shooty_export:SetBackdropColor(TOOLTIP_DEFAULT_BACKGROUND_COLOR.r, TOOLTIP_DEFAULT_BACKGROUND_COLOR.g, TOOLTIP_DEFAULT_BACKGROUND_COLOR.b)
shooty_export.action = CreateFrame("Button","shooty_exportaction", shooty_export, "UIPanelButtonTemplate")
shooty_export.action:SetWidth(100)
shooty_export.action:SetHeight(22)
shooty_export.action:SetPoint("BOTTOM",0,-20)
shooty_export.action:SetText("Import")
shooty_export.action:Hide()
shooty_export.action:SetScript("OnClick",function() sepgp_standings.import() end)
shooty_export.title = shooty_export:CreateFontString(nil,"OVERLAY")
shooty_export.title:SetPoint("TOP",0,-5)
shooty_export.title:SetFont("Fonts\\ARIALN.TTF", 12)
shooty_export.title:SetWidth(200)
shooty_export.title:SetJustifyH("LEFT")
shooty_export.title:SetJustifyV("CENTER")
shooty_export.title:SetShadowOffset(1, -1)
shooty_export.edit = CreateFrame("EditBox", "shooty_exportedit", shooty_export)
shooty_export.edit:SetMultiLine(true)
shooty_export.edit:SetAutoFocus(true)
shooty_export.edit:EnableMouse(true)
shooty_export.edit:SetMaxLetters(0)
shooty_export.edit:SetHistoryLines(1)
shooty_export.edit:SetFont('Fonts\\ARIALN.ttf', 12, 'THINOUTLINE')
shooty_export.edit:SetWidth(290)
shooty_export.edit:SetHeight(190)
shooty_export.edit:SetScript("OnEscapePressed", function() 
    shooty_export.edit:SetText("")
    shooty_export:Hide() 
  end)
shooty_export.edit:SetScript("OnEditFocusGained", function()
  shooty_export.edit:HighlightText()
end)
shooty_export.edit:SetScript("OnCursorChanged", function() 
  shooty_export.edit:HighlightText()
end)
shooty_export.AddSelectText = function(txt)
  shooty_export.edit:SetText(txt)
  shooty_export.edit:HighlightText()
end
shooty_export.scroll = CreateFrame("ScrollFrame", "shooty_exportscroll", shooty_export, 'UIPanelScrollFrameTemplate')
shooty_export.scroll:SetPoint('TOPLEFT', shooty_export, 'TOPLEFT', 8, -30)
shooty_export.scroll:SetPoint('BOTTOMRIGHT', shooty_export, 'BOTTOMRIGHT', -30, 8)
shooty_export.scroll:SetScrollChild(shooty_export.edit)
sepgp:make_escable("shooty_exportframe","add")

-- Re-skin with pfUI's border/button/scrollbar when pfUI is detected as
-- enabled, instead of the default Blizzard tooltip look set up above.
-- Registered (not just called once) because this frame is built at file
-- load time, before we can be sure pfUI has already finished loading.
sepgp_pfui.Register(shooty_export, function()
  sepgp_pfui.SkinFrame(shooty_export)
  sepgp_pfui.SkinButton(shooty_export.action)
  sepgp_pfui.SkinScrollbar(_G["shooty_exportscrollScrollBar"])
end)

function sepgp_standings:Export()
  shooty_export.action:Hide()
  shooty_export.title:SetText(C:Gold(L["Ctrl-C to copy. Esc to close."]))
  local t = {}
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    local ep = (sepgp:get_ep_v3(name,officernote) or 0) 
    local gp = (sepgp:get_gp_v3(name,officernote) or sepgp.VARS.basegp) 
    if ep > 0 then
      table.insert(t,{name,ep,gp,ep/gp})
    end
  end 
  table.sort(t, function(a,b)
      return tonumber(a[4]) > tonumber(b[4])
    end)
  shooty_export:Show()
  local txt = "Name;EP;GP;PR\n"
  for i,val in ipairs(t) do
    txt = string.format("%s%s;%d;%d;%.4f\n",txt,val[1],val[2],val[3],val[4])
  end
  shooty_export.AddSelectText(txt)
end

function sepgp_standings:Import()
  if not IsGuildLeader() then return end
  shooty_export.action:Show()
  shooty_export.title:SetText(C:Red("Ctrl-V to paste data. Esc to close."))
  shooty_export.AddSelectText(L.IMPORT_WARNING)
  shooty_export:Show()
end

function sepgp_standings.import()
  if not IsGuildLeader() then return end
  local text = shooty_export.edit:GetText()
  local t = {}
  local found
  for line in string.gfind(text,"[^\r\n]+") do
    local name,ep,gp,pr = sepgp:strsplit(";",line)
    ep,gp,pr = tonumber(ep),tonumber(gp),tonumber(pr)
    if (name) and (ep) and (gp) and (pr) then
      t[name]={ep,gp}
      found = true
    end
  end
  if (found) then
    local count = 0
    shooty_export.edit:SetText("")
    for i=1,GetNumGuildMembers(1) do
      local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
      local name_epgp = t[name]
      if (name_epgp) then
        count = count + 1
        --sepgp:debugPrint(string.format("%s {%s:%s}",name,name_epgp[1],name_epgp[2])) -- Debug
        sepgp:update_epgp_v3(name_epgp[1],name_epgp[2],i,name,officernote)
        t[name]=nil
      end
    end
    sepgp:defaultPrint(string.format(L["Imported %d members."],count))
    local report = string.format(L["Imported %d members.\n"],count)
    report = string.format(L["%s\nFailed to import:"],report)
    for name,epgp in pairs(t) do
      report = string.format("%s%s {%s:%s}\n",report,name,t[1],t[2])
    end
    shooty_export.AddSelectText(report)
  end
end

local class_cache = setmetatable({},{__index = function(t,k)
  local class
  if BC:HasReverseTranslation(k) then
    class = string.upper(BC:GetReverseTranslation(k))
  else
    class = string.upper(k)
  end
  if (class) then
    rawset(t,k,class)
    return class
  end
  return k
end})
function sepgp_standings:getArmorClass(class)
  class = class_cache[class]
  return class_to_armor[class] or 0
end

function sepgp_standings:getRolesClass(roster)
  local roster_num = table.getn(roster)
  for i=1,roster_num do
    local player = roster[i]
    local name, lclass, armor_class, ep, gp, pr = unpack(player)
    local class = class_cache[lclass]
    local roles = class_to_role[class]
    if not (roles) then
      player[3]=0
    else
      for i,role in ipairs(roles) do
        if i==1 then
          player[3]=role
        else
          table.insert(roster,{player[1],player[2],role,player[4],player[5],player[6]})
        end
      end      
    end
  end
  return roster
end 

function sepgp_standings:OnEnable()
  if not T:IsRegistered("sepgp_standings") then
    T:Register("sepgp_standings",
      "children", function()
        T:SetTitle(L["BoW-EPGP Standings"])
        self:OnTooltipUpdate()
      end,
  		"showTitleWhenDetached", true,
  		"showHintWhenDetached", true,
  		"cantAttach", true,
  		"menu", function()
        D:AddLine(
          "text", L["Raid Only"],
          "tooltipText", L["Only show members in raid."],
          "checked", sepgp_raidonly,
          "func", function() sepgp_standings:ToggleRaidOnly() end
        )      
        D:AddLine(
          "text", L["Group by class"],
          "tooltipText", L["Group members by class."],
          "checked", sepgp_groupbyclass,
          "func", function() sepgp_standings:ToggleGroupBy("sepgp_groupbyclass") end
        )
        D:AddLine(
          "text", L["Group by armor"],
          "tooltipText", L["Group members by armor."],
          "checked", sepgp_groupbyarmor,
          "func", function() sepgp_standings:ToggleGroupBy("sepgp_groupbyarmor") end
        )
        D:AddLine(
          "text", L["Group by roles"],
          "tooltipText", L["Group members by roles."],
          "checked", sepgp_groupbyrole,
          "func", function() sepgp_standings:ToggleGroupBy("sepgp_groupbyrole") end
        )
        D:AddLine(
          "text", L["Refresh"],
          "tooltipText", L["Refresh window"],
          "func", function() sepgp_standings:Refresh() end
        )
        D:AddLine(
          "text", L["Export"],
          "tooltipText", L["Export standings to csv."],
          "func", function() sepgp_standings:Export() end
        )
        if IsGuildLeader() then
          D:AddLine(
          "text", L["Import"],
          "tooltipText", L["Import standings from csv."],
          "func", function() sepgp_standings:Import() end
        )
        end
  		end
    )
  end
  if not T:IsAttached("sepgp_standings") then
    T:Open("sepgp_standings")
  end
end

function sepgp_standings:OnDisable()
  closeSepgpMenu()
  T:Close("sepgp_standings")
end

function sepgp_standings:Refresh()
  T:Refresh("sepgp_standings")
end

-- true when the pfUI theme is active: tablet_pfui_skin.lua already puts its
-- own skinned close button on the window in that case
local function pfuiHandlesClose()
  local p = _G.sepgp_pfui
  if p and type(p.IsEnabled) == "function" then
    local ok, r = pcall(p.IsEnabled, p)
    if ok and r then return true end
  end
  return false
end

-- close (X) button for the normal (non-pfUI) theme
local function ensureCloseButton(tablet)
  if pfuiHandlesClose() then
    if tablet.sepgpXBtn then tablet.sepgpXBtn:Hide() end
    return
  end
  local btn = tablet.sepgpXBtn
  if not btn then
    btn = CreateFrame("Button", nil, tablet, "UIPanelCloseButton")
    btn:SetWidth(24)
    btn:SetHeight(24)
    btn:SetPoint("TOPRIGHT", tablet, "TOPRIGHT", -2, -2)
    btn:SetScript("OnClick", function() tablet:Hide() end)
    tablet.sepgpXBtn = btn
  end
  btn:SetFrameLevel((tablet:GetFrameLevel() or 1) + 10)
  btn:Show()
end

function sepgp_standings:setHideScript()
  local i = 1
  local tablet = getglobal(string.format("Tablet20DetachedFrame%d",i))
  while (tablet) and i<100 do
    if tablet.owner ~= nil and tablet.owner == "sepgp_standings" then
      sepgp:make_escable(string.format("Tablet20DetachedFrame%d",i),"add")
      ensureCloseButton(tablet)
      tablet:SetScript("OnHide",nil)
      tablet:SetScript("OnHide",function()
          closeSepgpMenu()
          -- Tablet frames are pooled and shared: never leave our X on
          -- a frame another addon may show next
          if this.sepgpXBtn then this.sepgpXBtn:Hide() end
          if not T:IsAttached("sepgp_standings") then
            T:Attach("sepgp_standings")
            this:SetScript("OnHide",nil)
          end
        end)
      break
    end    
    i = i+1
    tablet = getglobal(string.format("Tablet20DetachedFrame%d",i))
  end  
end

function sepgp_standings:Top()
  if T:IsRegistered("sepgp_standings") and (T.registry.sepgp_standings.tooltip) then
    T.registry.sepgp_standings.tooltip.scroll=0
  end  
end

function sepgp_standings:Toggle(forceShow)
  self:Top()
  if T:IsAttached("sepgp_standings") then -- hidden
    T:Detach("sepgp_standings") -- show
    if (T:IsLocked("sepgp_standings")) then
      T:ToggleLocked("sepgp_standings")
    end
    self:setHideScript()
    if sepgp.extRemote then sepgp.extRemote:OnOpen() end
  else
    if (forceShow) then
      sepgp_standings:Refresh()
    else
      T:Attach("sepgp_standings") -- hide
      closeSepgpMenu()
    end
  end  
end

function sepgp_standings:ToggleGroupBy(setting)
  for _,value in ipairs(groupings) do
    if value ~= setting then
      _G[value] = false
    end
  end
  _G[setting] = not _G[setting]
  self:Top()
  self:Refresh()
end

function sepgp_standings:ToggleRaidOnly()
  sepgp_raidonly = not sepgp_raidonly
  self:Top()
  sepgp:SetRefresh(true)
end

local pr_sorter_standings = function(a,b)
  if sepgp_minep > 0 then
    local a_over = a[4]-sepgp_minep >= 0
    local b_over = b[4]-sepgp_minep >= 0
    if a_over and b_over or (not a_over and not b_over) then
      if a[6] ~= b[6] then
        return tonumber(a[6]) > tonumber(b[6])
      else
        return tonumber(a[4]) > tonumber(b[4])
      end
    elseif a_over and (not b_over) then
      return true
    elseif b_over and (not a_over) then
      return false
    end
  else
    if a[6] ~= b[6] then
      return tonumber(a[6]) > tonumber(b[6])
    else
      return tonumber(a[4]) > tonumber(b[4])
    end
  end
end
-- Builds a standings table with record:
-- name, class, armor_class, roles, EP, GP, PR
-- and sorted by PR
function sepgp_standings:BuildStandingsTable()
  local t = { }
  local r = { }
  if (sepgp_raidonly) and GetNumRaidMembers() > 0 then
    for i = 1, GetNumRaidMembers(true) do
      local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i) 
      r[name] = true
    end
  end
  sepgp.alts = {}
  -- External mains (not in Blades of Wrynn): use the list relayed by a guild member
  local remote = sepgp.extRemote and sepgp.extRemote:IsActive() and sepgp.extRemote:Rows()
  if remote then
    for i = 1, table.getn(remote) do
      local rw = remote[i]
      if (not sepgp_raidonly) or (not next(r)) or r[rw[1]] then
        table.insert(t,{rw[1],rw[2],self:getArmorClass(rw[2]),rw[3],rw[4],rw[3]/rw[4],rw[5]})
      end
    end
  end
  sepgp:buildExternalMainsTable()
  for i = 1, (remote and 0 or GetNumGuildMembers(1)) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    local ep = (sepgp:get_ep_v3(name,officernote) or 0) 
    local gp = (sepgp:get_gp_v3(name,officernote) or sepgp.VARS.basegp)
    local main, main_class, main_rank = sepgp:parseAlt(name,officernote)
    local ext_name = sepgp.external_mains_reverse and sepgp.external_mains_reverse[name]
    if (main) then
      if ((self._playerName) and (name == self._playerName)) then
        if (not sepgp_main) or (sepgp_main and sepgp_main ~= main) then
          sepgp_main = main
          self:defaultPrint(L["Your main has been set to %s"],sepgp_main)
        end
      end
      main = C:Colorize(BC:GetHexColor(main_class), main)
      sepgp.alts[main] = sepgp.alts[main] or {}
      sepgp.alts[main][name] = class
    end
    local armor_class = self:getArmorClass(class)
    if ep > 0 then
      if (sepgp_raidonly) and next(r) then
        if r[name] then
          table.insert(t,{name,class,armor_class,ep,gp,ep/gp,ext_name})
        end
      else
      	table.insert(t,{name,class,armor_class,ep,gp,ep/gp,ext_name})
      end
    end
  end
  if (sepgp_groupbyclass) then
    table.sort(t, function(a,b)
      if (a[2] ~= b[2]) then return a[2] > b[2]
      else return pr_sorter_standings(a,b) end
    end)
  elseif (sepgp_groupbyarmor) then
    table.sort(t, function(a,b)
      if (a[3] ~= b[3]) then return a[3] > b[3]
      else return pr_sorter_standings(a,b) end
    end)
  elseif (sepgp_groupbyrole) then
    t = self:getRolesClass(t) -- we are subbing role into armor_class to avoid extra table creation
    table.sort(t, function(a,b)
    if (a[3] ~= b[3]) then return a[3] > b[3]
      else return pr_sorter_standings(a,b) end
    end)   
  else
    table.sort(t, pr_sorter_standings)
  end
  return t
end

function sepgp_standings:OnTooltipUpdate()
  -- A blank line under the window title, so the title has room before the
  -- separator line and the table header. (Tablet would also insert its own
  -- automatic blank line above the table -- that one is switched off below
  -- with hideBlankLine, otherwise it becomes a second, undersized gap.)
  local spacer = T:AddCategory("columns", 1, "hideBlankLine", true)
  spacer:AddLine("text", " ")

  -- Name is left-aligned, EP / GP / PR (header row included) are centered;
  -- the lines, row dividers and tint are drawn by the table-look code below.
  local cat = T:AddCategory(
      "columns", 4,
      "hideBlankLine", true,
      "justify", "LEFT", "justify2", "CENTER", "justify3", "CENTER", "justify4", "CENTER",
      "text",  C:Orange(string.upper(L["Name"])), "child_textR",    1, "child_textG",    1, "child_textB",    1, "child_justify",  "LEFT",
      "text2", C:Orange(string.upper(L["ep"])),   "child_text2R",   1, "child_text2G",   1, "child_text2B",   1, "child_justify2", "CENTER",
      "text3", C:Orange(string.upper(L["gp"])),   "child_text3R",   1, "child_text3G",   1, "child_text3B",   1, "child_justify3", "CENTER",
      "text4", C:Orange(string.upper(L["pr"])),   "child_text4R",   1, "child_text4G",   1, "child_text4B",   0, "child_justify4", "CENTER"
    )
  local t = self:BuildStandingsTable()
  if sepgp.extRemote and sepgp.extRemote:IsActive() then
    cat:AddLine(
      "text", C:Colorize("999999", sepgp.extRemote:StatusText()),
      "text2", "",
      "text3", "",
      "text4", ""
    )
  end
  local separator
  for i = 1, table.getn(t) do
    local name, class, armor_class, ep, gp, pr, ext_name = unpack(t[i])
    if (sepgp_groupbyarmor) or (sepgp_groupbyrole) then
      if not (separator) then
        if (sepgp_groupbyarmor) then
          separator = armor_text[armor_class]
        elseif (sepgp_groupbyrole) then
          separator = role_text[armor_class]
        end
        if (separator) then
          cat:AddLine(
            "text", C:Green(separator),
            "text2", "",
            "text3", "",
            "text4", ""
          )
        end
      else
        local last_separator = separator
        if (sepgp_groupbyarmor) then
          separator = armor_text[armor_class]
        elseif (sepgp_groupbyrole) then
          separator = role_text[armor_class]
        end
        if (separator) and (separator ~= last_separator) then
          cat:AddLine(
            "text", C:Green(separator),
            "text2", "",
            "text3", "",
            "text4", ""
          )          
        end
      end
    end
    local displayname = ext_name and string.format("%s |cff999999[ext:%s]|r",ext_name,name) or name
    local text = C:Colorize(BC:GetHexColor(class), displayname)
    local text2, text4
    if sepgp_minep > 0 and ep < sepgp_minep then
      text2 = C:Red(string.format("%.4g", ep))
      text4 = C:Red(string.format("%.4g", pr))
    else
      text2 = string.format("%.4g", ep)
      text4 = string.format("%.4g", pr)
    end
    local text3 = string.format("%.4g", gp)    
    if ((sepgp._playerName) and sepgp._playerName == name) or ((sepgp_main) and sepgp_main == name) or (ext_name and sepgp._playerName == ext_name) then
      text = string.format("(*)%s",text)
      local pr_decay = sepgp:capcalc(ep,gp)
      if pr_decay < 0 then
        text4 = string.format("%s(|cffff0000%.4g|r)",text4,pr_decay)
      end
    end
    cat:AddLine(
      "text", text,
      "text2", text2,
      "text3", text3,
      "text4", text4
    )
  end

  -- a blank line under the LAST row, mirroring the spacer line under the
  -- title above. This gives Tablet real content to size the window's
  -- bottom margin around. The old approach tried to carve out that same
  -- space by growing the window's height by hand after Tablet had already
  -- laid everything out -- which fought Tablet's own auto-sizing, since
  -- Tablet re-measures "how many rows fit" from the window's height on
  -- every redraw and would fill the extra room with more rows instead of
  -- leaving it blank (that fight is also what was making the title/header
  -- vanish: once Tablet pulled in extra rows it no longer had room for
  -- those two at the top). Adding a real blank row here means Tablet
  -- accounts for the footer space itself, the same way it already does
  -- for the gap under the title.
  local footerSpacer = T:AddCategory("columns", 1, "hideBlankLine", true)
  footerSpacer:AddLine("text", " ")

  -- make sure the table look is hooked into this window before Tablet
  -- shows it, so the lines are there on the very first paint
  if hookStandingsTip then hookStandingsTip() end
end

-------------------------------------------------------------------------
-- Table look for the standings window: vertical column dividers, a line
-- between the title and the table, a divider under every row, alternating
-- row tint, and a footer gap for Tablet's "Scroll up/down (x / y)" hint.
--
-- Tablet-2.0 is a plain tooltip layout engine -- it has no concept of
-- table borders or row shading. Every one of these is a thin texture that
-- lives ON the row's own Tablet button and is anchored to that button (or
-- to the row's own cells), never placed from screen coordinates.
--
-- That matters: an earlier version read GetLeft()/GetTop() of every row
-- and positioned the lines from those numbers. Tablet keeps rows that are
-- scrolled out of view "shown" with an anchor-less, stale rectangle, so
-- after moving the window (or scrolling) the lines were drawn from old
-- screen positions -- that was the grid floating far away from the window,
-- and the phantom empty row at the top/bottom. Anchoring to the buttons
-- removes the whole class of problem: the lines are attached to the rows,
-- they hide with them, and they move with the window by themselves.
--
-- What is still decided in code is WHICH buttons are real table rows:
--   * a button counts only if Tablet itself has it shown (IsShown() on the
--     button -- Tablet hides out-of-range buttons, unlike their fontstrings)
--   * the title line and blank/spacer lines (no visible text) are skipped
-- and this runs from a hook on the window's Show() (so it happens in the
-- same frame Tablet lays the rows out: no delay, no flicker on scroll),
-- plus a slow poll as a safety net.
-------------------------------------------------------------------------
local LINE_R, LINE_G, LINE_B, LINE_A = 0.15, 0.15, 0.15, 1                 -- dark gray dividers
local STRIPE_A_R, STRIPE_A_G, STRIPE_A_B, STRIPE_A_A = 1, 1, 1, 0.035     -- zebra stripe, even lines
local STRIPE_B_R, STRIPE_B_G, STRIPE_B_B, STRIPE_B_A = 0, 0, 0, 0.12      -- zebra stripe, odd lines
local TITLE_GAP = 10        -- vertical gap between the title and the separator line above the table (scales with Size)
local TOP_PAD = 14          -- vertical gap between the window's top edge and the title/"Scroll up" text (scales with Size)
local EDGE_PAD = 3          -- how far row lines/stripes stick out sideways past the row (scales with Size)
local FOOTER_GAP = 7        -- extra room between the table and the "Scroll up/down" text (scales with Size)
local SCROLLBAR_WIDTH = 8  -- fixed UI-control size, does not scale with Size
local SCROLLBAR_GUTTER = 8  -- blank gap between the table (stripe/divider) and the scrollbar, so they never touch (scales with Size)
local SCROLLBAR_MARGIN = 6  -- blank gap between the scrollbar and the window's own right edge (scales with Size)

local floor = math.floor

-- true 1-screen-pixel size for a texture on `tip`. One pixel is
-- (768 / physical screen height) UI units at scale 1, divided by the
-- frame's effective scale. Falls back to 1/scale when the resolution
-- can't be read.
local physicalHeight
local function onePixel(tip)
  if physicalHeight == nil then
    physicalHeight = false
    local res = GetCVar and GetCVar("gxResolution")
    if res then
      local _, _, _, h = string.find(res, "(%d+)%s*[xX]%s*(%d+)")
      h = tonumber(h)
      if h and h > 0 then physicalHeight = h end
    end
  end
  local scale = tip:GetEffectiveScale()
  if not scale or scale <= 0 then scale = 1 end
  if physicalHeight then
    return (768 / physicalHeight) / scale
  end
  return 1 / scale
end

local function getDeco(btn)
  local d = btn.sepgpDeco
  if d then return d end
  d = {}
  d.stripe = btn:CreateTexture(nil, "BORDER")   -- under the row's text
  d.stripe:Hide()
  d.line = btn:CreateTexture(nil, "OVERLAY")    -- divider under the row
  d.line:SetTexture(LINE_R, LINE_G, LINE_B, LINE_A)
  d.line:Hide()
  d.top = btn:CreateTexture(nil, "OVERLAY")     -- line above the first visible row
  d.top:SetTexture(LINE_R, LINE_G, LINE_B, LINE_A)
  d.top:Hide()
  d.cols = {}
  for k = 1, 3 do
    local c = btn:CreateTexture(nil, "OVERLAY") -- vertical column divider
    c:SetTexture(LINE_R, LINE_G, LINE_B, LINE_A)
    c:Hide()
    d.cols[k] = c
  end
  btn.sepgpDeco = d
  return d
end

local function hideDeco(btn)
  local d = btn and btn.sepgpDeco
  if not d then return end
  d.stripe:Hide()
  d.line:Hide()
  d.top:Hide()
  for k = 1, 3 do d.cols[k]:Hide() end
  btn.sepgpDecorated = nil
end

-- Gap Tablet leaves between two neighbouring columns of a row: it anchors
-- the 2nd column's fontstring to the 1st column's TOPRIGHT with that gap
-- as the x offset, so it can be read straight off the anchor.
local function columnGap(tip, i)
  local right, left = tip.rights[i], tip.lefts[i]
  if not (right and left) then return nil end
  local n = right.GetNumPoints and right:GetNumPoints() or 1
  for k = 1, n do
    local point, rel, relPoint, x = right:GetPoint(k)
    if point == "TOPLEFT" and rel == left and relPoint == "TOPRIGHT" and x then
      return x
    end
  end
  return nil
end

local HDR_NAME, HDR_EP = string.upper(L["Name"]), string.upper(L["ep"])

local function decorateRow(tip, i, isFirst, isHeader, px, gap, pad, rInset)
  local btn = tip.buttons[i]
  local parity = math.mod(i, 2)
  local first = isFirst and 1 or 0
  local header = isHeader and 1 or 0
  local bh = btn:GetHeight() or 0
  rInset = rInset or 0
  if btn.sepgpDecorated and btn.sepgpPx == px and btn.sepgpGap == gap and btn.sepgpPad == pad
     and btn.sepgpFirst == first and btn.sepgpHeader == header and btn.sepgpParity == parity
     and btn.sepgpH == bh and btn.sepgpRInset == rInset
     and btn.sepgpTipR == (tip:GetRight() or 0) then
    return -- already drawn exactly like this
  end
  local d = getDeco(btn)
  -- Right edge: the row button stretches to the window edge, so measure how
  -- far that is and pull the stripe in by exactly the scrollbar column.
  local padR = pad
  if rInset > 0 then
    local br, tr = btn:GetRight(), tip:GetRight()
    if br and tr then padR = (tr - rInset) - br + (SCROLLBAR_GUTTER * 0.5) else padR = pad - rInset end
  end

  -- divider right under the row (in the 2-unit gap Tablet leaves between rows)
  d.line:ClearAllPoints()
  d.line:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", -pad, -1)
  d.line:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", padR, -1)
  d.line:SetHeight(px)
  d.line:Show()

  -- line above the first visible row: this is the title-to-table separator
  -- (or the separator under "Scroll up" when the list is scrolled)
  if isFirst then
    d.top:ClearAllPoints()
    d.top:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", -pad, 1)
    d.top:SetPoint("BOTTOMRIGHT", btn, "TOPRIGHT", padR, 1)
    d.top:SetHeight(px)
    d.top:Show()
  else
    d.top:Hide()
  end

  -- zebra tint on data rows only; the header row stays plain. Parity comes
  -- from the row's own line number, so scrolling never flips the colors.
  if isHeader then
    d.stripe:Hide()
  else
    if parity == 0 then
      d.stripe:SetTexture(STRIPE_A_R, STRIPE_A_G, STRIPE_A_B, STRIPE_A_A)
    else
      d.stripe:SetTexture(STRIPE_B_R, STRIPE_B_G, STRIPE_B_B, STRIPE_B_A)
    end
    d.stripe:ClearAllPoints()
    d.stripe:SetPoint("TOPLEFT", btn, "TOPLEFT", -pad, 1)
    d.stripe:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", padR, -1)
    d.stripe:Show()
  end

  -- vertical column dividers, centered in the gap after columns 1, 2, 3.
  -- Height comes from the button (explicit, always valid) instead of the
  -- cells, because a cell with empty text has no height of its own.
  local cells = { tip.lefts[i], tip.rights[i], tip.thirds[i] }
  for k = 1, 3 do
    local c = d.cols[k]
    if gap then
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", cells[k], "TOPRIGHT", gap / 2, 1)
      c:SetWidth(px)
      c:SetHeight(bh + 2)
      c:Show()
    else
      c:Hide()
    end
  end

  btn.sepgpDecorated = true
  btn.sepgpPx, btn.sepgpGap, btn.sepgpPad = px, gap, pad
  btn.sepgpFirst, btn.sepgpHeader, btn.sepgpParity, btn.sepgpH = first, header, parity, bh
  btn.sepgpRInset = rInset
  btn.sepgpTipR = tip:GetRight() or 0
end

-- Tablet anchors both scroll hints with a RIGHT point at the window's own
-- right edge, while the rows stop 12 units short of it -- so the hint text
-- sits a few pixels right of the table's center. `inset` lines it up.
local function setHintInset(tip, inset)
  local y = -10 * (tip.fontSizePercent or 1)
  if tip.scrollUp then tip.scrollUp:SetPoint("RIGHT", tip, "RIGHT", inset, y) end
  if tip.scrollDown then tip.scrollDown:SetPoint("RIGHT", tip, "RIGHT", inset, y) end
end

-- A real, draggable vertical scrollbar for the standings window, built
-- once per window and repositioned/shown or hidden every decorate() call.
-- It drives Tablet's own self.scroll (the same field the mouse wheel and
-- the "Scroll up/down" text use), so it can never disagree with them.
--
-- Built from plain Frame/Texture objects rather than
-- CreateFrame("Slider", ..., "UISliderTemplate"): that template isn't
-- guaranteed to exist on every client (some strip or rename UI templates),
-- and CreateFrame() throws immediately when the inherited node is missing
-- -- "Couldn't find inherited node 'UISliderTemplate'" -- which aborted
-- the whole decorate() call before anything else in it could run. A plain
-- Frame has no such dependency, so the rest of decorate() can never be
-- taken down by it again.
local function ensureScrollbar(tip)
  local sb = tip.sepgpScrollbar
  if sb then return sb end

  sb = CreateFrame("Frame", nil, tip)
  sb:EnableMouse(true)

  -- Track and thumb used to be two very-close shades of light gray (0.85
  -- vs 0.8), which read as a single smear against the dark tooltip
  -- background instead of two distinct pieces -- the thumb was only
  -- really readable while it was moving. The track is now a dark, mostly
  -- transparent groove (so it reads as a channel cut into the background,
  -- like the gray column in the Google Sheets mockup) and the thumb is a
  -- solid, bright, fully-opaque bar, so the two are visibly different at
  -- a glance whether or not anything is being dragged. A 1px border on
  -- the thumb (a second, slightly darker texture just behind it) keeps it
  -- readable even when it fills almost the whole track.
  local track = sb:CreateTexture(nil, "ARTWORK")
  track:SetTexture(0, 0, 0, 0.25)
  track:SetAllPoints(sb)
  sb.track = track

  local thumb = CreateFrame("Frame", nil, sb)
  thumb:EnableMouse(true)
  thumb:SetWidth(SCROLLBAR_WIDTH)
  thumb:SetHeight(30)
  local thumbBorder = thumb:CreateTexture(nil, "BORDER")
  thumbBorder:SetTexture(0, 0, 0, 0.35)
  thumbBorder:SetPoint("TOPLEFT", thumb, "TOPLEFT", -1, 1)
  thumbBorder:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", 1, -1)
  thumb.border = thumbBorder
  local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
  thumbTex:SetTexture(0.75, 0.65, 0.3, 0.75)
  thumbTex:SetAllPoints(thumb)
  thumb.tex = thumbTex
  sb.thumb = thumb

  -- dragging: WoW only fires OnMouseUp on the frame the cursor happens to
  -- be over at release time, which is unreliable once the cursor has
  -- moved off the thumb mid-drag -- so "are we still dragging" is polled
  -- every frame via IsMouseButtonDown() instead of trusting OnMouseUp.
  thumb:SetScript("OnMouseDown", function()
    thumb.sepgpDragging = true
  end)
  thumb:SetScript("OnUpdate", function()
    if not thumb.sepgpDragging then return end
    if not IsMouseButtonDown("LeftButton") then
      thumb.sepgpDragging = nil
      return
    end
    local tp = sb.sepgpTip
    local maxScroll = sb.sepgpMaxScroll
    if not (tp and maxScroll and maxScroll > 0) then return end
    local scale = sb:GetEffectiveScale() or 1
    local _, cy = GetCursorPosition()
    cy = cy / scale
    local top = sb:GetTop() or 0
    local trackHeight = sb:GetHeight() or 0
    local thumbHeight = thumb:GetHeight() or 0
    local maxOffset = trackHeight - thumbHeight
    if maxOffset < 0 then maxOffset = 0 end
    local offset = (top - cy) - (thumbHeight / 2)
    if offset < 0 then offset = 0 end
    if offset > maxOffset then offset = maxOffset end
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", sb, "TOP", 0, -offset)
    local newScroll = 0
    if maxOffset > 0 then
      newScroll = floor((offset / maxOffset) * maxScroll + 0.5)
    end
    if newScroll ~= tp.scroll then
      tp.scroll = newScroll
      if tp:IsShown() then tp:Show() end
    end
  end)

  -- clicking the track above/below the thumb pages the list a line at a
  -- time, same as clicking the empty track of a normal slider would.
  sb:SetScript("OnMouseDown", function()
    local tp = sb.sepgpTip
    if not tp then return end
    local scale = sb:GetEffectiveScale() or 1
    local _, cy = GetCursorPosition()
    cy = cy / scale
    local thumbTop = thumb:GetTop()
    local thumbBottom = thumb:GetBottom()
    if not (thumbTop and thumbBottom) then return end
    if cy > thumbTop then
      tp.scroll = math.max(0, (tp.scroll or 0) - 1)
      if tp:IsShown() then tp:Show() end
    elseif cy < thumbBottom then
      local maxScroll = sb.sepgpMaxScroll or 0
      tp.scroll = math.min(maxScroll, (tp.scroll or 0) + 1)
      if tp:IsShown() then tp:Show() end
    end
  end)

  tip.sepgpScrollbar = sb
  return sb
end

-------------------------------------------------------------------------
-- Frozen title/header overlay.
--
-- Tablet has no concept of a pinned row: line 1 (the title) gets its own
-- text swapped out for its "Scroll up (x/y)" hint once the list scrolls
-- away from the top, and the header line (NAME/EP/GP/PR) is just an
-- ordinary line -- once scrolled past, its button is hidden exactly like
-- any data row's, so both go blank at once.
--
-- Faked here with a small always-shown frame parented directly to the
-- window itself (never to one of Tablet's own scrolling lines), raised
-- above the scrollchild so the real rows visually run in behind it. Its
-- own text is set once from whatever Tablet is showing at the moment the
-- window is unscrolled (the one moment both the title and the header
-- line are guaranteed to hold their real text) and reused from that cache
-- afterward, so it never picks up Tablet's own hint text.
-------------------------------------------------------------------------
local function restoreDimmed(tip)
  if tip.sepgpDimmed then
    for _, c in ipairs(tip.sepgpDimmed) do c:SetAlpha(1) end
    tip.sepgpDimmed = nil
  end
end

local function ensureFrozenHeader(tip)
  local fr = tip.sepgpFrozen
  if fr then return fr end

  local f = CreateFrame("Frame", nil, tip)
  f:SetFrameStrata("TOOLTIP")
  f:SetFrameLevel((tip:GetFrameLevel() or 0) + 20)
  f:SetPoint("TOPLEFT", tip, "TOPLEFT", 0, 0)
  f:SetPoint("TOPRIGHT", tip, "TOPRIGHT", 0, 0)
  fr = { frame = f }

  local bg = f:CreateTexture(nil, "BACKGROUND")
  -- Opaque so the rows Tablet still lays out under the title/header while
  -- scrolled are hidden behind it (a frozen row). Split in two so the
  -- window's close button (top-right corner) is never covered.
  bg:SetTexture(0, 0, 0, 0)  -- transparent like the rest of the window; Tablet's own title/header are hidden by alpha instead
  fr.bg = bg
  local bg2 = f:CreateTexture(nil, "BACKGROUND")
  bg2:SetTexture(0, 0, 0, 0)
  fr.bg2 = bg2
  -- same dividers the real header row has: line above, line below, and
  -- the three vertical column separators
  local function mkLine()
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetTexture(LINE_R, LINE_G, LINE_B, LINE_A)
    return t
  end
  fr.lineTop, fr.lineBot = mkLine(), mkLine()
  fr.cols = { mkLine(), mkLine(), mkLine() }

  -- A FontString has no font until one is set, and SetText() on one
  -- throws "Font not set". Give every string a default here; the real
  -- font/color are copied over from Tablet's own strings each update.
  -- One title fontstring, parented to the overlay frame, used for every
  -- state. The overlay frame is now ALWAYS shown; when the list is not
  -- scrolled only its title is visible (bg/lines/header copies are hidden),
  -- so the title is drawn by the same object in the same place either way.
  fr.title = f:CreateFontString(nil, "OVERLAY")
  fr.title:SetFontObject(GameFontNormal)
  fr.title:SetJustifyH("CENTER")

  local function mkCell(justify)
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(GameFontNormal)
    fs:SetJustifyH(justify)
    return fs
  end
  fr.name = mkCell("LEFT")
  fr.ep   = mkCell("CENTER")
  fr.gp   = mkCell("CENTER")
  fr.pr   = mkCell("CENTER")

  -- Tiny always-shown watcher: re-runs decorate() once the column layout
  -- has been still for a moment, in case Tablet stops calling us by then.
  local wf = CreateFrame("Frame", nil, tip)
  wf:SetScript("OnUpdate", function()
    local t = tip.sepgpWaitUntil
    if t and GetTime() >= t then
      tip.sepgpWaitUntil = nil
      if tip.sepgpRedo then tip.sepgpRedo() end
    end
  end)

  tip.sepgpFrozen = fr
  return fr
end

local function decorate(tip)
  if not (tip and tip.buttons and tip.lefts and tip.rights and tip.thirds) then return end
  local nButtons = table.getn(tip.buttons)

  -- Tablet's window frames are pooled and shared with other addons: when a
  -- frame is showing someone else's content, take our lines off it.
  if tip.owner ~= "sepgp_standings" then
    if tip.sepgpTouched then
      for i = 1, nButtons do hideDeco(tip.buttons[i]) end
      setHintInset(tip, 0)
      if tip.sepgpScrollbar then tip.sepgpScrollbar:Hide() end
      if tip.sepgpFrozen then tip.sepgpFrozen.frame:Hide() end
      if tip.lefts[1] then tip.lefts[1]:SetAlpha(1) end
      restoreDimmed(tip)
      tip.sepgpTouched = nil
    end
    return
  end
  tip.sepgpTouched = true

  local n = tip.numLines or 0
  local fsp = tip.fontSizePercent or 1
  local px = onePixel(tip)
  local pad = EDGE_PAD * fsp

  -- how many lines fit on screen / whether the scrollbar will be needed --
  -- computed once here so both the width reservation below (2c) and the
  -- scrollbar block (6) agree on it.
  local maxLinesPerScreen = floor(30 / fsp)
  if maxLinesPerScreen < 1 then maxLinesPerScreen = 1 end
  local maxScroll = n - maxLinesPerScreen

  -- 0) Tablet's tip.scroll is never reset by a Size change on its own: zoom
  -- back down until the whole list fits on screen again and it stays
  -- wherever it was left (still showing "Scroll up (x/30)" and starting
  -- mid-list) instead of snapping back to the top -- this is what makes
  -- scaling back down look broken until the window is closed and reopened
  -- (which rebuilds it from scratch with scroll back at 0). Whenever
  -- nothing needs scrolling any more, force it back to 0 ourselves and
  -- re-run Tablet's own Show() so the row content actually reflects that
  -- (decorate() only lays out what Show() already drew; it can't change
  -- which lines Tablet chose to draw). Bounded to one extra hop: by the
  -- time Show() calls us back, tip.scroll is already 0, so this can't fire
  -- again.
  if maxScroll <= 0 and (tip.scroll or 0) ~= 0 then
    tip.scroll = 0
    if tip.Show then tip:Show() end
    return
  end

  -- 1) Find the table header line (the NAME / EP row). Everything above it
  -- is title space; everything from it down is the table. Found by its
  -- text, on ALL lines (a scrolled-off header keeps its text), so a stray
  -- empty line Tablet or we put above the header can never turn into a
  -- decorated "row".
  local headerIdx
  for i = 2, n do
    local txt = tip.lefts[i]:GetText()
    if txt and string.find(txt, HDR_NAME, 1, true) then
      local ept = tip.rights[i]:GetText()
      if ept and string.find(ept, HDR_EP, 1, true) then
        headerIdx = i
        break
      end
    end
  end

  -- 2) Classify every line: 0 = not a table row, 1 = data row, 2 = header.
  -- A row must be shown by Tablet AND still have anchors (Tablet clears the
  -- anchors of the lines it scrolls out).
  local kinds = tip.sepgpKinds
  if not kinds then kinds = {}; tip.sepgpKinds = kinds end
  local firstReal, gap
  local firstVisibleBtn, lastVisibleBtn
  -- dataRowCount/dataRowH: how many real DATA rows (kind == 1, i.e. never
  -- the header itself) are actually on screen right now, and the on-screen
  -- height of one of them. Used by the scrollbar (6) to size itself from
  -- a row count/height instead of anchoring to any one row's GetBottom()
  -- -- see the comment there for why that goes stale.
  local dataRowCount, dataRowH, firstDataIdx, lastDataIdx = 0, nil, nil, nil
  for i = 1, nButtons do
    local kind = 0
    local btn = tip.buttons[i]
    if i <= n and btn:IsShown() and btn:GetNumPoints() > 0 then
      if not firstVisibleBtn then firstVisibleBtn = btn end
      lastVisibleBtn = btn
      if i > 1 then -- line 1 is always the title
        if headerIdx then
          if i == headerIdx then
            kind = 2
          elseif i > headerIdx then
            -- still requires real text, same as the headerIdx-not-found
            -- branch below -- otherwise the blank footer spacer line
            -- (added after the last member) would get decorated as if it
            -- were one more data row.
            local txt = tip.lefts[i]:GetText()
            if txt and string.find(txt, "%S") then kind = 1 end
          end
        else
          local txt = tip.lefts[i]:GetText()
          if txt and string.find(txt, "%S") then kind = 1 end
        end
        if kind > 0 and not firstReal then
          firstReal = i
          gap = columnGap(tip, i)
        end
      end
    end
    kinds[i] = kind
    if kind == 1 then
      dataRowCount = dataRowCount + 1
      if not firstDataIdx then firstDataIdx = i end
      lastDataIdx = i
      if not dataRowH then
        local h = btn:GetHeight()
        if h and h > 0 then dataRowH = h end
      end
    end
  end

  -- 2b) Tablet reapplies its ORIGINAL, pre-zoom pixel widths to every
  -- column's fontstring on every AddLine (i.e. every Show()): SetFontSizePercent
  -- grows the rendered font and the window by a ratio, but never re-measures
  -- those per-column widths to match. At a high enough Size the box is then
  -- narrower than the (now bigger) text, and the client clips it down to
  -- "..." -- most visible on the EP/GP headers, since their box started out
  -- barely wider than "EP"/"GP" at 100%. Recomputed here from each visible
  -- fontstring's own GetStringWidth() -- its natural width at the CURRENT
  -- font size, ignoring whatever width Tablet just clamped it back to --
  -- and reapplied as one uniform width per column (the widest cell in it)
  -- so every row still lines up; done every call so it also keeps up as
  -- scrolling brings longer names into view, not just when Size changes.
  local function neededWidth(list, i, best)
    local fs = list and list[i]
    if not fs then return best end
    local w = fs:GetStringWidth() or 0
    if w > best then return w end
    return best
  end
  local needL, needR, needT, needF = 0, 0, 0, 0
  for i = 1, nButtons do
    if kinds[i] > 0 then
      needL = neededWidth(tip.lefts, i, needL)
      needR = neededWidth(tip.rights, i, needR)
      needT = neededWidth(tip.thirds, i, needT)
      needF = neededWidth(tip.fourths, i, needF)
    end
  end
  local colPad = 4 * fsp
  if needL > 0 then needL = needL + colPad end
  if needR > 0 then needR = needR + colPad end
  if needT > 0 then needT = needT + colPad end
  if needF > 0 then needF = needF + colPad end
  for i = 1, nButtons do
    if kinds[i] > 0 then
      local l, r, t = tip.lefts[i], tip.rights[i], tip.thirds[i]
      local f = tip.fourths and tip.fourths[i]
      if needL > 0 and l and l:GetWidth() ~= needL then l:SetWidth(needL) end
      if needR > 0 and r and r:GetWidth() ~= needR then r:SetWidth(needR) end
      if needT > 0 and t and t:GetWidth() ~= needT then t:SetWidth(needT) end
      if needF > 0 and f and f:GetWidth() ~= needF then f:SetWidth(needF) end
    end
  end

  -- 2c) Window width. Tablet sizes the frame once per Show(), from its own
  -- pre-widen column widths -- the widening above (2b) can leave the table
  -- wider than that frame, so the rightmost column spills past the right
  -- edge. Most visible while live-dragging the Size slider, since Tablet
  -- re-shrinks the frame back to its own (too-narrow) width on every tick,
  -- and disappears on a fresh open because the very first layout has
  -- nothing yet widened to spill. Fixed the same way the footer height is
  -- (5, below): measure the actual on-screen right edge of the widest row
  -- against the frame's own right edge, fresh every call, and correct the
  -- gap -- never accumulated/incremental, so it can't drift under
  -- SetFontSizePercent the way the old height code used to.
  local scrollReserve = 0
  if firstReal and tip.GetRight and tip:GetRight() then
    local rightCell = (tip.fourths and tip.fourths[firstReal]) or tip.thirds[firstReal] or tip.rights[firstReal]
    if rightCell and rightCell:GetRight() then
      -- pad already covers the stripe's own overhang past the cell; the
      -- gutter is EXTRA space on top of that so the scrollbar sits in its
      -- own clear column instead of butting straight up against the
      -- stripe the way it used to (compare the Guild Bank Viewer addon,
      -- which keeps a visible gap between its item rows and its
      -- scrollbar).
      if maxScroll > 0 then
        scrollReserve = (SCROLLBAR_GUTTER * fsp) + SCROLLBAR_WIDTH + (SCROLLBAR_MARGIN * fsp)
      end
      local reserve = pad + scrollReserve
      local needed = (rightCell:GetRight() + reserve) - tip:GetRight()
      if needed > 0.05 then
        tip:SetWidth((tip:GetWidth() or 0) + needed)
      end
    end

  end

  -- Title (line 1). The same fontstring/slot is reused by Tablet for the
  -- "Scroll up (x/30)" hint whenever the list is scrolled away from the
  -- top -- and Tablet gives that hint state a much smaller vertical offset
  -- than it gives the real title, which is why the top of the window looks
  -- fine unscrolled but reads as "no padding" the moment you scroll down
  -- (and, being the same object, the same object-centering problem from
  -- 2b/2c applies to it too). Re-anchored here, every call, straight to
  -- the frame's own TOP-center with ONE fixed, scaled offset regardless of
  -- which text it's currently showing, so both states get the same
  -- padding and stay centered on the frame's actual current width.
  local elemGap = 2 * fsp
  local title = tip.lefts[1]
  if title then
    title:ClearAllPoints()
    title:SetPoint("TOP", tip, "TOP", 0, -TOP_PAD * fsp)
    title:SetJustifyH("CENTER")
  end

  -- Cache the REAL title text/font/color the one moment it's guaranteed to
  -- be genuine (tip.scroll forced to 0 up in (0) whenever nothing needs
  -- scrolling, and every window starts at scroll 0 on first Show()) -- any
  -- later call while scrolled would otherwise read back Tablet's own
  -- "Scroll up (x/y)" replacement text instead of the title.
  if title and (tip.scroll or 0) == 0 then
    local t = title:GetText()
    if t and string.find(t, "%S") then
      tip.sepgpTitleText = t
      local f, h, flags = title:GetFont()
      if f then tip.sepgpTitleFont = { f, h, flags } end
      local tr_, tg_, tb_ = title:GetTextColor()
      tip.sepgpTitleColor = { tr_, tg_, tb_, 1 } -- never copy the alpha: the real title is hidden by alpha now
      -- Measure the real title's exact box (left/top relative to the
      -- window, and its width) so the scrolled overlay copy can be put on
      -- precisely the same spot, sub-pixels included -- no re-centering
      -- math of our own that could land a fraction of a pixel elsewhere.
      -- Only trusted once Tablet has finished laying the title out.
      local tl, tt, tw = title:GetLeft(), title:GetTop(), title:GetWidth()
      local wl, wt = tip:GetLeft(), tip:GetTop()
      if tl and tt and wl and wt and (tw or 0) > 1 then
        tip.sepgpTitleL = tl - wl
        tip.sepgpTitleT = wt - tt
        tip.sepgpTitleW = tw
      end
    end
  end

  -- Close button: Tablet nudges it ~2px sideways while the list is
  -- scrolled (it lays it out with the scroll hint), which reads as the
  -- header "jittering". Find it once (a small Button in the window's
  -- top-right corner), remember where it sits while unscrolled, and put
  -- it back there on every update.
  do
    local cb = tip.sepgpCloseBtn
    if not cb and tip.GetChildren then
      local tr, tt = tip:GetRight(), tip:GetTop()
      if tr and tt and (tip.scroll or 0) == 0 then
        local kids = { tip:GetChildren() }
        for _, k in ipairs(kids) do
          if k.IsObjectType and k:IsObjectType("Button") and k ~= tip.sepgpScrollbar then
            local w, r, t = k:GetWidth(), k:GetRight(), k:GetTop()
            if w and w > 4 and w < 40 and r and t
               and (tr - r) < 30 and (tt - t) < 30 and (tr - r) >= -2 then
              cb = k; tip.sepgpCloseBtn = k; break
            end
          end
        end
      end
    end
    if cb then
      if (tip.scroll or 0) == 0 then
        local tr, tt, r, t = tip:GetRight(), tip:GetTop(), cb:GetRight(), cb:GetTop()
        if tr and tt and r and t then tip.sepgpCloseOff = { r - tr, t - tt } end
      elseif tip.sepgpCloseOff then
        cb:ClearAllPoints()
        cb:SetPoint("TOPRIGHT", tip, "TOPRIGHT", tip.sepgpCloseOff[1], tip.sepgpCloseOff[2])
      end
    end
  end

  local headerBtn = headerIdx and tip.buttons[headerIdx]
  local headerH = (headerBtn and headerBtn:GetHeight()) or 0

  -- Frozen title/header overlay -- see ensureFrozenHeader() above for why
  -- this exists instead of just repositioning Tablet's own lines. The
  -- header's own cell fontstrings (unlike the title's) keep their real
  -- text even while scrolled off, so those are read live every call
  -- instead of needing the same cache as the title.
  do
    local fr = ensureFrozenHeader(tip)
    if headerIdx and firstDataIdx and tip:GetLeft() then
      -- Tablet's own copies are made invisible (alpha only) so they don't
      -- ghost under the overlay's text while the list is unscrolled.
      -- Fail-safe: while unscrolled Tablet's own title/header are shown
      -- as normal and the overlay stays hidden; the overlay only takes
      -- over once the real ones have scrolled away.
      -- The overlay (title + header row) is now drawn in EVERY state once
      -- the real title has been measured, not only while scrolled. Two
      -- different draws of the same text (Tablet's, and ours) land on
      -- pixels that differ by 1px in places, so swapping between them at
      -- the moment scrolling starts/stops made the title and the GP header
      -- hop. With only one draw there is nothing to hop between; its opaque
      -- background covers Tablet's own title/header underneath.
      -- Wait for the column layout to sit still before taking over. Right
      -- after the window opens Tablet's columns glide into place for about
      -- half a second; drawing the overlay from live positions during that
      -- time replays the glide as EP/GP/PR "flying in". While unsettled the
      -- overlay stays hidden and Tablet's own header is what you see.
      local settled = true
      local usingSaved = false
      if (tip.scroll or 0) == 0 then
        local tipLeft = tip:GetLeft()
        local parts = { string.format("%.1f", tip:GetWidth() or 0) }
        local refs = { tip.lefts, tip.rights, tip.thirds, tip.fourths }
        for ri = 1, 4 do
          local c = refs[ri] and refs[ri][firstDataIdx]
          if c and c:GetLeft() then
            table.insert(parts, string.format("%.1f/%.1f", c:GetLeft() - tipLeft, c:GetWidth() or 0))
          end
        end
        local sig = table.concat(parts, "|")
        local now = GetTime()
        if tip.sepgpSig ~= sig then
          tip.sepgpSig = sig
          tip.sepgpSigT = now
        end
        settled = (now - (tip.sepgpSigT or now)) >= 0.4
        if not settled then
          -- The layout we saved the last time it was settled (same scale and
          -- width) is exactly what it will settle back to, so use that right
          -- away: the overlay then appears at its final positions from the
          -- very first frame instead of waiting (and ticking over) or
          -- following the live cells while they are still moving.
          local key = fsp * 1000 + floor((tip:GetWidth() or 0) + 0.5)
          -- After a /reload the in-memory copy is gone: fall back to the one
          -- stored in the addon's saved settings (if it matches this size).
          if not tip.sepgpGeoSaved then
            local okp, prof = pcall(function() return sepgp and sepgp.db and sepgp.db.profile end)
            local st = okp and prof and prof.uiGeoSaved
            if type(st) == "table" and type(st.geo) == "table" then
              tip.sepgpGeoSaved = st.geo
              tip.sepgpGeoSavedK = st.k
            end
          end
          if tip.sepgpGeoSaved and tip.sepgpGeoSavedK == key then
            local copy = {}
            for k, v in pairs(tip.sepgpGeoSaved) do copy[k] = v end
            tip.sepgpGeo = copy
            tip.sepgpGeoK = key
            usingSaved = true
            settled = true
          else
            tip.sepgpWaitUntil = (tip.sepgpSigT or now) + 0.45
          end
        end
        tip.sepgpRedo = tip.sepgpRedo or function() decorate(tip) end
      end
      local ov = (((tip.scroll or 0) > 0) or (settled and tip.sepgpTitleText and tip.sepgpTitleL)) and 1 or 0
      local titleY = TOP_PAD * fsp
      fr.title:SetText(tip.sepgpTitleText or "")
      if tip.sepgpTitleFont then fr.title:SetFont(unpack(tip.sepgpTitleFont)) end
      if tip.sepgpTitleColor then fr.title:SetTextColor(unpack(tip.sepgpTitleColor)) end
      fr.title:SetAlpha(1)
      fr.title:ClearAllPoints()
      fr.title:SetJustifyH("CENTER")
      if tip.sepgpTitleL and tip.sepgpTitleW then
        fr.title:SetWidth(tip.sepgpTitleW)
        -- + a tenth of a pixel: the measured left edge often sits exactly
        -- on a pixel boundary, where float noise decides whether the copy
        -- rounds to the same pixel as the real title or one to the left
        fr.title:SetPoint("TOPLEFT", fr.frame, "TOPLEFT", tip.sepgpTitleL + px * 0.1, -tip.sepgpTitleT)
      else
        fr.title:SetPoint("TOP", fr.frame, "TOP", 0, -titleY)
      end
      -- Tablet's own title and header are made invisible (alpha only) while
      -- the overlay draws them, since the overlay background is transparent.
      restoreDimmed(tip)
      if ov == 1 then
        local dim = {}
        if title then table.insert(dim, title) end
        for _, ref in ipairs({ tip.lefts, tip.rights, tip.thirds, tip.fourths }) do
          local c = ref and ref[headerIdx]
          if c then table.insert(dim, c) end
        end
        for _, c in ipairs(dim) do c:SetAlpha(0) end
        tip.sepgpDimmed = dim
      elseif title then
        title:SetAlpha(1)
      end
      local titleH = fr.title:GetHeight()
      if not titleH or titleH <= 0 then titleH = headerH end
      local headerY = titleY + titleH + (TITLE_GAP * fsp)

      local tipLeft = tip:GetLeft()
      -- Column geometry is measured live while the window is unscrolled and
      -- REUSED while scrolled. Read live in both states it comes out 1px
      -- different for some columns (GP, PR), which made the header text
      -- hop sideways the moment scrolling started.
      -- (dropped whenever the window's size or Size-slider scale changes)
      local geoK = fsp * 1000 + floor((tip:GetWidth() or 0) + 0.5)
      if tip.sepgpGeoK ~= geoK or not tip.sepgpGeo then
        tip.sepgpGeo = {}
        tip.sepgpGeoK = geoK
      end
      local geoLive = (tip.scroll or 0) == 0 and not usingSaved
      local function geo(key, live)
        if geoLive then
          if live ~= nil then tip.sepgpGeo[key] = live end
          return live
        end
        local c = tip.sepgpGeo[key]
        if c ~= nil then return c end
        return live
      end
      local function alignCell(dst, ref, srcTxt, dx, key)
        local left, w = ref and ref:GetLeft(), ref and ref:GetWidth()
        if left and w then
          left = geo(key .. "L", left - tipLeft) + tipLeft
          w = geo(key .. "W", w)
        end
        if not (left and w) then dst:Hide(); return end
        dst:ClearAllPoints()
        dst:SetWidth(w)
        dst:SetHeight(headerH > 0 and headerH or 20)
        dst:SetJustifyV("MIDDLE")
        dst:SetPoint("TOPLEFT", fr.frame, "TOPLEFT", left - tipLeft + (dx or 0) + px * 0.1, -headerY)
        dst:SetText(srcTxt or "")
        dst:Show()
      end
      local function alignFrom(dst, gref, src, dx, key)
        alignCell(dst, gref, src:GetText(), dx, key)
        local sf, sh, sflags = src:GetFont()
        if sf then dst:SetFont(sf, sh, sflags) end
        local cr_, cg_, cb_ = src:GetTextColor()
        dst:SetTextColor(cr_, cg_, cb_, 1)
        dst:SetAlpha(1)
      end
      alignFrom(fr.name, tip.lefts[firstDataIdx],  tip.lefts[headerIdx], nil, "name")
      alignFrom(fr.ep,   tip.rights[firstDataIdx], tip.rights[headerIdx], nil, "ep")
      alignFrom(fr.gp,   tip.thirds[firstDataIdx], tip.thirds[headerIdx], nil, "gp")
      if tip.fourths and tip.fourths[headerIdx] and tip.fourths[firstDataIdx] then
        alignFrom(fr.pr, tip.fourths[firstDataIdx], tip.fourths[headerIdx], px, "pr")
      else
        fr.pr:Hide()
      end

      -- dividers
      local hH = (headerH > 0 and headerH or 20)
      local lastCell = (tip.fourths and tip.fourths[firstDataIdx]) or tip.thirds[firstDataIdx]
      local firstCell = tip.lefts[firstDataIdx]
      local fl, lr = firstCell:GetLeft(), lastCell and lastCell:GetRight()
      if fl and lr then
        fl = geo("divFL", fl - tipLeft) + tipLeft
        lr = geo("divLR", lr - tipLeft) + tipLeft
        local x1, x2 = (fl - tipLeft) - pad, (lr - tipLeft) + pad
        -- the rows' stripes end at the scrollbar gutter, not at the last
        -- cell + pad, so match that edge or a sliver of them peeks out
        if scrollReserve > 0 and tip:GetRight() then
          x2 = (tip:GetRight() - tipLeft) - scrollReserve + SCROLLBAR_GUTTER * 0.5 + px
        end
        for _, ln in ipairs({ fr.lineTop, fr.lineBot }) do
          ln:ClearAllPoints()
          ln:SetHeight(px)
          ln:SetPoint("TOPLEFT", fr.frame, "TOPLEFT", x1, 0)
          ln:SetWidth(x2 - x1)
        end
        fr.lineTop:SetPoint("TOPLEFT", fr.frame, "TOPLEFT", x1, -(headerY - 1 - px))
        fr.lineBot:SetPoint("TOPLEFT", fr.frame, "TOPLEFT", x1, -(headerY + hH + 1))
        fr.lineTop:Show(); fr.lineBot:Show()
        -- background only under the table's own width (rows never extend
        -- past it), so it can't spill onto the window border or close button
        fr.bg2:Hide()
        fr.bg:ClearAllPoints()
        fr.bg:SetPoint("TOPLEFT", fr.frame, "TOPLEFT", x1, -(TOP_PAD * fsp * 0.4))
        -- run the black all the way across (over the scrollbar column too),
        -- stopping just inside the window border, so no see-through gap
        -- is left at the top right
        local bgRight = x2
        if tip:GetRight() then bgRight = (tip:GetRight() - tipLeft) - 5 end
        if bgRight < x2 then bgRight = x2 end
        fr.bg:SetPoint("BOTTOMRIGHT", fr.frame, "BOTTOMLEFT", bgRight, 0)
        local cellsG = { tip.lefts[firstDataIdx], tip.rights[firstDataIdx], tip.thirds[firstDataIdx] }
        for k = 1, 3 do
          local c, cr = fr.cols[k], cellsG[k]:GetRight()
          if cr then cr = geo("divC" .. k, cr - tipLeft) + tipLeft end
          if gap and cr then
            c:ClearAllPoints()
            c:SetWidth(px)
            c:SetHeight(hH + 2)
            c:SetPoint("TOPLEFT", fr.frame, "TOPLEFT", (cr - tipLeft) + gap / 2, -(headerY - 1))
            c:Show()
          else
            c:Hide()
          end
        end
      end
      local contentTopY = headerY + (headerH > 0 and headerH or 20) + elemGap
      fr.frame:SetHeight(contentTopY)
      if ov == 1 then fr.frame:Show() else fr.frame:Hide() end
      -- remember this layout for the next time the window opens
      if geoLive and settled and tip.sepgpGeo then
        local copy = {}
        for k, v in pairs(tip.sepgpGeo) do copy[k] = v end
        tip.sepgpGeoSaved = copy
        tip.sepgpGeoSavedK = tip.sepgpGeoK
        -- also keep it in the saved settings so it survives /reload
        local okp, prof = pcall(function() return sepgp and sepgp.db and sepgp.db.profile end)
        if okp and prof then
          local c2 = {}
          for k, v in pairs(copy) do c2[k] = v end
          prof.uiGeoSaved = { k = tip.sepgpGeoK, geo = c2 }
        end
      end
      tip.sepgpContentTopY = contentTopY
      -- The overlay background is transparent now, so rows that have scrolled
      -- up under the title/header would show through it. Hide those rows
      -- (alpha only) instead; they are restored on the next update.
      if ov == 1 and tip.sepgpDimmed and (tip.scroll or 0) > 0 and lastDataIdx then
        local tt2 = tip:GetTop()
        if tt2 then
          local tol = 3 * fsp
          for i = firstDataIdx, lastDataIdx do
            local b = tip.buttons[i]
            local bt = b and b:IsShown() and b:GetTop()
            if bt and (tt2 - bt) < (contentTopY - tol) then
              local objs = { b, tip.lefts[i], tip.rights[i], tip.thirds[i], tip.fourths and tip.fourths[i] }
              for k = 1, 5 do
                local o = objs[k]
                if o then o:SetAlpha(0); table.insert(tip.sepgpDimmed, o) end
              end
            end
          end
        end
      end
    else
      fr.frame:Hide()
      restoreDimmed(tip)
      if title then title:SetAlpha(1) end
    end
  end

  -- 3) Title space. Every line between the title and the header is just
  -- empty space; shrink them so the gap is exactly TITLE_GAP no matter how
  -- many of them Tablet / OnTooltipUpdate produced. Tablet re-sets every
  -- button height in its own Show(), so this is redone after each one
  -- (the hook clears sepgpGapDelta); the window height follows below.
  local gapDelta = 0
  if headerIdx then
    for i = 2, headerIdx - 1 do
      local btn = tip.buttons[i]
      if btn and btn:IsShown() and btn:GetNumPoints() > 0 then
        if btn.sepgpGapDelta == nil then
          local target = (i == 2) and (TITLE_GAP * fsp) or 1
          local cur = btn:GetHeight() or 0
          btn:SetHeight(target)
          btn.sepgpGapDelta = target - cur
        end
        gapDelta = gapDelta + btn.sepgpGapDelta
      end
    end
  end

  -- 3b) Footer space: same idea as 3 above, but for the blank line(s)
  -- Tablet leaves after the LAST data row (see the footerSpacer line added
  -- in OnTooltipUpdate). Forced to exactly FOOTER_GAP so the bottom margin
  -- is predictable regardless of how many blank lines Tablet produced.
  if firstReal then
    local lastReal = firstReal
    for i = firstReal, nButtons do
      if kinds[i] > 0 then lastReal = i end
    end
    local footerBudget = FOOTER_GAP * fsp
    for i = lastReal + 1, nButtons do
      local btn = tip.buttons[i]
      if btn and btn:IsShown() and btn:GetNumPoints() > 0 then
        if btn.sepgpGapDelta == nil then
          local cur = btn:GetHeight() or 0
          btn:SetHeight(footerBudget)
          btn.sepgpGapDelta = footerBudget - cur
        end
      end
    end
  end

  -- 4) draw / clear per line (every button, so nothing stale is left over)
  for i = 1, nButtons do
    local btn = tip.buttons[i]
    if kinds[i] > 0 then
      decorateRow(tip, i, i == firstReal, kinds[i] == 2, px, gap, pad, scrollReserve)
    elseif btn.sepgpDecorated then
      hideDeco(btn)
    end
  end

  -- 4b) Keep the window's height the same scrolled and unscrolled.
  -- Measured from your screenshots: while scrolled the window is 4px
  -- shorter (its top edge sits 2px lower and its bottom edge 2px higher),
  -- because Tablet lays the top line out smaller in its scroll-hint state.
  -- The height is remembered while unscrolled and put back while scrolled.
  -- It is exactly the height that already holds this many rows, so Tablet
  -- gets no extra room to fit more of them.
  do
    local h = tip:GetHeight()
    if h then
      if (tip.scroll or 0) == 0 then
        tip.sepgpH0, tip.sepgpH0K = h, fsp
      elseif tip.sepgpH0 and tip.sepgpH0K == fsp then
        local d = tip.sepgpH0 - h
        if d > 0.3 and d < 12 then tip:SetHeight(tip.sepgpH0) end
      end
    end
  end

  -- 5) Tablet's "Scroll up/down (x / y)" hint text is never shown any
  -- more -- the scrollbar thumb's own size already says how much there is
  -- to scroll, so the hint was just noise (and its RIGHT-anchored text
  -- used to force a right-side inset on the whole table). Hide it
  -- outright instead of repositioning it.
  --
  -- The footer margin itself is no longer created here. It used to be
  -- carved out by measuring the gap under the last row and growing the
  -- window's height by hand (tip:SetHeight()) to reach a target -- but
  -- Tablet re-measures "how many rows fit" from the window's own height
  -- on every redraw, so handing it extra height that way just gave it
  -- room to lay out MORE rows into on its very next Show(), instead of
  -- leaving that space blank. That tug-of-war (us growing the window,
  -- Tablet filling the growth with rows, the gap disappearing again, us
  -- growing it again...) is also what was making the title and header
  -- intermittently vanish. The footerSpacer blank line added in
  -- OnTooltipUpdate, sized by 3b above, gives Tablet the same footer
  -- space as real content it lays out itself, so there's nothing left
  -- here to fight it.
  if tip.scrollUp then tip.scrollUp:Hide() end
  if tip.scrollDown then tip.scrollDown:Hide() end

  -- 6) scrollbar: a real, draggable vertical slider mirroring Tablet's own
  -- self.scroll / self.numLines, so it always agrees with the mouse-wheel
  -- scrolling and the "Scroll up/down" hint text.
  local sb = ensureScrollbar(tip)
  if maxScroll > 0 and dataRowCount > 0 and dataRowH and headerIdx and tip.sepgpContentTopY then
    -- The TOP used to be anchored off Tablet's own title fontstring
    -- (title:GetBottom() plus a fixed offset). That object is the same
    -- one Tablet repurposes for its "Scroll up (x/y)" hint while
    -- scrolled (see the title-caching comment above) -- and the hint can
    -- render in a different font/size than the real title, which changes
    -- title:GetHeight() and so silently shifts title:GetBottom() the
    -- moment you scroll. Since the frozen-header block above already
    -- computed the exact pixel offset from the window's own TOP down to
    -- where the data rows start (tip.sepgpContentTopY), anchoring off
    -- that instead ties the bar to the same fixed number our own always-
    -- correct overlay uses, not to a Tablet object whose size can change
    -- out from under it.
    --
    -- The BOTTOM used to be anchored to lastVisibleBtn's on-screen
    -- GetBottom(). That row is real and currently shown, so it isn't
    -- stale the way a scrolled-off row is, but it's still only ONE
    -- sample: any per-row rounding/height quirk on that specific button
    -- (or it simply not being the true last row, e.g. a hidden footer
    -- line the IsShown()/anchors check let through) throws the whole
    -- track off, which is what was cutting the bar short of the actual
    -- last row on screen. Sizing the frame instead of anchoring its
    -- bottom removes that single point of failure: dataRowCount/dataRowH
    -- come from counting every row this exact call already classified as
    -- kind == 1, so the bar's height always matches precisely the rows
    -- decorate() just drew, not wherever one particular button happens to
    -- report its edge.
    sb:ClearAllPoints()
    local topOff, sbH = tip.sepgpContentTopY, dataRowCount * dataRowH
    local fb, lb = tip.buttons[firstDataIdx], tip.buttons[lastDataIdx]
    local tt, ft, lbm = tip:GetTop(), fb and fb:GetTop(), lb and lb:GetBottom()
    if tt and ft and lbm and ft > lbm then
      topOff = math.max(tt - ft, tip.sepgpContentTopY) -- below the frozen header
      sbH = (tt - lbm) - topOff                        -- ...to the last row's bottom
      if sbH < 10 then sbH = dataRowCount * dataRowH end
    end
    -- Measured while unscrolled and reused while scrolled: the last row's
    -- position reads differently once the list has moved, which made the
    -- bar (and its thumb) change size as you scrolled.
    local sbKey = fsp * 1000 + floor((tip:GetWidth() or 0) + 0.5) + n * 1000000
    if (tip.scroll or 0) == 0 or tip.sepgpSbKey ~= sbKey then
      if (tip.scroll or 0) == 0 then
        tip.sepgpSbKey, tip.sepgpSbTop, tip.sepgpSbH = sbKey, topOff, sbH
      end
    else
      topOff, sbH = tip.sepgpSbTop, tip.sepgpSbH
    end
    sb:SetPoint("TOP", tip, "TOP", 0, -topOff)
    sb:SetPoint("RIGHT", tip, "RIGHT", -(SCROLLBAR_MARGIN * fsp), 0)
    sb:SetWidth(SCROLLBAR_WIDTH)
    sb:SetHeight(sbH)
    sb.sepgpTip = tip
    sb.sepgpMaxScroll = maxScroll

    local trackHeight = sb:GetHeight() or 0
    local visibleFrac = maxLinesPerScreen / n
    if visibleFrac > 1 then visibleFrac = 1 end
    local thumbHeight = trackHeight * visibleFrac
    if thumbHeight < 16 then thumbHeight = 16 end
    if thumbHeight > trackHeight then thumbHeight = trackHeight end
    sb.thumb:SetWidth(SCROLLBAR_WIDTH)
    sb.thumb:SetHeight(thumbHeight)

    if not sb.thumb.sepgpDragging then
      local maxOffset = trackHeight - thumbHeight
      if maxOffset < 0 then maxOffset = 0 end
      local frac = (tip.scroll or 0) / maxScroll -- 0 = top, 1 = fully scrolled down
      local offset = frac * maxOffset
      sb.thumb:ClearAllPoints()
      sb.thumb:SetPoint("TOP", sb, "TOP", 0, -offset)
    end
    sb.track:Show()
    sb.thumb:Show()
    sb:Show()
  else
    sb:Hide()
    if sb.thumb then sb.thumb:Hide() end
  end
end

-- /sepgpdeco prints what the standings window is made of, line by line
-- (Tablet line number, shown?, anchors, height, how it was classified, and
-- the text of the first two columns). Meant for tracking down any line
-- that still looks wrong.
local function esc(s)
  if not s then return "nil" end
  s = string.gsub(s, "|", "||")
  s = string.gsub(s, "\n", "\\n")
  return s
end
SLASH_SEPGPDECO1 = "/sepgpdeco"
SlashCmdList["SEPGPDECO"] = function()
  local reg = T.registry and T.registry.sepgp_standings
  local tip = reg and reg.tooltip
  if not (tip and tip.buttons and tip.owner == "sepgp_standings") then
    DEFAULT_CHAT_FRAME:AddMessage("sepgpdeco: standings window is not open")
    return
  end
  DEFAULT_CHAT_FRAME:AddMessage(string.format("sepgpdeco: numLines=%s scroll=%s height=%.1f fontSizePercent=%s",
    tostring(tip.numLines), tostring(tip.scroll), tip:GetHeight() or 0, tostring(tip.fontSizePercent)))
  for i = 1, tip.numLines or 0 do
    local btn = tip.buttons[i]
    DEFAULT_CHAT_FRAME:AddMessage(string.format("%d shown=%s pts=%d h=%.1f kind=%s L=[%s] R=[%s]",
      i, tostring(btn:IsShown()), btn:GetNumPoints(), btn:GetHeight() or 0,
      tostring(tip.sepgpKinds and tip.sepgpKinds[i]),
      esc(tip.lefts[i]:GetText()), esc(tip.rights[i]:GetText())))
  end
end

-- Tablet-2.0 recomputes every row position and the window height inside
-- tip:Show(). Wrapping Show() on OUR frame runs the decoration the moment
-- Tablet is done, in the same frame -- so the lines are there from the very
-- first paint and follow scrolling without lagging behind by a poll tick.
local function installShowHook(tip)
  if not tip or tip.sepgpShowHooked or type(tip.Show) ~= "function" then return end
  tip.sepgpShowHooked = true
  local origShow = tip.Show
  tip.Show = function(self, a, b, c)
    origShow(self, a, b, c)
    if self.buttons then
      for i = 1, table.getn(self.buttons) do self.buttons[i].sepgpGapDelta = nil end
    end
    decorate(self)
  end
end

function hookStandingsTip()
  local reg = T.registry and T.registry.sepgp_standings
  local tip = reg and reg.tooltip
  if tip then installShowHook(tip) end
  return tip
end

-- Runs every frame while the window is open. This used to be throttled to
-- a few times a second, which was the "lines lag behind while dragging the
-- Size slider" complaint: SetFontSizePercent fires (and calls Show(), which
-- the hook above already catches) on every tick of that slider, but a lot
-- of the rounding/positioning depends on values (button heights, GetBottom
-- readings) that only settle once WoW's own layout pass for that frame has
-- run, which can land a frame after Show() returns. Polling every frame
-- instead of every 0.25s means we're never more than one frame behind
-- instead of visibly catching up in a lurch. This is safe to do without a
-- throttle because decorateRow() already no-ops when nothing about a row
-- has actually changed since the last call.
local poller = CreateFrame("Frame")
poller:SetScript("OnUpdate", function()
  local tip = hookStandingsTip()
  if tip and tip.owner == "sepgp_standings" and tip:IsShown() then
    decorate(tip)
  end
end)

-- GLOBALS: sepgp_saychannel,sepgp_groupbyclass,sepgp_groupbyarmor,sepgp_groupbyrole,sepgp_raidonly,sepgp_decay,sepgp_minep,sepgp_reservechannel,sepgp_main,sepgp_progress,sepgp_discount,sepgp_log,sepgp_dbver,sepgp_looted
-- GLOBALS: sepgp,sepgp_prices,sepgp_standings,sepgp_bids,sepgp_loot,sepgp_reserves,sepgp_alts,sepgp_logs
