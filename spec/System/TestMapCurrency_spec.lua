describe("Experimental map currency",function()
	local currency=require("Modules.MapCurrency")
	local function state(rarity,selected) return {baseId="Metadata/Items/Maps/MapWorldsStrand",tier=16,itemLevel=83,rarity=rarity,selected=selected or {}} end
	it("rolls deterministic rare modifiers without changing the input",function()
		local initial=state("normal");local first=currency.perform(initial,"alchemy",123)
		local second=currency.perform(initial,"alchemy",123)
		assert.same(first.state,second.state);assert.equal("rare",first.state.rarity)
		assert.is_true(#first.state.selected>=4 and #first.state.selected<=6);assert.same({},initial.selected)
		assert.matches("estimates",first.note);assert.matches("independent uniform",first.note);assert.equal(#first.state.selected,#first.state.rolls)
	end)
	it("enforces magic limits and currency preconditions",function()
		local magic=currency.perform(state("normal"),"transmute",9).state
		assert.equal("magic",magic.rarity);assert.is_true(#magic.selected>=1 and #magic.selected<=2)
		local rare=currency.perform(magic,"regal",11).state
		assert.equal("rare",rare.rarity);assert.equal(#magic.selected+1,#rare.selected)
		local cleared=currency.perform(rare,"scour",12).state
		assert.equal("normal",cleared.rarity);assert.same({},cleared.selected)
		assert.has_error(function() currency.perform(cleared,"chaos",1) end)
		assert.has_error(function() currency.perform(state("magic",{"MapContainsMirageWorlds"}),"regal",1) end)
		assert.has_error(function() currency.perform(state("normal"),"alchemy",0) end)
	end)
	it("adds and removes only one modifier when eligible",function()
		local rare=currency.perform(state("normal"),"alchemy",123).state
		local removed=currency.perform(rare,"annul",17).state
		assert.equal(#rare.selected-1,#removed.selected)
		local added=currency.perform(removed,"exalt",19).state
		assert.equal(#rare.selected,#added.selected)
		for _,old in ipairs(removed.rolls) do local found=false;for _,new in ipairs(added.rolls) do if new.id==old.id then assert.same(old.values,new.values);found=true end end;assert.is_true(found) end
		local invalid=copyTable(rare);invalid.rolls[1].values[1]=1000000000
		assert.has_error(function() currency.perform(invalid,"annul",1) end);assert.equal(1000000000,invalid.rolls[1].values[1])
	end)
	it("rerolls and augments magic and rare maps under their own limits",function()
		local magic=currency.perform(state("normal"),"transmute",1).state
		assert.equal(1,#magic.selected)
		local augmented=currency.perform(magic,"augmentation",2).state;assert.equal(2,#augmented.selected)
		assert.has_error(function() currency.perform(augmented,"augmentation",2) end)
		local rerolled=currency.perform(augmented,"alteration",3).state
		assert.equal("magic",rerolled.rarity);assert.is_true(#rerolled.selected>=1 and #rerolled.selected<=2)
		local rare=currency.perform(state("normal"),"alchemy",123).state
		local chaos=currency.perform(rare,"chaos",99).state;assert.equal("rare",chaos.rarity)
		assert.is_true(#chaos.selected>=4 and #chaos.selected<=6)
	end)
end)
