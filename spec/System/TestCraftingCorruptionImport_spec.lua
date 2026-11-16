describe("Imported corruption identities",function()
	local sim=require("Modules.CraftingSimulator")
	local resolve=require("Modules.CraftingCorruptionImport").resolve
	local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86\nSockets: W W W"
	local function fixture(lines,mods,base)
		local model={item={corrupted=true,implicitModLines={},base={implicit=base}},initial={},byId=mods,corruptions={}}
		local metadata={}
		for _,line in ipairs(lines) do model.item.implicitModLines[#model.item.implicitModLines+1]=type(line)=="table" and line or {line=line} end
		for id in pairs(mods) do model.corruptions[#model.corruptions+1]={id=id};metadata[id]={groups={id}} end
		return model,metadata
	end
	before_each(function() newBuild();main.popups={} end)
	after_each(function() main.popups={} end)
	it("reopens a replaced single synthesised implicit without guessing untagged text",function()
		local text="Rarity: NORMAL\nGold Amulet\nItem Level: 86\nImplicits: 1\n+10 to Strength\nSynthesised Item"
		local model=sim.model(text);local changed=sim.action(model,model.initial,{method="vaal"},function() return 0 end)
		local upgraded=sim.model(sim.perform(text,{method="alchemy"},1).itemText)
		assert.is_true(upgraded.item.synthesised)
		local available,reason=require("Modules.CraftingAvailability").check("fracture",upgraded.initial,upgraded)
		assert.is_false(available);assert.is_truthy(reason:find("synthesised",1,true))
		assert.equal(1,#changed.corruptedImplicits)
		local result=sim.toItem(model,changed).raw;local reopened=sim.model(result)
		assert.is_true(reopened.item.synthesised);assert.is_nil(reopened.unresolvedCorruption)
		assert.same(changed.corruptedImplicits,reopened.initial.corruptedImplicits)
		local target={{scope="implicit",anyOf={changed.corruptedImplicits[1].id}}}
		assert.is_true(sim.matches(reopened.initial,target,nil,reopened))
		local untagged=result:gsub("{modGroup:crafting_[^}]+}","")
		assert.is_truthy(sim.model(untagged).unresolvedCorruption)
		local forged=result:gsub("crafting_"..changed.corruptedImplicits[1].id,"crafting_InvalidModifier")
		assert.is_truthy(sim.model(forged).unresolvedCorruption)
	end)
	it("retains and reopens either surviving Eldritch implicit after corruption",function()
		local model=sim.model(raw);local check=require("Modules.CraftingAvailability").check
		local first=sim.perform(raw,{method="eldritch_implicit",side="Exarch",tier=2},11).state
		assert.is_true(check("vaal",first,model))
		local second=sim.perform(raw,{method="eldritch_implicit",side="Eater",tier=1},12,first).state
		assert.equal(2,#second.implicits)
		assert.is_true(check("vaal",second,model))
		local applied=sim.action(model,second,{method="vaal"},function() return 0 end)
		assert.equal(1,#applied.implicits);assert.equal(1,#applied.corruptedImplicits)
		local recipe={steps={{method="vaal"}},targets={{scope="implicit",anyOf={second.implicits[1].id}}}}
		local estimate=sim.simulate(raw,recipe,{initialState=second,trials=20,maxActions=1,forceFirstAction=true})
		assert.is_nil(next(estimate.transitionErrors));assert.is_true(estimate.successes>0)
		for _,draw in ipairs({0,0.999}) do
			local mixed=copyTable(second);sim.rollCorrupted(model,mixed,function() return draw end)
			assert.equal(1,#mixed.implicits);assert.equal(1,#mixed.corruptedImplicits)
			assert.equal(second.implicits[draw==0 and 2 or 1].id,mixed.implicits[1].id)
			mixed=sim.validateState(model,mixed)
			local targets={{scope="implicit",anyOf={mixed.implicits[1].id}},{scope="implicit",anyOf={mixed.corruptedImplicits[1].id}}}
			assert.is_true(sim.matches(mixed,targets,nil,model))
			local reopened=sim.model(sim.toItem(model,mixed).raw)
			assert.same(mixed.implicits,reopened.initial.implicits);assert.same(mixed.corruptedImplicits,reopened.initial.corruptedImplicits)
			assert.is_true(sim.matches(reopened.initial,targets,nil,reopened))
			local forged=sim.toItem(model,mixed).raw:gsub("crafting_"..mixed.implicits[1].id,"crafting_InvalidModifier")
			assert.is_true(sim.model(forged).unresolvedEldritch)
			forged=sim.toItem(model,mixed).raw:gsub("crafting_"..mixed.corruptedImplicits[1].id,"crafting_InvalidModifier")
			local unresolved=sim.model(forged);assert.is_truthy(unresolved.unresolvedCorruption)
			assert.is_false(pcall(sim.matches,unresolved.initial,targets,nil,unresolved))
		end
		model.unresolvedEldritch=true;assert.is_false(check("vaal",model.initial,model))
		local synth=sim.model("Rarity: NORMAL\nGold Amulet\nItem Level: 86\nImplicits: 2\n+10 to Strength\n+12 to Dexterity\nSynthesised Item")
		local available,reason=check("vaal",synth.initial,synth)
		assert.is_false(available);assert.is_truthy(reason:find("synthesised",1,true))
		assert.has_error(function() sim.action(synth,synth.initial,{method="vaal"},function() return 0 end) end,reason)
	end)
	it("models a second corruption while retaining or replacing an existing implicit",function()
		local model=sim.model(raw);local first=copyTable(model.initial)
		sim.rollCorrupted(model,first,function() return 0.1 end,1)
		local second=sim.action(model,first,{method="locus"},function() return 0 end)
		assert.is_true(second.twiceCorrupted);assert.equal(2,#second.corruptedImplicits)
		assert.equal(first.corruptedImplicits[1].id,second.corruptedImplicits[1].id)
		local item=sim.toItem(model,second).raw;assert.matches("Twice Corrupted",item)
		local reopened=sim.model(item);assert.is_true(reopened.initial.twiceCorrupted)
		local expected=copyTable(second.corruptedImplicits);table.sort(expected,function(a,b) return a.id<b.id end)
		assert.same(expected,reopened.initial.corruptedImplicits)
		assert.is_false(pcall(sim.action,model,second,{method="locus"},function() return 0 end))
		local pair=copyTable(model.initial);sim.rollCorrupted(model,pair,function() return 0.1 end,2)
		local retained=pair.corruptedImplicits[2].id
		local replaced=sim.action(model,pair,{method="locus"},function() return 0 end)
		assert.equal(2,#replaced.corruptedImplicits);assert.equal(retained,replaced.corruptedImplicits[1].id)
		local unchanged=sim.action(model,first,{method="locus"},function() return 0.3 end)
		assert.same(first.corruptedImplicits,unchanged.corruptedImplicits);assert.is_true(unchanged.twiceCorrupted)
		local destroyed=sim.action(model,first,{method="locus"},function() return 0.6 end)
		assert.is_true(destroyed.destroyed);assert.equal(0,#(destroyed.influences or {}))
		assert.is_false(pcall(sim.action,model,model.initial,{method="locus"},function() return 0 end))
		local unresolved=model;unresolved.unresolvedCorruption="unresolved"
		local unknown=copyTable(first);unknown.corruptedImplicits=nil
		assert.is_false(require("Modules.CraftingAvailability").check("locus",unknown,unresolved))
		assert.is_false(pcall(sim.action,unresolved,unknown,{method="locus"},function() return 0 end))
	end)
	it("colours one white socket with a Vaal Orb and all white sockets with the Locus",function()
		local model=sim.model(raw)
		local state=copyTable(model.initial)
		state.sockets={{color="W",group=0},{color="B",group=0},{color="W",group=1},{color="W",group=1}}
		local function roll()
			local first=true;return function() if first then first=false;return 0.3 end;return 0 end
		end
		local vaal=sim.action(model,state,{method="vaal"},roll())
		assert.same({{color="R",group=0},{color="B",group=0},{color="W",group=1},{color="W",group=1}},vaal.sockets)
		assert.is_true(vaal.corrupted);assert.same(state.sockets,sim.model(sim.toItem(model,state).raw).initial.sockets)
		local corrupted=copyTable(state);corrupted.corrupted=true
		local locus=sim.action(model,corrupted,{method="locus"},roll())
		assert.same({{color="R",group=0},{color="B",group=0},{color="R",group=1},{color="R",group=1}},locus.sockets)
		assert.is_true(locus.twiceCorrupted);assert.same(locus.sockets,sim.model(sim.toItem(model,locus).raw).initial.sockets)
		local noWhite=copyTable(state);for _,socket in ipairs(noWhite.sockets) do socket.color="G" end
		assert.same(noWhite.sockets,sim.action(model,noWhite,{method="vaal"},roll()).sockets)
	end)
	it("uses 3.30 maximum-charge weights on rings without changing other bases",function()
		local ids={"V2MaxPowerChargesCorrupted","V2MaxFrenzyChargesCorrupted","V2MaximumEnduranceChargesCorruption"}
		local function weight(base,id)
			local model=sim.model("Rarity: NORMAL\n"..base.."\nItem Level: 86")
			for _,entry in ipairs(model.corruptions) do if entry.id==id then return entry.weight end end
		end
		for _,id in ipairs(ids) do assert.equal(50,weight("Iron Ring",id)) end
		assert.equal(1000,weight("Iron Hat",ids[1]))
		assert.equal(1000,weight("Iron Gauntlets",ids[2]))
		assert.equal(1000,weight("Iron Greaves",ids[3]))
		local model=sim.model("Rarity: NORMAL\nIron Ring\nItem Level: 86")
		local total,before=0,0;for _,entry in ipairs(model.corruptions) do
			if entry.id==ids[1] then before=total end;total=total+entry.weight
		end
		local first=true;local function random() if first then first=false;return (before+25)/total end;return 0 end
		local state=copyTable(model.initial);sim.rollCorrupted(model,state,random,2)
		assert.equal(ids[1],state.corruptedImplicits[1].id);assert.equal(2,#state.corruptedImplicits)
	end)
	it("includes the 3.30 minimum power charge corruption on eligible bases",function()
		local id="V2MinPowerChargesCorruptedNew"
		for _,base in ipairs({"Gold Amulet","Goathide Buckler","Iron Ring"}) do
			local model=sim.model("Rarity: NORMAL\n"..base.."\nItem Level: 86")
			local found,before,total
			before,total=0,0
			for _,entry in ipairs(model.corruptions) do
				if entry.id==id then found=entry;before=total end
				total=total+entry.weight
			end
			if base=="Iron Ring" then assert.is_nil(found)
			else
				assert.equal(1000,assert(found).weight)
				local catalog=require("Modules.CraftingModifiers").catalog(model);local row
				for _,candidate in ipairs(catalog) do if candidate.id==id then row=candidate end end
				assert.is_truthy(row);assert.equal("+1 to Minimum Power Charges",row.text)
				local first=true
				local function random() if first then first=false;return (before+1)/total end;return 0 end
				local state=copyTable(model.initial);sim.rollCorrupted(model,state,random,1)
				assert.equal(id,state.corruptedImplicits[1].id)
				local text=sim.toItem(model,state).raw
				assert.is_truthy(text:find("+1 to Minimum Power Charges",1,true))
				local reopened=sim.model(text)
				assert.equal(id,reopened.initial.corruptedImplicits[1].id)
			end
		end
		local low=sim.model("Rarity: NORMAL\nGold Amulet\nItem Level: 39")
		for _,entry in ipairs(low.corruptions) do assert.is_not.equal(id,entry.id) end
	end)
	it("rolls the 3.30 Life Gain on Hit support while preserving legacy corruptions",function()
		local raw="Rarity: NORMAL\nEzomyte Axe\nItem Level: 86"
		local id="V2SupportedByLifeGainOnHitCorrupted"
		local model=sim.model(raw);local before,total=0,0
		local row;for _,candidate in ipairs(require("Modules.CraftingModifiers").catalog(model)) do if candidate.id==id then row=candidate end end
		assert.matches("Level 15 Life Gain On Hit",assert(row).text)
		local details=require("Modules.CraftingInspection").modDetails(model,id);assert.matches("Level 15 Life Gain On Hit",table.concat(details," "))
		for _,entry in ipairs(model.corruptions) do if entry.id==id then before=total end;total=total+entry.weight end
		local first=true;local function random() if first then first=false;return (before+1)/total end;return 0 end
		local state=copyTable(model.initial);sim.rollCorrupted(model,state,random,1)
		assert.equal(id,state.corruptedImplicits[1].id);assert.is_true(state.corruptedImplicits[1].corruption330)
		local text=sim.toItem(model,state).raw;assert.matches("Level 15 Life Gain On Hit",text)
		local parsed,extra=modLib.parseMod("Socketed Gems are Supported by Level 15 Life Gain On Hit")
		assert.is_nil(extra);assert.equal("ExtraSupport",parsed[1].name);assert.equal(15,parsed[1].value.level);assert.equal("SupportLifeGainOnHit",parsed[1].value.skillId)
		local reopened=sim.model(text);assert.same(state.corruptedImplicits,reopened.initial.corruptedImplicits)
		local currentText=text:gsub("Level 15 Life Gain On Hit","Level 15 Life Gain on Hit Support")
		local current=sim.model(currentText);assert.same(state.corruptedImplicits,current.initial.corruptedImplicits)
		local legacy=copyTable(state);legacy.corruptedImplicits[1].corruption330=nil
		local oldText=sim.toItem(model,legacy).raw;assert.matches("Level 10 Life Gain On Hit",oldText)
		local old=sim.model(oldText);assert.same(legacy.corruptedImplicits,old.initial.corruptedImplicits)
		local invalid=copyTable(state);invalid.corruptedImplicits[1].corruption330="yes"
		assert.is_false(pcall(sim.validateState,model,invalid))
	end)
	it("recovers one and two native implicits and preserves them through tainted crafting",function()
		local model=sim.model(raw)
		for count=1,2 do
			local state=copyTable(model.initial);sim.rollCorrupted(model,state,function() return 0.1 end,count);state.twiceCorrupted=true
			local text=sim.toItem(model,state).raw;local imported=sim.model(text)
			assert.are.equal(count,#imported.initial.corruptedImplicits);assert.is_nil(imported.unresolvedCorruption)
			for _,entry in ipairs(state.corruptedImplicits) do assert.is_true(sim.matches(imported.initial,{{anyOf={entry.id},scope="implicit"}},nil,imported)) end
			local result=sim.perform(text,{method="tainted_chromatic"},1)
			assert.are.same(imported.initial.corruptedImplicits,result.state.corruptedImplicits);assert.is_true(new("Item"):Item(result.itemText).twiceCorrupted)
		end
	end)
	it("retains independent ranges and recognises reordered multi-line modifiers",function()
		local model,metadata=fixture({"14 added Fire Damage","4 added Cold Damage"},{one={"(1-5) added Cold Damage","(10-20) added Fire Damage"}})
		local entries=resolve(sim,model,metadata);assert.are.same({{id="one",range={0.75,0.4}}},entries)
	end)
	it("does not guess between overlapping identities but honours exact native templates",function()
		local mods={one={"(1-5) added Cold Damage"},two={"(3-7) added Cold Damage"}}
		local model,metadata=fixture({"4 added Cold Damage"},mods)
		local entries,reason=resolve(sim,model,metadata);assert.is_nil(entries);assert.are.equal("unresolved",reason)
		model.item.implicitModLines={{line=mods.one[1],range=0.75}}
		entries=resolve(sim,model,metadata);assert.are.same({{id="one",range=0.75}},entries)
	end)
	it("rejects conflicting groups and more than two corruption modifiers",function()
		local model,metadata=fixture({"1 added Cold Damage","2 added Fire Damage"},{one={"1 added Cold Damage"},two={"2 added Fire Damage"}})
		metadata.two.groups=metadata.one.groups
		local entries,reason=resolve(sim,model,metadata);assert.is_nil(entries);assert.are.equal("unresolved",reason)
		model,metadata=fixture({"1 added Cold Damage","2 added Fire Damage","3 added Chaos Damage"},{one={"1 added Cold Damage"},two={"2 added Fire Damage"},three={"3 added Chaos Damage"}})
		entries,reason=resolve(sim,model,metadata);assert.is_nil(entries);assert.are.equal("unresolved",reason)
	end)
	it("keeps unchanged natural implicits separate and refuses ambiguous natural alternatives",function()
		local model,metadata=fixture({"4 added Cold Damage"},{one={"1 added Fire Damage"}},"(1-5) added Cold Damage")
		local entries,reason=resolve(sim,model,metadata);assert.is_nil(entries);assert.is_nil(reason)
		model.byId.one={"(1-5) added Cold Damage"};entries,reason=resolve(sim,model,metadata);assert.is_nil(entries);assert.are.equal("unresolved",reason)
		model,metadata=fixture({"2 added Fire Damage","1 added Cold Damage"},{one={"1 added Cold Damage"},two={"2 added Fire Damage"}},"1 added Cold Damage\n2 added Fire Damage")
		entries,reason=resolve(sim,model,metadata);assert.is_nil(entries);assert.are.equal("unresolved",reason)
	end)
	it("explains unresolved implicit targets while allowing explicit checks and resolved overrides",function()
		local model={unresolvedCorruption="unresolved"};local state={rarity="NORMAL",affixes={}}
		assert.has_error(function() sim.matches(state,{{anyOf={"one"},scope="implicit"}},nil,model) end,"The imported implicit modifiers could not be identified uniquely. Paste advanced item text with modifier ranges, or choose another starting item.")
		assert.is_true(sim.matches(state,{},nil,model));state.corruptedImplicits={{id="one",range=0.5}}
		assert.is_true(sim.matches(state,{{anyOf={"one"},scope="implicit"}},nil,model))
	end)
	it("explains unavailable calculations before starting a job",function()
		local text=raw.."\nImplicits: 1\n31% increased Movement Speed\nCorrupted"
		local target={anyOf={"V2ColdDamageLifeLeechPermyriadCorrupted_"},scope="implicit"}
		assert.is_truthy(sim.model(text).unresolvedCorruption)
		local p={id="unknown-implicit",title="Unknown implicit",slot="Helmet",startingItem=text,goals={},steps={},preferredMethod="tainted_chromatic",nativeRecipe={steps={{method="tainted_chromatic"}},targets={target}}}
		local c=require("Classes.CraftingSimulatorControl").Open(build,p)
		local visible={};for _,row in ipairs(c.resultSummary.list) do visible[#visible+1]=StripEscapes(row[1]) end
		assert.is_truthy(table.concat(visible," "):find("could not be identified uniquely",1,true))
		assert.is_truthy(c.intro.label:find("Implicit target unavailable",1,true))
		for _,key in ipairs({"simulate","runRecipe","exact","compareRecipes","optimize"}) do
			assert.is_false(c[key]:IsEnabled(),key);assert.is_truthy(c[key]:GetProperty("tooltipText"):find("could not be identified uniquely",1,true),key)
		end
		c.simulate:Click();c.runRecipe:Click();assert.is_nil(require("Modules.CraftingTasks").job)
	end)
	it("accepts an explicit valid Eldritch state despite ambiguous source text",function()
		local generated=sim.perform(raw,{method="eldritch_implicit",side="Exarch",tier=1},1).state
		local model=sim.model(raw.."\nImplicits: 1\n31% increased Movement Speed\nCorrupted")
		local state=copyTable(model.initial);state.implicits=generated.implicits
		state=sim.validateState(model,state)
		assert.is_true(sim.matches(state,{{anyOf={state.implicits[1].id},scope="implicit"}},nil,model))
		assert.is_nil(sim.implicitTargetReason(model,state,{{anyOf={state.implicits[1].id},scope="implicit"}}))
	end)
	it("does not infer positive or negated targets from unresolved Eldritch text",function()
		local model=sim.model(raw.."\nImplicits: 1\n{exarch}31% increased Movement Speed")
		assert.is_true(model.unresolvedEldritch)
		local target={anyOf={"AreaOfEffectEldritchImplicit1"},scope="implicit"}
		for _,negate in ipairs({false,true}) do
			target.negate=negate;assert.is_false(pcall(sim.matches,model.initial,{target},nil,model))
			assert.is_truthy(sim.implicitTargetReason(model,model.initial,{target}))
		end
	end)
	it("preserves twice corruption across every tainted equipment method",function()
		local text=sim.perform(raw,{method="alchemy"},1).itemText.."\nTwice Corrupted"
		for _,method in ipairs({"tainted_chaos","tainted_exalt","tainted_quality","tainted_chromatic","tainted_jeweller","tainted_fusing"}) do for seed=1,10 do
			local result=sim.perform(text,{method=method},seed);assert.is_true(result.state.corrupted);assert.is_true(result.state.twiceCorrupted)
			assert.is_true(new("Item"):Item(result.itemText).twiceCorrupted);sim.validateState(sim.model(text),result.state)
		end end
	end)
	it("recovers missing identities from older saved states without mutating them",function()
		local model=sim.model(raw);local source=copyTable(model.initial);sim.rollCorrupted(model,source,function() return 0.1 end,2)
		local text=sim.toItem(model,source).raw;model=sim.model(text)
		local legacy=copyTable(model.initial);legacy.corruptedImplicits=nil;local before=copyTable(legacy)
		local restored=sim.validateState(model,legacy);assert.are.same(model.initial.corruptedImplicits,restored.corruptedImplicits);assert.are.same(before,legacy)
		local result=sim.perform(text,{method="tainted_chromatic"},1,legacy)
		assert.are.same(restored.corruptedImplicits,result.state.corruptedImplicits)
	end)
end)
