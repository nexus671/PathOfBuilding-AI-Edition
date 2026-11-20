describe("Configuration stat tracking", function()
	before_each(function() newBuild() end)

	it("tracks every stat in a PerStat list as well as single-stat modifiers", function()
		build.configTab.input.customMods = "2% increased Mana Reservation Efficiency of Skills per 250 total Attributes\n1% increased Damage per 10 Strength"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local used = build.calcsTab.mainEnv.perStatsUsed
		for _, stat in ipairs({ "Str", "Dex", "Int" }) do
			local found = false
			for _, mod in ipairs(used[stat] or {}) do
				if mod.name == "ManaReservationEfficiency" then found = true end
			end
			assert.is_true(found, stat .. " must include the total-attributes modifier")
		end
		local foundSingle = false
		for _, mod in ipairs(used.Str or {}) do
			if mod.name == "Damage" then foundSingle = true end
		end
		assert.is_true(foundSingle, "single-stat modifier remains tracked")
	end)
end)
