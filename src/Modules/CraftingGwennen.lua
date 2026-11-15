-- Bounded model of a pair observed in Gwennen's 3.30 crafting interface.
local G={}
local supported={[1000]=true,[1001]=true,[1004]=true,[1005]=true,[1006]=true,[1007]=true,[1008]=true,[1009]=true,[1014]=true,[1015]=true,[1022]=true,[1023]=true,[1024]=true,[1025]=true,[1026]=true,[1029]=true,[1041]=true,[1042]=true}
local deterministic={[1000]="No change",[1001]="Remove all modifiers",[1022]="Destroy",[1029]="Set quality to 20%"}
local currencies={lesser="Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction1_1",greater="Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction1_2",grand="Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction1_3",exceptional="Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction1_4"}
local astragali="Metadata/Items/Currency/CurrencyRefreshGambler"
function G.supports(id) return supported[id]==true end
function G.deterministic(id) return deterministic[id] end
function G.validate(craft)
	assert(supported[craft.firstOutcome] and supported[craft.secondOutcome],"Choose two supported, observed Gwennen outcomes")
	assert(not craft.allflame,"Allflame cannot be used with Gwennen")
	if craft.artifactCost~=nil then
		assert(type(craft.artifactCost)=="table","Invalid observed artifact cost")
		for key,value in pairs(craft.artifactCost) do assert(currencies[key] and type(value)=="number" and value==math.floor(value) and value>=0 and value<=1000000000,"Invalid observed artifact cost") end
	end
