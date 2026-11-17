describe("Crafting action preconditions",function()
	local sim=require("Modules.CraftingSimulator")
	local check=require("Modules.CraftingAvailability").check
	before_each(function() newBuild() end)
	it("explains Locus restrictions before offering the action",function()
		local function shallow(source) local result={};for k,v in pairs(source) do result[k]=v end;return setmetatable(result,getmetatable(source)) end
		local model=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86")
		local state=copyTable(model.initial);state.corrupted=true
		assert.is_true(check("locus",state,model))
		local mod=model.mods[1];local fractured=copyTable(state);fractured.rarity="RARE";fractured.affixes={{id=mod.id,range=0.5,fractured=true}}
		local allowed,reason=check("locus",fractured,model);assert.is_false(allowed);assert.matches("fractured",reason)
		local ok,errorText=pcall(sim.action,model,fractured,{method="locus"},function() return 0 end);assert.is_false(ok);assert.is_truthy(errorText:find(reason,1,true))
		local special=sim.model("Rarity: NORMAL\nSacrificial Garb\nItem Level: 86")
		local specialState=copyTable(special.initial);specialState.corrupted=true
		allowed,reason=check("locus",specialState,special);assert.is_false(allowed);assert.matches("special Locus",reason)
		ok,errorText=pcall(sim.action,special,specialState,{method="locus"},function() return 0 end);assert.is_false(ok);assert.is_truthy(errorText:find(reason,1,true))
		local synthesised=shallow(model);synthesised.item=shallow(model.item);synthesised.item.synthesised=true
		allowed,reason=check("locus",state,synthesised);assert.is_false(allowed);assert.matches("special Locus",reason)
		local locked=copyTable(state);locked.rarity="RARE";locked.affixes={{id=mod.id,range=0.5}}
		local custom=shallow(model);custom.byId=shallow(model.byId);custom.byId[mod.id]=shallow(model.byId[mod.id]);custom.byId[mod.id][1]="Prefixes Cannot Be Changed"
		allowed,reason=check("locus",locked,custom);assert.is_false(allowed);assert.matches("meta%-modifier",reason)
		ok,errorText=pcall(sim.action,custom,locked,{method="locus"},function() return 0 end);assert.is_false(ok);assert.is_truthy(errorText:find(reason,1,true))
	end)
	it("explains Aspect crafts without equipment or a free suffix",function()
		local jewel=sim.model("Rarity: NORMAL\nCobalt Jewel\nItem Level: 86")
		local allowed,reason=check("beast_aspect",jewel.initial,jewel);assert.is_false(allowed);assert.are.equal("Aspect crafts require equipment.",reason)
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local model=sim.model(raw)
		assert.is_true(check("beast_aspect",model.initial,model))
		local full
		for seed=1,100 do local state=sim.perform(raw,{method="alchemy"},seed).state;local count=0;for _,entry in ipairs(state.affixes) do if model.byId[entry.id].type=="Suffix" then count=count+1 end end;if count==3 then full=state;break end end
		assert.is_truthy(full);allowed,reason=check("beast_aspect",full,model);assert.is_false(allowed);assert.are.equal("Requires an open suffix.",reason)
	end)
	it("explains when an Annulment has no removable modifier",function()
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local model=sim.model(raw);local state=copyTable(model.initial)
		state.rarity="MAGIC";state.affixes={{id=model.mods[1].id,range=0.5,fractured=true}}
		state=sim.validateState(model,state)
		local allowed,reason=check("annul",state,model);assert.is_false(allowed);assert.matches("fractures or locks",reason)
		local catalog=sim.catalog(raw,"",5,state);local annul;for _,entry in ipairs(catalog.methodAvailability) do if entry.method=="annul" then annul=entry end end
		assert.is_false(annul.available);assert.matches("fractures or locks",annul.unavailableReason);assert.matches("further restrictions",catalog.methodAvailabilityNote)
		assert.is_false(pcall(sim.action,model,state,{method="annul"},function() return 0.5 end))
		main.popups={};local project={id="protected-annul",title="Fractured helmet",slot="Helmet",startingItem=raw,goals={},steps={},run=require("Modules.CraftingInventory").run(state)}
		local controls=require("Classes.CraftingSimulatorControl").Open(build,project)
		assert.is_false(controls.currency_annul:IsEnabled());assert.matches("fractures or locks",controls.currency_annul.tooltipText())
		local candidate=copyTable(state);candidate.affixes[1].fractured=nil;assert.is_true(check("annul",candidate,model))
		main.popups={}
	end)
	it("requires actual defence variance for Sacred Orbs",function()
		local model=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86")
		assert.is_true(check("sacred",model.initial,model))
		-- A fixed-range native model must agree with the action's own precondition.
		model.item.base=copyTable(model.item.base)
		for _,property in ipairs({"Armour","Evasion","EnergyShield","Ward"}) do model.item.base.armour[property.."BaseMax"]=model.item.base.armour[property.."BaseMin"] end
		assert.is_false(check("sacred",model.initial,model))
		assert.is_false(pcall(sim.action,model,model.initial,{method="sacred"},function() return 0.5 end))
	end)
	it("explains missing rarities, implicit states, imprints, sockets and fractures",function()
		local model=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86");local state=model.initial
		for _,method in ipairs({"chaos","fracture","conflict","restore_imprint","unveil","chromatic","remove_crafted"}) do local ok,why=check(method,state,model);assert.is_false(ok,method);assert.is_truthy(why,method) end
		assert.is_true(check("alchemy",state,model));assert.is_true(check("quality",state,model))
		state=sim.perform(model.raw or "Rarity: NORMAL\nIron Hat\nItem Level: 86",{method="alchemy"},104729).state;assert.is_true(check("fracture",state,model));state.affixes[1].fractured=true;assert.is_false(check("fracture",state,model))
	end)
	it("keeps valid corrupted and unfinished-state exceptions available",function()
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86\nSockets: R-G-B";local model=sim.model(raw);local state=sim.perform(raw,{method="alchemy"},104729).state
		state.corrupted=true;assert.is_false(check("chaos",state,model));assert.is_true(check("tainted_chaos",state,model));assert.is_true(check("socket_bench",state,model))
		state.intangibility=50;assert.is_true(check("ducat_tzamoto",state,model));state.corrupted=false
		state=sim.perform(raw,{method="veiled_orb"},104729,state).state;assert.is_true(check("unveil",state,model));assert.is_false(check("annul",state,model))
	end)
	it("offers the non-white socket bench only when it has a valid count option",function()
		local model=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86\nSockets: W");local state=model.initial
		local allowed,reason=check("socket_colour_bench",state,model)
		assert.is_false(allowed);assert.are.equal("Requires at least two sockets.",reason)
		assert.are.equal(0,#sim.actionOptions(model,state,"socket_colour_bench"));assert.is_true(check("chromatic",state,model))
		state=sim.perform(model.raw,{method="socket_bench",count=2},1).state
		assert.is_true(check("socket_colour_bench",state,model));assert.are.equal(1,#sim.actionOptions(model,state,"socket_colour_bench"))
		state.corrupted=true;assert.is_true(check("socket_colour_bench",state,model))
	end)
	it("uses the proper class restrictions and bundled quality currency artwork",function()
		local model=sim.model("Rarity: NORMAL\nSmall Life Flask\nItem Level: 20");assert.is_true(check("quality",model.initial,model));assert.is_false(check("alchemy",model.initial,model));assert.is_false(check("catalyst",model.initial,model))
		local art=require("Modules.CraftingWorkbench");local path=art.icon("quality",{},model);local file=assert(io.open("Assets/Crafting/currencies.json"));local manifest=assert(require("dkjson").decode(file:read("*a")));file:close();local expected
		for _,entry in pairs(manifest.items) do if entry.name=="Glassblower's Bauble" then expected=entry.path end end;assert.is_truthy(expected);assert.equal(expected,path)
	end)
	it("explains missing automatic Allflame data and accepts an observed override",function()
		local raw="Rarity: NORMAL\nPrismatic Tincture\nItem Level: 86";local model=sim.model(raw)
		local state=sim.perform(raw,{method="transmute"},1).state
		local action={method="ducat_kishara"};local reason=sim.configurationReason(model,state,action)
		assert.matches("observed override",reason)
		local catalog=sim.catalog(raw,"",5,state);local entry
		for _,row in ipairs(catalog.methodAvailability) do if row.method==action.method then entry=row end end
		assert.is_true(entry.available);assert.equal(reason,entry.configurationRequired)
		local project={id="kishara-tincture",title="Tincture",slot="Tincture 1",startingItem=raw,goals={},steps={},run=require("Modules.CraftingInventory").run(state)}
		local controls=require("Classes.CraftingSimulatorControl").Open(build,project)
		controls.method:SelByValue(action.method,"val");controls.method.selFunc()
		assert.is_false(controls.apply:IsEnabled());assert.matches("observed override",controls.apply.tooltipText())
		controls.page:SelByValue("Craft settings");controls.page.selFunc();controls.allflame:Click()
		local settings=main.popups[1].controls;settings.mode:SelByValue("Observed override")
		settings.outcomes:SetText("1");settings.gainMin:SetText("0");settings.gainMax:SetText("0");settings.sulphur:SetText("0");settings.use:Click()
		assert.is_true(controls.apply:IsEnabled());assert.not_matches("observed override",controls.apply.tooltipText())
		controls.page:SelByValue("Emulate item");controls.page.selFunc();controls.apply:Click();assert.is_true(controls.undo:IsEnabled());main.popups={}
	end)

end)
