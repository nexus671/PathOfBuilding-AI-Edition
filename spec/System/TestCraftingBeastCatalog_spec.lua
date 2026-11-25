describe("Bestiary AI modifier catalogue",function()
 local sim=require("Modules.CraftingSimulator")
 before_each(function() newBuild() end)
 it("pages the selected beast pool without implying action probabilities",function()
  local model=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 20");local state=copyTable(model.initial)
  local action={method="beast_prefix_suffix",beastLevel=86}
  local first=sim.beastCatalog(model,state,action,"",3,0);local second=sim.beastCatalog(model,state,action,"",3,3)
  assert.equal(86,first.beastLevel);assert.equal("Suffix",first.side);assert.is_false(first.usesItemLevel);assert.is_true(first.hasMore)
  assert.equal(3,#first.rows);assert.equal(3,#second.rows);assert.not_equal(first.rows[1].id,second.rows[1].id)
  for _,row in ipairs(first.rows) do assert.equal("Suffix",row.type);assert.is_true(row.level<=86);assert.is_truthy(row.groups) end
  assert.matches("not probabilities",first.note);assert.equal("beast_level_pool",first.warnings[1].code)
  local low=sim.beastCatalog(model,state,{method="beast_suffix_prefix",beastLevel=1},"",100,0)
  for _,row in ipairs(low.rows) do assert.equal("Prefix",row.type);assert.is_true(row.level<=1) end
  local fallback=sim.beastCatalog(model,state,{method="beast_prefix_suffix"},"",1,0);assert.is_true(fallback.usesItemLevel);assert.equal(20,fallback.beastLevel)
  local empty=sim.beastCatalog(model,state,action,"",3,100000);assert.equal(0,#empty.rows);assert.is_false(empty.hasMore)
  assert.has_error(function() sim.beastCatalog(model,state,{method="chaos"},"",3,0) end)
  assert.has_error(function() sim.beastCatalog(model,state,action,"",3,-1) end)
 end)
 it("filters to the current influence and supports text searches",function()
  local model=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 68");local state=copyTable(model.initial);state.influences={"shaper"}
  local expected={};for _,entry in ipairs(sim.beastTargetSource(model,state,86)) do expected[entry.id]=true end
  local page=sim.beastCatalog(model,state,{method="beast_prefix_suffix",beastLevel=86},"resistance",100,0)
  assert.is_true(page.total>0)
  for _,row in ipairs(page.rows) do assert.is_true(expected[row.id]);assert.is_truthy((row.id.." "..row.text):lower():find("resistance",1,true)) end
 end)
 it("uses a recombined item's current base and level",function()
  local model=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 20")
  local raw="Rarity: NORMAL\nLeather Cap\nItem Level: 50";local state=copyTable(model.initial);state.baseItem=raw
  local action={method="beast_prefix_suffix"};local result=sim.beastCatalog(model,state,action,"",100,0)
  local other=sim.model(raw);local direct=sim.beastCatalog(other,other.initial,action,"",100,0)
  assert.equal(50,result.beastLevel);assert.equal(direct.total,result.total);assert.same(direct.rows,result.rows)
 end)

end)
