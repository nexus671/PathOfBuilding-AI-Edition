describe("Map reroll estimate control",function()
	local tasks=require("Modules.CraftingTasks")
	before_each(function() newBuild();main.popups={} end)
	after_each(function() if tasks.job then tasks.cancel() end;main.popups={} end)
	it("runs an estimate and applies an explicitly selected example",function()
		local sample;local state={baseId="Metadata/Items/Maps/MapWorldsStrand",tier=16,itemLevel=83,rarity="rare",selected={}}
		local controls=require("Classes.MapCraftEstimateControl").Open(build,{state=state,avoid={"MapMonsterAreaOfEffectMapWorlds"},apply=function(value) sample=value end})
		assert.matches("Area of Effect",StripEscapes(controls.avoid.list[2][1]))
		controls.trials:SetText("2",true);controls.attempts:SetText("1",true);controls.run:Click()
		assert.is_falsy(controls.trials:IsEnabled())
		for _=1,10000 do if not tasks.job then break end;tasks.tick(build) end
		assert.is_nil(tasks.job);assert.is_true(controls.use:IsEnabled());controls.attempts:SetText("2",true);assert.is_falsy(controls.use:IsEnabled())
		controls.attempts:SetText("1",true);controls.run:Click();for _=1,10000 do if not tasks.job then break end;tasks.tick(build) end
		assert.is_true(controls.use:IsEnabled());controls.use:Click()
		assert.is_truthy(sample);assert.equal("rare",sample.rarity);assert.equal(#sample.selected,#sample.rolls)
	end)
	it("cancels its own job when closed",function()
		local state={baseId="Metadata/Items/Maps/MapWorldsStrand",tier=16,itemLevel=83,rarity="rare",selected={}}
		local controls=require("Classes.MapCraftEstimateControl").Open(build,{state=state,avoid={"MapMonsterAreaOfEffectMapWorlds"},apply=function() error("unexpected apply") end})
		controls.run:Click();assert.is_truthy(tasks.job);controls.close:Click();assert.is_nil(tasks.job)
	end)
end)
