describe("Mirror of Kalandra crafting",function()
 local sim=require("Modules.CraftingSimulator");local check=require("Modules.CraftingAvailability").check
 local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86\nQuality: 20\nSockets: R-G B"
 before_each(function() newBuild();main.popups={} end)
 it("returns the untouched original and a locked copy with preserved properties",function()
  local source=sim.perform(raw,{method="alchemy"},104729).state
  local before=copyTable(source);local result=sim.perform(raw,{method="mirror"},73,source)
  assert.same(before,source);assert.same(before,result.originalState);assert.is_true(result.state.mirrored)
  local copy=copyTable(result.state);copy.mirrored=before.mirrored;assert.same(before,copy)
  assert.matches("Mirrored",result.itemText,1,true);assert.not_matches("Mirrored",result.originalItemText,1,true)
  assert.is_false(check("exalt",result.state,sim.model(raw)));assert.has_error(function() sim.perform(raw,{method="exalt"},1,result.state) end)
  assert.same({mirror=1},sim.components({method="mirror"}));assert.equal("mirror",sim.priceKey({method="mirror"}))
  local key=require("Modules.CraftingPrices").key("mirror",sim.model(raw));assert.matches("CurrencyDuplicate",key,1,true)
  assert.matches("mirror_copy",result.warnings[1].code,1,true)
 end)
 it("runs a priced recipe to a mirrored target and preserves that target",function()
  local recipe={steps={{method="mirror"}},targets={},requirements={mirrored=true}}
  local result=sim.simulate(raw,recipe,{trials=2,maxActions=1,seed=1,currency="chaos",prices={mirror=100}})
  assert.equal(100,result.successChance);assert.equal(100,result.meanCost);assert.is_true(result.sampleState.mirrored)
  local kept;local target=require("Classes.CraftingTargetControl").Open({},nil,nil,function(_,conditions) kept=conditions end,nil,"Iron Hat")
  target.mirrored:SelByValue("Must be mirrored");target.keep:Click();assert.is_true(kept.mirrored);main.popups={}
 end)
 it("rejects corrupted, mirrored, destroyed and pending-unveil inputs",function()
  local model=sim.model(raw)
  for _,flag in ipairs({"corrupted","mirrored","destroyed"}) do
   local state=copyTable(model.initial);state[flag]=true;assert.is_false(check("mirror",state,model),flag)
   assert.has_error(function() sim.action(model,state,{method="mirror"},function() return 0.5 end) end)
  end
  local rare=sim.perform(raw,{method="alchemy"},104729).state;local pending=sim.perform(raw,{method="veiled_orb"},104729,rare).state
  assert.is_false(check("mirror",pending,model));assert.has_error(function() sim.action(model,pending,{method="mirror"},function() return 0.5 end) end)
  assert.has_error(function() sim.perform("Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86",{method="mirror"},1) end)
 end)
 it("keeps original in saved history and allows undo in the workbench",function()
  local project={id="mirror-workbench",title="Mirror helmet",slot="Helmet",startingItem=raw,goals={},steps={}}
  local controls=require("Classes.CraftingSimulatorControl").Open(build,project)
  controls.method:SelByValue("mirror","val");controls.method.selFunc();assert.is_true(controls.apply:IsEnabled())
  controls.apply:Click();assert.is_true(controls.undo:IsEnabled())
  local visible={};for _,row in ipairs(controls.itemMods.list) do visible[#visible+1]=StripEscapes(row[1] or "") end;assert.matches("Mirrored",table.concat(visible," "),1,true)
  local history=controls.history;history:Click();local changes={};for _,row in ipairs(main.popups[1].controls.changes.list) do changes[#changes+1]=StripEscapes(row[1] or "") end
  assert.matches("Mirrored: no -> yes",table.concat(changes," "),1,true);main:ClosePopup()
  controls.keepWorking:Click();local saver=build.savers.CraftingProjects;local saved
  for _,entry in ipairs(saver.projects) do if entry.id==project.id then saved=entry end end
  assert.is_true(saved.run.state.mirrored);assert.is_false(saved.run.history[1].mirrored);assert.equal("mirror",saved.run.actions[1].method)
  controls.undo:Click();assert.is_true(controls.apply:IsEnabled());main.popups={}
 end)
end)
