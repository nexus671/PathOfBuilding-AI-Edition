-- Validate sampled map stat values and render only source-matched lines.
local M={}
local function array(value,limit,label)
	assert(type(value)=="table" and #value<=limit,"Invalid "..label)
	for key in pairs(value) do assert(type(key)=="number" and key==math.floor(key) and key>=1 and key<=#value,"Invalid "..label) end
	return value
end
function M.validate(selected,rolls,source)
	local byId,allowed={},{};for _,id in ipairs(selected or {}) do allowed[id]=true end
	for _,entry in ipairs(array(rolls or {},6,"map rolls")) do
		assert(type(entry)=="table" and type(entry.id)=="string" and allowed[entry.id] and not byId[entry.id],"Invalid map roll modifier")
		local mod=assert(source.mods[entry.id],"Unknown rolled map modifier");local values=array(entry.values,20,"map roll values")
		assert(#values==#mod.stats,"Map roll does not match the modifier stats")
		local copy={};for i,stat in ipairs(mod.stats) do
			local value=values[i];assert(type(value)=="number" and value==math.floor(value) and value>=stat.min and value<=stat.max,"Map roll is outside the source range");copy[i]=value
		end
		byId[entry.id]=copy
	end
	return byId
end
function M.sample(mod,random)
	local values={};for i,stat in ipairs(mod.stats) do
		values[i]=stat.min==stat.max and stat.min or stat.min+math.floor(random()*(stat.max-stat.min+1))
	end
	return values
end
function M.render(mod,values)
	if not values then return {} end
	local ranges,rolled={},{}
	for i,stat in ipairs(mod.stats) do ranges[stat.id]={min=stat.min,max=stat.max};rolled[stat.id]=values[i] end
	local describe=require("Modules.StatDescriber")
	local ok,a,am=pcall(describe,ranges,"stat_descriptions");if not ok then return {} end
	local ok2,b,bm=pcall(describe,rolled,"stat_descriptions");if not ok2 or #a~=#b then return {} end
	local function sourceStyle(line) return (line:gsub("%(%-(%d+)%-%-(%d+)%)","-(%1-%2)")) end
	local count,rolledCount={},{};for _,line in ipairs(a) do local key=sourceStyle(line);count[key]=(count[key] or 0)+1 end
	for _,line in ipairs(b) do rolledCount[line]=(rolledCount[line] or 0)+1 end
	local replacements={};for i,line in ipairs(a) do
		local key=sourceStyle(line);if count[key]==1 and rolledCount[b[i]]==1 and am[line] and am[line]==bm[b[i]] then replacements[key]=b[i] end
	end
	return replacements
end
return M
