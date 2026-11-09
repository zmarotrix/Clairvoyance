-- A small mark on bag slots holding an item that's part of a quest, in the bottom-left corner: the stack
-- count has the bottom right, and Dimension's marks the top. Two kinds, so you can tell them apart at a
-- glance (Maro, 2026-11-08):
--   a gold "?", the game's own turn-in mark: a quest in your log needs it. It stays after you have enough,
--     because you still need it to turn the quest in.
--   a silver diamond: a quest you could pick up needs it, or it starts one the game hasn't marked.
-- An item that starts a quest already gets the game's own "!" over its whole icon, and quest items get the
-- game's gold border, so neither gets a mark of ours on top: that hid the game's "!" and said the same thing.
--
-- Any item's mark can be hidden, for good, with a key on the hovered item (Key Bindings, Clairvoyance); the
-- settings bring them all back. Its tooltip names the quests it's for, so you can see why it's marked.
--
-- Marks are separate frames that take no mouse, kept in a table of our own, so nothing is written
-- onto Blizzard's buttons and clicks reach them as before. Any other bag window built from the game's
-- buttons gets them by sending NORGANNON_BAG_BUTTON_UPDATED (button).

local Core = NorgannonCore
local CV = Clairvoyance

local BagMarks = {}
CV.BagMarks = BagMarks

local MARK_SIZE = 16
local DIAMOND_SIZE = 12
local SILVER = { .82, .87, .95 }
BagMarks.SILVER = SILVER

local marks = setmetatable({}, { __mode = "k" })   -- item button -> its mark
BagMarks.marks = marks
local hooked = {}
local known = {}                                   -- item -> "have", "can" or false, until the log changes

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

---Could you take this quest? Being too low a level still counts: the item will be wanted soon.
local function couldTake(questId)
  local ok, why = CV.Availability.Check(questId, NorgannonDB:Get("quests", questId))
  return ok or why == "level too low"
end

---The items whose mark the player hid: [itemId] = true, account-wide.
local function hiddenMarks()
  CV.db.hiddenBagMarks = CV.db.hiddenBagMarks or {}
  return CV.db.hiddenBagMarks
end

function BagMarks.IsHidden(itemId) return hiddenMarks()[itemId] == true end

