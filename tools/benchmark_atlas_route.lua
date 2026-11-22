-- Compare bounded Atlas route CPU time using an optional older module file.
local prior=arg[1];arg={};dofile("HeadlessWrapper.lua")
local atlas=prior and assert(loadfile(prior))() or require("Modules.AtlasPlanner")
local ids={53175,34352,14203,63753,57123,55003}
for _,count in ipairs({2,4,6}) do
 local targets={};for i=1,count do targets[i]=ids[i] end
 local plan={id="benchmark",title="Benchmark",version="3.30.0-preview",budget=150,nodes={},notes=""}
 atlas.connectOptimized(plan,targets);local start=os.clock();local route,added,info
 for _=1,20 do route,added,info=atlas.connectOptimized(plan,targets) end
 print(string.format("ROUTE_BENCH count=%d mean_seconds=%.6f added=%d attempts=%d exact=%s",count,(os.clock()-start)/20,#added,info.attempts,tostring(not info.heuristic)))
end
