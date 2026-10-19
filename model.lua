-- The quest model: every quest in the log, joined with NorgannonDB. For each objective it keeps the
-- game's live progress and where the objective happens (targets): NPCs, objects, item sources
-- ranked by drop chance, explore and area-trigger spots, "use item on" targets. It also keeps the
-- turn-in NPCs, the quest's usable item and party progress (Core.Comms).
--
-- Rebuilt per quest when Core.Player reports a change; announces CLAIRVOYANCE_MODEL_UPDATED
-- (questId, or nil for "everything"). Missing data is "unknown", never an error.

local Core = NorgannonCore
local DB = NorgannonDB
local CV = Clairvoyance
if CV.disabled then return end

local Model = { quests = {} }
CV.Model = Model

local MAX_ITEM_SOURCES = 4   -- an item objective shows its most likely sources

-------------------------------------------------------------------------------------------
-- Targets: where an objective happens
-------------------------------------------------------------------------------------------

-- target = { kind = "npcs" | "objects", id } or { kind = "spawns", spawns = SpawnList, name }

local function itemSources(itemId)
  local item = DB:Get("items", itemId)
  local out = {}
  if not item then return out end
  local sources = {}
  for npc, chance in pairs(item.drops and item.drops.npcs or {}) do sources[#sources + 1] = { "npcs", npc, chance } end
  for obj, chance in pairs(item.drops and item.drops.objects or {}) do sources[#sources + 1] = { "objects", obj, chance } end
  for npc in pairs(item.vendors or {}) do sources[#sources + 1] = { "npcs", npc, 100 } end
  -- unknown chances (0) sort after known ones; ties by id for a stable order
  table.sort(sources, function(a, b)
    if (a[3] or 0) ~= (b[3] or 0) then return (a[3] or 0) > (b[3] or 0) end
    return a[2] < b[2]
  end)
  for i = 1, math.min(MAX_ITEM_SOURCES, #sources) do
    out[#out + 1] = { kind = sources[i][1], id = sources[i][2], chance = sources[i][3] }
  end
  return out
end

local function useItemTargets(objectives, itemId)
  local out = {}
  local use = objectives.useItemOn and objectives.useItemOn[itemId]
  for npc in pairs(use and use.npcs or {}) do out[#out + 1] = { kind = "npcs", id = npc } end
  for obj in pairs(use and use.objects or {}) do out[#out + 1] = { kind = "objects", id = obj } end
  return out
end

-- explore, area triggers and special objectives: places rather than things
local function placeTargets(objectives)
  local out = {}
  if objectives.explore and objectives.explore.spawns then
    out[#out + 1] = { kind = "spawns", spawns = objectives.explore.spawns, name = objectives.explore.text }
  end
  for _, trigger in ipairs(objectives.areaTriggers or {}) do
    local t = DB.areaTriggers and DB.areaTriggers[trigger]
    if t and t.spawns then out[#out + 1] = { kind = "spawns", spawns = t.spawns } end
  end
  for _, extra in ipairs(objectives.extra or {}) do
    if extra.spawns then out[#out + 1] = { kind = "spawns", spawns = extra.spawns, name = extra.text } end
    for _, ref in ipairs(extra.references or {}) do
      local kind = ref[1] == "object" and "objects" or (ref[1] == "npc" or ref[1] == "monster") and "npcs" or nil
      if kind then out[#out + 1] = { kind = kind, id = ref[2] } end
    end
  end
  return out
end

-- The database objective behind the game's objective i (objectives.order follows the client).
local function databaseObjective(objectives, i)
  local order = objectives.order
  if order and order[i] then
    local kind, n = order[i][1], order[i][2]
    return kind, objectives[kind] and objectives[kind][n]
  end
  local flat = {}
  for _, kind in ipairs({ "npcs", "objects", "items", "killCredit" }) do
    for _, entry in ipairs(objectives[kind] or {}) do flat[#flat + 1] = { kind, entry } end
  end
  if flat[i] then return flat[i][1], flat[i][2] end
end

local function targetsFor(quest, i, live)
  local objectives = quest and quest.objectives or {}
  local kind, entry = databaseObjective(objectives, i)
  local targets = {}
  if kind == "npcs" or kind == "objects" then
    targets[1] = { kind = kind, id = entry.id }
  elseif kind == "killCredit" then
    for _, npc in ipairs(entry.npcs or {}) do targets[#targets + 1] = { kind = "npcs", id = npc } end
  elseif kind == "items" then
    targets = useItemTargets(objectives, entry.id)
    if #targets == 0 then targets = itemSources(entry.id) end
  end
  -- event and log objectives ("Explore ...", "Use ... on ..."): the quest's places and use targets
  if #targets == 0 and live and (live.type == "event" or live.type == "log" or not kind) then
    targets = placeTargets(objectives)
    for itemId in pairs(objectives.useItemOn or {}) do
      for _, t in ipairs(useItemTargets(objectives, itemId)) do targets[#targets + 1] = t end
    end
  end
  return targets, kind, entry and (entry.id or entry.credit)
end

-------------------------------------------------------------------------------------------
-- The quest's usable item (the tracker's item button)
-------------------------------------------------------------------------------------------

local function specialItem(entry, quest)
  if GetQuestLogSpecialItemInfo and entry.logIndex then
    local ok, link = pcall(GetQuestLogSpecialItemInfo, entry.logIndex)
    if ok and type(link) == "string" and not Core.IsSecret(link) then
      local id = tonumber(link:match("item:(%d+)"))
      if id then return id end
    end
  end
  local source = quest and quest.sourceItem
  if source and GetItemSpell then
    local ok, spell = pcall(GetItemSpell, source)
    if ok and spell then return source end
  end
end

-------------------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------------------

local function build(questId)
  local entry = Core.Player:GetQuest(questId)
  if not entry then return nil end
  local quest = DB:Get("quests", questId)
  local m = {
    id = questId, title = entry.title or (quest and quest.name) or ("Quest " .. questId),
    level = entry.level or (quest and quest.level), complete = entry.complete, logIndex = entry.logIndex,
    zone = quest and quest.zoneOrSort and quest.zoneOrSort > 0 and quest.zoneOrSort or nil,
    known = quest ~= nil, objectives = {}, turnins = {}, item = specialItem(entry, quest),
    party = Core.Comms and Core.Comms:GetParty(questId) or {},
  }
  for i, live in ipairs(entry.objectives) do
    local targets, kind, entity = targetsFor(quest, i, live)
    m.objectives[i] = {
      index = i, text = live.text, name = live.name, type = live.type, current = live.current,
      required = live.required, finished = live.finished, kind = kind, entity = entity, targets = targets,
    }
  end
  local finishers = quest and quest.finishers or {}
  for _, npc in ipairs(finishers.npcs or {}) do m.turnins[#m.turnins + 1] = { kind = "npcs", id = npc } end
  for _, obj in ipairs(finishers.objects or {}) do m.turnins[#m.turnins + 1] = { kind = "objects", id = obj } end
  return m
end
Model.Build = build

function Model:Rebuild(questId)
  if questId then
    self.quests[questId] = build(questId)
  else
    self.quests = {}
    for _, id in ipairs(Core.Player:QuestIds()) do self.quests[id] = build(id) end
  end
  CV:Send("MODEL_UPDATED", questId)
end

---Quest model entries in quest log order.
function Model:List()
  local list = {}
  for _, id in ipairs(Core.Player:QuestIds()) do
    if self.quests[id] then list[#list + 1] = self.quests[id] end
  end
  return list
end

function Model:Get(questId) return self.quests[questId] end

---Name of a target ("Mottled Boar"), localized.
function Model.TargetName(target)
  if target.kind == "npcs" or target.kind == "objects" then return Core.DB:Name(target.kind, target.id) end
  return target.name
end

-------------------------------------------------------------------------------------------
-- Keeping it current
-------------------------------------------------------------------------------------------

CV:OnReady(function() Model:Rebuild() end)

Core:Listen("NORGANNON_QUESTLOG_UPDATED", "clairvoyance.model", function(_, changes)
  if not CV.ready then return end
  local touched = {}
  for _, list in pairs(changes) do
    for _, id in ipairs(list) do touched[id] = true end
  end
  for id in pairs(touched) do
    if Core.Player:HasQuest(id) then Model:Rebuild(id) else
      Model.quests[id] = nil
      CV:Send("MODEL_UPDATED", id)
    end
  end
end)

Core:Listen("NORGANNON_PARTY_UPDATED", "clairvoyance.model", function(_, questId)
  local m = Model.quests[questId]
  if m then
    m.party = Core.Comms:GetParty(questId)
    CV:Send("MODEL_UPDATED", questId)
  end
end)

Core:Listen("NORGANNON_PARTY_CLEARED", "clairvoyance.model", function()
  for _, m in pairs(Model.quests) do m.party = {} end
  CV:Send("MODEL_UPDATED", nil)
end)
