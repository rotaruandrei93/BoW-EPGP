-- externalnotify.lua
-- Remote standings for external mains (players in OTHER guilds / unguilded whose
-- EPGP lives on a banker alt in Blades of Wrynn, tagged {X:Name} in the officer note).
--
-- When an external main opens the standings window (or types /sepgpstanding):
--   1. the addon runs /who g-"Blades of Wrynn" and sends a hidden addon message
--      (XQ) to online members, in small batches;
--   2. every member who can read officer notes AND is rank Squire or higher
--      answers "I can serve" (XA);
--   3. the requester picks the first one (XR) and that member streams the whole
--      standings list back in small hidden chunks (XL);
--   4. the standings window is filled with that list and a copy is saved, so the
--      window still shows the last known list when nobody qualified is online.
--
-- No party/raid needed, no chat whispers, no bot. (Hidden addon whispers are the
-- only way the WoW API lets a player outside the guild talk to guild members.)
--
-- Commands:  /sepgpstanding  open the standings window and refresh it
--            /sepgpask <name>  ask one specific BoW member directly (fallback)

local PREFIX         = "SEPGPX"
local GUILD_NAME     = "Blades of Wrynn"
local MIN_RANK_NAME  = "Squire"   -- this rank and every rank above it may serve
local BATCH_SIZE     = 8          -- members asked per batch
local BATCH_WAIT     = 3          -- seconds between batches
local MAX_TARGETS    = 40
local WHO_COOLDOWN   = 30
local PICK_TIMEOUT   = 12         -- seconds a chosen member gets to finish streaming
local AUTO_MIN_AGE   = 60         -- don't re-request if the saved list is fresher than this
local SERVE_COOLDOWN = 30
local CHUNK_CHARS    = 200

local ext = {}
sepgp.extRemote = ext

local frame = CreateFrame("Frame")
local tasks = {}
local cur = nil                   -- current request
local whoReq = nil
local lastWho = -1000
local lastServed = {}
local lastAnswered = {}

------------------------------------------------------------------ helpers

local function after(delay, fn)
  table.insert(tasks, {at = GetTime() + delay, fn = fn})
end

frame:SetScript("OnUpdate", function()
  if table.getn(tasks) == 0 then return end
  local now = GetTime()
  local i = 1
  while i <= table.getn(tasks) do
    local t = tasks[i]
    if now >= t.at then
      table.remove(tasks, i)
      t.fn()
    else
      i = i + 1
    end
  end
end)

local function say(msg) sepgp:defaultPrint(msg) end

local function round(x) return math.floor((tonumber(x) or 0) + 0.5) end

local function isBoW()
  local g = GetGuildInfo("player")
  return g == GUILD_NAME
end

-- true only when we are SURE this character is not in Blades of Wrynn
-- (guild name not loaded yet = unknown = not remote)
local function notBoW()
  if not IsInGuild() then return true end
  local g = GetGuildInfo("player")
  return (g ~= nil) and (g ~= GUILD_NAME)
end

local function ageText(ts)
  local d = time() - (ts or 0)
  if d < 90 then return "just now" end
  if d < 5400 then return string.format("%d min ago", math.floor(d / 60)) end
  if d < 172800 then return string.format("%d h ago", math.floor(d / 3600)) end
  return string.format("%d days ago", math.floor(d / 86400))
end

-- May this character serve standings? (BoW member, Squire+, can read officer notes)
local function canServe()
  if not isBoW() or not CanViewOfficerNote() then return false end
  if GetNumGuildMembers(1) == 0 then GuildRoster() return false end
  local _, _, myIdx = GetGuildInfo("player")
  local limit
  for i = 1, GuildControlGetNumRanks() do
    if string.lower(GuildControlGetRankName(i) or "") == string.lower(MIN_RANK_NAME) then
      limit = i - 1
      break
    end
  end
  if limit and myIdx then return myIdx <= limit end
  return true
end

------------------------------------------------------------------ view hooks (used by standings.lua)

function ext:IsActive()
  if not notBoW() then return false end
  return (sepgp_external_snapshot ~= nil and sepgp_external_snapshot.rows ~= nil) or (cur ~= nil)
end

function ext:Rows()
  if sepgp_external_snapshot and sepgp_external_snapshot.rows then
    return sepgp_external_snapshot.rows
  end
  return {}
end

function ext:StatusText()
  local s = sepgp_external_snapshot
  if cur then
    if s and s.ts then
      return string.format("Updating from Blades of Wrynn... (showing list from %s)", ageText(s.ts))
    end
    return "Requesting standings from Blades of Wrynn..."
  end
  if s and s.ts then
    return string.format("Blades of Wrynn standings - updated %s", ageText(s.ts))
  end
  return "No standings received yet"
end

------------------------------------------------------------------ requester

