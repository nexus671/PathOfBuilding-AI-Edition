describe("Independent modifier ranges",function()
	local sim=require("Modules.CraftingSimulator")
	it("advances vector rolls over lines while preserving scalar and singleton rolls",function()
		local mod={"Adds (1-3) to (4-6) Fire Damage","Cannot be Frozen","+(10-20) to maximum Life"}
		assert.are.same({"Adds 1 to 6 Fire Damage","Cannot be Frozen","+15 to maximum Life"},itemLib.applyModRanges(mod,{0,1,0.5}))
		assert.are.same(itemLib.applyModRanges(mod,0),itemLib.applyModRanges(mod,{0}))
		assert.are.same({"Adds 3 to 6 Fire Damage","Cannot be Frozen","+20 to maximum Life"},itemLib.applyModRanges(mod,1))
	end)
	it("retains every independent multi-line roll through native item conversion",function()
		local tested=0
		for _,base in ipairs({"Iron Hat","Plate Vest","Rusted Sword","Small Life Flask","Prismatic Tincture"}) do
			local m=sim.model("Rarity: NORMAL\n"..base.."\nItem Level: 86")
			for _,entry in ipairs(m.mods) do if #entry.mod>1 then
				local values={};local rangedLines=0
				for _,line in ipairs(entry.mod) do local count=0;for _ in line:gmatch("%(%-?%d+%.?%d*%-%-?%d+%.?%d*%)") do values[#values+1]=#values%2;count=count+1 end;if count>0 then rangedLines=rangedLines+1 end end
				if rangedLines>1 then
					tested=tested+1;local state=copyTable(m.initial);state.rarity=(m.item.type=="Flask" or m.item.type=="Tincture") and "MAGIC" or "RARE";state.affixes={{id=entry.id,range=values}}
					local item=sim.toItem(m,state);local expected=itemLib.applyModRanges(entry.mod,values);local actual={}
					for _,line in ipairs(item.explicitModLines) do actual[#actual+1]=line.line end;table.sort(expected);table.sort(actual)
					assert.are.same(expected,actual,entry.id);local imported=sim.model(item.raw)
					assert.are.same(values,imported.initial.affixes[1].range,entry.id)
					assert.are.same(values,state.affixes[1].range)
				end
			end end
		end
		assert.is_true(tested>=40)
	end)
	it("infers distinct rolls on separate lines rather than requiring equal fractions",function()
		local m=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86");local id="LocalBaseArmourAndLife1"
		local state=copyTable(m.initial);state.rarity="RARE";state.affixes={{id=id,range={0,1}}}
		m.item=sim.toItem(m,state);m.mods={{id=id,mod=m.byId[id]}};m.essences={};m.bench={}
		local resolved=require("Modules.CraftingImport").resolve(sim,m,{rarity="RARE",affixes={}})
		assert.are.equal(1,#resolved.affixes);assert.are.equal(id,resolved.affixes[1].id);assert.are.same({0,1},resolved.affixes[1].range)
	end)
	it("matches repeated copied lines across separate affixes without inventing ambiguity",function()
		local m=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86")
		local first={"+(1-3) to Example", "+(4-6) to Other Example",type="Prefix",group="ExampleA"}
		local second={"+(1-3) to Example",type="Prefix",group="ExampleB"}
		m.byId.ExampleA=first;m.byId.ExampleB=second;m.mods={{id="ExampleA"},{id="ExampleB"}};m.essences={};m.bench={}
		m.item.explicitModLines={{line="+2 to Example"},{line="+5 to Other Example"},{line="+2 to Example"}}
		local resolved=require("Modules.CraftingImport").resolve(sim,m,{rarity="RARE",affixes={}})
		assert.are.equal(2,#resolved.affixes)
		local ids={};for _,entry in ipairs(resolved.affixes) do ids[entry.id]=true end
		assert.is_true(ids.ExampleA);assert.is_true(ids.ExampleB)
		m.item.explicitModLines[3].line="+3 to Example"
		local ok,err=pcall(require("Modules.CraftingImport").resolve,sim,m,{rarity="RARE",affixes={}})
		assert.is_false(ok);assert.matches("several modifier identities",err,1,true)
	end)
	it("resolves an overlapping life roll on actual life and armour-life modifiers",function()
		local m=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86")
		local life,hybrid="IncreasedLife1","LocalBaseArmourAndLife1"
		m.mods={{id=life},{id=hybrid}};m.essences={};m.bench={}
		m.item.explicitModLines={{line="+21 to maximum Life"},{line="+26 to Armour"},{line="+21 to maximum Life"}}
		local resolved=require("Modules.CraftingImport").resolve(sim,m,{rarity="RARE",affixes={}})
		local ids={};for _,entry in ipairs(resolved.affixes) do ids[entry.id]=true end
		assert.is_true(ids[life]);assert.is_true(ids[hybrid])
	end)
	it("honours prefix and suffix labels when matching a known modifier",function()
		local m=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86")
		local prefix,suffix="LocalIncreasedPhysicalDamageReductionRatingPercentAndStunRecovery4","StunRecovery1"
		m.mods={{id=suffix}};m.essences={};m.bench={}
		m.item.explicitModLines={{line="12% increased Stun and Block Recovery",suffix=true},{line="27% increased Armour",prefix=true},{line="12% increased Stun and Block Recovery",prefix=true}}
		local resolved=require("Modules.CraftingImport").resolve(sim,m,{rarity="RARE",affixes={{id=prefix,range={0,0}}}})
		assert.are.equal(2,#resolved.affixes);assert.are.equal(suffix,resolved.affixes[2].id)
	end)
end)
