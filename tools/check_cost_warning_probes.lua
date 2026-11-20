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
local function snapshot()
 wipeGlobalCache()
 local env = calcs.buildOutput(build, "MAIN")
 local out = env.player.output
 local result = {}
 for key, value in pairs(out) do
  if type(value) == "number" or type(value) == "boolean" or type(value) == "string" then result[key] = value
  elseif type(value) == "table" and key:find("Warning") then result[key] = table.concat(value, "\n") end
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
 calcs.buildActiveSkill = original
 local actual = snapshot()
 for key, value in pairs(expected) do assert(actual[key] == value, "Changed main output " .. key .. ": " .. tostring(value) .. " vs " .. tostring(actual[key])) end
 for key in pairs(actual) do assert(expected[key] ~= nil, "Unexpected main output " .. key) end
end
compareOutput()
local selected
for _, node in pairsSortByKey(build.spec.nodes) do
 if not node.alloc and (node.type == "Normal" or node.type == "Notable") and not node.isMultipleChoiceOption and not node.ascendancyName and node.path and #node.path == 1 then selected = node; break end
end
assert(selected, "No adjacent passive available for comparison")
build.spec:AllocNode(selected); compareOutput()
build.spec:DeallocSingleNode(selected); build.spec:BuildAllDependsAndPaths(); compareOutput()
if fixture:find("Generals Perforate", 1, true) then assert(fallbackCount > 0, "General's Cry did not exercise the cache fallback") end
print("COST_PROBES_OK " .. compared .. " partial=" .. partialCount .. " full=" .. fallbackCount .. " " .. fixture)
