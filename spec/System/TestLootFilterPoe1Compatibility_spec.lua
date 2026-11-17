describe("PoE 1 filter compatibility",function()
 local filters=require("Modules.LootFilters")
 local parser=require("Modules.LootFilterParser")
 before_each(function() newBuild();main.popups={} end)
 after_each(function() main.popups={} end)
 it("preserves but blocks PoE 2-only conditions in both game modes",function()
  for _,key in ipairs({"AlwaysShow","HasVaalUniqueMod","IsVaalUnique","WaystoneTier"}) do
   for _,mode in ipairs({"Normal","Ruthless"}) do
    local p=filters.profile("compat","Compatibility");p.mode=mode;p.template="Show";p.rules={{id="legacy",title="Legacy",text="Show\n "..key..(key=="WaystoneTier" and " >= 3" or " True"),enabled=true}}
    p.sampleSets={{id="saved",title="Saved",samples={{BaseType="Iron Hat",AlwaysShow=true}}}}
    local validated=filters.validate({schemaVersion=1,activeId=p.id,profiles={p}});assert.equal(p.rules[1].text,validated.profiles[1].rules[1].text)
    local saver=filters.new(build);saver:Replace(validated);local xml={};saver:Save(xml);local restored=filters.new(build);restored:Load(xml)
    assert.equal(p.rules[1].text,restored.data.profiles[1].rules[1].text);assert.is_true(restored.data.profiles[1].sampleSets[1].samples[1].AlwaysShow)
    local _,report=filters.compile(p);local found;for _,d in ipairs(report.diagnostics) do if d.error and d.error:find(key,1,true) then found=d end end
    assert.is_truthy(found);assert.matches("Path of Exile 2%-only",found.error);assert.is_true(found.line>0)
    local result=filters.simulate(p,{BaseType="Iron Hat",AlwaysShow=true});assert.equal("invalid",result.status);assert.equal("Unknown",result.action)
    local page=filters.simulateExamples(p,"saved",0,1);assert.equal("invalid",page.results[1].result.status);assert.equal("Unknown",page.results[1].result.action)
   end
  end
 end)
 it("detects unsupported conditions in expanded local imports without rewriting them",function()
  local p=filters.profile("imported","Imported");p.template='Import "nested.filter"';p.importFiles={{name="nested.filter",text="Show\n AlwaysShow True"}}
  local raw,report=filters.compile(p);assert.is_truthy(raw:find("AlwaysShow True",1,true));assert.equal('Import "nested.filter"',p.template)
  local found;for _,d in ipairs(report.diagnostics) do if d.error and d.error:find("AlwaysShow",1,true) then found=true end end;assert.is_true(found)
 end)
 it("offers PoE 1 fields for new rules but keeps legacy conditions editable",function()
  local editor=require("Classes.LootFilterControl")
  editor.Conditions({id="clean",title="Clean",text='Show\n BaseType == "Iron Hat"'},function() end)
  local list=main.popups[1].controls.c1key.list;for _,value in ipairs(list) do assert.not_equal("AlwaysShow",value) end;main.popups={}
  editor.Conditions({id="old",title="Old",text='Show\n AlwaysShow True'},function() end)
  local c=main.popups[1].controls;assert.equal("AlwaysShow",c.c1key:GetSelValue());c.c1remove:Click();assert.is_nil(c.c1key)
 end)
 it("continues to support current PoE 1 conditions",function()
  local p=filters.profile("valid","Valid");p.template='Show\n TwiceCorrupted True\n Fated False\n UnidentifiedItemTier >= 4'
  local _,report=filters.compile(p);for _,d in ipairs(report.diagnostics) do assert.is_nil(d.error) end
 end)
 it("keeps every bundled strictness usable in both PoE 1 modes",function()
  for _,mode in ipairs({"Normal","Ruthless"}) do for strictness=0,6 do
   local p=filters.profile("bundled","Bundled");p.mode=mode;p.strictness=strictness
   local _,report=filters.compile(p);for _,d in ipairs(report.diagnostics) do assert.is_nil(d.error,mode.." strictness "..strictness..": "..tostring(d.error)) end
  end end
 end)

end)
