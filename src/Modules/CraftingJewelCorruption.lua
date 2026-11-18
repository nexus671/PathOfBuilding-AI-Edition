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
