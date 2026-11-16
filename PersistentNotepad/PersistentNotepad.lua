-- compatibility helpers for older/custom clients
local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
local function setShown(frame, show) if show then frame:Show() else frame:Hide() end end

local f = CreateFrame("Frame", "PersistentNotepadFrame", UIParent, backdropTemplate)
f:SetSize(400, 300)
f:SetPoint("CENTER")
f:SetBackdrop({
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 24,
  insets = { left = 6, right = 6, top = 6, bottom = 6 },
})
f:SetMovable(true); f:SetResizable(true); f:EnableMouse(true)
f:SetClampedToScreen(true); f:SetFrameStrata("DIALOG")
if f.SetResizeBounds then f:SetResizeBounds(200, 120) elseif f.SetMinResize then f:SetMinResize(200, 120) end
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:Hide()
tinsert(UISpecialFrames, "PersistentNotepadFrame") -- Esc closes it

local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", 0, -12)
title:SetText("Notepad")

local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -2, -2)

local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 14, -32)
scroll:SetPoint("BOTTOMRIGHT", -32, 16)

local edit = CreateFrame("EditBox", nil, scroll)
edit:SetMultiLine(true)
edit:SetAutoFocus(false)
edit:SetFontObject(ChatFontNormal)
edit:SetWidth(scroll:GetWidth())
edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
edit:SetScript("OnTextChanged", function(self)
  PersistentNotepadDB.text = self:GetText()
end)
scroll:SetScrollChild(edit)
scroll:SetScript("OnSizeChanged", function(_, w) edit:SetWidth(w) end)
scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)

-- resize grip
local grip = CreateFrame("Button", nil, f)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -6, 6)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
  if name ~= "PersistentNotepad" then return end
  PersistentNotepadDB = PersistentNotepadDB or { text = "" }
  PersistentNotepadDB.minimapAngle = PersistentNotepadDB.minimapAngle or 225
  edit:SetText(PersistentNotepadDB.text or "")
  PersistentNotepad_UpdateMinimapButton()
end)

SLASH_PERSISTENTNOTEPAD1 = "/notepad"
SLASH_PERSISTENTNOTEPAD2 = "/np"
SlashCmdList.PERSISTENTNOTEPAD = function(msg)
  if msg and msg:lower():match("^%s*minimap") then
    PersistentNotepadDB.hideMinimap = not PersistentNotepadDB.hideMinimap
    PersistentNotepad_UpdateMinimapButton()
    return
  end
  setShown(f, not f:IsShown())
end

-- Minimap button
local mb = CreateFrame("Button", "PersistentNotepadMinimapButton", Minimap)
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
icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
icon:SetPoint("TOPLEFT", 7, -6)

local border = mb:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetPoint("TOPLEFT")

local function placeButton()
  local a = math.rad(PersistentNotepadDB.minimapAngle or 225)
  local r = (Minimap:GetWidth() / 2) + 10
  mb:ClearAllPoints()
  mb:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function PersistentNotepad_UpdateMinimapButton()
  placeButton()
  setShown(mb, not PersistentNotepadDB.hideMinimap)
end

mb:SetScript("OnClick", function() setShown(f, not f:IsShown()) end)
mb:SetScript("OnDragStart", function(self)
  self:SetScript("OnUpdate", function()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    PersistentNotepadDB.minimapAngle = math.deg((math.atan2 or math.atan)(cy - my, cx - mx))
    placeButton()
  end)
end)
mb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mb:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("Notepad")
  GameTooltip:AddLine("Click to open. Drag to move.", 1, 1, 1)
  GameTooltip:AddLine("/np minimap to hide/show this button.", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end)
mb:SetScript("OnLeave", function() GameTooltip:Hide() end)
