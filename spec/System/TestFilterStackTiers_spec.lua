describe("Stack tier rule generation",function()
 local stack=require("Modules.LootFilterStackTiers")
 local parser=require("Modules.LootFilterParser")
 it("preserves source conditions and applies the chosen tier's complete appearance at the threshold",function()
  local source='Show\n Class == "Stackable Currency"\n BaseType == "Chaos Orb"\n AreaLevel >= 60\n SetFontSize 25'
  local target='Show\n BaseType == "Divine Orb"\n SetFontSize 45\n SetTextColor 255 0 0\n PlayAlertSound 6 200'
  local rule=stack.rule(source,target,5);local parsed=parser.parse(rule.."\n"..source)
  local below=parser.simulate(parsed,{BaseType="Chaos Orb",Class="Stackable Currency",AreaLevel=75,StackSize=4})
  local above=parser.simulate(parsed,{BaseType="Chaos Orb",Class="Stackable Currency",AreaLevel=75,StackSize=5})
  local other=parser.simulate(parsed,{BaseType="Divine Orb",Class="Stackable Currency",AreaLevel=75,StackSize=5})
  assert.same({"25"},below.styles.SetFontSize);assert.same({"45"},above.styles.SetFontSize);assert.same({"6","200"},above.styles.PlayAlertSound)
  assert.is_nil(other.styles.SetFontSize);assert.is_nil(above.styles.SetBackgroundColor)
  assert.equal("Unknown",parser.simulate(parsed,{BaseType="Chaos Orb",Class="Stackable Currency",AreaLevel=75}).action)
  local hidden=stack.rule(source,target:gsub("^Show","Hide"),5)
  assert.equal("Hide",parser.simulate(parser.parse(hidden.."\n"..source),{BaseType="Chaos Orb",Class="Stackable Currency",AreaLevel=75,StackSize=5}).action)
 end)
 it("rejects invalid thresholds, continuation and unknown target directives",function()
  local source='Show\n BaseType == "Chaos Orb"';local target='Show\n BaseType == "Divine Orb"'
  for _,n in ipairs({0,1,2.5,1000000001}) do assert.has_error(function() stack.rule(source,target,n) end) end
  assert.has_error(function() stack.rule(source.."\n Continue",target,3) end)
  assert.has_error(function() stack.rule(source,target.."\n FutureDirective 1",3) end)
  assert.has_error(function() stack.rule(source.."\n StackSize < 5",target,5) end)
  assert.has_no.errors(function() stack.rule(source.."\n StackSize <= 5",target,5) end)
 end)
 it("compiles and shares descending stack thresholds with tier changes",function()
  local filters=require("Modules.LootFilters");local editing=require("Modules.LootFilterEditing")
  local p=filters.profile("stacks","Stacks");p.template='Show\n BaseType == "Chaos Orb"\n SetFontSize 12'
  p.tiers={editing.newTier("low","Low",'Show\n Class == "Stackable Currency"\n BaseType == "Chaos Orb"\n SetFontSize 20'),
   editing.newTier("mid","Mid",'Show\n BaseType == "Divine Orb"\n SetFontSize 30'),editing.newTier("high","High",'Show\n BaseType == "Mirror of Kalandra"\n SetFontSize 45')}
  p.tiers[1].items={"Chaos Orb"};p.tiers[2].items={"Divine Orb"};p.tiers[3].items={"Mirror of Kalandra"}
  p.tiers[1].stackRules={{minimum=5,styleTierId="mid"},{minimum=10,styleTierId="high"}}
  local validated=filters.validate({schemaVersion=1,activeId=p.id,profiles={p}}).profiles[1]
  assert.same(p.tiers[1].stackRules,validated.tiers[1].stackRules)
  for _,case in ipairs({{1,"20"},{5,"30"},{10,"45"}}) do
   local result=filters.simulate(p,{BaseType="Chaos Orb",Class="Stackable Currency",StackSize=case[1]})
   assert.same({case[2]},result.styles.SetFontSize)
  end
  local outline=require("Modules.LootFilterStructure").outline(p);assert.is_truthy(outline.entries[1].title:find("10+ stack",1,true))
  local module=editing.module(p,"export","Export");assert.equal(5,#module.rules)
  local before=copyTable(p);before.tiers[1].stackRules=nil
  local changes=editing.review({profiles={before}},{profiles={p}});assert.is_truthy(table.concat(changes[1].details,"\n"):find("5+ uses Mid",1,true))
  p.tiers[3].text=p.tiers[3].text:gsub("45","42");assert.same({"42"},filters.simulate(p,{BaseType="Chaos Orb",Class="Stackable Currency",StackSize=10}).styles.SetFontSize)
  p.rules={{id="personal",title="Personal override",text='Show\n BaseType == "Chaos Orb"\n SetFontSize 17',enabled=true}}
  assert.same({"17"},filters.simulate(p,{BaseType="Chaos Orb",Class="Stackable Currency",StackSize=10}).styles.SetFontSize)
 end)
 it("rejects unresolved, duplicate, self-referencing or unsupported stack rules",function()
  local editing=require("Modules.LootFilterEditing")
  local a=editing.newTier("a","A");local b=editing.newTier("b","B")
  for _,rules in ipairs({{{minimum=1,styleTierId="b"}},{{minimum=5,styleTierId="missing"}},{{minimum=5,styleTierId="a"}},{{minimum=5,styleTierId="b"},{minimum=5,styleTierId="b"}}}) do
   a.stackRules=rules;assert.has_error(function() editing.validateTiers({a,b}) end)
  end
  a.stackRules={};for n=2,20 do a.stackRules[#a.stackRules+1]={minimum=n,styleTierId="b"} end
  assert.equal(19,#editing.validateTiers({a,b})[1].stackRules)
  a.stackRules={{minimum=5,styleTierId="b"}};b.text=b.text.."\n Continue";assert.has_error(function() editing.validateTiers({a,b}) end)
 end)

 it("retains stack rules across all bundled strictness exports",function()
  local filters=require("Modules.LootFilters");local editing=require("Modules.LootFilterEditing")
  local p=filters.profile("variants","Variants")
  local low=editing.newTier("low","Low",'Show\n Class == "Stackable Currency"\n BaseType == "Chaos Orb"\n SetFontSize 20')
  local high=editing.newTier("high","High",'Show\n BaseType == "Divine Orb"\n SetFontSize 45')
  low.items={"Chaos Orb"};high.items={"Divine Orb"};low.stackRules={{minimum=5,styleTierId="high"}};p.tiers={low,high}
  local variants=filters.variants(p);assert.equal(7,#variants)
  for _,variant in ipairs(variants) do
   local result=parser.simulate(parser.parse(variant.text),{BaseType="Chaos Orb",Class="Stackable Currency",StackSize=5})
   assert.same({"45"},result.styles.SetFontSize)
  end
 end)

end)
