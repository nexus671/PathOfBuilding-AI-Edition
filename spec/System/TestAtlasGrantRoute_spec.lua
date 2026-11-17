describe("Atlas point-grant route proofs",function()
	local route=require("Modules.AtlasGrantRoute")
	local tree={start=1,nodes={
		[1]={links={2,3},grantedPoints=0},[2]={links={1,5},grantedPoints=0},
		[3]={links={1,4},grantedPoints=0},[4]={links={3,5},grantedPoints=0},
		[5]={links={2,4},grantedPoints=2},
	}}
	local final={[1]=true,[3]=true,[4]=true,[5]=true}
	it("constructs a connected, affordable temporary route and refunds the shortcut",function()
		local steps=assert(route.find(tree,final,{},2,5));local allocated={[1]=true};local used=0;local refunds=0
		for _,step in ipairs(steps) do
			if step.action=="Allocate" then
				assert.is_true(used<2+(allocated[5] and 2 or 0))
				local adjacent=false;for _,id in ipairs(tree.nodes[step.id].links) do if allocated[id] then adjacent=true end end
				assert.is_true(adjacent);assert.is_false(allocated[step.id] or false);allocated[step.id]=true;used=used+1
			else assert.equal("Refund",step.action);assert.is_true(allocated[step.id]);allocated[step.id]=nil;used=used-1;refunds=refunds+1 end
			local capacity=2+(allocated[5] and 2 or 0);assert.is_true(used<=capacity)
			local seen={[1]=true};local q={1};local i=1
			while i<=#q do local id=q[i];i=i+1;for _,n in ipairs(tree.nodes[id].links) do if allocated[n] and not seen[n] then seen[n]=true;q[#q+1]=n end end end
			for id in pairs(allocated) do assert.is_true(seen[id]) end
		end
		assert.same(final,allocated);assert.equal(1,refunds)
	end)
	it("replays a route on the bundled Atlas without exceeding its budget",function()
		newBuild();local atlas=require("Modules.AtlasPlanner");local version="3.29.3";local tree=atlas.tree(version)
		local target=atlas.search(version,"Unwavering Vision",10).matches[1].id
		local empty={id="test",title="Test",version=version,budget=tree.maxPoints,nodes={},notes=""}
		local shortest=atlas.connect(empty,{target});local plan=atlas.connect(empty,{target},{17321});plan.budget=#shortest.nodes
		local final={[tree.start]=true};for _,id in ipairs(plan.nodes) do final[id]=true end
		local steps=assert(route.find(tree,final,{},plan.budget,target));local state=copyTable(empty);state.budget=plan.budget
		local granted=false;local refunds=0
		for _,step in ipairs(steps) do
			if step.action=="Allocate" then
				assert.is_true(#state.nodes<state.budget+(granted and tree.nodes[target].grantedPoints or 0))
				state.nodes[#state.nodes+1]=step.id;if step.id==target then granted=true end
			else for i,id in ipairs(state.nodes) do if id==step.id then table.remove(state.nodes,i);break end end;refunds=refunds+1 end
			state=atlas.validate(state)
		end
		assert.same(plan.nodes,state.nodes);assert.is_true(refunds>0)
	end)
	it("keeps impossible or unproven transitions unknown",function()
		assert.is_nil(route.find(tree,final,{},1,5))
		assert.is_nil(route.find(tree,final,{[2]=true},2,5))
		local noGrant=copyTable(tree);noGrant.nodes[5].grantedPoints=0
		assert.is_nil(route.find(noGrant,final,{},2,5))
		local tight=copyTable(tree);tight.nodes[5].grantedPoints=1
		-- The final tree fits three points, but building its replacement path
		-- needs an extra point before the temporary shortcut can be refunded.
		assert.is_nil(route.find(tight,final,{},2,5))
	end)
	it("never returns an invalid proof across varied directed graphs",function()
		local seed=17;local function random(n) seed=(seed*16807)%2147483647;return seed%n end
		for _=1,80 do
			local graph={start=1,nodes={}};for id=1,7 do graph.nodes[id]={links={},grantedPoints=id==7 and 3 or 0} end
			for id=1,6 do graph.nodes[id].links[#graph.nodes[id].links+1]=id+1 end
			for from=1,7 do for to=1,7 do if from~=to and random(5)==0 then graph.nodes[from].links[#graph.nodes[from].links+1]=to end end end
			local goal={};for id=1,7 do goal[id]=true end;local budget=3+random(4)
			local steps=route.find(graph,goal,{},budget,7)
			if steps then
				local held={[1]=true};local used=0
				for _,step in ipairs(steps) do
					if step.action=="Allocate" then
						assert.is_true(used<budget+(held[7] and 3 or 0));local connected=false
						for id in pairs(held) do for _,other in ipairs(graph.nodes[id].links) do if other==step.id then connected=true end end end
						assert.is_true(connected);assert.is_nil(held[step.id]);held[step.id]=true;used=used+1
					else assert.equal("Refund",step.action);assert.is_true(held[step.id]);held[step.id]=nil;used=used-1 end
					local seen={[1]=true};local q={1};local head=1
					while head<=#q do local id=q[head];head=head+1;for _,other in ipairs(graph.nodes[id].links) do if held[other] and not seen[other] then seen[other]=true;q[#q+1]=other end end end
					for id in pairs(held) do assert.is_true(seen[id]) end
					assert.is_true(used<=budget+(held[7] and 3 or 0))
				end
				assert.same(goal,held)
			end
		end
	end)
end)
