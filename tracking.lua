-- Beyond quests: track anything, gathering nodes and rares.
--
--   Track anything: find an NPC, object or item by name (the Finder: the magnifier in the
--   tracker's header, "Track…" on the world map) or a service (flight masters, mailboxes, ...).
--   Every spawn of that name gets a violet diamond on the map, minimap and compass, and the
--   tracker lists it under "Tracking" with the distance to the nearest one. An item tracks the
--   places it comes from. Shift-click a diamond or click the x in the tracker to stop.
--
--   Gathering: with Herbalism, Mining or Fishing, a chip on the world map ("Herbs · 145") shows
--   the nodes you can gather now, and the next 25 skill points' nodes dimmed so you can see
--   where to go next. The tracker shows the nearest one; click it to point the arrow there.
--
--   Rares: rare NPCs on the map with their level and notable drops, and an optional quiet chat
--   line when one shows up on your nameplates in the open world.
--
-- Gathering and rare pins cover the zones that matter (where you are, what the map shows), so
-- the map never holds every node in the world at once.

local Core = NorgannonCore
local DB = NorgannonDB
local CV = Clairvoyance
if CV.disabled then return end
local UI = Core.UI
local C = UI.C
local HBD = LibStub("HereBeDragons-NorgannonCore-2.0")

local Extras = {}
CV.Extras = Extras

local OWNER_TRACKING, OWNER_GATHERING, OWNER_RARES = "clairvoyance.tracking", "clairvoyance.gathering", "clairvoyance.rares"
local VIOLET = UI.Hex("b48cff")
local NEXT_BAND = 25              -- skill points ahead whose nodes show dimmed
local ITEM_SOURCES = 8            -- an item tracks its most likely sources
local NOTABLE_DROP = 5            -- percent: a rare's drops worth naming
local NAMED_LOOT_SOURCES = 5      -- an item dropped by at most this many NPCs is named loot
local RARE_ALERT_AGAIN = 300      -- seconds before the same rare is announced again
local RARE_ICON = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local NODE_ICON = UI.TEX.circle

Extras.VIOLET = VIOLET

-- tracked entries share the quests' colour system (Core.Colors): a stable palette colour per
-- entry, click a pin for a new one, right-click to choose. Key: "track:<entry key>".
local function colorKey(key) return "track:" .. key end
function Extras.ColorOf(key) return Core.Colors:ForQuest(colorKey(key)) end
Extras.ColorKey = colorKey

-- the gathering professions (skill line ids) and their NorgannonDB categories
local PROFESSIONS = {
  { key = "herbs", skill = 182, label = "Herbs", name = "Herbalism", color = UI.Hex("6fd36a") },
  { key = "mines", skill = 186, label = "Ore", name = "Mining", color = UI.Hex("d8955a") },
  { key = "fish", skill = 356, label = "Fishing", name = "Fishing", color = UI.Hex("5fb6ff"), noSkill = true },
}
Extras.PROFESSIONS = PROFESSIONS

-- services the Finder lists before you type (NorgannonDB categories)
local SERVICES = {
  { "flight", "Flight masters" }, { "innkeeper", "Innkeepers" }, { "mailbox", "Mailboxes" },
  { "banker", "Bankers" }, { "auctioneer", "Auctioneers" }, { "repair", "Repair" },
  { "vendor", "Vendors" }, { "trainer", "Trainers" }, { "stablemaster", "Stable masters" },
  { "spirithealer", "Spirit healers" }, { "meetingstone", "Meeting stones" },
  { "battlemaster", "Battlemasters" }, { "chests", "Treasure chests" },
}
Extras.SERVICES = SERVICES

local PLURAL = { npc = "npcs", object = "objects", item = "items", npcs = "npcs", objects = "objects", items = "items" }
---The icon of a tracked entry or Finder result, on a texture: a service's own icon, else the diamond.
local function markIcon(tex, category, tracked, color)
  local name = category and Core.Map.ICONS["service." .. category] and ("service." .. category) or "diamond"
  local tint = Core.Map.SetIcon(tex, name)
  local c = color or VIOLET
  if tint then tex:SetVertexColor(c[1], c[2], c[3]) else tex:SetVertexColor(1, 1, 1) end
  tex:SetAlpha(tracked and 1 or (name == "diamond" and .25 or .7))
end
Extras.MarkIcon = markIcon

local KIND_LABEL = { npcs = "NPC", objects = "Object", items = "Item", category = "Service" }

-------------------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------------------

local function myFaction()
  local f = Core.Player.faction or UnitFactionGroup("player")
  return f == "Alliance" and "A" or f == "Horde" and "H" or nil
end

-- a category entry's reaction code ("A", "H", "AH") allows the player's faction
local function friendly(code)
  if type(code) ~= "string" then return true end
  local mine = myFaction()
  return not mine or code:find(mine, 1, true) ~= nil
end

local function spawnPins(list, kind, id, spec, onlyArea)
  local record = DB:Get(kind, id)
  local spawns = record and record.spawns
  if not spawns then return end
  local title = spec.title or Core.DB:Name(kind, id)
  for area, points in pairs(spawns) do
    if not onlyArea or area == onlyArea then
      for _, p in ipairs(points) do
        if p[1] and p[1] >= 0 then
          local pin = { area = area, x = p[1], y = p[2], title = title, kind = kind, id = id }
          for k, v in pairs(spec) do if pin[k] == nil then pin[k] = v end end
          list[#list + 1] = pin
        end
      end
    end
  end
end

---{ pin, distance, angle } of the nearest pin in a list (same continent), or nil.
local function nearestOf(pins, filter)
  local px, py, instance = HBD:GetPlayerWorldPosition()
  if not px or Core.IsSecret(px) then return nil end
  local best, bestD2
  for _, pin in ipairs(pins or {}) do
    if not filter or filter(pin) then
      local wx, wy, inst = Core.Map.WorldOf(pin)
      if wx and inst == instance then
        local dx, dy = wx - px, wy - py
        local d2 = dx * dx + dy * dy
        if not bestD2 or d2 < bestD2 then best, bestD2 = pin, d2 end
      end
    end
  end
  if not best then return nil end
  local wx, wy = Core.Map.WorldOf(best)
  local angle, distance = HBD:GetWorldVector(instance, px, py, wx, wy)
  return { pin = best, distance = distance, angle = angle }
end
Extras.NearestOf = nearestOf

local function pointArrow(near, title)
  if not near then return false end
  Core.Arrow:SetTarget({ area = near.pin.area, x = near.pin.x, y = near.pin.y, owner = "clairvoyance", title = title or near.pin.title })
  return true
end

-------------------------------------------------------------------------------------------
-- Track anything
-------------------------------------------------------------------------------------------

local trackedPins = {}     -- entry key -> { pin, ... }

local function entryKey(kind, name) return kind .. ":" .. string.lower(name or "") end

function CV:TrackedList() return self.char.tracked end

function CV:IsTracked(key)
  for _, e in ipairs(self.char.tracked) do if e.key == key then return true end end
  return false
end

---Tracks an entity on the map: CV:Track("npc" | "object" | "item", id) tracks every spawn of
---that name; CV:Track("category", "flight") a service. Tracking it again stops it.
function CV:Track(kind, id, name)
  local entry
  if kind == "category" then
    local label
    for _, s in ipairs(SERVICES) do if s[1] == id then label = s[2] end end
    if not (DB.categories and DB.categories[id]) then return false end
    entry = { key = "category:" .. id, kind = "category", category = id, name = label or id }
  else
    kind = PLURAL[kind]
    if not kind or not id then return false end
    local ids = type(id) == "table" and id or nil
    name = name or Core.DB:Name(kind, ids and ids[1] or id)
    if not name then return false end
    if not ids then
      ids = Core.DB:IdsByName(kind, name)
      if #ids == 0 then ids = { id } end
    end
    entry = { key = entryKey(kind, name), kind = kind, ids = ids, name = name }
  end
  if self:IsTracked(entry.key) then
    self:Untrack(entry.key)
    return false
  end
  table.insert(self.char.tracked, entry)
  if not self.db.filters.tracking then
    self.db.filters.tracking = true
    self:Send("FILTERS_CHANGED", "tracking")
  end
  Extras:RebuildTracking()
  return true
end

function CV:Untrack(key)
  for i, e in ipairs(self.char.tracked) do
    if e.key == key then table.remove(self.char.tracked, i) break end
  end
  Extras:RebuildTracking()
end

---Stops tracking everything.
function CV:ClearTracking()
  wipe(self.char.tracked)
  Extras:RebuildTracking()
end

---The right-click menu of a tracked entry (tracker row).
function Extras:TrackedMenu(owner, key)
  local entry
  for _, e in ipairs(CV.char.tracked) do if e.key == key then entry = e end end
  if not entry then return end
  local nearest = function() return nearestOf(Extras:TrackedPins(key)) end
  Core:ShowActionMenu(owner, nil, nil, { title = entry.name, items = {
    { text = "Point the arrow at the nearest", func = function()
      if not pointArrow(nearest()) then CV:Print("None of these on this continent.") end
    end },
    { text = "Show on map", func = function()
      local near = nearest()
      local uiMap = near and Core.Map.AreaToUiMap(near.pin.area)
      if not uiMap then CV:Print("None of these on this continent.") return end
      if OpenWorldMap then OpenWorldMap(uiMap) else WorldMapFrame:Show() WorldMapFrame:SetMapID(uiMap) end
      Core.Map:Pulse("track:" .. key)
    end },
    "-",
    { text = "New colour", func = function() Core.Colors:Randomize(colorKey(key)) end },
    { text = "Choose colour…", func = function() Core.Colors:Pick(colorKey(key)) end },
    "-",
    { text = "Stop tracking", func = function() CV:Untrack(key) end },
    { text = "Clear all tracking", func = function() CV:ClearTracking() end },
  } })
end

-- a random colour for a quest avoids the tracked entries' colours too, and the other way round
Core.Colors:RegisterInUse("clairvoyance.tracking", function()
  local keys = {}
  for _, e in ipairs(CV.char and CV.char.tracked or {}) do keys[#keys + 1] = colorKey(e.key) end
  return keys
end)
Core:Listen("NORGANNON_QUEST_COLOR_CHANGED", "clairvoyance.extras", function(_, key)
  if type(key) == "string" and key:find("^track:") then Extras:Refresh() if Extras.finder and Extras.finder:IsShown() then Extras:FillFinder() end end
end)

local function trackedTooltip(entry)
  return function(pin, tt)
    tt:AddLine(pin.title or entry.name, 1, 1, 1)
    if pin.via then tt:AddLine(pin.via, C.muted[1], C.muted[2], C.muted[3]) end
    local c = Extras.ColorOf(entry.key)
    tt:AddLine("Tracking: " .. entry.name, c[1], c[2], c[3])
  end
end

local function untrackPin(pin) CV:Untrack(pin.trackKey) end

local function buildEntry(entry)
  local list = {}
  local group = "track:" .. entry.key
  -- a service shows the game's own icon (flight master's boot, mailbox letter); the rest a violet diamond
  local service = entry.kind == "category" and Core.Map.ICONS["service." .. entry.category] and ("service." .. entry.category)
  local spec = { icon = service or "diamond", colorKey = colorKey(entry.key), layer = 4, size = service and 16 or 12, cluster = group, compass = group, highlight = group,
    trackKey = entry.key, tooltip = trackedTooltip(entry), onShiftClick = untrackPin, shiftHint = "Shift-click: stop tracking" }
  if entry.kind == "npcs" or entry.kind == "objects" then
    for _, id in ipairs(entry.ids) do spawnPins(list, entry.kind, id, spec) end
  elseif entry.kind == "items" then
    -- where the item comes from: its likeliest drops and every vendor
    local sources = {}
    for _, itemId in ipairs(entry.ids) do
      local item = DB:Get("items", itemId)
      for npc, chance in pairs(item and item.drops and item.drops.npcs or {}) do sources[#sources + 1] = { "npcs", npc, chance } end
      for obj, chance in pairs(item and item.drops and item.drops.objects or {}) do sources[#sources + 1] = { "objects", obj, chance } end
      for npc in pairs(item and item.vendors or {}) do sources[#sources + 1] = { "npcs", npc, 100, true } end
    end
    table.sort(sources, function(a, b)
      if a[3] ~= b[3] then return a[3] > b[3] end
      return a[2] < b[2]
    end)
    for i = 1, math.min(ITEM_SOURCES, #sources) do
      local s = sources[i]
      local via = s[4] and ("Sells " .. entry.name) or (s[3] > 0 and string.format("Drops %s (%s%%)", entry.name, s[3]) or ("Drops " .. entry.name))
      local copy = { via = via }
      for k, v in pairs(spec) do copy[k] = v end
      spawnPins(list, s[1], s[2], copy)
    end
  elseif entry.kind == "category" then
    local cat = DB.categories[entry.category] or {}
    for _, kind in ipairs({ "npcs", "objects" }) do
      for id, code in pairs(cat[kind] or {}) do
        if friendly(code) then spawnPins(list, kind, id, spec) end
      end
    end
  end
  return list
end

function Extras:RebuildTracking()
  trackedPins = {}
  local all = {}
  if CV.db.filters.tracking then
    for _, entry in ipairs(CV.char.tracked) do
      local list = buildEntry(entry)
      trackedPins[entry.key] = list
      for _, pin in ipairs(list) do all[#all + 1] = pin end
    end
  end
  Core.Map:SetPins(OWNER_TRACKING, #all > 0 and all or nil)
  CV:Send("EXTRAS_UPDATED", "tracking")
end

function Extras:TrackedPins(key) return trackedPins[key] or {} end

-------------------------------------------------------------------------------------------
-- Gathering
-------------------------------------------------------------------------------------------

local gatherPins = {}      -- profession key -> { pin, ... }

---The player's rank in a gathering profession (nil without it).
function Extras.Rank(prof) return Core.Player:GetSkill(prof.skill) end

---Whether this profession's chip shows (the player has it).
function Extras.HasProfession(prof) return Extras.Rank(prof) ~= nil end

-- the game's colours for a node: orange (sure skill-up), yellow, green, grey (none)
local function nodeColor(rank, required)
  if rank < required then return C.impossible end
  if rank < required + 25 then return C.hard end
  if rank < required + 50 then return C.fair end
  if rank < required + 100 then return C.easy end
  return C.trivial
end

local function nodeTooltip(prof)
  return function(pin, tt)
    local rank = Extras.Rank(prof) or 0
    if prof.noSkill or not pin.required then
      tt:AddLine(pin.title or "?", 1, 1, 1)
    else
      local c = nodeColor(rank, pin.required)
      tt:AddLine(pin.title or "?", c[1], c[2], c[3])
      if pin.required > rank then
        tt:AddLine(string.format("Needs %s %d (%d more)", prof.name, pin.required, pin.required - rank), C.muted[1], C.muted[2], C.muted[3])
      else
        tt:AddLine(string.format("%s %d", prof.name, pin.required), C.muted[1], C.muted[2], C.muted[3])
      end
    end
  end
end

local function buildGathering(prof, areas)
  local rank = Extras.Rank(prof)
  local list = {}
  if not rank or not CV.db.filters[prof.key] then return list end
  local nodes = DB.categories and DB.categories[prof.key] and DB.categories[prof.key].objects or {}
  local group = "gather:" .. prof.key
  for _, area in ipairs(areas) do
    for _, id in ipairs(Core.DB:Zone(area).objects) do
      local value = nodes[id]
      if value ~= nil then
        local required = (not prof.noSkill and type(value) == "number") and value or nil
        local now = not required or required <= rank
        if now or required <= rank + NEXT_BAND then
          spawnPins(list, "objects", id, {
            icon = NODE_ICON, color = prof.color, layer = 2, size = now and 9 or 7, alpha = now and 1 or .4,
            cluster = group .. (now and "" or ":next"), highlight = group, compass = now and group or nil,
            required = required, gather = prof.key, tooltip = nodeTooltip(prof), continent = false,
          }, area)
        end
      end
    end
  end
  return list
end

-------------------------------------------------------------------------------------------
-- Rares
-------------------------------------------------------------------------------------------

local function rareLabel(npc)
  local rank = npc and npc.rank
  return rank == 2 and "Rare elite" or "Rare"
end

local function rareLevel(npc)
  if not npc then return nil end
  local lo, hi = npc.minLevel, npc.maxLevel
  if lo and hi and hi ~= lo then return lo .. "-" .. hi end
  return lo or hi
end

-- an item few NPCs drop is the rare's own loot (Linen Cloth drops from hundreds)
local function fewSources(itemId)
  local item = DB:Get("items", itemId)
  local n = 0
  for _ in pairs(item and item.drops and item.drops.npcs or {}) do
    n = n + 1
    if n > NAMED_LOOT_SOURCES then return false end
  end
  return item ~= nil
end

---A rare's own loot: dropped by few NPCs, chance at least NOTABLE_DROP percent, best first (at most 3).
function Extras.NotableDrops(npcId)
  local npc = DB:Get("npcs", npcId)
  local out = {}
  for itemId, chance in pairs(npc and npc.drops or {}) do
    itemId = tonumber(itemId) or itemId
    if type(chance) == "number" and chance >= NOTABLE_DROP and fewSources(itemId) then out[#out + 1] = { id = itemId, chance = chance } end
  end
  table.sort(out, function(a, b)
    if a.chance ~= b.chance then return a.chance > b.chance end
    return tostring(a.id) < tostring(b.id)
  end)
  for i = 4, #out do out[i] = nil end
  return out
end

local function rareTooltip(pin, tt)
  local npc = DB:Get("npcs", pin.id)
  local level = npc and (npc.maxLevel or npc.minLevel) or 0
  local c = UI.Difficulty(level, Core.Player.level or UnitLevel("player") or 1)
  tt:AddLine(pin.title or "?", c[1], c[2], c[3])
  local lv = rareLevel(npc)
  tt:AddLine(rareLabel(npc) .. (lv and (" · level " .. lv) or ""), C.muted[1], C.muted[2], C.muted[3])
  for _, d in ipairs(Extras.NotableDrops(pin.id)) do
    tt:AddLine(string.format("   %s  %s%%", Core.DB:Name("items", d.id) or ("Item " .. d.id), d.chance), C.text[1], C.text[2], C.text[3])
  end
end

local function buildRares(areas)
  local list = {}
  if not CV.db.filters.rares then return list end
  local rares = DB.categories and DB.categories.rares and DB.categories.rares.npcs or {}
  for _, area in ipairs(areas) do
    for _, id in ipairs(Core.DB:Zone(area).npcs) do
      if rares[id] then
        spawnPins(list, "npcs", id, { icon = RARE_ICON, color = { 1, 1, 1 }, layer = 4, size = 14, cluster = "rare:" .. id,
          highlight = "rare:" .. id, tooltip = rareTooltip, rare = true, continent = false }, area)
      end
    end
  end
  return list
end

-- the quiet alert: a rare on your nameplates, open world only, once per RARE_ALERT_AGAIN
local announced = {}

function Extras:CheckRareUnit(unit)
  if not (CV.ready and CV.db.rareAlert) then return end
  if IsInInstance and IsInInstance() then return end
  local class = UnitClassification(unit)
  if Core.IsSecret(class) or (class ~= "rare" and class ~= "rareelite") then return end
  if UnitIsDead and UnitIsDead(unit) then return end
  local guid = UnitGUID(unit)
  local kind, id = CV.Tooltips.ParseGUID(guid)
  if kind ~= "npcs" then return end
  local now = GetTime()
  if announced[id] and now - announced[id] < RARE_ALERT_AGAIN then return end
  announced[id] = now
  local name = UnitName(unit)
  if Core.IsSecret(name) then name = nil end
  name = name or Core.DB:Name("npcs", id) or "A rare"
  local level = UnitLevel(unit)
  if Core.IsSecret(level) then level = nil end
  CV:Print(string.format("Rare nearby: |cffffffff%s|r%s", name, (level and level > 0) and (" (" .. level .. ")") or ""))
  if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.MAP_PING or 3175, "SFX") end
  CV:Send("RARE_SEEN", id, name)
  return id
end

Core:On("NAME_PLATE_UNIT_ADDED", "clairvoyance.rares", function(_, unit) Extras:CheckRareUnit(unit) end)

-------------------------------------------------------------------------------------------
-- Zone-scoped pins: rebuilt when the zones that matter or the player's skills change
-------------------------------------------------------------------------------------------

local lastAreas = ""

function Extras:RebuildZones(force)
  local areas = CV.Availability:Areas()
  local key = table.concat(areas, ",")
  if not force and key == lastAreas then return end
  lastAreas = key
  local gathering = {}
  gatherPins = {}
  for _, prof in ipairs(PROFESSIONS) do
    local list = buildGathering(prof, areas)
    gatherPins[prof.key] = list
    for _, pin in ipairs(list) do gathering[#gathering + 1] = pin end
  end
  Core.Map:SetPins(OWNER_GATHERING, #gathering > 0 and gathering or nil)
  local rares = buildRares(areas)
  Core.Map:SetPins(OWNER_RARES, #rares > 0 and rares or nil)
  CV:Send("EXTRAS_UPDATED", "zones")
end

function Extras:GatherPins(key) return gatherPins[key] or {} end

CV:OnReady(function()
  Extras:RebuildTracking()
  Extras:RebuildZones(true)
end)
CV:Listen("AVAILABLE_UPDATED", "extras", function() if CV.ready then Extras:RebuildZones() end end)
CV:Listen("FILTERS_CHANGED", "extras", function(_, key)
  if key == "tracking" then Extras:RebuildTracking() else Extras:RebuildZones(true) end
end)
Core:Listen("NORGANNON_SKILLS_CHANGED", "clairvoyance.extras", function()
  if not CV.ready then return end
  Extras:RebuildZones(true)
  CV:Send("FILTERS_CHANGED", "skills")   -- the chips' "Herbs · 145" labels
end)

-------------------------------------------------------------------------------------------
-- The Finder: search names or pick a service, click to track
-------------------------------------------------------------------------------------------

local finder
local MAX_RESULTS = 10
local ROW_H = 20
local FINDER_W = 300

local function resultRow(i)
  local row = finder.rows[i]
  if row then return row end
  row = CreateFrame("Button", nil, finder)
  row:SetHeight(ROW_H)
  row:SetPoint("TOPLEFT", finder.search, "BOTTOMLEFT", 0, -6 - (i - 1) * ROW_H)
  row:SetPoint("TOPRIGHT", finder.search, "BOTTOMRIGHT", 0, -6 - (i - 1) * ROW_H)
  row.hl = row:CreateTexture(nil, "BACKGROUND")
  row.hl:SetAllPoints()
  row.hl:SetColorTexture(1, 1, 1, .06)
  row.hl:Hide()
  row.mark = row:CreateTexture(nil, "ARTWORK")
  row.mark:SetSize(14, 14)
  row.mark:SetPoint("LEFT", 2, 0)
  row.name = UI.Text(row, "body", 13, C.text)
  row.name:SetPoint("LEFT", 18, 0)
  row.name:SetPoint("RIGHT", -64, 0)
  row.name:SetJustifyH("LEFT")
  row.kind = UI.Text(row, "body", 11, C.faint)
  row.kind:SetPoint("RIGHT", -4, 0)
  row.kind:SetJustifyH("RIGHT")
  row:SetScript("OnEnter", function(self) self.hl:Show() end)
  row:SetScript("OnLeave", function(self) self.hl:Hide() end)
  row:SetScript("OnClick", function(self)
    local r = self.result
    if r.category then CV:Track("category", r.category) else CV:Track(r.key, r.ids, r.name) end
    Extras:FillFinder()
  end)
  finder.rows[i] = row
  return row
end

-- has something to put on the map: spawns, or (items) a drop source or vendor
local function trackable(kind, id)
  local record = DB:Get(kind, id)
  if not record then return false end
  if kind ~= "items" then return record.spawns ~= nil and next(record.spawns) ~= nil end
  local drops = record.drops
  return (record.vendors and next(record.vendors) ~= nil) or (drops and ((drops.npcs and next(drops.npcs) ~= nil)
    or (drops.objects and next(drops.objects) ~= nil))) or false
end
Extras.Trackable = trackable

-- what a result is, in a player's words: "Herb", "Ore", "Rare", the NPC's title, "Item"
local CATEGORY_LABEL = { herbs = "Herb", mines = "Ore", fish = "Fishing pool", chests = "Chest", rares = "Rare" }
local function describe(kind, ids)
  local cats = DB.categories or {}
  for cat, label in pairs(CATEGORY_LABEL) do
    local list = cats[cat] and cats[cat][kind]
    if list then for _, id in ipairs(ids) do if list[id] ~= nil then return label end end end
  end
  if kind == "npcs" then
    local title = DB:L("npcs", ids[1], "subName")
    if title and title ~= "" then return title end
  end
  return KIND_LABEL[kind]
end
Extras.Describe = describe

---Results for the Finder: services when empty, else NPCs, objects and items by name.
function Extras.FinderResults(text)
  local out = {}
  text = strtrim(text or "")
  if text == "" then
    for _, s in ipairs(SERVICES) do
      if DB.categories and DB.categories[s[1]] then
        out[#out + 1] = { category = s[1], name = s[2], key = "category", trackKey = "category:" .. s[1] }
      end
    end
    return out
  end
  -- one row per name: a herb's node and its item are one thing to find. Records with nothing to
  -- show on the map (no spawns, no sources) are left out.
  local byName, order = {}, {}
  for _, r in ipairs(Core.DB:Search(text, { kinds = { npcs = true, objects = true, items = true }, limit = MAX_RESULTS * 4 })) do
    local lower = string.lower(r.name)
    local group = byName[lower]
    if not group then
      group = { name = r.name }
      byName[lower] = group
      order[#order + 1] = group
    end
    local ids = {}
    for _, id in ipairs(r.ids) do if trackable(r.key, id) then ids[#ids + 1] = id end end
    if #ids > 0 then group[r.key] = ids end
  end
  for _, group in ipairs(order) do
    -- what's on the map itself first (nodes, NPCs), else where the item comes from
    local key = group.objects and "objects" or group.npcs and "npcs" or group.items and "items"
    if key then
      out[#out + 1] = { key = key, name = group.name, ids = group[key], trackKey = entryKey(key, group.name),
        label = describe(key, group[key]) }
      if #out >= MAX_RESULTS then break end
    end
  end
  return out
end

function Extras:FillFinder()
  if not finder then return end
  local results = Extras.FinderResults(finder.search:GetText())
  local shown = #results   -- every service, or at most MAX_RESULTS names (the search's limit)
  for i = 1, shown do
    local row, r = resultRow(i), results[i]
    row.result = r
    row.name:SetText(r.name)
    local tracked = CV:IsTracked(r.trackKey)
    local tc = tracked and Extras.ColorOf(r.trackKey) or C.text
    row.name:SetTextColor(tc[1], tc[2], tc[3])
    markIcon(row.mark, r.category, tracked, tracked and Extras.ColorOf(r.trackKey) or nil)
    local label = r.label or KIND_LABEL[r.key] or ""
    row.kind:SetText(tracked and "tracking" or label)
    row:Show()
  end
  for i = shown + 1, #finder.rows do finder.rows[i]:Hide() end
  finder.empty:SetShown(shown == 0)
  finder.title:SetText(strtrim(finder.search:GetText() or "") == "" and "Track a service, or search by name" or "Click to track · again to stop")
  finder:SetHeight(28 + 6 + 28 + 6 + math.max(1, shown) * ROW_H + 8)
end

local function buildFinder()
  finder = CreateFrame("Frame", "ClairvoyanceFinder", UIParent)
  finder:SetWidth(FINDER_W)
  finder:SetFrameStrata("DIALOG")
  finder:SetClampedToScreen(true)
  finder:EnableMouse(true)
  finder.bg = UI.Round(finder, "BACKGROUND", 0, 8)
  finder.bg:SetColor({ .04, .032, .022 }, .96)
  finder.outline = UI.Round(finder, "BACKGROUND", 2, 8, "line")
  finder.outline:SetColor(VIOLET, .45)
  finder.mark = UI.Mark(finder, "clairvoyance", 18)
  finder.mark:SetPoint("TOPLEFT", 8, -6)
  finder.title = UI.Text(finder, "body", 12, C.muted)
  finder.title:SetPoint("LEFT", finder.mark, "RIGHT", 6, 0)
  finder.close = CreateFrame("Button", nil, finder)
  finder.close:SetSize(18, 18)
  finder.close:SetPoint("TOPRIGHT", -6, -6)
  finder.close.icon = UI.Icon(finder.close, "close", 10, C.muted)
  finder.close.icon:SetPoint("CENTER")
  finder.close:SetScript("OnClick", function() finder:Hide() end)
  finder.search = UI.Search(finder, "Herb, ore, NPC, item…", function() Extras:FillFinder() end, function()
    local first = finder.rows[1]
    if first and first:IsShown() then first:Click() end
  end)
  finder.search:ApplyAccent(VIOLET)
  finder.search:SetPoint("TOPLEFT", 8, -32)
  finder.search:SetPoint("TOPRIGHT", -8, -32)
  finder.empty = UI.Text(finder, "body", 12, C.faint)
  finder.empty:SetPoint("TOPLEFT", finder.search, "BOTTOMLEFT", 4, -8)
  finder.empty:SetText("Nothing by that name.")
  finder.rows = {}
  finder:SetScript("OnShow", function() Extras:FillFinder() end)
  finder:Hide()
  if UISpecialFrames then table.insert(UISpecialFrames, "ClairvoyanceFinder") end   -- Escape closes it
  Extras.finder = finder
end

---Opens the Finder next to a frame (the tracker's header, the map's button); again closes it.
---below: under the frame; alignRight: its right edge lines up with the frame's (opens leftwards).
function Extras:ToggleFinder(anchor, below, alignRight)
  if not finder then buildFinder() end
  if finder:IsShown() and finder.anchor == anchor then finder:Hide() return end
  finder.anchor = anchor
  finder:ClearAllPoints()
  if below and alignRight then
    finder:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
  elseif below then
    finder:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
  else
    finder:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -6, 0)
  end
  finder:Show()
  finder.search:SetText("")
  finder.search:SetFocus()
  Extras:FillFinder()
end

-------------------------------------------------------------------------------------------
-- The tracker's groups: "Tracking" and "Gathering", below the quests
-------------------------------------------------------------------------------------------

local lines = {}
local groupLabels = {}

local function groupLabel(content, i, width)
  local h = groupLabels[i]
  if not h then
    h = CreateFrame("Frame", nil, content)
    h:SetSize(width, 20)
    h.text = UI.Text(h, "title", 13, C.goldSoft)
    h.text:SetPoint("LEFT", 4, 0)
    -- "Clear": asks once ("Clear all?"), a second click within 3 seconds clears
    h.clear = CreateFrame("Button", nil, h)
    h.clear:SetSize(60, 18)
    h.clear:SetPoint("RIGHT", -6, 0)
    h.clear.text = UI.Text(h.clear, "body", 12, C.faint)
    h.clear.text:SetPoint("RIGHT")
    h.clear.text:SetJustifyH("RIGHT")
    h.clear:SetScript("OnEnter", function(self) self.text:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
    h.clear:SetScript("OnLeave", function(self) self.text:SetTextColor(C.faint[1], C.faint[2], C.faint[3]) end)
    h.clear:SetScript("OnClick", function(self)
      if self.armed and GetTime() - self.armed < 3 then
        self.armed = nil
        CV:ClearTracking()
      else
        self.armed = GetTime()
        self.text:SetText("Clear all?")   -- the tracker's refresh puts "Clear" back after 3 seconds
      end
    end)
    h.clear:Hide()
    groupLabels[i] = h
  end
  return h
end

local function extraLine(content, i, width)
  local line = lines[i]
  if line then return line end
  line = CreateFrame("Button", nil, content)
  line:SetSize(width, 20)
  line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  line.edge = line:CreateTexture(nil, "ARTWORK")   -- the entry's colour, like a quest card's edge
  line.edge:SetSize(3, 14)
  line.edge:SetPoint("LEFT", 1, 0)
  line.edge:SetColorTexture(1, 1, 1, 1)
  line.mark = line:CreateTexture(nil, "ARTWORK")
  line.mark:SetSize(14, 14)
  line.mark:SetPoint("LEFT", 6, 0)
  line.name = UI.Text(line, "body", 13, { .87, .84, .77 })
  line.name:SetPoint("LEFT", 22, 0)
  line.count = UI.Text(line, "body", 12, C.faint)
  line.count:SetPoint("LEFT", line.name, "RIGHT", 5, 0)
  line.remove = CreateFrame("Button", nil, line)
  line.remove:SetSize(16, 16)
  line.remove:SetPoint("RIGHT", -6, 0)
  line.remove.icon = UI.Icon(line.remove, "close", 8, C.faint)
  line.remove.icon:SetPoint("CENTER")
  line.remove:SetScript("OnClick", function(self) CV:Untrack(self:GetParent().trackKey) end)
  line.dist = UI.Text(line, "body", 12, C.muted)
  line.dist:SetJustifyH("RIGHT")
  line.arrow = UI.Icon(line, "arrow", 11, C.muted)
  line.arrow:SetPoint("RIGHT", line.dist, "LEFT", -3, 0)
  line:SetScript("OnEnter", function(self)
    if self.highlight then Core.Map:SetHighlight(self.highlight) end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(self.tipTitle or "", 1, 1, 1)
    if self.tipText then GameTooltip:AddLine(self.tipText, C.muted[1], C.muted[2], C.muted[3]) end
    GameTooltip:AddLine(self.trackKey and "Click: point the arrow at the nearest · Right-click: colour, remove"
      or "Click: point the arrow at the nearest", C.faint[1], C.faint[2], C.faint[3])
    GameTooltip:Show()
  end)
  line:SetScript("OnLeave", function() Core.Map:SetHighlight(nil) GameTooltip:Hide() end)
  line:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      if self.trackKey then Extras:TrackedMenu(self, self.trackKey) end
      return
    end
    local near = self.nearest and self.nearest()
    if not pointArrow(near, near and near.pin.title) then CV:Print("None of these on this continent.") end
  end)
  lines[i] = line
  return line
end

local function yards(d)
  if d >= 1000 then return string.format("%.1fk yd", d / 1000) end
  return string.format("%d yd", math.floor(d / 5 + .5) * 5)
end

local function paint(line)
  if line.trackKey then
    local c = Extras.ColorOf(line.trackKey)
    line.edge:SetVertexColor(c[1], c[2], c[3])
    line.edge:Show()
    markIcon(line.mark, line.category, true, c)
  else
    line.edge:Hide()
  end
end

local function fillDistance(line)
  paint(line)
  local near = line.nearest and line.nearest()
  if near and CV.char.tracker.arrows ~= false then
    line.dist:SetText(yards(near.distance))
    local facing = GetPlayerFacing()
    local ok = facing ~= nil and not Core.IsSecret(facing)
    line.arrow:SetShown(ok)
    if ok then line.arrow:SetRotation(near.angle - facing) end
  else
    line.dist:SetText("")
    line.arrow:Hide()
  end
  if line.detail then line.count:SetText(line.detail(near)) end
end

---The groups' rows for the tracker, from y down; returns the new y.
function Extras:Draw(content, y, width)
  for _, h in ipairs(groupLabels) do h:Hide() end
  for _, l in ipairs(lines) do l:Hide() end
  local used, g = 0, 0

  local tracked = CV.db.filters.tracking and CV.char.tracked or {}
  if #tracked > 0 then
    g = g + 1
    local h = groupLabel(content, g, width)
    h.text:SetText("Tracking  " .. UI.Code(C.faint) .. #tracked .. "|r")
    h.clear.armed = nil
    h.clear.text:SetText("Clear")
    h.clear:Show()
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    h:Show()
    y = y + 22
    for _, entry in ipairs(tracked) do
      used = used + 1
      local line = extraLine(content, used, width)
      local key = entry.key
      line.trackKey, line.highlight, line.category = key, "track:" .. key, entry.category
      line.name:SetText(entry.name)
      local n = #Extras:TrackedPins(key)
      line.detail = function() return n > 1 and ("×" .. n) or "" end
      line.tipTitle, line.tipText = entry.name, KIND_LABEL[entry.kind]
      line.nearest = function() return nearestOf(Extras:TrackedPins(key)) end
      line.remove:Show()
      line.dist:ClearAllPoints()
      line.dist:SetPoint("RIGHT", line.remove, "LEFT", -4, 0)
      line:ClearAllPoints()
      line:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
      fillDistance(line)
      line:Show()
      y = y + 20
    end
  end

  local first = true
  for _, prof in ipairs(PROFESSIONS) do
    local rank = Extras.Rank(prof)
    if rank and CV.db.filters[prof.key] then
      if first then
        first, g = false, g + 1
        local h = groupLabel(content, g, width)
        h.text:SetText("Gathering")
        h.clear:Hide()
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        h:Show()
        y = y + 22
      end
      used = used + 1
      local line = extraLine(content, used, width)
      local key = prof.key
      line.trackKey, line.highlight, line.category = nil, "gather:" .. key, prof.key
      markIcon(line.mark, prof.key, true)
      line.name:SetText(prof.noSkill and prof.name or (prof.name .. " " .. rank))
      line.nearest = function()
        return nearestOf(Extras:GatherPins(key), function(pin) return (pin.alpha or 1) >= 1 end)
      end
      line.detail = function(near) return near and near.pin.title or "none nearby" end
      line.tipTitle, line.tipText = prof.name, "The nearest node you can gather now"
      line.remove:Hide()
      line.dist:ClearAllPoints()
      line.dist:SetPoint("RIGHT", line, "RIGHT", -8, 0)
      line:ClearAllPoints()
      line:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
      fillDistance(line)
      line:Show()
      y = y + 20
    end
  end
  return y
end

---Distances only (the tracker's refresh).
function Extras:Refresh()
  for _, h in ipairs(groupLabels) do
    local clear = h.clear
    if clear.armed and GetTime() - clear.armed >= 3 then
      clear.armed = nil
      clear.text:SetText("Clear")
    end
  end
  for _, line in ipairs(lines) do
    if line:IsShown() then fillDistance(line) end
  end
end

CV:Listen("EXTRAS_UPDATED", "extras.tracker", function() if CV.Tracker and CV.Tracker.Layout then CV.Tracker:Layout() end end)
