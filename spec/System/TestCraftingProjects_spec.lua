describe("Crafting projects", function()
	local projects = require("Modules.CraftingProjects")
	local bridge = require("Modules.DesktopBuildBridge")
	local json = require("dkjson")
	before_each(function() newBuild(); bridge.prepared=nil end)
	after_each(function() bridge.prepared=nil; bridge.history={}; main.popups={} end)
	local function project()
		return {id="life-helmet",title="Life helmet",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",
			targetItem="Rarity: RARE\nPlanned Hat\nIron Hat\n+100 to maximum Life",goals={"100 Life"},
			steps={{action="Choose and test a method in Craft of Exile",stopWhen="Target modifiers present",onFailure="Stop at budget limit"}}}
	end
	it("preserves written quality steps that are incompatible with unique jewellery",function()
		local ring="Rarity: UNIQUE\nAhkeli's Meadow\nRuby Ring\nItem Level: 86\nImplicits: 1\n+25% to Fire Resistance\n+20 to Strength\n5% increased maximum Energy Shield\n5% increased maximum Life"
		for _,case in ipairs({{method="quality",action="Use 1 Armourer's Scrap"},{method="tainted_quality",action="Use a Tainted Armourer's Scrap to reroll quality",corrupted=true}}) do
			local p=project();p.slot="Ring 1";p.targetItem=nil;p.startingItem=ring..(case.corrupted and "\nCorrupted" or "");p.steps={{action=case.action,uniqueCraft={method=case.method,count=1}}}
			local result=projects.validate(p);assert.equal(case.action,result.steps[1].action);assert.is_nil(result.steps[1].uniqueCraft)
			build.savers.CraftingProjects:Upsert(result)
		end
		local p=project();p.startingItem="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nCorrupted";p.steps={{action="Use a Tainted Armourer's Scrap to reroll quality",uniqueCraft={method="tainted_quality",count=1}}}
		assert.equal("tainted_quality",projects.validate(p).steps[1].uniqueCraft.method)
	end)
	it("presents guarded planning errors without source paths or missing messages", function()
		local ui=require("Modules.PlanningUI")
		local function message()
			local labels={};for _,control in pairs(main.popups[1].controls) do if type(control.label)=="string" then labels[#labels+1]=control.label end end
			return table.concat(labels," ")
		end
		local bad=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{0,0,120,28},"Test",function() error("C:\\work\\test.lua:12: Invalid value",0) end))
		bad:Click();assert.matches("Invalid value",message(),1,true);assert.is_nil(message():find(".lua:",1,true));main:ClosePopup()
		local empty=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{0,0,120,28},"Test",function() error(nil,0) end))
		empty:Click();assert.matches("Unable to complete this action.",message(),1,true)
	end)
	it("keeps long guarded errors readable and closable", function()
		local headless=require("Modules.HeadlessUI").install({width=960,height=640});headless:bind(build)
		local ok,err=pcall(function()
			local ui=require("Modules.PlanningUI")
			local detail=string.rep("Check the saved item and its crafting conditions. ",100).."Final guidance."
			local bad=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{0,0,120,28},"Test",function() error(detail,0) end))
			bad:Click();local popup=main.popups[1];assert.is_true(popup.width<=main.screenW-40);assert.is_true(popup.height<=main.screenH-48)
			local lines={};for _,row in ipairs(popup.controls.message.list) do lines[#lines+1]=StripEscapes(row[1] or "") end
			assert.matches("Final guidance.",table.concat(lines," "),1,true);assert.is_true(popup.controls.close:IsEnabled())
			headless:frame();assert.is_true(popup.controls.message.controls.scrollBar.offsetMax>0)
			popup.controls.close:Click();assert.is_nil(main.popups[1])
		end)
		headless:restore();assert.is_true(ok,err)
	end)

	it("previews a target and project separately without changing or saving the live build", function()
		local entry=project()
		local revision=bridge.revision(build)
		local prepared=bridge.prepare(build,{mode="edit",title=entry.title,baseRevision=revision,operations={{type="set_crafting_project",project=entry},{type="equip_item",slot=entry.slot,text=entry.targetItem}}})
		assert.are.equal(0,#build.savers.CraftingProjects.projects)
		assert.are.equal(1,#prepared.candidate.savers.CraftingProjects.projects)
		assert.is_true(prepared.after.LifeUnreserved > prepared.before.LifeUnreserved)
		assert.are.equal(revision,bridge.revision(build))
		assert.is_truthy(table.concat(prepared.changes," "):find("Stop at budget limit",1,true))
	end)

	it("round trips plans and opaque simulator exports through the native build XML", function()
		local entry=project()
		entry.primarySimulation={trials=40,maxActions=25,seed=777}
		entry.simulatorExport='{"data":"<not executable>&"}'
		entry.steps[1].done=true
		build.savers.CraftingProjects:Upsert(entry)
		local prepared=bridge.prepare(build,{mode="edit",title="Keep crafting metadata",baseRevision=bridge.revision(build),operations={{type="set_character",level=80}}})
		local loaded=prepared.candidate.savers.CraftingProjects.projects[1]
		assert.are.equal(entry.simulatorExport,loaded.simulatorExport)
		assert.are.same(entry.primarySimulation,loaded.primarySimulation)
		assert.is_true(loaded.steps[1].done)
		assert.are.equal(entry.steps[1].onFailure,loaded.steps[1].onFailure)
	end)

	it("rejects invalid saved primary simulation settings without replacing the project",function()
		local entry=project();entry.primarySimulation={trials=40,maxActions=25,seed=777};local store=build.savers.CraftingProjects;store:Upsert(entry)
		for _,settings in ipairs({{trials=0,maxActions=1,seed=1},{trials=1.5,maxActions=1,seed=1},{trials=201,maxActions=100,seed=1},{trials=1,maxActions=1,seed=0},{trials=1,maxActions=1,seed=1,extra=true}}) do
			local invalid=copyTable(entry);invalid.primarySimulation=settings;assert.has_error(function() store:Upsert(invalid) end);assert.are.same(entry.primarySimulation,store.projects[1].primarySimulation)
		end
		local oldClient=copyTable(entry);oldClient.primarySimulation=nil;oldClient.title="Edited guide";store:Upsert(oldClient);assert.are.same(entry.primarySimulation,store.projects[1].primarySimulation)
		oldClient.primarySimulation=false;store:Upsert(oldClient);assert.is_nil(store.projects[1].primarySimulation)
	end)

	it("preserves unsupported metadata instead of discarding it while loading a build", function()
		local store=projects.new(build)
		local raw='{"schemaVersion":99,"projects":[]}'
		store:Load({raw})
		assert.is_truthy(store.warning)
		local xml={}; store:Save(xml)
		assert.are.equal(raw,xml[1])
		assert.are.equal(false,pcall(store.Upsert,store,project()))
	end)

	it("rejects invalid equipment targets without imposing a project count limit", function()
		local store=build.savers.CraftingProjects
		local entry=project(); entry.targetItem="Rarity: NORMAL\nGold Ring"
		assert.are.equal(false,pcall(store.Upsert,store,entry))
		assert.are.equal(0,#store.projects)
		for i=1,64 do entry=project();entry.id="project-"..i;store:Upsert(entry) end
		assert.are.equal(64,#store.projects)
		entry=project();entry.id="project-32";entry.notes="Alternative route updated";store:Upsert(entry)
		assert.are.equal(64,#store.projects);assert.are.equal(entry.notes,store.projects[32].notes)
		local prepared=bridge.prepare(build,{mode="edit",title="Keep all gear plans",baseRevision=bridge.revision(build),operations={{type="set_character",level=80}}})
		local loaded=prepared.candidate.savers.CraftingProjects
		assert.are.equal(64,#loaded.projects);assert.are.equal("project-64",loaded.projects[64].id);assert.are.equal(entry.notes,loaded.projects[32].notes)
	end)
	it("keeps long guides and goals through native editing and save/reopen",function()
		local entry=project();entry.goals={};entry.steps={}
		for i=1,20 do entry.goals[i]="Goal "..i end
		for i=1,75 do entry.steps[i]={action="Craft step "..i,stopWhen="Stop "..i,done=i==1} end
		build.savers.CraftingProjects:Upsert(entry)
		require("Classes.CraftingProjectControl").Open(build);main.popups[1].controls.edit:Click()
		local c=main.popups[1].controls;c.steps:SetText(c.steps.buf.."\nCraft step 76")
		c.wizardPage:SelByValue("Review");c.wizardPage.selFunc();c.save:Click()
		local xml={};build.savers.CraftingProjects:Save(xml);local loaded=projects.new(build);loaded:Load(xml)
		assert.is_nil(loaded.warning);assert.equal(20,#loaded.projects[1].goals);assert.equal(76,#loaded.projects[1].steps)
		assert.equal("Stop 1",loaded.projects[1].steps[1].stopWhen);assert.is_true(loaded.projects[1].steps[1].done)
		assert.equal("Craft step 76",loaded.projects[1].steps[76].action)
		local bad=project();bad.steps={[1]={action="One"},[3]={action="Three"}};assert.has_error(function() projects.validate(bad) end)
	end)
	it("finds and updates any long-guide step without changing its instructions",function()
		local entry=project();entry.steps={};for i=1,76 do entry.steps[i]={action="Craft step "..i,stopWhen="Stop "..i,onFailure="Recover "..i} end
		local store=build.savers.CraftingProjects;store:Upsert(entry)
		local parent=require("Classes.CraftingProjectControl").Open(build);assert.is_true(parent.browseSteps:IsEnabled());parent.browseSteps:Click()
		local c=main.popups[1].controls;c.search:SetText("Recover 76",true);assert.equal(1,#c.results.list);c.results.planningSelect(c.results.list[1])
		assert.equal("Mark done",c.toggle.label());c.toggle:Click();assert.is_true(store.projects[1].steps[76].done);assert.equal("Recover 76",store.projects[1].steps[76].onFailure)
		assert.equal("Mark to do",c.toggle.label());c.toggle:Click();assert.is_false(store.projects[1].steps[76].done)
		c.status:SelByValue("Done");c.status.selFunc();assert.is_nil(c.results.list[1].index)
		local xml={};store:Save(xml);local reopened=projects.new(build);reopened:Load(xml);assert.is_false(reopened.projects[1].steps[76].done)
	end)
	it("preserves duplicate step metadata and removes the intended duplicate explicitly",function()
		local entry=project();entry.steps={{action="Repeat craft",done=true,stopWhen="First result"},{action="Repeat craft",done=false,onFailure="Second recovery"}}
		local store=build.savers.CraftingProjects;store:Upsert(entry)
		require("Classes.CraftingProjectControl").Open(build).edit:Click();local c=main.popups[1].controls
		c.steps:SetText(c.steps.buf.."\nFinish craft");c.wizardPage:SelByValue("Review");c.wizardPage.selFunc();c.save:Click()
		assert.equal(3,#store.projects[1].steps);assert.is_true(store.projects[1].steps[1].done);assert.equal("Second recovery",store.projects[1].steps[2].onFailure)
		main.popups[1].controls.edit:Click();c=main.popups[1].controls;c.steps:SetText("Repeat craft\nFinish craft");c.wizardPage:SelByValue("Method & budget");c.next:Click()
		assert.equal("Planning tool",main.popups[1].title);local warning={};for _,control in pairs(main.popups[1].controls) do if type(control.label)=="string" then warning[#warning+1]=control.label end end
		local message=table.concat(warning," ");assert.matches("Browse guide steps",message,1,true);assert.is_nil(message:find(".lua:",1,true))
		main:ClosePopup();assert.equal("Repeat craft\nFinish craft",main.popups[1].controls.steps.buf);main:ClosePopup()
		main.popups[1].controls.browseSteps:Click();c=main.popups[1].controls;c.results.planningSelect(c.results.list[2]);c.remove:Click()
		assert.equal("Remove crafting step",main.popups[1].title);main.popups[1].controls.confirm:Click()
		assert.equal(2,#store.projects[1].steps);assert.is_true(store.projects[1].steps[1].done);assert.equal("First result",store.projects[1].steps[1].stopWhen)
	end)
	it("removes unannotated duplicates while retaining protected instructions",function()
		local entry=project();entry.steps={{action="Repeat craft"},{action="Repeat craft",done=true,stopWhen="Keep result"},{action="Repeat craft"}}
		local store=build.savers.CraftingProjects;store:Upsert(entry)
		require("Classes.CraftingProjectControl").Open(build).edit:Click();local c=main.popups[1].controls
		c.steps:SetText("Repeat craft");c.wizardPage:SelByValue("Review");c.wizardPage.selFunc();c.save:Click()
		assert.equal(1,#store.projects[1].steps);assert.is_true(store.projects[1].steps[1].done);assert.equal("Keep result",store.projects[1].steps[1].stopWhen)
		main.popups[1].controls.edit:Click();c=main.popups[1].controls;c.steps:SetText("");c.wizardPage:SelByValue("Method & budget");c.next:Click()
		assert.equal("Planning tool",main.popups[1].title);assert.equal("Keep result",store.projects[1].steps[1].stopWhen)
	end)
	it("edits a step without losing its progress or recovery notes",function()
		local entry=project();entry.steps={{action="Original instruction",stopWhen="Original goal",onFailure="Original recovery",done=true}}
		local store=build.savers.CraftingProjects;store:Upsert(entry)
		require("Classes.CraftingProjectControl").Open(build).edit:Click();local wizard=main.popups[1].controls
		wizard.steps:SetText("Revised instruction");wizard.wizardPage:SelByValue("Method & budget");wizard.next:Click()
		assert.equal("Planning tool",main.popups[1].title);main:ClosePopup();main:ClosePopup()
		main.popups[1].controls.browseSteps:Click();local browser=main.popups[1].controls;browser.results.planningSelect(browser.results.list[1]);browser.edit:Click()
		local edit=main.popups[1].controls;edit.action:SetText("Revised instruction");edit.stop:SetText("Revised goal");edit.saveStep:Click()
		local step=store.projects[1].steps[1];assert.equal("Revised instruction",step.action);assert.equal("Revised goal",step.stopWhen);assert.equal("Original recovery",step.onFailure);assert.is_true(step.done)
	end)
	it("undoes a step removal without overwriting later project changes",function()
		local entry=project();entry.steps={{action="First",done=true,stopWhen="Keep this",onFailure="Recovery"},{action="Second"}}
		local store=build.savers.CraftingProjects;store:Upsert(entry)
		local browser=require("Classes.CraftingGuideStepsControl").Open(build,entry.id);browser.results.planningSelect(browser.results.list[1]);browser.remove:Click();main.popups[1].controls.confirm:Click()
		assert.equal(1,#store.projects[1].steps);assert.is_true(browser.undoRemove:IsEnabled())
		local updated=copyTable(store.projects[1]);updated.notes="Updated independently";store:Upsert(updated);browser.undoRemove:Click()
		assert.equal(2,#store.projects[1].steps);assert.is_true(store.projects[1].steps[1].done);assert.equal("Recovery",store.projects[1].steps[1].onFailure);assert.equal("Updated independently",store.projects[1].notes)
		browser.results.planningSelect(browser.results.list[1]);browser.remove:Click();main.popups[1].controls.confirm:Click()
		updated=copyTable(store.projects[1]);updated.steps[1].action="Changed later";store:Upsert(updated);browser.undoRemove:Click()
		assert.equal("Crafting guide",main.popups[1].title);assert.equal(1,#store.projects[1].steps);assert.equal("Changed later",store.projects[1].steps[1].action)
	end)
	it("preserves malformed project collections",function()
		local store=build.savers.CraftingProjects
		for _,raw in ipairs({'{"schemaVersion":1,"projects":{}}','{"schemaVersion":1,"projects":{"one":{}}}','{"schemaVersion":1,"projects":[null]}','{"schemaVersion":1,"projects":null}',string.rep(" ",2*1024*1024).."{}"}) do
			local loaded=projects.new(build);loaded:Load({raw});assert.is_truthy(loaded.warning)
			local xml={};loaded:Save(xml);assert.are.equal(raw,xml[1])
		end
	end)
	it("saves and reopens crafting collections larger than the former limit",function()
		local store=build.savers.CraftingProjects;local entry=project();entry.notes=string.rep("x",8000)
		entry.simulatorExport=string.rep("x",128000)
		for i=1,15 do entry.id="large-"..i;store:Upsert(entry) end
		entry.id="large-16";store:Upsert(entry);assert.are.equal(16,#store.projects)
		local xml={};store:Save(xml);assert.is_true(#xml[1]>2*1024*1024)
		local reopened=projects.new(build);reopened:Load(xml);assert.is_nil(reopened.warning)
		assert.are.equal(16,#reopened.projects);assert.are.equal(entry.simulatorExport,reopened.projects[16].simulatorExport)
		local saved=build:SaveDB("Large guides");loadBuildFromXML(saved,"Large guides")
		assert.is_nil(build.savers.CraftingProjects.warning);assert.are.equal(16,#build.savers.CraftingProjects.projects)
		assert.are.equal(entry.simulatorExport,build.savers.CraftingProjects.projects[16].simulatorExport)
	end)
	it("keeps a different equipment base after recombination without changing its slot", function()
		local entry=project();entry.targetItem="Rarity: NORMAL\nLeather Cap"
		build.savers.CraftingProjects:Upsert(entry)
		assert.are.equal("Leather Cap",projects.item(build.savers.CraftingProjects.projects[1].targetItem).baseName)
	end)

	it("labels lossy base handoffs and retains advanced game copies", function()
		local basic=projects.handoff(project().targetItem)
		assert.are.equal("base-only",basic.mode)
		assert.is_truthy(basic.warnings[1]:find("not transferred",1,true))
		assert.is_nil(basic.itemText:find("maximum Life",1,true))
		local raw="Item Class: Helmets\nRarity: Rare\nTest Hat\nIron Hat\n--------\nItem Level: 86\n--------\n{ Prefix Modifier \"Virile\" (Tier: 3) }\n+100 to maximum Life\n--------"
		local advanced=projects.handoff(raw)
		assert.are.equal("advanced-item",advanced.mode)
		assert.is_truthy(advanced.url:find("%2B100",1,true))
		assert.is_truthy(advanced.url:find("%0D%0A",1,true))
		assert.are.equal(raw,advanced.itemText)
	end)

	it("filters native modifier references by item level without presenting weights as odds", function()
		local early=projects.inspect("Rarity: NORMAL\nIron Hat\nItem Level: 1","maximum Life",100)
		local late=projects.inspect(project().startingItem,"maximum Life",100)
		assert.is_true(late.total > early.total)
		for _,entry in ipairs(early.matches) do assert.is_true(entry.level <= 1) end
		assert.is_truthy(late.limitations[2]:find("not success probabilities",1,true))
	end)

	it("records external simulation counts as supplied evidence and rejects impossible totals", function()
		local entry=project()
		entry.simulation={patch="3.29",observedAt=os.time(),trials=100,successes=25}
		local validated=projects.validate(entry)
		assert.are.equal(25,validated.simulation.successes)
		assert.is_truthy(table.concat(projects.lines(validated)," "):find("not rerun or verified",1,true))
		entry.simulation.successes=101
		assert.are.equal(false,pcall(projects.validate,entry))
	end)

	it("supports native project editing and reversible step progress", function()
		local panel=require("Classes.CraftingProjectControl")
		build.savers.CraftingProjects:Upsert(project())
		panel.Open(build)
		main.popups[1]:Draw({x=0,y=0,width=1920,height=1080})
		main.popups[1].controls.done:Click()
		assert.is_true(build.savers.CraftingProjects.projects[1].steps[1].done)
		main.popups[1].controls.undoStep:Click()
		assert.are.equal(false,build.savers.CraftingProjects.projects[1].steps[1].done)
		main.popups[1].controls.edit:Click()
		main.popups[1]:Draw({x=0,y=0,width=1920,height=1080})
		main.popups[1].controls.title:SetText("Edited plan")
		main.popups[1].controls.wizardPage:SelByValue("Review");main.popups[1].controls.wizardPage.selFunc()
		main.popups[1].controls.save:Click()
		assert.are.equal("Edited plan",build.savers.CraftingProjects.projects[1].title)
		assert.is_true(build.modFlag)
	end)

	it("emulates currency, undoes outcomes and saves a native recipe through desktop controls", function()
		local entry=project()
		build.savers.CraftingProjects:Upsert(entry)
		require("Classes.CraftingSimulatorControl").Open(build,entry)
		local popup=main.popups[1]
		popup:Draw({x=0,y=0,width=1920,height=1080})
		popup.controls.apply:Click()
		popup.controls.undo:Click()
		popup.controls.apply:Click()
		popup.controls.page:SelByValue("Target conditions")
		popup.controls.addTarget:Click()
		popup.controls.page:SelByValue("Craft settings")
		popup.controls.keepRecipe:Click()
		assert.is_truthy(build.savers.CraftingProjects.projects[1].nativeRecipe)
		assert.are.equal(1,#build.savers.CraftingProjects.projects[1].nativeRecipe.steps)
		assert.are.equal(0,build.itemsTab.slots.Helmet.selItemId)
		assert.are.equal("Crafting workbench",main.popups[1].title)
	end)

	it("lets the user inspect and keep an Allflame ghost without equipping it", function()
		local entry=project();build.savers.CraftingProjects:Upsert(entry)
		require("Classes.CraftingSimulatorControl").Open(build,entry)
		local panel=main.popups[1];panel.controls.page:SelByValue("Craft settings");panel.controls.allflame:Click()
		local settings=main.popups[1]
		settings.controls.mode:SelByValue("Observed override")
		settings.controls.outcomes:SetText("4");settings.controls.gainMin:SetText("0");settings.controls.gainMax:SetText("0");settings.controls.sulphur:SetText("100")
		settings.controls.use:Click();panel.controls.page:SelByValue("Emulate item");panel.controls.apply:Click()
		local choices=main.popups[1]
		assert.are.equal("Allflame outcomes",choices.title)
		assert.are.equal(4,#choices.controls.choice.list)
		choices.controls.choice:SelByValue(3,"val");choices.controls.keep:Click()
		panel.controls.page:SelByValue("Target conditions");panel.controls.addTarget:Click()
		panel.controls.page:SelByValue("Craft settings");panel.controls.keepRecipe:Click()
		assert.are.equal(3,build.savers.CraftingProjects.projects[1].nativeRecipe.steps[1].allflame.choiceIndex)
		assert.are.equal(0,build.itemsTab.slots.Helmet.selItemId)
	end)
	it("stages a manually edited recipe start without equipping or mutating the source",function()
		local sim=require("Modules.CraftingSimulator");local entry=project();local model=sim.model(entry.startingItem)
		local original=copyTable(model.initial);local kept
		local editor=require("Classes.CraftingItemEditorControl").Open(model,original,function(state) kept=state end)
		editor.rarity:SelByValue("RARE");editor.properties:Click()
		editor.fractured:SelByValue("Fractured");editor.add:Click()
		editor.keep:Click()
		assert.is_truthy(kept);assert.are.equal(1,#kept.affixes);assert.is_true(kept.affixes[1].fractured)
		assert.are.equal(0,#original.affixes);assert.are.equal("NORMAL",original.rarity)
		assert.are.equal(0,build.itemsTab.slots.Helmet.selItemId)
	end)
	it("stages a drop-only modifier from the browser and keeps the recipe",function()
		local entry=project();build.savers.CraftingProjects:Upsert(entry)
		require("Classes.CraftingSimulatorControl").Open(build,entry)
		local workbench=main.popups[1];workbench.controls.page:SelByValue("Target conditions");workbench.controls.targetPicker:Click()
		local browser=main.popups[1];local id="FireResistEnhancedLevel50ModPhys"
		browser.controls.search:SetText(id,true);assert.is_true(browser.controls.present:IsEnabled());browser.controls.present:Click()
		assert.equal("Crafting workbench",main.popups[1].title)
		workbench.controls.addTarget:Click()
		workbench.controls.method:SelByValue("divine","val");workbench.controls.method.selFunc();workbench.controls.page:SelByValue("Emulate item");workbench.controls.apply:Click()
		assert.equal("Crafting workbench",main.popups[1].title)
		workbench.controls.page:SelByValue("Craft settings");assert.is_true(workbench.controls.keepRecipe:IsEnabled());workbench.controls.keepRecipe:Click()
		assert.equal("Crafting workbench",main.popups[1].title)
		local saved=build.savers.CraftingProjects.projects[1];assert.equal(id,saved.nativeRecipe.initialState.affixes[1].id)
		assert.equal("divine",saved.nativeRecipe.steps[1].method);assert.equal(0,build.itemsTab.slots.Helmet.selItemId)
		local reopened=bridge.prepare(build,{mode="edit",title="Reopen crafting guide",baseRevision=bridge.revision(build),operations={{type="set_character",level=80}}}).candidate
		saved=reopened.savers.CraftingProjects.projects[1];assert.equal(id,saved.nativeRecipe.initialState.affixes[1].id)
		main.popups={};require("Classes.CraftingSimulatorControl").Open(reopened,saved)
		assert.equal("Crafting workbench",main.popups[1].title)
		assert.is_truthy(table.concat((function() local lines={};for _,row in ipairs(main.popups[1].controls.itemMods.list) do lines[#lines+1]=row[1] end;return lines end)()," "):find("Fire Resistance",1,true))
	end)
	it("keeps and reopens a Harvest recipe for a legacy Delve prefix",function()
		local item=new("Item"):Item("Rarity: RARE\nLegacy Hat\nIron Hat\nItem Level: 86\nCrafted: true\nPrefix: DelveArmourFireResistance1");item:Craft()
		local entry=project();entry.startingItem=item.raw;entry.targetItem=nil;build.savers.CraftingProjects:Upsert(entry)
		require("Classes.CraftingSimulatorControl").Open(build,entry)
		local workbench=main.popups[1];workbench.controls.method:SelByValue("harvest_resistance","val");workbench.controls.method.selFunc()
		workbench.controls.option:SelByValue("fire to cold","label");workbench.controls.option.selFunc()
		workbench.controls.page:SelByValue("Emulate item");assert.is_true(workbench.controls.apply:IsEnabled());workbench.controls.apply:Click()
		assert.equal("Crafting workbench",main.popups[1].title)
		workbench.controls.page:SelByValue("Target conditions");workbench.controls.addTarget:Click()
		workbench.controls.page:SelByValue("Craft settings");workbench.controls.keepRecipe:Click()
		local saved=build.savers.CraftingProjects.projects[1]
		assert.equal("harvest_resistance",saved.nativeRecipe.steps[1].method)
		assert.equal("cold",saved.nativeRecipe.steps[1].to)
		assert.is_truthy(saved.targetItem:find("Cold Resistance",1,true));assert.equal(0,build.itemsTab.slots.Helmet.selItemId)
		local reopened=bridge.prepare(build,{mode="edit",title="Reopen crafting guide",baseRevision=bridge.revision(build),operations={{type="set_character",level=80}}}).candidate
		saved=reopened.savers.CraftingProjects.projects[1]
		local result=require("Modules.CraftingSimulator").simulate(saved.startingItem,saved.nativeRecipe,{trials=2,maxActions=1})
		assert.is_nil(next(result.transitionErrors));assert.is_truthy(result.sampleItem:find("Cold Resistance",1,true))
	end)
	it("keeps an Incursion resistance conversion in a saved crafting guide",function()
		local entry=project();entry.targetItem=nil
		entry.startingItem="Rarity: RARE\nDread Crest\nIron Hat\nItem Level: 86\n+47% to Fire Resistance\n4% of Physical Damage from Hits taken as Fire Damage"
		build.savers.CraftingProjects:Upsert(entry);require("Classes.CraftingSimulatorControl").Open(build,entry)
		local workbench=main.popups[1];workbench.controls.method:SelByValue("harvest_resistance","val");workbench.controls.method.selFunc()
		workbench.controls.option:SelByValue("fire to cold","label");workbench.controls.option.selFunc()
		workbench.controls.page:SelByValue("Emulate item");assert.is_true(workbench.controls.apply:IsEnabled());workbench.controls.apply:Click()
		assert.equal("Crafting workbench",main.popups[1].title)
		workbench.controls.page:SelByValue("Target conditions");workbench.controls.addTarget:Click()
		workbench.controls.page:SelByValue("Craft settings");workbench.controls.keepRecipe:Click()
		local saved=build.savers.CraftingProjects.projects[1];assert.is_truthy(saved.nativeRecipe)
		assert.is_truthy(saved.targetItem:find("Cold Resistance",1,true));assert.equal(0,build.itemsTab.slots.Helmet.selItemId)
		local reopened=bridge.prepare(build,{mode="edit",title="Reopen guide",baseRevision=bridge.revision(build),operations={{type="set_character",level=80}}}).candidate
		saved=reopened.savers.CraftingProjects.projects[1]
		local result=require("Modules.CraftingSimulator").simulate(saved.startingItem,saved.nativeRecipe,{trials=2,maxActions=1})
		assert.is_nil(next(result.transitionErrors));assert.is_truthy(result.sampleItem:find("Cold Resistance",1,true))
	end)

	it("keeps a compared recipe with its working starting state and confirms replacement",function()
		local entry=project();entry.preferredMethod="alchemy";entry.nativeRecipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1}}
		build.savers.CraftingProjects:Upsert(entry);local control=require("Classes.CraftingSimulatorControl").Open(build,entry)
		control.page:SelByValue("Emulate item");control.apply:Click();assert.equal("Crafting workbench",main.popups[1].title)
		control.page:SelByValue("Simulate recipe");control.compareRecipes:Click();local compare=main.popups[1].controls
		compare.edit1:Click();local editor=main.popups[1].controls;editor.add:Click();editor.keep:Click()
		compare.keep1:Click();assert.equal("Replace saved recipe",main.popups[1].title);main:ClosePopup()
		assert.equal(1,#build.savers.CraftingProjects.projects[1].nativeRecipe.steps)
		compare.keep1:Click();main.popups[1].controls.confirm:Click();assert.equal("Recipe kept",main.popups[1].title);main:ClosePopup()
		compare.edit2:Click();assert.equal(2,#main.popups[1].controls.graph.list);main:ClosePopup()
		local kept=build.savers.CraftingProjects.projects[1];assert.equal(2,#kept.nativeRecipe.steps);assert.equal("RARE",kept.nativeRecipe.initialState.rarity)
		assert.equal(entry.steps[1].action,kept.steps[1].action);assert.equal(0,build.itemsTab.slots.Helmet.selItemId)
		local reopened=bridge.prepare(build,{mode="edit",title="Reopen compared recipe",baseRevision=bridge.revision(build),operations={{type="set_character",level=80}}}).candidate
		kept=reopened.savers.CraftingProjects.projects[1];assert.equal(2,#kept.nativeRecipe.steps);assert.equal("RARE",kept.nativeRecipe.initialState.rarity)
	end)

	it("keeps, renames, promotes and removes independent recipe alternatives",function()
		local entry=project();entry.preferredMethod="alchemy";entry.nativeRecipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1}}
		build.savers.CraftingProjects:Upsert(entry);local control=require("Classes.CraftingSimulatorControl").Open(build,entry)
		control.page:SelByValue("Emulate item");control.apply:Click();assert.equal("Crafting workbench",main.popups[1].title)
		control.page:SelByValue("Simulate recipe");control.compareRecipes:Click();local compare=main.popups[1].controls
		compare.alternative1:Click();local popup=main.popups[1].controls;popup.name:SetText("First route");popup.save:Click();assert.equal("Recipe kept",main.popups[1].title);main:ClosePopup()
		compare.alternative2:Click();popup=main.popups[1].controls;popup.name:SetText("Second route");popup.save:Click();main:ClosePopup()
		local kept=build.savers.CraftingProjects.projects[1];assert.equal(2,#kept.recipeAlternatives);assert.equal(1,#kept.nativeRecipe.steps)
		local reopened=bridge.prepare(build,{mode="edit",title="Reopen alternative recipes",baseRevision=bridge.revision(build),operations={{type="set_character",level=80}}}).candidate
		assert.equal("First route",reopened.savers.CraftingProjects.projects[1].recipeAlternatives[1].name)
		compare.manageAlternatives:Click();popup=main.popups[1].controls;popup.list.onClick({line=popup.list.list[1]});popup.track:Click();assert.is_true(build.savers.CraftingProjects.projects[1].recipeAlternatives[1].trackPickups)
		popup.name:SetText("Improved route");popup.rename:Click()
		assert.equal("Improved route",build.savers.CraftingProjects.projects[1].recipeAlternatives[1].name);assert.is_true(build.savers.CraftingProjects.projects[1].recipeAlternatives[1].trackPickups)
		local tracked=bridge.prepare(build,{mode="edit",title="Reopen pickup tracking",baseRevision=bridge.revision(build),operations={{type="set_character",level=80}}}).candidate;assert.is_true(tracked.savers.CraftingProjects.projects[1].recipeAlternatives[1].trackPickups)
		popup.use:Click();assert.equal("Replace saved recipe",main.popups[1].title);main.popups[1].controls.confirm:Click();assert.equal("Recipe kept",main.popups[1].title);main:ClosePopup()
		assert.equal("RARE",build.savers.CraftingProjects.projects[1].nativeRecipe.initialState.rarity)
		popup.remove:Click();assert.equal("Remove alternative",main.popups[1].title);main.popups[1].controls.confirm:Click()
		kept=build.savers.CraftingProjects.projects[1];assert.equal(1,#kept.recipeAlternatives);assert.equal("Second route",kept.recipeAlternatives[1].name)
		local minimal=copyTable(kept);minimal.recipeAlternatives=nil;build.savers.CraftingProjects:Upsert(minimal);assert.equal(1,#build.savers.CraftingProjects.projects[1].recipeAlternatives)
		minimal.recipeAlternatives={};build.savers.CraftingProjects:Upsert(minimal);assert.equal(0,#build.savers.CraftingProjects.projects[1].recipeAlternatives)
	end)
	it("updates a renamed alternative from an edited comparison route",function()
		local entry=project();entry.preferredMethod="alchemy";entry.nativeRecipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1}}
		entry.recipeAlternatives={{name="Original",trackPickups=true,recipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1}}}}
		build.savers.CraftingProjects:Upsert(entry);local control=require("Classes.CraftingSimulatorControl").Open(build,entry)
		control.page:SelByValue("Emulate item");control.apply:Click();control.page:SelByValue("Simulate recipe");control.compareRecipes:Click();local compare=main.popups[1].controls
		local index;for i,value in ipairs(compare.route1.list) do if value.label=="Saved: Original" then index=i end end;assert.is_not_nil(index);compare.route1:SetSel(index)
		compare.edit1:Click();local editor=main.popups[1].controls;editor.add:Click();editor.keep:Click()
		compare.manageAlternatives:Click();local manager=main.popups[1].controls;manager.list.onClick({line=manager.list.list[1]});manager.name:SetText("Renamed");manager.rename:Click();manager.close:Click()
		compare.alternative1:Click();local dialog=main.popups[1].controls;assert.is_not_nil(dialog.update);dialog.update:Click();assert.equal("Update alternative",main.popups[1].title);main:ClosePopup()
		assert.equal(1,#build.savers.CraftingProjects.projects[1].recipeAlternatives[1].recipe.steps)
		dialog.update:Click();main.popups[1].controls.confirm:Click();assert.equal("Recipe kept",main.popups[1].title);main:ClosePopup()
		local kept=build.savers.CraftingProjects.projects[1];assert.equal(1,#kept.recipeAlternatives);assert.equal("Renamed",kept.recipeAlternatives[1].name)
		assert.equal(2,#kept.recipeAlternatives[1].recipe.steps);assert.equal("RARE",kept.recipeAlternatives[1].recipe.initialState.rarity);assert.is_true(kept.recipeAlternatives[1].trackPickups);assert.equal(1,#kept.nativeRecipe.steps)
		assert.equal("Saved: Renamed",compare.route1:GetSelValue().label)
		local reopened=bridge.prepare(build,{mode="edit",title="Reopen updated alternative",baseRevision=bridge.revision(build),operations={{type="set_character",level=80}}}).candidate
		assert.equal(2,#reopened.savers.CraftingProjects.projects[1].recipeAlternatives[1].recipe.steps)
	end)
	it("follows a newly saved copy when editing it again",function()
		local entry=project();entry.nativeRecipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1}}
		entry.recipeAlternatives={{name="Original",recipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1}}}}
		build.savers.CraftingProjects:Upsert(entry);local control=require("Classes.CraftingSimulatorControl").Open(build,entry);control.page:SelByValue("Simulate recipe");control.compareRecipes:Click();local compare=main.popups[1].controls
		local index;for i,value in ipairs(compare.route1.list) do if value.label=="Saved: Original" then index=i end end;compare.route1:SetSel(index)
		compare.alternative1:Click();local dialog=main.popups[1].controls;dialog.name:SetText("Copy");dialog.save:Click();main:ClosePopup();assert.equal("Saved: Copy",compare.route1:GetSelValue().label)
		compare.edit1:Click();local editor=main.popups[1].controls;editor.add:Click();editor.keep:Click();compare.alternative1:Click();dialog=main.popups[1].controls;assert.is_truthy(dialog.update.tooltipText:find("Copy",1,true));dialog.update:Click();main.popups[1].controls.confirm:Click();main:ClosePopup()
		local alternatives=build.savers.CraftingProjects.projects[1].recipeAlternatives;assert.equal(1,#alternatives[1].recipe.steps);assert.equal(2,#alternatives[2].recipe.steps)
	end)
	it("does not update an alternative after that saved entry was removed",function()
		local entry=project();entry.nativeRecipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1}}
		entry.recipeAlternatives={{name="Old",recipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1}}}}
		build.savers.CraftingProjects:Upsert(entry);local control=require("Classes.CraftingSimulatorControl").Open(build,entry);control.page:SelByValue("Simulate recipe");control.compareRecipes:Click();local compare=main.popups[1].controls
		local index;for i,value in ipairs(compare.route1.list) do if value.label=="Saved: Old" then index=i end end;compare.route1:SetSel(index)
		compare.edit1:Click();main.popups[1].controls.keep:Click();compare.manageAlternatives:Click();local manager=main.popups[1].controls;manager.list.onClick({line=manager.list.list[1]});manager.remove:Click();main.popups[1].controls.confirm:Click();manager.close:Click()
		compare.alternative1:Click();assert.is_nil(main.popups[1].controls.update)
	end)
	it("refuses to promote an alternative with an incompatible saved starting state",function()
		local entry=project();entry.nativeRecipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1}}
		entry.recipeAlternatives={{name="Incompatible",recipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1},initialState={rarity="RARE",affixes={{id="UnknownModifier",roll=1}}}}}}
		build.savers.CraftingProjects:Upsert(entry);local control=require("Classes.CraftingSimulatorControl").Open(build,entry)
		control.page:SelByValue("Simulate recipe");control.compareRecipes:Click();local compare=main.popups[1].controls;compare.manageAlternatives:Click()
		local manager=main.popups[1].controls;manager.list.onClick({line=manager.list.list[1]});manager.use:Click();main.popups[1].controls.confirm:Click()
		assert.equal("Make primary",main.popups[1].title);assert.is_nil(build.savers.CraftingProjects.projects[1].nativeRecipe.initialState)
	end)
	it("round trips more than eight recipe alternatives without a count limit",function()
		local entry=project();entry.recipeAlternatives={}
		for i=1,12 do entry.recipeAlternatives[i]={name="Route "..i,recipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1}}} end
		build.savers.CraftingProjects:Upsert(entry)
		local xml={};build.savers.CraftingProjects:Save(xml);local loaded=projects.new(build);loaded:Load(xml)
		assert.is_nil(loaded.warning);assert.equal(12,#loaded.projects[1].recipeAlternatives);assert.equal("Route 12",loaded.projects[1].recipeAlternatives[12].name)
	end)
	it("rejects duplicate or malformed recipe alternatives",function()
		local entry=project();local recipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1}}
		entry.recipeAlternatives={{name="Plan",recipe=recipe},{name=" plan ",recipe=recipe}};assert.has_error(function() projects.validate(entry) end)
		entry.recipeAlternatives={{name="^1Injected",recipe=recipe}};assert.has_error(function() projects.validate(entry) end)
		entry.recipeAlternatives={{name="Plan",recipe=recipe,trackPickups="yes"}};assert.has_error(function() projects.validate(entry) end)
		entry.recipeAlternatives={{name="Plan",recipe={steps={},targets={}}}};assert.has_error(function() projects.validate(entry) end)
	end)

end)
