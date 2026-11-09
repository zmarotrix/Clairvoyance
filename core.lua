-- Clairvoyance: a modern quest helper for WoW Forever, built on NorgannonDB and NorgannonDB_Core.
-- Plan: docs/clairvoyance-v1.md in the suite workspace. Clairvoyance owns the quest rules and its
-- own UI; the Core owns the shared machinery (player state, map layer, compass, colours, comms).

local ADDON = ...
local Core = NorgannonCore
local DB = NorgannonDB

if not (Core and Core.NewAddon) then
  Clairvoyance = { disabled = true }
  print("Clairvoyance needs NorgannonDB Core 1.20 or newer; it is turned off.")
  return
end

Clairvoyance = {}
local CV = Clairvoyance

-- The suite's plumbing (Core:NewAddon): version checks, the slash command, the minimap row and the add-on menu.
-- Clairvoyance loads its own saved variables (ownLoad: character or global settings, below) and is ready once the
-- player is in the world. A click shows or hides the tracker, Shift-click opens Track anything, right-click settings;
-- /clair alone opens settings, as it always has. Messages inside it are CLAIRVOYANCE_* (CV:Send, CV:Listen).
Core:NewAddon("clairvoyance", {
  folder = ADDON, api = { 1, 20 }, data = { 1, 2 }, ownLoad = true,
  slash = { "/clair", "/clairvoyance", "/cv" },
  commands = {
    [""] = function() CV:OpenSettings() end,
    welcome = { function() CV.Welcome:Show() end, "run this character's first-time setup again" },
    why = { function(rest)
      -- /clair why <questId>: is it available, and if not, which rule blocks it
      local id = tonumber(rest:match("^(%d+)"))
      if not id then return CV:Print("/clair why <questId>") end
      local ok, reason = CV.Availability:Why(id)
      local name = Core.DB:Name("quests", id) or "unknown quest"
      CV:Print(string.format("%s (%d): %s", name, id, ok and "available" or ("not available: " .. tostring(reason))))
      -- how the game rates it next to Classic's level rule (the quest log colours by the game's)
      local q = DB:Get("quests", id)
      local byLevel
      if q and q.level and q.level > 0 then
        local c = Core.UI.Difficulty(q.level, UnitLevel("player") or 1)
        for _, key in ipairs({ "trivial", "easy", "fair", "hard", "impossible" }) do
          if Core.UI.C[key] == c then byLevel = key end
        end
      end
      CV:Print(string.format("  difficulty: game says %s, level rule says %s", CV.Availability.GameDifficulty(id) or "nothing",
        byLevel or "nothing"))
    end, "<questId>: is a quest available, and if not, why" },
    maptaint = { function()
      local bad, pins, names = CV.MapTaint()
      if not bad then return CV:Print("Can't check the map on this client.") end
      if bad == 0 then return CV:Print(string.format("The map is clean (%d pins checked).", pins)) end
      CV:Print(string.format("%d of the map's %d pins were touched by add-on code (%s). Toggling the map in combat "
        .. "may fail until you /reload.", bad, pins, table.concat(names, ", ")))
    end, "check whether add-on code has tainted the world map's pins (open the map first)" },
    perf = { function(rest) CV.Perf.Command(rest) end, "[seconds | stop | report]: measure Clairvoyance while you play" },
  },
  minimap = {
    clickHint = "show or hide the tracker",
    onShiftClick = function() CV.Extras:ToggleFinder(Core.MinimapButton.buttons.clairvoyance or UIParent) end,
    shiftHint = "track anything",
  },
})
if CV.disabled then return end

