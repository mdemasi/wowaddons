-- QuestZones: where are my unfinished quest objectives?
--  * % split of objectives by continent
--  * zones ranked by how much of your quest log you can progress there
--  * top zones to pick up your next quests (available, at/slightly below your level)
-- Turn-ins are ignored; quests ready to turn in are left out.
local DATA = QuestZonesData
local INFO = QuestZonesInfo
local FAVOR = 1.5      -- weight multiplier for yellow and green quests
local BELOW = 5        -- recommender: quests from (your level - BELOW) up to your level
local TOP_PICKS = 6
local DUNGEON = (Enum and Enum.UIMapType and Enum.UIMapType.Dungeon) or 4
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

local isInstance = {}
local function IsInstance(id)
  if isInstance[id] == nil then
    local info = C_Map and C_Map.GetMapInfo(id)
    isInstance[id] = info and info.mapType == DUNGEON or false
  end
  return isInstance[id]
end

-- A quest's zones as { uiMapID, share, ... } honoring the dungeon/raid toggle:
-- when off, quests done mostly inside instances are dropped and instance
-- zones are removed from the rest.
local function QuestZoneList(id)
  local d = DATA[id]
  if not d or QuestZonesDB.includeInstances then return d end
  local inside = 0
  for i = 1, #d, 2 do if IsInstance(d[i]) then inside = inside + d[i + 1] end end
  if inside == 0 then return d end
  if inside >= 500 then return nil, true end
  local out = {}
  for i = 1, #d, 2 do
    if not IsInstance(d[i]) then out[#out + 1] = d[i]; out[#out + 1] = d[i + 1] end
  end
  return out
end

-- Quest difficulty -----------------------------------------------------------
local function GreenRange(level)
  if UnitQuestTrivialLevelRange then return UnitQuestTrivialLevelRange("player") end
  if GetQuestGreenRange then return GetQuestGreenRange() end
  if level <= 5 then return 5 elseif level <= 39 then return math.floor(level / 10) + 5 end
  return math.floor(level / 5) + 1
end

-- "red", "orange", "yellow", "green" or "grey" for a quest level
local function Difficulty(qlevel)
  local p = UnitLevel("player")
  if not qlevel or qlevel <= 0 then qlevel = p end
  local d = qlevel - p
  if d >= 5 then return "red" elseif d >= 3 then return "orange" elseif d >= -2 then return "yellow"
  elseif -d <= GreenRange(p) then return "green" end
  return "grey"
end
local COLORS = { red = "ff2020", orange = "ff8040", yellow = "ffff00", green = "40c040", grey = "808080" }

-- Quest log ------------------------------------------------------------------
-- Returns list of { id, title, remaining } for quests not yet ready to turn in.
local inLog = {}
local function ActiveQuests()
  local list = {}
  wipe(inLog)
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local info = C_QuestLog.GetInfo(i)
      if info and not info.isHeader and not info.isHidden and info.questID and info.questID > 0 then
        local id = info.questID
        inLog[id] = true
        if not C_QuestLog.IsComplete(id) then
          local remaining = 0
          for _, o in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
            if not o.finished then remaining = remaining + 1 end
          end
          list[#list + 1] = { id = id, title = info.title, level = info.level, remaining = math.max(remaining, 1) }
        end
      end
    end
  elseif GetNumQuestLogEntries then
    for i = 1, GetNumQuestLogEntries() do
      local title, qlevel, _, isHeader, _, isComplete, _, id = GetQuestLogTitle(i)
      if id and not isHeader then inLog[id] = true end
      if not isHeader and id and isComplete ~= 1 then
        local remaining = 0
        for j = 1, (GetNumQuestLeaderBoards(i) or 0) do
          local _, _, done = GetQuestLogLeaderBoard(j, i)
          if not done then remaining = remaining + 1 end
        end
        list[#list + 1] = { id = id, title = title, level = qlevel, remaining = math.max(remaining, 1) }
      end
    end
  end
  return list
end

-- Recommender ------------------------------------------------------------------
local function IsDone(id)
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(id) end
  return IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(id)
end
local function HasBit(mask, n) return mask == 0 or math.floor(mask / 2 ^ n) % 2 == 1 end

-- Quests you can pick up now at or slightly below your level, grouped by
-- the zones where their objectives are.
local function Recommend()
  local p = UnitLevel("player")
  local race = select(3, UnitRace("player")) or 0
  local class = select(3, UnitClass("player")) or 0
  local zones = {}
  for id, q in pairs(INFO) do
    local lvl = q[2] > 0 and q[2] or p
    if lvl <= p and lvl >= p - BELOW and q[3] <= p and not inLog[id]
        and HasBit(q[4], race - 1) and HasBit(q[5], class - 1) and not IsDone(id) then
      local ok = true
      if #q[7] > 0 then -- any one of these first
        ok = false
        for _, pre in ipairs(q[7]) do if IsDone(pre) then ok = true; break end end
      end
      for _, pre in ipairs(q[8]) do if not IsDone(pre) then ok = false; break end end
      for _, ex in ipairs(q[9]) do if IsDone(ex) or inLog[ex] then ok = false; break end end
      local d = ok and QuestZoneList(id)
      if d then
        -- quests from the same chain count once per zone (largest share wins)
        local chain = q[10] or id
        for i = 1, #d, 2 do
          local ui = d[i]
          local z = zones[ui]
          if not z then z = { id = ui, chains = {} }; zones[ui] = z end
          local c = z.chains[chain]
          if not c then c = { share = 0, quests = {} }; z.chains[chain] = c end
          c.share = math.max(c.share, d[i + 1] / 1000)
          c.quests[#c.quests + 1] = { title = q[1], level = lvl, start = q[6] }
        end
      end
    end
  end
  local list = {}
  for _, z in pairs(zones) do
    z.weight, z.quests = 0, {}
    for _, c in pairs(z.chains) do
      z.weight = z.weight + c.share
      table.sort(c.quests, function(a, b) return a.level < b.level end)
      local first = c.quests[1]
      local title = first.title
      if #c.quests > 1 then title = title .. " |cff808080(+" .. (#c.quests - 1) .. " in chain)|r" end
      z.quests[#z.quests + 1] = { title = title, level = first.level, start = first.start }
    end
    list[#list + 1] = z
  end
  table.sort(list, function(a, b) return a.weight > b.weight end)
  for i = #list, TOP_PICKS + 1, -1 do list[i] = nil end
  return list, math.max(1, p - BELOW), p
end

-- Each unfinished objective is worth 1, split across the zones where the
-- quest's objectives are done.
local result
local function Compute()
  local zones, continents, total = {}, {}, 0
  local unknown, counted = {}, 0
  local skipped = 0
  for _, q in ipairs(ActiveQuests()) do
    local d, instanceOnly = QuestZoneList(q.id)
    if instanceOnly then skipped = skipped + 1 end
    if d then
      counted = counted + 1
      for i = 1, #d, 2 do
        local diff = Difficulty(q.level)
        local favor = (diff == "yellow" or diff == "green") and FAVOR or 1
        local ui, w = d[i], d[i + 1] / 1000 * q.remaining * favor
        local z = zones[ui]
        if not z then z = { id = ui, weight = 0, quests = {} }; zones[ui] = z end
        z.weight = z.weight + w
        z.quests[#z.quests + 1] = { title = q.title, weight = w, diff = diff }
        local c = ContinentName(ui)
        continents[c] = (continents[c] or 0) + w
        total = total + w
      end
    elseif not instanceOnly then
      unknown[#unknown + 1] = q.title
    end
  end
  local zl, cl = {}, {}
  for _, z in pairs(zones) do zl[#zl + 1] = z end
  table.sort(zl, function(a, b) return a.weight > b.weight end)
  for name, w in pairs(continents) do cl[#cl + 1] = { name = name, weight = w } end
  table.sort(cl, function(a, b) return a.weight > b.weight end)
  local picks, lo, hi = Recommend()
  result = { zones = zl, continents = cl, total = total, counted = counted, unknown = unknown, time = date("%H:%M"),
    picks = picks, lo = lo, hi = hi, skipped = skipped }
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

local instToggle = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
instToggle:SetSize(22, 22)
instToggle:SetPoint("TOPLEFT", 12, -28)
local instLabel = instToggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
instLabel:SetPoint("LEFT", instToggle, "RIGHT", 2, 0)
instLabel:SetText("Count dungeon & raid quests")

local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 12, -54)
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
  r.bar:Hide(); r.right:SetText(""); r.bar:SetColorTexture(0.2, 0.5, 1, 0.35)
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
    GameTooltip:AddDoubleLine("|cff" .. COLORS[q.diff or "yellow"] .. q.title .. "|r", ("%.1f"):format(q.weight), 1, 1, 1, 0.6, 0.8, 1)
  end
  GameTooltip:AddLine("Numbers are unfinished objectives you can work on here (yellow and green quests count " .. FAVOR .. "x).", 0.6, 0.6, 0.6, true)
  GameTooltip:Show()
end

local function PickTooltip(self)
  local z = self.zone
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine("Quests to pick up for " .. MapName(z.id))
  table.sort(z.quests, function(a, b) return a.level > b.level end)
  for _, q in ipairs(z.quests) do
    local start = (q.start and q.start > 0) and MapName(q.start) or "?"
    GameTooltip:AddDoubleLine(("|cff%s[%d] %s|r"):format(COLORS[Difficulty(q.level)], q.level, q.title),
      "from " .. start, 1, 1, 1, 0.7, 0.7, 0.7)
  end
  GameTooltip:AddLine("Not done, not in your log, prerequisites met. Each quest chain counts once.", 0.6, 0.6, 0.6, true)
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

  y = y + 8
  header(("Where to pick up quests next (level %d-%d)"):format(result.lo, result.hi))
  if #result.picks == 0 then
    local r = Row(); r.left:SetText("|cff808080Nothing found in that level range.|r"); place(r)
  end
  for i, z in ipairs(result.picks) do
    local r = Row()
    r.left:SetText(("%d. %s"):format(i, MapName(z.id)))
    r.right:SetText(#z.quests == 1 and "1 quest" or (#z.quests .. " quests"))
    bar(r, z.weight / result.picks[1].weight)
    r.bar:SetColorTexture(0.25, 0.75, 0.25, 0.35)
    r.zone = z
    r:SetScript("OnEnter", PickTooltip)
    place(r)
  end
  content:SetHeight(y)
  local notes = {}
  if #result.unknown > 0 then notes[#notes + 1] = #result.unknown .. " without location data" end
  if result.skipped > 0 then notes[#notes + 1] = result.skipped .. " dungeon/raid hidden" end
  footer:SetText(("%d quests counted, updated %s%s"):format(result.counted, result.time,
    #notes > 0 and (" |cff808080(" .. table.concat(notes, ", ") .. ")|r") or ""))
end

local function Recompute() Compute(); if win:IsShown() then Render() end end
recompute:SetScript("OnClick", Recompute)
instToggle:SetScript("OnClick", function(self)
  QuestZonesDB.includeInstances = self:GetChecked() and true or false
  Recompute()
end)
win:SetScript("OnShow", function()
  local s = QuestZonesDB.size
  if s then win:SetSize(s[1], s[2]) end
  instToggle:SetChecked(QuestZonesDB.includeInstances and true or false)
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
for _, e in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP" }) do
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
