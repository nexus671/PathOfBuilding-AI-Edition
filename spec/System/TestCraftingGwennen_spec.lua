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
