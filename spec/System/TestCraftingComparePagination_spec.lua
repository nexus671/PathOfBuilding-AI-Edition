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
 it("compares the chosen Essence and Harvest variants without substituting the first option",function()
  local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local model=sim.model(raw)
  local state=sim.perform(raw,{method="alchemy"},1).state;local essences=sim.actionOptions(model,state,"essence");local harvest=sim.actionOptions(model,state,"harvest_reforge")
  assert.is_true(#essences>=2);assert.is_true(#harvest>=1)
  local selected=copyTable(essences[2].action);local seen={}
  sim.simulate=function(_,recipe,options)
   seen[#seen+1]={action=copyTable(recipe.steps[1]),prices=copyTable(options.actionPrices or {})}
   return {successChance=50,confidenceLow=25,confidenceHigh=75,meanActions=1,trials=2,transitionErrors={},warnings={},actionDistribution={{actions=1,trials=2,successes=1}}}
  end
  local c=require("Classes.CraftingCompareControl").Open(build,raw,state,{}, {minAffixes=1},nil,selected,nil,{budget=1,trials=2,seed=1,currency="chaos"})
  assert.is_truthy(c.route1.list[1].label:find(essences[2].label,1,true))
  local first,second,reforge
  for index,entry in ipairs(c.route1.list) do
   if entry.label==essences[1].label then first=index end
   if entry.label==essences[2].label then second=index end
   if entry.label==require("Modules.CraftingWorkbench").actionLabel(harvest[1].action,model) then reforge=index end
  end
  assert.is_not_nil(first);assert.is_not_nil(second);assert.is_not_nil(reforge)
  c.route1:SetSel(first);c.price1:SetText("11",true);c.route2:SetSel(second);c.price2:SetText("22",true);c.route3:SetSel(reforge);c.price3:SetText("33",true)
  c.run:Click();local tasks=require("Modules.CraftingTasks");while tasks.job do tasks.tick(build) end
  assert.equal(essences[1].action.essenceId,seen[1].action.essenceId);assert.equal(essences[2].action.essenceId,seen[2].action.essenceId)
  assert.equal(harvest[1].action.tag,seen[3].action.tag);assert.equal(11,seen[1].prices[sim.priceKey(essences[1].action)]);assert.equal(22,seen[2].prices[sim.priceKey(essences[2].action)]);assert.equal(33,seen[3].prices[sim.priceKey(harvest[1].action)])
  local lines={};for _,row in ipairs(c.results.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;local text=table.concat(lines," ")
  assert.is_truthy(text:find(essences[1].label,1,true));assert.is_truthy(text:find(essences[2].label,1,true))
 end)

 it("creates independent multi-step comparison recipes without changing the saved recipe",function()
  local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local model=sim.model(raw);local saved={steps={{method="alchemy"}},targets={}};local seen={}
  sim.simulate=function(_,recipe,options)
   seen[#seen+1]={recipe=copyTable(recipe),prices=copyTable(options.actionPrices or {})}
   return {successChance=50,confidenceLow=25,confidenceHigh=75,meanActions=1,trials=2,transitionErrors={},warnings={},actionDistribution={{actions=1,trials=2,successes=1}}}
  end
  local c=require("Classes.CraftingCompareControl").Open(build,raw,model.initial,{}, {minAffixes=1},nil,{method="transmute"},saved,{budget=2,trials=2,seed=1,currency="chaos"})
  c.price1:SetText("11",true);c.edit1:Click();local edit=main.popups[1].controls;edit.add:Click();edit.keep:Click()
  assert.matches("Custom recipe 1",c.route1:GetSelValue().label);assert.is_false(c.price1:IsEnabled())
  c.edit2:Click();edit=main.popups[1].controls;edit.add:Click();edit.keep:Click()
  assert.matches("Custom recipe 2",c.route2:GetSelValue().label);assert.equal(1,#saved.steps)
  c.addRoute:Click();c.previousPage:Click();assert.matches("Custom recipe 1",c.route1:GetSelValue().label);assert.matches("Custom recipe 2",c.route2:GetSelValue().label)
  c.run:Click();local tasks=require("Modules.CraftingTasks");while tasks.job do tasks.tick(build) end
  assert.equal(4,#seen);assert.equal(2,#seen[1].recipe.steps);assert.equal("transmute",seen[1].recipe.steps[1].method);assert.equal(2,#seen[2].recipe.steps);assert.equal("alchemy",seen[2].recipe.steps[1].method);assert.equal("transmute",seen[2].recipe.steps[2].method)
  assert.is_nil(next(seen[1].prices));assert.is_nil(next(seen[2].prices))
 end)

 it("adds the newly kept recipe to comparisons that started without one",function()
  local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local model=sim.model(raw);local kept
  local settings={budget=1,trials=2,seed=1,currency="chaos",hasSavedRecipe=function() return kept~=nil end,keepRecipe=function(recipe) kept=copyTable(recipe) end}
  local c=require("Classes.CraftingCompareControl").Open(build,raw,model.initial,{}, {minAffixes=1},nil,{method="transmute"},nil,settings)
  c.keep1:Click();assert.equal("Recipe kept",main.popups[1].title);main:ClosePopup();assert.equal("transmute",kept.steps[1].method)
  local savedIndex;for index,entry in ipairs(c.route2.list) do if entry.label=="Saved recipe" then savedIndex=index end end
  assert.is_not_nil(savedIndex);c.route2:SetSel(savedIndex);c.edit2:Click();assert.equal(1,#main.popups[1].controls.graph.list);main:ClosePopup()
  c.keep1:Click();assert.equal("Replace saved recipe",main.popups[1].title);main:ClosePopup()
 end)

end)
