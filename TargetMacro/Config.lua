-- TargetMacro settings window (minimap button or /tmacro config): choose
-- what goes into the macros this addon creates, with a live preview.
local _, ns = ...
local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil

-- Options, in the order their lines appear in the macro.
local OPTIONS = {
  { "keepEnemy", "Keep my current enemy target",
    "If you already have a living enemy targeted, the macro does nothing (won't switch or re-mark).\n/stopmacro [@target,harm,nodead]" },
  { "clearFirst", "Clear target first",
    "Start from no target, so if the creature isn't found you end up with nothing targeted.\n/cleartarget" },
  { "exact", "Exact name match",
    "On: /targetexact (only that exact name). Off: /target (also matches names that start with it)." },
  { "skipDead", "Ignore dead creatures",
    "Drop the target if the match is a corpse.\n/cleartarget [dead]" },
  { "hostileOnly", "Only attackable creatures",
    "Drop the target if it can't be attacked (friendly or neutral NPCs, players of your faction).\n/cleartarget [noharm]" },
  { "restoreLast", "Go back to previous target if not found",
    "If nothing ends up targeted, return to what you had before. Works best with 'Clear target first'.\n/targetlasttarget [noexists]" },
  { "mark", "Put a raid marker on it",
    "Mark the target with the marker chosen below. Pressing again on an already-marked target removes the marker.\n/tm" },
  { "markSoloOnly", "  ...only when not in a group",
    "Skip marking in a party or raid (avoids the 'too many markers' warning).\n[nogroup]" },
  { "setFocus", "Also set it as focus", "/focus [exists]" },
  { "petAttack", "Send pet to attack", "/petattack [@target,harm,nodead]" },
  { "startAttack", "Start melee auto attack", "/startattack [harm,nodead]" },
  { "autoShot", "Start Auto Shot (hunters)", "/cast [harm,nodead] !Auto Shot" },
}

local function SetOpt(key, value)
  TargetMacroDB.options[key] = value
end

-- Window -------------------------------------------------------------------
local win = CreateFrame("Frame", "TargetMacroConfig", UIParent, backdropTemplate)
win:SetSize(380, 560)
win:SetPoint("CENTER")
win:SetBackdrop({
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 24,
  insets = { left = 6, right = 6, top = 6, bottom = 6 },
})
win:SetMovable(true); win:EnableMouse(true); win:SetClampedToScreen(true)
win:SetFrameStrata("DIALOG")
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
win:Hide()
tinsert(UISpecialFrames, "TargetMacroConfig")

local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", 0, -12)
title:SetText("Target Macro Settings")
local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -2, -2)

local preview, count, updateBtn
local checks = {}
local markerButtons = {}

local function Refresh()
  for key, cb in pairs(checks) do cb:SetChecked(ns.Opt(key) and true or false) end
  local markOn = ns.Opt("mark")
  checks.markSoloOnly:SetEnabled(markOn)
  for i, b in ipairs(markerButtons) do
    b:SetAlpha(markOn and 1 or 0.4)
    if ns.Opt("marker") == i then b.sel:Show() else b.sel:Hide() end
  end
  local body = ns.BuildBody("Hogger")
  preview:SetText(body)
  local n = #body
  count:SetText(("%d / 255 characters with a 6-letter name"):format(n))
  count:SetTextColor(n > 230 and 1 or 0.6, n > 230 and 0.3 or 0.6, n > 230 and 0.3 or 0.6)
  updateBtn:SetText(("Update my macros (%d)"):format(ns.CountMacros()))
end

