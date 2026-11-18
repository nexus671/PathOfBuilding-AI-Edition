-- cspell:ignore Allflames
describe("Native Atlas planner", function()
	local atlas=require("Modules.AtlasPlanner")
	local bridge=require("Modules.DesktopBuildBridge")
	local function plan(version,budget)
		version=version or "3.27.0"
		return {id="mapping",title="Mapping strategy",version=version,budget=budget or atlas.tree(version).maxPoints,nodes={},notes="Map sustain first"}
	end
	before_each(function() newBuild(); bridge.prepared=nil end)
	after_each(function() bridge.prepared=nil; main.popups={} end)
	it("presents the released 3.30 name without changing saved identifiers",function()
		assert.equal("3.30.0",atlas.versionLabel("3.30.0-preview"))
		assert.equal("3.30.0 Ruthless",atlas.versionLabel("3.30.0-preview-ruthless"))
		local source=plan("3.30.0-preview");local validated=atlas.validate(source)
		assert.equal("3.30.0-preview",validated.version)
		local report=atlas.report(validated);assert.equal("3.30.0",report.displayVersion);assert.equal("3.30.0",report.releaseTag);assert.equal("2026-11-18",report.releaseCheckedAt)
		local controls=require("Classes.AtlasPlannerControl").Open(build,validated)
		assert.equal("3.30.0",controls.version:GetSelValueByKey("label"))
		assert.equal("3.30.0-preview",controls.version:GetSelValueByKey("val"))
	end)
	it("persists a tier 17 Nightmare map draft",function()
		local source=plan("3.30.0-preview")
		source.mapDrafts={{id="nightmare",title="Abomination",patch="3.30.0.2.2",baseId="Metadata/Items/Maps/MapWorldsAbomination",tier=17,itemLevel=84,rarity="rare",selected={"MapUberModCurses"}}}
		source.mapDrafts[1].estimate={wantedGroups={{"MapUberWeakContainsDeliriumMirror"}},avoid={},trials=3,maxAttempts=5,price={amount=0.5,currency="chaos"}}
		local store=atlas.new(build);store:Upsert(source);local xml={};store:Save(xml)
		local reopened=atlas.new(build);reopened:Load(xml);assert.same(source.mapDrafts,reopened.plans[1].mapDrafts)
		assert.same(source.mapDrafts,atlas.import(atlas.export(source)).mapDrafts)
		local invalid=copyTable(source);invalid.mapDrafts[1].rarity="magic";assert.has_error(function() atlas.validate(invalid) end)
	end)
	it("keeps multiple map drafts through Atlas save, export and reopen",function()
		local source=plan("3.30.0-preview");source.mapDrafts={}
		for i=1,12 do source.mapDrafts[i]={id="map-"..i,title="Map "..i,patch="3.30.0.2.2",baseId="Metadata/Items/Maps/MapWorldsStrand",tier=16,itemLevel=83,rarity="normal",selected={}} end
		source.mapDrafts[1].rarity="rare";source.mapDrafts[1].selected={"MapMonsterCriticalStrikesAndDamageMapWorlds"};source.mapDrafts[1].rolls={{id="MapMonsterCriticalStrikesAndDamageMapWorlds",values={16,9,6,183,32}}}
		source.mapDrafts[1].quality={kind="Pack Size",value=20}
		source.mapDrafts[1].observedEffects={{kind="implicit",text="Area is Influenced by the Originator's Memories"},{kind="enchant",text="Players are Delirious"}}
		local map=require("Modules.MapCraftingData");local ids={}
		for _=1,9 do local page=map.inspect("Metadata/Items/Maps/MapWorldsStrand",16,83,ids,"",0,100,nil,"rare",nil,true);ids[#ids+1]=page.candidates[1].id end
		source.mapDrafts[2].rarity="rare";source.mapDrafts[2].corrupted=true;source.mapDrafts[2].selected=ids;source.mapDrafts[2].implicit={id="MapCorruptionItemRarity",value=15}
		source.mapDrafts[2].observedEffects={{kind="explicit",text="Players in Area are 35% Delirious"},{kind="explicit",text="Delirium Reward Type: Currency"}}
		source.mapDrafts[3].corrupted=true;source.mapDrafts[3].implicit={id="MapCorruptionItemRarity",value=15}
		source.mapDrafts[4].mirrored=true;source.mapDrafts[4].rarity="magic";source.mapDrafts[4].corrupted=true;source.mapDrafts[4].unidentified=true
		source.mapDrafts[1].estimate={wantedGroups={{"MapContainsMirageWorlds","MapContainsWildwoodWorlds"}},avoid={"MapMonsterAreaOfEffectMapWorlds"},trials=25,maxAttempts=10}
		local store=atlas.new(build);store:Upsert(source);local xml={};store:Save(xml)
		local reopened=atlas.new(build);reopened:Load(xml);assert.same(source.mapDrafts,reopened.plans[1].mapDrafts)
		assert.same(source.mapDrafts,atlas.import(atlas.export(source)).mapDrafts)
		local unsupported=copyTable(source);unsupported.mapDrafts[1].baseId="Metadata/UnknownFutureMap";assert.same(unsupported.mapDrafts,atlas.validate(unsupported).mapDrafts)
		local duplicate=copyTable(source);duplicate.mapDrafts[2].id=duplicate.mapDrafts[1].id;assert.has_error(function() atlas.validate(duplicate) end)
		local badQuality=copyTable(source);badQuality.mapDrafts[1].quality.value=101;assert.has_error(function() atlas.validate(badQuality) end)
		local badObserved=copyTable(source);badObserved.mapDrafts[1].observedEffects[1].text="^1unsafe";assert.has_error(function() atlas.validate(badObserved) end)
		local badRarity=copyTable(source);badRarity.mapDrafts[3].observedEffects=copyTable(source.mapDrafts[2].observedEffects);assert.has_error(function() atlas.validate(badRarity) end)
		local badRoll=copyTable(source);badRoll.mapDrafts[1].rolls[1].id="unknown";assert.has_error(function() atlas.validate(badRoll) end)
		local badTarget=copyTable(source);badTarget.mapDrafts[1].estimate.avoid={"MapContainsMirageWorlds"};assert.has_error(function() atlas.validate(badTarget) end)
		local badBudget=copyTable(source);badBudget.mapDrafts[1].estimate.trials=1000;badBudget.mapDrafts[1].estimate.maxAttempts=21;assert.has_error(function() atlas.validate(badBudget) end)
	end)
	it("keeps, opens and removes map drafts from the Atlas planner",function()
		local panel=require("Classes.AtlasPlannerControl");local controls=panel.Open(build,plan("3.30.0-preview"))
		controls.tools:Click();local tools=main.popups[1].controls;tools.search:SetText("Map modifier explorer",true);tools.choose:Click()
		local mapControls=main.popups[1].controls;mapControls.draftName:SetText("My map",true)
		mapControls.list.onClick({line=mapControls.list.list[1]});mapControls.add:Click();mapControls.keep:Click();mapControls.draftName:SetText("Updated map",true);assert.matches("Keep the map draft again",mapControls.status.label);mapControls.keep:Click();mapControls.close:Click()
		controls.keep:Click();assert.equal(1,#build.savers.AtlasPlans.plans[1].mapDrafts)
		controls=panel.Open(build,build.savers.AtlasPlans.plans[1]);controls.tools:Click();tools=main.popups[1].controls;tools.search:SetText("Saved map drafts",true);tools.choose:Click()
		local library=main.popups[1].controls;assert.matches("Updated map",library.results.list[1][1]);library.choose:Click()
		mapControls=main.popups[1].controls;assert.equal("Updated map",mapControls.draftName.buf);assert.is_true(mapControls.remove:IsEnabled());mapControls.close:Click()
		controls.tools:Click();tools=main.popups[1].controls;tools.search:SetText("Saved map drafts",true);tools.choose:Click();library=main.popups[1].controls;library.secondary:Click();main:ClosePopup()
		controls.keep:Click();assert.equal(0,#build.savers.AtlasPlans.plans[1].mapDrafts)
	end)
	it("preserves, searches and reports 3.30 multiple-choice effects",function()
		local version="3.30.0-preview";local node=atlas.tree(version).nodes[45404]
		assert.equal("Secrets Unveiled",node.name);assert.equal(2,#node.variantEffects)
		assert.is_true(atlas.search(version,"Double-Veiled Item",100).total>0)
		local routed=atlas.connect(plan(version),{node.id});assert.equal(1,#atlas.report(routed).missingChoices)
		local chosen=atlas.chooseEffect(routed,node.id,node.variantEffects[1].effect)
		assert.equal(0,#atlas.report(chosen).missingChoices);assert.equal(node.variantEffects[1].stats[1],atlas.nodeStats(chosen,node)[1])
		local restored=atlas.import(atlas.export(chosen),version);assert.same(chosen.choices,restored.choices)
		local store=atlas.new(build);store:Upsert(chosen);local xml={};store:Save(xml);local reopened=atlas.new(build);reopened:Load(xml);assert.same(chosen.choices,reopened.plans[1].choices)
		assert.same(chosen.choices,atlas.import(atlas.url(chosen),version).choices)
		assert.has_error(function() atlas.url(routed) end)
		local panel=require("Classes.AtlasPlannerControl");local controls=panel.Open(build,routed)
		assert.is_false(controls.url:IsEnabled());controls=panel.Open(build,chosen);assert.is_true(controls.url:IsEnabled())
		assert.has_error(function() atlas.chooseEffect(chosen,node.id,65535) end)
		assert.has_error(function() atlas.chooseEffect(plan(version),node.id,node.variantEffects[1].effect) end)
		local removed=atlas.remove(chosen,node.id);assert.equal(0,#removed.choices)
		local strategy=require("Modules.AtlasStrategy");local other=atlas.chooseEffect(chosen,node.id,node.variantEffects[2].effect)
		assert.is_true(#strategy.compare(chosen,other).stats>=2)
		local ruthless=atlas.tree("3.30.0-preview-ruthless").nodes[node.id];assert.is_truthy(ruthless.variantEffects)
	end)
	it("renders official Atlas link markup as readable text",function()
		assert.equal("Threads and Mirage",atlas.displayStat("[Thread|Threads] and [Mirage]"))
		local node=atlas.tree("3.30.0-preview").nodes[64980]
		local plan=atlas.chooseEffect(atlas.connect(plan("3.30.0-preview"),{node.id}),node.id,node.variantEffects[1].effect)
		assert.same({"Threads found in your Maps cannot be of type","Breach"},atlas.nodeStats(plan,node))
		local match=atlas.search(plan.version,"Threads found in your Maps cannot",100).matches
		local found=false;for _,entry in ipairs(match) do if entry.id==node.id then found=true;assert.equal("Breach",entry.variantEffects[1].stats[1]);assert.is_truthy(entry.stats[1]:find("Threads",1,true)) end end;assert.is_true(found)
	end)
	it("reviews and routes effect changes and refunds between Atlas stages",function()
		local version="3.30.0-preview";local node=atlas.tree(version).nodes[45404]
		local base=atlas.connect(plan(version),{node.id});local first=atlas.chooseEffect(base,node.id,node.variantEffects[1].effect)
		local second=atlas.chooseEffect(base,node.id,node.variantEffects[2].effect);local strategy=require("Modules.AtlasStrategy")
		local changed=strategy.transition(first,second);assert.is_truthy(changed.steps);assert.equal(0,#changed.steps)
		assert.equal(node.variantEffects[2].effect,changed.choiceChanges[1].effect);assert.is_truthy(table.concat(changed.lines," "):find("Allflames",1,true))
		assert.is_true(changed.choiceReselectionCostUnknown);assert.is_true(changed.choiceChanges[1].reselectionCostUnknown)
		assert.equal(node.variantEffects[1].effect,changed.choiceChanges[1].previousEffect)
		assert.matches("additional refund",table.concat(changed.lines," "));assert.matches("unverified",table.concat(changed.lines," "))
		assert.is_false(strategy.transition(first,first).choiceReselectionCostUnknown)
		assert.is_false(strategy.transition(base,first).choiceReselectionCostUnknown)
		local removed=atlas.remove(first,node.id);local refunded=strategy.transition(first,removed);assert.is_truthy(refunded.steps)
		local found=false;for _,step in ipairs(refunded.steps) do if step.action=="Refund" and step.id==node.id then found=true end end;assert.is_true(found)
		local noChoice=strategy.transition(first,base);assert.is_truthy(table.concat(noChoice.lines," "):find("destination has none selected",1,true))
		build.savers.AtlasPlans:Upsert(first);local revision=bridge.revision(build)
		local prepared=bridge.prepare(build,{mode="edit",title=second.title,baseRevision=revision,operations={{type="set_atlas_plan",plan=second}}})
		assert.is_truthy(table.concat(prepared.changes," "):find("Selected effect: Secrets Unveiled",1,true));assert.is_truthy(table.concat(prepared.changes," "):find("Allflames",1,true))
		second.id="next-stage";second.progression={stage="final",previousId=first.id}
		require("Classes.AtlasPlanningControl").Open(build,second,function() end)
		local rows={};for _,row in ipairs(main.popups[1].controls.transition.list) do rows[#rows+1]=StripEscapes(row[1]) end
		assert.is_truthy(table.concat(rows," "):find("Choose effect for Secrets Unveiled",1,true));assert.is_truthy(table.concat(rows," "):find("additional refund",1,true))
	end)
	it("loads pinned Standard graphs with symmetric edges and free starts", function()
		for _,version in ipairs(atlas.versions) do
			local tree=atlas.tree(version)
			assert.are.equal(29045,tree.start)
			assert.are.equal(0,atlas.report(plan(version)).used)
			for id,node in pairs(tree.nodes) do for _,other in ipairs(node.links) do
				local found=false; for _,reverse in ipairs(tree.nodes[other].links) do if reverse == id then found=true end end
				assert.is_true(found)
			end end
		end
	end)
	it("searches literal names and stat text without allocating decorative labels", function()
		local matches=atlas.search("3.27.0","Essence",100)
		assert.is_true(matches.total > 1)
		assert.is_true(#matches.matches <= 100)
		assert.is_true(atlas.search("3.27.0","[",100).total >= 0)
		assert.are.equal(false,pcall(atlas.tree,"3.28.0"))
		assert.are.equal(false,pcall(atlas.validate,{id="x",title="x",version="3.27.0",budget=132,nodes={56946}}))
	end)
	it("connects a known path with a budget and no mutation of its input", function()
		local input=plan(); local tree=atlas.tree(input.version)
		local target=tree.nodes[tree.start].links[1]
		local result,added=atlas.connect(input,{target})
		assert.are.equal(1,#result.nodes); assert.are.equal(target,added[1])
		assert.are.equal(0,#input.nodes)
		assert.are.equal(false,pcall(atlas.connect,plan(nil,0),{target}))
		assert.are.equal(false,pcall(atlas.connect,input,{target},{target}))
	end)
	it("prunes nodes disconnected by branch removal and rejects duplicate or disconnected input", function()
		local tree=atlas.tree("3.27.0"); local target=atlas.search("3.27.0","Unwavering Vision",10).matches[1].id
		local result=atlas.connect(plan(),{target})
		assert.is_true(#result.nodes > 1)
		local startNeighbour
		for _,id in ipairs(result.nodes) do for _,other in ipairs(tree.nodes[tree.start].links) do if id == other then startNeighbour=id end end end
		assert.are.equal(0,#atlas.remove(result,startNeighbour).nodes)
		local invalid=plan(); invalid.nodes={target}; assert.are.equal(false,pcall(atlas.validate,invalid))
		invalid.nodes={tree.start,tree.start}; assert.are.equal(false,pcall(atlas.validate,invalid))
	end)
	it("asks before removing a disconnected branch and supports cancel and undo",function()
		local tree=atlas.tree("3.27.0");local original=atlas.connect(plan(),{65225});local allocated={}
		for _,id in ipairs(original.nodes) do allocated[id]=true end
		local root;for _,id in ipairs(tree.nodes[tree.start].links) do if allocated[id] then root=id;break end end
		local controls=require("Classes.AtlasPlannerControl").Open(build,original);controls.canvas.focus=root
		controls.remove:Click();assert.is_truthy(main.popups[1].controls.confirm);main:ClosePopup()
		assert.is_truthy(controls.status.label:find("20 granted",1,true))
		controls.remove:Click();main.popups[1].controls.confirm:Click();assert.is_truthy(controls.status.label:find("0 /",1,true))
		controls.undo:Click();assert.is_truthy(controls.status.label:find("20 granted",1,true))
	end)
	it("accounts for granted points and keeps raw stat counts separate from effective odds", function()
		local target=atlas.search("3.27.0","Unwavering Vision",10).matches[1].id
		local result=atlas.connect(plan(),{target}); local report=atlas.report(result)
		assert.are.equal(20,report.bonus)
		assert.are.equal(result.budget+20-#result.nodes,report.remaining)
		assert.is_true(#report.stats > 0)
		assert.are.equal("Unwavering Vision",report.keystones[1])
		assert.is_truthy(report.limitations[2]:find("not combined",1,true))
	end)
	it("requires enough earned points to reach a point-granting node before spending its grant",function()
		local target=atlas.search("3.29.3","Unwavering Vision",10).matches[1].id
		local full=atlas.connect(plan("3.29.3"),{target});local needed=#full.nodes
		assert.is_true(needed>1 and needed<=20)
		local impossible=copyTable(full);impossible.budget=needed-1
		assert.is_false(atlas.budgetReachability(impossible));assert.is_false(pcall(atlas.connect,plan("3.29.3",needed-1),{target}))
		assert.is_false(pcall(atlas.connect,plan("3.29.3",0),{target}))
		local report=atlas.report(impossible);assert.is_false(report.budgetReachable);assert.equal(needed,report.pointsBeforeGrant);assert.is_truthy(report.budgetWarning:find("Unwavering Vision",1,true))
		local store=atlas.new(build);assert.is_false(pcall(store.Upsert,store,impossible))
		store.plans={copyTable(impossible)};impossible.notes="Keep my old notes";assert.equal(impossible.notes,store:Upsert(impossible).notes)
		local attainable=copyTable(full);attainable.budget=needed;assert.is_true(atlas.budgetReachability(attainable))
		assert.is_true(atlas.budgetReachability(atlas.connect(plan("3.29.3",needed),{target})))
		local alternate=atlas.connect(plan("3.29.3"),{target},{17321});alternate.avoided=nil;assert.is_true(#alternate.nodes>needed)
		alternate.budget=needed;local direct,warning,_,proof=atlas.budgetReachability(alternate)
		assert.is_true(direct);assert.is_truthy(warning:find("temporary route",1,true));assert.is_true(#proof>0);assert.equal(alternate.id,atlas.new(build):Upsert(alternate).id)
		assert.same(proof,atlas.report(alternate).grantRoute)
		local originalId=proof[1].id;proof[1].id=0;assert.equal(originalId,atlas.report(alternate).grantRoute[1].id)
		local controls=require("Classes.AtlasPlannerControl").Open(build,alternate);assert.matches("Temporary grant route",controls.status.label)
		controls.stats:Click();local browser=main.popups[1].controls;local found=false
		for _,row in ipairs(browser.results.list) do if row.entry and row.entry.id=="grant-route" then found=true end end
		assert.is_true(found);browser.search:SetText("Temporary grant route",true);browser.choose:Click()
		local routeBrowser=main.popups[1].controls;assert.equal("Show on tree",routeBrowser.choose.label);routeBrowser.choose:Click()
		assert.equal(originalId,controls.canvas.focus);assert.equal(atlas.tree(alternate.version).nodes[originalId].x,controls.canvas.centerX)
		assert.matches("Route step 1",controls.help.label);assert.is_nil(next(controls.canvas.preview));assert.is_false(controls.grantPrevious:IsEnabled());assert.is_true(controls.grantNext:IsEnabled())
		controls.grantNext:Click();assert.equal(atlas.report(alternate).grantRoute[2].id,controls.canvas.focus);assert.matches("Route step 2",controls.help.label)
		controls.grantPrevious:Click();assert.equal(originalId,controls.canvas.focus);assert.same(alternate.nodes,controls.canvas.selected().nodes)
		controls.grantExit:Click();assert.is_false(controls.grantNext:IsShown());assert.is_true(controls.undo:IsShown())
		controls.stats:Click();browser=main.popups[1].controls;browser.search:SetText("Temporary grant route",true);browser.choose:Click();main.popups[1].controls.choose:Click()
		controls.budget:SetText(tostring(needed+1),true);assert.is_false(controls.grantNext:IsShown());main.popups={}
		alternate.avoided={17321}
		local reachable,reason,required=atlas.budgetReachability(alternate)
		assert.is_false(reachable);assert.is_true(required>needed);assert.matches("avoided",reason)
		assert.is_false(pcall(atlas.connect,plan("3.29.3",needed),{target},{17321}))
		assert.is_false(pcall(atlas.connectOptimized,plan("3.29.3",needed),{target},{17321}))
		local checked=atlas.report(alternate);assert.is_false(checked.budgetReachable);assert.equal(required,checked.pointsBeforeGrant)
		alternate.budget=required;assert.is_true(atlas.budgetReachability(alternate))
	end)
	it("uses gateway graph links without allocating decorative mastery nodes", function()
		local tree=atlas.tree("3.29.1")
		local result=atlas.connect(plan("3.29.1"),{13842,17000})
		local nodes={}; for _,id in ipairs(result.nodes) do nodes[id]=true end
		assert.is_true(nodes[13842] and nodes[17000]); assert.are.equal(2,atlas.report(result).counts.gateway)
		local avoided=atlas.connect(plan("3.29.1"),{17000},{13842})
		for _,id in ipairs(avoided.nodes) do assert.are_not.equals(13842,id) end
		assert.is_true(#tree.nodes[13842].links > 0)
	end)
	it("round trips versioned JSON and strict official version-six links", function()
		local result=atlas.connect(plan(),{65225})
		local decoded=atlas.import(atlas.export(result))
		assert.is_true(tableDeepEquals(result,decoded))
		decoded=atlas.import(atlas.url(result),result.version,result.id,result.title,result.budget)
		assert.is_true(tableDeepEquals(result.nodes,decoded.nodes))
		assert.are.equal(false,pcall(atlas.import,"https://example.com/tree",result.version))
		assert.are.equal(false,pcall(atlas.import,atlas.url(result):sub(1,-7),result.version))
		assert.are.equal(#result.nodes,#atlas.import(" \n"..atlas.url(result).."\r\n",result.version).nodes)
		-- A known empty v6 Atlas payload: version, Standard mode, one start ID, two empty sections.
		local payload=string.char(0,0,0,6,0,0,1,113,117,0,0)
		local url="https://www.pathofexile.com/fullscreen-atlas-skill-tree/"..common.base64.encode(payload):gsub("+","-"):gsub("/","_")
		assert.are.equal(0,#atlas.import(url,"3.27.0").nodes)
		-- Captured from the current official league tree after one allocation.
		local league="https://www.pathofexile.com/atlas-skill-tree/league/AAAABgAAAR_EAAA="
		assert.same({8132},atlas.import(league,"3.30.0-preview").nodes)
		assert.has_error(function() atlas.import(league,"3.30.0-preview-ruthless") end)
		assert.has_error(function() atlas.import(league,"3.29.3") end)
	end)
	it("round trips effect choices in official links captured from the site", function()
		-- cspell:ignore RcgCy fHs sfvXT
		local url="https://www.pathofexile.com/fullscreen-atlas-skill-tree/AAAABgAAEQLICZ0ciy67MiQzgzufaiR1J30djKORfbH7t_fHs9dN_dQAAkXIAsjRxP3U"
		local result=atlas.import(url,"3.30.0-preview")
		assert.same({{node=712,effect=17864},{node=64980,effect=53700}},result.choices)
		assert.equal(url,atlas.url(result))
		local ruthless=url:gsub("/fullscreen%-atlas%-skill%-tree/","/fullscreen-atlas-skill-tree/ruthless/")
		local other=atlas.import(ruthless,"3.30.0-preview-ruthless");assert.same(result.choices,other.choices);assert.equal(ruthless,atlas.url(other))
		local first=atlas.import("https://www.pathofexile.com/fullscreen-atlas-skill-tree/AAAABgAACQLICZ0uuzODaiR9HZF9sfvXTQABRcgCyA==","3.30.0-preview")
		assert.same({{node=712,effect=17864}},first.choices)
		local invalid=copyTable(first);invalid.choices[1].effect=65535;assert.has_error(function() atlas.url(invalid) end)
		invalid=copyTable(first);invalid.choices[2]=copyTable(invalid.choices[1]);assert.has_error(function() atlas.url(invalid) end)
		assert.has_error(function() atlas.import(url:sub(1,-5),"3.30.0-preview") end)
	end)
	it("preserves unknown schemas and malformed XML metadata unchanged", function()
		local store=atlas.new(build); local raw='{"schemaVersion":99,"plans":[]}'
		store:Load({raw}); assert.is_truthy(store.warning)
		local xml={}; store:Save(xml); assert.are.equal(raw,xml[1])
		assert.are.equal(false,pcall(store.Upsert,store,plan()))
		store=atlas.new(build); store:Load({{elem="Unknown",attrib={},"opaque"}})
		xml={}; store:Save(xml); assert.are.equal("Unknown",xml[1].elem)
		store=atlas.new(build); raw='{"schemaVersion":1,"plans":[{"id":"x","title":"x","version":"3.27.0","budget":132,"nodes":{"unexpected":true}}]}'
		store:Load({raw}); assert.is_truthy(store.warning); xml={};store:Save(xml);assert.are.equal(raw,xml[1])
	end)
	it("persists native plans through candidate XML without changing character stats or live state", function()
		local entry=atlas.connect(plan(),{65225}); local revision=bridge.revision(build)
		local prepared=bridge.prepare(build,{mode="edit",title=entry.title,baseRevision=revision,operations={{type="set_atlas_plan",plan=entry}}})
		assert.are.equal(0,#build.savers.AtlasPlans.plans)
		assert.are.equal(1,#prepared.candidate.savers.AtlasPlans.plans)
		assert.are.equal(prepared.before.LifeUnreserved,prepared.after.LifeUnreserved)
		assert.are.equal(prepared.before.CombinedDPS,prepared.after.CombinedDPS)
		assert.are.equal(revision,bridge.revision(build))
		assert.is_truthy(table.concat(prepared.changes," "):find("Unwavering Vision",1,true))
		local store=build.savers.AtlasPlans
		for i=1,8 do local p=plan(); p.id="atlas-"..i; store:Upsert(p) end
		local p=plan();p.id="ninth";store:Upsert(p);store:Remove("atlas-1");assert.are.equal(8,#store.plans)
	end)
	it("exercises native canvas, search, allocation, undo and plan retention callbacks", function()
		local panel=require("Classes.AtlasPlannerControl")
		local controls=panel.Open(build,plan())
		controls.canvas:Draw()
		local mouseOver=controls.canvas.IsMouseOver
		controls.canvas.IsMouseOver=function() return true end
		local scale=controls.canvas.scale
		main.popups[1]:ProcessControlsInput({{type="KeyUp",key="WHEELUP"}},{x=-10000,y=-10000,width=20000,height=20000})
		controls.canvas.IsMouseOver=mouseOver
		assert.is_true(controls.canvas.scale > scale)
		controls.search:SetText("Unwavering Vision");controls.search.changeFunc();controls.find:Click()
		assert.are.equal(65225,controls.canvas.focus)
		controls.allocate:Click(); assert.is_true(controls.status.label:find("20 granted",1,true) ~= nil)
		controls.undo:Click(); assert.is_truthy(controls.status.label:find("0 /",1,true))
		controls.allocate:Click(); controls.keep:Click()
		assert.are.equal(1,#build.savers.AtlasPlans.plans)
		assert.is_true(#build.savers.AtlasPlans.plans[1].nodes > 0)
		panel.Library(build); main.popups[1].controls.open:Click()
		assert.is_truthy(main.popups[1].controls.canvas)
		controls=main.popups[1].controls
		local imported=plan("3.29.1"); imported.notes="Imported strategy notes"
		imported.avoided={atlas.tree(imported.version).nodes[atlas.tree(imported.version).start].links[1]}
		local environment=getfenv(panel.Open); local paste=environment.Paste
		environment.Paste=function() return atlas.export(imported) end
		controls.page:SelByValue("Notes & sharing");assert.is_false(controls.targets.shown());controls.import:Click(); environment.Paste=paste
		assert.are.equal(imported.notes,controls.notes.buf)
		assert.are.equal("3.29.1",controls.canvas.tree.version)
		assert.same(imported.avoided,controls.canvas.avoided())
		local copied;local copy=environment.Copy;environment.Copy=function(text) copied=text end;controls.copy:Click();environment.Copy=copy
		assert.same(imported.avoided,atlas.import(copied).avoided)
		controls.page:SelByValue("Tree");assert.is_true(controls.targets.shown());controls.undo:Click(); controls.canvas:Draw()
		assert.same({},controls.canvas.avoided())
		controls.redo:Click();assert.are.equal("3.29.1",controls.canvas.tree.version);assert.same(imported.avoided,controls.canvas.avoided())
		controls.undo:Click();assert.are.equal("3.27.0",controls.canvas.tree.version);assert.same({},controls.canvas.avoided())
		assert.are.equal("3.27.0",controls.canvas.tree.version)
		assert.are.equal("Map sustain first",controls.notes.buf)
	end)
end)
