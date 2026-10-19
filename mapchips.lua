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

local function sync()
  for _, chip in ipairs(bar.chips) do chip:SetOn(CV.db.filters[chip.key], true) end
end

CV:OnReady(function()
  build()
  sync()
end)
CV:Listen("FILTERS_CHANGED", "mapchips", function() if bar then sync() end end)
CV.MapChips = function() return bar end
