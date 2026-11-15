describe("Corrupted jewel implicit import",function()
 local sim=require("Modules.CraftingSimulator")
 local regular="V2CorruptedBloodImmunityCorrupted"
 local abyss="V2CorruptedBloodImmunityAbyssalJewelCorrupted"
 local function raw(base,level) return "Rarity: MAGIC\n"..base.."\nItem Level: "..(level or 86).."\nImplicits: 1\nCorrupted Blood cannot be inflicted on you\nCorrupted" end
 it("recovers regular and abyss jewel implicits with their native identities",function()
  for _,v in ipairs({{"Cobalt Jewel",regular},{"Searching Eye Jewel",abyss},{"Assembled Eye Jewel",abyss}}) do
   local model=sim.model(raw(v[1]));assert.is_nil(model.unresolvedCorruption,v[1]);assert.equal(v[2],model.initial.corruptedImplicits[1].id)
   assert.is_true(sim.matches(model.initial,{{scope="implicit",anyOf={v[2]}}},nil,model));assert.is_false(sim.matches(model.initial,{{scope="implicit",anyOf={v[2]==regular and abyss or regular}}},nil,model))
   local copy=sim.validateState(model,model.initial);local recreated=sim.toItem(model,copy).raw;assert.matches("Corrupted Blood cannot be inflicted",recreated)
   assert.equal(v[2],sim.model(recreated).initial.corruptedImplicits[1].id)
   local catalog=sim.catalog(raw(v[1]),"Corrupted Blood",100);local found;for _,row in ipairs(catalog.modifierTable.rows) do if row.id==v[2] then found=row end end
   assert.equal("Special",assert(found).source);assert.equal("Corrupted",found.type)
  end
 end)
 it("serializes every currently eligible regular and abyss corruption",function()
  for _,base in ipairs({"Cobalt Jewel","Searching Eye Jewel"}) do
   local model=sim.model("Rarity: NORMAL\n"..base.."\nItem Level: 86");assert.equal(21,#model.corruptions)
   for _,entry in ipairs(model.corruptions) do
    local state=copyTable(model.initial);state.corrupted=true;state.corruptedImplicits={{id=entry.id,range=0.5}}
    local output=sim.toItem(model,sim.validateState(model,state)).raw;local ok,reopened=pcall(sim.model,output);assert.is_true(ok,entry.id..": "..tostring(reopened))
    if reopened.initial.corruptedImplicits then assert.equal(entry.id,reopened.initial.corruptedImplicits[1].id,entry.id) else assert.equal("unresolved",reopened.unresolvedCorruption,entry.id) end
   end
  end
 end)
 it("keeps jewel pools base-specific and respects item level",function()
  local a=sim.model("Rarity: NORMAL\nCobalt Jewel\nItem Level: 86");local b=sim.model("Rarity: NORMAL\nSearching Eye Jewel\nItem Level: 86")
  assert.is_true(a.corruptionIds[regular]);assert.is_nil(a.corruptionIds[abyss]);assert.is_true(b.corruptionIds[abyss]);assert.is_nil(b.corruptionIds[regular])
  local low=sim.model("Rarity: NORMAL\nCobalt Jewel\nItem Level: 10");assert.is_nil(low.corruptionIds[regular])
  local wrong=copyTable(a.initial);wrong.corrupted=true;wrong.corruptedImplicits={{id=abyss,range=0.5}};assert.is_false(pcall(sim.validateState,a,wrong))
  assert.is_false(require("Modules.CraftingAvailability").check("vaal",a.initial,a))
 end)
 it("models Abyss jewel Vaal branches without treating special drops as ordinary rolls",function()
  for _,base in ipairs({"Searching Eye Jewel","Assembled Eye Jewel"}) do
   local model=sim.model("Rarity: NORMAL\n"..base.."\nItem Level: 86")
   assert.is_true(require("Modules.CraftingAvailability").check("vaal",model.initial,model))
   for _,value in ipairs({0.1,0.3,0.55,0.8}) do
    local state=sim.action(model,model.initial,{method="vaal"},function() return value end)
    assert.is_true(state.corrupted);sim.validateState(model,state)
    if value==0.1 then assert.equal(1,#state.corruptedImplicits)
    elseif value==0.55 then assert.equal("RARE",state.rarity);assert.equal(4,#state.affixes)
    else assert.equal("NORMAL",state.rarity);assert.is_nil(state.corruptedImplicits) end
    local reopened=sim.model(sim.toItem(model,state).raw);assert.is_true(reopened.initial.corrupted)
    assert.equal(#state.affixes,#reopened.initial.affixes)
   end
   local recipe={steps={{method="vaal"}},targets={},requirements={minAffixes=4,corrupted=true}}
   local result=sim.simulate(model.raw,recipe,{trials=12,maxActions=1,seed=3})
   assert.equal("abyss_vaal_assumptions",result.warnings[1].code)
   local odds=sim.calculate(model.raw,{method="vaal"},{},nil,{requirements=recipe.requirements,trials=12,seed=3})
   assert.is_true(odds.sampled);assert.equal("abyss_vaal_assumptions",odds.warnings[1].code)
   assert.matches("unverified",require("Modules.CraftingWorkbench").hint("vaal",model.initial,model))
  end
 end)
 it("preserves cluster jewel enchantments with a corrupted implicit",function()
  local text="Rarity: MAGIC\nLarge Cluster Jewel\nItem Level: 86\nCluster Jewel Skill: affliction_axe_and_sword_damage\nCluster Jewel Node Count: 8\nImplicits: 3\n{crafted}Adds 8 Passive Skills\n{crafted}Added Small Passive Skills grant: 12% increased Axe and Sword Damage\n{corrupted}Corrupted Blood cannot be inflicted on you\nCorrupted"
  local model=sim.model(text);assert.is_nil(model.unresolvedCorruption);assert.equal(regular,model.initial.corruptedImplicits[1].id)
  local recreated=sim.toItem(model,sim.validateState(model,model.initial)).raw;local reopened=sim.model(recreated)
  assert.equal(regular,reopened.initial.corruptedImplicits[1].id);assert.equal(model.item.clusterJewelSkill,reopened.item.clusterJewelSkill);assert.equal(model.item.clusterJewelNodeCount,reopened.item.clusterJewelNodeCount)
 end)
 it("retains uniquely identifiable legacy implicits without generating them",function()
  local text="Rarity: MAGIC\nCobalt Jewel\nItem Level: 86\nImplicits: 1\n4% reduced Chill Duration on you\nCorrupted"
  local legacy="ReducedChillDurationJewelCorrupted";local model=sim.model(text);assert.is_nil(model.unresolvedCorruption)
  assert.equal(legacy,model.initial.corruptedImplicits[1].id);assert.is_nil(model.corruptionIds[legacy]);assert.is_true(model.legacyCorruptionIds[legacy])
  local recreated=sim.toItem(model,sim.validateState(model,model.initial)).raw;assert.equal(legacy,sim.model(recreated).initial.corruptedImplicits[1].id)
  local blank=sim.model("Rarity: NORMAL\nCobalt Jewel\nItem Level: 86");local invented=copyTable(blank.initial);invented.corrupted=true;invented.corruptedImplicits={{id=legacy,range=0.5}}
  assert.is_false(pcall(sim.validateState,blank,invented))
 end)
 it("does not guess between identical current and legacy implicits",function()
  local text="Rarity: MAGIC\nCobalt Jewel\nItem Level: 86\nImplicits: 1\nYou cannot be Cursed with Silence\nCorrupted"
  local model=sim.model(text);assert.equal("unresolved",model.unresolvedCorruption);assert.is_nil(model.initial.corruptedImplicits)
  local catalog=sim.catalog(text,"",5);assert.matches("could not be identified uniquely",catalog.importWarning)
  assert.is_false(pcall(sim.matches,model.initial,{{scope="implicit",anyOf={"V2SilenceImmunityJewelCorrupted"}}},nil,model))
  assert.matches("You cannot be Cursed with Silence",sim.toItem(model,model.initial).raw)
 end)
 it("retains a corrupted jewel in saved inventory",function()
  newBuild();local model=sim.model(raw("Cobalt Jewel"));local slot;local item=require("Modules.CraftingProjects").item(model.raw)
  for name in pairs(build.itemsTab.slots) do if name:match("^Jewel %d+$") and build.itemsTab:IsItemValidForSlot(item,name) then slot=name;break end end
  assert.is_truthy(slot);local project={id="corrupted-jewel",title="Corrupted jewel",slot=slot,startingItem=model.raw,goals={},steps={}}
  local inventory=require("Modules.CraftingInventory");project.inventory={inventory.capture(project,model.initial,"Corrupted jewel")};build.savers.CraftingProjects:Upsert(project)
  local xml=build:SaveDB("Corrupted jewel");loadBuildFromXML(xml,"Corrupted jewel")
  local state=build.savers.CraftingProjects.projects[1].inventory[1].state;assert.equal(regular,state.corruptedImplicits[1].id)
 end)
end)

describe("Corrupted Abyss jewel modifier limits", function()
 local sim=require("Modules.CraftingSimulator")
 it("reopens five and six modifiers while retaining ordinary limits", function()
  local model=sim.model("Rarity: NORMAL\nSearching Eye Jewel\nItem Level: 86")
  local state=copyTable(model.initial); state.rarity="RARE"; state.corrupted=true
  for _,entry in ipairs(model.mods) do
   local candidate=copyTable(state); candidate.affixes[#candidate.affixes+1]={id=entry.id,range=0.5}
   if pcall(sim.validateState,model,candidate) then
    state=candidate
    if #state.affixes>=5 then
     local raw=sim.toItem(model,state).raw
     local reopened=sim.model(raw)
     assert.equal(#state.affixes,#reopened.initial.affixes)
     assert.is_true(reopened.initial.corrupted)
     assert.is_truthy(sim.validateState(reopened,reopened.initial))
     local ordinary=copyTable(state); ordinary.corrupted=false
     assert.is_false(pcall(sim.validateState,model,ordinary))
    end
    if #state.affixes==6 then break end
   end
  end
  assert.equal(6,#state.affixes)
 end)
end)
