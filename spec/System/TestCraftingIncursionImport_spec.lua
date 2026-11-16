describe("Drop-only Incursion modifier import",function()
	local sim=require("Modules.CraftingSimulator")
	local function item(base,level,lines)
		return "Rarity: RARE\nDread Crest\n"..base.."\nItem Level: "..level.."\n"..lines
	end
	it("recovers a unique hybrid modifier without adding it to the rollable pool",function()
		local raw=item("Iron Hat",86,"+47% to Fire Resistance\n4% of Physical Damage from Hits taken as Fire Damage")
		local model=sim.model(raw);assert.equal(1,#model.initial.affixes)
		assert.equal("FireResistEnhancedLevel50ModPhys",model.initial.affixes[1].id)
		for _,entry in ipairs(model.mods) do assert.not_equal("FireResistEnhancedLevel50ModPhys",entry.id) end
		assert.matches("unsupported conversion family",sim.resistanceReason(model,model.initial,"fire","cold"))
		local rebuilt=sim.toItem(model,model.initial);assert.is_truthy(rebuilt.raw:find("4%% of Physical Damage from Hits taken as Fire Damage"))
		local starting=copyTable(model.initial);starting.origin=nil
		local blank=item("Iron Hat",86,""):gsub("Rarity: RARE","Rarity: NORMAL")
		local restored=sim.perform(blank,{method="divine"},1,starting).state
		assert.equal(model.initial.affixes[1].id,restored.affixes[1].id)
		local wrong=item("Gold Ring",86,""):gsub("Rarity: RARE","Rarity: NORMAL")
		assert.has_error(function() sim.perform(wrong,{method="divine"},1,starting) end)
	end)
	it("rejects modifiers outside their native category or minimum level",function()
		local lines="+47% to Fire Resistance\n4% of Physical Damage from Hits taken as Fire Damage"
		assert.has_error(function() sim.model(item("Gold Ring",86,lines)) end)
		assert.has_error(function() sim.model(item("Iron Hat",40,lines)) end)
	end)
end)
