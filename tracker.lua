-- The quest tracker (docs/clairvoyance-v1.md section 3; design/suite/clairvoyance.html).
-- Every quest in the log (any can be hidden), sorted Nearest / Zone / Level / Log, with live
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
local REFRESH = .5                -- seconds between distance updates
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

local function levelColor(m)
  local level = m.level or 0
  if level <= 0 then return C.muted end
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
end

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
  line.party = UI.Text(line, "body", 11, UI.Accent("clairvoyance"))
  line.party:SetPoint("LEFT", line.text, "RIGHT", 6, 0)
  line.bar = UI.Bar(line)
  line.bar:SetPoint("TOPLEFT", line.text, "BOTTOMLEFT", 0, -3)
  line.bar:SetWidth(WIDTH - 34)
  line.mark = UI.Tex(line.bar, "OVERLAY", 0, { .53, .53, .53, 1 })
  line.mark:SetSize(2, 8)
  row.lines[i] = line
  return line
end

local function newRow()
  local row = CreateFrame("Button", nil, f.content)
  row:SetWidth(WIDTH)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row.bg = UI.Tex(row, "BACKGROUND", 0, { .03, .024, .016, .62 })
  row.bg:SetAllPoints()
  row.edge = UI.Tex(row, "BORDER", 0)
  row.edge:SetWidth(3)
  row.edge:SetPoint("TOPLEFT")
  row.edge:SetPoint("BOTTOMLEFT")
  row.itemSlot = CreateFrame("Frame", nil, row)
  row.itemSlot:SetSize(22, 22)
  row.itemSlot:SetPoint("TOPLEFT", 9, -4)
  row.level = UI.Text(row, "body", 12)
  row.title = UI.Text(row, "title", 14)
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
    self.bg:SetColorTexture(.055, .043, .027, .85)
    Core.Map:SetHighlight("q" .. self.m.id)
    Tracker:ShowTooltip(self, self.m)
  end)
  row:SetScript("OnLeave", function(self)
    self.bg:SetColorTexture(.03, .024, .016, .62)
    Core.Map:SetHighlight(nil)
    GameTooltip:Hide()
  end)
  row:SetScript("OnClick", function(self, button)
    local m = self.m
    if button == "RightButton" then openMenu(self, m)
    elseif IsControlKeyDown() then Tracker:Focus(m)
    elseif IsShiftKeyDown() then linkQuest(m)
    else openQuestLog(m) end
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
  GameTooltip:AddLine("Click: quest log · Ctrl-click: point the arrow · Right-click: actions", fa[1], fa[2], fa[3])
  GameTooltip:Show()
end

-- Fills a row from the model; returns its height. values only = no anchors or visibility changes
-- that alter the layout (used in combat).
local function fillRow(row, m, valuesOnly)
  row.m = m
  local c = questColor(m.id)
  row.edge:SetColorTexture(c[1], c[2], c[3], 1)
  local lc = levelColor(m)
  row.level:SetTextColor(lc[1], lc[2], lc[3])
  row.level:SetText(m.level and m.level > 0 and m.level or "")
  row.title:SetTextColor(lc[1], lc[2], lc[3])
  row.title:SetText(m.complete == "failed" and (m.title .. " (failed)") or m.title)
  if m.complete == "failed" then row.title:SetTextColor(C.impossible[1], C.impossible[2], C.impossible[3]) end

  local near = CV.Pins:Nearest(m.id)
  if near then
    row.dist:SetText(yards(near.distance))
    local facing = GetPlayerFacing()
    row.arrow:SetShown(facing ~= nil and not Core.IsSecret(facing))
    if facing and not Core.IsSecret(facing) then row.arrow:SetRotation(near.angle - facing) end
    local tc = m.complete == true and C.gold or C.muted
    row.arrow:SetVertexColor(tc[1], tc[2], tc[3])
    row.dist:SetTextColor(tc[1], tc[2], tc[3])
  else
    row.dist:SetText(m.complete == true and m.turnins[1] and "other zone" or "")
    row.arrow:Hide()
  end
  if valuesOnly then
    for i, o in ipairs(m.objectives) do
      local line = row.lines[i]
      if line then
        line.text:SetText(o.name or o.text or "?")
        line.count:SetText(o.current and o.required and (o.current .. "/" .. o.required) or "")
        line.bar:SetProgress(o.current or 0, o.required or 1)
      end
    end
    return row:GetHeight()
  end

  -- layout
  local left = 9
  row.itemSlot:SetShown(m.item ~= nil)
  if m.item then left = left + 26 end
  row.level:ClearAllPoints()
  row.level:SetPoint("TOPLEFT", left, -8)
  row.title:ClearAllPoints()
  row.title:SetPoint("LEFT", row.level, "RIGHT", 5, 0)
  row.focus:ClearAllPoints()
  row.focus:SetPoint("LEFT", row.title, "RIGHT", 5, 0)
  row.focus:SetShown(CV.focus == m.id)

  local y = -28
  for i = 1, #row.lines do row.lines[i]:Hide() end
  row.turnin:Hide()
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
      -- party: the first member's progress as a chip and a mark on the bar
      local partyName, party
      for player, objectives in pairs(m.party or {}) do
        if objectives[i] then partyName, party = player, objectives[i] break end
      end
      line.party:SetText(party and not done and (string.sub(partyName, 1, 1) .. " " .. (party.fulfilled or 0)) or "")
      local hasBar = not done and o.required and o.required > 1
      line.bar:SetShown(hasBar)
      if hasBar then
        line.bar.accent = c
        line.bar:SetProgress(o.current or 0, o.required)
        line.mark:SetShown(party ~= nil)
        if party then
          line.mark:ClearAllPoints()
          line.mark:SetPoint("CENTER", line.bar, "LEFT", (WIDTH - 34) * math.min(1, (party.fulfilled or 0) / (party.required or 1)), 0)
        end
      end
      local h = hasBar and 24 or 18
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

local function sorted(list)
  local mode = CV.char.tracker.sort
  local dist = {}
  for _, m in ipairs(list) do
    local near = CV.Pins:Nearest(m.id)
    dist[m.id] = near and near.distance or math.huge
  end
  if mode == "near" then
    table.sort(list, function(a, b)
      if dist[a.id] ~= dist[b.id] then return dist[a.id] < dist[b.id] end
      return a.logIndex < b.logIndex
    end)
  elseif mode == "level" then
    table.sort(list, function(a, b)
      if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
      return a.title < b.title
    end)
  elseif mode == "zone" then
    table.sort(list, function(a, b)
      local za, zb = areaName(a.zone) or "~", areaName(b.zone) or "~"
      if za ~= zb then return za < zb end
      return dist[a.id] < dist[b.id]
    end)
  else
    table.sort(list, function(a, b) return a.logIndex < b.logIndex end)
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

local function groupHeader(i)
  local h = groupHeaders[i]
  if not h then
    h = UI.Text(f.content, "title", 13, C.goldSoft)
    groupHeaders[i] = h
  end
  return h
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
  local y, zone, g = 0, nil, 0
  for i, m in ipairs(quests) do
    local row = rows[i] or newRow()
    rows[i] = row
    if CV.char.tracker.sort == "zone" then
      local z = areaName(m.zone) or "Other"
      if z ~= zone then
        zone, g = z, g + 1
        local h = groupHeader(g)
        h:SetText(z)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", f.content, "TOPLEFT", 4, -y - 4)
        h:Show()
        y = y + 22
      end
    end
    local height = fillRow(row, m)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
    row:Show()
    y = y + height + 6
  end
  for i = #quests + 1, #rows do
    rows[i]:Hide()
    if rows[i].m then Core.ItemButtons:Hide("cv" .. rows[i].m.id) end
    rows[i].m = nil
  end
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
  local maxH = (UIParent:GetHeight() or 800) * MAX_HEIGHT_SHARE
  local listH = math.min(y, maxH)
  f.scroll:SetHeight(math.max(1, listH))
  f:SetHeight(collapsed and 26 or (26 + 24 + listH + 4))
  placeItemButtons()
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
end

-------------------------------------------------------------------------------------------
-- Frame
-------------------------------------------------------------------------------------------

local function segmented(parent)
  local seg = CreateFrame("Frame", nil, parent)
  seg:SetHeight(18)
  seg.border = UI.Pill(seg, 18, "BACKGROUND", 0)
  seg.border:SetColor(C.lineStrong)
  seg.fill = UI.Pill(seg, 18, "BACKGROUND", 1, 1)
  seg.fill:SetColor({ 0, 0, 0, .55 })
  seg.buttons = {}
  local x = 4
  for _, s in ipairs(SORTS) do
    local b = CreateFrame("Button", nil, seg)
    b.key = s[1]
    b.bg = UI.Tex(b, "ARTWORK", 0)
    b.bg:SetAllPoints()
    b.text = UI.Text(b, "body", 12, C.muted)
    b.text:SetPoint("CENTER")
    b.text:SetJustifyH("CENTER")
    b.text:SetText(s[2])
    local w = math.floor(b.text:GetStringWidth() + 14)
    b:SetSize(w, 16)
    b:SetPoint("LEFT", seg, "LEFT", x, 0)
    x = x + w
    b:SetScript("OnClick", function(self)
      CV.char.tracker.sort = self.key
      seg:Paint()
      Tracker:Layout()
    end)
    seg.buttons[#seg.buttons + 1] = b
  end
  seg:SetWidth(x + 4)
  function seg:Paint()
    local a = UI.Accent("clairvoyance")
    for _, b in ipairs(self.buttons) do
      local on = b.key == CV.char.tracker.sort
      b.bg:SetColorTexture(a[1], a[2], a[3], on and .3 or 0)
      local tc = on and { 1, 1, 1 } or C.muted
      b.text:SetTextColor(tc[1], tc[2], tc[3])
    end
  end
  return seg
end

local function savePosition()
  local point, _, relativePoint, x, y = f:GetPoint()
  CV.char.tracker.position = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function build()
  f = CreateFrame("Frame", "ClairvoyanceTracker", UIParent)
  f:SetWidth(WIDTH)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  local pos = CV.char.tracker.position
  if pos and pos.point then
    f:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
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
  f.sort = segmented(f.tools)
  f.sort:SetPoint("LEFT", 0, 0)
  f.sort:Paint()

  f.scroll = UI.ScrollArea(f)
  f.scroll:SetPoint("TOPLEFT", f.tools, "BOTTOMLEFT", 0, -4)
  f.scroll:SetWidth(WIDTH)
  f.content = f.scroll.content
  f.content:SetWidth(WIDTH)
  f.scroll:HookScript("OnMouseWheel", function() if not InCombatLockdown() then placeItemButtons() end end)

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
    if elapsed < REFRESH then return end
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
CV:Listen("PINS_UPDATED", "tracker", function() Tracker:Refresh(InCombatLockdown()) end)
Core:Listen("NORGANNON_QUEST_COLOR_CHANGED", "clairvoyance.tracker", function() Tracker:Refresh(true) end)
Core:On("PLAYER_REGEN_ENABLED", "clairvoyance.tracker", function() if layoutPending then Tracker:Layout() end end)
