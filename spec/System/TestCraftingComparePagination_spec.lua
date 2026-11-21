describe("Recipe comparison pagination",function()
 local sim=require("Modules.CraftingSimulator");local original;local ui
 before_each(function() newBuild();main.popups={};original=sim.simulate;ui=require("Modules.HeadlessUI").install({width=960,height=640}) end)
 after_each(function() sim.simulate=original;main.popups={};ui:restore() end)
 it("retains route prices across pages, compares all routes and pages the chart",function()
  local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local model=sim.model(raw);local seen={}
  sim.simulate=function(_,recipe,options)
   seen[#seen+1]={recipe=copyTable(recipe),prices=copyTable(options.actionPrices or {})}
   return {successChance=50,confidenceLow=25,confidenceHigh=75,meanActions=1,trials=2,transitionErrors={},warnings={},actionDistribution={{actions=1,trials=2,successes=1}}}
  end
  local c=require("Classes.CraftingCompareControl").Open(build,raw,model.initial,{}, {minAffixes=1},nil,{method="transmute"},nil,{budget=1,trials=2,seed=1,currency="chaos"})
  c.price1:SetText("11",true);c.addRoute:Click();c.route1:SetSel(1);c.price1:SetText("44",true)
  c.addRoute:Click();c.route2:SetSel(1);c.price2:SetText("55",true)
  c.previousPage:Click();assert.equal("11",c.price1.buf);c.nextPage:Click();assert.equal("44",c.price1.buf);assert.equal("55",c.price2.buf)
  c.remove1:Click();assert.equal("55",c.price1.buf)
  c.run:Click();local tasks=require("Modules.CraftingTasks");while tasks.job do tasks.tick(build) end
  assert.equal(4,#seen);assert.equal(11,seen[1].prices.transmute);assert.equal(55,seen[4].prices.transmute)
  assert.is_true(c.charts:IsEnabled());c.charts:Click();local chart=main.popups[1].controls
  assert.matches("Route 1",chart.legend1.label());assert.is_true(chart.nextPage:IsEnabled());chart.nextPage:Click();assert.matches("Route 4",chart.legend1.label())
  chart.copy:Click();assert.is_truthy(ui.clipboard:find('Route 1:',1,true));assert.is_truthy(ui.clipboard:find('Route 4:',1,true))
  main:ClosePopup();c.addRoute:Click();assert.is_false(c.charts:IsEnabled())
 end)
end)
