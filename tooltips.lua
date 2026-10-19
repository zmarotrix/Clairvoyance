-- Quest info in tooltips: hovering an NPC, a world object or an item shows which of your quests
-- it belongs to (kill target, drop source, quest item, turn-in), your progress and your party
-- members' progress (Questie users included), and quests only your party has.
--
-- Hooked through the client's TooltipDataProcessor. NPCs and objects are identified by their
-- GUID; an object without a usable GUID falls back to its name. Secret values (combat,
-- instances) are skipped, never compared. Setting: ClairvoyanceDB.tooltips.

local Core = NorgannonCore
local DB = NorgannonDB
local CV = Clairvoyance
if CV.disabled then return end
local UI = Core.UI
local C = UI.C

local Tips = {}
CV.Tooltips = Tips

-------------------------------------------------------------------------------------------
-- Index: which objectives and turn-ins each entity takes part in (from the quest model)
-------------------------------------------------------------------------------------------

local objectivesOf, turninsOf, dirty = {}, {}, true

local function add(map, kind, id, value)
  map[kind] = map[kind] or {}
  map[kind][id] = map[kind][id] or {}
  table.insert(map[kind][id], value)
end

local function rebuild()
  objectivesOf, turninsOf = {}, {}
  for _, m in ipairs(CV.Model:List()) do
    for _, o in ipairs(m.objectives) do
      if o.kind == "items" and o.entity then add(objectivesOf, "items", o.entity, { m.id, o.index }) end
      for _, t in ipairs(o.targets) do
        if t.kind == "npcs" or t.kind == "objects" then add(objectivesOf, t.kind, t.id, { m.id, o.index }) end
      end
    end
    for _, t in ipairs(m.turnins) do add(turninsOf, t.kind, t.id, m.id) end
  end
  dirty = false
end

CV:Listen("MODEL_UPDATED", "tooltips", function() dirty = true end)

-------------------------------------------------------------------------------------------
-- Lines
-------------------------------------------------------------------------------------------

local function progressText(o)
  if o.text then return o.text end
  if o.current and o.required then return string.format("%s: %d/%d", o.name or "?", o.current, o.required) end
  return o.name or "?"
end

---Adds the quest lines for one entity to a tooltip; returns how many it added.
function Tips:AddLines(tt, kind, id, seen)
  if not CV.db.tooltips then return 0 end
  if dirty then rebuild() end
  seen = seen or {}
  local added = 0
  local accent = UI.Accent("clairvoyance")
  local function line(text, c) tt:AddLine(text, c[1], c[2], c[3]) added = added + 1 end

  -- your quests: header in the quest's colour, the objective, then each party member's progress
  local headed = {}
  for _, hit in ipairs((objectivesOf[kind] or {})[id] or {}) do
    local questId, index = hit[1], hit[2]
    local m = CV.Model:Get(questId)
    local o = m and m.objectives[index]
    if o and not seen[questId .. ":" .. index] then
      seen[questId .. ":" .. index] = true
      if not headed[questId] then
        headed[questId] = true
        line(m.title, Core.Colors:ForQuest(questId))
      end
      line("   " .. progressText(o), o.finished and C.faint or C.text)
      for player, objectives in pairs(m.party or {}) do
        local p = objectives[index]
        if p then line(string.format("   %s: %d/%d", player, p.fulfilled or 0, p.required or 1), accent) end
      end
    end
  end

  -- turn-ins
  for _, questId in ipairs((turninsOf[kind] or {})[id] or {}) do
    local m = CV.Model:Get(questId)
    if m and not seen["t" .. questId] then
      seen["t" .. questId] = true
      if m.complete == true then line("Turn in: " .. m.title, C.gold) else line("Turn in later: " .. m.title, C.muted) end
    end
  end

  -- quests only your party has
  for _, hit in ipairs(Core.Comms:ProgressFor(kind, id)) do
    if not CV.Model:Get(hit.questId) and not seen["p" .. hit.questId .. hit.player .. hit.index] then
      seen["p" .. hit.questId .. hit.player .. hit.index] = true
      local o = hit.objective
      line(string.format("Party: %s · %s %d/%d", hit.player, Core.DB:Name("quests", hit.questId) or ("Quest " .. hit.questId),
        o.fulfilled or 0, o.required or 1), accent)
    end
  end

  -- an item that starts a quest you can still take
  if kind == "items" then
    local item = DB:Get("items", id)
    local start = item and item.startQuest
    if start and not seen["s" .. start] and CV.Availability.Check(start, DB:Get("quests", start)) then
      seen["s" .. start] = true
      line("Starts a quest: " .. (Core.DB:Name("quests", start) or ("Quest " .. start)), C.gold)
    end
  end
  return added
end

-------------------------------------------------------------------------------------------
-- Hooks
-------------------------------------------------------------------------------------------

-- "Creature-0-<server>-<instance>-<zone>-<npcId>-<spawn>", "GameObject-...-<objectId>-..."
function Tips.ParseGUID(guid)
  if type(guid) ~= "string" or Core.IsSecret(guid) then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  id = tonumber(id)
  if not id then return nil end
  if kind == "Creature" or kind == "Vehicle" then return "npcs", id end
  if kind == "GameObject" then return "objects", id end
end

local function public(t) return type(t) == "table" and not Core.IsSecret(t) end

local function onUnit(tt, data)
  if not CV.ready or not public(data) then return end
  local kind, id = Tips.ParseGUID(data.guid)
  if kind == "npcs" and Tips:AddLines(tt, kind, id) > 0 then tt:Show() end
end

local function onItem(tt, data)
  if not CV.ready or not public(data) then return end
  local id = data.id
  if type(id) == "number" and not Core.IsSecret(id) and Tips:AddLines(tt, "items", id) > 0 then tt:Show() end
end

local function onObject(tt, data)
  if not CV.ready or not public(data) then return end
  local kind, id = Tips.ParseGUID(data.guid)
  local added = 0
  if kind == "objects" then
    added = Tips:AddLines(tt, kind, id)
  else
    -- no usable GUID: match the object's name (every object of that name)
    local line = public(data.lines) and data.lines[1]
    local name = public(line) and line.leftText
    local seen = {}
    for _, objectId in ipairs(Core.DB:IdsByName("objects", name)) do
      added = added + Tips:AddLines(tt, "objects", objectId, seen)
    end
  end
  if added > 0 then tt:Show() end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  local T = Enum.TooltipDataType
  if T.Unit then TooltipDataProcessor.AddTooltipPostCall(T.Unit, onUnit) end
  if T.Item then TooltipDataProcessor.AddTooltipPostCall(T.Item, onItem) end
  if T.Object then TooltipDataProcessor.AddTooltipPostCall(T.Object, onObject) end
end
