local C={}
-- Client 3.30.0.1.4 lowers these three ring weights; other bases retain
-- their original weights. Other modifier metadata uses the reviewed 3.30 overlay.
local ringChargeWeights330={V2MaxPowerChargesCorrupted=50,V2MaxFrenzyChargesCorrupted=50,V2MaximumEnduranceChargesCorruption=50}
local lifeGainOnHit330="V2SupportedByLifeGainOnHitCorrupted"
function C.extend(M,A,api)
	local extra=require("Modules.CraftingCorruption330")
	local metadata=setmetatable({}, {__index=function(_,id) return A.data().mods[id] or extra[id] end})
	local labels={vaal="Vaal Orb",locus="Locus of Corruption",tainted_exalt="Tainted Exalted Orb",tainted_chaos="Tainted Chaos Orb"}
	for method,label in pairs(labels) do M.methods[#M.methods+1]=method;M.labels[method]=label end;table.sort(M.methods)
	local originalModel,originalAction,originalDecorate,originalValidate,originalItem=M.model,M.action,M.decorateItem,M.validateState,M.toItem
	local originalMatches=M.matches
	local function mixedImplicitReason(model,state)
		if model.unresolvedEldritch and not state.implicits then
			return "Corruption of unidentified Eldritch implicits is not modeled."
		end
		if model.item.synthesised and #(model.item.implicitModLines or {}) > 1 and not model.synthesisGroups then
			return "The synthesised implicit modifiers could not be grouped unambiguously."
		end
	end
	M.methodChecks.vaal=mixedImplicitReason
	M.methodChecks.locus=function(model,state)
		local flags=api.flags(model,state)
		if flags.prefixes or flags.suffixes or flags.attack or flags.caster then return "Locus meta-modifier interactions need additional validation" end
		for _,entry in ipairs(state.affixes) do if entry.fractured then return "Locus influence outcomes on fractured bases need additional validation" end end
		if model.item.synthesised or model.item.baseName=="Sacrificial Garb" then return "This special Locus transformation is not modeled" end
		if model.item.type=="Jewel" then
			local retained=state.corruptedImplicits or {}
			for removed=1,(#retained==2 and 2 or 1) do
				local groups={};for index,entry in ipairs(retained) do if #retained<2 or index~=removed then for _,group in ipairs(metadata[entry.id].groups) do groups[group]=true end end end
				local possible=false;for _,entry in ipairs(model.corruptions) do
					local legal=true;for _,group in ipairs(metadata[entry.id].groups) do if groups[group] then legal=false;break end end
					if legal then possible=true;break end
				end
				if not possible then return "The current corruption pool has no compatible additional jewel implicit." end
			end
		end
	end
	function M.implicitTargetReason(model,state,targets)
		if model and model.synthesisGroups and not state.destroyed and not state.veil then
			local active=state.synthRetained
			if not active and not state.corruptedImplicits and not state.implicits then active={};for index in ipairs(model.synthesisGroups) do active[#active+1]=index end end
			for _,index in ipairs(active or {}) do
				local candidates=model.synthesisGroups[index].candidates
				if #candidates>1 then for _,target in ipairs(targets) do if target.scope=="implicit" and require("Modules.CraftingSynthesisGroups").targetStatus(model.synthesisGroups[index],target)==nil then
					return "A synthesised implicit matches multiple modifier identities; its target cannot be evaluated reliably."
				end end end
			end
		end
		if model and ((model.unresolvedCorruption and not state.corruptedImplicits and (not state.implicits or model.initial.implicits)) or (model.unresolvedEldritch and not state.implicits)) and not state.destroyed and not state.veil then
			for _,group in ipairs(targets) do
				if group.scope=="implicit" then return "The imported implicit modifiers could not be identified uniquely. Paste advanced item text with modifier ranges, or choose another starting item." end
			end
		end
	end
	function M.matches(state,targets,rarity,model,...)
		local reason=M.implicitTargetReason(model,state,targets);assert(not reason,reason)
		return originalMatches(state,targets,rarity,model,...)
	end
	function M.toItem(model,state) assert(not state.destroyed,"The hypothetical item was destroyed");return originalItem(model,state) end
	local function weight(model,id)
		local mod=metadata[id]
		if not mod then return 0 end
		for _,entry in ipairs(mod.spawn_weights) do
			if entry.tag == "default" or model.item.base.tags[entry.tag] then
				return entry.tag == "ring" and ringChargeWeights330[id] or entry.weight
			end
		end
		return 0
	end
	function M.model(raw)
		local model=originalModel(raw)
		if model.item.synthesised then
			local lines={}
			for _,line in ipairs(model.item.implicitModLines or {}) do
				local group=line.modGroup or ""
				if group:sub(1,9)~="crafting_" and (not model.item.corrupted or group:sub(1,6)=="synth_") then lines[#lines+1]=line end
			end
			if #lines>0 then model.synthesisGroups=require("Modules.CraftingSynthesisGroups").resolve(lines,data.itemMods.Synthesis) end
			for _,group in ipairs(model.synthesisGroups or {}) do for _,candidate in ipairs(group.candidates) do
				model.byId[candidate.id]=data.itemMods.Synthesis[candidate.id];model.special[candidate.id]=true
				if #group.candidates>1 then model.synthesisAmbiguous=model.synthesisAmbiguous or {};model.synthesisAmbiguous[candidate.id]=true end
			end end
		end
		model.corruptions330={}
		local old=model.byId[lifeGainOnHit330]
		if old then
			local legacy,current=copyTable(old),copyTable(old)
			assert(old[1]=="Socketed Gems are Supported by Level 10 Life Gain On Hit" or old[1]=="Socketed Gems are Supported by Level 15 Life Gain on Hit Support","Unexpected Life Gain on Hit corruption data")
			legacy[1]="Socketed Gems are Supported by Level 10 Life Gain On Hit"
			current[1]="Socketed Gems are Supported by Level 15 Life Gain On Hit"
			model.corruptions330[lifeGainOnHit330]=current;model.legacyLifeGainOnHit=legacy
			if old[1]~=legacy[1] then model.corruptionImportAliases={[lifeGainOnHit330]=copyTable(old)} end
		end
		model.initial.twiceCorrupted=model.item.twiceCorrupted or nil
		model.corruptions={};model.corruptionIds={};model.corruptionImports={};model.legacyCorruptionIds={}
		local source=model.item.type=="Jewel" and model.item.affixes or data.itemMods.Corrupted
		for id,mod in pairs(source) do if mod.type=="Corrupted" and metadata[id] then
			local current=mod.level <= model.item.itemLevel and weight(model,id)>0
			if current then model.corruptions[#model.corruptions+1]={id=id,weight=weight(model,id)};model.corruptionIds[id]=true;model.special[id]=true;model.byId[id]=id==lifeGainOnHit330 and model.legacyLifeGainOnHit or mod end
			-- Legacy jewel modifiers are import candidates, never new roll outcomes.
			if current or model.item.type=="Jewel" and model.item.corrupted then model.corruptionImports[#model.corruptionImports+1]={id=id} end
		end end
		table.sort(model.corruptions,function(a,b) return a.id < b.id end)
		table.sort(model.corruptionImports,function(a,b) return a.id < b.id end)
		local imported,reason=require("Modules.CraftingCorruptionImport").resolve(M,model,metadata)
		model.initial.corruptedImplicits=imported;model.unresolvedCorruption=reason
		if imported and model.item.corrupted and model.synthesisGroups then
			model.initial.synthRetained={};for index in ipairs(model.synthesisGroups) do model.initial.synthRetained[index]=index end
		end
		for _,entry in ipairs(imported or {}) do if not model.corruptionIds[entry.id] then model.legacyCorruptionIds[entry.id]=true;model.special[entry.id]=true end end
		return model
	end
	function M.rollCorrupted(model,state,random,count,retained)
		local reason=mixedImplicitReason(model,state);assert(not reason,reason)
		local chosen,groups=copyTable(retained or {}),{}
		for _,entry in ipairs(chosen) do for _,group in ipairs(metadata[entry.id].groups) do groups[group]=true end end
		for _=1,(count or 1) do
			local eligible,total={},0
			for _,entry in ipairs(model.corruptions) do
				local legal=true;for _,group in ipairs(metadata[entry.id].groups) do if groups[group] then legal=false end end
				if legal then eligible[#eligible+1]=entry;total=total+entry.weight end
			end
			assert(total > 0,"No current corruption implicit is available for this base")
			local pick=random()*total;local id
			for _,entry in ipairs(eligible) do pick=pick-entry.weight;if pick < 0 then id=entry.id;break end end
			chosen[#chosen+1]={id=assert(id),range=M.rollRange(model.byId[id],random),corruption330=model.corruptions330[id] and true or nil}
			for _,group in ipairs(metadata[id].groups) do groups[group]=true end
		end
		state.corruptedImplicits=chosen
		if model.synthesisGroups then
			local retained=copyTable(state.synthRetained or {})
			if #retained==0 then for index in ipairs(model.synthesisGroups) do retained[#retained+1]=index end end
			local removed=#retained==1 and 1 or math.floor(random()*#retained)+1
			table.remove(retained,removed)
			state.synthRetained=#retained>0 and retained or nil
		end
		if state.implicits then
			if #state.implicits > 1 then table.remove(state.implicits,math.floor(random()*#state.implicits)+1)
			else state.implicits=nil end
		end
		state.baseImplicitRanges=nil;state.baseImplicit330=nil;state.baseImplicitReconstructed=nil;state.vendorImplicit=nil;state.corrupted=true
	end
	function M.decorateItem(model,state,item)
		originalDecorate(model,state,item)
		local twice=state.twiceCorrupted
		if twice==nil and state.corrupted~=false then
			if model.initial then twice=model.initial.twiceCorrupted else twice=model.item.twiceCorrupted end
		end
		item.twiceCorrupted=twice or nil
		if state.corruptedImplicits then
			if not state.implicits then item.implicitModLines={} end
			for _,index in ipairs(state.synthRetained or {}) do
				for _,source in ipairs(model.synthesisGroups[index]) do
					local line=copyTable(source);line.modGroup="synth_"..index;item.implicitModLines[#item.implicitModLines+1]=line
				end
			end
			for _,entry in ipairs(state.corruptedImplicits) do for _,line in ipairs(M.rolledLines(M.entryMod(model,entry),entry.range)) do item.implicitModLines[#item.implicitModLines+1]={line=line,modGroup="crafting_"..entry.id} end end
		end
	end
	function M.validateState(model,state)
		assert(type(state)=="table","Invalid crafting state")
		-- Missing markers inherit the starting text; explicit false is a manual override.
		if state.corrupted==nil and model.initial.corrupted then state=copyTable(state);state.corrupted=true end
		if state.twiceCorrupted==nil and state.corrupted and model.initial.twiceCorrupted then state=copyTable(state);state.twiceCorrupted=true end
		if not state.destroyed and state.corrupted and not state.corruptedImplicits and not state.implicits and not state.vendorImplicit and not state.baseImplicitRanges and model.initial.corruptedImplicits then
			state=copyTable(state);state.corruptedImplicits=copyTable(model.initial.corruptedImplicits)
		end
		if not state.destroyed and state.corruptedImplicits and not state.synthRetained and model.item.corrupted and model.synthesisGroups then
			state=copyTable(state);state.synthRetained={};for index in ipairs(model.synthesisGroups) do state.synthRetained[index]=index end
		end
		assert(state.twiceCorrupted==nil or type(state.twiceCorrupted)=="boolean","Invalid twice-corruption marker")
		assert(not state.twiceCorrupted or state.corrupted==true,"Twice Corrupted items must also be Corrupted")
		assert(state.destroyed == nil or type(state.destroyed) == "boolean","Invalid destruction flag")
		if state.destroyed then assert(type(state.affixes) == "table" and #state.affixes == 0,"Destroyed items cannot retain usable affixes") end
		if state.corruptedImplicits and model.item.synthesised and not model.item.corrupted then
			assert(model.synthesisGroups or #(model.item.implicitModLines or {})<=1,"Synthesised implicit grouping is unresolved")
			assert(not model.synthesisGroups or #model.synthesisGroups<=1 or state.synthRetained,"Missing retained synthesised modifiers")
		end
		if state.synthRetained then
			assert(type(state.synthRetained)=="table" and model.item.synthesised and model.synthesisGroups and state.corruptedImplicits,"Invalid retained synthesised implicit state")
			local seen={};for _,index in ipairs(state.synthRetained) do assert(type(index)=="number" and index==math.floor(index) and model.synthesisGroups[index] and not seen[index],"Invalid retained synthesised implicit");seen[index]=true end
			assert(#state.synthRetained>=1 and #state.synthRetained<=2,"Invalid retained synthesised implicit count")
			assert(#state.synthRetained==#model.synthesisGroups-(model.item.corrupted and 0 or 1),"Retained synthesised modifiers do not match the corruption outcome")
		end
		if state.corruptedImplicits then
			assert(state.corrupted and #state.corruptedImplicits >= 1 and #state.corruptedImplicits + #(state.implicits or {}) <= 2 and (not state.synthRetained or #state.corruptedImplicits==1 and not state.implicits),"Invalid corruption implicit state")
			local groups={}
			for _,entry in ipairs(state.corruptedImplicits) do
				assert(model.corruptionIds[entry.id] or model.legacyCorruptionIds[entry.id],"Invalid corruption implicit for this base")
				assert(entry.corruption330==nil or (entry.corruption330==true and model.corruptions330[entry.id]),"Invalid 3.30 corruption modifier")
				for _,group in ipairs(metadata[entry.id].groups) do assert(not groups[group],"Conflicting corrupted implicits");groups[group]=true end
				local ranges=type(entry.range) == "table" and entry.range or {entry.range};assert(#ranges >= 1 and #ranges <= 20,"Invalid corruption range count")
				for _,range in ipairs(ranges) do assert(type(range) == "number" and range >= 0 and range <= 1,"Invalid corruption roll") end
			end
		end
		return originalValidate(model,state)
	end
	function M.action(model,input,craft,random)
		local method=craft.method
		if not labels[method] then return originalAction(model,input,craft,random) end
		assert(not input.destroyed and not input.mirrored and not input.veil,"Cannot craft a destroyed or mirrored item or an unfinished unveil")
		local state=copyTable(input)
		if method == "vaal" or method == "locus" then
			if method == "vaal" then assert(not input.corrupted,"The item is already corrupted")
			else
				assert(input.corrupted and not input.twiceCorrupted,"The 3.30 altar model requires a Corrupted item that is not Twice Corrupted")
				assert(not model.unresolvedCorruption or input.corruptedImplicits,"The existing corruption implicits must be identified first")
				assert(not input.implicits and not model.unresolvedEldritch,"Second corruption of Eldritch implicits is not modeled")
			end
			if method=="vaal" and model.item.type=="Flask" then
				-- The published range is known; equal weights are an explicit model assumption.
				state.quality=math.max(0,math.min(40,(state.quality or 0)+math.floor(random()*21)-10))
				state.corrupted=true;state.imprint=nil;return state
			end
			if method=="vaal" and model.item.type=="Jewel" and (model.item.base.subType=="Abyss" or model.item.clusterJewel or model.item.baseName=="Prismatic Jewel") then
				-- The four branches are equally weighted as an explicit, unverified model assumption.
				local outcome=math.floor(random()*4)
				if outcome==0 then M.rollCorrupted(model,state,random,1)
				elseif outcome==2 then
					local flags=api.flags(model,state);api.clear(model,state);state.rollBlock={attack=flags.attack,caster=flags.caster}
					state.rarity="RARE"
					while #state.affixes<M.capacities(model,state).total do
						local ok=pcall(api.add,model,state,random);if not ok then break end
					end
					state.rollBlock=nil
				end
				state.corrupted=true;state.imprint=nil;return state
			end
			assert((model.item.type ~= "Jewel" or method=="locus") and model.item.type ~= "Flask" and model.item.type ~= "Tincture","This corruption model supports equipment, jewel Locus corruption, Abyss, cluster and Prismatic jewel Vaal Orbs, and flask Vaal Orbs")
			if method == "locus" then
				local reason=M.methodChecks.locus(model,state);assert(not reason,reason)
			end
			local outcome=math.floor(random()*4)
			if outcome == 0 then
				local retained=method=="locus" and copyTable(state.corruptedImplicits or {}) or {}
				if #retained==2 then table.remove(retained,math.floor(random()*2)+1) end
				M.rollCorrupted(model,state,random,1,retained)
			elseif outcome == 1 then
				local white={};for i,socket in ipairs(state.sockets or {}) do if socket.color == "W" then white[#white+1]=i end end
				if #white > 0 then
					if method == "vaal" then
						local selected=white[math.floor(random()*#white)+1]
						state.sockets[selected].color=({"R","G","B"})[math.floor(random()*3)+1]
					else
						for _,i in ipairs(white) do state.sockets[i].color=({"R","G","B"})[math.floor(random()*3)+1] end
					end
				end
			elseif outcome == 2 and method ~= "locus" then
				-- Keep fractures and metamod-protected affixes on the rare reroll.
				-- Its socket and link outcome is not modeled. Preserve the prior
				-- layout only as an editable placeholder, never as a known result.
				if M.socketLimit(model,state)>0 then state.socketLayoutUnknown=true end
				state.corrupted=false;local flags=api.flags(model,state);api.clear(model,state);state.rollBlock={attack=flags.attack,caster=flags.caster}
				state.rarity="RARE"
				while #state.affixes < M.capacities(model,state).total do
					local ok=pcall(api.add,model,state,random);if not ok then break end
				end
				state.rollBlock=nil
			elseif method == "locus" then state.destroyed=true;state.affixes={};state.implicits=nil;state.corruptedImplicits=nil
			end
			state.corrupted=true;state.imprint=nil
			if method=="locus" and not state.destroyed then state.twiceCorrupted=true end
		else
			assert(input.corrupted and state.rarity == "RARE","Tainted affix currency requires a corrupted rare item")
			if method == "tainted_exalt" then state=api.taintedAffixAction(model,state,{method=random() < 0.5 and "exalt" or "annul"},random)
			elseif random() < 0.5 then state=api.taintedAffixAction(model,state,{method="chaos"},random)
			else state=api.taintedAffixAction(model,state,{method="scour"},random) end
			state.corrupted=true
		end
		return state
	end
	M.limits[#M.limits+1]="Flask Vaal quality changes by an integer from -10 to +10, clamped to 0-40; equal weights are assumed and unverified."
	M.limits[#M.limits+1]="Abyss, cluster and Prismatic jewel Vaal outcomes use assumed equal weights; rare rerolls use the ordinary four-affix limit, and the unique-jewel outcome is modeled as no change. These outcomes and probabilities are unverified."
	M.limits[#M.limits+1]="The equipment Vaal model includes the four outcome branches and current non-white socket conversion. Rare-brick socket/link rerolls are not modeled; tainted affix outcomes use a 50/50 assumption."
	M.limits[#M.limits+1]="Corrupting unidentified Eldritch implicits or ambiguously grouped synthesised implicits is not modeled. Replacement is selected uniformly as an unverified assumption."
	M.limits[#M.limits+1]="The 3.30 Locus model requires a Corrupted item and adds a second corruption. Outcome chances, socket conversion and selection of a replaced implicit are assumptions; uncorrupted altar use is not modeled. Fractured, synthesised, meta-modified and special transformation bases are excluded."
end
return C
