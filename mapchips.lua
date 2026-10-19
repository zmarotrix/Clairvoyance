-- Filter chips on the world map ("Objectives", "Turn-ins", ...): what Clairvoyance draws.
-- A small bar in the map's top-left corner, in the suite's style; the choices are saved.

local Core = NorgannonCore
local CV = Clairvoyance
if CV.disabled then return end
local UI = Core.UI

-- the categories built so far (tracking, gathering and rares join later)
local CHIPS = {
  { key = "objectives", label = "Objectives", color = UI.Accent("clairvoyance") },
  { key = "turnins", label = "Turn-ins", color = UI.C.gold },
  { key = "available", label = "Available", color = UI.C.fair },
}

local bar

local function build()
  local container = WorldMapFrame.ScrollContainer or WorldMapFrame
  bar = CreateFrame("Frame", "ClairvoyanceMapChips", WorldMapFrame)
  bar:SetPoint("TOPLEFT", container, "TOPLEFT", 8, -8)
  bar:SetHeight(28)
  bar:SetFrameStrata(WorldMapFrame:GetFrameStrata() or "HIGH")
  bar:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 2040)   -- above the map canvas and its pins
  local back = UI.Pill(bar, 28, "BACKGROUND", 0)
  back:SetColor({ .03, .025, .02, .78 })
  bar.mark = UI.Mark(bar, "clairvoyance", 20)
  bar.mark:SetPoint("LEFT", 5, 0)
  bar.chips = {}
  local previous = bar.mark
  local width = 32
  for _, def in ipairs(CHIPS) do
    local chip = UI.Chip(bar, def.label, def.color, function(on)
      CV.db.filters[def.key] = on
      CV:Send("FILTERS_CHANGED", def.key)
    end)
    chip:SetPoint("LEFT", previous, "RIGHT", previous == bar.mark and 6 or 4, 0)
    chip.key = def.key
    previous = chip
    width = width + chip:GetWidth() + 4
    bar.chips[#bar.chips + 1] = chip
  end
  bar:SetWidth(width + 8)
end

local function hiddenIds()
  local ids = {}
  for id in pairs(CV.char.hiddenOnMap) do ids[#ids + 1] = id end
  table.sort(ids, function(a, b) return (Core.DB:Name("quests", a) or "") < (Core.DB:Name("quests", b) or "") end)
  return ids
end

-- "Hidden · N": shown when quests are hidden; opens a menu to show them again
local function hiddenMenu(owner)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Hidden on the map")
    for _, id in ipairs(hiddenIds()) do
      root:CreateButton(Core.DB:Name("quests", id) or ("Quest " .. id), function() CV:SetHiddenOnMap({ id }, false) end)
    end
    root:CreateDivider()
    root:CreateButton("Show all", function() CV:SetHiddenOnMap(hiddenIds(), false) end)
  end)
end

local function layoutBar()
  local width = 32
  local previous = bar.mark
  for _, chip in ipairs(bar.chips) do
    if chip:IsShown() then
      chip:ClearAllPoints()
      chip:SetPoint("LEFT", previous, "RIGHT", previous == bar.mark and 6 or 4, 0)
      previous = chip
      width = width + chip:GetWidth() + 4
    end
  end
  bar:SetWidth(width + 8)
end

-- not a filter: a list of what shift-click hid (after hiddenMenu is defined)
local function addHiddenChip()
  local hidden = UI.Chip(bar, "Hidden · 0", UI.C.faint)
  hidden:SetScript("OnClick", function(self) self:SetOn(false, true) hiddenMenu(self) end)
  hidden:Hide()
  bar.hidden = hidden
  bar.chips[#bar.chips + 1] = hidden
end

local function sync()
  for _, chip in ipairs(bar.chips) do
    if chip.key then chip:SetOn(CV.db.filters[chip.key], true) end
  end
  local n = #hiddenIds()
  bar.hidden.label:SetText("Hidden · " .. n)
  bar.hidden:SetWidth(math.floor(bar.hidden.label:GetStringWidth() + 33))
  bar.hidden:SetShown(n > 0)
  layoutBar()
end

CV:OnReady(function()
  build()
  addHiddenChip()
  sync()
end)
CV:Listen("FILTERS_CHANGED", "mapchips", function() if bar then sync() end end)
CV:Listen("HIDDEN_CHANGED", "mapchips", function() if bar then sync() end end)
CV.MapChips = function() return bar end
