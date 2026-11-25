-- Enumerate the same illustrative cases used by the economy review, in pages.
local parser = require("Modules.LootFilterParser")
local library = require("Modules.LootFilterLibrary")
local pickupAreas = require("Modules.LootFilterPickupAreas")
local appearance = require("Modules.LootFilterPriceAppearance")
local M = {}

function M.prepare(change, before, after)
	assert(type(change)=="table" and type(change.classes)=="table" and #change.classes>0 and #change.classes<=50, "Decision classes are unavailable")
	assert(type(change.name)=="string" and type(change.old)=="number" and type(change.cutoff)=="number", "Decision details are unavailable")
	assert(change.highlights==nil or type(change.highlights)=="table" and #change.highlights<=50, "Decision highlights are unavailable")
	for _,class in ipairs(change.classes) do assert(type(class)=="string" and #class<=100, "Invalid decision class") end
	assert((type(before)=="string" or type(before)=="table") and (type(after)=="string" or type(after)=="table"), "Filter comparison is unavailable")
	local areas = pickupAreas.samples(change.scope,change.tier)
	local stack = change.old==change.cutoff and change.highlights and change.highlights[1] and change.highlights[1].firstStack or math.min(change.cutoff,change.old)+1
	local stacks,seen = {stack},{[stack]=true}
	for _,highlight in ipairs(change.highlights or {}) do
		local threshold=highlight.firstStack
		assert(type(threshold)=="number", "Invalid highlight threshold")
		if not seen[threshold] then stacks[#stacks+1]=threshold;seen[threshold]=true end
	end
	local rarities=change.uniqueBase and {"Unique"} or change.tier and {"Normal","Magic","Rare"} or {"Normal"}
	return {change=change,areas=areas,stacks=stacks,rarities=rarities,before=type(before)=="string" and parser.parse(before) or before,after=type(after)=="string" and parser.parse(after) or after,
		total=#change.classes * #areas * #stacks * #rarities}
end

function M.page(prepared, offset, limit)
	offset,limit=offset or 0,limit or 20
	assert(type(offset)=="number" and offset==math.floor(offset) and offset>=0 and offset<=prepared.total, "Invalid example offset")
	assert(type(limit)=="number" and limit==math.floor(limit) and limit>=1 and limit<=50, "Use 1 to 50 examples per page")
	local change,results,index=prepared.change,{},0
	local base=library.baseProperties(change.name,"Normal")
	for _,class in ipairs(change.classes) do for _,area in ipairs(prepared.areas) do
		local sample={BaseType=change.name,Class=class,Rarity="Normal",AreaLevel=area,DropLevel=base.DropLevel,
			Width=base.Width,Height=base.Height,HasExplicitMod={},HasEnchantment={},HasInfluence={"None"},SocketGroup="",EnchantmentPassiveNode=""}
		for name in pairs(parser.numeric) do if sample[name]==nil and name~="ItemLevel" and name~="DropLevel" and name~="Width" and name~="Height" then sample[name]=0 end end
		for name in pairs(parser.booleans) do sample[name]=false end
		if change.tier then sample.MapTier=change.tier;sample.BlightedMap=change.blighted or change.ravaged;sample.UberBlightedMap=change.ravaged end
		if change.gemLevel then sample.GemLevel,sample.Quality,sample.Corrupted=change.gemLevel,change.gemQuality,change.corrupted end
		for _,rarity in ipairs(prepared.rarities) do for _,size in ipairs(prepared.stacks) do
			index=index+1
			if index>offset and index<=offset+limit then
				sample.Rarity,sample.StackSize=rarity,size
				local before,after=parser.simulate(prepared.before,sample),parser.simulate(prepared.after,sample)
				results[#results+1]={action=after.action,line=after.line,before=before.action,beforeLine=before.line,
					beforeMissing=parser.safeMissingProperties(before.missingProperties),afterMissing=parser.safeMissingProperties(after.missingProperties),
					class=class,count=size,area=area,rarity=change.tier and rarity or nil,
					actions=appearance.resultActions(after),marker=after.action=="Show" and after.styles.MinimapIcon and table.concat(after.styles.MinimapIcon," ") or nil}
			end
		end end
	end end
	local nextOffset=offset+#results
	return {total=prepared.total,offset=offset,nextOffset=nextOffset<prepared.total and nextOffset or nil,results=results}
end
return M
