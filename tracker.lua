-- The quest tracker (docs/clairvoyance-v1.md section 3; design/suite/clairvoyance.html).
-- Two views: Detailed (objective lines with bars) and Compact (one line per quest). Every quest
-- in the log (any can be hidden), sorted Nearest / Zone / Level / Log (zones collapse), with live
-- objective progress, party members' progress, the distance and bearing of the nearest target,
-- the turn-in once a quest is complete, and the quest's usable item.
--
-- Hover highlights the quest on the map, minimap and compass. Click opens the quest log,
-- shift-click links it, ctrl-click points the arrow at it, right-click opens its actions.
--
-- Combat: our frames aren't protected, so text and bars update in combat. Layout (rows added,
-- removed, re-sorted or resized) waits for combat to end, because the secure item buttons are
-- placed by the rows' screen positions and can't move in combat.

local Core = NorgannonCore
local CV = Clairvoyance
if CV.disabled then return end
local UI = Core.UI
local C = UI.C

local Tracker = {}
CV.Tracker = Tracker

local WIDTH = 300
local MAX_HEIGHT_SHARE = .62      -- of the screen height; beyond it the list scrolls
local MIN_LIST, GRIP = 60, 12     -- the shortest list you can drag it to; the grip's height
-- a finished quest's title: bright, saturated lime (#99ff1a, pfUI-like; saturated because the
-- title font is thin), brighter than the game's "easy" level green (#40bf40) and a yellower hue,
-- so finished and low-level quests never read alike
local COMPLETE = { .6, 1, .1 }
local GRIP_IDLE = .35             -- the handle's opacity when the mouse isn't on it
local REFRESH = .5                -- default seconds between distance and arrow updates (setting: tracker.refresh)
local RESORT_AFTER = 2            -- a new nearest-first order must hold this long before rows move
local SORTS = { { "near", "Nearest" }, { "zone", "Zone" }, { "level", "Level" }, { "log", "Log" } }

local f, rows, hiddenLine
local order, pendingOrder, pendingSince = {}, nil, nil
local layoutPending = false

-------------------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------------------

local function maxQuests()
  if C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept then
    local ok, n = pcall(C_QuestLog.GetMaxNumQuestsCanAccept)
    if ok and type(n) == "number" and n > 0 and not Core.IsSecret(n) then return n end
  end
  return 40   -- WoW Forever's quest log
end

local function areaName(area)
  if not area then return nil end
  if C_Map and C_Map.GetAreaInfo then
    local ok, name = pcall(C_Map.GetAreaInfo, area)
    if ok and type(name) == "string" then return name end
  end
  local zones = NorgannonDB.zones
  return zones and zones[area] and zones[area].name
end

local function questColor(id) return Core.Colors:ForQuest(id) end

Tracker.COMPLETE = COMPLETE

---pfQuest's progress colour: red at none, yellow halfway, green when done (lightened to read on
---the dark cards). nil when progress colours are off.
function Tracker.ProgressColor(current, required)
  if CV.char.tracker.completeGreen == false then return nil end
  required = tonumber(required) or 1
  local p = required > 0 and math.max(0, math.min(1, (tonumber(current) or 0) / required)) or 1
  local r, g
  if p <= .5 then r, g = 1, p * 2 else r, g = 1 - (p * 2 - 1), 1 end
  return { math.min(1, r + .2), math.min(1, g + .2), .2 }
end

local function setCountColor(fs, current, required)
  local c = (current and required) and Tracker.ProgressColor(current, required) or C.muted
  fs:SetTextColor(c[1], c[2], c[3])
end

local function levelColor(m)
  local level = m.level or 0
  if level <= 0 or m.levelless then return C.muted end
  return UI.Difficulty(level, UnitLevel("player") or 1)
end

local function yards(d)
  if d >= 1000 then return string.format("%.1fk yd", d / 1000) end
  return string.format("%d yd", math.floor(d / 5 + .5) * 5)
end

local function turninWhere(m)
  local target = m.turnins[1]
  if not target then return nil, nil end
  local name = CV.Model.TargetName(target)
  local record = NorgannonDB:Get(target.kind, target.id)
  return name, record and areaName(record.zone)
end

-------------------------------------------------------------------------------------------
-- Quest actions
-------------------------------------------------------------------------------------------

local function openQuestLog(m)
  if QuestMapFrame_OpenToQuestDetails then
    QuestMapFrame_OpenToQuestDetails(m.id)
  elseif QuestLogFrame then
    if SelectQuestLogEntry and m.logIndex then SelectQuestLogEntry(m.logIndex) end
    ShowUIPanel(QuestLogFrame)
  end
end

local function linkQuest(m)
  local link = GetQuestLink and GetQuestLink(m.id)
  if not link then
    link = string.format("|cffffff00|Hquest:%d:%d|h[%s]|h|r", m.id, m.level or 0, m.title)
  end
  if ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
end

function Tracker:Focus(m)
  if CV.focus == m.id then
    Core.Arrow:Clear("unfocused")
    return
  end
  local near = CV.Pins:Nearest(m.id)
  if not near then
    CV:Print("No known location for " .. m.title .. " on this continent.")
    return
  end
  CV.focus = m.id
  Core.Arrow:SetTarget({ area = near.pin.area, x = near.pin.x, y = near.pin.y, owner = "clairvoyance",
    title = (near.pin.title and (near.pin.title .. " · ") or "") .. m.title })
  self:Refresh()
