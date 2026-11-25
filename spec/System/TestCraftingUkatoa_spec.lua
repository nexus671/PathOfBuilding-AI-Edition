-- cspell:ignore Ukatoa
describe("Ukatoa's Ducat amulet crafting",function()
 local sim=require("Modules.CraftingSimulator")
 local raw="Rarity: NORMAL\nGold Amulet\nItem Level: 86"
 it("replaces an ordinary implicit and preserves the result in state and item text",function()
  local model=sim.model(raw);assert.is_true(require("Modules.CraftingAvailability").check("ducat_ukatoa",model.initial,model))
  for _,seed in ipairs({1,2,3,4,5,7,13,42}) do
   local result=sim.perform(raw,{method="ducat_ukatoa"},seed)
   assert.equal(1,#result.state.implicits);local implicit=result.state.implicits[1]
   assert.is_true(implicit.tier>=1 and implicit.tier<=4);assert.is_truthy(model.byId[implicit.id]);assert.is_truthy(sim.validateState(model,result.state))
   assert.is_true(sim.matches(result.state,{{scope="implicit",anyOf={implicit.id}}},nil,model))
   local item=sim.toItem(model,result.state);assert.is_true(item.raw:find("{exarch}",1,true)~=nil or item.raw:find("{eater}",1,true)~=nil)
   local reopened=sim.model(item.raw)
   assert.is_truthy(reopened.initial.implicits or reopened.unresolvedEldritch)
   local available=require("Modules.CraftingAvailability").check("ducat_ukatoa",result.state,model);assert.is_false(available)
   local warned=false;for _,warning in ipairs(result.warnings) do if warning.code=="ukatoa_assumptions" then warned=true end end;assert.is_true(warned)
  end
 end)
 it("rejects another item type and corrupted or already eldritch amulets",function()
  for _,text in ipairs({"Rarity: NORMAL\nIron Ring\nItem Level: 86",raw.."\nCorrupted"}) do
   local model=sim.model(text);assert.is_false(require("Modules.CraftingAvailability").check("ducat_ukatoa",model.initial,model))
   assert.is_false(pcall(sim.perform,text,{method="ducat_ukatoa"},1))
  end
 end)
end)

describe("Ukatoa special amulet cases",function()
 local sim=require("Modules.CraftingSimulator")
 it("replaces all synthesized implicits while keeping the synthesized marker",function()
  local raw="Rarity: NORMAL\nGold Amulet\nItem Level: 86\nImplicits: 2\n+10 to Strength\n+12 to Dexterity\nSynthesised Item"
  local model=sim.model(raw);assert.is_true(model.item.synthesised);assert.is_true(require("Modules.CraftingAvailability").check("ducat_ukatoa",model.initial,model))
  local result=sim.perform(raw,{method="ducat_ukatoa"},1);local item=sim.toItem(model,result.state)
  assert.is_true(item.synthesised);assert.equal(1,#item.implicitModLines);assert.is_nil(item.raw:find("+10 to Strength",1,true));assert.is_nil(item.raw:find("+12 to Dexterity",1,true))
 end)
 it("does not apply to fixed-implicit amulets or amulets without an implicit",function()
  for _,base in ipairs({"Simplex Amulet","Focused Amulet","Astrolabe Amulet"}) do
   local raw="Rarity: NORMAL\n"..base.."\nItem Level: 86";local model=sim.model(raw)
   local allowed,reason=require("Modules.CraftingAvailability").check("ducat_ukatoa",model.initial,model)
   assert.is_false(allowed);assert.matches("fixed implicit",reason)
   assert.has_error(function() sim.perform(raw,{method="ducat_ukatoa"},1) end)
  end
 end)
end)
describe("Ukatoa craft project persistence",function()
 it("keeps the outcome and recipe with its named price component",function()
  newBuild();local sim=require("Modules.CraftingSimulator");local raw="Rarity: NORMAL\nGold Amulet\nItem Level: 86";local model=sim.model(raw)
  local result=sim.perform(raw,{method="ducat_ukatoa"},42);local project={id="ukatoa",title="Eldritch amulet",slot="Amulet",startingItem=raw,goals={},steps={},nativeRecipe={steps={{method="ducat_ukatoa"}},targets={},requirements={minAffixes=0}}}
  local inventory=require("Modules.CraftingInventory");project.inventory={inventory.capture(project,result.state,"Eldritch amulet")};build.savers.CraftingProjects:Upsert(project)
  local xml=build:SaveDB("Ukatoa");loadBuildFromXML(xml,"Ukatoa")
  local saved=build.savers.CraftingProjects.projects[1];assert.equal("ducat_ukatoa",saved.nativeRecipe.steps[1].method);assert.same(result.state.implicits,saved.inventory[1].state.implicits)
  local parts=sim.components({method="ducat_ukatoa"},model.initial,model);assert.is_truthy(next(parts))
 end)
end)
