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
	ui:click("nav_tools");do local browser=main.popups[1].controls;local selected;for _,row in ipairs(browser.results.list) do if row.entry and row.entry.id=="qualityVendor" then selected=row;break end end;assert(selected,"Quality vendor review is missing");browser.results.onClick({line=selected});ui:click("choose") end
	ui.clipboard="Item Class: Wands\nRarity: Normal\nDriftwood Wand\n--------\nQuality: +20%";ui:click("paste")
	for _,quality in ipairs({18,12,10}) do ui.clipboard="Item Class: Helmets\nRarity: Magic\nExample Item\nIron Hat\n--------\nQuality: +"..quality.."%";ui:click("paste") end
	do local c=main.popups[1].controls;local details={};for _,row in ipairs(c.details.list) do details[#details+1]=StripEscapes(row[1] or "") end;local text=table.concat(details," ");assert(text:find("Whetstone",1,true) and text:find("Scrap",1,true) and text:find("40%",1,true),"Quality vendor groups were not displayed") end
	frame("vendor-quality-groups");ui:click("close")
	ui:click("nav_tools");do local browser=main.popups[1].controls;local selected;for _,row in ipairs(browser.results.list) do if row.entry and row.entry.id=="qualityVendor" then selected=row;break end end;assert(selected);browser.results.onClick({line=selected});ui:click("choose") end
	assert(main.popups[1].controls.status.label:find("4 pasted items",1,true),"Quality vendor review lost its working items");frame("vendor-quality-reopened");ui:click("clear")
	for _,quality in ipairs({18,17,13,12,11,9}) do ui.clipboard="Item Class: Wands\nRarity: Magic\nExample Item\nDriftwood Wand\n--------\nQuality: +"..quality.."%";ui:click("paste") end
	do local c=main.popups[1].controls;local details={};for _,row in ipairs(c.details.list) do details[#details+1]=StripEscapes(row[1] or "") end;assert(table.concat(details," "):find("2 maximum",1,true),"Maximum quality groups were not displayed") end
	frame("vendor-quality-optimal");ui:click("clear");ui:click("close")
end
