-- The pickup map: click a quest to pick up in the tracker and a small map of its giver's zone
-- opens beside the row, the giver's eye pulsing on it, with the coordinates.
--
-- Clairvoyance's own window, never Blizzard's map: add-on code that opens or switches the world
-- map taints its quest pins for the session (Core.Map:Reveal). The art is the zone's own, from
-- C_Map's art layers, with every explored-area overlay on top (Oracle's data/reveal.lua, when
-- Oracle is loaded; the pickups come from Oracle, so it is). Oracle's Zones page draws the same
-- way; two add-ons is below Core's three-copy rule, so each keeps its own few lines.
--
-- Click the row again, the close button or Escape to close it.

local Core = NorgannonCore
local CV = Clairvoyance
if CV.disabled then return end
local UI = Core.UI
local C = UI.C
local Extras = CV.Extras

local Preview = {}
CV.PickupMap = Preview

local NAME = "ClairvoyancePickupMap"
local MAP_W, MAP_H = 372, 248          -- the art's box (zone maps are 1002 x 668, 3:2)
local PAD, HEAD, FOOT = 8, 44, 24
local OVERLAY_TILE = 256               -- the world map's overlay textures come in 256 px pieces
local PIN, OTHER_PIN = 28, 18          -- the giver's eye; the quest's other givers in the zone
local PULSE_PERIOD, PULSE_GROW = 1.1, .35
local PLAYER_EVERY = .2                -- seconds between player-marker updates

local frame
local tiles, overlays, others = {}, {}, {}

local function accent() return UI.Accent("clairvoyance") end

