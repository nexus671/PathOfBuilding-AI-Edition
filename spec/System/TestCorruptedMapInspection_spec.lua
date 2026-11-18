describe("Corrupted map inspection",function()
 local map=require("Modules.MapCraftingData")
 local atlas=require("Modules.AtlasPlanner")
 local currency=require("Modules.MapCurrency")
 local estimate=require("Modules.MapCraftEstimate")
 local base="Metadata/Items/Maps/MapWorldsBeach"
 local function inspect(selected,corrupted)
  return map.inspect(base,16,83,selected,"",0,100,nil,"rare",nil,corrupted)
 end
 it("inspects and saves up to nine compatible explicit modifiers",function()
  local selected={};for _=1,9 do local page=inspect(selected,true);assert.is_true(#page.candidates>0);selected[#selected+1]=page.candidates[1].id end
  local result=inspect(selected,true);assert.equal(9,result.counts.prefix+result.counts.suffix);assert.equal(0,result.total);assert.matches("per%-side",result.note)
  assert.has_error(function() inspect(selected,false) end)
  local rolls={};for _,id in ipairs(selected) do local values={};for _,stat in ipairs(map.source().mods[id].stats) do values[#values+1]=stat.min end;rolls[#rolls+1]={id=id,values=values} end
  assert.is_truthy(map.inspect(base,16,83,selected,"",0,10,nil,"rare",rolls,true).summary)
  local draft=atlas.validateMapDraft({id="corrupt",title="Corrupted map",patch=map.source().patch,baseId=base,tier=16,itemLevel=83,rarity="rare",selected=selected,rolls=rolls,corrupted=true})
  assert.is_true(draft.corrupted);assert.same(selected,draft.selected);assert.same(rolls,draft.rolls)
  local state={baseId=base,tier=16,itemLevel=83,rarity="rare",selected=selected,corrupted=true}
  assert.has_error(function() currency.perform(state,"chaos",1) end)
  assert.has_error(function() estimate.run(state,{wanted={},avoid={},trials=1,maxAttempts=1,seed=1}) end)
 end)
 it("does not permit ten modifiers or corrupted normal drafts",function()
  local draft={id="x",title="Map",patch=map.source().patch,baseId=base,tier=16,itemLevel=83,rarity="normal",selected={},corrupted=true}
  assert.has_error(function() atlas.validateMapDraft(draft) end)
  local selected={};for _=1,9 do local page=inspect(selected,true);selected[#selected+1]=page.candidates[1].id end
  selected[10]=selected[1];assert.has_error(function() inspect(selected,true) end)
 end)
end)
