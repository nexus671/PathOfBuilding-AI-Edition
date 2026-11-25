describe("Veiled Chaos Orb",function()
 local sim=require("Modules.CraftingSimulator")
 local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86"
 local function model() return sim.model(raw) end
 local function rare() return sim.perform(raw,{method="alchemy"},12).state end
 it("reforges a rare item, reserves a veil slot, and can unveil",function()
  local source=rare();local original=copyTable(source)
  local result=sim.perform(raw,{method="veiled_chaos"},19,source)
  assert.same(original,source);assert.is_truthy(result.state.veil)
  assert.is_true(#result.state.affixes>=3 and #result.state.affixes<=5)
  assert.equal("veiled_chaos_assumptions",result.warnings[1].code)
  assert.equal(1,sim.components({method="veiled_chaos"}).veiled_chaos)
  local unveiled=sim.perform(raw,{method="unveil",modId=result.state.veil.choices[1]},20,result.state)
  assert.is_nil(unveiled.state.veil);assert.equal(#result.state.affixes+1,#unveiled.state.affixes)
 end)
 it("rerolls an unprotected pending veil but rejects a fractured veil",function()
  local first=sim.perform(raw,{method="veiled_chaos"},19,rare()).state
  local second=sim.perform(raw,{method="veiled_chaos"},20,first).state
  assert.is_truthy(second.veil);assert.is_true(require("Modules.CraftingAvailability").check("veiled_chaos",first,model()))
  first.veil.fractured=true
  local available,reason=require("Modules.CraftingAvailability").check("veiled_chaos",first,model())
  assert.is_false(available);assert.matches("protected",reason)
  local ok,message=pcall(sim.perform,raw,{method="veiled_chaos"},21,first)
  assert.is_false(ok);assert.matches("protected",message)
 end)
 it("rejects protected unveiled modifiers and full side locks",function()
  local m=model();local pending=sim.perform(raw,{method="veiled_chaos"},19,rare()).state
  local revealed=sim.perform(raw,{method="unveil"},20,pending).state
  local veiledId=pending.veil.choices[1]
  for _,entry in ipairs(revealed.affixes) do if entry.id==veiledId then entry.fractured=true end end
  local ok,reason=require("Modules.CraftingAvailability").check("veiled_chaos",revealed,m)
  assert.is_false(ok);assert.matches("protected",reason)
  local lockText=pending.veil.type=="Prefix" and "Prefixes Cannot Be Changed" or "Suffixes Cannot Be Changed"
  local lock;for _,entry in ipairs(m.bench) do if entry.mod[1]==lockText then lock=entry.id;break end end
  local protected={rarity="RARE",affixes={{id=lock,range=0.5,crafted=true}},veil=copyTable(pending.veil)}
  sim.validateState(m,protected)
  ok,reason=require("Modules.CraftingAvailability").check("veiled_chaos",protected,m)
  assert.is_false(ok);assert.matches("protected",reason)
 end)
 it("preserves a fractured ordinary modifier on reforge",function()
  local source=rare();source.affixes[1].fractured=true;local id=source.affixes[1].id
  local result=sim.perform(raw,{method="veiled_chaos"},19,source).state
  local found=false;for _,entry in ipairs(result.affixes) do if entry.id==id and entry.fractured then found=true end end
  assert.is_true(found)
 end)
 it("uses the memory strand consumption model",function()
  local source=rare();source.memoryStrands=100
  assert.equal(80,sim.consumesStrands({method="veiled_chaos"}))
  local result=sim.perform(raw,{method="veiled_chaos"},19,source).state
  assert.is_true(result.memoryStrands>=20 and result.memoryStrands<=100)
 end)
 it("includes the pending veil in partial-lock selection",function()
  local m=model();local choice
  for _,entry in ipairs(m.veiled) do if entry.mod.type=="Prefix" then choice=entry.id;break end end
  local source={rarity="RARE",affixes={{id="IncreasedLife0",range=0.5},{id="bench:partial-prefix-1",range=0.5,crafted=true}},veil={type="Prefix",choices={choice}}}
  sim.validateState(m,source)
  local before=copyTable(source)
  local allowed=sim.action(m,source,{method="veiled_chaos"},function() return 0.01 end)
  assert.is_truthy(allowed.veil);assert.same(before,source)
  local ok,reason=pcall(sim.action,m,source,{method="veiled_chaos"},function() return 0.99 end)
  assert.is_false(ok);assert.matches("protected",reason);assert.same(before,source)
 end)
end)