---The quests a player could take that want this item, or that it starts: { questId }, without the ones in the log.
function BagMarks.CouldTake(itemId)
  local out, seen = {}, {}
  local info = Core.DB:ItemInfo(itemId)
  if not info then return out end
  local P = Core.Player
  local function consider(questId)
    if questId and not seen[questId] and not P:HasQuest(questId) and couldTake(questId) then
      seen[questId] = true
      out[#out + 1] = questId
    end
  end
  for _, questId in ipairs(info.objective) do consider(questId) end
  consider(info.startQuest)
  return out
end

---"have" if a quest in your log needs the item, "can" if one you could take does, or false.
local function questStateOf(itemId)
  local info = Core.DB:ItemInfo(itemId)
  if not info then return false end
  local P = Core.Player
  for _, questId in ipairs(info.objective) do
    if P:HasQuest(questId) then return "have" end
  end
  for _, questId in ipairs(info.objective) do
    if couldTake(questId) then return "can" end
  end
  local start = info.startQuest
  if start and not P:HasQuest(start) and couldTake(start) then return "can" end
  return false
end

---What a slot's mark is: "have", "can" or nil. The game's own word on the slot comes first: it knows
---items that aren't in NorgannonDB yet, and it marks quest starters itself.
function BagMarks.QuestState(bag, slot)
  local ok, itemId = pcall(C_Container.GetContainerItemID, bag, slot)
  if not ok or not itemId or Core.IsSecret(itemId) then return nil end
  if BagMarks.IsHidden(itemId) then return nil end
  if C_Container.GetContainerItemQuestInfo then
    local okInfo, quest = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
    if okInfo and type(quest) == "table" and not Core.IsSecret(quest.questID) and quest.questID then
      if not Core.IsSecret(quest.isActive) and quest.isActive then return "have" end
      return nil              -- the game's "!" is on it
    end
  end
  return BagMarks.ItemState(itemId)
end

---What the database says about an item, whatever slot it's in: "have", "can" or nil. Hidden marks count.
function BagMarks.ItemState(itemId)
  if known[itemId] == nil then known[itemId] = questStateOf(itemId) end
  return known[itemId] or nil
end

---Whether a slot gets a mark at all.
function BagMarks.IsQuestSlot(bag, slot) return BagMarks.QuestState(bag, slot) ~= nil end

local function markFor(button)
  local m = marks[button]
  if m then return m end
  m = CreateFrame("Frame", nil, button)
  m:SetSize(MARK_SIZE, MARK_SIZE)
  m:SetPoint("BOTTOMLEFT", 1, 1)
  m:EnableMouse(false)
  m:SetFrameLevel((button:GetFrameLevel() or 1) + 3)
  m.have = m:CreateTexture(nil, "OVERLAY")
  m.have:SetAllPoints()
  Core.Map.SetIcon(m.have, "question")
  -- a dark diamond a little larger behind the silver one, so it reads on any icon
  m.shadow = Core.UI.Icon(m, "pinDiamond", DIAMOND_SIZE + 3, { 0, 0, 0, .85 }, "OVERLAY")
  m.shadow:SetPoint("CENTER")
  m.can = Core.UI.Icon(m, "pinDiamond", DIAMOND_SIZE, SILVER, "OVERLAY")
  m.can:SetDrawLayer("OVERLAY", 1)
  m.can:SetPoint("CENTER")
  marks[button] = m
  return m
end

local function refreshButton(button)
  local okBag, bag = pcall(button.GetBagID, button)
  local okSlot, slot = pcall(button.GetID, button)
  if not (okBag and okSlot and bag and slot) or Core.IsSecret(bag) then return end
  local state = CV.db.bagMarks and BagMarks.QuestState(bag, slot)
  if state then
    local m = markFor(button)
    m.have:SetShown(state == "have")
    m.can:SetShown(state == "can")
    m.shadow:SetShown(state == "can")
    m.state = state
    m:Show()
  elseif marks[button] then
    marks[button].state = nil
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
  wipe(known)
  refreshSoon()
  -- and every button that has had a mark, wherever it is: another add-on's bag window too
  Core:NextFrame(function()
    if CV.ready then
      for button in pairs(marks) do refreshButton(button) end
    end
  end, "clairvoyance.bagmarks.all")
end

---Hides an item's mark, or shows it again.
function BagMarks:SetHidden(itemId, hidden)
  hiddenMarks()[itemId] = hidden and true or nil
  self:Reset()
end

---How many marks are hidden.
function BagMarks.HiddenCount()
  local n = 0
  for _ in pairs(hiddenMarks()) do n = n + 1 end
  return n
end

function BagMarks:ShowAll()
  wipe(hiddenMarks())
  self:Reset()
end

---The item under the mouse: a bag button's, or any item tooltip's.
function BagMarks.Hovered()
  local foci = rawget(_G, "GetMouseFoci") and GetMouseFoci()
  local focus = type(foci) == "table" and foci[1]
  if focus and not Core.IsSecret(focus) and focus.GetBagID and focus.GetID then
    local ok, bag = pcall(focus.GetBagID, focus)
    local okSlot, slot = pcall(focus.GetID, focus)
    if ok and okSlot and bag and slot and not Core.IsSecret(bag) then
      local okId, id = pcall(C_Container.GetContainerItemID, bag, slot)
      if okId and id and not Core.IsSecret(id) then return id end
    end
  end
  if GameTooltip:IsShown() and GameTooltip.GetItem then
    local _, link = GameTooltip:GetItem()
    if type(link) == "string" and not Core.IsSecret(link) then return tonumber(link:match("item:(%d+)")) end
  end
end

---The key binding: hides the hovered item's mark, or shows it again.
function BagMarks:ToggleHovered()
  local id = self.Hovered()
  if not id then return end
  local name = Core.DB:Name("items", id) or ("item " .. id)
  if self.IsHidden(id) then
    self:SetHidden(id, false)
    CV:Print(name .. ": its quest mark shows again.")
  else
    self:SetHidden(id, true)
    CV:Print(name .. ": quest mark hidden. The same key shows it again, or Show them all in the settings.")
  end
end

---The tooltip's last line for a marked or hidden item, about the key: nil for an item with no mark.
function BagMarks.TooltipHint(itemId)
  if not CV.db.bagMarks then return nil end
  local key = rawget(_G, "GetBindingKey") and GetBindingKey("CLAIRVOYANCE_BAGMARK")
  if BagMarks.IsHidden(itemId) then
    return "Quest mark hidden" .. (key and (". " .. key .. " shows it again.") or ".")
  end
  if not BagMarks.ItemState(itemId) then return nil end
  return key and (key .. ": hide this quest mark") or "Hide this quest mark: set a key in Key Bindings, Clairvoyance"
end

CV:OnReady(function() BagMarks:Refresh() end)
Core:On("BAG_UPDATE_DELAYED", "clairvoyance.bagmarks", refreshSoon)
-- quests joining or leaving the log change which items count (not progress on them), and so does a new level
Core:Listen("NORGANNON_QUESTLOG_UPDATED", "clairvoyance.bagmarks", function(_, changes)
  if CV.Availability and CV.Availability.LogChangeMatters(changes) then BagMarks:Reset() end
end)
Core:On("PLAYER_LEVEL_UP", "clairvoyance.bagmarks.level", function() BagMarks:Reset() end)
Core:Listen("NORGANNON_BAG_BUTTON_UPDATED", "clairvoyance.bagmarks", function(_, button)
  if CV.ready then refreshButton(button) end
end)

-- Key Bindings, under AddOns
BINDING_HEADER_CLAIRVOYANCE = "Clairvoyance"
BINDING_NAME_CLAIRVOYANCE_BAGMARK = "Hide or show the quest mark on the hovered item"
