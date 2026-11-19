-- Telling your party how a quest goes, in party chat, so members without a quest add-on see it too:
--
--   {diamond} [Dragonkin Menace] Black Broodling slain 15/15     an objective just finished
--   {diamond} [Dragonkin Menace] is ready to hand in             the last one finished
--
-- Only finished objectives, never every kill; only in a party (a raid's chat would drown);
-- once per objective until the quest leaves your log; changes within half a second are sent
-- as one line (the quest's last objective says just "ready to hand in"). With Questie running,
-- Questie already says it, so Clairvoyance stays quiet. Setting: tellGroup.

local Core = NorgannonCore
local CV = Clairvoyance
if CV.disabled then return end

local Announce = { said = {}, pending = {} }
CV.Announce = Announce

local ICON = "{rt3}"   -- the purple diamond, Clairvoyance's colour; every client draws it
local WAIT = .5

local function loaded(name)
  local api = rawget(_G, "C_AddOns")
  local fn = (api and api.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
  return fn and fn(name) and true or false
end

---Whether a line would go out now: the setting is on, you're in a party (not a raid), and no
---Questie is there to say it already.
function Announce.Active()
  return CV.ready and CV.db.tellGroup ~= false and IsInGroup() and not IsInRaid() and not loaded("Questie")
end

local function questLink(q, id)
  local getLink = rawget(_G, "GetQuestLink")
  local link = getLink and getLink(id)
  if type(link) == "string" and not Core.IsSecret(link) then return link end
  return "[" .. (q.title or "a quest") .. "]"
end

---"Black Broodling slain 15/15" from the objective (the game's text ends ": 15/15").
function Announce.ObjectiveText(o)
  local text = o.text and o.text:gsub(":%s*%d+%s*/%s*%d+%s*$", "") or o.name
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
    CV:Print("Told your party you finished an objective. To stop, turn off Tell your party under Automation.")
  end
end

local function flush(id)
  local indexes = Announce.pending[id]
  Announce.pending[id] = nil
  local q = Core.Player.quests[id]
  if not indexes or not q or not Announce.Active() then return end
  local link = questLink(q, id)
  if q.complete == true then
    if not Announce.said[id .. ":done"] then
      Announce.said[id .. ":done"] = true
      send(ICON .. " " .. link .. " is ready to hand in")
    end
    return
  end
  local parts = {}
  for _, i in ipairs(indexes) do
    local o = q.objectives[i]
    local text = o and o.finished and Announce.ObjectiveText(o)
    if text and not Announce.said[id .. ":" .. i] then
      Announce.said[id .. ":" .. i] = true
      parts[#parts + 1] = text
    end
  end
  if #parts > 0 then send(ICON .. " " .. link .. " " .. table.concat(parts, ", ")) end
end

local function later(id, index)
  if not Announce.Active() then return end
  local pending = Announce.pending[id]
  local first = not pending
  pending = pending or {}
  Announce.pending[id] = pending
  if index then pending[#pending + 1] = index end
  if first then C_Timer.After(WAIT, function() flush(id) end) end
end

Core:Listen("NORGANNON_QUEST_PROGRESS", "clairvoyance.announce", function(_, id, index)
  local q = Core.Player.quests[id]
  local o = q and q.objectives[index]
  if o and o.finished then later(id, index) end
end)
Core:Listen("NORGANNON_QUEST_COMPLETE", "clairvoyance.announce", function(_, id) later(id) end)
Core:Listen("NORGANNON_QUEST_REMOVED", "clairvoyance.announce", function(_, id)
  for key in pairs(Announce.said) do
    if key:match("^(%d+):") == tostring(id) then Announce.said[key] = nil end
  end
end)
