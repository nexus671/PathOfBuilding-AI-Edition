describe("Animate Guardian gear auras", function()
	before_each(function()
		newBuild()
	end)

	local function guardianWithItem(raw, supports)
		build.skillsTab:PasteSocketGroup("Fireball 20/0  1")
		build.skillsTab:PasteSocketGroup("Animate Guardian 20/0  1" .. (supports or ""))
		local group = build.skillsTab.socketGroupList[2]
		group.gemList[1].skillMinionItemSet = 2
		group.gemList[1].skillMinionItemSetCalcs = 2
		build.itemsTab:NewItemSet(2)
		table.insert(build.itemsTab.itemSetOrderList, 2)
		build.itemsTab:EquipItemInSet(new("Item"):Item(raw), 2)
		runCallback("OnFrame")
		return group
	end

	it("applies a separate Guardian item's ally damage bonus and removes it when disabled", function()
		local group = guardianWithItem("Rarity: UNIQUE\nDying Breath\nIron Staff\nItem Level: 86\nImplicits: 0\nAllies within 7.5 metres gain 18% increased Damage")
		local withAura = build.calcsTab.mainOutput.TotalDPS
		group.enabled = false
		build.buildFlag = true
		runCallback("OnFrame")
		local withoutAura = build.calcsTab.mainOutput.TotalDPS
		assert.is_true(withAura > withoutAura)
		assert.are.near(withoutAura * 1.18, withAura, withoutAura * 0.001)
	end)

	it("combines Guardian Fortification with Companionship's minion life sharing", function()
		local group = guardianWithItem("Rarity: UNIQUE\nKingmaker\nDespot Axe\nItem Level: 86\nImplicits: 0\nAllies within 3 metres have +10 Fortification", "\nCompanionship 3/0  1")
		local output = build.calcsTab.mainOutput
		assert.are.equals(10, output.FortificationStacks)
		assert.are.equals(15, output.MinionAllyDamageMitigation)
		assert.is_true(output.TotalMinionLife > 0)
		group.enabled = false
		build.buildFlag = true
		runCallback("OnFrame")
		assert.are.equals(0, build.calcsTab.mainOutput.FortificationStacks or 0)
	end)
end)
