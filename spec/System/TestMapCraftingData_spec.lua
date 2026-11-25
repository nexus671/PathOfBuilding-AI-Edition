describe("Map crafting source data",function()
	it("finds eligible matching map modifier identities without guessing values",function()
		local map=require("Modules.MapCraftingData");local base="Metadata/Items/Maps/MapWorldsBeach"
		local result=map.inspect(base,16,83,{},"",0,100,nil,"rare",nil,nil,nil,nil,nil,nil,nil,"MapMonsterFireDamageMapWorlds")
		assert.equal("MapMonsterFireDamageMapWorlds",result.relatedTo);assert.equal(1,result.total);assert.equal("MapMonsterFireDamage3MapWorlds",result.candidates[1].id)
		assert.matches("do not prove identical",result.note,1,true)
		local empty=map.inspect(base,16,83,{},"",0,100,nil,"rare",nil,nil,nil,nil,nil,nil,nil,"MapMonsterFireDamage3MapWorlds");assert.equal(0,empty.total)
		assert.has_error(function() map.inspect(base,16,83,{},"",0,100,nil,"rare",nil,nil,nil,nil,nil,nil,nil,"unknown") end)
	end)
	it("requires a current tier-based map item to match its tier",function()
		local map=require("Modules.MapCraftingData")
		assert.equal("Map (Tier 5)",map.inspect("Metadata/Items/Maps/MapKeyTier5",5,68,{}).baseName)
		assert.has_error(function() map.inspect("Metadata/Items/Maps/MapKeyTier5",16,83,{}) end)
	end)
	it("reports observed effects that are not modeled during inspection",function()
		local data=require("Modules.MapCraftingData")
		local effect={{kind="implicit",text="Area is Influenced by the Originator's Memories"}}
		local result=data.inspect("Metadata/Items/Maps/MapKeyTier5",5,68,{},"",0,1,nil,"rare",nil,nil,nil,nil,effect)
		assert.same(effect,result.observedEffects);assert.matches("not modeled",result.note)
	end)
	local data=require("Modules.MapCraftingData")
	it("keeps lightweight candidate selection equivalent to full inspection",function()
		for _,case in ipairs({
			{base="Metadata/Items/Maps/MapKeyTier5",tier=5,level=68,selected={}},
			{base="Metadata/Items/Maps/MapWorldsAbomination",tier=17,level=84,selected={"MapUberModCurses"}},
			{base="Metadata/Items/Maps/MapKeyNightmareBoss",tier=17,level=84,selected={"MapUberModCurses"}},
		}) do
			local full=data.inspect(case.base,case.tier,case.level,case.selected,"",0,100,nil,"rare")
			local light=data.inspect(case.base,case.tier,case.level,case.selected,"",0,100,nil,"rare",nil,nil,nil,nil,nil,nil,true)
			assert.equal(full.total,light.total);assert.equal(full.nextOffset,light.nextOffset);assert.is_nil(light.summary)
			for i,entry in ipairs(full.candidates) do local other=light.candidates[i]
				assert.equal(entry.id,other.id);assert.equal(entry.side,other.side);assert.equal(entry.spawnWeight,other.spawnWeight);assert.equal(entry.matchedTag,other.matchedTag)
			end
		end
	end)
	it("inspects Nightmare pools and their unlocked candidates",function()
		local base="Metadata/Items/Maps/MapWorldsAbomination"
		for _,name in ipairs({"Abomination","Citadel","Fortress","Sanctuary","Ziggurat"}) do
			local id="Metadata/Items/Maps/MapWorlds"..name;assert.is_true(data.inspect(id,17,84,{},"",0,1,nil,"rare").nightmare)
		end
		local first=data.inspect(base,17,84,{},"MapUberModCurses",0,10,nil,"rare")
		assert.is_true(first.nightmare);assert.equal(1,first.total);assert.matches("experimental",first.note)
		assert.equal(0,data.inspect(base,17,84,{},"MapUberWeakContainsDeliriumMirror",0,10,nil,"rare").total)
		assert.equal(1,data.inspect(base,17,84,{"MapUberModCurses"},"MapUberWeakContainsDeliriumMirror",0,10,nil,"rare").total)
		assert.has_error(function() data.inspect(base,16,84,{}) end)
		assert.has_error(function() data.inspect(base,17,84,{},"",0,10,nil,"magic") end)
	end)
	it("opens reviewed older map drafts without accepting unknown versions",function()
		assert.is_true(data.acceptsDraftVersion("3.30.0.2.2"));assert.is_true(data.acceptsDraftVersion("3.30.0.3"));assert.is_true(data.acceptsDraftVersion("3.30.0.4"));assert.is_false(data.acceptsDraftVersion("3.30.0.5"))
	end)
	it("retains the pinned source and applies the first matching spawn rule",function()
		assert.equal("3.30.0.4",data.source().patch)
		local tags=data.baseTags("Metadata/Items/Maps/MapWorldsBeach")
		assert.is_true(tags.map);assert.is_true(tags.default);assert.is_true(tags.beach)
		assert.has_error(function() data.baseTags("unknown") end)
		local mod=assert(data.source().mods.MapMonsterAreaOfEffectMapWorlds)
		assert.equal(800,data.spawnWeight(mod,{low_tier_map=true,default=true}))
		assert.equal(0,data.spawnWeight(mod,{uber_tier_map=true,low_tier_map=true,default=true}))
		for _,id in ipairs({"MapContainsBeyondDemonFactionWorlds","MapContainsBeyondFleshFactionWorlds","MapContainsBeyondPaleFactionWorlds","MapContainsDeliriumMirrorWorlds","MapContainsMirageWorlds","MapContainsWildwoodWorlds","MapContainsSentinelApexWorlds","MapContainsSentinelPandemoniumWorlds","MapContainsSentinelStalkerWorlds"}) do
			local affected=assert(data.source().mods[id]);local weight,tag=data.spawnWeight(affected,{infected_map=true,default=true})
			assert.equal(0,weight);assert.equal("infected_map",tag)
		end
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
		assert.equal(data.source().patch,first.dataPatch);assert.same(data.source().source,first.dataSource)
		local second=data.searchBases("Map",first.nextOffset,2);assert.not_equal(first.results[1].id,second.results[1].id)
		local base="Metadata/Items/Maps/MapWorldsBeach"
		local firstMods=data.inspect(base,5,68,{},"",0,1)
		local secondMods=data.inspect(base,5,68,{},"",firstMods.nextOffset,1)
		assert.equal(1,#firstMods.candidates);assert.equal(1,firstMods.nextOffset)
		assert.not_equal(firstMods.candidates[1].id,secondMods.candidates[1].id)
		assert.has_error(function() data.searchBases("",0,101) end)
	end)
	it("applies magic-map limits and the 3.30 rare-only suffix restriction",function()
		local base="Metadata/Items/Maps/MapWorldsStrand"
		local ids={"MapContainsBeyondDemonFactionWorlds","MapContainsBeyondFleshFactionWorlds","MapContainsBeyondPaleFactionWorlds","MapContainsDeliriumMirrorWorlds","MapContainsMirageWorlds","MapContainsWildwoodWorlds","MapContainsSentinelApexWorlds","MapContainsSentinelPandemoniumWorlds","MapContainsSentinelStalkerWorlds"}
		for _,id in ipairs(ids) do
			assert.equal(1,data.inspect(base,16,83,{},id,0,30,nil,"rare").total)
			assert.equal(0,data.inspect(base,16,83,{},id,0,30,nil,"magic").total)
			assert.has_error(function() data.inspect(base,16,83,{id},"",0,30,nil,"magic") end)
		end
		local magic=data.inspect(base,16,83,{},"",0,100,nil,"magic");assert.equal("magic",magic.rarity)
		local prefix,suffix
		for _,entry in ipairs(magic.candidates) do if entry.side=="prefix" then prefix=prefix or entry.id else suffix=suffix or entry.id end end
		assert.is_truthy(prefix);assert.is_truthy(suffix)
		assert.equal(0,data.inspect(base,16,83,{prefix,suffix},"",0,30,nil,"magic").total)
		assert.has_error(function() data.inspect(base,16,83,{prefix,suffix},"",0,30,nil,"normal") end)
	end)
	it("excludes current rare-only encounter modifiers from recognized Blighted maps",function()
		local base="Metadata/Items/Maps/MapWorldsStrand"
		local effect={{kind="implicit",text="Area is infested with Fungal Growths"}}
		local note=data.inspect(base,16,83,{},"",0,30,nil,"rare",nil,nil,nil,nil,effect).note
		assert.matches("Blighted rare%-only",note);assert.matches("not modeled",note)
		for _,id in ipairs({"MapContainsBeyondDemonFactionWorlds","MapContainsBeyondFleshFactionWorlds","MapContainsBeyondPaleFactionWorlds","MapContainsDeliriumMirrorWorlds","MapContainsMirageWorlds","MapContainsWildwoodWorlds","MapContainsSentinelApexWorlds","MapContainsSentinelPandemoniumWorlds","MapContainsSentinelStalkerWorlds"}) do
			assert.equal(1,data.inspect(base,16,83,{},id,0,30,nil,"rare").total)
			assert.equal(0,data.inspect(base,16,83,{},id,0,30,nil,"rare",nil,nil,nil,nil,effect).total)
		end
	end)
	it("combines known modifier bonuses without treating ranges as rolled values",function()
		local result=data.summarize({"MapMonsterAreaOfEffectMapWorlds","MapContainsMirageWorlds"})
		assert.same({min=26,max=26},result.totals.atlasDrops);assert.same({min=16,max=16},result.totals.rarity);assert.same({min=10,max=10},result.totals.packSize)
		assert.same({"Monsters have 45% increased Area of Effect"},result.effects[1].lines)
		assert.same({"Area contains a Mirage"},result.effects[2].lines);assert.matches("excludes quality",result.note)
		local ranged=data.summarize({"MapCorruptedSideAreaPackSize"});assert.same({min=30,max=60},ranged.totals.packSize)
		assert.has_error(function() data.summarize({"unknown"}) end)
	end)
	it("adds documented 20 percent quality bonuses while keeping more multipliers separate",function()
		local selected={"MapMonsterAreaOfEffectMapWorlds"}
		local pack=data.summarize(selected,nil,nil,{kind="Pack Size",value=20})
		assert.equal(pack.totals.packSize.min+10,pack.estimatedTotals.packSize.min)
		assert.equal("packSize",pack.qualityEffect.stat)
		local rarity=data.summarize(selected,nil,nil,{kind="Rarity",value=20})
		assert.equal(rarity.totals.rarity.min+25,rarity.estimatedTotals.rarity.min)
		local combined=data.summarize(selected,nil,{id="MapCorruptionItemRarity",value=15},{kind="Rarity",value=20})
		assert.equal(combined.totals.rarity.min+40,combined.estimatedTotals.rarity.min)
		local currency=data.summarize(selected,nil,nil,{kind="Currency",value=20})
		assert.is_nil(currency.estimatedTotals);assert.same({supported=true,stat="currencyMore",value=50,text="50% more Currency"},currency.qualityEffect)
		local cards=data.summarize(selected,nil,nil,{kind="Divination Cards",value=20})
		assert.equal("divinationMore",cards.qualityEffect.stat);assert.equal(50,cards.qualityEffect.value)
		local partial=data.summarize(selected,nil,nil,{kind="Pack Size",value=19})
		assert.is_nil(partial.estimatedTotals);assert.is_false(partial.qualityEffect.supported)
		local threads=data.summarize(selected,nil,nil,{kind="Threads",value=20})
		assert.is_nil(threads.estimatedTotals);assert.equal("threadQuantity",threads.qualityEffect.stat);assert.equal("amount_unverified",threads.qualityEffect.status);assert.is_nil(threads.qualityEffect.value)
		local legacy=data.summarize(selected,nil,nil,{kind="Item Quantity",value=20})
		assert.is_nil(legacy.estimatedTotals);assert.equal("legacyItemQuantity",legacy.qualityEffect.stat);assert.equal("historical",legacy.qualityEffect.status);assert.equal(10,legacy.qualityEffect.value)
		local unknown=data.summarize(selected,nil,{id="MapCorruptionItemRarity",value=15},{kind="Other",value=20})
		assert.is_false(unknown.qualityEffect.supported);assert.matches("quality effect is not included",unknown.estimateNote)
		assert.equal(unknown.totals.rarity.min+15,unknown.estimatedTotals.rarity.min)
	end)
	it("renders only source-matched sampled lines and validates their values",function()
		local id="MapMonsterCriticalStrikesAndDamageMapWorlds"
		local rolls={{id=id,values={16,9,6,183,32}}}
		local sampled=data.summarize({id},rolls)
		assert.same({"Monsters have 183% increased Critical Strike Chance","+32% to Monster Critical Strike Multiplier"},sampled.effects[1].lines)
		assert.is_true(sampled.effects[1].hasValues);assert.same({min=16,max=16},sampled.totals.atlasDrops)
		local unknown=data.summarize({id});assert.matches("160%-200",unknown.effects[1].lines[1]);assert.is_false(unknown.effects[1].hasValues)
		local negative="MapPlayerMaxResists1MapWorlds";local negativeRoll=data.summarize({negative},{{id=negative,values={19,11,7,-6}}})
		assert.equal("Players have -6% to all maximum Resistances",negativeRoll.effects[1].lines[1])
		local mods=data.source().mods;mods.TestUnmatched=copyTable(mods[id]);mods.TestUnmatched.text="Unmatched (160-200) source text"
		local ok,fallback=pcall(data.summarize,{"TestUnmatched"},{{id="TestUnmatched",values={16,9,6,183,32}}});mods.TestUnmatched=nil
		assert.is_true(ok);assert.equal("Unmatched (160-200) source text",fallback.effects[1].lines[1])
		mods.TestDuplicate=copyTable(mods[id]);mods.TestDuplicate.text="Monsters have (160-200)% increased Critical Strike Chance\nMonsters have (160-200)% increased Critical Strike Chance"
		local ok2,duplicate=pcall(data.summarize,{"TestDuplicate"},{{id="TestDuplicate",values={16,9,6,183,32}}});mods.TestDuplicate=nil
		assert.is_true(ok2);assert.same({"Monsters have (160-200)% increased Critical Strike Chance","Monsters have (160-200)% increased Critical Strike Chance"},duplicate.effects[1].lines)
		assert.has_error(function() data.summarize({id},{{id=id,values={16,9,6,201,32}}}) end)
		assert.has_error(function() data.summarize({},rolls) end)
	end)
	it("renders the pinned ordinary-map variable lines at their midpoint",function()
		local rangeCount=0
		for id,mod in pairs(data.source().mods) do if id:match("Worlds$") then
			local values={};for i,stat in ipairs(mod.stats) do values[i]=math.floor((stat.min+stat.max)/2) end
			for line in (mod.text or ""):gmatch("[^\r\n]+") do if line:find("%(%-?%d+%-%-?%d+%)") then rangeCount=rangeCount+1 end end
			local result=data.summarize({id},{{id=id,values=values}})
			for _,line in ipairs(result.effects[1].lines) do assert.is_nil(line:find("%(%-?%d+%-%-?%d+%)"),id..": "..line) end
		end end
		assert.equal(39,rangeCount)
	end)
end)
