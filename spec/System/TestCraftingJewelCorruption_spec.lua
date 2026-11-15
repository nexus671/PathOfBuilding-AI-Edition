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
   assert.matches("unique%-jewel outcome is modeled as no change",result.warnings[1].message)
   local odds=sim.calculate(model.raw,{method="vaal"},{},nil,{requirements=recipe.requirements,trials=12,seed=3})
   assert.is_true(odds.sampled);assert.equal("abyss_vaal_assumptions",odds.warnings[1].code)
   assert.matches("unique%-jewel outcome is modeled as no change",odds.warnings[1].message)
   assert.matches("unverified",require("Modules.CraftingWorkbench").hint("vaal",model.initial,model))
  end
 end)
 it("preserves cluster jewel enchantments with a corrupted implicit",function()
  local text="Rarity: MAGIC\nLarge Cluster Jewel\nItem Level: 86\nCluster Jewel Skill: affliction_axe_and_sword_damage\nCluster Jewel Node Count: 8\nImplicits: 3\n{crafted}Adds 8 Passive Skills\n{crafted}Added Small Passive Skills grant: 12% increased Axe and Sword Damage\n{corrupted}Corrupted Blood cannot be inflicted on you\nCorrupted"
  local model=sim.model(text);assert.is_nil(model.unresolvedCorruption);assert.equal(regular,model.initial.corruptedImplicits[1].id)
  local recreated=sim.toItem(model,sim.validateState(model,model.initial)).raw;local reopened=sim.model(recreated)
  assert.equal(regular,reopened.initial.corruptedImplicits[1].id);assert.equal(model.item.clusterJewelSkill,reopened.item.clusterJewelSkill);assert.equal(model.item.clusterJewelNodeCount,reopened.item.clusterJewelNodeCount)
 end)
 it("retains cluster enchantments through all modeled Vaal outcomes",function()
  local raw="Rarity: NORMAL\nLarge Cluster Jewel\nItem Level: 86\nCluster Jewel Skill: affliction_axe_and_sword_damage\nCluster Jewel Node Count: 8\nImplicits: 2\n{crafted}Adds 8 Passive Skills\n{crafted}Added Small Passive Skills grant: 12% increased Axe and Sword Damage"
  local model=sim.model(raw);assert.is_true(require("Modules.CraftingAvailability").check("vaal",model.initial,model))
  for _,draw in ipairs({0.1,0.3,0.55,0.8}) do
   local state=sim.action(model,model.initial,{method="vaal"},function() return draw end);sim.validateState(model,state)
   local reopened=sim.model(sim.toItem(model,state).raw)
   assert.equal(model.item.clusterJewelSkill,reopened.item.clusterJewelSkill);assert.equal(8,reopened.item.clusterJewelNodeCount);assert.is_true(reopened.initial.corrupted)
   if draw==0.1 then assert.equal(1,#state.corruptedImplicits);assert.equal(state.corruptedImplicits[1].id,reopened.initial.corruptedImplicits[1].id)
   elseif draw==0.55 then assert.equal("RARE",state.rarity);assert.is_true(#state.affixes<=4);assert.equal(#state.affixes,#reopened.initial.affixes) end
  end
  local warnings=sim.actionWarnings({method="vaal"},model);assert.equal("cluster_vaal_assumptions",warnings[1].code);assert.matches("unique%-jewel outcome is modeled as no change",warnings[1].message)
  local result=sim.simulate(raw,{steps={{method="vaal"}},targets={},requirements={minAffixes=4,corrupted=true}},{trials=12,maxActions=1,seed=3})
  assert.equal("cluster_vaal_assumptions",result.warnings[1].code)
  assert.matches("unique%-jewel outcome is modeled as no change",result.warnings[1].message)
  local odds=sim.calculate(raw,{method="vaal"},{},nil,{requirements={minAffixes=4,corrupted=true},trials=12,seed=3})
  assert.is_true(odds.sampled);assert.equal("cluster_vaal_assumptions",odds.warnings[1].code)
 end)
 it("round-trips every current corruption across cluster jewel sizes",function()
  local cases={{"Large Cluster Jewel",8,"affliction_axe_and_sword_damage","12% increased Axe and Sword Damage"},{"Medium Cluster Jewel",4,"affliction_fire_damage_over_time_multiplier","12% increased Burning Damage"},{"Small Cluster Jewel",2,"affliction_maximum_life","4% increased maximum Life"}}
  for _,v in ipairs(cases) do
   local raw="Rarity: NORMAL\n"..v[1].."\nItem Level: 86\nCluster Jewel Skill: "..v[3].."\nCluster Jewel Node Count: "..v[2].."\nImplicits: 2\n{crafted}Adds "..v[2].." Passive Skills\n{crafted}Added Small Passive Skills grant: "..v[4]
   local model=sim.model(raw);local total=0;for _,entry in ipairs(model.corruptions) do total=total+entry.weight end;assert.is_true(total>0)
   local before=0
   for _,entry in ipairs(model.corruptions) do
    local pick=(before+entry.weight/2)/total;before=before+entry.weight;local draws=0
    local state=sim.action(model,model.initial,{method="vaal"},function() draws=draws+1;return draws==1 and 0.1 or draws==2 and pick or 0.5 end)
    assert.equal(entry.id,state.corruptedImplicits[1].id)
    local reopened=sim.model(sim.toItem(model,sim.validateState(model,state)).raw)
    assert.equal(v[3],reopened.item.clusterJewelSkill);assert.equal(v[2],reopened.item.clusterJewelNodeCount)
    if reopened.initial.corruptedImplicits then assert.equal(entry.id,reopened.initial.corruptedImplicits[1].id) else assert.equal("unresolved",reopened.unresolvedCorruption) end
   end
  end
 end)
 it("models jewel Locus branches and preserves existing implicits",function()
  local cases={"Rarity: NORMAL\nCobalt Jewel\nItem Level: 86","Rarity: NORMAL\nSearching Eye Jewel\nItem Level: 86","Rarity: NORMAL\nLarge Cluster Jewel\nItem Level: 86\nCluster Jewel Skill: affliction_axe_and_sword_damage\nCluster Jewel Node Count: 8\nImplicits: 2\n{crafted}Adds 8 Passive Skills\n{crafted}Added Small Passive Skills grant: 12% increased Axe and Sword Damage"}
  for _,raw in ipairs(cases) do
   local model=sim.model(raw);local input=copyTable(model.initial);sim.rollCorrupted(model,input,function() return 0.1 end,1)
   local original=input.corruptedImplicits[1].id;assert.is_true(require("Modules.CraftingAvailability").check("locus",input,model))
   for _,draw in ipairs({0.1,0.3,0.6,0.9}) do
    local state=sim.action(model,input,{method="locus"},function() return draw end);sim.validateState(model,state)
    if draw==0.1 then
     assert.is_true(state.twiceCorrupted);assert.equal(2,#state.corruptedImplicits);assert.equal(original,state.corruptedImplicits[1].id);assert.is_not.equal(original,state.corruptedImplicits[2].id)
     local reopened=sim.model(sim.toItem(model,state).raw);assert.is_true(reopened.initial.twiceCorrupted)
     if model.item.clusterJewel then assert.equal(model.item.clusterJewelSkill,reopened.item.clusterJewelSkill);assert.equal(8,reopened.item.clusterJewelNodeCount) end
    elseif draw==0.3 then assert.is_true(state.twiceCorrupted);assert.equal(original,state.corruptedImplicits[1].id)
    else assert.is_true(state.destroyed) end
   end
   local warnings=sim.actionWarnings({method="locus"},model);assert.matches("25%% no change",warnings[1].message)
   local trial=sim.simulate(raw,{steps={{method="locus"}},targets={{scope="implicit",anyOf={original}}}},{initialState=input,trials=8,maxActions=1,forceFirstAction=true,seed=5})
   assert.matches("25%% no change",trial.warnings[1].message)
   local isolated={};for key,value in pairs(model) do isolated[key]=value end;isolated.corruptions={{id=original,weight=1}}
   assert.matches("no compatible",sim.methodChecks.locus(isolated,input))
   local pair=copyTable(input);sim.rollCorrupted(model,pair,function() return 0.7 end,1,pair.corruptedImplicits)
   for _,selection in ipairs({0.1,0.9}) do
    local n=0;local replaced=sim.action(model,pair,{method="locus"},function() n=n+1;return n==1 and 0.1 or n==2 and selection or 0.5 end)
    assert.equal(2,#replaced.corruptedImplicits);assert.equal(pair.corruptedImplicits[selection<0.5 and 2 or 1].id,replaced.corruptedImplicits[1].id)
    sim.validateState(model,replaced)
   end
  end
 end)
 it("does not restore imported implicits onto a destroyed jewel",function()
  local model=sim.model(raw("Searching Eye Jewel"));local destroyed=sim.action(model,model.initial,{method="locus"},function() return 0.9 end)
  assert.is_true(destroyed.destroyed);local validated=sim.validateState(model,destroyed);assert.is_nil(validated.corruptedImplicits)
 end)
 it("matches, edits and saves once- and twice-corrupted item goals",function()
  newBuild();local source="Rarity: NORMAL\nSearching Eye Jewel\nItem Level: 86";local model=sim.model(source)
  local normal=copyTable(model.initial);local once=copyTable(normal);once.corrupted=true
  local twice=copyTable(once);twice.twiceCorrupted=true
  local function matches(state,requirements) return sim.matches(state,{},nil,model,requirements) end
  assert.is_false(matches(normal,{twiceCorrupted=true}));assert.is_false(matches(once,{twiceCorrupted=true}));assert.is_true(matches(twice,{twiceCorrupted=true}))
  assert.is_true(matches(normal,{twiceCorrupted=false}));assert.is_true(matches(once,{corrupted=true,twiceCorrupted=false}));assert.is_false(matches(twice,{twiceCorrupted=false}))
  assert.has_error(function() sim.validateRecipe({steps={{method="vaal"}},targets={},requirements={corrupted=false,twiceCorrupted=true}}) end)
  local trial=sim.simulate(source,{initialState=once,steps={{method="locus"}},targets={},requirements={twiceCorrupted=true}},{trials=20,maxActions=1,retainSuccesses=20,seed=5})
  assert.is_true(trial.successes>0);assert.is_true(trial.successes<20);assert.equal(trial.successes,#trial.retainedSuccesses)
  for _,success in ipairs(trial.retainedSuccesses) do assert.is_true(success.state.twiceCorrupted) end
  local saved;main.popups={};local editor=require("Classes.CraftingTargetControl").Open({},nil,nil,function(_,value) saved=value end)
  editor.corrupted:SelByValue("Must be twice corrupted");editor.keep:Click();assert.same({twiceCorrupted=true},saved)
  editor=require("Classes.CraftingTargetControl").Open({},saved,nil,function(_,value) saved=value end);assert.equal("Must be twice corrupted",editor.corrupted:GetSelValue())
  editor.corrupted:SelByValue("Must be corrupted once");editor.keep:Click();assert.same({corrupted=true,twiceCorrupted=false},saved)
  editor=require("Classes.CraftingTargetControl").Open({},saved,nil,function(_,value) saved=value end);assert.equal("Must be corrupted once",editor.corrupted:GetSelValue())
  editor.corrupted:SelByValue("Must not be twice corrupted");editor.keep:Click();assert.same({twiceCorrupted=false},saved)
  editor=require("Classes.CraftingTargetControl").Open({},saved,nil,function(_,value) saved=value end);assert.equal("Must not be twice corrupted",editor.corrupted:GetSelValue());editor.close:Click()
  local slot;local item=require("Modules.CraftingProjects").item(source)
  for name in pairs(build.itemsTab.slots) do if name:match("^Jewel %d+$") and build.itemsTab:IsItemValidForSlot(item,name) then slot=name;break end end
  assert.is_truthy(slot);local project={id="twice-goal",title="Corruption goal",slot=slot,startingItem=source,goals={},steps={},nativeRecipe={steps={{method="locus"}},targets={},requirements={twiceCorrupted=true}}}
  build.savers.CraftingProjects:Upsert(project);local xml=build:SaveDB("Corruption goal");loadBuildFromXML(xml,"Corruption goal")
  assert.is_true(build.savers.CraftingProjects.projects[1].nativeRecipe.requirements.twiceCorrupted)
  project.nativeRecipe.requirements={corrupted=true,twiceCorrupted=false};build.savers.CraftingProjects:Upsert(project)
  xml=build:SaveDB("Once goal");loadBuildFromXML(xml,"Once goal");assert.same({corrupted=true,twiceCorrupted=false},build.savers.CraftingProjects.projects[1].nativeRecipe.requirements)
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
