-- /petab debug: report what this client exposes about learned pet abilities,
-- then watch for 20 seconds while you open Beast Training.
local _, ns = ...
local DATA = PetAbilityMapData

local function P(t) print("|cff33ff99PetAbilityMap debug|r: " .. t) end

local WATCH = { "CRAFT_SHOW", "CRAFT_UPDATE", "CRAFT_CLOSE", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE",
  "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRAINER_SHOW", "TRAINER_UPDATE", "SPELLS_CHANGED",
  "LEARNED_SPELL_IN_TAB", "PET_BAR_UPDATE", "UNIT_PET", "PET_STABLE_SHOW", "PET_STABLE_UPDATE" }
local FRAMES = { "CraftFrame", "TradeSkillFrame", "ProfessionsFrame", "ClassTrainerFrame",
  "PetStableFrame", "SpellBookFrame", "PlayerSpellsFrame" }

local function Report()
  P(("APIs: crafts=%s tradeskill=%s C_SpellBook=%s HasPetSpells=%s"):format(
    tostring(GetNumCrafts ~= nil), tostring(C_TradeSkillUI ~= nil),
    tostring(C_SpellBook ~= nil), tostring(HasPetSpells ~= nil)))

  local n = HasPetSpells and HasPetSpells()
  P("pet spells: " .. tostring(n))
  for i = 1, (n or 0) do
    local name, sub, id = ns.BookItem(i, "pet")
    local a, r = ns.Identify(name, sub, id)
    print(("  %d: %s | sub=%s | id=%s -> %s"):format(i, tostring(name), tostring(sub), tostring(id),
      a and (a .. " " .. r) or "-"))
  end

  local hits = 0
  for i = 1, ns.NumPlayerBookItems() do
    local name, sub, id = ns.BookItem(i, "player")
    if name and (DATA.abilities[name] or name == "Beast Training" or name:find("Pet")) then
      hits = hits + 1
      print(("  book %d: %s | sub=%s | id=%s"):format(i, name, tostring(sub), tostring(id)))
    end
  end
  P("matching player spellbook entries: " .. hits)

  if GetNumCrafts then
    P(("craft window: %s, %s entries"):format(tostring(GetCraftDisplaySkillLine and GetCraftDisplaySkillLine()),
      tostring(GetNumCrafts())))
    for i = 1, math.min(GetNumCrafts(), 5) do
      local name, sub, kind = GetCraftInfo(i)
      print(("  craft %d: %s | %s | %s"):format(i, tostring(name), tostring(sub), tostring(kind)))
    end
  end
  if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
    local ids = C_TradeSkillUI.GetAllRecipeIDs() or {}
    P("trade skill recipes: " .. #ids)
    for i = 1, math.min(#ids, 5) do
      local info = C_TradeSkillUI.GetRecipeInfo(ids[i])
      print(("  recipe %d: %s | learned=%s"):format(ids[i], tostring(info and info.name), tostring(info and info.learned)))
    end
  end

  local shown = {}
  for _, f in ipairs(FRAMES) do if _G[f] and _G[f]:IsShown() then shown[#shown + 1] = f end end
  P("open windows: " .. (#shown > 0 and table.concat(shown, ", ") or "none"))

  local k, list = PetAbilityMapCharDB.known, {}
  for a, r in pairs(k) do list[#list + 1] = a .. " " .. r end
  P("recorded as known: " .. (#list > 0 and table.concat(list, ", ") or "nothing"))
end

local watcher = CreateFrame("Frame")
local seen = {}
watcher:SetScript("OnEvent", function(_, e)
  if not seen[e] then seen[e] = true; P("event " .. e) end
end)

function ns.Debug()
  ns.Scan()
  Report()
  wipe(seen)
  for _, e in ipairs(WATCH) do pcall(watcher.RegisterEvent, watcher, e) end
  P("now open Beast Training (and summon your pet). Watching for 20 seconds...")
  C_Timer.After(20, function()
    watcher:UnregisterAllEvents()
    ns.Scan()
    P("--- after 20 seconds ---")
    Report()
    P("done. Screenshot or copy these lines and send them over.")
  end)
end
