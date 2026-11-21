-- Compare full skill calculations and partial resource-warning probes on a build.
-- Run from src with an XML fixture; the file is only read.
local fixture = assert(arg[1], "Supply a build XML path")
arg = {}
dofile("HeadlessWrapper.lua")
main.disableDevAutoSave = true
local file = assert(io.open(fixture, "rb")); local raw = file:read("*a"); file:close()
loadBuildFromXML(raw, "Cost probe comparison")
build.treeTab:ConvertToVersion(latestTreeVersion, true, false)
build.buildFlag = true; runCallback("OnFrame")
local calcs = require("Modules.Calcs")
local outputKeys = {"LifeCost", "ManaCost", "RageCost", "ESCost", "LifePercentCost", "ManaPercentCost"}
local compared, partialCount, fallbackCount = 0, 0, 0
local mainEnv = build.calcsTab.mainEnv
for _, skill in ipairs(mainEnv.player.activeSkillList) do
 local uuid = cacheSkillUUID(skill, mainEnv)
 wipeGlobalCache()
 calcs.buildActiveSkill(mainEnv, "MAIN", skill, uuid)
 local complete = GlobalCache.cachedData.MAIN[uuid]
 if complete then
  local expected, expectedSkill = complete.Env.player.output, complete.Env.player.mainSkill
  wipeGlobalCache()
  local partial, partialSkill = calcs.buildActiveSkill(mainEnv, "MAIN", skill, uuid, nil, nil, nil, true)
  local fallback = GlobalCache.cachedData.MAIN[uuid]
  if fallback then fallbackCount = fallbackCount + 1 else partialCount = partialCount + 1 end
  local actual = fallback and fallback.Env.player.output or partial
  local actualSkill = fallback and fallback.Env.player.mainSkill or partialSkill
  assert(actual and actualSkill, "Missing probe for " .. skill.activeEffect.grantedEffect.name)
  for _, key in ipairs(outputKeys) do
   assert(expected[key] == actual[key], skill.activeEffect.grantedEffect.name .. " has different " .. key .. ": " .. tostring(expected[key]) .. " vs " .. tostring(actual[key]))
  end
  for _, pool in ipairs({"Life", "Mana", "Rage", "EnergyShield"}) do
   local key = pool .. "ReservedPercent"
   assert(expectedSkill.skillData[key] == actualSkill.skillData[key], skill.activeEffect.grantedEffect.name .. " has different " .. key)
  end
  if partial then assert(not GlobalCache.cachedData.MAIN[uuid], "Partial skill result was published to the full cache") end
  compared = compared + 1
 end
end
assert(compared > 0, "No active skills were compared")
local original = calcs.buildActiveSkill
local function snapshot(includeCache)
 wipeGlobalCache()
 local env = calcs.buildOutput(build, "MAIN")
 local out = env.player.output
 local result = {}
 for key, value in pairs(out) do
  if type(value) == "number" or type(value) == "boolean" or type(value) == "string" then result[key] = value
  elseif type(value) == "table" and key:find("Warning") then result[key] = table.concat(value, "\n")
  elseif key == "SkillDPS" and type(value) == "table" then
   for index, row in ipairs(value) do
    for _, field in ipairs({"name", "dps", "count"}) do
     local entry = row[field]
     if type(entry) == "number" or type(entry) == "string" then result["SkillDPS:" .. index .. ":" .. field] = entry end
    end
   end
  end
 end
 -- Nested calculations can publish skill caches even from a rejected probe.
 -- Capture them before a later full calculation can overwrite stale values.
 if includeCache then
  local cache={};result.__cache=cache
  for _,mode in ipairs({"MAIN","CALCULATOR"}) do for uuid,entry in pairs(GlobalCache.cachedData[mode]) do
   local prefix="cache:"..mode..":"..uuid..":"
   for key,value in pairs(entry) do if type(value)=="number" or type(value)=="boolean" or type(value)=="string" then cache[prefix..key]=value end end
   if entry.Env and entry.Env.player and entry.Env.player.output then for key,value in pairs(entry.Env.player.output) do
    if type(value)=="number" or type(value)=="boolean" or type(value)=="string" then cache[prefix.."output:"..key]=value end
   end end
  end end
 end
 -- A later trigger or detail view may demand a complete skill cache.
 for _, skill in ipairs(env.player.activeSkillList) do
  local uuid = cacheSkillUUID(skill, env)
  if not GlobalCache.cachedData.MAIN[uuid] then calcs.buildActiveSkill(env, "MAIN", skill, uuid) end
  local cached = GlobalCache.cachedData.MAIN[uuid]
  if cached then
   for _, key in ipairs({"TotalDPS", "Speed", "CritChance"}) do
    local value = cached[key]
    if type(value) == "number" then result["skill:" .. uuid .. ":" .. key] = value end
   end
   for _, key in ipairs(outputKeys) do
    local value = cached.Env.player.output[key]
    if value ~= nil then result["skill:" .. uuid .. ":" .. key] = value end
   end
  end
 end
 return result
