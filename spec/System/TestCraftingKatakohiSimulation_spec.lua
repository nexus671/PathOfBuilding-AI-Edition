-- cspell:ignore Katakohi
describe("Experimental Katakohi crafting",function()
 local sim=require("Modules.CraftingSimulator")
 local katakohi=require("Modules.CraftingKatakohi")
 local raw="Rarity: NORMAL\nIron Gauntlets\nItem Level: 86\nSockets: R-R-R-R"
 local action={method="ducat_katakohi"}
 it("uses base attribute pools instead of the existing socket colours",function()
  local function pool(base) return katakohi.pool(sim.model("Rarity: NORMAL\n"..base.."\nItem Level: 86\nSockets: W-W-W-W")) end
  local function has(entries,fragment) for _,entry in ipairs(entries) do if entry.id:find(fragment,1,true) then return true end end return false end
  assert.is_true(has(pool("Iron Gauntlets"),"Str"));assert.is_false(has(pool("Iron Gauntlets"),"Dex"))
  assert.is_true(has(pool("Rawhide Gloves"),"Dex"));assert.is_false(has(pool("Rawhide Gloves"),"Str"))
  local hybrid=pool("Steelscale Gauntlets");assert.is_true(has(hybrid,"Str"));assert.is_true(has(hybrid,"Dex"));assert.is_false(has(hybrid,"Int"))
  local catalogue=sim.catalog(raw,"Movement Speed",100);assert.is_false(catalogue.katakohiEnchants[1].modeledEligible)
  catalogue=sim.catalog(raw,"Fire Damage",100);assert.is_true(catalogue.katakohiEnchants[1].modeledEligible)
 end)
 it("breaks links across an etched socket under the stated retention assumption",function()
  local model=sim.model(raw);local draws={0,0.26,0};local i=0
  local state=sim.action(model,model.initial,{method="ducat_katakohi",allflame={outcomes=1,gainMin=0,gainMax=0,sulphur=0}},function() i=i+1;return assert(draws[i]) end)
  assert.are.equal(3,#state.sockets);assert.are.same({0,1,1},{state.sockets[1].group,state.sockets[2].group,state.sockets[3].group})
 end)
 it("chooses a matching ghost for a recipe target when one is offered",function()
  local model=sim.model(raw);local targets={{scope="enchant",anyOf={"DeepwaterTattooEnchantStrGlobalFireDamage"}}};local found=false
  for seed=1,40 do
   local roll=sim.perform(raw,action,seed);local any=false
   for _,choice in ipairs(roll.choices) do if sim.matches(choice.state,targets,nil,model) then any=true end end
   if any and not sim.matches(roll.choices[1].state,targets,nil,model) then
    local result=sim.simulate(raw,{steps={action},targets=targets},{trials=1,maxActions=1,seed=seed})
    assert.are.equal(1,result.successes);found=true;break
   end
  end
  assert.is_true(found,"Expected a fixture with a matching later ghost")
 end)
 it("produces historical ghost choices, preserves other item properties and discloses assumptions",function()
  local model=sim.model(raw);local before=copyTable(model.initial)
  local result=sim.perform(raw,action,17);assert.are.same(before,model.initial)
  assert.are.equal(4,#result.choices);assert.is_truthy(result.allflame.sulphur>0)
  local codes={};for _,warning in ipairs(result.warnings) do codes[warning.code]=true end
  assert.is_true(codes.katakohi_assumptions);assert.is_true(codes.allflame_historical)
  for _,choice in ipairs(result.choices) do
   local state=choice.state;assert.is_true(#state.katakohiEnchants>=1 and #state.katakohiEnchants<=3)
   assert.are.equal(4,#state.sockets+#state.katakohiEnchants);assert.are.same(before.affixes,state.affixes)
   local seen={};for _,id in ipairs(state.katakohiEnchants) do assert.is_false(seen[id] or false);seen[id]=true;assert.matches("Str",id) end
   sim.validateState(model,state);assert.are.equal(2*#state.katakohiEnchants,#sim.toItem(model,state).enchantModLines)
  end
  local cost=sim.components(action,model.initial,model);assert.are.equal(1,cost.ducat_katakohi);assert.is_truthy(cost.dead_mans_sulphur>0)
 end)
 it("rejects unsupported item states and labels calculated probabilities as sampled",function()
  local noSockets=sim.model("Rarity: NORMAL\nIron Gauntlets\nItem Level: 86")
  local allowed,reason=require("Modules.CraftingAvailability").check(action.method,noSockets.initial,noSockets)
  assert.is_false(allowed);assert.matches("socket",reason)
  assert.is_false(pcall(sim.perform,"Rarity: NORMAL\nIron Hat\nItem Level: 86\nSockets: R-R",action,1))
  local model=sim.model(raw);local corrupted=copyTable(model.initial);corrupted.corrupted=true
  assert.is_false(pcall(sim.action,model,corrupted,action,function() return 0.5 end))
  local result=sim.calculate(raw,action,{{scope="enchant",anyOf={"DeepwaterTattooEnchantStrGlobalFireDamage"}}},nil,{trials=20})
  assert.is_true(result.sampled);assert.is_truthy(result.warnings[1].code=="katakohi_assumptions")
 end)
end)
