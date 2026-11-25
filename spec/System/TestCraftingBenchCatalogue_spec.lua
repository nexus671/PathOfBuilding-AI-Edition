describe("3.30 client bench catalogue",function()
	local bench=require("Modules.CraftingBenchCosts")
	it("indexes current class-specific costs while accepting saved lock wording",function()
		local f=assert(io.open("Data/Crafting/3.30-bench.json","rb"));local raw=f:read("*a");f:close()
		local catalogue=assert(require("dkjson").decode(raw));assert.are.equal(782,#catalogue.bench)
		local lookup=bench.index(catalogue)
		local mod={"Prefixes Cannot Be Changed",level=1,type="Suffix"}
		local model={item={type="Ring",base={}},byId={["bench:728"]=mod}}
		local cost,sources=bench.cost(model,"bench:728",lookup)
		assert.are.same({["Metadata/Items/Currency/CurrencyModValues"]=4,["Metadata/Items/Currency/CurrencyAddModToRare"]=8},cost)
		assert.are.same({"StrMasterItemGenerationCannotChangePrefixesC"},sources)
		model.item.type="Body Armour"
		assert.are.same({["Metadata/Items/Currency/CurrencyModValues"]=4,["Metadata/Items/Currency/CurrencyRerollImplicit"]=4},bench.cost(model,"bench:728",lookup))
		model.item.type="Jewel";assert.is_nil(bench.cost(model,"bench:728",lookup))
	end)
	it("matches client display links to native effects without losing their ingredient costs",function()
		local sim=require("Modules.CraftingSimulator")
		local cases={
			{"Iron Greaves","chance to gain Onslaught", "JunMaster2MovementVelocityAndOnslaughtOnKill1", "CurrencyRerollMagic",4},
			{"Iron Gauntlets","Onslaught during Soul Gain Prevention", "JunMaster2GainOnslaughtDuringSoulGainPrevention1", "CurrencyCorrupt",3},
			{"Gold Amulet","Summon Spectral Wolf", "JunMaster2WolfOnKill1", "CurrencyRerollRare",3},
			{"Rusted Sword","(13-15)% chance to Blind", "JunMaster2LocalIncreasedPhysicalDamageAndBlindChanceCrafted1_", "CurrencyUpgradeToRare",3},
		}
		for _,case in ipairs(cases) do
			local model=sim.model("Rarity: NORMAL\n"..case[1].."\nItem Level: 86");local found
			for _,entry in ipairs(model.bench) do
				if not entry.mod.legacyBenchUnavailable and table.concat(entry.mod,"\n"):find(case[2],1,true) then
					local cost,sources=bench.cost(model,entry.id)
					if cost and isValueInTable(sources,case[3]) then
						assert.are.same({["Metadata/Items/Currency/"..case[4]]=case[5]},cost)
						assert.are.same(cost,sim.components({method="bench",modId=entry.id},model.initial,model));found=true
					end
				end
			end
			assert.is_true(found,case[3])
		end
	end)
	it("does not select a price when normalized client effects conflict",function()
		local catalogue={benchMods={a={text="Gain [Onslaught] on Hit",required_level=1,generation_type="suffix"},b={text="Gain Onslaught on hit",required_level=1,generation_type="suffix"}},bench={}}
		for i,id in ipairs({"a","b"}) do catalogue.bench[i]={actions={add_explicit_mod=id},item_classes={"Ring"},cost={orb=i}} end
		local mod={"Gain Onslaught on Hit",level=1,type="Suffix"};local model={item={type="Ring",base={}},byId={["bench:1"]=mod}}
		assert.is_nil(bench.cost(model,"bench:1",bench.index(catalogue)))
	end)
end)
