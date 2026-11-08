-- Measuring Clairvoyance in game. Its hot paths are timed by the suite's profiler (/norg perf,
-- NorgannonDB_Core perf.lua), which wraps them only while a measurement runs. /clair perf starts
-- the same measurement and adds what only Clairvoyance knows: how much its memory grew while you
-- played (the garbage it made, until the collector runs) and how much it holds (quests, pins).
--
--   /clair perf [seconds]   measure (default 60 s): play normally, move, fight, open the map
--   /clair perf stop        end early
--   /clair perf report      the last report again

local Core = NorgannonCore
local CV = Clairvoyance
if CV.disabled then return end

local Perf = {}
CV.Perf = Perf

local OWNERS = { "clairvoyance.objectives", "clairvoyance.turnins", "clairvoyance.available", "clairvoyance.tracking",
  "clairvoyance.gathering", "clairvoyance.rares" }

CV:OnReady(function()
  local function perf(label, tbl, method) Core:RegisterPerf("Clairvoyance: " .. label, tbl, method, "clairvoyance") end
  perf("tracker tick", CV.Tracker, "Tick")
  perf("tracker refresh", CV.Tracker, "Refresh")
  perf("tracker layout", CV.Tracker, "Layout")
  perf("nearest target", CV.Pins, "FindNearest")
  perf("quest model", CV.Model, "Rebuild")
  perf("objective pins", CV.Pins, "Rebuild")
  perf("available quests", CV.Pins, "RebuildAvailable")
  perf("availability rules", CV.Availability, "ForArea")
  perf("gathering and rares", CV.Extras, "RebuildZones")
  perf("tracked things", CV.Extras, "RebuildTracking")
  perf("tracking distances", CV.Extras, "Refresh")
  perf("tooltips", CV.Tooltips, "AddLines")
  perf("bag marks", CV.BagMarks, "Refresh")
end)

---Clairvoyance's memory in KB, or nil when the client can't say.
function Perf.Memory()
  if UpdateAddOnMemoryUsage then pcall(UpdateAddOnMemoryUsage) end
  local get = GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
  if not get then return nil end
  local ok, kb = pcall(get, CV.addonName or "Clairvoyance")
  if ok and type(kb) == "number" then return kb end
end

---What Clairvoyance holds now: quests in the model, pins per kind, areas with availability worked out.
function Perf.Holdings()
  local quests, pins, parts = 0, 0, {}
  for _ in pairs(CV.Model.quests) do quests = quests + 1 end
  for _, owner in ipairs(OWNERS) do
    local n = #(Core.Map.owners[owner] or {})
    pins = pins + n
    if n > 0 then parts[#parts + 1] = owner:gsub("^clairvoyance%.", "") .. " " .. n end
  end
  local areas = 0
  for _ in pairs(CV.Availability.byArea) do areas = areas + 1 end
  return { quests = quests, pins = pins, byOwner = parts, areas = areas }
end

local started   -- { kb, time } while measuring

local function report()
  local h = Perf.Holdings()
  CV:Print(string.format("holds %d quests, %d pins (%s), availability for %d areas", h.quests, h.pins,
    #h.byOwner > 0 and table.concat(h.byOwner, ", ") or "none", h.areas))
  local kb = Perf.Memory()
  if started and kb and started.kb then
    local seconds = math.max(1, GetTime() - started.time)
    CV:Print(string.format("memory %.0f KB -> %.0f KB: %+.1f KB/s while measuring (garbage made, until the collector runs)",
      started.kb, kb, (kb - started.kb) / seconds))
  elseif kb then
    CV:Print(string.format("memory %.0f KB", kb))
  end
  Perf.last = { holdings = h, kb = kb, startKb = started and started.kb }
  started = nil
end

---/clair perf [seconds | stop | report]
function Perf.Command(rest)
  rest = rest or ""
  if rest == "stop" then
    if Core.Perf:Stop() then report() else CV:Print("not measuring") end
  elseif rest == "report" then
    Core.Perf:Print()
    report()
  else
    local seconds = tonumber(rest) or 60
    started = { kb = Perf.Memory(), time = GetTime() }
    Core.Perf:Start(seconds)
    local token = {}
    Perf.token = token
    C_Timer.After(seconds + .1, function()
      if Perf.token == token and started then report() end
    end)
  end
end
