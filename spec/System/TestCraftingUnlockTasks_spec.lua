describe("Crafting recipe unlock tasks",function()
	local raw="Rarity: NORMAL\nPlate Vest\nItem Level: 86"
	local function project() return {id="body",title="Body armour",slot="Body Armour",startingItem=raw,goals={},steps={}} end
	local function action(id) return {method="bench",modId=id or "bench:partial-prefix-1"} end
	before_each(function() newBuild();main.popups={} end)
	it("adds a linked task once and preserves edits across save and reopen",function()
		local buildModel=require("Modules.CraftingSimulator");local model=buildModel.model(raw)
		build.savers.CraftingProjects:Upsert(project());local tracker=require("Modules.CraftingUnlockTasks")
		local result=tracker.track(build,"body",model,action());assert.is_true(result.created)
		local tasks=build.savers.BuildJourney.data.milestones;assert.equal(1,#tasks);assert.equal("body",tasks[1].projectId)
		assert.matches("Sanctuary Map",tasks[1].notes,1,true);assert.is_false(tasks[1].done)
		local captured=require("Modules.DesktopBuildBridge").capture(build);assert.equal(tasks[1].id,captured.context.journey.milestones[1].id)
		local changed=copyTable(tasks[1]);changed.notes="Already checked";changed.done=true;build.savers.BuildJourney:Put("milestones",changed)
		local again=tracker.track(build,"body",model,action());assert.is_false(again.created);assert.equal("Already checked",again.task.notes);assert.is_true(again.task.done)
		assert.equal(1,#build.savers.CraftingProjects:References("body"))
		local xml=build:SaveDB("Unlock test");loadBuildFromXML(xml,"Unlock test")
		local reopened=tracker.track(build,"body",buildModel.model(raw),action());assert.is_false(reopened.created)
		assert.equal(1,#build.savers.BuildJourney.data.milestones);assert.equal("Already checked",reopened.task.notes);assert.is_true(reopened.task.done)
	end)
	it("reviews distinct unlocks and existing tasks without assuming account state",function()
		local sim=require("Modules.CraftingSimulator");local model=sim.model(raw);local tracker=require("Modules.CraftingUnlockTasks")
		build.savers.CraftingProjects:Upsert(project())
		local steps={action(),action(),action("bench:partial-suffix-1"),{method="bench",modId="missing"},{method="chaos"}}
		local report=tracker.review(build,"body",model,steps);assert.equal(2,#report.entries);assert.same({1,2},report.entries[1].steps)
		assert.equal("untracked",report.entries[1].taskStatus);assert.equal("Sanctuary Map",report.entries[1].unlock.map);assert.equal("Citadel Map",report.entries[2].unlock.map)
		assert.equal(1,#report.unresolved);assert.equal(4,report.unresolved[1].step);assert.equal(0,#build.savers.BuildJourney.data.milestones)
		local tracked=tracker.track(build,"body",model,action());local next=tracker.review(build,"body",model,steps)
		assert.equal("tracked",next.entries[1].taskStatus);assert.equal(tracked.task.id,next.entries[1].taskId)
		build.savers.BuildJourney:Complete(tracked.task.id);assert.equal("complete",tracker.review(build,"body",model,steps).entries[1].taskStatus)
		local relinked=copyTable(build.savers.BuildJourney.data.milestones[1]);relinked.projectId="other";build.savers.BuildJourney:Put("milestones",relinked)
		assert.equal("conflict",tracker.review(build,"body",model,steps).entries[1].taskStatus);local collision=tracker.track(build,"body",model,action());assert.is_false(collision.created);assert.is_true(collision.conflict)
		assert.equal("other",build.savers.BuildJourney.data.milestones[1].projectId)
		build.savers.BuildJourney.unreadable="future data";local unreadable=tracker.review(build,"body",model,steps);assert.equal("unknown",unreadable.entries[1].taskStatus);assert.matches("preserved",unreadable.warning,1,true)
		assert.has_error(function() tracker.track(build,"body",model,action()) end);assert.equal("other",build.savers.BuildJourney.data.milestones[1].projectId)
	end)
	it("does not mutate the Roadmap for missing projects, unsupported actions or unreadable data",function()
		local model=require("Modules.CraftingSimulator").model(raw);local tracker=require("Modules.CraftingUnlockTasks")
		assert.has_error(function() tracker.track(build,"missing",model,action()) end);assert.equal(0,#build.savers.BuildJourney.data.milestones)
		build.savers.CraftingProjects:Upsert(project())
		assert.has_error(function() tracker.track(build,"body",model,{method="chaos"}) end)
		assert.has_error(function() tracker.track(build,"body",model,action("unknown")) end)
		build.savers.BuildJourney.unreadable="future data";assert.has_error(function() tracker.track(build,"body",model,action()) end)
		assert.equal(0,#build.savers.BuildJourney.data.milestones)
	end)
	it("disables checklist tracking for relinked and unreadable Roadmap tasks",function()
		local model=require("Modules.CraftingSimulator").model(raw);local tracker=require("Modules.CraftingUnlockTasks")
		build.savers.CraftingProjects:Upsert(project());tracker.track(build,"body",model,action())
		local changed=copyTable(build.savers.BuildJourney.data.milestones[1]);changed.projectId="other";build.savers.BuildJourney:Put("milestones",changed)
		local controls=require("Classes.CraftingRecipeControl").Open({steps={action()},targets={}},action(),function() end,model,
			{trackUnlock=function(step,context) return tracker.track(build,"body",context,step) end,reviewUnlocks=function(steps,context) return tracker.review(build,"body",context,steps) end})
		controls.reviewUnlocks:Click();local browser=main.popups[1].controls;assert.is_false(browser.choose:IsEnabled())
		local lines={};for _,row in ipairs(browser.details.list) do lines[#lines+1]=StripEscapes(row[1] or "") end
		assert.matches("relinked",table.concat(lines," "),1,true);main:ClosePopup()
		build.savers.BuildJourney.unreadable="future data";controls.reviewUnlocks:Click();browser=main.popups[1].controls;assert.is_false(browser.choose:IsEnabled())
		lines={};for _,row in ipairs(browser.details.list) do lines[#lines+1]=StripEscapes(row[1] or "") end
		assert.matches("unknown",table.concat(lines," "),1,true);main:ClosePopup();controls.close:Click()
	end)
	it("adds socket currencies directly from the recipe picker",function()
		local kept;local controls=require("Classes.CraftingRecipeControl").Open({steps={},targets={},requirements={links=6}},{method="alchemy"},function(recipe) kept=recipe end)
		for _,name in ipairs({"Jeweller's Orb (experimental)","Orb of Fusing (experimental)","Tainted Chromatic Orb","Tainted Jeweller's Orb","Tainted Orb of Fusing","Jeweller's Orb + Omen of the Jeweller","Orb of Fusing + Omen of Connections","Omen of Trichromatism (RGB)"}) do
			controls.addCurrency:Click();local browser=main.popups[1].controls;browser.search:SetText(name);browser.search.changeFunc()
			assert.is_true(browser.choose:IsEnabled());browser.choose:Click()
		end
		controls.keep:Click();assert.is_truthy(kept);local methods={};for _,step in ipairs(kept.steps) do methods[#methods+1]=step.method end
		assert.same({"jeweller","fusing","tainted_chromatic","tainted_jeweller","tainted_fusing","omen_jeweller","omen_connections","omen_trichromatism"},methods)
	end)
	it("adds advanced currencies from the recipe picker",function()
		local kept;local controls=require("Classes.CraftingRecipeControl").Open({steps={},targets={},requirements={minAffixes=4}},{method="alchemy"},function(recipe) kept=recipe end)
		for _,name in ipairs({"Fracturing Orb","Veiled Exalted Orb","Eldritch Chaos Orb","Tainted Exalted Orb","Orb of Remembrance (measured distribution)"}) do
			controls.addCurrency:Click();local browser=main.popups[1].controls;browser.search:SetText(name);browser.search.changeFunc()
			if name=="Tainted Exalted Orb" then local text={};for _,row in ipairs(browser.details.list) do text[#text+1]=StripEscapes(row[1] or "") end;assert.matches("unverified",table.concat(text," "),1,true) end
			assert.is_true(browser.choose:IsEnabled());browser.choose:Click()
		end
		controls.keep:Click();assert.is_truthy(kept);local methods={};for _,step in ipairs(kept.steps) do methods[#methods+1]=step.method end
		assert.same({"fracture","veiled_orb","eldritch_chaos","tainted_exalt","remembrance"},methods)
	end)
	it("offers all supported Harvest reforge tags without inventing augments",function()
		local kept;local controls=require("Classes.CraftingRecipeControl").Open({steps={},targets={},requirements={minAffixes=4}},{method="alchemy"},function(recipe) kept=recipe end)
		for _,tag in ipairs({"minion","elemental","attribute","mana","drop"}) do
			controls.addCurrency:Click();local browser=main.popups[1].controls;browser.search:SetText("reforge with a tagged modifier ("..tag..")");browser.search.changeFunc()
			if tag=="minion" then local details={};for _,row in ipairs(browser.details.list) do details[#details+1]=StripEscapes(row[1] or "") end;local text=table.concat(details," ");assert.matches("200 Primal Crystallised Lifeforce",text,1,true);assert.matches("3 Crystallised Rancour",text,1,true) end
			assert.is_true(browser.choose:IsEnabled());browser.choose:Click()
		end
		controls.addCurrency:Click();local browser=main.popups[1].controls;browser.search:SetText("add tagged / remove random (minion)");browser.search.changeFunc();assert.is_false(browser.choose:IsEnabled());browser.close:Click()
		controls.keep:Click();assert.is_truthy(kept);local tags={};for _,step in ipairs(kept.steps) do assert.equal("harvest_reforge",step.method);tags[#tags+1]=step.tag end
		assert.same({"minion","elemental","attribute","mana","drop"},tags)
	end)
	it("offers tracking from the selected recipe step without keeping the recipe",function()
		local model=require("Modules.CraftingSimulator").model(raw);build.savers.CraftingProjects:Upsert(project())
		local step=action();local controls=require("Classes.CraftingRecipeControl").Open({steps={step},targets={}},step,function() error("Recipe should not be kept") end,model,
			{trackUnlock=function(selected,context) return require("Modules.CraftingUnlockTasks").track(build,"body",context,selected) end})
		assert.is_true(controls.trackUnlock:IsEnabled());controls.trackUnlock:Click()
		assert.equal("Recipe unlock",main.popups[1].title);assert.equal(1,#build.savers.BuildJourney.data.milestones)
		assert.is_nil(build.savers.CraftingProjects.projects[1].nativeRecipe);main:ClosePopup();controls.close:Click()
	end)
end)
