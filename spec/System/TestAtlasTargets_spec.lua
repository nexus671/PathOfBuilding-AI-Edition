-- cspell:ignore Allflames
describe("Desired Atlas routes",function()
	local atlas=require("Modules.AtlasPlanner")
	local targets=require("Modules.AtlasTargets")
	local function plan() return {id="targets",title="Targets",version="3.30.0-preview",budget=150,nodes={},notes=""} end
	before_each(function() newBuild();main.popups={} end)
	after_each(function() targets.jobs[build]=nil;main.popups={} end)
	it("finds new Atlas mechanics and multi-mechanic notables",function()
		local strategy=require("Modules.AtlasStrategy");local p=plan()
		local function contains(list,id) for _,entry in ipairs(list) do if (type(entry)=="table" and entry.id or entry)==id then return true end end return false end
		for name,id in pairs({Mirage=14203,Wildwood=3814,Sentinels=40046,Torment=875,["Rogue Exiles"]=33902,Mercenaries=50374,["Ore Deposits"]=65008,Threads=34352}) do
			assert.is_true(contains(strategy.results(p,"",name),id));assert.is_true(contains(targets.mechanic(p,name).desired,id))
		end
		assert.is_true(contains(strategy.results(p,"","Rogue Exiles"),26414));assert.is_true(contains(strategy.results(p,"","Torment"),26414))
		assert.is_true(contains(targets.mechanic(p,"Torment").desired,26414))
		assert.is_true(contains(strategy.results(p,"","Harvest"),53175));assert.is_true(contains(targets.mechanic(p,"Harvest").desired,53175))
		assert.is_false(contains(strategy.results(p,"","Wildwood"),53175));assert.is_false(contains(strategy.results(p,"","Wildwood"),52197))
		local tree=atlas.tree(p.version);local blight=tree.nodes[64318]
		assert.is_true(strategy.hasMechanic(blight,"Blight"));assert.is_false(strategy.hasMechanic(blight,"Incursion"))
		assert.is_false(contains(strategy.results(p,"","Incursion"),64318));assert.is_false(contains(targets.mechanic(p,"Incursion").desired,64318))
		local mixed=tree.nodes[4908];assert.is_true(strategy.hasMechanic(mixed,"Strongboxes"));assert.is_true(strategy.hasMechanic(mixed,"Mercenaries"))
		local names={};for _,name in ipairs(strategy.allMechanics(mixed)) do names[name]=true end
		assert.is_true(names.Strongboxes);assert.is_true(names.Mercenaries);assert.is_nil(names.Maps)
		assert.is_false(strategy.hasMechanic({name="Greater Strongbox",stats={}},"Bosses"))
		assert.is_true(strategy.hasMechanic({name="Alva's Workshop",stats={}},"Incursion"))
		assert.is_true(strategy.hasMechanic({name="Unknown",stats={"Your Maps have no chance to contain the Sacred Grove"}},"Harvest"))
		assert.is_true(strategy.hasMechanic({name="Unknown",stats={"Your Maps have no chance to contain Smuggler's Caches"}},"Heist"))
	end)
	it("classifies Mercenary and Ore investments without double-counting",function()
		local p=atlas.connect(plan(),{50374,65008});local summary=targets.summary(p);local count,found=0,{}
		for _,row in ipairs(summary.mechanics) do count=count+row.total;found[row.name]=true end
		assert.equal(#p.nodes,count);assert.is_true(found.Mercenaries);assert.is_true(found["Ore Deposits"])
	end)
	it("classifies Thread choices as Threads while keeping their names searchable",function()
		local strategy=require("Modules.AtlasStrategy")
		local function contains(rows,id) for _,entry in ipairs(rows) do if (type(entry)=="table" and entry.id or entry)==id then return true end end;return false end
		for _,version in ipairs({"3.30.0-preview","3.30.0-preview-ruthless"}) do
			local p=plan();p.version=version;local tree=atlas.tree(version)
			local threadResults=strategy.results(p,"Breach","Threads")
			local breachResults=strategy.results(p,"","Breach")
			local threadTargets=targets.mechanic(p,"Threads").desired
			local breachTargets=targets.mechanic(p,"Breach").desired
			for _,id in ipairs({64980,54685}) do
				local node=tree.nodes[id];assert.equal("Threads",strategy.mechanic(node))
				assert.same({"Threads"},strategy.allMechanics(node));assert.is_false(strategy.hasMechanic(node,"Breach"))
				assert.is_true(contains(threadResults,id));assert.is_false(contains(breachResults,id))
				assert.is_true(contains(threadTargets,id));assert.is_false(contains(breachTargets,id))
			end
			local breachRoute=false;for _,route in ipairs(strategy.presets(p)) do if route.mechanic=="Breach" then
				breachRoute=true
				assert.is_false(contains(route.targets,64980));assert.is_false(contains(route.targets,54685))
			end end
			assert.is_true(breachRoute)
		end
	end)
	it("invalidates Thread classification when base and choice text change",function()
		local strategy=require("Modules.AtlasStrategy")
		local node={name="Test",stats={"Threads found in your Maps cannot be of type"},variantEffects={{stats={"Breach"}}}}
		assert.equal("Threads",strategy.mechanic(node));assert.is_false(strategy.hasMechanic(node,"Breach"))
		-- The combined search text is unchanged, but the semantic boundary moved.
		node.stats={"Threads found in your Maps"};node.variantEffects[1].stats={"cannot be of type Breach"}
		assert.is_true(strategy.hasMechanic(node,"Breach"))
		node.variantEffects[1].stats={"cannot be of type Ritual"}
		assert.is_false(strategy.hasMechanic(node,"Breach"));assert.is_true(strategy.hasMechanic(node,"Ritual"))
	end)
	it("classifies both Secrets Unveiled choices as Betrayal",function()
		local strategy=require("Modules.AtlasStrategy");local node=atlas.tree("3.30.0-preview").nodes[45404]
		local p=atlas.connect(plan(),{node.id});local counts={}
		for _,effect in ipairs(node.variantEffects) do
			p=atlas.chooseEffect(p,node.id,effect.effect)
			assert.equal("Betrayal",strategy.mechanic(strategy.selectedNode(p,node)))
			for _,row in ipairs(targets.summary(p).mechanics) do if row.name=="Betrayal" then counts[#counts+1]=row.total end end
		end
		assert.equal(2,#counts);assert.equal(counts[1],counts[2])
		assert.is_false(strategy.hasMechanic({name="Unknown",stats={"Allflames found in your Maps"}},"Betrayal"))
	end)
	it("warns when historical Mercenary investment includes its encounter blocker",function()
		local version="3.29.3";local p=atlas.connect({id="blocked",title="Blocked",version=version,budget=atlas.tree(version).maxPoints,nodes={}}, {24930,50374})
		local warnings=table.concat(targets.summary(p).warnings," ")
		assert.matches("Mercenaries investment includes a blocking modifier",warnings);assert.matches("no chance to contain Mercenaries",warnings)
	end)
	it("detects an invested mechanic even when a node has another primary category",function()
		local version="3.29.3";local tree=atlas.tree(version);local p=atlas.connect({id="secondary",title="Secondary",version=version,budget=tree.maxPoints,nodes={}}, {24930})
		assert.equal(0,#targets.summary(p).warnings)
		local node;for _,id in ipairs(p.nodes) do local candidate=tree.nodes[id];if require("Modules.AtlasStrategy").mechanic(candidate)=="Incursion" then node=candidate;break end end
		assert.is_not_nil(node);local original=node.stats;node.stats=copyTable(original);node.stats[#node.stats+1]="Wild Mercenaries accompany this encounter"
		local ok,result=pcall(targets.summary,p);node.stats=original
		assert.is_true(ok,tostring(result));assert.matches("Mercenaries investment includes a blocking modifier",table.concat(result.warnings," "))
	end)
	it("keeps desired and avoided preferences exclusive and portable",function()
		local p=plan();local id=atlas.search(p.version,"Bountiful Harvest",1).matches[1].id
		p=targets.toggle(p,id,"desired");assert.same({id},p.desired)
		p=targets.toggle(p,id,"avoided");assert.same({},p.desired);assert.same({id},p.avoided)
		assert.same(p,atlas.import(atlas.export(p)))
		local invalid=copyTable(p);invalid.desired={id};assert.is_false(pcall(atlas.validate,invalid))
		p=targets.toggle(p,id,"avoided");p=targets.toggle(p,id,"desired");p=atlas.connect(p,{id});assert.is_false(pcall(targets.toggle,p,id,"avoided"))
	end)
	it("selects mechanic notables without selecting blocking notables",function()
		local p=targets.mechanic(plan(),"Harvest");assert.is_true(#p.desired>0)
		for _,id in ipairs(p.desired) do local node=atlas.tree(p.version).nodes[id];assert.equal("notable",node.kind);assert.equal(0,#targets.blocking(node)) end
		assert.same({},targets.mechanic(p,"Harvest").desired)
	end)
	it("previews in cooperative slices and rejects stale application",function()
		local p=targets.mechanic(plan(),"Harvest");local state=targets.start(build,p)
		state.paused=true;targets.tick(build,true);assert.equal("suspended",coroutine.status(state.thread));assert.is_nil(state.result)
		state.paused=false;for _=1,1000 do targets.tick(build,true);if not state.thread then break end end
		assert.is_nil(state.error);assert.is_truthy(state.result);assert.equal(0,#p.nodes)
		local preview=targets.apply(build,p);assert.is_true(#preview.nodes>0);assert.same(p.desired,preview.desired)
		local changed=copyTable(p);changed.notes="Changed";assert.is_false(pcall(targets.apply,build,changed))
		targets.cancel(build);assert.is_nil(state.result);assert.equal("Cancelled",state.status)
	end)
	it("retains selected effects only when rebuilt routes retain their nodes",function()
		local node=atlas.tree("3.30.0-preview").nodes[45404];local p=atlas.connect(plan(),{node.id})
		p=atlas.chooseEffect(p,node.id,node.variantEffects[1].effect);p.desired={node.id}
		local state=targets.start(build,p,true);for _=1,1000 do targets.tick(build,true);if not state.thread then break end end
		assert.is_nil(state.error);assert.same(p.choices,state.result.plan.choices)
		p.desired={atlas.tree(p.version).nodes[atlas.tree(p.version).start].links[1]}
		state=targets.start(build,p,true);for _=1,1000 do targets.tick(build,true);if not state.thread then break end end
		assert.is_nil(state.error);assert.same({},state.result.plan.choices)
	end)
	it("explains conflicting selected Thread types without claiming encounters are blocked",function()
		local tree=atlas.tree("3.30.0-preview");local positive,negative=tree.nodes[54685],tree.nodes[64980]
		local p=atlas.connect(plan(),{positive.id,negative.id})
		p=atlas.chooseEffect(p,positive.id,positive.variantEffects[1].effect);p=atlas.chooseEffect(p,negative.id,negative.variantEffects[1].effect)
		local strategy=require("Modules.AtlasStrategy")
		for _,node in ipairs({positive,negative}) do
			local selected=strategy.selectedNode(p,node)
			assert.equal("Threads",strategy.mechanic(selected));assert.is_false(strategy.hasMechanic(selected,"Breach"))
			assert.same({"Threads"},strategy.allMechanics(selected))
		end
		local summary=targets.summary(p);assert.equal(1,#summary.threadRestrictions);assert.equal("Breach",summary.threadRestrictions[1].mechanic)
		local threads;for _,row in ipairs(summary.mechanics) do if row.name=="Threads" then threads=row end end
		assert.is_truthy(threads);assert.is_true(threads.total>=2)
		local warning=table.concat(summary.warnings," ");assert.is_truthy(warning:find("conflicting with Dextral Threads",1,true));assert.is_truthy(warning:find("does not block Breach encounters",1,true))
		p=atlas.chooseEffect(p,negative.id,negative.variantEffects[2].effect);summary=targets.summary(p)
		assert.equal("Ritual",summary.threadRestrictions[1].mechanic);assert.is_nil(table.concat(summary.warnings," "):find("conflicting with Dextral Threads",1,true))
		p=atlas.chooseEffect(p,negative.id,nil);assert.equal(0,#targets.summary(p).threadRestrictions)
	end)
	it("honors saved exclusions even when no extra exclusions are supplied",function()
		local p=plan();local neighbour=atlas.tree(p.version).nodes[atlas.tree(p.version).start].links[1];p.avoided={neighbour}
		assert.is_false(pcall(atlas.connect,p,{neighbour}));assert.is_false(pcall(atlas.connectOptimized,p,{neighbour}))
		assert.is_true(#targets.summary(p).mechanics==0)
	end)
	it("clears running and completed routes when the build mode is reused",function()
		local p=targets.mechanic(plan(),"Harvest");local state=targets.start(build,p)
		newBuild();assert.is_nil(targets.jobs[build]);assert.is_nil(state.result);assert.is_nil(state.thread)
		state=targets.start(build,p)
		for _=1,1000 do targets.tick(build,true);if not state.thread then break end end
		assert.is_truthy(state.result);newBuild();assert.is_nil(targets.jobs[build]);assert.is_nil(state.result)
	end)
end)
