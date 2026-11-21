-- Telling your party how your quests go, in party chat, so members without a quest add-on see it:
--
--   {diamond} Clairvoyance: [Dragonkin Menace] Black Broodling slain 7/15    progress    (off)
--   {diamond} Clairvoyance: [Dragonkin Menace] Black Broodling slain 15/15   objectives  (on)
--   {diamond} Clairvoyance: [Dragonkin Menace] Quest Complete!                quests      (on)
--   {diamond} Clairvoyance: Picked up [Dragonkin Menace]                     accepted    (off)
--   {diamond} Clairvoyance: Abandoned [Dragonkin Menace]                     abandoned   (on)
--
-- Each kind has its own switch (CV.db.tell), under one main switch (CV.db.tellGroup). Only in a
-- party (a raid's chat would drown). A finished objective or quest is said once until the quest
-- leaves your log. Changes within half a second go out as one line per quest, and a quest that
-- just finished says only "Quest Complete!" (with that switch on). With Questie running, it
-- says the same, so Clairvoyance stays quiet.

local Core = NorgannonCore
local CV = Clairvoyance
if CV.disabled then return end

local Announce = { said = {}, pending = {}, titles = {} }
CV.Announce = Announce

local ICON = "{rt3} Clairvoyance:"   -- the purple diamond (every client draws it) and our name
local WAIT = .5
local ABANDON_WINDOW = 5             -- seconds: a quest leaving the log this soon after AbandonQuest

Announce.DEFAULTS = { progress = false, objectives = true, quests = true, accepted = false, abandoned = true }

local function loaded(name)
  local api = rawget(_G, "C_AddOns")
  local fn = (api and api.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
  return fn and fn(name) and true or false
end

---Whether this kind of line is wanted: its switch (or its default).
function Announce.Wants(kind)
  local tell = CV.db.tell
  local v = tell and tell[kind]
  if v == nil then return Announce.DEFAULTS[kind] == true end
  return v == true
end

---Whether a line would go out now: the main switch is on, you're in a party (not a raid), and no
---Questie is there to say it already. kind: also that kind's switch.
function Announce.Active(kind)
  if not (CV.ready and CV.db.tellGroup ~= false and IsInGroup() and not IsInRaid() and not loaded("Questie")) then
    return false
  end
  return kind == nil or Announce.Wants(kind)
end

local function questLink(id, title)
  local getLink = rawget(_G, "GetQuestLink")
  local link = getLink and getLink(id)
  if type(link) == "string" and not Core.IsSecret(link) then return link end
  title = title or Announce.titles[id] or (Core.DB and Core.DB:Name("quests", id))
  return "[" .. (title or "a quest") .. "]"
end

---"Black Broodling slain 15/15" from the objective.
function Announce.ObjectiveText(o)
  -- the game's text carries the count, in front ("15/15 Black Broodling slain") or behind
  -- ("Black Broodling slain: 15/15"); drop it wherever it is, and add ours at the end
  local text = o.text or o.name
  if text then
    text = text:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub(":?%s*%(?%d+%s*/%s*%d+%)?%s*$", "")
  end
  if not text or text == "" then return nil end
  if o.current and o.required and o.required > 1 then text = text .. " " .. o.current .. "/" .. o.required end
  return text
end

local function send(text)
  local api = rawget(_G, "C_ChatInfo")
  local fn = (api and api.SendChatMessage) or rawget(_G, "SendChatMessage")
  if not fn or not pcall(fn, text:sub(1, 255), "PARTY") then return end
  if not CV.db.toldGroup then
    CV.db.toldGroup = true
    CV:Print("Told your party how a quest went. What gets said, or nothing, is under Party chat in the settings.")
  end
end

local function flush(id)
  local indexes = Announce.pending[id]
  Announce.pending[id] = nil
  local q = Core.Player.quests[id]
  if not indexes or not q or not Announce.Active() then return end
  local link = questLink(id, q.title)
  if q.complete == true and Announce.Wants("quests") then
    if not Announce.said[id .. ":done"] then
      Announce.said[id .. ":done"] = true
      send(ICON .. " " .. link .. " Quest Complete!")
    end
    return
  end
  local parts, seen = {}, {}
  for _, i in ipairs(indexes) do
    local o = q.objectives[i]
    local text = o and not seen[i] and Announce.ObjectiveText(o)
    seen[i] = true
    if text then
      local key = id .. ":" .. i
      if o.finished then
        -- a finished objective is said once, by either switch
        if not Announce.said[key] and (Announce.Wants("objectives") or Announce.Wants("progress")) then
          Announce.said[key] = true
          parts[#parts + 1] = text
        end
      elseif Announce.Wants("progress") then
        Announce.said[key] = nil
        parts[#parts + 1] = text
      end
    end
  end
  if #parts > 0 then send(ICON .. " " .. link .. " " .. table.concat(parts, ", ")) end
end

local function later(id, index)
  local pending = Announce.pending[id]
  local first = not pending
  pending = pending or {}
  Announce.pending[id] = pending
  if index then pending[#pending + 1] = index end
  if first then C_Timer.After(WAIT, function() flush(id) end) end
end

-- each objective's last count, so only a rise is progress (not an item dropped or sold)
local before = {}

Core:Listen("NORGANNON_QUEST_PROGRESS", "clairvoyance.announce", function(_, id, index)
  local q = Core.Player.quests[id]
  local o = q and q.objectives[index]
  if not o then return end
  local key = id .. ":" .. index
  local was = before[key]
  before[key] = o.current
  if not Announce.Active() then return end
  local rose = o.current and (was == nil or o.current > was)
  if o.finished or (rose and Announce.Wants("progress")) then later(id, index) end
end)

Core:Listen("NORGANNON_QUEST_COMPLETE", "clairvoyance.announce", function(_, id)
  if Announce.Active() then later(id) end
end)

Core:Listen("NORGANNON_QUEST_ACCEPTED", "clairvoyance.announce", function(_, id)
  local q = Core.Player.quests[id]
  if q then
    Announce.titles[id] = q.title
    for i, o in ipairs(q.objectives or {}) do before[id .. ":" .. i] = o.current end
  end
  if Announce.Active("accepted") then send(ICON .. " Picked up " .. questLink(id, q and q.title)) end
end)

-- AbandonQuest says it was abandoned, not failed or handed in; without the hook, not handed in
local hooked, abandonedAt = false, nil
if rawget(_G, "AbandonQuest") and rawget(_G, "hooksecurefunc") then
  hooksecurefunc("AbandonQuest", function() abandonedAt = GetTime() end)
  hooked = true
end
Announce.AbandonHooked = hooked

local function forget(map, id)
  local prefix = id .. ":"
  for key in pairs(map) do
    if key:sub(1, #prefix) == prefix then map[key] = nil end
  end
end

Core:Listen("NORGANNON_QUEST_REMOVED", "clairvoyance.announce", function(_, id, turnedIn)
  local abandoned = not turnedIn and (not hooked or (abandonedAt ~= nil and GetTime() - abandonedAt < ABANDON_WINDOW))
  if abandoned and Announce.Active("abandoned") then
    send(ICON .. " Abandoned " .. questLink(id, Announce.titles[id]))
  end
  forget(Announce.said, id)
  forget(before, id)
end)

-- titles and counts for quests already in the log at login
Core:Listen("NORGANNON_PLAYER_READY", "clairvoyance.announce", function()
  for id, q in pairs(Core.Player.quests) do
    Announce.titles[id] = q.title
    for i, o in ipairs(q.objectives or {}) do before[id .. ":" .. i] = o.current end
  end
end)
