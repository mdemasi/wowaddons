-- TargetMacro: right-click target/focus frame -> "Create Target Macro"
local ICON = "Ability_Hunter_SniperShot" -- crosshair icon
local MAX_NAME = 16 -- WoW macro name limit

local function Msg(t) print("|cff33ff99TargetMacro|r: " .. t) end

-- Macro: target the unit by exact name, then put a skull on it only if
-- the target really is that unit (so a failed /targetexact marks nothing).
-- Skips marking if it already has a skull, since setting it again removes it.
local function BuildBody(name)
  local safe = name:gsub('"', ''):lower()
  -- case-insensitive, and matches with or without "-Realm"
  return "/targetexact " .. name .. "\n" ..
    '/run local t,n="target","' .. safe .. '" if UnitExists(t) and (GetUnitName(t,true):lower()==n' ..
    ' or UnitName(t):lower()==n) and GetRaidTargetIndex(t)~=8 then SetRaidTarget(t,8) end'
end

local function MakeMacro(unit, name)
  if InCombatLockdown() then Msg("can't create macros in combat."); return end
  if not name then
    unit = unit or "target"
    if not UnitExists(unit) then Msg("no " .. unit .. "."); return end
    name = GetUnitName(unit, true) -- includes realm for other-realm players
  end
  local body = BuildBody(name)
  if #body > 255 then Msg("name too long for a macro."); return end
  local macroName = name:sub(1, MAX_NAME)

  local index = GetMacroIndexByName(macroName)
  if index and index > 0 then
    EditMacro(index, macroName, ICON, body)
  else
    local numAccount, numChar = GetNumMacros()
    local maxAccount = MAX_ACCOUNT_MACROS or 120
    local maxChar = MAX_CHARACTER_MACROS or 18
    if numAccount < maxAccount then
      index = CreateMacro(macroName, ICON, body, false)
    elseif numChar < maxChar then
      index = CreateMacro(macroName, ICON, body, true)
    else
      Msg("your macro slots are full."); return
    end
  end

  if index and index > 0 then
    PickupMacro(index)
    Msg("macro for " .. name .. " is on your cursor. Drop it on an action bar.")
  end
end

-- Work out which unit a menu belongs to: the menu's own data first,
-- otherwise which frame it was opened from.
local function MenuUnit(owner, contextData)
  local unit = contextData and contextData.unit
  if unit == "target" or unit == "focus" then return unit end
  local frame = owner
  while frame do
    if frame == TargetFrame then return "target" end
    if FocusFrame and frame == FocusFrame then return "focus" end
    frame = frame.GetParent and frame:GetParent()
  end
end

local debug = false

-- Modern menus: hook every unit menu type the target/focus frame might use.
if Menu and Menu.ModifyMenu then
  local tags = { "TARGET", "FOCUS", "SELF", "PLAYER", "ENEMY_PLAYER", "PARTY",
    "RAID_PLAYER", "RAID", "FRIEND", "PET", "OTHERPET", "BOSS", "VEHICLE",
    "ARENAENEMY", "RAID_TARGET_ICON" }
  for _, tag in ipairs(tags) do
    Menu.ModifyMenu("MENU_UNIT_" .. tag, function(owner, root, contextData)
      local unit = MenuUnit(owner, contextData)
      if debug then
        Msg(("menu %s, unit=%s, owner=%s"):format(tag, tostring(contextData and contextData.unit),
          tostring(owner and owner.GetName and owner:GetName())))
      end
      if not unit then return end
      root:CreateDivider()
      root:CreateButton("Create Target Macro", function() MakeMacro(unit) end)
    end)
  end
end

-- Older dropdown menus (UIDropDownMenu based)
if UnitPopup_ShowMenu and UIDropDownMenu_AddButton then
  hooksecurefunc("UnitPopup_ShowMenu", function(dropdown, which, unit)
    if debug then Msg(("old menu %s, unit=%s"):format(tostring(which), tostring(unit))) end
    if UIDROPDOWNMENU_MENU_LEVEL and UIDROPDOWNMENU_MENU_LEVEL > 1 then return end
    if unit ~= "target" and unit ~= "focus" then return end
    local info = UIDropDownMenu_CreateInfo()
    info.text = "Create Target Macro"
    info.notCheckable = true
    info.func = function() MakeMacro(unit) end
    UIDropDownMenu_AddButton(info)
  end)
end

-- Debug: report every unit menu that opens, to find the one WoW Forever uses.
if UnitPopup_OpenMenu then
  hooksecurefunc("UnitPopup_OpenMenu", function(which, contextData)
    if debug then Msg(("opened %s, unit=%s"):format(tostring(which), tostring(contextData and contextData.unit))) end
  end)
end

-- /tmacro            -> current target
-- /tmacro focus      -> current focus
-- /tmacro <name>     -> macro for that name (doesn't need to be targeted)
SLASH_TARGETMACRO1 = "/tmacro"
SlashCmdList.TARGETMACRO = function(msg)
  msg = strtrim(msg or "")
  local lower = msg:lower()
  if lower == "debug" then
    debug = not debug
    Msg("debug " .. (debug and "on: right-click your target frame and send me what prints." or "off"))
    if debug then
      Msg(("Menu.ModifyMenu=%s UnitPopup_ShowMenu=%s UnitPopup_OpenMenu=%s"):format(
        tostring(Menu and Menu.ModifyMenu ~= nil), tostring(UnitPopup_ShowMenu ~= nil), tostring(UnitPopup_OpenMenu ~= nil)))
    end
  elseif lower == "" or lower == "target" then MakeMacro("target")
  elseif lower == "focus" then MakeMacro("focus")
  else MakeMacro(nil, msg) end
end
