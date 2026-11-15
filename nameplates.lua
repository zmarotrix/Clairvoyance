-- Quest marks on nameplates: a mob you still need for a quest in your log shows a sword (kill it)
-- or a bag (it drops something you need) right of its health bar, with how many are left. A mob
-- that's both shows both.
--
-- Drawn on Blizzard's own plates, our frame parented to theirs (Bulwark adds to the same plates:
-- its raid mark sits above the name or left of the bar, so these go right). The mob is known by
-- its GUID when its plate appears; in combat the GUID can be secret, so it's remembered per plate
-- and progress updates (which come in combat) redraw from what was remembered.
-- Setting: ClairvoyanceDB.plateMarks.

local Core = NorgannonCore
local CV = Clairvoyance
if CV.disabled then return end
local UI = Core.UI
local IsSecret = Core.IsSecret

local Plates = { marks = {}, npcOf = {} }   -- plate -> our frame; unit token -> npc id
CV.Plates = Plates

local SIZE = 16
local KINDS = {   -- the objective's type in the game's log -> the mark
  monster = { icon = "sword", color = { 1, .38, .3 } },
  item = { icon = "bag", color = { 1, .82, .2 } },
}
local ORDER = { "monster", "item" }

---What's left to do on a mob: { monster = n|true, item = n|true } (true when there's no count),
---or nil. Only unfinished objectives of quests in your log.
function Plates.Needs(npcId)
  local needs
  for _, hit in ipairs(CV.Tooltips.ObjectivesFor("npcs", npcId)) do
    local m = CV.Model:Get(hit[1])
    local o = m and m.objectives[hit[2]]
    local kind = o and not o.finished and (o.type == "monster" and "monster" or o.type == "item" and "item")
    if kind then
      needs = needs or {}
      local left = (o.current and o.required) and (o.required - o.current) or true
      local had = needs[kind]
      if had == nil then needs[kind] = left
      elseif type(had) == "number" and type(left) == "number" then needs[kind] = had + left
      else needs[kind] = true end
    end
  end
  return needs
end

local function plateOf(unit)
  local NP = rawget(_G, "C_NamePlate")
  if not (NP and NP.GetNamePlateForUnit) then return nil end
  local ok, p = pcall(NP.GetNamePlateForUnit, unit)
  if not ok or p == nil or IsSecret(p) then return nil end
  if p.IsForbidden and p:IsForbidden() then return nil end
  return p
end

local function markFor(plate)
  local f = Plates.marks[plate]
  if f then return f end
  f = CreateFrame("Frame", nil, plate)
  f:SetSize(SIZE * 2 + 24, SIZE)
  f:EnableMouse(false)
  f.slots = {}
  for i = 1, #ORDER do
    local s = {}
    s.icon = UI.Icon(f, "sword", SIZE)
    s.count = f:CreateFontString(nil, "OVERLAY")
    s.count:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    s.count:SetPoint("LEFT", s.icon, "RIGHT", -2, -4)
    f.slots[i] = s
  end
  Plates.marks[plate] = f
  return f
end

local function place(f, plate)
  local uf = plate.UnitFrame
  local bar = uf and (uf.HealthBarsContainer or uf.healthBar)
  f:ClearAllPoints()
  if bar then f:SetPoint("LEFT", bar, "RIGHT", 4, 0) else f:SetPoint("LEFT", plate, "RIGHT", 0, 0) end
  f:SetFrameLevel((plate:GetFrameLevel() or 1) + 12)
end

local function npcFromUnit(unit)
  local guid = Core.Plain(UnitGUID, unit)
  if not guid or IsSecret(guid) then return nil end
  local kind, id = CV.Tooltips.ParseGUID(guid)
  return kind == "npcs" and id or nil
end

---Draws (or clears) the marks on one unit's plate.
function Plates:Update(unit)
  if IsSecret(unit) or type(unit) ~= "string" then return end
  local plate = plateOf(unit)
  if not plate then return end
  local f = self.marks[plate]
  local npc = self.npcOf[unit]
  local needs = CV.db.plateMarks and npc and Plates.Needs(npc)
  if not needs then
    if f then f:Hide() end
    return
  end
  f = markFor(plate)
  place(f, plate)
  local prev
  for i, s in ipairs(f.slots) do s.icon:Hide() s.count:Hide() end
  local n = 0
  for _, kind in ipairs(ORDER) do
    local left = needs[kind]
    if left then
      n = n + 1
      local s, look = f.slots[n], KINDS[kind]
      s.icon:SetTexture(UI.TEX[look.icon])
      s.icon:SetVertexColor(look.color[1], look.color[2], look.color[3])
      s.icon:ClearAllPoints()
      if prev then s.icon:SetPoint("LEFT", prev, "RIGHT", 4, 0) else s.icon:SetPoint("LEFT", f, "LEFT", 0, 0) end
      s.icon:Show()
      if type(left) == "number" and left > 0 then
        s.count:SetText(tostring(left))
        s.count:Show()
        prev = s.count
      else
        prev = s.icon
      end
    end
  end
  f:Show()
end

function Plates:Added(unit)
  if IsSecret(unit) or type(unit) ~= "string" then return end
  self.npcOf[unit] = npcFromUnit(unit)
  self:Update(unit)
end

function Plates:Removed(unit)
  if IsSecret(unit) or type(unit) ~= "string" then return end
  self.npcOf[unit] = nil
  local plate = plateOf(unit)
  local f = plate and self.marks[plate]
  if f then f:Hide() end
end

---Redraws every plate on screen (progress changed, or the setting).
function Plates:Refresh()
  for unit in pairs(self.npcOf) do self:Update(unit) end
  if not CV.db.plateMarks then
    for _, f in pairs(self.marks) do f:Hide() end
  end
end

Core:On("NAME_PLATE_UNIT_ADDED", "clairvoyance.plates", function(_, unit) if CV.ready then Plates:Added(unit) end end)
Core:On("NAME_PLATE_UNIT_REMOVED", "clairvoyance.plates", function(_, unit) Plates:Removed(unit) end)
-- progress (the tooltips' index rebuilds itself on the next ask)
CV:Listen("MODEL_UPDATED", "plates", function() if CV.ready then Plates:Refresh() end end)
CV:OnReady(function()
  -- plates already on screen at login or /reload
  for i = 1, 40 do
    local unit = "nameplate" .. i
    if Core.Plain(UnitExists, unit) then Plates:Added(unit) end
  end
end)
