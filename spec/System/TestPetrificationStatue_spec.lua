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

	it("calculates the selected skill's duration and cooldown with modifiers", function()
		local item = new("Item"):Item("Rarity: UNIQUE\nGreater Chimeral Eye\nChimeral Eye\nImplicits: 1\nGrants Level 20 Petrification Statue")
		build.itemsTab:AddItem(item)
		build.itemsTab.slots["Wickerman Head"].selItemId = item.id
		build.buildFlag = true; runCallback("OnFrame"); build.calcsTab:BuildOutput()
		local groupIndex
		for index, group in ipairs(build.skillsTab.socketGroupList) do
			if group.gemList[1] and group.gemList[1].skillId == "SummonPetrificationStatue" then groupIndex = index end
		end
		assert.is_truthy(groupIndex)
		build.mainSocketGroup = groupIndex
		build.buildFlag = true; runCallback("OnFrame"); build.calcsTab:BuildOutput()
		local output = build.calcsTab.mainOutput
		assert.is_true(output.Duration >= 4 and output.Duration < 4.04)
		assert.is_true(output.Cooldown >= 30 and output.Cooldown < 30.04)
		build.configTab.input.customMods = "50% increased Skill Effect Duration\n50% increased Cooldown Recovery Rate"
		build.configTab:BuildModList(); build.buildFlag = true; runCallback("OnFrame"); build.calcsTab:BuildOutput()
		output = build.calcsTab.mainOutput
		assert.is_true(output.Duration >= 6 and output.Duration < 6.04)
		assert.is_true(output.Cooldown >= 20 and output.Cooldown < 20.04)
	end)

	it("restores the granted skill and warning after reopening a build", function()
		local item = new("Item"):Item("Rarity: UNIQUE\nGreater Chimeral Eye\nChimeral Eye\nImplicits: 1\nGrants Level 20 Petrification Statue")
		build.itemsTab:AddItem(item)
		build.itemsTab.slots["Wickerman Head"].selItemId = item.id
		build.buildFlag = true; runCallback("OnFrame"); build.calcsTab:BuildOutput()
		local xml = build:SaveDB("Statue roundtrip")
		loadBuildFromXML(xml, "Statue roundtrip")
		build.calcsTab:BuildOutput()
		local count = 0
		for _, active in ipairs(build.calcsTab.mainEnv.player.activeSkillList) do
			if active.activeEffect.grantedEffect.id == "SummonPetrificationStatue" then
				count = count + 1
				assert.equal(1, active.activeEffect.level)
			end
		end
		assert.equal(1, count)
		assert.matches("Petrification Statue's enemy slow and petrification are not included", table.concat(build.controls.warnings.lines, "\n"))
	end)
end)
