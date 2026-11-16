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

-- Add the option to the target and focus right-click menus
if Menu and Menu.ModifyMenu then
  -- The target/focus frame uses different menus depending on who you target
  -- (NPC, friendly/enemy player, party/raid member), so hook them all and
  -- only add the button when the menu was opened from the target or focus frame.
  local tags = { "TARGET", "FOCUS", "PLAYER", "ENEMY_PLAYER", "PARTY", "RAID_PLAYER", "RAID" }
  for _, tag in ipairs(tags) do
    Menu.ModifyMenu("MENU_UNIT_" .. tag, function(owner, root, contextData)
      local unit = contextData and contextData.unit
      if unit ~= "target" and unit ~= "focus" then return end
      root:CreateDivider()
      root:CreateButton("Create Target Macro", function() MakeMacro(unit) end)
    end)
  end
end

-- /tmacro            -> current target
-- /tmacro focus      -> current focus
-- /tmacro <name>     -> macro for that name (doesn't need to be targeted)
SLASH_TARGETMACRO1 = "/tmacro"
SlashCmdList.TARGETMACRO = function(msg)
  msg = strtrim(msg or "")
  local lower = msg:lower()
  if lower == "" or lower == "target" then MakeMacro("target")
  elseif lower == "focus" then MakeMacro("focus")
  else MakeMacro(nil, msg) end
end
