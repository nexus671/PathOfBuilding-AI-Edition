describe("Encounter reporting and comparisons",function()
	local encounter=require("Modules.CalcEncounter")
	local time=require("Modules.CalcTime")
	before_each(function() newBuild() end)

	it("highlights distinct important timeline events instead of repeated recharge events",function()
		local breakdown=build.calcsTab.controls.breakdown
		local events=breakdown:TimelineEventHighlights({
			{time=0,event="Recharge interrupted by hit"},{time=1,event="Recharge interrupted by hit"},
			{time=3,event="Guard expired"},{time=4,event="Tincture deactivated"},{time=9,event="Death"},
		})
		assert.same({"9.00s Death","3.00s Guard expired","4.00s Tincture deactivated"},events)
		local guard=breakdown:TimelineEventHighlights({{time=0,event="Recharge interrupted by hit"},{time=3,event="Guard expired"}})
		assert.same({"3.00s Guard expired","0.00s Recharge interrupted by hit"},guard)
	end)
	it("keeps encounter scenario names readable at the narrow window size",function()
		local ui=require("Modules.HeadlessUI").install({width=960,height=640});ui:bind(build)
		local ok,err=pcall(function()
			build.calcsTab:OpenEncounterWorkspace();local preset=main.popups[1].controls.preset
			local width,height=preset:GetSize();local textSize=math.min(height-4,preset.planningTextSize or height-4)
			for _,entry in ipairs(preset.list) do assert.is_true(DrawStringWidth(textSize,"VAR",entry.label)<=width-height,entry.label) end
			preset:SelByValue(7,"val");assert.equal("Scenario: Hits plus continuous damage",preset:GetProperty("tooltipText"))
		end)
		main:ClosePopup();ui:restore();assert.is_true(ok,tostring(err))
	end)
	it("formats digit-bearing poison outputs as values instead of raw placeholders",function()
		assert.are.equal("123.5",formatCalcStr("{1:output:PoisonDPSAt1}",{output={PoisonDPSAt1=123.456}}))
		assert.are.equal("7",formatCalcStr("{output:PoisonDPSAt10}",{output={PoisonDPSAt10=7}}))
	end)

	it("resolves saved avoidance power categories and separates player/minion stats",function()
		local output={MeleeNotHitChance=51,SpellNotHitChance=12,ProjectileNotHitChance=63,Life=100,
			TotalPoisonDPS=1000,Minion={Life=999,MeleeNotHitChance=7,TotalPoisonDPS=200}}
		for key,value in pairs({MeleeAvoidChance=51,SpellAvoidChance=12,ProjectileAvoidChance=63,MinionMeleeAvoidChance=7,Life=100,MinionLife=999,TotalPoisonDPS=1200}) do
			assert.are.equal(value,data.powerStatList.GetFromOutput(output,{stat=key}))
		end
	end)
	it("keeps node power and heatmap colours defined for zero and infinite values",function()
		local power=common.classes.CalcsTab.CalculatePowerStat;local stat={stat="SecondMinimalMaximumHitTaken"}
		assert.equal(0,power(nil,stat,{SecondMinimalMaximumHitTaken=math.huge},{SecondMinimalMaximumHitTaken=math.huge}))
		assert.equal(math.huge,power(nil,stat,{SecondMinimalMaximumHitTaken=math.huge},{SecondMinimalMaximumHitTaken=100}))
		local color=data.powerStatList.HeatmapIntensity
		assert.equal(0,color(0,0));assert.equal(0,color(1,math.huge));assert.equal(0,color(0/0,10))
		assert.near(math.sqrt(1.5),color(math.huge,math.huge),1e-9);assert.near(math.sqrt(0.75),color(5,10),1e-9)
	end)
	it("draws zero and infinite power heatmaps without invalid colours",function()
		local ui=require("Modules.HeadlessUI").install({width=1024,height=768});local viewer=build.treeTab.viewer;local oldTheme=main.nodePowerTheme
		local ok,message=pcall(function()
			viewer.showHeatMap=true;build.calcsTab.BuildPower=function() end;main.nodePowerTheme="RED/BLUE"
			for _,node in pairs(build.spec.nodes) do node.power=node.power or {} end
			for _,case in ipairs({{single=true,value=0},{single=false,value=0},{single=true,value=math.huge},{single=false,value=math.huge}}) do
				build.calcsTab.powerStat=case.single and {stat="SecondMinimalMaximumHitTaken"} or nil
				build.calcsTab.powerMax={singleStat=case.value,offence=case.value,defence=case.value}
				for _,node in pairs(build.spec.nodes) do node.power.singleStat=case.value;node.power.offence=case.value;node.power.defence=case.value end
				ui:frame(function(viewport) viewer:Draw(build,viewport,{}) end)
				local count,highlight=0,false
				for _,command in ipairs(ui.commands) do for _,value in ipairs(command.color or {}) do
					assert.is_true(type(value)=="number" and value==value and math.abs(value)<math.huge);count=count+1;if value>1.2 then highlight=true end
				end end
				assert.is_true(count>0);if case.value==math.huge then assert.is_true(highlight) end
			end
		end)
		ui:restore();main.nodePowerTheme=oldTheme;assert.is_true(ok,message)
	end)

	it("calculates distinct node identities with identical modifiers independently",function()
		local nodes={}
		for id=1,2 do nodes[id]={id=id,modKey="same",power={},pathDist=1} end
		local control=setmetatable({powerStat={stat="Life"},mainEnv={grantedPassives={}},
			build={spec={nodes=nodes,tree={clusterNodeMap={}},masterySelections={}}}}, {__index=common.classes.CalcsTab})
		control.GetMiscCalculator=function() return function(override)
			local node=next(override.addNodes)
			return {Life=100+node.id}
		end,{Life=100} end
		control:PowerBuilder()
		assert.are.equal(1,nodes[1].power.singleStat); assert.are.equal(2,nodes[2].power.singleStat)
	end)

	it("preserves final tincture-value provenance across raw-item saves",function()
		local raw="Item Class: Tinctures\nRarity: Magic\nTest Tincture\nPrismatic Tincture\nQuality: +20%\nImplicits: 0\n29% increased Attack Speed"
		local item=new("Item"):Item(raw)
		assert.are.equal("Final",item.tinctureValues)
		item:BuildAndParseRaw(); assert.are.equal("Final",item.tinctureValues)
		local base=new("Item"):Item(raw:gsub("Item Class: Tinctures\n",""))
		assert.is_nil(base.tinctureValues)
	end)

	it("parses separate tincture lingering duration and cap",function()
		local list,extra=modLib.parseMod("Tincture Effects Linger on you for 0.5 seconds per Mana Burn on you when the Tincture was deactivated, up to a maximum of 6 seconds")
		assert.is_nil(extra)
		assert.are.equal("TinctureLingerPerBurn",list[1].name); assert.are.equal(0.5,list[1].value)
		assert.are.equal("TinctureLingerMax",list[2].name); assert.are.equal(6,list[2].value)
	end)

	it("separates indexed incoming rolls while preserving reproducible trial identity",function()
		local count,trialCounts=0,{ }
		for trial=1,64 do
			trialCounts[trial]=0
			local seed=encounter.seed(104729,trial)
			assert.are.equal(seed,encounter.seed(104729,trial))
			for attempt=1,256 do
				local random=time.random(encounter.seed(seed,attempt,100))
				local rolls={}; for i=1,6 do rolls[i]=random() end
				if rolls[4] >= 0.75 then trialCounts[trial]=trialCounts[trial]+1 end
				if rolls[4] >= 0.75 and rolls[6] >= 0.47 then count=count+1 end
			end
		end
		assert.are.near(0.25*0.53,count/(64*256),0.01)
		local mean,variance=0,0
		for _,n in ipairs(trialCounts) do mean=mean+n/64 end
		for _,n in ipairs(trialCounts) do variance=variance+(n-mean)^2/63 end
		assert.is_true(variance > 20 and variance < 100,"Trial counts should vary around their binomial expectation, rather than repeating a correlated pattern")
	end)

	it("integrates poison application, gaps and expiry without multiplying steady DPS by uptime",function()
		local p=encounter.poison(1000)
		p:hit(0,{{slope=100,duration=2}},1,20)
		local rate,damage=p:advance(4)
		assert.are.equal(0,rate); assert.are.near(200,damage,1e-8)
		p:hit(5,{{slope=100,duration=2}},1,20)
		local _,total,direct=p:advance(10)
		assert.are.near(400,total,1e-8); assert.are.equal(40,direct)
	end)

	it("snapshots poison damage and independently expires old applications",function()
		local p=encounter.poison(1000)
		p:hit(0,{{slope=10,duration=4}},1)
		p:hit(2,{{slope=20,duration=4}},1)
		assert.are.near(30,p:advance(3),1e-8)
		assert.are.near(20,p:advance(4),1e-8)
		local rate,damage=p:advance(6)
		assert.are.equal(0,rate); assert.are.near(120,damage,1e-8)
	end)

	it("applies poison stream limits and the shared DoT cap before integration",function()
		local p=encounter.poison(25)
		p:hit(0,{{slope=100,duration=2,limit=10},{slope=100,duration=4}},1)
		local _,damage=p:advance(4)
		assert.are.near(100,damage,1e-8)
	end)

	it("rounds flask cost after combining local and global modifiers (#7578)",function()
		assert.are.equal(11,encounter.chargesUsed(20,-19,-32))
		assert.are.equal(10,encounter.chargesUsed(20,-19,-33))
	end)

	it("shares charge state across passive gain, use and event gain",function()
		local bank=encounter.charges({charges=20,used=10,generation=1,gain=2},function() return 1 end)
		assert.is_true(bank:use(0)); assert.are.equal(10,bank.charges)
		bank:gain(1,3); assert.are.equal(17,bank.charges)
		assert.is_true(bank:use(2)); assert.are.equal(8,bank.charges)
		bank:advance(4); assert.are.equal(10,bank.charges)
	end)
	it("blocks passive and hit or critical flask charges only while its effect lasts",function()
		local sealed=encounter.charges({charges=10,used=10,generation=2,gain=1,duration=4,noGainDuringEffect=true},function() return 1 end)
		local ordinary=encounter.charges({charges=10,used=10,generation=2},function() return 1 end)
		assert.is_true(sealed:use(0));assert.is_true(ordinary:use(0))
		local events=encounter.chargeEvents({sealed,ordinary},{{chargesWhenHit=3,critChance=100},{chargesWhenHit=3}},function() return 0 end)
		events:hit(1);events:critical(1,0);assert.equal(0,sealed.charges);assert.equal(5,ordinary.charges)
		sealed:update(2,4,1);assert.equal(0,sealed.charges);assert.equal(6.5,sealed:next(2))
		sealed:advance(4);assert.equal(0,sealed.charges);sealed:gain(4,2);assert.equal(2,sealed.charges)
		sealed:advance(5);ordinary:advance(5);assert.equal(6,sealed.charges);assert.equal(10,ordinary.charges)
	end)

	it("honors non-consumption without allowing repeated uses at the same timestamp",function()
		local bank=encounter.charges({charges=10,used=10,freeChance=100},function() return 0 end)
		assert.are.equal(true,bank:use(0)); assert.are.equal(false,bank:use(0))
		assert.are.equal(true,bank:use(1)); assert.are.equal(10,bank.charges)
		assert.are.equal(2,bank.uses)
	end)

	it("limits critical charge gain to one recipient and a shared 100ms interval",function()
		local a=encounter.charges({charges=10,used=10},function() return 1 end)
		local b=encounter.charges({charges=10,used=10},function() return 1 end)
		a:use(0); b:use(0)
		local events=encounter.chargeEvents({a,b},{{critChance=100},{critChance=100}},function() return 0 end)
		events:critical(0,0); events:critical(0.05,0); events:critical(0.1,0)
		assert.are.equal(2,a.charges); assert.are.equal(0,b.charges)
	end)

	it("gives hit charges to each eligible flask with independent 100ms intervals",function()
		local a=encounter.charges({charges=10,used=10},function() return 1 end)
		local b=encounter.charges({charges=10,used=10},function() return 1 end)
		a:use(0); b:use(0)
		local events=encounter.chargeEvents({a,b},{{chargesWhenHit=3},{chargesWhenHit=2}},function() return 0 end)
		events:hit(0); events:hit(0.099); events:hit(0.1)
		assert.are.equal(6,a.charges); assert.are.equal(4,b.charges)
	end)

	it("recovers missing life at natural flask expiry but cancels that recovery at full",function()
		for _,cancel in ipairs({false,true}) do
			local use=time.recoveryFlask({charges=10,used=10,resources={Life=true},threshold=1,reaction=0})
			local p,full={Life=20},{Life=100}
			local function profile() return {Life={rate=10,finishLife=true}},5 end
			use(0,p,full,full,profile)
			if cancel then p.Life=100; use(1,p,full,full,profile); p.Life=20 end
			use(5,p,full,full,profile)
			assert.are.equal(cancel and 20 or 100,p.Life)
		end
	end)

	it("keeps hybrid recovery until both source pools are full",function()
		local use=time.recoveryFlask({charges=10,used=10,resources={Life=true,Mana=true},threshold=1,reaction=0})
		local p,full={Life=20,Mana=20},{Life=100,Mana=100}
		local function profile() return {Life={rate=10},Mana={rate=10}},5 end
		use(0,p,full,full,profile); p.Life=100
		local active=use(1,p,full,full,profile); assert.are.equal(true,active)
		p.Life=50; local _,rates=use(2,p,full,full,profile); assert.are.equal(10,rates.Life)
		p.Life,p.Mana=100,100; active=use(3,p,full,full,profile); assert.are.equal(false,active)
	end)

	it("ends ES copied from a Life flask when its source Life reaches full",function()
		local use=time.recoveryFlask({charges=10,used=10,resources={Life=true},threshold=1,reaction=0})
		local p,full={Life=20,EnergyShield=0},{Life=100,EnergyShield=100}
		local function profile() return {Life={rate=10},EnergyShield={rate=10}},5 end
		use(0,p,full,full,profile); p.Life=100
		assert.are.equal(false,use(1,p,full,full,profile))
	end)

	it("uses a Wilson interval that expresses uncertainty after zero deaths",function()
		local low,high=encounter.wilson(128,128)
		assert.is_true(low > 97 and low < 98); assert.are.near(100,high,1e-7)
		low,high=encounter.wilson(0,128)
		assert.are.near(0,low,1e-7); assert.is_true(high > 2 and high < 3)
	end)

	it("computes uncertainty from paired differences rather than independent arm variance",function()
		local delta,low,high=encounter.paired({{x=1},{x=100}},{{x=3},{x=102}},function(r) return r.x end)
		assert.are.equal(2,delta); assert.are.equal(2,low); assert.are.equal(2,high)
	end)

	it("bounds timeline events while retaining samples and the terminal state",function()
		local trace=encounter.trace(60)
		local p={Life=100,Mana=10,EnergyShield=20}
		for i=1,1100 do trace:add(i/100,p,"Hit") end
		trace:add(60,p,"Window reached")
		assert.are.equal(1001,#trace.rows); assert.are.equal(100,trace.dropped)
		assert.are.equal("Window reached",trace.rows[#trace.rows].event)
	end)

	it("does not alter results when observing a timeline",function()
		local function run(observe)
			return time.survival({pools={Life=100,Mana=0,EnergyShield=50},caps={Life=100,Mana=0,EnergyShield=50},
				window=10,interval=0.7,step=math.huge,rates={Life=5},observe=observe,
				hit=function(p) p.Life=p.Life-13; return p end})
		end
		local a,b=run(nil),run(function() end)
		assert.are.equal(a.time,b.time); assert.are.equal(a.pools.Life,b.pools.Life)
	end)

	it("reports configuration contradictions without modifying inputs",function()
		local input={multiplierManaBurnStacks=15,conditionFullLife=true,conditionLowLife=true}
		local rows,count=encounter.audit(input,{uncheckedRecovery=true})
		assert.are.equal(3,count); assert.is_true(#rows > count)
		assert.are.equal(15,input.multiplierManaBurnStacks)
	end)

	local function calculate()
		local input=build.configTab.input
		input.simulateRecovery=true; input.recoverySimulationAttacking=true
		input.recoverySimulationTrials=4; input.recoverySimulationWindow=10
		input.enemyDamageType="Untyped"; input.enemyIsBoss="None"; input.enemySpeed=1000; input.enemyCritChance=0
		for _,kind in ipairs({"Physical","Fire","Cold","Lightning","Chaos"}) do input["enemy"..kind.."Damage"]=kind=="Cold" and "20" or "0" end
		input.customMods="+3000 to maximum Life\n+60% to Cold Resistance"
		build.configTab:BuildModList(); runCallback("OnFrame")
		assert(not __mainObject__.promptMsg,__mainObject__.promptMsg)
		return build.calcsTab.calcsOutput
	end
	it("applies the no-charge enchantment to the actual encounter flask trace",function()
		local function trace(enchant)
			newBuild()
			local raw="Rarity: MAGIC\nGranite Flask\nItem Level: 86\n"..(enchant and "Implicits: 1\n{enchant}Gains no Charges during Effect\n" or "")
			local flask=new("Item"):Item(raw);build.itemsTab:AddItem(flask)
			build.itemsTab.slots["Flask 1"].selItemId=flask.id;build.itemsTab.slots["Flask 1"].active=true
			calculate();build.configTab.input.customMods="+3000 to maximum Life\n+60% to Cold Resistance\nFlasks gain 10 Charges every 1 seconds"
			build.configTab:BuildModList();runCallback("OnFrame");assert(not __mainObject__.promptMsg,__mainObject__.promptMsg)
			return build.calcsTab.calcsEnv.player.recoverySimulationTrace.points
		end
		local normal,sealed=trace(false),trace(true)
		local function atOne(points)
			for _,point in ipairs(points) do if point.time>=1-1e-8 then return point.chargesTotal end end
			error("Missing one-second flask sample")
		end
		assert.is_true(atOne(normal)>atOne(sealed),"An active enchanted flask must not gain passive charges")
	end)

	it("does not apply quality twice to game tincture modifiers but retains external effect",function()
		local claw=new("Item"):Item("Rarity: Normal\nImperial Claw")
		build.itemsTab:AddItem(claw); build.itemsTab.slots["Weapon 1"].selItemId=claw.id
		build.skillsTab:PasteSocketGroup("Viper Strike 20/0  1")
		build.skillsTab:ProcessSocketGroup(build.skillsTab.socketGroupList[1])
		local raw="Rarity: Magic\nPersevering Prismatic Tincture of Mastery\nPrismatic Tincture\nQuality: +20%\nImplicits: 0\n29% increased Attack Speed"
		local function speed(text,external)
			local item=new("Item"):Item(text)
			build.itemsTab:AddItem(item); build.itemsTab.slots["Flask 1"].selItemId=item.id; build.itemsTab.slots["Flask 1"].active=true
			build.configTab.input.customMods=external or ""
			build.configTab:BuildModList(); runCallback("OnFrame")
			assert(not __mainObject__.promptMsg,__mainObject__.promptMsg)
			return build.calcsTab.calcsOutput.Speed
		end
		local created=speed(raw)
		local final=speed("Item Class: Tinctures\n"..raw)
		build.itemsTab:SetDisplayItem(new("Item"):Item("Item Class: Tinctures\n"..raw))
		assert.are.equal(2,build.itemsTab.controls.displayItemTinctureValues.selIndex)
		build.viewMode="ITEMS"; runCallback("OnFrame"); assert(not __mainObject__.promptMsg,__mainObject__.promptMsg)
		assert.is_true(created > final)
		assert.are.near(final,speed("Item Class: Tinctures\n"..raw:gsub("Quality: %+20%%","Quality: +0%")),1e-8)
		assert.is_true(speed("Item Class: Tinctures\n"..raw,"Tinctures applied to you have 20% increased effect") > final)
	end)

	it("retains copied tincture local-effect baseline when editing the item",function()
		local claw=new("Item"):Item("Rarity: Normal\nImperial Claw");build.itemsTab:AddItem(claw);build.itemsTab.slots["Weapon 1"].selItemId=claw.id
		build.skillsTab:PasteSocketGroup("Viper Strike 20/0  1");build.skillsTab:ProcessSocketGroup(build.skillsTab.socketGroupList[1])
		local raw="Item Class: Tinctures\nRarity: MAGIC\nHorticultural Prismatic Tincture of Mastery\nPrismatic Tincture\nItem Level: 86\nQuality: 20\nImplicits: 0\n20% increased effect\n29% increased Attack Speed"
		local function speed(text) local item=new("Item"):Item(text);build.itemsTab:AddItem(item);build.itemsTab.slots["Flask 1"].selItemId=item.id;build.itemsTab.slots["Flask 1"].active=true;build.configTab:BuildModList();runCallback("OnFrame");assert(not __mainObject__.promptMsg,__mainObject__.promptMsg);return build.calcsTab.calcsOutput.Speed end
		local original=new("Item"):Item(raw);assert.equal(20,original.tinctureImportedEffect);local saved=original:BuildRaw();assert.matches("Tincture Imported Effect: 20",saved,1,true)
		local changed=(saved:gsub("20%% increased effect","40%% increased effect"));local restored=new("Item"):Item(changed)
		assert.equal(20,restored.tinctureImportedEffect);assert.equal(40,restored.tinctureData.effectInc);assert.is_true(speed(changed)>speed(raw))
		local negative=new("Item"):Item((raw:gsub("20%% increased effect","20%% reduced effect")));assert.equal(-20,negative.tinctureImportedEffect);assert.equal(-20,new("Item"):Item(negative:BuildRaw()).tinctureImportedEffect)
	end)
	it("applies quality changes to copied unique tincture effects",function()
		local claw=new("Item"):Item("Rarity: Normal\nImperial Claw");build.itemsTab:AddItem(claw);build.itemsTab.slots["Weapon 1"].selItemId=claw.id
		build.skillsTab:PasteSocketGroup("Viper Strike 20/0  1");build.skillsTab:ProcessSocketGroup(build.skillsTab.socketGroupList[1])
		-- The modifier is synthetic to isolate the quality baseline in character calculations.
		local raw="Item Class: Tinctures\nRarity: UNIQUE\nThe Battle Within\nOakbranch Tincture\nItem Level: 86\nQuality: 10\nImplicits: 0\n29% increased Attack Speed"
		local function speed(text)
			local item=new("Item"):Item(text);build.itemsTab:AddItem(item);build.itemsTab.slots["Flask 1"].selItemId=item.id;build.itemsTab.slots["Flask 1"].active=true
			build.configTab:BuildModList();runCallback("OnFrame");assert(not __mainObject__.promptMsg,__mainObject__.promptMsg);return build.calcsTab.calcsOutput.Speed
		end
		local before=speed(raw);local changed=raw;for _=1,10 do changed=require("Modules.CraftingUniqueQuality").apply(changed).itemText end
		local after=speed(changed);local withoutBaseline=speed((raw:gsub("Quality: 10","Quality: 20")))
		assert.is_true(after>before);assert.are.near(before,withoutBaseline,1e-8)
	end)
	it("scales newly rerolled tincture modifiers as base values",function()
		local raw="Item Class: Tinctures\nRarity: MAGIC\nPersevering Prismatic Tincture of Mastery\nPrismatic Tincture\nItem Level: 85\nQuality: 18\nImplicits: 1\n100% increased Elemental Damage with Melee Weapons\n26% reduced Mana Burn rate\n29% increased Melee Weapon Attack Speed"
		local result=require("Modules.CraftingSimulator").perform(raw,{method="alteration"},3);assert.is_true(result.state.tinctureBaseExplicit)
		local claw=new("Item"):Item("Rarity: Normal\nImperial Claw");build.itemsTab:AddItem(claw);build.itemsTab.slots["Weapon 1"].selItemId=claw.id;build.skillsTab:PasteSocketGroup("Viper Strike 20/0  1");build.skillsTab:ProcessSocketGroup(build.skillsTab.socketGroupList[1])
		local function speed(text) local item=new("Item"):Item(text);build.itemsTab:AddItem(item);build.itemsTab.slots["Flask 1"].selItemId=item.id;build.itemsTab.slots["Flask 1"].active=true;build.configTab:BuildModList();runCallback("OnFrame");assert(not __mainObject__.promptMsg,__mainObject__.promptMsg);return build.calcsTab.calcsOutput.Speed end
		local reference=result.itemText:gsub("\nTincture Values: Final",""):gsub("\nTincture Imported Quality: [^\n]+",""):gsub("\nTincture Imported Effect: [^\n]+",""):gsub("\nTincture Base Explicit: true","")
		assert.are.near(speed(reference),speed(result.itemText),1e-8)
		local withEffect=require("Modules.CraftingSimulator").perform(raw,{method="alteration"},11500000).itemText
		assert.matches("17%% increased effect",withEffect);assert.equal(17,new("Item"):Item(withEffect).tinctureData.effectInc)
		local baseReference=withEffect:gsub("\nTincture Values: Final",""):gsub("\nTincture Imported Quality: [^\n]+",""):gsub("\nTincture Imported Effect: [^\n]+",""):gsub("\nTincture Base Explicit: true","")
		assert.are.near(speed(baseReference),speed(withEffect),1e-8)
	end)
	it("scales a newly added tincture suffix without rescaling copied values",function()
		local common="Item Class: Tinctures\nRarity: MAGIC\nPrismatic Tincture\nItem Level: 85\nQuality: 18\nImplicits: 1\n100% increased Elemental Damage with Melee Weapons\n"
		local added=require("Modules.CraftingSimulator").perform(common.."26% reduced Mana Burn rate",{method="augmentation"},500000);assert.is_true(added.state.tinctureBaseSuffix)
		local claw=new("Item"):Item("Rarity: Normal\nImperial Claw");build.itemsTab:AddItem(claw);build.itemsTab.slots["Weapon 1"].selItemId=claw.id;build.skillsTab:PasteSocketGroup("Viper Strike 20/0  1");build.skillsTab:ProcessSocketGroup(build.skillsTab.socketGroupList[1])
		local function speed(text) local item=new("Item"):Item(text);build.itemsTab:AddItem(item);build.itemsTab.slots["Flask 1"].selItemId=item.id;build.itemsTab.slots["Flask 1"].active=true;build.configTab:BuildModList();runCallback("OnFrame");assert(not __mainObject__.promptMsg,__mainObject__.promptMsg);return build.calcsTab.calcsOutput.Speed end
		local reference=added.itemText:gsub("\nTincture Values: Final",""):gsub("\nTincture Imported Quality: [^\n]+",""):gsub("\nTincture Imported Effect: [^\n]+",""):gsub("\nTincture Base Suffix: true","")
		assert.are.near(speed(reference),speed(added.itemText),1e-8)
		local copied=common.."29% increased Melee Weapon Attack Speed";local withPrefix=require("Modules.CraftingSimulator").perform(copied,{method="augmentation"},3);assert.is_true(withPrefix.state.tinctureBasePrefix);assert.are.near(speed(copied),speed(withPrefix.itemText),1e-8)
	end)
	it("scales a rerolled tincture implicit as a base value",function()
		local raw="Item Class: Tinctures\nRarity: MAGIC\nPrismatic Tincture\nItem Level: 85\nQuality: 18\nImplicits: 1\n100% increased Elemental Damage with Melee Weapons\n26% reduced Mana Burn rate"
		local result=require("Modules.CraftingSimulator").perform(raw,{method="blessed"},5);assert.is_true(result.state.tinctureBaseImplicit)
		local claw=new("Item"):Item("Rarity: RARE\nTest Claw\nImperial Claw\nAdds 100 to 200 Fire Damage");build.itemsTab:AddItem(claw);build.itemsTab.slots["Weapon 1"].selItemId=claw.id;build.skillsTab:PasteSocketGroup("Viper Strike 20/0  1");build.skillsTab:ProcessSocketGroup(build.skillsTab.socketGroupList[1])
		local function dps(text) local item=new("Item"):Item(text);build.itemsTab:AddItem(item);build.itemsTab.slots["Flask 1"].selItemId=item.id;build.itemsTab.slots["Flask 1"].active=true;build.configTab:BuildModList();runCallback("OnFrame");assert(not __mainObject__.promptMsg,__mainObject__.promptMsg);return build.calcsTab.calcsOutput.TotalDPS end
		local reference=result.itemText:gsub("\nTincture Values: Final",""):gsub("\nTincture Imported Quality: [^\n]+",""):gsub("\nTincture Imported Effect: [^\n]+",""):gsub("\nTincture Base Implicit: true","")
		local withoutMarker=(result.itemText:gsub("\nTincture Base Implicit: true",""));local actual=dps(result.itemText);assert.are.near(dps(reference),actual,1e-8);assert.is_true(actual>dps(withoutMarker))
	end)
	it("deactivates a native tincture at zero mana and removes its drain",function()
		local tincture=new("Item"):Item("Rarity: Normal\nPrismatic Tincture")
		build.itemsTab:AddItem(tincture); build.itemsTab.slots["Flask 1"].selItemId=tincture.id
		build.itemsTab.slots["Flask 1"].active=true
		calculate()
		build.configTab.input.recoverySimulationAttacking=false
		build.configTab.input.customMods="+3000 to maximum Life\n+60% to Cold Resistance\nCannot Regenerate Mana"
		build.configTab.input.multiplierManaBurnStacks=99
		build.configTab:BuildModList(); runCallback("OnFrame")
		assert(not __mainObject__.promptMsg,__mainObject__.promptMsg)
		local trace=build.calcsTab.calcsEnv.player.recoverySimulationTrace
		local deactivated
		for _,event in ipairs(trace.rows) do
			if event.event:find("Tincture deactivated",1,true) then deactivated=event; break end
		end
		assert.is_truthy(deactivated)
		assert.is_true(deactivated.time > 0.7)
		assert.is_true(build.calcsTab.calcsOutput.RecoverySimulationSurvivalChance > 0)
	end)

	it("creates named scenarios using existing saved config sets",function()
		calculate()
		local original=build.configTab.activeConfigSetId
		local config=build.configTab:CreateEncounterConfigSet(1)
		assert.are.equal("Single heavy hit",config.title)
		assert.are.equal(true,config.input.recoverySimulationSingleHit)
		assert.are.equal("40",config.input.enemyColdDamage)
		assert.are.equal("20",build.configTab.configSets[original].input.enemyColdDamage)
		local xml={}; build.configTab:Save(xml)
		build.configTab:Load(xml)
		assert.are.equal("Single heavy hit",build.configTab.configSets[config.id].title)
		assert.are.equal(true,build.configTab.configSets[config.id].input.recoverySimulationSingleHit)
	end)

	it("compares identical saved configs with zero deltas and no live mutation",function()
		calculate()
		local tab=build.configTab
		local original=tab.activeConfigSetId
		local target=tab:NewConfigSet(nil,"Same scenario")
		target.input=copyTable(tab.input); target.placeholder=copyTable(tab.placeholder)
		target.customModsList=copyTable(tab.configSets[original].customModsList)
		target.input.recoverySimulationTrials=99; target.input.recoverySimulationWindow=300; target.input.recoverySimulationSeed=9
		table.insert(tab.configSetOrderList,target.id)
		tab.input.recoverySimulationCompareSet=target.id
		tab:BuildModList(); runCallback("OnFrame")
		assert(not __mainObject__.promptMsg,__mainObject__.promptMsg)
		local o=build.calcsTab.calcsOutput
		assert.are.near(0,o.RecoveryComparisonSurvivalDelta,1e-8)
		assert.are.near(0,o.RecoveryComparisonTimeDelta,1e-8)
		assert.are.near(0,o.RecoveryComparisonDamageDelta,1e-6)
		assert.are.equal(true,o.RecoveryComparisonReady)
		assert.are.equal(true,build.calcsTab:CheckFlag({haveOutput="RecoveryComparisonReady"}))
		assert.are.equal(true,tab.varControls.recoverySimulationCompareSet.enableDroppedWidth)
		assert.are.equal(original,tab.activeConfigSetId)
		assert.are.equal(target.id,tab.input.recoverySimulationCompareSet)
		assert.are.equal(99,target.input.recoverySimulationTrials)
		assert.are.equal(300,target.input.recoverySimulationWindow)
		assert.are.equal(9,target.input.recoverySimulationSeed)
	end)

	it("reduces native poison-window damage when mana prevents further attacks",function()
		local claw=new("Item"):Item("Rarity: Normal\nImperial Claw")
		build.itemsTab:AddItem(claw); build.itemsTab.slots["Weapon 1"].selItemId=claw.id
		build.skillsTab:PasteSocketGroup("Cobra Lash 20/0  1")
		build.skillsTab:ProcessSocketGroup(build.skillsTab.socketGroupList[1])
		calculate()
		build.configTab.input.customMods="+3000 to maximum Life\n+100 to maximum Mana\n+60% to Cold Resistance\n100% chance to Poison on Hit\nCannot Regenerate Mana\n+50 to Total Mana Cost of Skills"
		build.configTab.input.poisonDamageWindow=10
		build.configTab:BuildModList(); runCallback("OnFrame")
		assert(not __mainObject__.promptMsg,__mainObject__.promptMsg)
		local actor=build.calcsTab.calcsEnv.player
		local o=actor.output
		assert.is_true(#actor.mainSkill.recoveryPoisonProfiles > 0)
		assert.is_true(o.RecoverySimulationPoisonDPS > 0)
		assert.is_true(o.RecoverySimulationAttackUptime < 100)
		assert.is_true(o.RecoverySimulationPoisonDPS < o.PoisonWindowAverageDPS)
	end)

	it("renders the timeline graph and configuration report through native Calcs",function()
		calculate()
		local actor=build.calcsTab.calcsEnv.player
		assert.is_true(#actor.recoverySimulationTrace.points > 1)
		assert.is_true(#actor.breakdown.RecoverySimulationTimeline.rowList > 1)
		local control=build.calcsTab.controls.breakdown
		control:DrawEncounterTimeline(0,0,{width=730,timeline=actor.recoverySimulationTrace})
		control:SetBreakdownData({{breakdown="RecoverySimulationTimeline"},x=20,y=20,width=120},true)
		assert.are.equal("TIMELINE",control.sectionList[2].type)
		assert.are.equal("TABLE",control.sectionList[3].type)
		for _,row in ipairs(control.sectionList[3].rowList) do assert.are_not.equals("Sample",row.event) end
		assert.are.equal(true,control.isTimeline)
		control:Draw({x=0,y=0,width=1920,height=1080})
		local drawEnv,plotEnv=getfenv(control.Draw),getfenv(control.DrawEncounterTimeline)
		local savedDrawControls,savedLayer,savedQuad=control.DrawControls,rawget(drawEnv,"SetDrawLayer"),rawget(plotEnv,"DrawImageQuad")
		local layer,plotted=0,false
		control.DrawControls=function() drawEnv.SetDrawLayer(nil,0) end
		drawEnv.SetDrawLayer=function(_,subLayer) layer=subLayer or 0 end
		plotEnv.DrawImageQuad=function(...) assert.are.equal(10,layer); plotted=true end
		local ok,err=pcall(function() control:Draw({x=0,y=0,width=1920,height=1080}) end)
		control.DrawControls,drawEnv.SetDrawLayer,plotEnv.DrawImageQuad=savedDrawControls,savedLayer,savedQuad
		assert(ok,err); assert.are.equal(true,plotted)
		build.configTab:ShowEncounterSimulation()
		assert.are.equal("Encounter Simulation",build.configTab.controls.search.buf)
		assert.are.equal(true,build.configTab.varControls.simulateRecovery:IsShown())
		assert.are.equal(false,build.configTab.varControls.enemyCritChance:IsShown())
		build.calcsTab:ShowRecoverySimulation()
		runCallback("OnFrame"); assert(not __mainObject__.promptMsg,__mainObject__.promptMsg)
		for _,view in ipairs({"CONFIG","CALCS"}) do build.viewMode=view; runCallback("OnFrame"); assert(not __mainObject__.promptMsg,__mainObject__.promptMsg) end
	end)

	it("parses local hit-charge and end-recovery flask properties",function()
		local flask=new("Item"):Item("Rarity: Magic\nFlagellant's Granite Flask\nGranite Flask\nGain 3 Charges when you are Hit by an Enemy")
		assert.are.equal(3,flask.flaskData.chargesWhenHit)
		local karui=new("Item"):Item("Rarity: Unique\nBlood of the Karui\nSanctified Life Flask\nRecover Full Life at the end of the Effect")
		assert.are.equal(true,karui.flaskData.finishLife)
	end)
	it("finishes deferred recovery with identical trials and an isolated calculator cache",function()
		calculate()
		local tab=build.calcsTab;local tasks=require("Modules.RecoveryTasks")
		local expected=copyTable(tab.calcsEnv.player.recoverySimulationResults)
		local expectedTrace=copyTable(tab.calcsEnv.player.recoverySimulationTrace.points)
		wipeGlobalCache();tab:BuildOutput(true)
		assert.is_true(tab.calcsOutput.RecoverySimulationPending)
		assert.is_nil(tab.calcsEnv.player.recoverySimulationResults)
		assert.is_true(require("Modules.EncounterReport").capture(build).calculationPending)
		local originalCache=GlobalCache;local calculator=GlobalCache.cachedData.CALCULATOR
		local steps=0
		while tab.recoveryJob do
			tasks.tick(tab,0);steps=steps+1;assert.is_true(steps < 1000)
			assert.are.equal(originalCache,GlobalCache);assert.are.equal(calculator,GlobalCache.cachedData.CALCULATOR)
		end
		assert.is_true(steps > 2);assert.is_nil(tab.calcsOutput.RecoverySimulationPending)
		assert.are.same(expected,tab.calcsEnv.player.recoverySimulationResults)
		assert.are.same(expectedTrace,tab.calcsEnv.player.recoverySimulationTrace.points)
	end)
	it("preserves timed tincture trials when projected calculations yield",function()
		local tincture=new("Item"):Item("Rarity: Normal\nPrismatic Tincture")
		build.itemsTab:AddItem(tincture);build.itemsTab.slots["Flask 1"].selItemId=tincture.id;build.itemsTab.slots["Flask 1"].active=true
		calculate()
		local tab=build.calcsTab;local tasks=require("Modules.RecoveryTasks")
		local expected=copyTable(tab.calcsEnv.player.recoverySimulationResults)
		local expectedTrace=copyTable(tab.calcsEnv.player.recoverySimulationTrace.points)
		assert.is_truthy(expected)
		tab:BuildOutput(true);local originalCache=GlobalCache;local calculator=GlobalCache.cachedData.CALCULATOR
		local perform=tab.calcs.perform;local projections=0
		tab.calcs.perform=function(env,...) if env.recoveryProjection and env.recoveryCheckpoint then projections=projections+1 end;return perform(env,...) end
		local ok,message=pcall(function()
			local steps=0;while tab.recoveryJob do tasks.tick(tab,0);steps=steps+1;assert.is_true(steps<5000);assert.are.equal(originalCache,GlobalCache);assert.are.equal(calculator,GlobalCache.cachedData.CALCULATOR) end
			assert.is_true(steps>2);assert.is_true(projections>0);assert.is_falsy(tab.calcsOutput.RecoverySimulationUnsupported)
		end)
		tab.calcs.perform=perform;assert.is_true(ok,message)
		assert.are.same(expected,tab.calcsEnv.player.recoverySimulationResults)
		assert.are.same(expectedTrace,tab.calcsEnv.player.recoverySimulationTrace.points)
	end)
	it("replaces pending recovery on edits and keeps captured level and configuration",function()
		calculate()
		local tab=build.calcsTab;local tasks=require("Modules.RecoveryTasks")
		local expected=copyTable(tab.calcsEnv.player.recoverySimulationResults)
		tab:BuildOutput(true);local previous=tab.recoveryJob;tasks.tick(tab,0)
		tab:BuildOutput(true);assert.are_not.equal(previous,tab.recoveryJob)
		local level=build.characterLevel;build.characterLevel=100
		build.configTab.input.enemyColdDamage="9999999"
		local steps=0;while tab.recoveryJob do tasks.tick(tab,0);steps=steps+1;assert.is_true(steps < 1000) end
		assert.are.same(expected,tab.calcsEnv.player.recoverySimulationResults)
		assert.is_nil(previous.current.player.recoverySimulationResults)
		build.characterLevel=level
	end)
	it("can replace a recovery job while a tincture projection is suspended",function()
		local tincture=new("Item"):Item("Rarity: Normal\nPrismatic Tincture")
		build.itemsTab:AddItem(tincture);build.itemsTab.slots["Flask 1"].selItemId=tincture.id;build.itemsTab.slots["Flask 1"].active=true
		calculate();local tab=build.calcsTab;local tasks=require("Modules.RecoveryTasks")
		local expected=copyTable(tab.calcsEnv.player.recoverySimulationResults);local perform=tab.calcs.perform;local entered=false
		tab:BuildOutput(true);local cancelled=tab.recoveryJob;local cache=GlobalCache
		tab.calcs.perform=function(env,...) if env.recoveryProjection and env.recoveryCheckpoint then entered=true;env.recoveryCheckpoint() end;return perform(env,...) end
		local ok,message=pcall(function()
			local steps=0;while not entered and tab.recoveryJob do tasks.tick(tab,0);steps=steps+1;assert.is_true(steps<5000);assert.are.equal(cache,GlobalCache) end
			assert.is_true(entered);assert.are.equal(cancelled,tab.recoveryJob)
		end)
		tab.calcs.perform=perform;assert.is_true(ok,message)
		tab:BuildOutput(true);assert.are_not.equal(cancelled,tab.recoveryJob)
		local steps=0;while tab.recoveryJob do tasks.tick(tab,0);steps=steps+1;assert.is_true(steps<5000);assert.are.equal(cache,GlobalCache) end
		assert.are.same(expected,tab.calcsEnv.player.recoverySimulationResults)
	end)

	it("keeps paired configuration comparisons identical when recovery yields",function()
		calculate();local config=build.configTab
		local target=config:NewConfigSet(nil,"Background comparison")
		target.input=copyTable(config.input);target.placeholder=copyTable(config.placeholder)
		target.customModsList=copyTable(config.configSets[config.activeConfigSetId].customModsList)
		table.insert(config.configSetOrderList,target.id)
		config.input.recoverySimulationCompareSet=target.id;config:BuildModList()
		build.calcsTab:BuildOutput()
		local expected=copyTable(build.calcsTab.calcsEnv.player.recoveryComparisonResults)
		assert.is_true(build.calcsTab.calcsOutput.RecoveryComparisonReady)
		build.calcsTab:BuildOutput(true)
		local steps=0;local cache=GlobalCache
		while build.calcsTab.recoveryJob do
			require("Modules.RecoveryTasks").tick(build.calcsTab,0);steps=steps+1;assert.is_true(steps<2000)
			assert.are.equal(cache,GlobalCache)
		end
		assert.is_true(build.calcsTab.calcsOutput.RecoveryComparisonReady)
		assert.are.same(expected,build.calcsTab.calcsEnv.player.recoveryComparisonResults)
	end)

	it("restores calculator caches and clears pending results after a background error",function()
		calculate();local tab=build.calcsTab;local tasks=require("Modules.RecoveryTasks")
		tab:BuildOutput(true)
		local original=tab.calcs.recoveryOverTime;local cache=GlobalCache
		tab.calcs.recoveryOverTime=function(env)
			GlobalCache.cachedData.CALCULATOR.failureSentinel=true
			env.recoveryCheckpoint();error("deliberate recovery failure")
		end
		local ok,message=pcall(function() tasks.tick(tab,0);tasks.tick(tab,0) end)
		tab.calcs.recoveryOverTime=original
		assert(ok,message);assert.are.equal(cache,GlobalCache)
		assert.is_nil(GlobalCache.cachedData.CALCULATOR.failureSentinel)
		assert.is_nil(tab.recoveryJob);assert.is_nil(tab.calcsOutput.RecoverySimulationPending)
		assert.is_true(tab.calcsOutput.RecoverySimulationUnsupported)
		assert.is_nil(tab.calcsEnv.player.recoverySimulationResults)
	end)
	it("yields node power work within a short frame budget",function()
		local nodes={};for id=1,50 do nodes[id]={id=id,modKey="same",power={},pathDist=1} end
		local control=setmetatable({powerStat={stat="Life"},mainEnv={grantedPassives={}},
			build={spec={nodes=nodes,tree={clusterNodeMap={}},masterySelections={}}}}, {__index=common.classes.CalcsTab})
		local evaluated=0
		control.GetMiscCalculator=function() return function(override)
			evaluated=evaluated+1;local node=next(override.addNodes);return {Life=100+node.id}
		end,{Life=100} end
		local original=_G.GetTime;local clock=0;_G.GetTime=function() clock=clock+5;return clock end
		local thread=coroutine.create(function() control:PowerBuilder() end)
		local first,firstError=coroutine.resume(thread);local second,secondError=coroutine.resume(thread)
		_G.GetTime=original
		assert(first,firstError);assert(second,secondError)
		assert.are.equal("suspended",coroutine.status(thread))
		assert.is_true(evaluated>0 and evaluated<50)
	end)

end)
