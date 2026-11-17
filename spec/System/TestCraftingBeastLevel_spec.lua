describe("Bestiary modifier level",function()
 local sim=require("Modules.CraftingSimulator")
 before_each(function() newBuild() end)
 it("uses the supplied beast level without changing item level and preserves the result",function()
  local raw="Rarity: NORMAL\nIron Hat\nItem Level: 20";local model=sim.model(raw);local initial=copyTable(model.initial);initial.rarity="RARE"
  local prefix;for _,entry in ipairs(model.mods) do if entry.mod.type=="Prefix" and entry.mod.level<=1 then prefix=entry.id;break end end
  assert.is_truthy(prefix);initial.affixes={{id=prefix,range=0.5}}
  local high;local original=sim.model(raw)
  for i=0,99 do local candidate=sim.action(model,initial,{method="beast_prefix_suffix",beastLevel=86},function() return i/100 end)
   local entry=candidate.affixes[1];if model.byId[entry.id].level>20 and not original.special[entry.id] then high=candidate;break end
  end
  assert.is_truthy(high);local id=high.affixes[1].id;assert.is_true(model.byId[id].level<=86)
  local validated=sim.validateState(sim.model(raw),high);local output=sim.toItem(model,validated).raw
  assert.is_truthy(output:find("Item Level: 20",1,true));local reopened=sim.model(output);assert.equal(20,reopened.item.itemLevel);assert.equal(id,reopened.initial.affixes[1].id)
  assert.has_no.errors(function() sim.validateTargetAvailability(sim.model(raw),{{anyOf={id}}},{{method="beast_prefix_suffix",beastLevel=86}}) end)
  for i=0,19 do local low=sim.action(model,initial,{method="beast_prefix_suffix",beastLevel=1},function() return i/20 end);assert.is_true(model.byId[low.affixes[1].id].level<=1) end
 end)
 it("applies both directions at lower and higher beast levels and rejects invalid levels",function()
  for _,case in ipairs({{method="beast_prefix_suffix",from="Prefix",to="Suffix"},{method="beast_suffix_prefix",from="Suffix",to="Prefix"}}) do
   local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local model=sim.model(raw);local initial=copyTable(model.initial);initial.rarity="RARE"
   local original;for _,entry in ipairs(model.mods) do if entry.mod.type==case.from and entry.mod.level<=1 then original=entry.id;break end end
   assert.is_truthy(original);initial.affixes={{id=original,range=0.5}}
   for i=0,19 do
    local result=sim.action(model,initial,{method=case.method,beastLevel=1},function() return i/20 end)
    local mod=model.byId[result.affixes[1].id];assert.equal(case.to,mod.type);assert.is_true(mod.level<=1)
    assert.equal(86,sim.model(sim.toItem(model,result).raw).item.itemLevel)
   end
   for _,bad in ipairs({0,101,1.5}) do assert.has_error(function() sim.action(model,initial,{method=case.method,beastLevel=bad},function() return 0.5 end) end) end
   assert.has_error(function() sim.validateRecipe({steps={{method=case.method,beastLevel=0}},targets={}}) end)
  end
  assert.has_error(function() sim.validateRecipe({steps={{method="chaos",beastLevel=50}},targets={}}) end)
 end)
 it("retains a high-level affix through later actions and structured save/restore",function()
  local raw="Rarity: NORMAL\nIron Hat\nItem Level: 20";local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="RARE"
  for _,entry in ipairs(model.mods) do if entry.mod.type=="Suffix" and entry.mod.level<=1 then state.affixes={{id=entry.id,range=0.5}};break end end
  local high
  for i=0,99 do local result=sim.action(model,state,{method="beast_suffix_prefix",beastLevel=86},function() return i/100 end)
   if model.byId[result.affixes[1].id].level>20 then high=result;break end
  end
  assert.is_truthy(high);local fresh=sim.model(raw);local restored=sim.validateState(fresh,copyTable(high))
  local result=sim.action(fresh,restored,{method="exalt"},function() return 0.5 end)
  assert.equal(high.affixes[1].id,result.affixes[1].id);assert.equal(2,#result.affixes)
  assert.has_no.errors(function() sim.validateState(sim.model(raw),result) end)
 end)

 it("preserves beast-level configuration and actions in saved working crafts",function()
  local raw="Rarity: NORMAL\nIron Hat\nItem Level: 20";local model=sim.model(raw)
  local run=require("Modules.CraftingInventory").run(model.initial)
  run.configured={beast_prefix_suffix={method="beast_prefix_suffix",beastLevel=86}}
  run.actions={{method="beast_prefix_suffix",beastLevel=86}}
  local restored=require("Modules.CraftingCheckpoint").validate(raw,run)
  assert.equal(86,restored.configured.beast_prefix_suffix.beastLevel);assert.equal(86,restored.actions[1].beastLevel)
 end)
 it("constructs a lower-level pool for an imported rare item with existing higher-tier affixes",function()
  local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="RARE"
  for _,entry in ipairs(model.mods) do if entry.mod.type=="Prefix" and entry.mod.level>20 then state.affixes={{id=entry.id,range=0.5}};break end end
  assert.is_truthy(state.affixes[1]);local imported=sim.model(sim.toItem(model,state).raw)
  local result=sim.action(imported,imported.initial,{method="beast_prefix_suffix",beastLevel=1},function() return 0.5 end)
  assert.is_true(imported.byId[result.affixes[1].id].level<=1);assert.equal(86,sim.model(sim.toItem(imported,result).raw).item.itemLevel)
 end)

 it("does not include essence-only modifiers in a beast-level influenced pool",function()
  local model=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 20")
  local data=require("Modules.CraftingAdvanced").data()
  for _,entry in ipairs(sim.beastSource(model,{influences={"shaper"}},86)) do
   local metadata=data.mods[entry.id]
   assert.is_false(metadata and metadata.is_essence_only or false,entry.id.." is essence-only")
  end
 end)

 it("retains influence when using the selected beast pool",function()
  local raw="Rarity: NORMAL\nIron Hat\nItem Level: 68";local model=sim.model(raw);local initial=copyTable(model.initial);initial.rarity="RARE"
  for _,entry in ipairs(model.mods) do if entry.mod.type=="Prefix" and entry.mod.level<=1 then initial.affixes={{id=entry.id,range=0.5}};break end end
  local influenced=sim.action(model,initial,{method="influence_exalt",influence="shaper"},function() return 0.5 end)
  local result=sim.action(model,influenced,{method="beast_prefix_suffix",beastLevel=86},function() return 0.5 end)
  assert.same({"shaper"},result.influences);assert.has_no.errors(function() sim.validateState(sim.model(raw),result) end)
  assert.equal(68,sim.model(sim.toItem(model,result).raw).item.itemLevel)
 end)

 it("filters beast targets by the item's actual influence",function()
  local model=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 68");local state=copyTable(model.initial);state.influences={"shaper"}
  local item=setmetatable({shaper=true,elder=false,adjudicator=false,basilisk=false,crusader=false,eyrie=false},{__index=model.item})
  local expected,excluded={},0
  for _,entry in ipairs(sim.beastSource(model,state,86)) do
   if item:GetModSpawnWeight(entry.mod,model.extraTags)>0 then expected[entry.id]=true else excluded=excluded+1 end
  end
  assert.is_true(excluded>0,"Fixture must include modifiers from other influences")
  local actual={};for _,entry in ipairs(sim.beastTargetSource(model,state,86)) do actual[entry.id]=true end
  assert.same(expected,actual)
 end)

end)
