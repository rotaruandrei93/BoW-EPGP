-- externalnotify.lua
-- Remote standings for external mains (players in OTHER guilds / unguilded whose
-- EPGP lives on a banker alt in Blades of Wrynn, tagged {X:Name} in the officer note).
--
-- WoW 1.12 cannot send addon messages to a player outside your guild (only
-- PARTY / RAID / GUILD / BATTLEGROUND exist), so this uses a small hidden custom
-- chat channel that Squire+ members and external mains join. Every message is
-- tagged and filtered out of all chat windows, so nobody sees anything.
--
-- When an external main opens the standings window (or types /sepgpstanding):
--   1. the addon joins the hidden channel and asks "who can serve me?" (XQ);
--   2. every online member who is rank Squire or higher (can read officer notes)
--      answers (XA) - but only if the asker is a registered external main
--      ({X:Name} in some officer note), so random channel joiners get nothing;
--   3. the requester picks the first one (XR) and that member streams the whole
--      standings list back in small chunks (XL);
--   4. the standings window is filled with that list and a copy is saved, so the
--      window still shows the last known list when nobody qualified is online.
--
-- Command:  /sepgpstanding  open the standings window and refresh it

local VERSION        = "6"         -- shown by /sepgpstanding so you can check every copy matches
local CHANNEL        = "BoWEPGPSync"
local MARK           = "SEPGPX;"
local GUILD_NAME     = "Blades of Wrynn"
local MIN_RANK_NAME  = "Squire"   -- this rank and every rank above it may serve
local OFFER_WAIT     = 8          -- seconds to wait for any Squire+ member to answer
local PICK_TIMEOUT   = 15         -- seconds a chosen member gets to finish streaming
local AUTO_MIN_AGE   = 60         -- don't re-request if the saved list is fresher than this
local SERVE_COOLDOWN = 30
local CHUNK_CHARS    = 200
local CHUNK_SPACING  = 0.4

local ext = {}
sepgp.extRemote = ext

local frame = CreateFrame("Frame")
local tasks = {}
local cur = nil                   -- current request
local lastServed = {}
local lastAnswered = {}
local serverJoined = false

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

------------------------------------------------------------------ hidden channel

local function channelId()
  local id = GetChannelName(CHANNEL)
  if id and id > 0 then return id end
  return nil
end

-- join (if needed), then run fn; gives up silently after ~10 s
local function withChannel(fn, tries)
  tries = tries or 0
  if channelId() then fn() return end
  if tries == 0 then
    JoinChannelByName(CHANNEL)
    if ChatFrame_RemoveChannel then ChatFrame_RemoveChannel(DEFAULT_CHAT_FRAME, CHANNEL) end
  end
  if tries >= 10 then return end
  after(1, function() withChannel(fn, tries + 1) end)
end

local function send(msg)
  local id = channelId()
  if id then SendChatMessage(MARK .. msg, "CHANNEL", nil, id) end
end

local function isOurChannel(name)
  return name and string.find(string.lower(name), string.lower(CHANNEL), 1, true) ~= nil
end

-- Hide everything we send/receive and the channel join/leave notices from all chat frames.
local orig_ChatFrame_OnEvent = ChatFrame_OnEvent
ChatFrame_OnEvent = function(ev)
  if ev == "CHAT_MSG_CHANNEL" then
    if arg1 and string.sub(arg1, 1, string.len(MARK)) == MARK then return end
  elseif ev == "CHAT_MSG_CHANNEL_NOTICE" or ev == "CHAT_MSG_CHANNEL_NOTICE_USER"
      or ev == "CHAT_MSG_CHANNEL_JOIN" or ev == "CHAT_MSG_CHANNEL_LEAVE" then
    if isOurChannel(arg4) or isOurChannel(arg8) or isOurChannel(arg1) then return end
  end
  return orig_ChatFrame_OnEvent(ev)
end

------------------------------------------------------------------ view hooks (used by standings.lua)

local function hasSnapshot()
  local s = sepgp_external_snapshot
  return s ~= nil and s.rows ~= nil and table.getn(s.rows) > 0
end

function ext:IsActive()
  if not notBoW() then return false end
  return hasSnapshot() or (cur ~= nil)
end

function ext:Rows()
  if hasSnapshot() then
    return sepgp_external_snapshot.rows
  end
  return {}
end

function ext:StatusText()
  local s = hasSnapshot() and sepgp_external_snapshot or nil
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

local NOBODY = "No Blades of Wrynn member (rank " .. MIN_RANK_NAME .. "+ with the addon) is online to answer. Showing the last saved list."

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
  send("XR;" .. req.id .. ";" .. who)
  local idx = req.offerIdx
  after(PICK_TIMEOUT, function()
    if req == cur and not req.done and req.offerIdx == idx then
      pickNext(req)   -- that member never finished; try the next one who offered
      if not req.picking then fail(req, NOBODY) end
    end
  end)
end

