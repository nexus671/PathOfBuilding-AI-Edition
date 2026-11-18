describe("Bench crafting before unveiling",function()
 local sim=require("Modules.CraftingSimulator")
 local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86"
 local function pending() local rare=sim.perform(raw,{method="alchemy"},12).state;return sim.perform(raw,{method="veiled_chaos"},19,rare).state end
 it("retains fixed draws while a blocking craft is added and removed",function()
  local m=sim.model(raw);local start=pending();local original=copyTable(start)
  -- Leave room to exercise a bench prefix or suffix, retaining the veil.
  start.affixes={};local available=require("Modules.CraftingAvailability")
  assert.is_true(available.check("bench",start,m));local options=sim.actionOptions(m,start,"bench");assert.is_true(#options>0)
  local craft={method="bench",modId=options[1].action.modId}
  local performed=sim.perform(raw,craft,101,start);assert.equal("veil_bench_assumptions",performed.warnings[1].code)
  local added=performed.state
  assert.same(start.veil.offerRolls,added.veil.offerRolls);assert.is_true(added.affixes[1].crafted)
  local removed=sim.perform(raw,{method="remove_crafted"},102,added).state
  assert.same(start.veil.offerRolls,removed.veil.offerRolls)
  local repeated=sim.perform(raw,craft,104,removed).state;assert.same(added.veil.choices,repeated.veil.choices)
  assert.is_truthy(sim.perform(raw,{method="unveil"},103,added).itemText)
  assert.same(original.veil.offerRolls,start.veil.offerRolls)
 end)
 it("removes bench-blocked groups from the modeled unveil offers",function()
  local m=sim.model(raw);local state=pending();state.affixes={};local metadata=require("Modules.CraftingAdvanced").data().mods
  local selected
  for _,option in ipairs(sim.actionOptions(m,state,"bench")) do
   local group=m.byId[option.action.modId].group
   for _,id in ipairs(state.veil.choices) do for _,g in ipairs(metadata[id] and metadata[id].groups or {}) do if g==group then selected=option.action;break end end end
   if selected then break end
  end
  assert.is_truthy(selected,"Expected a bench craft sharing an offered unveil group")
  local group=m.byId[selected.modId].group;local result=sim.perform(raw,selected,11,state).state
  for _,id in ipairs(result.veil.choices) do for _,g in ipairs(metadata[id] and metadata[id].groups or {}) do assert.not_equal(group,g) end end
 end)
 it("counts a pending veil as occupying its side",function()
  local m=sim.model(raw);local state=pending();state.affixes={}
  local side=state.veil.type;local groups={};for _,entry in ipairs(m.mods) do
   if entry.mod.type==side and not groups[entry.mod.group] and #state.affixes<2 then groups[entry.mod.group]=true;state.affixes[#state.affixes+1]={id=entry.id,range=0.5} end
  end
  assert.matches(side=="Prefix" and "Prefixes 3/3" or "Suffixes 3/3",require("Modules.CraftingInspection").slots(m,state))
  for _,entry in ipairs(m.bench) do if entry.mod.type==side then assert.is_truthy(sim.benchReason(m,state,entry.id)) end end
 end)
 it("keeps older observed choices immutable",function()
  local state=pending();state.veil.offerRolls=nil;local m=sim.model(raw)
  local ok,reason=require("Modules.CraftingAvailability").check("bench",state,m)
  assert.is_false(ok);assert.matches("observed choices",reason)
 end)
end)
