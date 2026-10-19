-- Quest log extras (hooks only, never replacing Blizzard functions):
--   levels in front of quest titles, "[12] Cutting Teeth" (setting: questLog.levels)
--   the quest ID after the title (setting: questLog.ids, off by default)
--   "Show on map" and "Point the arrow" buttons above the selected quest's details
-- Works with the classic quest log (QuestLogFrame) and the modern one (QuestMapFrame), whichever
-- the client has.

local Core = NorgannonCore
local CV = Clairvoyance
if CV.disabled then return end
local UI = Core.UI

local QL = {}
CV.QuestLog = QL

local function settings() return CV.db.questLog end

-- the classic and the modern log's globals: only one set exists on a client
local function G(name) return rawget(_G, name) end

---The title a quest log row shows: "[12] Cutting Teeth", with " (788)" when IDs are on.
function QL.Decorate(title, level, questId, elite)
  if not title then return title end
  local s = settings()
  local out = title
  if s.levels and level and level > 0 then out = "[" .. level .. (elite and "+" or "") .. "] " .. out end
  if s.ids and questId then out = out .. " (" .. questId .. ")" end
  return out
end

local function infoByIndex(index)
  if C_QuestLog and C_QuestLog.GetInfo then
    local info = C_QuestLog.GetInfo(index)
    if info and not info.isHeader then return info.title, info.level, info.questID, info.suggestedGroup and info.suggestedGroup > 0 end
    return nil
  end
  if G("GetQuestLogTitle") then
    local title, level, tag, isHeader, _, _, _, questId = G("GetQuestLogTitle")(index)
    if not isHeader then return title, level, questId, tag ~= nil end
  end
end

local function decorateButton(button, title, level, questId, elite)
  local fs = button.Text or button.normalText or (button.GetFontString and button:GetFontString())
  if not (fs and fs.SetText and title) then return end
  fs:SetText(QL.Decorate(title, level, questId, elite))
end

---Re-decorates the visible rows (the hooks call it after Blizzard draws the log).
function QL:Update()
  if not CV.ready then return end
  local s = settings()
  if not (s.levels or s.ids) then return end
  -- modern log: pooled title buttons carry their quest ID
  local pool = G("QuestScrollFrame") and G("QuestScrollFrame").titleFramePool
  if pool and pool.EnumerateActive then
    for button in pool:EnumerateActive() do
      local id = button.questID
      local index = id and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
      if index then decorateButton(button, infoByIndex(index)) end
    end
    return
  end
  -- classic log: QuestLogTitle1..N, scrolled by FauxScrollFrame
  local offset = G("QuestLogListScrollFrame") and G("FauxScrollFrame_GetOffset") and G("FauxScrollFrame_GetOffset")(G("QuestLogListScrollFrame")) or 0
  for i = 1, (G("QUESTS_DISPLAYED") or 0) do
    local button = G("QuestLogTitle" .. i)
    if button and button:IsShown() then
      local index = button:GetID() > 0 and button:GetID() or (i + offset)
      decorateButton(button, infoByIndex(index))
    end
  end
end

-------------------------------------------------------------------------------------------
-- Buttons above the details: Show on map, Point the arrow
-------------------------------------------------------------------------------------------

local function selectedQuest()
  if C_QuestLog and C_QuestLog.GetSelectedQuest then
    local id = C_QuestLog.GetSelectedQuest()
    if id and id > 0 then return id end
  end
  local index = G("GetQuestLogSelection") and G("GetQuestLogSelection")()
  if index and index > 0 then return select(3, infoByIndex(index)) end
end
QL.SelectedQuest = selectedQuest

local bar

local function buildBar()
  local dock = (G("QuestMapFrame") and G("QuestMapFrame").DetailsFrame) or G("QuestLogDetailScrollFrame") or G("QuestLogFrame")
  if not dock then return end
  bar = CreateFrame("Frame", "ClairvoyanceQuestLogBar", dock)
  bar:SetSize(220, 22)
  bar:SetPoint("BOTTOMRIGHT", dock, "TOPRIGHT", 0, 4)
  bar:SetFrameStrata("HIGH")
  bar.map = UI.Button(bar, "Show on map", "quiet", function()
    local m = CV.Model:Get(selectedQuest() or 0)
    if m then CV.Tracker.ShowOnMap(m) end
  end)
  bar.map:SetSize(104, 20)
  bar.map:SetPoint("RIGHT", 0, 0)
  bar.arrow = UI.Button(bar, "Point arrow", "quiet", function()
    local m = CV.Model:Get(selectedQuest() or 0)
    if m then CV.Tracker:Focus(m) end
  end)
  bar.arrow:SetSize(104, 20)
  bar.arrow:SetPoint("RIGHT", bar.map, "LEFT", -4, 0)
  QL.bar = bar
end

function QL:UpdateBar()
  if not bar then return end
  local shown = settings().buttons and CV.Model:Get(selectedQuest() or 0) ~= nil
  bar:SetShown(shown)
end

-------------------------------------------------------------------------------------------
-- Hooks
-------------------------------------------------------------------------------------------

CV:OnReady(function()
  buildBar()
  for _, name in ipairs({ "QuestLog_Update", "QuestLogQuests_Update" }) do
    if G(name) then hooksecurefunc(name, function() QL:Update() QL:UpdateBar() end) end
  end
  for _, name in ipairs({ "QuestLog_SetSelection", "QuestMapFrame_ShowQuestDetails" }) do
    if G(name) then hooksecurefunc(name, function() QL:UpdateBar() end) end
  end
  QL:UpdateBar()
end)

---Redraws the log after a setting changes.
function QL:Refresh()
  if G("QuestLog_Update") and G("QuestLogFrame") and G("QuestLogFrame"):IsShown() then G("QuestLog_Update")()
  elseif G("QuestLogQuests_Update") and G("QuestMapFrame") and G("QuestMapFrame"):IsShown() then G("QuestLogQuests_Update")() end
  self:UpdateBar()
end
