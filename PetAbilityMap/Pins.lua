-- PetAbilityMap pins: ability icons on the world map where tameable
-- teachers spawn (locations from QuestieDB). Toggled by clicking the map icon.
local _, ns = ...
local LOC = PetAbilityMapLocations
local DATA = PetAbilityMapData
local ICON_PATH = "Interface\\Icons\\"
local PIN_SIZE = 16

local pins, canvas, lastScale = {}, nil, nil

local function CanvasScale()
  local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
  return (sc and sc.GetCanvasScale and sc:GetCanvasScale()) or 1
end

local function PinTooltip(self)
  local npc = LOC.npcs[self.npc]
  if not npc then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(npc[1] .. "  (level " .. npc[2] .. ")")
  local ab = npc[3]
  for i = 1, #ab, 2 do
    local ability, rank = ab[i], ab[i + 1]
    local icon = DATA.icons[ability]
    local text = (icon and ("|T" .. ICON_PATH .. icon .. ":14|t ") or "") .. ability .. " " .. rank
    if ns.IsKnown(ability, rank) then
      GameTooltip:AddLine(text .. " - known", 0.5, 0.5, 0.5)
    else
      GameTooltip:AddLine(text, 0.6, 1, 0.6)
    end
  end
  GameTooltip:Show()
end

local function GetPin(i)
  if pins[i] then return pins[i] end
  local p = CreateFrame("Button", nil, canvas)
  p:SetFrameLevel(canvas:GetFrameLevel() + 20)
  p.icon = p:CreateTexture(nil, "ARTWORK")
  p.icon:SetAllPoints()
  p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  p:SetScript("OnEnter", PinTooltip)
  p:SetScript("OnLeave", function() GameTooltip:Hide() end)
  pins[i] = p
  return p
end

-- Icon of the first ability this creature teaches that you don't know yet.
local function PinIcon(npcId)
  local npc = LOC.npcs[npcId]
  local ab = npc and npc[3] or {}
  for i = 1, #ab, 2 do
    if not ns.IsKnown(ab[i], ab[i + 1]) then return DATA.icons[ab[i]], false end
  end
  return ab[1] and DATA.icons[ab[1]], true
end

function ns.RefreshPins()
  if not (WorldMapFrame and WorldMapFrame.ScrollContainer) then return end
  canvas = canvas or WorldMapFrame.ScrollContainer.Child
  if not canvas then return end
  for _, p in ipairs(pins) do p:Hide() end
  if not PetAbilityMapCharDB.showPins then return end

  local list = LOC.pins[WorldMapFrame:GetMapID()]
  if not list then return end
  local w, h = canvas:GetSize()
  local scale = CanvasScale()
  lastScale = scale
  local size = PIN_SIZE / scale
  local n = 0
  for i = 1, #list, 3 do
    n = n + 1
    local p = GetPin(n)
    local icon, allKnown = PinIcon(list[i])
    p.npc = list[i]
    p:SetSize(size, size)
    p:ClearAllPoints()
    p:SetPoint("CENTER", canvas, "TOPLEFT", list[i + 1] / 100 * w, -list[i + 2] / 100 * h)
    p.icon:SetTexture(ICON_PATH .. (icon or "INV_Misc_QuestionMark"))
    p.icon:SetDesaturated(allKnown)
    p:SetAlpha(allKnown and 0.5 or 1)
    p:Show()
  end
end

-- Keep pins a constant size on screen when zooming the map.
function ns.CheckPinScale()
  if PetAbilityMapCharDB.showPins and lastScale and CanvasScale() ~= lastScale then
    ns.RefreshPins()
  end
end

function ns.TogglePins()
  PetAbilityMapCharDB.showPins = not PetAbilityMapCharDB.showPins
  ns.RefreshPins()
end