-- the smallest power of two that holds n pixels (an overlay piece's texture file size)
local function fileSize(n)
  local s = 16
  while s < n do s = s * 2 end
  return s
end

---Draws a zone's map art fitted and centred in the art box; returns { left, top, width, height,
---tiles, overlays } or nil when the game has no map for it.
function Preview:DrawArt(uiMap)
  for _, t in ipairs(tiles) do t:Hide() end
  for _, t in ipairs(overlays) do t:Hide() end
  local layers = uiMap and C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(uiMap)
  local layer = layers and layers[1]
  local textures = layer and C_Map.GetMapArtLayerTextures(uiMap, 1)
  if not (layer and textures and textures[1]) then return nil end
  local art = frame.art
  local scale = math.min(MAP_W / layer.layerWidth, MAP_H / layer.layerHeight)
  local x0, y0 = (MAP_W - layer.layerWidth * scale) / 2, (MAP_H - layer.layerHeight * scale) / 2
  local cols = math.ceil(layer.layerWidth / layer.tileWidth)
  for i, file in ipairs(textures) do
    local t = tiles[i]
    if not t then
      t = art:CreateTexture(nil, "ARTWORK")
      tiles[i] = t
    end
    local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
    t:SetTexture(file)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", art, "TOPLEFT", x0 + c * layer.tileWidth * scale, -(y0 + r * layer.tileHeight * scale))
    t:SetSize(layer.tileWidth * scale, layer.tileHeight * scale)
    t:Show()
  end
  -- every explored-area overlay, so the zone reads filled in whether you've been there or not
  local n = 0
  local oracle = rawget(_G, "Oracle")   -- optional: Clairvoyance runs without Oracle
  local reveal = oracle and oracle.Reveal
  for _, o in ipairs(reveal and reveal[uiMap] or {}) do
    local width, height, ox, oy, files = o[1], o[2], o[3], o[4], o[5]
    local ocols, orows = math.ceil(width / OVERLAY_TILE), math.ceil(height / OVERLAY_TILE)
    for r = 1, orows do
      local h = r < orows and OVERLAY_TILE or (height - OVERLAY_TILE * (orows - 1))
      for c = 1, ocols do
        local file = files[(r - 1) * ocols + c]
        if file then
          local w = c < ocols and OVERLAY_TILE or (width - OVERLAY_TILE * (ocols - 1))
          n = n + 1
          local t = overlays[n]
          if not t then
            t = art:CreateTexture(nil, "ARTWORK", nil, 1)
            overlays[n] = t
          end
          t:SetTexture(file)
          t:SetTexCoord(0, w / fileSize(w), 0, h / fileSize(h))
          t:ClearAllPoints()
          t:SetPoint("TOPLEFT", art, "TOPLEFT", x0 + (ox + (c - 1) * OVERLAY_TILE) * scale,
            -(y0 + (oy + (r - 1) * OVERLAY_TILE) * scale))
          t:SetSize(w * scale, h * scale)
          t:Show()
        end
      end
    end
  end
  return { left = x0, top = y0, width = layer.layerWidth * scale, height = layer.layerHeight * scale, tiles = #textures, overlays = n }
end

local function place(region, d, x, y)
  region:ClearAllPoints()
  region:SetPoint("CENTER", frame.art, "TOPLEFT", d.left + x / 100 * d.width, -(d.top + y / 100 * d.height))
end

local function otherPin(i)
  local t = others[i]
  if not t then
    t = frame.art:CreateTexture(nil, "OVERLAY", nil, 1)
    t:SetTexture(Extras.PICKUP_ICON)
    t:SetSize(OTHER_PIN, OTHER_PIN)
    t:SetAlpha(.7)
    others[i] = t
  end
  return t
end

-- the player on the map, when they're in the zone shown
local function updatePlayer()
  local d, me = frame.drawn, frame.me
  local pos = d and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(frame.uiMap, "player")
  local x, y
  if pos then x, y = pos:GetXY() end
  if not x or Core.IsSecret(x) or Core.IsSecret(y) or (x == 0 and y == 0) then
    me:Hide()
    return false
  end
  place(me, d, x * 100, y * 100)
  local facing = GetPlayerFacing and GetPlayerFacing()
  if facing and not Core.IsSecret(facing) then me:SetRotation(facing) end
  me:Show()
  return true
end

local function build()
  frame = CreateFrame("Frame", NAME, UIParent)
  frame:SetSize(MAP_W + PAD * 2, HEAD + MAP_H + FOOT + PAD)
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  Extras.DressPanel(frame)
  frame.mark = UI.Icon(frame, Extras.PICKUP_ICON, 22)
  frame.mark:SetPoint("TOPLEFT", PAD, -PAD + 2)
  frame.title = UI.Text(frame, "body", 14, UI.AccentText("clairvoyance"))
  frame.title:SetPoint("TOPLEFT", frame.mark, "TOPRIGHT", 6, -1)
  frame.title:SetWidth(MAP_W - 52)
  frame.title:SetJustifyH("LEFT")
  frame.title:SetWordWrap(false)
  frame.where = UI.Text(frame, "body", 12, C.muted)
  frame.where:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)
  frame.where:SetWidth(MAP_W - 28)
  frame.where:SetJustifyH("LEFT")
  frame.where:SetWordWrap(false)
  frame.close = CreateFrame("Button", nil, frame)
  frame.close:SetSize(18, 18)
  frame.close:SetPoint("TOPRIGHT", -6, -6)
  frame.close.icon = UI.Icon(frame.close, "close", 10, C.muted)
  frame.close.icon:SetPoint("CENTER")
  frame.close:SetScript("OnClick", function() frame:Hide() end)

  local box = CreateFrame("Frame", nil, frame)
  box:SetSize(MAP_W, MAP_H)
  box:SetPoint("TOPLEFT", PAD, -HEAD)
  box:SetClipsChildren(true)
  box.bg = UI.Tex(box, "BACKGROUND", 0, { .051, .043, .071 })
  box.bg:SetAllPoints()
  box.outline = UI.Round(box, "OVERLAY", 7, 4, "line")
  box.outline:SetColor(UI.Mix(C.line, accent(), .16), 1)
  frame.box = box
  frame.art = CreateFrame("Frame", nil, box)
  frame.art:SetSize(MAP_W, MAP_H)
  frame.art:SetPoint("TOPLEFT")
  frame.none = UI.Text(box, "body", 13, C.faint)
  frame.none:SetPoint("CENTER")
  frame.none:SetText("The game has no map for this zone.")
  frame.none:Hide()
  -- the giver: a soft glow under a pulsing eye
  frame.glow = frame.art:CreateTexture(nil, "OVERLAY", nil, 2)
  frame.glow:SetTexture(UI.TEX.ring or UI.TEX.circle)
  frame.glow:SetSize(PIN + 10, PIN + 10)
  local a = accent()
  frame.glow:SetVertexColor(a[1], a[2], a[3], .8)
  frame.pin = frame.art:CreateTexture(nil, "OVERLAY", nil, 3)
  frame.pin:SetTexture(Extras.PICKUP_ICON)
  frame.pin:SetSize(PIN, PIN)
  frame.me = frame.art:CreateTexture(nil, "OVERLAY", nil, 4)
  frame.me:SetTexture("Interface\\Minimap\\MinimapArrow")
  frame.me:SetSize(22, 22)
  frame.me:Hide()

  frame.hint = UI.Text(frame, "body", 11, C.faint)
  frame.hint:SetPoint("BOTTOMLEFT", PAD + 2, 7)
  frame.hint:SetWidth(MAP_W - 4)
  frame.hint:SetJustifyH("LEFT")
  frame.hint:SetWordWrap(false)

  local since, playerAt = 0, 0
  frame:SetScript("OnUpdate", function(self, dt)
    -- the row it belongs to moved on (picked up, list untracked, tracker folded): close
    local row = self.row
    if not (row and row:IsVisible() and row.pickupOf == self.key and row.pickup and row.pickup.step == self.step) then
      self:Hide()
      return
    end
    since = since + dt
    local s = 1 + PULSE_GROW * (1 - math.cos(2 * math.pi * since / PULSE_PERIOD)) / 2
    self.pin:SetSize(PIN * s, PIN * s)
    self.glow:SetSize((PIN + 10) * s, (PIN + 10) * s)
    self.glow:SetAlpha(.9 - .5 * (s - 1) / PULSE_GROW)
    playerAt = playerAt + dt
    if playerAt >= PLAYER_EVERY then
      playerAt = 0
      if self.drawn then updatePlayer() end
    end
  end)
  frame:SetScript("OnHide", function(self) self.row, self.key, self.step = nil, nil, nil end)
  frame:Hide()
  if UISpecialFrames then table.insert(UISpecialFrames, NAME) end   -- Escape closes it
  Preview.frame = frame
