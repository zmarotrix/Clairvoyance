-- Which quests the player can pick up. Pure rules over NorgannonDB and Core.Player, checked in
-- the order the game does, each with a reason (so a "why isn't it offered?" answer is one call):
--
--   hidden in NorgannonDB · already done · in the log · level window · race · class · seasonal
--   prerequisites (all of / any one of) · exclusive alternatives · breadcrumb already followed
--   available only while/after another quest · until another is done · not while another is
--   in the log · profession skill · reputation window · a spell the player must (not) know
--
-- Evaluated per zone (the player's and the one the world map shows), cached, and recalculated
-- only when something relevant changes. CLAIRVOYANCE_AVAILABLE_UPDATED (area) announces it.

local Core = NorgannonCore
local DB = NorgannonDB
local CV = Clairvoyance
if CV.disabled then return end

local Availability = { byArea = {}, FAR_ABOVE = 10, LEVELLESS_GAP = 20 }

---A quest whose level is far beyond its minimum (e.g. level 60, open from level 1) has no real
---level: WoW Forever uses that for quests anyone can do. It is never trivial or too high.
function Availability.Levelless(q)
  local level = q and q.level
  return level ~= nil and level > 0 and level - (q.minLevel or 1) >= Availability.LEVELLESS_GAP
end
CV.Availability = Availability

local REPEATABLE, EVENT = 1, 2   -- specialFlags bits

-- race and class masks: 0 means everyone (NorgannonDB.HasFlag)
local function hasFlag(mask, flag) return DB.HasFlag(mask, flag) end
-- quest flags: a plain bit test (0 means no flags at all, unlike race masks)
local function flagSet(mask, flag)
  mask = mask or 0
  return mask % (2 * flag) >= flag
end

local function spellKnown(spell)
  if IsSpellKnown then
    local ok, known = pcall(IsSpellKnown, spell)
    if ok then return known and true or false end
  end
  if IsPlayerSpell then
    local ok, known = pcall(IsPlayerSpell, spell)
    if ok then return known and true or false end
  end
  return nil   -- can't tell
end

local function playerMasks()
  local _, _, raceId = UnitRace("player")
  local enums = DB.enums or {}
  return enums.raceMaskById and enums.raceMaskById[raceId], enums.classKeys and enums.classKeys[Core.Player.class or ""]
end

---Can the player take this quest now? Returns true, or false and a reason. q is the decoded
---NorgannonDB record (tests pass their own).
function Availability.Check(id, q)
  local P = Core.Player
  if not q then return false, "unknown" end
  if q.hidden == true or Core.DB:IsQuestHidden(id) then return false, "hidden" end
  if P:HasQuest(id) then return false, "in log" end
  if P:IsCompleted(id) and not flagSet(q.specialFlags, REPEATABLE) then return false, "done" end
  local level = P.level or UnitLevel("player") or 1
  if (q.minLevel or 1) > level then return false, "level too low" end
  if q.maxLevel and q.maxLevel > 0 and level > q.maxLevel then return false, "level too high" end
  local raceMask, classMask = playerMasks()
  if raceMask and q.races and q.races ~= 0 and not hasFlag(q.races, raceMask) then return false, "race" end
  if classMask and q.classes and q.classes ~= 0 and not hasFlag(q.classes, classMask) then return false, "class" end
  if q.event or flagSet(q.specialFlags, EVENT) then return false, "seasonal" end

  local pre = q.prerequisites
  if pre then
    for _, p in ipairs(pre.all or {}) do
      if not P:IsCompleted(p) then return false, "needs " .. p end
    end
    if pre.any and #pre.any > 0 then
      local any = false
      for _, p in ipairs(pre.any) do if P:IsCompleted(p) then any = true break end end
      if not any then return false, "needs one of " .. table.concat(pre.any, "/") end
    end
  end
  for _, other in ipairs(q.exclusiveTo or {}) do
    if P:IsCompleted(other) or P:HasQuest(other) then return false, "exclusive with " .. other end
  end
  if q.breadcrumbFor and (P:IsCompleted(q.breadcrumbFor) or P:HasQuest(q.breadcrumbFor)) then
    return false, "breadcrumb followed"
  end
  local w = q.availableStartingWith
  if w and not (P:HasQuest(w) or P:IsCompleted(w)) then return false, "starts with " .. w end
  if q.availableUntilCompleted and P:IsCompleted(q.availableUntilCompleted) then return false, "ended by " .. q.availableUntilCompleted end
  if q.disabledByQuest and P:HasQuest(q.disabledByQuest) then return false, "blocked by " .. q.disabledByQuest end

  local skill = q.requiredSkill
  if skill and skill[1] then
    local rank = P:GetSkill(skill[1])
    if not rank or rank < (skill[2] or 1) then return false, "skill" end
  end
  local minRep = q.requiredMinRep
  if minRep and minRep[1] then
    local rep = P:GetReputation(minRep[1])
    if not rep or rep < (minRep[2] or 0) then return false, "reputation too low" end
  end
  local maxRep = q.requiredMaxRep
  if maxRep and maxRep[1] then
    local rep = P:GetReputation(maxRep[1])
    if rep and rep >= (maxRep[2] or 0) then return false, "reputation too high" end
  end
  local spell = q.requiredSpell
  if spell and spell ~= 0 then
    local known = spellKnown(math.abs(spell))
    if known ~= nil and ((spell > 0 and not known) or (spell < 0 and known)) then return false, "spell" end
  end
  return true
end

---Why a quest is (not) available: Availability:Why(questId) -> ok, reason.
function Availability:Why(id) return Availability.Check(id, DB:Get("quests", id)) end

-------------------------------------------------------------------------------------------
-- Per zone
-------------------------------------------------------------------------------------------

local function friendly(record)
  local reaction = record and record.reaction
  if not reaction then return true end
  local mine = Core.Player.faction == "Alliance" and "A" or Core.Player.faction == "Horde" and "H" or nil
  return not mine or string.find(reaction, mine, 1, true) ~= nil
end

---Quests available from givers in an area: { {id, quest, starters = { {kind, id} }, trivial, repeatable}, ... }.
function Availability:ForArea(area)
  if not area then return {} end
  local cached = self.byArea[area]
  if cached then return cached end
  local list = {}
  local level = Core.Player.level or 1
  for _, id in ipairs(Core.DB:Zone(area).quests) do
    local q = DB:Get("quests", id)
    if q and Availability.Check(id, q) then
      local starters = {}
      for _, npc in ipairs(q.starters and q.starters.npcs or {}) do
        if friendly(DB:Get("npcs", npc)) then starters[#starters + 1] = { kind = "npcs", id = npc } end
      end
      for _, obj in ipairs(q.starters and q.starters.objects or {}) do
        if friendly(DB:Get("objects", obj)) then starters[#starters + 1] = { kind = "objects", id = obj } end
      end
      if #starters > 0 then
        local levelless = Availability.Levelless(q)
        local qlevel = (q.level and q.level > 0 and not levelless) and q.level or level
        list[#list + 1] = {
          id = id, quest = q, starters = starters, level = qlevel,
          levelless = levelless,
          trivial = not levelless and Core.UI.Difficulty(qlevel, level) == Core.UI.C.trivial,
          farAbove = not levelless and qlevel >= level + Availability.FAR_ABOVE,
          repeatable = flagSet(q.specialFlags, REPEATABLE),
        }
      end
    end
  end
  self.byArea[area] = list
  return list
end

-- the areas worth knowing: where the player is and what the world map shows
local playerArea, mapArea

function Availability:Areas()
  local out = {}
  if playerArea then out[#out + 1] = playerArea end
  if mapArea and mapArea ~= playerArea then out[#out + 1] = mapArea end
  return out
end

function Availability:Invalidate()
  self.byArea = {}
  CV:Send("AVAILABLE_UPDATED")
end

local function locate()
  local _, _, _, area = Core.Player:GetPosition()
  if area and area ~= playerArea then
    playerArea = area
    CV:Send("AVAILABLE_UPDATED", area)
  end
end

CV:OnReady(function() locate() Availability:Invalidate() end)
for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "PLAYER_ENTERING_WORLD" }) do
  Core:On(event, "clairvoyance.availability", function() if CV.ready then locate() end end)
end
Core:Listen("NORGANNON_WORLDMAP_CHANGED", "clairvoyance.availability", function(_, uiMap, area)
  if not CV.ready then return end
  mapArea = uiMap and area or nil
  CV:Send("AVAILABLE_UPDATED", mapArea)
end)
-- anything that changes the rules' answers
for _, message in ipairs({ "NORGANNON_QUESTLOG_UPDATED", "NORGANNON_QUEST_TURNED_IN", "NORGANNON_LEVEL_CHANGED",
  "NORGANNON_SKILLS_CHANGED", "NORGANNON_REPUTATION_CHANGED" }) do
  Core:Listen(message, "clairvoyance.availability", function()
    if CV.ready then Core:NextFrame(function() Availability:Invalidate() end, "clairvoyance.availability") end
  end)
end
