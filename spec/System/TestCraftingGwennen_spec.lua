describe("Experimental Gwennen pair",function()
	local sim=require("Modules.CraftingSimulator")
	local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86"
	local function item()
		local model=sim.model(raw);local state=sim.perform(raw,{method="alchemy"},4).state
		while #state.affixes>3 do state=sim.action(model,state,{method="annul"},function() return 0.3 end) end
		return model,state
	end
	it("selects either observed branch without changing the input",function()
		local model,state=item();local original=copyTable(state)
		local pair={method="gwennen",firstOutcome=1000,secondOutcome=1022}
		local intact,first=sim.action(model,state,pair,function() return 0.1 end)
		local destroyed,second=sim.action(model,state,pair,function() return 0.9 end)
		assert.same(original,state);assert.same(original,intact);assert.is_true(destroyed.destroyed);assert.equal(0,#destroyed.affixes)
		assert.equal(1000,first.gwennen.outcome);assert.equal(1022,second.gwennen.outcome)
	end)
	it("runs add and remove branches and reports estimates on calculations",function()
		local model,state=item();local pair={method="gwennen",firstOutcome=1004,secondOutcome=1005}
		local removed=sim.action(model,state,pair,function() return 0.1 end)
		local added=sim.action(model,state,pair,function() return 0.9 end)
		assert.equal(#state.affixes-1,#removed.affixes);assert.equal(#state.affixes+1,#added.affixes)
		local result=sim.perform(raw,pair,7,state);assert.equal("gwennen_estimate",result.warnings[1].code);assert.is_not_nil(result.gwennen.outcome)
		local odds=sim.calculate(raw,pair,{},state,{requirements={minAffixes=1},trials=4});assert.equal("gwennen_estimate",odds.warnings[1].code)
	end)
	it("models the Pantheon Aspect branch using the documented Brinehook assumptions",function()
		local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="RARE";state.affixes={}
		local original=copyTable(state);local pair={method="gwennen",firstOutcome=1013,secondOutcome=1000}
		local found={}
		for _,choice in ipairs({0.01,0.26,0.51,0.76}) do
			local draws={0.1,choice};local at=0
			local result=sim.action(model,state,pair,function() at=at+1;return draws[at] or 0.5 end)
			assert.equal(1,#result.affixes);local id=result.affixes[1].id
			assert.is_truthy(id:find("AspectCrafted",1,true));assert.equal("Suffix",model.byId[id].type)
			found[id]=true;sim.validateState(model,result);assert.is_truthy(sim.toItem(model,result).raw)
		end
		local count=0;for _ in pairs(found) do count=count+1 end;assert.equal(4,count);assert.same(original,state)
		local result=sim.perform(raw,pair,7,state);assert.equal("gwennen_pantheon_assumptions",result.warnings[2].code)
		local full=copyTable(state);local groups={}
		for _,candidate in ipairs(model.mods) do local mod=candidate.mod
			if mod.type=="Suffix" and not groups[mod.group] then full.affixes[#full.affixes+1]={id=candidate.id,range=0.5};groups[mod.group]=true;if #full.affixes==3 then break end end
		end
		assert.equal(3,#full.affixes)
		assert.has_error(function() sim.action(model,full,pair,function() return 0.1 end) end)
	end)
	it("rerolls while retaining the selected original modifier and its values",function()
		local model,state=item();local original=copyTable(state);local pair={method="gwennen",firstOutcome=1027,secondOutcome=1000}
		for selected=1,#state.affixes do
			local draws={0.1,(selected-0.5)/#state.affixes,0.1};local at=0
			local result,detail=sim.action(model,state,pair,function() at=at+1;return draws[at] or 0.37 end)
			assert.equal(1027,detail.gwennen.outcome);assert.same(state.affixes[selected],result.affixes[1]);assert.equal(4,#result.affixes)
			sim.validateState(model,result);assert.is_truthy(sim.toItem(model,result).raw);assert.same(original,state)
		end
		local unchanged=sim.action(model,state,pair,function() return 0.9 end);assert.same(original,unchanged)
		local empty=copyTable(state);empty.affixes={};assert.has_error(function() sim.action(model,empty,pair,function() return 0.1 end) end)
		local odds=sim.calculate(raw,pair,{},state,{requirements={minAffixes=4},trials=4})
		assert.is_true(odds.sampled);assert.equal("gwennen_preserve_assumptions",odds.warnings[2].code)
	end)
	it("charges observed artifacts and never treats an unknown price as free",function()
		local pair={method="gwennen",firstOutcome=1000,secondOutcome=1022}
		local astragali="Metadata/Items/Currency/CurrencyRefreshGambler"
		local grand="Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction1_3"
		assert.same({[astragali]=1,["gwennen:observed_artifacts"]=1},sim.components(pair))
		pair.artifactCost={grand=20};assert.same({[astragali]=1,[grand]=20},sim.components(pair))
		local _,state=item();local result=sim.simulate(raw,{initialState=state,steps={pair},targets={},requirements={minQuality=20}},{trials=2,maxActions=1})
		local usage={};for _,entry in ipairs(result.resourceUsage) do usage[entry.key]=entry.amount end
		assert.equal(2,usage[astragali]);assert.equal(40,usage[grand]);assert.is_nil(result.meanCost)
		assert.has_error(function() sim.components({method="gwennen",firstOutcome=1000,secondOutcome=1022,artifactCost={grand=-1}}) end)
		assert.has_error(function() sim.validateRecipe({steps={{method="unsupported_method",firstOutcome=1000,secondOutcome=1022}},targets={},requirements={minAffixes=1}}) end)
		assert.has_error(function() sim.validateRecipe({steps={{method="gwennen",firstOutcome=1000,secondOutcome=1044}},targets={},requirements={minAffixes=1}}) end)
	end)
	it("models the quality and modifier reroll branches",function()
		local model,state=item();local before=copyTable(state)
		local quality=sim.action(model,state,{method="gwennen",firstOutcome=1029,secondOutcome=1000},function() return 0.1 end)
		assert.equal(20,quality.quality);assert.same(before.affixes,quality.affixes)
		local rerolled=sim.action(model,state,{method="gwennen",firstOutcome=1014,secondOutcome=1015},function() return 0.1 end)
		assert.equal("RARE",rerolled.rarity);assert.is_true(#rerolled.affixes>=4)
		local values=sim.action(model,state,{method="gwennen",firstOutcome=1014,secondOutcome=1015},function() return 0.9 end)
		for i,entry in ipairs(values.affixes) do assert.equal(before.affixes[i].id,entry.id) end
		assert.same(before,state)
	end)
	it("adds and removes only the selected affix side",function()
		local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="RARE";state.affixes={}
		local groups={};for _,side in ipairs({"Prefix","Suffix"}) do
			for _,candidate in ipairs(model.mods) do local mod=candidate.mod
				if mod.type==side and not groups[mod.group] then state.affixes[#state.affixes+1]={id=candidate.id,range=0.5};groups[mod.group]=true;break end
			end
		end
		assert.equal(2,#state.affixes);local before=copyTable(state)
		for _,case in ipairs({{1006,"Suffix"},{1007,"Prefix"}}) do
			local result=sim.action(model,state,{method="gwennen",firstOutcome=case[1],secondOutcome=1000},function() return 0.1 end)
			assert.equal(1,#result.affixes);assert.are_not.equal(case[2],model.byId[result.affixes[1].id].type)
		end
		for _,case in ipairs({{1008,"Suffix"},{1009,"Prefix"}}) do
			local result=sim.action(model,state,{method="gwennen",firstOutcome=case[1],secondOutcome=1000},function() return 0.1 end)
			assert.equal(3,#result.affixes);assert.equal(case[2],model.byId[result.affixes[3].id].type)
		end
		assert.same(before,state)
	end)
	it("rerolls only the selected side and preserves its modeled count",function()
		local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="RARE";state.affixes={}
		local groups,counts={}, {Prefix=0,Suffix=0}
		for _,candidate in ipairs(model.mods) do local mod=candidate.mod
			if counts[mod.type] and counts[mod.type]<2 and not groups[mod.group] then
				state.affixes[#state.affixes+1]={id=candidate.id,range=0.5};groups[mod.group]=true;counts[mod.type]=counts[mod.type]+1
			end
		end
		assert.equal(4,#state.affixes);local before=copyTable(state)
		for _,case in ipairs({{1018,"Prefix","Suffix"},{1019,"Suffix","Prefix"}}) do
			local pair={method="gwennen",firstOutcome=case[1],secondOutcome=1000}
			for _,draw in ipairs({0.1,0.3,0.49}) do
				local result=sim.action(model,state,pair,function() return draw end);local actual={Prefix=0,Suffix=0};local untouched={}
				for _,entry in ipairs(result.affixes) do local side=model.byId[entry.id].type;actual[side]=actual[side]+1;if side==case[3] then untouched[#untouched+1]=entry end end
				local expected={};for _,entry in ipairs(before.affixes) do if model.byId[entry.id].type==case[3] then expected[#expected+1]=entry end end
				assert.same(counts,actual);assert.same(expected,untouched);assert.same(before,state)
				sim.validateState(model,result);assert.is_truthy(sim.toItem(model,result).raw)
			end
			local estimate=sim.calculate(raw,pair,{},state,{requirements={minQuality=20},trials=4})
			assert.is_true(estimate.sampled);assert.equal("gwennen_side_reroll_assumptions",estimate.warnings[2].code)
		end
		local empty=copyTable(state);for i=#empty.affixes,1,-1 do if model.byId[empty.affixes[i].id].type=="Prefix" then table.remove(empty.affixes,i) end end
		assert.has_error(function() sim.action(model,empty,{method="gwennen",firstOutcome=1018,secondOutcome=1000},function() return 0.1 end) end)
	end)
	it("models random influence and counts influence goals under stated assumptions",function()
		local model,state=item();local before=copyTable(state);local pair={method="gwennen",firstOutcome=1031,secondOutcome=1031}
		local kinds={"shaper","elder","adjudicator","basilisk","crusader","eyrie"}
		for i,key in ipairs(kinds) do
			local result=sim.action(model,state,pair,function() return (i-0.5)/#kinds end)
			assert.same({key},result.influences);assert.same(before.affixes,result.affixes);assert.same(before,state)
			assert.is_true(sim.matches(result,{},nil,model,{influence=key}));sim.validateState(model,result)
			assert.is_truthy(sim.toItem(model,result).raw)
		end
		local odds=sim.calculate(raw,pair,{},state,{requirements={influence="shaper"}})
		assert.is_false(odds.sampled);assert.are.near(100/6,odds.successChance,1e-8);assert.equal(12,#odds.outcomes)
		assert.equal("gwennen_influence_assumptions",odds.warnings[2].code)
		local existing=copyTable(state);existing.influences={"shaper"}
		assert.has_error(function() sim.action(model,existing,pair,function() return 0.1 end) end)
		assert.has_error(function() sim.validateRecipe({steps={pair},targets={},requirements={influence="unknown"}}) end)
	end)
	it("saves and reopens a guide with an influence target",function()
		newBuild()
		local recipe={steps={{method="gwennen",firstOutcome=1031,secondOutcome=1031}},targets={},requirements={influence="shaper"}}
		build.savers.CraftingProjects:Upsert({id="influence",title="Influenced helmet",slot="Helmet",startingItem=raw,goals={},steps={},nativeRecipe=recipe})
		local xml=build:SaveDB("Influence guide");loadBuildFromXML(xml,"Influence guide")
		assert.equal("shaper",build.savers.CraftingProjects.projects[1].nativeRecipe.requirements.influence)
	end)
	it("continues crafting with the influence gained from a Gwennen pair",function()
		local model,state=item()
		local influenced=sim.action(model,state,{method="gwennen",firstOutcome=1031,secondOutcome=1031},function() return 0.01 end)
		assert.same({"shaper"},influenced.influences)
		local rebuilt=sim.toItem(model,influenced)
		assert.is_true(rebuilt.shaper)
		local shaperTag=model.item.base.influenceTags.shaper
		local influencedMod
		for _,entry in ipairs(sim.pool(model,influenced)) do
			for _,tag in ipairs(model.byId[entry.id].weightKey or {}) do
				if tag==shaperTag then influencedMod=true end
			end
		end
		assert.is_true(influencedMod)
		local nextState=sim.action(model,influenced,{method="beast_influence",influence="shaper"},function() return 0.1 end)
		assert.equal(#influenced.affixes+1,#nextState.affixes)
		assert.same({"shaper"},nextState.influences)
		sim.validateState(model,nextState)
	end)
	it("models explicit removal, retained modifiers and filled slots",function()
		local model,state=item();local before=copyTable(state)
		local cleared=sim.action(model,state,{method="gwennen",firstOutcome=1001,secondOutcome=1000},function() return 0.1 end)
		assert.equal("NORMAL",cleared.rarity);assert.equal(0,#cleared.affixes)
		local kept=sim.action(model,state,{method="gwennen",firstOutcome=1023,secondOutcome=1000},function() return 0.1 end)
		assert.equal("RARE",kept.rarity);assert.equal(1,#kept.affixes);assert.equal(state.affixes[1].id,kept.affixes[1].id)
		local filled=sim.action(model,state,{method="gwennen",firstOutcome=1025,secondOutcome=1000},function() return 0.1 end)
		assert.equal(sim.capacities(model,state).total,#filled.affixes)
		local pair={method="gwennen",firstOutcome=1026,secondOutcome=1026}
		assert.equal(#state.affixes-1,#sim.action(model,state,pair,function() return 0.1 end).affixes)
		assert.equal(#state.affixes-3,#sim.action(model,state,pair,function() return 0.9 end).affixes)
		assert.same(before,state)
	end)
	it("removes a lowest-level modifier and protects maximum rolls",function()
		local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="RARE";state.affixes={}
		local groups,counts={}, {Prefix=0,Suffix=0}
		for _,candidate in ipairs(model.mods) do
			local mod=candidate.mod;local text=table.concat(mod," / ")
			if #state.affixes<3 and counts[mod.type] and counts[mod.type]<2 and not groups[mod.group] and text:match("%(%-?%d+%-%-?%d+%)") then
				state.affixes[#state.affixes+1]={id=candidate.id,range=#state.affixes==0 and 0.2 or 1};groups[mod.group]=true;counts[mod.type]=counts[mod.type]+1
			end
		end
		assert.equal(3,#state.affixes);local before=copyTable(state)
		local removed=sim.action(model,state,{method="gwennen",firstOutcome=1041,secondOutcome=1000},function() return 0.1 end)
		local lowest=math.huge;for _,entry in ipairs(state.affixes) do lowest=math.min(lowest,model.byId[entry.id].level) end
		local remaining={};for _,entry in ipairs(removed.affixes) do remaining[entry.id]=true end
		local found;for _,entry in ipairs(state.affixes) do if not remaining[entry.id] then found=entry end end
		assert.equal(lowest,model.byId[found.id].level)
		for _,id in ipairs({1024,1042}) do
			local result=sim.action(model,state,{method="gwennen",firstOutcome=id,secondOutcome=1000},function() return 0.1 end)
			assert.same(before.affixes[2],result.affixes[2]);assert.same(before.affixes[3],result.affixes[3])
			assert.are_not.same(before.affixes[1].range,result.affixes[1].range)
		end
		local maximum=copyTable(state);for _,entry in ipairs(maximum.affixes) do entry.range=1 end
		assert.has_error(function() sim.action(model,maximum,{method="gwennen",firstOutcome=1024,secondOutcome=1000},function() return 0.1 end) end)
		assert.same(before,state)
	end)
	it("enumerates deterministic pairs under the assumed fair coin",function()
		local _,state=item();local pair={method="gwennen",firstOutcome=1000,secondOutcome=1022}
		local result=sim.calculate(raw,pair,{},state,{requirements={minAffixes=1}})
		assert.is_false(result.sampled);assert.equal(50,result.successChance);assert.equal(2,#result.outcomes)
		assert.equal(50,result.outcomes[1].chance);assert.is_true(result.outcomes[2].state.destroyed)
		assert.equal("gwennen_estimate",result.warnings[1].code)
		pair.firstOutcome=1022;pair.secondOutcome=1022
		local destroyed=sim.calculate(raw,pair,{},state,{requirements={minAffixes=1}})
		assert.equal(0,destroyed.successChance);assert.is_nil(destroyed.sampleItem)
	end)
	it("enumerates removal choices and unordered multi-removal sets",function()
		local _,state=item();local target={{anyOf={state.affixes[1].id}}}
		local odds=sim.calculate(raw,{method="gwennen",firstOutcome=1004,secondOutcome=1000},target,state)
		assert.is_false(odds.sampled);assert.are.near(100*5/6,odds.successChance,1e-8);assert.equal(4,#odds.outcomes)
		local multi=sim.calculate(raw,{method="gwennen",firstOutcome=1026,secondOutcome=1026},{},state,{requirements={maxAffixes=0}})
		assert.is_false(multi.sampled);assert.are.near(100/3,multi.successChance,1e-8);assert.equal(14,#multi.outcomes)
		local total=0;for _,outcome in ipairs(multi.outcomes) do total=total+outcome.chance end;assert.are.near(100,total,1e-8)
	end)
	it("reuses bounded fracture and corruption transitions without consuming their currencies",function()
		local model=sim.model(raw);local state=sim.perform(raw,{method="alchemy"},4).state
		assert.is_true(#state.affixes>=4)
		local fracture={method="gwennen",firstOutcome=1003,secondOutcome=1000}
		local fractured=sim.action(model,state,fracture,function() return 0.1 end)
		local count=0;for _,entry in ipairs(fractured.affixes) do if entry.fractured then count=count+1 end end;assert.equal(1,count)
		assert.has_error(function() sim.action(model,fractured,fracture,function() return 0.1 end) end)
		local corrupt={method="gwennen",firstOutcome=1012,secondOutcome=1012}
		local result=sim.action(model,state,corrupt,function() return 0.9 end);assert.is_true(result.corrupted)
		assert.equal("gwennen_corruption",sim.actionWarnings(corrupt)[2].code)
		local cost=sim.components(fracture);assert.is_nil(cost.fracture);assert.is_nil(cost.vaal)
	end)
	it("rejects unsupported pairs and a pair with an unusable branch",function()
		local model,state=item()
		assert.has_error(function() sim.action(model,state,{method="gwennen",firstOutcome=1000,secondOutcome=1044},function() return 0.1 end) end)
		state.affixes={}
		assert.has_error(function() sim.action(model,state,{method="gwennen",firstOutcome=1000,secondOutcome=1004},function() return 0.1 end) end)
		state.corrupted=true
		assert.has_error(function() sim.action(model,state,{method="gwennen",firstOutcome=1000,secondOutcome=1022},function() return 0.1 end) end)
	end)
end)
