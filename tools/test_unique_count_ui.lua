-- Kept separate because the main UI scenario approaches LuaJIT's jump limit.
return function(build,ui,frame)
	local project={id="unique-count-ui",title="Unique socket count",slot="Helmet",startingItem="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B\nCorrupted",goals={},steps={}}
	build.savers.CraftingProjects:Upsert(project);local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
	ui:click("socketCount");ui:choose("count",4,"val");frame("crafting-unique-count-menu");ui:click("apply");frame("crafting-unique-count-result")
	ui:click("benchLink");ui:click("resources")
	local lines={};for _,row in ipairs(main.popups[1].controls.results.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;local text=table.concat(lines," ")
	for _,expected in ipairs({"Jeweller's Orb: 10","Orb of Fusing: 5","Vaal Orb: 15"}) do assert(text:find(expected,1,true),expected) end
	ui:click("close");ui:click("undo");ui:click("resources");lines={};for _,row in ipairs(main.popups[1].controls.results.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;text=table.concat(lines," ")
	assert(text:find("Vaal Orb: 10",1,true) and not text:find("Orb of Fusing",1,true),"Undo did not update preview resources")
	ui:click("close");ui:click("redo");ui:click("guide");ui:click("recipe")
	local saved;for _,entry in ipairs(build.savers.CraftingProjects.projects) do if entry.id==project.id then saved=entry;break end end
	assert(saved and saved.steps[1].uniqueCraft.method=="socket_count_bench" and saved.steps[2].uniqueCraft.method=="socket_bench","Socket-count guide lost its actions")
	assert(saved.nativeRecipe and saved.nativeRecipe.requirements.exactSockets==4,"Socket-count recipe did not preserve its exact target")
	main.popups={}
end
