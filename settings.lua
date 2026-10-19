-- Clairvoyance's settings page, under NorgannonDB in the game's Settings window. Opened by the
-- gear in the tracker's header and by /clair.

local Core = NorgannonCore
local CV = Clairvoyance
if CV.disabled then return end
local UI = Core.UI

local function tracker() return CV.char.tracker end

CV:OnReady(function()
  local page = CreateFrame("Frame")
  page:Hide()
  local list = UI.SettingsList(page)

  list:Header("Quest tracker")
  list:Toggle("Show the quest tracker", "Blizzard's tracker is hidden while Clairvoyance's is on.",
    function() return tracker().shown end, function(on) CV.Tracker:SetShown(on) end)
  list:Dropdown("Quests show as", "The default for every quest. Click a quest in the tracker to switch just that one.",
    { { "detailed", "Detailed" }, { "compact", "Compact" } },
    function() return tracker().view end,
    function(v)
      tracker().view = v
      wipe(tracker().questView)
      if CV.Tracker.frame then CV.Tracker.frame.view:Select(v, true) end
      CV.Tracker:Layout()
    end)
  list:Slider("Card background", "How dark the quest cards are behind the text.", 0, 1, .05,
    function() return tracker().cardAlpha end,
    function(v) tracker().cardAlpha = v CV.Tracker:Layout() end, "%.0f%%", 100)
  list:Slider("Tracker size", nil, .7, 1.4, .05,
    function() return tracker().scale end,
    function(v)
      tracker().scale = v
      if CV.Tracker.frame then CV.Tracker.frame:SetScale(v) end
    end, "%.0f%%", 100)

  list:Header("Tooltips")
  list:Toggle("Quest info in tooltips", "On NPCs, objects and items: which of your quests they're for, your progress and your party's.",
    function() return CV.db.tooltips end, function(on) CV.db.tooltips = on end)

  list:Header("Map")
  list:Toggle("Objectives", "Where to find what your quests ask for.",
    function() return CV.db.filters.objectives end,
    function(on) CV.db.filters.objectives = on CV:Send("FILTERS_CHANGED", "objectives") end)
  list:Toggle("Turn-ins", "Where to hand quests in.",
    function() return CV.db.filters.turnins end,
    function(on) CV.db.filters.turnins = on CV:Send("FILTERS_CHANGED", "turnins") end)
  list:Toggle("Available quests", "Quest givers with quests you can take now.",
    function() return CV.db.filters.available end,
    function(on) CV.db.filters.available = on CV:Send("FILTERS_CHANGED", "available") end)
  list:Toggle("Low-level quests", "Also show quests far below your level (grey \"!\").",
    function() return CV.db.showTrivial end,
    function(on) CV.db.showTrivial = on CV:Send("FILTERS_CHANGED", "available") end)
  list:Toggle("Quests far above your level", "Also show quests 10 or more levels above you.",
    function() return CV.db.showFarAbove end,
    function(on) CV.db.showFarAbove = on CV:Send("FILTERS_CHANGED", "available") end)

  page:SetScript("OnShow", function() list:Refresh() end)
  CV.settingsPage, CV.settingsList = page, list
  CV.settingsCategory = Core:AddSettingsPage(page, "Clairvoyance")
end)

function CV:OpenSettings()
  if self.settingsCategory and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(self.settingsCategory:GetID())
  else
    Core:OpenSettings()
  end
end
