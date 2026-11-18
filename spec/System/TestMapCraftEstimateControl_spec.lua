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
		local state={baseId="Metadata/Items/Maps/MapWorldsStrand",tier=5,itemLevel=68,rarity="rare",selected={}}
		local settings={wantedGroups={{"MapMonsterFireDamageMapWorlds"},{"MapMonsterColdDamageMapWorlds"}},avoid={},trials=1000,maxAttempts=20}
		local controls=require("Classes.MapCraftEstimateControl").Open(build,{state=state,settings=settings,apply=function() error("unexpected apply") end})
		controls.run:Click();local job=tasks.job;assert.is_truthy(job)
		for _=1,10000 do if not tasks.job or (job.current.attempts or 0)>=10 then break end;tasks.tick(build) end
		assert.equal(job,tasks.job);assert.is_true(job.current.attempts>=10)
		controls.close:Click();assert.is_nil(tasks.job)
	end)
	it("adds and removes a user-chosen wanted alternative",function()
		local state={baseId="Metadata/Items/Maps/MapWorldsStrand",tier=16,itemLevel=83,rarity="rare",selected={}}
		local controls=require("Classes.MapCraftEstimateControl").Open(build,{state=state,wanted={"MapContainsMirageWorlds","MapContainsWildwoodWorlds"},apply=function() end})
		controls.targetGroup:SelByValue(2,"val");controls.addAlternative:Click();local picker=main.popups[1].controls;picker.search:SetText("MapContainsDeliriumMirrorWorlds",true);assert.is_true(picker.choose:IsEnabled());picker.choose:Click()
		local text="";for _,line in ipairs(controls.wanted.list) do text=text..StripEscapes(line[1] or "").."\n" end
		assert.matches("Mirror of Delirium",text);assert.matches("Viridian Wildwood",text);assert.is_true(controls.removeAlternative:IsEnabled());controls.removeAlternative:Click()
		picker=main.popups[1].controls;picker.search:SetText("MapContainsWildwoodWorlds",true);picker.choose:Click()
		text="";for _,line in ipairs(controls.wanted.list) do text=text..StripEscapes(line[1] or "").."\n" end;assert.is_nil(text:find("Viridian Wildwood",1,true));assert.matches("Mirror of Delirium",text)
	end)
	it("removes a chosen exclusion without changing the other saved targets",function()
		local saved;local state={baseId="Metadata/Items/Maps/MapWorldsStrand",tier=16,itemLevel=83,rarity="rare",selected={}}
		local settings={wantedGroups={{"MapContainsMirageWorlds"}},avoid={"MapMonsterAreaOfEffectMapWorlds","MapContainsWildwoodWorlds"},trials=3,maxAttempts=2}
		local controls=require("Classes.MapCraftEstimateControl").Open(build,{state=state,settings=settings,saveSettings=function(value) saved=value end,apply=function() end})
		controls.removeAvoid:Click();local picker=main.popups[1].controls;picker.search:SetText("MapMonsterAreaOfEffectMapWorlds",true);picker.choose:Click()
		controls.keepSettings:Click();assert.same({"MapContainsWildwoodWorlds"},saved.avoid);assert.same(settings.wantedGroups,saved.wantedGroups)
	end)
	it("keeps, reopens and edits target settings",function()
		local saved;local state={baseId="Metadata/Items/Maps/MapWorldsStrand",tier=16,itemLevel=83,rarity="rare",selected={}}
		local settings={wantedGroups={{"MapContainsMirageWorlds","MapContainsWildwoodWorlds"}},avoid={"MapMonsterAreaOfEffectMapWorlds"},trials=3,maxAttempts=2}
		local options={state=state,wanted={"MapContainsMirageWorlds"},settings=settings,saveSettings=function(value) saved=copyTable(value) end,apply=function() end}
		local controls=require("Classes.MapCraftEstimateControl").Open(build,options)
		controls.addTarget:Click();local picker=main.popups[1].controls;picker.search:SetText("MapContainsDeliriumMirrorWorlds",true);picker.choose:Click()
		controls.keepSettings:Click();assert.equal(2,#saved.wantedGroups);assert.same(settings.avoid,saved.avoid)
		controls.trials:SetText("4",true);assert.matches("Keep targets again",controls.report.list[1][1]);assert.equal(3,saved.trials)
		controls.keepSettings:Click();assert.equal(4,saved.trials);controls.close:Click()
		options.settings=saved;controls=require("Classes.MapCraftEstimateControl").Open(build,options);assert.equal("4",controls.trials.buf)
		controls.targetGroup:SelByValue(2,"val");controls.removeTarget:Click();controls.keepSettings:Click();assert.equal(1,#saved.wantedGroups)
		controls.fromMap:Click();controls.keepSettings:Click();assert.same({{"MapContainsMirageWorlds"}},saved.wantedGroups)
	end)
end)