local function refreshWindow()
  if sepgp_standings and sepgp_standings.Refresh then sepgp_standings:Refresh() end
end

local function finish(req)
  if cur == req then cur = nil end
  refreshWindow()
end

local function fail(req, text)
  if req.manual and text then say(text) end
  finish(req)
end

local function pickNext(req)
  if req ~= cur or req.done then return end
  req.offerIdx = req.offerIdx + 1
  local who = req.offers[req.offerIdx]
  if not who then
    req.picking = false
    return
  end
  req.picking = true
  req.chunks = {}
  req.total = nil
  req.got = 0
  SendAddonMessage(PREFIX, "XR;" .. req.id, "WHISPER", who)
  local idx = req.offerIdx
  after(PICK_TIMEOUT, function()
    if req == cur and not req.done and req.offerIdx == idx then
      pickNext(req)   -- that member never finished; try the next one who offered
    end
  end)
end

local function sendBatch(req)
  if req ~= cur or req.done then return end
  if req.picking then
    after(BATCH_WAIT, function() sendBatch(req) end)
    return
  end
  if req.idx > table.getn(req.targets) then
    if req.offerIdx >= table.getn(req.offers) then
      fail(req, "No Blades of Wrynn member (rank " .. MIN_RANK_NAME .. "+ with the addon) answered. Showing the last saved list. Try again later, or /sepgpask <name>.")
    end
    return
  end
  for i = 1, BATCH_SIZE do
    local t = req.targets[req.idx]
    if not t then break end
    SendAddonMessage(PREFIX, "XQ;" .. req.id, "WHISPER", t)
    req.idx = req.idx + 1
  end
  after(BATCH_WAIT, function() sendBatch(req) end)
end

local function newRequest(manual)
  return {id = tostring(math.random(100000, 999999)), manual = manual, targets = {}, idx = 1,
          offers = {}, offerIdx = 0, picking = false, chunks = {}, got = 0, done = false}
end

local function startRequest(manual)
  if not notBoW() then return end
  if cur then
    if manual then cur.manual = true end
    return
  end
  local s = sepgp_external_snapshot
  if (not manual) and s and s.got and (time() - s.got) < AUTO_MIN_AGE then return end
  if GetTime() - lastWho < WHO_COOLDOWN then
    if manual then say("Please wait a few seconds before refreshing again.") end
    return
  end
  lastWho = GetTime()
  cur = newRequest(manual)
  whoReq = {req = cur, wasVisible = (FriendsFrame and FriendsFrame:IsVisible()) and true or false}
  SetWhoToUI(1)
  SendWho('g-"' .. GUILD_NAME .. '"')
  refreshWindow()
  -- if /who never answers, give up
  local req = cur
  after(15, function()
    if cur == req and whoReq and whoReq.req == req then
      whoReq = nil
      SetWhoToUI(0)
      fail(req, "Could not search for Blades of Wrynn members (/who gave no answer).")
    end
  end)
end

local function onWhoList()
  if not whoReq then return end
  local wr = whoReq
  whoReq = nil
  SetWhoToUI(0)
  if FriendsFrame and FriendsFrame:IsVisible() and not wr.wasVisible then
    HideUIPanel(FriendsFrame)
  end
  local req = wr.req
  if req ~= cur then return end
  local me = UnitName("player")
  local targets = {}
  local num = GetNumWhoResults()
  for i = 1, num do
    local name, guild = GetWhoInfo(i)
    if name and name ~= me and guild == GUILD_NAME then
      table.insert(targets, name)
    end
  end
  for i = table.getn(targets), 2, -1 do
    local j = math.random(i)
    targets[i], targets[j] = targets[j], targets[i]
  end
  while table.getn(targets) > MAX_TARGETS do table.remove(targets) end
  if table.getn(targets) == 0 then
    fail(req, "No Blades of Wrynn members are online right now. Showing the last saved list.")
    return
  end
  req.targets = targets
  sendBatch(req)
end

local function commit(req, sender)
  local rows = {}
  for seq = 1, req.total do
    local chunk = req.chunks[seq] or ""
    for row in string.gfind(chunk, "([^|]+)") do
      local _, _, n, c, ep, gp, x = string.find(row, "^([^:]+):([^:]+):(%d+):(%d+):([^:]*)$")
      if n then
        if x == "-" or x == "" then x = nil end
        table.insert(rows, {n, c, tonumber(ep), math.max(1, tonumber(gp)), x})
      end
    end
  end
  req.done = true
  sepgp_external_snapshot = {rows = rows, ts = time(), got = time(), src = sender}
  if req.manual then
    say(string.format("Standings updated (%d entries, via %s).", table.getn(rows), sender))
  end
  finish(req)
end

------------------------------------------------------------------ server side (Squire+ members)

