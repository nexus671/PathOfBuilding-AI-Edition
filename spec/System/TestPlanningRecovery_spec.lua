describe("Local planning draft recovery",function()
	local recovery=require("Modules.PlanningRecovery")
	local filters=require("Modules.LootFilters")
	local directory;local session
	local function entry(title) return {plan={data={schemaVersion=1,activeId="test",profiles={filters.profile("test",title)}},selected="test",page="Overview"}} end
	before_each(function()
		newBuild();directory=os.tmpname();os.remove(directory);assert(require("lfs").mkdir(directory));session=recovery.session;recovery.testDirectory=directory;recovery.cache={}
	end)
	after_each(function() for _,kind in ipairs({"filters","atlas","crafting"}) do recovery.clear(build,kind) end;for _,record in ipairs(recovery.listUnique(build)) do recovery.clear(build,"uniqueQuality",record.entry.plan.project.id) end;os.remove(directory);recovery.testDirectory=nil;recovery.cache={};recovery.session=session;recovery.lastError=nil;main.popups={} end)
	it("discovers earlier drafts incrementally without changing recovery files",function()
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86"
		local p={id="scan-unique",title="Unique",slot="Helmet",startingItem=raw,goals={},steps={}}
		local changed=require("Modules.CraftingUniqueQuality").apply(raw).itemText
		assert.is_true(recovery.save(build,"uniqueQuality",{plan={kind="uniqueQuality",project=p,itemText=changed,history={raw}}},true))
		local record=recovery.load(build,"uniqueQuality",p.id);local file=assert(io.open(record.path,"rb"));local before=file:read("*a");file:close()
		recovery.session="later-session";recovery.cache={}
		local scan=assert(recovery.startScan(build));assert.is_false(recovery.hasPending(build));local steps=0
		while coroutine.status(scan)~="dead" do assert(coroutine.resume(scan));steps=steps+1 end
		assert.is_true(steps>=4);assert.is_true(recovery.hasPending(build))
		file=assert(io.open(record.path,"rb"));assert.equal(before,file:read("*a"));file:close()
		recovery.acknowledge(build,"uniqueQuality",p.id);assert.is_false(recovery.hasPending(build))
	end)
	it("does not re-alert for an acknowledged or already-kept draft",function()
		local value=entry("Kept");build.savers.LootFilters:Replace(value.plan.data);assert.is_true(recovery.save(build,"filters",value,true))
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86";local p={id="scan-ack",title="Unique",slot="Helmet",startingItem=raw,goals={},steps={}}
		local changed=require("Modules.CraftingUniqueQuality").apply(raw).itemText
		assert.is_true(recovery.save(build,"uniqueQuality",{plan={kind="uniqueQuality",project=p,itemText=changed,history={raw}}},true))
		recovery.session="later-session";recovery.cache={};local scan=assert(recovery.startScan(build));recovery.acknowledge(build,"uniqueQuality",p.id)
		while coroutine.status(scan)~="dead" do assert(coroutine.resume(scan)) end
		assert.is_false(recovery.hasPending(build))
	end)
	it("does not leak recovery notices when a build object opens another file",function()
		local oldFile=build.dbFileName;assert.is_true(recovery.save(build,"filters",entry("First file"),true))
		recovery.session="later-session";recovery.cache={};local scan=assert(recovery.startScan(build))
		while coroutine.status(scan)~="dead" do assert(coroutine.resume(scan)) end;assert.is_true(recovery.hasPending(build))
		build.dbFileName="different-file.xml";assert.is_false(recovery.hasPending(build))
		recovery.session="second-earlier-session";assert.is_true(recovery.save(build,"filters",entry("Second file"),true))
		recovery.session="later-session";scan=assert(recovery.startScan(build))
		while coroutine.status(scan)~="dead" do assert(coroutine.resume(scan)) end;assert.is_true(recovery.hasPending(build))
		recovery.clear(build,"filters");build.dbFileName=oldFile;recovery.clear(build,"filters")
	end)
	it("shows the Tools indicator after scanning an earlier draft",function()
		assert.is_true(recovery.save(build,"filters",entry("Interrupted"),true));recovery.session="later-session";recovery.cache={}
		local ui=require("Modules.HeadlessUI").install({width=1024,height=768});local ok,err=pcall(function()
			build.viewMode="PLANNER";build.planningWorkspace=require("Modules.PlanningWorkspace").new(build);ui:bind(build)
			for _=1,8 do ui:frame() end
			assert.equal("Tools *",build.planningWorkspace.nav.controls.nav_tools:GetProperty("label"))
			recovery.acknowledge(build,"filters");assert.equal("Tools",build.planningWorkspace.nav.controls.nav_tools:GetProperty("label"))
		end);ui:restore();assert(ok,err)
	end)
	it("recovers the older complete slot after an interrupted write",function()
		assert.is_true(recovery.save(build,"filters",entry("First"),true));assert.is_true(recovery.save(build,"filters",entry("Second"),true))
		local latest=recovery.load(build,"filters");assert.equal("Second",latest.entry.plan.data.profiles[1].title)
		local file=assert(io.open(latest.path,"wb"));file:write('{"schemaVersion":');file:close()
		assert.equal("First",recovery.load(build,"filters").entry.plan.data.profiles[1].title)
	end)
	it("preserves earlier-session drafts until they are acknowledged",function()
		recovery.save(build,"filters",entry("Interrupted"),true);recovery.session="new-session";recovery.cache={}
		recovery.save(build,"filters",entry("Current saved state"),true)
		assert.equal("Interrupted",recovery.load(build,"filters").entry.plan.data.profiles[1].title);assert.is_true(recovery.hasPending(build))
		recovery.acknowledge(build,"filters");recovery.save(build,"filters",entry("Reviewed"),true)
		assert.equal("Reviewed",recovery.load(build,"filters").entry.plan.data.profiles[1].title);assert.is_false(recovery.hasPending(build))
	end)
	it("rejects invalid payloads and separates draft kinds",function()
		assert.is_false(recovery.save(build,"filters",{plan={data={schemaVersion=99}}},true));assert.is_nil(recovery.load(build,"filters"))
		local atlas=require("Modules.AtlasPlanner");local plan={id="test",title="Test",version="3.30.0-preview",budget=150,nodes={}}
		assert.is_true(recovery.save(build,"atlas",{plan=plan},true));assert.same(atlas.validate(plan),recovery.load(build,"atlas").entry.plan);assert.is_nil(recovery.load(build,"filters"))
	end)
	it("does not flag an identical kept plan but retains unfinished Atlas editor text",function()
		local value=entry("Kept");build.savers.LootFilters:Replace(value.plan.data);assert.is_true(recovery.isCurrent(build,"filters",recovery.clean("filters",value)))
		local plan={id="test",title="Saved Atlas",version="3.30.0-preview",budget=150,nodes={}};build.savers.AtlasPlans:Upsert(plan)
		assert.is_true(recovery.isCurrent(build,"atlas",{plan=require("Modules.AtlasPlanner").validate(plan)}))
		assert.is_false(recovery.isCurrent(build,"atlas",{plan=plan,view={title="",budgetText="-1",notes="Unfinished"}}))
	end)
	it("recovers unfinished Atlas stage inputs without applying them",function()
		local plan={id="test",title="Saved Atlas",version="3.30.0-preview",budget=150,nodes={},notes=""};build.savers.AtlasPlans:Upsert(plan)
		local stage={page="Strategy",stage="starter",previous="",fields={maps="",scarabs="",requirements="",avoid=""},amount="",currency="chaos",source=""}
		local view={title=plan.title,notes="",budgetText="150",search="",centerX=0,centerY=0,scale=0.16,stageResume=stage,grantSteps={{node=1}}}
		assert.is_true(recovery.isCurrent(build,"atlas",recovery.clean("atlas",{plan=plan,view=view})))
		stage.fields.requirements="Unfinished requirement";stage.amount="many"
		assert.is_true(recovery.save(build,"atlas",{plan=plan,view=view},true))
		local recovered=recovery.load(build,"atlas").entry
		assert.same(stage,recovered.view.stageResume);assert.is_nil(recovered.view.grantSteps)
		assert.is_false(recovery.isCurrent(build,"atlas",recovered))
		recovery.session="new-session";recovery.cache={};view.stageResume=nil
		assert.is_true(recovery.save(build,"atlas",{plan=plan,view=view},true))
		assert.same(stage,recovery.load(build,"atlas").entry.view.stageResume);assert.is_true(recovery.hasPending(build))
		assert.is_nil(build.savers.AtlasPlans.plans[1].strategy)
	end)
	it("rejects malformed Atlas stage recovery inputs",function()
		local plan={id="test",title="Test",version="3.30.0-preview",budget=150,nodes={}}
		local view={title="Test",notes="",budgetText="150",search="",scale=0.16,stageResume={page="Strategy",stage="starter",previous="",fields={maps=string.rep("x",4001),scarabs="",requirements="",avoid=""},amount="",currency="chaos",source=""}}
		assert.is_false(recovery.save(build,"atlas",{plan=plan,view=view},true));assert.is_nil(recovery.load(build,"atlas"))
	end)
	it("discards only current-session copies of an Atlas draft",function()
		local plan={id="draft",title="Earlier draft",version="3.30.0-preview",budget=150,nodes={}}
		assert.is_true(recovery.save(build,"atlas",{plan=plan},true));local earlier=recovery.session
		recovery.session="later-session";recovery.cache={};recovery.acknowledge(build,"atlas")
		plan.title="Current draft";assert.is_true(recovery.save(build,"atlas",{plan=plan},true))
		recovery.forgetAtlasSessionDraft(build,"draft");local remaining=recovery.load(build,"atlas")
		assert.equal(earlier,remaining.session);assert.equal("Earlier draft",remaining.entry.plan.title);assert.is_true(recovery.hasPending(build))
		assert.is_true(recovery.save(build,"atlas",{plan={id="other",title="Other",version=plan.version,budget=150,nodes={}}},true))
		assert.equal("Earlier draft",recovery.load(build,"atlas").entry.plan.title)
	end)
	it("captures open stage edits and restores them into the editor",function()
		local plan={id="test",title="Test",version="3.30.0-preview",budget=150,nodes={},notes=""};build.savers.AtlasPlans:Upsert(plan)
		local layout={width=1100,height=750,mount=function() end}
		local panel=require("Classes.AtlasPlannerControl").Open(build,plan,layout);panel.progression:Click()
		local stage=main.popups[1].controls;stage.requirements:SetText("Unfinished",true);stage.amount:SetText("many",true)
		assert.is_true(recovery.save(build,"atlas",{plan=layout.snapshot(),view=layout.viewState()},true))
		local recovered=recovery.load(build,"atlas").entry;assert.is_false(recovery.isCurrent(build,"atlas",recovered))
		stage.close:Click();assert.is_nil(layout.viewState().stageResume)
		local restored={width=1100,height=750,mount=function() end,restore=recovered.view}
		local reopened=require("Classes.AtlasPlannerControl").Open(build,recovered.plan,restored)
		assert.equal("Resume stages",reopened.progression.label());reopened.progression:Click()
		stage=main.popups[1].controls;assert.equal("Unfinished",stage.requirements.buf);assert.equal("many",stage.amount.buf)
		assert.equal("Unfinished",restored.viewState().stageResume.fields.requirements);stage.close:Click()
	end)
	it("removes only the requested project's valid recovery slots and returns its working draft",function()
		local function craft(id)
			local p={id=id,title=id,slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={}}
			local state=require("Modules.CraftingSimulator").model(p.startingItem).initial
			local run=require("Modules.CraftingInventory").run(state);run.project=p;run.kind="workbench";return {plan=run}
		end
		assert.is_true(recovery.save(build,"crafting",craft("a"),true));assert.is_true(recovery.save(build,"crafting",craft("b"),true))
		assert.is_true(recovery.save(build,"filters",entry("Unrelated filter"),true))
		local saved=recovery.forgetCraftingProject(build,"a");assert.are.equal("a",saved.draft.project.id)
		assert.is_nil(recovery.forCraftingProject(build,"a"));assert.are.equal("b",recovery.load(build,"crafting").entry.plan.project.id)
		assert.are.equal("Unrelated filter",recovery.load(build,"filters").entry.plan.data.profiles[1].title)
		assert.is_true(recovery.save(build,"crafting",{plan=saved.draft},true));assert.is_truthy(recovery.forCraftingProject(build,"a"))
	end)
	it("recovers an interrupted unique preview separately from ordinary crafts",function()
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B"
		local project={id="unique-recovery",title="Unique",slot="Helmet",startingItem=raw,goals={},steps={}}
		build.savers.CraftingProjects:Upsert(project)
		local oldName,oldFile=build.buildName,build.dbFileName;local xml=build:SaveDB("Unique recovery")
		local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		control.apply:Click();control.apply:Click();control.link:Click();control.close:Click()
		local saved=recovery.load(build,"uniqueQuality",project.id);assert.is_not_nil(saved);assert.equal(2,select(2,require("Modules.CraftingUniqueQuality").inspect(saved.entry.plan.itemText)).quality)
		assert.equal(3,#saved.entry.plan.history);assert.same({"quality","quality","beast_max_links"},saved.entry.plan.actions);assert.matches("Sockets: R%-G%-B",saved.entry.plan.itemText);assert.is_nil(recovery.load(build,"crafting"))
		recovery.session="later-session";recovery.cache={};loadBuildFromXML(xml,"Unique recovery");build.buildName=oldName;build.dbFileName=oldFile
		assert.is_false(recovery.isCurrent(build,"uniqueQuality",saved.entry));assert.is_nil(build.savers.CraftingProjects.projects[1].targetItem)
		local workspace=require("Modules.PlanningWorkspace").new(build);build.planningWorkspace=workspace
		require("Classes.PlanningToolsControl").Recovery(build);local browser=main.popups[1].controls
		assert.matches("Unique crafting: Unique",browser.results.list[1][1]);assert.matches("Goldrim",browser.details.list[1][1]);assert.matches("2%% quality",browser.details.list[1][1]);assert.matches("Sockets: R%-G%-B",browser.details.list[2][1]);browser.choose:Click()
		assert.equal("crafting",workspace.page);assert.matches("2%%",workspace.controls.status.label);assert.is_false(workspace.controls.link:IsEnabled());assert.is_true(workspace.controls.guide:IsEnabled())
		workspace.controls.undo:Click();assert.is_true(workspace.controls.link:IsEnabled());workspace.controls.undo:Click();assert.matches("1%%",workspace.controls.status.label)
		assert.is_true(require("Modules.PlanningUI").hasDraft(build,"uniqueQuality",project.id))
	end)
	it("protects older unique previews and rejects mismatched recovery items",function()
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86"
		local p={id="quality-guard",title="Unique",slot="Helmet",startingItem=raw,goals={},steps={}}
		local changed=require("Modules.CraftingUniqueQuality").apply(raw).itemText
		local draft={plan={kind="uniqueQuality",project=p,itemText=changed,history={raw}}}
		assert.is_true(recovery.save(build,"uniqueQuality",draft,true));recovery.session="later-session";recovery.cache={}
		local later=copyTable(draft);later.plan.itemText=raw;assert.is_true(recovery.save(build,"uniqueQuality",later,true))
		assert.equal(changed,recovery.load(build,"uniqueQuality",p.id).entry.plan.itemText);assert.is_true(recovery.hasPending(build))
		local invalid=copyTable(draft);invalid.plan.itemText="Rarity: UNIQUE\nThe Saviour\nLegion Sword\nItem Level: 86"
		assert.has_error(function() recovery.clean("uniqueQuality",invalid) end)
	end)
	it("recovers a new unsaved project but refuses a conflicting project ID",function()
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86"
		local p={id="quality-new",title="Unsaved guide",slot="Helmet",startingItem=raw,goals={},steps={}}
		local changed=require("Modules.CraftingUniqueQuality").apply(raw).itemText;local history={};for i=1,70 do history[i]=raw end
		assert.is_true(recovery.save(build,"uniqueQuality",{plan={kind="uniqueQuality",project=p,itemText=changed,history=history}},true))
		assert.equal(64,#recovery.load(build,"uniqueQuality",p.id).entry.plan.history)
		local conflicting=copyTable(p);conflicting.startingItem="Rarity: UNIQUE\nThe Gull\nRaven Mask\nItem Level: 86";build.savers.CraftingProjects:Upsert(conflicting)
		local browser=require("Classes.PlanningBrowserControl");local oldOpen=browser.Open;local entries,options
		browser.Open=function(_,values,config) entries,options=values,config end
		require("Classes.PlanningToolsControl").Recovery(build);browser.Open=oldOpen
		assert.has_error(function() options.choose(entries[1]) end)
		assert.equal(conflicting.startingItem,build.savers.CraftingProjects.projects[1].startingItem)
		build.savers.CraftingProjects:Remove(p.id)
		local workspace=require("Modules.PlanningWorkspace").new(build);build.planningWorkspace=workspace
		require("Classes.PlanningToolsControl").Recovery(build);main.popups[1].controls.choose:Click()
		assert.matches("1%%",workspace.controls.status.label);workspace.controls.keep:Click()
		assert.equal("quality-new",build.savers.CraftingProjects.projects[1].id)
		assert.equal(changed,build.savers.CraftingProjects.projects[1].targetItem)
	end)
	it("falls back to the older unique slot after an interrupted write",function()
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86"
		local p={id="unique-interrupted",title="Unique",slot="Helmet",startingItem=raw,goals={},steps={}}
		local quality=require("Modules.CraftingUniqueQuality");local one=quality.apply(raw).itemText;local two=quality.apply(one).itemText
		assert.is_true(recovery.save(build,"uniqueQuality",{plan={kind="uniqueQuality",project=p,itemText=one,history={raw}}},true))
		assert.is_true(recovery.save(build,"uniqueQuality",{plan={kind="uniqueQuality",project=p,itemText=two,history={raw,one}}},true))
		local latest=recovery.load(build,"uniqueQuality",p.id);local file=assert(io.open(latest.path,"wb"));file:write('{"schemaVersion":');file:close()
		assert.equal(one,recovery.load(build,"uniqueQuality",p.id).entry.plan.itemText)
	end)
	it("retains independent recovery previews for every unique project",function()
		local quality=require("Modules.CraftingUniqueQuality");local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86"
		for i=1,12 do
			local p={id="unique-"..i,title="Guide "..i,slot="Helmet",startingItem=raw,goals={},steps={}}
			assert.is_true(recovery.save(build,"uniqueQuality",{plan={kind="uniqueQuality",project=p,itemText=quality.apply(raw).itemText,history={raw}}},true))
		end
		for _,id in ipairs({"same-case","SAME-CASE"}) do
			local p={id=id,title=id,slot="Helmet",startingItem=raw,goals={},steps={}}
			assert.is_true(recovery.save(build,"uniqueQuality",{plan={kind="uniqueQuality",project=p,itemText=quality.apply(raw).itemText,history={raw}}},true))
		end
		assert.equal(14,#recovery.listUnique(build));assert.is_not_nil(recovery.load(build,"uniqueQuality","same-case"));assert.is_not_nil(recovery.load(build,"uniqueQuality","SAME-CASE"))
		local oldSearch,oldHeadless=NewFileSearch,launch.headless
		local ok,err=pcall(function()
			launch.headless=false
			_G.NewFileSearch=function(pattern)
				assert.matches("uniqueQuality",pattern);local names={}
				for name in require("lfs").dir(directory) do if name:match("%.json$") then names[#names+1]=name end end
				if #names==0 then return nil end;local index=1
				return {GetFileName=function() return names[index] end,NextFile=function() index=index+1;return index<=#names end}
			end
			assert.equal(14,#recovery.listUnique(build))
		end)
		_G.NewFileSearch=oldSearch;launch.headless=oldHeadless;assert(ok,err)
		for i=1,12 do assert.equal("unique-"..i,recovery.load(build,"uniqueQuality","unique-"..i).entry.plan.project.id) end
		recovery.clear(build,"uniqueQuality","unique-4");assert.equal(13,#recovery.listUnique(build));assert.is_nil(recovery.load(build,"uniqueQuality","unique-4"));assert.is_not_nil(recovery.load(build,"uniqueQuality","unique-5"))
	end)
	it("yields while discovering many project files",function()
		local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86";local changed=require("Modules.CraftingUniqueQuality").apply(raw).itemText
		for i=1,35 do
			local p={id="scan-many-"..i,title="Guide "..i,slot="Helmet",startingItem=raw,goals={},steps={}}
			assert.is_true(recovery.save(build,"uniqueQuality",{plan={kind="uniqueQuality",project=p,itemText=changed,history={raw}}},true))
		end
		recovery.session="later-session";recovery.cache={};local scan=assert(recovery.startScan(build));local steps=0
		while coroutine.status(scan)~="dead" do local ok,err=coroutine.resume(scan);assert(ok,err);steps=steps+1 end
		assert.is_true(steps>=40);assert.is_true(recovery.hasPending(build))
	end)
	it("keeps recovery files unchanged while preparing and applying an MCP removal",function()
		local p={id="review-delete",title="Review delete",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={}}
		build.savers.CraftingProjects:Upsert(p)
		local run=require("Modules.CraftingInventory").run(require("Modules.CraftingSimulator").model(p.startingItem).initial);run.project=p;run.kind="workbench"
		assert.is_true(recovery.save(build,"crafting",{plan=run},true))
		local function bytes() local f=assert(io.open(recovery.load(build,"crafting").path,"rb"));local raw=f:read("*a");f:close();return raw end
		local original=bytes();local bridge=require("Modules.DesktopBuildBridge");local base=build
		local prepared=bridge.prepare(base,{mode="edit",title="Remove guide",baseRevision=bridge.revision(base),operations={{type="remove_crafting_project",projectId=p.id}}})
		assert.are.equal(original,bytes());bridge.apply(prepared);assert.are.equal(original,bytes())
		bridge.restore();assert.are.equal(original,bytes())
	end)
end)
