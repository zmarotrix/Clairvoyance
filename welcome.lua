-- The first-run welcome (design/suite/clairvoyance.js), once per character: "How much help would
-- you like?" Whether this character keeps its own settings or uses the global ones, three presets
-- and the four automation switches. "Start questing" applies them once; after that the settings
-- are yours to change ("Decide later" asks again next login; /clair welcome runs it again).
-- Choosing All characters when global settings exist uses them as they are, unless you pick a
-- preset to replace them.
--
--   Simple      your quests only: tracker (compact), tooltips, objective and turn-in pins. No
--               available quests, compass, gathering, rares or automation
--   Balanced    (recommended) adds available quests, the compass and detailed quest cards
--   Everything  every feature on: herbs, ore, fishing and rares on the map, rare alerts, quest IDs
--               in the log, and the safe automation (accept, turn in, skip gossip; never picks a
--               reward for you)
-- No preset is a guide: nothing ever tells you which quest to do next.

local Core = NorgannonCore
local CV = Clairvoyance
if CV.disabled then return end
local UI = Core.UI
local C = UI.C

local Welcome = {}
CV.Welcome = Welcome

local NONE = { accept = false, turnin = false, reward = false, gossip = false }
local SAFE = { accept = true, turnin = true, reward = false, gossip = true }   -- rewards stay your choice

local PRESETS = {
  { key = "simple", name = "Simple", tag = "Just your quests",
    points = { "Compact tracker and tooltips", "Pins for the quests you have", "Nothing else on screen" },
    auto = NONE, available = false, compass = false, view = "compact", extras = false },
  { key = "balanced", name = "Balanced", tag = "Recommended",
    points = { "Everything in Simple", "Quests you can pick up nearby", "Compass and detailed cards", "No automation" },
    auto = NONE, available = true, compass = true, view = "detailed", extras = false },
  { key = "everything", name = "Everything", tag = "Every feature on",
    points = { "Everything in Balanced", "Herbs, ore and rares on the map", "Rare alerts, quest IDs", "Accepts and turns in quests" },
    auto = SAFE, available = true, compass = true, view = "detailed", extras = true },
}
-- presets saved before they were renamed (0.1 builds)
local RENAMED = { helper = "balanced", guided = "everything", minimal = "simple" }
Welcome.PRESETS = PRESETS

local AUTO_ROWS = {
  { "accept", "Accept quests", "Not grey ones or ones you hid; hold Shift to pause any of these" },
  { "turnin", "Turn in quests", "Takes the reward when there's only one" },
  { "reward", "Choose rewards", "With a choice, takes the one worth the most at a vendor" },
  { "gossip", "Skip gossip", "Goes straight to the quest at NPCs with quests for you" },
}
Welcome.AUTO_ROWS = AUTO_ROWS

local function presetByKey(key)
  key = RENAMED[key] or key
  for _, p in ipairs(PRESETS) do if p.key == key then return p end end
end

---Applies a preset and automation switches (auto: { accept, turnin, reward, gossip }).
function Welcome.Apply(key, auto)
  local p = presetByKey(key) or PRESETS[2]
  auto = auto or p.auto
  for k in pairs(NONE) do CV.db.auto[k] = auto[k] and true or false end
  local f = CV.db.filters
  f.objectives, f.turnins, f.available = true, true, p.available
  CV.db.tooltips = true
  -- the extras: gathering (chips show only with the profession), rares, rare alerts, quest IDs
  f.herbs, f.mines, f.fish, f.rares = p.extras, p.extras, p.extras, p.extras
  CV.db.rareAlert = p.extras
  CV.db.questLog.ids = p.extras
  CV.db.tracker.shown = true
  CV.db.tracker.view = p.view
  wipe(CV.char.tracker.questView)
  Core.Compass:SetShown(p.compass)
  CV.db.preset = p.key
  CV.charData.welcomed = true
  CV:SettingsChanged()
end

-------------------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------------------

local win
local choice, auto = "balanced", {}
local scope, keep = "char", false   -- keep: use the existing global settings as they are

