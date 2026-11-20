return function(build,ui,frame)
	local raw="Rarity: NORMAL\nGold Amulet\nItem Level: 86\nImplicits: 3\n+10 to Strength\n+20 to Dexterity\n+20 to Intelligence\nSynthesised Item"
	local blood="Metadata/Items/Currency/CurrencyDelveCraftingVaal";local gilded="Metadata/Items/Currency/CurrencyDelveCraftingSellPrice"
	local project={id="paired-fossil-ui",title="Paired fossils",slot="Amulet",startingItem=raw,goals={},steps={},preferredMethod="fossil"}
	local controls=require("Classes.CraftingSimulatorControl").Open(build,project)
	ui:click("tab_settings");ui:click("configure");ui:choose("fossil1",blood,"id");ui:choose("fossil2",gilded,"id");ui:click("use")
	ui:click("tab_craft");assert(controls.apply:IsEnabled(),"Paired fossils unavailable");frame("crafting-paired-fossil-ready")
	ui:click("apply");assert(controls.intro.label:find("Applied",1,true),"Paired fossils were not applied");frame("crafting-paired-fossil-result")
	ui:click("keepWorking");local saved;for _,entry in ipairs(build.savers.CraftingProjects.projects) do if entry.id==project.id then saved=entry end end
	assert(saved and saved.run.state.fossilImplicitReplacement and saved.run.state.vendorImplicit and #saved.run.state.corruptedImplicits==1,"Combined fossil state was not kept")
	ui:click("close")
end
