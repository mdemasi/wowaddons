-- PetAbilityMap: world map icon with a tooltip of pet abilities taught by
-- tameable creatures in the zone being viewed. Data from wow-petopia.com.
local DATA = PetAbilityMapData
local ICON_PATH = "Interface\\Icons\\"
local GREY = { 0.5, 0.5, 0.5 }

local function Msg(t) print("|cff33ff99PetAbilityMap|r: " .. t) end

-- Known abilities --------------------------------------------------------
-- known[ability] = highest rank known. Learned from the Beast Training
-- window (when open) and from your current pet's spellbook.
local function Known() return PetAbilityMapCharDB.known end

local function RankOf(sub)
  return tonumber(sub and sub:match("(%d+)")) or 1
end

local function Learn(name, sub)
  if not name or not DATA.icons[name] then return end
  local r = RankOf(sub)
  local k = Known()
  if (k[name] or 0) < r then k[name] = r end
end

local function ScanBeastTraining()
  if not (GetNumCrafts and GetCraftInfo) then return end
  if GetCraftDisplaySkillLine and GetCraftDisplaySkillLine() ~= "Beast Training" then return end
  for i = 1, GetNumCrafts() do
    local name, sub, kind = GetCraftInfo(i)
    if kind ~= "header" then Learn(name, sub) end
  end
end

local function PetSpellName(i)
  if C_SpellBook and C_SpellBook.GetSpellBookItemName and Enum and Enum.SpellBookSpellBank then
    return C_SpellBook.GetSpellBookItemName(i, Enum.SpellBookSpellBank.Pet)
  elseif GetSpellBookItemName then
    return GetSpellBookItemName(i, BOOKTYPE_PET or "pet")
  elseif GetSpellName then
    return GetSpellName(i, "pet")
  end
end

local function ScanPet()
  local n = HasPetSpells and HasPetSpells()
  if not n then return end
  for i = 1, n do Learn(PetSpellName(i)) end
end

local function IsKnown(ability, rank) return (Known()[ability] or 0) >= rank end

-- Zone lookup --------------------------------------------------------------
local function ZoneEntries(name)
  return name and DATA.zones[name:lower()]
end

local function MapZoneName()
  local id = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
  local info = id and C_Map and C_Map.GetMapInfo(id)
  return info and info.name
end

local function CountUnknown(entries)
  local seen, n = {}, 0
  for _, e in ipairs(entries or {}) do
    local key = e[1] .. e[2]
    if not seen[key] and not IsKnown(e[1], e[2]) then seen[key] = true; n = n + 1 end
  end
  return n
end

-- Tooltip ----------------------------------------------------------------
local function FillTooltip(tt, zone)
  local entries = ZoneEntries(zone)
  tt:AddLine("Pet abilities: " .. (zone or "?"))
  if not entries then
    tt:AddLine("No tameable ability teachers here.", 1, 1, 1)
    return
  end
  local lastAbility, lastRank
  for _, e in ipairs(entries) do
    local ability, rank, petLevel, creature, level = e[1], e[2], e[3], e[4], e[5]
    local known = IsKnown(ability, rank)
    if ability ~= lastAbility then
      local icon = DATA.icons[ability]
      local head = (icon and ("|T" .. ICON_PATH .. icon .. ":14|t ") or "") .. ability
      if known then tt:AddLine(" ") tt:AddLine(head, unpack(GREY)) else tt:AddLine(" ") tt:AddLine(head, 1, 0.82, 0) end
      lastAbility, lastRank = ability, nil
    end
    local left = (rank ~= lastRank) and ("  Rank " .. rank .. " (pet " .. petLevel .. ")") or " "
    lastRank = rank
    if known then
      tt:AddDoubleLine(left .. " - known", creature .. " (" .. level .. ")", GREY[1], GREY[2], GREY[3], GREY[1], GREY[2], GREY[3])
    else
      tt:AddDoubleLine(left, creature .. " (" .. level .. ")", 1, 1, 1, 0.6, 1, 0.6)
    end
  end
end

-- Map button ---------------------------------------------------------------
local btn
local function CreateButton()
  if btn or not WorldMapFrame then return end
  local parent = WorldMapFrame.ScrollContainer or WorldMapFrame
  btn = CreateFrame("Button", "PetAbilityMapButton", parent)
  btn:SetSize(30, 30)
  btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -8)
  btn:SetFrameLevel(parent:GetFrameLevel() + 50)

  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetAllPoints()
  btn.icon:SetTexture(ICON_PATH .. "Ability_Hunter_BeastTraining")
  btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

  btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  btn.count:SetPoint("BOTTOMRIGHT", -1, 2)

  local lastZone
  local function Refresh(self)
    local zone = MapZoneName()
    lastZone = zone
    local entries = ZoneEntries(zone)
    local n = CountUnknown(entries)
    self.icon:SetDesaturated(not entries or n == 0)
    self.count:SetText(n > 0 and n or "")
    if GameTooltip:IsOwned(self) then
      GameTooltip:ClearLines(); FillTooltip(GameTooltip, zone); GameTooltip:Show()
    end
  end

  local acc = 0
  btn:SetScript("OnUpdate", function(self, el)
    acc = acc + el
    if acc < 0.25 then return end
    acc = 0
    if MapZoneName() ~= lastZone then Refresh(self) end
  end)
  btn:SetScript("OnShow", Refresh)
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    FillTooltip(GameTooltip, MapZoneName())
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  Refresh(btn)
end

-- Events -------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PET_BAR_UPDATE")
ev:RegisterEvent("UNIT_PET")
pcall(ev.RegisterEvent, ev, "CRAFT_SHOW")
pcall(ev.RegisterEvent, ev, "CRAFT_UPDATE")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == "PetAbilityMap" then
    PetAbilityMapCharDB = PetAbilityMapCharDB or {}
    PetAbilityMapCharDB.known = PetAbilityMapCharDB.known or {}
  elseif event == "PLAYER_LOGIN" then
    ScanPet(); CreateButton()
  elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
    ScanBeastTraining()
  elseif event == "PET_BAR_UPDATE" or event == "UNIT_PET" then
    ScanPet()
  end
end)

-- Slash commands -----------------------------------------------------------
SLASH_PETABILITYMAP1 = "/petab"
SlashCmdList.PETABILITYMAP = function(msg)
  msg = strtrim((msg or ""):lower())
  if msg == "known" then
    ScanPet(); ScanBeastTraining()
    local any
    for a, r in pairs(Known()) do Msg(a .. " " .. r); any = true end
    if not any then Msg("nothing recorded yet. Open Beast Training or summon your pet.") end
  elseif msg == "reset" then
    wipe(Known()); Msg("known abilities cleared.")
  else
    local zone = GetRealZoneText and GetRealZoneText() or GetZoneText()
    local entries = ZoneEntries(zone)
    if not entries then Msg("no ability teachers in " .. tostring(zone) .. "."); return end
    Msg(zone .. ":")
    for _, e in ipairs(entries) do
      local tag = IsKnown(e[1], e[2]) and " |cff808080(known)|r" or ""
      print(("  %s %d - %s (%s)%s"):format(e[1], e[2], e[4], e[5], tag))
    end
  end
end
