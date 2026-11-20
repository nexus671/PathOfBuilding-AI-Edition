return function(build,ui,frame)
	local project={id="unique-colour-ui",title="Unique colours",slot="Helmet",startingItem="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: W-W W W",goals={},steps={}}
	local store=build.savers.CraftingProjects;store:Upsert(project)
	local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
	ui:click("socketCount");frame("crafting-unique-socket-menu");ui:click("colours");frame("crafting-unique-colour-picker")
	ui:click("apply");frame("crafting-unique-colour-preview");ui:click("guide");ui:click("recipe")
	local saved;for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end
	assert(saved and saved.steps[1].uniqueCraft.method=="chromatic" and saved.nativeRecipe.steps[1].method=="chromatic","Unique colour guide or recipe was not kept")
	ui:click("recipe");frame("crafting-unique-colour-result");ui:click("close")
	main.popups={}
	local direct={id="unique-direct-colour-ui",title="Desired colours",slot="Helmet",startingItem=project.startingItem,goals={},steps={}}
	store:Upsert(direct);require("Classes.CraftingUniqueQualityControl").Open(build,direct)
	ui:click("socketCount");ui:click("colours");ui:text("target","RG");main.popups[1].controls.placement:SelByValue("In one linked group");frame("crafting-unique-colour-target");ui:click("plan")
	local planned;for _,entry in ipairs(store.projects) do if entry.id==direct.id then planned=entry end end
	assert(planned and planned.nativeRecipe.requirements.socketColours=="RG" and planned.nativeRecipe.requirements.linkedColours and planned.steps[1].uniqueCraft.method=="chromatic","Direct colour plan was not kept")
	ui:click("socketCount");ui:click("colours");ui:text("target","RR");ui:click("plan");frame("crafting-unique-colour-replace");ui:click("confirm")
	for _,entry in ipairs(store.projects) do if entry.id==direct.id then planned=entry end end
	assert(planned.nativeRecipe.requirements.socketColours=="RR" and #planned.steps==1 and planned.steps[1].stopWhen=="At least RR sockets in any order","Colour guide did not follow the replacement");main.popups={}
end
