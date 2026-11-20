-- PetAbilityMap: world map icon with a tooltip of pet abilities taught by
-- tameable creatures in the zone being viewed. Data from wow-petopia.com.
local _, ns = ...
local DATA = PetAbilityMapData
local ICON_PATH = "Interface\\Icons\\"
local GREY = { 0.5, 0.5, 0.5 }

local function Msg(t) print("|cff33ff99PetAbilityMap|r: " .. t) end

-- Known abilities --------------------------------------------------------
-- known[ability] = highest rank known. Gathered from the Beast Training
-- window, the pet's spellbook and the hunter's spellbook. Ranks come from
-- "Rank N" text when the client shows it, otherwise by matching the spell's
-- description numbers (e.g. "11 to 13") against each rank's data.
local function Known() return PetAbilityMapCharDB.known end

-- "Bite (Rank 3)" / "Bite 3" / "Bite" -> "Bite", 3 | nil
local function SplitName(name)
  local base, r = name:match("^(.-)%s*%(Rank (%d+)%)$")
  if not base then base, r = name:match("^(.-)%s+(%d+)$") end
  if base and DATA.abilities[base] then return base, tonumber(r) end
  return name
end

local function SpellDescription(spellID)
  if not spellID then return nil end
  if C_Spell and C_Spell.GetSpellDescription then return C_Spell.GetSpellDescription(spellID) end
  if GetSpellDescription then return GetSpellDescription(spellID) end
end

local function RankFromDescription(ability, desc)
  if not desc or desc == "" then return nil end
  local best
  for _, rank in ipairs(DATA.abilities[ability].ranks) do
    local key = rank[7]
    if key and key ~= "" and desc:find(key, 1, true) then best = rank[1] end
  end
  return best
end

-- Returns ability, rank (or nil if not a pet ability).
local function Identify(name, sub, spellID)
  if not name then return nil end
  local ability, rank = SplitName(name)
  if not DATA.abilities[ability] then return nil end
  rank = rank or tonumber(sub and sub:match("(%d+)"))
    or RankFromDescription(ability, SpellDescription(spellID)) or 1
  return ability, rank
end
ns.Identify = Identify

local function Learn(name, sub, spellID)
  local ability, rank = Identify(name, sub, spellID)
  if not ability then return end
  local k = Known()
  if (k[ability] or 0) < rank then k[ability] = rank end
end

-- Classic-style Beast Training window (craft API)
local function ScanBeastTraining()
  if not (GetNumCrafts and GetCraftInfo) then return end
  if GetCraftDisplaySkillLine and GetCraftDisplaySkillLine() ~= "Beast Training" then return end
  for i = 1, GetNumCrafts() do
    local name, sub, kind = GetCraftInfo(i)
    if kind ~= "header" then Learn(name, sub) end
  end
end

-- WoW Forever: Beast Training opens as a trainer window (TRAINER_SHOW).
-- It lists only abilities the hunter has learned, so every entry counts,
-- whatever its type (available / unavailable / used). Filters are opened
-- up temporarily so nothing is hidden, then put back.
local lastTrainerScan = 0
local function ScanTrainer()
  if not (GetNumTrainerServices and GetTrainerServiceInfo) then return end
  -- changing filters fires TRAINER_UPDATE; don't let that re-trigger us
  if GetTime() - lastTrainerScan < 1 then return end
  lastTrainerScan = GetTime()
  local saved = {}
  if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
    for _, t in ipairs({ "available", "unavailable", "used" }) do
      saved[t] = GetTrainerServiceTypeFilter(t)
      if not saved[t] then SetTrainerServiceTypeFilter(t, 1) end
    end
  end
  for i = 1, GetNumTrainerServices() do
    local name, sub, kind = GetTrainerServiceInfo(i)
    if name and kind ~= "header" then
      local ability, rank = SplitName(name)
      if DATA.abilities[ability] then
        rank = rank or tonumber(sub and sub:match("(%d+)"))
          or RankFromDescription(ability, GetTrainerServiceDescription and GetTrainerServiceDescription(i)) or 1
        local k = PetAbilityMapCharDB.known
        if (k[ability] or 0) < rank then k[ability] = rank end
      end
    end
  end
  for t, v in pairs(saved) do if not v then SetTrainerServiceTypeFilter(t, 0) end end
end
ns.ScanTrainer = ScanTrainer

-- Modern trade-skill style window, in case Beast Training uses it
local function ScanTradeSkill()
  local T = C_TradeSkillUI
  if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo) then return end
  for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
    local info = T.GetRecipeInfo(id)
    if info and info.learned then Learn(info.name, info.subText, info.recipeID) end
  end
end

