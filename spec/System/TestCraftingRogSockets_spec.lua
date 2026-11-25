describe("Rog socket offers",function()
 local sim=require("Modules.CraftingSimulator");local rog=require("Modules.CraftingRog")
 local raw="Rarity: NORMAL\nPlate Vest\nItem Level: 86\nSockets: R-G W-W"
 local function stream(seed) return function() seed=seed*48271%2147483647;return seed/2147483647 end end
 before_each(function() newBuild();main.popups={} end)
 after_each(function() main.popups={} end)
 it("samples the requested observed offer without modifying the starting item",function()
  local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="RARE";local before=copyTable(state)
  for _,op in ipairs({"socket_count","socket_links"}) do for _,rolls in ipairs({10,20,30,50,100}) do
   local action={method="rog_reroll",rogOperation=op,rogSocketRolls=rolls,artifactCost={grand=7}}
   local expected=op=="socket_count" and sim.bestJeweller(model,state,rolls,stream(73)) or sim.bestFusing(model,state,rolls,stream(73))
   local actual=sim.action(model,state,action,stream(73));assert.same(expected,actual);assert.same(before,state);sim.validateState(model,actual)
   assert.matches("socket",sim.actionWarnings(action,model)[1].message);assert.matches(tostring(rolls),sim.priceKey(action),1,true)
   assert.same({["Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction3_3"]=7},sim.components(action))
   local validated=sim.validateRecipe({steps={action},targets={},requirements={minQuality=0}});assert.equal(rolls,validated.steps[1].rogSocketRolls)
  end end
  local odds=sim.calculate(raw,{method="rog_reroll",rogOperation="socket_links",rogSocketRolls=10},{},state,{trials=5,requirements={links=4}})
  assert.is_truthy(odds.successChance);assert.is_truthy(odds.warnings)
  assert.has_error(function() rog.validate({rogOperation="socket_count",rogSocketRolls=9}) end)
  assert.has_error(function() rog.validate({rogOperation="socket_links",rogSocketRolls=10,rogSide="Prefix"}) end)
  assert.has_error(function() rog.validate({rogOperation="fill",rogSocketRolls=10}) end)
 end)
 it("enumerates best-of odds under the socket model",function()
  local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="RARE"
  local probabilities=require("Modules.CraftingSockets").jewellerProbabilities(model,state);local below=0
  for count,chance in ipairs(probabilities) do if count<5 then below=below+chance end end
  local action={method="rog_reroll",rogOperation="socket_count",rogSocketRolls=20}
  local result=sim.calculate(raw,action,{},state,{requirements={sockets=5}})
  assert.is_false(result.sampled);assert.matches("estimated socket model",result.exactFor,1,true)
  assert.is_true(math.abs(result.successChance-100*(1-below^20))<0.0000001)
  local total=0;for _,outcome in ipairs(result.outcomes) do total=total+outcome.chance end;assert.is_true(math.abs(total-100)<0.0000001)
  local linkBelow=0;for _,candidate in ipairs(require("Modules.CraftingSockets").fusingOutcomes(state)) do
   local groups={};local best=0;for _,group in ipairs(candidate.groups) do groups[group]=(groups[group] or 0)+1;best=math.max(best,groups[group]) end
   if best<3 then linkBelow=linkBelow+candidate.probability end
  end
  action.rogOperation="socket_links";action.rogSocketRolls=10
  result=sim.calculate(raw,action,{},state,{requirements={links=3}})
  assert.is_false(result.sampled);assert.is_true(math.abs(result.successChance-100*(1-linkBelow^10))<0.0000001)
  total=0;for _,outcome in ipairs(result.outcomes) do total=total+outcome.chance end;assert.is_true(math.abs(total-100)<0.0000001)
 end)
 it("preserves rerolls, price and routes while editing a saved recipe",function()
  local recipe={steps={{method="rog_reroll",rogOperation="socket_count",rogSocketRolls=20,artifactCost={grand=7},maxAttempts=4,untilRequirements={sockets=6},onFailureAction="stop"}},targets={},requirements={sockets=6}}
  local saved;local editor=require("Classes.CraftingRecipeControl").Open(recipe,{method="alchemy"},function(value) saved=value end,sim.model(raw))
  editor.editRog:Click();local popup=main.popups[1].controls;assert.equal(20,popup.socketRolls:GetSelValueByKey("val"))
  popup.operation:SelByValue("socket_links","val");popup.socketRolls:SelByValue(30,"val");popup.keep:Click();editor.keep:Click()
  assert.equal("socket_links",saved.steps[1].rogOperation);assert.equal(30,saved.steps[1].rogSocketRolls)
  assert.equal(7,saved.steps[1].artifactCost.grand);assert.equal(4,saved.steps[1].maxAttempts);assert.equal("stop",saved.steps[1].onFailureAction)
 end)
 it("saves and reopens the observed offer in its settings",function()
  local saved;local c=require("Classes.CraftingRogControl").Open(nil,function(action) saved=action end)
  c.operation:SelByValue("socket_links","val");c.socketRolls:SelByValue(30,"val");c.grand:SetText("7",true);c.keep:Click()
  assert.equal("socket_links",saved.rogOperation);assert.equal(30,saved.rogSocketRolls);assert.equal(7,saved.artifactCost.grand)
  c=require("Classes.CraftingRogControl").Open(saved,function() end);assert.equal(30,c.socketRolls:GetSelValueByKey("val"));assert.equal("socket_links",c.operation:GetSelValueByKey("val"));main:ClosePopup()
 end)
end)
