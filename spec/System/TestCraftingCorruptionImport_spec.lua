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
	it("keeps a Gilded line separate from imported synthesised modifier groups",function()
		local text="Rarity: NORMAL\nGold Amulet\nItem Level: 86\nImplicits: 3\n+10 to Strength\n+20 to Dexterity\nItem sells for much more to vendors\nSynthesised Item"
		local model=sim.model(text);assert.equal("unknown",model.initial.vendorImplicit);assert.equal(2,#model.synthesisGroups)
		local output=sim.itemText(model,model.initial);assert.is_truthy(output:find("Item sells for much more to vendors",1,true));assert.is_truthy(output:find("+10 to Strength",1,true));assert.is_truthy(output:find("+20 to Dexterity",1,true))
	end)
	it("preserves exact synthesised range identity through corruption",function()
		local text="Rarity: NORMAL\nGold Amulet\nItem Level: 86\nImplicits: 2\n{range:0}(8-10)% increased maximum Life\n+20 to Dexterity\nSynthesised Item"
		local model=sim.model(text);local candidates=model.synthesisGroups[1].candidates
		assert.equal(1,#candidates);assert.equal("SynthesisImplicitPercentLife3",candidates[1].id);assert.equal(0,candidates[1].range)
		local target={{scope="implicit",anyOf={candidates[1].id}}};assert.is_true(sim.matches(model.initial,target,nil,model))
		local state=copyTable(model.initial);sim.rollCorrupted(model,state,function() return 0.999 end)
		local reopened=sim.model(sim.toItem(model,state).raw)
		assert.equal(1,#reopened.synthesisGroups[1].candidates);assert.equal(candidates[1].id,reopened.synthesisGroups[1].candidates[1].id)
		assert.equal(0,reopened.synthesisGroups[1].candidates[1].range);assert.is_true(sim.matches(reopened.initial,target,nil,reopened))
		local plain=sim.model(text:gsub("{range:0}%(8%-10%)%% increased maximum Life","8%% increased maximum Life"))
		assert.is_true(#plain.synthesisGroups[1].candidates>1);assert.is_false(pcall(sim.matches,plain.initial,target,nil,plain))
	end)
	it("replaces one identified synthesised modifier and reopens the survivors",function()
		local text="Rarity: NORMAL\nGold Amulet\nItem Level: 86\nImplicits: 2\n+10 to Strength\n+20 to Dexterity\nSynthesised Item"
		local model=sim.model(text);assert.equal(2,#model.synthesisGroups)
		local id=model.synthesisGroups[1].candidates[1].id
		assert.equal(1,#model.synthesisGroups[1].candidates)
		local preservedTarget={{scope="implicit",anyOf={id}}}
		assert.is_true(sim.matches(model.initial,preservedTarget,nil,model))
		assert.equal("implicit",require("Modules.CraftingModifiers").scope(model.byId[id]))
		local odds=sim.simulate(text,{steps={{method="vaal"}},targets=preservedTarget},{trials=40,maxActions=1,forceFirstAction=true})
		assert.is_true(odds.successes>0 and odds.successes<40);assert.is_nil(next(odds.transitionErrors))
		local catalogue=sim.catalog(text,"",5);assert.equal(2,#catalogue.synthesisGroups)
		assert.same({"+10 to Strength"},catalogue.synthesisGroups[1].lines);assert.is_true(catalogue.synthesisGroups[1].retained)
		assert.same({id},catalogue.synthesisGroups[1].candidates);assert.is_false(catalogue.synthesisGroups[1].ambiguous)
		assert.is_true(require("Modules.CraftingAvailability").check("vaal",model.initial,model))
		for _,draw in ipairs({0,0.999}) do
			local state=copyTable(model.initial);sim.rollCorrupted(model,state,function() return draw end)
			assert.equal(1,#state.synthRetained);assert.equal(draw==0 and 2 or 1,state.synthRetained[1])
			state=sim.validateState(model,state)
			assert.equal(draw~=0,sim.matches(state,preservedTarget,nil,model))
			local inspected=sim.catalog(text,"",5,state)
			assert.equal(draw~=0,inspected.synthesisGroups[1].retained)
			local invalid=copyTable(state);invalid.synthRetained={3};assert.is_false(pcall(sim.validateState,model,invalid))
			invalid.synthRetained={1,2};assert.is_false(pcall(sim.validateState,model,invalid))
			invalid.synthRetained=nil;assert.is_false(pcall(sim.validateState,model,invalid))
			local reopened=sim.model(sim.toItem(model,state).raw)
			assert.is_nil(reopened.unresolvedCorruption);assert.equal(1,#reopened.synthesisGroups)
			assert.equal(model.synthesisGroups[state.synthRetained[1]][1].line,reopened.synthesisGroups[1][1].line)
			assert.same(state.corruptedImplicits,reopened.initial.corruptedImplicits)
			assert.equal(draw~=0,sim.matches(reopened.initial,preservedTarget,nil,reopened))
			assert.is_true(sim.matches(reopened.initial,{{scope="implicit",anyOf={state.corruptedImplicits[1].id}}},nil,reopened))
		end
		local ambiguous=copyTable(model.synthesisGroups[1].candidates[1]);ambiguous.id="ambiguous-synthesis"
		model.synthesisGroups[1].candidates[2]=ambiguous
		for _,negate in ipairs({false,true}) do preservedTarget[1].negate=negate;assert.is_false(pcall(sim.matches,model.initial,preservedTarget,nil,model)) end
		preservedTarget[1].negate=nil;preservedTarget[1].anyOf={id,ambiguous.id};assert.is_true(sim.matches(model.initial,preservedTarget,nil,model))
		preservedTarget[1].anyOf={id};table.remove(model.synthesisGroups[1].candidates)
		local applied=sim.action(model,model.initial,{method="vaal"},function() return 0 end)
		assert.equal(1,#applied.synthRetained);assert.equal(1,#applied.corruptedImplicits)
		local estimate=sim.simulate(text,{steps={{method="vaal"}},targets={{scope="implicit",anyOf={applied.corruptedImplicits[1].id}}}},{trials=10,maxActions=1,forceFirstAction=true})
		assert.is_nil(next(estimate.transitionErrors))
		local three=sim.model(text:gsub("Implicits: 2","Implicits: 3"):gsub("Synthesised Item","+12 to Intelligence\nSynthesised Item"))
		assert.equal(3,#three.synthesisGroups)
		for _,draw in ipairs({0,0.4,0.999}) do
			local state=copyTable(three.initial);sim.rollCorrupted(three,state,function() return draw end)
			assert.equal(2,#state.synthRetained);state=sim.validateState(three,state)
			local invalid=copyTable(state);invalid.synthRetained={1,1};assert.is_false(pcall(sim.validateState,three,invalid))
			invalid.synthRetained={1};assert.is_false(pcall(sim.validateState,three,invalid))
			local reopened=sim.model(sim.toItem(three,state).raw)
			assert.equal(2,#reopened.synthesisGroups);assert.same(state.corruptedImplicits,reopened.initial.corruptedImplicits)
		end
	end)
	it("keeps retained synthesised modifiers in a saved crafting guide",function()
		local text="Rarity: NORMAL\nGold Amulet\nItem Level: 86\nImplicits: 2\n+10 to Strength\n+20 to Dexterity\nSynthesised Item"
		local model=sim.model(text);local state=copyTable(model.initial);sim.rollCorrupted(model,state,function() return 0 end)
		local project={id="synth-amulet",title="Synthesised amulet",slot="Amulet",startingItem=text,goals={},steps={},
			nativeRecipe={steps={{method="tainted_exalt"}},targets={},requirements={corrupted=true},initialState=state}}
		build.savers.CraftingProjects:Upsert(project)
		local xml=build:SaveDB("Synthesised guide");loadBuildFromXML(xml,"Synthesised guide")
		local restored=build.savers.CraftingProjects.projects[1].nativeRecipe.initialState
		assert.same(state.synthRetained,restored.synthRetained)
		assert.same(state.corruptedImplicits,restored.corruptedImplicits)
		assert.is_true(sim.validateState(sim.model(text),restored).corrupted)
	end)
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
		local synth=sim.model("Rarity: NORMAL\nGold Amulet\nItem Level: 86\nImplicits: 2\n+10 to Strength\nUnknown synthesised modifier\nSynthesised Item")
		local available,reason=check("vaal",synth.initial,synth)
		assert.is_false(available);assert.is_truthy(reason:find("synthesised",1,true))
		assert.has_error(function() sim.action(synth,synth.initial,{method="vaal"},function() return 0 end) end,reason)
	end)
	it("models a Gilded line as one possible first corruption replacement alongside Eldritch implicits",function()
		local model=sim.model(raw)
		local first=sim.perform(raw,{method="eldritch_implicit",side="Exarch",tier=2},11).state
		local second=sim.perform(raw,{method="eldritch_implicit",side="Eater",tier=1},12,first).state
		local gilded=sim.perform(raw,{method="fossil",fossils={"Metadata/Items/Currency/CurrencyDelveCraftingSellPrice"}},13,second).state
		for _,draw in ipairs({0,0.4,0.999}) do
			local mixed=copyTable(gilded);sim.rollCorrupted(model,mixed,function() return draw end)
			assert.equal(1,#mixed.corruptedImplicits);assert.equal(draw<0.9 and 1 or 2,#mixed.implicits)
			if draw<0.9 then assert.equal(gilded.vendorImplicit,mixed.vendorImplicit);assert.equal(second.implicits[draw==0 and 2 or 1].id,mixed.implicits[1].id) else assert.is_nil(mixed.vendorImplicit) end
			mixed=sim.validateState(model,mixed)
			local saved=require("Modules.CraftingCheckpoint").validate(raw,require("Modules.CraftingInventory").run(mixed)).state
			local output=sim.itemText(model,saved);local reopened=sim.model(output)
			assert.equal(#mixed.implicits,#reopened.initial.implicits);assert.same(mixed.corruptedImplicits,reopened.initial.corruptedImplicits)
			if draw<0.9 then assert.equal("unknown",reopened.initial.vendorImplicit) else assert.is_nil(reopened.initial.vendorImplicit) end
		end
		local targets={{scope="implicit",anyOf={second.implicits[1].id}},{scope="implicit",anyOf={second.implicits[2].id}}}
		local result=sim.simulate(raw,{initialState=gilded,steps={{method="vaal"}},targets=targets,requirements={corrupted=true}},{trials=100,maxActions=1,seed=73,forceFirstAction=true})
		assert.is_nil(next(result.transitionErrors));assert.is_true(result.successes>0);assert.is_true(result.successes<100)
	end)
	it("preserves synthesised survivors across second corruption and reopening",function()
		local lines={"+10 to Strength","+20 to Dexterity","+12 to Intelligence"}
		for count=1,3 do
			local text="Rarity: NORMAL\nGold Amulet\nItem Level: 86\nImplicits: "..count.."\n"..table.concat(lines,"\n",1,count).."\nSynthesised Item"
			local model=sim.model(text);local first=sim.action(model,model.initial,{method="vaal"},function() return 0 end)
			assert.is_true(require("Modules.CraftingAvailability").check("locus",first,model))
			local final=sim.action(model,first,{method="locus"},function() return 0 end)
			assert.is_true(final.twiceCorrupted);assert.equal(2,#final.corruptedImplicits);assert.equal(math.max(0,count-2),#(final.synthRetained or {}))
			assert.is_true(sim.validateState(model,final).twiceCorrupted)
			local reopened=sim.model(sim.toItem(model,final).raw);assert.is_true(reopened.initial.twiceCorrupted);assert.equal(2,#reopened.initial.corruptedImplicits)
			assert.equal(math.max(0,count-2),#(reopened.synthesisGroups or {}))
			if count==2 then
				local malformed=sim.toItem(model,final).raw:gsub("\nTwice Corrupted",""):gsub("\nCorrupted","")
				local unknown=sim.model(malformed);assert.is_false(require("Modules.CraftingAvailability").check("vaal",unknown.initial,unknown))
			end
			local intermediate=sim.model(sim.toItem(model,first).raw)
			assert.is_true(require("Modules.CraftingAvailability").check("locus",intermediate.initial,intermediate))
			local again=sim.action(intermediate,intermediate.initial,{method="locus"},function() return 0 end)
			assert.is_true(sim.validateState(intermediate,again).twiceCorrupted)
			local destroyed=sim.action(model,first,{method="locus"},function() return 0.6 end);assert.is_true(sim.validateState(model,destroyed).destroyed)
		end
	end)
	it("retains synthesised groups when replacing one of two existing corruptions",function()
		local text="Rarity: NORMAL\nGold Amulet\nItem Level: 86\nImplicits: 3\n+10 to Strength\n+20 to Dexterity\n+12 to Intelligence\nSynthesised Item"
		local model=sim.model(text);local once=sim.action(model,model.initial,{method="vaal"},function() return 0 end)
		local twice=sim.action(model,once,{method="locus"},function() return 0 end)
		local item=sim.toItem(model,twice).raw:gsub("Twice Corrupted","Corrupted")
		local reopened=sim.model(item);assert.equal(1,#reopened.initial.synthRetained);assert.equal(2,#reopened.initial.corruptedImplicits)
		local replaced=sim.action(reopened,reopened.initial,{method="locus"},function() return 0 end)
		assert.same(reopened.initial.synthRetained,replaced.synthRetained);assert.equal(2,#replaced.corruptedImplicits);assert.is_true(sim.validateState(reopened,replaced).twiceCorrupted)
	end)
	it("explains implicit additions and removals in crafting history",function()
		local text="Rarity: NORMAL\nGold Amulet\nItem Level: 86\nImplicits: 2\n+10 to Strength\n+20 to Dexterity\nSynthesised Item"
		local model=sim.model(text);local first=sim.action(model,model.initial,{method="vaal"},function() return 0 end)
		local final=sim.action(model,first,{method="locus"},function() return 0 end)
		local diff=require("Modules.CraftingInspection").diff(model,first,final);local joined=table.concat(diff,"\n")
		local surviving=model.synthesisGroups[first.synthRetained[1]][1].line
		assert.is_truthy(joined:find("- Implicit: "..surviving,1,true));assert.matches("%+ Implicit:",joined);assert.matches("Twice Corrupted",joined)
		local unchanged=require("Modules.CraftingInspection").diff(model,first,first);assert.same({"No displayed modifier or item-property changes."},unchanged)
		local destroyed=sim.action(model,first,{method="locus"},function() return 0.6 end)
		assert.matches("destroyed",table.concat(require("Modules.CraftingInspection").diff(model,first,destroyed)," "))
	end)
	it("saves an exhausted synthesised state and simulates a second corruption",function()
		local text="Rarity: NORMAL\nGold Amulet\nItem Level: 86\nImplicits: 2\n+10 to Strength\n+20 to Dexterity\nSynthesised Item"
		local model=sim.model(text);local first=sim.action(model,model.initial,{method="vaal"},function() return 0 end)
		local final=sim.action(model,first,{method="locus"},function() return 0 end);assert.is_true(final.synthExhausted)
		local invalid=copyTable(final);invalid.synthExhausted=false;assert.is_false(pcall(sim.validateState,model,invalid))
		local legacy=copyTable(final);legacy.intangibility=50;local destroyed=sim.action(model,legacy,{method="ducat_tzamoto"},function() return 0.9 end);assert.is_true(sim.validateState(model,destroyed).destroyed)

		local project={id="synth-second",title="Synthesised second corruption",slot="Amulet",startingItem=text,goals={},steps={},nativeRecipe={steps={{method="locus"}},targets={},requirements={twiceCorrupted=true},initialState=final}}
		build.savers.CraftingProjects:Upsert(project);local xml=build:SaveDB("Synthesised second corruption");loadBuildFromXML(xml,"Synthesised second corruption")
		local restored=build.savers.CraftingProjects.projects[1].nativeRecipe.initialState;assert.is_true(restored.synthExhausted);assert.same(final.corruptedImplicits,restored.corruptedImplicits);assert.is_true(sim.validateState(sim.model(text),restored).twiceCorrupted)
		local result=sim.simulate(text,{steps={{method="locus"}},targets={},requirements={twiceCorrupted=true}},{initialState=first,trials=20,maxActions=1,forceFirstAction=true})
		assert.is_nil(next(result.transitionErrors))
	end)
	it("models second corruption of identified Eldritch implicits as an explicit assumption",function()
		local model=sim.model(raw);local check=require("Modules.CraftingAvailability").check
		local first=sim.perform(raw,{method="eldritch_implicit",side="Exarch",tier=2},11).state
		local second=sim.perform(raw,{method="eldritch_implicit",side="Eater",tier=1},12,first).state
		local mixed=sim.action(model,second,{method="vaal"},function() return 0 end)
		assert.equal(1,#mixed.implicits);assert.equal(1,#mixed.corruptedImplicits);assert.is_true(check("locus",mixed,model))
		local result=sim.action(model,mixed,{method="locus"},function() return 0 end)
		assert.is_nil(result.implicits);assert.equal(2,#result.corruptedImplicits);assert.is_true(result.twiceCorrupted)
		assert.is_true(sim.validateState(model,result).twiceCorrupted)
		local reopened=sim.model(sim.toItem(model,result).raw);assert.equal(2,#reopened.initial.corruptedImplicits);assert.is_true(reopened.initial.twiceCorrupted)
		local corrupted=copyTable(second);corrupted.corrupted=true
		for _,choice in ipairs({0,0.999}) do
			local count=0;local outcome=sim.action(model,corrupted,{method="locus"},function() count=count+1;if count==1 then return 0 elseif count==2 then return 0.5 else return choice end end)
			assert.equal(1,#outcome.implicits);assert.equal(1,#outcome.corruptedImplicits);assert.is_true(sim.validateState(model,outcome).twiceCorrupted)
		end
		local estimate=sim.simulate(raw,{steps={{method="locus"}},targets={},requirements={twiceCorrupted=true}},{initialState=mixed,trials=20,maxActions=1,forceFirstAction=true})
		assert.is_nil(next(estimate.transitionErrors))
		local unchanged=sim.action(model,mixed,{method="locus"},function() return 0.3 end)
		assert.same(mixed.implicits,unchanged.implicits);assert.same(mixed.corruptedImplicits,unchanged.corruptedImplicits)
		local destroyed=sim.action(model,mixed,{method="locus"},function() return 0.6 end);assert.is_true(destroyed.destroyed)
		local state=copyTable(mixed);state.implicits=nil;model.unresolvedEldritch=true
		assert.is_false(check("locus",state,model));assert.has_error(function() sim.action(model,state,{method="locus"},function() return 0 end) end)
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
