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
	ui:click("nav_tools");do local browser=main.popups[1].controls;local selected;for _,row in ipairs(browser.results.list) do if row.entry and row.entry.id=="rareSets" then selected=row;break end end;assert(selected,"Rare set review is missing");browser.results.onClick({line=selected});ui:click("choose") end
	ui.clipboard="Item Class: Rings\nRarity: Rare\nExample Ring\n--------\nItem Level: 70\n--------\nUnidentified";ui:click("paste")
	do local c=main.popups[1].controls;local lines={};for _,row in ipairs(c.details.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;local text=table.concat(lines," ");assert(text:find("Next set needs",1,true) and text:find("1 Ring",1,true) and text:find("Weapon",1,true),"Missing rare-set slots not shown") end
	frame("vendor-rare-set-progress");ui:click("clear")
	for _,class in ipairs({"Helmets","Body Armours","Gloves","Boots","Amulets","Belts","Rings","Rings","Bows"}) do ui.clipboard="Item Class: "..class.."\nRarity: Rare\nExample Base\n--------\nItem Level: 70\n--------\nUnidentified";ui:click("paste") end
	do local c=main.popups[1].controls;local lines={};for _,row in ipairs(c.details.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;assert(table.concat(lines," "):find("Chaos Orb",1,true),"Rare set reward not displayed") end
	frame("vendor-rare-set");ui:click("close");ui:click("nav_tools");do local browser=main.popups[1].controls;for _,row in ipairs(browser.results.list) do if row.entry and row.entry.id=="rareSets" then browser.results.onClick({line=row});break end end;ui:click("choose") end
	assert(main.popups[1].controls.status.label:find("9 pasted",1,true),"Rare set items not retained");ui:click("clear")
	for _,class in ipairs({"Helmets","Body Armours","Gloves","Boots","Amulets","Belts","Rings","Rings","Bows","One Hand Swords","Shields"}) do
		local level=class=="Bows" and 40 or 80;ui.clipboard="Item Class: "..class.."\nRarity: Rare\nExample Base\n--------\nItem Level: "..level.."\n--------\nUnidentified";ui:click("paste")
	end
	do local c=main.popups[1].controls;local lines={};for _,row in ipairs(c.details.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;local text=table.concat(lines," ");assert(text:find("Regal Orb",1,true) and text:find("Remaining: #9",1,true),"Higher-level weapon combination was not selected") end
	frame("vendor-rare-set-weapon-choice")
	ui.clipboard="Item Class: Helmets\nRarity: Rare\nExample Base\n--------\nItem Level: 68\n--------\nUnidentified";ui:click("paste");ui:choose("preference","chaos","val")
	do local c=main.popups[1].controls;local lines={};for _,row in ipairs(c.details.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;assert(table.concat(lines," "):find("Chaos Orb",1,true),"Chaos preference did not select a Chaos set") end
	frame("vendor-rare-set-chaos");ui:click("close")
	require("Classes.VendorRareSetsControl").Open(build);assert(main.popups[1].controls.preference:GetSelValueByKey("val")=="chaos","Rare-set preference was not retained");ui:click("clear");ui:click("close")
	ui:click("nav_tools");do local browser=main.popups[1].controls;local selected;for _,row in ipairs(browser.results.list) do if row.entry and row.entry.id=="qualityVendor" then selected=row;break end end;assert(selected,"Quality vendor review is missing");browser.results.onClick({line=selected});ui:click("choose") end
	ui.clipboard="Item Class: Wands\nRarity: Normal\nDriftwood Wand\n--------\nQuality: +20%";ui:click("paste")
	for _,quality in ipairs({18,12,10}) do ui.clipboard="Item Class: Helmets\nRarity: Magic\nSuperior Iron Hat of the Fox\n--------\nQuality: +"..quality.."%";ui:click("paste") end
	ui.clipboard="Item Class: Life Flasks\nRarity: Normal\nSmall Life Flask\n--------\nQuality: +20%";ui:click("paste")
	ui.clipboard="Item Class: Active Skill Gems\nRarity: Gem\nArc\n--------\nQuality: +20%";ui:click("paste")
	ui.clipboard="Item Class: Support Skill Gems\nRarity: Gem\nAdded Fire Damage Support\n--------\nQuality: +21%";ui:click("paste")
	do local c=main.popups[1].controls;local details={};for _,row in ipairs(c.details.list) do details[#details+1]=StripEscapes(row[1] or "") end;local text=table.concat(details," ");assert(text:find("Whetstone",1,true) and text:find("Scrap",1,true) and text:find("Bauble",1,true) and text:find("Prism",1,true) and text:find("40%",1,true) and text:find("above 20% are unverified",1,true),"Quality vendor groups or gem limitation were not displayed") end
	frame("vendor-quality-groups");ui:click("close")
	ui:click("nav_tools");do local browser=main.popups[1].controls;local selected;for _,row in ipairs(browser.results.list) do if row.entry and row.entry.id=="qualityVendor" then selected=row;break end end;assert(selected);browser.results.onClick({line=selected});ui:click("choose") end
	assert(main.popups[1].controls.status.label:find("7 pasted items",1,true),"Quality vendor review lost its working items");frame("vendor-quality-reopened");ui:click("clear")
	for _,quality in ipairs({18,17,13,12,11,9}) do ui.clipboard="Item Class: Wands\nRarity: Magic\nSuperior Driftwood Wand of the Fox\n--------\nQuality: +"..quality.."%";ui:click("paste") end
	do local c=main.popups[1].controls;local details={};for _,row in ipairs(c.details.list) do details[#details+1]=StripEscapes(row[1] or "") end;assert(table.concat(details," "):find("2 maximum",1,true),"Maximum quality groups were not displayed") end
	frame("vendor-quality-optimal");ui:click("clear");ui:click("close")
end
