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
 it("rejects invalid thresholds and unknown target directives",function()
  local source='Show\n BaseType == "Chaos Orb"';local target='Show\n BaseType == "Divine Orb"'
  for _,n in ipairs({0,1,2.5,1000000001}) do assert.has_error(function() stack.rule(source,target,n) end) end
  assert.is_true(parser.parse(stack.rule(source.."\n Continue",target,3)).rules[1].continue)
  assert.is_falsy(parser.parse(stack.rule(source,target.."\n Continue",3)).rules[1].continue)
  assert.has_error(function() stack.rule(source,target.."\n FutureDirective 1",3) end)
  assert.has_error(function() stack.rule(source.."\n StackSize < 5",target,5) end)
  assert.has_no.errors(function() stack.rule(source.."\n StackSize <= 5",target,5) end)
  assert.has_error(function() stack.rule(source.."\n StackSize >= 10",target,5,10) end)
  assert.has_error(function() stack.rule(source.."\n StackSize == 10",target,5,10) end)
  assert.has_error(function() stack.rule(source.."\n StackSize > 9",target,5,10) end)
  assert.has_no.errors(function() stack.rule(source.."\n StackSize >= 9",target,5,10) end)
  assert.has_no.errors(function() stack.rule(source.."\n StackSize >= 10 9",target,5,10) end)
 end)
 it("preserves unverified continue arguments in generated tiers",function()
  local source='Show\n BaseType == "Chaos Orb"\n Continue unexpected';local target='Show\n BaseType == "Divine Orb"\n SetFontSize 40'
  local generated=stack.rule(source,target,5);assert.is_truthy(generated:find('Continue unexpected',1,true))
  local result=parser.simulate(parser.parse(generated),{BaseType="Chaos Orb",StackSize=5})
  assert.equal("unknown",result.status);assert.equal("Unknown",result.action)
  local editing=require("Modules.LootFilterEditing");local low=editing.newTier("low","Low",source);local high=editing.newTier("high","High",target)
  low.items={"Chaos Orb"};high.items={"Divine Orb"};low.stackRules={{minimum=5,styleTierId="high"}}
  local rules=editing.tierRules(editing.validateTiers({low,high}));assert.is_truthy(rules[1].text:find('Continue unexpected',1,true))
 end)
 it("rejects combined stack conditions only when no integer in the tier can match",function()
  local target='Show\n BaseType == "Divine Orb"';local base='Show\n BaseType == "Chaos Orb"'
  local conditions={'StackSize < 4','StackSize <= 4.5','StackSize > 4','StackSize >= 4.5',
   'StackSize == 3 5','StackSize == 4.5','StackSize != 3 4','StackSize != 5 6'}
  for _,first in ipairs(conditions) do for _,second in ipairs(conditions) do
   local source=base..'\n '..first..'\n '..second;local parsed=parser.parse(source);local possible=false
   for size=3,5 do if parser.simulate(parsed,{BaseType="Chaos Orb",StackSize=size}).line then possible=true end end
   local ok=pcall(stack.rule,source,target,3,6);assert.equal(possible,ok,first.." / "..second)
  end end
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
  a.stackRules={{minimum=5,styleTierId="b"}};b.text=b.text.."\n Continue";assert.has_no.errors(function() editing.validateTiers({a,b}) end)
 end)
 it("rejects an incompatible bulk stack change without mutating any tier",function()
  local editing=require("Modules.LootFilterEditing")
  local a=editing.newTier("a","A");local b=editing.newTier("b","B",'Show\n BaseType == "Chaos Orb"\n StackSize < 5')
  local style=editing.newTier("style","Style");local input={a,b,style};local before=copyTable(input)
  local ok,why=pcall(editing.setStackStyle,input,{"a","b"},5,"style")
  assert.is_false(ok);assert.is_truthy(tostring(why):find("B:",1,true));assert.same(before,input)
  assert.has_error(function() editing.setStackStyle(input,{"style"},5,"style") end)
	  local c=editing.newTier("c","Continuing",'Show\n BaseType == "Chaos Orb"\n StackSize >= 10\n Continue')
	  c.stackRules={{minimum=10,styleTierId="style"}};local continued={c,style}
	  assert.has_error(function() editing.setStackStyle(continued,{"c"},5,"style") end)
	  assert.equal(1,#continued[1].stackRules)
 end)

 it("preserves continuing source flow with mutually exclusive stack ranges",function()
  local editing=require("Modules.LootFilterEditing")
  local low=editing.newTier("low","Low",'Show\n BaseType == "Chaos Orb"\n SetFontSize 20\n Continue')
  local mid=editing.newTier("mid","Mid",'Hide\n BaseType == "Divine Orb"\n SetFontSize 30\n Continue')
  local high=editing.newTier("high","High",'Show\n BaseType == "Mirror of Kalandra"\n SetFontSize 45')
  low.items={"Chaos Orb"};mid.items={"Divine Orb"};high.items={"Mirror of Kalandra"}
  low.stackRules={{minimum=5,styleTierId="mid"},{minimum=10,styleTierId="high"}}
  local rules=editing.tierRules(editing.validateTiers({low,mid,high}));local lines={}
  for _,rule in ipairs(rules) do lines[#lines+1]=rule.text end
  lines[#lines+1]='Show\n BaseType == "Chaos Orb"\n SetBorderColor 1 2 3'
  local parsed=parser.parse(table.concat(lines,"\n"))
  for _,case in ipairs({{1,"20"},{4,"20"},{5,"30"},{9,"30"},{10,"45"},{20,"45"}}) do
   local result=parser.simulate(parsed,{BaseType="Chaos Orb",StackSize=case[1]})
   assert.equal("Show",result.action);assert.same({case[2]},result.styles.SetFontSize);assert.same({"1","2","3"},result.styles.SetBorderColor)
   assert.equal(2,#result.matches,"Only one tier and the later rule should match")
  end
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
