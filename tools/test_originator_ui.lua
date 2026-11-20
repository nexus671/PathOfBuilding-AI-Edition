return function(ui,frame)
	ui:click("remove");ui:choose("rarity","normal","val");ui:click("currency");ui:text("search","Chaos Orb")
	do local c=main.popups[1].controls;local detail={};for _,row in ipairs(c.details.list) do detail[#detail+1]=StripEscapes(row[1] or "") end;assert(not c.choose:IsEnabled() and table.concat(detail," "):find("Requires a rare map",1,true),"Incompatible currency did not explain why it is unavailable") end
	frame("map-currency-unavailable");ui:text("search","Orb of Alchemy");frame("map-currency-picker");ui:click("choose")
	assert(main.popups[1].controls.rarity:GetSelValueByKey("val")=="rare","Map Alchemy did not produce a rare map");assert(main.popups[1].controls.remove:IsEnabled(),"Map Alchemy did not add modifiers");frame("map-currency-result")
	ui:click("currency");ui:text("search","Originator's Exalted Orb");frame("map-originator-picker")
	do local c=main.popups[1].controls;local text="";for _,row in ipairs(c.details.list) do text=text..StripEscapes(row[1] or "").." " end;assert(c.choose:IsEnabled() and text:find("rare%-only replacement"),"Originator currency assumptions were not shown") end
	ui:click("choose");assert(main.popups[1].controls.status.label:find("Originator preview",1,true),"Originator result did not disclose its model");frame("map-originator-result")
end
