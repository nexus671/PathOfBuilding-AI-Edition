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
