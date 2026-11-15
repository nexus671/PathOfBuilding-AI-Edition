describe("Experimental Fusing link model",function()
	local sim=require("Modules.CraftingSimulator")
	local sockets=require("Modules.CraftingSockets")
	local raw="Rarity: NORMAL\nPlate Vest\nItem Level: 86\nQuality: 20\nSockets: R G B W W W"
	it("enumerates different contiguous layouts with normalized historical probabilities",function()
		local model=sim.model(raw);local outcomes=sockets.fusingOutcomes(model.initial);local total=0;local full
		assert.equal(31,#outcomes)
		for _,entry in ipairs(outcomes) do
			total=total+entry.probability
			local linked=true;for i=2,6 do linked=linked and entry.groups[i]==entry.groups[1] end
			if linked then full=entry.probability end
		end
		assert.are.near(1,total,1e-12);assert.is_true(full>=0.001 and full<0.0011)
		local low=copyTable(model.initial);low.quality=0;local lowFull
		for _,entry in ipairs(sockets.fusingOutcomes(low)) do local linked=true;for i=2,6 do linked=linked and entry.groups[i]==entry.groups[1] end;if linked then lowFull=entry.probability end end
		assert.is_true(lowFull<full)
	end)
	it("preserves socket colours, changes the link layout and protects full five- and six-links",function()
		local model=sim.model(raw);local state=copyTable(model.initial)
		local next=sim.action(model,state,{method="fusing"},function() return 0 end)
		assert.equal(#state.sockets,#next.sockets);for i,entry in ipairs(state.sockets) do assert.equal(entry.color,next.sockets[i].color) end
		local changed=false;for i=2,#state.sockets do if (state.sockets[i].group==state.sockets[i-1].group)~=(next.sockets[i].group==next.sockets[i-1].group) then changed=true end end
		assert.is_true(changed);assert.same(model.initial,state)
		local complete=sim.model((raw:gsub("R G B W W W","R-G-B-W-W-W")))
		assert.is_false(require("Modules.CraftingAvailability").check("fusing",complete.initial,complete));assert.is_false(pcall(sim.action,complete,complete.initial,{method="fusing"},function() return 0 end))
		local four=sim.model((raw:gsub("R G B W W W","R-G-B-W")));assert.is_true(require("Modules.CraftingAvailability").check("fusing",four.initial,four))
	end)
	it("calculates exact outcomes for the stated model and reports its uncertainty",function()
		local result=sim.calculate(raw,{method="fusing"},{},nil,{requirements={links=6}})
		assert.is_false(result.sampled);assert.equal(31,#result.outcomes);assert.equal("fusing_estimate",result.warnings[1].code)
		local sum,matching=0,0;for _,entry in ipairs(result.outcomes) do sum=sum+entry.chance;if entry.matches then matching=matching+entry.chance end end
		assert.are.near(100,sum,1e-8);assert.are.near(matching,result.successChance,1e-8)
		local craft=sim.perform(raw,{method="fusing"},123);assert.equal("fusing_estimate",craft.warnings[1].code)
	end)
end)
