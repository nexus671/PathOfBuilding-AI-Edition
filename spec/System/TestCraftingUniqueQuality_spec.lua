describe("Unique item quality",function()
	local quality=require("Modules.CraftingUniqueQuality")
	local shield="Rarity: UNIQUE\nThe Surrender\nEzomyte Tower Shield\nItem Level: 86\nQuality: 12\nSockets: R-G B\nImplicits: 1\n+5% Chance to Block Attack Damage\n+100 to maximum Life\n+1500 to Armour"
	local weapon="Rarity: UNIQUE\nThe Saviour\nLegion Sword\nItem Level: 86\nQuality: 0\nSockets: R-G-B\n+100% increased Physical Damage"
	before_each(function() newBuild() end)
	it("adds natural white sockets to unique items with the Jeweller Omen",function()
		local sim=require("Modules.CraftingSimulator")
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B\n+40% to Fire Resistance"
		local result=sim.perform(raw,{method="omen_jeweller"},1)
		assert.equal(raw:gsub("Sockets: R%-G B","Sockets: R-G B W"),result.itemText)
		assert.equal(1,result.components["Metadata/Items/Currency/AncestralOmenOnJewellersMakeFullSockets"])
		assert.equal(1,result.components["Metadata/Items/Currency/CurrencyRerollSocketNumbers"])
		local calculated=sim.calculate(raw,{method="omen_jeweller"},{},nil,{requirements={exactSockets=4}})
		assert.equal(100,calculated.successChance)
		local run=sim.simulate(raw,{steps={{method="omen_jeweller"}},targets={},requirements={exactSockets=4}},{trials=1,maxActions=1})
		assert.is_true(run.sampleSuccess);assert.equal(result.itemText,run.sampleItem)
		local found=false;for _,entry in ipairs(sim.catalog(raw,"omen",50).uniqueActions) do if entry.method=="omen_jeweller" then found=entry.available end end;assert.is_true(found)
		assert.has_error(function() quality.socketCount(raw,2,"omen_jeweller") end)
		assert.has_error(function() quality.socketCount(raw,4,"unknown") end)
		assert.has_error(function() sim.perform(raw.."\nCorrupted",{method="omen_jeweller"},1) end)
		assert.has_error(function() sim.perform(result.itemText,{method="omen_jeweller"},1) end)
		assert.has_error(function() sim.perform(raw.."\nSockets cannot be modified",{method="omen_jeweller"},1) end)
		local low=raw:gsub("Item Level: 86","Item Level: 25"):gsub("Sockets: R%-G B","Sockets: R-G")
		assert.matches("Sockets: R%-G W W",sim.perform(low,{method="omen_jeweller"},1).itemText)
		local project={id="unique-omen",title="Omen",slot="Helmet",startingItem=raw,goals={},steps={}}
		local store=build.savers.CraftingProjects;store:Upsert(project)
		local recovery=require("Modules.PlanningRecovery").clean("uniqueQuality",{plan={kind="uniqueQuality",project=project,itemText=result.itemText,history={raw},actions={"omen_jeweller"},redo={}}}).plan
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project,nil,recovery)
		assert.is_false(control.omenJeweller:IsEnabled());assert.is_true(control.undo:IsEnabled());control.undo:Click();assert.is_true(control.omenJeweller:IsEnabled());assert.is_true(control.redo:IsEnabled());control.redo:Click();assert.is_false(control.omenJeweller:IsEnabled())
		assert.is_true(control.recipe:IsEnabled());control.recipe:Click()
		assert.equal("omen_jeweller",store.projects[1].nativeRecipe.steps[1].method);control.guide:Click()
		assert.equal("omen_jeweller",store.projects[1].steps[1].uniqueCraft.method)
		local filters=require("Modules.LootFilters");local profile=filters.profile("unique-omen","Omen")
		local rules=filters.generate(build,profile);local names={};for _,rule in ipairs(rules) do names[rule.title]=true end
		assert.is_true(names["Omen of the Jeweller"]);assert.is_true(names["Jeweller's Orb"]);main.popups={}
	end)

	it("keeps a unique Omen and following bench link together in the guide",function()
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B\n+40% to Fire Resistance"
		local project={id="omen-link",title="Omen link",slot="Helmet",startingItem=raw,goals={},steps={}}
		local store=build.savers.CraftingProjects;store:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		control.omenJeweller:Click();assert.is_true(control.benchLink:IsEnabled());control.benchLink:Click()
		control.recipe:Click();control.guide:Click();local saved=store.projects[1]
		assert.equal("omen_jeweller",saved.steps[1].uniqueCraft.method);assert.equal("socket_bench",saved.steps[2].uniqueCraft.method)
		assert.matches("5 Orbs of Fusing",saved.steps[2].action,1,true);assert.equal(4,saved.nativeRecipe.requirements.exactSockets)
		local filters=require("Modules.LootFilters");local rules=filters.generate(build,filters.profile("omen-link","Omen link"));local names={}
		for _,rule in ipairs(rules) do if rule.origin=="craft:omen-link" then names[rule.title]=true end end
		for _,name in ipairs({"Omen of the Jeweller","Jeweller's Orb","Orb of Fusing"}) do assert.is_true(names[name]) end
		main.popups={}
	end)

	it("samples Divine rolls only for complete unambiguous unique range forms",function()
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B\n+(30-50) to Evasion Rating\n+10% to Item Rarity\n+(30-40)% to all Elemental Resistances\nReflects 4 Physical Damage to Melee Attackers"
		assert.is_nil(quality.divineReason(raw));local changed,values={},{}
		for seed=1,20 do
			local rollSeed=seed*104729;local result=quality.divine(raw,rollSeed);assert.equal(result.itemText,quality.divine(raw,rollSeed).itemText);assert.equal(1,result.components.divine)
			local item=quality.inspect(result.itemText);assert.equal("Goldrim",item.title);assert.equal(4,#item.explicitModLines);assert.equal(3,#item.sockets)
			assert.is_truthy(result.itemText:find("+10% to Item Rarity",1,true));changed[result.itemText]=true;values[item.armourData.Evasion]=true
		end
		local count=0;for _ in pairs(changed) do count=count+1 end;assert.is_true(count>1);count=0;for _ in pairs(values) do count=count+1 end;assert.is_true(count>1)
		assert.has_error(function() quality.divine(raw.."\nCorrupted",1) end)
		assert.has_error(function() quality.divine(raw:gsub("Reflects 4 Physical Damage to Melee Attackers",""),1) end)
		local copied=raw:gsub("%+%(30%-50%) to Evasion Rating","+40 to Evasion Rating"):gsub("%+%(30%-40%)%% to all Elemental Resistances","+35%% to all Elemental Resistances")
		assert.is_nil(quality.divineReason(copied));local converted=quality.divine(copied,104729)
		assert.is_truthy(converted.itemText:find("+(30-50) to Evasion Rating",1,true));assert.is_truthy(converted.itemText:find("+(30-40)% to all Elemental Resistances",1,true))
		assert.is_nil(quality.divineReason(converted.itemText));assert.equal(3,#quality.inspect(converted.itemText).sockets)
		local advanced=raw:gsub("%+%(30%-50%) to Evasion Rating","+40(30-50) to Evasion Rating"):gsub("%+%(30%-40%)%% to all Elemental Resistances","+35(30-40)%% to all Elemental Resistances")
		assert.is_nil(quality.divineReason(advanced));local advancedResult=quality.divine(advanced,104729);assert.is_nil(quality.divineReason(advancedResult.itemText))
		assert.has_error(function() quality.divine(copied:gsub("+40 to Evasion Rating","+51 to Evasion Rating",1),1) end)
		assert.has_error(function() quality.divine(raw,0) end)
		local variant=raw:gsub("Goldrim","Heatshiver"):gsub("Leather Cap","Leather Hood");assert.is_truthy(quality.divineReason(variant))
		local multi;for _,group in pairs(data.uniques) do for _,entry in ipairs(group) do if entry:match("^%s*Dreadarc[\r\n]") then multi=entry end end end
		assert.is_truthy(multi);local multiple="Rarity: UNIQUE\n"..multi.."\nItem Level: 86";assert.is_nil(quality.divineReason(multiple))
		local result=quality.divine(multiple,104729);assert.is_nil(quality.divineReason(result.itemText));assert.is_truthy(quality.divine(result.itemText,209458))
	end)

	it("identifies complete copied unique variants before Divine rolls",function()
		local current="Rarity: UNIQUE\nThe Blood Reaper\nHeadsman Axe\nItem Level: 86\n190% increased Physical Damage\n+100 to maximum Life\nRegenerate 20 Life per second\n1% of Physical Attack Damage Leeched as Life\n50% increased Mana Cost of Skills\n50% chance to cause Bleeding on Hit"
		local older=current:gsub("190%% increased Physical Damage","110%% increased Physical Damage"):gsub("Regenerate 20 Life per second","Regenerate 10 Life per second")
		for _,raw in ipairs({current,older}) do
			assert.is_nil(quality.divineReason(raw));local options=quality.divineOptions(raw);assert.equal(1,#options)
			local result=quality.divine(raw,104729);assert.is_nil(quality.divineReason(result.itemText));assert.is_truthy(quality.divine(result.itemText,209458))
		end

		local sim=require("Modules.CraftingSimulator");local catalog=sim.catalog(current,"divine",20);assert.is_true(catalog.uniqueActions[1].available)
		local goal={uniqueModifier={line="(180-200)% increased Physical Damage",minValue=200}};local recipe={rarity="UNIQUE",steps={{method="divine",maxAttempts=10,untilRequirements=goal}},targets={},requirements=goal}
		local run=sim.simulate(current,recipe,{trials=5,maxActions=10,seed=123});assert.equal(5,run.trials)
		assert.is_truthy(quality.divineReason(current:gsub("Regenerate 20 Life per second", "")))
		local ambiguous="Rarity: UNIQUE\nAtziri's Splendour\nSacrificial Garb\nItem Level: 86\nImplicits: 1\n+1 to Level of all Vaal Skill Gems\n400% increased Armour\n+95 to maximum Life\n+22% to all Elemental Resistances\nGain 100 Life per Enemy Killed\nGain 100 Mana per Enemy Killed"
		assert.equal("This item matches multiple unique variants",quality.divineReason(ambiguous))

	end)

	it("retains variant identity through overlapping multi-range Divine rolls",function()
		local raw="Rarity: UNIQUE\nAtziri's Disfavour\nVaal Axe\nItem Level: 86\n+2 to Level of Socketed Support Gems\nAdds 210 to 260 Physical Damage\n14% increased Attack Speed\n25% chance to cause Bleeding on Hit\n+0.2 metres to Weapon Range"
		assert.is_nil(quality.divineReason(raw));local advanced=raw:gsub("Adds 210 to 260 Physical Damage","Adds 220(205-220) to 270(250-270) Physical Damage")
		assert.is_nil(quality.divineReason(advanced));local result=quality.divine(advanced,104729);assert.is_nil(quality.divineReason(result.itemText));assert.is_truthy(quality.divine(result.itemText,209458))
		local overlap="Rarity: UNIQUE\nDeath's Hand\nKarui Sceptre\nItem Level: 86\nImplicits: 1\n26% increased Elemental Damage\nAdds 40 to 100 Physical Damage\n35% increased Critical Strike Chance\n30% chance to gain a Power Charge when you Stun\nGain Unholy Might for 4 seconds on Critical Strike"
		assert.equal("This item matches multiple unique variants",quality.divineReason(overlap))
		local identified=overlap:gsub("Adds 40 to 100 Physical Damage","Adds 40(35-46) to 100(85-128) Physical Damage")
		assert.is_nil(quality.divineReason(identified));assert.is_truthy(quality.divine(identified,104729))

	end)

	it("plans unique jewellery Divine rolls without inventing quality crafts",function()
		local raw="Rarity: UNIQUE\nAndvarius\nGold Ring\nItem Level: 86\nImplicits: 1\n+10% to Item Rarity\n+10 to Dexterity\n+60% to Item Rarity\n-20% to all Elemental Resistances"
		local item,info=quality.inspect(raw);assert.equal("Ring",item.type);assert.is_false(info.qualitySupported);assert.is_false(info.available)
		assert.is_nil(quality.divineReason(raw));local result=quality.divine(raw,104729);assert.is_nil(quality.divineReason(result.itemText));assert.is_truthy(quality.divine(result.itemText,209458))
		local catalog=quality.catalog(raw,"",50);assert.equal(1,#catalog.uniqueActions);assert.equal("divine",catalog.uniqueActions[1].method);assert.is_true(catalog.uniqueActions[1].available)
		assert.has_error(function() quality.apply(raw) end);assert.has_error(function() quality.matches(raw,{minQuality=1}) end)
		local scaled=raw:gsub("Item Level: 86","Item Level: 86\nCatalyst: Prismatic\nCatalystQuality: 20");assert.is_truthy(quality.divineReason(scaled));local _,scaledInfo=quality.inspect(scaled);assert.equal(20,scaledInfo.quality);assert.equal(20,quality.catalog(scaled,"divine",10).quality.value);assert.has_error(function() quality.divine(scaled,1) end)
		local defaultQuality=raw:gsub("Item Level: 86","Item Level: 86\nCatalyst: Prismatic");local _,defaultInfo=quality.inspect(defaultQuality);assert.equal(20,defaultInfo.quality);assert.is_truthy(quality.divineReason(defaultQuality));assert.has_error(function() quality.divine(defaultQuality,1) end)
		local zeroQuality=defaultQuality:gsub("Catalyst: Prismatic","Catalyst: Prismatic\nCatalystQuality: 0");local _,zeroInfo=quality.inspect(zeroQuality);assert.equal(0,zeroInfo.quality);assert.is_nil(quality.divineReason(zeroQuality))
		local copiedQuality=raw:gsub("Item Level: 86","Item Level: 86\nQuality (Resistance Modifiers): +20%%");local _,copiedInfo=quality.inspect(copiedQuality);assert.equal(20,copiedInfo.quality);assert.is_truthy(quality.divineReason(copiedQuality))
		local unrecognized=defaultQuality:gsub("Catalyst: Prismatic","Catalyst: Unknown");assert.matches("Unrecognized jewellery catalyst",quality.divineReason(unrecognized))

		local otherItems={
			"Rarity: UNIQUE\nBloodsoaked Medallion\nAmber Amulet\nItem Level: 86\nImplicits: 1\n+25 to Strength\n40% increased Global Critical Strike Chance\n+60 to maximum Life\n+20% to Chaos Resistance\nEvery 10 seconds:\nGain 2% of Life per Enemy Hit with Attacks for 5 seconds\nGain 5% of Life per Enemy Killed for 5 seconds",
			"Rarity: UNIQUE\nThe Burden of Truth\nCrystal Belt\nItem Level: 86\nImplicits: 1\n+80 to maximum Energy Shield\n33% of Non-Chaos Damage taken bypasses Energy Shield\n35% increased Life Recovery from Flasks\n33% of Chaos Damage taken does not bypass Energy Shield\nGain 7% of Maximum Life as Extra Maximum Energy Shield\nSupreme Decadence",
		}
		for _,other in ipairs(otherItems) do assert.is_nil(quality.divineReason(other));local rolled=quality.divine(other,104729);assert.is_nil(quality.divineReason(rolled.itemText));assert.is_truthy(quality.divine(rolled.itemText,209458)) end
		local goal={uniqueModifier={line="+(50-70)% to Item Rarity",minValue=70}};local recipe={rarity="UNIQUE",steps={{method="divine",maxAttempts=10,untilRequirements=goal}},targets={},requirements=goal}
		local run=require("Modules.CraftingSimulator").simulate(raw,recipe,{trials=5,maxActions=10,seed=123});assert.equal(5,run.trials)
	end)

	it("preserves copied armour base rolls when unique stats or quality change",function()
		local raw="Item Class: Helmets\nRarity: Unique\nGoldrim\nLeather Cap\n--------\nEvasion Rating: 67\n--------\nItem Level: 86\n--------\n+40 to Evasion Rating\n+10% to Item Rarity\n+35% to all Elemental Resistances\nReflects 4 Physical Damage to Melee Attackers"
		local before=quality.inspect(raw);local baseline=before.armourData.EvasionBasePercentile;assert.is_truthy(baseline)
		local values={};for seed=1,20 do local result=quality.divine(raw,seed*104729);local item=quality.inspect(result.itemText);assert.equal(baseline,item.armourData.EvasionBasePercentile);values[item.armourData.Evasion]=true;assert.is_truthy(result.itemText:find("EvasionBasePercentile:",1,true));assert.equal(4,#item.explicitModLines);assert.is_nil(quality.divineReason(result.itemText));assert.is_truthy(quality.divine(result.itemText,seed*130363)) end
		local distinct=0;for _ in pairs(values) do distinct=distinct+1 end;assert.is_true(distinct>1)
		local raised=quality.apply(raw);local item=quality.inspect(raised.itemText);assert.equal(baseline,item.armourData.EvasionBasePercentile);assert.equal(4,#item.explicitModLines);assert.is_nil(quality.divineReason(raised.itemText))
		local corrupted=raw.."\nCorrupted";local corruptedBefore=quality.inspect(corrupted);local tainted=quality.taintedQuality(corrupted,104729);item=quality.inspect(tainted.itemText);assert.equal(corruptedBefore.armourData.EvasionBasePercentile,item.armourData.EvasionBasePercentile);assert.equal(4,#item.explicitModLines)
		local windows=raw:gsub("\n","\r\n");local winResult=quality.divine(windows,104729);assert.is_truthy(winResult.itemText:find("\r\nEvasionBasePercentile:",1,true));assert.is_nil(quality.divineReason(winResult.itemText))
	end)

	it("exposes unique Divine previews, simulations and resource guides",function()
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B\n+(30-50) to Evasion Rating\n+10% to Item Rarity\n+(30-40)% to all Elemental Resistances\nReflects 4 Physical Damage to Melee Attackers"
		local sim=require("Modules.CraftingSimulator");local result=sim.perform(raw,{method="divine"},12);assert.equal(quality.divine(raw,12).itemText,result.itemText)
		local warned=false;for _,entry in ipairs(result.warnings) do if entry.code=="unique_divine_estimate" then warned=true end end;assert.is_true(warned)
		local catalog=sim.catalog(raw,"divine",20);assert.equal(1,#catalog.uniqueActions);assert.is_true(catalog.uniqueActions[1].available);assert.is_false(catalog.uniqueActions[1].deterministic)
		local recipe={steps={{method="divine",maxAttempts=5,untilRequirements={nativeStats={Evasion=60}}}},targets={},requirements={nativeStats={Evasion=60}}}
		local run=sim.simulate(raw,recipe,{trials=5,maxActions=5,seed=123,forceFirstAction=true});assert.is_true(run.sampled);assert.equal(5,run.trials)
		local calc=sim.calculate(raw,{method="divine"},{},nil,{trials=5,requirements={nativeStats={Evasion=60}}});assert.is_true(calc.sampled)
		local project={id="divine-unique",title="Divine",slot="Helmet",startingItem=raw,goals={},steps={catalog.uniqueActions[1].guideStep}}
		local store=build.savers.CraftingProjects;store:Upsert(project);local filters=require("Modules.LootFilters");local rules=filters.generate(build,filters.profile("divine-filter","Divine"));local found=false
		for _,rule in ipairs(rules) do if rule.origin=="craft:"..project.id and rule.title=="Divine Orb" then found=true end end;assert.is_true(found)
	end)

	it("rerolls and targets independent values on multi-range unique modifiers",function()
		local template;for _,group in pairs(data.uniques) do for _,entry in ipairs(group) do if entry:match("^%s*Dreadarc[\r\n]") then template=entry end end end
		assert.is_truthy(template);local raw="Rarity: UNIQUE\n"..template.."\nItem Level: 86"
		local copied=raw:gsub("Adds %(5%-15%) to %(20%-25%) Physical Damage","Adds 9 to 22 Physical Damage"):gsub("Adds %(5%-15%) to %(20%-25%) Fire Damage","Adds 12 to 21 Fire Damage")
		local options=quality.divineOptions(copied);assert.is_truthy(options);local parts={}
		for _,option in ipairs(options) do if option.line=="Adds (5-15) to (20-25) Physical Damage" then parts[option.component]=option end end
		assert.equal(9,parts[1].current);assert.equal(22,parts[2].current);assert.equal(2,parts[2].components)
		local goal={uniqueModifier={line=parts[2].line,component=2,minValue=23}};assert.is_false(quality.matches(copied,goal));goal.uniqueModifier.minValue=22;assert.is_true(quality.matches(copied,goal));goal.uniqueModifier.component=3;assert.has_error(function() quality.matches(copied,goal) end)
		local pairsSeen={};for seed=1,20 do
			local result=quality.divine(copied,seed*104729);local after=quality.divineOptions(result.itemText);assert.is_truthy(after)
			local first,second;for _,option in ipairs(after) do if option.line==parts[1].line then if option.component==1 then first=option.current else second=option.current end end end
			assert.is_true(first>=5 and first<=15 and second>=20 and second<=25);pairsSeen[first..":"..second]=true
			local item=quality.inspect(result.itemText);assert.equal(item.base.weapon.PhysicalMin+first,item.weaponData[1].PhysicalMin);assert.equal(item.base.weapon.PhysicalMax+second,item.weaponData[1].PhysicalMax)
			assert.is_truthy(quality.divine(result.itemText,seed*130363))
		end
		local count=0;for _ in pairs(pairsSeen) do count=count+1 end;assert.is_true(count>2)
	end)

	it("targets a specific unique modifier roll",function()
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B\n+40 to Evasion Rating\n+10% to Item Rarity\n+35% to all Elemental Resistances\nReflects 4 Physical Damage to Melee Attackers"
		local options=quality.divineOptions(raw);assert.equal(2,#options);local target
		for _,entry in ipairs(options) do if entry.line:find("Elemental Resistances",1,true) then target=entry end end
		assert.equal(30,target.min);assert.equal(40,target.max);assert.equal(35,target.current)
		local requirement={uniqueModifier={line=target.line,minValue=36}}
		assert.is_false(quality.matches(raw,requirement));requirement.uniqueModifier.minValue=35;assert.is_true(quality.matches(raw,requirement));requirement.uniqueModifier.minValue=41;assert.has_error(function() quality.matches(raw,requirement) end)
		assert.is_true(quality.matches(raw,{uniqueModifier={line=target.line,maxValue=35}}));assert.is_false(quality.matches(raw,{uniqueModifier={line=target.line,maxValue=34}}));assert.has_error(function() quality.matches(raw,{uniqueModifier={line=target.line,minValue=30,maxValue=40}}) end)
		requirement.uniqueModifier.minValue=40;local recipe={rarity="UNIQUE",steps={{method="divine",maxAttempts=30,untilRequirements=copyTable(requirement)}},targets={},requirements=requirement}
		local sim=require("Modules.CraftingSimulator");local result=sim.simulate(raw,recipe,{trials=10,maxActions=30,seed=123});assert.is_true(result.sampled);assert.is_true(result.successes>0)
		local calculated=sim.calculate(raw,{method="divine"},{},nil,{trials=5,requirements=requirement});assert.is_true(calculated.sampled)
		local invalid=copyTable(recipe);invalid.rarity=nil;assert.has_error(function() sim.validateRecipe(invalid) end)
	end)

	it("handles signed unique modifier ranges and copied negative rolls",function()
		local template;for _,group in pairs(data.uniques) do for _,entry in ipairs(group) do if entry:match("^%s*Saqawal's Talons[\r\n]") then template=entry end end end
		assert.is_truthy(template);local raw="Rarity: UNIQUE\n"..template.."\nItem Level: 86"
		local options=quality.divineOptions(raw);assert.is_truthy(options);local target;for _,entry in ipairs(options) do if entry.line:find("Avian's Flight Duration",1,true) then target=entry end end
		assert.is_truthy(target);assert.equal(-2,target.min);assert.equal(2,target.max);assert.equal(0,target.current)
		local goal={uniqueModifier={line=target.line,minValue=-1}};assert.is_true(quality.matches(raw,goal));goal.uniqueModifier.minValue=1;assert.is_false(quality.matches(raw,goal))
		local copied=raw:gsub("%(100%-150%)%% increased Armour and Evasion","125%% increased Armour and Evasion"):gsub("%(20%-30%)%% increased Movement Speed","25%% increased Movement Speed"):gsub("%+%(%-2%-2%) seconds to Avian's Flight Duration","-1 seconds to Avian's Flight Duration")
		local copiedOptions=quality.divineOptions(copied);assert.is_truthy(copiedOptions);for _,entry in ipairs(copiedOptions) do if entry.line==target.line then assert.equal(-1,entry.current) end end
		local result=quality.divine(copied,104729);assert.is_nil(quality.divineReason(result.itemText))
	end)

	it("previews and plans supported unique Divine rolls",function()
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B\n+(30-50) to Evasion Rating\n+10% to Item Rarity\n+(30-40)% to all Elemental Resistances\nReflects 4 Physical Damage to Melee Attackers"
		local project={id="divine-ui",title="Divine",slot="Helmet",startingItem=raw,goals={},steps={}}
		local store=build.savers.CraftingProjects;store:Upsert(project);local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		assert.is_true(control.divine:IsEnabled());control.divine:Click();local popup=main.popups[1].controls
		popup.stat:SelByValue("Evasion","val");popup.target:SetText("100");popup.attempts:SetText("250");assert.is_true(popup.plan:IsEnabled());popup.plan:Click()
		local saved;for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end
		assert.equal(100,saved.nativeRecipe.requirements.nativeStats.Evasion);assert.equal("divine",saved.steps[1].uniqueCraft.method)
		control.divine:Click();popup=main.popups[1].controls;popup.stat:SelByValue("Evasion","val");popup.target:SetText("80");popup.plan:Click();main.popups[1].controls.confirm:Click()
		for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end;assert.equal(1,#saved.steps);assert.equal(80,saved.nativeRecipe.requirements.nativeStats.Evasion)
		control.divine:Click();popup=main.popups[1].controls;popup.stat:SelByValue("modifier:2","val");popup.target:SetText("41");assert.is_false(popup.plan:IsEnabled());popup.target:SetText("40");assert.is_true(popup.plan:IsEnabled());popup.plan:Click();main.popups[1].controls.confirm:Click()
		for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end;assert.equal(1,#saved.steps);assert.equal(40,saved.nativeRecipe.requirements.uniqueModifier.minValue);assert.equal("+(30-40)% to all Elemental Resistances",saved.nativeRecipe.requirements.uniqueModifier.line)
		control.divine:Click();popup=main.popups[1].controls;popup.stat:SelByValue("modifier:2","val");popup.direction:SelByValue("At most");popup.target:SetText("30");assert.is_true(popup.plan:IsEnabled());popup.plan:Click();main.popups[1].controls.confirm:Click()
		for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end;assert.equal(1,#saved.steps);assert.equal(30,saved.nativeRecipe.requirements.uniqueModifier.maxValue);assert.matches("Roll at most 30",saved.steps[1].stopWhen)
		local sampled=require("Modules.CraftingSimulator").simulate(raw,saved.nativeRecipe,{trials=5,maxActions=100,seed=123});assert.is_true(sampled.sampled)
		control.divine:Click();popup=main.popups[1].controls;popup.apply:Click();assert.is_true(control.undo:IsEnabled());assert.is_true(control.guide:IsEnabled());main.popups={}
	end)

	it("samples tainted unique quality while preserving the item",function()
		for _,base in ipairs({shield,weapon}) do
			local raw=base.."\nCorrupted";local initial=quality.inspect(raw)
			for seed=1,20 do
				local rolled=quality.taintedQuality(raw,seed);assert.equal(rolled.itemText,quality.taintedQuality(raw,seed).itemText)
				local item,info=quality.inspect(rolled.itemText);assert.is_true(info.quality>=1 and info.quality<=20);assert.equal(initial.title,item.title);assert.is_true(item.corrupted)
				assert.is_true(rolled.itemText:find("Sockets:",1,true)~=nil)
			end
			assert.has_error(function() quality.taintedQuality(base,1) end)
		end
		local flask="Rarity: UNIQUE\nTaste of Hate\nSapphire Flask\nItem Level: 86\nCorrupted";assert.has_error(function() quality.taintedQuality(flask,1) end)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,{id="corrupted-flask",title="Flask",slot="Flask 1",startingItem=flask,goals={},steps={}})
		assert.is_false(control.apply:IsEnabled());assert.equal("Quality unavailable",control.apply.label);main.popups={}
		assert.has_error(function() quality.taintedQuality(shield.."\nCorrupted",0) end)
	end)

	it("connects tainted unique quality to simulations, guides and filters",function()
		local sim=require("Modules.CraftingSimulator")
		for index,base in ipairs({shield,weapon}) do
			local raw=base.."\nCorrupted";local result=sim.perform(raw,{method="tainted_quality"},12)
			assert.equal(quality.taintedQuality(raw,12).itemText,result.itemText)
			local warned=false;for _,entry in ipairs(result.warnings) do if entry.code=="tainted_quality_estimate" then warned=true end end;assert.is_true(warned)
			local recipe={steps={{method="tainted_quality",maxAttempts=20,untilRequirements={minQuality=20}}},targets={},requirements={minQuality=20}}
			local sampled=sim.simulate(raw,recipe,{trials=10,maxActions=20,seed=123});assert.is_true(sampled.sampled);assert.equal(10,sampled.trials)
			local calculation=sim.calculate(raw,{method="tainted_quality"},{},nil,{trials=10,requirements={minQuality=20}});assert.is_true(calculation.sampled)
			local catalog=sim.catalog(raw,"tainted quality",50);assert.equal(1,#catalog.uniqueActions);assert.is_true(catalog.uniqueActions[1].available)
			local project={id="tainted-quality-"..index,title="Quality",slot=index==1 and "Weapon 2" or "Weapon 1",startingItem=raw,goals={},steps={}}
			local store=build.savers.CraftingProjects;store:Upsert(project);local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
			assert.is_true(control.apply:IsEnabled());control.apply:Click();assert.is_true(control.undo:IsEnabled());assert.is_true(control.guide:IsEnabled());control.guide:Click()
			local saved;for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end
			assert.equal("tainted_quality",saved.steps[1].uniqueCraft.method)
			local _,info=quality.inspect(raw);local filters=require("Modules.LootFilters");local rules=filters.generate(build,filters.profile("tainted-quality-filter-"..index,"Quality"));local found=false
			for _,rule in ipairs(rules) do if rule.origin=="craft:"..project.id and rule.title=="Tainted "..info.resource then found=true end end;assert.is_true(found)
			main.popups={}
		end
	end)

	it("plans tainted unique quality directly and replaces unchanged guide steps",function()
		local raw=shield.."\nCorrupted";local project={id="quality-direct",title="Quality",slot="Weapon 2",startingItem=raw,goals={},steps={}}
		local store=build.savers.CraftingProjects;store:Upsert(project);local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		assert.is_true(control.qualityPlan:IsShown());control.qualityPlan:Click();local popup=main.popups[1].controls
		popup.target:SetText("21");assert.is_false(popup.plan:IsEnabled());popup.target:SetText("10");assert.matches("Already met",popup.targetHelp.label());popup.target:SetText("20");popup.attempts:SetText("1000");assert.is_true(popup.plan:IsEnabled());popup.plan:Click()
		local saved;for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end
		assert.equal(20,saved.nativeRecipe.requirements.minQuality);assert.equal(1000,saved.nativeRecipe.steps[1].maxAttempts);assert.equal("tainted_quality",saved.steps[1].uniqueCraft.method)
		control.qualityPlan:Click();popup=main.popups[1].controls;popup.target:SetText("18");popup.plan:Click();main.popups[1].controls.confirm:Click()
		for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end
		assert.equal(1,#saved.steps);assert.equal("At least 18% quality",saved.steps[1].stopWhen);assert.equal(18,saved.nativeRecipe.requirements.minQuality)
		local run=require("Modules.CraftingSimulator").simulate(raw,saved.nativeRecipe,{trials=10,maxActions=100,seed=123});assert.is_true(run.sampled);assert.is_true(run.successes>0);main.popups={}
	end)

	it("samples unique socket counts while preserving item properties and restrictions",function()
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B\n+40% to Fire Resistance"
		for _,method in ipairs({"jeweller","tainted_jeweller"}) do
			local input=raw..(method=="tainted_jeweller" and "\nCorrupted" or "")
			for seed=1,20 do
				local result=quality.randomSockets(input,method,seed)
				assert.equal(result.itemText,quality.randomSockets(input,method,seed).itemText)
				assert.is_true(result.itemText:find("+40% to Fire Resistance",1,true)~=nil)
				local item=quality.inspect(result.itemText)
				assert.is_true(#item.sockets>=1 and #item.sockets<=4)
				assert.equal(method=="tainted_jeweller",not not item.corrupted)
			end
		end
		assert.has_error(function() quality.randomSockets(raw,"tainted_jeweller",1) end)
		assert.has_error(function() quality.randomSockets(raw.."\nCorrupted","jeweller",1) end)
		assert.has_error(function() quality.randomSockets(raw.."\nSockets cannot be modified","jeweller",1) end)
		assert.has_error(function() quality.randomSockets(raw:gsub("Sockets: R%-G B","Sockets: R-G B W"),"jeweller",1) end)
		assert.has_error(function() quality.randomSockets(raw,"jeweller",0) end)
		local sim=require("Modules.CraftingSimulator")
		local result=sim.perform(raw,{method="jeweller"},12)
		assert.equal(quality.randomSockets(raw,"jeweller",12).itemText,result.itemText)
		local warnings={};for _,warning in ipairs(result.warnings) do warnings[warning.code]=true end
		assert.is_true(warnings.unique_socket_count_estimate)
		local recipe={steps={{method="jeweller",maxAttempts=10,untilRequirements={exactSockets=4}}},targets={},requirements={exactSockets=4}}
		local run=sim.simulate(raw,recipe,{trials=5,maxActions=10,seed=12})
		assert.is_true(run.sampled);assert.equal(5,run.trials)
		local calculated=sim.calculate(raw,{method="jeweller"},{},nil,{trials=5,requirements={exactSockets=4}})
		assert.is_true(calculated.sampled);assert.equal(5,calculated.trials)
		local entries=sim.catalog(raw,"jeweller",50).uniqueActions;local found={}
		for _,entry in ipairs(entries) do found[entry.method]=entry end
		assert.is_true(found.jeweller.available);assert.is_false(found.tainted_jeweller.available)

	end)

	it("samples unique socket colours without changing other item properties",function()
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B W\n+40% to Fire Resistance"
		for _,method in ipairs({"chromatic","omen_trichromatism","tainted_chromatic"}) do
			local input=raw..(method=="tainted_chromatic" and "\nCorrupted" or "")
			local first=quality.colour(input,method,123);local second=quality.colour(input,method,123)
			assert.equal(first.itemText,second.itemText);assert.is_true(first.itemText:find("+40% to Fire Resistance",1,true)~=nil)
			local item=quality.inspect(first.itemText);assert.equal(4,#item.sockets)
			assert.equal(item.sockets[1].group,item.sockets[2].group);assert.is_true(item.sockets[2].group~=item.sockets[3].group)
			if method=="omen_trichromatism" then local colors={};for _,socket in ipairs(item.sockets) do colors[socket.color]=true end;assert.is_true(colors.R and colors.G and colors.B) end
		end
		assert.has_error(function() quality.colour(raw.."\nCorrupted","chromatic",1) end)
		assert.has_error(function() quality.colour(raw,"tainted_chromatic",1) end)
		assert.has_error(function() quality.colour(raw:gsub("Sockets: R%-G B W","Sockets: R-G"),"omen_trichromatism",1) end)
		assert.has_error(function() quality.colour(raw.."\nSockets cannot be modified","chromatic",1) end)
	end)

	it("samples unique socket recipes with independent reproducible trials",function()
		local sim=require("Modules.CraftingSimulator")
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B W\n+40% to Fire Resistance"
		local options={trials=80,seed=123,requirements={socketColours="R"}}
		local a=sim.calculate(raw,{method="chromatic"},{},nil,options);local b=sim.calculate(raw,{method="chromatic"},{},nil,options)
		assert.is_true(a.sampled);assert.equal(80,a.trials);assert.equal(a.successes,b.successes)
		assert.is_true(a.successChance>0 and a.successChance<100);assert.is_true(a.confidenceLow<=a.successChance and a.confidenceHigh>=a.successChance)
		local recipe={steps={{method="omen_trichromatism"}},targets={},requirements={socketColours="RGB"}}
		local r=sim.simulate(raw,recipe,{trials=25,maxActions=1,seed=456,forceFirstAction=true})
		assert.is_true(r.sampled);assert.equal(25,r.successes);assert.equal(100,r.successChance);assert.equal(25,r.resourceUsage[1].amount)
		local once=sim.perform(raw,{method="omen_trichromatism"},1);assert.equal(1,once.components["Metadata/Items/Currency/CurrencyRerollSocketColours"])
		local repeatedRaw=raw:gsub("Sockets: R%-G B W","Sockets: W-W W W")
		local repeated={steps={{method="chromatic",maxAttempts=10,untilRequirements={socketColours="RR"}}},targets={},requirements={socketColours="RR"}}
		local repeatedOptions={trials=30,maxActions=10,seed=123,currency="chaos",prices={chromatic=1},retainSuccesses=4}
		local repeatResult=sim.simulate(repeatedRaw,repeated,repeatedOptions);local repeatAgain=sim.simulate(repeatedRaw,repeated,repeatedOptions)
		assert.is_true(repeatResult.successes>0 and repeatResult.successes<30);assert.equal(repeatResult.successes,repeatAgain.successes)
		assert.is_true(math.abs(repeatResult.meanActions-repeatResult.meanCost)<1e-8);assert.is_true(math.abs(repeatResult.meanActions*30-repeatResult.resourceUsage[1].amount)<1e-8)
		assert.equal(4,#repeatResult.retainedSuccesses);assert.is_true(repeatResult.confidenceLow<repeatResult.successChance and repeatResult.confidenceHigh>repeatResult.successChance)
		local rejectedRecipe={steps={{method="chromatic"},{method="omen_jeweller"}},targets={},requirements={socketColours="RRRR"}}
		local rejected=sim.simulate(repeatedRaw,rejectedRecipe,{trials=10,maxActions=2,seed=123})
		assert.equal(10,rejected.failedTransitionTrials);local warning
		for _,entry in ipairs(rejected.warnings) do if entry.code=="rejected_model_actions" then warning=entry.message end end
		assert.is_true(warning and warning:find("10 of 10",1,true)~=nil)
	end)

	it("previews unique socket colours and keeps a guide",function()
		for _,corrupted in ipairs({false,true}) do
			local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: W-W W W"..(corrupted and "\nCorrupted" or "")
			local project={id=corrupted and "colour-corrupt" or "colour-normal",title="Colour",slot="Helmet",startingItem=raw,goals={},steps={}}
			local store=build.savers.CraftingProjects;store:Upsert(project)
			local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
			control.socketCount:Click();main.popups[1].controls.colours:Click()
			local popup=main.popups[1].controls;assert.equal(corrupted and "tainted_chromatic" or "chromatic",popup.method:GetSelValueByKey("val"));assert.is_true(popup.apply:IsEnabled());popup.apply:Click()
			assert.is_true(control.undo:IsEnabled());control.guide:Click()
			local saved;for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end
			assert.equal(corrupted and "tainted_chromatic" or "chromatic",saved.steps[1].uniqueCraft.method);assert.is_true(control.recipe:IsEnabled());control.recipe:Click()
			for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end
			assert.equal(corrupted and "tainted_chromatic" or "chromatic",saved.nativeRecipe.steps[1].method);assert.equal(100,saved.nativeRecipe.steps[1].maxAttempts);main.popups={}
		end
	end)

	it("uses a fresh colour preview after undo and session recovery",function()
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: W-W W W"
		local project={id="colour-seeds",title="Colour",slot="Helmet",startingItem=raw,goals={},steps={}}
		local store=build.savers.CraftingProjects;store:Upsert(project)
		local original=quality.colour;local seeds={}
		quality.colour=function(item,method,seed) seeds[#seeds+1]=seed;return original(item,method,seed) end
		local function roll(control) control.socketCount:Click();main.popups[1].controls.colours:Click();main.popups[1].controls.apply:Click() end
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		roll(control);control.undo:Click();roll(control);control.close:Click()
		local snapshot=build.planningUniqueQualityDrafts[project.id]
		local recovered=require("Modules.PlanningRecovery").clean("uniqueQuality",{plan=snapshot}).plan
		main.popups={};control=require("Classes.CraftingUniqueQualityControl").Open(build,project,nil,recovered);control.undo:Click();roll(control)
		quality.colour=original;main.popups={}
		assert.equal(3,#seeds);assert.is_true(seeds[1]~=seeds[2] and seeds[2]~=seeds[3] and seeds[1]~=seeds[3]);assert.equal(2,recovered.colourRollCounter)
	end)

	it("offers a later successful sampled recipe item and per-trial resources",function()
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: W-W W W"
		local recipe={steps={{method="chromatic"}},targets={},requirements={socketColours="G"}}
		local direct=require("Modules.CraftingSimulator").simulate(raw,recipe,{trials=20,maxActions=100,retainSuccesses=1})
		assert.is_false(direct.sampleSuccess);assert.is_true(direct.successes>0);assert.equal(1,#direct.retainedSuccesses)
		local project={id="colour-result",title="Sampled result",slot="Helmet",startingItem=raw,goals={},steps={},nativeRecipe=recipe}
		local store=build.savers.CraftingProjects;store:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project);control.recipe:Click()
		local tasks=require("Modules.CraftingTasks");assert.is_truthy(tasks.job);while tasks.job do tasks.tick(build) end
		local view=main.popups[1].controls;assert.is_true(view.keep:IsEnabled())
		local lines={};for _,row in ipairs(view.details.list) do lines[#lines+1]=row[1] end
		assert.is_true(table.concat(lines," "):find("per trial",1,true)~=nil)
		view.keep:Click();local saved;for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end
		assert.is_true(quality.matches(saved.targetItem,{socketColours="G"}));main.popups={}
	end)

	it("saves a direct unique colour target without rolling first",function()
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: W-W W W"
		local project={id="direct-colour",title="Target colours",slot="Helmet",startingItem=raw,goals={},steps={}}
		local store=build.savers.CraftingProjects;store:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project);control.socketCount:Click();main.popups[1].controls.colours:Click()
		local popup=main.popups[1].controls;assert.is_false(popup.plan:IsEnabled());popup.target:SetText("RRRRR");assert.is_false(popup.plan:IsEnabled())
		popup.target:SetText("rgb");popup.attempts:SetText("0");assert.is_false(popup.plan:IsEnabled());popup.attempts:SetText("250");assert.is_true(popup.plan:IsEnabled());popup.plan:Click()
		local saved;for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end
		assert.equal(raw,saved.startingItem);assert.equal("RGB",saved.nativeRecipe.requirements.socketColours);assert.equal(250,saved.nativeRecipe.steps[1].maxAttempts);assert.equal("Stop after 250 attempts.",saved.steps[1].onFailure)
		assert.equal("chromatic",saved.steps[1].uniqueCraft.method);assert.matches("RGB",saved.steps[1].stopWhen);assert.is_true(control.recipe:IsEnabled())
		local result=require("Modules.CraftingSimulator").simulate(raw,saved.nativeRecipe,{trials=20,maxActions=100,seed=123})
		assert.is_true(result.sampled);assert.is_true(result.trials==20)
		local filters=require("Modules.LootFilters");local pickups=filters.generate(build,filters.profile("direct-colour","Colours"));local found=false
		for _,entry in ipairs(pickups) do if entry.origin=="craft:direct-colour" and entry.title=="Chromatic Orb" then found=true end end;assert.is_true(found)
		control.socketCount:Click();main.popups[1].controls.colours:Click();local replacement=main.popups[1].controls;replacement.target:SetText("RR");replacement.plan:Click()
		assert.equal("RGB",saved.nativeRecipe.requirements.socketColours);main.popups[1].controls.confirm:Click()
		for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end
		assert.equal("RR",saved.nativeRecipe.requirements.socketColours);assert.equal(1,#saved.steps);assert.equal("At least RR sockets in any order",saved.steps[1].stopWhen)
		local edited=copyTable(saved);edited.steps[1].stopWhen="My custom condition";store:Upsert(edited);main.popups={}
		control=require("Classes.CraftingUniqueQualityControl").Open(build,edited);control.socketCount:Click();main.popups[1].controls.colours:Click()
		replacement=main.popups[1].controls;replacement.target:SetText("G");replacement.plan:Click();main.popups[1].controls.confirm:Click()
		for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end
		assert.equal("G",saved.nativeRecipe.requirements.socketColours);assert.equal(2,#saved.steps);assert.equal("My custom condition",saved.steps[1].stopWhen);main.popups={}
	end)

	it("plans unique socket colours within one linked group",function()
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-R G G"
		local project={id="linked-colour",title="Linked colours",slot="Helmet",startingItem=raw,goals={},steps={}}
		local store=build.savers.CraftingProjects;store:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project);control.socketCount:Click();main.popups[1].controls.colours:Click()
		local popup=main.popups[1].controls;popup.placement:SelByValue("In one linked group");popup.target:SetText("RGB");assert.is_false(popup.plan:IsEnabled())
		assert.matches("linked group",popup.plan.tooltipText());popup.target:SetText("RG");assert.is_true(popup.plan:IsEnabled());popup.plan:Click()
		local saved;for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end
		assert.is_true(saved.nativeRecipe.requirements.linkedColours);assert.is_true(saved.nativeRecipe.steps[1].untilRequirements.linkedColours)
		assert.equal("At least RG sockets in one linked group",saved.steps[1].stopWhen);assert.is_false(quality.matches(raw,saved.nativeRecipe.requirements))
		local result=require("Modules.CraftingSimulator").simulate(raw,saved.nativeRecipe,{trials=20,maxActions=100,seed=123,retainSuccesses=1})
		assert.is_true(result.sampled);assert.is_true(result.successes>0);assert.is_true(quality.matches(result.retainedSuccesses[1].itemText,saved.nativeRecipe.requirements))
		control.socketCount:Click();main.popups[1].controls.colours:Click();popup=main.popups[1].controls;popup.target:SetText("G");popup.plan:Click();main.popups[1].controls.confirm:Click()
		for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end
		assert.is_false(saved.nativeRecipe.requirements.linkedColours);assert.equal(1,#saved.steps);assert.equal("At least G sockets in any order",saved.steps[1].stopWhen);main.popups={}
	end)

	it("explains colour targets that conflict with guaranteed outcomes",function()
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-R G G"
		local item=quality.inspect(raw)
		assert.matches("non%-white",quality.colourTargetReason(item,"chromatic","WWWW",false))
		assert.matches("guaranteed",quality.colourTargetReason(item,"omen_trichromatism","RRW",false))
		assert.is_nil(quality.colourTargetReason(item,"omen_trichromatism","RGB",false))
		assert.matches("linked group",quality.colourTargetReason(item,"chromatic","RGB",true))
		assert.is_nil(quality.colourTargetReason(item,"chromatic","RG",true))
		local white=quality.inspect(raw:gsub("Sockets: R%-R G G","Sockets: W-W W W"))
		local reason,already=quality.colourTargetReason(white,"chromatic","WWWW",false);assert.is_nil(reason);assert.is_true(already)
		assert.matches("non%-white",quality.colourTargetReason(white,"chromatic","WWWW",false,true))
		local calculation=require("Modules.CraftingSimulator").calculate(raw:gsub("Sockets: R%-R G G","Sockets: W-W W W"),{method="chromatic"},{},nil,{trials=5,requirements={socketColours="WWWW"}})
		assert.equal(0,calculation.successChance);local warned=false;for _,entry in ipairs(calculation.warnings) do if entry.code=="unique_socket_target_unreachable" then warned=true end end;assert.is_true(warned)
		local zero=require("Modules.CraftingSimulator").simulate(raw:gsub("Sockets: R%-R G G","Sockets: W-W W W"),{steps={{method="chromatic",maxAttempts=100,untilRequirements={socketColours="WWWW"}}},targets={},requirements={socketColours="WWWW"}},{trials=5,maxActions=100})
		assert.equal(5,zero.successes);assert.equal(0,zero.meanActions);assert.equal(0,#zero.resourceUsage)
		local project={id="impossible-colour",title="Colour",slot="Helmet",startingItem=raw,goals={},steps={}}
		build.savers.CraftingProjects:Upsert(project);local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		control.socketCount:Click();main.popups[1].controls.colours:Click();local popup=main.popups[1].controls
		popup.target:SetText("WWWW");assert.is_false(popup.plan:IsEnabled());assert.matches("non%-white",popup.targetHelp.label())
		popup.method:SelByValue("omen_trichromatism","val");popup.target:SetText("RRW");assert.is_false(popup.plan:IsEnabled());assert.matches("guaranteed",popup.targetHelp.label())
		popup.target:SetText("RGB");assert.is_true(popup.plan:IsEnabled());popup.method:SelByValue("chromatic","val");popup.target:SetText("RR")
		assert.is_true(popup.plan:IsEnabled());assert.matches("Already met",popup.targetHelp.label());main.popups={}
	end)

	it("samples unique links without changing socket colours",function()
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B W\n+40% to Fire Resistance"
		for _,method in ipairs({"fusing","tainted_fusing"}) do
			local input=raw..(method=="tainted_fusing" and "\nCorrupted" or "")
			local first=quality.randomLinks(input,method,123);local again=quality.randomLinks(input,method,123)
			assert.equal(first.itemText,again.itemText);local item=quality.inspect(first.itemText)
			assert.equal(4,#item.sockets);for index,colour in ipairs({"R","G","B","W"}) do assert.equal(colour,item.sockets[index].color) end
			assert.is_true(first.itemText:find("+40% to Fire Resistance",1,true)~=nil)
		end
		assert.has_error(function() quality.randomLinks(raw.."\nCorrupted","fusing",1) end)
		assert.has_error(function() quality.randomLinks(raw,"tainted_fusing",1) end)
		assert.has_error(function() quality.randomLinks(raw.."\nSockets cannot be modified","fusing",1) end)
		assert.has_error(function() quality.randomLinks(raw:gsub("Sockets: R%-G B W","Sockets: R-G-B-W").."\nCorrupted","tainted_fusing",1) end)
	end)

	it("simulates sampled unique Fusing recipes",function()
		local sim=require("Modules.CraftingSimulator");local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B W"
		local boundary={steps={{method="fusing",maxAttempts=2000,untilRequirements={links=4}}},targets={},requirements={links=4}}
		assert.equal(2000,sim.validateRecipe(boundary).steps[1].maxAttempts);boundary.steps[1].maxAttempts=2001;assert.has_error(function() sim.validateRecipe(boundary) end)
		for _,method in ipairs({"fusing","tainted_fusing"}) do
			local input=raw..(method=="tainted_fusing" and "\nCorrupted" or "")
			local catalog=sim.catalog(input,method,50);local action
			for _,entry in ipairs(catalog.uniqueActions) do if entry.method==method then action=entry end end
			assert.is_true(action.available);assert.is_false(action.deterministic)
			local first=sim.perform(input,{method=method},123);local second=sim.perform(input,{method=method},123);assert.equal(first.itemText,second.itemText)
			local recipe={steps={{method=method,maxAttempts=10,untilRequirements={links=4}}},targets={},requirements={links=4}}
			local result=sim.simulate(input,recipe,{trials=20,maxActions=10,seed=123,retainSuccesses=1})
			assert.is_true(result.sampled);assert.is_true(result.successes>0 and result.successes<20);assert.is_true(quality.matches(result.retainedSuccesses[1].itemText,{links=4}))
			local calculated=sim.calculate(input,{method=method},{},nil,{trials=20,seed=123,requirements={links=4}});assert.is_true(calculated.sampled)
		end
	end)

	it("plans and previews unique socket-count rolls",function()
		for _,corrupted in ipairs({false,true}) do
			local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B"..(corrupted and "\nCorrupted" or "")
			local project={id=corrupted and "sockets-corrupted" or "sockets-normal",title="Sockets",slot="Helmet",startingItem=raw,goals={},steps={}}
			local store=build.savers.CraftingProjects;store:Upsert(project)
			local control=require("Classes.CraftingUniqueQualityControl").Open(build,project);control.socketCount:Click();main.popups[1].controls.roll:Click()
			local popup=main.popups[1].controls;local method=corrupted and "tainted_jeweller" or "jeweller"
			assert.equal(method,popup.method:GetSelValueByKey("val"));popup.target:SetText("5");assert.is_false(popup.plan:IsEnabled());popup.target:SetText("3");assert.matches("Already met",popup.targetHelp.label());popup.target:SetText("4");popup.attempts:SetText("250");assert.is_true(popup.plan:IsEnabled());popup.plan:Click()
			local saved;for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end
			assert.equal(method,saved.nativeRecipe.steps[1].method);assert.equal(4,saved.nativeRecipe.requirements.exactSockets);assert.equal(250,saved.nativeRecipe.steps[1].maxAttempts);assert.equal(method,saved.steps[1].uniqueCraft.method)
			local result=require("Modules.CraftingSimulator").simulate(raw,saved.nativeRecipe,{trials=10,maxActions=250,seed=123});assert.is_true(result.sampled);assert.is_true(result.successes>0)
			local filters=require("Modules.LootFilters");local rules=filters.generate(build,filters.profile("socket-"..tostring(corrupted),"Sockets"));local found=false
			for _,rule in ipairs(rules) do if rule.origin=="craft:"..project.id and rule.title==(corrupted and "Tainted Jeweller's Orb" or "Jeweller's Orb") then found=true end end;assert.is_true(found)
			control.socketCount:Click();main.popups[1].controls.roll:Click();popup=main.popups[1].controls;popup.apply:Click();assert.is_true(control.undo:IsEnabled());main.popups={}
		end
	end)

	it("replaces only unchanged socket guide steps and accepts an already met maximum",function()
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B"
		local store=build.savers.CraftingProjects;local project={id="socket-replace",title="Sockets",slot="Helmet",startingItem=raw,goals={},steps={}}
		store:Upsert(project);local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		control.socketCount:Click();main.popups[1].controls.roll:Click();local popup=main.popups[1].controls;popup.target:SetText("4");popup.plan:Click()
		control.socketCount:Click();main.popups[1].controls.roll:Click();popup=main.popups[1].controls;popup.target:SetText("2");popup.plan:Click();main.popups[1].controls.confirm:Click()
		local saved;for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end
		assert.equal(1,#saved.steps);assert.equal("Exactly 2 sockets",saved.steps[1].stopWhen);assert.equal(2,saved.nativeRecipe.requirements.exactSockets)
		control.socketCount:Click();main.popups[1].controls.roll:Click();popup=main.popups[1].controls;popup.target:SetText("2");assert.matches("Maximum sockets stop",popup.targetHelp.label());main.popups={}
		local warningRun=require("Modules.CraftingSimulator").simulate(raw,saved.nativeRecipe,{trials=5,maxActions=100,seed=123});local warned=false
		for _,warning in ipairs(warningRun.warnings) do if warning.code=="unique_jeweller_maximum_stops" then warned=true end end;assert.is_true(warned)
		local full=raw:gsub("Sockets: R%-G B","Sockets: R-G B W")
		local complete={id="socket-complete",title="Complete",slot="Helmet",startingItem=full,goals={},steps={}}
		store:Upsert(complete);control=require("Classes.CraftingUniqueQualityControl").Open(build,complete);control.socketCount:Click();main.popups[1].controls.roll:Click();popup=main.popups[1].controls
		assert.is_false(popup.apply:IsEnabled());popup.target:SetText("4");assert.is_true(popup.plan:IsEnabled());assert.matches("Already met",popup.targetHelp.label());popup.plan:Click()
		for _,entry in ipairs(store.projects) do if entry.id==complete.id then saved=entry end end
		local run=require("Modules.CraftingSimulator").simulate(full,saved.nativeRecipe,{trials=1,maxActions=100});assert.is_true(run.sampleSuccess);assert.equal(0,run.meanActions);main.popups={}
	end)

	it("plans and previews unique socket links",function()
		for _,corrupted in ipairs({false,true}) do
			local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B W"..(corrupted and "\nCorrupted" or "")
			local project={id=corrupted and "link-corrupted" or "link-normal",title="Link",slot="Helmet",startingItem=raw,goals={},steps={}}
			local store=build.savers.CraftingProjects;store:Upsert(project)
			local control=require("Classes.CraftingUniqueQualityControl").Open(build,project);control.socketCount:Click();main.popups[1].controls.links:Click()
			local popup=main.popups[1].controls;local method=corrupted and "tainted_fusing" or "fusing"
			assert.equal(method,popup.method:GetSelValueByKey("val"));popup.target:SetText("5");assert.is_false(popup.plan:IsEnabled());popup.target:SetText("2");assert.matches("Already met",popup.targetHelp.label());popup.target:SetText("4");popup.attempts:SetText("2001");assert.is_false(popup.plan:IsEnabled());popup.attempts:SetText("1000");assert.is_true(popup.plan:IsEnabled());popup.plan:Click()
			local saved;for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end
			assert.equal(method,saved.nativeRecipe.steps[1].method);assert.equal(4,saved.nativeRecipe.requirements.links);assert.equal(1000,saved.nativeRecipe.steps[1].maxAttempts);assert.equal("Stop after 1000 attempts.",saved.steps[1].onFailure);assert.equal(method,saved.steps[1].uniqueCraft.method)
			local result=require("Modules.CraftingSimulator").simulate(raw,saved.nativeRecipe,{trials=20,maxActions=100,seed=123});assert.is_true(result.sampled);assert.is_true(result.successes>0)
			control.recipe:Click();local tasks=require("Modules.CraftingTasks");assert.is_truthy(tasks.job);while tasks.job do tasks.tick(build) end;local view=main.popups[1].controls;local summary={};for _,row in ipairs(view.details.list) do summary[#summary+1]=row[1] end;assert.is_true(table.concat(summary," "):find("10 trials",1,true)~=nil);assert.is_true(table.concat(summary," "):find("limit 1000",1,true)~=nil);view.close:Click()
			local filters=require("Modules.LootFilters");local rules=filters.generate(build,filters.profile("link-"..tostring(corrupted),"Links"));local found=false
			for _,rule in ipairs(rules) do if rule.origin=="craft:"..project.id and rule.title==(corrupted and "Tainted Orb of Fusing" or "Orb of Fusing") then found=true end end;assert.is_true(found)
			control.socketCount:Click();main.popups[1].controls.links:Click();popup=main.popups[1].controls;assert.is_true(popup.apply:IsEnabled());popup.apply:Click();assert.is_true(control.undo:IsEnabled());main.popups={}
		end
	end)

	it("saves an already fully linked unique target without rolling",function()
		for _,corrupted in ipairs({false,true}) do
			local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G-B-W"..(corrupted and "\nCorrupted" or "")
			local project={id=corrupted and "complete-tainted-link" or "complete-link",title="Links",slot="Helmet",startingItem=raw,goals={},steps={}}
			local store=build.savers.CraftingProjects;store:Upsert(project)
			local control=require("Classes.CraftingUniqueQualityControl").Open(build,project);control.socketCount:Click();main.popups[1].controls.links:Click()
			local popup=main.popups[1].controls;popup.target:SetText("4")
			if corrupted then assert.is_false(popup.apply:IsEnabled()) end
			assert.is_true(popup.plan:IsEnabled());assert.matches("Already met",popup.targetHelp.label());popup.plan:Click()
			local saved;for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end
			local result=require("Modules.CraftingSimulator").simulate(raw,saved.nativeRecipe,{trials=1,maxActions=100});assert.is_true(result.sampleSuccess);assert.equal(0,result.meanActions);main.popups={}
		end
		local raw="Rarity: UNIQUE\nBelly of the Beast\nFull Wyrmscale\nItem Level: 86\nSockets: R-G-B-W-R-G"
		local project={id="complete-six-link",title="Six links",slot="Body Armour",startingItem=raw,goals={},steps={}}
		local store=build.savers.CraftingProjects;store:Upsert(project);local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		control.socketCount:Click();main.popups[1].controls.links:Click();local popup=main.popups[1].controls;popup.target:SetText("6")
		assert.is_false(popup.apply:IsEnabled());assert.is_true(popup.plan:IsEnabled());assert.matches("Already met",popup.targetHelp.label());popup.plan:Click()
		local saved;for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end
		local result=require("Modules.CraftingSimulator").simulate(raw,saved.nativeRecipe,{trials=1,maxActions=100});assert.is_true(result.sampleSuccess);assert.equal(0,result.meanActions);main.popups={}
	end)

	it("runs and cancels long unique recipe checks in the background",function()
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B W"
		local recipe={steps={{method="fusing",maxAttempts=1000,untilRequirements={links=4}}},targets={},requirements={links=4}}
		local project={id="unique-background",title="Background",slot="Helmet",startingItem=raw,goals={},steps={},nativeRecipe=recipe}
		build.savers.CraftingProjects:Upsert(project);local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		local tasks=require("Modules.CraftingTasks");control.recipe:Click();assert.is_truthy(tasks.job);assert.is_truthy(main.popups[1].controls.cancel)
		main.popups[1].controls.cancel:Click();assert.is_nil(tasks.job)
		control.recipe:Click();assert.is_truthy(tasks.job);local slices=0;while tasks.job do tasks.tick(build);slices=slices+1;assert.is_true(slices<100000) end
		assert.is_true(slices>0);assert.is_truthy(main.popups[1].controls.details);main.popups={}
	end)

	it("retains long attempt budgets in the recipe editor and comparison",function()
		local kept;local editor=require("Classes.CraftingRecipeControl").Open({steps={{method="fusing"}},targets={},requirements={links=4}},{method="fusing"},function(value) kept=value end)
		editor.attempts:SetText("2000");editor.condition:SelByValue("Until final targets and properties match");editor.keep:Click();assert.equal(2000,kept.steps[1].maxAttempts);main.popups={}
		local sim=require("Modules.CraftingSimulator");local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local model=sim.model(raw);local seen={};local original=sim.simulate
		sim.simulate=function(_,recipe) seen[#seen+1]=recipe.steps[1].maxAttempts;error("comparison probe") end
		local controls=require("Classes.CraftingCompareControl").Open(build,raw,model.initial,{}, {minAffixes=1},nil,{method="transmute"},nil,{budget=1000,trials=1,seed=1,currency="chaos"})
		controls.run:Click();local tasks=require("Modules.CraftingTasks");while tasks.job do tasks.tick(build) end;sim.simulate=original
		assert.equal(3,#seen);for _,attempts in ipairs(seen) do assert.equal(1000,attempts) end;main.popups={}
	end)

	it("previews and simulates unique flask and tincture quality",function()
		local sim=require("Modules.CraftingSimulator")
		for _,entry in ipairs({{"Taste of Hate","Sapphire Flask"},{"The Battle Within","Oakbranch Tincture"}}) do
			local raw="Rarity: UNIQUE\n"..entry[1].."\n"..entry[2].."\nItem Level: 86\nQuality: 18"
			local item,info=quality.inspect(raw);assert.equal("Glassblower's Bauble",info.resource);assert.equal("Metadata/Items/Currency/CurrencyFlaskQuality",info.resourceKey)
			local next=quality.apply(raw);assert.equal(19,next.quality);assert.matches("Quality: 19",next.itemText,1,true)
			local catalog=sim.catalog(raw,"",50);assert.equal(2,#catalog.uniqueActions);assert.equal("quality",catalog.uniqueActions[1].method)
			local calc=sim.calculate(raw,{method="quality"},{},nil,{requirements={minQuality=19}});assert.equal(100,calc.successChance);assert.equal(1,calc.components[info.resourceKey])
			local result=sim.simulate(raw,{steps={{method="quality",maxAttempts=2,untilRequirements={minQuality=20}}},targets={},requirements={minQuality=20}},{trials=1,maxActions=2});assert.is_true(result.sampleSuccess);assert.equal(2,result.meanActions)
			assert.has_error(function() quality.apply(raw.."\nCorrupted") end);assert.has_error(function() quality.apply(raw:gsub("Quality: 18","Quality: 20")) end)
		end
	end)
	it("preserves the quality baseline of game-copied unique tinctures",function()
		local raw="Item Class: Tinctures\nRarity: UNIQUE\nThe Battle Within\nOakbranch Tincture\nItem Level: 86\nQuality: 18\nGain 3 Rage on Melee Weapon Hit"
		local before=quality.inspect(raw);assert.equal("Final",before.tinctureValues);assert.equal(18,before.tinctureImportedQuality);assert.matches("separate scaling model",quality.divineReason(raw))
		local first=quality.apply(raw);local after=quality.inspect(first.itemText);assert.equal(19,after.quality);assert.equal(18,after.tinctureImportedQuality)
		local second=quality.apply(first.itemText);local finished=quality.inspect(second.itemText);assert.equal(20,finished.quality);assert.equal(18,finished.tinctureImportedQuality)
		local _,count=second.itemText:gsub("Tincture Imported Quality:","");assert.equal(1,count)
	end)
	it("creates a checkable recipe from the complete unique preview",function()
		local project={id="unique-preview-recipe",title="Recipe",slot="Weapon 2",startingItem=shield,goals={},steps={}}
		local store=build.savers.CraftingProjects;store:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		assert.equal(152,select(2,control.item:GetSize()));assert.is_truthy(control.apply.planningIcon);assert.is_truthy(control.omen.planningIcon);assert.is_truthy(control.white.planningIcon)
		assert.is_false(control.recipe:IsEnabled());control.apply:Click();control.apply:Click();control.omen:Click();control.white:Click()
		assert.is_true(control.recipe:IsEnabled());control.recipe:Click()
		local recipe=store.projects[1].nativeRecipe;assert.equal(3,#recipe.steps);assert.equal(2,recipe.steps[1].maxAttempts)
		assert.equal("omen_connections",recipe.steps[2].method);assert.equal("socket_white_bench",recipe.steps[3].method)
		assert.equal(14,recipe.requirements.minQuality);assert.equal(3,recipe.requirements.links);assert.equal("WWW",recipe.requirements.socketColours)
		control.recipe:Click();assert.matches("Sockets: W%-W%-W",main.popups[1].controls.resultItemMods.list[1][1]);main.popups[1].controls.close:Click()
		control.apply:Click();control.recipe:Click();main.popups[1].controls.update:Click()
		assert.equal(14,store.projects[1].nativeRecipe.requirements.minQuality);main.popups[1].controls.confirm:Click()
		assert.equal(15,store.projects[1].nativeRecipe.requirements.minQuality);assert.matches("15%%",control.status.label);main.popups={}
	end)
	it("checks and saves a unique recipe result without changing the preview",function()
		local project={id="unique-recipe-ui",title="Recipe",slot="Weapon 2",startingItem=shield,goals={},steps={},nativeRecipe={steps={{method="omen_connections"}},targets={},requirements={links=3}}}
		local store=build.savers.CraftingProjects;store:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		control.apply:Click();assert.matches("13%%",control.status.label);assert.is_true(control.recipe:IsEnabled());control.recipe:Click()
		local popup=main.popups[1].controls;local text={};for _,row in ipairs(popup.details.list) do text[#text+1]=row[1] end
		assert.matches("Goal reached",table.concat(text," "));assert.matches("Sockets: R%-G%-B",popup.resultItemMods.list[1][1])
		assert.matches("13%%",control.status.label);assert.is_nil(store.projects[1].targetItem);popup.keep:Click()
		assert.matches("Sockets: R%-G%-B",store.projects[1].targetItem);assert.matches("13%%",control.status.label)
		local xml=build:SaveDB("Unique recipe target");loadBuildFromXML(xml,"Unique recipe target");main.popups={}
		local saved=build.savers.CraftingProjects.projects[1]
		assert.matches("Sockets: R%-G%-B",saved.targetItem);assert.equal("omen_connections",saved.nativeRecipe.steps[1].method)
		control=require("Classes.CraftingUniqueQualityControl").Open(build,saved);assert.is_true(control.recipe:IsEnabled());assert.is_true(control.loadTarget:IsEnabled());main.popups={}
	end)
	it("confirms before replacing a unique guide target with a recipe result",function()
		local project={id="unique-recipe-replace",title="Recipe",slot="Weapon 2",startingItem=shield,targetItem=shield,goals={},steps={},nativeRecipe={steps={{method="omen_connections"}},targets={},requirements={links=3}}}
		local store=build.savers.CraftingProjects;store:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project);control.recipe:Click()
		main.popups[1].controls.keep:Click();assert.equal(shield,store.projects[1].targetItem)
		main.popups[1].controls.confirm:Click();assert.matches("Sockets: R%-G%-B",store.projects[1].targetItem);main.popups={}
	end)
	it("links existing unique sockets without changing any other item properties",function()
		local simulator=require("Modules.CraftingSimulator")
		local source=shield.."\nNote: Preserve unknown fields"
		local result=simulator.perform(source,{method="beast_max_links"},7)
		assert.equal(source:gsub("Sockets: R%-G B","Sockets: R-G-B"),result.itemText)
		assert.same({beast_black_morrigan=1,beast_craicic_sand_spitter=1},result.components)
		local omen=simulator.perform(source,{method="omen_connections"},7)
		assert.equal(result.itemText,omen.itemText);assert.equal("omen_connections",omen.priceKey)
		assert.equal(1,omen.components["Metadata/Items/Currency/AncestralOmenOnFusingMakeFullLinks"])
		assert.equal(1,omen.components["Metadata/Items/Currency/CurrencyRerollSocketLinks"])
		assert.has_error(function() simulator.perform(result.itemText,{method="beast_max_links"},7) end)
		assert.has_error(function() simulator.perform(source.."\nCorrupted",{method="beast_max_links"},7) end)
		assert.has_error(function() simulator.perform(source.."\nSockets cannot be modified",{method="beast_max_links"},7) end)
		assert.has_error(function() simulator.perform(source:gsub("R%-G B","R A"),{method="beast_max_links"},7) end)
		assert.has_error(function() simulator.perform(source.."\nSockets: R G",{method="beast_max_links"},7) end)
		local project={id="unique-link",title="Links",slot="Weapon 2",startingItem=source,goals={},steps={}}
		build.savers.CraftingProjects:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		assert.matches("Sockets: R%-G B",control.itemMods.list[1][1])
		assert.is_true(control.link:IsEnabled());assert.matches("Black Morrigan",control.link.tooltipText());control.link:Click();assert.is_false(control.link:IsEnabled())
		assert.matches("Sockets: R%-G%-B",control.itemMods.list[1][1])
		assert.matches("already fully linked",control.link.tooltipText())
		control.undo:Click();assert.is_true(control.link:IsEnabled());assert.is_true(control.omen:IsEnabled());control.omen:Click();control.keep:Click()
		assert.equal(result.itemText,build.savers.CraftingProjects.projects[1].targetItem)
		main.popups={}
	end)
	it("does not display inferred sockets when the item text omits them",function()
		local project={id="unknown-unique-sockets",title="Unknown sockets",slot="Weapon 2",startingItem=shield:gsub("\nSockets: R%-G B",""),goals={},steps={}}
		build.savers.CraftingProjects:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		for _,row in ipairs(control.itemMods.list) do assert.is_nil(row[1]:find("Sockets:",1,true)) end
		assert.is_false(control.link:IsEnabled());main.popups={}
	end)
	it("whitens unique sockets on the bench and prices corrupted items correctly",function()
		local simulator=require("Modules.CraftingSimulator")
		local source=shield.."\nNote: Keep this property"
		local result=simulator.perform(source,{method="socket_white_bench"},1)
		assert.equal(source:gsub("Sockets: R%-G B","Sockets: W-W W"),result.itemText)
		local windows=source:gsub("\n","\r\n");assert.equal(windows:gsub("Sockets: R%-G B","Sockets: W-W W"),simulator.perform(windows,{method="socket_white_bench"},1).itemText)
		assert.equal(1,result.components["Metadata/Items/Currency/CurrencyConvertToNormal"]);assert.is_nil(result.components["Metadata/Items/Currency/CurrencyCorrupt"])
		assert.equal("Use the crafting bench to make all sockets white (1 Orb of Scouring)",quality.guideAction("socket_white_bench",1,"Armourer's Scrap",false))
		local corrupted=source.."\nCorrupted";local altered=simulator.perform(corrupted,{method="socket_white_bench"},1)
		assert.equal(corrupted:gsub("Sockets: R%-G B","Sockets: W-W W"),altered.itemText)
		assert.equal(1,altered.components["Metadata/Items/Currency/CurrencyConvertToNormal"]);assert.equal(1,altered.components["Metadata/Items/Currency/CurrencyCorrupt"])
		assert.has_error(function() simulator.perform(corrupted,{method="quality"},1) end)
		assert.has_error(function() simulator.perform(corrupted,{method="beast_max_links"},1) end)
		assert.has_error(function() simulator.perform(source.."\nSockets cannot be modified",{method="socket_white_bench"},1) end)
		assert.has_error(function() simulator.perform(source:gsub("R%-G B","R A"),{method="socket_white_bench"},1) end)
		assert.has_error(function() simulator.perform(source.."\nSockets: R G",{method="socket_white_bench"},1) end)
		local project={id="corrupted-white",title="Corrupted sockets",slot="Weapon 2",startingItem=corrupted,goals={},steps={}}
		local store=build.savers.CraftingProjects;store:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		assert.is_true(control.apply:IsEnabled());assert.is_false(control.link:IsEnabled());assert.is_true(control.white:IsEnabled())
		control.white:Click();assert.matches("Sockets: W%-W W",control.itemMods.list[1][1]);control.guide:Click()
		assert.matches("Orb of Scouring",control.currencyNote.list[1][1]);assert.matches("Vaal Orb",control.currencyNote.list[2][1])
		assert.equal("socket_white_bench",store.projects[1].steps[1].uniqueCraft.method)
		assert.matches("1 Orb of Scouring and 1 Vaal Orb",store.projects[1].steps[1].action)
		local legacy=copyTable(store.projects[1]);legacy.steps[1].action="Use the crafting bench to make all sockets white"
		assert.equal("socket_white_bench",require("Modules.CraftingProjects").validate(legacy).steps[1].uniqueCraft.method)
		control.undo:Click();assert.is_true(control.redo:IsEnabled());control.redo:Click();assert.is_false(control.white:IsEnabled());main.popups={}
	end)
	it("raises unique armour quality one point while preserving item text",function()
		local result=quality.apply(shield);assert.equal(12,result.beforeQuality);assert.equal(13,result.quality);assert.equal("Armourer's Scrap",result.resource)
		local original=new("Item"):Item(shield);local item=new("Item"):Item(result.itemText)
		assert.equal(original.title,item.title);assert.equal(original.baseName,item.baseName);assert.equal(13,item.quality)
		assert.same(original.sockets,item.sockets);assert.same(original.explicitModLines,item.explicitModLines);assert.same(original.implicitModLines,item.implicitModLines)
		assert.equal(14,quality.apply(result.itemText).quality)
		local extra=shield.."\nNote: Preserve unknown fields"
		assert.equal(extra:gsub("Quality: 12","Quality: 13"),quality.apply(extra).itemText)
		assert.has_error(function() quality.apply(shield.."\nQuality: 12") end)
		local noQuality=shield:gsub("\nQuality: 12","")
		assert.equal(noQuality.."\nQuality: 1",quality.apply(noQuality).itemText)
	end)
	it("exposes deterministic unique quality to AI actions without an ordinary state",function()
		local simulator=require("Modules.CraftingSimulator")
		local first=simulator.perform(shield,{method="quality"},1)
		assert.equal(13,first.uniqueQuality.quality);assert.is_nil(first.state)
		assert.equal(1,first.components[first.uniqueQuality.resourceKey])
		local second=simulator.perform(first.itemText,{method="quality"},2)
		assert.equal(14,second.uniqueQuality.quality)
		assert.has_error(function() simulator.perform(shield,{method="quality"},1,{}) end)
		assert.has_error(function() simulator.perform(shield,{method="quality",extra=true},1) end)
	end)
	it("catalogues supported unique crafts and their current availability",function()
		local simulator=require("Modules.CraftingSimulator")
		local catalog=simulator.catalog(shield,"",50,nil,"3_30")
		assert.is_true(catalog.uniqueCrafting);assert.equal(17,#catalog.uniqueActions);assert.equal(14,#catalog.socketCrafts)
		assert.same(require("Modules.CraftingItemStats").itemValues(new("Item"):Item(shield)),catalog.nativeStats);assert.is_true(catalog.nativeStats.Armour>0)
		local byMethod={};for _,action in ipairs(catalog.uniqueActions) do if action.method~="socket_bench" or action.action.linked then byMethod[action.method]=action end end
		assert.is_true(byMethod.quality.available);assert.is_true(byMethod.beast_max_links.available);assert.is_true(byMethod.socket_white_bench.available)
		local corrupted=simulator.catalog(shield.."\nCorrupted","",50)
		byMethod={};for _,action in ipairs(corrupted.uniqueActions) do if action.method~="socket_bench" or action.action.linked then byMethod[action.method]=action end end
		assert.is_false(byMethod.quality.available);assert.is_false(byMethod.beast_max_links.available);assert.is_true(byMethod.socket_white_bench.available);assert.is_true(byMethod.socket_bench.available)
		assert.equal(3,byMethod.socket_bench.components["Metadata/Items/Currency/CurrencyRerollSocketLinks"]);assert.equal(3,byMethod.socket_bench.components["Metadata/Items/Currency/CurrencyCorrupt"])
		local proposed={id="ai-guide",title="AI guide",slot="Weapon 2",startingItem=shield.."\nCorrupted",goals={},steps={byMethod.socket_bench.guideStep}}
		assert.equal("socket_bench",require("Modules.CraftingProjects").validate(proposed).steps[1].uniqueCraft.method)
		assert.equal(1,byMethod.socket_white_bench.components["Metadata/Items/Currency/CurrencyCorrupt"])
		local filtered=simulator.catalog(shield,"omen",50);assert.equal(3,#filtered.uniqueActions);assert.is_false(byMethod.omen_jeweller.available)
		assert.has_error(function() simulator.catalog(shield,"",50,{}) end)
	end)
	it("links unique sockets at the bench and saves the costs in a recipe",function()
		local simulator=require("Modules.CraftingSimulator");local fusing="Metadata/Items/Currency/CurrencyRerollSocketLinks";local vaal="Metadata/Items/Currency/CurrencyCorrupt"
		for _,corrupted in ipairs({false,true}) do
			local raw=shield..(corrupted and "\nCorrupted" or "");local action={method="socket_bench",count=3,linked=true}
			local result=simulator.perform(raw,action,1);assert.matches("Sockets: R%-G%-B",result.itemText)
			assert.equal(3,result.components[fusing]);assert.equal(corrupted and 3 or nil,result.components[vaal])
			assert.has_error(function() simulator.perform(raw,{method="socket_bench",count=2,linked=true},1) end)
			local recipe={steps={action},targets={},requirements={links=3}};local run=simulator.simulate(raw,recipe,{trials=1,maxActions=2})
			assert.is_true(run.sampleSuccess);assert.equal(result.itemText,run.sampleItem)
			local project={id=corrupted and "bench-corrupted" or "bench-normal",title="Bench links",slot="Weapon 2",startingItem=raw,goals={},steps={}}
			local store=build.savers.CraftingProjects;store:Upsert(project);local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
			assert.is_true(control.benchLink:IsEnabled());control.benchLink:Click();control.guide:Click()
			local saved=store.projects[#store.projects];assert.equal("socket_bench",saved.steps[1].uniqueCraft.method)
			assert.matches("3 Orbs of Fusing",saved.steps[1].action);if corrupted then assert.matches("3 Vaal Orbs",saved.steps[1].action) end
			local filters=require("Modules.LootFilters");local rules=filters.generate(build,filters.profile("bench-filter","Bench filter"));local fusingRule,vaalRule
			for _,rule in ipairs(rules) do if rule.origin=="craft:"..project.id then fusingRule=fusingRule or rule.text:find("Orb of Fusing",1,true);vaalRule=vaalRule or rule.text:find("Vaal Orb",1,true) end end
			assert.is_truthy(fusingRule);if corrupted then assert.is_truthy(vaalRule) end
			control.recipe:Click();saved=store.projects[#store.projects];assert.same(action,saved.nativeRecipe.steps[1])
			main.popups={}
		end
	end)
	it("changes unique socket counts and keeps sequential bench actions",function()
		local sim=require("Modules.CraftingSimulator");local unique=require("Modules.CraftingUniqueQuality")
		local source="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B\n+40% to Fire Resistance"
		local tabula="Rarity: UNIQUE\nTabula Rasa\nSimple Robe\nItem Level: 86\nSockets: W-W-W-W-W-W"
		assert.matches("fixes its socket count",unique.socketCountReason(tabula,2))
		for _,item in ipairs({{"Crest of Desire","Fluted Bascinet"},{"Crown of the Tyrant","Magistrate Crown"},{"The Squire","Elegant Round Shield"},{"Loreweave","Elegant Ringmail"},{"The Geomantic Gyre","Highborn Staff"}}) do
			local partial="Rarity: UNIQUE\n"..item[1].."\n"..item[2].."\nItem Level: 86\nSockets: W"
			assert.matches("fixes its socket count",unique.socketCountReason(partial,2))
		end
		assert.matches("fixes its socket count",unique.socketCountReason(source.."\nHas 1 Socket",2))
		assert.matches("Abyssal sockets",unique.socketCountReason(source.."\nHas 1 Abyssal Socket",2))
		for _,item in ipairs({{"Bubonic Trail","Murder Boots"},{"Tombfist","Steelscale Gauntlets"},{"Shroud of the Lightless","Carnal Armour"},{"Lightpoacher","Great Crown"},{"Wraithlord","Bone Circlet"}}) do
			local partial="Rarity: UNIQUE\n"..item[1].."\n"..item[2].."\nItem Level: 86\nSockets: W"
			assert.matches("Abyssal sockets",unique.socketCountReason(partial,2))
		end
		assert.is_nil(unique.socketCountReason(source.."\nHas 1 Socketed Gem",2))
		local crown="Rarity: UNIQUE\nCrown of the Tyrant\nMagistrate Crown\nItem Level: 86\nSockets: W"
		local options=sim.catalog(crown,"",50).uniqueActions;for _,entry in ipairs(options) do if entry.guideStep.uniqueCraft.method=="socket_count_bench" then assert.is_false(entry.available);assert.matches("fixes its socket count",entry.unavailableReason) end end
		local locked={id="fixed-socket-ui",title="Fixed socket",slot="Helmet",startingItem=crown,goals={},steps={}};build.savers.CraftingProjects:Upsert(locked)
		local lockedControl=require("Classes.CraftingUniqueQualityControl").Open(build,locked);assert.is_true(lockedControl.socketCount:IsEnabled());assert.matches("socket%-colour",lockedControl.socketCount.tooltipText());main.popups={}
		for _,corrupted in ipairs({false,true}) do
			local raw=source..(corrupted and "\nCorrupted" or "");local action={method="socket_bench",count=4}
			local changed=sim.perform(raw,action,1);assert.matches("Sockets: R%-G B W",changed.itemText)
			assert.equal(10,changed.components["Metadata/Items/Currency/CurrencyRerollSocketNumbers"]);assert.equal(corrupted and 10 or nil,changed.components["Metadata/Items/Currency/CurrencyCorrupt"])
			assert.matches("Sockets: R%-G",sim.perform(changed.itemText,{method="socket_bench",count=2},1).itemText)
			local priced=sim.simulate(raw,{steps={{method="socket_bench",count=2}},targets={},requirements={exactSockets=2}},{trials=1,maxActions=1,currency="chaos",actionPrices={["socket_bench:2:false"]=7}})
			assert.equal(7,priced.meanCost);assert.equal("socket_bench:2:false",priced.stepPriceKeys[1].priceKey)
			local warned=false;for _,warning in ipairs(priced.warnings) do if warning.code=="unique_socket_count_assumptions" then warned=true end end;assert.is_true(warned)
			assert.has_error(function() sim.perform(raw.."\nSockets cannot be modified",action,1) end)
			assert.has_error(function() sim.perform(raw.."\nHas 3 Sockets",action,1) end)
			local project={id=corrupted and "count-corrupted" or "count-normal",title="Socket count",slot="Helmet",startingItem=raw,goals={},steps={}}
			local store=build.savers.CraftingProjects;store:Upsert(project);local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
			control.socketCount:Click();local popup=main.popups[1].controls;popup.count:SelByValue(4,"val");popup.apply:Click()
			control.undo:Click();assert.is_true(control.redo:IsEnabled());control.redo:Click();assert.is_true(control.benchLink:IsEnabled())
			control.benchLink:Click();control.guide:Click();control.recipe:Click()
			local saved=store.projects[#store.projects];assert.equal("socket_count_bench",saved.steps[1].uniqueCraft.method);assert.equal(4,saved.steps[1].uniqueCraft.count);assert.equal("socket_bench",saved.steps[2].uniqueCraft.method)
			assert.equal(4,saved.nativeRecipe.requirements.exactSockets);local run=sim.simulate(raw,saved.nativeRecipe,{trials=1,maxActions=3});assert.is_true(run.sampleSuccess);assert.equal(saved.targetItem,run.sampleItem)
			local recovery=require("Modules.PlanningRecovery").clean("uniqueQuality",{plan={kind="uniqueQuality",project=project,itemText=changed.itemText,history={raw},actions={"socket_count_bench:4"},redo={}}});assert.equal("socket_count_bench:4",recovery.plan.actions[1])
			local filters=require("Modules.LootFilters");local rules=filters.generate(build,filters.profile("count-filter","Socket pickup"));local names={};for _,rule in ipairs(rules) do if rule.origin=="craft:"..project.id then names[rule.title]=true end end
			assert.is_true(names["Jeweller's Orb"]);assert.is_true(names["Orb of Fusing"]);if corrupted then assert.is_true(names["Vaal Orb"]) end
			main.popups={}
		end
	end)
	it("requires the corruption marker for known always-corrupted uniques",function()
		for _,item in ipairs({{"Skin of the Lords","Simple Robe"},{"Shadowstitch","Sacrificial Garb"},{"Glimpse of Chaos","Vaal Mask"},{"Malachai's Vision","Praetor Crown"}}) do
			local raw="Rarity: UNIQUE\n"..item[1].."\n"..item[2].."\nItem Level: 86\nSockets: "..(item[1]=="Skin of the Lords" and "R-G-B-R-G-B" or "R G B")
			local ok,reason=pcall(quality.inspect,raw);assert.is_false(ok);assert.matches("This unique is always corrupted",reason,1,true)
			local parsed=quality.inspect(raw.."\nCorrupted");assert.is_true(parsed.corrupted)
		end
		local normal="Rarity: UNIQUE\nSkin of the Loyal\nSimple Robe\nItem Level: 86\nSockets: R-G-B-R-G-B"
		assert.is_false(quality.inspect(normal).corrupted or false)
	end)
	it("initializes fixed unique restrictions on the first inspection",function()
		local cached=package.loaded["Modules.CraftingUniqueQuality"]
		for _,item in ipairs({{"Tabula Rasa","Simple Robe","W-W-W-W-W-W"},{"Oni-Goroshi","Charan's Sword","R-G-B-W-R-G"}}) do
			package.loaded["Modules.CraftingUniqueQuality"]=nil;local fresh=require("Modules.CraftingUniqueQuality")
			local parsed=fresh.inspect("Rarity: UNIQUE\n"..item[1].."\n"..item[2].."\nItem Level: 86\nSockets: "..item[3]);assert.equal(item[1],parsed.title)
		end
		package.loaded["Modules.CraftingUniqueQuality"]=cached
	end)
	it("rejects impossible Tabula and Oni socket layouts",function()
		for _,item in ipairs({{"Tabula Rasa","Simple Robe","W-W-W-W-W-W","R-W-W-W-W-W","six linked white sockets"},{"Oni-Goroshi","Charan's Sword","R-G-B-W-R-G","R-G-B","six linked sockets"}}) do
			local raw="Rarity: UNIQUE\n"..item[1].."\n"..item[2].."\nItem Level: 86";local missing=quality.inspect(raw);assert.is_truthy(missing)
			local valid=quality.inspect(raw.."\nSockets: "..item[3]);assert.is_truthy(valid)
			local ok,reason=pcall(quality.inspect,raw.."\nSockets: "..item[4]);assert.is_false(ok);assert.matches(item[5],reason,1,true)
		end
	end)
	it("rejects impossible explicit socket layouts on Skin uniques",function()
		for _,name in ipairs({"Skin of the Loyal","Skin of the Lords"}) do
			local raw="Rarity: UNIQUE\n"..name.."\nSimple Robe\nItem Level: 86\nSockets: R G B"..(name=="Skin of the Lords" and "\nCorrupted" or "")
			local ok,reason=pcall(quality.inspect,raw);assert.is_false(ok);assert.matches("six linked sockets",reason,1,true)
			local valid=quality.inspect((raw:gsub("Sockets: R G B","Sockets: R-G-B-R-G-B")));assert.is_truthy(valid)
		end
	end)
	it("rejects socket changes for known immutable uniques with partial text",function()
		for _,name in ipairs({"Skin of the Loyal","Skin of the Lords"}) do
			local raw="Rarity: UNIQUE\n"..name.."\nSimple Robe\nItem Level: 86\nSockets: R-G-B-R-G-B"..(name=="Skin of the Lords" and "\nCorrupted" or "")
			assert.matches("sockets cannot be modified",quality.socketCountReason(raw,4),1,true)
			assert.matches("sockets cannot be modified",quality.whiteReason(raw),1,true)
			assert.matches("sockets cannot be modified",quality.linkReason(raw,"socket_bench"),1,true)
			assert.has_error(function() quality.socketCount(raw,4) end);assert.has_error(function() quality.white(raw) end)
			local project={id=name=="Skin of the Loyal" and "loyal" or "lords",title=name,slot="Body Armour",startingItem=raw,goals={},steps={}}
			build.savers.CraftingProjects:Upsert(project);local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
			assert.is_false(control.white:IsEnabled());assert.is_false(control.omen:IsEnabled());assert.is_false(control.benchLink:IsEnabled());assert.is_false(control.socketCount:IsEnabled());main.popups={}
		end
	end)
	it("calculates deterministic unique crafts against supported item goals",function()
		local simulator=require("Modules.CraftingSimulator")
		local result=simulator.calculate(shield,{method="omen_connections"},{},nil,{requirements={sockets=3,links=3,socketColours="RGB",linkedColours=true,minQuality=12}})
		assert.is_true(result.uniqueCrafting);assert.is_false(result.sampled);assert.equal(100,result.successChance);assert.matches("Sockets: R%-G%-B",result.sampleItem)
		result=simulator.calculate(shield,{method="socket_white_bench"},{},nil,{requirements={socketColours="WWW",linkedColours=true}})
		assert.equal(0,result.successChance);assert.matches("Sockets: W%-W W",result.sampleItem)
		result=simulator.calculate(shield.."\nCorrupted",{method="socket_white_bench"},{},nil,{requirements={socketColours="WWW",corrupted=true}})
		assert.equal(100,result.successChance);assert.equal(1,result.components["Metadata/Items/Currency/CurrencyCorrupt"])
		result=simulator.calculate(shield,{method="quality"},{},nil,{requirements={minQuality=14}});assert.equal(0,result.successChance)
		local native=require("Modules.CraftingItemStats").itemValues(new("Item"):Item(result.sampleItem));assert.same(native,result.nativeStats)
		result=simulator.calculate(shield,{method="quality"},{},nil,{requirements={nativeStats={Armour=native.Armour}}});assert.equal(100,result.successChance)
		result=simulator.calculate(shield,{method="quality"},{},nil,{requirements={nativeStats={Armour=native.Armour+1}}});assert.equal(0,result.successChance)
		result=simulator.calculate(shield,{method="quality"},{},nil,{requirements={nativeStats={PhysicalDPS=0}}});assert.equal(0,result.successChance)
		local weaponResult=simulator.calculate(weapon,{method="quality"},{},nil,{requirements={nativeStats={PhysicalDPS=1}}})
		assert.equal(100,weaponResult.successChance);assert.is_true(weaponResult.nativeStats.PhysicalDPS>1)
		assert.same(require("Modules.CraftingItemStats").itemValues(new("Item"):Item(weaponResult.sampleItem)),weaponResult.nativeStats)
		assert.has_error(function() simulator.calculate(shield,{method="quality"},{{anyOf={"Life1"}}},nil,{}) end)
		assert.has_error(function() simulator.calculate(shield,{method="quality"},{},nil,{requirements={openPrefixes=1}}) end)
		assert.has_error(function() simulator.calculate(shield:gsub("\nSockets: R%-G B",""),{method="quality"},{},nil,{requirements={links=3}}) end)
	end)
	it("keeps the chosen unique actions as guide steps without duplicating them",function()
		local project={id="unique-guide",title="Guide",slot="Weapon 2",startingItem=shield,goals={},steps={{action="Acquire the base",done=false}}}
		local store=build.savers.CraftingProjects;store:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		assert.is_false(control.guide:IsEnabled());control.apply:Click();control.apply:Click();control.omen:Click()
		assert.is_true(control.guide:IsEnabled());control.guide:Click();assert.is_false(control.guide:IsEnabled())
		local saved=store.projects[1];assert.equal(3,#saved.steps);assert.equal("Acquire the base",saved.steps[1].action)
		assert.equal("Use 2 Armourer's Scraps",saved.steps[2].action);assert.matches("Omen of Connections",saved.steps[3].action)
		assert.matches("Sockets: R%-G%-B",saved.targetItem)
		control.close:Click();control=require("Classes.CraftingUniqueQualityControl").Open(build,saved);assert.is_false(control.guide:IsEnabled())
		control.apply:Click();assert.is_true(control.guide:IsEnabled());control.guide:Click()
		saved=store.projects[1];assert.equal(4,#saved.steps);assert.equal("Use 1 Armourer's Scrap",saved.steps[4].action)
		control.undo:Click();assert.is_false(control.guide:IsEnabled());assert.matches("no longer follows",control.guide.tooltipText());assert.is_true(control.redo:IsEnabled())
		control.redo:Click();assert.is_false(control.redo:IsEnabled());assert.matches("already in the guide",control.guide.tooltipText());control.undo:Click()
		control.close:Click();local changed=copyTable(saved);changed.steps[1].action="Changed starting step"
		control=require("Classes.CraftingUniqueQualityControl").Open(build,changed);assert.is_false(control.guide:IsEnabled());assert.matches("saved guide changed",control.guide.tooltipText())
		local legacy={kind="uniqueQuality",project=saved,itemText=saved.targetItem,history={shield}}
		main.popups={};control=require("Classes.CraftingUniqueQualityControl").Open(build,saved,nil,legacy)
		assert.is_false(control.guide:IsEnabled());assert.matches("older previews",control.guide.tooltipText())
		control.undo:Click();assert.is_true(control.redo:IsEnabled());control.redo:Click();assert.is_false(control.guide:IsEnabled())
		legacy.actions={"quality"};legacy.savedTrace=string.rep("a",40)
		main.popups={};control=require("Classes.CraftingUniqueQualityControl").Open(build,saved,nil,legacy)
		assert.is_false(control.guide:IsEnabled());assert.matches("cannot be verified",control.guide.tooltipText());main.popups={}
	end)
	it("clears redo when a different unique craft is chosen",function()
		local project={id="unique-redo",title="Redo",slot="Weapon 2",startingItem=shield,goals={},steps={}}
		build.savers.CraftingProjects:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		control.link:Click();control.undo:Click();assert.is_true(control.redo:IsEnabled())
		control.omen:Click();assert.is_false(control.redo:IsEnabled());main.popups={}
	end)
	it("does not invent crafting steps when a loaded target is undone and redone",function()
		local project={id="unique-redo-target",title="Redo target",slot="Weapon 2",startingItem=shield,goals={},steps={}}
		build.savers.CraftingProjects:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		control.apply:Click();control.keep:Click();control.undo:Click();assert.is_true(control.loadTarget:IsEnabled())
		control.loadTarget:Click();control.undo:Click();assert.is_true(control.redo:IsEnabled());control.redo:Click()
		assert.matches("13%%",control.status.label);assert.is_false(control.guide:IsEnabled())
		assert.matches("Loaded or older previews",control.guide.tooltipText());main.popups={}
	end)
	it("lets the user review an edited guide before adding new preview actions",function()
		local project={id="review-guide",title="Review guide",slot="Weapon 2",startingItem=shield,goals={},steps={{action="Acquire the item"}}}
		local store=build.savers.CraftingProjects;store:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		control.apply:Click();control.guide:Click();control.close:Click()
		local changed=copyTable(store.projects[1]);changed.steps[1].action="Acquire the unique shield"
		control=require("Classes.CraftingUniqueQualityControl").Open(build,changed);control.apply:Click()
		assert.is_false(control.guide:IsEnabled());assert.is_true(control.reviewGuide:IsShown());assert.is_true(control.reviewGuide:IsEnabled())
		control.reviewGuide:Click();local browser=main.popups[1].controls
		assert.is_nil(browser.search);assert.matches("Review guide",browser.heading.label)
		local details={};for _,row in ipairs(browser.details.list) do details[#details+1]=row[1] end
		assert.matches("Acquire the unique shield",table.concat(details," "));browser.choose:Click()
		assert.is_true(control.guide:IsEnabled());control.guide:Click()
		local saved=store.projects[1];assert.equal(3,#saved.steps);assert.equal("Acquire the unique shield",saved.steps[1].action);assert.equal("Use 1 Armourer's Scrap",saved.steps[3].action)
		assert.is_false(control.reviewGuide:IsShown());main.popups={}
	end)
	it("keeps a preview as a saved crafting project target",function()
		local project={id="unique-quality",title="Quality",slot="Weapon 2",startingItem=shield,goals={},steps={}}
		local store=build.savers.CraftingProjects;store:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		local ui=require("Modules.PlanningUI")
		assert.is_false(ui.hasDraft(build,"uniqueQuality",project.id))
		control.apply:Click();assert.matches("13%%",control.status.label);assert.is_true(ui.hasDraft(build,"uniqueQuality",project.id))
		assert.matches("Working draft",ui.saveStatus(build));ui.saved(build);assert.matches("Working draft",ui.saveStatus(build))
		control.undo:Click();assert.matches("12%%",control.status.label);assert.is_false(ui.hasDraft(build,"uniqueQuality",project.id))
		control.apply:Click();control.keep:Click();assert.is_false(ui.hasDraft(build,"uniqueQuality",project.id))
		assert.equal(13,select(2,quality.inspect(store.projects[1].targetItem)).quality)
		assert.equal(shield,store.projects[1].startingItem)
		local xml=build:SaveDB("Unique quality");loadBuildFromXML(xml,"Unique quality")
		local saved=build.savers.CraftingProjects.projects[1]
		assert.equal(13,select(2,quality.inspect(saved.targetItem)).quality)
		main.popups={};control=require("Classes.CraftingUniqueQualityControl").Open(build,saved)
		local inspect=quality.inspect;local inspections=0
		quality.inspect=function(...) inspections=inspections+1;return inspect(...) end
		local first=control.loadTarget:IsEnabled();local second=control.loadTarget:IsEnabled();quality.inspect=inspect
		assert.is_true(first);assert.is_true(second);assert.equal(1,inspections)
		control.loadTarget:Click();assert.matches("13%%",control.status.label)
		control.undo:Click();assert.matches("12%%",control.status.label);control.loadTarget:Click();control.apply:Click();control.keep:Click()
		assert.equal(14,select(2,quality.inspect(build.savers.CraftingProjects.projects[1].targetItem)).quality)
		local other=copyTable(saved);other.targetItem=weapon
		control=require("Classes.CraftingUniqueQualityControl").Open(build,other);assert.is_false(control.loadTarget:IsEnabled())
		main.popups={}
	end)
	it("retains session previews and undo history when returning to projects",function()
		local project={id="session-quality",title="Session",slot="Weapon 2",startingItem=shield,goals={},steps={}}
		local store=build.savers.CraftingProjects;store:Upsert(project)
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		control.apply:Click();control.apply:Click();control.close:Click()
		control=require("Classes.CraftingUniqueQualityControl").Open(build,store.projects[1])
		assert.matches("14%%",control.status.label);control.undo:Click();assert.matches("13%%",control.status.label)
		control.close:Click();store:Remove(project.id);assert.is_nil(build.planningUniqueQualityDrafts[project.id]);assert.is_false(require("Modules.PlanningUI").hasDraft(build,"uniqueQuality",project.id))
		store:UndoRemove();assert.is_true(require("Modules.PlanningUI").hasDraft(build,"uniqueQuality",project.id));control=require("Classes.CraftingUniqueQualityControl").Open(build,store.projects[1]);assert.matches("13%%",control.status.label)
		control.undo:Click();assert.matches("12%%",control.status.label)
		main.popups={};newBuild();assert.is_nil(build.planningUniqueQualityDrafts)
	end)
	it("copies session previews only to compatible reviewed builds",function()
		local project={id="copy-quality",title="Original",slot="Weapon 2",startingItem=shield,goals={},steps={}}
		build.savers.CraftingProjects:Upsert(project)
		local workspace=require("Modules.PlanningWorkspace").new(build);build.planningWorkspace=workspace
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		control.apply:Click();control.close:Click()
		local changed=copyTable(project);changed.title="Edited guide"
		local candidate={savers={CraftingProjects={projects={changed}}}}
		workspace:CopyCraftingDrafts(candidate)
		local saved=candidate.planningUniqueQualityDrafts[project.id]
		assert.equal("Edited guide",saved.project.title);assert.equal(13,select(2,quality.inspect(saved.itemText)).quality)
		assert.is_true(require("Modules.PlanningUI").hasDraft(candidate,"uniqueQuality",project.id))
		changed.startingItem=shield:gsub("Quality: 12","Quality: 11")
		workspace:CopyCraftingDrafts(candidate);assert.is_nil(candidate.planningUniqueQualityDrafts[project.id])
		main.popups={}
	end)
	it("uses a whetstone for weapons and refuses unavailable cases",function()
		assert.equal("Blacksmith's Whetstone",quality.apply(weapon).resource)
		assert.has_error(function() quality.apply(shield:gsub("Quality: 12","Quality: 20")) end)
		assert.has_error(function() quality.apply(shield.."\nCorrupted") end)
		assert.has_error(function() quality.apply(shield.."\nMirrored") end)
		assert.has_error(function() quality.apply("Rarity: NORMAL\nIron Hat\nItem Level: 86") end)
		assert.has_error(function() quality.apply("Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nUnidentified") end)
	end)
end)