local function startRequest(manual)
  if not notBoW() then return end
  if cur then
    if manual then cur.manual = true end
    return
  end
  local s = hasSnapshot() and sepgp_external_snapshot or nil
  if (not manual) and s and s.got and (time() - s.got) < AUTO_MIN_AGE then return end
  local req = {id = tostring(math.random(100000, 999999)), manual = manual,
               offers = {}, offerIdx = 0, picking = false, chunks = {}, got = 0, done = false}
  cur = req
  refreshWindow()
  withChannel(function()
    if req ~= cur or req.done then return end
    send("XQ;" .. req.id)
    after(OFFER_WAIT, function()
      if req == cur and not req.done and not req.picking then fail(req, NOBODY) end
    end)
  end)
  -- channel never came up
  after(OFFER_WAIT + 12, function()
    if req == cur and not req.done and not req.picking then
      fail(req, "Could not reach the Blades of Wrynn sync channel.")
    end
  end)
end

local function commit(req, sender)
  local rows = {}
  for seq = 1, req.total do
    local chunk = req.chunks[seq] or ""
    for row in string.gfind(chunk, "([^,|]+)") do
      local _, _, n, c, ep, gp, x = string.find(row, "^([^:]+):([^:]+):(%d+):(%d+):([^:]*)$")
      if n then
        if x == "-" or x == "" then x = nil end
        table.insert(rows, {n, c, tonumber(ep), math.max(1, tonumber(gp)), x})
      end
    end
  end
  req.done = true
  if table.getn(rows) == 0 then
    -- never replace a good saved list with an unreadable one
    local sample = string.gsub(string.sub(req.chunks[1] or "", 1, 70), "|", "/")
    say(string.format("%s sent a list I could not read (%d chunk(s)). Sample: %s - is their addon up to date?", sender, req.total, sample))
    finish(req)
    return
  end
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

local function serve(id)
  local rows = buildRows()
  local chunks, buf = {}, ""
  for i = 1, table.getn(rows) do
    if buf ~= "" and string.len(buf) + string.len(rows[i]) + 1 > CHUNK_CHARS then
      table.insert(chunks, buf)
      buf = ""
    end
    if buf ~= "" then buf = buf .. "," end
    buf = buf .. rows[i]
  end
  if buf ~= "" then table.insert(chunks, buf) end
  local total = table.getn(chunks)
  for seq = 1, total do
    local msg = string.format("XL;%s;%d;%d;%s", id, seq, total, chunks[seq])
    after(seq * CHUNK_SPACING, function() send(msg) end)
  end
end

-- only registered external mains ({X:Name} in an officer note) may be served
local function isRegisteredExternal(name)
  sepgp:buildExternalMainsTable()
  if not sepgp.external_mains then return false end
  return sepgp.external_mains[string.lower(name)] ~= nil
end

------------------------------------------------------------------ messages

local function onChannelMsg(text, sender)
  if not sender or sender == UnitName("player") then return end
  if string.sub(text, 1, string.len(MARK)) ~= MARK then return end
  local msg = string.sub(text, string.len(MARK) + 1)

  -- XQ: an external main asks who can serve standings
  local _, _, qid = string.find(msg, "^XQ;(%d+)$")
  if qid then
    if not serverJoined or not canServe() then return end
    if not isRegisteredExternal(sender) then return end
    local last = lastAnswered[sender]
    if last and GetTime() - last < 3 then return end
    lastAnswered[sender] = GetTime()
    after(math.random() * 0.8, function() send("XA;" .. qid .. ";" .. sender) end)
    return
  end

  -- XR: the requester picked one of us
  local _, _, rid, rto = string.find(msg, "^XR;(%d+);([^;]+)$")
  if rid then
    if rto ~= UnitName("player") then return end
    if not canServe() or not isRegisteredExternal(sender) then return end
    local last = lastServed[sender]
    if last and GetTime() - last < SERVE_COOLDOWN then return end
    lastServed[sender] = GetTime()
    GuildRoster() -- keep our own roster fresh for next time
    serve(rid)
    return
  end

  if not cur then return end

  -- XA: a Squire+ member offers to serve our request
  local _, _, aid, ato = string.find(msg, "^XA;(%d+);([^;]+)$")
  if aid then
    if aid ~= cur.id or ato ~= UnitName("player") or cur.done then return end
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

frame:RegisterEvent("CHAT_MSG_CHANNEL")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function()
  if event == "CHAT_MSG_CHANNEL" then
    if isOurChannel(arg4) then onChannelMsg(arg1, arg2) end
  elseif event == "PLAYER_ENTERING_WORLD" then
    frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    -- Squire+ members join the hidden channel once their guild data is loaded
    local function tryJoin(n)
      if IsInGuild() then GuildRoster() end
      after(5, function()
        if canServe() then
          withChannel(function() serverJoined = true end)
        elseif n < 4 then
          tryJoin(n + 1)
        end
      end)
    end
    after(20, function() tryJoin(1) end)
  end
end)

------------------------------------------------------------------ entry points

-- called by sepgp_standings:Toggle() whenever the window is opened
function ext:OnOpen()
  startRequest(false)
end

SLASH_SEPGPSTANDING1 = "/sepgpstanding"
SlashCmdList["SEPGPSTANDING"] = function()
  local g = IsInGuild() and GetGuildInfo("player") or nil
  say(string.format("externalnotify v%s (guild: %s)", VERSION, IsInGuild() and (g or "not loaded yet") or "none"))
  if not notBoW() then
    if g == GUILD_NAME then
      say("You are in Blades of Wrynn - use the normal standings window.")
    else
      say("Guild info is not loaded yet - try again in a few seconds.")
    end
    return
  end
  sepgp_standings:Toggle(true)
  startRequest(true)
end
