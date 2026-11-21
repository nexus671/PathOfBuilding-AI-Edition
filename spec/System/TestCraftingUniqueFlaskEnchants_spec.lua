describe("Unique utility flask enchantments",function()
 local sim=require("Modules.CraftingSimulator");local unique=require("Modules.CraftingUniqueQuality");local flask=require("Modules.CraftingFlaskEnchants")
 local raw="Rarity: UNIQUE\nTaste of Hate\nSapphire Flask\nItem Level: 86\nQuality: 20\n(10-15)% increased Cold Damage\n+17% to Cold Resistance"
 before_each(function() newBuild() end)
 it("preserves the original unique modifiers through both flask currencies",function()
  for _,method in ipairs({"instilling","enkindling"}) do
   local result=sim.perform(raw,{method=method},123);assert.equal(method,result.priceKey);assert.same({[method]=1},result.components)
   assert.is_truthy(result.flaskEnchant);assert.is_truthy(result.itemText:find("(10-15)% increased Cold Damage",1,true));assert.is_truthy(result.itemText:find("+17% to Cold Resistance",1,true))
   assert.same(result.flaskEnchant,flask.identify(unique.inspect(result.itemText)));assert.is_true(unique.matches(result.itemText,{flaskEnchant=result.flaskEnchant.id}))
  end
 end)
 it("replaces tagged enchants in PoB and game-copied text without dropping other lines",function()
  local cases={
   "Rarity: UNIQUE\nTaste of Hate\nSapphire Flask\nItem Level: 86\nImplicits: 1\n{enchant}Used when Charges reach full\n+17% to Cold Resistance",
	   "Rarity: UNIQUE\nTaste of Hate\nSapphire Flask\nItem Level: 86\nImplicits: 2\n{enchant}{range:0.5}(60-70)% increased effect\n{enchant}Gains no Charges during Effect\n+17% to Cold Resistance",
   "Item Class: Utility Flasks\r\nRarity: Unique\r\nTaste of Hate\r\nSapphire Flask\r\n--------\r\nItem Level: 86\r\n--------\r\nUsed when Charges reach full (enchant)\r\n--------\r\n+17% to Cold Resistance\r\n"}
  for _,source in ipairs(cases) do local result=unique.flaskEnchant(source,"enkindling",123);assert.is_truthy(result.itemText:find("+17% to Cold Resistance",1,true));assert.is_nil(result.itemText:find("Used when Charges reach full",1,true));assert.same(result.flaskEnchant,flask.identify(unique.inspect(result.itemText))) end
	  local implicit="Rarity: UNIQUE\nTaste of Hate\nSapphire Flask\nItem Level: 86\nImplicits: 1\n+40% to Cold Resistance\n+17% to Cold Resistance"
	  local withEnchant=unique.flaskEnchant(implicit,"enkindling",123);assert.matches("Implicits: 3",withEnchant.itemText,1,true);assert.is_truthy(withEnchant.itemText:find("+40% to Cold Resistance",1,true))
 end)
 it("simulates an enchantment goal and exposes the currencies to MCP",function()
  local catalog=sim.catalog(raw,"",100);assert.equal(21,#catalog.flaskEnchants);local seen={};for _,a in ipairs(catalog.uniqueActions) do seen[a.method]=a end;assert.is_true(seen.enkindling.available);assert.is_true(seen.instilling.available)
  local crafted=sim.perform(raw,{method="enkindling"},123);local requirements={flaskEnchant=crafted.flaskEnchant.id,flaskEnchantMin=crafted.flaskEnchant.roll}
  local recipe={steps={{method="enkindling",maxAttempts=8,untilRequirements=requirements}},targets={},requirements=requirements}
  local result=sim.simulate(raw,recipe,{trials=10,maxActions=8,seed=3});assert.equal(10,result.trials);assert.equal(0,result.failedTransitionTrials)
	  local warned=false;for _,warning in ipairs(result.warnings) do if warning.code=="flask_enchant_assumptions" then warned=true end end;assert.is_true(warned)
  local resultOdds=sim.calculate(raw,{method="enkindling"},{},nil,{requirements=requirements,trials=10});assert.is_true(resultOdds.sampled)
  assert.has_error(function() sim.perform(raw.."\nCorrupted",{method="enkindling"},123) end)
  assert.has_error(function() sim.perform("Rarity: UNIQUE\nKaom's Heart\nGlorious Plate\nItem Level: 86",{method="instilling"},123) end)
 end)
 it("applies a chosen bench enchantment to a unique and calculates the exact result",function()
  local action={method="bench_flask_enchant",enchantId="FlaskEnchantmentInjectorOnFullCharges__"}
  local result=sim.perform(raw,action,123);assert.equal(action.enchantId,result.flaskEnchant.id)
  assert.same({["Metadata/Items/Currency/CurrencyInstillingOrb"]=5,["Metadata/Items/Currency/CurrencyFlaskQuality"]=5},result.components)
  assert.is_truthy(result.itemText:find("+17% to Cold Resistance",1,true))
  local goal={flaskEnchant=action.enchantId};local odds=sim.calculate(raw,action,{},nil,{requirements=goal})
  assert.is_false(odds.sampled);assert.equal(100,odds.successChance)
  local run=sim.simulate(raw,{steps={action},targets={},requirements=goal},{trials=1,maxActions=1,forceFirstAction=true})
  assert.is_true(run.sampleSuccess);assert.equal(0,run.failedTransitionTrials)
  assert.has_error(function() sim.perform(raw,{method="bench_flask_enchant",enchantId="FlaskEnchantmentInjectorOnGuardSkillExpired"},123) end)
 end)
 it("keeps preview actions in a unique crafting guide and supports undo",function()
  local project={id="unique-flask-enchant",title="Taste",slot="Flask 1",startingItem=raw,goals={},steps={}};build.savers.CraftingProjects:Upsert(project)
  local c=require("Classes.CraftingUniqueQualityControl").Open(build,project);assert.is_true(c.enkindling:IsEnabled());c.enkindling:Click();assert.is_true(c.undo:IsEnabled());c.undo:Click();assert.is_true(c.redo:IsEnabled());c.redo:Click();c.guide:Click()
  local saved=build.savers.CraftingProjects.projects[1];assert.equal("enkindling",saved.steps[1].uniqueCraft.method);assert.is_truthy(saved.targetItem:find("{enchant}",1,true))
	  assert.is_true(c.recipe:IsEnabled());c.recipe:Click();saved=build.savers.CraftingProjects.projects[1];assert.equal("enkindling",saved.nativeRecipe.steps[1].method);assert.is_truthy(saved.nativeRecipe.requirements.flaskEnchant);assert.is_truthy(saved.nativeRecipe.requirements.flaskEnchantMin)
	  local xml=build:SaveDB("Unique flask");loadBuildFromXML(xml,"Unique flask");saved=build.savers.CraftingProjects.projects[1];assert.equal("enkindling",saved.nativeRecipe.steps[1].method);assert.equal("enkindling",saved.steps[1].uniqueCraft.method)
  local p=require("Modules.LootFilters").profile("unique-flask-filter","Flask");local rules=require("Modules.LootFilters").generate(build,p);local found=false;for _,rule in ipairs(rules) do if rule.title=="Enkindling Orb" then found=true end end;assert.is_true(found)
 end)
 it("keeps a chosen bench enchantment in the unique guide, recipe and filter",function()
  local project={id="unique-flask-bench",title="Taste",slot="Flask 1",startingItem=raw,goals={},steps={}};build.savers.CraftingProjects:Upsert(project)
  local c=require("Classes.CraftingUniqueQualityControl").Open(build,project);assert.is_true(c.flaskBench:IsEnabled());c.flaskBench:Click()
  local picker=main.popups[1].controls;local chosen=picker.option:GetSelValue().action.enchantId;picker.apply:Click()
  assert.is_true(c.undo:IsEnabled());c.undo:Click();c.redo:Click();c.guide:Click()
  local saved=build.savers.CraftingProjects.projects[1];assert.equal(chosen,saved.steps[1].uniqueCraft.enchantId)
  assert.is_true(c.recipe:IsEnabled());c.recipe:Click();saved=build.savers.CraftingProjects.projects[1]
  assert.equal(chosen,saved.nativeRecipe.steps[1].enchantId);assert.equal(chosen,saved.nativeRecipe.requirements.flaskEnchant)
  local xml=build:SaveDB("Unique flask bench");loadBuildFromXML(xml,"Unique flask bench");saved=build.savers.CraftingProjects.projects[1]
  assert.equal(chosen,saved.steps[1].uniqueCraft.enchantId);assert.equal(chosen,saved.nativeRecipe.steps[1].enchantId)
  local p=require("Modules.LootFilters").profile("unique-flask-bench-filter","Flask");local rules=require("Modules.LootFilters").generate(build,p);local found={}
  for _,rule in ipairs(rules) do found[rule.title]=true end
  assert.is_true(found["Instilling Orb"]);assert.is_true(found["Glassblower's Bauble"]);main.popups={}
 end)
end)
