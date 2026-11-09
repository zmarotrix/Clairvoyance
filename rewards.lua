-- The best-selling reward: with a choice of quest rewards, a small gold coin marks the one that
-- sells for the most at a vendor (its price times how many you get). Clairvoyance never picks for
-- you. Ties mark each one; no mark until every choice's price is known (the item cache fills in a
-- moment, GET_ITEM_INFO_RECEIVED), and none when nothing sells. Setting: rewardMark.
--
-- The marks are Clairvoyance's own textures on the reward buttons, kept in its own table: it
-- writes nothing into Blizzard's frames, which keeps the quest frame free of add-on taint.

local Core = NorgannonCore
local CV = Clairvoyance
if CV.disabled then return end
local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo

local Rewards = {}
CV.Rewards = Rewards

local COIN = "Interface\\MoneyFrame\\UI-GoldIcon"
local marks = setmetatable({}, { __mode = "k" })   -- reward button -> our coin texture
local waiting = false                               -- a choice's price wasn't cached yet

-- the reward frame's buttons: RewardButtons on the modern frame, numbered globals on older ones
local function buttons()
  local frame = rawget(_G, "QuestInfoRewardsFrame")
  if frame and type(frame.RewardButtons) == "table" then return frame.RewardButtons end
  local out = {}
  for i = 1, 10 do
    local b = rawget(_G, "QuestInfoRewardsFrameQuestInfoItem" .. i) or rawget(_G, "QuestInfoItem" .. i)
    if b then out[#out + 1] = b end
  end
  return out
end

---Whether this reward button shows the coin.
function Rewards.Marked(button) return marks[button] ~= nil and marks[button]:IsShown() end

local function hideAll()
  for _, coin in pairs(marks) do coin:Hide() end
end

---Which choices sell for the most: { [index] = true }, or nil while a price is unknown or when
---there's no choice. Each choice's worth is its vendor price times its count.
function Rewards.Best()
  local n = GetNumQuestChoices and GetNumQuestChoices() or 0
  if n <= 1 then return nil end
  local info = rawget(_G, "GetQuestItemInfo")
  local worth, best = {}, 0
  for i = 1, n do
    local link = GetQuestItemLink("choice", i)
    if not link then return nil end
    local price = select(11, GetItemInfo(link))
    if price == nil or Core.IsSecret(price) then waiting = true return nil end   -- not cached yet: wait
    local count = info and select(3, info("choice", i)) or 1
    if type(count) ~= "number" or Core.IsSecret(count) or count < 1 then count = 1 end
    worth[i] = price * count
    if worth[i] > best then best = worth[i] end
  end
  if best <= 0 then return nil end
  local out = {}
  for i = 1, n do if worth[i] == best then out[i] = true end end
  return out
end

local function coinOn(button)
  local coin = marks[button]
  if not coin then
    coin = button:CreateTexture(nil, "OVERLAY", nil, 7)
    coin:SetTexture(COIN)
    coin:SetSize(14, 14)
    local icon = button.Icon or button.icon
    if icon then coin:SetPoint("TOPLEFT", icon, "TOPLEFT", -3, 3) else coin:SetPoint("TOPLEFT", button, "TOPLEFT", -3, 3) end
    marks[button] = coin
  end
  coin:Show()
end

---Marks the best seller on the reward panel (and clears marks anywhere else).
function Rewards:Mark()
  hideAll()
  waiting = false
  if not (CV.ready and CV.db.rewardMark) then return end
  local panel = rawget(_G, "QuestFrameRewardPanel")
  if panel and not panel:IsShown() then return end
  local best = Rewards.Best()
  if not best then return end
  for _, b in ipairs(buttons()) do
    -- choices are the buttons of type "choice", by their ID; older frames number choices first
    local kind = b.type
    local index = b.GetID and b:GetID() or 0
    if b:IsShown() and (kind == nil or kind == "choice") and best[index] then coinOn(b) end
  end
end

local function markSoon() Core:NextFrame(function() Rewards:Mark() end, "clairvoyance.rewards") end

Core:On("QUEST_COMPLETE", "clairvoyance.rewards", markSoon)
Core:On("GET_ITEM_INFO_RECEIVED", "clairvoyance.rewards", function() if waiting then markSoon() end end)
Core:On("QUEST_FINISHED", "clairvoyance.rewards", function() waiting = false hideAll() end)
if rawget(_G, "QuestInfo_Display") then hooksecurefunc("QuestInfo_Display", markSoon) end
