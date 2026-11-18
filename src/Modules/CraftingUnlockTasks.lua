-- Add explicit, linked Roadmap tasks without inferring account unlock state.
local M={}
local function taskKey(projectId,modId)
	return "unlock-"..require("sha1")(projectId.."\0"..modId):sub(1,20)
end
local function savedProject(build,projectId)
	assert(type(projectId)=="string" and projectId~="","Choose a saved crafting project")
	for _,entry in ipairs(build.savers.CraftingProjects.projects) do if entry.id==projectId then return entry end end
	error("Keep the crafting project first")
end
-- A report is based on the supplied recipe and item model, not account data.
function M.review(build,projectId,model,steps)
	local project=savedProject(build,projectId);assert(type(model)=="table" and type(model.byId)=="table","Missing crafting item model")
	steps=steps or project.nativeRecipe and project.nativeRecipe.steps or {};assert(type(steps)=="table" and #steps<=20,"Invalid recipe steps")
	local entries,unknown,seen,existing={},{},{},{}
	local journey=build.savers.BuildJourney
	if not journey.unreadable then for _,entry in ipairs(journey.data.milestones) do existing[entry.id]=entry end end
	for index,step in ipairs(steps) do if step.method=="bench" then
		local id=step.modId;local mod=type(id)=="string" and model.byId[id]
		if not mod then unknown[#unknown+1]={step=index,modId=id or "",reason="Modifier is unavailable for the current item model."}
		else local unlock=require("Modules.CraftingBenchCosts").unlock(model,id)
			if unlock then
				local entry=seen[id]
				if not entry then
					local key=taskKey(projectId,id);local task=existing[key]
					entry={modId=id,title=table.concat(mod," / "),unlock=unlock,steps={},taskId=key,
						taskStatus=journey.unreadable and "unknown" or task and (task.done and "complete" or "tracked") or "untracked"}
					if task then entry.task=copyTable(task) end
					entries[#entries+1]=entry;seen[id]=entry
				end
				entry.steps[#entry.steps+1]=index
			end
		end
	end end
	return {projectId=projectId,entries=entries,unresolved=unknown,warning=journey.unreadable and (journey.warning or "Roadmap data could not be read; its original data is preserved.") or nil,note="Recipe-based reference only. Account unlocks, other bench recipes, and later item-base changes are not inferred."}
end
function M.track(build,projectId,model,action)
	savedProject(build,projectId)
	assert(type(action)=="table" and action.method=="bench","Select a bench recipe step")
	local unlock=assert(require("Modules.CraftingBenchCosts").unlock(model,action.modId),"This step has no listed unlock location")
	local mod=assert(model.byId[action.modId]);local title="Unlock "..table.concat(mod," / ")
	local key=taskKey(projectId,action.modId)
	local journey=build.savers.BuildJourney
	for _,entry in ipairs(journey.data.milestones) do if entry.id==key then return {created=false,task=copyTable(entry),unlock=unlock} end end
	local task={id=key,title=title,kind="craft",priority=3,done=false,dependencies={},projectId=projectId,
		notes="PoEDB lists "..unlock.map.." as the 3.30 recipe location. Verify the unlock in game; account and Ruthless availability are not checked. Source: "..unlock.source}
	journey:Put("milestones",task)
	return {created=true,task=task,unlock=unlock}
end
return M
