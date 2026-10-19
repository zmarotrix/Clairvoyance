-- Clairvoyance: a modern quest helper for WoW Forever, built on NorgannonDB and NorgannonDB_Core.
-- Plan: docs/clairvoyance-v1.md in the suite workspace. Clairvoyance owns the quest rules and its
-- own UI; the Core owns the shared machinery (player state, map layer, compass, colours, comms).

local ADDON = ...
local Core = NorgannonCore
local DB = NorgannonDB

Clairvoyance = { addonName = ADDON or "Clairvoyance" }
local CV = Clairvoyance

if not (Core and Core:Require(1, 11)) or not (DB and DB:RequireSchema(1, 2)) then
  CV.disabled = true
  C_Timer.After(5, function()
    print("|cff4fe3cfClairvoyance|r needs NorgannonDB 1.2 and NorgannonDB Core 1.11 or newer; it is turned off.")
  end)
  return
end

CV.PREFIX = "|cff4fe3cfClairvoyance|r"
function CV:Print(msg) Core:Print(msg, self.PREFIX) end

-------------------------------------------------------------------------------------------
-- Saved settings. Settings (filters, automation, tooltips, the quest log, how the tracker looks)
-- are either this character's own or one global set shared by every character that chooses it
-- (ClairvoyanceCharDB.useGlobal). Character data always stays with the character: tracked
-- things, hidden quests, the tracker's position, length and collapsed quests.
--
--   ClairvoyanceDB      = { global = settings | nil, globalFrom = "Name", legacy = 0.1 account settings }
--   ClairvoyanceCharDB  = { settings, useGlobal, welcomed, hidden, hiddenOnMap, tracked, tracker = layout }
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
    tooltips = true,
    rareAlert = true,     -- a quiet chat line when a rare shows up on your nameplates
    auto = { accept = false, turnin = false, reward = false, gossip = false },   -- off unless you turn it on
    questLog = { levels = true, ids = false, buttons = true },
    tracker = { shown = true, sort = "near", scale = 1, view = "detailed", cardAlpha = .62, bars = true,
      completeGreen = true, arrows = true, refresh = .5, finished = "inline" },
    -- preset: the welcome preset these settings started from
  },
  char = {
    hidden = {},          -- questId -> true: hidden from the tracker
    hiddenOnMap = {},     -- questId -> true: markers hidden on the map (shift-click)
    tracked = {},         -- track anything: { key, kind, ids | category, name }, in the order added
    tracker = { collapsed = false, collapsedZones = {}, questView = {} },   -- position, height when set
    -- useGlobal: this character uses the global settings; welcomed: the welcome was answered
    -- (true) or dismissed twice ("skipped"); welcomeLater: times it was closed without an answer
  },
}

local TRACKER_SETTINGS = {}
for k in pairs(DEFAULTS.settings.tracker) do TRACKER_SETTINGS[k] = true end
CV.TRACKER_SETTINGS = TRACKER_SETTINGS

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

function CV:Send(message, ...) Core:Send("CLAIRVOYANCE_" .. message, ...) end
function CV:Listen(message, owner, fn) Core:Listen("CLAIRVOYANCE_" .. message, owner, fn) end

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

Core:RegisterAddon("clairvoyance", { version = C_AddOns and C_AddOns.GetAddOnMetadata(CV.addonName, "Version") or "0.1.0" })

-- the suite's action for entities: show them on the map, through Clairvoyance
Core:RegisterAction("clairvoyance.track", {
  addon = "clairvoyance", label = "Show on map (Clairvoyance)", kinds = { "npc", "object", "item" },
  run = function(kind, id) if CV.Track then CV:Track(kind, id) end end,
})

SLASH_CLAIRVOYANCE1, SLASH_CLAIRVOYANCE2, SLASH_CLAIRVOYANCE3 = "/clair", "/clairvoyance", "/cv"
SlashCmdList["CLAIRVOYANCE"] = function(msg)
  msg = strtrim(string.lower(msg or ""))
  local why = tonumber(msg:match("^why%s+(%d+)"))
  if msg == "" or msg == "settings" then
    CV:OpenSettings()
  elseif msg == "welcome" then
    CV.Welcome:Show()
  elseif why then
    -- /clair why <questId>: is it available, and if not, which rule blocks it
    local ok, reason = CV.Availability:Why(why)
    local name = Core.DB:Name("quests", why) or "unknown quest"
    CV:Print(string.format("%s (%d): %s", name, why, ok and "available" or ("not available: " .. tostring(reason))))
  else
    CV:Print("/clair - settings")
    CV:Print("/clair welcome - run this character's first-time setup again")
    CV:Print("/clair why <questId> - is a quest available, and if not, why")
  end
end
