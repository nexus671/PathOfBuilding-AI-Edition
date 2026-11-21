return function(build,ui,frame)
	local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local sim=require("Modules.CraftingSimulator")
	local state=copyTable(sim.model(raw).initial);state.rarity="RARE";state.affixes={{id="IncreasedLife2",range=0.5},{id="FireResist2",range=0.5}}
	require("Classes.CraftingSimulatorControl").Open(build,{id="rog-ui",title="Rog offer",slot="Helmet",startingItem=raw,goals={},steps={},run=require("Modules.CraftingInventory").run(state)})
	ui:click("settings");ui:text("paletteSearch","Rog:");ui:click("paletteUse");assert(not main.popups[1].controls.apply:IsEnabled(),"Unconfigured Rog offer could be applied")
	ui:click("tab_settings");ui:click("configure");frame("crafting-rog-offer")
	ui:choose("operation","remove_lowest_two","val");assert(not main.popups[1].controls.side:IsShown() and main.popups[1].controls.removeHint:IsShown(),"Removal offer did not explain its selection assumption");frame("crafting-rog-removal")
	ui:choose("operation","add","val");ui:choose("side","Suffix","val");ui:choose("attempts",3,"val");ui:text("grand","12");ui:click("keep")
	ui:click("tab_craft");assert(main.popups[1].controls.apply:IsEnabled(),"Configured Rog offer could not be applied");ui:click("item");frame("crafting-rog-result")
	ui:click("keepWorking");local saved;for _,project in ipairs(build.savers.CraftingProjects.projects) do if project.id=="rog-ui" then saved=project end end
	assert(saved and saved.run.configured.rog_reroll.artifactCost.grand==12 and saved.run.configured.rog_reroll.rogOperation=="add","Rog offer was not saved");ui:click("close")
end
