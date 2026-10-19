-- Clairvoyance: a modern quest helper for WoW Forever, built on NorgannonDB and NorgannonDB_Core.
-- Plan: docs/clairvoyance-v1.md in the suite workspace. Clairvoyance owns the quest rules and its
-- own UI; the Core owns the shared machinery (player state, map layer, compass, colours, comms).

local ADDON = ...
local Core = NorgannonCore
local DB = NorgannonDB

Clairvoyance = { addonName = ADDON or "Clairvoyance" }
local CV = Clairvoyance

if not (Core and Core:Require(1, 2)) or not (DB and DB:RequireSchema(1, 2)) then
  CV.disabled = true
  C_Timer.After(5, function()
    print("|cff4fe3cfClairvoyance|r needs NorgannonDB 1.2 and NorgannonDB Core 1.2 or newer; it is turned off.")
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
    filters = { objectives = true, turnins = true, available = true, tracking = true, gathering = false, rares = false },
  },
  char = {
    hidden = {},          -- questId -> true: hidden from the tracker
    tracker = { shown = true, sort = "near", collapsed = false, scale = 1, view = "detailed", collapsedZones = {} },
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

Core:RegisterAddon("clairvoyance", { version = C_AddOns and C_AddOns.GetAddOnMetadata(CV.addonName, "Version") or "0.1.0" })

-- the suite's action for entities: show them on the map, through Clairvoyance
Core:RegisterAction("clairvoyance.track", {
  addon = "clairvoyance", label = "Show on map (Clairvoyance)", kinds = { "npc", "object", "item" },
  run = function(kind, id) if CV.Track then CV:Track(kind, id) end end,
})

SLASH_CLAIRVOYANCE1, SLASH_CLAIRVOYANCE2, SLASH_CLAIRVOYANCE3 = "/clair", "/clairvoyance", "/cv"
SlashCmdList["CLAIRVOYANCE"] = function(msg)
  msg = strtrim(string.lower(msg or ""))
  if msg == "" or msg == "settings" then
    Core:OpenSettings()
  else
    CV:Print("/clair - settings")
  end
end
