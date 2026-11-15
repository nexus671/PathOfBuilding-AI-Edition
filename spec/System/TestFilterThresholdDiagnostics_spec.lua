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