end

-- beside the tracker, on the side with room: left of it when it sits on the right half of the
-- screen, else right of it; level with the row
local function anchorTo(row)
  frame:ClearAllPoints()
  local tracker = CV.Tracker and CV.Tracker.frame
  local tl, tr = tracker and tracker:GetLeft(), tracker and tracker:GetRight()
  local rl, rr = row:GetLeft(), row:GetRight()
  local screen = UIParent:GetWidth() or 0
  local center = tl and tr and (tl + tr) / 2
  if center and rl and rr and center < screen / 2 then
    frame:SetPoint("TOPLEFT", row, "TOPRIGHT", (tr - rr) + 8, 0)
  else
    frame:SetPoint("TOPRIGHT", row, "TOPLEFT", -((rl and tl) and (rl - tl) or 0) - 8, 0)
  end
end

---Shows quest p's giver `pin` on the pickup map beside tracker row `row` (the row again closes
---it). Returns true when it opened, false when this closed it.
function Preview:Toggle(row, p, pin)
  if not frame then build() end
  if frame:IsShown() and frame.row == row and frame.key == row.pickupOf and frame.step == p.step then
    frame:Hide()
    return false
  end
  local uiMap = Core.Map.AreaToUiMap(pin.area)
  local info = uiMap and C_Map.GetMapInfo(uiMap)
  local zone = info and info.name or (C_Map.GetAreaInfo and C_Map.GetAreaInfo(pin.area)) or "Unknown zone"
  frame.row, frame.key, frame.step, frame.uiMap, frame.zone, frame.shown = row, row.pickupOf, p.step, uiMap, zone, pin
  frame.title:SetText(p.name)
  frame.where:SetText(string.format("%s  ·  %s  ·  %.1f, %.1f", pin.title or "The giver", zone, pin.x, pin.y))
  local d = self:DrawArt(uiMap)
  frame.drawn = d
  frame.none:SetShown(d == nil)
  for _, t in ipairs(others) do t:Hide() end
  local elsewhere = 0
  if d then
    place(frame.pin, d, pin.x, pin.y)
    place(frame.glow, d, pin.x, pin.y)
    frame.pin:Show()
    frame.glow:Show()
    local n = 0
    for _, o in ipairs(p.pins or {}) do
      if o ~= pin then
        if o.area == pin.area then
          n = n + 1
          place(otherPin(n), d, o.x, o.y)
          others[n]:Show()
        else
          elsewhere = elsewhere + 1
        end
      end
    end
    frame.others = n
  else
    frame.pin:Hide()
    frame.glow:Hide()
    frame.me:Hide()
    frame.others = 0
  end
  frame.here = d and updatePlayer() or false
  local hint = p.how or (p.before and ("It comes before " .. p.before .. ".")) or "Your world map shows it there too."
  if elsewhere > 0 then hint = string.format("%s  +%d more %s elsewhere.", hint, elsewhere, elsewhere == 1 and "giver" or "givers") end
  frame.hint:SetText(hint)
  anchorTo(row)
  frame:Show()
  return true
end

---A tracker draw put list key's quest step on row: the map follows it there (rows are pooled, so a
---redraw can move a quest to another row).
function Preview:Follow(key, step, row)
  if frame and frame:IsShown() and frame.key == key and frame.step == step and frame.row ~= row then
    frame.row = row
    anchorTo(row)
  end
end

function Preview:Hide() if frame then frame:Hide() end end
function Preview:IsShown() return frame ~= nil and frame:IsShown() end
