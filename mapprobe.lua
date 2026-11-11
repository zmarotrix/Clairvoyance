-- /clair mapprobe: can a secure button open the world map cleanly on this client?
--
-- Opening the map from add-on code taints its quest pins until /reload (0.12.1, 0.12.2). A secure
-- action button of type "click" clicks one of Blizzard's own buttons for you, which the game treats
-- as your own click, so the map should build its pins clean. This probe finds Blizzard buttons that
-- could open the map, shows a test button that clicks one, and reports whether the map opened and
-- whether its pins stayed clean. Research only: nothing else uses it yet.

local CV = Clairvoyance
local Core = NorgannonCore

local Probe = {}
CV.MapProbe = Probe

-- likely names first; the scan adds any other named Blizzard button that mentions the map
local KNOWN = { "WorldMapMicroButton", "QuestLogMicroButton", "MiniMapWorldMapButton", "MinimapZoneTextButton",
  "MinimapCluster.ZoneTextButton" }

local function lookup(name)
  local obj = _G
  for part in name:gmatch("[^%.]+") do
    if type(obj) ~= "table" then return nil end
    obj = rawget(obj, part)
  end
  return obj
end

local function isButton(obj)
  if type(obj) ~= "table" or type(obj.GetObjectType) ~= "function" then return false end
  local ok, kind = pcall(obj.GetObjectType, obj)
  return ok and (kind == "Button" or kind == "CheckButton")
end

local function usable(obj)
  if not isButton(obj) then return false end
  local okA, constrained = pcall(obj.HasAccessConstraints, obj)
  if okA and constrained then return false end
  return true
end

---The Blizzard buttons the probe could click: known names first, then a scan of named buttons with
---"Map" in the name. Returns { name, ... }.
function Probe.Candidates()
  local list, seen = {}, {}
  for _, name in ipairs(KNOWN) do
    if usable(lookup(name)) then list[#list + 1] = name seen[name] = true end
  end
  for name, obj in pairs(_G) do
    if type(name) == "string" and not seen[name] and #list < 20 and name:find("Map") and not name:find("^Clairvoyance")
        and not name:find("^Norgannon") and usable(obj) then
      local okP, protected = pcall(obj.IsProtected, obj)
      local okS, script = pcall(obj.GetScript, obj, "OnClick")
      if okS and script and not (okP and protected) then list[#list + 1] = name seen[name] = true end
    end
  end
  return list
end

local button

local function report()
  local shown = WorldMapFrame and WorldMapFrame:IsShown()
  local mapID = shown and WorldMapFrame:GetMapID()
  local bad, pins, names = CV.MapTaint()   -- pins is the reason when bad is nil
  CV:Print(string.format("probe: clicked %s. Map open: %s (map %s). Pins: %s.", tostring(button:GetAttribute("clickbutton-name")),
    tostring(shown), tostring(mapID),
    bad == nil and ("can't check, " .. tostring(pins)) or bad == 0 and string.format("clean (%d checked)", pins)
      or string.format("%d of %d tainted (%s)", bad, pins, table.concat(names, ", "))))
  if shown then CV:Print("probe: now close the map with M, open it again, and type /clair maptaint to be sure.") end
end

local function build()
  if button then return button end
  button = CreateFrame("Button", "ClairvoyanceMapProbe", UIParent, "SecureActionButtonTemplate,BackdropTemplate")
  button:SetSize(150, 26)
  button:SetPoint("CENTER", 0, 160)
  button:SetFrameStrata("DIALOG")
  button:RegisterForClicks("AnyUp")
  button:SetAttribute("useOnKeyDown", false)
  button:SetAttribute("type", "click")
  button:SetMovable(true)
  if button.SetBackdrop then
    button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    button:SetBackdropColor(.05, .1, .12, .92)
    button:SetBackdropBorderColor(.31, .89, .81, 1)
  end
  button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  button.text:SetPoint("CENTER")
  button:HookScript("PostClick", function() C_Timer.After(.5, report) end)
  return button
end

---`/clair mapprobe [ButtonName | hide]`
function Probe.Command(rest)
  rest = rest and rest:match("^%s*(.-)%s*$") or ""
  if rest == "hide" then
    if button and not InCombatLockdown() then button:Hide() end
    return
  end
  if InCombatLockdown() then return CV:Print("probe: out of combat, please (a secure button can't be set up in a fight).") end
  local list = Probe.Candidates()
  CV:Print("probe: buttons that could open the map: " .. (#list > 0 and table.concat(list, ", ") or "none found"))
  local name = rest ~= "" and rest or list[1]
  local target = name and lookup(name)
  if not usable(target) then
    return CV:Print("probe: " .. (name and (name .. " isn't a button I can click.") or "nothing to click. Tell Claude the line above."))
  end
  local b = build()
  b:SetAttribute("clickbutton", target)
  b:SetAttribute("clickbutton-name", name)
  b.text:SetText("Probe: open map")
  b:Show()
  CV:Print("probe: with the map closed, click the \"Probe: open map\" button. To try another: /clair mapprobe <name>. "
    .. "/clair mapprobe hide removes it.")
end
