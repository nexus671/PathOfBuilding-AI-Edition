describe("Experimental map currency",function()
	local currency=require("Modules.MapCurrency")
	local function state(rarity,selected) return {baseId="Metadata/Items/Maps/MapWorldsStrand",tier=16,itemLevel=83,rarity=rarity,selected=selected or {}} end
	it("reports the map data version for currency outcomes",function()
		local result=currency.perform(state("normal"),"alchemy",42)
		local source=require("Modules.MapCraftingData").source()
		assert.equal(source.patch,result.dataPatch);assert.same(source.source,result.dataSource)
		local fast=currency.perform(state("normal"),"alchemy",42,nil,true)
		assert.is_nil(fast.dataSource);assert.is_nil(fast.dataPatch)
	end)
	it("keeps Blighted modifier restrictions in currency rolls and cached pools",function()
		local input=state("rare");input.observedEffects={{kind="implicit",text="Area is infested with Fungal Growths"}}
		local forbidden={MapContainsBeyondDemonFactionWorlds=true,MapContainsBeyondFleshFactionWorlds=true,MapContainsBeyondPaleFactionWorlds=true,MapContainsDeliriumMirrorWorlds=true,MapContainsMirageWorlds=true,MapContainsWildwoodWorlds=true,MapContainsSentinelApexWorlds=true,MapContainsSentinelPandemoniumWorlds=true,MapContainsSentinelStalkerWorlds=true}
		local cache={};for seed=1,30 do
			local result=currency.perform(input,"chaos",seed,nil,false,cache)
			assert.same(input.observedEffects,result.state.observedEffects);assert.matches("Blighted rare%-only",result.note);assert.matches("not modeled",result.note)
			for _,id in ipairs(result.state.selected) do assert.is_nil(forbidden[id],id) end
		end
		local ordinary=state("rare")
		for seed=1,5 do assert.same(currency.perform(ordinary,"chaos",seed),currency.perform(ordinary,"chaos",seed,nil,false,cache)) end
		local target=copyTable(input);target.selected={"MapContainsMirageWorlds"}
		local exalted=currency.perform(target,"exalt",42)
		assert.is_truthy(isValueInArray(exalted.state.selected,"MapContainsMirageWorlds"));assert.matches("pre%-hotfix",exalted.note)
		local rerolled=currency.perform(target,"chaos",42).state
		for _,id in ipairs(rerolled.selected) do assert.is_nil(forbidden[id],id) end
		assert.equal("normal",currency.perform(target,"scour",42).state.rarity)
		assert.has_error(function() require("Modules.MapCraftEstimate").run(input,{wanted={"MapContainsMirageWorlds"},trials=1,maxAttempts=1,seed=1}) end)
		local estimate=require("Modules.MapCraftEstimate").run(input,{avoid={"MapContainsMirageWorlds"},trials=1,maxAttempts=1,seed=1})
		assert.matches("Blighted rare%-only",estimate.note);assert.matches("not modeled",estimate.note)
	end)
	it("rolls deterministic rare modifiers without changing the input",function()
		local initial=state("normal");initial.quality={kind="Pack Size",value=20};initial.observedEffects={{kind="enchant",text="Players are Delirious"}};local first=currency.perform(initial,"alchemy",123)
		local second=currency.perform(initial,"alchemy",123)
		assert.same(first.state,second.state);assert.equal("rare",first.state.rarity)
		assert.same(initial.quality,first.state.quality);assert.same(initial.quality,currency.perform(first.state,"scour",1).state.quality)
		assert.same(initial.observedEffects,first.state.observedEffects);assert.matches("not modeled",first.note)
		assert.equal(first.summary.totals.packSize.min+10,first.summary.estimatedTotals.packSize.min)
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
	it("rejects an impossible corruption implicit instead of dropping it",function()
		local input=state("rare");input.implicit={id="MapCorruptionItemRarity",value=15};local before=copyTable(input)
		assert.has_error(function() currency.perform(input,"chaos",1) end)
		assert.has_error(function() currency.options(input) end)
		assert.has_error(function() require("Modules.MapCraftEstimate").run(input,{wanted={},avoid={"MapMonsterAreaOfEffectMapWorlds"},trials=1,maxAttempts=1,seed=1}) end)
		assert.same(before,input)
		input.corrupted=true;assert.has_error(function() currency.perform(input,"chaos",1) end)
	end)
	it("rejects unsupported explicit modifiers rather than silently retaining them",function()
		local input=state("rare");input.observedEffects={{kind="explicit",text="Players in Area are 35% Delirious"}}
		assert.has_error(function() currency.perform(input,"chaos",1) end)
		assert.has_error(function() currency.options(input) end)
	end)
	it("previews only the conditional two-modifier Vaal outcome on ordinary rare maps",function()
		local map=require("Modules.MapCraftingData");local input
		for seed=1,100 do local candidate=currency.perform(state("normal"),"alchemy",seed*104729).state;if #candidate.selected==6 then input=candidate;break end end
		assert.is_not_nil(input);local before=copyTable(input)
		local options={};for _,entry in ipairs(currency.options(input)) do options[entry.id]=entry end;assert.is_true(options.vaal_add.available)
		for seed=1,20 do
			local result=currency.perform(input,"vaal_add",seed);assert.is_true(result.state.corrupted);assert.is_true(result.state.vaalPreview);assert.equal(8,#result.state.selected)
			assert.equal(8,#result.state.rolls);assert.same(input.quality,result.state.quality)
			for i,id in ipairs(input.selected) do assert.equal(id,result.state.selected[i]);assert.same(input.rolls[i],result.state.rolls[i]) end
			assert.matches("Conditional Vaal outcome only",result.note,1,true);assert.matches("not a full Vaal",result.note,1,true)
			assert.has_no.errors(function() map.inspect(result.state.baseId,result.state.tier,result.state.itemLevel,result.state.selected,"",0,50,nil,"rare",result.state.rolls,true) end)
			assert.has_error(function() currency.perform(result.state,"chaos",seed) end)
		end
		assert.same(before,input);assert.has_error(function() currency.perform(state("magic"),"vaal_add",1) end)
		local invalid=copyTable(input);invalid.vaalPreview=true;assert.has_error(function() currency.perform(invalid,"chaos",1) end)
		assert.has_error(function() require("Modules.MapCraftEstimate").run(invalid,{trials=1,maxAttempts=1,seed=1}) end)
		local nightmare={baseId="Metadata/Items/Maps/MapWorldsAbomination",tier=17,itemLevel=84,rarity="rare",selected={}}
		assert.has_error(function() currency.perform(nightmare,"vaal_add",1) end)
	end)
	it("rerolls values even when Chaos selects the same modifier again",function()
		local map=require("Modules.MapCraftingData")
		local inputs={state("rare"),{baseId="Metadata/Items/Maps/MapWorldsAbomination",tier=17,itemLevel=84,rarity="rare",selected={}}}
		for _,input in ipairs(inputs) do
			local expected=currency.perform(input,"chaos",42).state
			local previous=copyTable(expected);local changed=false
			for _,roll in ipairs(previous.rolls) do
				for index,stat in ipairs(map.source().mods[roll.id].stats) do
					if stat.min<stat.max then roll.values[index]=roll.values[index]==stat.min and stat.max or stat.min;changed=true;break end
				end
				if changed then break end
			end
			assert.is_true(changed)
			assert.same(expected,currency.perform(previous,"chaos",42).state)
		end
	end)
	it("keeps cached reroll samples identical to uncached samples",function()
		for _,input in ipairs({state("rare"),{baseId="Metadata/Items/Maps/MapWorldsAbomination",tier=17,itemLevel=84,rarity="rare",selected={}}}) do
			local cache={};for seed=1,12 do
				assert.same(currency.perform(input,"chaos",seed),currency.perform(input,"chaos",seed,nil,false,cache))
			end
		end
	end)
	it("models Nightmare Chaos rerolls with at least one exclusive modifier per side",function()
		local map=require("Modules.MapCraftingData")
		local input={baseId="Metadata/Items/Maps/MapWorldsAbomination",tier=17,itemLevel=84,rarity="rare",selected={}}
		local before=copyTable(input);local choices={};for _,entry in ipairs(currency.options(input)) do choices[entry.id]=entry end
		assert.is_true(choices.chaos.available);assert.is_false(choices.alchemy.available);assert.matches("Only Chaos",choices.scour.reason)
		for seed=1,50 do
			local result=currency.perform(input,"chaos",seed);assert.equal(6,#result.state.selected);assert.equal(6,#result.state.rolls)
			local sides={prefix=0,suffix=0};local exclusive={prefix=0,suffix=0}
			for _,id in ipairs(result.state.selected) do
				local mod=map.source().mods[id];sides[mod.generation_type]=sides[mod.generation_type]+1
				for _,tag in ipairs(mod.adds_tags or {}) do if tag:match("^has_uber_map_") then exclusive[mod.generation_type]=exclusive[mod.generation_type]+1 end end
			end
			assert.same({prefix=3,suffix=3},sides);assert.is_true(exclusive.prefix>=1);assert.is_true(exclusive.suffix>=1);assert.matches("unverified",result.note)
			assert.same(result,currency.perform(input,"chaos",seed))
		end
		assert.same(before,input);assert.has_error(function() currency.perform(input,"scour",1) end)
		local bad=copyTable(input);bad.rarity="magic";assert.has_error(function() currency.perform(bad,"chaos",1) end)
	end)
	it("explains unavailable currency actions without changing the map",function()
		local function options(input)
			local copy=copyTable(input);local result={};for _,entry in ipairs(currency.options(input)) do result[entry.id]=entry end
			assert.same(copy,input);return result
		end
		local normal=options(state("normal"));assert.is_true(normal.alchemy.available);assert.is_false(normal.chaos.available);assert.matches("magic map",normal.alteration.reason)
		assert.is_false(normal.annul.available);assert.matches("modifier",normal.annul.reason)
		local magic=currency.perform(state("normal"),"transmute",1).state
		magic=currency.perform(magic,"augmentation",2).state
		local m=options(magic);assert.is_false(m.augmentation.available);assert.matches("maximum of two",m.augmentation.reason);assert.is_true(m.regal.available)
		local rare;for seed=1,100 do local candidate=currency.perform(state("normal"),"alchemy",seed*104729).state;if #candidate.selected==6 then rare=candidate;break end end
		assert.is_not_nil(rare);local r=options(rare);assert.is_false(r.exalt.available);assert.matches("maximum of six",r.exalt.reason);assert.is_true(r.chaos.available)
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
