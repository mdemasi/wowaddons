-- PetAbilityMap UI: minimap button + window listing every pet ability,
-- with each rank shown underneath and marked learned or not.
local _, ns = ...
local DATA = PetAbilityMapData
local ICON_PATH = "Interface\\Icons\\"
local WIDTH, ROW_H, HEAD_H = 420, 16, 24

local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
local function setShown(f, show) if show then f:Show() else f:Hide() end end

-- Window -------------------------------------------------------------------
local win = CreateFrame("Frame", "PetAbilityMapWindow", UIParent, backdropTemplate)
win:SetSize(WIDTH + 40, 480)
win:SetPoint("CENTER")
win:SetBackdrop({
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 24,
  insets = { left = 6, right = 6, top = 6, bottom = 6 },
})
win:SetMovable(true); win:SetResizable(true); win:EnableMouse(true); win:SetClampedToScreen(true)
if win.SetResizeBounds then win:SetResizeBounds(320, 220) elseif win.SetMinResize then win:SetMinResize(320, 220) end
win:SetFrameStrata("DIALOG")
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
win:Hide()
tinsert(UISpecialFrames, "PetAbilityMapWindow")

local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", 0, -12)
title:SetText("Pet Abilities")

local summary = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
summary:SetPoint("TOP", title, "BOTTOM", 0, -2)

local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -2, -2)

local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 12, -42)
scroll:SetPoint("BOTTOMRIGHT", -32, 14)

local content = CreateFrame("Frame", nil, scroll)
content:SetSize(WIDTH, 1)
scroll:SetScrollChild(content)
scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)

-- Resize grip (bottom-right); size is remembered per character
local grip = CreateFrame("Button", nil, win)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -6, 6)
grip:SetFrameLevel(scroll:GetFrameLevel() + 5)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
grip:SetScript("OnMouseUp", function()
  win:StopMovingOrSizing()
  PetAbilityMapCharDB.windowSize = { win:GetWidth(), win:GetHeight() }
end)

-- Rows ---------------------------------------------------------------------
local heads, rankRows = {}, {}

local function SourceText(rank)
  local src, teachers = rank[3], rank[4]
  if src == "trainer" then return "Pet trainer" end
  if src == "none" or #teachers == 0 then return "No known source" end
  local first = teachers[1]
  local more = #teachers > 1 and (" +" .. (#teachers - 1) .. " more") or ""
  return "Tame " .. first[1] .. more
end

local function RankTooltip(self)
  local ability, rank = self.ability, self.rank
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  local icon = DATA.icons[ability]
  GameTooltip:AddLine((icon and ("|T" .. ICON_PATH .. icon .. ":16|t ") or "") .. ability .. " " .. rank[1])
  if ns.IsKnown(ability, rank[1]) then GameTooltip:AddLine("Learned", 0.25, 1, 0.25) end
  if rank[5] and rank[5] ~= "" then GameTooltip:AddLine(rank[5], 1, 1, 1, true) end
  GameTooltip:AddLine(("Pet level %d  -  %d training points"):format(rank[2], rank[6] or 0), 1, 0.82, 0)
  local fam = DATA.abilities[ability].families
  if fam and fam ~= "" then GameTooltip:AddLine("Learned by: " .. fam, 0.8, 0.8, 0.8, true) end
  GameTooltip:AddLine(" ")
  if rank[3] == "trainer" then
    GameTooltip:AddLine("Learned from a pet trainer.", 1, 1, 1)
  elseif #rank[4] == 0 then
    GameTooltip:AddLine("No known training source.", 0.6, 0.6, 0.6)
  else
    GameTooltip:AddLine("Tame one of these to learn it:", 1, 1, 1)
    for _, t in ipairs(rank[4]) do
      GameTooltip:AddDoubleLine(t[1] .. " (" .. t[2] .. ")", t[3], 0.6, 1, 0.6, 0.8, 0.8, 0.8)
    end
  end
  GameTooltip:Show()
end

