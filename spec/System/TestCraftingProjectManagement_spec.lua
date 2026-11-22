describe("Crafting project removal and save-state ownership",function()
	local projects=require("Modules.CraftingProjects")
	local sim=require("Modules.CraftingSimulator")
	local uiState=require("Modules.PlanningUI")
	local tasks=require("Modules.CraftingTasks")
	local bridge=require("Modules.DesktopBuildBridge")
	local activeMode,activeCache
	local function project(id)
		return {id=id,title="Guide "..id,slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={},priceBook={currency="chaos",source="Manual",quotedAt=1700000000,values={}}}
	end
	before_each(function() newBuild();activeMode=build;activeCache=GlobalCache;main.popups={};bridge.prepared=nil end)
	after_each(function()
		tasks.cancel();main.popups={};main.modes.BUILD=activeMode;GlobalCache=activeCache
		bridge.prepared=nil;bridge.owner=nil;bridge.build=nil;bridge.previous=nil;bridge.undo={};bridge.history={};bridge.enabled=false
	end)
	it("rejects stale recipe starting states in AI project edits without changing the build",function()
		local original=project("state-change");local initial=sim.model(original.startingItem).initial
		original.nativeRecipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1},initialState=initial}
		original.recipeAlternatives={{name="Alternative",recipe=copyTable(original.nativeRecipe)}}
		build.savers.CraftingProjects:Upsert(original)
		local changed=copyTable(original);changed.startingItem=original.startingItem.."\nQuality: 10"
		local function prepare(value) return bridge.prepare(build,{mode="edit",title="Change item",baseRevision=bridge.revision(build),operations={{type="set_crafting_project",project=value}}}) end
		local ok,err=pcall(prepare,changed);assert.is_false(ok);assert.matches("starting state incompatible",err,1,true)
		assert.equal(original.startingItem,build.savers.CraftingProjects.projects[1].startingItem)
		changed.nativeRecipe.initialState=nil;changed.recipeAlternatives=nil
		ok,err=pcall(prepare,changed);assert.is_false(ok);assert.matches("Alternative",err,1,true)
		changed.recipeAlternatives={};local prepared=prepare(changed)
		assert.equal(changed.startingItem,prepared.candidate.savers.CraftingProjects.projects[1].startingItem)
		changed.nativeRecipe.initialState=sim.model(changed.startingItem).initial;prepared=prepare(changed)
		assert.is_truthy(prepared.candidate.savers.CraftingProjects.projects[1].nativeRecipe.initialState)
	end)
	it("does not silently reuse a legacy unbound recipe state for another item",function()
		local original=project("unbound");local state=sim.model(original.startingItem).initial;state.origin=nil
		original.nativeRecipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1},initialState=state}
		build.savers.CraftingProjects:Upsert(original);local changed=copyTable(original);changed.startingItem=original.startingItem.."\nQuality: 10"
		local ok,err=pcall(build.savers.CraftingProjects.Upsert,build.savers.CraftingProjects,changed)
		assert.is_false(ok);assert.matches("unbound starting state",err,1,true);assert.equal(original.startingItem,build.savers.CraftingProjects.projects[1].startingItem)
		original.title="Renamed";build.savers.CraftingProjects:Upsert(original);assert.equal("Renamed",build.savers.CraftingProjects.projects[1].title)
	end)
	it("checks new AI recipe states while preserving unchanged legacy states",function()
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local state=sim.model(raw).initial
		local proposed=project("new-state");proposed.startingItem=raw.."\nQuality: 10"
		proposed.nativeRecipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1},initialState=state}
		local function prepare(entry) return bridge.prepare(build,{mode="edit",title="Edit craft",baseRevision=bridge.revision(build),operations={{type="set_crafting_project",project=entry}}}) end
		local ok,err=pcall(prepare,proposed);assert.is_false(ok);assert.matches("invalid starting state",err,1,true);assert.equal(0,#build.savers.CraftingProjects.projects)
		local valid=copyTable(proposed);valid.nativeRecipe.initialState=sim.model(valid.startingItem).initial
		local result=prepare(valid);assert.equal("new-state",result.candidate.savers.CraftingProjects.projects[1].id)
		-- Older saves may contain states that cannot be simulated; a title edit
		-- must preserve them without presenting them as newly validated.
		build.savers.CraftingProjects:Upsert(proposed);local renamed=copyTable(proposed);renamed.title="Renamed"
		result=prepare(renamed);assert.equal("Renamed",result.candidate.savers.CraftingProjects.projects[1].title)
		local modified=copyTable(renamed);modified.nativeRecipe.steps[1].method="transmute"
		ok,err=pcall(prepare,modified);assert.is_false(ok);assert.matches("invalid starting state",err,1,true)
		modified.nativeRecipe.initialState=sim.model(modified.startingItem).initial
		result=prepare(modified);assert.equal("transmute",result.candidate.savers.CraftingProjects.projects[1].nativeRecipe.steps[1].method)
		local changed=copyTable(renamed);changed.recipeAlternatives={{name="New alternative",recipe=copyTable(changed.nativeRecipe)}}
		ok,err=pcall(prepare,changed);assert.is_false(ok);assert.matches("New alternative",err,1,true)
		changed.recipeAlternatives[1].recipe.initialState=sim.model(changed.startingItem).initial
		result=prepare(changed);assert.is_truthy(result.candidate.savers.CraftingProjects.projects[1].recipeAlternatives[1])
		assert.equal(proposed.title,build.savers.CraftingProjects.projects[1].title)
	end)
	it("does not discard an unkept craft when an AI edit changes its base",function()
		local original=project("base-draft");build.savers.CraftingProjects:Upsert(original)
		local workspace=require("Modules.PlanningWorkspace").new(build);build.planningWorkspace=workspace
		local state=sim.model(original.startingItem).initial;state.quality=10
		local draft=require("Modules.CraftingInventory").run(state);draft.kind="workbench";draft.project=original
		workspace.craftDrafts[original.id]=draft;uiState.draft(build,"workingCraft",original.id)
		local changed=copyTable(original);changed.startingItem="Rarity: NORMAL\nLeather Cap\nItem Level: 86"
		local prepared=bridge.prepare(build,{mode="edit",title="Change base",baseRevision=bridge.revision(build),operations={{type="set_crafting_project",project=changed}}})
		local ok,err=pcall(bridge.apply,prepared);assert.is_false(ok);assert.matches("unkept working draft",err,1,true)
		assert.equal(build,main.modes.BUILD);assert.equal(10,workspace:CraftingDraft(original.id).state.quality);assert.is_true(uiState.hasDraft(build,"workingCraft",original.id))
		uiState.discard(build,"workingCraft",original.id);uiState.draft(build,"uniqueQuality",original.id)
		ok,err=pcall(bridge.apply,prepared);assert.is_false(ok);assert.matches("unkept working draft",err,1,true)
		uiState.discard(build,"uniqueQuality",original.id);local candidate=bridge.apply(prepared)
		assert.equal(changed.startingItem,candidate.savers.CraftingProjects.projects[1].startingItem)
	end)
	it("patches written guide fields while preserving the rest of the project",function()
		local original=project("patch-guide");original.simulatorExport=string.rep("x",128000)
		original.nativeRecipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1}}
		local state=sim.model(original.startingItem).initial
		original.run=require("Modules.CraftingInventory").run(state)
		original.inventory={{id="base",title="Saved base",slot="Helmet",baseItem=original.startingItem,at=1,state=state}}
		build.savers.CraftingProjects:Upsert(original)
		local function prepare(patch) return bridge.prepare(build,{mode="edit",title="Update guide",baseRevision=bridge.revision(build),operations={{type="patch_crafting_guide",projectId=original.id,patch=patch}}}) end
		local prepared=prepare({title="New title",steps={{action="Use an essence"}}});local candidate=prepared.candidate.savers.CraftingProjects.projects[1]
		assert.equal("New title",candidate.title);assert.equal("Use an essence",candidate.steps[1].action)
		assert.equal(original.simulatorExport,candidate.simulatorExport);assert.same(build.savers.CraftingProjects.projects[1].nativeRecipe,candidate.nativeRecipe)
		assert.equal(original.title,build.savers.CraftingProjects.projects[1].title)
		assert.is_false(pcall(prepare,{}));assert.is_false(pcall(prepare,{startingItem="other"}))
		local changes=table.concat(prepared.changes,"\n")
		assert.matches("New title",changes,1,true);assert.matches("Use an essence",changes,1,true)
		assert.is_nil(changes:find("checkpoint removed",1,true));assert.is_nil(changes:find("Removed saved item",1,true))
		local applied=bridge.apply(prepared);local xml=applied:SaveDB("Guide patch")
		loadBuildFromXML(xml,"Guide patch");local reopened=main.modes.BUILD.savers.CraftingProjects.projects[1]
		assert.equal("New title",reopened.title);assert.equal("Use an essence",reopened.steps[1].action)
		assert.equal(original.simulatorExport,reopened.simulatorExport);assert.is_truthy(reopened.run);assert.equal(1,#reopened.inventory)
		assert.equal("alchemy",reopened.nativeRecipe.steps[1].method)
	end)
	it("carries an unfinished Atlas draft across an unrelated AI edit",function()
		local plan={id="farm",title="Saved farm",version="3.30.0c",budget=100,nodes={}}
		build.savers.AtlasPlans:Upsert(plan);local workspace=require("Modules.PlanningWorkspace").new(build);build.planningWorkspace=workspace
		workspace:Show("atlas",plan);workspace.controls.title:SetText("Unkept farm",true)
		local prepared=bridge.prepare(build,{mode="edit",title="Change level",baseRevision=bridge.revision(build),operations={{type="set_character",level=5}}})
		local candidate=bridge.apply(prepared);assert.is_true(uiState.hasDraft(candidate,"atlas",plan.id))
		candidate=bridge.apply(bridge.prepare(candidate,{mode="edit",title="Another edit",baseRevision=bridge.revision(candidate),operations={{type="set_character",level=6}}}))
		assert.is_true(uiState.hasDraft(candidate,"atlas",plan.id))
		local reopened=require("Modules.PlanningWorkspace").new(candidate);reopened:Show("atlas",candidate.savers.AtlasPlans.plans[1])
		assert.equal("Unkept farm",reopened.controls.title.buf);assert.equal("Saved farm",candidate.savers.AtlasPlans.plans[1].title)
	end)
	it("carries a deferred crafting draft across consecutive AI edits",function()
		local p=project("deferred");build.savers.CraftingProjects:Upsert(p)
		local workspace=require("Modules.PlanningWorkspace").new(build);build.planningWorkspace=workspace
		local state=sim.model(p.startingItem).initial;state.quality=10;local draft=require("Modules.CraftingInventory").run(state);draft.kind="workbench";draft.project=p
		workspace.craftDrafts[p.id]=draft;uiState.draft(build,"workingCraft",p.id)
		local function edit(base,level) return bridge.apply(bridge.prepare(base,{mode="edit",title="Change level",baseRevision=bridge.revision(base),operations={{type="set_character",level=level}}})) end
		local first=edit(build,5);local second=edit(first,6)
		assert.equal(10,second.planningCraftDrafts[p.id].state.quality);assert.is_true(uiState.hasDraft(second,"workingCraft",p.id))
	end)
	it("carries a deferred unique preview across consecutive AI edits",function()
		local p=project("deferred-unique");p.startingItem="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86";build.savers.CraftingProjects:Upsert(p)
		local workspace=require("Modules.PlanningWorkspace").new(build);build.planningWorkspace=workspace
		local result=require("Modules.CraftingUniqueQuality").apply(p.startingItem)
		build.planningUniqueQualityDrafts={[p.id]={kind="uniqueQuality",project=p,itemText=result.itemText,history={p.startingItem}}};uiState.draft(build,"uniqueQuality",p.id)
		local function edit(base,level) return bridge.apply(bridge.prepare(base,{mode="edit",title="Change level",baseRevision=bridge.revision(base),operations={{type="set_character",level=level}}})) end
		local first=edit(build,5);local second=edit(first,6)
		assert.equal(result.itemText,second.planningUniqueQualityDrafts[p.id].itemText);assert.is_true(uiState.hasDraft(second,"uniqueQuality",p.id))
	end)
	it("keeps a conflicting Atlas draft separately from an AI-edited plan",function()
		local plan={id="farm",title="Saved farm",version="3.30.0c",budget=100,nodes={}}
		build.savers.AtlasPlans:Upsert(plan);local workspace=require("Modules.PlanningWorkspace").new(build);build.planningWorkspace=workspace
		workspace:Show("atlas",plan);workspace.controls.title:SetText("Unkept farm",true)
		local changed=copyTable(plan);changed.title="AI farm"
		local prepared=bridge.prepare(build,{mode="edit",title="Revise Atlas",baseRevision=bridge.revision(build),operations={{type="set_atlas_plan",plan=changed}}})
		local candidate=bridge.apply(prepared);local reopened=require("Modules.PlanningWorkspace").new(candidate);local id,entry=next(reopened.atlasDrafts)
		assert.is_truthy(id);assert.is_not.equal(plan.id,id);assert.is_true(entry.conflict);assert.is_true(uiState.hasDraft(candidate,"atlas",id))
		reopened:Show("atlas",candidate.savers.AtlasPlans.plans[1]);assert.equal("AI farm",reopened.controls.title.buf)
		reopened.controls.library:Click();local library=main.popups[1].controls;library.plans:SelByValue(id,"val");assert.matches("saved plan changed",library.plans:GetSelValue().label,1,true);library.open:Click()
		assert.equal("Unkept farm",reopened.controls.title.buf);assert.equal("AI farm",candidate.savers.AtlasPlans.plans[1].title)
	end)
	it("reviews removed guide, recipes, inventory and checkpoint before applying",function()
		local original=project("review");local model=sim.model(original.startingItem)
		original.goals={"High life"};original.steps={{action="Apply an Orb of Alchemy"},{action="Finish the helmet",done=true}}
		original.nativeRecipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1}}
		original.recipeAlternatives={{name="Alternative",recipe=copyTable(original.nativeRecipe),trackPickups=true}}
		original.primarySimulation={trials=20,maxActions=3,seed=7};original.run=require("Modules.CraftingInventory").run(model.initial)
		original.inventory={{id="saved",title="Saved base",slot="Helmet",baseItem=original.startingItem,at=1,state=model.initial}}
		build.savers.CraftingProjects:Upsert(original)
		local changed=copyTable(original);changed.startingItem="Rarity: NORMAL\nLeather Cap\nItem Level: 86";changed.goals={};changed.steps={};changed.nativeRecipe=nil;changed.recipeAlternatives={};changed.inventory={};changed.run=nil;changed.priceBook=nil;changed.primarySimulation=false
		local prepared=bridge.prepare(build,{mode="edit",title="Revise guide",baseRevision=bridge.revision(build),operations={{type="set_crafting_project",project=changed}}})
		local text=table.concat(prepared.changes,"\n")
		for _,expected in ipairs({"Removed goal 1: High life","Removed guide step 1: [todo] Apply an Orb of Alchemy","Removed guide step 2: [done] Finish the helmet","Primary recipe removed","Alternative recipe 'Alternative' removed","Removed saved item: Saved base [saved]","Working craft checkpoint removed","Resource price book removed","Primary simulation defaults:"}) do assert.is_truthy(text:find(expected,1,true),expected) end
		assert.equal(2,#build.savers.CraftingProjects.projects[1].steps);assert.equal(1,#build.savers.CraftingProjects.projects[1].inventory)
	end)
	it("reviews recipe actions and resource quote edits",function()
		local original=project("details");original.nativeRecipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1}}
		original.recipeAlternatives={{name="First",recipe=copyTable(original.nativeRecipe),trackPickups=true},{name="Second",recipe=copyTable(original.nativeRecipe)}};original.priceBook.values.chaos=2
		original=projects.validate(original);local changed=copyTable(original);changed.nativeRecipe.steps[1].method="chaos";changed.recipeAlternatives[1].trackPickups=false;changed.priceBook.values.chaos=3
		changed.recipeAlternatives[1],changed.recipeAlternatives[2]=changed.recipeAlternatives[2],changed.recipeAlternatives[1]
		local text=table.concat(projects.reviewChanges(original,changed),"\n")
		for _,expected in ipairs({"Primary recipe changed","Changed Primary recipe step 1:","Alternative pickup tracking for First: true -> false","Reordered alternative recipes: First, Second -> Second, First","Price chaos: 2 -> 3"}) do assert.is_truthy(text:find(expected,1,true),expected) end
	end)
	it("identifies changed checkpoint fields and added saved item state",function()
		local original=project("checkpoint-review");local model=sim.model(original.startingItem);original.run=require("Modules.CraftingInventory").run(model.initial)
		local changed=copyTable(original);changed.run.state.quality=1;changed.run.seed="7"
		changed.inventory={{id="saved",title="Base",slot="Helmet",baseItem=original.startingItem,at=1,state=copyTable(model.initial)}}
		local text=table.concat(projects.reviewChanges(original,changed),"\n")
		for _,expected in ipairs({"Added saved item: Base [saved]","Saved item saved base:","Saved item saved state:","Working craft checkpoint changed.","Working craft fields changed:","Working craft state:"}) do assert.is_truthy(text:find(expected,1,true),expected) end
	end)
	it("shows changes to supplied simulation notes",function()
		local original=project("simulation-notes")
		original.simulation={trials=100,successes=5,patch="3.30",observedAt=1,notes="Old assumptions"}
		local changed=copyTable(original);changed.simulation.notes="New assumptions"
		local review=table.concat(projects.reviewChanges(original,changed),"\n")
		assert.is_truthy(review:find("Supplied simulation notes: Old assumptions -> New assumptions",1,true))
		changed.simulation=nil
		review=table.concat(projects.reviewChanges(original,changed),"\n")
		assert.is_truthy(review:find("Supplied simulation notes: Old assumptions -> (not saved)",1,true))
	end)
	it("does not report automatically preserved project data as removed",function()
		local original=project("preserved");local model=sim.model(original.startingItem)
		original.nativeRecipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1}};original.recipeAlternatives={{name="Alternative",recipe=copyTable(original.nativeRecipe)}}
		original.primarySimulation={trials=20,maxActions=3,seed=7};original.run=require("Modules.CraftingInventory").run(model.initial)
		original.inventory={{id="saved",title="Saved base",slot="Helmet",baseItem=original.startingItem,at=1,state=model.initial}}
		build.savers.CraftingProjects:Upsert(original)
		local changed=copyTable(original);changed.title="Renamed guide";changed.recipeAlternatives=nil;changed.primarySimulation=nil;changed.inventory=nil;changed.run=nil
		local prepared=bridge.prepare(build,{mode="edit",title="Rename guide",baseRevision=bridge.revision(build),operations={{type="set_crafting_project",project=changed}}})
		local text=table.concat(prepared.changes,"\n");assert.is_nil(text:find("Alternative recipe 'Alternative' removed",1,true));assert.is_nil(text:find("Removed saved item",1,true));assert.is_nil(text:find("checkpoint removed",1,true));assert.is_nil(text:find("Primary simulation defaults:",1,true))
	end)
	it("previews unique project items and explains unsupported starting items",function()
		local unique="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\n+40% to Fire Resistance"
		local store=build.savers.CraftingProjects;local p=project("unique-target");p.targetItem=unique;store:Upsert(p)
		local layout={width=1100,height=650,mount=function() end,openWorkbench=function() end}
		local panel=require("Classes.CraftingProjectControl")
		local c=panel.Open(build,nil,nil,layout,p.id)
		assert.is_truthy(c.projectItem);assert.is_truthy(c.projectItemMods);assert.is_true(c.native:IsEnabled())
		local rows={};for _,row in ipairs(c.projectItemMods.list) do rows[#rows+1]=StripEscapes(row[1] or "") end
		assert.is_truthy(table.concat(rows," "):find("Fire Resistance",1,true))
		local starting=project("unique-start");starting.startingItem=unique;store:Upsert(starting)
		c=panel.Open(build,nil,nil,layout,starting.id);assert.is_truthy(c.projectItem);assert.is_true(c.native:IsEnabled())
		assert.matches("unique item",c.native.tooltipText())
		rows={};for _,row in ipairs(c.summary.list) do rows[#rows+1]=StripEscapes(row[1] or "") end
		assert.is_truthy(table.concat(rows," "):find("written guides",1,true))
		c=panel.Open(build,nil,nil,nil,starting.id);assert.is_true(c.native:IsEnabled());assert.matches("unique item",c.native.tooltipText())
		main.popups={};local xml=build:SaveDB("Unique guides");loadBuildFromXML(xml,"Unique guides")
		local saved=build.savers.CraftingProjects.projects;assert.equal(unique,saved[2].startingItem);assert.equal(unique,saved[1].targetItem)
		c=panel.Open(build,nil,nil,nil,starting.id);assert.is_true(c.native:IsEnabled());assert.matches("unique item",c.native.tooltipText())
	end)
	it("explains a missing corruption marker before opening a unique workbench",function()
		local p=project("corruption-marker");p.title="Skin";p.slot="Body Armour";p.startingItem="Rarity: UNIQUE\nSkin of the Lords\nSimple Robe\nItem Level: 86\nSockets: R-G-B-R-G-B"
		build.savers.CraftingProjects:Upsert(p);local panel=require("Classes.CraftingProjectControl")
		local c=panel.Open(build,nil,nil,nil,p.id);assert.is_false(c.native:IsEnabled());assert.matches("always corrupted",c.native.tooltipText(),1,true)
		local details="";for _,row in ipairs(c.details.list) do details=details..(row[1] or "") end;assert.matches("include its Corrupted line",details,1,true)
		main.popups={};p.startingItem=p.startingItem.."\nCorrupted";build.savers.CraftingProjects:Upsert(p);c=panel.Open(build,nil,nil,nil,p.id)
		assert.is_true(c.native:IsEnabled());assert.matches("unique item",c.native.tooltipText());main.popups={}
	end)
	it("explains why mirrored and unidentified uniques cannot open the workbench",function()
		local p=project("unique-reasons");p.title="Goldrim";p.startingItem="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R G B\nMirrored"
		build.savers.CraftingProjects:Upsert(p);local panel=require("Classes.CraftingProjectControl");local c=panel.Open(build,nil,nil,nil,p.id)
		assert.is_false(c.native:IsEnabled());assert.matches("Mirrored items cannot be crafted",c.native.tooltipText(),1,true);assert.is_nil(c.native.tooltipText():find(".lua:",1,true))
		main.popups={};p.startingItem=p.startingItem:gsub("Mirrored","Unidentified");build.savers.CraftingProjects:Upsert(p);c=panel.Open(build,nil,nil,nil,p.id)
		assert.is_false(c.native:IsEnabled());assert.matches("Identify the starting item",c.native.tooltipText(),1,true);main.popups={}
	end)
	it("resets draft and saved labels across reused builds and keeps project draft scopes separate",function()
		uiState.draft(build,"workingCraft","a");uiState.draft(build,"workingCraft","b");uiState.kept(build,"workingCraft","a")
		assert.is_false(uiState.hasDraft(build,"workingCraft","a"));assert.is_true(uiState.hasDraft(build,"workingCraft","b"))
		assert.is_truthy(uiState.saveStatus(build):find("Working draft",1,true));newBuild()
		assert.are.equal("No pending build changes",uiState.saveStatus(build))
		uiState.saved(build);newBuild();assert.are.equal("No pending build changes",uiState.saveStatus(build))
		uiState.kept(build,"crafting");newBuild();build.modFlag=true
		assert.are.equal("Build changes | Save needed",uiState.saveStatus(build))
	end)
	it("restores the exact project, order, inventory, checkpoint and empty dictionary quotes",function()
		local store=build.savers.CraftingProjects
		for _,id in ipairs({"a","b","c"}) do
			local p=project(id);local state=sim.model(p.startingItem).initial
			p.run=require("Modules.CraftingInventory").run(state);p.inventory={require("Modules.CraftingInventory").capture(p,state,"Saved base")};store:Upsert(p)
		end
		local before=projects.copy(store.projects);store:Remove("b")
		assert.are.equal(2,#store.projects);assert.are.equal("c",store.projects[2].id)
		store:UndoRemove();assert.are.same(before,store.projects)
		assert.is_truthy(require("dkjson").encode(store.projects[2]):find('"values":{}',1,true));assert.is_nil(store.lastRemoved)
		local xml=build:SaveDB("Restored guides");loadBuildFromXML(xml,"Restored guides");assert.are.same(before,build.savers.CraftingProjects.projects)
	end)
	it("refuses unknown, unreadable or conflicting restoration without losing history",function()
		local store=build.savers.CraftingProjects;store:Upsert(project("a"));store:Remove("a")
		assert.is_false(pcall(store.Remove,store,"missing"));assert.are.equal("a",store.lastRemoved.project.id)
		local replacement=project("a");replacement.title="Replacement";store:Upsert(replacement)
		assert.is_false(pcall(store.UndoRemove,store));assert.are.equal("Replacement",store.projects[1].title);assert.is_truthy(store.lastRemoved)
		store.unreadable="preserved";assert.is_false(pcall(store.Remove,store,"a"));assert.are.equal(1,#store.projects);store.unreadable=nil
	end)
	it("removes only the selected project's draft, analysis and job and restores its working state",function()
		local store=build.savers.CraftingProjects;local a,b=project("a"),project("b");store:Upsert(a);store:Upsert(b)
		local ui=require("Modules.HeadlessUI").install({width=1024,height=768})
		local ok,message=pcall(function()
			ui:bind(build);build.viewMode="CONFIG";ui:click("aiBuild")
			local workspace=build.planningWorkspace;workspace:Show("crafting",{kind="workbench",project=a});ui:frame();ui:click("currency_alchemy");ui:click("item")
			local aDraft=workspace:CraftingDraft("a");assert.is_true(uiState.hasDraft(build,"workingCraft","a"))
			workspace.craftDrafts.b={kind="workbench",project=b};uiState.draft(build,"workingCraft","b")
			local other=require("Modules.CraftingAnalysis").get(build,b)
			local own=require("Modules.CraftingAnalysis").get(build,a);own:start("odds",nil,function() coroutine.yield() end)
			store:Remove("a");assert.is_nil(tasks.job);assert.is_nil(workspace.craftDrafts.a);assert.is_nil(workspace.cache.crafting)
			assert.are.equal(other,build.craftingAnalyses.b);assert.is_truthy(workspace.craftDrafts.b);assert.is_true(uiState.hasDraft(build,"workingCraft","b"))
			assert.is_false(uiState.hasDraft(build,"workingCraft","a"));store:UndoRemove()
			assert.are.same(aDraft.state,workspace.craftDrafts.a.state);assert.is_true(uiState.hasDraft(build,"workingCraft","a"))
		end)
		ui:restore();assert(ok,message)
	end)
	it("keeps native remove and undo reachable, including the empty project list",function()
		local store=build.savers.CraftingProjects;store:Upsert(project("a"));local c=require("Classes.CraftingProjectControl").Open(build)
		c.remove:Click();c=main.popups[1].controls;assert.are.equal(0,#store.projects);assert.is_false(c.remove:IsEnabled());assert.is_true(c.undoRemove:IsEnabled())
		c.undoRemove:Click();c=main.popups[1].controls;assert.are.equal("a",store.projects[c.projects:GetSelValueByKey("val")].id);assert.is_false(c.undoRemove:IsEnabled())
	end)
	it("reviews removal explicitly and preserves unrelated working drafts through apply and build undo",function()
		local store=build.savers.CraftingProjects;local a,b=project("a"),project("b");store:Upsert(a);store:Upsert(b)
		local journey=require("Modules.BuildJourney").empty();journey.wishlist={{id="gear-a",title="Gear a",slot="Helmet",route="craft",status="planned",projectId="a"}};build.savers.BuildJourney:Replace(journey)
		assert.are.equal(1,#store:References("a"))
		local workspace=require("Modules.PlanningWorkspace").new(build);build.planningWorkspace=workspace
		workspace.craftDrafts.b={kind="workbench",project=b,state=sim.model(b.startingItem).initial};uiState.draft(build,"workingCraft","b")
		local base=build;local revision=bridge.revision(base)
		local prepared=bridge.prepare(base,{mode="edit",title="Remove guide",baseRevision=revision,operations={{type="remove_crafting_project",projectId="a"}}})
		assert.are.equal(2,#store.projects);assert.are.equal(revision,bridge.revision(base))
		assert.is_truthy(table.concat(prepared.changes," "):find("Removed crafting project: Guide a",1,true))
		assert.is_truthy(table.concat(prepared.changes," "):find("1 linked gear goal remains",1,true))
		local applied=bridge.apply(prepared);assert.are.equal(1,#applied.savers.CraftingProjects.projects)
		assert.is_truthy(applied.planningCraftDrafts.b);assert.is_true(uiState.hasDraft(applied,"workingCraft","b"))
		assert.is_truthy(workspace.craftDrafts.b);assert.are.equal(base,bridge.restore())
		assert.are.equal(2,#base.savers.CraftingProjects.projects)
	end)
	it("protects an earlier unkept craft in a batch removal",function()
		local a,b=project("a"),project("b");build.savers.CraftingProjects:Upsert(a);build.savers.CraftingProjects:Upsert(b)
		local workspace=require("Modules.PlanningWorkspace").new(build);build.planningWorkspace=workspace
		local state=sim.model(a.startingItem).initial;state.quality=10;local draft=require("Modules.CraftingInventory").run(state);draft.kind="workbench";draft.project=a
		workspace.craftDrafts.a=draft;uiState.draft(build,"workingCraft","a")
		local prepared=bridge.prepare(build,{mode="edit",title="Remove guides",baseRevision=bridge.revision(build),operations={{type="remove_crafting_project",projectId="a"},{type="remove_crafting_project",projectId="b"}}})
		local ok,err=pcall(bridge.apply,prepared);assert.is_false(ok);assert.matches("batch removal",err,1,true)
		assert.equal(build,main.modes.BUILD);assert.equal(10,workspace:CraftingDraft("a").state.quality);assert.is_true(uiState.hasDraft(build,"workingCraft","a"))
	end)
	it("retains a lazy working draft when its guide is removed and restored",function()
		local p=project("lazy");build.savers.CraftingProjects:Upsert(p)
		local state=sim.model(p.startingItem).initial;state.quality=10;local draft=require("Modules.CraftingInventory").run(state);draft.kind="workbench";draft.project=p
		build.planningCraftDrafts={lazy=draft};uiState.draft(build,"workingCraft","lazy")
		local prepared=bridge.prepare(build,{mode="edit",title="Remove guide",baseRevision=bridge.revision(build),operations={{type="remove_crafting_project",projectId="lazy"}}})
		local candidate=bridge.apply(prepared);assert.equal(10,candidate.savers.CraftingProjects.lastRemoved.draft.state.quality)
		candidate.savers.CraftingProjects:UndoRemove();assert.equal(10,candidate.planningCraftDrafts.lazy.state.quality);assert.is_true(uiState.hasDraft(candidate,"workingCraft","lazy"))
	end)
	it("retains a unique quality session through a reviewed build edit",function()
		local p=project("unique-reviewed");p.startingItem="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86"
		build.savers.CraftingProjects:Upsert(p)
		local workspace=require("Modules.PlanningWorkspace").new(build);build.planningWorkspace=workspace
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,p);control.apply:Click();control.close:Click()
		local base=build;local updated=copyTable(p);updated.title="Updated unique guide"
		local prepared=bridge.prepare(build,{mode="edit",title="Edit unique guide",baseRevision=bridge.revision(build),operations={{type="set_crafting_project",project=updated}}})
		local candidate=bridge.apply(prepared);local draft=candidate.planningUniqueQualityDrafts[p.id]
		assert.is_true(uiState.hasDraft(candidate,"uniqueQuality",p.id))
		assert.equal("Updated unique guide",draft.project.title)
		assert.equal(1,select(2,require("Modules.CraftingUniqueQuality").inspect(draft.itemText)).quality)
		control=require("Classes.CraftingUniqueQualityControl").Open(candidate,candidate.savers.CraftingProjects.projects[1]);assert.matches("1%%",control.status.label)
		assert.are.equal(base,bridge.restore())
	end)
	it("restores a unique quality preview after reviewed project removal",function()
		local p=project("unique-removed");p.startingItem="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86"
		build.savers.CraftingProjects:Upsert(p)
		local workspace=require("Modules.PlanningWorkspace").new(build);build.planningWorkspace=workspace
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,p);control.apply:Click();control.close:Click()
		local base=build
		local prepared=bridge.prepare(base,{mode="edit",title="Remove unique guide",baseRevision=bridge.revision(base),operations={{type="remove_crafting_project",projectId=p.id}}})
		local candidate=bridge.apply(prepared);assert.is_nil(candidate.planningUniqueQualityDrafts[p.id])
		candidate.savers.CraftingProjects:UndoRemove();local draft=candidate.planningUniqueQualityDrafts[p.id]
		assert.is_true(uiState.hasDraft(candidate,"uniqueQuality",p.id));assert.equal(1,select(2,require("Modules.CraftingUniqueQuality").inspect(draft.itemText)).quality)
		control=require("Classes.CraftingUniqueQualityControl").Open(candidate,candidate.savers.CraftingProjects.projects[1]);assert.matches("1%%",control.status.label)
		candidate.savers.CraftingProjects:Remove(p.id);assert.are.equal(base,bridge.restore())
	end)
	it("retains removal undo across an unrelated reviewed edit",function()
		local store=build.savers.CraftingProjects;store:Upsert(project("a"));store:Upsert(project("b"));store:Remove("a")
		local workspace=require("Modules.PlanningWorkspace").new(build);build.planningWorkspace=workspace
		local working=sim.model(project("b").startingItem).initial;working.quality=10
		local draft=require("Modules.CraftingInventory").run(working);draft.kind="workbench";draft.project=project("b")
		workspace.craftDrafts.b=draft;uiState.draft(build,"workingCraft","b")
		local b=project("b");b.title="Updated b"
		local prepared=bridge.prepare(build,{mode="edit",title="Edit another guide",baseRevision=bridge.revision(build),operations={{type="set_crafting_project",project=b}}})
		local candidate=bridge.apply(prepared);local changed=candidate.savers.CraftingProjects
		assert.is_truthy(changed.lastRemoved);changed:UndoRemove()
		assert.are.equal("a",changed.projects[1].id);assert.are.equal("Updated b",changed.projects[2].title)
		assert.are.equal("Updated b",candidate.planningCraftDrafts.b.project.title);assert.are.equal(10,candidate.planningCraftDrafts.b.state.quality)
		changed:Remove("a");bridge.restore()
	end)
	it("marks edited run settings and keeps their values across reopen without false draft flags",function()
		local store=build.savers.CraftingProjects;store:Upsert(project("settings"))
		local values={trials="21",budget="9",price="3",baseCost="4",seed="123",currency="divine"}
		for _,key in ipairs({"trials","budget","price","baseCost","seed","currency"}) do
			local c=require("Classes.CraftingSimulatorControl").Open(build,store.projects[1])
			assert.is_false(uiState.hasDraft(build,"workingCraft","settings"))
			c.page:SelByValue("Simulate recipe");c.page.selFunc()
			assert.is_false(uiState.hasDraft(build,"workingCraft","settings"))
			c[key]:SetText(values[key],true);assert.is_true(uiState.hasDraft(build,"workingCraft","settings"))
			c.keepWorking:Click();assert.is_false(uiState.hasDraft(build,"workingCraft","settings"))
			c.close:Click();c=require("Classes.CraftingSimulatorControl").Open(build,store.projects[1])
			assert.are.equal(values[key],c[key].buf);assert.is_false(uiState.hasDraft(build,"workingCraft","settings"));c.close:Click()
		end
		assert.are.equal("",store.projects[1].run.settings.price);assert.are.equal("",store.projects[1].run.settings.baseCost)
	end)
	it("marks target changes while cancelled target dialogs stay clean",function()
		local c=require("Classes.CraftingSimulatorControl").Open(build,project("targets"))
		c.page:SelByValue("Target conditions");c.page.selFunc()
		c.targetConditions:Click();main.popups[1].controls.close:Click();assert.is_false(uiState.hasDraft(build,"workingCraft","targets"))
		c.addTarget:Click();assert.is_true(uiState.hasDraft(build,"workingCraft","targets"));c.keepWorking:Click()
		c.alternative:Click();assert.is_true(uiState.hasDraft(build,"workingCraft","targets"));c.keepWorking:Click()
		c.clearTargets:Click();assert.is_true(uiState.hasDraft(build,"workingCraft","targets"));c.keepWorking:Click()
		c.targetConditions:Click();local p=main.popups[1].controls;p.minQuality:SetText("10");p.keep:Click()
		assert.is_true(uiState.hasDraft(build,"workingCraft","targets"));c.keepWorking:Click()
		assert.are.equal(10,build.savers.CraftingProjects.projects[1].run.requirements.minQuality)
	end)
	it("keeps saved quote-unit changes clean while retaining other unfinished settings",function()
		local c=require("Classes.CraftingSimulatorControl").Open(build,project("quotes"))
		c.page:SelByValue("Simulate recipe");c.page.selFunc();c.keepWorking:Click()
		c.resourcePrices:Click();local p=main.popups[1].controls;p.currency:SetText("divine");p.keep:Click()
		assert.is_false(uiState.hasDraft(build,"workingCraft","quotes"))
		assert.are.equal("divine",build.savers.CraftingProjects.projects[1].run.settings.currency)
		c.trials:SetText("31",true);c.resourcePrices:Click();p=main.popups[1].controls;p.currency:SetText("chaos");p.keep:Click()
		assert.is_true(uiState.hasDraft(build,"workingCraft","quotes"));c.keepWorking:Click()
		assert.are.equal("31",build.savers.CraftingProjects.projects[1].run.settings.trials)
	end)
	it("marks accepted advanced configurations without marking cancelled forms",function()
		local c=require("Classes.CraftingSimulatorControl").Open(build,project("configuration"))
		c.page:SelByValue("Craft settings");c.page.selFunc()
		c.method:SelByValue("fossil","val");c.method.selFunc();assert.is_true(uiState.hasDraft(build,"workingCraft","configuration"));c.keepWorking:Click()
		c.configure:Click();main.popups[1].controls.close:Click();assert.is_false(uiState.hasDraft(build,"workingCraft","configuration"))
		c.configure:Click();local p=main.popups[1].controls;p.fossil1:SetSel(2);p.use:Click()
		assert.is_true(uiState.hasDraft(build,"workingCraft","configuration"));c.keepWorking:Click()
		assert.are.equal(1,#build.savers.CraftingProjects.projects[1].run.configured.fossil.fossils)
	end)
	it("uses the saved recipe's starting state rather than a manually changed working base",function()
		local p=project("base-state");local state=sim.model(p.startingItem).initial;state.quality=20
		p.run=require("Modules.CraftingInventory").run(state)
		p.nativeRecipe={steps={{method="quality"}},targets={},requirements={minQuality=1}}
		p.priceBook.values["Metadata/Items/Currency/CurrencyArmourQuality"]=2
		local c=require("Classes.CraftingSimulatorControl").Open(build,p);c.page:SelByValue("Simulate recipe");c.page.selFunc()
		c.trials:SetText("2");c.budget:SetText("1");c.runRecipe:Click()
		for i=1,1000 do if not tasks.job then break end;tasks.tick(build) end
		assert.is_nil(tasks.job);local rows={};for _,row in ipairs(c.resultSummary.list) do rows[#rows+1]=row[1] end
		assert.is_truthy(table.concat(rows," "):find("Mean spent: 2.00 chaos",1,true))
	end)
end)
