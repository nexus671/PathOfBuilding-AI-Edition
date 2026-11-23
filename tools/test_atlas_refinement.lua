-- Compare a real eight-target Atlas route before and after subset refinement.
arg={};dofile("HeadlessWrapper.lua")
local atlas=require("Modules.AtlasPlanner");local tree=atlas.tree("3.30.0c")
local targets={3926,37197,37454,40832,48405,50907,55003,64980}
local plan={id="route-probe",title="Route probe",version="3.30.0c",budget=tree.maxPoints,nodes={},notes=""}
local start=os.clock();local baseline,old=atlas.connectOptimized(plan,targets,{}, {exact=false});local before=os.clock()-start
local progress=0;start=os.clock();local refined,added,details=atlas.connectOptimized(plan,targets,{}, {checkpoint=function() progress=progress+1 end});local after=os.clock()-start
assert(#old==63 and #added==62,"Expected the refinement to save a point on the published Atlas graph")
assert(details.heuristic and details.refinements==2 and progress>0,"Expected a cancellable heuristic refinement")
local set={};for _,id in ipairs(refined.nodes) do set[id]=true end;for _,id in ipairs(targets) do assert(set[id],"Refinement lost a desired node") end
local allocated=atlas.connect(plan,{targets[1]});local nextPlan,extra=atlas.connectOptimized(allocated,targets,{}, {})
local nextSet={};for _,id in ipairs(nextPlan.nodes) do nextSet[id]=true end;for _,id in ipairs(allocated.nodes) do assert(nextSet[id],"Refinement removed an existing allocation") end
local unrefined,plain,plainDetails=atlas.connectOptimized(allocated,targets,{}, {exact=false});assert(#extra<=#plain and plainDetails.refinements==0,"Refinement made the route worse")
local jobs=require("Modules.AtlasTargets");local owner={};local jobPlan=copyTable(plan);jobPlan.desired=targets
local job=jobs.start(owner,jobPlan,false);local ticks=0
while job.thread and ticks<5000 do jobs.tick(owner,true);ticks=ticks+1 end
assert(job.result and not job.error and ticks>1,"Background route did not complete in slices: "..tostring(job.error))
assert(#job.result.added==62,"Background route did not preserve the refinement")
jobs.reset(owner)
print(string.format("ATLAS_REFINEMENT_OK before=%d after=%d baseline=%.3fs refined=%.3fs",#old,#added,before,after))
