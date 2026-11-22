return function(build,ui,frame)
	ui:click("nav_tools")
	do local browser=main.popups[1].controls;local selected;for _,row in ipairs(browser.results.list) do if row.entry and row.entry.id=="baseSets" then selected=row;break end end;assert(selected,"Same-base review is missing from planning tools");browser.results.onClick({line=selected});ui:click("choose") end
	frame("vendor-base-empty")
	for _,raw in ipairs({"Rarity: Normal\nJade Amulet","Rarity: Magic\nJade Amulet of the Lynx","Rarity: Rare\nDoom Beads\nJade Amulet","Rarity: Unique\nKarui Ward\nJade Amulet"}) do ui.clipboard="Item Class: Amulets\n"..raw.."\n--------\nItem Level: 60";ui:click("paste") end
	do local c=main.popups[1].controls;assert(c.entries.list[2][1]:find("Jade Amulet",1,true) and c.entries.list[2][3]:find("1",1,true),"Same-base set was not displayed") end
	frame("vendor-base-complete");ui:click("undo");assert(main.popups[1].controls.entries.list[2][3]:find("0",1,true));ui:click("undo");assert(main.popups[1].controls.entries.list[2][3]:find("1",1,true))
	ui:click("clear");assert(#main.popups[1].controls.entries.list==1);ui:click("undo");assert(#main.popups[1].controls.entries.list==2);ui:click("close")
	ui:click("nav_tools");do local browser=main.popups[1].controls;local selected;for _,row in ipairs(browser.results.list) do if row.entry and row.entry.id=="baseSets" then selected=row;break end end;assert(selected);browser.results.onClick({line=selected});ui:click("choose") end
	assert(main.popups[1].controls.status.label:find("4 pasted",1,true),"Same-base review lost its working items");frame("vendor-base-reopened");ui:click("close")
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
	do local c=main.popups[1].controls;local lines={};for _,row in ipairs(c.details.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;local text=table.concat(lines," ");assert(text:find("Chaos Orb",1,true) and text:find("#1 Helmet: Example Base",1,true) and text:find("#9 Two hand: Example Base",1,true) and text:find("Item level 70 | Set 1",1,true),"Rare set pieces or selected assignment not displayed") end
	frame("vendor-rare-set");ui:click("close");ui:click("nav_tools");do local browser=main.popups[1].controls;for _,row in ipairs(browser.results.list) do if row.entry and row.entry.id=="rareSets" then browser.results.onClick({line=row});break end end;ui:click("choose") end
	assert(main.popups[1].controls.status.label:find("9 pasted",1,true),"Rare set items not retained");ui:click("clear")
	for _,class in ipairs({"Helmets","Body Armours","Gloves","Boots","Amulets","Belts","Rings","Rings","Bows","One Hand Swords","Shields"}) do
		local level=class=="Bows" and 40 or 80;ui.clipboard="Item Class: "..class.."\nRarity: Rare\nExample Base\n--------\nItem Level: "..level.."\n--------\nUnidentified";ui:click("paste")
	end
	do local c=main.popups[1].controls;local lines={};for _,row in ipairs(c.details.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;local text=table.concat(lines," ");assert(text:find("Regal Orb",1,true) and text:find("Remaining: #9",1,true),"Higher-level weapon combination was not selected");c.details.controls.scrollBar.offset=100;for _,row in ipairs(c.entries.list) do if row.itemIndex==9 then c.entries.onClick({line=row});break end end;assert(c.details.controls.scrollBar.offset==0,"Selected item summary should be visible");lines={};for _,row in ipairs(c.details.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;assert(table.concat(lines," "):find("Item level 40 | Unassigned",1,true),"Selected unassigned item was not explained") end
	frame("vendor-rare-set-weapon-choice")
	ui.clipboard="Item Class: Helmets\nRarity: Rare\nExample Base\n--------\nItem Level: 68\n--------\nUnidentified";ui:click("paste");ui:choose("preference","chaos","val")
	do local c=main.popups[1].controls;local lines={};for _,row in ipairs(c.details.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;local text=table.concat(lines," "):gsub("%s+"," ");assert(text:find("Chaos Orb",1,true),"Chaos preference did not select a Chaos set");assert(text:find("Maximum set count under modeled rules",1,true),"Modeled maximum proof was not shown") end
	frame("vendor-rare-set-chaos");ui:click("close")
	require("Classes.VendorRareSetsControl").Open(build);assert(main.popups[1].controls.preference:GetSelValueByKey("val")=="chaos","Rare-set preference was not retained");ui:click("clear")
	for _,class in ipairs({"Helmets","Body Armours","Gloves","Boots","Amulets","Belts","Rings","Rings","Bows","One Hand Swords"}) do
		local level=class=="One Hand Swords" and 70 or 80
		ui.clipboard="Item Class: "..class.."\nRarity: Rare\nExample Base\n--------\nItem Level: "..level.."\n--------\nUnidentified";ui:click("paste")
	end
	do local lines={};for _,row in ipairs(main.popups[1].controls.details.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;local text=table.concat(lines," ");assert(text:find("Chaos-level item or weapon partner",1,true) and text:find("pair the existing",1,true),"Unusable Chaos weapon anchor was not explained") end
	ui:click("clear");ui:click("close")
	ui:click("nav_tools");do local browser=main.popups[1].controls;local selected;for _,row in ipairs(browser.results.list) do if row.entry and row.entry.id=="qualityVendor" then selected=row;break end end;assert(selected,"Quality vendor review is missing");browser.results.onClick({line=selected});ui:click("choose") end
	ui.clipboard="Item Class: Wands\nRarity: Normal\nDriftwood Wand\n--------\nQuality: +20%";ui:click("paste")
	for _,quality in ipairs({18,12,10}) do ui.clipboard="Item Class: Helmets\nRarity: Magic\nSuperior Iron Hat of the Fox\n--------\nQuality: +"..quality.."%";ui:click("paste") end
	ui.clipboard="Item Class: Life Flasks\nRarity: Normal\nSmall Life Flask\n--------\nQuality: +20%";ui:click("paste")
	ui.clipboard="Item Class: Active Skill Gems\nRarity: Gem\nArc\n--------\nQuality: +20%";ui:click("paste")
	ui.clipboard="Item Class: Support Skill Gems\nRarity: Gem\nAdded Fire Damage Support\n--------\nQuality: +21%";ui:click("paste")
	do local c=main.popups[1].controls;local details={};for _,row in ipairs(c.details.list) do details[#details+1]=StripEscapes(row[1] or "") end;local text=table.concat(details," ");assert(text:find("Whetstone",1,true) and text:find("Scrap",1,true) and text:find("Bauble",1,true) and text:find("Prism",1,true) and text:find("40%",1,true) and text:find("above 20% are unverified",1,true),"Quality vendor groups or gem limitation were not displayed") end
	frame("vendor-quality-groups")
	for i=1,5 do ui.clipboard="Item Class: Active Skill Gems\nRarity: Gem\nVaal Arc\n--------"..(i==5 and "\nQuality: +20%" or "");ui:click("paste") end
	do local c=main.popups[1].controls;local details={};for _,row in ipairs(c.details.list) do details[#details+1]=StripEscapes(row[1] or "") end;local text=table.concat(details," ");assert(text:find("Vaal Orb: 1 possible set",1,true) and text:find("items may overlap",1,true) and text:find("Quality unknown",1,true),"Vaal vendor recipe or overlap was not displayed") end
	frame("vendor-vaal-gems")
	do local c=main.popups[1].controls;local selected;for _,row in ipairs(c.entries.list) do if row.itemIndex==12 then selected=row;break end end;assert(selected);c.entries.onClick({line=selected});local details={};for _,row in ipairs(c.details.list) do details[#details+1]=StripEscapes(row[1] or "") end;local text=table.concat(details," ");assert(text:find("Gemcutter's Prism group",1,true) and text:find("Vaal Orb group",1,true),"Overlapping quality and Vaal groups were not shown") end
	ui:click("close")
	ui:click("nav_tools");do local browser=main.popups[1].controls;local selected;for _,row in ipairs(browser.results.list) do if row.entry and row.entry.id=="qualityVendor" then selected=row;break end end;assert(selected);browser.results.onClick({line=selected});ui:click("choose") end
	assert(main.popups[1].controls.status.label:find("12 pasted items",1,true),"Quality vendor review lost its working items");frame("vendor-quality-reopened");ui:click("clear")
	for _,quality in ipairs({18,17,13,12,11,9}) do ui.clipboard="Item Class: Wands\nRarity: Magic\nSuperior Driftwood Wand of the Fox\n--------\nQuality: +"..quality.."%";ui:click("paste") end
	do local c=main.popups[1].controls;local details={};for _,row in ipairs(c.details.list) do details[#details+1]=StripEscapes(row[1] or "") end;assert(table.concat(details," "):find("2 maximum",1,true),"Maximum quality groups were not displayed") end
	frame("vendor-quality-optimal");ui:click("clear")
	for _,quality in ipairs({6,12,18,18,11,8,11,7,5,4,20,1,15,9,15}) do ui.clipboard="Item Class: Wands\nRarity: Magic\nSuperior Driftwood Wand of the Fox\n--------\nQuality: +"..quality.."%";ui:click("paste") end
	do local c=main.popups[1].controls;local details={};for _,row in ipairs(c.details.list) do details[#details+1]=StripEscapes(row[1] or "") end;assert(table.concat(details," "):find("4 maximum",1,true),"Larger quality collection did not find four groups") end
	frame("vendor-quality-larger-optimal")
	do local c=main.popups[1].controls;local selected;for _,row in ipairs(c.entries.list) do if row.itemIndex==11 then selected=row;break end end;assert(selected,"Copied item was not listed");c.entries.onClick({line=selected});local details={};for _,row in ipairs(c.details.list) do details[#details+1]=StripEscapes(row[1] or "") end;local text=table.concat(details," ");assert(text:find("Selected #11",1,true) and text:find("Whetstone group",1,true) and text:find("#11 Superior Driftwood Wand",1,true) and text:find("#14 Superior Driftwood Wand",1,true),"Selected recipe companions were not displayed") end
	frame("vendor-quality-selected-group")
	for _=1,4 do ui.clipboard="Item Class: Wands\nRarity: Magic\nSuperior Driftwood Wand of the Fox\n--------\nQuality: +1%";ui:click("paste") end
	do local c=main.popups[1].controls;local details={};for _,row in ipairs(c.details.list) do details[#details+1]=StripEscapes(row[1] or "") end;assert(table.concat(details," "):find("4 maximum",1,true),"Bounded search did not prove the 19-item result") end
	ui:click("clear");ui:click("close")
end
