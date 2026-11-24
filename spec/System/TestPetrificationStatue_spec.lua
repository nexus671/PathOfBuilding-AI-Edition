describe("Petrification Statue", function()
	before_each(function() newBuild() end)

	it("grants the level-one skill from both supported items", function()
		local cases = {
			{ "Helmet", "Rarity: UNIQUE\nGorgon's Gaze\nRegicide Mask\nGrants Level 1 Petrification Statue" },
			{ "Wickerman Head", "Rarity: UNIQUE\nGreater Chimeral Eye\nChimeral Eye\nImplicits: 1\nGrants Level 20 Petrification Statue" },
		}
		for _, case in ipairs(cases) do
			local item = new("Item"):Item(case[2])
			item:BuildModList()
			assert.equal(1, #item.grantedSkills)
			assert.equal("SummonPetrificationStatue", item.grantedSkills[1].skillId)
			assert.equal(1, item.grantedSkills[1].level)
			build.itemsTab:AddItem(item)
			build.itemsTab.slots[case[1]].selItemId = item.id
			build.buildFlag = true
			runCallback("OnFrame")
			build.calcsTab:BuildOutput()
			local found
			for _, active in ipairs(build.calcsTab.mainEnv.player.activeSkillList) do
				if active.activeEffect.grantedEffect.id == "SummonPetrificationStatue" then
					found = active.activeEffect.level
					assert.equal(4, active.skillData.duration)
					assert.equal(30, active.skillData.cooldown)
				end
			end
			assert.equal(1, found)
			runCallback("OnFrame")
			local warning = table.concat(build.controls.warnings.lines, "\n")
			assert.matches("Petrification Statue's enemy slow and petrification are not included", warning)
			build.itemsTab.slots[case[1]].selItemId = 0
			build.buildFlag = true
			runCallback("OnFrame")
			assert.is_nil(table.concat(build.controls.warnings.lines, "\n"):find("Petrification Statue", 1, true))
		end
	end)

	it("uses the exported base duration and cooldown without assuming enemy coverage", function()
		local statue = data.skills.SummonPetrificationStatue
		assert.equal(30, statue.levels[1].cooldown)
		assert.equal(4000, statue.constantStats[1][2])
		assert.matches("not automatically applied", statue.description)
		build.calcsTab:BuildOutput()
		local enemy = build.calcsTab.mainEnv.enemy.modDB
		local before = { enemy:Sum("BASE", nil, "ActionSpeed"), enemy:Sum("INC", nil, "ActionSpeed"), enemy:More(nil, "ActionSpeed") }
		local item = new("Item"):Item("Rarity: UNIQUE\nGreater Chimeral Eye\nChimeral Eye\nImplicits: 1\nGrants Level 20 Petrification Statue")
		build.itemsTab:AddItem(item)
		build.itemsTab.slots["Wickerman Head"].selItemId = item.id
		build.buildFlag = true
		runCallback("OnFrame")
		build.calcsTab:BuildOutput()
		enemy = build.calcsTab.mainEnv.enemy.modDB
		assert.same(before, { enemy:Sum("BASE", nil, "ActionSpeed"), enemy:Sum("INC", nil, "ActionSpeed"), enemy:More(nil, "ActionSpeed") })
	end)
end)
