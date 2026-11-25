-- Corruption-exclusive jewel candidates from the bundled unique item data.
-- These entries identify possible outcomes, not their relative game weights.
local M={}
local supported={["Cobalt Jewel"]=true,["Crimson Jewel"]=true,["Viridian Jewel"]=true}
local cache={}

function M.candidates(baseName)
	if not supported[baseName] then return {} end
	if cache[baseName] then return cache[baseName] end
	local result={}
	for _,raw in ipairs(data.uniques.jewel or {}) do
		local title,base=raw:match("^%s*([^\r\n]+)\r?\n([^\r\n]+)")
		local source=raw:match("\nSource: ([^\r\n]+)")
		if base==baseName and source and source:find("Use currency{Vaal Orb} on normal{"..baseName.."}",1,true) then
			result[#result+1]={title=title,baseName=base,raw=raw}
		end
	end
	table.sort(result,function(a,b) return a.title<b.title end)
	cache[baseName]=result
	return result
end

-- Some bundled entries mark corruption only on a variant line; explicitly
-- set it on the constructed outcome instead of trusting that annotation.
function M.item(baseName,title,itemLevel,seed)
	assert(type(itemLevel)=="number" and itemLevel==math.floor(itemLevel) and itemLevel>=1 and itemLevel<=100,"Invalid item level")
	assert(type(seed)=="number" and seed==math.floor(seed) and seed>=1 and seed<=2147483646,"Invalid unique jewel seed")
	for _,entry in ipairs(M.candidates(baseName)) do if entry.title==title then
		local raw=entry.raw:gsub("\n{variant:[^}]+}Corrupted\r?\n","\n")
		local item=new("Item"):Item(raw,"UNIQUE",true)
		assert(item.baseName==baseName and item.title==title,"Invalid unique jewel data")
		for _,line in ipairs(item.explicitModLines or {}) do
			seed=seed*16807%2147483647;line.range=seed/2147483647
		end
		item.itemLevel=itemLevel;item.corrupted=true;item:BuildAndParseRaw()
		return item
	end end
	error("Unknown corruption-exclusive jewel")
end

-- Read only the supported single-integer modifiers of the generated jewel.
-- Keep unsupported and duplicate lines out of the target picker.
function M.rollOptions(item)
	local result,seen,duplicates={},{},{}
	for _,line in ipairs(item.explicitModLines or {}) do if item:CheckModLineVariant(line) then
		local text=line.line;local low,high=text:match("%((%d+)%-(%d+)%)");low,high=tonumber(low),tonumber(high)
		local _,count=text:gsub("%(%-?%d+%.?%d*%-%-?%d+%.?%d*%)","")
		if low and high and high>low and high-low<=1000 and count==1 and not text:find("%-%(") then
			local shown=StripEscapes(itemLib.formatModLine(line,false) or "");local current;local displayed={};local ambiguous=false
			for value=low,high do local choice=itemLib.applyRange(text,(value-low)/(high-low));if displayed[choice] then ambiguous=true end;displayed[choice]=true;if choice==shown then current=value end end
			if current and not ambiguous then
				if seen[text] then duplicates[text]=true else seen[text]=true;result[#result+1]={line=text,component=1,min=low,max=high,current=current,step=1} end
			end
		end
	end end
	local clean={};for _,entry in ipairs(result) do if not duplicates[entry.line] then clean[#clean+1]=entry end end;return clean
end

function M.matchesRolls(item,requirements)
	local goals={};if requirements.uniqueModifier then goals[#goals+1]=requirements.uniqueModifier end;for _,goal in ipairs(requirements.uniqueModifiers or {}) do goals[#goals+1]=goal end
	if #goals==0 then return true end
	local options=M.rollOptions(item);local matched=true
	for _,goal in ipairs(goals) do
		local found;for _,entry in ipairs(options) do if entry.line==goal.line and (goal.component or 1)==entry.component then found=entry;break end end
		assert(found,"This unique jewel modifier is unavailable or needs a separate roll model")
		local value=goal.minValue or goal.maxValue;assert(type(value)=="number" and value==math.floor(value) and value>=found.min and value<=found.max,"Unique jewel roll target is outside its supported range")
		if goal.minValue and found.current<value or goal.maxValue and found.current>value then matched=false end
	end
	return matched
end

-- This state is deliberately separate from ordinary affixes: unique item
-- text cannot be reconstructed from the source jewel's modifier IDs.
function M.validateState(model,state)
	assert(model.item.type=="Jewel" and type(state)=="table" and state.rarity=="UNIQUE" and state.corrupted==true,"Invalid unique jewel state")
	local keys={origin=true,rarity=true,corrupted=true,affixes=true,uniqueTitle=true,uniqueSeed=true}
	for key in pairs(state) do assert(keys[key],"Unexpected unique jewel state property: "..tostring(key)) end
	assert(state.origin==model.initial.origin and type(state.affixes)=="table" and next(state.affixes)==nil,"Invalid unique jewel origin or affixes")
	assert(not state.destroyed and not state.veil and not state.mirrored and not state.baseItem,"Invalid unique jewel state")
	local item=M.item(model.item.baseName,state.uniqueTitle,model.item.itemLevel,state.uniqueSeed)
	assert(item.corrupted and item.rarity=="UNIQUE","Invalid unique jewel result")
	return {origin=state.origin,rarity="UNIQUE",corrupted=true,affixes={},uniqueTitle=state.uniqueTitle,uniqueSeed=state.uniqueSeed}
end

return M
