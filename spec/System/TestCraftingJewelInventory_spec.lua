describe("Recorded jewel inventory",function()
 it("persists fractured choices across save, reopen and resume",function()
  newBuild();local sim=require("Modules.CraftingSimulator");local inventory=require("Modules.CraftingInventory")
  local raw="Rarity: NORMAL\nCobalt Jewel\nItem Level: 86";local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="MAGIC"
  state=sim.recordJewelOffers(model,state,{"JunMasterVeiledJewelElusiveEffect","JunMasterVeiledJewelLifeOnBlock"},true)
  local slot;local item=require("Modules.CraftingProjects").item(raw)
  for name in pairs(build.itemsTab.slots) do if name:match("^Jewel %d+$") and build.itemsTab:IsItemValidForSlot(item,name) then slot=name;break end end
  assert.is_truthy(slot);local project={id="jewel-offers",title="Jewel",slot=slot,startingItem=raw,goals={},steps={}}
  project.inventory={inventory.capture(project,state,"Fractured choices")};build.savers.CraftingProjects:Upsert(project)
  local xml=build:SaveDB("Jewel offers");loadBuildFromXML(xml,"Jewel offers")
  local entry=build.savers.CraftingProjects.projects[1].inventory[1];assert.is_true(entry.state.veil.fractured);assert.same(state.veil,entry.state.veil)
  local resumed=inventory.project(entry);assert.same(state.veil,resumed.run.state.veil)
  main.popups={};local controls=require("Classes.CraftingSimulatorControl").Open(build,resumed)
  assert.equal("unveil",controls.method:GetSelValueByKey("val"));assert.equal(state.veil.choices[1],controls.option:GetSelValue().action.modId)
  main.popups={}
  local result=sim.perform(raw,{method="unveil",modId=state.veil.choices[2]},7,resumed.run.state);assert.is_true(result.state.affixes[1].fractured)
 end)
end)