end
function G.extend(M,api)
	M.methods[#M.methods+1]="gwennen";M.labels.gwennen="Gwennen: observed pair (experimental)";table.sort(M.methods)
	local action,components,priceKey,validateRecipe=M.action,M.components,M.priceKey,M.validateRecipe
	function M.validateRecipe(recipe)
		local result=validateRecipe(recipe)
		for _,step in ipairs(result.steps) do if step.method=="gwennen" then G.validate(step) end end
		return result
	end
	function M.action(model,input,craft,random)
		if craft.method~="gwennen" then return action(model,input,craft,random) end
		G.validate(craft);model=M.context(model,input)
		assert(input.rarity=="RARE" and not input.destroyed and not input.corrupted and not input.mirrored and not input.veil,"Gwennen requires an uncorrupted rare equipment item")
		assert(model.item.type~="Jewel" and model.item.type~="Flask" and model.item.type~="Tincture","Gwennen requires equipment")
		local flags=api.flags(model,input)
		assert(not (flags.prefixes or flags.suffixes or flags.attack or flags.caster or flags.explicitAttack or flags.explicitCaster or M.hasPartialLock(model,input)),"Gwennen interactions with meta modifiers are not modeled")
		for _,entry in ipairs(input.affixes) do assert(not entry.fractured,"Gwennen interactions with fractured modifiers are not modeled") end
		local function branch(id,draw)
			if id==1000 then return copyTable(input) end
			if id==1022 then local result=copyTable(input);result.destroyed=true;result.affixes={};result.imprint=nil;result.implicits=nil;result.corruptedImplicits=nil;return result end
			if id==1001 then
				assert(#input.affixes>0,"No modifier can be removed")
				local result=copyTable(input);result.affixes={};result.rarity="NORMAL";return result
			end
			if id==1006 or id==1007 then
				local result=copyTable(input);local side=id==1006 and "Suffix" or "Prefix";local choices={}
				for index,entry in ipairs(result.affixes) do if model.byId[entry.id].type==side then choices[#choices+1]=index end end
				assert(#choices>0,"No "..side:lower().." modifier can be removed")
				table.remove(result.affixes,choices[math.floor(draw()*#choices)+1]);return result
			end
			if id==1008 or id==1009 then
				local result=copyTable(input);local side=id==1008 and "Suffix" or "Prefix";local pool,total={},0
				for _,entry in ipairs(M.pool(model,result)) do if model.byId[entry.id].type==side then pool[#pool+1]=entry;total=total+entry.weight end end
				assert(total>0,"No "..side:lower().." modifier can be added")
				local pick=draw()*total
				for _,entry in ipairs(pool) do pick=pick-entry.weight;if pick<0 then result.affixes[#result.affixes+1]={id=entry.id,range=M.rollRange(model.byId[entry.id],draw)};return result end end
				error("Could not select a modifier")
			end
			if id==1023 then
				assert(#input.affixes>0,"No modifier can be retained")
				local result=copyTable(input);result.affixes={copyTable(input.affixes[math.floor(draw()*#input.affixes)+1])};return result
			end
			if id==1041 then
				local lowest,choices=nil,{}
				for index,entry in ipairs(input.affixes) do
					local level=assert(model.byId[entry.id].level,"Modifier level is unavailable")
					if not lowest or level<lowest then lowest=level;choices={} end
					if level==lowest then choices[#choices+1]=index end
				end
				assert(#choices>0,"No modifier can be removed")
				local result=copyTable(input);table.remove(result.affixes,choices[math.floor(draw()*#choices)+1]);return result
			end
			if id==1024 or id==1042 then
				local result=copyTable(input);local choices={}
				for index,entry in ipairs(result.affixes) do
					local mod=model.byId[entry.id];local ranges=type(entry.range)=="table" and entry.range or {entry.range or 0.5};local rangeIndex=0;local below=false
					for _,line in ipairs(mod) do for low,high in line:gmatch("%((%-?%d+%.?%d*)%-(%-?%d+%.?%d*)%)") do
						rangeIndex=rangeIndex+1
						if tonumber(low)~=tonumber(high) and (ranges[rangeIndex] or ranges[1] or 0.5)<1 then below=true end
					end end
					if below then choices[#choices+1]=index end
				end
				assert(#choices>0,"No supported modifier has a value below its maximum")
				if id==1042 then choices={choices[math.floor(draw()*#choices)+1]} end
				for _,index in ipairs(choices) do local entry=result.affixes[index];entry.legacyLightRadius=nil;entry.range=M.rollRange(model.byId[entry.id],draw) end
				return result
			end
			if id==1025 then
				local result=copyTable(input);local maximum=M.capacities(model,result).total
				assert(#result.affixes<maximum,"No empty modifier slot")
				while #result.affixes<maximum do api.add(model,result,draw) end;return result
			end
			if id==1026 then
				assert(#input.affixes>=3,"This experimental outcome requires at least three modifiers")
				local result=copyTable(input);local count=math.floor(draw()*3)+1
				for _=1,count do table.remove(result.affixes,math.floor(draw()*#result.affixes)+1) end;return result
			end
			if id==1029 then
				assert(model.item.base.armour or data.weaponTypeInfo[model.item.type],"This quality outcome requires a weapon or armour")
				local result=copyTable(input);result.quality=20;return result
			end
			local method=({[1004]="annul",[1005]="exalt",[1014]="chaos",[1015]="divine"})[id]
			return action(model,input,{method=method},draw)
		end
		-- An observed pair is valid only when both modeled branches are usable.
		-- Dry runs do not consume the caller's random stream or mutate its input.
		for _,id in ipairs({craft.firstOutcome,craft.secondOutcome}) do
			local ok,err=pcall(branch,id,function() return 0.42 end)
			assert(ok,"A modeled Gwennen outcome cannot apply: "..tostring(err))
		end
		local outcome=random()<0.5 and craft.firstOutcome or craft.secondOutcome
		return branch(outcome,random),{gwennen={outcome=outcome}}
	end
	function M.priceKey(craft)
		if craft.method~="gwennen" then return priceKey(craft) end
		local fields={"gwennen",tostring(craft.firstOutcome),tostring(craft.secondOutcome)}
		for _,key in ipairs({"lesser","greater","grand","exceptional"}) do fields[#fields+1]=craft.artifactCost and tostring(craft.artifactCost[key] or 0) or "unknown" end
		return table.concat(fields,":")
	end
	function M.components(craft,state,model)
		if craft.method~="gwennen" then return components(craft,state,model) end
		G.validate(craft);local result={[astragali]=1}
		if craft.artifactCost==nil then result["gwennen:observed_artifacts"]=1
		else for key,amount in pairs(craft.artifactCost) do if amount>0 then result[currencies[key]]=amount end end end
		return result
	end
	M.limits[#M.limits+1]="Experimental Gwennen pairs use only observed supported outcomes. A fair coin, uniform selection and removal counts, normalized maximum-roll checks and ordinary crafting transitions are assumptions; offer generation, prices and special modifier interactions are not verified. Unknown artifact prices remain unpriced."
end
return G