---The main action (left-click): show or hide the quest tracker.
-- Opening Blizzard's map from add-on code (OpenWorldMap, SetMapID, QuestMapFrame_OpenToQuestDetails)
-- makes the map build its own quest pins in tainted code. In combat the game blocks them
-- ("Clairvoyance tried to call the protected function Button:SetPassThroughButtons()"), and pins
-- made that way stay tainted, so toggling the map can keep failing in combat until /reload.
-- C_Map.OpenWorldMap is the client's own way to open the map; in combat it waits until combat ends.
-- Every "Show on map" in Clairvoyance goes through here.
function CV:OpenMap(uiMap, after)
  local function open()
    local cmap = rawget(_G, "C_Map")
    if cmap and cmap.OpenWorldMap then
      cmap.OpenWorldMap(uiMap)
    elseif OpenWorldMap then
      OpenWorldMap(uiMap)
    else
      return
    end
    if after then after() end
  end
  if InCombatLockdown() then
    CV:Print("The map opens when combat ends.")
    Core:AfterCombat(open, "clairvoyance.openmap")
    return false
  end
  open()
  return true
end

---How many of the map's own pins hold values written by add-on code (`/clair maptaint`): 0 means the
---map is clean. With some, toggling the map in combat can fail until /reload.
function CV.MapTaint()
  local frame = rawget(_G, "WorldMapFrame")
  if not (frame and frame.EnumerateAllPins and issecurevariable) then return nil end
  local pins, bad, by = 0, 0, {}
  for pin in frame:EnumerateAllPins() do
    pins = pins + 1
    for k in pairs(pin) do
      if type(k) == "string" then
        local secure, taint = issecurevariable(pin, k)
        if not secure then bad = bad + 1 by[taint or "?"] = true break end
      end
    end
  end
  local names = {}
  for name in pairs(by) do names[#names + 1] = name end
  table.sort(names)
  return bad, pins, names
end

function CV:Toggle()
  CV.Tracker:SetShown(not CV.char.tracker.shown)
end

-------------------------------------------------------------------------------------------
-- Saved settings. Settings (filters, automation, tooltips, the quest log, how the tracker looks)
-- are either this character's own or one global set shared by every character that chooses it
-- (ClairvoyanceCharDB.useGlobal). Character data always stays with the character: tracked
-- things, hidden quests, the tracker's position, length and collapsed quests.
--
--   ClairvoyanceDB      = { global = settings | nil, globalFrom = "Name", legacy = 0.1 account settings }
--   ClairvoyanceCharDB  = { settings, useGlobal, welcomed, hidden, hiddenOnMap, notOffered, tracked, tracker = layout }
--
-- CV.db is the settings in use; CV.char the character's data. CV.char.tracker reads and writes
-- the look-of-the-tracker keys (TRACKER_SETTINGS) in CV.db.tracker, the rest in the character's.
-------------------------------------------------------------------------------------------

local DEFAULTS = {
  settings = {
    filters = { objectives = true, turnins = true, available = true, tracking = true, herbs = false, mines = false, fish = false,
      rares = false },
    showTrivial = false,
    showFarAbove = false,
    questMarksOnMinimap = false,   -- the game draws its own "?" and "!" there
    tooltips = true,
    rewardMark = true,    -- a gold coin on the quest reward that sells for the most
    bagMarks = true,      -- a small mark on bag slots holding an item that's part of a quest
    rareAlert = true,    -- a quiet chat line when a rare shows up on your nameplates
    itemSources = 10,    -- a tracked item shows sources within this many times the best one's tries (0 = all)
    auto = { accept = false, turnin = false, gossip = false },   -- off unless you turn it on
    questLog = { levels = true, ids = false, buttons = true },
    tracker = { shown = true, sort = "zone", scale = 1, view = "detailed", cardAlpha = .62, bars = true,
      completeGreen = true, arrows = true, refresh = .5, finished = "inline", edges = true },
    -- preset: the welcome preset these settings started from
  },
  char = {
    hidden = {},          -- questId -> true: hidden from the tracker
    hiddenOnMap = {},     -- questId -> true: markers hidden on the map (shift-click)
    notOffered = {},      -- questId -> quest-giver id: the game didn't offer it there (offers.lua)
    tracked = {},         -- track anything: { key, kind, ids | category, name }, in the order added
    tracker = { collapsed = false, collapsedZones = {}, questView = {} },   -- position, height when set
    -- useGlobal: this character uses the global settings; welcomed: the welcome was answered
    -- (true) or dismissed twice ("skipped"); welcomeLater: times it was closed without an answer
  },
}

local TRACKER_SETTINGS = {}
for k in pairs(DEFAULTS.settings.tracker) do TRACKER_SETTINGS[k] = true end
CV.TRACKER_SETTINGS = TRACKER_SETTINGS
CV.DEFAULT_SORT = DEFAULTS.settings.tracker.sort

local function fill(target, defaults)
  for k, v in pairs(defaults) do
    if target[k] == nil then
      if type(v) == "table" then target[k] = {} fill(target[k], v) else target[k] = v end
    elseif type(v) == "table" and type(target[k]) == "table" then
      fill(target[k], v)
    end
  end
  return target
end

local function copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copy(v) end
  return out
end
CV.Copy = copy

local LEGACY_KEYS = { "filters", "showTrivial", "showFarAbove", "tooltips", "rareAlert", "auto", "questLog", "preset", "welcomed" }

-- 0.1 builds kept settings account-wide and the tracker's look per character: move them into this
-- character's own settings (each character takes the old account settings once)
local function migrate(account, char)
  if not account.legacy then
    local legacy
    for _, k in ipairs(LEGACY_KEYS) do
      if account[k] ~= nil then
        legacy = legacy or {}
        legacy[k], account[k] = account[k], nil
      end
    end
    account.legacy = legacy or false
  end
  if char.settings then return end
  local settings = {}
  if account.legacy then
    for k, v in pairs(account.legacy) do if k ~= "welcomed" then settings[k] = copy(v) end end
    if char.welcomed == nil and account.legacy.welcomed then char.welcomed = true end
  end
  settings.tracker = settings.tracker or {}
  for k in pairs(TRACKER_SETTINGS) do
    if char.tracker and char.tracker[k] ~= nil then settings.tracker[k], char.tracker[k] = char.tracker[k], nil end
  end
  char.settings = settings
end

-- CV.char.tracker: the tracker's look from the settings in use, its layout from the character
CV.Migrate = function(a, c) return migrate(a, c) end

local function trackerView(char)
  return setmetatable({}, {
    __index = function(_, k)
      if TRACKER_SETTINGS[k] then return CV.db.tracker[k] end
      return char.tracker[k]
    end,
    __newindex = function(_, k, v)
      if TRACKER_SETTINGS[k] then CV.db.tracker[k] = v else char.tracker[k] = v end
    end,
  })
end

local function bind(account, char)
  CV.account, CV.charData = account, char
  if char.useGlobal and account.global then
    CV.db = fill(account.global, DEFAULTS.settings)
  else
    char.useGlobal = nil
    CV.db = fill(char.settings, DEFAULTS.settings)
  end
  CV.char = setmetatable({ tracker = trackerView(char) }, { __index = char, __newindex = char })
  if CV.db.auto then CV.db.auto.reward = nil end   -- the reward-picking switch is gone (0.13.0)
end

---Whether global settings exist, and the character that set them up.
function CV:GlobalSettings()
  local g = self.account and self.account.global
  return g ~= nil, self.account and self.account.globalFrom
end

function CV:UsesGlobal() return self.charData.useGlobal == true end

---Switches this character between its own settings and the global ones. Switching to global
---uses the global settings if they exist, else starts them from this character's; switching
---back uses this character's own (a copy of the global ones if it never had any).
function CV:UseGlobal(on)
  local account, char = self.account, self.charData
  if on then
    if not account.global then
      account.global = copy(char.settings)
      account.globalFrom = UnitName("player")
    end
    char.useGlobal = true
  else
    if not char.settings or next(char.settings) == nil then char.settings = copy(account.global or {}) end
    char.useGlobal = nil
  end
  bind(account, char)
  self:SettingsChanged()
end

---Everything re-reads the settings in use (after a switch or a preset).
function CV:SettingsChanged()
  if not self.ready then return end
  self:Send("SETTINGS_CHANGED")
  for key in pairs(self.db.filters) do self:Send("FILTERS_CHANGED", key) end
  if self.settingsList then self.settingsList:Refresh() end
end

-------------------------------------------------------------------------------------------
-- Messages inside Clairvoyance ride on the Core's message bus, prefixed CLAIRVOYANCE_
-------------------------------------------------------------------------------------------


-------------------------------------------------------------------------------------------
-- Load
-------------------------------------------------------------------------------------------

local readyQueue = {}

---fn() once saved variables are loaded and the player is in the world (immediately after that).
function CV:OnReady(fn)
  if self.ready then Core.SafeCall(fn) else table.insert(readyQueue, fn) end
end

Core:On("ADDON_LOADED", CV, function(_, name)
  if name ~= CV.addonName then return end
  Core:Off("ADDON_LOADED", CV)
  -- rawget: on the first run the saved variables don't exist yet
  local account, char = rawget(_G, "ClairvoyanceDB"), rawget(_G, "ClairvoyanceCharDB")
  ClairvoyanceDB = type(account) == "table" and account or {}
  ClairvoyanceCharDB = fill(type(char) == "table" and char or {}, DEFAULTS.char)
  migrate(ClairvoyanceDB, ClairvoyanceCharDB)
  bind(ClairvoyanceDB, ClairvoyanceCharDB)
end)

local function becomeReady()
  if CV.ready or not CV.db then return end
  CV.ready = true
  for _, fn in ipairs(readyQueue) do Core.SafeCall(fn) end
  readyQueue = nil
end
Core:Listen("NORGANNON_PLAYER_READY", "clairvoyance", becomeReady)
-- loaded after the Core already knew the player (load on demand): start right away
Core:On("PLAYER_ENTERING_WORLD", CV, function()
  Core:Off("PLAYER_ENTERING_WORLD", CV)
  if Core.Player.ready then becomeReady() end
end)

-------------------------------------------------------------------------------------------
-- Another quest helper running too (Questie, pfQuest): two sets of map markers and trackers
-- confuse everyone, so ask once per character whether to turn the other one off
-------------------------------------------------------------------------------------------

local OTHER_HELPERS = { "Questie", "pfQuest" }

StaticPopupDialogs["CLAIRVOYANCE_OTHER_HELPER"] = {
  text = "%s is also running, so you'll see two sets of quest markers on the map.\n\nTurn %s off for this character? (The interface reloads.)",
  button1 = "Turn it off", button2 = "Keep both",
  OnAccept = function(self, addon)
    C_AddOns.DisableAddOn(addon, UnitName("player"))
    ReloadUI()
  end,
  timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}

function CV:CheckOtherHelpers()
  if not (C_AddOns and C_AddOns.IsAddOnLoaded) then return end
  CV.char.askedAbout = CV.char.askedAbout or {}
  for _, addon in ipairs(OTHER_HELPERS) do
    if C_AddOns.IsAddOnLoaded(addon) and not CV.char.askedAbout[addon] then
      CV.char.askedAbout[addon] = true
      local dialog = StaticPopup_Show("CLAIRVOYANCE_OTHER_HELPER", addon, addon)
      if dialog then dialog.data = addon end
      return addon
    end
  end
end
CV:OnReady(function() CV:CheckOtherHelpers() end)


-- the suite's action for entities: show them on the map, through Clairvoyance
Core:RegisterAction("clairvoyance.track", {
  addon = "clairvoyance", label = "Show on map (Clairvoyance)", kinds = { "npc", "object", "item" },
  run = function(kind, id) if CV.Track then CV:Track(kind, id) end end,
})
