return function(ui,frame)
	ui:click("remove");ui:choose("rarity","normal","val");ui:click("currency");ui:text("search","Chaos Orb")
	do local c=main.popups[1].controls;local detail={};for _,row in ipairs(c.details.list) do detail[#detail+1]=StripEscapes(row[1] or "") end;assert(not c.choose:IsEnabled() and table.concat(detail," "):find("Requires a rare map",1,true),"Incompatible currency did not explain why it is unavailable") end
	frame("map-currency-unavailable");ui:text("search","Orb of Alchemy");frame("map-currency-picker");ui:click("choose")
	assert(main.popups[1].controls.rarity:GetSelValueByKey("val")=="rare","Map Alchemy did not produce a rare map");assert(main.popups[1].controls.remove:IsEnabled(),"Map Alchemy did not add modifiers");frame("map-currency-result")
	ui:click("currency");ui:text("search","Originator's Exalted Orb");frame("map-originator-picker")
	do local c=main.popups[1].controls;local text="";for _,row in ipairs(c.details.list) do text=text..StripEscapes(row[1] or "").." " end;assert(c.choose:IsEnabled() and text:find("rare%-only replacement"),"Originator currency assumptions were not shown") end
	ui:click("choose");assert(main.popups[1].controls.status.label:find("Originator preview",1,true),"Originator result did not disclose its model");frame("map-originator-result")
	-- A failed modeled branch must not trap retries on the same random seed.
	local currency=require("Modules.MapCurrency")
	local initial=currency.perform({baseId="Metadata/Items/Maps/MapWorldsAbomination",tier=17,itemLevel=84,rarity="rare",selected={}},"chaos",300).state
	initial.id="originator-retry";initial.title="Retry";initial.patch=require("Modules.MapCraftingData").source().patch
	local clock=os.time;os.time=function() return 2722953 end
	local ok,controls=pcall(require("Classes.MapModifierControl").Open,{initial=initial});os.time=clock;assert(ok,controls)
	local before={};for _,row in ipairs(controls.affixes.list) do before[#before+1]=row[1] end
	ui:click("currency");ui:text("search","Originator's Exalted Orb")
	do local details={};for _,row in ipairs(main.popups[1].controls.details.list) do details[#details+1]=StripEscapes(row[1] or "") end;assert(table.concat(details," "):find("Some random suffix",1,true),"Unsupported branch warning missing") end
	ui:click("choose");assert(main.popups[1].controls.close,"Unsupported branch did not open an explanation");assert(main.popups[1].controls[1].label:find("Try again",1,true),"Retry was not explained");frame("map-originator-unsupported")
	local after={};for _,row in ipairs(controls.affixes.list) do after[#after+1]=row[1] end;assert(tableDeepEquals(before,after),"Unsupported branch changed the draft")
	ui:click("close");ui:click("choose");assert(controls.status.label:find("Originator preview",1,true),"Retry did not select a new branch");frame("map-originator-retry");ui:click("close")

end
