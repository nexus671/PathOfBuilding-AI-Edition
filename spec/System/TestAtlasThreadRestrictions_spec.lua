describe("Current Thread modifier restrictions",function()
	local strategy=require("Modules.AtlasStrategy")
	local function count(level,threads)
		local total=0;for _,row in ipairs(strategy.threadRestrictions(level,threads).modifiers) do if row.restrictionsMet then total=total+1 end end
		return total
	end
	it("checks the published level and Thread thresholds without predicting offers",function()
		assert.equal(0,count(100,1));assert.equal(0,count(72,2));assert.equal(3,count(73,2));assert.equal(3,count(79,8));assert.equal(7,count(80,2))
		local result=strategy.threadRestrictions(80,2);assert.equal("https://www.pathofexile.com/forum/view-thread/4015683",result.source);assert.matches("Other requirements",result.note)
		assert.has_error(function() strategy.threadRestrictions(80,1.5) end);assert.has_error(function() strategy.threadRestrictions(0,2) end)
	end)
	it("exposes the sourced restrictions to Atlas reports and updates the native control",function()
		newBuild();main.popups={}
		local atlas=require("Modules.AtlasPlanner")
		local plan={id="threads",title="Threads",version="3.30.0-preview",budget=150,nodes={}}
		assert.equal(7,#atlas.report(plan).threadRestrictions.modifiers)
		plan.version="3.29.3";plan.budget=120;assert.is_nil(atlas.report(plan).threadRestrictions)
		local c=require("Classes.AtlasThreadControl").Open()
		c.level:SetText("72",true);c.threads:SetText("2",true)
		local text="";for _,row in ipairs(c.results.list) do text=text..StripEscapes(row[1] or "").." " end
		assert.matches("Restricted",text);assert.not_matches("Conditions met",text)
		c.level:SetText("73",true);text="";for _,row in ipairs(c.results.list) do text=text..StripEscapes(row[1] or "").." " end
		assert.matches("Conditions met",text);assert.matches("Restricted",text)
		main.popups={}
	end)
end)
