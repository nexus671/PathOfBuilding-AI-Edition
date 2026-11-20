describe("Exact small Atlas routes",function()
	local exact=require("Modules.AtlasExactRoute")
	local atlas=require("Modules.AtlasPlanner")
	local bit=require("bit")
	local function graph(edges)
		local t={nodes={}}
		for _,edge in ipairs(edges) do
			for _,id in ipairs(edge) do t.nodes[id]=t.nodes[id] or {id=id,links={}} end
			t.nodes[edge[1]].links[#t.nodes[edge[1]].links+1]=edge[2]
			t.nodes[edge[2]].links[#t.nodes[edge[2]].links+1]=edge[1]
		end
		return t
	end
	local function brute(tree,allocated,blocked,targets)
		local candidates={};for id in pairs(tree.nodes) do if not allocated[id] and not blocked[id] then candidates[#candidates+1]=id end end;table.sort(candidates)
		local best
		for mask=0,2^#candidates-1 do
			local chosen=copyTable(allocated);local count=0
			for i,id in ipairs(candidates) do if bit.band(mask,2^(i-1))~=0 then chosen[id]=true;count=count+1 end end
			if not best or count<best then
				local start=next(allocated);local reached={[start]=true};local queue={start};local i=1
				while i<=#queue do for _,id in ipairs(tree.nodes[queue[i]].links) do if chosen[id] and not reached[id] then reached[id]=true;queue[#queue+1]=id end end;i=i+1 end
				local valid=true;for _,id in ipairs(targets) do if not reached[id] then valid=false end end
				if valid then best=count end
			end
		end
		return best
	end
	local function assertConnected(tree,allocated,blocked,targets,added)
		if not added then return end
		local chosen=copyTable(allocated);for id in pairs(added) do assert.is_nil(blocked[id]);chosen[id]=true end
		local start=next(allocated);local reached={[start]=true};local queue={start};local i=1
		while i<=#queue do for _,id in ipairs(tree.nodes[queue[i]].links) do if chosen[id] and not reached[id] then reached[id]=true;queue[#queue+1]=id end end;i=i+1 end
		for _,id in ipairs(targets) do assert.is_true(reached[id]) end
		for id in pairs(chosen) do assert.is_true(reached[id]) end
	end
	it("matches exhaustive graph search with shared paths, allocations and exclusions",function()
		local tree=graph({{1,2},{2,3},{3,4},{1,5},{5,6},{6,4},{2,7},{7,8},{6,8},{3,9},{8,9}})
		for _,case in ipairs({{{[1]=true},{},{4,8,9}},{{[1]=true,[2]=true},{},{4,6,9}},{{[1]=true},{[3]=true},{4,8}},{{[1]=true},{[2]=true,[6]=true},{4,9}},{{[1]=true},{},{4,6,8,9}},{{[1]=true},{},{4,5,6,7,8,9}},{{[1]=true},{[3]=true},{4,5,6,7,8,9}}}) do
			local actual=exact.find(tree,case[1],case[2],case[3]);local expected=brute(tree,case[1],case[2],case[3]);local count=0
			if actual then for _ in pairs(actual) do count=count+1 end end
			assert.equal(expected,actual and count or nil);assertConnected(tree,case[1],case[2],case[3],actual)
		end
	end)
	it("explains unreachable targets before exploring route orders",function()
		local p={id="blocked-route",title="Blocked",version="3.30.0-preview",budget=150,nodes={},notes=""}
		local tree=atlas.tree(p.version);local avoid=copyTable(tree.nodes[tree.start].links);local target
		local excluded={};for _,id in ipairs(avoid) do excluded[id]=true end
		for id,node in pairs(tree.nodes) do if id~=tree.start and not excluded[id] and node.name and node.name~="" then target=id;break end end
		assert.is_truthy(target);local checkpoints=0
		local ok,why=pcall(atlas.connectOptimized,p,{target},avoid,{checkpoint=function() checkpoints=checkpoints+1 end})
		assert.is_false(ok);assert.is_truthy(tostring(why):find(tree.nodes[target].name,1,true));assert.is_truthy(tostring(why):find("avoided nodes",1,true));assert.equal(0,checkpoints)
		p.desired={target};p.avoided=avoid;local jobs=require("Modules.AtlasTargets");local owner={};local job=jobs.start(owner,p)
		while job.thread do jobs.tick(owner,true) end
		assert.equal("Could not find a route",job.status);assert.is_truthy(job.error:find(tree.nodes[target].name,1,true));assert.is_truthy(job.error:find("avoided nodes",1,true));jobs.reset(owner)
	end)
	it("solves six distinct targets on the bundled tree and retains checkpoints",function()
		local p={id="six",title="Six",version="3.30.0-preview",budget=150,nodes={},notes=""}
		local ids={53175,34352,14203,63753,57123,55003};local checkpoints=0
		local route,added,info=atlas.connectOptimized(p,ids,nil,{checkpoint=function(progress) if progress.phase=="exact" then checkpoints=checkpoints+1 end end})
		assert.is_false(info.heuristic);assert.is_true(checkpoints>0)
		local present={};for _,id in ipairs(route.nodes) do present[id]=true end;for _,id in ipairs(ids) do assert.is_true(present[id]) end
		local _,greedy=atlas.connect(p,ids);assert.is_true(#added<=#greedy)
		local tree=atlas.tree(p.version);assert.is_nil(exact.find(tree,{[tree.start]=true},{},{53175,34352,14203,63753,57123,55003,23827}))
	end)
	it("keeps six-target route calculation resumable",function()
		local jobs=require("Modules.AtlasTargets");local owner={}
		local p={id="sliced",title="Sliced",version="3.30.0-preview",budget=150,nodes={},notes="",desired={53175,34352,14203,63753,57123,55003}}
		local job=jobs.start(owner,p,false);local ticks=0
		while job.thread and ticks<5000 do jobs.tick(owner,true);ticks=ticks+1 end
		assert.is_nil(job.error);assert.is_truthy(job.result);assert.is_false(job.result.routing.heuristic);assert.is_true(ticks>1)
		jobs.reset(owner)
	end)
	it("matches exhaustive search across many small graph shapes",function()
		for seed=1,48 do
			local edges={};for id=1,7 do edges[#edges+1]={id,id+1} end
			for a=1,8 do for b=a+2,8 do if (a*31+b*17+seed*13)%7<2 then edges[#edges+1]={a,b} end end end
			local tree=graph(edges);local blocked=seed%3==0 and {[4]=true} or {};local targets={6,7,8}
			local expected=brute(tree,{[1]=true},blocked,targets);local actual=exact.find(tree,{[1]=true},blocked,targets);local count=0
			if actual then for _ in pairs(actual) do count=count+1 end end
			assert.equal(expected,actual and count or nil);assertConnected(tree,{[1]=true},blocked,targets,actual)
		end
	end)
	it("finds the best valid shared route on the bundled tree",function()
		local p={id="exact",title="Exact",version="3.30.0-preview",budget=150,nodes={},notes=""}
		local ids={53175,34352,14203}
		local original,first=atlas.connect(p,ids);local route,added,info=atlas.connectOptimized(p,ids)
		assert.is_false(info.heuristic);assert.is_true(#added<=#first)
		local present={};for _,id in ipairs(route.nodes) do present[id]=true end;for _,id in ipairs(ids) do assert.is_true(present[id]) end
		assert.is_truthy(atlas.validate(original));assert.is_truthy(atlas.validate(route))
		local _,_,quick=atlas.connectOptimized(p,ids,nil,{exact=false});assert.is_true(quick.heuristic)
	end)
	it("improves a larger route without losing allocations or exclusions",function()
		local p={id="refine",title="Refine",version="3.30.0-preview",budget=150,nodes={},notes=""}
		local ids={39402,22270,60117,23416,23538,40832,52315};local checkpoints=0
		local _,before,old=atlas.connectOptimized(p,ids,nil,{refine=false})
		local route,after,info=atlas.connectOptimized(p,ids,nil,{checkpoint=function() checkpoints=checkpoints+1 end})
		assert.equal(51,#before);assert.equal(50,#after);assert.is_true(old.heuristic);assert.is_true(info.heuristic);assert.is_true(checkpoints>0)
		local tight=copyTable(p);tight.budget=50
		assert.is_false(pcall(atlas.connectOptimized,tight,ids,nil,{refine=false}))
		local valid,tightAdded=atlas.connectOptimized(tight,ids);assert.equal(50,#tightAdded);assert.is_truthy(atlas.validate(valid))
		local present={};for _,id in ipairs(route.nodes) do present[id]=true end;for _,id in ipairs(ids) do assert.is_true(present[id]) end
		assert.is_truthy(atlas.validate(route));assert.is_true(info.attempts<=old.attempts+24)
		local start=atlas.tree(p.version).nodes[atlas.tree(p.version).start];local neighbour
		for _,id in ipairs(start.links) do if not isValueInTable(ids,id) then neighbour=id;break end end
		local retained=atlas.connect(p,{assert(neighbour)});local excluded
		for id in pairs(atlas.tree(p.version).nodes) do if id~=atlas.tree(p.version).start and not isValueInTable(retained.nodes,id) and not isValueInTable(before,id) and not isValueInTable(ids,id) and (not excluded or id<excluded) then excluded=id end end
		local _,unrefined=atlas.connectOptimized(retained,ids,{excluded},{refine=false})
		local refined,improved=atlas.connectOptimized(retained,ids,{excluded})
		assert.is_true(#improved<=#unrefined);assert.is_nil(isValueInTable(refined.nodes,excluded) and true or nil)
		for _,id in ipairs(retained.nodes) do assert.is_truthy(isValueInTable(refined.nodes,id)) end
	end)
	it("keeps larger-route refinement resumable",function()
		local jobs=require("Modules.AtlasTargets");local owner={}
		local p={id="refined-slice",title="Refined slice",version="3.30.0-preview",budget=150,nodes={},notes="",desired={39402,22270,60117,23416,23538,40832,52315}}
		local job=jobs.start(owner,p,false);local ticks=0
		while job.thread and ticks<5000 do jobs.tick(owner,true);ticks=ticks+1 end
		assert.is_nil(job.error);assert.is_truthy(job.result);assert.is_true(job.result.routing.heuristic);assert.is_true(ticks>1);jobs.reset(owner)
	end)
	it("ignores allocated and repeated targets when choosing an exact route",function()
		local p={id="existing",title="Existing",version="3.30.0-preview",budget=150,nodes={},notes=""}
		p=atlas.connect(p,{53175});assert.is_true(#p.nodes>=4)
		local wanted=34352;local present={};for _,id in ipairs(p.nodes) do present[id]=true end
		assert.is_nil(present[wanted])
		local requests={p.nodes[1],p.nodes[2],p.nodes[3],p.nodes[4],wanted,wanted}
		local route,added,info=atlas.connectOptimized(p,requests)
		local direct,directAdded,directInfo=atlas.connectOptimized(p,{wanted})
		assert.is_false(info.heuristic);assert.is_false(directInfo.heuristic)
		assert.same(direct.nodes,route.nodes);assert.same(directAdded,added);assert.equal(directInfo.attempts,info.attempts)
		local unchanged,none,complete=atlas.connectOptimized(p,{p.nodes[1],p.nodes[2],p.nodes[1]})
		assert.same(p.nodes,unchanged.nodes);assert.equal(0,#none);assert.is_false(complete.heuristic)
	end)
end)
