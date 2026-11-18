-- Run from src: luajit ../tools/benchmark_map_rerolls.lua [stress]
-- CPU-time measurements vary by machine; they are not a frame-time guarantee.
local stress=arg[1]=="stress";arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local tasks=require("Modules.CraftingTasks")
local estimate=require("Modules.MapCraftEstimate")
local map=require("Modules.MapCraftingData")
local coldStart=os.clock();map.source();local loadMs=(os.clock()-coldStart)*1000
local state={baseId="Metadata/Items/Maps/MapWorldsStrand",tier=5,itemLevel=68,rarity="rare",selected={}}
-- Avoid every currently eligible modifier, forcing every attempt.
local page=map.inspect(state.baseId,state.tier,state.itemLevel,{},"",0,100,nil,state.rarity)
assert(not page.nextOffset,"Update the benchmark for a larger modifier pool")
local avoid={};for _,entry in ipairs(page.candidates) do avoid[#avoid+1]=entry.id end
local options={avoid=avoid,trials=stress and 1000 or 100,maxAttempts=stress and 20 or 5,seed=77}
local done,failed;local times={};local started=os.clock()
tasks.start(build,function(checkpoint) return estimate.run(state,options,checkpoint) end,function(value) done=value end,function(err) failed=err end)
while tasks.job do local t=os.clock();tasks.tick(build);times[#times+1]=(os.clock()-t)*1000 end
local elapsed=(os.clock()-started)*1000
assert(not failed,failed);assert(done and done.attempts==options.trials*options.maxAttempts and done.successes==0)
table.sort(times)
local cancelled,unexpected;local job=tasks.start(build,function(checkpoint) return estimate.run(state,options,checkpoint) end,function() unexpected=true end,function(err) cancelled=err end)
while tasks.job and (job.current.attempts or 0)<100 do tasks.tick(build) end
assert(tasks.job and job.current.attempts>=100);local cancelAt=job.current.attempts;tasks.cancel()
assert(not tasks.job and cancelled and not unexpected)
print("MAP_REROLL_BENCHMARK "..require("dkjson").encode({attempts=done.attempts,successes=done.successes,cpuMs=elapsed,coldDataLoadMs=loadMs,slices=#times,p95SliceMs=times[math.ceil(#times*0.95)],maxSliceMs=times[#times],cancelledAfter=cancelAt}))
