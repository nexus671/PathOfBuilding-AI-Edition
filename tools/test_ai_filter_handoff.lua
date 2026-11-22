-- Exercise unkept filter drafts through AI application and conflict review.
arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI");local bridge=require("Modules.DesktopBuildBridge");local filters=require("Modules.LootFilters");local status=require("Modules.PlanningUI")
for _,conflict in ipairs({false,true}) do
 newBuild();build=main.modes.BUILD;main.popups={};local ui=UI.install({width=1024,height=768});ui:bind(build)
 local profile=filters.profile("one","Saved filter");profile.trackBuildPickups=true;build.savers.LootFilters:Upsert(profile)
 local workspace=require("Modules.PlanningWorkspace").new(build);build.planningWorkspace=workspace;build.viewMode="PLANNER";workspace:Show("filters")
 ui:click("manage");ui:text("search","Disable pickup update notices");ui:click("choose");assert(status.hasDraft(build,"filters"))
 local operations={{type="set_character",level=5}}
 if conflict then local edited=copyTable(build.savers.LootFilters.data);edited.profiles[1].title="AI filter";operations={{type="set_loot_filters",filters=edited}} end
 local prepared=bridge.prepare(build,{mode="edit",title="AI edit",baseRevision=bridge.revision(build),operations=operations});local candidate=bridge.apply(prepared)
 assert(status.hasDraft(candidate,"filters"));local reopened=require("Modules.PlanningWorkspace").new(candidate);reopened:Show("filters")
 local snapshot=reopened.cache.filters.layout.snapshot();assert(snapshot.data.profiles[1].title=="Saved filter" and snapshot.data.profiles[1].trackBuildPickups==false)
 reopened.controls.keep:Click()
 if conflict then
  assert(main.popups[1] and main.popups[1].title=="Saved filters changed");assert(candidate.savers.LootFilters.data.profiles[1].title=="AI filter")
  main:ClosePopup();reopened.controls.keep:Click();main.popups[1].controls.confirm:Click()
 end
 assert(candidate.savers.LootFilters.data.profiles[1].trackBuildPickups==false);assert(not status.hasDraft(candidate,"filters"));ui:restore()
end
print("AI_FILTER_DRAFT_HANDOFF_OK")