end

Core:Listen("NORGANNON_ARROW_CLEARED", "clairvoyance.tracker", function()
  if CV.focus then
    CV.focus = nil
    Tracker:Refresh()
  end
end)

local function showOnMap(m)
  local near = CV.Pins:Nearest(m.id)
  local uiMap = near and Core.Map.AreaToUiMap(near.pin.area)
  if not uiMap then return end
  if OpenWorldMap then OpenWorldMap(uiMap) else WorldMapFrame:Show() WorldMapFrame:SetMapID(uiMap) end
  Core.Map:Pulse("q" .. m.id)   -- the quest's dots grow and shrink so the eye finds them
end

Tracker.ShowOnMap = showOnMap

local function selectQuest(m)
  if C_QuestLog and C_QuestLog.SetSelectedQuest then
    C_QuestLog.SetSelectedQuest(m.id)
  elseif SelectQuestLogEntry and m.logIndex then
    SelectQuestLogEntry(m.logIndex)
  end
end

local function share(m)
  selectQuest(m)
  if QuestLogPushQuest then QuestLogPushQuest() end
end

local function abandon(m)
  selectQuest(m)
  if C_QuestLog and C_QuestLog.SetAbandonQuest then C_QuestLog.SetAbandonQuest() elseif SetAbandonQuest then SetAbandonQuest() end
  StaticPopup_Show("ABANDON_QUEST", m.title)
end

local function openMenu(row, m)
  local focused = CV.focus == m.id
  Core:ShowActionMenu(row, "quest", m.id, { title = m.title, items = {
    { text = "Open in quest log", func = function() openQuestLog(m) end },
    { text = focused and "Stop pointing the arrow here" or "Point the arrow here", func = function() Tracker:Focus(m) end },
    { text = "Show on map", func = function() showOnMap(m) end },
    { text = "Hide from tracker", func = function() CV.char.hidden[m.id] = true Tracker:Layout() end },
    "-",
    { text = "New colour", func = function() Core.Colors:Randomize(m.id) end },
    { text = "Choose colour…", func = function() Core.Colors:Pick(m.id) end },
    "-",
    { text = "Share with party", func = function() share(m) end, disabled = not IsInGroup() },
    { text = "Abandon quest…", func = function() abandon(m) end },
  } })
end

-------------------------------------------------------------------------------------------
-- Rows
-------------------------------------------------------------------------------------------

---Card background at the chosen opacity (settings: 0 to 100%); hover darkens it a little.
---The outline fades with it, so a fully clear card has no box at all.
function Tracker.PaintCard(row, hover)
  local a = CV.char.tracker.cardAlpha or .62
  local share = a / .62
  row.bg:SetColor(hover and { .055, .043, .027 } or { .03, .024, .016 }, math.min(1, hover and a + .23 or a))
  row.outline:SetColor({ 1, 1, 1 }, math.min(.3, (hover and .14 or .06) * math.max(share, hover and .5 or 0)))
end

local function objectiveLine(row, i)
  local line = row.lines[i]
  if line then return line end
  line = CreateFrame("Frame", nil, row)
  line:SetHeight(20)
  line.text = UI.Text(line, "body", 13, { .87, .84, .77 })
  line.text:SetPoint("TOPLEFT", 0, 0)
  line.count = UI.Text(line, "body", 13, C.muted)
  line.count:SetPoint("TOPRIGHT", 0, 0)
  line.count:SetJustifyH("RIGHT")
  -- a party member's progress: a small pill in the suite's accent (mockup .party)
  line.chip = CreateFrame("Frame", nil, line)
  line.chip:SetHeight(14)
  line.chip:SetPoint("LEFT", line.text, "RIGHT", 6, 0)
  local accent = UI.Accent("clairvoyance")
  line.chip.border = UI.Pill(line.chip, 14, "BACKGROUND", 0)
  line.chip.border:SetColor(accent, .7)
  line.chip.fill = UI.Pill(line.chip, 14, "BACKGROUND", 1, 1)
  line.chip.fill:SetColor(UI.Mix({ .05, .04, .03 }, accent, .18))
  line.party = UI.Text(line.chip, "body", 11, { .85, 1, .97 })
  line.party:SetPoint("CENTER", 0, 0)
  line.party:SetJustifyH("CENTER")
  line.chip:Hide()
  line.bar = UI.Bar(line)
  line.bar:SetPoint("TOPLEFT", line.text, "BOTTOMLEFT", 0, -3)
  line.bar:SetWidth(WIDTH - 34)
  row.lines[i] = line
  return line
end

