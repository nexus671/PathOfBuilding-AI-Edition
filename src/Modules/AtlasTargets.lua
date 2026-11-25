-- Desired-node planning is separate from applying or saving allocations.
local atlas=require("Modules.AtlasPlanner")
local strategy=require("Modules.AtlasStrategy")
local identity=require("Modules.PlanningData")
local M={jobs=setmetatable({},{__mode="k"})}
M.blocking=strategy.blocking
function M.toggle(plan,id,kind)
	assert(kind=="desired" or kind=="avoided","Choose desired or avoided")
	local next=atlas.validate(plan);next.desired=next.desired or {};next.avoided=next.avoided or {}
	local list=next[kind];for i,other in ipairs(list) do if other==id then table.remove(list,i);return atlas.validate(next) end end
	local opposite=kind=="desired" and next.avoided or next.desired;for i=#opposite,1,-1 do if opposite[i]==id then table.remove(opposite,i) end end
	list[#list+1]=id;return atlas.validate(next)
end
function M.mechanic(plan,name)
	local next=atlas.validate(plan);local desired={};for _,id in ipairs(next.desired or {}) do desired[id]=true end
	local blocked={};for _,id in ipairs(next.avoided or {}) do blocked[id]=true end
	local candidates={};local all=true
	for id,node in pairs(atlas.tree(plan.version).nodes) do if node.kind=="notable" and strategy.hasMechanic(node,name) and #M.blocking(node)==0 and not blocked[id] then candidates[#candidates+1]=id;if not desired[id] then all=false end end end
	for _,id in ipairs(candidates) do desired[id]=not all or nil end
	next.desired={};for id in pairs(desired) do next.desired[#next.desired+1]=id end;return atlas.validate(next)
end
function M.start(build,plan,fromStart)
	plan=atlas.validate(plan);assert(#(plan.desired or {})>0,"Mark desired nodes first")
	local state={status="Calculating",baseHash=identity.hash(plan),base=copyTable(plan),fromStart=fromStart==true,progress={},paused=false}
	local input=copyTable(plan);if fromStart then input.nodes={};input.choices={} end
	state.thread=coroutine.create(function()
		local result,added,routing=atlas.connectOptimized(input,input.desired,input.avoided,{checkpoint=function(progress)
			state.progress=progress;if os.clock()>=state.deadline then coroutine.yield() end
		end})
		if fromStart then
			local retained={};for _,id in ipairs(result.nodes) do retained[id]=true end
			for _,choice in ipairs(plan.choices or {}) do if retained[choice.node] then result=atlas.chooseEffect(result,choice.node,choice.effect) end end
		end
		return {plan=result,added=added,routing=routing}
	end)
	M.jobs[build]=state;return state
end
function M.tick(build,force)
	local state=M.jobs[build];if not state or not state.thread or state.paused then return end
	local now=GetTime();if not force and state.lastTick==now then return end;state.lastTick=now
	local start=os.clock();state.deadline=start+0.004;local ok,result=coroutine.resume(state.thread)
	require("Modules.PlanningPerformance").record(build,"Atlas routing slice",os.clock()-start)
	if not ok then state.status="Could not find a route";state.error=tostring(result):match("^[^\n]+");state.thread=nil
	elseif coroutine.status(state.thread)=="dead" then state.status="Ready to review";state.result=result;state.thread=nil end
end
function M.apply(build,current)
	local state=assert(M.jobs[build],"Calculate a route first");assert(state.result,"Wait for the route preview")
	assert(identity.hash(atlas.validate(current))==state.baseHash,"The plan changed. Recalculate before using this preview.")
	return copyTable(state.result.plan)
end
function M.cancel(build) local state=M.jobs[build];if state then state.thread=nil;state.result=nil;state.status="Cancelled" end end
function M.reset(build) M.cancel(build);M.jobs[build]=nil end
function M.summary(plan)
	plan=atlas.validate(plan);local tree=atlas.tree(plan.version);local groups,blocks,investments={},{},{}
	local excludedThreads,increasedThreads={},{}
	for _,id in ipairs(plan.nodes) do local node=tree.nodes[id];local selectedNode=strategy.selectedNode(plan,node);local mechanic=strategy.mechanic(selectedNode);local row=groups[mechanic] or {name=mechanic,small=0,notable=0,keystone=0,gateway=0,total=0,content=0};groups[mechanic]=row
		row.total=row.total+1;row[node.kind]=row[node.kind]+1
		local threadRule=strategy.threadRule(plan,node);if threadRule then local rules=threadRule.kind=="exclude" and excludedThreads or increasedThreads;rules[#rules+1]=threadRule end
		local blocking=M.blocking(selectedNode);if #blocking==0 then row.content=row.content+1;for _,name in ipairs(strategy.allMechanics(selectedNode)) do investments[name]=true end else for _,stat in ipairs(blocking) do blocks[#blocks+1]={node=node.name,stat=stat,mechanic=mechanic} end end
	end
	local result={mechanics={},blocking=blocks,threadRestrictions=excludedThreads,warnings={},keystones={},desired=#(plan.desired or {}),avoided=#(plan.avoided or {}),connectedDesired=0}
	local allocated={};for _,id in ipairs(plan.nodes) do allocated[id]=true;local node=tree.nodes[id];if node.kind=="keystone" then result.keystones[#result.keystones+1]={id=id,name=node.name,stats=copyTable(node.stats)} end end
	for _,id in ipairs(plan.desired or {}) do if allocated[id] then result.connectedDesired=result.connectedDesired+1 end end
	table.sort(result.keystones,function(a,b) return a.name<b.name end)
	for _,row in pairsSortByKey(groups) do result.mechanics[#result.mechanics+1]=row end
	for _,block in ipairs(blocks) do if investments[block.mechanic] then result.warnings[#result.warnings+1]=block.mechanic.." investment includes a blocking modifier. Review natural-spawn restrictions and forced encounters: "..block.stat end end
	for _,excluded in ipairs(excludedThreads) do for _,increased in ipairs(increasedThreads) do if excluded.mechanic==increased.mechanic then
		result.warnings[#result.warnings+1]=excluded.name.." excludes "..excluded.mechanic.." Threads found in your Maps, conflicting with "..increased.name..". This does not block "..excluded.mechanic.." encounters."
	end end end
	return result
end
return M
