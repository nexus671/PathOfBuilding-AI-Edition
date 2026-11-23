-- cspell:ignore jsontype
describe("Saved crafting resource prices",function()
	local sim=require("Modules.CraftingSimulator");local prices=require("Modules.CraftingPrices")
	it("includes every reachable success and recovery route without following dead steps",function()
		local steps={{method="alchemy",onSuccess=3,onFailure=4},{method="alteration"},{method="chaos",onSuccess=5,onFailureAction="restart"},{method="scour",onSuccess=5,onFailureAction="stop"},{method="exalt",onSuccess=3,onFailureAction="salvage"}}
		local reachable=prices.reachableSteps(steps);assert.are.same({steps[1],steps[3],steps[4],steps[5]},reachable)
		steps[1].onFailure=2;steps[2].onFailure=4;assert.are.same(steps,prices.reachableSteps(steps))
		assert.are.same({},prices.reachableSteps({}))
	end)
	it("does not turn new service artwork into a currency quote",function()
		local aliases=prices.currencyAliases({alchemy="alchemy-id",beast_talisman_imprint="orb-id",future_service="orb-id"})
		assert.equal("alchemy-id",aliases.alchemy);assert.is_nil(aliases.beast_talisman_imprint);assert.is_nil(aliases.future_service)
	end)
	local raw="Rarity: NORMAL\nPlate Vest\nItem Level: 86\nQuality: 20\nSockets: W W W W W W"
	local omen="Metadata/Items/Currency/AncestralOmenOnFusingMakeFullLinks";local fusing="Metadata/Items/Currency/CurrencyRerollSocketLinks"
	local function book(values) return {currency="chaos",source="Test quotes",quotedAt=1700000000,values=values or {[omen]=2,[fusing]=0.25}} end
	it("shows the red beast and preserves existing flask-service quotes",function()
		local flask="Rarity: NORMAL\nSmall Life Flask\nItem Level: 86";local model=sim.model(flask)
		local action={method="beast_flask",modId="FlaskChillFreezeImmunity1"}
		local name,_,kind=prices.describe("beast_any_red",model,action)
		assert.equal("Any red beast",name);assert.equal("Beast",kind);assert.equal("beast_any_red",prices.key("beast_any_red",model))
		local rows=prices.entries(model,model.initial,{action},book({beast_flask=4}));local found
		for _,row in ipairs(rows) do if row.key=="beast_any_red" then found=row end end
		assert.is_not_nil(found);assert.equal("Any red beast",found.name);assert.is_true(found.required)
		for _,key in ipairs({"beast_flask","beast_any_red"}) do
			local recipe={steps={action},targets={{anyOf={action.modId}}}}
			local result=sim.simulate(flask,recipe,{trials=3,maxActions=1,seed=1,priceBook=book({[key]=4}),currency="chaos"})
			assert.equal(4,result.meanCost)
		end
		local recipe={steps={action},targets={{anyOf={action.modId}}}}
		local result=sim.simulate(flask,recipe,{trials=1,maxActions=1,seed=1,priceBook=book({beast_flask=4,beast_any_red=2}),currency="chaos"})
		assert.equal(4,result.meanCost)
		assert.equal("beast_any_red",result.resourceUsage[1].key);assert.equal(1,result.resourceUsage[1].amount)
		result=sim.simulate(flask,recipe,{trials=1,maxActions=1,seed=1,priceBook=book({beast_flask=4,beast_any_red=2}),actionPrices={beast_flask=7},currency="chaos"})
		assert.equal(7,result.meanCost);assert.equal("beast_any_red",result.resourceUsage[1].key)
		newBuild();main.popups={}
		local controls=require("Classes.CraftingPricesControl").Open(model,model.initial,{action},book({beast_flask=4}),"chaos",function() end)
		local hint={};for _,row in ipairs(controls.hint.list) do hint[#hint+1]=row[1] or "" end
		assert.matches("takes priority",table.concat(hint," "),1,true);main.popups={}
	end)
	local function project() return {id="priced-body",title="Priced body armour",slot="Body Armour",startingItem=raw,goals={},steps={},preferredMethod="omen_connections",nativeRecipe={steps={{method="omen_connections"}},targets={},requirements={links=6}},priceBook=book()} end
	before_each(function() newBuild() end)
	after_each(function() require("Modules.CraftingTasks").cancel();main.popups={} end)
	it("includes possible corrupted-item surcharges after either Gwennen outcome",function()
		local model=sim.model(raw);local vaal=prices.key("vaal",model)
		local function required(action)
			local entries=prices.entries(model,model.initial,{action,{method="socket_colour_bench",count=3}})
			for _,entry in ipairs(entries) do if entry.key==vaal then return entry.required end end
		end
		assert.is_true(required({method="gwennen",firstOutcome=1012,secondOutcome=1000}))
		assert.is_true(required({method="gwennen",firstOutcome=1000,secondOutcome=1012}))
		assert.is_false(required({method="gwennen",firstOutcome=1000,secondOutcome=1000}))
		local controls=require("Classes.CraftingPricesControl").Open(model,model.initial,{{method="gwennen",firstOutcome=1000,secondOutcome=1012},{method="socket_colour_bench",count=3}},nil,"chaos",function() end)
		controls.search:SetText("Vaal Orb",true);assert.matches("Vaal Orb",StripEscapes(controls.resources.list[1][1]));controls.close:Click()
	end)
	it("retains quote metadata, zero and unknown values across build save and reopen",function()
		local saved=project();saved.priceBook.values[fusing]=0;build.savers.CraftingProjects:Upsert(saved)
		local empty=project();empty.id="empty-quotes";empty.priceBook=book({});build.savers.CraftingProjects:Upsert(empty)
		build.savers.CraftingProjects:Upsert(saved)
		local json=require("dkjson")
		local copied=require("Modules.CraftingProjects").copy(build.savers.CraftingProjects.projects)
		assert.is_truthy(json.encode(copied[2].priceBook):find('"values":{}',1,true))
		assert.is_truthy(json.encode(require("Modules.BuildInsights").snapshot(build).craftingProjects[2].priceBook):find('"values":{}',1,true))
		local xml=build:SaveDB("Resource quote round trip");loadBuildFromXML(xml,"Resource quote round trip")
		assert.are.same(saved.priceBook,build.savers.CraftingProjects.projects[1].priceBook)
		assert.is_nil(build.savers.CraftingProjects.projects[1].priceBook.values.alchemy)
		assert.is_truthy(table.concat(require("Modules.CraftingProjects").lines(saved)," "):find("Resource quotes: 2 in chaos",1,true))
		assert.are.equal("object",getmetatable(prices.validate(book({})).values).__jsontype)
		for _,value in ipairs({-1,math.huge,0/0,"2"}) do local invalid=book({[omen]=value});assert.is_false(pcall(prices.validate,invalid)) end
	end)
	it("prices a two-step guide from saved resource quotes without mutating options",function()
		local recipe={steps={{method="harvest_enchant",enchantId="LifeBodyEnchant"},{method="omen_connections"}},targets={},requirements={links=6,harvestEnchant="LifeBodyEnchant"}}
		local quote=book({wild_lifeforce=0.1,[omen]=2,[fusing]=0.25});local options={trials=4,maxActions=2,priceBook=quote};local before=copyTable(options)
		local result=sim.simulate(raw,recipe,options)
		assert.are.equal(4,result.successes);assert.are.equal(327.25,result.meanCost);assert.are.equal("chaos",result.costCurrency)
		assert.are.equal(13000,result.currencySpent.wild_lifeforce);assert.are.equal("Test quotes",result.priceSource);assert.are.equal(1700000000,result.priceQuotedAt)
		assert.are.same(before,options);assert.is_false(result.priceOverridesSupplied)
		quote.values[fusing]=nil;result=sim.simulate(raw,recipe,options);assert.is_nil(result.meanCost);assert.is_true(result.unpriced[fusing])
		quote.values[fusing]=0;result=sim.simulate(raw,recipe,options);assert.are.equal(327,result.meanCost)
	end)
	it("lists corruption costs among the current recipe resources",function()
		local model=sim.model(raw);local state=copyTable(model.initial);state.corrupted=true
		local vaal=prices.key("vaal",model)
		for _,action in ipairs({{method="socket_white_bench"},{method="socket_colour_bench",count=3},{method="socket_bench",count=6,linked=true}}) do
			local rows=prices.entries(model,state,{action},book({}));local found
			for _,row in ipairs(rows) do if row.key==vaal then found=row end end
			assert.is_truthy(found,action.method);assert.is_true(found.required)
		end
		local rows=prices.entries(model,model.initial,{{method="socket_white_bench"}},book({}))
		for _,row in ipairs(rows) do if row.key==vaal then assert.is_false(row.required) end end
		for _,case in ipairs({
			{actions={{method="socket_white_bench"}},recipeState=state},
			{actions={{method="locus"},{method="socket_white_bench"}}},
			{actions={{method="socket_white_bench"},{method="locus",onSuccess=1}}},
		}) do
			local found
			for _,row in ipairs(prices.entries(model,model.initial,case.actions,book({}),case.recipeState)) do if row.key==vaal then found=row end end
			assert.is_truthy(found);assert.is_true(found.required)
		end
		local controls=require("Classes.CraftingPricesControl").Open(model,model.initial,{{method="socket_white_bench"}},book({}),"chaos",function() end,nil,state)
		controls.search:SetText("Vaal Orb",true)
		local visible=false;for _,row in ipairs(controls.resources.list) do if row.key==vaal then visible=true end end
		assert.is_true(visible)
		controls.close:Click()
	end)
	it("prices both currencies for a corrupted socket colour craft",function()
		local model=sim.model(raw);local state=copyTable(model.initial);state.corrupted=true
		local chromatic=prices.key("chromatic",model);local vaal=prices.key("vaal",model)
		local recipe={steps={{method="socket_colour_bench",count=3}},targets={},requirements={corrupted=true}}
		local result=sim.simulate(raw,recipe,{initialState=state,trials=3,maxActions=1,forceFirstAction=true,
			priceBook=book({[chromatic]=0.5,[vaal]=1})})
		assert.are.equal(3,result.successes);assert.are.equal(30,result.meanCost)
		local used={};for _,entry in ipairs(result.resourceUsage) do used[entry.key]=entry.amount end
		assert.are.equal(60,used[chromatic]);assert.are.equal(60,used[vaal])
		local missing=sim.simulate(raw,recipe,{initialState=state,trials=1,maxActions=1,forceFirstAction=true,
			priceBook=book({[chromatic]=0.5})})
		assert.is_nil(missing.meanCost);assert.is_true(missing.unpriced[vaal])
		local quoted=sim.simulate(raw,recipe,{initialState=state,trials=3,maxActions=1,forceFirstAction=true,currency="chaos",
			actionPrices={[sim.priceKey(recipe.steps[1])]=7}})
		assert.are.equal(7,quoted.meanCost);assert.are.same(result.resourceUsage,quoted.resourceUsage)
	end)
	it("resolves currency aliases and keeps explicit action overrides separate",function()
		local m=sim.model(raw);local state=copyTable(m.initial);state.rarity="RARE"
		local id=assert(prices.aliases(m).exalt);local quote=book({[id]=2})
		local recipe={steps={{method="exalt"}},targets={},requirements={minAffixes=1}}
		local result=sim.simulate(raw,recipe,{initialState=state,trials=1,maxActions=1,priceBook=quote});assert.are.equal(2,result.meanCost)
		result=sim.simulate(raw,recipe,{initialState=state,trials=1,maxActions=1,priceBook=quote,prices={exalt=7}});assert.are.equal(7,result.meanCost);assert.is_true(result.priceOverridesSupplied)
		result=sim.simulate(raw,recipe,{initialState=state,trials=1,maxActions=1,priceBook=quote,prices={[id]=9}});assert.are.equal(9,result.meanCost)
		assert.is_false(pcall(prices.resolve,quote,"divine",m));quote.values.exalt=3;assert.is_false(pcall(prices.resolve,quote,"chaos",m))
		for _,info in ipairs(itemLib.influenceInfo.default) do
			assert.are.equal(info.display.."'s Exalted Orb",prices.describe("influence_exalt:"..info.key,m))
		end
		local flask=sim.model("Rarity: NORMAL\nSmall Life Flask\nItem Level: 86")
		assert.are.equal("Glassblower's Bauble",prices.describe("quality",flask))
	end)
	it("uses fossil and resonator quotes in subset comparison",function()
		local fossil="Metadata/Items/Currency/CurrencyDelveCraftingLife";local m=sim.model(raw);local resonator=assert(prices.aliases(m)["resonator:1"])
		for i=1,4 do assert.is_truthy(prices.aliases(m)["resonator:"..i]) end
		assert.are.equal(resonator,prices.key("Metadata/Items/Delve/DelveSocketableCurrencyReroll1",m))
		local result=sim.optimizeFossils(raw,{}, {fossils={fossil},maxSockets=1,trials=3,requirements={minAffixes=1},priceBook=book({[fossil]=1,[resonator]=2})})
		assert.are.equal(3,result.combinations[1].meanCost)
	end)
	it("shows generic Bestiary quotes while allowing a specific price to replace them",function()
		local m=sim.model(raw);local a={method="beast_prefix_suffix",beastLevel=86};local key=sim.priceKey(a);local saved
		local c=require("Classes.CraftingPricesControl").Open(m,m.initial,{a},book({beast_prefix_suffix=2}),"chaos",function(value) saved=value end)
		c.search:SetText("beast level 86",true)
		assert.matches("Generic quote: 2 chaos",StripEscapes(c.resources.list[2][1]));assert.equal("",c.price.buf)
		c.mode:SelByValue("Quoted resources");c.mode.selFunc()
		assert.matches("Generic quote: 2 chaos",StripEscapes(c.resources.list[2][1]))
		c.price:SetText("7",true);assert.matches("7 chaos",StripEscapes(c.resources.list[2][1]))
		c.price:SetText("",true);assert.matches("Generic quote: 2 chaos",StripEscapes(c.resources.list[2][1]))
		c.keep:Click();assert.equal(2,saved.values.beast_prefix_suffix);assert.is_nil(saved.values[key])
	end)
	it("stages visual quote edits and requires resetting values before changing units",function()
		local m=sim.model(raw);local kept
		local c=require("Classes.CraftingPricesControl").Open(m,m.initial,{{method="omen_connections"}},nil,"chaos",function(value) kept=value end)
		c.search:SetText("Omen of Connections",true);c.price:SetText("2",true);assert.is_false(c.currency:IsEnabled())
		c.search:SetText("Orb of Fusing",true);c.price:SetText("0.25",true);c.keep:Click()
		assert.are.equal(2,kept.values[omen]);assert.are.equal(0.25,kept.values[fusing]);assert.are.equal(0,#main.popups)
		kept=nil;c=require("Classes.CraftingPricesControl").Open(m,m.initial,{{method="omen_connections"}},book(),"chaos",function(value) kept=value end)
		c.keep:Click();assert.are.equal(1700000000,kept.quotedAt)
		kept=nil;c=require("Classes.CraftingPricesControl").Open(m,m.initial,{{method="omen_connections"}},book(),"chaos",function(value) kept=value end)
		c.reset:Click();assert.is_true(c.currency:IsEnabled());c.currency:SetText("divine");c.close:Click();assert.is_nil(kept)
		local library=project();library.title="Quote library"
		c=require("Classes.CraftingPricesControl").Open(m,m.initial,{{method="omen_connections"}},nil,"divine",function(value) kept=value end,{library})
		c.copy:Click();main.popups[1].controls.keep:Click();assert.are.equal("chaos",c.currency.buf);c.keep:Click();assert.are.same(library.priceBook,kept)
	end)
	it("keeps action overrides with their action across switching and checkpoints",function()
		local p=project();p.priceBook=nil;p.preferredMethod="alchemy";p.nativeRecipe=nil
		local c=require("Classes.CraftingSimulatorControl").Open(build,p);c.price:SetText("3")
		c.method:SelByValue("chaos","val");c.method.selFunc();assert.are.equal("",c.price.buf)
		c.method:SelByValue("alchemy","val");c.method.selFunc();assert.are.equal("3",c.price.buf)
		c.keepWorking:Click();local saved=build.savers.CraftingProjects.projects[1];assert.are.equal("3",saved.run.priceOverrides.alchemy)
		c.close:Click();c=require("Classes.CraftingSimulatorControl").Open(build,saved);assert.are.equal("3",c.price.buf)
		c.method:SelByValue("chaos","val");c.method.selFunc();assert.are.equal("",c.price.buf)
		c.page:SelByValue("Simulate recipe");c.page.selFunc();c.baseCost:SetText("10");c.resourcePrices:Click();local editor=main.popups[1].controls
		editor.reset:Click();editor.currency:SetText("divine");editor.keep:Click()
		assert.are.equal("",c.price.buf);assert.are.equal("",c.baseCost.buf)
		c.method:SelByValue("alchemy","val");c.method.selFunc();assert.are.equal("",c.price.buf)
		local run=build.savers.CraftingProjects.projects[1].run
		assert.are.equal("divine",run.settings.currency);assert.are.equal("",run.settings.price);assert.are.equal("",run.settings.baseCost);assert.is_nil(next(run.priceOverrides))
	end)
	it("shares saved quotes between native simulation and recipe comparison",function()
		local p=project();build.savers.CraftingProjects:Upsert(p)
		local c=require("Classes.CraftingSimulatorControl").Open(build,p);c.page:SelByValue("Simulate recipe");c.page.selFunc()
		assert.is_false(c.currency:IsEnabled());c.trials:SetText("3");c.budget:SetText("1");c.runRecipe:Click()
		local jobs=require("Modules.CraftingTasks");for _=1,100 do if not jobs.job then break end;jobs.tick(build) end;assert.is_nil(jobs.job)
		local lines={};for _,row in ipairs(c.resultSummary.list) do lines[#lines+1]=row[1] end;assert.is_truthy(table.concat(lines," "):find("Mean spent: 2.25 chaos",1,true))
		c.compareRecipes:Click();local compare=main.popups[1].controls;compare.route2:SelByValue(2,"val");assert.is_false(compare.price2:IsEnabled())
		compare.price1:SetText("9");compare.route1:SetSel(2);compare.route1:SetSel(1);assert.are.equal("9",compare.price1.buf)
		compare.run:Click();for _=1,100 do if not jobs.job then break end;jobs.tick(build) end;assert.is_nil(jobs.job)
		lines={};for _,row in ipairs(compare.results.list) do lines[#lines+1]=row[1] end;assert.is_truthy(table.concat(lines," "):find("2.25 chaos",1,true))
	end)
end)