-- Spellbook item: name, subName, spellID
local function BookItem(i, bank)
  if C_SpellBook and C_SpellBook.GetSpellBookItemInfo and Enum and Enum.SpellBookSpellBank then
    local info = C_SpellBook.GetSpellBookItemInfo(i, bank == "pet" and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player)
    if info then return info.name, info.subName, info.spellID or info.actionID end
  elseif GetSpellBookItemName then
    local name, sub, id = GetSpellBookItemName(i, bank == "pet" and (BOOKTYPE_PET or "pet") or (BOOKTYPE_SPELL or "spell"))
    return name, sub, id
  end
end
ns.BookItem = BookItem

local function NumPlayerBookItems()
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
    local n = 0
    for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
      local info = C_SpellBook.GetSpellBookSkillLineInfo(i)
      if info then n = math.max(n, (info.itemIndexOffset or 0) + (info.numSpellBookItems or 0)) end
    end
    return n
  elseif GetNumSpellTabs then
    local n = 0
    for i = 1, GetNumSpellTabs() do
      local _, _, offset, num = GetSpellTabInfo(i)
      n = math.max(n, (offset or 0) + (num or 0))
    end
    return n
  end
  return 0
end
ns.NumPlayerBookItems = NumPlayerBookItems

local function NumPetSpells()
  if C_SpellBook and C_SpellBook.HasPetSpells then return (C_SpellBook.HasPetSpells()) end
  if HasPetSpells then return (HasPetSpells()) end
end
ns.NumPetSpells = NumPetSpells

local function ScanPet()
  local n = NumPetSpells()
  for i = 1, (n or 0) do Learn(BookItem(i, "pet")) end
end

local function ScanPlayer()
  for i = 1, NumPlayerBookItems() do Learn(BookItem(i, "player")) end
end

local function IsKnown(ability, rank) return (Known()[ability] or 0) >= rank end
ns.IsKnown = IsKnown
ns.KnownRank = function(ability) return Known()[ability] or 0 end
ns.Scan = function()
  pcall(ScanPet); pcall(ScanPlayer); pcall(ScanBeastTraining); pcall(ScanTradeSkill); pcall(ScanTrainer)
end

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
local FillTooltip
local function ShowTip(tt, zone)
  FillTooltip(tt, zone)
  tt:AddLine(" ")
  tt:AddLine("Click to " .. (PetAbilityMapCharDB.showPins and "hide" or "show") .. " creature locations on the map.", 0.6, 0.75, 1)
end

FillTooltip = function(tt, zone)
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
  btn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 8)
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
      GameTooltip:ClearLines(); ShowTip(GameTooltip, zone); GameTooltip:Show()
    end
  end

  local acc, lastMap = 0, nil
  btn:SetScript("OnUpdate", function(self, el)
    acc = acc + el
    if acc < 0.25 then return end
    acc = 0
    local mapID = WorldMapFrame:GetMapID()
    if mapID ~= lastMap then lastMap = mapID; Refresh(self); ns.RefreshPins() else ns.CheckPinScale() end
  end)
  btn:SetScript("OnShow", function(self) Refresh(self); ns.RefreshPins() end)
  btn:RegisterForClicks("LeftButtonUp")
  btn:SetScript("OnClick", function(self) ns.TogglePins(); Refresh(self) end)
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
    ShowTip(GameTooltip, MapZoneName())
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
for _, e in ipairs({ "CRAFT_SHOW", "CRAFT_UPDATE", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE",
    "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "TRAINER_SHOW", "TRAINER_UPDATE" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == "PetAbilityMap" then
    PetAbilityMapCharDB = PetAbilityMapCharDB or {}
    PetAbilityMapCharDB.known = PetAbilityMapCharDB.known or {}
  elseif event == "PLAYER_LOGIN" then
    ns.Scan(); CreateButton()
  elseif event ~= "ADDON_LOADED" then
    ns.Scan()
  end
end)

-- Slash commands -----------------------------------------------------------
SLASH_PETABILITYMAP1 = "/petab"
SlashCmdList.PETABILITYMAP = function(msg)
  msg = strtrim((msg or ""):lower())
  if msg == "debug" then
    ns.Debug()
  elseif msg == "known" then
    ns.Scan()
    local any
    for a, r in pairs(Known()) do Msg(a .. " " .. r); any = true end
    if not any then Msg("nothing recorded yet. Open Beast Training or summon your pet.") end
  elseif msg == "show" or msg == "list" then
    ns.ToggleUI()
  elseif msg == "minimap" then
    PetAbilityMapCharDB.hideMinimap = not PetAbilityMapCharDB.hideMinimap
    ns.UpdateMinimapButton()
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
