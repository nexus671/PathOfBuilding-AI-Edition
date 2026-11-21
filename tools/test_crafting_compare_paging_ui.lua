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
end
