-- TargetMacro: right-click target/focus frame -> "Create Target Macro"
local ICON = "Ability_Hunter_SniperShot" -- crosshair icon
local MAX_NAME = 16 -- WoW macro name limit

local function Msg(t) print("|cff33ff99TargetMacro|r: " .. t) end

local function MakeMacro(unit)
  unit = unit or "target"
  if InCombatLockdown() then Msg("can't create macros in combat."); return end
  if not UnitExists(unit) then Msg("no " .. unit .. "."); return end

  local name = GetUnitName(unit, true) -- includes realm for other-realm players
  local body = "/targetexact " .. name
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

-- Backup: /tmacro [focus]
SLASH_TARGETMACRO1 = "/tmacro"
SlashCmdList.TARGETMACRO = function(msg)
  MakeMacro((msg or ""):lower():match("focus") and "focus" or "target")
end
