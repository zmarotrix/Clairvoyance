-- Clairvoyance: a modern quest helper for WoW Forever, built on NorgannonDB and NorgannonDB_Core.
-- Plan: docs/clairvoyance-v1.md in the suite workspace. Clairvoyance owns the quest rules and its
-- own UI; the Core owns the shared machinery (player state, map layer, compass, colours, comms).

local ADDON = ...
local Core = NorgannonCore
local DB = NorgannonDB

Clairvoyance = { addonName = ADDON or "Clairvoyance" }
local CV = Clairvoyance

if not (Core and Core:Require(1, 9)) or not (DB and DB:RequireSchema(1, 2)) then
  CV.disabled = true
  C_Timer.After(5, function()
    print("|cff4fe3cfClairvoyance|r needs NorgannonDB 1.2 and NorgannonDB Core 1.9 or newer; it is turned off.")
  end)
  return
end

CV.PREFIX = "|cff4fe3cfClairvoyance|r"
function CV:Print(msg) Core:Print(msg, self.PREFIX) end

-------------------------------------------------------------------------------------------
-- Saved settings: account-wide (ClairvoyanceDB) and per character (ClairvoyanceCharDB)
-------------------------------------------------------------------------------------------

local DEFAULTS = {
  account = {
    filters = { objectives = true, turnins = true, available = true, tracking = true, herbs = false, mines = false, fish = false,
      rares = false },
    showTrivial = false,
    showFarAbove = false,
    tooltips = true,
    rareAlert = true,     -- a quiet chat line when a rare shows up on your nameplates
  },
  char = {
    hidden = {},          -- questId -> true: hidden from the tracker
    hiddenOnMap = {},     -- questId -> true: markers hidden on the map (shift-click)
    tracked = {},         -- track anything: { key, kind, ids | category, name }, in the order added
    tracker = { shown = true, sort = "near", collapsed = false, scale = 1, view = "detailed", collapsedZones = {},
      questView = {}, cardAlpha = .62, bars = true, completeGreen = true,
      arrows = true, refresh = .5 },
  },
}

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
  ClairvoyanceDB = fill(type(account) == "table" and account or {}, DEFAULTS.account)
  ClairvoyanceCharDB = fill(type(char) == "table" and char or {}, DEFAULTS.char)
  CV.db, CV.char = ClairvoyanceDB, ClairvoyanceCharDB
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
  elseif why then
    -- /clair why <questId>: is it available, and if not, which rule blocks it
    local ok, reason = CV.Availability:Why(why)
    local name = Core.DB:Name("quests", why) or "unknown quest"
    CV:Print(string.format("%s (%d): %s", name, why, ok and "available" or ("not available: " .. tostring(reason))))
  else
    CV:Print("/clair - settings")
    CV:Print("/clair why <questId> - is a quest available, and if not, why")
  end
end
