describe("Map reroll estimate control",function()
	local tasks=require("Modules.CraftingTasks")
	before_each(function() newBuild();main.popups={} end)
	after_each(function() if tasks.job then tasks.cancel() end;main.popups={} end)
	it("runs an estimate and applies an explicitly selected example",function()
		local sample;local state={baseId="Metadata/Items/Maps/MapWorldsStrand",tier=16,itemLevel=83,rarity="rare",selected={},plannedDeified=true}
		local controls=require("Classes.MapCraftEstimateControl").Open(build,{state=state,avoid={"MapMonsterAreaOfEffectMapWorlds"},apply=function(value) sample=value end})
		assert.matches("Area of Effect",StripEscapes(controls.avoid.list[2][1]))
		controls.trials:SetText("2",true);controls.attempts:SetText("1",true);controls.run:Click()
		assert.is_falsy(controls.trials:IsEnabled())
		for _=1,10000 do if not tasks.job then break end;tasks.tick(build) end
		assert.is_nil(tasks.job);assert.is_true(controls.use:IsEnabled())
		local report="";for _,row in ipairs(controls.report.list) do report=report..StripEscapes(row[1] or "") end
		assert.matches("Deified remains a plan",report,1,true);assert.matches("Cannot appear in modeled pool",report);assert.matches("Area of Effect",report);assert.matches("Map data: 3.30.0.4",report,1,true)
		controls.attempts:SetText("2",true);assert.is_falsy(controls.use:IsEnabled())
		controls.attempts:SetText("1",true);controls.run:Click();for _=1,10000 do if not tasks.job then break end;tasks.tick(build) end
		assert.is_true(controls.use:IsEnabled());controls.use:Click()
		assert.is_truthy(sample);assert.equal("rare",sample.rarity);assert.equal(#sample.selected,#sample.rolls);assert.is_true(sample.plannedDeified)
	end)
	it("warns when the feasibility search did not finish",function()
		local estimate=require("Modules.MapCraftEstimate");local previous=estimate.run
		local state={baseId="Metadata/Items/Maps/MapWorldsStrand",tier=16,itemLevel=83,rarity="rare",selected={}}
		local controls=require("Classes.MapCraftEstimateControl").Open(build,{state=state,avoid={"MapMonsterAreaOfEffectMapWorlds"},apply=function() end})
		estimate.run=function() return {feasibilityUnverified=true,successChance=0,maxAttempts=1,successes=0,trials=1,confidenceLow=0,confidenceHigh=100,meanAttempts=1,action="chaos",dataPatch="test"} end
		local ok,err=pcall(function()
			controls.run:Click();for _=1,10000 do if not tasks.job then break end;tasks.tick(build) end
		end)
		estimate.run=previous;assert.is_true(ok,tostring(err));assert.is_nil(tasks.job)
		local report="";for _,row in ipairs(controls.report.list) do report=report..StripEscapes(row[1] or "") end
		assert.matches("Target feasibility was not established",report,1,true)
	end)
	it("saves a manual orb price and displays bounded estimated costs",function()
		local saved;local state={baseId="Metadata/Items/Maps/MapWorldsStrand",tier=16,itemLevel=83,rarity="rare",selected={}}
		local options={state=state,avoid={"MapMonsterAreaOfEffectMapWorlds"},saveSettings=function(value) saved=copyTable(value) end,apply=function() end}
		local controls=require("Classes.MapCraftEstimateControl").Open(build,options)
		controls.price:Click();local popup=main.popups[1].controls;popup.amount:SetText("0.5",true);popup.currency:SetText("chaos",true);popup.keep:Click()
		assert.matches("Keep targets again",StripEscapes(controls.report.list[2][1]))
		controls.trials:SetText("2",true);controls.attempts:SetText("1",true);controls.keepSettings:Click();assert.same({amount=0.5,currency="chaos"},saved.price)
		controls.run:Click();for _=1,10000 do if not tasks.job then break end;tasks.tick(build) end
		local report="";for _,row in ipairs(controls.report.list) do report=report..StripEscapes(row[1] or "").." " end
		assert.matches("Mean orb cost per trial: 0.5 chaos",report);assert.matches("excludes the map",report)
		assert.matches("Spending percentiles: median 0.5",report);assert.matches("Includes failed trials",report)
		controls.close:Click();options.settings=saved;controls=require("Classes.MapCraftEstimateControl").Open(build,options)
		controls.price:Click();popup=main.popups[1].controls;assert.equal("0.5",popup.amount.buf);popup.clear:Click();controls.keepSettings:Click();assert.is_nil(saved.price)
	end)
	it("offers unlocked Nightmare modifiers and explains the estimate assumptions",function()
		local state={baseId="Metadata/Items/Maps/MapWorldsAbomination",tier=17,itemLevel=84,rarity="rare",selected={}}
		local settings={wantedGroups={{"MapUberWeakContainsDeliriumMirror"}},avoid={},trials=2,maxAttempts=2}
		local controls=require("Classes.MapCraftEstimateControl").Open(build,{state=state,settings=settings,apply=function() end})
		controls.addAvoid:Click();local picker=main.popups[1].controls;picker.search:SetText("MapUberWeakPlayersLessCooldownRecovery",true);assert.is_true(picker.choose:IsEnabled());picker.choose:Click()
		controls.run:Click();for _=1,10000 do if not tasks.job then break end;tasks.tick(build) end
		assert.is_nil(tasks.job);local text="";for _,row in ipairs(controls.report.list) do text=text..StripEscapes(row[1] or "").." " end
		assert.matches("Nightmare model",text);assert.matches("unverified",text)
	end)
	it("cancels its own job when closed",function()
		local state={baseId="Metadata/Items/Maps/MapWorldsStrand",tier=16,itemLevel=83,rarity="rare",selected={}}
		local settings={wantedGroups={{"MapContainsMirageWorlds"}},avoid={},trials=1000,maxAttempts=20}
		local controls=require("Classes.MapCraftEstimateControl").Open(build,{state=state,settings=settings,apply=function() error("unexpected apply") end})
		controls.run:Click();local job=tasks.job;assert.is_truthy(job)
		for _=1,10000 do if not tasks.job or (job.current.attempts or 0)>=10 then break end;tasks.tick(build) end
		assert.equal(job,tasks.job);assert.is_true(job.current.attempts>=10)
		controls.close:Click();assert.is_nil(tasks.job)
	end)
	it("explains incompatible targets before rolling",function()
		local state={baseId="Metadata/Items/Maps/MapWorldsStrand",tier=5,itemLevel=68,rarity="rare",selected={}}
		local settings={wantedGroups={{"MapMonsterFireDamageMapWorlds"},{"MapMonsterColdDamageMapWorlds"}},avoid={},trials=1000,maxAttempts=20}
		local controls=require("Classes.MapCraftEstimateControl").Open(build,{state=state,settings=settings,apply=function() error("unexpected apply") end})
		controls.run:Click();for _=1,1000 do if not tasks.job then break end;tasks.tick(build) end
		assert.is_nil(tasks.job);local text="";for _,row in ipairs(controls.report.list) do text=text..StripEscapes(row[1] or "").." " end
		assert.matches("Wanted groups 1 and 2 cannot coexist",text);assert.is_falsy(controls.use:IsEnabled())
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
	it("reviews matching tier replacements for wanted and avoided modifiers",function()
		local saved;local state={baseId="Metadata/Items/Maps/MapWorldsStrand",tier=16,itemLevel=83,rarity="rare",selected={}}
		local settings={wantedGroups={{"MapMonsterFireDamageMapWorlds"}},avoid={"MapMonsterColdDamageMapWorlds"},trials=3,maxAttempts=2}
		local controls=require("Classes.MapCraftEstimateControl").Open(build,{state=state,settings=settings,saveSettings=function(value) saved=value end,apply=function() end})
		assert.is_false(controls.run:IsEnabled());controls.removeAlternative:Click();local picker=main.popups[1].controls;assert.is_false(picker.choose:IsEnabled());picker.secondary:Click()
		local replacements=main.popups[1].controls;replacements.search:SetText("MapMonsterFireDamage3MapWorlds",true);assert.is_true(replacements.choose:IsEnabled());replacements.choose:Click()
		assert.is_true(controls.run:IsEnabled());controls.removeAvoid:Click();picker=main.popups[1].controls;picker.secondary:Click()
		replacements=main.popups[1].controls;replacements.search:SetText("MapMonsterColdDamage3MapWorlds",true);assert.is_true(replacements.choose:IsEnabled());replacements.choose:Click()
		controls.keepSettings:Click();assert.same({{"MapMonsterFireDamage3MapWorlds"}},saved.wantedGroups);assert.same({"MapMonsterColdDamage3MapWorlds_"},saved.avoid)
		assert.same({{"MapMonsterFireDamageMapWorlds"}},settings.wantedGroups);assert.same({"MapMonsterColdDamageMapWorlds"},settings.avoid)
	end)
	it("does not replace a target with an already selected modifier",function()
		local saved;local state={baseId="Metadata/Items/Maps/MapWorldsStrand",tier=16,itemLevel=83,rarity="rare",selected={}}
		local settings={wantedGroups={{"MapMonsterFireDamageMapWorlds"},{"MapMonsterFireDamage3MapWorlds"}},avoid={},trials=3,maxAttempts=2}
		local controls=require("Classes.MapCraftEstimateControl").Open(build,{state=state,settings=settings,saveSettings=function(value) saved=value end,apply=function() end})
		controls.removeAlternative:Click();main.popups[1].controls.secondary:Click();local picker=main.popups[1].controls
		picker.search:SetText("MapMonsterFireDamage3MapWorlds",true);assert.is_false(picker.choose:IsEnabled());picker.close:Click();main.popups[1].controls.close:Click()
		controls.keepSettings:Click();assert.same(settings.wantedGroups,saved.wantedGroups)
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