end
local function compareOutput()
 calcs.buildActiveSkill = function(a,b,c,d,e,f,g) return original(a,b,c,d,e,f,g) end
 local expected = snapshot()
 -- Compare the optimized warning probes against both full skill calculations
 -- and the same partial probes with environment reuse disabled.
 calcs.buildActiveSkill = function(a,b,c,d,e,f,g,h)
  if h then return original(a,b,c,d,e,f,nil,h) end
  return original(a,b,c,d,e,f,g,h)
 end
 local noReuse = snapshot(true)
 calcs.buildActiveSkill = original
 local actual = snapshot(true)
 for key, value in pairs(expected) do assert(actual[key] == value, "Changed main output " .. key .. ": " .. tostring(value) .. " vs " .. tostring(actual[key])) end
 for key in pairs(actual) do if key~="__cache" then assert(expected[key] ~= nil, "Unexpected main output " .. key) end end
 for key, value in pairs(noReuse) do if key~="__cache" then assert(actual[key] == value, "Probe reuse changed " .. key .. ": " .. tostring(value) .. " vs " .. tostring(actual[key])) end end
 for key in pairs(actual) do assert(noReuse[key] ~= nil, "Unexpected reused-probe output " .. key) end
 for key,value in pairs(noReuse.__cache) do assert(actual.__cache[key]==value,"Probe reuse changed "..key..": "..tostring(value).." vs "..tostring(actual.__cache[key])) end
 for key in pairs(actual.__cache) do assert(noReuse.__cache[key]~=nil,"Unexpected reused-probe "..key) end
 return actual
end
compareOutput()
local selected
for _, node in pairsSortByKey(build.spec.nodes) do
 if not node.alloc and (node.type == "Normal" or node.type == "Notable") and not node.isMultipleChoiceOption and not node.ascendancyName and node.path and #node.path == 1 then selected = node; break end
end
assert(selected, "No adjacent passive available for comparison")
build.spec:AllocNode(selected); compareOutput()
build.spec:DeallocSingleNode(selected); build.spec:BuildAllDependsAndPaths(); compareOutput()
if fixture:find("OccVortex", 1, true) then
 local config = build.configTab.configSets[build.configTab.activeConfigSetId]
 local block = { title = "Cost probe stress", enabled = true, text = "20000% increased Cost of Skills" }
 config.customModsList[#config.customModsList+1] = block
 build.configTab:BuildModList()
 local stressed = compareOutput()
 assert(stressed.ManaCostWarningList and stressed.ManaCostWarningList ~= "", "Mana stress did not produce a warning")
 block.text = "20000% increased Cost of Skills\nSkills Cost Life instead of Mana"
 build.configTab:BuildModList(); local lifeStress = compareOutput()
 assert(lifeStress.LifeCostWarningList and lifeStress.LifeCostWarningList ~= "", "Life stress did not produce a warning")
 block.text = "20000% increased Cost of Skills\nSkills Cost Energy Shield instead of Mana or Life"
 build.configTab:BuildModList(); local shieldStress = compareOutput()
 assert(shieldStress.ESCostWarningList and shieldStress.ESCostWarningList ~= "", "Energy shield stress did not produce a warning")
 block.text = "20000% increased Cost of Skills\nEnergy Shield protects Mana instead of Life"
 build.configTab:BuildModList(); local batteryStress = compareOutput()
 assert(batteryStress.EnergyShieldProtectsMana, "Energy shield protection was not active")
 assert(batteryStress.ManaCostWarningList and batteryStress.ManaCostWarningList ~= "", "Protected mana stress did not produce a warning")
 block.text = "Warcries Cost +150% of Life"
 build.configTab:BuildModList(); local percentStress = compareOutput()
 assert(percentStress.LifeCostWarningList and percentStress.LifeCostWarningList:find("Enduring Cry", 1, true), "Life-based warcry cost did not produce a warning")
 -- PoB reuses the build-mode object; switch to a different triggered build in-process.
 local nextFile = assert(io.open("../spec/TestBuilds/3.13/Dual Wield Cospris CoC.xml", "rb"))
 local nextRaw = nextFile:read("*a"); nextFile:close()
 loadBuildFromXML(nextRaw, "Cost probe build switch")
 build.treeTab:ConvertToVersion(latestTreeVersion, true, false)
 for _, group in ipairs(build.skillsTab.socketGroupList) do if group.enabled ~= false then group.includeInFullDPS = true end end
 build.buildFlag = true; runCallback("OnFrame"); local triggered = compareOutput()
 assert(triggered["FullDPS"] and triggered["FullDPS"] > 0, "Triggered build did not calculate full DPS")
end
if fixture:find("Generals Perforate", 1, true) then assert(fallbackCount > 0, "General's Cry did not exercise the cache fallback") end
print("COST_PROBES_OK " .. compared .. " partial=" .. partialCount .. " full=" .. fallbackCount .. " " .. fixture)
