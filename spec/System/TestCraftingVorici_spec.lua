describe("Vorici socket colour service",function()
	local sim=require("Modules.CraftingSimulator")
	local check=require("Modules.CraftingAvailability").check
	local raw="Rarity: NORMAL\nPlate Vest\nItem Level: 86\nQuality: 20\nSockets: R-G B W-W R"
	local action={method="vorici_socket_colours"}
	local function rng(seed)
		return function() seed=(seed*16807)%2147483647;return seed/2147483647 end
	end
	local function score(state)
		local count=0;for _,socket in ipairs(state.sockets) do if socket.color~="W" and socket.color~="A" then count=count+1 end end;return count
	end
	it("selects the first highest scoring result from 25 independent rolls",function()
		local model=sim.model(raw);local before=copyTable(model.initial)
		for seed=1,8 do
			local random=rng(seed);local expected
			for _=1,25 do local candidate=sim.action(model,before,{method="chromatic"},random);if not expected or score(candidate)>score(expected) then expected=candidate end end
			local actual=sim.action(model,before,action,rng(seed));assert.same(expected,actual)
			assert.same(before.sockets,model.initial.sockets)
			assert.same(actual.sockets,new("Item"):Item(sim.toItem(model,actual).raw).sockets)
		end
	end)
	it("keeps the greatest of 100 independent socket-count rolls",function()
		local model=sim.model(raw);local before=copyTable(model.initial);before.sockets={before.sockets[1],before.sockets[2],before.sockets[3]}
		local method={method="vorici_socket_count"}
		for seed=1,8 do
			local random=rng(seed);local expected
			for _=1,100 do local candidate=sim.action(model,before,{method="jeweller"},random);if not expected or #candidate.sockets>#expected.sockets then expected=candidate end end
			local actual=sim.action(model,before,method,rng(seed));assert.same(expected,actual)
			assert.same(actual.sockets,new("Item"):Item(sim.toItem(model,actual).raw).sockets)
		end
		assert.equal("vorici_socket_assumptions",sim.actionWarnings(method)[1].code)
		assert.same({vorici_socket_count=1},sim.components(method))
		local catalog=sim.catalog(raw,"best of 100",5,before);assert.is_true(catalog.socketCrafts[1].available);assert.is_false(catalog.socketCrafts[1].deterministic)
		assert.is_false(check(method.method,model.initial,model))
		local draws=0;assert.is_false(pcall(sim.action,model,model.initial,method,function() draws=draws+1;return 0.5 end));assert.equal(0,draws)
	end)
	it("explains unavailable items before consuming randomness",function()
		local model=sim.model(raw)
		for _,change in ipairs({{key="sockets",value={}},{key="mirrored",value=true},{key="destroyed",value=true},{key="corrupted",value=true}}) do
			local state=copyTable(model.initial);state[change.key]=change.value;assert.is_false(check(action.method,state,model))
			local draws=0;assert.is_false(pcall(sim.action,model,state,action,function() draws=draws+1;return 0.5 end));assert.equal(0,draws)
		end
		local state=copyTable(model.initial);state.sockets[1].color="A";assert.is_false(check(action.method,state,model))
	end)
	it("exposes the service, assumptions and whole-action price",function()
		local catalog=sim.catalog(raw,"vorici",20);assert.equal(action.method,catalog.socketCrafts[1].method)
		assert.is_true(catalog.socketCrafts[1].available);assert.is_false(catalog.socketCrafts[1].deterministic)
		assert.equal("vorici_colour_assumptions",sim.actionWarnings(action)[1].code)
		assert.same({vorici_socket_colours=1},sim.components(action))
		local recipe={steps={action},targets={},requirements={minQuality=30}}
		local result=sim.simulate(raw,recipe,{trials=2,maxActions=1,forceFirstAction=true,actionPrices={vorici_socket_colours=7},currency="chaos"})
		assert.equal(7,result.meanCost);assert.equal("service",result.resourceUsage[1].kind);assert.equal(2,result.resourceUsage[1].amount)
	end)
end)
