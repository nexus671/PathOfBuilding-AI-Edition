-- Experimental ordinary-map modifier and stat rolls. Probabilities are estimates.
local map=require("Modules.MapCraftingData")
local M={}
M.actions={{id="transmute",label="Orb of Transmutation"},{id="alchemy",label="Orb of Alchemy"},{id="alteration",label="Orb of Alteration"},{id="chaos",label="Chaos Orb"},{id="augmentation",label="Orb of Augmentation"},{id="regal",label="Regal Orb"},{id="exalt",label="Exalted Orb"},{id="originator",label="Originator's Exalted Orb"},{id="divine_vessel",label="Divine Vessel (conditional plan)"},{id="clear_deified_plan",label="Remove planned Deified"},{id="annul",label="Orb of Annulment"},{id="scour",label="Orb of Scouring"},{id="vaal_add",label="Vaal: +2 modifier outcome (conditional)"},{id="vaal_implicit",label="Vaal: corruption implicit (conditional)"},{id="vaal_unchanged",label="Vaal: no other change (conditional)"},{id="vaal_reroll",label="Vaal: reroll at same tier (conditional)"},{id="vaal_tier_up",label="Vaal: +1 tier reroll (conditional)"},{id="vaal_temple",label="Vaal: Vaal Temple outcome (conditional)"}}
local function rng(seed)
	assert(type(seed)=="number" and seed==math.floor(seed) and seed>=1 and seed<=2147483646,"Invalid map roll seed")
	return function() seed=seed*16807%2147483647;return seed/2147483647 end
end
local function inspect(state,offset,checkpoint)
	if checkpoint then checkpoint() end
	-- Selection does not need the item-card summary or rendered stat text.
	return map.inspect(state.baseId,state.tier,state.itemLevel,state.selected,"",offset,100,checkpoint,state.rarity,nil,state.corrupted,nil,nil,state.observedEffects,nil,true)
