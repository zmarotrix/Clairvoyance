-- What quest-givers really offer. NorgannonDB has no prerequisites for many of the quests new to
-- WoW Forever (303 of 872 have any), so the rules call some of them available too early: the
-- second "A Friend of the Family" (98191) showed a "!" on Bolvar for anyone. The game knows
-- better. Talking to a quest-giver lists what it will give you now, so a quest Clairvoyance
-- expected there that the game didn't list is held back for this character
-- (ClairvoyanceCharDB.notOffered[questId] = the NPC or object id) until one of these happens:
--
--   the quest-giver offers it after all · you level up · you turn in a quest from the same zone,
--   or one handed in to that quest-giver (what usually opens the next step of a chain)
--
-- Quests grey by level are never judged: the game leaves those off the list while low-level
-- quests are hidden. The game rates quests greener than Classic's ranges, never greyer, so a quest
-- the level rule calls green is always listed when it's really available.

local Core = NorgannonCore
local DB = NorgannonDB
local CV = Clairvoyance
if CV.disabled then return end

local Offers = {}
CV.Offers = Offers

local function held() return CV.char and CV.char.notOffered end

---Whether the game left this quest off its quest-giver's list for this character.
function Offers.Held(questId)
  local t = held()
  return t ~= nil and t[questId] ~= nil
end

---The quests this quest-giver should offer by the rules, grey ones left out (see the top).
local function expected(kind, id)
  local giver = DB:Get(kind, id)
  local out = {}
  local level = Core.Player.level or UnitLevel("player") or 1
  for _, questId in ipairs(giver and giver.questStarts or {}) do
    local q = DB:Get("quests", questId)
    if q and CV.Availability.Check(questId, q, true) then
      local grey = not CV.Availability.Levelless(q) and q.level and q.level > 0
        and Core.UI.Difficulty(q.level, level) == Core.UI.C.trivial
      if not grey then out[#out + 1] = questId end
    end
  end
  return out
end

---The game listed `offered` (questId -> true) at this quest-giver: hold back what it left out and
---release what it gave. Returns how many quests changed.
function Offers:Learn(kind, id, offered)
  local t = held()
  if not (t and kind and id) then return 0 end
  local changed = 0
  for _, questId in ipairs(expected(kind, id)) do
    if not offered[questId] and t[questId] == nil then t[questId] = id changed = changed + 1 end
  end
  for questId in pairs(offered) do
    if t[questId] ~= nil then t[questId] = nil changed = changed + 1 end
  end
  if changed > 0 then CV.Availability:Invalidate() end
  return changed
end

local function giver()
  return CV.Tooltips.ParseGUID(UnitGUID("npc"))
end

Core:On("GOSSIP_SHOW", "clairvoyance.offers", function()
  if not (CV.ready and C_GossipInfo and C_GossipInfo.GetAvailableQuests) then return end
  local kind, id = giver()
  if not kind then return end
  local offered = {}
  for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
    if type(q) == "table" and type(q.questID) == "number" and not Core.IsSecret(q.questID) then offered[q.questID] = true end
  end
  Offers:Learn(kind, id, offered)
end)

Core:On("QUEST_GREETING", "clairvoyance.offers", function()
  if not (CV.ready and GetNumAvailableQuests and GetAvailableQuestInfo) then return end
  local kind, id = giver()
  if not kind then return end
  local offered = {}
  for i = 1, GetNumAvailableQuests() or 0 do
    local questId = select(5, GetAvailableQuestInfo(i))
    -- without ids the list can't be read: judge nothing rather than hold back everything
    if type(questId) ~= "number" or Core.IsSecret(questId) then return end
    offered[questId] = true
  end
  Offers:Learn(kind, id, offered)
end)

---Release what a turn-in may have opened: quests from the same zone, and quests from the
---quest-giver the quest was handed in to.
function Offers:TurnedIn(questId)
  local t = held()
  if not (t and next(t)) then return end
  local done = DB:Get("quests", questId)
  if not done then return end
  local to = {}
  for _, npc in ipairs(done.finishers and done.finishers.npcs or {}) do to[npc] = true end
  for _, obj in ipairs(done.finishers and done.finishers.objects or {}) do to[obj] = true end
  for heldId, from in pairs(t) do
    local q = DB:Get("quests", heldId)
    if to[from] or (q and done.zoneOrSort and q.zoneOrSort == done.zoneOrSort) then t[heldId] = nil end
  end
end

Core:Listen("NORGANNON_QUEST_TURNED_IN", "clairvoyance.offers", function(_, questId)
  if CV.ready and questId then Offers:TurnedIn(questId) end
end)
Core:Listen("NORGANNON_LEVEL_CHANGED", "clairvoyance.offers", function()
  local t = held()
  if t then wipe(t) end
end)
