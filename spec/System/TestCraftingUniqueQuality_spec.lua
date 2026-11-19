describe("Unique item quality",function()
	local quality=require("Modules.CraftingUniqueQuality")
	local shield="Rarity: UNIQUE\nThe Surrender\nEzomyte Tower Shield\nItem Level: 86\nQuality: 12\nSockets: R-G B\nImplicits: 1\n+5% Chance to Block Attack Damage\n+100 to maximum Life\n+1500 to Armour"
	local weapon="Rarity: UNIQUE\nThe Saviour\nLegion Sword\nItem Level: 86\nQuality: 0\nSockets: R-G-B\n+100% increased Physical Damage"
	before_each(function() newBuild() end)
	it("links existing unique sockets without changing any other item properties",function()
		local simulator=require("Modules.CraftingSimulator")
		local source=shield.."\nNote: Preserve unknown fields"
		local result=simulator.perform(source,{method="beast_max_links"},7)
		assert.equal(source:gsub("Sockets: R%-G B","Sockets: R-G-B"),result.itemText)
		assert.same({beast_black_morrigan=1,beast_craicic_sand_spitter=1},result.components)
		local omen=simulator.perform(source,{method="omen_connections"},7)
		assert.equal(result.itemText,omen.itemText);assert.equal("omen_connections",omen.priceKey)
		assert.equal(1,omen.components["Metadata/Items/Currency/AncestralOmenOnFusingMakeFullLinks"])
		assert.equal(1,omen.components["Metadata/Items/Currency/CurrencyRerollSocketLinks"])
		assert.has_error(function() simulator.perform(result.itemText,{method="beast_max_links"},7) end)
		assert.has_error(function() simulator.perform(source.."\nCorrupted",{method="beast_max_links"},7) end)
		assert.has_error(function() simulator.perform(source.."\nSockets cannot be modified",{method="beast_max_links"},7) end)
		assert.has_error(function() simulator.perform(source:gsub("R%-G B","R A"),{method="beast_max_links"},7) end)
		assert.has_error(function() simulator.perform(source.."\nSockets: R G",{method="beast_max_links"},7) end)
		local project={id="unique-link",title="Links",slot="Weapon 2",startingItem=source,goals={},steps={}}
		build.savers.CraftingProjects:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		assert.matches("Sockets: R%-G B",control.itemMods.list[1][1])
		assert.is_true(control.link:IsEnabled());assert.matches("Black Morrigan",control.link.tooltipText());control.link:Click();assert.is_false(control.link:IsEnabled())
		assert.matches("Sockets: R%-G%-B",control.itemMods.list[1][1])
		assert.matches("already fully linked",control.link.tooltipText())
		control.undo:Click();assert.is_true(control.link:IsEnabled());assert.is_true(control.omen:IsEnabled());control.omen:Click();control.keep:Click()
		assert.equal(result.itemText,build.savers.CraftingProjects.projects[1].targetItem)
		main.popups={}
	end)
	it("does not display inferred sockets when the item text omits them",function()
		local project={id="unknown-unique-sockets",title="Unknown sockets",slot="Weapon 2",startingItem=shield:gsub("\nSockets: R%-G B",""),goals={},steps={}}
		build.savers.CraftingProjects:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		for _,row in ipairs(control.itemMods.list) do assert.is_nil(row[1]:find("Sockets:",1,true)) end
		assert.is_false(control.link:IsEnabled());main.popups={}
	end)
	it("raises unique armour quality one point while preserving item text",function()
		local result=quality.apply(shield);assert.equal(12,result.beforeQuality);assert.equal(13,result.quality);assert.equal("Armourer's Scrap",result.resource)
		local original=new("Item"):Item(shield);local item=new("Item"):Item(result.itemText)
		assert.equal(original.title,item.title);assert.equal(original.baseName,item.baseName);assert.equal(13,item.quality)
		assert.same(original.sockets,item.sockets);assert.same(original.explicitModLines,item.explicitModLines);assert.same(original.implicitModLines,item.implicitModLines)
		assert.equal(14,quality.apply(result.itemText).quality)
		local extra=shield.."\nNote: Preserve unknown fields"
		assert.equal(extra:gsub("Quality: 12","Quality: 13"),quality.apply(extra).itemText)
		assert.has_error(function() quality.apply(shield.."\nQuality: 12") end)
		local noQuality=shield:gsub("\nQuality: 12","")
		assert.equal(noQuality.."\nQuality: 1",quality.apply(noQuality).itemText)
	end)
	it("exposes deterministic unique quality to AI actions without an ordinary state",function()
		local simulator=require("Modules.CraftingSimulator")
		local first=simulator.perform(shield,{method="quality"},1)
		assert.equal(13,first.uniqueQuality.quality);assert.is_nil(first.state)
		assert.equal(1,first.components[first.uniqueQuality.resourceKey])
		local second=simulator.perform(first.itemText,{method="quality"},2)
		assert.equal(14,second.uniqueQuality.quality)
		assert.has_error(function() simulator.perform(shield,{method="quality"},1,{}) end)
		assert.has_error(function() simulator.perform(shield,{method="quality",extra=true},1) end)
	end)
	it("keeps the chosen unique actions as guide steps without duplicating them",function()
		local project={id="unique-guide",title="Guide",slot="Weapon 2",startingItem=shield,goals={},steps={{action="Acquire the base",done=false}}}
		local store=build.savers.CraftingProjects;store:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		assert.is_false(control.guide:IsEnabled());control.apply:Click();control.apply:Click();control.omen:Click()
		assert.is_true(control.guide:IsEnabled());control.guide:Click();assert.is_false(control.guide:IsEnabled())
		local saved=store.projects[1];assert.equal(3,#saved.steps);assert.equal("Acquire the base",saved.steps[1].action)
		assert.equal("Use 2 Armourer's Scraps",saved.steps[2].action);assert.matches("Omen of Connections",saved.steps[3].action)
		assert.matches("Sockets: R%-G%-B",saved.targetItem)
		control.close:Click();control=require("Classes.CraftingUniqueQualityControl").Open(build,saved);assert.is_false(control.guide:IsEnabled())
		control.apply:Click();assert.is_true(control.guide:IsEnabled());control.guide:Click()
		saved=store.projects[1];assert.equal(4,#saved.steps);assert.equal("Use 1 Armourer's Scrap",saved.steps[4].action)
		control.undo:Click();assert.is_false(control.guide:IsEnabled());assert.matches("no longer follows",control.guide.tooltipText());assert.is_true(control.redo:IsEnabled())
		control.redo:Click();assert.is_false(control.redo:IsEnabled());assert.matches("already in the guide",control.guide.tooltipText());control.undo:Click()
		control.close:Click();local changed=copyTable(saved);changed.steps[1].action="Changed starting step"
		control=require("Classes.CraftingUniqueQualityControl").Open(build,changed);assert.is_false(control.guide:IsEnabled());assert.matches("saved guide changed",control.guide.tooltipText())
		local legacy={kind="uniqueQuality",project=saved,itemText=saved.targetItem,history={shield}}
		main.popups={};control=require("Classes.CraftingUniqueQualityControl").Open(build,saved,nil,legacy)
		assert.is_false(control.guide:IsEnabled());assert.matches("older previews",control.guide.tooltipText())
		control.undo:Click();assert.is_true(control.redo:IsEnabled());control.redo:Click();assert.is_false(control.guide:IsEnabled())
		legacy.actions={"quality"};legacy.savedTrace=string.rep("a",40)
		main.popups={};control=require("Classes.CraftingUniqueQualityControl").Open(build,saved,nil,legacy)
		assert.is_false(control.guide:IsEnabled());assert.matches("cannot be verified",control.guide.tooltipText());main.popups={}
	end)
	it("clears redo when a different unique craft is chosen",function()
		local project={id="unique-redo",title="Redo",slot="Weapon 2",startingItem=shield,goals={},steps={}}
		build.savers.CraftingProjects:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		control.link:Click();control.undo:Click();assert.is_true(control.redo:IsEnabled())
		control.omen:Click();assert.is_false(control.redo:IsEnabled());main.popups={}
	end)
	it("does not invent crafting steps when a loaded target is undone and redone",function()
		local project={id="unique-redo-target",title="Redo target",slot="Weapon 2",startingItem=shield,goals={},steps={}}
		build.savers.CraftingProjects:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		control.apply:Click();control.keep:Click();control.undo:Click();assert.is_true(control.loadTarget:IsEnabled())
		control.loadTarget:Click();control.undo:Click();assert.is_true(control.redo:IsEnabled());control.redo:Click()
		assert.matches("13%%",control.status.label);assert.is_false(control.guide:IsEnabled())
		assert.matches("Loaded or older previews",control.guide.tooltipText());main.popups={}
	end)
	it("lets the user review an edited guide before adding new preview actions",function()
		local project={id="review-guide",title="Review guide",slot="Weapon 2",startingItem=shield,goals={},steps={{action="Acquire the item"}}}
		local store=build.savers.CraftingProjects;store:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		control.apply:Click();control.guide:Click();control.close:Click()
		local changed=copyTable(store.projects[1]);changed.steps[1].action="Acquire the unique shield"
		control=require("Classes.CraftingUniqueQualityControl").Open(build,changed);control.apply:Click()
		assert.is_false(control.guide:IsEnabled());assert.is_true(control.reviewGuide:IsShown());assert.is_true(control.reviewGuide:IsEnabled())
		control.reviewGuide:Click();local browser=main.popups[1].controls
		assert.is_nil(browser.search);assert.matches("Review guide",browser.heading.label)
		local details={};for _,row in ipairs(browser.details.list) do details[#details+1]=row[1] end
		assert.matches("Acquire the unique shield",table.concat(details," "));browser.choose:Click()
		assert.is_true(control.guide:IsEnabled());control.guide:Click()
		local saved=store.projects[1];assert.equal(3,#saved.steps);assert.equal("Acquire the unique shield",saved.steps[1].action);assert.equal("Use 1 Armourer's Scrap",saved.steps[3].action)
		assert.is_false(control.reviewGuide:IsShown());main.popups={}
	end)
	it("keeps a preview as a saved crafting project target",function()
		local project={id="unique-quality",title="Quality",slot="Weapon 2",startingItem=shield,goals={},steps={}}
		local store=build.savers.CraftingProjects;store:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		local ui=require("Modules.PlanningUI")
		assert.is_false(ui.hasDraft(build,"uniqueQuality",project.id))
		control.apply:Click();assert.matches("13%%",control.status.label);assert.is_true(ui.hasDraft(build,"uniqueQuality",project.id))
		assert.matches("Working draft",ui.saveStatus(build));ui.saved(build);assert.matches("Working draft",ui.saveStatus(build))
		control.undo:Click();assert.matches("12%%",control.status.label);assert.is_false(ui.hasDraft(build,"uniqueQuality",project.id))
		control.apply:Click();control.keep:Click();assert.is_false(ui.hasDraft(build,"uniqueQuality",project.id))
		assert.equal(13,select(2,quality.inspect(store.projects[1].targetItem)).quality)
		assert.equal(shield,store.projects[1].startingItem)
		local xml=build:SaveDB("Unique quality");loadBuildFromXML(xml,"Unique quality")
		local saved=build.savers.CraftingProjects.projects[1]
		assert.equal(13,select(2,quality.inspect(saved.targetItem)).quality)
		main.popups={};control=require("Classes.CraftingUniqueQualityControl").Open(build,saved)
		local inspect=quality.inspect;local inspections=0
		quality.inspect=function(...) inspections=inspections+1;return inspect(...) end
		local first=control.loadTarget:IsEnabled();local second=control.loadTarget:IsEnabled();quality.inspect=inspect
		assert.is_true(first);assert.is_true(second);assert.equal(1,inspections)
		control.loadTarget:Click();assert.matches("13%%",control.status.label)
		control.undo:Click();assert.matches("12%%",control.status.label);control.loadTarget:Click();control.apply:Click();control.keep:Click()
		assert.equal(14,select(2,quality.inspect(build.savers.CraftingProjects.projects[1].targetItem)).quality)
		local other=copyTable(saved);other.targetItem=weapon
		control=require("Classes.CraftingUniqueQualityControl").Open(build,other);assert.is_false(control.loadTarget:IsEnabled())
		main.popups={}
	end)
	it("retains session previews and undo history when returning to projects",function()
		local project={id="session-quality",title="Session",slot="Weapon 2",startingItem=shield,goals={},steps={}}
		local store=build.savers.CraftingProjects;store:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		control.apply:Click();control.apply:Click();control.close:Click()
		control=require("Classes.CraftingUniqueQualityControl").Open(build,store.projects[1])
		assert.matches("14%%",control.status.label);control.undo:Click();assert.matches("13%%",control.status.label)
		control.close:Click();store:Remove(project.id);assert.is_nil(build.planningUniqueQualityDrafts[project.id]);assert.is_false(require("Modules.PlanningUI").hasDraft(build,"uniqueQuality",project.id))
		store:UndoRemove();assert.is_true(require("Modules.PlanningUI").hasDraft(build,"uniqueQuality",project.id));control=require("Classes.CraftingUniqueQualityControl").Open(build,store.projects[1]);assert.matches("13%%",control.status.label)
		control.undo:Click();assert.matches("12%%",control.status.label)
		main.popups={};newBuild();assert.is_nil(build.planningUniqueQualityDrafts)
	end)
	it("copies session previews only to compatible reviewed builds",function()
		local project={id="copy-quality",title="Original",slot="Weapon 2",startingItem=shield,goals={},steps={}}
		build.savers.CraftingProjects:Upsert(project)
		local workspace=require("Modules.PlanningWorkspace").new(build);build.planningWorkspace=workspace
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		control.apply:Click();control.close:Click()
		local changed=copyTable(project);changed.title="Edited guide"
		local candidate={savers={CraftingProjects={projects={changed}}}}
		workspace:CopyCraftingDrafts(candidate)
		local saved=candidate.planningUniqueQualityDrafts[project.id]
		assert.equal("Edited guide",saved.project.title);assert.equal(13,select(2,quality.inspect(saved.itemText)).quality)
		assert.is_true(require("Modules.PlanningUI").hasDraft(candidate,"uniqueQuality",project.id))
		changed.startingItem=shield:gsub("Quality: 12","Quality: 11")
		workspace:CopyCraftingDrafts(candidate);assert.is_nil(candidate.planningUniqueQualityDrafts[project.id])
		main.popups={}
	end)
	it("uses a whetstone for weapons and refuses unavailable cases",function()
		assert.equal("Blacksmith's Whetstone",quality.apply(weapon).resource)
		assert.has_error(function() quality.apply(shield:gsub("Quality: 12","Quality: 20")) end)
		assert.has_error(function() quality.apply(shield.."\nCorrupted") end)
		assert.has_error(function() quality.apply(shield.."\nMirrored") end)
		assert.has_error(function() quality.apply("Rarity: NORMAL\nIron Hat\nItem Level: 86") end)
		assert.has_error(function() quality.apply("Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nUnidentified") end)
	end)
end)
