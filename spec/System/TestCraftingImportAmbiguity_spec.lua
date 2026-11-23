describe("Crafting import ambiguity",function()
	local sim=require("Modules.CraftingSimulator")
	before_each(function() newBuild() end)
	it("explains when an ordinary and an Essence modifier fit the same item",function()
		local raw="Rarity: RARE\nExample Item\nIron Hat\nItem Level: 86\nImplicits: 0\n+55 to Strength\n+107 to maximum Life"
		local ok,reason=pcall(sim.model,raw)
		assert.is_false(ok)
		assert.matches("several modifier identities",reason,1,true)
		assert.matches("ordinary modifier and an Essence modifier",reason,1,true)
		assert.matches("Ctrl+Alt+C",reason,1,true)
	end)
	it("shows the recovery shortcut without changing the saved item",function()
		local raw="Rarity: RARE\nExample Item\nIron Hat\nItem Level: 86\nImplicits: 0\n+55 to Strength\n+107 to maximum Life"
		local project={id="ambiguous",title="Ambiguous",slot="Helmet",startingItem=raw,goals={},steps={}}
		build.savers.CraftingProjects:Upsert(project);main.popups={}
		local controls=require("Classes.CraftingProjectControl").Open(build,nil,nil,nil,project.id)
		controls.native:Click();local popup=assert(main.popups[1]);local parts={}
		for _,control in pairs(popup.controls) do
			if control.list then for _,row in ipairs(control.list) do parts[#parts+1]=StripEscapes(row[1] or "") end
			elseif type(control.label)=="string" then parts[#parts+1]=StripEscapes(control.label) end
		end
		assert.matches("Ctrl+Alt+C",table.concat(parts," "),1,true)
		assert.equal(raw,build.savers.CraftingProjects.projects[1].startingItem);main.popups={}
	end)
	it("returns to the starting item and opens the workbench after an advanced copy is kept",function()
		local ui=require("Modules.HeadlessUI").install({width=960,height=640});ui:bind(build)
		local ok,err=pcall(function()
			local raw="Rarity: RARE\nExample Item\nIron Hat\nItem Level: 86\nImplicits: 0\n+55 to Strength\n+107 to maximum Life"
			local advanced='Rarity: RARE\nExample Item\nIron Hat\nItem Level: 86\nImplicits: 0\n{ Prefix Modifier "Virile" (Tier: 5) }\n+107(100-114) to maximum Life\n{ Suffix Modifier "of the Gods" (Tier: 2) }\n+55(51-55) to Strength'
			local project={id="ambiguous",title="Ambiguous",slot="Helmet",startingItem=raw,goals={},steps={}}
			build.savers.CraftingProjects:Upsert(project);main.popups={}
			build.planningWorkspace=require("Modules.PlanningWorkspace").new(build);build.viewMode="PLANNER";build.planningWorkspace:Show("crafting")
			build.planningWorkspace.body.controls.native:Click();assert.is_truthy(main.popups[1].controls.edit)
			main.popups[1].controls.edit:Click();local wizard=main.popups[1].controls
			assert.equal(raw,wizard.starting.buf);wizard.close:Click();assert.equal(raw,build.savers.CraftingProjects.projects[1].startingItem)
			build.planningWorkspace.body.controls.native:Click();main.popups[1].controls.edit:Click();wizard=main.popups[1].controls
			wizard.starting:SetText(advanced);wizard.starting.changeFunc();wizard.wizardPage:SetSel(4);wizard.save:Click()
			assert.equal(advanced,build.savers.CraftingProjects.projects[1].startingItem)
			build.planningWorkspace.body.controls.native:Click()
			assert.equal("workbench",build.planningWorkspace.cache.crafting.layout.snapshot().kind)
		end)
		ui:restore();main.popups={};assert.is_true(ok,err)
	end)
	it("preserves the originating planner when a linked craft needs import recovery",function()
		local ui=require("Modules.HeadlessUI").install({width=960,height=640});ui:bind(build)
		local ok,err=pcall(function()
			local raw="Rarity: RARE\nExample Item\nIron Hat\nItem Level: 86\nImplicits: 0\n+55 to Strength\n+107 to maximum Life"
			local project={id="ambiguous",title="Ambiguous",slot="Helmet",startingItem=raw,goals={},steps={}}
			build.savers.CraftingProjects:Upsert(project);main.popups={}
			local ws=require("Modules.PlanningWorkspace").new(build);build.planningWorkspace=ws;build.viewMode="PLANNER"
			ws:Show("crafting");local oldCrafting=ws.cache.crafting
			for _,page in ipairs({"journey","filters"}) do
				ws:Show(page);local body=ws.body;local layout=ws.cache[page].layout
				assert.is_true(require("Modules.LootFilterDependencies").open(build,layout,"craft:ambiguous"))
				assert.equal(page,ws.page);assert.equal(body,ws.body);assert.equal(oldCrafting,ws.cache.crafting)
				assert.is_truthy(main.popups[1].controls.edit);main.popups[1].controls.edit:Click()
				assert.equal(raw,main.popups[1].controls.starting.buf);main.popups[1].controls.close:Click()
				assert.equal(page,ws.page);assert.equal(body,ws.body);assert.equal(raw,build.savers.CraftingProjects.projects[1].startingItem)
			end
		end)
		ui:restore();main.popups={};assert.is_true(ok,err)
	end)
	it("returns to the edited project after recovering a linked craft",function()
		local ui=require("Modules.HeadlessUI").install({width=960,height=640});ui:bind(build)
		local ok,err=pcall(function()
			local raw="Rarity: RARE\nExample Item\nIron Hat\nItem Level: 86\nImplicits: 0\n+55 to Strength\n+107 to maximum Life"
			local advanced='Rarity: RARE\nExample Item\nIron Hat\nItem Level: 86\nImplicits: 0\n{ Prefix Modifier "Virile" (Tier: 5) }\n+107(100-114) to maximum Life\n{ Suffix Modifier "of the Gods" (Tier: 2) }\n+55(51-55) to Strength'
			local first={id="first",title="First",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={}}
			local second={id="second",title="Second",slot="Helmet",startingItem=raw,goals={},steps={}}
			build.savers.CraftingProjects:Upsert(first);build.savers.CraftingProjects:Upsert(second);main.popups={}
			local ws=require("Modules.PlanningWorkspace").new(build);build.planningWorkspace=ws;build.viewMode="PLANNER";ws:Show("filters")
			ws.cache.filters.layout.openWorkbench(second);main.popups[1].controls.edit:Click()
			local wizard=main.popups[1].controls;wizard.starting:SetText(advanced);wizard.starting.changeFunc();wizard.wizardPage:SetSel(4);wizard.save:Click()
			local projects=main.popups[1].controls;local index=projects.projects:GetSelValueByKey("val")
			assert.equal("second",build.savers.CraftingProjects.projects[index].id);assert.equal(advanced,build.savers.CraftingProjects.projects[index].startingItem)
			assert.equal("filters",ws.page);projects.native:Click();assert.equal("Crafting workbench",main.popups[1].title)
		end)
		ui:restore();main.popups={};assert.is_true(ok,err)
	end)
	it("restores navigation for other failures and still opens valid linked crafts",function()
		local ui=require("Modules.HeadlessUI").install({width=960,height=640});ui:bind(build)
		local ok,err=pcall(function()
			local good={id="valid",title="Valid",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={}}
			local bad={id="invalid",title="Invalid",slot="Helmet",startingItem="not an item",goals={},steps={}}
			local ws=require("Modules.PlanningWorkspace").new(build);build.planningWorkspace=ws;build.viewMode="PLANNER";main.popups={};ws:Show("journey")
			local body=ws.body;local success=pcall(ws.cache.journey.layout.openWorkbench,bad)
			assert.is_false(success);assert.equal("journey",ws.page);assert.equal(body,ws.body);assert.equal(0,#main.popups)
			assert.is_true(ws.cache.journey.layout.openWorkbench(good));assert.equal("crafting",ws.page)
			assert.equal("workbench",ws.cache.crafting.layout.snapshot().kind)
		end)
		ui:restore();main.popups={};assert.is_true(ok,err)
	end)
	it("uses advanced modifier names and ranges to resolve the same displayed rolls",function()
		for _,case in ipairs({{"of the Gods","51-55","Strength9"},{"of the Essence","51-58","StrengthEssence7_"}}) do
			local raw='Rarity: RARE\nExample Item\nIron Hat\nItem Level: 86\nImplicits: 0\n{ Prefix Modifier "Virile" (Tier: 5) }\n+107(100-114) to maximum Life\n{ Suffix Modifier "'..case[1]..'" (Tier: 2) }\n+55('..case[2]..') to Strength'
			local model=sim.model(raw);local ids={};for _,entry in ipairs(model.initial.affixes) do ids[entry.id]=true end
			assert.is_true(ids.IncreasedLife7);assert.is_true(ids[case[3]])
			local reopened=sim.model(sim.toItem(model,model.initial).raw);local reopenedIds={}
			for _,entry in ipairs(reopened.initial.affixes) do reopenedIds[entry.id]=true end
			assert.is_true(reopenedIds.IncreasedLife7);assert.is_true(reopenedIds[case[3]])
			local project={id="advanced-import",title="Advanced import",slot="Helmet",startingItem=raw,goals={},steps={}}
			build.savers.CraftingProjects:Upsert(project)
			assert.is_nil(require("Modules.CraftingProjects").workbenchReason(project))
			assert.is_truthy(require("Classes.CraftingSimulatorControl").Open(build,project))
			main.popups={}
		end
	end)
	it("does not claim Essence ambiguity for an unrelated tier conflict",function()
		local raw="Rarity: MAGIC\nSearching Eye Jewel\nItem Level: 86\n15% chance to Avoid Elemental Ailments while you have Elusive"
		local ok,reason=pcall(sim.model,raw)
		assert.is_false(ok)
		assert.matches("several modifier identities",reason,1,true)
		assert.is_nil(reason:find("ordinary modifier and an Essence modifier",1,true))
	end)
end)
