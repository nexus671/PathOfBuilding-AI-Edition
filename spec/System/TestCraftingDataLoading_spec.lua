describe("Crafting data loading",function()
	it("uses the reviewed 3.30 modifier metadata without relabeling older supplemental sources",function()
		local data=require("Modules.CraftingAdvanced").data()
		assert.equal("3.29.3.6",data.patch);assert.equal("3.30.0.2",data.modifierPatch)
		assert.equal("ae6d85a5c36857e08819852ab8732239294aba59",data.source.commit)
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
