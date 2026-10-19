-- Automation, off by default (the welcome presets or the settings turn it on), each part on its
-- own switch (ClairvoyanceDB.auto):
--
--   accept   accept quests offered to you, unless they're grey (low level, while low-level quests
--            are hidden) or you hid them on the map; never when your log is full
--   turnin   hand in finished quests; with one reward (or none) take it. Never when the turn-in
--            costs money
--   reward   with a choice of rewards, take the one that sells for the most (a hint for upgrades
--            comes later); without prices for every choice, it leaves the choice to you
--   gossip   skip the chatter: at an NPC with quests, go straight to a finished quest (turn-in) or
--            a quest to take (accept); only what the switches above would do anyway
--
-- Holding Shift pauses all of it. Every automatic step prints a short chat line, so nothing
-- happens unseen.

local Core = NorgannonCore
local DB = NorgannonDB
local CV = Clairvoyance
if CV.disabled then return end

local Auto = {}
CV.Auto = Auto

local function on(key) return CV.ready and CV.db.auto and CV.db.auto[key] and not IsShiftKeyDown() end
Auto.On = on

local function say(text) if CV.db.auto.quiet ~= true then CV:Print(text) end end

local function logFull()
  local count = #CV.Model:List()
  local max = 40
  if C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept then
    local ok, n = pcall(C_QuestLog.GetMaxNumQuestsCanAccept)
    if ok and type(n) == "number" and n > 0 and not Core.IsSecret(n) then max = n end
  end
  return count >= max
end

---Whether auto-accept may take this quest: not grey (unless grey quests are shown), not hidden
---on the map by you. Quests NorgannonDB doesn't know are taken.
function Auto.Acceptable(questId, trivialFromGame)
  if not questId or questId == 0 then return trivialFromGame ~= true or CV.db.showTrivial end
  if CV:IsHiddenOnMap(questId) then return false end
  local q = DB:Get("quests", questId)
  local trivial = trivialFromGame
  if trivial == nil and q and q.level and not CV.Availability.Levelless(q) then
    trivial = Core.UI.Difficulty(q.level, Core.Player.level or UnitLevel("player") or 1) == Core.UI.C.trivial
  end
  if trivial and not CV.db.showTrivial then return false end
  return true
end

local function questName(id, fallback) return (id and Core.DB:Name("quests", id)) or fallback or "quest" end

-------------------------------------------------------------------------------------------
-- The quest frame: offer, progress, rewards
-------------------------------------------------------------------------------------------

Core:On("QUEST_DETAIL", "clairvoyance.auto", function()
  if not on("accept") or logFull() then return end
  local id = GetQuestID and GetQuestID()
  if not Auto.Acceptable(id) then return end
  AcceptQuest()
  say("Accepted " .. questName(id, GetTitleText and GetTitleText()))
end)

Core:On("QUEST_PROGRESS", "clairvoyance.auto", function()
  if not on("turnin") then return end
  if not (IsQuestCompletable and IsQuestCompletable()) then return end
  if GetQuestMoneyToGet and (GetQuestMoneyToGet() or 0) > 0 then return end   -- costs money: your call
  CompleteQuest()
end)

---The reward to take: the only one, or (with the reward switch) the best seller. nil = ask you.
function Auto.PickReward()
  local n = GetNumQuestChoices and GetNumQuestChoices() or 0
  if n <= 1 then return n, nil end
  if not on("reward") then return nil end
  local best, bestPrice
  for i = 1, n do
    local link = GetQuestItemLink("choice", i)
    if not link then return nil end
    local price = select(11, GetItemInfo(link))
    if price == nil then return nil end         -- not cached yet: don't guess
    if not bestPrice or price > bestPrice then best, bestPrice = i, price end
  end
  return best, GetQuestItemLink("choice", best)
end

Core:On("QUEST_COMPLETE", "clairvoyance.auto", function()
  if not on("turnin") then return end
  local id = GetQuestID and GetQuestID()
  local choice, link = Auto.PickReward()
  if not choice then return end
  GetQuestReward(choice)
  say("Turned in " .. questName(id, GetTitleText and GetTitleText()) .. (link and (", took " .. link .. " (best vendor value)") or ""))
end)

-------------------------------------------------------------------------------------------
-- Gossip and the old quest greeting: straight to the quest
-------------------------------------------------------------------------------------------

Core:On("GOSSIP_SHOW", "clairvoyance.auto", function()
  if not on("gossip") or not C_GossipInfo then return end
  if on("turnin") then
    for _, q in ipairs(C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests() or {}) do
      if q.isComplete and q.questID then C_GossipInfo.SelectActiveQuest(q.questID) return end
    end
  end
  if on("accept") and not logFull() then
    for _, q in ipairs(C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests() or {}) do
      if q.questID and Auto.Acceptable(q.questID, q.isTrivial) then C_GossipInfo.SelectAvailableQuest(q.questID) return end
    end
  end
end)

Core:On("QUEST_GREETING", "clairvoyance.auto", function()
  if not on("gossip") then return end
  if on("turnin") then
    for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
      local _, complete = GetActiveTitle(i)
      if complete then SelectActiveQuest(i) return end
    end
  end
  if on("accept") and not logFull() then
    for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
      local trivial = GetAvailableQuestInfo and select(1, GetAvailableQuestInfo(i))
      local id = GetAvailableQuestInfo and select(5, GetAvailableQuestInfo(i))
      if Auto.Acceptable(type(id) == "number" and id or nil, trivial == true) then SelectAvailableQuest(i) return end
    end
  end
end)
