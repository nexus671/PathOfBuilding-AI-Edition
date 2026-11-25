describe("Blessed Orb on unique base implicits",function()
	local blessed=require("Modules.CraftingUniqueBlessed");local sim=require("Modules.CraftingSimulator");local quality=require("Modules.CraftingUniqueQuality")
	local raw="Rarity: UNIQUE\nAndvarius\nGold Ring\nItem Level: 86\nImplicits: 1\n+12% to Item Rarity\n+100 to Dexterity"
	before_each(function() newBuild() end)
	it("rerolls a recognized implicit while preserving the unique and its other text",function()
		local option=assert(blessed.options(raw));assert.equal(6,option.min);assert.equal(15,option.max);assert.equal(12,option.current)
		local result=sim.perform(raw,{method="blessed"},123);assert.equal(1,result.components.blessed);assert.equal(result.itemText,sim.perform(raw,{method="blessed"},123).itemText)
		assert.matches("%+100 to Dexterity",result.itemText);local current=assert(blessed.options(result.itemText));assert.is_true(current.current>=6 and current.current<=15)
		local warning;for _,entry in ipairs(result.warnings) do if entry.code=="unique_blessed_estimate" then warning=entry end end;assert.is_not_nil(warning)
		local copied="Item Class: Rings\nRarity: Unique\nAndvarius\nGold Ring\n--------\nItem Level: 86\n--------\n+12% to Item Rarity (implicit)\n--------\n+100 to Dexterity"
		assert.matches("%(implicit%)",blessed.roll(copied,123).itemText)
	end)
	it("rejects unknown or unsafe implicits and invalid targets",function()
		for _,bad in ipairs({raw.."\nCorrupted",raw.."\nSynthesised Item",raw:gsub("%+12%% to Item Rarity","+99%% to Item Rarity"),raw.."\n+12% to Item Rarity"}) do assert.is_not_nil(blessed.reason(bad)) end
		assert.has_error(function() quality.matches(raw,{uniqueImplicit={minValue=16}}) end)
		assert.has_error(function() sim.validateRecipe({rarity="UNIQUE",steps={{method="blessed"}},targets={},requirements={uniqueImplicit={minValue=10,maxValue=14}}}) end)
	end)
	it("simulates bounded target recipes and retains only matching successes",function()
		local goal={uniqueImplicit={minValue=15}};local recipe={rarity="UNIQUE",steps={{method="blessed",maxAttempts=10,untilRequirements=goal}},targets={},requirements=goal}
		local result=sim.simulate(raw,recipe,{trials=10,maxActions=10,seed=42,retainSuccesses=10});assert.is_true(result.sampled);assert.is_true(result.successes>0)
		for _,success in ipairs(result.retainedSuccesses) do assert.is_true(quality.matches(success.itemText,goal)) end
	end)
end)
