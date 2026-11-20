describe("Crafting data loading",function()
	it("loads the reviewed 3.30 crafting export and reconstructed modifiers",function()
		local data=require("Modules.CraftingAdvanced").data()
		assert.equal("3.30.0.3",data.patch);assert.equal("3.30.0.3",data.modifierPatch)
		assert.equal("3.30.0.3",data.benchPatch);assert.equal(782,#data.bench)
		assert.is_truthy(data.benchMods.StrMasterItemGenerationCannotChangeOnePrefixes)
		assert.equal("59cb134eeb57a3202837296a409cbb9d8f42be4b",data.source.commit)
		assert.is_truthy(isValueInTable(data.mods.JunMasterVeiledJewelLifeOnBlock.implicit_tags,"unveiled_mod"))
		assert.is_truthy(isValueInTable(data.mods.JunMasterVeiledAbyssSharedCDR.implicit_tags,"unveiled_mod"))
		assert.equal("jewel",data.mods.AccuracyAndCritsJewel.domain)
		assert.equal("jewel",data.mods.AddedChaosDamageJewelCorrupted.domain)
		local support=data.mods.V2SupportedByLifeGainOnHitCorrupted.stats[1]
		assert.equal(15,support.min);assert.equal(15,support.max)
		local speed=data.mods.AfflictionJewelSmallPassivesGrantAttackSpeed.groups
		assert.is_truthy(isValueInTable(speed,"AfflictionJewelAttackOrCastSpeed"))
		local weights=data.mods.AbyssAccuracyRatingJewel3.spawn_weights
		local found=false;for _,entry in ipairs(weights) do if entry.tag=="abyss_jewel_special" and entry.weight==750 then found=true end end
		assert.is_true(found)
		local unveiled=data.mods.JunMasterVeiledJewelElusiveEffect
		assert.is_truthy(unveiled);assert.equal("VeiledJewelElusiveEffect",unveiled.groups[1])
		local excluded=data.mods.JunMasterVeiledAddedColdAndLightningDamage.spawn_weights
		assert.equal("abyss_jewel",excluded[1].tag);assert.equal(0,excluded[1].weight)
		assert.equal("jewel",excluded[2].tag);assert.equal(0,excluded[2].weight)
	end)
	it("matches the synchronous catalogue after a staged load",function()
		local staged=dofile("Modules/CraftingAdvanced.lua");local yields=0
		local job=coroutine.create(function() staged.prepare(function() yields=yields+1;coroutine.yield() end) end)
		repeat local ok,err=coroutine.resume(job);assert.is_true(ok,err) until coroutine.status(job)=="dead"
		assert.is_true(yields>0)
		assert.same(require("Modules.CraftingAdvanced").data(),staged.data())
	end)
end)
