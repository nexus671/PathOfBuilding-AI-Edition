describe("The Apostate life mastery", function()
	it("only grants the no-life-modifier bonus to eligible armour", function()
		newBuild()
		local mastery = "15% increased maximum Life if there are no Life Modifiers on Equipped Body Armour"
		local function lifeWithAndWithoutMastery(raw)
			local item = new("Item"):Item(raw)
			build.itemsTab:AddItem(item); build.itemsTab.slots["Body Armour"].selItemId = item.id
			local values = {}
			for _, mods in ipairs({ "", mastery }) do
				build.configTab.input.customMods = mods; build.configTab:BuildModList(); build.buildFlag = true; runCallback("OnFrame")
				values[#values + 1] = build.calcsTab.mainOutput.Life
			end
			return values[1], values[2]
		end
		local normal = "Item Class: Body Armours\nRarity: NORMAL\nSavant's Robe\nItem Level: 86\nImplicits: 0"
		local apostate = "Item Class: Body Armours\nRarity: UNIQUE\nThe Apostate\nSavant's Robe\nItem Level: 86\nImplicits: 0\nGain Maximum Life instead of Maximum Energy Shield from Equipped Armour Items"
		local normalBase, normalMastery = lifeWithAndWithoutMastery(normal)
		local uniqueBase, uniqueMastery = lifeWithAndWithoutMastery(apostate)
		assert.is_true(normalMastery > normalBase)
		assert.equal(uniqueBase, uniqueMastery)
	end)
end)
