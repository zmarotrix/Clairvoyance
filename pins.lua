-- Map pins from the quest model: unfinished objectives (tinted pins in the quest's colour, one
-- cluster and compass group per objective) and turn-ins (the game's "?": gold when the quest is
-- complete, grey while it isn't). Filters: ClairvoyanceDB.filters.objectives / .turnins.
-- Also answers "how far is this quest" for the tracker: Pins:Nearest(questId).

local Core = NorgannonCore
local CV = Clairvoyance
if CV.disabled then return end
local UI = Core.UI
local HBD = LibStub("HereBeDragons-NorgannonCore-2.0")

local Pins = { objectives = {}, turnins = {} }   -- questId -> { pin, ... }
CV.Pins = Pins

local OWNER_OBJECTIVES, OWNER_TURNINS = "clairvoyance.objectives", "clairvoyance.turnins"

local function spawnsOf(target)
  if target.kind == "spawns" then return target.spawns end
  local record = NorgannonDB:Get(target.kind, target.id)
  return record and record.spawns
end

-------------------------------------------------------------------------------------------
-- Tooltips: quest, objective with progress, party members, the target
-------------------------------------------------------------------------------------------

local function partyLines(tt, m, index)
  local a = UI.Accent("clairvoyance")
  for player, objectives in pairs(m.party or {}) do
    local o = objectives[index]
    if o then
      tt:AddLine(string.format("%s: %s/%s", player, o.fulfilled or 0, o.required or 1), a[1], a[2], a[3])
    end
  end
end

local function objectiveTooltip(questId, index)
  return function(pin, tt)
    local m = CV.Model:Get(questId)
    if not m then return end
    local c = Core.Colors:ForQuest(questId)
    tt:AddLine(m.title, c[1], c[2], c[3])
    local o = m.objectives[index]
    if o and o.text then tt:AddLine(o.text, 1, 1, 1) end
    partyLines(tt, m, index)
    if pin.title then tt:AddLine(pin.title, UI.C.muted[1], UI.C.muted[2], UI.C.muted[3]) end
  end
end

local function turninTooltip(questId)
  return function(pin, tt)
    local m = CV.Model:Get(questId)
    if not m then return end
    tt:AddLine(pin.title or "?", 1, 1, 1)
    local c = Core.Colors:ForQuest(questId)
    tt:AddLine(m.title, c[1], c[2], c[3])
    local f = m.complete == true and UI.C.gold or UI.C.muted
    tt:AddLine(m.complete == true and "Ready to turn in" or "Turn in here when it's done", f[1], f[2], f[3])
  end
end

-------------------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------------------

local function addTarget(list, target, spec)
  local spawns = spawnsOf(target)
  local name = CV.Model.TargetName(target)
  for area, points in pairs(spawns or {}) do
    for _, p in ipairs(points) do
      if p[1] and p[1] >= 0 then
        list[#list + 1] = {
          area = area, x = p[1], y = p[2], icon = spec.icon, quest = spec.quest, layer = spec.layer, size = spec.size,
          cluster = spec.cluster, compass = spec.compass, title = name, tooltip = spec.tooltip,
          objective = spec.objective,
        }
      end
    end
  end
end

local function buildQuest(questId)
  local m = CV.Model:Get(questId)
  local objectives, turnins = {}, {}
  if m then
    if m.complete ~= true then
      for _, o in ipairs(m.objectives) do
        if not o.finished then
          local key = "q" .. questId .. ":" .. o.index
          local spec = { icon = "pin", quest = questId, layer = 3, cluster = key, compass = key, objective = o.index,
            tooltip = objectiveTooltip(questId, o.index) }
          for _, target in ipairs(o.targets) do addTarget(objectives, target, spec) end
        end
      end
    end
    local complete = m.complete == true
    for _, target in ipairs(m.turnins) do
      addTarget(turnins, target, { icon = complete and "question" or "questionGrey", quest = questId, layer = 5, size = 16,
        compass = complete and ("t" .. questId) or nil, tooltip = turninTooltip(questId) })
    end
  end
  Pins.objectives[questId] = #objectives > 0 and objectives or nil
  Pins.turnins[questId] = #turnins > 0 and turnins or nil
end

local function publish()
  local filters = CV.db.filters
  local function flatten(byQuest)
    local all = {}
    for _, list in pairs(byQuest) do
      for _, pin in ipairs(list) do all[#all + 1] = pin end
    end
    return all
  end
  Core.Map:SetPins(OWNER_OBJECTIVES, filters.objectives and flatten(Pins.objectives) or nil)
  Core.Map:SetPins(OWNER_TURNINS, filters.turnins and flatten(Pins.turnins) or nil)
  CV:Send("PINS_UPDATED")
end

function Pins:Rebuild(questId)
  if questId then
    buildQuest(questId)
  else
    self.objectives, self.turnins = {}, {}
    for _, m in ipairs(CV.Model:List()) do buildQuest(m.id) end
  end
  publish()
end

CV:Listen("MODEL_UPDATED", "pins", function(_, questId) Pins:Rebuild(questId) end)
CV:Listen("FILTERS_CHANGED", "pins", function() publish() end)

-------------------------------------------------------------------------------------------
-- Distance: the nearest unfinished objective (or the turn-in once the quest is complete)
-------------------------------------------------------------------------------------------

---{ pin, distance (yards), angle (world, radians) } of the quest's nearest target, or nil (other
---continent, instance, or nothing known). objectiveIndex limits it to one objective.
function Pins:Nearest(questId, objectiveIndex)
  local px, py, instance = HBD:GetPlayerWorldPosition()
  if not px or Core.IsSecret(px) then return nil end
  local m = CV.Model:Get(questId)
  local list = m and m.complete == true and self.turnins[questId] or self.objectives[questId]
  local best, bestD2
  for _, pin in ipairs(list or {}) do
    if not objectiveIndex or pin.objective == objectiveIndex then
      local wx, wy, inst = Core.Map.WorldOf(pin)
      if wx and inst == instance then
        local dx, dy = wx - px, wy - py
        local d2 = dx * dx + dy * dy
        if not bestD2 or d2 < bestD2 then best, bestD2 = pin, d2 end
      end
    end
  end
  if not best then return nil end
  local wx, wy = Core.Map.WorldOf(best)
  local angle, distance = HBD:GetWorldVector(instance, px, py, wx, wy)
  return { pin = best, distance = distance, angle = angle }
end