local function copyAuto(from)
  auto = {}
  for k in pairs(NONE) do auto[k] = from and from[k] and true or false end
end

local function paint()
  for _, card in ipairs(win.cards) do
    local selected = not keep and card.key == choice
    card.box:Set(selected and UI.Accent("clairvoyance") or C.lineStrong, C.inset)
    card.name:SetTextColor(selected and C.text[1] or C.muted[1], selected and C.text[2] or C.muted[2], selected and C.text[3] or C.muted[3])
    card:SetAlpha(keep and .55 or 1)
  end
  for _, row in ipairs(win.rows) do row.toggle:SetOn(auto[row.key], true) end
  win.scope:Select(scope, true)
  local exists, from = CV:GlobalSettings()
  if scope == "char" then
    win.scopeNote:SetText("Settings just for this character. You can switch to global ones later in the settings.")
  elseif keep then
    win.scopeNote:SetText("Global settings already exist" .. (from and (" (set up on " .. from .. ")") or "")
      .. ". They'll be used as they are; pick a preset only to replace them.")
  else
    win.scopeNote:SetText(exists and "This preset will replace your global settings for every character that uses them."
      or "New global settings, shared by every character that picks All characters.")
  end
  win.start.label:SetText(keep and "Use global settings" or "Start questing")
end

local function pick(key)
  choice, keep = key, false
  copyAuto(presetByKey(key).auto)
  paint()
end

local function setScope(value)
  scope = value
  local exists = CV:GlobalSettings()
  if scope == "global" and exists then
    keep = true
    copyAuto(CV.account.global.auto)
  else
    keep = false
    copyAuto(presetByKey(choice).auto)
  end
  paint()
end

---Answers the welcome: the scope, then the preset (or the global settings as they are).
function Welcome.Finish()
  Welcome.finished = true
  CV.charData.welcomed = true      -- first: whatever happens below, the question was answered
  CV.charData.welcomeLater = nil
  if scope == "global" then CV:UseGlobal(true) elseif CV:UsesGlobal() then CV:UseGlobal(false) end
  if keep then
    for k in pairs(NONE) do CV.db.auto[k] = auto[k] and true or false end
    CV.charData.welcomed = true
    CV:SettingsChanged()
  else
    Welcome.Apply(choice, auto)
  end
end