local function Build()
  local names = {}
  for name in pairs(DATA.abilities) do names[#names + 1] = name end
  table.sort(names)

  local y = 0
  for _, name in ipairs(names) do
    local info = DATA.abilities[name]
    local h = CreateFrame("Frame", nil, content)
    h:SetHeight(HEAD_H)
    h:SetPoint("TOPLEFT", 0, -y)
    h:SetPoint("TOPRIGHT", 0, -y)
    h.icon = h:CreateTexture(nil, "ARTWORK")
    h.icon:SetSize(20, 20)
    h.icon:SetPoint("LEFT", 2, 0)
    h.icon:SetTexture(ICON_PATH .. (DATA.icons[name] or "INV_Misc_QuestionMark"))
    h.name = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h.name:SetPoint("LEFT", h.icon, "RIGHT", 6, 0)
    h.name:SetText(name)
    h.fam = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    h.fam:SetPoint("LEFT", h.name, "RIGHT", 6, 0)
    h.fam:SetText(info.families ~= "" and ("(" .. info.families .. ")") or "")
    h.status = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    h.status:SetPoint("RIGHT", -4, 0)
    h.ability, h.max = name, #info.ranks
    heads[#heads + 1] = h
    y = y + HEAD_H

    for _, rank in ipairs(info.ranks) do
      local r = CreateFrame("Button", nil, content)
      r:SetHeight(ROW_H)
      r:SetPoint("TOPLEFT", 28, -y)
      r:SetPoint("TOPRIGHT", 0, -y)
      r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      r.check = r:CreateTexture(nil, "ARTWORK")
      r.check:SetSize(12, 12)
      r.check:SetPoint("LEFT", 0, 0)
      r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      r.label:SetPoint("LEFT", 16, 0)
      r.label:SetText("Rank " .. rank[1] .. "  (pet " .. rank[2] .. ")")
      r.src = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      r.src:SetPoint("RIGHT", -4, 0)
      r.ability, r.rank = name, rank
      r:SetScript("OnEnter", RankTooltip)
      r:SetScript("OnLeave", function() GameTooltip:Hide() end)
      rankRows[#rankRows + 1] = r
      y = y + ROW_H
    end
    y = y + 6
  end
  content:SetHeight(y)
end

local function Refresh()
  if #heads == 0 then Build() end
  ns.Scan()
  local learnedAbilities = 0
  for _, h in ipairs(heads) do
    local k = math.min(ns.KnownRank(h.ability), h.max)
    if k > 0 then
      learnedAbilities = learnedAbilities + 1
      h.status:SetText("|cff40ff40Rank " .. k .. " of " .. h.max .. " learned|r")
    else
      h.status:SetText("|cff808080Not learned|r")
    end
  end
  for _, r in ipairs(rankRows) do
    if ns.IsKnown(r.ability, r.rank[1]) then
      r.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
      r.label:SetTextColor(0.25, 1, 0.25)
      r.src:SetText("Learned"); r.src:SetTextColor(0.25, 1, 0.25)
    else
      r.check:SetTexture(nil)
      r.label:SetTextColor(0.8, 0.8, 0.8)
      r.src:SetText(SourceText(r.rank))
      if r.rank[3] == "none" then r.src:SetTextColor(0.5, 0.5, 0.5) else r.src:SetTextColor(0.6, 0.85, 1) end
    end
  end
  summary:SetText(learnedAbilities .. " of " .. #heads .. " abilities learned  -  hover a rank for teachers")
end

win:SetScript("OnShow", function()
  local sz = PetAbilityMapCharDB.windowSize
  if sz then win:SetSize(sz[1], sz[2]) end
  Refresh()
end)

function ns.ToggleUI() setShown(win, not win:IsShown()) end

-- Minimap button -----------------------------------------------------------
local mb = CreateFrame("Button", "PetAbilityMapMinimapButton", Minimap)
mb:SetSize(31, 31)
mb:SetFrameStrata("MEDIUM")
mb:SetFrameLevel(8)
mb:RegisterForClicks("LeftButtonUp")
mb:RegisterForDrag("LeftButton")
mb:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local bg = mb:CreateTexture(nil, "BACKGROUND")
bg:SetSize(20, 20)
bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
bg:SetPoint("TOPLEFT", 7, -5)

local icon = mb:CreateTexture(nil, "ARTWORK")
icon:SetSize(17, 17)
icon:SetTexture(ICON_PATH .. "Ability_Hunter_BeastTraining")
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
icon:SetPoint("TOPLEFT", 7, -6)

local border = mb:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetPoint("TOPLEFT")

local function PlaceButton()
  local a = math.rad(PetAbilityMapCharDB.minimapAngle or 200)
  local r = (Minimap:GetWidth() / 2) + 10
  mb:ClearAllPoints()
  mb:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function ns.UpdateMinimapButton()
  PlaceButton()
  setShown(mb, not PetAbilityMapCharDB.hideMinimap)
end

mb:SetScript("OnClick", ns.ToggleUI)
mb:SetScript("OnDragStart", function(self)
  self:SetScript("OnUpdate", function()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    PetAbilityMapCharDB.minimapAngle = math.deg((math.atan2 or math.atan)(cy - my, cx - mx))
    PlaceButton()
  end)
end)
mb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mb:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("Pet Abilities")
  GameTooltip:AddLine("Click to open. Drag to move.", 1, 1, 1)
  GameTooltip:AddLine("/petab minimap to hide/show this button.", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end)
mb:SetScript("OnLeave", function() GameTooltip:Hide() end)
mb:Hide()

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() ns.UpdateMinimapButton() end)
