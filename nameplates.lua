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

local SIZE = 24        -- the badge
local ICON = 18        -- the icon inside it
local GAP = 3
local KINDS = {   -- the objective's type in the game's log -> the icon (drawn in colour)
  monster = "sword",
  item = "bag",
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

-- a badge: a dark disc with a thin gold ring, the icon inside, the count in bold on its corner
local function badge(f)
  local g = CreateFrame("Frame", nil, f)
  g:SetSize(SIZE, SIZE)
  g.disc = UI.Icon(g, "circle", SIZE, { .05, .04, .03, .88 }, "BACKGROUND")
  g.disc:SetPoint("CENTER")
  g.ring = UI.Icon(g, "ring", SIZE + 2, { .91, .73, .32, 1 }, "BORDER")
  g.ring:SetPoint("CENTER")
  g.icon = g:CreateTexture(nil, "ARTWORK")
  g.icon:SetSize(ICON, ICON)
  g.icon:SetPoint("CENTER")
  g.count = UI.Text(g, "bold", 13, nil, "OVERLAY")
  local font = g.count:GetFont()
  if font then g.count:SetFont(font, 13, "THICKOUTLINE") end
  g.count:SetTextColor(1, 1, 1)
  g.count:SetPoint("BOTTOMLEFT", g, "BOTTOMRIGHT", -7, -3)
  return g
end

local function markFor(plate)
  local f = Plates.marks[plate]
  if f then return f end
  f = CreateFrame("Frame", nil, plate)
  f:SetSize(SIZE, SIZE)
  f:EnableMouse(false)
  f.slots = {}
  for i = 1, #ORDER do f.slots[i] = badge(f) end
  Plates.marks[plate] = f
  return f
end

local function place(f, plate)
  local uf = plate.UnitFrame
  local bar = uf and (uf.HealthBarsContainer or uf.healthBar)
  f:ClearAllPoints()
  if bar then f:SetPoint("LEFT", bar, "RIGHT", 8, 0) else f:SetPoint("LEFT", plate, "RIGHT", 0, 0) end
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
  for _, g in ipairs(f.slots) do g:Hide() end
  local n, prev = 0, nil
  for _, kind in ipairs(ORDER) do
    local left = needs[kind]
    if left then
      n = n + 1
      local g = f.slots[n]
      g.icon:SetTexture(UI.TEX[KINDS[kind]])
      local counted = type(left) == "number" and left > 0
      g.count:SetText(counted and tostring(left) or "")
      g:ClearAllPoints()
      if prev then
        -- after the previous badge's count, when it has one
        local width = prev.count:GetText() ~= "" and math.max(0, prev.count:GetStringWidth() - 7) or 0
        g:SetPoint("LEFT", prev, "RIGHT", GAP + width, 0)
      else
        g:SetPoint("LEFT", f, "LEFT", 0, 0)
      end
      g:Show()
      prev = g
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
