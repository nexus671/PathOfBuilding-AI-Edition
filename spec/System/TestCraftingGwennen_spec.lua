describe("Experimental Gwennen pair",function()
	local sim=require("Modules.CraftingSimulator")
	local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86"
	local function item()
		local model=sim.model(raw);local state=sim.perform(raw,{method="alchemy"},4).state
		while #state.affixes>3 do state=sim.action(model,state,{method="annul"},function() return 0.3 end) end
		return model,state
	end
	it("shows the commitment before a pair is recorded",function()
		newBuild()
		local controls=require("Classes.CraftingGwennenControl").Open(function() end)
		local rows={};for _,row in ipairs(controls.intro.list) do rows[#rows+1]=StripEscapes(row[1] or "") end
		assert.matches("keeps the item",table.concat(rows," "));assert.is_true(#rows<=2)
		main.popups={}
	end)
	it("reports an incomplete pair to the catalog and workbench",function()
		newBuild()
		local model,state=item()
		local reason=sim.configurationReason(model,state,{method="gwennen"})
		assert.matches("Configure a supported Gwennen pair",reason)
		local catalog=sim.catalog(raw,"",5,state);local row
		for _,entry in ipairs(catalog.methodAvailability) do if entry.method=="gwennen" then row=entry end end
		assert.is_true(row.available);assert.equal(reason,row.configurationRequired)
		local invalid={method="gwennen",firstOutcome=1000,secondOutcome=1022,artifactCost={grand=-1}}
		assert.equal(reason,sim.configurationReason(model,state,invalid))
		local pair={method="gwennen",firstOutcome=1000,secondOutcome=1022,artifactCost={grand=20}}
		assert.is_nil(sim.configurationReason(model,state,pair))
		assert.is_not_nil(sim.perform(raw,pair,1,state).gwennen)
		local project={id="gwennen-configuration",title="Helmet",slot="Helmet",startingItem=raw,goals={},steps={},run=require("Modules.CraftingInventory").run(state)}
		local controls=require("Classes.CraftingSimulatorControl").Open(build,project)
		controls.method:SelByValue("gwennen","val");controls.method.selFunc()
		assert.is_false(controls.apply:IsEnabled());assert.matches("Configure a supported Gwennen pair",controls.apply.tooltipText())
		local hints={};for _,row in ipairs(controls.actionHint.list) do hints[#hints+1]=StripEscapes(row[1] or "") end;assert.matches("Configure a supported Gwennen pair",table.concat(hints," "))
		main.popups={}
	end)
	it("checks both configured branches before applying without changing the item",function()
		newBuild()
		local ringRaw="Rarity: NORMAL\nGold Ring\nItem Level: 86";local model=sim.model(ringRaw);local state=copyTable(model.initial);state.rarity="RARE"
		local pair={method="gwennen",firstOutcome=1000,secondOutcome=1029};local before=copyTable(state)
		local reason=sim.gwennenPairReason(model,state,pair);assert.matches("quality outcome requires a weapon or armour",reason)
		assert.same(before,state);local ok,err=pcall(sim.action,model,state,pair,function() error("Should not draw") end);assert.is_false(ok);assert.matches("quality outcome requires",err)
		pair.firstOutcome,pair.secondOutcome=pair.secondOutcome,pair.firstOutcome;assert.matches("quality outcome requires",sim.gwennenPairReason(model,state,pair))
		local empty={method="gwennen",firstOutcome=1000,secondOutcome=1004};assert.is_not_nil(sim.gwennenPairReason(model,state,empty))
		local noSockets={method="gwennen",firstOutcome=1000,secondOutcome=1016};assert.is_not_nil(sim.gwennenPairReason(model,state,noSockets))
		local helmet=sim.model(raw);local helmetState=copyTable(helmet.initial);helmetState.rarity="RARE"
		assert.is_nil(sim.gwennenPairReason(helmet,helmetState,pair));assert.same(before,state)
		local randomPair={method="gwennen",firstOutcome=1005,secondOutcome=1000}
		local pristine=sim.model(raw);local pristineState=copyTable(pristine.initial);pristineState.rarity="RARE"
		assert.is_nil(sim.gwennenPairReason(helmet,helmetState,randomPair))
		local function random(seed) return function() seed=seed*48271%2147483647;return seed/2147483647 end end
		local afterProbe=sim.action(helmet,helmetState,randomPair,random(73));local withoutProbe=sim.action(pristine,pristineState,randomPair,random(73))
		assert.same(withoutProbe,afterProbe)
		local run=require("Modules.CraftingInventory").run(state);run.configured.gwennen=pair
		local project={id="gwennen-branch",title="Ring",slot="Ring 1",startingItem=ringRaw,goals={},steps={},run=run}
		local controls=require("Classes.CraftingSimulatorControl").Open(build,project);controls.method:SelByValue("gwennen","val");controls.method.selFunc()
		assert.is_false(controls.apply:IsEnabled());assert.matches("quality outcome requires",controls.apply.tooltipText())
		assert.is_false(controls.exact:IsEnabled());assert.is_true(controls.simulate:IsEnabled());assert.matches("without an action",controls.simulate.tooltipText())
		local simulation=sim.simulate(ringRaw,{steps={pair},targets={},requirements={minAffixes=0}},{initialState=state,trials=2,maxActions=1});assert.equal(2,simulation.successes)
		main.popups={}
	end)
	it("selects either observed branch without changing the input",function()
		local model,state=item();local original=copyTable(state)
		local pair={method="gwennen",firstOutcome=1000,secondOutcome=1022}
		local intact,first=sim.action(model,state,pair,function() return 0.1 end)
		local destroyed,second=sim.action(model,state,pair,function() return 0.9 end)
		assert.same(original,state);assert.same(original,intact);assert.is_true(destroyed.destroyed);assert.equal(0,#destroyed.affixes)
		assert.equal(1000,first.gwennen.outcome);assert.equal(1022,second.gwennen.outcome)
	end)
	it("models best-of prefix and suffix outcomes using independent candidate rolls",function()
		local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="RARE"
		state.affixes={{id="IncreasedLife2",range=0.5},{id="FireResist2",range=0.5}};local original=copyTable(state)
		local cases={{1033,1009,3,"Prefix"},{1034,1009,5,"Prefix"},{1035,1008,3,"Suffix"},{1036,1008,5,"Suffix"},{1037,1018,3,"Prefix"},{1038,1018,6,"Prefix"},{1039,1019,3,"Suffix"},{1040,1019,6,"Suffix"}}
		local function stream(seed) return function() seed=seed*48271%2147483647;return seed/2147483647 end end
		local function run(id,random)
			local first=true;return sim.action(model,state,{method="gwennen",firstOutcome=id,secondOutcome=1000},function() if first then first=false;return 0.1 end;return random() end)
		end
		local function score(item,side)
			local total,count=0,0;for _,entry in ipairs(item.affixes) do local mod=model.byId[entry.id];if mod.type==side then total=total+mod.level;count=count+1 end end;return total/count
		end
		for _,case in ipairs(cases) do for _,seed in ipairs({11,47,91}) do
			local actual=run(case[1],stream(seed));local random=stream(seed);local expected,best
			for _=1,case[3] do local candidate=run(case[2],random);local value=score(candidate,case[4]);if not best or value>best then best=value;expected=candidate end end
			assert.same(expected,actual);assert.same(original,state);sim.validateState(model,actual)
		end end
		local pair={method="gwennen",firstOutcome=1038,secondOutcome=1000}
		local warnings=sim.actionWarnings(pair,model);assert.equal("gwennen_best_assumptions",warnings[2].code)
		local result=sim.calculate(raw,pair,{},state,{requirements={minAffixes=1},trials=3,seed=7});assert.is_true(result.sampled);assert.equal("gwennen_best_assumptions",result.warnings[2].code)
	end)
	it("rerolls identifiable non-maximum ordinary and Eldritch implicits",function()
		local pair={method="gwennen",firstOutcome=1032,secondOutcome=1000}
		local source="Rarity: NORMAL\nCoral Ring\nItem Level: 86\nImplicits: 1\n+25 to maximum Life"
		local model=sim.model(source);local state=copyTable(model.initial);state.rarity="RARE";local original=copyTable(state)
		local rerolled=sim.action(model,state,pair,function() return 0 end)
		assert.same(original,state);assert.is_truthy(sim.toItem(model,rerolled).raw:find("+20 to maximum Life",1,true));sim.validateState(model,rerolled)
		local saved=require("Modules.CraftingCheckpoint").validate(source,require("Modules.CraftingInventory").run(rerolled)).state
		assert.is_truthy(sim.toItem(model,saved).raw:find("+20 to maximum Life",1,true))
		local legacy=copyTable(rerolled);legacy.baseImplicitReconstructed=nil;local legacyOK,legacyReason=pcall(sim.action,model,legacy,pair,function() return 0 end);assert.is_false(legacyOK);assert.matches("legacy implicit roll",legacyReason)
		local calculation=sim.calculate(source,pair,{},state,{requirements={minAffixes=0},trials=8,seed=7});assert.is_true(calculation.sampled);assert.equal("gwennen_implicit_assumptions",calculation.warnings[2].code)
		local maximum=sim.model(source:gsub("%+25","+30"));local full=copyTable(maximum.initial);full.rarity="RARE"
		local allowed,why=pcall(sim.action,maximum,full,pair,function() return 0 end);assert.is_false(allowed);assert.matches("No supported implicit",why);assert.is_nil(why:match("cannot apply:.-%.lua:"))
		local beforeFull=copyTable(full);assert.matches("below its maximum",require("Modules.CraftingGwennen").implicitReason(maximum,full));assert.same(beforeFull,full)
		assert.is_nil(require("Modules.CraftingGwennen").implicitReason(model,state));assert.same(original,state)
		local helm=sim.model(raw);local eldritch=sim.perform(raw,{method="eldritch_implicit",side="Exarch",tier=2},11).state
		eldritch=sim.perform(raw,{method="eldritch_implicit",side="Eater",tier=1},12,eldritch).state;eldritch.rarity="RARE"
		eldritch.implicits[1].id="SpellCriticalStrikeChanceEldritchImplicit2";eldritch.implicits[1].range=1;eldritch.implicits[2].id="EnergyShieldFromGlovesBootsEldritchImplicit1";eldritch.implicits[2].range=0;local before=copyTable(eldritch)
		local calls=0;local changed=sim.action(helm,eldritch,pair,function() calls=calls+1;return calls==1 and 0.1 or 0.5 end)
		assert.same(before,eldritch);assert.same(before.implicits[1],changed.implicits[1]);assert.not_same(before.implicits[2].range,changed.implicits[2].range)
		sim.validateState(helm,changed);local reopened=sim.model(sim.toItem(helm,changed).raw);assert.same(changed.implicits,reopened.initial.implicits)
		local warnings=sim.actionWarnings(pair,helm);assert.equal("gwennen_implicit_assumptions",warnings[2].code)
		local empty=copyTable(helm.initial);empty.rarity="RARE";local ok,reason=pcall(sim.action,helm,empty,pair,function() return 0 end);assert.is_false(ok);assert.matches("no supported implicit",reason)
		local invalid=sim.model(source:gsub("%+25","+99"));local unknown=copyTable(invalid.initial);unknown.rarity="RARE"
		assert.has_error(function() sim.action(invalid,unknown,pair,function() return 0 end) end)
		local steel=sim.model("Rarity: NORMAL\nSteel Ring\nItem Level: 86\nImplicits: 1\nAdds 3 to 14 Physical Damage to Attacks")
		local split=copyTable(steel.initial);split.rarity="RARE";local reroll=sim.action(steel,split,pair,function() return 0 end)
		assert.same({0,0},reroll.baseImplicitRanges[1]);sim.validateState(steel,reroll)
	end)
	it("rerolls a single varying line on multi-line ordinary base implicits",function()
		local pair={method="gwennen",firstOutcome=1032,secondOutcome=1000}
		for _,case in ipairs({
			{raw="Rarity: NORMAL\nGale Crown\nItem Level: 86\nImplicits: 2\nAdds 4 to 5 Cold Damage\nYour Hits treat Cold Resistance as 10% higher than actual value",expected="Adds 3 to 5 Cold Damage",fixed="Your Hits treat Cold Resistance as 10% higher than actual value"},
			{raw="Rarity: NORMAL\nDuskwalk Slippers\nItem Level: 86\nImplicits: 2\n10% reduced Movement Speed\n47% increased Cooldown Recovery Rate of Movement Skills",expected="45% increased Cooldown Recovery Rate of Movement Skills",fixed="10% reduced Movement Speed"},
		}) do
			local model=sim.model(case.raw);local state=copyTable(model.initial);state.rarity="RARE";local original=copyTable(state)
			local result=sim.action(model,state,pair,function() return 0 end)
			assert.same(original,state);sim.validateState(model,result)
			local text=sim.toItem(model,result).raw
			assert.is_truthy(text:find(case.expected,1,true));assert.is_truthy(text:find(case.fixed,1,true))
			local restored=require("Modules.CraftingCheckpoint").validate(case.raw,require("Modules.CraftingInventory").run(result)).state
			assert.same(result.baseImplicitRanges,restored.baseImplicitRanges)
			assert.is_truthy(sim.toItem(model,restored).raw:find(case.expected,1,true))
		end
	end)
	it("retains synthesised implicit identities and rolls through saving and corruption",function()
		local source="Rarity: NORMAL\nGold Amulet\nItem Level: 86\nImplicits: 2\n{range:0}(8-10)% increased maximum Life\n+20 to Dexterity\nSynthesised Item"
		local model=sim.model(source);local state=copyTable(model.initial);state.rarity="RARE";local original=copyTable(state)
		assert.equal(1,#model.synthesisGroups[1].candidates);assert.equal(1,#model.synthesisGroups[2].candidates)
		local calls=0;local changed=sim.action(model,state,{method="gwennen",firstOutcome=1032,secondOutcome=1000},function() calls=calls+1;return calls==1 and 0.1 or 0.999999 end)
		assert.same(original,state);assert.equal(1,changed.synthRolls[1].range);assert.equal(model.synthesisGroups[2].candidates[1].range,changed.synthRolls[2].range)
		local target={{scope="implicit",anyOf={changed.synthRolls[1].id},minRoll=0.9}};assert.is_true(sim.matches(changed,target,nil,model))
		local saved=require("Modules.CraftingCheckpoint").validate(source,require("Modules.CraftingInventory").run(changed)).state;assert.same(changed.synthRolls,saved.synthRolls)
		newBuild();build.savers.CraftingProjects:Upsert({id="synth-reroll",title="Synthesised amulet",slot="Amulet",startingItem=source,goals={},steps={},run=require("Modules.CraftingInventory").run(changed)})
		local xml=build:SaveDB("Synthesised reroll");loadBuildFromXML(xml,"Synthesised reroll");assert.same(changed.synthRolls,build.savers.CraftingProjects.projects[1].run.state.synthRolls)
		local item=sim.toItem(model,saved);local reopened=sim.model(item.raw);assert.equal(changed.synthRolls[1].id,reopened.synthesisGroups[1].candidates[1].id);assert.is_true(sim.matches(reopened.initial,target,nil,reopened))
		local copied=copyTable(changed);sim.rollCorrupted(model,copied,function() return 0.999999 end);copied=sim.validateState(model,copied)
		assert.same({1},copied.synthRetained);assert.is_true(sim.matches(copied,target,nil,model));local reopenedCorrupted=sim.model(sim.toItem(model,copied).raw)
		assert.equal(changed.synthRolls[1].id,reopenedCorrupted.synthesisGroups[1].candidates[1].id);assert.is_true(sim.matches(reopenedCorrupted.initial,target,nil,reopenedCorrupted))
		local invalid=copyTable(changed);invalid.synthRolls[1].id="forged";assert.has_error(function() sim.validateState(model,invalid) end)
		invalid=copyTable(changed);invalid.synthRolls[1].range={0,1};assert.has_error(function() sim.validateState(model,invalid) end)
		invalid=copyTable(changed);invalid.synthRolls[1].extra=true;assert.has_error(function() sim.validateState(model,invalid) end)
		local ambiguous=sim.model(source:gsub("{range:0}%(8%-10%)%% increased maximum Life","8%% increased maximum Life"));local unknown=copyTable(ambiguous.initial);unknown.rarity="RARE"
		assert.has_error(function() sim.action(ambiguous,unknown,{method="gwennen",firstOutcome=1032,secondOutcome=1000},function() return 0 end) end)
	end)
	it("retains the Gilded implicit when rerolling synthesised implicits",function()
		local source="Rarity: NORMAL\nGold Amulet\nItem Level: 86\nImplicits: 3\n{range:0}(8-10)% increased maximum Life\n+20 to Dexterity\nItem sells for much more to vendors\nSynthesised Item"
		local model=sim.model(source);local state=copyTable(model.initial);state.rarity="RARE"
		assert.equal("unknown",state.vendorImplicit);assert.equal(2,#model.synthesisGroups)
		local calls=0;local changed=sim.action(model,state,{method="gwennen",firstOutcome=1032,secondOutcome=1000},function() calls=calls+1;return calls==1 and 0.1 or 0.999999 end)
		assert.equal("unknown",changed.vendorImplicit);assert.equal(1,changed.synthRolls[1].range)
		local saved=require("Modules.CraftingCheckpoint").validate(source,require("Modules.CraftingInventory").run(changed)).state
		local output=sim.toItem(model,saved).raw;assert.is_truthy(output:find("Item sells for much more to vendors",1,true))
		local reopened=sim.model(output);assert.equal("unknown",reopened.initial.vendorImplicit);assert.equal(2,#reopened.synthesisGroups)
		local invalid=copyTable(changed);invalid.vendorImplicit="Strength1";assert.has_error(function() sim.validateState(model,invalid) end)
	end)
	it("keeps independent synthesised values and refuses forged identities",function()
		local source="Rarity: NORMAL\nCopper Sword\nItem Level: 86\nImplicits: 1\nAdds 4 to 9 Fire Damage\nSynthesised Item"
		local model=sim.model(source);assert.equal(1,#model.synthesisGroups[1].candidates);local state=copyTable(model.initial);state.rarity="RARE"
		local calls=0;local changed=sim.action(model,state,{method="gwennen",firstOutcome=1032,secondOutcome=1000},function() calls=calls+1;return calls==1 and 0.1 or calls==2 and 0 or 0.999999 end)
		assert.same({0,1},changed.synthRolls[1].range);local item=sim.toItem(model,changed);assert.is_truthy(item.raw:find("Adds 4 to 15 Fire Damage",1,true))
		local reopened=sim.model(item.raw);assert.equal(changed.synthRolls[1].id,reopened.synthesisGroups[1].candidates[1].id);assert.same({0,1},reopened.synthesisGroups[1].candidates[1].range)
		local forged=item.raw:gsub("synth_id_"..changed.synthRolls[1].id,"synth_id_NotARealImplicit");assert.is_nil(sim.model(forged).synthesisGroups)
		local inconsistent=item.raw:gsub("Adds 4 to 15 Fire Damage","Adds 5 to 15 Fire Damage");assert.is_nil(sim.model(inconsistent).synthesisGroups)
	end)
	it("preserves fractional synthesised rolls in exported item text",function()
		local source="Rarity: NORMAL\nGold Amulet\nItem Level: 86\nImplicits: 1\n{range:0}Regenerate (11.7-18.3) Life per second\nSynthesised Item"
		local model=sim.model(source);assert.is_truthy(model.synthesisGroups);local state=copyTable(model.initial);state.rarity="RARE"
		local calls=0;local changed=sim.action(model,state,{method="gwennen",firstOutcome=1032,secondOutcome=1000},function() calls=calls+1;return calls==1 and 0.1 or 0.37 end)
		local reopened=sim.model(sim.toItem(model,changed).raw);assert.are.near(changed.synthRolls[1].range,reopened.synthesisGroups[1].candidates[1].range,0.000001)
	end)
	it("retains catalyst scaling on rerolled synthesised implicits",function()
		local source="Rarity: NORMAL\nGold Amulet\nItem Level: 86\nCatalyst: Fertile\nCatalystQuality: 20\nImplicits: 1\n{tags:resource,life}{range:0}(8-10)% increased maximum Life\nSynthesised Item"
		local model=sim.model(source);local state=copyTable(model.initial);state.rarity="RARE";local calls=0
		local changed=sim.action(model,state,{method="gwennen",firstOutcome=1032,secondOutcome=1000},function() calls=calls+1;return calls==1 and 0.1 or 0.999999 end)
		local item=sim.toItem(model,changed);assert.is_truthy(item.raw:find("{tags:resource,life}",1,true));assert.equal("12% increased maximum Life",StripEscapes(itemLib.formatModLine(item.implicitModLines[1],false)))
		local reopened=sim.model(item.raw);local restored=sim.toItem(reopened,reopened.initial);assert.equal("12% increased maximum Life",StripEscapes(itemLib.formatModLine(restored.implicitModLines[1],false)))
		local unscaled=sim.model(source:gsub("{tags:resource,life}","{unscalable}{tags:resource,life}"));local unscaledState=copyTable(unscaled.initial);unscaledState.rarity="RARE";calls=0
		local unscaledResult=sim.action(unscaled,unscaledState,{method="gwennen",firstOutcome=1032,secondOutcome=1000},function() calls=calls+1;return calls==1 and 0.1 or 0.999999 end)
		local unscaledItem=sim.toItem(unscaled,unscaledResult);assert.is_true(unscaledItem.implicitModLines[1].unscalable);assert.equal("10% increased maximum Life",StripEscapes(itemLib.formatModLine(unscaledItem.implicitModLines[1],false)))
	end)
	it("runs add and remove branches and reports estimates on calculations",function()
		local model,state=item();local pair={method="gwennen",firstOutcome=1004,secondOutcome=1005}
		local removed=sim.action(model,state,pair,function() return 0.1 end)
		local added=sim.action(model,state,pair,function() return 0.9 end)
		assert.equal(#state.affixes-1,#removed.affixes);assert.equal(#state.affixes+1,#added.affixes)
		local result=sim.perform(raw,pair,7,state);assert.equal("gwennen_estimate",result.warnings[1].code);assert.equal("gwennen_empty_sockets",result.warnings[2].code);assert.matches("socketed gems",result.warnings[2].message);assert.is_not_nil(result.gwennen.outcome)
		local odds=sim.calculate(raw,pair,{},state,{requirements={minAffixes=1},trials=4});assert.equal("gwennen_estimate",odds.warnings[1].code);assert.equal("gwennen_empty_sockets",odds.warnings[2].code)
		for _,response in ipairs({result,odds}) do
			local commitment
			for _,warning in ipairs(response.warnings) do if warning.code=="gwennen_item_commitment" then commitment=warning end end
			assert.is_not_nil(commitment);assert.matches("keeps the item",commitment.message);assert.equal("https://www.pathofexile.com/forum/view-thread/4014963",commitment.source)
		end
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
	it("selects the first best of the stated socket-colour rerolls",function()
		local socketRaw="Rarity: NORMAL\nPlate Vest\nItem Level: 86\nSockets: R-G B W-W W"
		local model=sim.model(socketRaw);local state=copyTable(model.initial);state.rarity="RARE";local before=copyTable(state)
		local function stream() local seed=91;return function() seed=(seed*48271)%2147483647;return seed/2147483647 end end
		for _,case in ipairs({{1010,50},{1011,20}}) do
			local draw=stream();draw();local best,score=nil,-1
			for _=1,case[2] do
				local candidate=sim.action(model,state,{method="chromatic"},draw);local count=0
				for _,socket in ipairs(candidate.sockets) do if socket.color~="W" and socket.color~="A" then count=count+1 end end
				if count>score then best,score=candidate,count end
			end
			local pair={method="gwennen",firstOutcome=case[1],secondOutcome=case[1]};local actualDraw=stream();local actual=sim.action(model,state,pair,actualDraw)
			assert.same(best,actual);assert.equal(draw(),actualDraw());assert.same(before,state);sim.validateState(model,actual)
			local result=sim.perform(socketRaw,pair,5,state);assert.equal("gwennen_socket_colour_assumptions",result.warnings[2].code)
			local odds=sim.calculate(socketRaw,pair,{},state,{requirements={socketColours="RR"},trials=12,seed=3})
			assert.is_true(odds.sampled);assert.equal("gwennen_socket_colour_assumptions",odds.warnings[2].code)
		end
		local noSockets=copyTable(state);noSockets.sockets={}
		assert.has_error(function() sim.action(model,noSockets,{method="gwennen",firstOutcome=1010,secondOutcome=1000},function() return 0.1 end) end)
	end)
	it("keeps socket rerolls equivalent across seeds, quality and Abyssal layouts",function()
		local raw="Rarity: NORMAL\nPlate Vest\nItem Level: 86\nSockets: R-G B W-W W"
		local model=sim.model(raw)
		for _,sockets in ipairs({{{color="W",group=3}},{{color="A",group=0},{color="W",group=1},{color="G",group=1}},model.initial.sockets}) do
			for _,quality in ipairs({0,20,30}) do for seed=1,24 do
				local state=copyTable(model.initial);state.rarity="RARE";state.sockets=copyTable(sockets);state.quality=quality
				state.intangibility=17;state.memoryStrands=3;state.imprint=copyTable(model.initial);local original=copyTable(state)
				local function stream() local value=seed;return function() value=value*48271%2147483647;return value/2147483647 end end
				local expectedDraw=stream();expectedDraw();local best,score=nil,-1
				for _=1,20 do local candidate=sim.action(model,state,{method="chromatic"},expectedDraw);local count=0
					for _,socket in ipairs(candidate.sockets) do if socket.color~="W" and socket.color~="A" then count=count+1 end end
					if count>score then best,score=candidate,count end
				end
				local actualDraw=stream();local actual=sim.action(model,state,{method="gwennen",firstOutcome=1011,secondOutcome=1011},actualDraw)
				assert.same(best,actual);assert.equal(expectedDraw(),actualDraw());assert.same(original,state)
			end end
		end
	end)
	it("keeps the first best link result from independent modeled Fusing rolls",function()
		local raw="Rarity: NORMAL\nPlate Vest\nItem Level: 86\nSockets: W W W W W W"
		local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="RARE";state.quality=20;state.imprint=copyTable(model.initial)
		local original=copyTable(state)
		local function stream(seed) return function() seed=seed*48271%2147483647;return seed/2147483647 end end
		local function largest(sockets) local counts,best={},0;for _,socket in ipairs(sockets) do counts[socket.group]=(counts[socket.group] or 0)+1;best=math.max(best,counts[socket.group]) end;return best end
		for _,case in ipairs({{1016,100},{1017,50}}) do for seed=1,12 do
			local draw=stream(seed);draw();local best,score=nil,-1
			for _=1,case[2] do local candidate=sim.action(model,state,{method="fusing"},draw);local n=largest(candidate.sockets);if n>score then best,score=candidate,n end end
			local actualDraw=stream(seed);local pair={method="gwennen",firstOutcome=case[1],secondOutcome=case[1]};local actual=sim.action(model,state,pair,actualDraw)
			assert.same(best,actual);assert.equal(draw(),actualDraw());assert.same(original,state);sim.validateState(model,actual)
		end end
		local pair={method="gwennen",firstOutcome=1016,secondOutcome=1017}
		local result=sim.calculate(raw,pair,{},state,{requirements={links=6},trials=12,seed=3})
		local probability=0
		for _,candidate in ipairs(require("Modules.CraftingSockets").fusingOutcomes(state)) do
			local linked=true;for _,group in ipairs(candidate.groups) do linked=linked and group==candidate.groups[1] end
			if linked then probability=probability+candidate.probability end
		end
		local expected=50*(2-(1-probability)^100-(1-probability)^50)
		assert.is_false(result.sampled);assert.are.near(expected,result.successChance,1e-8)
		local total=0;for _,outcome in ipairs(result.outcomes) do total=total+outcome.chance end
		assert.are.near(100,total,1e-8);assert.equal("gwennen_socket_link_assumptions",result.warnings[2].code)
		local mixed=sim.calculate(raw,{method="gwennen",firstOutcome=1000,secondOutcome=1017},{},state,{requirements={links=6}})
		assert.is_false(mixed.sampled);assert.are.near(50*(1-(1-probability)^50),mixed.successChance,1e-8)
		assert.same(original,state)
		-- Distinct layouts tied at four links retain their relative Fusing weights.
		local candidates=require("Modules.CraftingSockets").fusingOutcomes(state);local chanceByLayout={};local scoreMass=0
		for _,candidate in ipairs(candidates) do
			local counts,best={},0;for _,group in ipairs(candidate.groups) do counts[group]=(counts[group] or 0)+1;best=math.max(best,counts[group]) end
			if best==4 then chanceByLayout[table.concat(candidate.groups,"-")]=candidate.probability;scoreMass=scoreMass+candidate.probability end
		end
		local distribution=require("Modules.CraftingGwennen").discrete(model,state,1017);local observed={}
		for _,entry in ipairs(distribution) do
			local layout=entry.text:match("layout ([%d%-]+)")
			if chanceByLayout[layout] then observed[#observed+1]={probability=entry.probability,base=chanceByLayout[layout]} end
		end
		assert.is_true(#observed>1 and scoreMass>0)
		assert.are.near(observed[1].probability/observed[1].base,observed[2].probability/observed[2].base,1e-10)
		local full=copyTable(state);for _,socket in ipairs(full.sockets) do socket.group=0 end
		assert.has_error(function() sim.action(model,full,pair,function() return 0.1 end) end)
		assert.has_error(function() sim.calculate(raw,pair,{},full,{requirements={links=6}}) end)
		local abyss=copyTable(state);abyss.sockets[1].color="A"
		assert.has_error(function() sim.action(model,abyss,pair,function() return 0.1 end) end)
		assert.has_error(function() sim.calculate(raw,pair,{},abyss,{requirements={links=6}}) end)
	end)
	it("models the best of 50 socket counts and enumerates the assumed odds",function()
		local socketRaw="Rarity: NORMAL\nPlate Vest\nItem Level: 86\nSockets: R-G B"
		local model=sim.model(socketRaw);local state=copyTable(model.initial);state.rarity="RARE";state.quality=20
		local before=copyTable(state);local pair={method="gwennen",firstOutcome=1028,secondOutcome=1000}
		local function stream(seed) return function() seed=seed*48271%2147483647;return seed/2147483647 end end
		for seed=1,12 do
			local expectedDraw=stream(seed);expectedDraw();local best=0
			for _=1,50 do local candidate=sim.action(model,state,{method="jeweller"},expectedDraw);best=math.max(best,#candidate.sockets) end
			-- Force the first branch while retaining the same subsequent stream.
			local actualDraw=stream(seed);local first=true
			local actual=sim.action(model,state,pair,function() local value=actualDraw();if first then first=false;return 0.1 end;return value end)
			assert.equal(best,#actual.sockets);assert.equal(expectedDraw(),actualDraw());assert.same(before,state)
		end
		local probability=require("Modules.CraftingSockets").jewellerProbabilities(model,state)[6]
		local result=sim.calculate(socketRaw,pair,{},state,{requirements={sockets=6}})
		assert.is_false(result.sampled);assert.are.near(50*(1-(1-probability)^50),result.successChance,1e-8)
		local total=0;for _,outcome in ipairs(result.outcomes) do total=total+outcome.chance end
		assert.are.near(100,total,1e-8);assert.equal("gwennen_socket_count_assumptions",result.warnings[2].code)
		local full=copyTable(state);while #full.sockets<6 do full.sockets[#full.sockets+1]={color="W",group=#full.sockets} end
		local draws=0;assert.has_error(function() sim.action(model,full,pair,function() draws=draws+1;return 0.1 end) end);assert.equal(0,draws)
		local abyss=copyTable(state);abyss.sockets[1].color="A"
		assert.has_error(function() sim.calculate(socketRaw,pair,{},abyss,{requirements={sockets=6}}) end)
		assert.is_true(require("Modules.CraftingGwennen").supports(1030))
	end)
	it("requires and compares explicit scenarios for the disputed socket offer",function()
		local raw="Rarity: NORMAL\nPlate Vest\nItem Level: 86\nSockets: R-G B"
		local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="RARE"
		local craft={method="gwennen",firstOutcome=1030,secondOutcome=1000}
		assert.has_error(function() sim.action(model,state,craft,function() return 0.1 end) end)
		craft.gwennenSocketRerolls=75;assert.has_error(function() sim.validateRecipe({steps={craft},targets={}}) end)
		local probability=require("Modules.CraftingSockets").jewellerProbabilities(model,state)[6]
		local odds={}
		for _,rolls in ipairs({50,100}) do
			craft.gwennenSocketRerolls=rolls
			local result=sim.calculate(raw,craft,{},state,{requirements={sockets=6}})
			assert.is_false(result.sampled);assert.are.near(50*(1-(1-probability)^rolls),result.successChance,1e-8)
			assert.equal("gwennen_socket_count_disputed",result.warnings[2].code);assert.matches(tostring(rolls),result.warnings[2].message)
			odds[rolls]=result.successChance
			local calls=0;sim.action(model,state,craft,function() calls=calls+1;return 0.1 end);assert.equal(rolls+1,calls)
		end
		assert.is_true(odds[100]>odds[50])
		local recipe=sim.validateRecipe({steps={craft},targets={},requirements={sockets=6}});assert.equal(100,recipe.steps[1].gwennenSocketRerolls)
		local invalid={method="gwennen",firstOutcome=1028,secondOutcome=1000,gwennenSocketRerolls=50}
		assert.has_error(function() sim.validateRecipe({steps={invalid},targets={},requirements={sockets=6}}) end)
	end)
	it("requires the socket scenario in the crafting dialog and restores it",function()
		newBuild();local picked
		local controls=require("Classes.CraftingGwennenControl").Open(function() end,function(first,second,cost,rolls) picked=rolls end)
		controls.first:SelByValue(1030,"val");controls.first.selFunc();controls.second:SelByValue(1000,"val");controls.second.selFunc()
		assert.is_false(controls.simulate:IsEnabled());controls.rerolls:SelByValue(100,"val");controls.rerolls.selFunc()
		assert.is_true(controls.simulate:IsEnabled());controls.simulate:Click();assert.equal(100,picked)
		controls=require("Classes.CraftingGwennenControl").Open(function() end,function() end,{firstOutcome=1030,secondOutcome=1000,gwennenSocketRerolls=50})
		assert.equal(50,controls.rerolls:GetSelValueByKey("val"));assert.is_true(controls.simulate:IsEnabled());main.popups={}
	end)
	it("offers implicit rerolls in the modeled pair dialog",function()
		newBuild();local selected
		local controls=require("Classes.CraftingGwennenControl").Open(function() end,function(first,second) selected={first.id,second.id} end)
		controls.first:SelByValue(1032,"val");controls.first.selFunc();controls.second:SelByValue(1000,"val");controls.second.selFunc()
		assert.is_true(controls.simulate:IsEnabled());controls.simulate:Click();assert.same({1032,1000},selected)
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
		assert.has_error(function() sim.validateRecipe({steps={{method="gwennen",firstOutcome=1000,secondOutcome=1045}},targets={},requirements={minAffixes=1}}) end)
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
	it("models one-tier changes only for uniquely identified ordinary families",function()
		local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="RARE"
		state.affixes={{id="IncreasedLife2",range=0.5},{id="FireResist2",range=0.5}}
		local original=copyTable(state)
		for _,case in ipairs({{1020,"IncreasedLife3","FireResist3"},{1021,"IncreasedLife1","FireResist1"}}) do
			local pair={method="gwennen",firstOutcome=case[1],secondOutcome=case[1]}
			local first=sim.action(model,state,pair,function() return 0.1 end)
			local second=sim.action(model,state,pair,function() return 0.9 end)
			assert.equal(case[2],first.affixes[1].id);assert.equal("FireResist2",first.affixes[2].id)
			assert.equal("IncreasedLife2",second.affixes[1].id);assert.equal(case[3],second.affixes[2].id)
			assert.same(original,state);sim.validateState(model,first);sim.validateState(model,second)
			local estimate=sim.calculate(raw,pair,{},state,{requirements={minAffixes=1},trials=4})
			assert.is_true(estimate.sampled);assert.equal("gwennen_tier_assumptions",estimate.warnings[2].code)
		end
		local boundary=copyTable(state);boundary.affixes[1].id="IncreasedLife0"
		assert.has_error(function() sim.action(model,boundary,{method="gwennen",firstOutcome=1021,secondOutcome=1000},function() return 0.1 end) end)
		local crafted=copyTable(state);crafted.affixes[1].crafted=true
		assert.has_error(function() sim.action(model,crafted,{method="gwennen",firstOutcome=1020,secondOutcome=1000},function() return 0.1 end) end)
	end)
	it("models two or three distinct tier upgrades under explicit assumptions",function()
		local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="RARE"
		state.affixes={{id="IncreasedLife2",range=0.5},{id="FireResist2",range=0.5},{id="ColdResist2",range=0.5}}
		local before=copyTable(state)
		for _,case in ipairs({{1043,2},{1044,3}}) do
			local pair={method="gwennen",firstOutcome=case[1],secondOutcome=case[1]}
			for _,draw in ipairs({0.1,0.5,0.9}) do
				local result=sim.action(model,state,pair,function() return draw end);local changed=0
				for i,entry in ipairs(result.affixes) do if entry.id~=state.affixes[i].id then
					changed=changed+1;assert.equal(state.affixes[i].id:gsub("2$","3"),entry.id)
				end end
				assert.equal(case[2],changed);sim.validateState(model,result);assert.same(before,state)
			end
			local estimate=sim.calculate(raw,pair,{},state,{requirements={minAffixes=1},trials=4})
			assert.is_true(estimate.sampled);assert.equal("gwennen_tier_assumptions",estimate.warnings[2].code)
		end
		local two=copyTable(state);table.remove(two.affixes,3);local draws=0
		assert.has_error(function() sim.action(model,two,{method="gwennen",firstOutcome=1044,secondOutcome=1000},function() draws=draws+1;return 0.1 end) end);assert.equal(0,draws)
		local metadata=require("Modules.CraftingAdvanced").data().mods.IncreasedLife3
		local tags=metadata.adds_tags;metadata.adds_tags={"test_tier_tag"}
		local ok=pcall(sim.action,model,state,{method="gwennen",firstOutcome=1043,secondOutcome=1000},function() return 0.1 end)
		metadata.adds_tags=tags;assert.is_false(ok)
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
