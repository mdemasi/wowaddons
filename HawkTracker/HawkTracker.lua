-- HawkTracker: tracks hawks from "Summon Hawk"
local SPELL = "Summon Hawk"
local SPELL_ID = 1293241
local MAX_HAWKS = 2
local DEFAULT_DURATION = 18
local DEFAULT_WARN = 3

local hawks = {}          -- list of {guid=, expires=, warned=}

-- UI ---------------------------------------------------------------
local WIDTH, BAR_H, GAP = 180, 18, 3

local f = CreateFrame("Frame", "HawkTrackerFrame", UIParent)
f:SetSize(WIDTH, 20)
f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
f:SetMovable(true); f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", function(s) if not HawkTrackerDB.locked then s:StartMoving() end end)
f:SetScript("OnDragStop", function(s)
  s:StopMovingOrSizing()
  local p, _, rp, x, y = s:GetPoint()
  HawkTrackerDB.pos = { p, rp, x, y }
end)

local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", 0, 0)

local bars = {}
local function GetBar(i)
  if bars[i] then return bars[i] end
  local b = CreateFrame("StatusBar", nil, f)
  b:SetSize(WIDTH, BAR_H)
  b:SetPoint("TOPLEFT", 0, -16 - (i - 1) * (BAR_H + GAP))
  b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  b:SetMinMaxValues(0, 1)
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.6)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.label:SetPoint("LEFT", 4, 0)
  b.time = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.time:SetPoint("RIGHT", -4, 0)
  bars[i] = b
  return b
end

local function Refresh()
  local now = GetTime()
  for i = #hawks, 1, -1 do
    if hawks[i].expires <= now then table.remove(hawks, i) end
  end
  table.sort(hawks, function(a, b) return a.expires < b.expires end)
  title:SetText("Hawks: " .. #hawks .. "/" .. MAX_HAWKS)

  local dur, warn = HawkTrackerDB.duration, HawkTrackerDB.warn
  for i, h in ipairs(hawks) do
    local left = h.expires - now
    local b = GetBar(i)
    b:SetMinMaxValues(0, dur)
    b:SetValue(left)
    b.label:SetText("Hawk " .. i)
    b.time:SetText(string.format("%.1f", left))
    if left <= warn then b:SetStatusBarColor(0.9, 0.2, 0.2) else b:SetStatusBarColor(0.2, 0.7, 1) end
    b:Show()
    if not h.warned and left <= warn then
      h.warned = true
      if HawkTrackerDB.sound then PlaySound((SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master") end
    end
  end
  for i = #hawks + 1, #bars do bars[i]:Hide() end
  f:SetHeight(16 + #hawks * (BAR_H + GAP))
  if #hawks == 0 and HawkTrackerDB.hideEmpty then f:Hide() else f:Show() end
end

local function AddHawk(guid)
  if #hawks >= MAX_HAWKS then table.remove(hawks, 1) end -- oldest is replaced
  table.insert(hawks, { guid = guid, expires = GetTime() + HawkTrackerDB.duration })
  Refresh()
end

local function RemoveHawk(guid)
  for i = #hawks, 1, -1 do
    if hawks[i].guid == guid then table.remove(hawks, i); Refresh(); return end
  end
end

-- Timer (separate frame so it keeps running while the display is hidden)
local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(_, el)
  acc = acc + el
  if acc < 0.05 then return end
  acc = 0
  if #hawks > 0 then Refresh() end
end)

-- Events -----------------------------------------------------------
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
f:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" and ... == "HawkTracker" then
    HawkTrackerDB = HawkTrackerDB or {}
    local db = HawkTrackerDB
    db.duration = db.duration or DEFAULT_DURATION
    db.warn = db.warn or DEFAULT_WARN
    if db.sound == nil then db.sound = true end
    if db.pos then f:ClearAllPoints(); f:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4]) end
  elseif event == "PLAYER_LOGIN" then
    Refresh()
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local unit, _, spellId = ...
    if unit ~= "player" then return end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellId)
    if spellId == SPELL_ID or name == SPELL then AddHawk(nil) end
  end
end)

-- Slash commands ---------------------------------------------------
SLASH_HAWKTRACKER1 = "/hawks"
SlashCmdList["HAWKTRACKER"] = function(msg)
  local db = HawkTrackerDB
  local cmd, arg = string.match(msg or "", "^(%S*)%s*(.-)$")
  cmd = string.lower(cmd or "")
  if cmd == "duration" and tonumber(arg) then
    db.duration = tonumber(arg); print("HawkTracker: duration " .. arg .. "s")
  elseif cmd == "warn" and tonumber(arg) then
    db.warn = tonumber(arg); print("HawkTracker: warning at " .. arg .. "s left")
  elseif cmd == "sound" then
    db.sound = not db.sound; print("HawkTracker: sound " .. (db.sound and "on" or "off"))
  elseif cmd == "lock" then
    db.locked = not db.locked; print("HawkTracker: " .. (db.locked and "locked" or "unlocked"))
  elseif cmd == "hide" then
    db.hideEmpty = not db.hideEmpty
    print("HawkTracker: hide when empty " .. (db.hideEmpty and "on" or "off")); Refresh()
  elseif cmd == "reset" then
    wipe(hawks); Refresh()
  elseif cmd == "test" then
    AddHawk(nil)
  else
    print("HawkTracker: /hawks duration <s> | warn <s> | sound | lock | hide | reset | test")
    print(string.format("Duration %ss, warn at %ss, sound %s", db.duration, db.warn, db.sound and "on" or "off"))
  end
end
