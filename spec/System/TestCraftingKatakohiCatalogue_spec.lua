-- cspell:ignore Katakohi

describe("Katakohi enchantment catalogue",function()
 local sim=require("Modules.CraftingSimulator")
 it("lists the 24 pinned modifiers without inventing roll probabilities",function()
  local raw="Rarity: NORMAL\nIron Gauntlets\nItem Level: 86"
  local catalog=sim.catalog(raw,"",100);assert.equal(24,#catalog.katakohiEnchants);assert.matches("not probabilities",catalog.katakohiNote)
  for _,row in ipairs(catalog.katakohiEnchants) do assert.equal("-1 to maximum Sockets",row.lines[1]);assert.equal(20,row.requiredLevel);assert.is_nil(row.chance) end
  local movement=sim.catalog(raw,"Movement Speed",100);assert.equal(1,#movement.katakohiEnchants);assert.equal("DeepwaterTattooEnchantDexMovementSpeed",movement.katakohiEnchants[1].id)
  assert.equal(2,#sim.catalog(raw,"",2).katakohiEnchants)
  assert.is_nil(sim.catalog("Rarity: NORMAL\nIron Hat\nItem Level: 86","",100).katakohiEnchants)
 end)
end)

describe("Hypothetical socket enchantments",function()
 local sim=require("Modules.CraftingSimulator")
 local raw="Rarity: NORMAL\nIron Gauntlets\nItem Level: 86\nSockets: W-W-W-W"
 local movement="DeepwaterTattooEnchantDexMovementSpeed"
 local fire="DeepwaterTattooEnchantStrGlobalFireDamage"
 it("previews and saves chosen enchantments with reduced sockets",function()
  newBuild();local model=sim.model(raw);local before=copyTable(model.initial)
  local state=sim.setKatakohi(model,before,{movement,fire})
  assert.same(model.initial,before);assert.equal(2,#state.sockets);assert.equal(2,sim.socketLimit(model,state))
  local item=sim.toItem(model,state);assert.equal(4,#item.enchantModLines);assert.matches("6%% increased Movement Speed",item.raw);assert.matches("20%% increased Fire Damage",item.raw)
  local reopened=sim.model(item.raw);assert.equal(2,sim.socketLimit(reopened,reopened.initial));assert.equal(2,reopened.item.selectableSocketCount)
  runCallback("OnFrame");local beforeSpeed=build.calcsTab.mainOutput.MovementSpeedMod
  build.itemsTab:CreateDisplayItemFromRaw(item.raw);build.itemsTab:AddDisplayItem();runCallback("OnFrame")
  assert.are.near(beforeSpeed+0.06,build.calcsTab.mainOutput.MovementSpeedMod,1e-9)
  local project={id="katakohi",title="Socket enchantments",slot="Gloves",startingItem=raw,goals={},steps={}}
  project.inventory={require("Modules.CraftingInventory").capture(project,state,"Hypothetical gloves")};build.savers.CraftingProjects:Upsert(project)
  local xml=build:SaveDB("Enchanted gloves");loadBuildFromXML(xml,"Enchanted gloves")
  assert.same({movement,fire},build.savers.CraftingProjects.projects[1].inventory[1].state.katakohiEnchants)
 end)
 it("rejects duplicate, unknown and ineligible choices",function()
  local model=sim.model(raw)
  assert.is_false(pcall(sim.setKatakohi,model,model.initial,{movement,movement}))
  assert.is_false(pcall(sim.setKatakohi,model,model.initial,{"unknown"}))
  assert.is_false(pcall(sim.setKatakohi,sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86"),model.initial,{movement}))
  local low=sim.model(raw:gsub("86","10"));assert.is_false(pcall(sim.setKatakohi,low,low.initial,{movement}))
 end)
end)
