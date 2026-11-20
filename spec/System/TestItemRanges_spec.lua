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
	it("preserves known hybrid rolls and rejects ambiguous combined copied values",function()
		local m=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86");local state=copyTable(m.initial);state.rarity="RARE"
		state.affixes={{id="IncreasedLife1",range=0.5},{id="LocalBaseArmourAndLife1",range={0.5,0.6}}}
		local item=sim.toItem(m,state);local imported=sim.model(item.raw)
		local ids={};for _,entry in ipairs(imported.initial.affixes) do ids[entry.id]=true end
		assert.is_true(ids.IncreasedLife1);assert.is_true(ids.LocalBaseArmourAndLife1)
		local copied="Rarity: RARE\nExample Hood\nIron Hat\nItem Level: 86\nImplicits: 0\n+26 to Armour\n+38 to maximum Life"
		local ok,err=pcall(sim.model,copied);assert.is_false(ok);assert.matches("several modifier identities",err,1,true)
	end)
	it("does not mistake combined armour rolls for a unique modifier assignment",function()
		local copied="Rarity: RARE\nExample Hood\nIron Hat\nItem Level: 86\nImplicits: 0\n79% increased Armour\n13% increased Stun and Block Recovery"
		local ok,err=pcall(sim.model,copied);assert.is_false(ok);assert.matches("several modifier identities",err,1,true)
		local base=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86");local state=copyTable(base.initial);state.rarity="RARE"
		state.affixes={{id="LocalIncreasedPhysicalDamageReductionRatingPercentAndStunRecovery4",range=0.5},{id="LocalIncreasedPhysicalDamageReductionRatingPercent3",range=0.5}}
		local imported=sim.model(sim.toItem(base,state).raw);local ids={};for _,entry in ipairs(imported.initial.affixes) do ids[entry.id]=true end
		assert.is_true(ids.LocalIncreasedPhysicalDamageReductionRatingPercentAndStunRecovery4);assert.is_true(ids.LocalIncreasedPhysicalDamageReductionRatingPercent3)
	end)
	it("explains combined values when no individual modifier matches",function()
		local copied="Rarity: RARE\nExample Hood\nIron Hat\nItem Level: 86\nImplicits: 0\n132% increased Armour\n17% increased Stun and Block Recovery"
		local ok,err=pcall(sim.model,copied);assert.is_false(ok);assert.matches("may combine multiple modifiers",err,1,true);assert.matches("advanced copy text",err,1,true)
	end)
	it("keeps combined prefix and suffix contributions on their own sides",function()
		local m=sim.model("Rarity: NORMAL\nPlate Vest\nItem Level: 86");local state=copyTable(m.initial);state.rarity="RARE"
		state.affixes={{id="LocalIncreasedPhysicalDamageReductionRatingPercentAndStunRecovery3",range={0,0}},{id="StunRecovery6",range=1}}
		local item=sim.toItem(m,state);local prefix,suffix
		for _,line in ipairs(item.explicitModLines) do
			if line.line=="10% increased Stun and Block Recovery" then prefix=line end
			if line.line=="28% increased Stun and Block Recovery" then suffix=line end
		end
		assert.is_not_nil(prefix);assert.is_true(prefix.prefix);assert.is_falsy(prefix.suffix)
		assert.is_not_nil(suffix);assert.is_true(suffix.suffix);assert.is_falsy(suffix.prefix)
		item.modMagnitudeMods={{tags={"prefix"},quality=50}}
		assert.are.equal(1.5,item:GetModLineValueScalar(prefix,"explicit"));assert.are.equal(1,item:GetModLineValueScalar(suffix,"explicit"))
		local imported=sim.model(item.raw);assert.equal(2,#imported.initial.affixes)
		local hat=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86");local sameSide=copyTable(hat.initial);sameSide.rarity="RARE"
		sameSide.affixes={{id="LocalIncreasedPhysicalDamageReductionRatingPercentAndStunRecovery6",range={1,1}},{id="LocalIncreasedPhysicalDamageReductionRatingPercent6",range=1}}
		local combined=sim.toItem(hat,sameSide);local found=0;for _,line in ipairs(combined.explicitModLines) do if line.line=="133% increased Armour" and line.prefix then found=found+1 end end
		assert.equal(1,found)
		sameSide.affixes[1].fractured=true;local split=sim.toItem(hat,sameSide);local fractured,ordinary
		for _,line in ipairs(split.explicitModLines) do if line.line=="42% increased Armour" then fractured=line elseif line.line=="91% increased Armour" then ordinary=line end end
		assert.is_not_nil(fractured);assert.is_not_nil(ordinary);assert.is_true(fractured.fractured);assert.is_falsy(ordinary.fractured)
	end)
	it("keeps tag and fracture information when same-side stats overlap",function()
		local m=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86");local state=copyTable(m.initial);state.rarity="RARE"
		state.affixes={{id="IncreasedLife9",range=0.5,fractured=true},{id="LocalBaseArmourAndLife1",range={0.5,0.5}}}
		local item=sim.toItem(m,state);local flat,hybrid
		for _,line in ipairs(item.explicitModLines) do
			if line.line=="+137 to maximum Life" then flat=line end
			if line.line=="+21 to maximum Life" then hybrid=line end
		end
		assert.is_not_nil(flat);assert.is_not_nil(hybrid);assert.is_true(flat.fractured);assert.is_falsy(hybrid.fractured)
		item.modMagnitudeMods={{tags={"armour"},quality=50}}
		assert.are.equal(1,item:GetModLineValueScalar(flat,"explicit"));assert.are.equal(1.5,item:GetModLineValueScalar(hybrid,"explicit"))
		local imported=sim.model(item.raw);assert.equal(2,#imported.initial.affixes)
	end)
	it("keeps fractional modifier contributions numerically correct",function()
		-- These bundled templates demonstrate decimal arithmetic; their current
		-- availability together is not assumed by this rendering test.
		local m=sim.model("Rarity: NORMAL\nPlate Vest\nItem Level: 86");local state=copyTable(m.initial);state.rarity="RARE"
		local first,second="LifeRegenerationEnhancedLevel50Mod","LifeRegenerationPercentBodyInfluenceMaven"
		m.byId[first]=data.itemMods.Explicit[first];m.byId[second]=data.itemMods.Explicit[second]
		state.affixes={{id=first,range=0.5},{id=second,range=7/9}}
		local item=sim.toItem(m,state);local values={};local total=0
		for _,line in ipairs(item.explicitModLines) do values[line.line]=true end
		for _,mod in ipairs(item.baseModList) do if mod.name=="LifeRegenPercent" then total=total+mod.value end end
		assert.is_true(values["Regenerate 0.4% of Life per second"]);assert.is_true(values["Regenerate 2.8% of Life per second"])
		assert.are.near(3.2,total,0.000001)
	end)
	it("does not combine matching text from different native stats",function()
		local m=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86")
		local function mod(high,group,order) return {"(1-"..high..")% increased Example",type="Prefix",group=group,statOrder={order}} end
		m.byId.ExampleA=mod(10,"ExampleA",100);m.byId.ExampleB=mod(5,"ExampleB",101);m.byId.ExampleC=mod(5,"ExampleC",102)
		m.mods={{id="ExampleA"},{id="ExampleB"},{id="ExampleC"}};m.essences={};m.bench={};m.item.explicitModLines={{line="6% increased Example"}}
		local state=require("Modules.CraftingImport").resolve(sim,m,{rarity="RARE",affixes={}})
		assert.are.equal(1,#state.affixes);assert.are.equal("ExampleA",state.affixes[1].id)
	end)
	it("checks Essence modifiers as possible combined-value contributors",function()
		local m=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86")
		local function mod(high,group) return {"(1-"..high..")% increased Example",type="Prefix",group=group,statOrder={100}} end
		m.byId.ExampleA=mod(10,"ExampleA");m.byId.ExampleB=mod(5,"ExampleB");m.byId.ExampleC=mod(5,"ExampleC")
		m.mods={{id="ExampleA"},{id="ExampleB"}};m.essences={{modId="ExampleC"}};m.bench={};m.item.explicitModLines={{line="6% increased Example"}}
		local ok,err=pcall(require("Modules.CraftingImport").resolve,sim,m,{rarity="RARE",affixes={}})
		assert.is_false(ok);assert.matches("several modifier identities",err,1,true)
	end)
	it("rejects a three-contributor alternative without conflating different stats",function()
		local m=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86")
		local function mod(value,group,order) return {"("..value.."-"..value..")% increased Example",type="Prefix",group=group,statOrder={order}} end
		m.byId.ExampleA=mod(9,"ExampleA",100);m.byId.ExampleB=mod(3,"ExampleB",100)
		m.byId.ExampleC=mod(3,"ExampleC",100);m.byId.ExampleD=mod(3,"ExampleD",100)
		m.mods={{id="ExampleA"},{id="ExampleB"},{id="ExampleC"},{id="ExampleD"}};m.essences={};m.bench={}
		m.item.explicitModLines={{line="9% increased Example"}}
		local import=require("Modules.CraftingImport")
		local ok,err=pcall(import.resolve,sim,m,{rarity="RARE",affixes={}})
		assert.is_false(ok);assert.matches("several modifier identities",err,1,true)
		m.byId.ExampleD.statOrder={101}
		local state=import.resolve(sim,m,{rarity="RARE",affixes={}})
		assert.are.equal(1,#state.affixes);assert.are.equal("ExampleA",state.affixes[1].id)
	end)

	it("rejects four contributors only when their groups and sides can coexist",function()
		local m=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86")
		local function mod(value,group,kind) return {"("..value.."-"..value..")% increased Example",type=kind,group=group,statOrder={100}} end
		m.byId.ExampleA=mod(8,"ExampleA","Prefix");m.byId.ExampleB=mod(2,"ExampleB","Prefix")
		m.byId.ExampleC=mod(2,"ExampleC","Prefix");m.byId.ExampleD=mod(2,"ExampleD","Suffix");m.byId.ExampleE=mod(2,"ExampleE","Suffix")
		m.mods={{id="ExampleA"},{id="ExampleB"},{id="ExampleC"},{id="ExampleD"},{id="ExampleE"}};m.essences={};m.bench={}
		m.item.explicitModLines={{line="8% increased Example"}}
		local import=require("Modules.CraftingImport")
		local ok,err=pcall(import.resolve,sim,m,{rarity="RARE",affixes={}})
		assert.is_false(ok);assert.matches("several modifier identities",err,1,true)
		m.byId.ExampleE.group="ExampleD"
		local state=import.resolve(sim,m,{rarity="RARE",affixes={}})
		assert.are.equal(1,#state.affixes);assert.are.equal("ExampleA",state.affixes[1].id)
	end)

	it("detects alternatives with five or six contributing modifiers",function()
		for _,count in ipairs({5,6}) do
			local m=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86")
			local function mod(value,group,kind) return {"("..value.."-"..value..")% increased Example",type=kind,group=group,statOrder={100}} end
			m.byId.ExampleDirect=mod(count,"Direct","Prefix");m.mods={{id="ExampleDirect"}}
			for i=1,count do
				local id="Example"..i;m.byId[id]=mod(1,id,i<=3 and "Prefix" or "Suffix");m.mods[#m.mods+1]={id=id}
			end
			m.essences={};m.bench={};m.item.explicitModLines={{line=count.."% increased Example"}}
			local ok,err=pcall(require("Modules.CraftingImport").resolve,sim,m,{rarity="RARE",affixes={}})
			assert.is_false(ok);assert.matches("several modifier identities",err,1,true)
		end
	end)

	it("detects hybrid modifiers combined across multiple displayed rows",function()
		local m=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86")
		local function mod(first,second,group) return {"("..first.."-"..first..")% increased Example","("..second.."-"..second..")% increased Other",type="Prefix",group=group,statOrder={100,101}} end
		m.byId.ExampleA=mod(8,10,"ExampleA");m.byId.ExampleB=mod(4,5,"ExampleB");m.byId.ExampleC=mod(4,5,"ExampleC")
		m.mods={{id="ExampleA"},{id="ExampleB"},{id="ExampleC"}};m.essences={};m.bench={}
		m.item.explicitModLines={{line="8% increased Example"},{line="10% increased Other"}}
		local import=require("Modules.CraftingImport")
		local ok,err=pcall(import.resolve,sim,m,{rarity="RARE",affixes={}})
		assert.is_false(ok);assert.matches("several modifier identities",err,1,true)
		m.byId.ExampleC.statOrder[2]=102
		local state=import.resolve(sim,m,{rarity="RARE",affixes={}})
		assert.are.equal(1,#state.affixes);assert.are.equal("ExampleA",state.affixes[1].id)
	end)

	it("detects separate combined contributor groups across rows",function()
		local m=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86")
		local function mod(value,label,group,kind,order) return {"("..value.."-"..value..")% increased "..label,type=kind,group=group,statOrder={order}} end
		m.byId.A=mod(8,"Example","GroupA","Prefix",100);m.byId.B=mod(10,"Other","GroupB","Suffix",101)
		m.byId.C=mod(4,"Example","GroupB","Prefix",100);m.byId.D=mod(4,"Example","GroupD","Prefix",100)
		m.byId.E=mod(5,"Other","GroupA","Suffix",101);m.byId.F=mod(5,"Other","GroupF","Suffix",101)
		m.mods={{id="A"},{id="B"},{id="C"},{id="D"},{id="E"},{id="F"}};m.essences={};m.bench={}
		m.item.explicitModLines={{line="8% increased Example"},{line="10% increased Other"}}
		local import=require("Modules.CraftingImport")
		local ok,err=pcall(import.resolve,sim,m,{rarity="RARE",affixes={}})
		assert.is_false(ok);assert.matches("several modifier identities",err,1,true)
		m.byId.F.statOrder[1]=102
		local state=import.resolve(sim,m,{rarity="RARE",affixes={}});assert.are.equal(2,#state.affixes)
	end)

end)
