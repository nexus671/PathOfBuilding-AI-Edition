describe("Experimental Rog side rerolls",function()
	local sim=require("Modules.CraftingSimulator")
	local rog=require("Modules.CraftingRog")
	local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86"
	local function stream(seed) return function() seed=seed*48271%2147483647;return seed/2147483647 end end
	it("keeps the best independent candidate, preserves the other side and leaves the input unchanged",function()
		local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="RARE"
		state.affixes={{id="IncreasedLife2",range=0.5},{id="FireResist2",range=0.5}}
		local original=copyTable(state)
		for _,side in ipairs({"Prefix","Suffix"}) do for _,attempts in ipairs({1,3,5}) do
			local actual=rog.reroll(sim,model,state,{rogSide=side,rogAttempts=attempts},stream(73))
			local random=stream(73);local best,score
			for _=1,attempts do
				local candidate=rog.reroll(sim,model,state,{rogSide=side,rogAttempts=1},random)
				local value=0;for _,entry in ipairs(candidate.affixes) do if model.byId[entry.id].type==side then value=value+model.byId[entry.id].level end end
				if not score or value>score then best,score=candidate,value end
			end
			assert.same(best,actual);assert.same(original,state);sim.validateState(model,actual)
			for _,entry in ipairs(state.affixes) do if model.byId[entry.id].type~=side then
				local found=false;for _,other in ipairs(actual.affixes) do if other.id==entry.id and other.range==entry.range then found=true end end
				assert.is_true(found)
			end end
		end end
	end)
	it("validates offers and keeps unknown and observed artifact costs distinct",function()
		local craft={rogSide="Prefix",rogAttempts=3}
		assert.same({["rog:observed_artifacts"]=1},rog.components(craft))
		craft.artifactCost={lesser=2,grand=7};assert.same({["Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction3_1"]=2,["Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction3_3"]=7},rog.components(craft))
		craft.rogAttempts=6;assert.has_error(function() rog.validate(craft) end)
		craft.rogAttempts=5;craft.artifactCost={lesser=-1};assert.has_error(function() rog.validate(craft) end)
		local prices=require("Modules.CraftingPrices")
		local name,path,kind=prices.describe("Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction3_3")
		assert.equal("Grand Order Artifact",name);assert.equal("Currency",kind);assert.is_truthy(path)
		assert.is_truthy(require("Modules.CraftingWorkbench").icon("rog_reroll"));assert.is_truthy(require("Modules.CraftingWorkbench").icon("gwennen"))
		name,_,kind=prices.describe("rog:observed_artifacts");assert.equal("Unspecified artifact cost",name);assert.equal("Resource",kind)
	end)
	it("fills open modifier slots while respecting a base implicit roll restriction",function()
		local wand="Rarity: NORMAL\nSomatic Wand\nItem Level: 86\nImplicits: 1\nCannot roll Caster Modifiers"
		local model=sim.model(wand);local input=copyTable(model.initial);input.rarity="RARE"
		local original=copyTable(input);local action={method="rog_reroll",rogOperation="fill",artifactCost={grand=7}}
		assert.is_nil(sim.configurationReason(model,input,action))
		for seed=1,10 do
			local result=sim.action(model,input,action,stream(seed));sim.validateState(model,result)
			assert.equal(sim.capacities(model,input).total,#result.affixes)
			for _,entry in ipairs(result.affixes) do for _,tag in ipairs(model.byId[entry.id].modTags or {}) do assert.is_false(tag=="caster") end end
		end
		assert.same(original,input)
		local result=sim.perform(wand,action,17,input);assert.matches("sequential",result.warnings[1].message)
		assert.same({["Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction3_3"]=7},sim.components(action))
		assert.matches("No empty",sim.configurationReason(model,result.state,action))
		assert.has_error(function() rog.validate({rogOperation="fill",rogSide="Prefix"}) end)
	end)
	it("sets eligible equipment quality to 20 with one exact outcome",function()
		local model=sim.model(raw);local input=copyTable(model.initial);input.rarity="RARE";input.quality=7
		input.affixes={{id="IncreasedLife2",range=0.5},{id="FireResist2",range=0.5}}
		local before=copyTable(input);local action={method="rog_reroll",rogOperation="set_quality",artifactCost={grand=7}}
		local output=sim.action(model,input,action,function() error("Quality offer should not draw randomness") end)
		assert.equal(20,output.quality);assert.same(before,input);assert.same(input.affixes,output.affixes)
		local result=sim.calculate(raw,action,{},input,{requirements={minQuality=20},trials=2})
		assert.is_false(result.sampled);assert.equal(100,result.successChance);assert.equal(20,result.sampleState.quality)
		assert.equal("rog_reroll_assumptions",result.warnings[1].code)
		assert.same({["Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction3_3"]=7},sim.components(action))
		local id="Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction3_3"
		local recipe={steps={action},targets={},requirements={minQuality=20}}
		local plan=sim.simulate(raw,recipe,{initialState=input,trials=2,maxActions=1,currency="chaos",prices={[id]=2}})
		assert.equal(100,plan.successChance);assert.equal(14,plan.meanCost);assert.equal(14,plan.currencySpent[id])
		local ring=sim.model("Rarity: NORMAL\nCoral Ring\nItem Level: 86");local state=copyTable(ring.initial);state.rarity="RARE"
		assert.matches("weapon or armour",sim.configurationReason(ring,state,action))
		assert.has_error(function() sim.action(ring,state,action,stream(1)) end)
		assert.has_error(function() rog.validate({rogOperation="set_quality",rogSide="Prefix"}) end)
	end)
	it("adds one legal modifier to the chosen side and selects the best independent roll",function()
		local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="RARE"
		state.affixes={{id="IncreasedLife2",range=0.5},{id="FireResist2",range=0.5}};local before=copyTable(state)
		for _,side in ipairs({"Prefix","Suffix"}) do for _,attempts in ipairs({1,3,5}) do
			local craft={method="rog_reroll",rogOperation="add",rogSide=side,rogAttempts=attempts}
			local actual=sim.action(model,state,craft,stream(73));local random=stream(73);local best,bestLevel
			for _=1,attempts do
				local one=copyTable(craft);one.rogAttempts=1;local candidate=sim.action(model,state,one,random)
				local added=candidate.affixes[#candidate.affixes];local level=model.byId[added.id].level
				if not bestLevel or level>bestLevel then best,bestLevel=candidate,level end
			end
			assert.same(best,actual);assert.same(before,state);assert.equal(#state.affixes+1,#actual.affixes);sim.validateState(model,actual)
		end end
		local magic=copyTable(state);magic.rarity="MAGIC"
		assert.has_error(function() sim.action(model,magic,{method="rog_reroll",rogOperation="add",rogSide="Prefix",rogAttempts=1},stream(1)) end)
	end)
	it("removes lowest required-level modifiers with explicit tie handling",function()
		local model={byId={a={level=10},b={level=10},c={level=20}}}
		local state={affixes={{id="a"},{id="b"},{id="c"}}};local before=copyTable(state)
		local one={rogOperation="remove_lowest"};local two={rogOperation="remove_lowest_two"}
		rog.validate(one);rog.validate(two)
		assert.same({{id="b"},{id="c"}},rog.removeLowest(model,state,one,function() return 0 end).affixes)
		assert.same({{id="a"},{id="c"}},rog.removeLowest(model,state,one,function() return 0.99 end).affixes)
		assert.same({{id="c"}},rog.removeLowest(model,state,two,function() return 0 end).affixes)
		assert.same(before,state);assert.has_error(function() rog.validate({rogOperation="remove_lowest",rogSide="Prefix"}) end)
		local real=sim.model(raw);local input=copyTable(real.initial);input.rarity="RARE"
		input.affixes={{id="IncreasedLife2",range=0.5},{id="FireResist2",range=0.5}}
		local output=sim.action(real,input,{method="rog_reroll",rogOperation="remove_lowest"},stream(1))
		assert.equal(1,#output.affixes);sim.validateState(real,output)
		assert.has_error(function() sim.action(real,output,{method="rog_reroll",rogOperation="remove_lowest_two"},stream(1)) end)
	end)
	it("enumerates tied lowest-removal sets without double-counting their order",function()
		local model={byId={a={"A",level=10},b={"B",level=10},c={"C",level=10},d={"D",level=20}}}
		local state={affixes={{id="a"},{id="b"},{id="c"},{id="d"}}};local before=copyTable(state)
		local branches=rog.removalOutcomes(model,state,{rogOperation="remove_lowest_two"});local total=0
		assert.equal(3,#branches)
		for _,branch in ipairs(branches) do
			assert.are.near(1/3,branch.probability,1e-12);total=total+branch.probability
			local i=0;local actual=rog.removeLowest(model,state,{rogOperation="remove_lowest_two"},function() i=i+1;return branch.draws[i] end)
			assert.equal(2,#actual.affixes);assert.equal("d",actual.affixes[2].id)
		end
		assert.are.near(1,total,1e-12);assert.same(before,state)
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local real=sim.model(raw);local input=copyTable(real.initial);input.rarity="RARE"
		input.affixes={{id="IncreasedLife2",range=0.5},{id="FireResist2",range=0.5}}
		local craft={method="rog_reroll",rogOperation="remove_lowest"}
		local result=sim.calculate(raw,craft,{},input,{requirements={minAffixes=1},trials=1})
		assert.is_false(result.sampled);assert.are.near(100,result.successChance,1e-10);assert.is_truthy(result.exactFor:find("assumed",1,true))
		assert.equal("rog_reroll_assumptions",result.warnings[1].code)
	end)
	it("runs configured offers through the shared simulator and saved checkpoint",function()
		local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="RARE"
		state.affixes={{id="IncreasedLife2",range=0.5},{id="FireResist2",range=0.5}}
		local craft={method="rog_reroll",rogSide="Prefix",rogAttempts=3,artifactCost={grand=7}}
		assert.is_nil(sim.configurationReason(model,state,craft))
		assert.is_not_nil(sim.configurationReason(model,state,{method="rog_reroll"}))
		local result=sim.perform(raw,craft,17,state);sim.validateState(model,result.state)
		assert.equal("rog_reroll_assumptions",result.warnings[1].code)
		local id="Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction3_3"
		local trials=sim.simulate(raw,{steps={craft},targets={},requirements={minAffixes=3}},{initialState=state,trials=2,maxActions=1,currency="chaos",prices={[id]=2}})
		assert.equal(0,trials.successes);assert.equal(14,trials.meanCost);assert.equal(14,trials.currencySpent[id])
		local run=require("Modules.CraftingInventory").run(state);run.configured.rog_reroll=craft
		local restored=require("Modules.CraftingCheckpoint").validate(raw,run)
		assert.same(craft,restored.configured.rog_reroll)
		local locked=copyTable(state);locked.affixes[1].fractured=true
		assert.has_error(function() sim.action(model,locked,craft,stream(1)) end)
	end)
	it("explains missing modifiers and full slots before applying an observed offer",function()
		local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="MAGIC"
		state.affixes={{id="IncreasedLife2",range=0.5},{id="FireResist2",range=0.5}}
		local add={method="rog_reroll",rogOperation="add",rogSide="Prefix",rogAttempts=1}
		assert.matches("No open prefix",sim.configurationReason(model,state,add))
		local removed=copyTable(state);removed.affixes={}
		assert.matches("No suffix modifiers",sim.configurationReason(model,removed,{method="rog_reroll",rogSide="Suffix",rogAttempts=1}))
		assert.matches("at least 2 modifiers",sim.configurationReason(model,removed,{method="rog_reroll",rogOperation="remove_lowest_two"}))
		assert.is_nil(sim.configurationReason(model,state,{method="rog_reroll",rogOperation="remove_lowest_two"}))
		newBuild();local project={id="rog-readiness",title="Helmet",slot="Helmet",startingItem=raw,goals={},steps={},run=require("Modules.CraftingInventory").run(state)}
		local c=require("Classes.CraftingSimulatorControl").Open(build,project);c.method:SelByValue("rog_reroll","val");c.method.selFunc();c.page:SelByValue("Craft settings");c.page.selFunc();c.configure:Click()
		local popup=main.popups[1].controls;popup.operation:SelByValue("add","val");popup.keep:Click()
		assert.is_false(c.apply:IsEnabled());assert.matches("No open prefix",c.apply.tooltipText())
		main.popups={}
	end)
	it("configures and restores an observed offer in the dialog",function()
		newBuild();local saved
		local c=require("Classes.CraftingRogControl").Open(nil,function(craft) saved=craft end)
		c.side:SelByValue("Suffix","val");c.attempts:SelByValue(5,"val");c.operation:SelByValue("add","val");c.grand:SetText("12",true);c.keep:Click()
		assert.same({method="rog_reroll",rogSide="Suffix",rogAttempts=5,rogOperation="add",artifactCost={grand=12}},saved)
		c=require("Classes.CraftingRogControl").Open(saved,function() end)
		assert.equal("Suffix",c.side:GetSelValueByKey("val"));assert.equal(5,c.attempts:GetSelValueByKey("val"));assert.equal("add",c.operation:GetSelValueByKey("val"));assert.equal("12",c.grand.buf)
		main.popups={}
	end)
	it("configures a removal without unrelated side or attempt fields",function()
		newBuild();local saved
		local c=require("Classes.CraftingRogControl").Open(nil,function(craft) saved=craft end)
		c.operation:SelByValue("remove_lowest_two","val");assert.is_false(c.side:IsShown());assert.is_true(c.removeHint:IsShown())
		c.keep:Click();assert.same({method="rog_reroll",rogOperation="remove_lowest_two"},saved)
		c=require("Classes.CraftingRogControl").Open(saved,function() end);assert.equal("remove_lowest_two",c.operation:GetSelValueByKey("val"));main.popups={}
	end)
	it("configures the offer from the workbench and preserves it in the working craft",function()
		newBuild();local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="RARE"
		state.affixes={{id="IncreasedLife2",range=0.5},{id="FireResist2",range=0.5}}
		local project={id="rog-workbench",title="Helmet",slot="Helmet",startingItem=raw,goals={},steps={},run=require("Modules.CraftingInventory").run(state)}
		build.savers.CraftingProjects:Upsert(project)
		local controls=require("Classes.CraftingSimulatorControl").Open(build,project)
		controls.method:SelByValue("rog_reroll","val");controls.method.selFunc()
		assert.is_false(controls.apply:IsEnabled());controls.page:SelByValue("Craft settings");controls.page.selFunc();controls.configure:Click()
		local popup=main.popups[1].controls;assert(popup.side,"Unexpected popup: "..tostring(main.popups[1].title).." method "..tostring(controls.method:GetSelValueByKey("val")));popup.side:SelByValue("Suffix","val");popup.attempts:SelByValue(3,"val");popup.grand:SetText("12",true);popup.keep:Click()
		assert.is_true(controls.apply:IsEnabled());controls.keepWorking:Click()
		local run=build.savers.CraftingProjects.projects[1].run
		assert.equal("Suffix",run.configured.rog_reroll.rogSide);assert.equal(3,run.configured.rog_reroll.rogAttempts);assert.equal(12,run.configured.rog_reroll.artifactCost.grand)
		main.popups={}
	end)
end)
