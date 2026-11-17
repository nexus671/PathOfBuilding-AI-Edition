describe("Map crafting source data",function()
	local data=require("Modules.MapCraftingData")
	it("retains the pinned source and applies the first matching spawn rule",function()
		assert.equal("3.30.0.2.2",data.source().patch)
		local tags=data.baseTags("Metadata/Items/Maps/MapWorldsBeach")
		assert.is_true(tags.map);assert.is_true(tags.default);assert.is_true(tags.beach)
		assert.has_error(function() data.baseTags("unknown") end)
		local mod=assert(data.source().mods.MapMonsterAreaOfEffectMapWorlds)
		assert.equal(800,data.spawnWeight(mod,{low_tier_map=true,default=true}))
		assert.equal(0,data.spawnWeight(mod,{uber_tier_map=true,low_tier_map=true,default=true}))
	end)
	it("returns eligible records in deterministic order without changing source data",function()
		local tags={low_tier_map=true,map=true,default=true}
		local candidates=data.candidates(tags,68);local found
		for i,entry in ipairs(candidates) do
			if i>1 then assert.is_true(candidates[i-1].id<entry.id) end
			if entry.id=="MapMonsterAreaOfEffectMapWorlds" then found=entry end
		end
		assert.is_truthy(found);assert.equal(800,found.spawnWeight);assert.equal("suffix",found.side)
		found.groups[1]="changed";assert.not_equal("changed",data.source().mods[found.id].groups[1])
		assert.has_error(function() data.candidates({},68) end)
	end)
	it("excludes an existing modifier and its conflicting groups",function()
		local tags={low_tier_map=true,map=true,default=true}
		local selected="MapMonsterColdDamageMapWorlds"
		local source=data.source().mods[selected];assert.is_truthy(source)
		local before=data.candidates(tags,68);local other
		for _,entry in ipairs(before) do
			if entry.id~=selected and entry.groups[1]==source.groups[1] then other=entry.id;break end
		end
		assert.is_truthy(other)
		for _,entry in ipairs(data.candidates(tags,68,{selected})) do
			assert.not_equal(selected,entry.id);assert.not_equal(other,entry.id)
		end
		assert.has_error(function() data.candidates(tags,68,{selected,selected}) end)
	end)
	it("inspects ordinary tier bands and rejects invalid selected groups",function()
		local base="Metadata/Items/Maps/MapWorldsBeach"
		local low=data.inspect(base,5,68,{});local yellow=data.inspect(base,6,73,{})
		local function has(result,id) for _,entry in ipairs(result.candidates) do if entry.id==id then return true end end end
		assert.is_true(has(low,"MapMonsterAreaOfEffectMapWorlds"))
		assert.is_nil(has(yellow,"MapMonsterAreaOfEffectMapWorlds"))
		assert.matches("not outcome probabilities",low.note)
		assert.has_error(function() data.inspect(base,17,83,{}) end)
		local tiered=data.inspect("Metadata/Items/Maps/Map2Tier1_4",11,83,{})
		assert.is_nil(has(tiered,"MapMonsterAreaOfEffectMapWorlds"))
		assert.has_error(function() data.inspect("Metadata/Items/Maps/MapWorldsSanctuary",16,83,{}) end)
		assert.has_error(function() data.inspect(base,5,68,{"MapMonsterColdDamageMapWorlds","MapMonsterFireDamageMapWorlds"}) end)
	end)
	it("pages base and modifier searches without losing records",function()
		local first=data.searchBases("Map",0,2);assert.equal(2,#first.results);assert.equal(2,first.nextOffset)
		local second=data.searchBases("Map",first.nextOffset,2);assert.not_equal(first.results[1].id,second.results[1].id)
		local base="Metadata/Items/Maps/MapWorldsBeach"
		local firstMods=data.inspect(base,5,68,{},"",0,1)
		local secondMods=data.inspect(base,5,68,{},"",firstMods.nextOffset,1)
		assert.equal(1,#firstMods.candidates);assert.equal(1,firstMods.nextOffset)
		assert.not_equal(firstMods.candidates[1].id,secondMods.candidates[1].id)
		assert.has_error(function() data.searchBases("",0,101) end)
	end)
end)
