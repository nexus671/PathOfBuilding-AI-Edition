describe('Collective loot-filter priority conflicts',function()
 local parser=require('Modules.LootFilterParser');local diagnostics=require('Modules.LootFilterDiagnostics')
 local a='Hide\n BaseType == "Chaos Orb"\n ItemLevel >= 70\n'
 local b='Show\n BaseType == "Divine Orb"\n ItemLevel >= 70\n'
 local target='Show\n BaseType == "Chaos Orb" "Divine Orb"\n ItemLevel >= 70'
 it('reports coverage by multiple terminating blocks and preserves their lines',function()
  local parsed=parser.parse(a..b..target);local result=diagnostics.shadowing(parsed)
  assert.equal(1,#result);assert.equal(parsed.rules[1].line,result[1].shadowedBy)
  assert.same({parsed.rules[1].line,parsed.rules[2].line},result[1].shadowedByLines);assert.matches('collectively',result[1].warning,1,true)
  for _,base in ipairs({'Chaos Orb','Divine Orb'}) do for _,level in ipairs({69,70,80}) do
   local item={BaseType=base,ItemLevel=level};local later=true
   for _,condition in ipairs(parsed.rules[3].conditions) do if not parser.condition(condition,item) then later=false end end
   local actual=parser.simulate(parsed,item);if later then assert.is_true(actual.line<parsed.rules[3].line) end
  end end
 end)
 it('does not claim coverage from continuing, partial or differently constrained rules',function()
  assert.equal(0,#diagnostics.shadowing(parser.parse(a:gsub('ItemLevel >= 70\n','ItemLevel >= 70\n Continue\n')..b..target)))
  assert.equal(0,#diagnostics.shadowing(parser.parse(a..b..target:gsub('"Divine Orb"','"Divine Orb" "Exalted Orb"'))))
  assert.equal(0,#diagnostics.shadowing(parser.parse(a..b:gsub('>= 70','>= 80')..target)))
 end)
 it('reports all contributing blocks when three lists are required',function()
  local raw=a..b..'Hide\n BaseType == "Exalted Orb"\n ItemLevel >= 70\n'..target:gsub('"Divine Orb"','"Divine Orb" "Exalted Orb"')
  local parsed=parser.parse(raw);local result=diagnostics.shadowing(parsed)
  assert.equal(1,#result);assert.same({parsed.rules[1].line,parsed.rules[2].line,parsed.rules[3].line},result[1].shadowedByLines)
 end)
 it('keeps the blocker pointer consistent when a different list has an earlier single blocker',function()
  local raw='Hide\n BaseType == "Iron Hat" "Wool Shoes"\n Class == "Helmets" "Boots" "Gloves"\n'..
   'Hide\n BaseType == "Iron Hat"\n Class == "Helmets" "Boots"\n'..
   'Hide\n BaseType == "Wool Shoes"\n Class == "Helmets" "Boots"\n'..
   'Show\n BaseType == "Iron Hat" "Wool Shoes"\n Class == "Helmets" "Boots"'
  local parsed=parser.parse(raw);local last
  for _,entry in ipairs(diagnostics.shadowing(parsed)) do if entry.line==parsed.rules[4].line then last=entry end end
  assert.is_true(last~=nil);assert.equal(parsed.rules[1].line,last.shadowedBy);assert.is_nil(last.shadowedByLines)
 end)
 it('works for class lists and points the structure view at the first blocker',function()
  local filters=require('Modules.LootFilters');local structure=require('Modules.LootFilterStructure');local p=filters.profile('union-test','Union test')
  p.template='Hide\n Class == "Helmets"\nHide\n Class == "Boots"\nShow\n Class == "Helmets" "Boots"'
  local view=structure.outline(p);local conflicts=structure.filter(view,'',nil,nil,'Priority conflicts');assert.equal(1,#conflicts)
  local d=structure.diagnostics(view,conflicts[1])[1];assert.equal(2,#d.shadowedByLines);assert.equal(d.shadowedBy,structure.blockingEntry(view,conflicts[1]).line)
  local blockers=structure.blockingEntries(view,conflicts[1]);assert.equal(2,#blockers);assert.same(d.shadowedByLines,{blockers[1].line,blockers[2].line})
 end)
 it('agrees with exhaustive exact-list coverage for small item sets',function()
  local values={'Chaos Orb','Divine Orb','Exalted Orb'}
  local function included(mask,index) return math.floor(mask/2^(index-1))%2==1 end
  local function names(mask) local out={};for i,value in ipairs(values) do if included(mask,i) then out[#out+1]='"'..value..'"' end end;return table.concat(out,' ') end
  for first=1,7 do for second=1,7 do for last=1,7 do
   local raw='Hide\n BaseType == '..names(first)..'\nShow\n BaseType == '..names(second)..'\nHide\n BaseType == '..names(last)
   local parsed=parser.parse(raw);local covered=true
   for i=1,#values do if included(last,i) and not included(first,i) and not included(second,i) then covered=false end end
   local detected=false;for _,d in ipairs(diagnostics.shadowing(parsed)) do if d.line==parsed.rules[3].line then detected=true end end
   assert.equal(covered,detected,raw)
  end end end
 end)
end)