local function build()
  win = UI.Window({ name = "ClairvoyanceWelcome", addon = "clairvoyance", title = "Welcome", width = 640, height = 510, footer = true })
  win:SetAccent("clairvoyance")
  local body = win.body
  local h = UI.Text(body, "title", 22, C.gold)
  h:SetPoint("TOPLEFT", 18, -14)
  h:SetText("How much help would you like?")
  local p = UI.Text(body, "body", 13, C.muted)
  p:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -4)
  p:SetText("A starting point for this character. Afterwards, every option is yours to change (/clair).")

  -- whose settings: this character's own, or the global set
  local label = UI.Text(body, "body", 14, C.text)
  label:SetPoint("TOPLEFT", 18, -66)
  label:SetText("Settings for")
  win.scope = UI.Segmented(body, { { key = "char", label = "This character" }, { key = "global", label = "All characters" } }, setScope)
  win.scope:ApplyAccent(UI.Accent("clairvoyance"))
  win.scope:SetPoint("LEFT", label, "RIGHT", 10, 0)
  win.scopeNote = UI.Text(body, "body", 12, C.faint)
  win.scopeNote:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -10)
  win.scopeNote:SetWidth(640 - 36)
  win.scopeNote:SetJustifyH("LEFT")

  win.cards = {}
  local cardW = math.floor((640 - 36 - 20) / 3)
  for i, preset in ipairs(PRESETS) do
    local card = CreateFrame("Button", nil, body)
    card:SetSize(cardW, 132)
    card:SetPoint("TOPLEFT", 18 + (i - 1) * (cardW + 10), -116)
    card.key = preset.key
    card.box = UI.Box(card, "BACKGROUND", 0)
    card.tag = UI.Text(card, "body", 11, UI.Accent("clairvoyance"))
    card.tag:SetPoint("TOPLEFT", 10, -8)
    card.tag:SetText(string.upper(preset.tag))
    card.name = UI.Text(card, "title", 17)
    card.name:SetPoint("TOPLEFT", card.tag, "BOTTOMLEFT", 0, -3)
    card.name:SetText(preset.name)
    local y = -50
    for _, point in ipairs(preset.points) do
      local t = UI.Text(card, "body", 12, C.muted)
      t:SetPoint("TOPLEFT", 12, y)
      t:SetPoint("TOPRIGHT", -8, y)
      t:SetJustifyH("LEFT")
      t:SetText("· " .. point)
      y = y - 18
    end
    card:SetScript("OnClick", function() pick(preset.key) end)
    win.cards[i] = card
  end

  local pane = UI.Pane(body)
  pane:SetPoint("TOPLEFT", 18, -258)
  pane:SetPoint("TOPRIGHT", -18, -258)
  pane:SetHeight(#AUTO_ROWS * 40 + 10)
  win.rows = {}
  for i, def in ipairs(AUTO_ROWS) do
    local row = CreateFrame("Frame", nil, pane)
    row:SetHeight(38)
    row:SetPoint("TOPLEFT", 10, -5 - (i - 1) * 40)
    row:SetPoint("TOPRIGHT", -10, -5 - (i - 1) * 40)
    row.key = def[1]
    row.toggle = UI.Toggle(row, function(on) auto[def[1]] = on end)
    row.toggle:SetPoint("LEFT", 0, 0)
    row.name = UI.Text(row, "body", 14, C.text)
    row.name:SetPoint("TOPLEFT", row.toggle, "TOPRIGHT", 10, 2)
    row.name:SetText(def[2])
    row.desc = UI.Text(row, "body", 12, C.faint)
    row.desc:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
    row.desc:SetText(def[3])
    win.rows[i] = row
  end

  win.footerText:SetText("Automation is off unless you turn it on.")
  win.start = UI.Button(win.footer, "Start questing", "primary", function()
    Welcome.Finish()
    win:Hide()
  end)
  win.start:SetSize(150, 22)
  win.start:SetPoint("RIGHT", -10, 0)
  win.later = UI.Button(win.footer, "Decide later", "quiet", function() win:Hide() end)
  -- closing it without Start (Decide later, the X, Escape) is "later": never again on a reload,
  -- once more on the next login, then not at all
  win:HookScript("OnHide", function()
    if Welcome.finished then return end
    local later = (CV.charData.welcomeLater or 0) + 1
    CV.charData.welcomeLater = later
    if later >= 2 then CV.charData.welcomed = "skipped" end
  end)
  win.later:SetSize(110, 22)
  win.later:SetPoint("RIGHT", win.start, "LEFT", -8, 0)
  Welcome.frame = win
end

---Opens the welcome, starting from this character's scope, preset and automation switches.
function Welcome:Show()
  if not win then build() end
  Welcome.finished = false
  scope, keep = CV:UsesGlobal() and "global" or "char", false
  choice = (presetByKey(CV.db.preset) or PRESETS[2]).key
  copyAuto(CV.db.auto)
  paint()
  win:Show()
end
Welcome.SetScope = function(value) setScope(value) end
Welcome.Pick = function(key) pick(key) end

-- first run, per character. A reload never brings it back after "later"; a fresh login asks
-- once more (PLAYER_ENTERING_WORLD says which it was).
local freshLogin = true
Core:On("PLAYER_ENTERING_WORLD", "clairvoyance.welcome", function(_, isInitialLogin, isReloadingUi)
  if isInitialLogin ~= nil or isReloadingUi ~= nil then freshLogin = isInitialLogin == true and not isReloadingUi end
end)

---Whether the welcome should open now.
function Welcome.Due()
  local c = CV.charData
  if c.welcomed then return false end
  if (c.welcomeLater or 0) > 0 then return freshLogin end
  return true
end

CV:OnReady(function()
  if Welcome.Due() then
    C_Timer.After(3, function() if Welcome.Due() and not (win and win:IsShown()) then Welcome:Show() end end)
  end
end)
