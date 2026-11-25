describe("Drop-only Delve modifier import",function()
	local sim=require("Modules.CraftingSimulator")
	local function item(base,lines)
		return "Rarity: RARE\nDread Grasp\n"..base.."\nItem Level: 86\n"..lines
	end
	it("recovers an unambiguous drop-only modifier without adding it to normal rolls",function()
		local raw=item("Iron Gauntlets","40% increased Damage with Bleeding\nAttacks have 25% chance to cause Bleeding")
		local model=sim.model(raw);assert.equal(1,#model.initial.affixes)
		assert.equal("BleedingDamageChanceDelve__",model.initial.affixes[1].id)
		for _,entry in ipairs(model.mods) do assert.not_equal("BleedingDamageChanceDelve__",entry.id) end
		local changed=sim.perform(raw,{method="divine"},1).state;assert.equal(model.initial.affixes[1].id,changed.affixes[1].id)
		local blank=item("Iron Gauntlets",""):gsub("Rarity: RARE","Rarity: NORMAL")
		local starting=copyTable(model.initial);starting.origin=nil
		local restored=sim.perform(blank,{method="divine"},1,starting).state
		assert.equal(model.initial.affixes[1].id,restored.affixes[1].id)
	end)
	it("rejects the modifier on an incompatible category",function()
		assert.has_error(function() sim.model(item("Gold Ring","40% increased Damage with Bleeding\nAttacks have 25% chance to cause Bleeding")) end)
	end)
end)
