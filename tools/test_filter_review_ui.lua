-- Review a saved filter tracking change through the native profile tools.
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
	newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
	local profile=require("Modules.LootFilters").profile("review-ui","Review filter");profile.trackBuildPickups=true
	build.savers.LootFilters:Upsert(profile);build.planningWorkspace=require("Modules.PlanningWorkspace").new(build);build.viewMode="PLANNER";build.planningWorkspace:Show("filters")
	ui:click("manage");ui:text("search","Disable pickup update notices");ui:click("choose")
	ui:click("manage");ui:text("search","Review changes");ui:click("choose")
	assert(main.popups[1].title=="Filter changes","Filter review did not open")
	local details={};for _,row in ipairs(main.popups[1].controls.details.list) do details[#details+1]=StripEscapes(row[1] or "") end
	assert(table.concat(details," "):find("Build pickup notices: Enabled -> Disabled",1,true),"Review omitted the notice setting")
	if output then ui:frame():write(output.."/"..size[1].."-filter-tracking-review.json") end
	ui:click("close")
	local project={id="manual-notice",title="Helmet crafting",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={{action="Use a rare currency"}}};build.savers.CraftingProjects:Upsert(project)
	ui:click("generate");for i=1,2000 do ui:frame();if main.popups[1] and main.popups[1].title=="Review build pickups" then break end end
	assert(main.popups[1] and main.popups[1].title=="Review build pickups","Manual guide notice did not open")
	local notice={};for _,row in ipairs(main.popups[1].controls.details.list) do notice[#notice+1]=StripEscapes(row[1] or "") end
	assert(table.concat(notice," "):find("Written guide steps",1,true),"Manual guide notice was not visible")
	if output then ui:frame():write(output.."/"..size[1].."-filter-pickup-notice.json") end
	ui:click("choose");assert(build.planningWorkspace.page=="crafting","Pickup notice did not open the crafting source")
	assert(build.planningWorkspace.controls.libraryPage:GetSelValue()=="Plan","Manual guide notice did not open the saved guide")
	assert(build.planningWorkspace.selections.crafting==project.id,"Manual guide notice opened a different project")
	if output then ui:frame():write(output.."/"..size[1].."-filter-notice-guide.json") end
	build.planningWorkspace:Show("filters");local restored=build.planningWorkspace.cache.filters.layout.snapshot()
	assert(restored.dirty and restored.data.profiles[1].trackBuildPickups==true,"Opening a notice discarded the generated filter draft")
	local linked=false;for _,rule in ipairs(restored.data.profiles[1].rules) do if rule.origin=="craft:"..project.id then linked=true end end
	assert(linked,"Opening a notice discarded the project's generated pickup")
end
for _,kind in ipairs({"atlas","budget"}) do
	newBuild();main.popups={};local ui=UI.install({width=960,height=640});ui:bind(build)
	if kind=="atlas" then
		build.savers.AtlasPlans:Upsert({id="warning-atlas",title="Atlas warning",version="3.30.0c",budget=150,nodes={},strategy={maps="Strand Map"}})
	else
		local journey=require("Modules.BuildJourney").empty();journey.resources={{id="warning-budget",title="Beach Maps"}};build.savers.BuildJourney:Replace(journey)
	end
	local profile=require("Modules.LootFilters").profile("source-ui","Source test");build.savers.LootFilters:Upsert(profile);build.planningWorkspace=require("Modules.PlanningWorkspace").new(build);build.viewMode="PLANNER";build.planningWorkspace:Show("filters")
	ui:click("generate");for i=1,2000 do ui:frame();if main.popups[1] and main.popups[1].title=="Review build pickups" then break end end
	assert(main.popups[1] and main.popups[1].title=="Review build pickups",kind.." notice did not open")
	assert(not main.popups[1].controls.secondary:IsEnabled(),"An unrelated notice offered guide acknowledgment")
	ui:click("choose");assert(build.planningWorkspace.page==(kind=="atlas" and "atlas" or "journey"),kind.." notice opened the wrong source")
end
do
	newBuild();main.popups={};local ui=UI.install({width=960,height=640});ui:bind(build)
	local project={id="preserve-work",title="Helmet crafting",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={{action="Use a rare currency"}}};build.savers.CraftingProjects:Upsert(project)
	local profile=require("Modules.LootFilters").profile("draft-check","Filter");build.savers.LootFilters:Upsert(profile)
	local workspace=require("Modules.PlanningWorkspace").new(build);build.planningWorkspace=workspace;build.viewMode="PLANNER";workspace:Show("crafting")
	ui:click("native");ui:choose("page","Emulate item");ui:click("currency_transmute");ui:click("item")
	local before=workspace.cache.crafting.layout.snapshot().state;assert(before and #before.affixes>0,"Working craft was not created")
	workspace:Show("filters");ui:click("generate");for i=1,2000 do ui:frame();if main.popups[1] and main.popups[1].title=="Review build pickups" then break end end
	assert(main.popups[1] and main.popups[1].title=="Review build pickups");ui:click("choose")
	ui:click("tab_item");ui:click("native");local after=workspace.cache.crafting.layout.snapshot().state
	assert(tableDeepEquals(before,after) and tableDeepEquals(after,before),"Opening the guide discarded the working craft")
end
do
	newBuild();main.popups={};local ui=UI.install({width=960,height=640});ui:bind(build)
	local project={id="review-guide",title="Helmet guide",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={{action="Use a rare currency"}}};build.savers.CraftingProjects:Upsert(project)
	local filters=require("Modules.LootFilters");local profile=filters.profile("review-guide-filter","Filter");build.savers.LootFilters:Upsert(profile)
	build.planningWorkspace=require("Modules.PlanningWorkspace").new(build);build.viewMode="PLANNER";build.planningWorkspace:Show("filters");ui:click("generate")
	for _=1,2000 do ui:frame();if main.popups[1] and main.popups[1].title=="Review build pickups" then break end end
	assert(main.popups[1] and main.popups[1].title=="Review build pickups" and main.popups[1].controls.secondary:IsEnabled(),"Guide review action is unavailable")
	if output then ui:frame():write(output.."/960-filter-guide-review.json") end
	ui:click("secondary");local snapshot=build.planningWorkspace.cache.filters.layout.snapshot();local draft=snapshot.data.profiles[1]
	assert(snapshot.dirty and draft.manualGuideReviews and #draft.manualGuideReviews==1,"Review was not kept in the filter draft")
	local _,warnings=filters.generate(build,draft);for _,warning in ipairs(warnings) do assert(warning.origin~="craft:review-guide","Reviewed guide still warns") end
	ui:click("manage");ui:text("search","Duplicate profile");ui:click("choose")
	snapshot=build.planningWorkspace.cache.filters.layout.snapshot();assert(#snapshot.data.profiles==2,"Profile was not duplicated")
	local duplicate=snapshot.data.profiles[2];assert(duplicate.id~=draft.id and duplicate.manualGuideReviews and #duplicate.manualGuideReviews==1,"Duplicate lost its guide review")
	_,warnings=filters.generate(build,duplicate);for _,warning in ipairs(warnings) do assert(warning.origin~="craft:review-guide","Duplicate unexpectedly warns") end
	ui:click("keep");local bundle=require("Modules.PlanningBundle");local raw=bundle.export(build);local imported=bundle.import(raw)
	loadBuildFromXML(imported.xml,"Imported reviewed guide");local kept=build.savers.LootFilters.data.profiles[2]
	assert(kept.manualGuideReviews and #kept.manualGuideReviews==1,"Guide review did not survive save and reopen")
	_,warnings=filters.generate(build,kept);for _,warning in ipairs(warnings) do assert(warning.origin~="craft:review-guide","Reopened guide unexpectedly warns") end
	local changed=copyTable(build.savers.CraftingProjects.projects[1]);changed.steps[1].action="Use a different currency";build.savers.CraftingProjects:Upsert(changed)
	_,warnings=filters.generate(build,kept);local warned=false;for _,warning in ipairs(warnings) do if warning.origin=="craft:review-guide" then warned=true end end
	assert(warned,"Changing the imported guide did not restore its review notice")
end
do
	newBuild();local filters=require("Modules.LootFilters");local unique=require("Modules.CraftingUniqueQuality")
	local project={id="stale-typed-guide",title="Unique guide",slot="Weapon 1",startingItem="Rarity: UNIQUE\nThe Blood Reaper\nHeadsman Axe\nItem Level: 86",goals={},steps={{action=unique.guideAction("divine",1),uniqueCraft={method="divine",count=1}}}}
	build.savers.CraftingProjects:Upsert(project);local profile=filters.profile("typed-guide","Filter")
	local _,warnings=filters.generate(build,profile);for _,warning in ipairs(warnings) do assert(warning.origin~="craft:stale-typed-guide","Valid structured step unexpectedly warned") end
	-- Older or imported data can contain a typed action whose text no longer agrees.
	build.savers.CraftingProjects.projects[1].steps[1].action="Use another currency"
	local rules;rules,warnings=filters.generate(build,profile);local notice
	for _,warning in ipairs(warnings) do if warning.origin=="craft:stale-typed-guide" and warning.manualGuideSignature then notice=warning end end
	assert(notice,"Unmatched structured step did not offer guide review")
	for _,rule in ipairs(rules) do assert(not (rule.origin==notice.origin and rule.text:find('BaseType == "Divine Orb"',1,true)),"Unmatched structured step generated a Divine Orb pickup") end
	profile.manualGuideReviews={{projectId=project.id,signature=notice.manualGuideSignature}};_,warnings=filters.generate(build,profile)
	for _,warning in ipairs(warnings) do assert(not warning.manualGuideSignature,"Reviewed unmatched step still warned") end
	build.savers.CraftingProjects.projects[1].startingItem="Rarity: UNIQUE\nUnknown item\nUnknown base\nItem Level: 86"
	_,warnings=filters.generate(build,profile);local inspectWarning,reviewWarning=false,false
	for _,warning in ipairs(warnings) do inspectWarning=inspectWarning or warning.retry==true;reviewWarning=reviewWarning or warning.manualGuideSignature~=nil end
	assert(inspectWarning and reviewWarning,"A structured guide that cannot be inspected did not preserve both repair and review notices")
end
do
	newBuild();main.popups={};local ui=UI.install({width=960,height=640});ui:bind(build)
	for _,id in ipairs({"first-review","second-review"}) do build.savers.CraftingProjects:Upsert({id=id,title=id,slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={{action="Use a rare currency"}}}) end
	build.savers.AtlasPlans:Upsert({id="remaining-atlas",title="Atlas warning",version="3.30.0c",budget=150,nodes={},strategy={maps="Strand Map"}})
	local filters=require("Modules.LootFilters");build.savers.LootFilters:Upsert(filters.profile("review-queue","Filter"))
	build.planningWorkspace=require("Modules.PlanningWorkspace").new(build);build.viewMode="PLANNER";build.planningWorkspace:Show("filters");ui:click("generate")
	for _=1,2000 do ui:frame();if main.popups[1] and main.popups[1].title=="Review build pickups" then break end end
	assert(main.popups[1] and main.popups[1].controls.secondary:IsEnabled(),"First guide review missing")
	ui:click("secondary");assert(main.popups[1] and main.popups[1].title=="Review build pickups" and main.popups[1].controls.secondary:IsEnabled(),"Remaining guide review was dismissed")
	ui:click("secondary");assert(main.popups[1] and main.popups[1].title=="Review build pickups" and not main.popups[1].controls.secondary:IsEnabled(),"Unrelated Atlas notice was dismissed")
	ui:click("close");assert(not main.popups[1],"Review popup did not close")
	local profile=build.planningWorkspace.cache.filters.layout.snapshot().data.profiles[1];assert(#profile.manualGuideReviews==2,"Both guide reviews were not kept")
	local _,warnings=filters.generate(build,profile);for _,warning in ipairs(warnings) do assert(not warning.manualGuideSignature,"Reviewed guide still warns") end
end
print("FILTER_REVIEW_UI_OK")
