describe("Blessed Orb on copied base implicits",function()
	local sim=require("Modules.CraftingSimulator")
	it("does not spend a Blessed Orb on fixed or protected implicits",function()
		for _,base in ipairs({"Unset Ring","Composite Ring"}) do
			local model=sim.model("Rarity: NORMAL\n"..base.."\nItem Level: 86")
			local available=require("Modules.CraftingAvailability").check("blessed",model.initial,model)
			assert.is_false(available,base)
			assert.has_error(function() sim.action(model,model.initial,{method="blessed"},function() return 0 end) end)
		end
	end)
	it("rerolls identified synthesised and Eldritch implicits without changing their identities",function()
		local synthRaw="Rarity: NORMAL\nGold Amulet\nItem Level: 86\nImplicits: 2\n{range:0}(8-10)% increased maximum Life\n+20 to Dexterity\nSynthesised Item"
		local model=sim.model(synthRaw);local before=copyTable(model.initial)
		assert.is_true(require("Modules.CraftingAvailability").check("blessed",before,model))
		local changed=sim.action(model,before,{method="blessed"},function() return 0.999999 end)
		assert.same(model.initial,before);assert.equal(model.synthesisGroups[1].candidates[1].id,changed.synthRolls[1].id)
		assert.equal(1,changed.synthRolls[1].range);assert.is_truthy(sim.validateState(model,changed))
		local saved=require("Modules.CraftingCheckpoint").validate(synthRaw,require("Modules.CraftingInventory").run(changed)).state
		assert.same(changed.synthRolls,saved.synthRolls)
		local target={{scope="implicit",anyOf={changed.synthRolls[1].id},minRoll=0.9}}
		local calculation=sim.calculate(synthRaw,{method="blessed"},target,before,{trials=8,seed=7})
		assert.is_true(calculation.sampled);assert.equal("blessed_roll_assumptions",calculation.warnings[1].code)
		local reopened=sim.model(sim.toItem(model,changed).raw);assert.equal(changed.synthRolls[1].id,reopened.synthesisGroups[1].candidates[1].id)
		local catalyst=sim.model("Rarity: NORMAL\nGold Amulet\nItem Level: 86\nCatalyst: Fertile\nCatalystQuality: 20\nImplicits: 1\n{tags:resource,life}{range:0}(8-10)% increased maximum Life\nSynthesised Item")
		local scaled=sim.toItem(catalyst,sim.action(catalyst,catalyst.initial,{method="blessed"},function() return 0.999999 end))
		assert.equal("12% increased maximum Life",StripEscapes(itemLib.formatModLine(scaled.implicitModLines[1],false)))
		local ambiguous=sim.model(synthRaw:gsub("{range:0}%(8%-10%)%% increased maximum Life","8%% increased maximum Life"))
		assert.is_false(require("Modules.CraftingAvailability").check("blessed",ambiguous.initial,ambiguous))
		assert.has_error(function() sim.action(ambiguous,ambiguous.initial,{method="blessed"},function() return 0 end) end)
		local gilded=sim.model(synthRaw:gsub("Implicits: 2","Implicits: 3"):gsub("Synthesised Item","Item sells for much more to vendors\nSynthesised Item"))
		local gildedResult=sim.action(gilded,gilded.initial,{method="blessed"},function() return 0.999999 end)
		assert.equal("unknown",gildedResult.vendorImplicit);assert.is_truthy(sim.toItem(gilded,gildedResult).raw:find("Item sells for much more to vendors",1,true))
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";model=sim.model(raw)
		local state=sim.perform(raw,{method="eldritch_implicit",side="Exarch",tier=2},11).state
		state=sim.perform(raw,{method="eldritch_implicit",side="Eater",tier=1},12,state).state
		state.implicits[1].id="SpellCriticalStrikeChanceEldritchImplicit2";state.implicits[1].range=0
		state.implicits[2].id="EnergyShieldFromGlovesBootsEldritchImplicit1";state.implicits[2].range=0
		before=copyTable(state);assert.is_true(require("Modules.CraftingAvailability").check("blessed",state,model))
		changed=sim.action(model,state,{method="blessed"},function() return 0.999999 end)
		assert.same(before,state);assert.equal(before.implicits[1].id,changed.implicits[1].id);assert.equal(before.implicits[2].id,changed.implicits[2].id)
		assert.equal(1,changed.implicits[1].range);assert.equal(1,changed.implicits[2].range);assert.is_truthy(sim.validateState(model,changed))
		assert.same(changed.implicits,sim.model(sim.toItem(model,changed).raw).initial.implicits)
	end)
	it("rerolls a copied value within its known base range",function()
		local raw="Rarity: NORMAL\nCoral Ring\nItem Level: 86\nImplicits: 1\n+25 to maximum Life"
		local model=sim.model(raw)
		local low=sim.action(model,model.initial,{method="blessed"},function() return 0 end)
		local high=sim.action(model,model.initial,{method="blessed"},function() return 0.999999 end)
		assert.is_truthy(sim.toItem(model,low).raw:find("+20 to maximum Life",1,true))
		local diff=table.concat(require("Modules.CraftingInspection").diff(model,model.initial,low),"\n")
		assert.is_truthy(diff:find("- Implicit: +25 to maximum Life",1,true));assert.is_truthy(diff:find("+ Implicit: +20 to maximum Life",1,true))
		assert.is_truthy(sim.toItem(model,high).raw:find("+30 to maximum Life",1,true))
	end)
	it("retains independent multi-stat rolls and saved state",function()
		local raw="Rarity: NORMAL\nSteel Ring\nItem Level: 86\nImplicits: 1\nAdds 4 to 12 Physical Damage to Attacks"
		local model=sim.model(raw);assert.is_truthy(sim.toItem(model,model.initial).raw:find("Adds 4 to 12 Physical Damage",1,true))
		local calls=0;local state=sim.action(model,model.initial,{method="blessed"},function() calls=calls+1;return calls==1 and 0 or 0.999999 end)
		assert.is_true(state.baseImplicitReconstructed);assert.same({0,1},state.baseImplicitRanges[1])
		assert.is_truthy(sim.toItem(model,state).raw:find("Adds 3 to 14 Physical Damage",1,true))
		local saved=require("Modules.CraftingCheckpoint").validate(raw,require("Modules.CraftingInventory").run(state)).state
		assert.is_truthy(sim.toItem(model,saved).raw:find("Adds 3 to 14 Physical Damage",1,true))
		local legacy=copyTable(state);legacy.baseImplicitReconstructed=nil
		assert.is_truthy(sim.toItem(model,legacy).raw:find("Adds 4 to 12 Physical Damage",1,true))
	end)
	it("recognizes an ordinary implicit in a game-style item copy",function()
		local raw="Item Class: Rings\nRarity: Normal\nCoral Ring\n--------\nItem Level: 86\n--------\n+25 to maximum Life (implicit)"
		local model=sim.model(raw)
		local result=sim.action(model,model.initial,{method="blessed"},function() return 0 end)
		assert.is_true(result.baseImplicitReconstructed)
		assert.is_truthy(sim.toItem(model,result).raw:find("+20 to maximum Life",1,true))
	end)
	it("does not replace an unrecognized implicit with the base template",function()
		local raw="Rarity: NORMAL\nCoral Ring\nItem Level: 86\nImplicits: 1\n+99 to maximum Life"
		local model=sim.model(raw);assert.is_nil(model.baseImplicitTemplates)
		assert.is_false(require("Modules.CraftingAvailability").check("blessed",model.initial,model))
		assert.has_error(function() sim.action(model,model.initial,{method="blessed"},function() return 0 end) end)
		assert.is_truthy(sim.toItem(model,model.initial).raw:find("+99 to maximum Life",1,true))
	end)
	it("accepts catalyst-scaled copies and rerolls the underlying range",function()
		local raw="Rarity: NORMAL\nCoral Ring\nItem Level: 86\nCatalyst: Fertile\nCatalystQuality: 20\nImplicits: 1\n+36 to maximum Life"
		local model=sim.model(raw)
		assert.is_true(require("Modules.CraftingAvailability").check("blessed",model.initial,model))
		local original=sim.toItem(model,model.initial);assert.equal("+36 to maximum Life",StripEscapes(itemLib.formatModLine(original.implicitModLines[1],false)))
		local state=sim.action(model,model.initial,{method="blessed"},function() return 0 end)
		local item=sim.toItem(model,state)
		assert.equal("+24 to maximum Life",StripEscapes(itemLib.formatModLine(item.implicitModLines[1],false)))
		local high=sim.action(model,model.initial,{method="blessed"},function() return 0.999999 end)
		item=sim.toItem(model,high);assert.equal("+36 to maximum Life",StripEscapes(itemLib.formatModLine(item.implicitModLines[1],false)))
		local saved=require("Modules.CraftingCheckpoint").validate(raw,require("Modules.CraftingInventory").run(state)).state
		item=sim.toItem(sim.model(raw),saved);assert.equal("+24 to maximum Life",StripEscapes(itemLib.formatModLine(item.implicitModLines[1],false)))
		for _,invalid in ipairs({(raw:gsub("%+36","+37")),(raw:gsub("Fertile","Prismatic")),(raw:gsub("CatalystQuality: 20","CatalystQuality: 0"))}) do
			local bad=sim.model(invalid);assert.is_false(require("Modules.CraftingAvailability").check("blessed",bad.initial,bad))
		end
		local copied="Item Class: Rings\nRarity: Normal\nCoral Ring\n--------\nQuality (Life and Mana Modifiers): +20% (augmented)\n--------\nItem Level: 86\n--------\n+36 to maximum Life (implicit)"
		local gameModel=sim.model(copied);local gameState=sim.action(gameModel,gameModel.initial,{method="blessed"},function() return 0 end)
		item=sim.toItem(gameModel,gameState);assert.equal("+24 to maximum Life",StripEscapes(itemLib.formatModLine(item.implicitModLines[1],false)))
		local advanced=copied:gsub("%+36 to maximum Life %(implicit%)","{ Implicit Modifier — Life }\n+36(24-36) to maximum Life")
		gameModel=sim.model(advanced);item=sim.toItem(gameModel,gameModel.initial);assert.equal("+36 to maximum Life",StripEscapes(itemLib.formatModLine(item.implicitModLines[1],false)))
		local reopened=sim.model(item.raw);local restored=sim.toItem(reopened,reopened.initial);assert.equal("+36 to maximum Life",StripEscapes(itemLib.formatModLine(restored.implicitModLines[1],false)))
		gameState=sim.action(gameModel,gameModel.initial,{method="blessed"},function() return 0 end)
		item=sim.toItem(gameModel,gameState);assert.equal("+24 to maximum Life",StripEscapes(itemLib.formatModLine(item.implicitModLines[1],false)))
		local middle=advanced:gsub("%+36%(24%-36%)","+31(24-36)")
		gameModel=sim.model(middle);item=sim.toItem(gameModel,gameModel.initial);assert.equal("+31 to maximum Life",StripEscapes(itemLib.formatModLine(item.implicitModLines[1],false)))
		local wrongRange=advanced:gsub("%(24%-36%)","(24-48)")
		gameModel=sim.model(wrongRange);assert.is_false(require("Modules.CraftingAvailability").check("blessed",gameModel.initial,gameModel))
	end)
	it("recognizes independently rolled catalyst-scaled base stats",function()
		local raw="Rarity: NORMAL\nSteel Ring\nItem Level: 86\nCatalyst: Noxious\nCatalystQuality: 20\nImplicits: 1\nAdds 4 to 16 Physical Damage to Attacks"
		local model=sim.model(raw);local calls=0
		local state=sim.action(model,model.initial,{method="blessed"},function() calls=calls+1;return calls==1 and 0 or 0.999999 end)
		local item=sim.toItem(model,state)
		assert.equal("Adds 3 to 16 Physical Damage to Attacks",StripEscapes(itemLib.formatModLine(item.implicitModLines[1],false)))
	end)
	it("updates copied implicit values when catalyst quality changes",function()
		local raw="Rarity: NORMAL\nCoral Ring\nItem Level: 86\nImplicits: 1\n+25 to maximum Life"
		local model=sim.model(raw)
		local state=model.initial; for i=1,20 do if (state.catalystQuality or 0)<20 then state=sim.action(model,state,{method="catalyst",catalyst=4},function() return 0 end) end end
		local item=sim.toItem(model,state)
		assert.equal("+30 to maximum Life",StripEscapes(itemLib.formatModLine(item.implicitModLines[1],false)))
		local changed=sim.action(model,state,{method="catalyst",catalyst=8},function() return 0 end)
		item=sim.toItem(model,changed)
		assert.equal("+25 to maximum Life",StripEscapes(itemLib.formatModLine(item.implicitModLines[1],false)))
	end)

	it("preserves the underlying roll for scaled copies and native save text",function()
		local raw="Rarity: NORMAL\nCoral Ring\nItem Level: 86\nCatalyst: Fertile\nCatalystQuality: 20\nImplicits: 1\n+25 to maximum Life"
		local model=sim.model(raw)
		local item=sim.toItem(model,model.initial)
		assert.equal("+25 to maximum Life",StripEscapes(itemLib.formatModLine(item.implicitModLines[1],false)))
		local reopened=sim.model(item.raw)
		item=sim.toItem(reopened,reopened.initial)
		assert.equal("+25 to maximum Life",StripEscapes(itemLib.formatModLine(item.implicitModLines[1],false)))
		local changed=sim.action(reopened,reopened.initial,{method="catalyst",catalyst=8},function() return 0 end)
		item=sim.toItem(reopened,changed)
		assert.equal("+21 to maximum Life",StripEscapes(itemLib.formatModLine(item.implicitModLines[1],false)))
	end)

end)
