-- Experimental ordinary-map modifier identity rolls. Probabilities are estimates.
local map=require("Modules.MapCraftingData")
local M={}
local function rng(seed)
	assert(type(seed)=="number" and seed==math.floor(seed) and seed>=1 and seed<=2147483646,"Invalid map roll seed")
	return function() seed=seed*16807%2147483647;return seed/2147483647 end
end
local function inspect(state,offset,checkpoint)
	return map.inspect(state.baseId,state.tier,state.itemLevel,state.selected,"",offset,100,checkpoint,state.rarity)
end
local function candidates(state,checkpoint)
	local all,offset={},0
	repeat
		local page=inspect(state,offset,checkpoint)
		for _,entry in ipairs(page.candidates) do all[#all+1]=entry end
		offset=page.nextOffset
	until not offset
	return all
end
local function add(state,random,checkpoint)
	local options=candidates(state,checkpoint);local total=0
	for _,entry in ipairs(options) do total=total+entry.spawnWeight end
	assert(total>0,"No modeled eligible map modifier remains")
	local target=random()*total
	for _,entry in ipairs(options) do
		target=target-entry.spawnWeight
		if target<0 then state.selected[#state.selected+1]=entry.id;return end
	end
	error("Could not select a map modifier")
end
function M.perform(input,action,seed,checkpoint)
	assert(type(input)=="table" and type(input.selected)=="table","Invalid map state")
	local state={baseId=input.baseId,tier=input.tier,itemLevel=input.itemLevel,rarity=input.rarity,selected={}}
	for _,id in ipairs(input.selected) do state.selected[#state.selected+1]=id end
	assert(state.rarity=="normal" or state.rarity=="magic" or state.rarity=="rare","Invalid map rarity")
	if state.rarity=="normal" then
		assert(#state.selected==0,"A normal map cannot have explicit modifiers")
		-- Validate the base, tier and level before changing state.
		local probe={baseId=state.baseId,tier=state.tier,itemLevel=state.itemLevel,rarity="rare",selected={}};inspect(probe,0,checkpoint)
	else
		inspect(state,0,checkpoint)
		local prior={baseId=state.baseId,tier=state.tier,itemLevel=state.itemLevel,rarity=state.rarity,selected={}}
		for _,id in ipairs(state.selected) do
			local found=false;for _,entry in ipairs(candidates(prior,checkpoint)) do if entry.id==id then found=true;break end end
			assert(found,"A selected modifier is not eligible for this modeled map state")
			prior.selected[#prior.selected+1]=id
		end
	end
	local random=rng(seed)
	if action=="transmute" or action=="alchemy" then
		assert(state.rarity=="normal","Requires a normal map")
		state.rarity=action=="transmute" and "magic" or "rare"
	elseif action=="alteration" then assert(state.rarity=="magic","Requires a magic map");state.selected={}
	elseif action=="chaos" then assert(state.rarity=="rare","Requires a rare map");state.selected={}
	elseif action=="augmentation" then assert(state.rarity=="magic","Requires a magic map");add(state,random,checkpoint)
	elseif action=="regal" then assert(state.rarity=="magic","Requires a magic map");state.rarity="rare";add(state,random,checkpoint)
	elseif action=="exalt" then assert(state.rarity=="rare","Requires a rare map");add(state,random,checkpoint)
	elseif action=="annul" then assert(state.rarity~="normal" and #state.selected>0,"Requires a magic or rare map with a modifier");table.remove(state.selected,math.floor(random()*#state.selected)+1)
	elseif action=="scour" then assert(state.rarity~="normal","Requires a magic or rare map");state.rarity="normal";state.selected={}
	else error("Unsupported map currency") end
	if action=="transmute" or action=="alteration" or action=="alchemy" or action=="chaos" then
		local value=random();local count=state.rarity=="magic" and (value<0.5 and 1 or 2) or (value<8/12 and 4 or value<11/12 and 5 or 6)
		for _=1,count do add(state,random,checkpoint) end
	end
	return {state=state,seed=seed,action=action,summary=map.summarize(state.selected),note="Experimental modifier identities only: count distribution, spawn-weight selection and interactions are estimates. Numerical modifier values are not rolled; base availability and some map restrictions are unverified."}
end
return M
