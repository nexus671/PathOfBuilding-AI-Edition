-- Run from src: luajit ../tools/benchmark_atlas_report.lua
-- This is a report CPU measurement, not a tree interaction latency benchmark.
arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local atlas=require("Modules.AtlasPlanner");local tree=atlas.tree("3.30.0c")
local plan={id="report-benchmark",title="Report benchmark",version="3.30.0c",budget=tree.maxPoints,nodes={}}
local queue,seen={tree.start},{[tree.start]=true};local at=1
while at<=#queue and #plan.nodes<120 do
	local links=copyTable(tree.nodes[queue[at]].links);table.sort(links)
	for _,id in ipairs(links) do if tree.nodes[id] and not seen[id] and #plan.nodes<120 then
		seen[id]=true;queue[#queue+1]=id;plan.nodes[#plan.nodes+1]=id
	end end
	at=at+1
end
assert(#plan.nodes==120,"Could not build a connected Atlas benchmark fixture")
local full=atlas.report(plan);local quick=atlas.report(plan,{includeAdditive=false})
assert(tableDeepEquals(full.counts,quick.counts) and full.remaining==quick.remaining and tableDeepEquals(full.stats,quick.stats) and #quick.additiveTotals==0,"Lightweight report changed the tree summary")
local loops=100
local function measure(options)
	local start=os.clock();for _=1,loops do atlas.report(plan,options) end
	return (os.clock()-start)*1000/loops
end
measure(nil);measure({includeAdditive=false})
print("ATLAS_REPORT_BENCHMARK "..require("dkjson").encode({nodes=#plan.nodes,iterations=loops,fullCpuMs=measure(nil),refreshCpuMs=measure({includeAdditive=false}),scope="Report CPU only; not measured UI latency"}))
