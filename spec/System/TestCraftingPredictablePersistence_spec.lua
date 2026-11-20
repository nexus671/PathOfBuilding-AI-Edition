describe("Predictable recombination observation persistence",function()
	it("retains the observed recipient in a saved build and checks it after reopening",function()
		newBuild()
		local sim=require("Modules.CraftingSimulator")
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local model=sim.model(raw)
		local recipient=copyTable(model.initial);recipient.rarity="MAGIC";recipient.affixes={{id="IncreasedLife1",range=0.75}}
		local donor=copyTable(model.initial);donor.rarity="MAGIC";donor.affixes={{id="FireResist1",range=0.25}}
		local action={method="recombine_predictable",donorItem=sim.toItem(model,donor).raw,selectedMods={left={"IncreasedLife1"},right={"FireResist1"}},reportedSuccessChance=0,observedRecipientState=copyTable(recipient)}
		action.observedInputs=sim.predictableObservation(action)
		local recipe={initialState=recipient,steps={action},targets={{anyOf={"IncreasedLife1"}},{anyOf={"FireResist1"}}}}
		build.savers.CraftingProjects:Upsert({id="observed",title="Observed helmet",slot="Helmet",startingItem=raw,goals={},steps={},nativeRecipe=recipe})
		local xml=build:SaveDB("Observed helmet");loadBuildFromXML(xml,"Observed helmet")
		local saved=build.savers.CraftingProjects.projects[1].nativeRecipe
		assert.same(recipient,saved.steps[1].observedRecipientState)
		assert.same(action.observedInputs,saved.steps[1].observedInputs)
		local result=sim.simulate(raw,saved,{trials=1,maxActions=1,forceFirstAction=true});assert.equal(1,result.destroyedTrials)
		for _,change in ipairs({function(step) step.donorItem=step.donorItem.."\nNote: changed" end,function(step) step.selectedMods.right={"ColdResist1"} end,function(step) step.reportedSuccessChance=10 end,function(step) step.observedInputs=nil end}) do
			local stale=copyTable(saved);change(stale.steps[1]);local ok,message=pcall(sim.simulate,raw,stale,{trials=1,maxActions=1})
			assert.is_false(ok);assert.matches("reconfirm",message)
		end
		local changedAction=copyTable(action);changedAction.reportedSuccessChance=10
		local accepted,reason=pcall(sim.action,model,recipient,changedAction,function() return 0.5 end)
		assert.is_false(accepted);assert.matches("changed since the observation",reason)
		saved.initialState.quality=1
		local ok,message=pcall(sim.simulate,raw,saved,{trials=1,maxActions=1,forceFirstAction=true})
		assert.is_false(ok);assert.matches("Recipient differs",message)
	end)
	it("restores a configured observation in the workbench and rejects stale or older settings",function()
		newBuild()
		local sim=require("Modules.CraftingSimulator");local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local model=sim.model(raw)
		local recipient=copyTable(model.initial);recipient.rarity="MAGIC";recipient.affixes={{id="IncreasedLife1",range=0.75}}
		local donor=copyTable(model.initial);donor.rarity="MAGIC";donor.affixes={{id="FireResist1",range=0.25}}
		local action={method="recombine_predictable",donorItem=sim.toItem(model,donor).raw,selectedMods={left={"IncreasedLife1"},right={"FireResist1"}},reportedSuccessChance=0,observedRecipientState=copyTable(recipient)}
		action.observedInputs=sim.predictableObservation(action)
		local run=require("Modules.CraftingInventory").run(recipient);run.method="recombine_predictable";run.configured.recombine_predictable=action
		build.savers.CraftingProjects:Upsert({id="observed-ui",title="Observed helmet",slot="Helmet",startingItem=raw,goals={},steps={},run=run})
		local xml=build:SaveDB("Observed workbench");loadBuildFromXML(xml,"Observed workbench")
		local project=build.savers.CraftingProjects.projects[1];local open=require("Classes.CraftingSimulatorControl").Open
		local controls=open(build,project);assert.is_true(controls.apply:IsEnabled())
		local stale=copyTable(project);stale.run.state.quality=1
		controls=open(build,stale);assert.is_false(controls.apply:IsEnabled());assert.matches("Reconfirm",controls.apply.tooltipText())
		local older=copyTable(project);older.run.configured.recombine_predictable.observedRecipientState=nil
		controls=open(build,older);assert.is_false(controls.apply:IsEnabled());assert.matches("observation is missing",controls.apply.tooltipText())
		local changed=copyTable(project);changed.run.configured.recombine_predictable.reportedSuccessChance=10
		controls=open(build,changed);assert.is_false(controls.apply:IsEnabled());assert.matches("Donor or selection changed",controls.apply.tooltipText())
		main.popups={}
	end)
end)
