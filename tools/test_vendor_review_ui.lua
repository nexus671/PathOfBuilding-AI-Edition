return function(build,ui,frame)
	ui:click("nav_tools")
	do local browser=main.popups[1].controls;local selected;for _,row in ipairs(browser.results.list) do if row.entry and row.entry.id=="vendor" then selected=row;break end end;assert(selected,"Vendor review is missing from planning tools");browser.results.onClick({line=selected});ui:click("choose") end
	frame("vendor-rare-empty")
	ui.clipboard="Item Class: Helmets\nRarity: Rare\nVortex Visage\nIron Hat\n--------\nItem Level: 80"
	ui:click("paste");ui.clipboard=ui.clipboard:gsub("Iron Hat","Hubris Circlet");ui:click("paste");ui.clipboard=ui.clipboard:gsub("Hubris Circlet","Iron Hat");ui:click("paste")
	do local c=main.popups[1].controls;assert(c.entries.list[2][1]:find("Vortex Visage",1,true) and c.entries.list[2][3]:find("1 Exalted",1,true),"Vendor triple was not displayed") end
	frame("vendor-rare-match")
	do local c=main.popups[1].controls;local selected;for _,row in ipairs(c.details.list) do if row.itemIndex==2 then selected=row;break end end;assert(selected and selected[1]:find("Hubris Circlet",1,true),"Individual vendor items were not displayed");c.details.onClick({line=selected}) end
	ui:click("remove");assert(main.popups[1].controls.entries.list[2][3]:find("1 Chaos",1,true));frame("vendor-rare-removed");ui:click("undo");ui:click("close")
	ui:click("nav_tools");do local browser=main.popups[1].controls;local selected;for _,row in ipairs(browser.results.list) do if row.entry and row.entry.id=="vendor" then selected=row;break end end;assert(selected);browser.results.onClick({line=selected});ui:click("choose") end
	do local c=main.popups[1].controls;assert(c.entries.list[2][1]:find("Vortex Visage",1,true) and c.entries.list[2][2]:find("1",1,true),"Reopened review lost its working items") end
	frame("vendor-rare-reopened");ui:click("clear");ui:click("close")
end
