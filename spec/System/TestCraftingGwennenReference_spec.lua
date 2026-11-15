describe("Gwennen outcome reference",function()
	local sim=require("Modules.CraftingSimulator")
	local raw="Rarity: RARE\nExample\nIron Hat\nItem Level: 86"
	it("searches the pinned reference without claiming availability or probabilities",function()
		local all=sim.catalog(raw,"",100).gwennenReference
		assert.equal(45,all.total);assert.equal(45,#all.offers);assert.equal(64,#all.sourceSha256)
		assert.matches("not available crafting actions",all.note)
		for _,row in ipairs(all.offers) do assert.is_nil(row.chance);assert.is_nil(row.action) end
		local destroyed=sim.catalog(raw,"destroy",10).gwennenReference
		assert.equal(1,destroyed.total);assert.equal(1022,destroyed.offers[1].id)
		local disputed=sim.catalog(raw,"1030",10).gwennenReference.offers[1]
		assert.matches("100 rerolls",disputed.note);assert.equal("50",disputed.arguments)
		local limited=sim.catalog(raw,"",2).gwennenReference
		assert.equal(45,limited.total);assert.equal(2,#limited.offers)
		assert.equal(0,#sim.catalog(raw,"",-1).gwennenReference.offers)
		assert.is_false(pcall(sim.perform,raw,{method="gwennen"},1))
	end)
end)
