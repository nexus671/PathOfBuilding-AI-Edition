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
	it("configures and restores an observed offer in the dialog",function()
		newBuild();local saved
		local c=require("Classes.CraftingRogControl").Open(nil,function(craft) saved=craft end)
		c.side:SelByValue("Suffix","val");c.attempts:SelByValue(5,"val");c.operation:SelByValue("add","val");c.grand:SetText("12",true);c.keep:Click()
		assert.same({method="rog_reroll",rogSide="Suffix",rogAttempts=5,rogOperation="add",artifactCost={grand=12}},saved)
		c=require("Classes.CraftingRogControl").Open(saved,function() end)
		assert.equal("Suffix",c.side:GetSelValueByKey("val"));assert.equal(5,c.attempts:GetSelValueByKey("val"));assert.equal("add",c.operation:GetSelValueByKey("val"));assert.equal("12",c.grand.buf)
		main.popups={}
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
