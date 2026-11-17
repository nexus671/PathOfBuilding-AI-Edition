describe("Visual filter catalogue",function()
	local filters=require("Modules.LootFilters")
	local parser=require("Modules.LootFilterParser")
	local library=require("Modules.LootFilterLibrary")
	before_each(function() newBuild();main.popups={} end)
	after_each(function() main.popups={} end)
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
		local editor=main.popups[1].controls;editor.Sockets:SetText("4");editor.SocketGroup:SetText("R-G B A");editor.useSample:Click()
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
		for _,case in ipairs({{kind="Maps & threads",base="Beach Map",class="Maps",other="Breach Thread",otherClass="Map Fragments"},
			{kind="Flasks & tinctures",base="Sacred Life Flask",class="Life Flasks",other="Prismatic Tincture",otherClass="Tinctures"},
			{kind="Crafting materials",base="Hollow Fossil",class="Stackable Currency",other="Powerful Chaotic Resonator",otherClass="Delve Stackable Socketable Currency"},
			{kind="Heist & Expedition",base="Blueprint: Underbelly",class="Blueprints",other="Expedition Logbook",otherClass="Expedition Logbooks"}}) do
			local scene=library.scene(profile,build,case.kind,0,76,81);assert.equal(12,#scene)
			assert.equal(case.base,scene[1].BaseType);assert.equal(case.class,scene[1].Class)
			if case.kind=="Maps & threads" then
				assert.is_nil(scene[1].MapTier)
				assert.equal("unknown",parser.simulate(parser.parse('Hide\n MapTier >= 10\nShow'),scene[1]).status)
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
	it("uses pinned base drop levels and sizes, leaving ambiguous values unknown",function()
		local profile=filters.profile("base-properties","Base properties");local mixed=library.scene(profile,build,"Mixed drops",0,83,86);local byName={}
		for _,item in ipairs(mixed) do byName[item.BaseType]=item end
		assert.equal(68,byName["Vaal Regalia"].DropLevel);assert.equal(2,byName["Vaal Regalia"].Width);assert.equal(3,byName["Vaal Regalia"].Height)
		assert.equal(12,byName["Chaos Orb"].DropLevel);assert.equal(2,byName["Iron Hat"].Width);assert.equal(2,byName["Iron Hat"].Height)
		assert.is_nil(byName["Leather Belt"].DropLevel);assert.is_nil(byName["Vaal Regalia"].Sockets);assert.is_nil(byName["Vaal Regalia"].SocketGroup)
		local rules=parser.parse('Hide\n DropLevel >= 65\nShow');assert.equal("Hide",parser.simulate(rules,byName["Vaal Regalia"]).action);assert.equal("Show",parser.simulate(rules,byName["Chaos Orb"]).action)
		assert.equal("unknown",parser.simulate(rules,byName["Leather Belt"]).status)
		assert.equal("unknown",parser.simulate(parser.parse('Hide\n Sockets >= 4\nShow'),byName["Vaal Regalia"]).status)
		local maps=library.scene(profile,build,"Maps & threads",0,83,86);assert.equal("Beach Map",maps[1].BaseType);assert.is_nil(maps[1].DropLevel)
		assert.equal("unknown",parser.simulate(rules,maps[1]).status);assert.equal(1,maps[1].Width);assert.equal(1,maps[1].Height)
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
	it("tests memory strands and preserves legacy sample fields",function()
		local rules=parser.parse('Hide\n MemoryStrands >= 60\nShow')
		local item=library.sample();assert.is_nil(item.MemoryStrands);assert.is_nil(item.AlwaysShow)
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
end)
