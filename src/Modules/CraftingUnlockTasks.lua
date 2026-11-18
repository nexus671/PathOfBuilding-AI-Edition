-- Add explicit, linked Roadmap tasks without inferring account unlock state.
local M={}
function M.track(build,projectId,model,action)
	assert(type(projectId)=="string" and projectId~="","Choose a saved crafting project")
	local project;for _,entry in ipairs(build.savers.CraftingProjects.projects) do if entry.id==projectId then project=entry;break end end
	assert(project,"Keep the crafting project before tracking an unlock")
	assert(type(action)=="table" and action.method=="bench","Select a bench recipe step")
	local unlock=assert(require("Modules.CraftingBenchCosts").unlock(model,action.modId),"This step has no listed unlock location")
	local mod=assert(model.byId[action.modId]);local title="Unlock "..table.concat(mod," / ")
	local key="unlock-"..require("sha1")(projectId.."\0"..action.modId):sub(1,20)
	local journey=build.savers.BuildJourney
	for _,entry in ipairs(journey.data.milestones) do if entry.id==key then return {created=false,task=copyTable(entry),unlock=unlock} end end
	local task={id=key,title=title,kind="craft",priority=3,done=false,dependencies={},projectId=projectId,
		notes="PoEDB lists "..unlock.map.." as the 3.30 recipe location. Verify the unlock in game; account and Ruthless availability are not checked. Source: "..unlock.source}
	journey:Put("milestones",task)
	return {created=true,task=task,unlock=unlock}
end
return M
