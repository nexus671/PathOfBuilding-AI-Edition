return function(build,ui,frame)
	local project={id="unique-colour-ui",title="Unique colours",slot="Helmet",startingItem="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: W-W W W",goals={},steps={}}
	local store=build.savers.CraftingProjects;store:Upsert(project)
	local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
	ui:click("socketCount");frame("crafting-unique-socket-menu");ui:click("colours");frame("crafting-unique-colour-picker")
	ui:click("apply");frame("crafting-unique-colour-preview");ui:click("guide");ui:click("recipe")
	local saved;for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end
	assert(saved and saved.steps[1].uniqueCraft.method=="chromatic" and saved.nativeRecipe.steps[1].method=="chromatic","Unique colour guide or recipe was not kept")
	ui:click("recipe");local colourTasks=require("Modules.CraftingTasks");assert(colourTasks.job,"Sampled colour recipe did not use a background task");while colourTasks.job do colourTasks.tick(build) end;frame("crafting-unique-colour-result");ui:click("close")
	main.popups={}
	local direct={id="unique-direct-colour-ui",title="Desired colours",slot="Helmet",startingItem=project.startingItem,goals={},steps={}}
	store:Upsert(direct);require("Classes.CraftingUniqueQualityControl").Open(build,direct)
	ui:click("socketCount");ui:click("colours");local picker=main.popups[1].controls
	ui:text("target","WWWW");assert(picker.plan:IsEnabled() and picker.targetHelp.label():find("Already met",1,true),"Already-satisfied colour target was not explained");frame("crafting-unique-colour-already")
	picker.method:SelByValue("omen_trichromatism","val");picker.target:SetText("RRW");assert(not picker.plan:IsEnabled(),"Impossible colour target was enabled");frame("crafting-unique-colour-impossible")
	picker.method:SelByValue("chromatic","val");picker.target:SetText("RG");picker.placement:SelByValue("In one linked group");ui:text("attempts","250");frame("crafting-unique-colour-target");ui:click("plan")
	local planned;for _,entry in ipairs(store.projects) do if entry.id==direct.id then planned=entry end end
	assert(planned and planned.nativeRecipe.requirements.socketColours=="RG" and planned.nativeRecipe.requirements.linkedColours and planned.nativeRecipe.steps[1].maxAttempts==250 and planned.steps[1].onFailure=="Stop after 250 attempts." and planned.steps[1].uniqueCraft.method=="chromatic","Direct colour plan was not kept")
	ui:click("socketCount");ui:click("colours");ui:text("target","RR");ui:click("plan");frame("crafting-unique-colour-replace");ui:click("confirm")
	for _,entry in ipairs(store.projects) do if entry.id==direct.id then planned=entry end end
	assert(planned.nativeRecipe.requirements.socketColours=="RR" and #planned.steps==1 and planned.steps[1].stopWhen=="At least RR sockets in any order","Colour guide did not follow the replacement");main.popups={}
	local socketProject={id="unique-random-sockets-ui",title="Desired sockets",slot="Helmet",startingItem="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B",goals={},steps={}}
	store:Upsert(socketProject);require("Classes.CraftingUniqueQualityControl").Open(build,socketProject)
	ui:click("socketCount");ui:click("roll");ui:text("target","4");ui:text("attempts","250");frame("crafting-unique-socket-target");ui:click("plan")
	local sockets;for _,entry in ipairs(store.projects) do if entry.id==socketProject.id then sockets=entry end end
	assert(sockets and sockets.nativeRecipe.requirements.exactSockets==4 and sockets.nativeRecipe.steps[1].maxAttempts==250 and sockets.steps[1].uniqueCraft.method=="jeweller","Unique socket plan was not kept")
	ui:click("recipe");local socketTasks=require("Modules.CraftingTasks");assert(socketTasks.job,"Socket recipe did not use a background task");while socketTasks.job do socketTasks.tick(build) end;frame("crafting-unique-socket-result");ui:click("close");main.popups={}
	local linkProject={id="unique-random-links-ui",title="Desired links",slot="Helmet",startingItem="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B W",goals={},steps={}}
	store:Upsert(linkProject);require("Classes.CraftingUniqueQualityControl").Open(build,linkProject)
	ui:click("socketCount");ui:click("links");ui:text("target","4");ui:text("attempts","1000");frame("crafting-unique-link-target");ui:click("plan")
	local linked;for _,entry in ipairs(store.projects) do if entry.id==linkProject.id then linked=entry end end
	assert(linked and linked.nativeRecipe.requirements.links==4 and linked.nativeRecipe.steps[1].maxAttempts==1000 and linked.steps[1].uniqueCraft.method=="fusing","Unique link plan was not kept")
	ui:click("recipe");frame("crafting-unique-link-progress");local tasks=require("Modules.CraftingTasks");assert(tasks.job,"Long unique recipe did not use a background task");while tasks.job do tasks.tick(build) end;frame("crafting-unique-link-result");local details={};for _,row in ipairs(main.popups[1].controls.details.list) do details[#details+1]=row[1] end;assert(table.concat(details," "):find("10 trials",1,true),"Long link budget was not checked");ui:click("close")
	ui:click("socketCount");ui:click("links");ui:click("apply");frame("crafting-unique-link-preview");main.popups={}
end