local function buildRows()
  local rows = {}
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, _, officernote = GetGuildRosterInfo(i)
    if name then
      local ep = round(sepgp:get_ep_v3(name, officernote))
      if ep > 0 then
        local gp = round(sepgp:get_gp_v3(name, officernote) or sepgp.VARS.basegp)
        local x = sepgp:parseExternalTag(officernote) or "-"
        table.insert(rows, string.format("%s:%s:%d:%d:%s", name, class or "?", ep, gp, x))
      end
    end
  end
  return rows
end

local function serve(to, id)
  local rows = buildRows()
  local chunks, buf = {}, ""
  for i = 1, table.getn(rows) do
    if buf ~= "" and string.len(buf) + string.len(rows[i]) + 1 > CHUNK_CHARS then
      table.insert(chunks, buf)
      buf = ""
    end
    if buf ~= "" then buf = buf .. "|" end
    buf = buf .. rows[i]
  end
  if buf ~= "" then table.insert(chunks, buf) end
  local total = table.getn(chunks)
  if total == 0 then return end
  for seq = 1, total do
    local msg = string.format("XL;%s;%d;%d;%s", id, seq, total, chunks[seq])
    after(seq * 0.25, function() SendAddonMessage(PREFIX, msg, "WHISPER", to) end)
  end
end

------------------------------------------------------------------ messages

local function onAddon(prefix, msg, channel, sender)
  if prefix ~= PREFIX or channel ~= "WHISPER" then return end
  if not sender or sender == UnitName("player") then return end

  -- XQ: someone asks who can serve standings
  local _, _, qid = string.find(msg, "^XQ;(%d+)$")
  if qid then
    if not canServe() then return end
    local last = lastAnswered[sender]
    if last and GetTime() - last < 3 then return end
    lastAnswered[sender] = GetTime()
    after(math.random() * 0.8, function()
      SendAddonMessage(PREFIX, "XA;" .. qid, "WHISPER", sender)
    end)
    return
  end

  -- XR: the requester picked us
  local _, _, rid = string.find(msg, "^XR;(%d+)$")
  if rid then
    if not canServe() then return end
    local last = lastServed[sender]
    if last and GetTime() - last < SERVE_COOLDOWN then return end
    lastServed[sender] = GetTime()
    GuildRoster() -- keep our own roster fresh for next time
    serve(sender, rid)
    return
  end

  if not cur then return end

  -- XA: a Squire+ member offers to serve our request
  local _, _, aid = string.find(msg, "^XA;(%d+)$")
  if aid then
    if aid ~= cur.id or cur.done then return end
    for i = 1, table.getn(cur.offers) do
      if cur.offers[i] == sender then return end
    end
    table.insert(cur.offers, sender)
    if not cur.picking then pickNext(cur) end
    return
  end

  -- XL: a chunk of the standings list from the member we picked
  local _, _, lid, seq, total, rows = string.find(msg, "^XL;(%d+);(%d+);(%d+);(.*)$")
  if lid then
    if lid ~= cur.id or cur.done then return end
    if cur.offers[cur.offerIdx] ~= sender then return end
    seq, total = tonumber(seq), tonumber(total)
    if not cur.total then cur.total = total end
    if total ~= cur.total or cur.chunks[seq] then return end
    cur.chunks[seq] = rows
    cur.got = cur.got + 1
    if cur.got >= cur.total then commit(cur, sender) end
  end
end

frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("WHO_LIST_UPDATE")
frame:SetScript("OnEvent", function()
  if event == "CHAT_MSG_ADDON" then
    onAddon(arg1, arg2, arg3, arg4)
  elseif event == "WHO_LIST_UPDATE" then
    onWhoList()
  end
end)

------------------------------------------------------------------ entry points

-- called by sepgp_standings:Toggle() whenever the window is opened
function ext:OnOpen()
  startRequest(false)
end

SLASH_SEPGPSTANDING1 = "/sepgpstanding"
SlashCmdList["SEPGPSTANDING"] = function()
  if not notBoW() then
    say("You are in Blades of Wrynn - use the normal standings window.")
    return
  end
  sepgp_standings:Toggle(true)
  startRequest(true)
end

SLASH_SEPGPASK1 = "/sepgpask"
SlashCmdList["SEPGPASK"] = function(name)
  if not notBoW() then return end
  if not name or name == "" then
    say("Usage: /sepgpask <Blades of Wrynn member name>")
    return
  end
  if cur then cur.manual = true else
    cur = newRequest(true)
    local req = cur
    after(20, function() if cur == req and not req.done and not req.picking then fail(req, "No answer from " .. name .. ".") end end)
  end
  SendAddonMessage(PREFIX, "XQ;" .. cur.id, "WHISPER", name)
  refreshWindow()
end
