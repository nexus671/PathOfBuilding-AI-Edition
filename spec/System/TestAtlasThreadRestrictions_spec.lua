describe("Current Thread modifier restrictions",function()
	local strategy=require("Modules.AtlasStrategy")
	local function count(level,threads,spent)
		local total=0;for _,row in ipairs(strategy.threadRestrictions(level,threads,nil,spent).modifiers) do if row.restrictionsMet then total=total+1 end end
		return total
	end
	it("checks the published level and Thread thresholds without predicting offers",function()
		assert.equal(0,count(100,8,1));assert.equal(0,count(72,2,2));assert.equal(3,count(73,2,2));assert.equal(3,count(79,8,2));assert.equal(7,count(80,2,2))
		local result=strategy.threadRestrictions(80,2);assert.equal("https://www.pathofexile.com/forum/view-thread/4015683",result.source);assert.matches("Other requirements",result.note);assert.matches("other Thread types are unverified",result.note)
		for _,row in ipairs(result.modifiers) do assert.is_nil(row.restrictionsMet);assert.equal("spend_unresolved",row.conditionStatus) end
		for _,row in ipairs(strategy.threadRestrictions(80,8,nil,1).modifiers) do assert.is_false(row.restrictionsMet);assert.equal("restricted",row.conditionStatus) end
		for _,row in ipairs(strategy.threadRestrictions(80,8,nil,0).modifiers) do assert.is_nil(row.restrictionsMet) end
		assert.has_error(function() strategy.threadRestrictions(80,1.5) end);assert.has_error(function() strategy.threadRestrictions(0,2) end)
	end)
	it("distinguishes spent Abyss Threads from the applied total",function()
		local unknown=strategy.threadRestrictions(83,8).abyssalConsort
		assert.is_nil(unknown.spentThreads);assert.is_nil(unknown.restricted)
		local restricted=strategy.threadRestrictions(83,8,1).abyssalConsort
		assert.equal(1,restricted.spentThreads);assert.is_true(restricted.restricted);assert.matches("free or bonus",restricted.note)
		for _,spent in ipairs({0,2,8}) do assert.is_nil(strategy.threadRestrictions(83,8,spent).abyssalConsort.restricted) end
		assert.has_error(function() strategy.threadRestrictions(83,8,-1) end);assert.has_error(function() strategy.threadRestrictions(83,8,1.5) end)
	end)
	it("reports the 3.30.0c modifier guarantees and published milestones",function()
		for _,case in ipairs({{0,0,nil},{1,1,nil},{2,1,nil},{3,1,3},{4,2,3},{5,2,3},{6,2,6},{7,2,6},{8,3,8},{9,3,8}}) do
			local result=strategy.threadRestrictions(83,case[1]);assert.equal(case[2],result.guaranteedModifiers);assert.equal(case[3],result.milestones.threshold)
			assert.same({3,6,8},result.milestones.thresholds);assert.equal(10,#result.milestones.mechanics)
			if case[3] then assert.is_truthy(result.milestones.mechanics[1].current) else assert.is_nil(result.milestones.mechanics[1].current) end
		end
		local result=strategy.threadRestrictions(83,8);assert.equal("3 additional pits",result.milestones.mechanics[1].current)
		assert.equal("https://www.pathofexile.com/forum/view-thread/4017172",result.milestones.source)
		assert.is_true(result.guaranteeRequiresSpend);assert.matches("Free%-only cases are not established",result.guaranteeNote)
	end)
	it("exposes the sourced restrictions to Atlas reports and updates the native control",function()
		newBuild();main.popups={}
		local atlas=require("Modules.AtlasPlanner")
		local plan={id="threads",title="Threads",version="3.30.0-preview",budget=150,nodes={}}
		assert.equal(7,#atlas.report(plan).threadRestrictions.modifiers)
		plan.version="3.29.3";plan.budget=120;assert.is_nil(atlas.report(plan).threadRestrictions)
		local c=require("Classes.AtlasThreadControl").Open()
		c.level:SetText("72",true);c.threads:SetText("2",true);c.spent:SetText("2",true)
		local text="";for _,row in ipairs(c.results.list) do text=text..StripEscapes(row[1] or "").." " end
		assert.matches("Restricted",text);assert.not_matches("Conditions met",text)
		c.level:SetText("73",true);text="";for _,row in ipairs(c.results.list) do text=text..StripEscapes(row[1] or "").." " end
		assert.matches("Conditions met",text);assert.matches("Restricted",text)
		c.threads:SetText("8",true);text="";for _,row in ipairs(c.results.list) do text=text..StripEscapes(row[1] or "").." " end
		assert.matches("When spending Threads: 3 guaranteed modifiers",text);assert.matches("Free%-only guarantees are not established",text);assert.matches("Abyss: 3 additional pits",text);assert.matches("stacking not assumed",text)
		c.spent:SetText("1",true);text="";for _,row in ipairs(c.results.list) do text=text..StripEscapes(row[1] or "").." " end
		assert.matches("Consorts: restricted",text);assert.matches("free Threads are separate",text)
		main.popups={}
	end)
end)
