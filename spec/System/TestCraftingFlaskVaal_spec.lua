describe("Flask Vaal quality",function()
 local sim=require("Modules.CraftingSimulator");local check=require("Modules.CraftingAvailability").check
 local raw="Rarity: NORMAL\nSmall Life Flask\nItem Level: 86\nQuality: 30"
 it("models each documented quality change while preserving the item",function()
  local model=sim.model(raw);assert.is_true(check("vaal",model.initial,model))
  for delta=-10,10 do
   local result=sim.action(model,model.initial,{method="vaal"},function() return (delta+10+0.5)/21 end)
   assert.equal(30+delta,result.quality);assert.is_true(result.corrupted);assert.same(model.initial.affixes,result.affixes)
   assert.is_false(check("vaal",result,model));assert.equal(result.quality,sim.model(sim.toItem(model,result).raw).initial.quality)
   assert.same(result,sim.validateState(model,result))
  end
 end)
 it("clamps at zero and accepts forty only on corrupted flasks",function()
  local model=sim.model(raw);local input=copyTable(model.initial);input.quality=0
  assert.equal(0,sim.action(model,input,{method="vaal"},function() return 0 end).quality)
  input.quality=40;assert.is_false(pcall(sim.validateState,model,input));input.corrupted=true;assert.equal(40,sim.validateState(model,input).quality)
  local helmet=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86");local invalid=copyTable(helmet.initial);invalid.quality=40;invalid.corrupted=true
  assert.is_false(pcall(sim.validateState,helmet,invalid))
 end)
 it("saves and resumes a corrupted forty-quality flask",function()
  newBuild();local model=sim.model(raw);local state=copyTable(model.initial);state.quality=40;state.corrupted=true
  local project={id="flask-vaal",title="Flask quality",slot="Flask 1",startingItem=raw,goals={},steps={}}
  local inventory=require("Modules.CraftingInventory");project.inventory={inventory.capture(project,state,"Corrupted flask")}
  build.savers.CraftingProjects:Upsert(project);local xml=build:SaveDB("Flask quality");loadBuildFromXML(xml,"Flask quality")
  local restored=build.savers.CraftingProjects.projects[1].inventory[1];assert.equal(40,restored.state.quality);assert.is_true(restored.state.corrupted)
  assert.equal(40,inventory.project(restored).run.state.quality)
 end)
 it("uses one composed flask sprite in item cards",function()
  local art=require("Modules.CraftingWorkbench");local model=sim.model(raw);local path,width,height=art.itemArt(model.item)
  local w,h,sprite=art.artDimensions(model.item,width,height,96);assert.is_true(sprite);assert.equal(48,w);assert.equal(96,h);assert.is_string(path)
  local tincture=sim.model("Rarity: NORMAL\nPrismatic Tincture\nItem Level: 86");local _,tw,th=art.itemArt(tincture.item)
  local _,_,split=art.artDimensions(tincture.item,tw,th,96);assert.is_false(split)
 end)
 it("exposes the assumption in simulation, inspection and workbench",function()
  local model=sim.model(raw);local result=sim.perform(raw,{method="vaal"},7)
  assert.is_true(result.state.corrupted);assert.equal("flask_vaal_weights",result.warnings[1].code)
  assert.matches("assumed",require("Modules.CraftingWorkbench").hint("vaal",model.initial,model))
  local catalog=sim.catalog(raw,"",5);assert.equal("flask_vaal_weights",catalog.methodWarnings.vaal[1].code)
  local recipe={steps={{method="vaal"}},targets={},requirements={minQuality=40,corrupted=true}};assert.is_truthy(sim.validateRecipe(recipe))
  local outcome=sim.simulate(raw,recipe,{trials=10,maxActions=1,seed=1});assert.equal("flask_vaal_weights",outcome.warnings[1].code)
  local odds=sim.calculate(raw,{method="vaal"},{},nil,{requirements={minQuality=40,corrupted=true},trials=30,seed=1});assert.equal("flask_vaal_weights",odds.warnings[1].code)
  assert.is_false(odds.sampled);assert.equal(21,#odds.outcomes);assert.near(100/21,odds.successChance,0.00001)
  local zero=copyTable(model.initial);zero.quality=0;local clamped=sim.calculate(raw,{method="vaal"},{},zero,{requirements={minQuality=1}})
  assert.equal(11,clamped.outcomes[1].weight);assert.near(1000/21,clamped.successChance,0.00001)
 end)
end)