local function newRow()
  local row = CreateFrame("Button", nil, f.content)
  row:SetWidth(WIDTH)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  -- the card (design/suite: rounded, a faint outline, the quest's colour along the left edge)
  row.bg = UI.Round(row, "BACKGROUND", 0, 6)
  row.outline = UI.Round(row, "BACKGROUND", 2, 6, "line")
  Tracker.PaintCard(row, false)
  row.edge = UI.RoundEdge(row, "BORDER", 0, 6, 3)
  row.summary = UI.Text(row, "body", 12, C.muted)
  row.summary:SetJustifyH("RIGHT")
  row.qicon = row:CreateTexture(nil, "ARTWORK")
  row.qicon:SetSize(20, 20)
  row.itemSlot = CreateFrame("Frame", nil, row)
  row.itemSlot:SetSize(22, 22)
  row.itemSlot:SetPoint("TOPLEFT", 9, -4)
  -- the level in a small rounded badge tinted with its difficulty colour; the text lives inside
  -- the badge's frame so the badge never covers it
  row.badge = CreateFrame("Frame", nil, row)
  row.badge:SetHeight(16)
  row.badge.border = UI.Pill(row.badge, 16, "BACKGROUND", 0)
  row.badge.fill = UI.Pill(row.badge, 16, "BACKGROUND", 1, 1)
  row.level = UI.Text(row.badge, "bold", 12)
  -- optically centred: digits sit low in the font's line box, and the usual drop shadow would
  -- make them heavier on one side of such a small badge
  row.level:SetPoint("CENTER", 1, 1)   -- digits' right-side spacing reads as left of centre
  row.level:SetJustifyH("CENTER")
  row.level:SetShadowOffset(0, 0)
  row.title = UI.Text(row, "title", 14)
  -- a soft black glow all round, so names read on any card opacity (an outline looked harsh)
  UI.Glow(row.title)
  row.dist = UI.Text(row, "body", 12, C.muted)
  row.dist:SetPoint("TOPRIGHT", -8, -7)
  row.dist:SetJustifyH("RIGHT")
  row.arrow = UI.Icon(row, "arrow", 11, C.muted)
  row.arrow:SetPoint("RIGHT", row.dist, "LEFT", -3, 0)
  row.focus = UI.Icon(row, "pinDiamond", 9, C.gold)
  row.turnin = CreateFrame("Frame", nil, row)
  row.turnin:SetHeight(18)
  row.turnin.icon = row.turnin:CreateTexture(nil, "ARTWORK")
  row.turnin.icon:SetSize(14, 14)
  row.turnin.icon:SetPoint("LEFT")
  row.turnin.text = UI.Text(row.turnin, "body", 13, C.gold)
  row.turnin.text:SetPoint("LEFT", row.turnin.icon, "RIGHT", 4, 0)
  row.turnin.where = UI.Text(row.turnin, "body", 12, C.muted)
  row.turnin.where:SetPoint("LEFT", row.turnin.text, "RIGHT", 6, 0)
  row.lines = {}

  row:SetScript("OnEnter", function(self)
    Tracker.PaintCard(self, true)
    Core.Map:SetHighlight("q" .. self.m.id)
    Tracker:ShowTooltip(self, self.m)
  end)
  row:SetScript("OnLeave", function(self)
    Tracker.PaintCard(self, false)
    Core.Map:SetHighlight(nil)
    GameTooltip:Hide()
  end)
  row:SetScript("OnClick", function(self, button)
    local m = self.m
    if button == "RightButton" then openMenu(self, m)
    elseif IsControlKeyDown() then Tracker:Focus(m)
    elseif IsShiftKeyDown() then linkQuest(m)
    else
      -- click: this quest alone switches between compact and expanded
      CV.char.tracker.questView[m.id] = Tracker.IsCompact(m) and "detailed" or "compact"
      Tracker:Layout()
    end
  end)
  return row
end

function Tracker:ShowTooltip(row, m)
  GameTooltip:SetOwner(row, "ANCHOR_LEFT")
  local c = questColor(m.id)
  GameTooltip:AddLine(m.title, c[1], c[2], c[3])
  if m.level and m.level > 0 then GameTooltip:AddLine("Level " .. m.level, C.muted[1], C.muted[2], C.muted[3]) end
  for _, o in ipairs(m.objectives) do
    local done = o.finished
    GameTooltip:AddLine(o.text or o.name or "?", done and .5 or 1, done and .5 or 1, done and .5 or 1)
    for player, objectives in pairs(m.party or {}) do
      local p = objectives[o.index]
      if p then
        local a = UI.Accent("clairvoyance")
        GameTooltip:AddLine("   " .. player .. ": " .. (p.fulfilled or 0) .. "/" .. (p.required or 1), a[1], a[2], a[3])
      end
    end
  end
  local fa = C.faint
  GameTooltip:AddLine("Click: expand or compact · Ctrl-click: point the arrow · Right-click: actions", fa[1], fa[2], fa[3])
  GameTooltip:Show()
end

-- Fills a row from the model; returns its height. values only = no anchors or visibility changes
-- that alter the layout (used in combat).
local function fillRow(row, m, valuesOnly)
  row.m = m
  local c = questColor(m.id)
  row.edge:SetColor(c)
  local lc = levelColor(m)
  local levelText = m.levelless and "–" or (m.level and m.level > 0 and tostring(m.level) or "")
  row.level:SetText(levelText)
  local bright = UI.Mix(lc, { 1, 1, 1 }, .3)
  row.level:SetTextColor(bright[1], bright[2], bright[3])
  row.badge.border:SetColor(lc, .8)
  row.badge.fill:SetColor(UI.Mix({ .06, .05, .035 }, lc, .3), .95)
  -- an even width with an even margin, so the number lands on whole pixels
  row.badge:SetWidth(math.max(22, 2 * math.floor((row.level:GetStringWidth() + 12) / 2 + .5)))
  row.badge:SetShown(levelText ~= "")
  row.title:SetTextColor(lc[1], lc[2], lc[3])
  row.title:SetText(m.complete == "failed" and (m.title .. " (failed)") or m.title)
  if m.complete == "failed" then row.title:SetTextColor(C.impossible[1], C.impossible[2], C.impossible[3]) end
  if m.complete == true and CV.char.tracker.completeGreen ~= false then
    -- done: the title turns green, the end of pfQuest's red-yellow-green progress scale
    row.title:SetTextColor(COMPLETE[1], COMPLETE[2], COMPLETE[3])
  end

  -- distance and direction (setting: tracker.arrows turns both off; no lookups then)
  local showWay = CV.char.tracker.arrows ~= false
  local near = showWay and CV.Pins:Nearest(m.id)
  if near then
    row.dist:SetText(yards(near.distance))
    local facing = GetPlayerFacing()
    row.arrow:SetShown(facing ~= nil and not Core.IsSecret(facing))
    if facing and not Core.IsSecret(facing) then row.arrow:SetRotation(near.angle - facing) end
    local tc = m.complete == true and C.gold or C.muted
    row.arrow:SetVertexColor(tc[1], tc[2], tc[3])
    row.dist:SetTextColor(tc[1], tc[2], tc[3])
  else
    row.dist:SetText(showWay and m.complete == true and m.turnins[1] and "other zone" or "")
    row.arrow:Hide()
  end
  row.summary:SetText(Tracker.Summary(m))
  local pc = Tracker.ProgressColor(Tracker.Progress(m), 1) or C.muted
  row.summary:SetTextColor(pc[1], pc[2], pc[3])
  if valuesOnly then
    for i, o in ipairs(m.objectives) do
      local line = row.lines[i]
      if line then
        line.text:SetText(o.name or o.text or "?")
        line.count:SetText(o.current and o.required and (o.current .. "/" .. o.required) or "")
        setCountColor(line.count, o.current, o.required)
        line.bar:SetProgress(o.current or 0, o.required or 1)
      end
    end
    return row:GetHeight()
  end

  -- layout
  local left = 9
  row.itemSlot:SetShown(m.item ~= nil)
  if m.item then left = left + 26 end
  row.badge:ClearAllPoints()
  row.badge:SetPoint("TOPLEFT", left - 2, -6)
  row.title:ClearAllPoints()
  if row.badge:IsShown() then
    row.title:SetPoint("LEFT", row.badge, "RIGHT", 6, 0)
  else
    row.title:SetPoint("LEFT", row.badge, "LEFT", 0, 0)
  end
  row.focus:ClearAllPoints()
  row.focus:SetPoint("LEFT", row.title, "RIGHT", 5, 0)
  row.focus:SetShown(CV.focus == m.id)

  local y = -28
  for i = 1, #row.lines do row.lines[i]:Hide() end
  row.turnin:Hide()
  local compact = Tracker.IsCompact(m)
  -- compact cards centre the distance (and with it the "?" or %) on the card's one line, even
  -- when the distance is off and empty; detailed cards keep it beside the title
  row.dist:ClearAllPoints()
  if compact then row.dist:SetPoint("RIGHT", row, "RIGHT", -8, 0) else row.dist:SetPoint("TOPRIGHT", -8, -7) end
  row.summary:ClearAllPoints()
  row.qicon:ClearAllPoints()
  if compact then
    -- one line: the summary (or the turn-in "?") sits left of the distance
    local anchor = row.arrow:IsShown() and row.arrow or row.dist
    if m.complete == true then
      Core.Map.SetIcon(row.qicon, "question")
      row.qicon:SetPoint("RIGHT", anchor, "LEFT", anchor == row.dist and row.dist:GetText() == "" and 2 or -4, 0)
      row.qicon:Show()
      row.summary:Hide()
    else
      row.qicon:Hide()
      row.summary:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
      row.summary:Show()
    end
    row:SetHeight(28)
    return 28
  end
  row.summary:Hide()
  row.qicon:Hide()
  if m.complete == true then
    local name, where = turninWhere(m)
    Core.Map.SetIcon(row.turnin.icon, "question")
    row.turnin.text:SetText("Turn in: " .. (name or "quest giver"))
    row.turnin.where:SetText(where or "")
    row.turnin:ClearAllPoints()
    row.turnin:SetPoint("TOPLEFT", 9, y)
    row.turnin:SetPoint("TOPRIGHT", -8, y)
    row.turnin:Show()
    y = y - 20
  else
    for i, o in ipairs(m.objectives) do
      local line = objectiveLine(row, i)
      line:ClearAllPoints()
      line:SetPoint("TOPLEFT", 9, y)
      line:SetPoint("TOPRIGHT", -8, y)
      line.text:SetText(o.name or o.text or "?")
      local done = o.finished
      local tc = done and C.faint or { .87, .84, .77 }
      line.text:SetTextColor(tc[1], tc[2], tc[3])
      line.count:SetText(o.current and o.required and (o.current .. "/" .. o.required) or "")
      setCountColor(line.count, o.current, o.required)
      -- party: the first member's progress as a chip and a mark on the bar
      local partyName, party
      for player, objectives in pairs(m.party or {}) do
        if objectives[i] then partyName, party = player, objectives[i] break end
      end
      if party and not done then
        line.party:SetText(string.sub(partyName, 1, 1) .. " " .. (party.fulfilled or 0))
        line.chip:SetWidth(math.floor(line.party:GetStringWidth() + 12))
        line.chip:Show()
      else
        line.party:SetText("")
        line.chip:Hide()
      end
      local hasBar = CV.char.tracker.bars ~= false and not done and o.required and o.required > 1
      line.bar:SetShown(hasBar)
      if hasBar then
        line.bar.accent = c
        line.bar:SetProgress(o.current or 0, o.required)
        -- the party member's progress: a round dot on your bar
        line.bar:SetMarker(party and (party.fulfilled or 0) / (party.required or 1) or nil, UI.Mix(C.text, UI.Accent("clairvoyance"), .5))
      end
      local h = hasBar and 25 or 18
      line:SetHeight(h)
      line:Show()
      y = y - h
    end
  end
  local height = -y + 6
  row:SetHeight(height)
  return height
end

-------------------------------------------------------------------------------------------
-- Ordering
-------------------------------------------------------------------------------------------

local function visibleQuests()
  local list = {}
  for _, m in ipairs(CV.Model:List()) do
    if not CV.char.hidden[m.id] then list[#list + 1] = m end
  end
  return list
end

-- finished quests grouped at the top or bottom of their group (setting: tracker.finished =
-- "top" | "bottom" | "inline"); nil when it doesn't decide
local function finishedFirst(a, b)
  local where = CV.char.tracker.finished
  if where ~= "top" and where ~= "bottom" then return nil end
  local fa, fb = a.complete == true, b.complete == true
  if fa == fb then return nil end
  if where == "top" then return fa end
  return fb
end
Tracker.FinishedFirst = finishedFirst

local function sorted(list)
  local mode = CV.char.tracker.sort
  local dist = {}
  for _, m in ipairs(list) do
    local near = CV.Pins:Nearest(m.id)
    dist[m.id] = near and near.distance or math.huge
  end
  if mode == "near" then
    table.sort(list, function(a, b)
      local f = finishedFirst(a, b)
      if f ~= nil then return f end
      if dist[a.id] ~= dist[b.id] then return dist[a.id] < dist[b.id] end
      return a.logIndex < b.logIndex
    end)
  elseif mode == "level" then
    table.sort(list, function(a, b)
      local f = finishedFirst(a, b)
      if f ~= nil then return f end
      if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
      return a.title < b.title
    end)
  elseif mode == "zone" then
    table.sort(list, function(a, b)
      local za, zb = areaName(a.zone) or "~", areaName(b.zone) or "~"
      if za ~= zb then return za < zb end
      local f = finishedFirst(a, b)            -- within the zone
      if f ~= nil then return f end
      return dist[a.id] < dist[b.id]
    end)
  else
    table.sort(list, function(a, b)
      local f = finishedFirst(a, b)
      if f ~= nil then return f end
      return a.logIndex < b.logIndex
    end)
  end
  return list
end

local function sameOrder(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i].id ~= b[i].id then return false end end
  return true
end

-------------------------------------------------------------------------------------------
-- Layout
-------------------------------------------------------------------------------------------

local groupHeaders = {}
Tracker.headers = groupHeaders

-- zone headers (Zone sort): click to collapse or expand that zone; remembered per character
local function groupHeader(i)
  local h = groupHeaders[i]
  if not h then
    h = CreateFrame("Button", nil, f.content)
    h:SetSize(WIDTH, 20)
    h.chev = UI.Icon(h, "chevron", 10, C.goldSoft)
    h.chev:SetPoint("LEFT", 4, 0)
    h.text = UI.Text(h, "title", 13, C.goldSoft)
    h.text:SetPoint("LEFT", h.chev, "RIGHT", 5, 0)
    h:SetScript("OnClick", function(self)
      local zones = CV.char.tracker.collapsedZones
      zones[self.zone] = not zones[self.zone] or nil
      Tracker:Layout()
    end)
    h:SetScript("OnEnter", function(self) self.text:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) end)
    h:SetScript("OnLeave", function(self) self.text:SetTextColor(C.goldSoft[1], C.goldSoft[2], C.goldSoft[3]) end)
    groupHeaders[i] = h
  end
  return h
end

---Whether a quest shows compact: its own choice (clicked), else the tracker's default view.
function Tracker.IsCompact(m)
  local own = CV.char.tracker.questView[m.id]
  return (own or CV.char.tracker.view) == "compact"
end

---How far along a quest is, 0 to 1: the average of its objectives (pfQuest's percentage).
function Tracker.Progress(m)
  if m.complete == true then return 1 end
  if #m.objectives == 0 then return 0 end
  local sum = 0
  for _, o in ipairs(m.objectives) do
    if o.finished then sum = sum + 1
    elseif o.current and o.required and o.required > 0 then sum = sum + math.min(1, o.current / o.required) end
  end
  return sum / #m.objectives
end

---The one-line progress of a quest for the compact view: "45%".
function Tracker.Summary(m)
  if m.complete == true or #m.objectives == 0 then return "" end
  return math.floor(Tracker.Progress(m) * 100) .. "%"
end

local function placeItemButtons()
  for _, row in ipairs(rows) do
    local key = "cv" .. (row.m and row.m.id or 0)
    if row:IsShown() and row.m and row.m.item and f:IsShown() and not CV.char.tracker.collapsed then
      local slot = row.itemSlot
      local scale = slot:GetEffectiveScale() / UIParent:GetEffectiveScale()
      local x, y = (slot:GetLeft() or 0) * scale, (slot:GetTop() or 0) * scale
      Core.ItemButtons:Show(key, row.m.item, function(b) b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y) end)
    elseif row.m then
      Core.ItemButtons:Hide(key)
    end
  end
end

function Tracker:Layout()
  if not f then return end
  if InCombatLockdown() then
    layoutPending = true
    self:Refresh(true)
    return
  end
  layoutPending = false
  local quests = sorted(visibleQuests())
  order, pendingOrder, pendingSince = quests, nil, nil
  self:Draw(quests)
end

function Tracker:Draw(quests)
  local collapsed = CV.char.tracker.collapsed
  f.count:SetText(#CV.Model:List() .. "/" .. maxQuests())
  f.collapse:SetRotation(collapsed and math.pi / 2 or 0)
  f.tools:SetShown(not collapsed)
  f.scroll:SetShown(not collapsed)
  for _, h in ipairs(groupHeaders) do h:Hide() end
  local byZone = CV.char.tracker.sort == "zone"
  local counts = {}
  if byZone then
    for _, m in ipairs(quests) do
      local z = areaName(m.zone) or "Other"
      counts[z] = (counts[z] or 0) + 1
    end
  end
  local compact = CV.char.tracker.view == "compact"
  local gap = compact and 2 or 3
  local y, zone, g, used = 0, nil, 0, 0
  for _, m in ipairs(quests) do
    local z = byZone and (areaName(m.zone) or "Other")
    if byZone and z ~= zone then
      zone, g = z, g + 1
      local h = groupHeader(g)
      h.zone = z
      h.text:SetText(z .. "  " .. UI.Code(C.faint) .. counts[z] .. "|r")
      h.chev:SetRotation(CV.char.tracker.collapsedZones[z] and math.pi / 2 or 0)
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
      h:Show()
      y = y + 22
    end
    if not (byZone and CV.char.tracker.collapsedZones[z]) then
      used = used + 1
      local row = rows[used] or newRow()
      rows[used] = row
      local height = fillRow(row, m)
      Tracker.PaintCard(row, false)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
      row:Show()
      y = y + height + gap
    end
  end
  for i = used + 1, #rows do
    rows[i]:Hide()
    if rows[i].m then Core.ItemButtons:Hide("cv" .. rows[i].m.id) end
    rows[i].m = nil
  end
  if CV.Extras then y = CV.Extras:Draw(f.content, y, WIDTH) end   -- Tracking and Gathering
  local hidden = 0
  for id in pairs(CV.char.hidden) do if CV.Model:Get(id) then hidden = hidden + 1 end end
  hiddenLine:SetShown(hidden > 0)
  if hidden > 0 then
    hiddenLine.text:SetText(hidden .. " hidden from the tracker · show")
    hiddenLine:ClearAllPoints()
    hiddenLine:SetPoint("TOPLEFT", f.content, "TOPLEFT", 4, -y)
    y = y + 18
  end
  f.content:SetHeight(math.max(1, y))
  local listH = math.min(y, Tracker.MaxListHeight())
  f.scroll:SetHeight(math.max(1, listH))
  f:SetHeight(collapsed and 26 or (26 + 24 + listH + 4 + GRIP))
  f.grip:SetShown(not collapsed)
  placeItemButtons()
end

---How tall the list may get before it scrolls: the length you dragged, else a share of the screen.
function Tracker.MaxListHeight()
  local screen = UIParent:GetHeight() or 800
  local h = CV.char.tracker.height
  if h then return math.max(MIN_LIST, math.min(h, screen * .9)) end
  return screen * MAX_HEIGHT_SHARE
end

---Updates distances and progress; re-sorts nearest-first only when the new order has held for
---RESORT_AFTER seconds, so rows don't jump while you walk. valuesOnly: never move rows (combat).
function Tracker:Refresh(valuesOnly)
  if not f or not f:IsShown() or CV.char.tracker.collapsed then return end
  if not valuesOnly and CV.char.tracker.sort == "near" then
    local desired = sorted(visibleQuests())
    if not sameOrder(desired, order) then
      if pendingOrder and sameOrder(desired, pendingOrder) then
        if GetTime() - pendingSince >= RESORT_AFTER then return self:Layout() end
      else
        pendingOrder, pendingSince = desired, GetTime()
      end
    else
      pendingOrder = nil
    end
  end
  for _, row in ipairs(rows) do
    if row:IsShown() and row.m then
      local m = CV.Model:Get(row.m.id)
      if m then fillRow(row, m, true) end
    end
  end
  if CV.Extras then CV.Extras:Refresh() end
end

-------------------------------------------------------------------------------------------
-- Frame
-------------------------------------------------------------------------------------------

local function savePosition()
  local left, top = f:GetLeft(), f:GetTop()
  if not (left and top) then return end
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
  CV.char.tracker.position = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = left, y = top }
end
Tracker.SavePosition = savePosition

local function build()
  f = CreateFrame("Frame", "ClairvoyanceTracker", UIParent)
  f:SetWidth(WIDTH)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  local pos = CV.char.tracker.position
  if pos and pos.point then
    f:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
    if pos.point ~= "TOPLEFT" then C_Timer.After(0, savePosition) end   -- saved by 0.1: convert
  else
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -70, -250)
  end
  f:SetScale(CV.char.tracker.scale or 1)

  local head = CreateFrame("Frame", nil, f)
  head:SetHeight(24)
  head:SetPoint("TOPLEFT")
  head:SetPoint("TOPRIGHT")
  head:EnableMouse(true)
  head:RegisterForDrag("LeftButton")
  head:SetScript("OnDragStart", function() if not InCombatLockdown() then f:StartMoving() end end)
  head:SetScript("OnDragStop", function() f:StopMovingOrSizing() savePosition() Tracker:Layout() end)
  f.mark = UI.Mark(head, "clairvoyance", 20)
  f.mark:SetPoint("LEFT", 0, 0)
  f.title = UI.Text(head, "title", 15, C.gold)
  f.title:SetPoint("LEFT", f.mark, "RIGHT", 6, 0)
  f.title:SetText("Quests")
  f.count = UI.Text(head, "body", 12, C.muted)
  f.count:SetPoint("LEFT", f.title, "RIGHT", 6, -1)
  local collapse = CreateFrame("Button", nil, head)
  collapse:SetSize(18, 18)
  collapse:SetPoint("RIGHT", -2, 0)
  local gear = CreateFrame("Button", nil, head)
  gear:SetSize(18, 18)
  gear:SetPoint("RIGHT", collapse, "LEFT", -2, 0)
  gear.icon = UI.Icon(gear, "gear", 12, C.muted)
  gear.icon:SetPoint("CENTER")
  gear:SetScript("OnClick", function() CV:OpenSettings() end)
  gear:SetScript("OnEnter", function(self)
    self.icon:SetVertexColor(1, 1, 1)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Clairvoyance settings", 1, 1, 1)
    GameTooltip:Show()
  end)
  gear:SetScript("OnLeave", function(self) self.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3]) GameTooltip:Hide() end)
  f.gear = gear
  -- track anything: the Finder opens beside the tracker
  local find = CreateFrame("Button", nil, head)
  find:SetSize(18, 18)
  find:SetPoint("RIGHT", gear, "LEFT", -2, 0)
  find.icon = UI.Icon(find, "search", 12, C.muted)
  find.icon:SetPoint("CENTER")
  find:SetScript("OnClick", function() CV.Extras:ToggleFinder(f) end)
  find:SetScript("OnEnter", function(self)
    self.icon:SetVertexColor(1, 1, 1)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Track anything", 1, 1, 1)
    GameTooltip:AddLine("Herbs, ore, NPCs, items, flight masters, mailboxes…", C.muted[1], C.muted[2], C.muted[3])
    GameTooltip:Show()
  end)
  find:SetScript("OnLeave", function(self) self.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3]) GameTooltip:Hide() end)
  f.find = find
  f.collapse = UI.Icon(collapse, "chevron", 12, C.muted)
  f.collapse:SetPoint("CENTER")
  collapse:SetScript("OnClick", function()
    CV.char.tracker.collapsed = not CV.char.tracker.collapsed
    Tracker:Layout()
  end)


  f.tools = CreateFrame("Frame", nil, f)
  f.tools:SetHeight(20)
  f.tools:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -2)
  f.tools:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -2)
  local items = {}
  for _, s in ipairs(SORTS) do items[#items + 1] = { key = s[1], label = s[2] } end
  f.sort = UI.Segmented(f.tools, items, function(key)
    CV.char.tracker.sort = key
    Tracker:Layout()
  end)
  f.sort:ApplyAccent(UI.Accent("clairvoyance"))
  f.sort:SetPoint("LEFT", 0, 0)
  f.sort:Select(CV.char.tracker.sort, true)
  -- the default view for every quest (a click on a quest changes just that one)
  f.view = UI.Segmented(f.tools, {
    { key = "detailed", icon = "viewDetailed", tip = "Detailed view (all quests)" },
    { key = "compact", icon = "viewCompact", tip = "Compact view (all quests)" },
  }, function(key)
    CV.char.tracker.view = key
    wipe(CV.char.tracker.questView)
    Tracker:Layout()
  end)
  f.view:ApplyAccent(UI.Accent("clairvoyance"))
  f.view:SetPoint("RIGHT", 0, 0)
  f.view:Select(CV.char.tracker.view, true)
  f.view.parts = f.view.buttons
  f.view:EnableMouse(true)
  f.view:SetScript("OnMouseUp", function(self)   -- clicking the pill itself flips the view
    self:Select(CV.char.tracker.view == "compact" and "detailed" or "compact")
  end)

  f.scroll = UI.ScrollArea(f)
  f.scroll:SetPoint("TOPLEFT", f.tools, "BOTTOMLEFT", 0, -4)
  f.scroll:SetWidth(WIDTH)
  f.content = f.scroll.content
  f.content:SetWidth(WIDTH)
  f.scroll:HookScript("OnMouseWheel", function() if not InCombatLockdown() then placeItemButtons() end end)

  -- the bottom edge: drag to set the tracker's length (the list scrolls beyond it); right-click
  -- goes back to automatic. Only the length changes; the size slider in settings scales it all.
  local grip = CreateFrame("Button", nil, f)
  grip:SetHeight(GRIP)
  grip:SetPoint("BOTTOMLEFT")
  grip:SetPoint("BOTTOMRIGHT")
  grip:RegisterForClicks("RightButtonUp")
  grip.bar = CreateFrame("Frame", nil, grip)   -- a small handle, always faintly there, bright on hover
  grip.bar:SetSize(48, 4)
  grip.bar:SetPoint("CENTER", 0, 0)
  UI.Pill(grip.bar, 4, "OVERLAY", 0):SetColor(C.muted, .8)
  grip.bar:SetAlpha(GRIP_IDLE)
  local function cursorY() return select(2, GetCursorPosition()) / f:GetEffectiveScale() end
  function grip:Apply(listH)
    f.scroll:SetHeight(listH)
    f:SetHeight(26 + 24 + listH + 4 + GRIP)
  end
  grip:SetScript("OnEnter", function(self)
    self.bar:SetAlpha(1)
    if SetCursor then pcall(SetCursor, "UI_RESIZE_CURSOR") end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Drag to change the tracker's length", 1, 1, 1)
    GameTooltip:AddLine("Right-click: automatic", C.muted[1], C.muted[2], C.muted[3])
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function(self)
    if not self.dragging then
      self.bar:SetAlpha(GRIP_IDLE)
      if ResetCursor then ResetCursor() end
    end
    GameTooltip:Hide()
  end)
  grip:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" or InCombatLockdown() then return end
    self.dragging, self.startY, self.startH = true, cursorY(), f.scroll:GetHeight()
    GameTooltip:Hide()
    self:SetScript("OnUpdate", function()
      local h = self.startH + (self.startY - cursorY())
      self.height = math.floor(math.max(MIN_LIST, math.min(h, (UIParent:GetHeight() or 800) * .9)) + .5)
      self:Apply(self.height)
    end)
  end)
  grip:SetScript("OnMouseUp", function(self, button)
    if button ~= "LeftButton" or not self.dragging then return end
    self.dragging = false
    self:SetScript("OnUpdate", nil)
    local over = self:IsMouseOver()
    self.bar:SetAlpha(over and 1 or GRIP_IDLE)
    if not over and ResetCursor then ResetCursor() end
    if self.height then CV.char.tracker.height = self.height end
    Tracker:Layout()
  end)
  grip:SetScript("OnClick", function()
    CV.char.tracker.height = nil
    Tracker:Layout()
  end)
  f.grip = grip

  hiddenLine = CreateFrame("Button", nil, f.content)
  hiddenLine:SetSize(WIDTH, 16)
  hiddenLine.text = UI.Text(hiddenLine, "body", 12, C.muted)
  hiddenLine.text:SetPoint("LEFT")
  hiddenLine:SetScript("OnClick", function()
    wipe(CV.char.hidden)
    Tracker:Layout()
  end)
  hiddenLine:Hide()

  rows = {}
  local elapsed = 0
  f:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < (CV.char.tracker.refresh or REFRESH) then return end
    elapsed = 0
    Tracker:Refresh(InCombatLockdown())
  end)
  Tracker.frame = f