local y = -36
for _, o in ipairs(OPTIONS) do
  local key, label, tip = o[1], o[2], o[3]
  local cb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb:SetPoint("TOPLEFT", key == "markSoloOnly" and 32 or 16, y)
  local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  text:SetText(label)
  cb:SetScript("OnClick", function(self) SetOpt(key, self:GetChecked() and true or false); Refresh() end)
  cb:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(label)
    GameTooltip:AddLine(tip, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  checks[key] = cb
  y = y - 24
  if key == "markSoloOnly" then
    -- marker picker
    local lbl = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", 40, y - 6)
    lbl:SetText("Marker:")
    for i = 1, 8 do
      local b = CreateFrame("Button", nil, win)
      b:SetSize(20, 20)
      b:SetPoint("TOPLEFT", 90 + (i - 1) * 24, y - 2)
      local t = b:CreateTexture(nil, "ARTWORK")
      t:SetAllPoints()
      t:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i)
      b.sel = b:CreateTexture(nil, "OVERLAY")
      b.sel:SetPoint("TOPLEFT", -3, 3); b.sel:SetPoint("BOTTOMRIGHT", 3, -3)
      b.sel:SetTexture("Interface\\Buttons\\CheckButtonHilight")
      b.sel:SetBlendMode("ADD")
      b:SetScript("OnClick", function() SetOpt("marker", i); Refresh() end)
      markerButtons[i] = b
    end
    y = y - 28
  end
end

local plabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
plabel:SetPoint("TOPLEFT", 18, y - 6)
plabel:SetText("Preview (for a creature named Hogger):")
local pbox = CreateFrame("Frame", nil, win, backdropTemplate)
pbox:SetPoint("TOPLEFT", 14, y - 22)
pbox:SetPoint("BOTTOMRIGHT", -14, 62)
pbox:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
pbox:SetBackdropColor(0, 0, 0, 0.6)
preview = pbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
preview:SetPoint("TOPLEFT", 8, -8); preview:SetPoint("BOTTOMRIGHT", -8, 8)
preview:SetJustifyH("LEFT"); preview:SetJustifyV("TOP")
count = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
count:SetPoint("BOTTOMLEFT", 18, 44)

updateBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
updateBtn:SetSize(170, 22)
updateBtn:SetPoint("BOTTOMLEFT", 14, 14)
updateBtn:SetScript("OnClick", function() ns.UpdateAll(); Refresh() end)
updateBtn:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:AddLine("Rewrite every macro this addon made using the settings above.", 1, 1, 1, true)
  GameTooltip:Show()
end)
updateBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local resetBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
resetBtn:SetSize(120, 22)
resetBtn:SetPoint("BOTTOMRIGHT", -14, 14)
resetBtn:SetText("Reset to defaults")
resetBtn:SetScript("OnClick", function() wipe(TargetMacroDB.options); Refresh() end)

win:SetScript("OnShow", Refresh)
function ns.ToggleConfig() if win:IsShown() then win:Hide() else win:Show() end end

-- Minimap button -----------------------------------------------------------
local mb = CreateFrame("Button", "TargetMacroMinimapButton", Minimap)
mb:SetSize(31, 31)
mb:SetFrameStrata("MEDIUM")
mb:SetFrameLevel(8)
mb:RegisterForClicks("LeftButtonUp")
mb:RegisterForDrag("LeftButton")
mb:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local bg = mb:CreateTexture(nil, "BACKGROUND")
bg:SetSize(20, 20); bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background"); bg:SetPoint("TOPLEFT", 7, -5)
local icon = mb:CreateTexture(nil, "ARTWORK")
icon:SetSize(17, 17); icon:SetTexture("Interface\\Icons\\Ability_Hunter_SniperShot")
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95); icon:SetPoint("TOPLEFT", 7, -6)
local border = mb:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); border:SetPoint("TOPLEFT")

local function PlaceButton()
  local a = math.rad(TargetMacroDB.minimapAngle or 120)
  local r = (Minimap:GetWidth() / 2) + 10
  mb:ClearAllPoints()
  mb:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end
mb:SetScript("OnClick", ns.ToggleConfig)
mb:SetScript("OnDragStart", function(self)
  self:SetScript("OnUpdate", function()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local s = Minimap:GetEffectiveScale()
    TargetMacroDB.minimapAngle = math.deg((math.atan2 or math.atan)(cy / s - my, cx / s - mx))
    PlaceButton()
  end)
end)
mb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mb:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("Target Macro")
  GameTooltip:AddLine("Click for macro settings. Drag to move.", 1, 1, 1)
  GameTooltip:AddLine("/tmacro minimap to hide/show this button.", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end)
mb:SetScript("OnLeave", function() GameTooltip:Hide() end)
mb:Hide()

function ns.UpdateMinimapButton()
  PlaceButton()
  if TargetMacroDB.hideMinimap then mb:Hide() else mb:Show() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", ns.UpdateMinimapButton)
