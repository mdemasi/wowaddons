-- QuestZones: where are my unfinished quest objectives?
--  * % split of objectives by continent
--  * zones ranked by how much of your quest log you can progress there
-- Turn-ins are ignored; quests ready to turn in are left out.
local DATA = QuestZonesData
local WIDTH = 300

local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
local function setShown(f, show) if show then f:Show() else f:Hide() end end
local function Msg(t) print("|cff33ff99QuestZones|r: " .. t) end

-- Map helpers --------------------------------------------------------------
local mapNames, continentOf = {}, {}
local CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2

local function MapName(id)
  if mapNames[id] == nil then
    local info = C_Map and C_Map.GetMapInfo(id)
    mapNames[id] = info and info.name or ("Map " .. id)
  end
  return mapNames[id]
end

local function ContinentName(id)
  if continentOf[id] == nil then
    local name, cur, guard = "Other", id, 0
    while cur and cur > 0 and guard < 10 do
      local info = C_Map.GetMapInfo(cur)
      if not info then break end
      if info.mapType == CONTINENT then name = info.name; break end
      cur, guard = info.parentMapID, guard + 1
    end
    continentOf[id] = name
  end
  return continentOf[id]
end

-- Quest log ------------------------------------------------------------------
-- Returns list of { id, title, remaining } for quests not yet ready to turn in.
local function ActiveQuests()
  local list = {}
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local info = C_QuestLog.GetInfo(i)
      if info and not info.isHeader and not info.isHidden and info.questID and info.questID > 0 then
        local id = info.questID
        if not C_QuestLog.IsComplete(id) then
          local remaining = 0
          for _, o in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
            if not o.finished then remaining = remaining + 1 end
          end
          list[#list + 1] = { id = id, title = info.title, remaining = math.max(remaining, 1) }
        end
      end
    end
  elseif GetNumQuestLogEntries then
    for i = 1, GetNumQuestLogEntries() do
      local title, _, _, isHeader, _, isComplete, _, id = GetQuestLogTitle(i)
      if not isHeader and id and isComplete ~= 1 then
        local remaining = 0
        for j = 1, (GetNumQuestLeaderBoards(i) or 0) do
          local _, _, done = GetQuestLogLeaderBoard(j, i)
          if not done then remaining = remaining + 1 end
        end
        list[#list + 1] = { id = id, title = title, remaining = math.max(remaining, 1) }
      end
    end
  end
  return list
end

-- Each unfinished objective is worth 1, split across the zones where the
-- quest's objectives are done.
local result
local function Compute()
  local zones, continents, total = {}, {}, 0
  local unknown, counted = {}, 0
  for _, q in ipairs(ActiveQuests()) do
    local d = DATA[q.id]
    if d then
      counted = counted + 1
      for i = 1, #d, 2 do
        local ui, w = d[i], d[i + 1] / 1000 * q.remaining
        local z = zones[ui]
        if not z then z = { id = ui, weight = 0, quests = {} }; zones[ui] = z end
        z.weight = z.weight + w
        z.quests[#z.quests + 1] = { title = q.title, weight = w }
        local c = ContinentName(ui)
        continents[c] = (continents[c] or 0) + w
        total = total + w
      end
    else
      unknown[#unknown + 1] = q.title
    end
  end
  local zl, cl = {}, {}
  for _, z in pairs(zones) do zl[#zl + 1] = z end
  table.sort(zl, function(a, b) return a.weight > b.weight end)
  for name, w in pairs(continents) do cl[#cl + 1] = { name = name, weight = w } end
  table.sort(cl, function(a, b) return a.weight > b.weight end)
  result = { zones = zl, continents = cl, total = total, counted = counted, unknown = unknown, time = date("%H:%M") }
end

-- Window -------------------------------------------------------------------
local win = CreateFrame("Frame", "QuestZonesWindow", UIParent, backdropTemplate)
win:SetSize(WIDTH + 40, 420)
win:SetPoint("CENTER", 300, 0)
win:SetBackdrop({
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 24,
  insets = { left = 6, right = 6, top = 6, bottom = 6 },
})
win:SetMovable(true); win:SetResizable(true); win:EnableMouse(true); win:SetClampedToScreen(true)
if win.SetResizeBounds then win:SetResizeBounds(240, 200) elseif win.SetMinResize then win:SetMinResize(240, 200) end
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local p, _, rp, x, y = self:GetPoint()
  QuestZonesDB.pos = { p, rp, x, y }
end)
win:Hide()

local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", 0, -12)
title:SetText("Quest Zones")

local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -2, -2)
close:SetScript("OnClick", function() win:Hide(); QuestZonesDB.shown = false end)

local recompute = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
recompute:SetSize(90, 20)
recompute:SetPoint("BOTTOMLEFT", 12, 12)
recompute:SetText("Recompute")

local footer = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
footer:SetPoint("LEFT", recompute, "RIGHT", 8, 0)
footer:SetPoint("RIGHT", win, "RIGHT", -28, 0)
footer:SetJustifyH("LEFT")

local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 12, -32)
scroll:SetPoint("BOTTOMRIGHT", -32, 38)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(WIDTH, 1)
scroll:SetScrollChild(content)
scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)

local grip = CreateFrame("Button", nil, win)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -6, 6)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
grip:SetScript("OnMouseUp", function()
  win:StopMovingOrSizing()
  QuestZonesDB.size = { win:GetWidth(), win:GetHeight() }
end)

-- Row pool: headers and bar rows
local rows, used = {}, 0
local function Row()
  used = used + 1
  local r = rows[used]
  if not r then
    r = CreateFrame("Button", nil, content)
    r:SetHeight(18)
    r.bar = r:CreateTexture(nil, "BACKGROUND")
    r.bar:SetPoint("TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT")
    r.bar:SetColorTexture(0.2, 0.5, 1, 0.35)
    r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.left:SetPoint("LEFT", 4, 0)
    r.left:SetPoint("RIGHT", -60, 0)
    r.left:SetJustifyH("LEFT")
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", -4, 0)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[used] = r
  end
  r:SetScript("OnEnter", nil)
  r.bar:Hide(); r.right:SetText("")
  r.left:SetFontObject("GameFontHighlightSmall")
  r:Show()
  return r
end

local function ZoneTooltip(self)
  local z = self.zone
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(MapName(z.id) .. "  (" .. ContinentName(z.id) .. ")")
  table.sort(z.quests, function(a, b) return a.weight > b.weight end)
  for _, q in ipairs(z.quests) do
    GameTooltip:AddDoubleLine(q.title, ("%.1f"):format(q.weight), 1, 1, 1, 0.6, 0.8, 1)
  end
  GameTooltip:AddLine("Numbers are unfinished objectives you can work on here.", 0.6, 0.6, 0.6, true)
  GameTooltip:Show()
end

local function Render()
  if not result then Compute() end
  for _, r in ipairs(rows) do r:Hide() end
  used = 0
  local y = 0
  local width = content:GetWidth()
  local function place(r, h) r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("TOPRIGHT", 0, -y); y = y + (h or 18) end
  local function header(text)
    local r = Row(); r.left:SetFontObject("GameFontNormal"); r.left:SetText(text); place(r, 22)
  end
  local function bar(r, frac)
    r.bar:SetWidth(math.max(1, width * frac)); r.bar:Show()
  end

  header("Objectives by continent")
  if result.total == 0 then
    local r = Row(); r.left:SetText("|cff808080No unfinished objectives with known locations.|r"); place(r)
  end
  for _, c in ipairs(result.continents) do
    local r = Row()
    local frac = c.weight / result.total
    r.left:SetText(c.name); r.right:SetText(("%d%%"):format(frac * 100 + 0.5)); bar(r, frac); place(r)
  end

  y = y + 8
  header("Best zones for your quest log")
  local top = result.zones[1] and result.zones[1].weight or 1
  for i, z in ipairs(result.zones) do
    local r = Row()
    r.left:SetText(("%d. %s |cff808080(%d quest%s)|r"):format(i, MapName(z.id), #z.quests, #z.quests == 1 and "" or "s"))
    r.right:SetText(("%d%%"):format(z.weight / result.total * 100 + 0.5))
    bar(r, z.weight / top)
    r.zone = z
    r:SetScript("OnEnter", ZoneTooltip)
    place(r)
  end
  content:SetHeight(y)
  footer:SetText(("%d quests counted, updated %s%s"):format(result.counted, result.time,
    #result.unknown > 0 and (" |cff808080(" .. #result.unknown .. " without location data)|r") or ""))
end

local function Recompute() Compute(); if win:IsShown() then Render() end end
recompute:SetScript("OnClick", Recompute)
win:SetScript("OnShow", function()
  local s = QuestZonesDB.size
  if s then win:SetSize(s[1], s[2]) end
  Recompute()
end)
footer:SetScript("OnEnter", nil)

-- Footer hover: list quests without data
local footerHit = CreateFrame("Frame", nil, win)
footerHit:SetAllPoints(footer)
footerHit:EnableMouse(true)
footerHit:SetScript("OnEnter", function(self)
  if not result or #result.unknown == 0 then return end
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:AddLine("No objective location data:")
  for _, t in ipairs(result.unknown) do GameTooltip:AddLine(t, 1, 1, 1) end
  GameTooltip:AddLine("Usually talk-to or delivery quests.", 0.6, 0.6, 0.6, true)
  GameTooltip:Show()
end)
footerHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function Toggle()
  setShown(win, not win:IsShown())
  QuestZonesDB.shown = win:IsShown()
end

-- Minimap button -----------------------------------------------------------
local mb = CreateFrame("Button", "QuestZonesMinimapButton", Minimap)
mb:SetSize(31, 31)
mb:SetFrameStrata("MEDIUM")
mb:SetFrameLevel(8)
mb:RegisterForClicks("LeftButtonUp")
mb:RegisterForDrag("LeftButton")
mb:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local mbg = mb:CreateTexture(nil, "BACKGROUND")
mbg:SetSize(20, 20); mbg:SetTexture("Interface\\Minimap\\UI-Minimap-Background"); mbg:SetPoint("TOPLEFT", 7, -5)
local micon = mb:CreateTexture(nil, "ARTWORK")
micon:SetSize(17, 17); micon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
micon:SetTexCoord(0.05, 0.95, 0.05, 0.95); micon:SetPoint("TOPLEFT", 7, -6)
local mborder = mb:CreateTexture(nil, "OVERLAY")
mborder:SetSize(53, 53); mborder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); mborder:SetPoint("TOPLEFT")

local function PlaceButton()
  local a = math.rad(QuestZonesDB.minimapAngle or 160)
  local r = (Minimap:GetWidth() / 2) + 10
  mb:ClearAllPoints()
  mb:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end
mb:SetScript("OnClick", Toggle)
mb:SetScript("OnDragStart", function(self)
  self:SetScript("OnUpdate", function()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local s = Minimap:GetEffectiveScale()
    QuestZonesDB.minimapAngle = math.deg((math.atan2 or math.atan)(cy / s - my, cx / s - mx))
    PlaceButton()
  end)
end)
mb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mb:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("Quest Zones")
  GameTooltip:AddLine("Click to open. Drag to move.", 1, 1, 1)
  GameTooltip:AddLine("/qz minimap to hide/show this button.", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end)
mb:SetScript("OnLeave", function() GameTooltip:Hide() end)
mb:Hide()

-- Events -------------------------------------------------------------------
-- Recompute on turn-in, accept and abandon; objective progress is batched.
local pending = false
local function Soon()
  if pending then return end
  pending = true
  C_Timer.After(0.5, function() pending = false; Recompute() end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_LOG_UPDATE" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == "QuestZones" then QuestZonesDB = QuestZonesDB or {} end
  elseif event == "PLAYER_LOGIN" then
    local p = QuestZonesDB.pos
    if p then win:ClearAllPoints(); win:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end
    PlaceButton(); setShown(mb, not QuestZonesDB.hideMinimap)
    if QuestZonesDB.shown then win:Show() end
  else
    Soon()
  end
end)

SLASH_QUESTZONES1 = "/qz"
SLASH_QUESTZONES2 = "/questzones"
SlashCmdList.QUESTZONES = function(msg)
  msg = strtrim((msg or ""):lower())
  if msg == "minimap" then
    QuestZonesDB.hideMinimap = not QuestZonesDB.hideMinimap
    setShown(mb, not QuestZonesDB.hideMinimap)
  elseif msg == "recompute" then
    Recompute(); Msg("recomputed.")
  else
    Toggle()
  end
end