end
local function candidates(state,checkpoint,cache)
	-- Reroll trials repeatedly visit the same empty and one-modifier pools.
	-- Keep this cache local to one estimate and bound it to those small states.
	if checkpoint then checkpoint() end
	local key
	if cache and #state.selected<=1 then
		key=table.concat({state.baseId,state.tier,state.itemLevel,state.rarity,tostring(require("Modules.MapObservedEffects").isBlighted(state.observedEffects)),state.selected[1] or ""},"|")
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
local function add(state,random,checkpoint,cache,requiredSide,exclusive)
	local options=candidates(state,checkpoint,cache);local total=0
	for _,entry in ipairs(options) do if (not requiredSide or entry.side==requiredSide) and (not exclusive or entry.matchedTag=="uber_tier_map") then total=total+entry.spawnWeight end end
	assert(total>0,"No modeled eligible map modifier remains")
	local target=random()*total
	for _,entry in ipairs(options) do
		if (not requiredSide or entry.side==requiredSide) and (not exclusive or entry.matchedTag=="uber_tier_map") then
			target=target-entry.spawnWeight
			if target<0 then state.selected[#state.selected+1]=entry.id;return end
		end
	end
	error("Could not select a map modifier")
end
-- The 3.30 notes identify nine rare-only suffixes. Their Nightmare variants,
-- weights and interactions with other modifiers remain assumptions.
local function originatorPool(state,index,checkpoint,cache)
	local after=copyTable(state);table.remove(after.selected,index)
	local eligible={};local total=0
	for _,entry in ipairs(candidates(after,checkpoint,cache)) do
		if map.isOriginatorModifier(entry.id) then eligible[#eligible+1]=entry;total=total+entry.spawnWeight end
	end
	return eligible,total
end
local function originatorBranches(state,checkpoint,cache)
	local suffixes,unsupported={},0
	for index,id in ipairs(state.selected) do if map.source().mods[id].generation_type=="suffix" then
		suffixes[#suffixes+1]=index;local _,weight=originatorPool(state,index,checkpoint,cache);if weight==0 then unsupported=unsupported+1 end
	end end
	return suffixes,unsupported
end
local function validate(input,checkpoint,cache)
	assert(type(input)=="table" and type(input.selected)=="table","Invalid map state")
	local selectedCount=0;for key in pairs(input.selected) do assert(type(key)=="number" and key==math.floor(key) and key>=1 and key<=#input.selected,"Invalid selected map modifiers");selectedCount=selectedCount+1 end
	assert(selectedCount==#input.selected,"Invalid selected map modifiers")
	assert(input.twiceCorrupted==nil or type(input.twiceCorrupted)=="boolean","Invalid twice-corrupted map state")
	assert(not input.twiceCorrupted or input.corrupted,"A twice-corrupted map must be corrupted")
	local plannedAllflame=require("Modules.MapAllflame").validate(input.plannedAllflame)
	assert(input.plannedDeified==nil or type(input.plannedDeified)=="boolean","Invalid planned Deified marker")
	assert(input.vaalPreview==nil or type(input.vaalPreview)=="boolean","Invalid conditional Vaal preview marker")
	assert(not input.vaalPreview or input.corrupted,"A conditional Vaal preview requires a corrupted map")
	assert(input.vaalTierUpPreview==nil or type(input.vaalTierUpPreview)=="boolean","Invalid tier-up preview marker")
	assert(not input.vaalTierUpPreview or input.vaalPreview,"A tier-up preview requires a conditional Vaal preview")
	assert(not input.corrupted,"Corrupted maps cannot be modified with these currencies")
	assert(input.implicit==nil,"A map corruption implicit requires a corrupted map")
	assert(not input.mirrored,"Mirrored maps cannot be modified with these currencies")
	assert(not input.unidentified,"Identify the map before simulating currency")
	local state={baseId=input.baseId,tier=input.tier,itemLevel=input.itemLevel,rarity=input.rarity,plannedDeified=input.plannedDeified or nil,plannedAllflame=plannedAllflame,plannedDelirium=require("Modules.MapObservedEffects").validateDeliriumPlan(input.plannedDelirium),selected={},rolls={},quality=require("Modules.MapQuality").validate(input.quality),observedEffects=require("Modules.MapObservedEffects").validate(input.observedEffects)}
	assert(not require("Modules.MapObservedEffects").hasExplicit(state.observedEffects),"Currency simulation is unavailable while unsupported explicit map modifiers are recorded")
	for _,id in ipairs(input.selected) do state.selected[#state.selected+1]=id end
	local values=require("Modules.MapRollValues");local existing=values.validate(state.selected,input.rolls,map.source());local priorIds={}
	for _,id in ipairs(state.selected) do priorIds[id]=true end
	assert(state.rarity=="normal" or state.rarity=="magic" or state.rarity=="rare","Invalid map rarity")
	assert(not map.isNightmare(state.baseId) or state.rarity=="rare","Nightmare maps require rare rarity")
	if state.rarity=="normal" then
		assert(#state.selected==0,"A normal map cannot have explicit modifiers")
		-- Validate the base, tier and level before changing state.
		local probe={baseId=state.baseId,tier=state.tier,itemLevel=state.itemLevel,rarity="rare",selected={},observedEffects=state.observedEffects};inspect(probe,0,checkpoint)
	else
		-- Estimate trials start from the same empty state. The candidate cache
		-- already validates that base, tier, item level and rarity on first use.
		if #state.selected==0 and cache then candidates(state,checkpoint,cache) else inspect(state,0,checkpoint) end
		local prior={baseId=state.baseId,tier=state.tier,itemLevel=state.itemLevel,rarity=state.rarity,selected={},observedEffects=state.observedEffects}
		if map.isNightmare(state.baseId) and #state.selected>0 then
			-- Copied modifiers need not be listed in generation order. Check
			-- each against the union of the initial and unlocked pools.
			local eligible,offset={},0
			repeat local page=map.inspect(state.baseId,state.tier,state.itemLevel,{},"",offset,100,checkpoint,"rare",nil,nil,nil,nil,nil,true,true);for _,entry in ipairs(page.candidates) do eligible[entry.id]=true end;offset=page.nextOffset until not offset
			for _,id in ipairs(state.selected) do assert(eligible[id],"A selected modifier is not eligible for this modeled Nightmare map") end
		else
			for _,id in ipairs(state.selected) do
				local found=false;for _,entry in ipairs(candidates(prior,checkpoint,cache)) do if entry.id==id then found=true;break end end
				-- Existing Blighted maps can retain these pre-hotfix modifiers.
				-- Check their ordinary pool eligibility without adding them back to
				-- the pool used for future currency rolls.
				if not found and state.rarity=="rare" and map.isRareOnly(id) and require("Modules.MapObservedEffects").isBlighted(state.observedEffects) then
					local legacy=copyTable(prior);legacy.observedEffects=nil
					for _,entry in ipairs(candidates(legacy,checkpoint,cache)) do if entry.id==id then found=true;break end end
				end
				assert(found,"A selected modifier is not eligible for this modeled map state")
				prior.selected[#prior.selected+1]=id
			end
		end
	end
	return state,existing,priorIds
end
-- Validate an existing state without consuming currency or generating a roll.
function M.validateInput(input,checkpoint) validate(input,checkpoint) end
function M.reason(state,action)
	local rarity=state.rarity;local count=#state.selected
	if map.isNightmare(state.baseId) and action~="chaos" and action~="originator" and action~="divine_vessel" and action~="clear_deified_plan" and action~="plan_allflame" and action~="clear_allflame_plan" then return "Only Chaos and Originator's Exalted Orbs are modeled for Nightmare maps." end
	if action=="plan_allflame" then return nil end
	if action=="clear_allflame_plan" then if not state.plannedAllflame then return "There is no planned Allflame to remove." end;return nil end
	if action=="clear_deified_plan" then if not state.plannedDeified then return "There is no planned Deified effect to remove." end;return nil end
	if action=="divine_vessel" then
		if state.plannedDeified or require("Modules.MapObservedEffects").deified(state.observedEffects) then return "This map already has a planned or observed Deified effect." end
		return nil
	end
	if action=="transmute" or action=="alchemy" then if rarity~="normal" then return "Requires a normal map." end
	elseif action=="alteration" or action=="augmentation" or action=="regal" then
		if rarity~="magic" then return "Requires a magic map." end
		if action=="augmentation" and count>=2 then return "A magic map already has its maximum of two modifiers." end
	elseif action=="chaos" or action=="exalt" or action=="originator" then
		if rarity~="rare" then return "Requires a rare map." end
		if action=="exalt" and count>=6 then return "A rare map already has its maximum of six modifiers." end
		if action=="originator" then local found=false;for _,id in ipairs(state.selected) do if map.source().mods[id].generation_type=="suffix" then found=true;break end end;if not found then return "Requires a rare map with a suffix." end end
	elseif action=="annul" then if rarity=="normal" or count==0 then return "Requires a magic or rare map with a modifier." end
	elseif action=="scour" then if rarity=="normal" then return "Requires a magic or rare map." end
	elseif action=="vaal_add" then if rarity~="rare" then return "Only the rare-map outcome is modeled." end
	elseif action=="vaal_reroll" then if rarity~="rare" then return "Only the rare-map reroll is modeled." end
	elseif action=="vaal_tier_up" then
		if rarity~="rare" then return "Only the rare-map tier-up reroll is modeled." end
		if state.tier>=16 or state.baseId~="Metadata/Items/Maps/MapKeyTier"..state.tier then return "Requires a generic tier 1-15 map item; special and legacy maps are not modeled." end
		if state.observedEffects and #state.observedEffects>0 or state.plannedDeified or state.plannedAllflame or state.plannedDelirium then return "Remove special or planned effects before previewing this outcome; their interactions are unverified." end
	elseif action=="vaal_temple" then
		if rarity~="rare" or state.tier~=16 or state.baseId~="Metadata/Items/Maps/MapKeyTier16" then return "Requires a generic rare tier 16 map item." end
		if state.observedEffects and #state.observedEffects>0 or state.plannedDeified or state.plannedAllflame or state.plannedDelirium then return "Remove special or planned effects before previewing this outcome; their interactions are unverified." end
	elseif action=="vaal_implicit" or action=="vaal_unchanged" then return nil
	else return "Unsupported map currency." end
end
local planningState
local function templeReason(state,checkpoint)
 if not state.corrupted then return "Requires an already corrupted map." end
 if state.twiceCorrupted then return "This map is already twice corrupted." end
 if state.mirrored or state.unidentified then return "Requires an identified map that is not mirrored." end
 if state.rarity~="rare" or state.baseId~="Metadata/Items/Maps/MapKeyTier"..state.tier or state.tier>16 then return "Only generic rare tier 1-16 maps are modeled." end
 if state.observedEffects and #state.observedEffects>0 or state.plannedDeified or state.plannedAllflame or state.plannedDelirium then return "Special and planned effects are not modeled for this preview." end
 if #state.selected>=9 then return "This map already has nine modifiers." end
 inspect(state,0,checkpoint)
 local eligible={};local probe=copyTable(state);probe.selected={}
 for _,entry in ipairs(candidates(probe,checkpoint)) do eligible[entry.id]=true end
 for _,id in ipairs(state.selected) do if not eligible[id] then return "A selected modifier is not eligible in the modeled pool." end end
 if #candidates(state,checkpoint)==0 then return "No modeled eligible modifier remains." end
end
function M.options(input,checkpoint)
 if input.corrupted then
  local state=planningState(input);local reason=templeReason(state,checkpoint)
  return {{id="temple_add",label="Temple: +2 modifiers (hypothetical)",available=not reason,reason=reason,detail="Hypothetical second-corruption outcome; availability, implicit retention and odds are unverified."}}
 end
	local state=validate(input,checkpoint);local result={};local cache={}
	for _,action in ipairs(M.actions) do
		local reason=M.reason(state,action.id)
		if not reason and (action.id=="augmentation" or action.id=="regal" or action.id=="exalt") then
			local candidateState=copyTable(state);if action.id=="regal" then candidateState.rarity="rare" end
			if #candidates(candidateState,checkpoint,cache)==0 then reason="No modeled eligible modifier remains." end
		end
		local detail
		if not reason and action.id=="originator" then
			local suffixes,unsupported=originatorBranches(state,checkpoint,cache)
			if unsupported==#suffixes then reason="No supported replacement remains after any suffix removal."
			elseif unsupported>0 then detail="Some random suffix removals have no supported replacement; those previews stop without changing the map." end
		elseif not reason and action.id=="vaal_tier_up" then
			detail="Conditional outcome only: assumes a generic next-tier map and unchanged item level. Odds and current-game interactions are unverified."
		elseif not reason and action.id=="vaal_temple" then
			detail="Conditional outcome only: assumes the current Vaal Temple base and unchanged item level. Odds and current-game interactions are unverified."
		end
		result[#result+1]={id=action.id,label=action.label,available=not reason,reason=reason,detail=detail}
	end
	return result
end
planningState=function(input)
 assert(type(input)=="table","Invalid map state")
 local draft=copyTable(input);draft.id="preview";draft.title="Map preview";draft.patch=map.source().patch
 local state=require("Modules.AtlasPlanner").validateMapDraft(draft);state.id=nil;state.title=nil;state.patch=nil
 return state
end
function M.planningOptions(input)
 local state=planningState(input);local result={}
 for _,entry in ipairs({{id="divine_vessel",label="Plan Deified"},{id="clear_deified_plan",label="Remove planned Deified"},{id="plan_allflame",label="Plan Allflame"},{id="clear_allflame_plan",label="Remove planned Allflame"}}) do
  local reason=M.reason(state,entry.id)
  result[#result+1]={id=entry.id,label=entry.label,available=not reason,reason=reason,detail="Hypothetical plan only; in-game eligibility and interactions are unverified."}
 end
 return result
end
function M.perform(input,action,seed,checkpoint,identitiesOnly,cache,allflameId)
 if action=="temple_add" then
  local random=rng(seed);local state=planningState(input)
  local reason=templeReason(state,checkpoint);assert(not reason,reason)
  local values=require("Modules.MapRollValues");values.validate(state.selected,state.rolls,map.source())
  state.rolls=state.rolls or {};local first=#state.selected+1
  for _=1,math.min(2,9-#state.selected) do add(state,random,checkpoint,cache) end
  for index=first,#state.selected do local id=state.selected[index];local roll=not identitiesOnly and values.sample(map.source().mods[id],random);if roll then state.rolls[#state.rolls+1]={id=id,values=roll} end end
  state.twiceCorrupted=true;state.vaalPreview=true;state.templePreview=true
  local implicitInfo=state.implicit and require("Modules.MapCorruptionImplicits").describe(state.implicit,state.itemLevel) or nil
  return {state=state,seed=seed,action=action,dataPatch=map.source().patch,dataSource=copyTable(map.source().source),summary=not identitiesOnly and map.summarize(state.selected,state.rolls,implicitInfo,state.quality) or nil,note="Hypothetical Temple second-corruption add-modifiers outcome. Whether this outcome is possible, implicit retention, weights, values, interactions and odds are unverified; this is not a full device simulation."}
 end
	if action=="divine_vessel" or action=="clear_deified_plan" or action=="plan_allflame" or action=="clear_allflame_plan" then
		-- This is a reversible planning marker, not an assertion that the currency
		-- can be used on a corrupted, mirrored or unidentified map in the game.
		rng(seed)
		local state=planningState(input)
		local reason=M.reason(state,action);assert(not reason,reason)
		local inspected=map.inspect(state.baseId,state.tier,state.itemLevel,state.selected,"",0,1,checkpoint,state.rarity,state.rolls,state.corrupted,state.implicit,state.quality,state.observedEffects)
		if action=="divine_vessel" then state.plannedDeified=true elseif action=="clear_deified_plan" then state.plannedDeified=nil
		elseif action=="plan_allflame" then state.plannedAllflame=require("Modules.MapAllflame").validate(assert(allflameId,"Choose an Allflame")) else state.plannedAllflame=nil end
		return {state=state,seed=seed,action=action,allflame=require("Modules.MapAllflame").describe(state.plannedAllflame),deified=require("Modules.MapObservedEffects").deified(state.observedEffects,state.plannedDeified),dataPatch=map.source().patch,dataSource=copyTable(map.source().source),summary=not state.unidentified and inspected.summary or nil,
		 note=(action=="divine_vessel" or action=="plan_allflame") and "Conditional map enchantment plan. Eligibility, stacking, replacement, other enchantments, corruption order and outcomes need in-game verification; no map or currency is changed." or "Removed the hypothetical enchantment plan; copied effects are unchanged."}
	end
	local state,existing,priorIds=validate(input,checkpoint,cache)
	local reason=M.reason(state,action);assert(not reason,reason)
	local values=require("Modules.MapRollValues")
	local random=rng(seed)
	if action=="transmute" or action=="alchemy" then
		assert(state.rarity=="normal","Requires a normal map")
		state.rarity=action=="transmute" and "magic" or "rare"
	elseif action=="alteration" then assert(state.rarity=="magic","Requires a magic map");state.selected={};existing={};priorIds={}
	elseif action=="chaos" or action=="vaal_reroll" or action=="vaal_tier_up" or action=="vaal_temple" then
		assert(state.rarity=="rare","Requires a rare map");state.selected={};existing={};priorIds={}
		if action=="vaal_tier_up" then state.tier=state.tier+1;state.baseId="Metadata/Items/Maps/MapKeyTier"..state.tier
		elseif action=="vaal_temple" then state.baseId="Metadata/Items/Maps/MapWorldsVaalTemple" end
	elseif action=="augmentation" then assert(state.rarity=="magic","Requires a magic map");add(state,random,checkpoint,cache)
	elseif action=="regal" then assert(state.rarity=="magic","Requires a magic map");state.rarity="rare";add(state,random,checkpoint,cache)
	elseif action=="exalt" then assert(state.rarity=="rare","Requires a rare map");add(state,random,checkpoint,cache)
	elseif action=="originator" then
		local suffixes={};for index,id in ipairs(state.selected) do if map.source().mods[id].generation_type=="suffix" then suffixes[#suffixes+1]=index end end
		local index=suffixes[math.floor(random()*#suffixes)+1];local options,total=originatorPool(state,index,checkpoint,cache)
		assert(total>0,"Unsupported outcome; map unchanged. Try again.")
		local removed=table.remove(state.selected,index);existing[removed]=nil;priorIds[removed]=nil
		local target=random()*total;local picked
		for _,entry in ipairs(options) do target=target-entry.spawnWeight;if target<0 then picked=entry.id;break end end
		assert(picked,"Could not select a modeled Originator modifier");state.selected[#state.selected+1]=picked
	elseif action=="annul" then assert(state.rarity~="normal" and #state.selected>0,"Requires a magic or rare map with a modifier");table.remove(state.selected,math.floor(random()*#state.selected)+1)
	elseif action=="scour" then assert(state.rarity~="normal","Requires a magic or rare map");state.rarity="normal";state.selected={}
	elseif action=="vaal_add" then
		-- Preview only this outcome; no Vaal outcome probability is implied.
		state.corrupted=true;state.vaalPreview=true
		for _=1,math.min(2,9-#state.selected) do add(state,random,checkpoint,cache) end
	elseif action=="vaal_implicit" or action=="vaal_unchanged" then
		state.corrupted=true;state.vaalPreview=true
		if action=="vaal_implicit" then state.implicit=require("Modules.MapCorruptionImplicits").roll(state.itemLevel,require("Modules.MapObservedEffects").isBlighted(state.observedEffects),random) end
	else error("Unsupported map currency") end
	if action=="chaos" and map.isNightmare(state.baseId) then
		-- Historical Tier 17 notes require one exclusive prefix and suffix;
		-- selecting them first and then filling by weight is an assumption.
		add(state,random,checkpoint,cache,"prefix",true);add(state,random,checkpoint,cache,"suffix",true)
		for _=1,4 do add(state,random,checkpoint,cache) end
	elseif action=="transmute" or action=="alteration" or action=="alchemy" or action=="chaos" or action=="vaal_reroll" or action=="vaal_tier_up" or action=="vaal_temple" then
		local value=random();local count=state.rarity=="magic" and (value<0.5 and 1 or 2) or (value<8/12 and 4 or value<11/12 and 5 or 6)
		for _=1,count do add(state,random,checkpoint,cache) end
	end
	if action=="vaal_reroll" or action=="vaal_tier_up" or action=="vaal_temple" then state.corrupted=true;state.vaalPreview=true;state.vaalTierUpPreview=action=="vaal_tier_up" or nil end
	for _,id in ipairs(state.selected) do
		local roll=existing[id] or (not identitiesOnly and not priorIds[id] and values.sample(map.source().mods[id],random))
		if roll then state.rolls[#state.rolls+1]={id=id,values=roll} end
	end
	local implicitInfo=state.implicit and require("Modules.MapCorruptionImplicits").describe(state.implicit,state.itemLevel) or nil
	return {state=state,seed=seed,action=action,baseImplicit=map.baseImplicit(state.baseId),allflame=require("Modules.MapAllflame").describe(state.plannedAllflame),deified=require("Modules.MapObservedEffects").deified(state.observedEffects,state.plannedDeified),dataPatch=not identitiesOnly and map.source().patch or nil,dataSource=not identitiesOnly and copyTable(map.source().source) or nil,implicitSource=state.implicit and require("Modules.MapCorruptionImplicits").source() or nil,summary=not identitiesOnly and map.summarize(state.selected,state.rolls,implicitInfo,state.quality) or nil,note=(action=="originator" and "Experimental Originator preview: a suffix is selected uniformly and a documented rare-only replacement is sampled using exported spawn weights. Independent uniform stat rolls, Nightmare variants, eligibility, selection weights and interactions are unverified; some removal branches are unsupported." or action=="vaal_add" and "Conditional Vaal outcome only: two modifiers are added and the map is corrupted. This is not a full Vaal Orb simulation or an outcome probability. Weighted selection, stat rolls, side limits and interactions are unverified assumptions." or action=="vaal_implicit" and "Conditional Vaal implicit outcome only; this is not a full Vaal Orb roll or an outcome probability. Implicit selection uses pinned weights, with uniformly sampled values; eligibility and interactions are unverified." or action=="vaal_unchanged" and "Conditional Vaal outcome only: the map is corrupted without another change. This is not a full Vaal Orb roll or an outcome probability." or action=="vaal_temple" and "Conditional Vaal Temple outcome only; this is not a full Vaal Orb roll or an outcome probability. The current Vaal Temple base and unchanged item level are assumptions. Modifier counts, weights, values, quality retention and current-game interactions are unverified." or action=="vaal_tier_up" and "Conditional Vaal tier-up reroll only; this is not a full Vaal Orb roll or an outcome probability. The generic next-tier map and unchanged item level are assumptions. Modifier counts, weights, values, quality retention and current-game interactions are unverified; Vaal Temple is excluded." or action=="vaal_reroll" and "Conditional Vaal reroll at the same tier only; this is not a full Vaal Orb roll or an outcome probability. Modifier counts, weights, uniform values and interactions are unverified assumptions; tier changes and Vaal Temple are excluded." or map.isNightmare(state.baseId) and "Experimental Nightmare model: six modifiers, one exclusive prefix and suffix drawn first, then four weighted draws. Draw order, weights, independent uniform values and interactions are unverified assumptions." or "Experimental: modifier counts, weighted selection, independent uniform stat rolls and map interactions are estimates. Unmatched or unsampled text remains a range; base availability and some restrictions are unverified.")..require("Modules.MapObservedEffects").note(state.observedEffects)..(map.hasBlightedLegacy(state.selected,state.observedEffects) and " Existing rare-only modifiers are retained as possible pre-hotfix rolls; they cannot roll again." or "")}
end
return M
