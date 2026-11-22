describe("Crafting import ambiguity",function()
	local sim=require("Modules.CraftingSimulator")
	before_each(function() newBuild() end)
	it("explains when an ordinary and an Essence modifier fit the same item",function()
		local raw="Rarity: RARE\nExample Item\nIron Hat\nItem Level: 86\nImplicits: 0\n+55 to Strength\n+107 to maximum Life"
		local ok,reason=pcall(sim.model,raw)
		assert.is_false(ok)
		assert.matches("several modifier identities",reason,1,true)
		assert.matches("ordinary modifier and an Essence modifier",reason,1,true)
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
