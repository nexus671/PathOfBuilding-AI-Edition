describe("Linked planning tools",function()
	local filters=require("Modules.LootFilters")
	local dependencies=require("Modules.LootFilterDependencies")
	local function craft() return {id="helmet",title="Helmet",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={}} end
	before_each(function() newBuild();main.popups={} end)
	after_each(function() main.popups={} end)
	it("keeps identical pickups linked to each crafting and gear source",function()
		local first=craft();build.savers.CraftingProjects:Upsert(first)
		local profile=filters.profile("shared","Shared pickups");profile.rules=filters.generate(build,profile)
		local second=copyTable(first);second.id="second";second.title="Second helmet";build.savers.CraftingProjects:Upsert(second)
		local function statuses()
			local report=dependencies.report(build,profile);local result={}
			for _,entry in ipairs(report.entries) do result[entry.origin]=entry.status end
			return result,report.stale
		end
		local state,stale=statuses();assert.is_true(stale);assert.equal("Current",state["craft:helmet"]);assert.equal("New target",state["craft:second"])
		profile.rules=filters.generate(build,profile);state,stale=statuses();assert.is_false(stale);assert.equal("Current",state["craft:second"])
		local journey=require("Modules.BuildJourney").empty();journey.wishlist={{id="gear-hat",title="Helmet goal",slot="Helmet",route="craft",targetItem=first.startingItem}};build.savers.BuildJourney:Replace(journey)
		state,stale=statuses();assert.is_true(stale);assert.equal("New target",state["gear:gear-hat"])
		profile.rules=filters.generate(build,profile);local ids={};for _,rule in ipairs(profile.rules) do if rule.origin then ids[rule.origin]=rule.id end end
		assert.is_truthy(ids["craft:helmet"]);assert.is_truthy(ids["craft:second"]);assert.is_truthy(ids["gear:gear-hat"])
		local opened;local layout={openWorkbench=function(project) opened=project.id end,navigate=function(_,entry) opened=entry.selected end}
		assert.is_true(dependencies.open(build,layout,"craft:helmet"));assert.equal("helmet",opened)
		assert.is_true(dependencies.open(build,layout,"craft:second"));assert.equal("second",opened)
		assert.is_true(dependencies.open(build,layout,"gear:gear-hat"));assert.equal("gear-hat",opened)
		second.startingItem=second.startingItem:gsub("86","84");build.savers.CraftingProjects:Upsert(second)
		state,stale=statuses();assert.is_true(stale);assert.equal("Current",state["craft:helmet"]);assert.equal("Changed",state["craft:second"]);assert.equal("Current",state["gear:gear-hat"])
		profile.rules=filters.generate(build,profile);build.savers.CraftingProjects:Remove("helmet")
		state,stale=statuses();assert.is_true(stale);assert.equal("Source removed / no longer needed",state["craft:helmet"]);assert.equal("Current",state["craft:second"]);assert.equal("Current",state["gear:gear-hat"])
		profile.rules=filters.generate(build,profile);local retained={};for _,rule in ipairs(profile.rules) do if rule.origin then retained[rule.origin]=rule.id end end
		assert.equal(ids["craft:second"],retained["craft:second"]);assert.equal(ids["gear:gear-hat"],retained["gear:gear-hat"])
		profile.template="Hide";assert.equal("Show",filters.simulate(profile,{BaseType="Iron Hat",Rarity="Rare",ItemLevel=86}).action)
	end)
	it("shows unique wishlist items without requiring the copied item's level",function()
		local journey=require("Modules.BuildJourney").empty()
		journey.wishlist={{id="surrender",title="The Surrender",slot="Weapon 2",route="farm",targetItem="Rarity: UNIQUE\nThe Surrender\nEzomyte Tower Shield\nItem Level: 86"}}
		build.savers.BuildJourney:Replace(journey)
		local profile=filters.profile("unique-target","Unique target");profile.template="Hide";profile.rules=filters.generate(build,profile)
		local pickup;for _,rule in ipairs(profile.rules) do if rule.origin=="gear:surrender" then pickup=rule end end
		assert.is_truthy(pickup);assert.is_truthy(pickup.text:find('BaseType == "Ezomyte Tower Shield"',1,true))
		assert.is_truthy(pickup.text:find("Rarity == Unique",1,true));assert.is_nil(pickup.text:find("ItemLevel",1,true))
		assert.equal("Show",filters.simulate(profile,{BaseType="Ezomyte Tower Shield",Rarity="Unique",ItemLevel=70}).action)
		assert.equal("Hide",filters.simulate(profile,{BaseType="Ezomyte Tower Shield",Rarity="Rare",ItemLevel=86}).action)
	end)
	it("keeps shared recipe currencies linked to each guide",function()
		local first=craft();first.nativeRecipe={steps={{method="omen_connections"}},targets={},requirements={links=4}}
		local second=copyTable(first);second.id="second";second.title="Second helmet"
		build.savers.CraftingProjects:Upsert(first);build.savers.CraftingProjects:Upsert(second)
		local profile=filters.profile("shared-currency","Shared currency");profile.rules=filters.generate(build,profile)
		local sources={};for _,rule in ipairs(profile.rules) do if rule.title=="Omen of Connections" then sources[rule.origin]=true end end
		assert.is_true(sources["craft:helmet"]);assert.is_true(sources["craft:second"])
		first.nativeRecipe.steps={{method="socket_white_bench"}};build.savers.CraftingProjects:Upsert(first)
		profile.rules=filters.generate(build,profile);sources={};for _,rule in ipairs(profile.rules) do if rule.title=="Omen of Connections" then sources[rule.origin]=true end end
		assert.is_nil(sources["craft:helmet"]);assert.is_true(sources["craft:second"])
	end)
	it("adds linked loot targets for every mechanic on a multi-mechanic Atlas node",function()
		local atlas=require("Modules.AtlasPlanner");local tree=atlas.tree("3.30.0-preview")
		local plan=atlas.connect({id="multi",title="Multi mechanic",version="3.30.0-preview",budget=150,nodes={}}, {4908})
		build.savers.AtlasPlans:Upsert(plan)
		local node=tree.nodes[4908];local original=node.stats;node.stats=copyTable(original)
		node.stats[#node.stats+1]="Your Maps contain a Blight Encounter and an Incursion"
		local ok,rules=pcall(filters.generate,build,filters.profile("multi-filter","Multi mechanic"));node.stats=original
		assert.is_true(ok,tostring(rules));local names={};for _,rule in ipairs(rules) do names[rule.title]=true end
		assert.is_true(names["Blight Thread"]);assert.is_true(names["Incursion Thread"])
	end)
	it("uses only the selected Atlas effect for linked thread suggestions",function()
		local atlas=require("Modules.AtlasPlanner");local node=atlas.tree("3.30.0-preview").nodes[54685]
		local plan={id="choice",title="Choice",version="3.30.0-preview",budget=150,nodes={node.id},choices={{node=node.id,effect=node.variantEffects[1].effect}}}
		-- Isolate the chosen node so intermediate path nodes cannot add other mechanics.
		build.savers.AtlasPlans.plans={plan}
		local profile=filters.profile("choice-filter","Choice filter");local names={}
		for _,rule in ipairs(filters.generate(build,profile)) do if rule.origin=="atlas:choice" then names[rule.title]=true end end
		assert.is_true(names["Breach Thread"]);assert.is_nil(names["Ritual Thread"]);assert.is_nil(names["Ultimatum Thread"])
		plan.choices[1].effect=node.variantEffects[2].effect;names={}
		for _,rule in ipairs(filters.generate(build,profile)) do if rule.origin=="atlas:choice" then names[rule.title]=true end end
		assert.is_nil(names["Breach Thread"]);assert.is_true(names["Ritual Thread"])
	end)
	it("does not suggest a thread excluded by an Atlas effect",function()
		local atlas=require("Modules.AtlasPlanner");local tree=atlas.tree("3.30.0-preview")
		local positive,negative=tree.nodes[54685],tree.nodes[64980]
		local plan={id="exclusion",title="Exclusion",version=tree.version,budget=150,nodes={positive.id,negative.id},choices={{node=positive.id,effect=positive.variantEffects[1].effect},{node=negative.id,effect=negative.variantEffects[1].effect}}}
		build.savers.AtlasPlans.plans={plan};local profile=filters.profile("exclusion-filter","Exclusion filter")
		local function names() local result={};for _,rule in ipairs(filters.generate(build,profile)) do if rule.origin=="atlas:exclusion" then result[rule.title]=true end end;return result end
		assert.is_nil(names()["Breach Thread"])
		plan.choices[2].effect=negative.variantEffects[2].effect;assert.is_true(names()["Breach Thread"])
		plan.choices[2].effect=negative.variantEffects[1].effect;plan.strategy={scarabs="Breach Thread"};assert.is_true(names()["Breach Thread"])
		positive,negative=tree.nodes[61484],tree.nodes[61620];plan.strategy=nil;plan.nodes={positive.id,negative.id};plan.choices={{node=positive.id,effect=positive.variantEffects[1].effect},{node=negative.id,effect=negative.variantEffects[1].effect}}
		assert.is_nil(names()["Abyss Thread"]);plan.choices[2].effect=negative.variantEffects[2].effect;assert.is_true(names()["Abyss Thread"])
	end)
	it("generates stable map pickups from specific Atlas strategy names",function()
		local plan={id="farming",title="Farming",version="3.30.0-preview",budget=150,nodes={},strategy={maps="Run Shaped Strand Map and Beach Maps; avoid Toxic Sewer Mapmaker",scarabs="Use Omen of Connections"}}
		build.savers.AtlasPlans:Upsert(plan)
		local profile=filters.profile("map-filter","Map filter");profile.rules=filters.generate(build,profile)
		local found={};for _,rule in ipairs(profile.rules) do if rule.origin=="atlas:farming" then found[rule.title]=rule end end
		assert.is_truthy(found["Shaped Strand Map"]);assert.is_truthy(found["Beach Map"]);assert.is_truthy(found["Omen of Connections"])
		assert.is_nil(found["Strand Map"]);assert.is_nil(found["Toxic Sewer Map"])
		local oldId=found["Beach Map"].id
		plan.strategy.maps="Beach Map, then Shaped Strand Map";build.savers.AtlasPlans:Upsert(plan)
		assert.is_true(dependencies.report(build,profile).stale==false)
		profile.rules=filters.generate(build,profile);found={};for _,rule in ipairs(profile.rules) do found[rule.title]=rule end
		assert.equal(oldId,found["Beach Map"].id)
		plan.strategy.maps="Strand Map";build.savers.AtlasPlans:Upsert(plan);assert.is_true(dependencies.report(build,profile).stale)
	end)
	it("respects named Atlas exclusions without suppressing separate budget pickups",function()
		local atlas=require("Modules.AtlasPlanner")
		local plan=atlas.connect({id="avoid",title="Avoided maps",version="3.30.0-preview",budget=150,nodes={},strategy={maps="Strand Map, Beach Map and Shaped Strand Map",scarabs="Breach Thread",avoid="Beach Maps and Breach Thread"}}, {4908})
		build.savers.AtlasPlans:Upsert(plan)
		local data=copyTable(build.savers.BuildJourney.data);data.resources={{id="budget-thread",title="Breach Thread"}};build.savers.BuildJourney.data=data
		local profile=filters.profile("avoid-filter","Avoid filter");profile.rules=filters.generate(build,profile)
		local found={};for _,rule in ipairs(profile.rules) do found[rule.title]=rule end
		assert.is_truthy(found["Strand Map"]);assert.is_truthy(found["Shaped Strand Map"]);assert.is_nil(found["Beach Map"])
		assert.equal("budget:budget-thread",found["Breach Thread"].origin)
	end)
	it("describes linked sources by name and handles removed sources",function()
		build.savers.CraftingProjects:Upsert(craft())
		build.savers.AtlasPlans:Upsert({id="maps",title="My maps",version="3.30.0-preview",budget=150,nodes={}})
		local data=copyTable(build.savers.BuildJourney.data);data.resources={{id="fossil",title="Fossils"}};data.wishlist={{id="hat",title="Life helmet",slot="Helmet",route="craft"}};build.savers.BuildJourney.data=data
		for origin,label in pairs({["craft:helmet"]="Crafting: Helmet",["atlas:maps"]="Atlas: My maps",["budget:fossil"]="Budget: Fossils",["gear:hat"]="Gear: Life helmet",gems="Active skill gems",["atlas:missing"]="Source no longer available"}) do
			assert.equal(label,dependencies.sourceLabel(build,origin))
		end
	end)
	it("lets an older saved filter review and keep the new base",function()
		local profile=filters.profile("old-base","Old base");profile.baseCommit="3ab00dd016b00c6be7acfa989baf498842973d54"
		profile.rules={{id="personal",title="My thread",text='Hide\n BaseType == "Frayed Thread"',enabled=true}}
		local workspace=require("Modules.PlanningWorkspace").new(build)
		workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}},page="Overview"})
		workspace.controls.manage:Click();main.popups[1].controls.search:SetText("Audit and update",true);main.popups[1].controls.choose:Click()
		assert.equal("Filter audit",main.popups[1].title);main.popups[1].controls.choose:Click()
		local updated=workspace.cache.filters.layout.snapshot().data.profiles[1]
		assert.equal(filters.source().commit,updated.baseCommit);assert.same(profile.rules,updated.rules)
		assert.is_truthy(filters.compile(updated));workspace.controls.keep:Click()
		local xml=build:SaveDB("Filter update");loadBuildFromXML(xml,"Filter update")
		local saved=build.savers.LootFilters.data.profiles[1];assert.equal(filters.source().commit,saved.baseCommit);assert.same(profile.rules,saved.rules)
	end)
	it("selects and deduplicates examples when switching filter scenes",function()
		local profile=filters.profile("scene-switch","Scene switch");local workspace=require("Modules.PlanningWorkspace").new(build)
		workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}},page="Simulate"})
		workspace.controls.sceneKind.selFunc(nil,"Divination cards")
		assert.equal("Divination Cards",workspace.cache.filters.layout.snapshot().sample.Class)
		workspace.controls.sceneStats:Click();assert.matches("12 results",main.popups[1].controls.count.label);main:ClosePopup()
		workspace.controls.sceneKind.selFunc(nil,"Essences")
		assert.matches("Essence",workspace.cache.filters.layout.snapshot().sample.BaseType)
		for _,row in ipairs(workspace.controls.selection.list) do assert.is_nil(row[1]:find("Unidentified item tier",1,true)) end
		workspace.controls.sceneStats:Click();assert.matches("12 results",main.popups[1].controls.count.label)
		for _,row in ipairs(main.popups[1].controls.results.list) do assert.is_nil(row[1]:find("(no tier)",1,true)) end;main:ClosePopup()
		local draft=workspace.cache.filters.layout.snapshot();draft.sample=require("Modules.LootFilterLibrary").sample();draft.sample.BaseType="Divine Orb"
		workspace:Show("filters",draft);workspace.controls.sceneStats:Click()
		assert.matches("13 results",main.popups[1].controls.count.label);main:ClosePopup()
		workspace.controls.sceneKind.selFunc(nil,"Tiered gear");local details={}
		for _,row in ipairs(workspace.controls.selection.list) do details[#details+1]=row[1] end
		assert.matches("Unidentified item tier: 0",table.concat(details," "))
	end)
	it("shows unknown tier on generated rare examples and explains Ruthless comparisons",function()
		local library=require("Modules.LootFilterLibrary");local profile=filters.profile("tier-preview","Tier preview")
		local sample;for _,item in ipairs(library.scene(profile,build,"Mixed drops",0,83,86)) do if item.BaseType=="Iron Hat" then sample=item end end
		local workspace=require("Modules.PlanningWorkspace").new(build)
		workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}},page="Simulate",sample=sample})
		local details={};for _,row in ipairs(workspace.controls.selection.list) do details[#details+1]=row[1] end
		assert.matches("Unidentified item tier: unknown",table.concat(details," "))
		workspace.controls.sceneStats:Click();main.popups[1].controls.search:SetText("Iron Hat",true)
		local rows={};for _,row in ipairs(main.popups[1].controls.results.list) do rows[#rows+1]=row[1] end
		assert.matches("tier unknown",table.concat(rows," "));main:ClosePopup()
		profile.mode="Ruthless";workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}},page="Simulate",sceneKind="Tiered gear"})
		assert.equal(0,workspace.cache.filters.layout.snapshot().sample.UnidentifiedItemTier)
	end)
	it("distinguishes quoted numeric modifier names from counts when checking linked targets",function()
		build.savers.CraftingProjects:Upsert(craft());local profile=filters.profile("filter","Filter");profile.rules=filters.generate(build,profile)
		profile.rules[1].text='Show\n HasExplicitMod "1" "foo"'
		local current=copyTable(profile.rules);current[1].text='Show\n HasExplicitMod 1 "foo"'
		local generate=filters.generate;filters.generate=function() return current end
		local ok,report=pcall(dependencies.report,build,profile);filters.generate=generate
		assert.is_true(ok);assert.is_true(report.stale);assert.equal("Changed",report.entries[1].status)
	end)
	it("does not mark linked targets stale for harmless string quoting",function()
		build.savers.CraftingProjects:Upsert(craft());local profile=filters.profile("filter","Filter");profile.rules=filters.generate(build,profile)
		profile.rules[1].text='Show\n BaseType "IronHat"'
		local current=copyTable(profile.rules);current[1].text='Show\n BaseType IronHat'
		local generate=filters.generate;filters.generate=function() return current end
		local ok,report=pcall(dependencies.report,build,profile);filters.generate=generate
		assert.is_true(ok);assert.is_false(report.stale)
	end)
	it("detects changed or removed generated targets without treating styles or inventory as dependencies",function()
		local project=craft();build.savers.CraftingProjects:Upsert(project);local profile=filters.profile("filter","Filter");profile.rules=filters.generate(build,profile)
		assert.is_false(dependencies.report(build,profile).stale)
		profile.rules[1].enabled=false;profile.rules[1].text=profile.rules[1].text.."\n SetFontSize 20";assert.is_false(dependencies.report(build,profile).stale)
		project.inventory={require("Modules.CraftingInventory").capture(project,require("Modules.CraftingSimulator").model(project.startingItem).initial)};build.savers.CraftingProjects:Upsert(project);assert.is_false(dependencies.report(build,profile).stale)
		project.startingItem=project.startingItem:gsub("86","87");build.savers.CraftingProjects:Upsert(project);local report=dependencies.report(build,profile);assert.is_true(report.stale);assert.equal("Changed",report.entries[1].status)
		profile.rules=filters.generate(build,profile);assert.is_false(dependencies.report(build,profile).stale)
		build.savers.CraftingProjects.projects={};assert.is_true(dependencies.report(build,profile).stale)
	end)
	it("links modeled recipe currencies to the filter and marks changed recipes stale",function()
		local project=craft();project.nativeRecipe={steps={{method="omen_connections"},{method="beast_max_links"}},targets={},requirements={links=4}}
		build.savers.CraftingProjects:Upsert(project)
		local profile=filters.profile("craft-resources","Craft resources");profile.rules=filters.generate(build,profile)
		local names={};for _,rule in ipairs(profile.rules) do names[rule.title]=true end
		assert.is_true(names["Omen of Connections"]);assert.is_true(names["Orb of Fusing"]);assert.is_nil(names["The Black Morrigan"])
		assert.equal("Show",filters.simulate(profile,{BaseType="Omen of Connections"}).action)
		assert.is_false(dependencies.report(build,profile).stale)
		project.nativeRecipe.steps={{method="socket_white_bench"}};build.savers.CraftingProjects:Upsert(project)
		assert.is_true(dependencies.report(build,profile).stale)
		profile.rules=filters.generate(build,profile);names={};for _,rule in ipairs(profile.rules) do names[rule.title]=true end
		assert.is_nil(names["Omen of Connections"]);assert.is_true(names["Orb of Scouring"])
	end)
	it("links exact saved crafting-resource budgets and refreshes them when the budget changes",function()
		local data=copyTable(build.savers.BuildJourney.data)
		data.resources={{id="fossil",title="pristine fossils"},{id="ichor",title="Greater Eldritch Ichor"},{id="omen",title="Omen of Connections"},
			{id="service",title="The Black Morrigan"},{id="unknown",title="Pristine Fossil service"},{id="removed",title="Perfect Fossil"}}
		build.savers.BuildJourney.data=data
		local profile=filters.profile("budget-items","Budget items");profile.rules=filters.generate(build,profile)
		local rules={};for _,rule in ipairs(profile.rules) do rules[rule.title]=rule end
		for _,name in ipairs({"Pristine Fossil","Greater Eldritch Ichor","Omen of Connections"}) do
			assert.is_truthy(rules[name],name);assert.matches('BaseType == "'..name..'"',rules[name].text)
			assert.equal("Show",require("Modules.LootFilterParser").simulate(require("Modules.LootFilterParser").parse(rules[name].text.."\nHide"),{BaseType=name}).action)
		end
		assert.is_nil(rules["The Black Morrigan"]);assert.is_nil(rules["Pristine Fossil service"]);assert.is_nil(rules["Perfect Fossil"])
		assert.is_false(dependencies.report(build,profile).stale)
		data=copyTable(data);data.resources[1].title="Dense Fossil";build.savers.BuildJourney.data=data
		assert.is_true(dependencies.report(build,profile).stale)
		profile.rules=filters.generate(build,profile);rules={};for _,rule in ipairs(profile.rules) do rules[rule.title]=true end
		assert.is_true(rules["Dense Fossil"]);assert.is_nil(rules["Pristine Fossil"])
	end)
	it("recognizes additional exact currency budgets without guessing service names",function()
		local data=copyTable(build.savers.BuildJourney.data)
		data.resources={{id="oil",title="golden oils"},{id="tattoo",title="Tattoo of the Ramako Archer"},
			{id="shard",title="Chaos Shard"},{id="gem",title="Gemcutter's Prism"},
			{id="service",title="Golden Oil service"}}
		build.savers.BuildJourney:Replace(data)
		local profile=filters.profile("more-budget","More budget items");profile.rules=filters.generate(build,profile)
		local origins={};for _,rule in ipairs(profile.rules) do origins[rule.origin]=rule end
		for origin,name in pairs({["budget:oil"]="Golden Oil",["budget:tattoo"]="Tattoo of the Ramako Archer",["budget:shard"]="Chaos Shard",["budget:gem"]="Gemcutter's Prism"}) do
			assert.is_truthy(origins[origin]);assert.is_truthy(origins[origin].text:find('BaseType == "'..name..'"',1,true))
			assert.equal("Show",filters.simulate(profile,{BaseType=name}).action)
		end
		assert.is_nil(origins["budget:service"])
	end)
	it("recognizes old budget names regardless of case and simple plurals",function()
		local data=require("Modules.BuildJourney").empty()
		data.resources={{id="orb",title="skittering delirium orbs"},{id="chisel",title="MAVEN'S CHISEL OF SCARABS"},
			{id="coin",title="coin of knowledge"},{id="service",title="skittering delirium orb service"}}
		build.savers.BuildJourney:Replace(data)
		local profile=filters.profile("renamed-budget","Renamed budget");profile.rules=filters.generate(build,profile)
		local found={};for _,rule in ipairs(profile.rules) do found[rule.origin]=rule.title end
		assert.equal("Threaded Delirium Orb",found["budget:orb"])
		assert.equal("Maven's Chisel of Threads",found["budget:chisel"])
		assert.equal("Soul Core of Intellect",found["budget:coin"])
		assert.is_nil(found["budget:service"])
	end)
	it("preserves recipe pickups and reports inspection failures",function()
		local project=craft();project.nativeRecipe={steps={{method="omen_connections"}},targets={},requirements={links=4}}
		build.savers.CraftingProjects:Upsert(project);local profile=filters.profile("review-craft","Review craft");profile.rules=filters.generate(build,profile)
		project.nativeRecipe.steps={{method="omen_connections"},{method="scour"}};build.savers.CraftingProjects:Upsert(project)
		local sim=require("Modules.CraftingSimulator");local original=sim.model;sim.model=function() error("fixture failure") end
		local ok,rules,warnings=pcall(filters.generate,build,profile)
		local reportOk,report=pcall(dependencies.report,build,profile);sim.model=original
		assert.is_true(ok);assert.equal(1,#warnings);assert.equal("craft:helmet",warnings[1].origin)
		assert.is_true(reportOk,report);assert.is_true(report.stale);assert.equal("Needs review",report.entries[1].status)
		local found=false;for _,rule in ipairs(rules) do if rule.title=="Omen of Connections" then found=true end end;assert.is_true(found)
		report=dependencies.report(build,profile);assert.equal("Changed",report.entries[1].status)
	end)
	it("retains unreadable base pickups and reports their sources for review",function()
		local project=craft();build.savers.CraftingProjects:Upsert(project)
		local journey=require("Modules.BuildJourney").empty()
		journey.wishlist={{id="hat",title="Hat target",slot="Helmet",route="farm",targetItem=project.startingItem}}
		build.savers.BuildJourney:Replace(journey)
		local profile=filters.profile("base-review","Base review");profile.rules=filters.generate(build,profile)
		local originalRules=copyTable(profile.rules)
		local projects=require("Modules.CraftingProjects");local original=projects.item
		projects.item=function(raw) if raw==project.startingItem then error("fixture item unavailable") end;return original(raw) end
		local ok,rules,warnings=pcall(filters.generate,build,profile)
		local reportOk,report=pcall(dependencies.report,build,profile)
		projects.item=original
		assert.is_true(ok);assert.is_true(reportOk,report);assert.equal(2,#warnings)
		local retained={};for _,rule in ipairs(rules) do retained[rule.id]=rule end
		for _,rule in ipairs(originalRules) do assert.same(rule,retained[rule.id]) end
		local statuses={};for _,entry in ipairs(report.entries) do statuses[entry.origin]=entry.status end
		assert.equal("Needs review",statuses["craft:helmet"]);assert.equal("Needs review",statuses["gear:hat"])
		journey.wishlist[1].targetItem=nil;build.savers.BuildJourney:Replace(journey)
		rules,warnings=filters.generate(build,profile);assert.equal(0,#warnings)
		for _,rule in ipairs(rules) do assert.not_equal("gear:hat",rule.origin) end
	end)
	it("generates and refreshes broad donor-base pickups for crafting guides",function()
		local project=craft();local donor="Rarity: NORMAL\nCone Helmet\nItem Level: 80"
		project.nativeRecipe={steps={{method="recombine",donorItem=donor},{method="recombine",donorItem=donor}},targets={},requirements={minAffixes=1}}
		build.savers.CraftingProjects:Upsert(project);local profile=filters.profile("donors","Donor bases");profile.rules=filters.generate(build,profile)
		local found={};for _,rule in ipairs(profile.rules) do if rule.id:match("^craft%-donor%-") then found[#found+1]=rule end end
		assert.equal(1,#found);assert.equal("Donor base: Cone Helmet",found[1].title);assert.matches('BaseType == "Cone Helmet"',found[1].text);assert.matches("ItemLevel >= 80",found[1].text)
		assert.equal("Show",filters.simulate(profile,{BaseType="Cone Helmet",Rarity="Normal",ItemLevel=80}).action)
		project.nativeRecipe.steps={{method="recombine",donorItem="Not a recognized item"}};build.savers.CraftingProjects:Upsert(project)
		local preserved,warnings=filters.generate(build,profile);local kept=false
		for _,rule in ipairs(preserved) do if rule.id==found[1].id then kept=true end end
		assert.is_true(kept);assert.is_true(#warnings>0);assert.matches("donor base",warnings[1].message)
		project.nativeRecipe.steps={{method="recombine",donorItem="Rarity: NORMAL\nIron Hat\nItem Level: 86"}};build.savers.CraftingProjects:Upsert(project)
		assert.is_true(dependencies.report(build,profile).stale);profile.rules=filters.generate(build,profile)
		for _,rule in ipairs(profile.rules) do assert.is_nil(rule.id:match("^craft%-donor%-")) end -- starting-base rule already covers this donor
	end)
	it("reports partial ingredient coverage while retaining known pickups",function()
		local project=craft();project.nativeRecipe={steps={{method="omen_connections"}},targets={},requirements={links=4}}
		build.savers.CraftingProjects:Upsert(project);local profile=filters.profile("partial-craft","Partial craft");profile.rules=filters.generate(build,profile)
		project.nativeRecipe.steps={{method="omen_connections"},{method="locus"}};build.savers.CraftingProjects:Upsert(project)
		local rules,warnings=filters.generate(build,profile);assert.equal(1,#warnings);assert.matches("ingredient breakdown",warnings[1].message)
		local names={};for _,rule in ipairs(rules) do names[rule.title]=true end;assert.is_true(names["Omen of Connections"]);assert.is_true(names["Orb of Fusing"])
		assert.is_true(dependencies.report(build,profile).stale)
	end)
	it("shows every warning for a crafting guide in linked targets",function()
		local project=craft();project.nativeRecipe={steps={{method="recombine",donorItem="Not a recognized item"},{method="locus"}},targets={},requirements={minAffixes=1}}
		build.savers.CraftingProjects:Upsert(project);local profile=filters.profile("multiple-warnings","Multiple warnings");profile.rules=filters.generate(build,profile)
		local report=dependencies.report(build,profile);local entry
		for _,value in ipairs(report.entries) do if value.origin=="craft:helmet" then entry=value end end
		assert.is_truthy(entry);assert.equal("Needs review",entry.status)
		local details=table.concat(entry.details,"\n");assert.matches("configured donor base",details);assert.matches("ingredient breakdown",details)
	end)
	it("reuses incomplete recipe checks until the retained draft changes",function()
		local project=craft();project.nativeRecipe={steps={{method="omen_connections"},{method="locus"}},targets={},requirements={links=4}}
		build.savers.CraftingProjects:Upsert(project);local profile=filters.profile("partial-cache","Partial cache");profile.rules=filters.generate(build,profile)
		local original=filters.generate;local calls=0;filters.generate=function(...) calls=calls+1;return original(...) end
		local ok,err=pcall(function()
			local first=dependencies.report(build,profile);assert.equal("Needs review",first.entries[1].status)
			assert.same(first,dependencies.report(build,profile));assert.equal(1,calls)
			profile.rules[1].title="Edited pickup";dependencies.report(build,profile);assert.equal(2,calls)
		end)
		filters.generate=original;assert.is_true(ok,err)
	end)
	it("shows recipe inspection warnings when refreshing pickups in the workspace",function()
		local project=craft();project.nativeRecipe={steps={{method="omen_connections"}},targets={},requirements={links=4}}
		build.savers.CraftingProjects:Upsert(project);local profile=filters.profile("review-ui","Review UI");profile.rules=filters.generate(build,profile)
		local workspace=require("Modules.PlanningWorkspace").new(build);workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}}})
		project.nativeRecipe.steps={{method="omen_connections"},{method="chaos"}};build.savers.CraftingProjects:Upsert(project)
		local sim=require("Modules.CraftingSimulator");local original=sim.model;sim.model=function() error("fixture failure") end
		local ok,err=pcall(function()
			workspace.controls.generate:Click()
			for _=1,10 do if main.popups[1] then break end;workspace.cache.filters.layout.tick() end
			assert.is_truthy(main.popups[1].controls.results)
		end)
		sim.model=original;assert.is_true(ok,err)
	end)
	it("leaves entirely manual filters untracked and preserves personal overrides on refresh",function()
		build.savers.CraftingProjects:Upsert(craft());local profile=filters.profile("filter","Filter");profile.rules={filters.rule("mine","Personal",{'BaseType == "Chaos Orb"'})}
		assert.is_false(dependencies.report(build,profile).stale);local original=copyTable(profile.rules[1]);profile.rules=filters.generate(build,profile);assert.same(original,profile.rules[1])
		local opened;assert.is_true(dependencies.open(build,{openWorkbench=function(project) opened=project.id end},"craft:helmet"));assert.equal("helmet",opened)
		for _,origin in ipairs({"craft:missing","atlas:missing","gear:missing","budget:missing","invalid"}) do
			local ok,reason=dependencies.open(build,{},origin);assert.is_false(ok);assert.matches("Refresh build pickups",reason)
		end
	end)
	it("reuses generated dependencies until native source state changes",function()
		local project=craft();build.savers.CraftingProjects:Upsert(project);local p=filters.profile("filter","Filter");local original=filters.generate;local calls=0
		filters.generate=function(...) calls=calls+1;return original(...) end
		local ok,err=pcall(function()
			dependencies.report(build,p);dependencies.report(build,p);assert.equal(1,calls)
			project.startingItem=project.startingItem:gsub("86","87");build.savers.CraftingProjects:Upsert(project);dependencies.report(build,p);assert.equal(2,calls)
		end)
		filters.generate=original;assert.is_true(ok,err)
	end)
	it("detects skill and active weapon changes before recalculation",function()
		local original=build.skillsTab.socketGroupList
		build.skillsTab.socketGroupList={{enabled=true,slot="Weapon 1",gemList={{enabled=true,nameSpec="Fireball"}}},{enabled=true,slot="Weapon 1 Swap",gemList={{enabled=true,nameSpec="Arc"}}}}
		local profile=filters.profile("skills","Skills");profile.rules=filters.generate(build,profile)
		local revision=build.outputRevision;assert.is_false(dependencies.report(build,profile).stale)
		build.itemsTab.activeItemSet.useSecondWeaponSet=true
		assert.equal(revision,build.outputRevision);assert.is_true(dependencies.report(build,profile).stale)
		profile.rules=filters.generate(build,profile);assert.is_false(dependencies.report(build,profile).stale)
		build.skillsTab.socketGroupList[2].enabled=false
		assert.equal(revision,build.outputRevision);assert.is_true(dependencies.report(build,profile).stale)
		build.itemsTab.activeItemSet.useSecondWeaponSet=false;build.skillsTab.socketGroupList=original
	end)
	it("checks recipe dependencies in bounded steps and discards changed sources",function()
		for i=1,3 do
			local project=craft();project.id="step"..i;project.startingItem=project.startingItem:gsub("86",tostring(70+i))
			project.nativeRecipe={steps={{method="omen_connections"}},targets={},requirements={links=4}};build.savers.CraftingProjects:Upsert(project)
		end
		local profile=filters.profile("async-check","Async check");local job=dependencies.begin(build,profile)
		local done,result,err=dependencies.poll(job);assert.is_false(done)
		local changed=copyTable(build.savers.CraftingProjects.projects[1]);changed.title="Changed during check";build.savers.CraftingProjects:Upsert(changed)
		done,result,err=dependencies.poll(job);assert.is_true(done);assert.is_nil(result);assert.equal("changed",err)
		job=dependencies.begin(build,profile);local slices=0
		repeat slices=slices+1;done,result,err=dependencies.poll(job);assert.is_nil(err) until done or slices>10
		assert.is_true(done);assert.is_true(slices>1);assert.same(dependencies.report(build,profile),result)
	end)
	it("generates pickups in steps and rejects an edited filter",function()
		for i=1,3 do
			local project=craft();project.id="generation"..i;project.startingItem=project.startingItem:gsub("86",tostring(30+i))
			project.nativeRecipe={steps={{method="socket_white_bench"}},targets={},requirements={sockets=1}};build.savers.CraftingProjects:Upsert(project)
		end
		local profile=filters.profile("generation","Generation");local job=dependencies.beginGenerate(build,profile)
		local done,result,err=dependencies.poll(job);assert.is_false(done)
		profile.rules[1]=filters.rule("manual","Manual",{'BaseType == "Chaos Orb"'})
		done,result,err=dependencies.poll(job);assert.is_true(done);assert.is_nil(result);assert.equal("changed",err)
		job=dependencies.beginGenerate(build,profile);local slices=0
		repeat slices=slices+1;done,result,err=dependencies.poll(job);assert.is_nil(err) until done or slices>10
		local rules,warnings=filters.generate(build,profile);assert.is_true(done);assert.is_true(slices>1);assert.same(rules,result.rules);assert.same(warnings,result.warnings)
	end)
	it("keeps the filter workspace usable while linked recipes are checked",function()
		for i=1,3 do
			local project=craft();project.id="ui-step"..i;project.startingItem=project.startingItem:gsub("86",tostring(60+i))
			project.nativeRecipe={steps={{method="socket_white_bench"}},targets={},requirements={sockets=1}};build.savers.CraftingProjects:Upsert(project)
		end
		local profile=filters.profile("async-ui","Async UI");local workspace=require("Modules.PlanningWorkspace").new(build)
		workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}}})
		assert.is_false(workspace.controls.generate:IsEnabled())
		assert.equal("Checking build pickups...",workspace.controls.generate.label())
		for _=1,10 do if workspace.controls.generate:IsEnabled() then break end;workspace.cache.filters.layout.tick() end
		assert.is_true(workspace.controls.generate:IsEnabled())
	end)
	it("shows target review warnings even before any pickup has been generated",function()
		local project=craft();build.savers.CraftingProjects:Upsert(project)
		local profile=filters.profile("unreadable-ui","Unreadable target")
		local projects=require("Modules.CraftingProjects");local original=projects.item
		projects.item=function(raw) if raw==project.startingItem then error("fixture item unavailable") end;return original(raw) end
		local ok,err=pcall(function()
			local report=dependencies.report(build,profile)
			assert.equal(0,report.linked);assert.is_false(report.stale);assert.is_true(report.needsReview)
			local workspace=require("Modules.PlanningWorkspace").new(build)
			workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}}})
			for _=1,10 do if workspace.controls.generate:IsEnabled() then break end;workspace.cache.filters.layout.tick() end
			assert.equal("Build pickups need review *",workspace.controls.generate.label())
			workspace.controls.generate:Click()
			for _=1,10 do if main.popups[1] then break end;workspace.cache.filters.layout.tick() end
			assert.is_truthy(main.popups[1].controls.results)
		end)
		projects.item=original;assert.is_true(ok,err)
	end)
	it("does not apply a pending pickup update after the build changes",function()
		local profile=filters.profile("generation-ui","Generation UI");local workspace=require("Modules.PlanningWorkspace").new(build)
		workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}}})
		local project=craft();project.startingItem=project.startingItem:gsub("86","37")
		project.nativeRecipe={steps={{method="socket_white_bench"}},targets={},requirements={sockets=1}};build.savers.CraftingProjects:Upsert(project)
		workspace.controls.generate:Click();assert.is_false(workspace.controls.generate:IsEnabled());assert.equal("Updating build pickups...",workspace.controls.generate.label())
		project.title="Changed during update";build.savers.CraftingProjects:Upsert(project);workspace.cache.filters.layout.tick()
		assert.equal(0,#workspace.cache.filters.layout.snapshot().data.profiles[1].rules);assert.is_truthy(main.popups[1])
	end)
	it("applies generated pickups after the staged update completes",function()
		local profile=filters.profile("generation-complete","Generation complete");local workspace=require("Modules.PlanningWorkspace").new(build)
		workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}}})
		for i=1,2 do
			local project=craft();project.id="ui-generate"..i;project.startingItem=project.startingItem:gsub("86",tostring(40+i))
			project.nativeRecipe={steps={{method="socket_white_bench"}},targets={},requirements={sockets=1}};build.savers.CraftingProjects:Upsert(project)
		end
		local previous=workspace.cache.filters.layout;workspace.controls.generate:Click()
		assert.equal(0,#previous.snapshot().data.profiles[1].rules)
		for _=1,10 do if workspace.cache.filters.layout~=previous then break end;previous.tick() end
		assert.is_not.equal(previous,workspace.cache.filters.layout)
		assert.is_true(#workspace.cache.filters.layout.snapshot().data.profiles[1].rules>0)
	end)
	it("shows unmatched Atlas strategy fields in the pickup review",function()
		build.savers.AtlasPlans:Upsert({id="notes",title="Atlas notes",version="3.30.0-preview",budget=150,nodes={},strategy={maps="Fast layouts"}})
		local profile=filters.profile("warnings","Warnings");local workspace=require("Modules.PlanningWorkspace").new(build)
		workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}}})
		local browser=require("Classes.PlanningBrowserControl");local original=browser.Open;local captured
		browser.Open=function(title,entries) captured={title=title,entries=entries} end
		workspace.controls.generate:Click()
		for _=1,20 do if not workspace.transient.filterGeneration then break end;workspace.cache.filters.layout.tick() end
		browser.Open=original
		assert.is_truthy(captured);assert.equal("Review build pickups",captured.title)
		assert.equal("Atlas notes",captured.entries[1].label);assert.matches("maps",captured.entries[1].details[1],1,true)
	end)
	it("continues a pickup update after changing filter screens",function()
		local profile=filters.profile("generation-nav","Generation navigation");local workspace=require("Modules.PlanningWorkspace").new(build)
		workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}}})
		for i=1,2 do
			local project=craft();project.id="nav-generate"..i;project.startingItem=project.startingItem:gsub("86",tostring(20+i))
			project.nativeRecipe={steps={{method="socket_white_bench"}},targets={},requirements={sockets=1}};build.savers.CraftingProjects:Upsert(project)
		end
		workspace.controls.generate:Click();assert.is_truthy(workspace.transient.filterGeneration)
		assert.is_nil(workspace.cache.filters.layout.snapshot().filterGeneration)
		workspace.controls.customize:Click()
		assert.is_truthy(workspace.transient.filterGeneration)
		workspace:Remember("filters");workspace.cache.filters=nil;workspace:Show("filters");local current=workspace.cache.filters.layout
		assert.is_truthy(workspace.transient.filterGeneration)
		for _=1,10 do if not workspace.transient.filterGeneration then break end;workspace.cache.filters.layout.tick() end
		assert.is_nil(workspace.transient.filterGeneration);assert.is_not.equal(current,workspace.cache.filters.layout)
		assert.is_true(#workspace.cache.filters.layout.snapshot().data.profiles[1].rules>0)
	end)
	it("does not apply an update to a different filter profile",function()
		local first=filters.profile("generation-first","First");local second=filters.profile("generation-second","Second")
		local workspace=require("Modules.PlanningWorkspace").new(build)
		workspace:Show("filters",{data={schemaVersion=1,activeId=first.id,profiles={first,second}}})
		local project=craft();project.startingItem=project.startingItem:gsub("86","19")
		project.nativeRecipe={steps={{method="socket_white_bench"}},targets={},requirements={sockets=1}};build.savers.CraftingProjects:Upsert(project)
		workspace.controls.generate:Click();assert.is_truthy(workspace.transient.filterGeneration)
		local state=workspace.cache.filters.layout.snapshot();state.selected=second.id;workspace:Show("filters",state)
		workspace.cache.filters.layout.tick();assert.is_nil(workspace.transient.filterGeneration);assert.is_truthy(main.popups[1])
		local profiles=workspace.cache.filters.layout.snapshot().data.profiles;assert.equal(0,#profiles[1].rules);assert.equal(0,#profiles[2].rules)
	end)
	it("prepares build-target simulator examples in stages and refreshes changed sources",function()
		for i=1,3 do
			local project=craft();project.id="scene"..i;project.startingItem=project.startingItem:gsub("86",tostring(10+i))
			project.nativeRecipe={steps={{method="socket_white_bench"}},targets={},requirements={sockets=1}};build.savers.CraftingProjects:Upsert(project)
		end
		local profile=filters.profile("target-scene","Target scene");local workspace=require("Modules.PlanningWorkspace").new(build)
		workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}},page="Simulate",sceneKind="Build targets"})
		local first=workspace.transient.filterSceneTargets;assert.is_truthy(first);assert.is_nil(first.rules)
		local changed=copyTable(build.savers.CraftingProjects.projects[1]);changed.title="Updated target";build.savers.CraftingProjects:Upsert(changed)
		for _=1,20 do if workspace.transient.filterSceneTargets.rules then break end;workspace.cache.filters.layout.tick() end
		local ready=workspace.transient.filterSceneTargets;assert.is_not.equal(first,ready);assert.is_truthy(ready.rules)
		local found=false;for _,rule in ipairs(ready.rules) do if rule.title=="Updated target base" then found=true end end;assert.is_true(found)
		assert.equal(0,#workspace.cache.filters.layout.snapshot().data.profiles[1].rules)
	end)
	it("clears pending simulator targets if the last profile is removed",function()
		local profile=filters.profile("target-remove","Target removal");local workspace=require("Modules.PlanningWorkspace").new(build)
		workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}},page="Simulate",sceneKind="Build targets"})
		assert.is_truthy(workspace.transient.filterSceneTargets)
		workspace:Show("filters",{data={schemaVersion=1,profiles={}},page="Simulate",sceneKind="Build targets"})
		assert.is_nil(workspace.transient.filterSceneTargets);assert.has_no.errors(function() workspace.cache.filters.layout.tick() end)
	end)
	it("reuses a compiled filter across navigation but recompiles after an edit",function()
		local profile=filters.profile("compile-cache","Compile cache");local workspace=require("Modules.PlanningWorkspace").new(build)
		local original=filters.compile;local calls=0;filters.compile=function(...) calls=calls+1;return original(...) end
		local ok,err=pcall(function()
			workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}}});local first=calls
			workspace.controls.viewSimulate:Click();assert.equal(first,calls)
			local state=workspace.cache.filters.layout.snapshot();state.data.profiles[1].title="Edited filter";workspace:Show("filters",state);assert.is_true(calls>first)
		end)
		filters.compile=original;assert.is_true(ok,err)
	end)
	it("reuses example evaluations while paging and invalidates them after a filter edit",function()
		local parser=require("Modules.LootFilterParser");local original=parser.simulate;local calls=0
		parser.simulate=function(...) calls=calls+1;return original(...) end
		local ok,err=pcall(function()
			local profile=filters.profile("scene-cache","Scene cache");local samples={}
			for i=1,30 do samples[i]={BaseType="Example "..i,Rarity="Normal",ItemLevel=86} end
			profile.sampleSets={{id="many",title="Many",samples=samples}}
			profile.rules={{id="hide",title="Hide first",text='Hide\n BaseType == "Example 1"',enabled=true}}
			local workspace=require("Modules.PlanningWorkspace").new(build)
			workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}},page="Simulate",sceneKind="Saved examples",sampleSetId="many",showHidden=false})
			local first=calls;assert.is_true(first>=30)
			local state=workspace.cache.filters.layout.snapshot();state.scenePage=2;workspace:Show("filters",state)
			assert.is_true(calls-first<5,"Paging reevaluated cached examples")
			local beforeReview=calls;workspace.controls.sceneStats:Click();assert.is_true(calls-beforeReview<5,"Review reevaluated cached examples");main:ClosePopup()
			state=workspace.cache.filters.layout.snapshot();state.data.profiles[1].rules[1].text='Show\n BaseType == "Example 1"';local beforeEdit=calls;workspace:Show("filters",state)
			assert.is_true(calls-beforeEdit>=30,"Changed filter reused old outcomes")
		end)
		parser.simulate=original;assert.is_true(ok,err)
	end)
	it("keeps nearby numeric sample values distinct in cached filter results",function()
		local profile=filters.profile("precise-scene","Precise scene")
		profile.template="Show"
		profile.rules={{id="threshold",title="Threshold",text="Hide\n Quality > 1.0000000000000002",enabled=true}}
		profile.sampleSets={{id="values",title="Values",samples={{BaseType="Iron Hat",Rarity="Normal",Quality=1},{BaseType="Iron Hat",Rarity="Normal",Quality=1.0000000000000004}}}}
		local workspace=require("Modules.PlanningWorkspace").new(build)
		workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}},page="Simulate",sceneKind="Saved examples",sampleSetId="values",showHidden=false})
		workspace.controls.sceneStats:Click();local seen={}
		for _,row in ipairs(main.popups[1].controls.results.list) do if row.entry and row.entry.sample and row.entry.sample.BaseType=="Iron Hat" then seen[row.entry.sample.Quality]=row.entry.category end end
		assert.equal("Show",seen[1]);assert.equal("Hide",seen[1.0000000000000004])
	end)
	it("retains bounded cache hits for example sets larger than the cache",function()
		local parser=require("Modules.LootFilterParser");local original=parser.simulate;local calls=0
		parser.simulate=function(...) calls=calls+1;return original(...) end
		local ok,err=pcall(function()
			local profile=filters.profile("large-scene","Large scene");profile.template="Show";local samples={}
			for i=1,1100 do samples[i]={BaseType="Example "..i,Rarity="Normal",ItemLevel=86} end
			profile.sampleSets={{id="many",title="Many",samples=samples}}
			local workspace=require("Modules.PlanningWorkspace").new(build)
			workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}},page="Simulate",sceneKind="Saved examples",sampleSetId="many",showHidden=false})
			local first=calls;local state=workspace.cache.filters.layout.snapshot();state.scenePage=2;workspace:Show("filters",state)
			assert.is_true(calls-first<100,"Large example sets evicted their reusable results")
			assert.equal(1024,workspace.transient.filterEvaluations.count)
		end)
		parser.simulate=original;assert.is_true(ok,err)
	end)
	it("keeps the source filter draft and previous working craft when following a link",function()
		local project=craft();build.savers.CraftingProjects:Upsert(project);local workspace=require("Modules.PlanningWorkspace").new(build)
		local profile=filters.profile("filter","Unsaved filter name");workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}},dirty=true})
		workspace.cache.filters.layout.openWorkbench(project);assert.equal("crafting",workspace.page);assert.is_truthy(workspace.drafts.filters.plan.dirty)
		workspace.controls.currency_alchemy:Click();workspace.controls.apply:Click();local previous=workspace.cache.crafting.layout.snapshot();assert.equal(1,#previous.actions)
		local item=require("Modules.CraftingInventory").capture(project,previous.state);workspace.cache.crafting.layout.openWorkbench(require("Modules.CraftingInventory").project(item))
		assert.equal(1,#workspace.craftDrafts[project.id].actions)
		workspace:Show("filters");assert.equal("Unsaved filter name",workspace.cache.filters.layout.snapshot().data.profiles[1].title)
	end)
end)
