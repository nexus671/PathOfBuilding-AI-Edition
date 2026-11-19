-- cspell:ignore unproven
 describe("Crafting legacy roll provenance",function()
 local sim=require("Modules.CraftingSimulator")
 local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86"
 local function legacy(base)
  local model=sim.model("Rarity: NORMAL\n"..base.."\nItem Level: 86")
  local state=copyTable(model.initial);state.rarity="MAGIC";state.affixes={{id="IncreasedLife2",range=5}}
  return model,state,sim.toItem(model,state).raw
 end
 before_each(function() newBuild() end)
 it("rejects unproven rolls and preserves a matching legacy source",function()
  local model,state,source=legacy("Iron Hat")
  assert.has_error(function() sim.validateState(model,state) end)
  state.affixes[1].legacySource=source;assert.same(state.affixes,sim.validateState(model,state).affixes)
  local changed=copyTable(state);changed.affixes[1].range=4;assert.has_error(function() sim.validateState(model,changed) end)
  local imported=sim.model(source);assert.same(imported.initial.affixes,sim.validateState(imported,imported.initial).affixes)
  local _,_,wrong=legacy("Plate Vest");local mismatch=copyTable(state);mismatch.affixes[1].legacySource=wrong
  assert.has_error(function() sim.validateState(model,mismatch) end)
 end)
 it("does not use an in-range roll to justify an out-of-range roll",function()
  local model=sim.model(raw);local valid=copyTable(model.initial);valid.rarity="MAGIC";valid.affixes={{id="IncreasedLife2",range=1}}
  local source=sim.toItem(model,valid).raw;local changed=copyTable(valid);changed.affixes[1].range=1.0004;changed.affixes[1].legacySource=source
  assert.has_error(function() sim.validateState(model,changed) end)
  for _,range in ipairs({1.0004,-0.0004}) do
   local old=copyTable(valid);old.affixes[1].range=range
   local saved=require("Modules.CraftingCheckpoint").validate(raw,require("Modules.CraftingInventory").run(old)).state
   assert.equal(range,saved.affixes[1].range);assert.is_truthy(sim.validateState(model,saved))
  end
 end)
 it("checks each component of a multi-value legacy roll",function()
  local model=sim.model("Rarity: NORMAL\nRusted Sword\nItem Level: 86")
  local state=copyTable(model.initial);state.rarity="MAGIC";state.affixes={{id="LocalAddedChaosDamage1",range={1,1.5}}}
  local source=sim.toItem(model,state).raw;state.affixes[1].legacySource=source
  assert.is_truthy(sim.validateState(model,state))
  local changed=copyTable(state);changed.affixes[1].range={1.0004,1.5}
  assert.has_error(function() sim.validateState(model,changed) end)
  changed.affixes[1].legacySource=nil
  local saved=require("Modules.CraftingCheckpoint").validate("Rarity: NORMAL\nRusted Sword\nItem Level: 86",require("Modules.CraftingInventory").run(changed)).state
  assert.is_truthy(sim.validateState(model,saved));assert.same({1.0004,1.5},saved.affixes[1].range)
 end)
 it("checks legacy rolls inside an imprint before they can be restored",function()
  local model,state,source=legacy("Iron Hat");local imprint=copyTable(state);imprint.origin=model.initial.origin
  local current=copyTable(model.initial);current.rarity="MAGIC";current.imprint=imprint
  assert.has_error(function() sim.validateState(model,current) end)
  current.imprint.affixes[1].legacySource=source;assert.is_truthy(sim.validateState(model,current))
  local old=copyTable(current);old.imprint.affixes[1].legacySource=nil
  local restored=require("Modules.CraftingCheckpoint").validate(raw,require("Modules.CraftingInventory").run(old)).state
  assert.is_truthy(restored.imprint.affixes[1].legacySource);assert.is_truthy(sim.validateState(model,restored))
 end)
 it("migrates older checkpoints without changing their retained values",function()
  local model,state=legacy("Iron Hat")
  local restored=require("Modules.CraftingCheckpoint").validate(raw,require("Modules.CraftingInventory").run(state))
  assert.equal(5,restored.state.affixes[1].range);assert.is_truthy(restored.state.affixes[1].legacySource)
  assert.is_truthy(sim.validateState(model,restored.state))
 end)
 it("migrates an older checkpoint with a legacy Light Radius modifier",function()
  local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="MAGIC"
  state.affixes={{id="LightRadiusAndAccuracy3",range=0.5,legacyLightRadius=true}}
  assert.has_error(function() sim.validateState(model,state) end)
  local saved=require("Modules.CraftingCheckpoint").validate(raw,require("Modules.CraftingInventory").run(state)).state
  assert.is_truthy(saved.affixes[1].legacySource);assert.is_truthy(sim.validateState(model,saved))
  local invalid=copyTable(saved);invalid.affixes[1].legacySource="invalid item";assert.has_error(function() sim.validateState(model,invalid) end)
 end)
 it("keeps donor legacy rolls through either unpredictable host and a checkpoint",function()
  local model=sim.model(raw);local _,_,donor=legacy("Cone Helmet");local hosts={}
  for seed=1,500 do
   local ok,out=pcall(sim.perform,raw,{method="recombine",donorItem=donor},seed)
   if ok then for _,entry in ipairs(out.state.affixes) do if entry.id=="IncreasedLife2" then
    assert.is_truthy(entry.legacySource);local checked=sim.validateState(model,out.state);hosts[sim.toItem(model,checked).baseName]=true
    local saved=require("Modules.CraftingCheckpoint").validate(raw,require("Modules.CraftingInventory").run(checked)).state
    assert.is_truthy(sim.validateState(model,saved))
   end end end
   if hosts["Iron Hat"] and hosts["Cone Helmet"] then break end
  end
  assert.is_true(hosts["Iron Hat"]);assert.is_true(hosts["Cone Helmet"])
 end)
 it("retains legacy Light Radius rolls through either recombination base",function()
  local model=sim.model(raw);local donorModel=sim.model("Rarity: NORMAL\nCone Helmet\nItem Level: 86")
  local state=copyTable(donorModel.initial);state.rarity="MAGIC";state.affixes={{id="LightRadiusAndAccuracy3",range=0.5,legacyLightRadius=true}}
  local donor=sim.toItem(donorModel,state).raw;assert.is_true(sim.model(donor).initial.affixes[1].legacyLightRadius)
  local hosts={}
  for seed=1,500 do
   local ok,out=pcall(sim.perform,raw,{method="recombine",donorItem=donor},seed)
   if ok then for _,entry in ipairs(out.state.affixes) do if entry.legacyLightRadius then
    assert.is_truthy(entry.legacySource);local checked=sim.validateState(model,out.state);hosts[sim.toItem(model,checked).baseName]=true
    local saved=require("Modules.CraftingCheckpoint").validate(raw,require("Modules.CraftingInventory").run(checked)).state
    assert.is_truthy(sim.validateState(model,saved))
   end end end
   if hosts["Iron Hat"] and hosts["Cone Helmet"] then break end
  end
  assert.is_true(hosts["Iron Hat"]);assert.is_true(hosts["Cone Helmet"])
 end)
 it("preserves legacy influenced rolls transferred by an Awakener Orb",function()
  local source="Rarity: NORMAL\nGlorious Plate\nItem Level: 86";local model=sim.model(source)
  local blank=copyTable(model.initial);blank.rarity="RARE"
  local target=sim.perform(source,{method="influence_exalt",influence="shaper"},43,blank).state
  local donor=sim.perform(source,{method="influence_exalt",influence="elder"},44,blank).state
  donor.affixes[1].range=5;local donorText=sim.toItem(model,donor).raw
  local result=sim.perform(source,{method="awakener",donorItem=donorText},1,target);local found=false
  for _,entry in ipairs(result.state.affixes) do if entry.range==5 then assert.is_truthy(entry.legacySource);found=true end end
  assert.is_true(found);local checked=sim.validateState(model,result.state)
  local saved=require("Modules.CraftingCheckpoint").validate(source,require("Modules.CraftingInventory").run(checked)).state
  assert.is_truthy(sim.validateState(model,saved))
 end)
 it("keeps donor legacy rolls through either predictable host",function()
  local model=sim.model(raw);local _,_,donor=legacy("Cone Helmet")
  local input=copyTable(model.initial);input.rarity="MAGIC";input.affixes={{id="FireResist1",range=0.5}}
  local craft={method="recombine_predictable",donorItem=donor,selectedMods={left={"FireResist1"},right={"IncreasedLife2"}},reportedSuccessChance=40}
  local targets={{anyOf={"FireResist1"}},{anyOf={"IncreasedLife2"}}};local odds=sim.calculate(raw,craft,targets,input)
  local picks={odds.outcomes[1].chance/200,(odds.outcomes[1].chance+odds.outcomes[2].chance/2)/100};local hosts={}
  for _,pick in ipairs(picks) do
   local result=sim.action(model,input,craft,function() return pick end);assert.is_falsy(result.destroyed)
   local checked=sim.validateState(model,result);hosts[sim.toItem(model,checked).baseName]=true
   local saved=require("Modules.CraftingCheckpoint").validate(raw,require("Modules.CraftingInventory").run(checked)).state
   assert.is_truthy(sim.validateState(model,saved))
  end
  assert.is_true(hosts["Iron Hat"]);assert.is_true(hosts["Cone Helmet"])
 end)
end)
