-- Experimental ordinary-map modifier and stat rolls. Probabilities are estimates.
local map=require("Modules.MapCraftingData")
local M={}
M.actions={{id="transmute",label="Orb of Transmutation"},{id="alchemy",label="Orb of Alchemy"},{id="alteration",label="Orb of Alteration"},{id="chaos",label="Chaos Orb"},{id="augmentation",label="Orb of Augmentation"},{id="regal",label="Regal Orb"},{id="exalt",label="Exalted Orb"},{id="annul",label="Orb of Annulment"},{id="scour",label="Orb of Scouring"}}
local function rng(seed)
	assert(type(seed)=="number" and seed==math.floor(seed) and seed>=1 and seed<=2147483646,"Invalid map roll seed")
	return function() seed=seed*16807%2147483647;return seed/2147483647 end
end
local function inspect(state,offset,checkpoint)
	if checkpoint then checkpoint() end
	return map.inspect(state.baseId,state.tier,state.itemLevel,state.selected,"",offset,100,checkpoint,state.rarity)
end
local function candidates(state,checkpoint,cache)
	-- Reroll trials repeatedly visit the same empty and one-modifier pools.
	-- Keep this cache local to one estimate and bound it to those small states.
	if checkpoint then checkpoint() end
	local key
	if cache and #state.selected<=1 then
		key=table.concat({state.baseId,state.tier,state.itemLevel,state.rarity,state.selected[1] or ""},"|")
		if cache[key] then return cache[key] end
	end
	local all,offset={},0
	repeat
		local page=inspect(state,offset,checkpoint)
		for _,entry in ipairs(page.candidates) do all[#all+1]=entry end
		offset=page.nextOffset
	until not offset
	if key and (cache._count or 0)<128 then cache[key]=all;cache._count=(cache._count or 0)+1 end
	return all
end
local function add(state,random,checkpoint,cache)
	local options=candidates(state,checkpoint,cache);local total=0
	for _,entry in ipairs(options) do total=total+entry.spawnWeight end
	assert(total>0,"No modeled eligible map modifier remains")
	local target=random()*total
	for _,entry in ipairs(options) do
		target=target-entry.spawnWeight
		if target<0 then state.selected[#state.selected+1]=entry.id;return end
	end
	error("Could not select a map modifier")
end
local function validate(input,checkpoint,cache)
	assert(type(input)=="table" and type(input.selected)=="table","Invalid map state")
	assert(not input.corrupted,"Corrupted maps cannot be modified with these currencies")
	local state={baseId=input.baseId,tier=input.tier,itemLevel=input.itemLevel,rarity=input.rarity,selected={},rolls={},quality=require("Modules.MapQuality").validate(input.quality)}
	for _,id in ipairs(input.selected) do state.selected[#state.selected+1]=id end
	local values=require("Modules.MapRollValues");local existing=values.validate(state.selected,input.rolls,map.source());local priorIds={}
	for _,id in ipairs(state.selected) do priorIds[id]=true end
	assert(state.rarity=="normal" or state.rarity=="magic" or state.rarity=="rare","Invalid map rarity")
	if state.rarity=="normal" then
		assert(#state.selected==0,"A normal map cannot have explicit modifiers")
		-- Validate the base, tier and level before changing state.
		local probe={baseId=state.baseId,tier=state.tier,itemLevel=state.itemLevel,rarity="rare",selected={}};inspect(probe,0,checkpoint)
	else
		inspect(state,0,checkpoint)
		local prior={baseId=state.baseId,tier=state.tier,itemLevel=state.itemLevel,rarity=state.rarity,selected={}}
		for _,id in ipairs(state.selected) do
			local found=false;for _,entry in ipairs(candidates(prior,checkpoint,cache)) do if entry.id==id then found=true;break end end
			assert(found,"A selected modifier is not eligible for this modeled map state")
			prior.selected[#prior.selected+1]=id
		end
	end
	return state,existing,priorIds
end
function M.reason(state,action)
	local rarity=state.rarity;local count=#state.selected
	if action=="transmute" or action=="alchemy" then if rarity~="normal" then return "Requires a normal map." end
	elseif action=="alteration" or action=="augmentation" or action=="regal" then
		if rarity~="magic" then return "Requires a magic map." end
		if action=="augmentation" and count>=2 then return "A magic map already has its maximum of two modifiers." end
	elseif action=="chaos" or action=="exalt" then
		if rarity~="rare" then return "Requires a rare map." end
		if action=="exalt" and count>=6 then return "A rare map already has its maximum of six modifiers." end
	elseif action=="annul" then if rarity=="normal" or count==0 then return "Requires a magic or rare map with a modifier." end
	elseif action=="scour" then if rarity=="normal" then return "Requires a magic or rare map." end
	else return "Unsupported map currency." end
end
function M.options(input,checkpoint)
	local state=validate(input,checkpoint);local result={};local cache={}
	for _,action in ipairs(M.actions) do
		local reason=M.reason(state,action.id)
		if not reason and (action.id=="augmentation" or action.id=="regal" or action.id=="exalt") then
			local candidateState=copyTable(state);if action.id=="regal" then candidateState.rarity="rare" end
			if #candidates(candidateState,checkpoint,cache)==0 then reason="No modeled eligible modifier remains." end
		end
		result[#result+1]={id=action.id,label=action.label,available=not reason,reason=reason}
	end
	return result
end
function M.perform(input,action,seed,checkpoint,identitiesOnly,cache)
	local state,existing,priorIds=validate(input,checkpoint,cache)
	local reason=M.reason(state,action);assert(not reason,reason)
	local values=require("Modules.MapRollValues")
	local random=rng(seed)
	if action=="transmute" or action=="alchemy" then
		assert(state.rarity=="normal","Requires a normal map")
		state.rarity=action=="transmute" and "magic" or "rare"
	elseif action=="alteration" then assert(state.rarity=="magic","Requires a magic map");state.selected={};existing={};priorIds={}
	elseif action=="chaos" then assert(state.rarity=="rare","Requires a rare map");state.selected={};existing={};priorIds={}
	elseif action=="augmentation" then assert(state.rarity=="magic","Requires a magic map");add(state,random,checkpoint,cache)
	elseif action=="regal" then assert(state.rarity=="magic","Requires a magic map");state.rarity="rare";add(state,random,checkpoint,cache)
	elseif action=="exalt" then assert(state.rarity=="rare","Requires a rare map");add(state,random,checkpoint,cache)
	elseif action=="annul" then assert(state.rarity~="normal" and #state.selected>0,"Requires a magic or rare map with a modifier");table.remove(state.selected,math.floor(random()*#state.selected)+1)
	elseif action=="scour" then assert(state.rarity~="normal","Requires a magic or rare map");state.rarity="normal";state.selected={}
	else error("Unsupported map currency") end
	if action=="transmute" or action=="alteration" or action=="alchemy" or action=="chaos" then
		local value=random();local count=state.rarity=="magic" and (value<0.5 and 1 or 2) or (value<8/12 and 4 or value<11/12 and 5 or 6)
		for _=1,count do add(state,random,checkpoint,cache) end
	end
	for _,id in ipairs(state.selected) do
		local roll=existing[id] or (not identitiesOnly and not priorIds[id] and values.sample(map.source().mods[id],random))
		if roll then state.rolls[#state.rolls+1]={id=id,values=roll} end
	end
	return {state=state,seed=seed,action=action,summary=not identitiesOnly and map.summarize(state.selected,state.rolls,nil,state.quality) or nil,note="Experimental: modifier counts, weighted selection, independent uniform stat rolls and map interactions are estimates. Unmatched or unsampled text remains a range; base availability and some restrictions are unverified."}
end
return M
