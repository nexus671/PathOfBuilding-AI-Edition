describe("Map Allflame planning",function()
 local allflame=require("Modules.MapAllflame");local currency=require("Modules.MapCurrency");local map=require("Modules.MapCraftingData");local atlas=require("Modules.AtlasPlanner")
 local first="Metadata/Items/MapFragments/AtlasAllflamePack";local second="Metadata/Items/MapFragments/PantheonAllflamePack"
 local function state() return {baseId="Metadata/Items/Maps/MapWorldsStrand",tier=16,itemLevel=83,rarity="rare",selected={},observedEffects={{kind="implicit",text="Area is Influenced by the Originator's Memories"}},plannedDeified=true} end
 before_each(function() newBuild();main.popups={} end)
 after_each(function() main.popups={} end)
 it("references all current map embers without inventing outcomes",function()
  local items=allflame.list();assert.equal(11,#items);local seen={}
  for _,item in ipairs(items) do assert.is_nil(seen[item.id]);seen[item.id]=true;assert.is_truthy(item.description);assert.is_truthy(item.icon) end
  assert.is_true(seen[first]);assert.is_true(seen[second]);assert.has_error(function() allflame.validate("unknown") end)
  local input=state();local before=copyTable(input);local result=currency.perform(input,"plan_allflame",42,nil,nil,nil,first)
  assert.same(before,input);assert.equal(first,result.state.plannedAllflame);assert.is_true(result.state.plannedDeified);assert.same(before.observedEffects,result.state.observedEffects)
  assert.equal("planned",result.allflame.provenance);assert.matches("300%%",result.allflame.description);assert.matches("verification",result.allflame.note)
  local replaced=currency.perform(result.state,"plan_allflame",42,nil,nil,nil,second);assert.equal(second,replaced.state.plannedAllflame);assert.equal(first,result.state.plannedAllflame)
  local removed=currency.perform(replaced.state,"clear_allflame_plan",42);assert.is_nil(removed.state.plannedAllflame);assert.is_true(removed.state.plannedDeified);assert.same(before.observedEffects,removed.state.observedEffects)
  assert.has_error(function() currency.perform(input,"plan_allflame",42,nil,nil,nil,"unknown") end)
  assert.has_error(function() currency.perform(input,"clear_allflame_plan",42) end)
 end)
 it("reports planning actions independently of currency restrictions",function()
  local input=state();input.corrupted=true;input.twiceCorrupted=true;input.mirrored=true;input.plannedAllflame=first
  local before=copyTable(input);local options={};for _,entry in ipairs(currency.planningOptions(input)) do options[entry.id]=entry end
  assert.same(before,input);assert.is_true(options.plan_allflame.available);assert.is_true(options.clear_allflame_plan.available)
  assert.is_false(options.divine_vessel.available);assert.is_true(options.clear_deified_plan.available);assert.matches("Hypothetical",options.plan_allflame.detail)
  assert.has_error(function() currency.options(input) end)
  local cleared=currency.perform(input,"clear_allflame_plan",42).state;local updated={};for _,entry in ipairs(currency.planningOptions(cleared)) do updated[entry.id]=entry end
  assert.is_false(updated.clear_allflame_plan.available);assert.matches("no planned",updated.clear_allflame_plan.reason)
  local unknown=state();unknown.unidentified=true;unknown.plannedDeified=nil
  local hidden={};for _,entry in ipairs(currency.planningOptions(unknown)) do hidden[entry.id]=entry end
  assert.is_true(hidden.divine_vessel.available);assert.is_true(hidden.plan_allflame.available);assert.is_false(hidden.clear_deified_plan.available)
  assert.has_error(function() currency.options(unknown) end)
 end)
 it("persists plans through map rerolls, Atlas save and export",function()
  local input=state();input.corrupted=true;input.twiceCorrupted=true
  local plan=currency.perform(input,"plan_allflame",42,nil,nil,nil,first).state;assert.is_true(plan.twiceCorrupted)
  plan.id="allflame";plan.title="Allflame map";plan.patch=map.source().patch
  local source={id="atlas",title="Atlas",version="3.30.0-preview",budget=atlas.tree("3.30.0-preview").maxPoints,nodes={},mapDrafts={plan}}
  local store=atlas.new(build);store:Upsert(source);local xml={};store:Save(xml);local opened=atlas.new(build);opened:Load(xml)
  assert.same(source.mapDrafts,opened.plans[1].mapDrafts);assert.same(source.mapDrafts,atlas.import(atlas.export(source)).mapDrafts)
  local rare=state();rare.plannedAllflame=first;local estimate=require("Modules.MapCraftEstimate").run(rare,{avoid={"MapMonsterAreaOfEffectMapWorlds"},trials=1,maxAttempts=1,seed=42})
  assert.equal(first,estimate.plannedAllflame);assert.equal(first,estimate.allflame.id);assert.equal("planned",estimate.allflame.provenance);assert.matches("unverified",estimate.note);if estimate.sampleSuccess then assert.equal(first,estimate.sampleSuccess.plannedAllflame) end
 end)
 it("selects and clears a plan in the map editor",function()
  local draft=state();draft.id="plan";draft.title="Map";draft.patch=map.source().patch
  local saved;local controls=require("Classes.MapModifierControl").Open({build=build,initial=draft,keep=function(value) saved=atlas.validateMapDraft(value);return value.id end})
  controls.allflamePlan:Click();local picker=main.popups[1].controls;picker.search:SetText("Multitude",true);picker.choose:Click()
  local lines={};for _,row in ipairs(controls.affixes.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;assert.matches("Allflame Ember of the Multitude",table.concat(lines," "),1,true)
  controls.keep:Click();assert.equal(first,saved.plannedAllflame);assert.is_true(saved.plannedDeified);assert.same(draft.observedEffects,saved.observedEffects)
  controls.allflamePlan:Click();main.popups[1].controls.secondary:Click();controls.keep:Click();assert.is_nil(saved.plannedAllflame);assert.is_true(saved.plannedDeified)
 end)
end)
