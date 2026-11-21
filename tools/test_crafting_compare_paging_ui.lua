return function(ui, frame, build, sim, jobs)
	local compareRaw="Rarity: NORMAL\nIron Hat\nItem Level: 86"
	local model=sim.model(compareRaw)
	local c=require("Classes.CraftingCompareControl").Open(build,compareRaw,model.initial,{}, {minAffixes=1},nil,{method="transmute"},nil,{budget=1,trials=2,seed=1,currency="chaos"})
	for i=1,3 do ui:choose("route"..i,1,"val") end
	ui:text("price1","11")
	ui:click("addRoute");ui:choose("route1",1,"val");ui:text("price1","44")
	ui:click("addRoute");ui:choose("route2",1,"val");ui:text("price2","55")
	frame("crafting-many-recipe-routes")
	ui:click("previousPage");assert(c.price1.buf=="11");ui:click("nextPage");assert(c.price1.buf=="44" and c.price2.buf=="55")
	ui:click("run");for i=1,2000 do if not jobs.job then break end;jobs.tick(build) end
	assert(not jobs.job,"Many-route comparison did not finish")
	ui:click("charts");local chart=main.popups[1].controls;assert(chart.nextPage:IsEnabled());ui:click("nextPage")
	assert(StripEscapes(chart.legend1.label()):find("Route 4",1,true));frame("crafting-many-recipe-chart")
	ui:click("copy");assert(ui.clipboard:find("Route 1:",1,true) and ui.clipboard:find("Route 5:",1,true))
	ui:click("close");ui:click("close")
	do
		local rare=sim.perform(compareRaw,{method="alchemy"},1).state
		local essences=sim.actionOptions(model,rare,"essence");local harvest=sim.actionOptions(model,rare,"harvest_reforge")
		assert(#essences>=2 and #harvest>0,"Expected Essence and Harvest options")
		local control=require("Classes.CraftingCompareControl").Open(build,compareRaw,rare,{}, {minAffixes=1},nil,essences[2].action,nil,{budget=1,trials=2,seed=1,currency="chaos"})
		ui:choose("route1",essences[1].label,"label");ui:choose("route2",essences[2].label,"label")
		local harvestLabel=require("Modules.CraftingWorkbench").actionLabel(harvest[1].action,model);ui:choose("route3",harvestLabel,"label")
		ui:text("price1","11");ui:text("price2","22");ui:text("price3","33");frame("crafting-comparison-choices")
		ui:click("run");for i=1,2000 do if not jobs.job then break end;jobs.tick(build) end;assert(not jobs.job,"Choice comparison did not finish")
		local lines={};for _,row in ipairs(control.results.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;local results=table.concat(lines," ")
		assert(results:find(essences[1].label,1,true) and results:find(essences[2].label,1,true) and results:find(harvestLabel,1,true),"Compared choices were not identified")
		ui:click("close")
	end
	do
		local c=require("Classes.CraftingCompareControl").Open(build,compareRaw,model.initial,{}, {minAffixes=1},nil,{method="transmute"},nil,{budget=2,trials=2,seed=1,currency="chaos"})
		ui:click("edit1");ui:click("add");frame("crafting-comparison-edit-recipe");ui:click("keep")
		ui:click("edit2");ui:click("add");ui:click("keep");frame("crafting-comparison-custom-recipes")
		assert(c.route1:GetSelValue().label:find("Custom recipe 1",1,true) and c.route2:GetSelValue().label:find("Custom recipe 2",1,true),"Comparison lost edited recipes")
		ui:click("run");for i=1,2000 do if not jobs.job then break end;jobs.tick(build) end;assert(not jobs.job,"Custom recipe comparison did not finish")
		local lines={};for _,row in ipairs(c.results.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;local results=table.concat(lines," ")
		assert(results:find("Custom recipe 1",1,true) and results:find("Custom recipe 2",1,true),"Custom recipe results were not identified")
		ui:click("close")
	end
	do
		local store=build.savers.CraftingProjects;local original=copyTable(store.projects)
		local project={id="comparison-keep-test",title="Comparison keep test",slot="Helmet",startingItem=compareRaw,goals={},steps={},preferredMethod="alchemy",nativeRecipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1}}}
		store:Upsert(project);require("Classes.CraftingSimulatorControl").Open(build,project)
		ui:choose("page","Simulate recipe");ui:click("compareRecipes");ui:click("edit1");ui:click("add");ui:click("keep");frame("crafting-comparison-keep-route")
		ui:click("keep1");frame("crafting-comparison-keep-confirm");ui:click("confirm");assert(main.popups[1].title=="Recipe kept");ui:click("close")
		local saved;for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end
		assert(saved and #saved.nativeRecipe.steps==2 and saved.nativeRecipe.initialState.rarity=="NORMAL","Kept comparison recipe lost its state")
		ui:click("alternative1");ui:text("name","Test route");frame("crafting-alternative-save");ui:click("save");ui:click("close")
		ui:choose("route1","Saved: Test route","label");ui:click("edit1");ui:click("add");ui:click("keep");ui:click("alternative1");frame("crafting-alternative-update");ui:click("update");frame("crafting-alternative-update-confirm");ui:click("confirm");ui:click("close")
		assert(#store.projects[#store.projects].recipeAlternatives[1].recipe.steps==3,"Alternative update was not saved")
		ui:click("manageAlternatives");local popup=main.popups[1].controls;local x,y=popup.list:GetPos();ui:clickAt(x+20,y+12);ui:text("name","Renamed route");frame("crafting-alternative-manage");ui:click("rename")
		assert(store.projects[#store.projects].recipeAlternatives[1].name=="Renamed route","Alternative rename was not saved")
		ui:click("use");ui:click("confirm");ui:click("close");ui:click("remove");ui:click("confirm");assert(#store.projects[#store.projects].recipeAlternatives==0,"Alternative removal was not saved")
		ui:click("close");ui:click("close");ui:click("close");store.projects=original
	end

end
