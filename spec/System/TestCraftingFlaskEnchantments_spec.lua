describe("Utility flask enchantments",function()
 local sim=require("Modules.CraftingSimulator");local flask=require("Modules.CraftingFlaskEnchants")
 local raw="Rarity: NORMAL\nQuicksilver Flask\nItem Level: 86"
 before_each(function() newBuild() end)
 it("round trips every modeled enchantment through native item text",function()
  local model=sim.model(raw)
  for group,pool in pairs(flask.data().pools) do
   local method=group=="INSTILLING" and "instilling" or "enkindling";local total=0;for _,entry in ipairs(pool) do total=total+entry.weight end
   local before=0
   for _,entry in ipairs(pool) do
    local calls=0;local state
    if entry.weight>0 then state=sim.action(model,model.initial,{method=method},function() calls=calls+1;return calls==1 and (before+entry.weight/2)/total or 0.5 end)
    else state=copyTable(model.initial);state.flaskEnchant={id=entry.id} end
    before=before+entry.weight;assert.equal(entry.id,state.flaskEnchant.id)
    assert.same(state.flaskEnchant,sim.validateState(model,state).flaskEnchant)
    local item=sim.toItem(model,state);local reopened=sim.model(item.raw)
    assert.same(state.flaskEnchant,reopened.initial.flaskEnchant)
    assert.is_true(sim.matches(reopened.initial,{},nil,reopened,{flaskEnchant=entry.id}))
   end
  end
 end)
 it("replaces a flask enchantment, retains affixes and rejects ineligible items",function()
  local model=sim.model(raw);local a=sim.action(model,model.initial,{method="enkindling"},function() return 0 end)
  local b=sim.action(model,a,{method="instilling"},function() return 0 end)
  assert.equal("FlaskEnchantmentInjectorAdjacentFlasks___",b.flaskEnchant.id);assert.same(a.affixes,b.affixes)
  local item=sim.toItem(model,b);assert.equal(1,#item.enchantModLines)
	  local swapped,count=(sim.toItem(model,a).raw.."\n"):gsub("{enchant}(.-)\n{enchant}(.-)\n","{enchant}%2\n{enchant}%1\n")
	  assert.equal(1,count);assert.same(a.flaskEnchant,sim.model(swapped).initial.flaskEnchant)
  for _,text in ipairs({"Rarity: NORMAL\nGlassblower's Bauble\nItem Level: 86","Rarity: NORMAL\nDivine Life Flask\nItem Level: 86","Rarity: NORMAL\nIron Hat\nItem Level: 86"}) do
   local ok,other=pcall(sim.model,text);if ok then local available=require("Modules.CraftingWorkbench").available("instilling",other.initial,other);assert.is_false(available);assert.has_error(function() sim.action(other,other.initial,{method="instilling"},function() return 0 end) end) end
  end
  local corrupted=copyTable(model.initial);corrupted.corrupted=true;assert.has_error(function() sim.action(model,corrupted,{method="enkindling"},function() return 0 end) end)
 end)
 it("uses the specified enchantment as a recipe target and prices its currency",function()
  local action={method="enkindling"};local result=sim.perform(raw,action,123);local requirement={flaskEnchant=result.state.flaskEnchant.id}
  assert.is_true(sim.matches(result.state,{},nil,sim.model(raw),requirement));assert.same({enkindling=1},sim.components(action))
  local odds=sim.calculate(raw,action,{},nil,{requirements=requirement});assert.is_true(odds.successChance>0);assert.is_true(odds.sampled)
	  local minGoal={flaskEnchant=result.state.flaskEnchant.id,flaskEnchantMin=result.state.flaskEnchant.roll}
	  assert.is_true(sim.matches(result.state,{},nil,sim.model(raw),minGoal));minGoal.flaskEnchantMin=result.state.flaskEnchant.roll+1
	  assert.is_false(sim.matches(result.state,{},nil,sim.model(raw),minGoal))
	  assert.has_error(function() sim.validateRecipe({steps={action},targets={},requirements={flaskEnchant="FlaskEnchantmentInjectorOnFullCharges__",flaskEnchantMin=1}}) end)
  assert.is_not_nil(require("Modules.CraftingWorkbench").icon("enkindling"));assert.is_not_nil(require("Modules.CraftingWorkbench").icon("instilling"))
  local run=require("Modules.CraftingInventory").run(result.state);run.method="enkindling";run.requirements=requirement
  build.savers.CraftingProjects:Upsert({id="flask-enchant",title="Flask",slot="Flask 1",startingItem=raw,goals={},steps={},run=run,nativeRecipe={steps={{method="enkindling"}},targets={},requirements=requirement}})
  local xml=build:SaveDB("Flask");loadBuildFromXML(xml,"Flask")
  local project=build.savers.CraftingProjects.projects[1];assert.same(result.state.flaskEnchant,project.run.state.flaskEnchant);assert.equal(requirement.flaskEnchant,project.nativeRecipe.requirements.flaskEnchant)
 end)
 it("exposes the complete pinned flask enchantment catalogue",function()
  local entries=sim.catalog(raw,"",100).flaskEnchants;assert.equal(21,#entries)
  local dead=0;for _,entry in ipairs(entries) do if not entry.rollable then dead=dead+1;assert.equal("FlaskEnchantmentInjectorOnGuardSkillExpired",entry.id) end end
  assert.equal(1,dead);assert.equal(1,#sim.catalog(raw,"OnFullCharges",100).flaskEnchants)
 end)
 it("lets the workbench select a flask enchantment goal",function()
  local selected
  local controls=require("Classes.CraftingTargetControl").Open({},nil,nil,function(_,requirements) selected=requirements end,0,"Quicksilver Flask")
  local id="FlaskEnchantmentSealIncreasedEffect_";controls.harvestEnchant:SelByValue(id,"val");controls.minAbyssSockets:SetText("68");controls.keep:Click()
  assert.equal(id,selected.flaskEnchant);assert.equal(68,selected.flaskEnchantMin)
  local model=sim.model(raw);local option=require("Modules.CraftingWorkbench")
  assert.is_true(option.available("instilling",model.initial,model));assert.is_true(option.available("enkindling",model.initial,model))
  main.popups={}
 end)
end)