end

-------------------------------------------------------------------------------------------
-- Blizzard's tracker: hidden while ours is shown (changed only out of combat)
-------------------------------------------------------------------------------------------

local blizzardHooked

local function blizzardTracker() return ObjectiveTrackerFrame or QuestWatchFrame or WatchFrame end

local function applyBlizzard()
  local frame = blizzardTracker()
  if not frame then return end
  Core:AfterCombat(function()
    if CV.char.tracker.shown then
      frame:Hide()
    else
      frame:Show()
      if frame == ObjectiveTrackerFrame and frame.Update then frame:Update() end   -- refill it
    end
  end, "clairvoyance.blizzardtracker")
  if not blizzardHooked then
    blizzardHooked = true
    frame:HookScript("OnShow", function() if CV.char.tracker.shown then applyBlizzard() end end)
  end
end

---Shows or hides Clairvoyance's tracker (and the opposite for Blizzard's).
function Tracker:SetShown(on)
  CV.char.tracker.shown = on and true or false
  if f then
    f:SetShown(on)
    if on then self:Layout() else placeItemButtons() end
  end
  applyBlizzard()
end

-------------------------------------------------------------------------------------------
-- Wiring
-------------------------------------------------------------------------------------------

CV:OnReady(function()
  build()
  Tracker:SetShown(CV.char.tracker.shown)
end)

CV:Listen("MODEL_UPDATED", "tracker", function() Tracker:Layout() end)
-- another set of settings (a scope switch or a preset): the tracker's look follows
CV:Listen("SETTINGS_CHANGED", "tracker", function()
  if not f then return end
  local t = CV.char.tracker
  f:SetScale(t.scale or 1)
  f.view:Select(t.view, true)
  f.sort:Select(t.sort, true)
  Tracker:SetShown(t.shown)
end)
CV:Listen("PINS_UPDATED", "tracker", function() Tracker:Refresh(InCombatLockdown()) end)
Core:Listen("NORGANNON_QUEST_COLOR_CHANGED", "clairvoyance.tracker", function() Tracker:Refresh(true) end)
Core:On("PLAYER_REGEN_ENABLED", "clairvoyance.tracker", function() if layoutPending then Tracker:Layout() end end)
