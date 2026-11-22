-- TargetMacro: right-click target/focus frame -> "Create Target Macro"
local ICON = "Ability_Hunter_SniperShot" -- crosshair icon
local MAX_NAME = 16 -- WoW macro name limit

local function Msg(t) print("|cff33ff99TargetMacro|r: " .. t) end

-- Macro text is built from the options in the settings window (Config.lua).
-- Only built-in slash commands are used (no /run Lua, which WoW Forever blocks).
local _, ns = ...
ns.DEFAULTS = {
  keepEnemy = false, clearFirst = true, exact = true, skipDead = true, hostileOnly = false,
  restoreLast = false, mark = true, marker = 8, markSoloOnly = true, setFocus = false,
  petAttack = false, startAttack = false, autoShot = false,
}
function ns.Opt(key)
  local v = TargetMacroDB and TargetMacroDB.options and TargetMacroDB.options[key]
  if v == nil then return ns.DEFAULTS[key] end
  return v
end

function ns.BuildBody(name)
  local o, L = ns.Opt, {}
  if o("keepEnemy") then L[#L + 1] = "/stopmacro [@target,harm,nodead]" end
  if o("clearFirst") then L[#L + 1] = "/cleartarget" end
  L[#L + 1] = (o("exact") and "/targetexact " or "/target ") .. name
  if o("skipDead") then L[#L + 1] = "/cleartarget [dead]" end
  if o("hostileOnly") then L[#L + 1] = "/cleartarget [noharm]" end
  if o("restoreLast") then L[#L + 1] = "/targetlasttarget [noexists]" end
  if o("mark") then L[#L + 1] = ("/tm %s %d"):format(o("markSoloOnly") and "[nogroup,exists]" or "[exists]", o("marker")) end
  if o("setFocus") then L[#L + 1] = "/focus [exists]" end
  if o("petAttack") then L[#L + 1] = "/petattack [@target,harm,nodead]" end
  if o("startAttack") then L[#L + 1] = "/startattack [harm,nodead]" end
  if o("autoShot") then L[#L + 1] = "/cast [harm,nodead] !Auto Shot" end
  return table.concat(L, "\n")
end
local BuildBody = ns.BuildBody

local function MakeMacro(unit, name)
  if InCombatLockdown() then Msg("can't create macros in combat."); return end
  if not name then
    unit = unit or "target"
    if not UnitExists(unit) then Msg("no " .. unit .. "."); return end
    name = GetUnitName(unit, true) -- includes realm for other-realm players
  end
  local body = BuildBody(name)
  if #body > 255 then
    Msg(("macro would be %d characters (limit 255). Turn off some options in /tmacro config."):format(#body))
    return
  end
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
    TargetMacroDB.macros[macroName] = name
    PickupMacro(index)
    Msg("macro for " .. name .. " is on your cursor. Drop it on an action bar.")
  end
end

-- Rewrite every macro this addon made with the current options.
function ns.UpdateAll()
  if InCombatLockdown() then Msg("can't edit macros in combat."); return end
  local n = 0
  for macroName, name in pairs(TargetMacroDB.macros) do
    local index = GetMacroIndexByName(macroName)
    if index and index > 0 then
      local body = BuildBody(name)
      if #body <= 255 then EditMacro(index, macroName, ICON, body); n = n + 1 end
    else
      TargetMacroDB.macros[macroName] = nil -- deleted by the player
    end
  end
  Msg("updated " .. n .. " macro" .. (n == 1 and "" or "s") .. ".")
end

function ns.CountMacros()
  local n = 0
  for macroName in pairs(TargetMacroDB.macros) do
    local index = GetMacroIndexByName(macroName)
    if index and index > 0 then n = n + 1 end
  end
  return n
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
-- /tmacro config     -> settings window
-- /tmacro update     -> rewrite all macros made by this addon with current settings
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
  elseif lower == "config" or lower == "options" or lower == "settings" then ns.ToggleConfig()
  elseif lower == "update" then ns.UpdateAll()
  elseif lower == "minimap" then
    TargetMacroDB.hideMinimap = not TargetMacroDB.hideMinimap
    ns.UpdateMinimapButton()
  elseif lower == "" or lower == "target" then MakeMacro("target")
  elseif lower == "focus" then MakeMacro("focus")
  else MakeMacro(nil, msg) end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, _, name)
  if name ~= "TargetMacro" then return end
  TargetMacroDB = TargetMacroDB or {}
  TargetMacroDB.options = TargetMacroDB.options or {}
  TargetMacroDB.macros = TargetMacroDB.macros or {}
end)
