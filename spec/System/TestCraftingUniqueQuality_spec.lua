describe("Unique item quality",function()
	local quality=require("Modules.CraftingUniqueQuality")
	local shield="Rarity: UNIQUE\nThe Surrender\nEzomyte Tower Shield\nItem Level: 86\nQuality: 12\nSockets: R-G B\nImplicits: 1\n+5% Chance to Block Attack Damage\n+100 to maximum Life\n+1500 to Armour"
	local weapon="Rarity: UNIQUE\nThe Saviour\nLegion Sword\nItem Level: 86\nQuality: 0\nSockets: R-G-B\n+100% increased Physical Damage"
	before_each(function() newBuild() end)
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
		assert.is_false(control.apply:IsEnabled());assert.is_false(control.link:IsEnabled());assert.is_true(control.white:IsEnabled())
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
		assert.is_true(catalog.uniqueCrafting);assert.equal(7,#catalog.uniqueActions);assert.equal(6,#catalog.socketCrafts)
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
		local filtered=simulator.catalog(shield,"omen",50);assert.equal(1,#filtered.uniqueActions);assert.equal("omen_connections",filtered.uniqueActions[1].method)
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
		local lockedControl=require("Classes.CraftingUniqueQualityControl").Open(build,locked);assert.is_false(lockedControl.socketCount:IsEnabled());assert.matches("fixes its socket count",lockedControl.socketCount.tooltipText());main.popups={}
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
