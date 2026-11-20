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
	local ring="Rarity: NORMAL\nAmethyst Ring\nItem Level: 86\nCatalyst: Prismatic\nCatalystQuality: 20\nImplicits: 2\n+27% to Chaos Resistance\nItem sells for much more to vendors"
	local retainedProject={id="gilded-base-330-ui",title="Gilded ring",slot="Ring 1",startingItem=ring,goals={},steps={}}
	local retained=require("Classes.CraftingSimulatorControl").Open(build,retainedProject)
	ui:click("tab_settings");ui:text("seed","1");ui:click("tab_craft");ui:click("currency_vaal");ui:click("item")
	assert(retained.intro.label:find("Applied",1,true),"Gilded corruption did not apply");frame("crafting-gilded-330-retained")
	ui:click("keepWorking");local retainedSaved;for _,entry in ipairs(build.savers.CraftingProjects.projects) do if entry.id==retainedProject.id then retainedSaved=entry end end
	assert(retainedSaved and retainedSaved.run.state.baseImplicitRetained,"Retained 3.30 implicit was not saved")
	local sim=require("Modules.CraftingSimulator");local model=sim.model(ring);assert(sim.toItem(model,retainedSaved.run.state).baseModList:Sum("BASE",nil,"ChaosResist")==27,"Catalyst-scaled retained value changed")
	ui:click("close");retained=require("Classes.CraftingSimulatorControl").Open(build,retainedSaved)
	local text="";for _,row in ipairs(retained.itemMods.list) do text=text..StripEscapes(row[1] or "").." " end;assert(text:find("Chaos Resistance",1,true),"Reopened craft lost its retained implicit")
	frame("crafting-gilded-330-reopened");ui:click("close")

	local crown="Rarity: NORMAL\nImp Crown\nItem Level: 86\nImplicits: 3\n-1 to Level of Socketed Support Gems\n+1 to Level of Socketed Skill Gems\nItem sells for much more to vendors"
	local crownProject={id="gilded-multiline-ui",title="Gilded crown",slot="Helmet",startingItem=crown,goals={},steps={}}
	local crownControls=require("Classes.CraftingSimulatorControl").Open(build,crownProject)
	ui:click("tab_settings");ui:text("seed","1");ui:click("tab_craft");ui:click("currency_vaal");ui:click("item")
	assert(crownControls.intro.label:find("Applied",1,true),"Gilded crown corruption did not apply");frame("crafting-gilded-multiline-retained")
	ui:click("keepWorking");local crownSaved;for _,entry in ipairs(build.savers.CraftingProjects.projects) do if entry.id==crownProject.id then crownSaved=entry end end
	assert(crownSaved and crownSaved.run.state.baseImplicitRetained,"Retained multi-line implicit was not saved")
	ui:click("close");crownControls=require("Classes.CraftingSimulatorControl").Open(build,crownSaved)
	local crownText="";for _,row in ipairs(crownControls.itemMods.list) do crownText=crownText..StripEscapes(row[1] or "").." " end
	assert(crownText:find("Socketed Support Gems",1,true) and crownText:find("Socketed Skill Gems",1,true),"Reopened crown lost an implicit line")
	frame("crafting-gilded-multiline-reopened");ui:click("close")

end
