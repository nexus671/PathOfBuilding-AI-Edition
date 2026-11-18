describe("Filter threshold conflict diagnostics",function()
 local parser=require("Modules.LootFilterParser");local diagnostics=require("Modules.LootFilterDiagnostics")
 local function warnings(first,second)
  return diagnostics.shadowing(parser.parse("Show\n "..first.."\nHide\n "..second))
 end
 it("identifies narrower numeric thresholds while respecting strict boundaries",function()
  for _,pair in ipairs({{">= 70",">= 80"},{"> 70",">= 71"},{"<= 80","< 80"},{"< 80","<= 79"},{">= 70","> 70"},{"< 80","< 80"}}) do
   local result=warnings("ItemLevel "..pair[1],"ItemLevel "..pair[2]);assert.equal(1,#result,pair[1].." / "..pair[2]);assert.equal(1,result[1].shadowedBy)
  end
  for _,pair in ipairs({{"> 70",">= 70"},{">= 80",">= 70"},{"< 80","<= 80"},{"<= 70","<= 80"},{">= 70","<= 80"}}) do
   assert.equal(0,#warnings("ItemLevel "..pair[1],"ItemLevel "..pair[2]),pair[1].." / "..pair[2])
  end
 end)
 it("does not infer overlap for different predicates, unions, sockets or continuing rules",function()
  assert.equal(0,#warnings("ItemLevel >= 70","AreaLevel >= 80"))
  assert.equal(0,#warnings("ItemLevel >= 70 80","ItemLevel >= 90"))
  assert.equal(0,#warnings("Sockets >= 3","Sockets >= 4"))
  assert.equal(0,#diagnostics.shadowing(parser.parse("Show\n ItemLevel >= 70\n Continue\nHide\n ItemLevel >= 80")))
  assert.equal(0,#diagnostics.shadowing(parser.parse('Show\n BaseType == "Iron Hat"\n ItemLevel >= 70\nHide\n BaseType == "Wool Shoes"\n ItemLevel >= 80')))
 end)
 it("handles long sequences of progressively broader thresholds",function()
  local lines={};for value=3000,1,-1 do lines[#lines+1]="Show";lines[#lines+1]=" ItemLevel >= "..value end
  assert.equal(0,#diagnostics.shadowing(parser.parse(table.concat(lines,"\n"))))
 end)
 it("keeps mixed-rule conflict reports sound against the evaluator",function()
  local seed=91373;local function random(n) seed=(seed*48271)%2147483647;return seed%n+1 end
  for trial=1,120 do
   local text={};for i=1,12 do text[#text+1]=(i%2==0 and "Hide" or "Show")
    for _,name in ipairs({"ItemLevel","AreaLevel"}) do if random(100)<=65 then text[#text+1]=" "..name.." "..({">",">=","<","<="})[random(4)].." "..(random(6)-1) end end
    if random(100)<=20 then text[#text+1]=" Continue" end
   end
   local parsed=parser.parse(table.concat(text,"\n"));local byLine={};for _,rule in ipairs(parsed.rules) do byLine[rule.line]=rule end
   for _,warning in ipairs(diagnostics.shadowing(parsed)) do local prior,later=byLine[warning.shadowedBy],byLine[warning.line];assert.is_falsy(prior.continue)
    for level=0,6 do for area=0,6 do local item={ItemLevel=level,AreaLevel=area}
     local function matches(rule) for _,condition in ipairs(rule.conditions) do if not parser.condition(condition,item) then return false end end;return true end
     assert.is_false(matches(later) and not matches(prior),"Unsound conflict in trial "..trial)
    end end
   end
  end
 end)
 it("proves reported numeric coverage against the evaluator",function()
  for _,prior in ipairs({"> 0",">= 0","< 5","<= 5"}) do for _,later in ipairs({"> -1",">= 0","> 1",">= 3","< 4","<= 5","< 6"}) do
   local parsed=parser.parse("Show\n ItemLevel "..prior.."\nHide\n ItemLevel "..later)
   if #diagnostics.shadowing(parsed)>0 then for level=-2,8 do
    local first=parser.condition(parsed.rules[1].conditions[1],{ItemLevel=level});local second=parser.condition(parsed.rules[2].conditions[1],{ItemLevel=level})
    assert.is_false(second and not first,prior.." / "..later.." at "..level)
   end end
  end end
 end)
 it("finds exact class and base lists that cover later lists",function()
  for _,key in ipairs({"Class","BaseType"}) do
   assert.equal(1,#warnings(key..' == "Iron Hat" "Wool Shoes"',key..' == "Wool Shoes"'))
   assert.equal(0,#warnings(key..' == "Iron Hat"',key..' == "Iron Hat" "Wool Shoes"'))
   assert.equal(0,#warnings(key..' == "Iron Hat" "Wool Shoes"',key..' == "Wool Shoes" "Other"'))
   assert.equal(0,#warnings(key..' = "Iron Hat" "Wool Shoes"',key..' == "Wool Shoes"'))
   assert.equal(0,#diagnostics.shadowing(parser.parse('Show\n '..key..' == "Iron Hat" "Wool Shoes"\n Continue\nHide\n '..key..' == "Wool Shoes"')))
   local lists={'"Iron Hat"','"Wool Shoes"','"Iron Hat" "Wool Shoes"','"Iron Hat" "Other"'}
   for _,first in ipairs(lists) do for _,second in ipairs(lists) do
    local parsed=parser.parse('Show\n '..key..' == '..first..'\n ItemLevel >= 10\nHide\n '..key..' == '..second..'\n ItemLevel >= 10')
    for _,warning in ipairs(diagnostics.shadowing(parsed)) do
     for _,name in ipairs({"Iron Hat","Wool Shoes","Other","Unrelated"}) do for _,level in ipairs({1,10,20}) do
      local item={[key]=name,ItemLevel=level};local matches=function(rule) for _,condition in ipairs(rule.conditions) do if not parser.condition(condition,item) then return false end end;return true end
      assert.is_false(matches(parsed.rules[2]) and not matches(parsed.rules[1]),warning.warning)
     end end
    end
   end end
  end
  assert.equal(1,#diagnostics.shadowing(parser.parse('Show\n BaseType == "Iron Hat" "Wool Shoes"\n ItemLevel >= 10\nHide\n BaseType == "Wool Shoes"\n ItemLevel >= 20')))
 end)
 it("keeps combined list and threshold conflicts sound",function()
  local lists={'"Iron Hat"','"Wool Shoes"','"Iron Hat" "Wool Shoes"'}
  local limits={"> 10",">= 10",">= 20","< 20","<= 20"}
  for _,first in ipairs(lists) do for _,second in ipairs(lists) do
   for _,a in ipairs(limits) do for _,b in ipairs(limits) do
    local parsed=parser.parse('Show\n BaseType == '..first..'\n ItemLevel '..a..'\nHide\n BaseType == '..second..'\n ItemLevel '..b)
    for _,warning in ipairs(diagnostics.shadowing(parsed)) do
     for _,name in ipairs({"Iron Hat","Wool Shoes","Other"}) do for _,level in ipairs({0,10,11,19,20,21}) do
      local item={BaseType=name,ItemLevel=level};local matches=function(rule) for _,condition in ipairs(rule.conditions) do if not parser.condition(condition,item) then return false end end;return true end
      assert.is_false(matches(parsed.rules[2]) and not matches(parsed.rules[1]),warning.warning)
     end end
    end
   end end
  end end
  assert.equal(0,#diagnostics.shadowing(parser.parse('Show\n BaseType == "Iron Hat" "Wool Shoes"\n ItemLevel >= 10\n Continue\nHide\n BaseType == "Wool Shoes"\n ItemLevel >= 20')))
  assert.equal(0,#diagnostics.shadowing(parser.parse('Show\n BaseType == "Iron Hat"\n ItemLevel >= 10\nHide\n BaseType == "Wool Shoes"\n ItemLevel >= 20')))
  assert.equal(1,#diagnostics.shadowing(parser.parse('Show\n Class == "Boots" "Helmets"\n AreaLevel < 80\nHide\n Class == "Boots"\n AreaLevel <= 70')))
  assert.equal(0,#diagnostics.shadowing(parser.parse('Show\n Class == "Boots" "Helmets"\n AreaLevel < 80\nHide\n Class == "Boots"\n AreaLevel <= 80')))
  assert.equal(0,#diagnostics.shadowing(parser.parse('Show\n Class == "Boots" "Helmets"\n AreaLevel < 80\n Rarity Rare\nHide\n Class == "Boots"\n AreaLevel <= 70\n Rarity Magic')))
 end)
 it("finds two simultaneously narrower bounds without inventing conflicts",function()
  local limits={"> 10",">= 10",">= 20","< 20","<= 20"}
  for _,a in ipairs(limits) do for _,b in ipairs(limits) do for _,c in ipairs(limits) do for _,d in ipairs(limits) do
   local parsed=parser.parse('Show\n ItemLevel '..a..'\n AreaLevel '..b..'\nHide\n AreaLevel '..d..'\n ItemLevel '..c)
   for _,warning in ipairs(diagnostics.shadowing(parsed)) do
    for _,itemLevel in ipairs({0,10,11,19,20,21}) do for _,areaLevel in ipairs({0,10,11,19,20,21}) do
     local item={ItemLevel=itemLevel,AreaLevel=areaLevel};local function matches(rule) for _,condition in ipairs(rule.conditions) do if not parser.condition(condition,item) then return false end end;return true end
     assert.is_false(matches(parsed.rules[2]) and not matches(parsed.rules[1]),warning.warning)
    end end
   end
  end end end end
  local text='Show\n ItemLevel >= 70\n AreaLevel >= 70\nHide\n AreaLevel >= 80\n ItemLevel >= 80'
  assert.equal(1,#diagnostics.shadowing(parser.parse(text)))
  assert.equal(0,#diagnostics.shadowing(parser.parse(text:gsub('Hide',' Continue\nHide'))))
  assert.equal(0,#diagnostics.shadowing(parser.parse(text:gsub('AreaLevel >= 80','AreaLevel >= 60'))))
 end)
end)
