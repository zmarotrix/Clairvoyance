-- A small mark on bag slots holding an item that's part of a quest: one a quest in your log needs,
-- one that starts a quest you haven't done, or one the game itself calls a quest item. A needed item
-- stays marked after you have enough, because you still need it to turn the quest in.
--
-- Marks are separate frames that take no mouse, kept in a table of our own, so nothing is written
-- onto Blizzard's buttons and clicks reach them as before. They sit in the bottom-left corner: the
-- stack count has the bottom right, and Dimension's marks the top. Any other bag window built from
-- the game's buttons gets them by sending NORGANNON_BAG_BUTTON_UPDATED (button).

local Core = NorgannonCore
local CV = Clairvoyance
local UI = Core.UI

local BagMarks = {}
CV.BagMarks = BagMarks

local MARK_SIZE = 14
local GOLD = { .98, .82, .3 }
local DOT = { .05, .04, .03, .85 }

local marks = setmetatable({}, { __mode = "k" })   -- item button -> its mark
BagMarks.marks = marks
local hooked = {}
local wanted = {}                                  -- item -> is it part of a quest, until the log changes

local function containerFrames()
  local out = {}
  local combined = rawget(_G, "ContainerFrameCombinedBags")
  if combined then out[#out + 1] = combined end
  for i = 1, rawget(_G, "NUM_CONTAINER_FRAMES") or 13 do
    local f = rawget(_G, "ContainerFrame" .. i)
    if f then out[#out + 1] = f end
  end
  return out
end

local function partOfQuest(itemId)
  if Core.Bags and Core.Bags.Kind(itemId) == "quest" then return true end
  local info = Core.DB:ItemInfo(itemId)
  if not info then return false end
  if info.startQuest and not Core.Player:IsCompleted(info.startQuest) then return true end
  for _, questId in ipairs(info.objective) do
    if Core.Player:HasQuest(questId) then return true end
  end
  return false
end

---Whether a slot holds an item that's part of a quest. Also asks the game, which knows items that
---aren't in NorgannonDB yet.
function BagMarks.IsQuestSlot(bag, slot)
  local ok, itemId = pcall(C_Container.GetContainerItemID, bag, slot)
  if not ok or not itemId or Core.IsSecret(itemId) then return false end
  if wanted[itemId] == nil then wanted[itemId] = partOfQuest(itemId) end
  if wanted[itemId] then return true end
  if not C_Container.GetContainerItemQuestInfo then return false end
  local okInfo, quest = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
  return okInfo and type(quest) == "table" and not Core.IsSecret(quest.isQuestItem) and quest.isQuestItem == true
end

local function markFor(button)
  local m = marks[button]
  if m then return m end
  m = CreateFrame("Frame", nil, button)
  m:SetSize(MARK_SIZE, MARK_SIZE)
  m:SetPoint("BOTTOMLEFT", 1, 1)
  m:EnableMouse(false)
  m:SetFrameLevel((button:GetFrameLevel() or 1) + 3)
  UI.Icon(m, "circle", MARK_SIZE, DOT, "ARTWORK"):SetAllPoints()
  UI.Icon(m, "exclaim", MARK_SIZE - 2, GOLD, "OVERLAY"):SetPoint("CENTER")
  marks[button] = m
  return m
end

local function refreshButton(button)
  local okBag, bag = pcall(button.GetBagID, button)
  local okSlot, slot = pcall(button.GetID, button)
  if not (okBag and okSlot and bag and slot) or Core.IsSecret(bag) then return end
  local show = CV.db.bagMarks and BagMarks.IsQuestSlot(bag, slot)
  if show then
    markFor(button):Show()
  elseif marks[button] then
    marks[button]:Hide()
  end
end

---Marks again on whichever of the game's bags are showing.
function BagMarks:Refresh()
  self:HookFrames()
  for _, frame in ipairs(containerFrames()) do
    if frame.EnumerateValidItems and frame:IsShown() then
      for _, button in frame:EnumerateValidItems() do refreshButton(button) end
    end
  end
end

local function refreshSoon()
  Core:NextFrame(function() if CV.ready then BagMarks:Refresh() end end, "clairvoyance.bagmarks")
end

---Follows the game's bag frames as they open and fill. Runs again until they exist: some load late.
function BagMarks:HookFrames()
  for _, frame in ipairs(containerFrames()) do
    if not hooked[frame] then
      hooked[frame] = true
      frame:HookScript("OnShow", refreshSoon)
      if frame.UpdateItems then hooksecurefunc(frame, "UpdateItems", refreshSoon) end
    end
  end
end

---After the setting changes, and after the quest log does: what counts as part of a quest changes too.
function BagMarks:Reset()
  wipe(wanted)
  refreshSoon()
end

CV:OnReady(function() BagMarks:Refresh() end)
Core:On("BAG_UPDATE_DELAYED", "clairvoyance.bagmarks", refreshSoon)
Core:Listen("NORGANNON_QUESTLOG_UPDATED", "clairvoyance.bagmarks", function() BagMarks:Reset() end)
Core:Listen("NORGANNON_BAG_BUTTON_UPDATED", "clairvoyance.bagmarks", function(_, button)
  if CV.ready then refreshButton(button) end
end)
