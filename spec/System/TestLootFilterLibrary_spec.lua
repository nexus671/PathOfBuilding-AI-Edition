describe("Visual filter catalogue",function()
	local filters=require("Modules.LootFilters")
	local parser=require("Modules.LootFilterParser")
	local library=require("Modules.LootFilterLibrary")
	before_each(function() newBuild();main.popups={} end)
	after_each(function() main.popups={} end)
	it("does not guess relational text comparisons while retaining modifier counts",function()
		for _,condition in ipairs({'BaseType > "Gold"','Class <= "Currency"','HasExplicitMod > "Fire"','HasEnchantment < "Damage"'}) do
			local parsed=parser.parse('Hide\n '..condition..'\nShow')
			assert.matches('cannot verify this text comparison',parsed.diagnostics[1].warning)
			local result=parser.simulate(parsed,{BaseType="Gold",Class="Currency",Identified=true,HasExplicitMod={"Fire"},HasEnchantment={"Damage"}})
			assert.equal("unknown",result.status)
			assert.matches("Relational text comparison",result.reasons[1])
		end
		local item={Identified=true,HasExplicitMod={"Fire","Cold"},HasEnchantment={"Damage","Speed"}}
		for _,condition in ipairs({'HasExplicitMod >=2 "Fire" "Cold"','HasEnchantment >=2 "Damage" "Speed"'}) do
			local parsed=parser.parse('Hide\n '..condition..'\nShow')
			assert.equal(0,#parsed.diagnostics)
			assert.equal("Hide",parser.simulate(parsed,item).action)
		end
	end)
	it("shows every rule condition with its comparison and quoted values",function()
		local block=parser.parse('Show\n BaseType == "Gold" "Gold Ring"\n StackSize >= 50\n HasExplicitMod >=1 "Fire Resistance"').rules[1]
		assert.same({'Base Type == "Gold" "Gold Ring"','Stack Size >= 50','Has Explicit Mod >=1 "Fire Resistance"'},library.conditionSummaries(block))
		assert.same({},library.conditionSummaries(parser.parse('Show').rules[1]))
	end)
	it("shows the selected rule conditions and resets the details when changing rules",function()
		local ui=require("Modules.HeadlessUI").install({width=960,height=640})
		local ok,err=pcall(function()
			build.viewMode="CONFIG";ui:bind(build);ui:click("aiBuild");ui:click("nav_filters")
			ui:click("create2");ui:text("title","Rule details");ui:click("viewCustomize");ui:choose("source","Base filter")
			local controls=build.planningWorkspace.controls;local text={}
			for _,row in ipairs(controls.detail.list) do text[#text+1]=row[1] or "" end
			assert.is_true(table.concat(text," "):find("Matching conditions",1,true)~=nil)
			controls.detail.controls.scrollBar.offset=80;controls.rules.planningMove(1)
			assert.equal(0,controls.detail.controls.scrollBar.offset)
		end)
		ui:restore();main.popups={};assert.is_true(ok,err)
	end)
	it("compares explicit vendor-recipe examples at the selected levels",function()
		local profile=filters.profile("vendor-scenes","Vendor scenes");local scene=library.scene(profile,build,"Vendor recipes",0,65,72)
		assert.equal(20,#scene);for _,item in ipairs(scene) do assert.equal(65,item.AreaLevel);assert.equal(72,item.ItemLevel) end
		local function matches(condition,item) return parser.simulate(parser.parse("Hide\n "..condition.."\nShow"),item).action end
		assert.equal("Hide",matches("SocketGroup RGB",scene[1]));assert.equal("Hide",matches("Sockets 6",scene[2]));assert.equal("Hide",matches("LinkedSockets 6",scene[3]))
		assert.equal("Hide",matches("Quality >= 1",scene[4]));assert.equal("Hide",matches("Rarity Rare\n Identified False\n ItemLevel >= 60",scene[5]))
		local rotated=library.scene(profile,build,"Vendor recipes",1,65,72);assert.equal(scene[2].BaseType,rotated[1].BaseType)
		local page=filters.simulateScene(profile,"Vendor recipes",0,65,72,0,10);assert.equal(20,page.total);assert.equal("Iron Hat",page.results[1].sample.BaseType)
		local second=filters.simulateScene(profile,"Vendor recipes",0,65,72,10,10);assert.equal(10,#second.results);assert.equal("Prismatic Tincture",second.results[5].sample.BaseType)
		for i,rarity in ipairs({"Normal","Magic","Rare","Unique"}) do assert.equal("Jade Amulet",scene[15+i].BaseType);assert.equal(rarity,scene[15+i].Rarity) end
		assert.is_true(scene[16].Identified);assert.is_nil(scene[19].UnidentifiedItemTier)
		local label=require("Classes.LootFilterWorkspace").vendorLabel
		for i,value in ipairs({"3 linked colours","6 sockets","6 linked","Quality gem","Rare piece"}) do assert.equal(value,label(scene[i])) end
		assert.equal("Quality weapon",label(scene[11]));assert.equal("Quality armour",label(scene[12]))
		assert.equal("Quality flask",label(scene[13]));assert.equal("Quality flask",label(scene[14]));assert.equal("Quality tincture",label(scene[15]))
		for i=13,15 do assert.equal("Hide",matches('Class == "Life Flasks" "Utility Flasks" "Tinctures"\n Quality >= 1',scene[i])) end
		assert.equal("Vaal Arc",scene[20].BaseType);assert.equal("Vaal gem",label(scene[20]));assert.is_nil(label({Class="Skill Gems",BaseType="Vaal Fiction"}))
		assert.is_nil(label({SocketGroup="R G B"}))
	end)
	it("shows the identifying properties of a vendor-recipe sample",function()
		local profile=filters.profile("vendor-ui","Vendor UI");local scene=library.scene(profile,build,"Vendor recipes",0,65,72)
		local mounted;local layout={width=1280,height=720,navigate=function() end,mount=function(_,_,_,controls) mounted=controls end}
		require("Classes.LootFilterWorkspace").Open(build,{data={schemaVersion=1,activeId=profile.id,profiles={profile}},selected=profile.id,page="Simulate",sceneKind="Vendor recipes",sample=scene[1]},layout,{})
		assert.is_truthy(mounted.drop1.tooltipText:find("Sockets: R-G-B",1,true))
		local found=false;for _,control in pairs(mounted) do if type(control)=="table" and type(control.tooltipText)=="string" and control.tooltipText:find("Quality: 20%",1,true) then found=true end end;assert.is_true(found)
	end)
	it("finds Gold with currencies and generates its actual item class",function()
		local rule={text='Show\n BaseType == "Gold"\n StackSize >= 500'}
		assert.equal("Currency",library.category(rule));assert.equal("Currency",library.category({text='Show\n Class == "Gold"'}))
		assert.not_equal("Currency",library.category({text='Show\n BaseType == "Gold Ring"\n Rarity Rare'}))
		assert.not_equal("Currency",library.category({text='Show\n BaseType "Gold"'}))
		local sample=library.sample(rule);assert.equal("Gold",sample.BaseType);assert.equal("Gold",sample.Class);assert.equal(0,sample.Sockets)
		assert.equal("Hide",parser.simulate(parser.parse('Hide\n Class == "Gold"\nShow'),sample).action)
		local byClass=library.sample({text='Show\n Class == "Gold"'});assert.equal("Gold",byClass.BaseType);assert.equal("Gold",byClass.Class)
		local profile=filters.profile("gold-test","Gold test");local count=0
		for _,entry in ipairs(library.catalog(profile)) do if entry.rule.title=="Gold" then count=count+1;assert.equal("Currency",entry.category);assert.equal("Gold",entry.sample.Class) end end
		assert.is_true(count>0)
	end)
	it("uses unambiguous client classes for examples without guessing duplicate names",function()
		for _,case in ipairs({{"Contract: Laboratory","Contracts"},{"Ancient Wombgift","Wombgifts"},{"The Fortunate","Divination Cards"},{"Allflame Ember of Kulemak","Stackable Currency"}}) do
			local sample=library.sample({text='Show\n BaseType == "'..case[1]..'"'})
			assert.equal(case[2],sample.Class,case[1])
			assert.equal("Show",parser.simulate(parser.parse('Show\n Class == "'..case[2]..'"\nHide'),sample).action)
		end
		local name="Primitive Chaotic Resonator"
		local unknown=library.sample({text='Show\n BaseType == "'..name..'"'})
		assert.is_nil(unknown.Class)
		assert.equal("unknown",parser.simulate(parser.parse('Show\n Class == "Delve Stackable Socketable Currency"\nHide'),unknown).status)
		local explicit=library.sample({text='Show\n BaseType == "'..name..'"\n Class == "Delve Stackable Socketable Currency"'})
		assert.equal("Delve Stackable Socketable Currency",explicit.Class)
		assert.is_nil(library.sample({text='Show\n BaseType == "Map"'}).Class)
		assert.is_nil(library.sample({text='Show\n BaseType == "Unfamiliar Base"'}).Class)
	end)
	it("groups Expedition and Heist encounter items without reclassifying Heist gear",function()
		local logbook={text='Show\n BaseType == "Expedition Logbook"'}
		assert.equal("League items",library.category(logbook))
		local example=library.sample(logbook);assert.equal("Expedition Logbooks",example.Class);assert.equal(0,example.Sockets)
		assert.equal("Show",parser.simulate(parser.parse('Show\n Class == "Expedition Logbooks"\nHide'),example).action)
		for _,class in ipairs({"Contracts","Blueprints"}) do
			local rule={text='Show\n Class == "'..class..'"\n Rarity Normal Magic Rare'}
			assert.equal("League items",library.category(rule));local sample=library.sample(rule)
			assert.equal(class,sample.Class);assert.equal(0,sample.Sockets)
			assert.equal("Show",parser.simulate(parser.parse(rule.text),sample).action)
		end
		assert.equal("League items",library.category({text='Show\n Class == "Contracts" "Blueprints"'}))
		assert.not_equal("League items",library.category({text='Show\n Class == "Heist Cloaks"\n Rarity Rare'}))
		assert.not_equal("League items",library.category({text='Show\n Class == "Contracts" "Heist Cloaks"'}))
		local found={};for _,entry in ipairs(library.catalog(filters.profile("league-test","League test"))) do
			local tag=entry.rule.text:match('%$type%-%>([%w_%-]+)%-%>([%w_%-]+)')
			if entry.rule.title=="Expedition Logbook" then assert.equal("League items",entry.category);assert.equal("Expedition Logbooks",entry.sample.Class);found.logbook=true end
			if tag=="heist" and (entry.rule.text:find('Class == "Contracts"',1,true) or entry.rule.text:find('Class == "Blueprints"',1,true)) then assert.equal("League items",entry.category);found.heist=true end
		end
		assert.is_true(found.logbook);assert.is_true(found.heist)
	end)
	it("tests complete socket colours entered without a separate count",function()
		local saved;require("Classes.LootFilterControl").EditSample({BaseType="Iron Hat"},function(item) saved=item end)
		local editor=main.popups[1].controls;editor.SocketColours:SetText("R-G B A");editor.useSample:Click()
		assert.is_nil(saved.Sockets);assert.equal("R-G B A",saved.SocketColours)
		assert.equal("Show",parser.simulate(parser.parse("Show\n Sockets >= 4\nHide"),saved).action)
	end)
	it("tests complete socket groups entered without a separate link count",function()
		local saved;require("Classes.LootFilterControl").EditSample({BaseType="Iron Hat"},function(item) saved=item end)
		local editor=main.popups[1].controls;assert.matches("total in Sockets",editor.SocketGroup.tooltipText,1,true);editor.Sockets:SetText("4");editor.SocketGroup:SetText("R-G B A");editor.useSample:Click()
		assert.is_nil(saved.LinkedSockets)
		assert.equal("Show",parser.simulate(parser.parse("Show\n LinkedSockets = 2\nHide"),saved).action)
	end)
	it("generates named transfigured-gem examples without inventing a variant",function()
		local rule={text='Show\n TransfiguredGem "Leap Slam"\nHide'}
		local sample=library.sample(rule);assert.equal("Leap Slam",sample.TransfiguredGem)
		assert.equal("Skill Gems",sample.Class);assert.is_nil(sample.BaseType)
		local visual=require("Modules.LootFilterVisuals");assert.equal("Leap Slam (transfigured example)",visual.sampleName(sample));assert.equal("Unknown item",visual.sampleName({}));assert.equal("Iron Hat",visual.sampleName({BaseType="Iron Hat",TransfiguredGem="Leap Slam"}))
		assert.equal("Show",parser.simulate(parser.parse(rule.text),sample).action)
		local withClass=library.sample({text='Show\n Class == "Skill Gems"\n TransfiguredGem "Leap Slam"'})
		assert.equal("Skill Gems",withClass.Class);assert.is_nil(withClass.BaseType)
		local any=library.sample({text="Show\n TransfiguredGem True"});assert.is_true(any.TransfiguredGem);assert.is_nil(any.BaseType);assert.equal("Transfigured gem example",visual.sampleName(any))
		local ordinary=library.sample({text="Show\n TransfiguredGem False"});assert.is_false(ordinary.TransfiguredGem)
	end)
	it("shows only generated build targets in the build-target scene",function()
		local profile=filters.profile("targets","Targets")
		profile.rules={filters.rule("personal","Personal rule",{'BaseType == "Divine Orb"'})}
		assert.same({},library.scene(profile,build,"Build targets",0,70,75))
		build.savers.CraftingProjects:Upsert({id="hat",title="Craft helmet",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={}})
		local scene=library.scene(profile,build,"Build targets",0,70,75)
		assert.equal(1,#scene);assert.equal("Iron Hat",scene[1].BaseType)
		assert.equal(70,scene[1].AreaLevel);assert.equal(75,scene[1].ItemLevel)
		assert.same({},library.scene(profile,build,"Build targets",0,70,75,{}))
	end)
	it("does not invent an item tier for generated unidentified gear",function()
		local profile=filters.profile("unknown-tier","Unknown tier")
		local scene=library.scene(profile,build,"Mixed drops",0,83,86);local byName={}
		for _,item in ipairs(scene) do byName[item.BaseType]=item end
		local filter=parser.parse('Show\n UnidentifiedItemTier >= 4\nHide')
		assert.is_nil(byName["Iron Hat"].UnidentifiedItemTier)
		assert.equal("unknown",parser.simulate(filter,byName["Iron Hat"]).status)
		assert.equal(0,byName["Chaos Orb"].UnidentifiedItemTier)
		local sample=library.sample({text='Show\n Rarity Rare\n BaseType "Iron Hat"'})
		assert.is_nil(sample.UnidentifiedItemTier);assert.equal("unknown",parser.simulate(filter,sample).status)
		local explicit=library.sample({text='Show\n Rarity Rare\n BaseType "Iron Hat"\n UnidentifiedItemTier >= 4'})
		assert.equal(4,explicit.UnidentifiedItemTier);assert.equal("Show",parser.simulate(filter,explicit).action)
		require("Classes.LootFilterControl").EditSample(explicit,function() end);local editor=main.popups[1].controls
		editor.Rarity:SetText("Magic",true);assert.equal("",editor.UnidentifiedItemTier.buf)
		editor.UnidentifiedItemTier:SetText("4",true);editor.BaseType:SetText("Vaal Regalia",true);assert.equal("",editor.UnidentifiedItemTier.buf);main:ClosePopup()
		profile.mode="Ruthless";local ruthless=library.scene(profile,build,"Mixed drops",0,83,86)
		for _,item in ipairs(ruthless) do if item.BaseType=="Iron Hat" then assert.equal(0,item.UnidentifiedItemTier) end end
		local tiers=library.scene(profile,build,"Tiered gear",0,83,86);assert.equal(1,#tiers);assert.equal(0,tiers[1].UnidentifiedItemTier)
	end)
	it("provides reproducible mapping and flask examples with their filter classes",function()
		local profile=filters.profile("test","Test")
		for _,case in ipairs({{kind="Maps & threads",base="Map (Tier 1)",class="Maps",other="Breach Thread",otherClass="Map Fragments"},
			{kind="Flasks & tinctures",base="Sacred Life Flask",class="Life Flasks",other="Prismatic Tincture",otherClass="Tinctures"},
			{kind="Crafting materials",base="Hollow Fossil",class="Stackable Currency",other="Powerful Chaotic Resonator",otherClass="Delve Stackable Socketable Currency"},
			{kind="Heist & Expedition",base="Blueprint: Underbelly",class="Blueprints",other="Expedition Logbook",otherClass="Expedition Logbooks"}}) do
			local scene=library.scene(profile,build,case.kind,0,76,81);assert.equal(case.kind=="Maps & threads" and 17 or case.kind=="Flasks & tinctures" and 13 or 12,#scene)
			assert.equal(case.base,scene[1].BaseType);assert.equal(case.class,scene[1].Class)
			if case.kind=="Maps & threads" then
				assert.equal("Nightmare Map",scene[13].BaseType);assert.equal(17,scene[13].MapTier)
				assert.is_true(scene[16].BlightedMap);assert.is_false(scene[16].UberBlightedMap)
				assert.is_true(scene[17].UberBlightedMap)
				local visual=require("Modules.LootFilterVisuals")
				assert.equal("Blighted Map (Tier 16)",visual.sampleName(scene[16]));assert.equal("Blight-ravaged Map (Tier 16)",visual.sampleName(scene[17]))
				assert.equal(1,scene[1].MapTier)
				assert.equal("Show",parser.simulate(parser.parse('Hide\n MapTier >= 10\nShow'),scene[1]).action)
				assert.equal(10,scene[3].MapTier)
				assert.equal("Hide",parser.simulate(parser.parse('Hide\n MapTier >= 10\nShow'),scene[3]).action)
			end
			local found
			for _,item in ipairs(scene) do
				assert.equal(76,item.AreaLevel);assert.equal(81,item.ItemLevel)
				if item.BaseType==case.other then found=item end
			end
			assert.equal(case.otherClass,assert(found).Class)
			if case.kind=="Crafting materials" then assert.is_nil(found.Sockets);assert.equal("unknown",parser.simulate(parser.parse('Hide\n Sockets >= 3\nShow'),found).status) end
			local rule=parser.parse('Show\n Class == "'..case.otherClass..'"\n BaseType == "'..case.other..'"\nHide')
			assert.equal("Show",parser.simulate(rule,found).action)
			assert.equal("Hide",parser.simulate(rule,scene[1]).action)
			local rotated=library.scene(profile,build,case.kind,1,76,81)
			assert.equal(scene[2].BaseType,rotated[1].BaseType);assert.same(rotated,library.scene(profile,build,case.kind,1,76,81))
		end
	end)
	it("offers pinned encounter examples to users and AI",function()
		local profile=filters.profile("encounters","Encounters")
		local file=assert(io.open("Data/LootFilters/base-classes.json","rb"));local raw=file:read("*a");file:close();local classes=assert(require("dkjson").decode(raw)).classes
		for _,case in ipairs({{"Beyond",9,"Tainted Chromatic Orb"},{"Incursion",7,"Royal Visage"},{"Delirium",8,"Simulacrum Splinter"},{"Harvest",5,"Wild Crystallised Lifeforce"},{"Ritual",8,"Ritual Vessel"},{"Abyss",7,"Murderous Eye Jewel"},{"Ultimatum",9,"Inscribed Ultimatum"}}) do
			local scene=library.scene(profile,build,case[1],0,76,81);assert.equal(case[2],#scene);assert.equal(case[3],scene[1].BaseType)
			for _,item in ipairs(scene) do assert.is_nil(item.BaseType:find("Scarab",1,true));assert.equal(classes[item.BaseType],item.Class);assert.equal(76,item.AreaLevel);assert.equal(81,item.ItemLevel) end
			if case[1]=="Delirium" then assert.equal("Threaded Delirium Orb",scene[4].BaseType);assert.equal("Stackable Currency",scene[4].Class);assert.equal("Refracting Fog",scene[8].BaseType);assert.equal("Stackable Currency",scene[8].Class) end
			local rotated=library.scene(profile,build,case[1],1,76,81);assert.equal(scene[2].BaseType,rotated[1].BaseType)
			local page=filters.simulateScene(profile,case[1],0,76,81,1,2);assert.equal(case[2],page.total);assert.equal(scene[2].BaseType,page.results[1].sample.BaseType)
		end
	end)
	it("compares Blight oils and explicitly flagged map variants",function()
		local profile=filters.profile("blight","Blight");local scene=library.scene(profile,build,"Blight & oils",0,76,81)
		assert.equal(16,#scene);assert.equal("Clear Oil",scene[1].BaseType);assert.equal("Stackable Currency",scene[1].Class)
		assert.equal("Golden Oil",scene[12].BaseType);assert.equal("Blight Thread",scene[14].BaseType);assert.equal("Map Fragments",scene[14].Class)
		assert.is_true(scene[15].BlightedMap);assert.is_false(scene[15].UberBlightedMap);assert.is_true(scene[16].UberBlightedMap);assert.equal(16,scene[16].MapTier)
		local rule=parser.parse('Show\n UberBlightedMap True\nHide');assert.equal("Hide",parser.simulate(rule,scene[15]).action);assert.equal("Show",parser.simulate(rule,scene[16]).action)
		local page=filters.simulateScene(profile,"Blight & oils",0,76,81,14,2);assert.equal(16,page.total)
	end)
	it("uses pinned base drop levels and sizes, leaving ambiguous values unknown",function()
		local profile=filters.profile("base-properties","Base properties");local mixed=library.scene(profile,build,"Mixed drops",0,83,86);local byName={}
		for _,item in ipairs(mixed) do byName[item.BaseType]=item end
		assert.equal(68,byName["Vaal Regalia"].DropLevel);assert.equal(2,byName["Vaal Regalia"].Width);assert.equal(3,byName["Vaal Regalia"].Height)
		assert.equal(12,byName["Chaos Orb"].DropLevel);assert.equal(2,byName["Iron Hat"].Width);assert.equal(2,byName["Iron Hat"].Height)
		assert.is_nil(byName["Leather Belt"].DropLevel);assert.is_nil(byName["Vaal Regalia"].Sockets);assert.is_nil(byName["Vaal Regalia"].SocketGroup)
		local rules=parser.parse('Hide\n DropLevel >= 65\nShow');assert.equal("Hide",parser.simulate(rules,byName["Vaal Regalia"]).action);assert.equal("Show",parser.simulate(rules,byName["Chaos Orb"]).action)
		assert.equal("unknown",parser.simulate(rules,byName["Leather Belt"]).status)
		assert.equal("unknown",parser.simulate(parser.parse('Hide\n Sockets >= 4\nShow'),byName["Vaal Regalia"]).status)
		local maps=library.scene(profile,build,"Maps & threads",0,83,86);assert.equal("Map (Tier 1)",maps[1].BaseType);assert.equal(58,maps[1].DropLevel)
		assert.equal("Show",parser.simulate(rules,maps[1]).action);assert.equal(1,maps[1].Width);assert.equal(1,maps[1].Height)
		local flasks=library.scene(profile,build,"Flasks & tinctures",0,83,86);assert.equal(36,flasks[1].DropLevel);assert.equal(2,flasks[1].Height)
		local gear=library.scene(profile,build,"Tiered gear",0,83,86);assert.equal(2,gear[1].Width);assert.equal(2,gear[1].Height)
		local saved;require("Classes.LootFilterControl").EditSample(byName["Vaal Regalia"],function(item) saved=item end);local editor=main.popups[1].controls
		assert.equal("68",editor.DropLevel.buf);assert.equal("2",editor.Width.buf);assert.equal("3",editor.Height.buf);assert.equal("",editor.Sockets.buf)
		editor.DropLevel:SetText("");editor.useSample:Click();assert.is_nil(saved.DropLevel);assert.equal(2,saved.Width)
		require("Classes.LootFilterControl").EditSample(byName["Vaal Regalia"],function(item) saved=item end);editor=main.popups[1].controls
		editor.Rarity:SetText("Unique",true);assert.equal("",editor.DropLevel.buf)
		editor.BaseType:SetText("Iron Hat",true);for _,key in ipairs({"Class","DropLevel","Width","Height","MapTier","Sockets","SocketGroup","SocketColours","LinkedSockets"}) do assert.equal("",editor[key].buf,key) end
		editor.useSample:Click();assert.is_nil(saved.DropLevel);assert.is_nil(saved.Class)
	end)
	it("keeps rule examples consistent with base dimensions and socket limits",function()
		local impossible={text='Show\n Class == "Helmets"\n SocketGroup >= 5GGG'};local hat=library.sample(impossible)
		assert.equal("Iron Hat",hat.BaseType);assert.equal(2,hat.Width);assert.equal(2,hat.Height);assert.is_nil(hat.Sockets);assert.is_nil(hat.SocketGroup)
		assert.equal("unknown",parser.simulate(parser.parse(impossible.text),hat).status)
		local possible={text='Show\n BaseType == "Vaal Regalia"\n SocketGroup >= 5GGG'};local body=library.sample(possible)
		assert.equal(5,body.Sockets);assert.equal(2,body.Width);assert.equal(3,body.Height)
		assert.equal("Show",parser.simulate(parser.parse(possible.text),body).action)
		local empty={text='Show\n Class == "Stackable Currency"\n Sockets 0'};local currency=library.sample(empty)
		assert.equal(0,currency.Sockets);assert.equal("Show",parser.simulate(parser.parse(empty.text),currency).action)
		local incompatible={text='Show\n Class == "Rings"\n BaseType == "Iron Hat"\nHide'};local sample=library.sample(incompatible)
		assert.equal("Helmets",sample.Class);assert.equal("Hide",parser.simulate(parser.parse(incompatible.text),sample).action)
	end)
	it("keeps sample fields above the actions on shorter windows",function()
		local height=main.screenH;main.screenH=500
		local ok,err=pcall(function()
			require("Classes.LootFilterControl").EditSample(library.sample(),function() end);local c=main.popups[1].controls
			for _,key in ipairs({"DropLevel","Width","Height","BaseDefencePercentile","MemoryStrands","HasExplicitMod"}) do assert.is_true(c[key].y+c[key].height<c.useSample.y,key) end
		end)
		main.screenH=height;main.popups={};assert(ok,err)
	end)
	it("offers all supported conditions in the graphical rule editor",function()
		require("Classes.LootFilterControl").Conditions({id="all",title="All conditions",text='Show\n BaseType "Iron Hat"'},function() end)
		local list=main.popups[1].controls.c1key.list;local found={};for _,key in ipairs(list) do assert.is_nil(found[key],key);found[key]=true end
		for _,group in ipairs({parser.numeric,parser.booleans,parser.strings}) do for key in pairs(group) do if parser.poe2Only[key] then assert.is_nil(found[key],key) else assert.is_true(found[key],key) end end end
		assert.is_true(found.SocketGroup);assert.is_true(found.Rarity)
	end)
	it("edits additional sample properties across pages and preserves them on use",function()
		local original=library.sample();local saved;local height=main.screenH;main.screenH=500
		assert.is_nil(original.BaseArmour);assert.equal("unknown",parser.simulate(parser.parse("Hide\n BaseArmour >= 1\nShow"),original).status)
		local ok,err=pcall(function()
			local control=require("Classes.LootFilterControl");control.EditSample(original,function(value) saved=value end)
			local parent=main.popups[1].controls;parent.moreSample:Click();local more=main.popups[1].controls
			assert.is_false(more.extraPrevious:IsEnabled());assert.is_true(more.extraNext:IsEnabled())
			local function find(key)
				for _=1,4 do local value=more["extra_"..key];if value then return value end;more.extraNext:Click() end
				error("Missing extra field "..key)
			end
			find("BaseArmour"):SetText("500");find("HasEnchantment"):SetText('"Fortified"');find("Mirrored"):SelByValue("Yes");find("TransfiguredGem"):SetText("Leap Slam");assert.is_false(more.extraNext:IsEnabled())
			more.keepExtra:Click();assert.is_nil(original.BaseArmour);parent.useSample:Click()
			assert.equal(500,saved.BaseArmour);assert.same({"Fortified"},saved.HasEnchantment);assert.is_true(saved.Mirrored);assert.equal("Leap Slam",saved.TransfiguredGem)
			local rule=parser.parse('Hide\n BaseArmour >= 500\n HasEnchantment "Fortified"\n Mirrored True\n TransfiguredGem "Leap Slam"\nShow')
			assert.equal("Hide",parser.simulate(rule,saved).action)
			control.EditSample(saved,function(value) saved=value end);parent=main.popups[1].controls;parent.moreSample:Click();more=main.popups[1].controls
			find("BaseArmour"):SetText("200");more.cancelExtra:Click();parent.useSample:Click();assert.equal(500,saved.BaseArmour)
			control.EditSample(saved,function(value) saved=value end);parent=main.popups[1].controls;parent.BaseType:SetText("Iron Hat",true);parent.useSample:Click();assert.is_nil(saved.BaseArmour);assert.is_nil(saved.Mirrored)
		end)
		main.screenH=height;main.popups={};assert(ok,err)
	end)
	it("preserves unknown, absent and named influence while editing a sample",function()
		local editor=require("Classes.LootFilterControl");local rules=parser.parse("Hide\n HasInfluence None\nShow");local saved
		local function open(item) editor.EditSample(item,function(value) saved=value end);return main.popups[1].controls end
		local c=open({BaseType="Iron Hat"});c.useSample:Click();assert.is_nil(saved.HasInfluence);assert.equal("unknown",parser.simulate(rules,saved).status)
		c=open({BaseType="Iron Hat",HasInfluence={}});assert.equal("None",c.HasInfluence.buf);c.useSample:Click();assert.equal("Hide",parser.simulate(rules,saved).action)
		c=open(saved);c.HasInfluence:SetText("Shaper Elder");c.useSample:Click();assert.same({"Shaper","Elder"},saved.HasInfluence);assert.equal("Show",parser.simulate(rules,saved).action)
		c=open(saved);c.BaseType:SetText("Vaal Regalia",true);assert.equal("",c.HasInfluence.buf);c.useSample:Click();assert.is_nil(saved.HasInfluence);assert.equal("unknown",parser.simulate(rules,saved).status)
	end)
	it("clears stale Shaper and Elder flags when editing influence",function()
		local saved;local item={BaseType="Iron Hat",HasInfluence={"Shaper"},ShaperItem=true,ElderItem=false}
		require("Classes.LootFilterControl").EditSample(item,function(value) saved=value end)
		local c=main.popups[1].controls;c.HasInfluence:SetText("Elder",true);c.useSample:Click()
		assert.same({"Elder"},saved.HasInfluence);assert.is_nil(saved.ShaperItem);assert.is_nil(saved.ElderItem)
		assert.equal("Show",parser.simulate(parser.parse("Hide\n ShaperItem True\nShow"),saved).action)
		assert.equal("Hide",parser.simulate(parser.parse("Hide\n ElderItem True\nShow"),saved).action)
		assert.is_true(item.ShaperItem);assert.is_false(item.ElderItem)
	end)
	it("opens the requested additional sample property and preserves edits",function()
		local saved;local height=main.screenH;main.screenH=500
		local ok,err=pcall(function()
			local control=require("Classes.LootFilterControl");control.EditSample({BaseType="Iron Hat"},function(value) saved=value end,"Mirrored")
			assert.equal(2,#main.popups);local more=main.popups[1].controls;assert.is_truthy(more.extra_Mirrored);more.extra_Mirrored:SelByValue("Yes");more.keepExtra:Click()
			main.popups[1].controls.useSample:Click();assert.is_true(saved.Mirrored)
			control.EditSample(saved,function(value) saved=value end,"ItemLevel");assert.equal(1,#main.popups);assert.is_truthy(main.popups[1].controls.ItemLevel);main.popups[1].controls.cancel:Click()
		end)
		main.screenH=height;main.popups={};assert(ok,err)
	end)
	it("routes Configure to the property blocking the selected drop preview",function()
		local profile=filters.profile("missing","Missing");profile.template="Hide\n BaseArmour >= 10\nShow"
		local mounted,focus;local layout={width=1280,height=720,navigate=function() end,mount=function(_,_,_,controls) mounted=controls end}
		local controller={EditSample=function(_,_,key) focus=key end}
		require("Classes.LootFilterWorkspace").Open(build,{data={schemaVersion=1,activeId=profile.id,profiles={profile}},selected=profile.id,page="Simulate",sample={BaseType="Iron Hat"}},layout,controller)
		local lines={};for _,row in ipairs(mounted.selection.list) do lines[#lines+1]=StripEscapes(row[1] or "") end
		assert.is_truthy(table.concat(lines," "):find("Configure opens BaseArmour",1,true));mounted.sampleEdit:Click();assert.equal("BaseArmour",focus)
	end)
	it("explains the effective drop sound in the item preview",function()
		local profile=filters.profile("drop-sound","Drop sound");profile.template="Show\n DisableDropSound\n Continue\nShow\n EnableDropSound\n DisableDropSoundIfAlertSound"
		local mounted;local layout={width=1280,height=720,navigate=function() end,mount=function(_,_,_,controls) mounted=controls end}
		require("Classes.LootFilterWorkspace").Open(build,{data={schemaVersion=1,activeId=profile.id,profiles={profile}},selected=profile.id,page="Simulate",sample={BaseType="Iron Hat"}},layout,{})
		local lines={};for _,row in ipairs(mounted.selection.list) do lines[#lines+1]=StripEscapes(row[1] or "") end
		assert.is_truthy(table.concat(lines," "):find("Drop sound: disabled when an alert",1,true))
	end)
	it("shows the first filter error and its compiled line on selected and scene drops",function()
		local profile=filters.profile("invalid-preview","Invalid preview");profile.template="Show\n SetFontSize 99\n SetTextColor 999 0 0"
		local mounted,opened,focused;local layout={width=1280,height=720,navigate=function() end,mount=function(_,_,_,controls) mounted=controls end}
		local controller={Audit=function(profileArg,report,saveArg,focusErrors) opened=report;focused=focusErrors end}
		require("Classes.LootFilterWorkspace").Open(build,{data={schemaVersion=1,activeId=profile.id,profiles={profile}},selected=profile.id,page="Simulate",sample={BaseType="Iron Hat"}},layout,controller)
		local _,report=filters.compile(profile);local first
		for _,entry in ipairs(report.diagnostics) do if entry.error then first=entry;break end end
		local expected="Filter line "..first.line..": "..first.error
		assert.is_truthy(mounted.drop1.tooltipText:find(expected,1,true))
		local lines={};for _,row in ipairs(mounted.selection.list) do lines[#lines+1]=StripEscapes(row[1] or "") end
		assert.is_truthy(table.concat(lines," "):find("Filter error: Filter line "..first.line,1,true))
		mounted.inspectMatch:Click();assert.is_truthy(opened);assert.equal(first.error,opened.diagnostics[1].error);assert.is_true(focused)
	end)
	it("tests memory strands and preserves legacy sample fields",function()
		local rules=parser.parse('Hide\n MemoryStrands >= 60\nShow')
		local item=library.sample();assert.is_nil(item.MemoryStrands);assert.is_nil(item.AlwaysShow)
		assert.equal("Show",parser.simulate(rules,item).action)
		assert.equal("unknown",parser.simulate(parser.parse("Hide\n MemoryStrands >= 0\nShow"),item).status)
		item.MemoryStrands=75;assert.equal("Hide",parser.simulate(rules,item).action);item.MemoryStrands=nil
		item.Class="Helmets";item.BaseType="Hubris Circlet"
		assert.equal("unknown",parser.simulate(rules,item).status)
		item.AlwaysShow=false
		local saved;require("Classes.LootFilterControl").EditSample(item,function(value) saved=value end)
		local c=main.popups[1].controls;assert.equal("",c.MemoryStrands.buf);assert.is_nil(c.AlwaysShow)
		c.MemoryStrands:SetText("75");c.useSample:Click()
		assert.equal(75,saved.MemoryStrands);assert.is_false(saved.AlwaysShow);assert.equal("Hide",parser.simulate(rules,saved).action)
		local stored=require("Modules.LootFilterCollections").sample(saved);assert.equal(75,stored.MemoryStrands);assert.is_false(stored.AlwaysShow)
		require("Classes.LootFilterControl").EditSample(saved,function(value) saved=value end);c=main.popups[1].controls
		c.BaseType:SetText("Iron Hat",true);assert.equal("",c.MemoryStrands.buf);c.useSample:Click();assert.is_nil(saved.AlwaysShow)
	end)
	it("does not invent a defence roll for example drops",function()
		local profile=filters.profile("test","Test");local scene=library.scene(profile,build,"All items",0,83,86);local examples={}
		for _,item in ipairs(scene) do examples[item.BaseType]=item end
		assert.equal(0,examples["Chaos Orb"].BaseDefencePercentile)
		assert.is_nil(examples["Vaal Regalia"].BaseDefencePercentile)
		assert.equal(100,examples["Iron Ring"].BaseDefencePercentile)
		local resonators=0
		for _,item in ipairs(library.scene(profile,build,"Crafting materials",0,83,86)) do
			if item.Class=="Delve Stackable Socketable Currency" then resonators=resonators+1;assert.equal(0,item.BaseDefencePercentile);assert.is_nil(item.Sockets) end
		end
		assert.equal(2,resonators)
		assert.equal(0,library.baseDefencePercentile("Primitive Chaotic Resonator","Delve Socketable Currency","Normal"))
		local rules=parser.parse("Hide\n BaseDefencePercentile >= 40\nShow")
		assert.equal("Show",parser.simulate(rules,examples["Chaos Orb"]).action)
		assert.equal("unknown",parser.simulate(rules,examples["Vaal Regalia"]).status)
		assert.equal("Hide",parser.simulate(rules,examples["Iron Ring"]).action)
		local sample=library.sample({text='Show\n BaseType == "Vaal Regalia"\n BaseDefencePercentile >= 80'})
		assert.equal(80,sample.BaseDefencePercentile)
		local saved;require("Classes.LootFilterControl").EditSample(examples["Vaal Regalia"],function(item) saved=item end)
		local c=main.popups[1].controls;assert.equal("",c.BaseDefencePercentile.buf);c.BaseDefencePercentile:SetText("85");c.useSample:Click()
		assert.equal(85,saved.BaseDefencePercentile);assert.equal("Hide",parser.simulate(rules,saved).action)
		require("Classes.LootFilterControl").EditSample(saved,function(item) saved=item end);c=main.popups[1].controls
		c.BaseType:SetText("Iron Hat",true);assert.equal("",c.BaseDefencePercentile.buf)
		c.BaseDefencePercentile:SetText("100");c.Rarity:SetText("Unique",true);assert.equal("",c.BaseDefencePercentile.buf)
	end)
	it("resolves the defence percentile of non-equipment examples",function()
		local rules=parser.parse("Hide\n BaseDefencePercentile >= 1\nShow")
		for _,case in ipairs({{"Abyssal Incubator","Incubators"},{"Allflame Ember of Abyss","Embers of the Allflame"},{"Metamorph Brain","Metamorph Samples"},{"Abberathine Horns","Heist Targets"}}) do
			assert.equal(0,library.baseDefencePercentile(case[1],case[2],"Normal"))
			assert.equal("Show",parser.simulate(rules,{BaseType=case[1],Class=case[2],BaseDefencePercentile=library.baseDefencePercentile(case[1],case[2],"Normal")}).action)
		end
		local found=0;for _,sample in ipairs(library.scene(filters.profile("test","Test"),build,"Legion",0,83,86)) do if sample.Class=="Incubators" then found=found+1;assert.equal(0,sample.BaseDefencePercentile);assert.equal("Show",parser.simulate(rules,sample).action) end end;assert.is_true(found>0)
		assert.is_nil(library.baseDefencePercentile("Unknown item","Unrecognized class","Normal"))
		assert.is_nil(library.baseDefencePercentile("Vaal Regalia","Body Armours","Rare"))
	end)
	it("offers reproducible card and essence examples for testing filter rules",function()
		local profile=filters.profile("test","Test")
		for _,case in ipairs({{kind="Divination cards",class="Divination Cards",base="The Doctor",count=12},
			{kind="Essences",class="Stackable Currency",base="Essence of Horror",count=12}}) do
			local scene=library.scene(profile,build,case.kind,0,76,81);assert.equal(case.count,#scene)
			local rule=parser.parse('Show\n Class == "'..case.class..'"\n BaseType == "'..case.base..'"\nHide')
			local found=0;local names={};for _,item in ipairs(scene) do
				names[item.BaseType]=true
				assert.equal(case.class,item.Class);assert.equal(76,item.AreaLevel);assert.equal(81,item.ItemLevel)
				if parser.simulate(rule,item).action=="Show" then assert.equal(case.base,item.BaseType);found=found+1 end
			end
			assert.equal(1,found)
			if case.kind=="Essences" then assert.is_true(names["Essence of Trickery"]) end
			local rotated=library.scene(profile,build,case.kind,1,76,81);assert.equal(scene[2].BaseType,rotated[1].BaseType)
			assert.same(rotated,library.scene(profile,build,case.kind,1,76,81))
		end
	end)
	it("builds pinned currency highlights without guessing item classes or live prices",function()
		local profile=filters.profile("test","Test");local scene=library.scene(profile,build,"Preset highlights",0,76,81)
		assert.is_true(#scene>0);local seen={}
		for _,item in ipairs(scene) do
			assert.is_nil(seen[item.BaseType]);seen[item.BaseType]=true
			assert.equal(library.baseClass(item.BaseType),item.Class)
			assert.equal(76,item.AreaLevel);assert.equal(81,item.ItemLevel)
		end
		assert.is_true(seen["Hollow Fossil"])
		local rotated=library.scene(profile,build,"Preset highlights",1,76,81)
		assert.equal(scene[2].BaseType,rotated[1].BaseType)
		assert.same(rotated,library.scene(profile,build,"Preset highlights",1,76,81))
	end)
	it("pages built-in scene results without changing the profile",function()
		local profile=filters.profile("test","Test");local before=copyTable(profile)
		local expected=library.scene(profile,nil,"Preset highlights",3,76,81)
		local first=filters.simulateScene(profile,"Preset highlights",3,76,81,0,2)
		assert.equal(#expected,first.total);assert.equal(2,first.nextOffset)
		assert.same(expected[1],first.results[1].sample);assert.same(expected[2],first.results[2].sample)
		local maps=copyTable(profile);maps.rules={{id="map",title="Map tier",text='Show\n Class == "Maps"\n MapTier >= 1'}}
		assert.equal("Show",filters.simulateScene(maps,"Maps & threads",0,76,81,0,1).results[1].result.action)
		local last=filters.simulateScene(profile,"Preset highlights",3,76,81,first.nextOffset,50)
		assert.equal(expected[3].BaseType,last.results[1].sample.BaseType);assert.is_nil(last.nextOffset);assert.same(before,profile)
		local invalid=copyTable(profile);invalid.rules={{id="bad",title="Unsupported",text="Show\n AlwaysShow False"}}
		assert.equal("invalid",filters.simulateScene(invalid,"Currency",0,76,81,0,1).results[1].result.status)
		assert.has_error(function() filters.simulateScene(profile,"Build targets") end)
		build.savers.CraftingProjects:Upsert({id="hat",title="Craft helmet",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={}})
		build.savers.CraftingProjects:Upsert({id="ring",title="Craft ring",slot="Ring 1",startingItem="Rarity: NORMAL\nIron Ring\nItem Level: 86",goals={},steps={}})
		local expectedTargets=library.scene(profile,build,"Build targets",0,76,86)
		local originalSample=library.sample;local sampleCalls=0
		library.sample=function(...) sampleCalls=sampleCalls+1;return originalSample(...) end
		local ok,targets=pcall(filters.simulateScene,profile,"Build targets",0,76,86,0,1,nil,build)
		library.sample=originalSample;assert.is_true(ok,targets)
		assert.equal(1,sampleCalls);assert.is_true(#expectedTargets>=2);assert.equal(#expectedTargets,targets.total)
		assert.same(expectedTargets[1],targets.results[1].sample);assert.same(before,profile)
		local nextTarget=filters.simulateScene(profile,"Build targets",0,76,86,targets.nextOffset,1,nil,build)
		assert.same(expectedTargets[2],nextTarget.results[1].sample);assert.equal(1,nextTarget.results[1].index)
		assert.equal(0,targets.warningCount)
		build.savers.CraftingProjects.projects[1].startingItem="Not an item"
		local incomplete=filters.simulateScene(profile,"Build targets",0,76,86,0,1,nil,build)
		assert.equal(1,incomplete.warningCount);assert.match("Could not read",incomplete.warnings[1].message)
		assert.equal("craft:hat",incomplete.warnings[1].origin);assert.same(before,profile)
		for i=1,20 do local project=copyTable(build.savers.CraftingProjects.projects[1]);project.id="bad"..i;table.insert(build.savers.CraftingProjects.projects,project) end
		local many=filters.simulateScene(profile,"Build targets",0,76,86,0,1,nil,build)
		assert.equal(21,many.warningCount);assert.equal(20,#many.warnings);assert.is_true(many.warningsTruncated)
		assert.has_error(function() filters.simulateScene(profile,"Currency",-1) end)
	end)
	it("keeps UTF-8 characters intact when a paged rule title is truncated",function()
		local profile=filters.profile("test","Test")
		profile.template="# PoB rule: "..string.rep("a",159).."é suffix\nShow"
		local result=filters.simulateScene(profile,"Currency",0,76,81,0,1)
		assert.equal(string.rep("a",159),result.results[1].result.ruleTitle)
		assert.is_true(result.results[1].result.ruleTitleTruncated)
		profile.template="# PoB rule: "..string.rep("a",158).."é suffix\nShow"
		result=filters.simulateScene(profile,"Currency",0,76,81,0,1)
		assert.equal(string.rep("a",158).."é",result.results[1].result.ruleTitle)
	end)
	it("reuses build-target scenes while preserving the caller's list and refreshing levels and rules",function()
		local workspace=require("Classes.LootFilterWorkspace")
		local profile=filters.profile("test","Test")
		local rules={{id="hat",title="Hat",origin="gear:hat",text='Show\n BaseType == "Iron Hat"'}}
		local state={rules=rules};local settings={areaLevel=76,itemLevel=81}
		local first,keys=workspace.targetScene(state,profile,build,settings)
		assert.equal(1,#first);assert.is_true(keys[require("Modules.PlanningData").encode(first[1])])
		local cached=state.sceneCache;table.insert(first,1,{BaseType="Extra"})
		local second=workspace.targetScene(state,profile,build,settings)
		assert.equal(cached,state.sceneCache);assert.equal(1,#second);assert.equal("Iron Hat",second[1].BaseType)
		settings.itemLevel=82;local changed=workspace.targetScene(state,profile,build,settings)
		assert.not_equal(cached,state.sceneCache);assert.equal(82,changed[1].ItemLevel)
		cached=state.sceneCache;state.rules={{id="ring",title="Ring",origin="gear:ring",text='Show\n BaseType == "Iron Ring"'}}
		changed=workspace.targetScene(state,profile,build,settings)
		assert.not_equal(cached,state.sceneCache);assert.equal("Iron Ring",changed[1].BaseType)
	end)
	it("builds a reproducible 3.30 league-item example scene from published item classes",function()
		local profile=filters.profile("test","Test");local scene=library.scene(profile,build,"Covens & Threads",0,76,81)
		local file=assert(io.open("Data/LootFilters/patch-3.30.json","rb"));local patch=assert(require("dkjson").decode(file:read("*a")));file:close()
		assert.equal(16,#scene);local seen={}
		for _,item in ipairs(scene) do
			assert.is_truthy(isValueInTable(patch.added[item.Class],item.BaseType),item.BaseType)
			assert.equal(76,item.AreaLevel);assert.equal(81,item.ItemLevel);seen[item.BaseType]=true
		end
		assert.is_true(seen["Frayed Thread"]);assert.is_true(seen["Breach Thread"]);assert.is_true(seen["Enshrouded Quiver"]);assert.is_true(seen["Scorched Arm"])
		local rotated=library.scene(profile,build,"Covens & Threads",1,76,81)
		assert.equal(scene[2].BaseType,rotated[1].BaseType);assert.same(rotated,library.scene(profile,build,"Covens & Threads",1,76,81))
	end)
	it("tests Sanctum and pinnacle examples using pinned item classes",function()
		local f=assert(io.open("Data/LootFilters/base-classes.json","rb"));local classes=assert(require("dkjson").decode(f:read("*a"))).classes;f:close()
		local profile=filters.profile("scenes","Scenes");profile.template='Show\n Class == "Sanctum Research" "Map Fragments"\nHide'
		for _,example in ipairs({{"Sanctum","Forbidden Tome",11},{"Pinnacle bosses","Crescent Splinter",12}}) do
			local scene=library.scene(profile,build,example[1],0,76,81);assert.equal(example[3],#scene);assert.equal(example[2],scene[1].BaseType)
			for _,item in ipairs(scene) do assert.is_nil(item.BaseType:find("Maven's Invitation",1,true));assert.equal(classes[item.BaseType],item.Class);assert.equal(76,item.AreaLevel);assert.equal(81,item.ItemLevel) end
			local page=filters.simulateScene(profile,example[1],0,76,81,0,2);assert.equal(example[3],page.total);assert.equal(example[2],page.results[1].sample.BaseType)
			assert.equal(example[1]=="Sanctum" and "Show" or "Hide",page.results[1].result.action)
			local nextPage=filters.simulateScene(profile,example[1],0,76,81,2,2);assert.equal(scene[3].BaseType,nextPage.results[1].sample.BaseType)
		end
	end)
	it("browses real base blocks without mutating the profile or their conditions",function()
		local profile=filters.profile("test","Test");local before=copyTable(profile)
		local entries=library.catalog(profile);assert.is_true(#entries>500)
		assert.same(before,profile)
		local currency=library.entries(profile,entries,"All items","Chaos Orb");assert.is_true(#currency>0)
		for _,entry in ipairs(currency) do assert.is_truthy(entry.rule.text:find("Chaos Orb",1,true));assert.is_true(entry.base);assert.equal(1,#parser.parse(entry.rule.text).rules) end
	end)
	it("edits appearance while preserving multi-value conditions, Continue and custom sound volume",function()
		local rule={id="base-1",title="Target",text='Show\n HasExplicitMod >=2 "of Haast" "of Ephij"\n BaseType == "Iron Hat"\n CustomAlertSound "my sound.wav" 125\n Continue',enabled=false}
		local changed=library.appearance(rule,{SetTextColor={"255","200","100"},SetFontSize={"40"}})
		local old,new=parser.parse(rule.text).rules[1],parser.parse(changed.text).rules[1]
		assert.same(old.conditions,new.conditions);assert.same({"my sound.wav","125"},new.styles.CustomAlertSound);assert.is_true(new.continue);assert.is_false(changed.enabled)
		assert.is_nil(rule.text:find("SetTextColor",1,true))
	end)
	it("creates a personal override without replacing imported source text",function()
		local profile=filters.profile("test","Test");profile.template='Show\n BaseType == "Iron Hat"\n SetTextColor 255 255 255'
		local source=profile.template;local entry=library.catalog(profile)[1]
		local override=library.appearance(entry.rule,{SetTextColor={"255","0","0"}});profile.rules={override}
		assert.equal(source,profile.template)
		local result=filters.simulate(profile,{BaseType="Iron Hat"});assert.same({"255","0","0"},result.styles.SetTextColor)
	end)
	it("keeps base override identities stable when unrelated source rules move",function()
		local profile=filters.profile("test","Test");local hat='Show\n BaseType == "Iron Hat"\n SetFontSize 40';local ring='Show\n BaseType == "Iron Ring"\n SetFontSize 30'
		profile.template=hat.."\n"..ring;local original=library.catalog(profile)
		profile.template=ring.."\n"..hat;local reordered=library.catalog(profile)
		assert.equal(original[1].rule.id,reordered[2].rule.id);assert.is_not.equal(original[1].rule.id,reordered[1].rule.id)
	end)
	it("generates deterministic example scenes and labels unknown item data honestly",function()
		local profile=filters.profile("test","Test");local first=library.scene(profile,build,"Mixed drops",7,72)
		assert.same(first,library.scene(profile,build,"Mixed drops",7,72));assert.equal(72,first[1].AreaLevel)
		for _,item in ipairs(library.scene(profile,build,"Currency",1,83)) do assert.equal("Stackable Currency",item.Class) end
		profile.template='Hide\n FutureCondition True\nShow'
		local unresolved=copyTable(first[1]);unresolved.BaseType="Iron Hat";unresolved.Class="Helmets"
		assert.equal("unknown",filters.simulate(profile,unresolved).status)
	end)
	it("compares explicitly tiered unidentified gear without modeling drop rates",function()
		local scene=library.scene(filters.profile("test","Test"),build,"Tiered gear",4,72,75)
		assert.equal(5,#scene)
		for index,tier in ipairs({0,2,3,4,5}) do
			local item=scene[index];assert.equal(tier,item.UnidentifiedItemTier);assert.is_false(item.Identified)
			assert.equal("Iron Hat",item.BaseType);assert.equal(72,item.AreaLevel);assert.equal(75,item.ItemLevel)
			local result=parser.simulate(parser.parse("Show\n UnidentifiedItemTier >= 4\nHide"),item)
			assert.equal(tier>=4 and "Show" or "Hide",result.action)
		end
	end)
	it("compares Foulborn and other gear using identical examples",function()
		local profile=filters.profile("foulborn","Foulborn");local scene=library.scene(profile,build,"Foulborn gear",7,72,75)
		assert.equal(10,#scene);assert.same(scene,library.scene(profile,build,"Foulborn gear",0,72,75))
		local parsed=parser.parse("Show\n Foulborn True\nHide")
		for i=1,#scene,2 do
			local first,second=scene[i],scene[i+1];assert.is_true(first.Foulborn);assert.is_false(second.Foulborn)
			local same=copyTable(first);same.Foulborn=false;assert.same(same,second)
			assert.equal("Show",parser.simulate(parsed,first).action);assert.equal("Hide",parser.simulate(parsed,second).action)
		end
	end)
	it("compares Fated and other rare gear at the same sample tier",function()
		local profile=filters.profile("fated","Fated");local scene=library.scene(profile,build,"Fated gear",7,72,75)
		assert.equal(10,#scene);assert.same(scene,library.scene(profile,build,"Fated gear",0,72,75))
		local parsed=parser.parse("Show\n Fated True\nHide")
		for i=1,#scene,2 do
			local fated,other=scene[i],scene[i+1];assert.equal(fated.BaseType,other.BaseType);assert.equal(fated.Class,other.Class)
			assert.is_true(fated.Fated);assert.is_false(other.Fated);assert.is_false(fated.Identified);assert.equal(4,fated.UnidentifiedItemTier);assert.equal(4,other.UnidentifiedItemTier)
			assert.equal(72,fated.AreaLevel);assert.equal(75,fated.ItemLevel);assert.equal(0,fated.MemoryStrands);local same=copyTable(fated);same.Fated=false;assert.same(same,other)
			assert.equal("Show",parser.simulate(parsed,fated).action);assert.equal("Hide",parser.simulate(parsed,other).action)
		end
		profile.mode="Ruthless";local ruthless=library.scene(profile,build,"Fated gear",0,83,86);assert.equal(0,ruthless[1].UnidentifiedItemTier)
	end)
	it("compares explicit map tiers with a Nightmare example",function()
		local profile=filters.profile("maps","Maps");local scene=library.scene(profile,build,"Map tiers",9,72,75)
		assert.equal(17,#scene);assert.same(scene,library.scene(profile,build,"Map tiers",3,72,75))
		for tier,item in ipairs(scene) do
			assert.equal(tier,item.MapTier);assert.equal("Maps",item.Class);assert.equal(72,item.AreaLevel);assert.equal(75,item.ItemLevel)
			assert.equal(tier==17 and "Nightmare Map" or "Map (Tier "..tier..")",item.BaseType)
			local result=parser.simulate(parser.parse("Show\n MapTier >= 16\nHide"),item)
			assert.equal(tier>=16 and "Show" or "Hide",result.action)
		end
		local page=filters.simulateScene(profile,"Map tiers",0,72,75,15,2)
		assert.equal(17,page.total);assert.equal(16,page.results[1].sample.MapTier);assert.equal(17,page.results[2].sample.MapTier)
	end)
	it("builds example properties only when requested and reuses the parsed block",function()
		local p=filters.profile("test","Test");p.template='Show\n BaseType == "Iron Hat"\n ItemLevel >= 83'
		local entry=library.catalog(p)[1];assert.is_nil(rawget(entry,"sample"));local sample=entry.sample;assert.equal("Iron Hat",sample.BaseType);assert.equal(83,sample.ItemLevel)
		assert.equal(sample,entry.sample);assert.same(library.sample(entry.rule),sample)
	end)
	it("labels generic rules using their real conditions instead of an invented example",function()
		local p=filters.profile("labels","Labels");p.template='Show\n Identified True\n Rarity Rare\n HasExplicitMod "Elreon"\nShow\n Class == "Helmets"\nShow\n Sockets >= 5\nHide\n BaseType != "Chaos Orb"'
		local entries=library.catalog(p)
		assert.equal("Has Explicit Mod = Elreon",entries[1].rule.title)
		assert.equal("Class == Helmets",entries[2].rule.title)
		assert.equal("Sockets >= 5",entries[3].rule.title)
		assert.equal("Base Type != Chaos Orb",entries[4].rule.title)
		local structure=require("Modules.LootFilterStructure").filter(require("Modules.LootFilterStructure").outline(p),"","base")
		for i,entry in ipairs(entries) do assert.equal(entry.rule.title,structure[i].title);assert.is_nil(rawget(entry,"sample")) end
	end)
	it("builds representative rare and modifier examples without overriding identification",function()
		local text='Show\n Rarity Rare\n HasExplicitMod >=2 "Haast" "Ephij"\nHide'
		local item=library.sample({text=text});assert.equal("Iron Hat",item.BaseType);assert.equal("Helmets",item.Class)
		assert.is_true(item.Identified);assert.same({"Haast","Ephij"},item.HasExplicitMod);assert.equal("Show",parser.simulate(parser.parse(text),item).action)
		local unidentified=library.sample({text='Show\n Identified False\n HasExplicitMod "Haast"'});assert.is_false(unidentified.Identified)
		assert.equal("unknown",parser.simulate(parser.parse('Show\n Identified False\n HasExplicitMod "Haast"'),unidentified).status)
		local numeric=library.sample({text='Show\n HasExplicitMod "1"'});assert.same({"1"},numeric.HasExplicitMod)
		local alternatives=library.sample({text='Show\n HasExplicitMod "Haast" "Ephij"'});assert.same({"Haast"},alternatives.HasExplicitMod)
		local tooMany=library.sample({text='Show\n HasExplicitMod >=7 "a" "b" "c" "d" "e" "f" "g"'});assert.equal(6,#tooMany.HasExplicitMod)
		assert.equal("Iron Hat",library.sample({text='Show\n Rarity Magic'}).BaseType)
	end)
	it("builds coherent equipment examples for common socket rules",function()
		for _,condition in ipairs({"SocketGroup RGB", "SocketGroup == 5GGG", "SocketGroup == 5GW", "Sockets >= 5", "Sockets 5GGG", "LinkedSockets >= 5"}) do
			local text="Show\n "..condition.."\nHide"
			local item=library.sample({text=text})
			assert.equal("Body Armours",item.Class)
			assert.equal(item.Sockets,#item.SocketColours)
			assert.equal(item.Sockets,item.LinkedSockets)
			assert.equal("Show",parser.simulate(parser.parse(text),item).action)
		end
	end)
	it("uses native default text colours for item rarity and known item classes",function()
		local color=require("Modules.LootFilterVisuals").defaultTextColor
		assert.same({200,200,200},color({Rarity="Normal",Class="Helmets"}))
		assert.same({136,136,255},color({Rarity="Magic"}));assert.same({255,255,119},color({Rarity="Rare"}));assert.same({175,96,37},color({Rarity="Unique"}))
		assert.same({170,158,130},color({Rarity="Normal",Class="Stackable Currency"}));assert.same({26,162,155},color({Rarity="Normal",Class="Skill Gems"}))
		assert.same({255,255,119},color({Rarity="Rare",Class="Stackable Currency"}));assert.same({220,225,215},color({}))
	end)
	it("derives known equipment classes and leaves unfamiliar bases unknown",function()
		assert.equal("One Hand Swords",library.sample({text='Show\n BaseType == "Rusted Sword"'}).Class)
		local item=library.sample({text='Show\n BaseType == "Unknown Future Base"'});assert.is_nil(item.Class)
		assert.equal("unknown",parser.simulate(parser.parse('Hide\n Class == "Stackable Currency"\nShow'),item).status)
		local p=filters.profile("test","Test");p.template='Hide\nShow\n Continue'
		local entries=library.catalog(p);assert.equal("Hide remaining items",entries[1].rule.title);assert.equal("Style remaining items",entries[2].rule.title)
	end)
	it("provides Breach and Legion scenes to filter simulation",function()
		local profile=filters.profile("encounters","Encounters")
		for _,case in ipairs({{kind="Breach",count=9,base="Splinter of Chayula",class="Stackable Currency"},
			{kind="Legion",count=13,base="Timeless Maraketh Emblem",class="Map Fragments"}}) do
			local scene=library.scene(profile,build,case.kind,0,76,81);assert.equal(case.count,#scene)
			local found;for _,item in ipairs(scene) do
				assert.is_nil(item.BaseType:find("Scarab",1,true));assert.equal(76,item.AreaLevel);assert.equal(81,item.ItemLevel)
				if item.BaseType==case.base then found=item end
			end
			assert.equal(case.class,assert(found).Class)
			local rule=parser.parse('Show\n Class == "'..case.class..'"\n BaseType == "'..case.base..'"\nHide')
			assert.equal("Show",parser.simulate(rule,found).action)
			local page=filters.simulateScene(profile,case.kind,0,76,81,0,3);assert.equal(case.count,page.total)
		end
	end)

end)
