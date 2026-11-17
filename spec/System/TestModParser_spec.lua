describe("TestModParser", function()
	local function getMasterDistillerCritMultiplier(value, skillTypes, hasDiamondFlask)
		local mods, extra = modLib.parseMod("If Diamond Flask Charges are consumed, +" .. value .. "% to Critical Strike Multiplier")
		assert.is_nil(extra)
		local modDB = new("ModDB"):ModDB()
		modDB:AddList(mods)
		modDB.conditions.HaveDiamondFlask = hasDiamondFlask
		return modDB:Sum("BASE", { skillTypes = skillTypes }, "CritMultiplier")
	end

	it("applies the Master Distiller diamond flask bonus only to eligible skills while the flask is present", function()
		assert.are.equal(100, getMasterDistillerCritMultiplier(100, {}, true))
		assert.are.equal(60, getMasterDistillerCritMultiplier(60, {}, true))
		assert.are.equal(0, getMasterDistillerCritMultiplier(100, {}, false))
		assert.are.equal(0, getMasterDistillerCritMultiplier(100, { [SkillType.Triggered] = true }, true))
		assert.are.equal(0, getMasterDistillerCritMultiplier(100, { [SkillType.Channel] = true }, true))
	end)
	it("applies the shrine buff from Screams of the Desiccated only without flask effects", function()
		local mods, extra = modLib.parseMod("Players have Diamond Shrine Buff while affected by no Flasks")
		assert.is_nil(extra)
		local modDB = new("ModDB"):ModDB(); modDB:AddList(mods)
		assert.is_true(modDB:Flag(nil, "Condition:DiamondShrine"))
		modDB.conditions.UsingFlask = true
		local flag = modDB:Flag(nil, "Condition:DiamondShrine"); assert.is_falsy(flag)
	end)

end)
