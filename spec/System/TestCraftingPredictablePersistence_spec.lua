describe("Predictable recombination observation persistence",function()
	it("retains the observed recipient in a saved build and checks it after reopening",function()
		newBuild()
		local sim=require("Modules.CraftingSimulator")
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local model=sim.model(raw)
		local recipient=copyTable(model.initial);recipient.rarity="MAGIC";recipient.affixes={{id="IncreasedLife1",range=0.75}}
		local donor=copyTable(model.initial);donor.rarity="MAGIC";donor.affixes={{id="FireResist1",range=0.25}}
		local action={method="recombine_predictable",donorItem=sim.toItem(model,donor).raw,selectedMods={left={"IncreasedLife1"},right={"FireResist1"}},reportedSuccessChance=0,observedRecipientState=copyTable(recipient)}
		local recipe={initialState=recipient,steps={action},targets={{anyOf={"IncreasedLife1"}},{anyOf={"FireResist1"}}}}
		build.savers.CraftingProjects:Upsert({id="observed",title="Observed helmet",slot="Helmet",startingItem=raw,goals={},steps={},nativeRecipe=recipe})
		local xml=build:SaveDB("Observed helmet");loadBuildFromXML(xml,"Observed helmet")
		local saved=build.savers.CraftingProjects.projects[1].nativeRecipe
		assert.same(recipient,saved.steps[1].observedRecipientState)
		local result=sim.simulate(raw,saved,{trials=1,maxActions=1,forceFirstAction=true});assert.equal(1,result.destroyedTrials)
		saved.initialState.quality=1
		local ok,message=pcall(sim.simulate,raw,saved,{trials=1,maxActions=1,forceFirstAction=true})
		assert.is_false(ok);assert.matches("Recipient differs",message)
	end)
end)
