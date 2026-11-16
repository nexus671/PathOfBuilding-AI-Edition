describe("Crafting budget and spending charts",function()
	local charts=require("Modules.CraftingChartData")
	local result={trials=10,successChance=40,costCurrency="chaos",actionDistribution={{actions=1,trials=2,successes=1},{actions=3,trials=5,successes=3},{actions=5,trials=3,successes=0}},costDistribution={{cost=2,trials=2,successes=1},{cost=6,trials=5,successes=3},{cost=10,trials=3,successes=0}}}
	it("keeps capped failures in the denominator of success curves",function()
		local data=charts.series({{label="Route",result=result}},charts.modes[1]);local points=data.series[1].points
		assert.equal(0,charts.at(points,0).y);assert.equal(10,charts.at(points,2).y);assert.equal(40,charts.at(points,3).y);assert.equal(40,charts.at(points,100).y)
		assert.equal(10,points[3].trials);assert.same(result.actionDistribution,{{actions=1,trials=2,successes=1},{actions=3,trials=5,successes=3},{actions=5,trials=3,successes=0}})
		local usage=charts.series({{label="Route",result=result}},charts.modes[2]);assert.equal(100,usage.series[1].points[3].y)
	end)
	it("charts supplied costs without mixing units or inventing missing prices",function()
		local missing=copyTable(result);missing.costDistribution=nil;local different=copyTable(result);different.costCurrency="divine"
		local data=charts.series({{label='Route "A"',result=result},{label="Unknown",result=missing},{label="Other unit",result=different}},charts.modes[3])
		assert.equal(1,#data.series);assert.equal(2,#data.omitted);assert.equal("chaos",data.unit);assert.equal(40,charts.at(data.series[1].points,10).y)
		assert.is_truthy(charts.csv(data):find('"Route ""A""",2,10,1,10',1,true))
		local csv=charts.csv(data);assert.is_truthy(csv:find('"Success by spending","chaos",',1,true));assert.is_truthy(csv:find('Unknown: missing prices',1,true));assert.is_truthy(csv:find('Other unit: different price unit',1,true))
		local empty=charts.series({{label="Unknown",result=missing}},charts.modes[3]);assert.is_truthy(charts.csv(empty):find('Unknown: missing prices',1,true))
	end)
	it("explains uncharged transition failures on the chart and in its model notes",function()
		newBuild();main.popups={};local sim=require("Modules.CraftingSimulator");local raw="Rarity: NORMAL\nCobalt Jewel\nItem Level: 86"
		local input=sim.perform(raw,{method="alchemy"},104729).state;input.corrupted=true
		local run=sim.simulate(raw,{initialState=input,steps={{method="tainted_exalt"}},targets={},requirements={minAffixes=3}},{trials=40,maxActions=1,seed=1,forceFirstAction=true,prices={tainted_exalt=1},currency="chaos"})
		local failed=0;for _,count in pairs(run.transitionErrors) do failed=failed+count end;assert.is_true(failed>0)
		local routes={{label="Tainted jewel",result=run}};local data=charts.series(routes,charts.modes[3]);local notice="Tainted jewel: "..failed.." failed modeled transitions were not charged."
		local found=false;for _,warning in ipairs(data.warnings) do if warning:find(notice,1,true) then found=true end end;assert.is_true(found)
		local csv=charts.csv(data);assert.is_truthy(csv:find('"Success by spending","chaos",'..failed..',',1,true));assert.is_truthy(csv:find("failed modeled transitions were not charged",1,true))
		local controls=require("Classes.CraftingChartsControl").Open(routes);assert.matches("Failed transitions were not charged",controls.assumption.label());assert.is_true(controls.notes:IsEnabled());controls.notes:Click()
		local lines={};for _,row in ipairs(main.popups[1].controls.messages.list) do lines[#lines+1]=row[1] end
		assert.is_truthy(table.concat(lines," "):find("failed modeled transitions were not charged",1,true));main.popups={}
	end)
	it("returns complete trial distributions only when every executed currency is priced",function()
		newBuild();local sim=require("Modules.CraftingSimulator");local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86"
		local recipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=4}}
		local priced=sim.simulate(raw,recipe,{trials=10,maxActions=1,prices={alchemy=3},baseCost=2,currency="chaos"})
		assert.same({{cost=5,trials=10,successes=10}},priced.costDistribution)
		local missing=sim.simulate(raw,recipe,{trials=10,maxActions=1,retainSuccesses=2});assert.is_nil(missing.costDistribution);assert.is_nil(missing.retainedSuccesses[1].cost)
	end)
	it("retains individual costs when other successful trials used unpriced actions",function()
		newBuild();local sim=require("Modules.CraftingSimulator");local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86"
		local recipe={steps={{method="alchemy"},{method="chaos"}},targets={},requirements={minAffixes=5}}
		local result=sim.simulate(raw,recipe,{trials=100,maxActions=2,retainSuccesses=100,prices={alchemy=3},baseCost=2,currency="chaos",seed=3})
		assert.is_true(result.unpriced.chaos);assert.is_nil(result.meanCost);assert.is_nil(result.costDistribution)
		local priced,unpriced=0,0
		for _,item in ipairs(result.retainedSuccesses) do
			if item.actions==1 then assert.equal(5,item.cost);priced=priced+1
			else assert.equal(2,item.actions);assert.is_nil(item.cost);unpriced=unpriced+1 end
		end
		assert.is_true(priced>0);assert.is_true(unpriced>0)
	end)
end)
