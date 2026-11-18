-- What Clairvoyance draws on the world map: one small Clairvoyance button in the map's top-right
-- corner (the top-left has the game's own map pin button); click it for a dropdown of filter chips ("Objectives", "Turn-ins", "Herbs · 145", ...),
-- "Track…" and, when quests are hidden, "Hidden · N". The dropdown closes with the map or a
-- second click, so the map stays clear. The choices are saved.

local Core = NorgannonCore
local CV = Clairvoyance
if CV.disabled then return end
local UI = Core.UI
local C = UI.C

-- what Clairvoyance draws; a profession's chip shows only if you have it ("Herbs · 145")
local CHIPS = {
  { key = "objectives", label = "Objectives", color = UI.Accent("clairvoyance") },
  { key = "turnins", label = "Turn-ins", color = UI.C.gold },
  { key = "available", label = "Available", color = UI.C.fair },
  { key = "tracking", label = "Tracking", color = CV.Extras.VIOLET },
}
for _, prof in ipairs(CV.Extras.PROFESSIONS) do
  CHIPS[#CHIPS + 1] = { key = prof.key, label = prof.label, color = prof.color, profession = prof }
end
CHIPS[#CHIPS + 1] = { key = "rares", label = "Rares", color = UI.C.text }

local BUTTON = 30
local PAD, GAP, ROW = 8, 4, 20

local bar   -- the button; bar.panel is the dropdown, bar.chips its chips

local function build()
  local container = WorldMapFrame.ScrollContainer or WorldMapFrame
  bar = CreateFrame("Button", "ClairvoyanceMapChips", WorldMapFrame)
  bar:SetPoint("TOPRIGHT", container, "TOPRIGHT", -8, -8)
  bar:SetSize(BUTTON, BUTTON)
  bar:SetFrameStrata(WorldMapFrame:GetFrameStrata() or "HIGH")
  bar:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 2040)   -- above the map canvas and its pins
  bar.back = UI.Round(bar, "BACKGROUND", 0, BUTTON / 2)          -- a dark disc
  bar.back:SetColor({ .03, .025, .02 }, .82)
  bar.ring = UI.Round(bar, "BORDER", 0, BUTTON / 2, "line")       -- and its accent ring
  bar.mark = UI.Mark(bar, "clairvoyance", 22)
  bar.mark:SetPoint("CENTER", 0, 0)

  local panel = CreateFrame("Frame", nil, bar)
  panel:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -4)   -- opens leftwards, onto the map
  panel:EnableMouse(true)
  panel.bg = UI.Round(panel, "BACKGROUND", 0, 8)
  panel.bg:SetColor({ .04, .032, .022 }, .94)
  panel.outline = UI.Round(panel, "BACKGROUND", 2, 8, "line")
  panel.outline:SetColor(UI.Accent("clairvoyance"), .35)
  panel.title = UI.Text(panel, "body", 12, C.faint)
  panel.title:SetPoint("TOPLEFT", PAD + 2, -PAD)
  panel.title:SetText("On the map")
  panel:Hide()
  bar.panel = panel

  bar.chips = {}
  for _, def in ipairs(CHIPS) do
    local chip = UI.Chip(panel, def.label, def.color, function(on)
      CV.db.filters[def.key] = on
      CV:Send("FILTERS_CHANGED", def.key)
    end)
    chip.key = def.key
    chip.profession = def.profession
    bar.chips[#bar.chips + 1] = chip
  end

  local function paintButton(hover)
    bar.ring:SetColor(UI.Accent("clairvoyance"), (hover or panel:IsShown()) and .9 or .4)
  end
  bar.Paint = paintButton
  bar:SetScript("OnClick", function()
    panel:SetShown(not panel:IsShown())
    if panel:IsShown() and CV.Extras.finder then CV.Extras.finder:Hide() end
    paintButton(true)
  end)
  bar:SetScript("OnEnter", function(self)
    paintButton(true)
    if panel:IsShown() then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Clairvoyance", 1, 1, 1)
    GameTooltip:AddLine("What's shown on the map, and Track…", C.muted[1], C.muted[2], C.muted[3])
    GameTooltip:Show()
  end)
  bar:SetScript("OnLeave", function() paintButton(false) GameTooltip:Hide() end)
  bar:SetScript("OnHide", function() panel:Hide() end)   -- the map closed
  panel:SetScript("OnHide", function() paintButton(false) end)
  paintButton(false)
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

-- the chips in a column, all as wide as the widest
local function layout()
  local panel = bar.panel
  local width = math.floor(panel.title:GetStringWidth() + 4)
  for _, chip in ipairs(bar.chips) do
    if chip:IsShown() then width = math.max(width, math.floor(chip.label:GetStringWidth() + (chip.dot and 33 or 20))) end
  end
  local y = -PAD - 18
  for _, chip in ipairs(bar.chips) do
    if chip:IsShown() then
      chip:ClearAllPoints()
      chip:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
      chip:SetWidth(width)
      y = y - ROW - GAP
    end
  end
  panel:SetSize(width + PAD * 2, -y - GAP + PAD)
end

-- not a filter: opens the Finder under the button
local function addFindChip()
  local find = UI.Chip(bar.panel, "Track…", nil)
  find:SetScript("OnClick", function(self)
    self:SetOn(false, true)
    bar.panel:Hide()
    CV.Extras:ToggleFinder(bar, true, true)
  end)
  bar.find = find
  bar.chips[#bar.chips + 1] = find
end

-- not a filter: a list of what shift-click hid (after hiddenMenu is defined)
local function addHiddenChip()
  local hidden = UI.Chip(bar.panel, "Hidden · 0", UI.C.faint)
  hidden:SetScript("OnClick", function(self) self:SetOn(false, true) hiddenMenu(self) end)
  hidden:Hide()
  bar.hidden = hidden
  bar.chips[#bar.chips + 1] = hidden
end

local function sync()
  for _, chip in ipairs(bar.chips) do
    if chip.key then chip:SetOn(CV.db.filters[chip.key], true) end
    local prof = chip.profession
    if prof then
      local rank = CV.Extras.Rank(prof)
      chip.label:SetText(prof.noSkill and prof.label or (prof.label .. " · " .. (rank or 0)))
      chip:SetShown(rank ~= nil)
    end
  end
  local n = #hiddenIds()
  bar.hidden.label:SetText("Hidden · " .. n)
  bar.hidden:SetShown(n > 0)
  layout()
end

-------------------------------------------------------------------------------------------
-- "Pick up X from Y in Zone": after you click a quest to pick up in the tracker, opening your map
-- on any other zone shows where its giver is, since add-ons can't turn Blizzard's map there for
-- you (that taints its quest pins; Core.Map:Reveal). It goes once the map reaches that zone (the
-- giver's eye pulses there), when you close it with its x, take the quest or after HINT_FOR.
-------------------------------------------------------------------------------------------

local HINT_FOR = 300          -- seconds the hint lasts after the click
local REVEAL_WAIT = 110       -- after about this long Core's own Reveal has given up: pulse it here
local HINT_EVERY = .2

local hint, hintFrame

local function hintLive()
  if not hint then return false end
  if GetTime() - hint.at > HINT_FOR then hint = nil return false end
  -- still to pick up? (taken or handed in: the tracker row went, so does the hint)
  if not hint.key then return true end
  for _, p in ipairs(CV.Extras:TrackedPins(hint.key).pickups or {}) do
    if p.step == hint.step then return true end
  end
  hint = nil
  return false
end

local function updateHint()
  local f = hintFrame
  if not hintLive() then f.pill:Hide() return end
  if WorldMapFrame:GetMapID() == hint.uiMap then
    -- you're there: its eye pulses (Core's Reveal does, unless it has stopped waiting)
    if GetTime() - hint.at > REVEAL_WAIT then Core.Map:Pulse(hint.highlight) end
    hint = nil
    f.pill:Hide()
    return
  end
  if not f.pill:IsShown() or f.pill.for_ ~= hint then
    f.pill.for_ = hint
    f.pill.text:SetText(string.format("Pick up %s from %s in %s (%.1f, %.1f)", hint.name, hint.giver, hint.zone, hint.x, hint.y))
    f.pill:SetWidth(math.floor(f.pill.text:GetStringWidth() + 64))
    f.pill:Show()
  end
end

local function buildHint()
  local container = WorldMapFrame.ScrollContainer or WorldMapFrame
  -- always shown with the map, so it checks the map's zone while the map is open (and only then)
  hintFrame = CreateFrame("Frame", nil, WorldMapFrame)
  hintFrame:SetSize(1, 1)
  hintFrame:SetPoint("TOP", container, "TOP", 0, -10)
  local pill = CreateFrame("Button", "ClairvoyancePickupHint", hintFrame)
  pill:SetHeight(28)
  pill:SetPoint("TOP", hintFrame, "TOP", 0, 0)
  pill:SetFrameStrata(WorldMapFrame:GetFrameStrata() or "HIGH")
  pill:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 2040)
  pill.bg = UI.Round(pill, "BACKGROUND", 0, 14)
  pill.bg:SetColor({ .03, .025, .02 }, .9)
  pill.ring = UI.Round(pill, "BORDER", 0, 14, "line")
  pill.ring:SetColor(UI.Accent("clairvoyance"), .7)
  pill.eye = UI.Icon(pill, CV.Extras.PICKUP_ICON, 20)
  pill.eye:SetPoint("LEFT", 8, 0)
  pill.text = UI.Text(pill, "body", 13, C.text)
  pill.text:SetPoint("LEFT", pill.eye, "RIGHT", 6, 0)
  pill.close = CreateFrame("Button", nil, pill)
  pill.close:SetSize(18, 18)
  pill.close:SetPoint("RIGHT", -6, 0)
  pill.close.icon = UI.Icon(pill.close, "close", 9, C.muted)
  pill.close.icon:SetPoint("CENTER")
  pill.close:SetScript("OnClick", function() hint = nil pill:Hide() end)
  pill:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Pick up: " .. (hint and hint.name or ""), 1, 1, 1)
    GameTooltip:AddLine("Go to " .. (hint and hint.zone or "its zone") .. " on this map: the giver's eye pulses there.",
      C.muted[1], C.muted[2], C.muted[3], true)
    GameTooltip:Show()
  end)
  pill:SetScript("OnLeave", function() GameTooltip:Hide() end)
  pill:Hide()
  hintFrame.pill = pill
  local since = HINT_EVERY
  hintFrame:SetScript("OnUpdate", function(_, dt)
    since = since + dt
    if since < HINT_EVERY then return end
    since = 0
    updateHint()
  end)
end

---Remembers the quest to pick up you just clicked in the tracker, for the world map's hint:
---{ key, step, name, giver, uiMap, zone, x, y, highlight }. nil forgets it.
function CV:SetPickupHint(info)
  hint = info
  if hint then hint.at = GetTime() end
  if hintFrame then
    hintFrame.pill:Hide()
    if WorldMapFrame:IsShown() then updateHint() end
  end
end
function CV:PickupHint() return hintLive() and hint or nil, hintFrame end

CV:OnReady(function()
  build()
  addFindChip()
  addHiddenChip()
  sync()
  buildHint()
end)
CV:Listen("FILTERS_CHANGED", "mapchips", function() if bar then sync() end end)
CV:Listen("HIDDEN_CHANGED", "mapchips", function() if bar then sync() end end)
CV.MapChips = function() return bar end
