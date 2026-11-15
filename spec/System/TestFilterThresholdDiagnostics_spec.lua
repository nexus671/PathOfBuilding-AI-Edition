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
end)
