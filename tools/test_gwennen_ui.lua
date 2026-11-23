return function(build,ui,frame)
	do
		local raw="Rarity: RARE\nExample\nIron Hat\nItem Level: 86"
		require("Classes.CraftingSimulatorControl").Open(build,{id="gwennen-ui",title="Gwennen pair",slot="Helmet",startingItem=raw,goals={},steps={}})
		ui:click("settings");ui:text("paletteSearch","Gwennen");ui:click("paletteUse");assert(not main.popups[1].controls.apply:IsEnabled(),"An unconfigured Gwennen pair could be applied")
		ui:click("tab_settings");ui:click("gwennen");assert(not main.popups[1].controls.keep:IsEnabled());frame("crafting-gwennen-empty")
		ui:choose("first",1002,"val");ui:choose("second",1000,"val");local lockNotes={};for _,row in ipairs(main.popups[1].controls.limits.list) do lockNotes[#lockNotes+1]=StripEscapes(row[1]) end;assert(main.popups[1].controls.keep:IsEnabled() and main.popups[1].controls.simulate:IsEnabled() and table.concat(lockNotes," "):find("actual future outcome",1,true),"Foreseeing must be modeled and its limitation explained");frame("crafting-gwennen-lock")
		ui:choose("first",1030,"val");local warning={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do warning[#warning+1]=StripEscapes(row[1]) end
		assert(table.concat(warning," "):find("conflict",1,true),"Disputed outcome did not show its warning");frame("crafting-gwennen-conflict")
		ui:choose("second",1000,"val");assert(not main.popups[1].controls.simulate:IsEnabled(),"Disputed offer needs an explicit scenario")
		ui:choose("rerolls",50,"val");assert(main.popups[1].controls.simulate:IsEnabled(),"Selected socket scenario did not enable modeling");frame("crafting-gwennen-socket-scenario")
		ui:choose("first",1005,"val");ui:choose("second",1022,"val");ui:text("cost","20 Grand Broken Circle Artifacts")
		assert(main.popups[1].controls.keep:IsEnabled());frame("crafting-gwennen-pair");ui:click("keep");ui:click("keepWorking")
		local saved;for _,project in ipairs(build.savers.CraftingProjects.projects) do if project.id=="gwennen-ui" then saved=project end end
		assert(saved and #saved.steps==1 and saved.steps[1].action=="Gwennen observed pair: Add a random Modifier OR Destroy. Artifact price: 20 Grand Broken Circle Artifacts.","Observed pair was not saved in the guide")
		assert(saved.steps[1].stopWhen:find("keeps the item",1,true),"Gwennen commitment was not saved in the guide")
		assert(build:SaveDB("Gwennen test"):find("20 Grand Broken Circle Artifacts",1,true),"Observed pair was not serialized in the build")
		assert(not saved.nativeRecipe,"Observed pair was incorrectly added to simulated actions")
		ui:click("gwennen");ui:choose("first",1018,"val");ui:choose("second",1019,"val")
		local notes={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do notes[#notes+1]=StripEscapes(row[1]) end
		assert(main.popups[1].controls.simulate:IsEnabled() and table.concat(notes," "):find("unverified",1,true),"Side rerolls or their assumption were not shown");frame("crafting-gwennen-side-rerolls")
		do ui:choose("first",1033,"val");ui:choose("second",1038,"val");local bestNotes={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do bestNotes[#bestNotes+1]=StripEscapes(row[1]) end
			assert(main.popups[1].controls.simulate:IsEnabled() and table.concat(bestNotes," "):find("unverified",1,true),"Best-of outcomes or their assumptions were not shown");frame("crafting-gwennen-best-of") end
		ui:choose("first",1020,"val");ui:choose("second",1021,"val");local tierNotes={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do tierNotes[#tierNotes+1]=StripEscapes(row[1]) end
		assert(main.popups[1].controls.simulate:IsEnabled() and table.concat(tierNotes," "):find("unverified",1,true),"Tier outcomes or their assumptions were not shown");frame("crafting-gwennen-tier")
		ui:choose("first",1043,"val");ui:choose("second",1044,"val");local multiTierNotes={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do multiTierNotes[#multiTierNotes+1]=StripEscapes(row[1]) end
		assert(main.popups[1].controls.simulate:IsEnabled() and table.concat(multiTierNotes," "):find("unverified",1,true),"Multi-tier outcomes or their assumptions were not shown");frame("crafting-gwennen-multi-tier")
		ui:choose("first",1031,"val");ui:choose("second",1031,"val");assert(main.popups[1].controls.simulate:IsEnabled(),"Influence outcome is not available");frame("crafting-gwennen-influence")
		do ui:choose("first",1032,"val");local notes={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do notes[#notes+1]=StripEscapes(row[1]) end;assert(main.popups[1].controls.simulate:IsEnabled() and table.concat(notes," "):find("unverified",1,true),"Implicit reroll or its assumptions were not shown");frame("crafting-gwennen-implicit") end
		ui:choose("first",1013,"val");local aspectNotes={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do aspectNotes[#aspectNotes+1]=StripEscapes(row[1]) end
		assert(main.popups[1].controls.simulate:IsEnabled() and table.concat(aspectNotes," "):find("unverified",1,true),"Pantheon outcome or its assumptions were not shown")
		ui:choose("first",1027,"val");local keepNotes={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do keepNotes[#keepNotes+1]=StripEscapes(row[1]) end
		assert(main.popups[1].controls.simulate:IsEnabled() and table.concat(keepNotes," "):find("unverified",1,true),"Keep-one reroll or its assumptions were not shown")
		ui:choose("first",1010,"val");ui:choose("second",1011,"val");local colourNotes={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do colourNotes[#colourNotes+1]=StripEscapes(row[1]) end
		assert(main.popups[1].controls.simulate:IsEnabled() and table.concat(colourNotes," "):find("unverified",1,true),"Socket-colour outcomes or their assumptions were not shown")
		ui:choose("first",1016,"val");ui:choose("second",1017,"val");local linkNotes={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do linkNotes[#linkNotes+1]=StripEscapes(row[1]) end
		assert(main.popups[1].controls.simulate:IsEnabled() and table.concat(linkNotes," "):find("unverified",1,true),"Link outcomes or their assumptions were not shown")
		ui:choose("first",1028,"val");local countNotes={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do countNotes[#countNotes+1]=StripEscapes(row[1]) end
		assert(main.popups[1].controls.simulate:IsEnabled() and table.concat(countNotes," "):find("unverified",1,true),"Socket-count outcome or its assumptions were not shown")
		local readiness={};for _,row in ipairs(main.popups[1].controls.limits.list) do readiness[#readiness+1]=StripEscapes(row[1]) end
		local readinessText=table.concat(readiness," ");assert(readinessText:find("Add a socket",1,true) and readinessText:find("later step",1,true) and not readinessText:find(".lua",1,true),"Current-item restriction should be readable and preserve future-step planning");frame("crafting-gwennen-readiness")
		ui:choose("first",1041,"val");ui:choose("second",1022,"val");assert(main.popups[1].controls.simulate:IsEnabled(),"Lowest-level removal is not available");ui:choose("first",1003,"val");ui:choose("second",1012,"val");assert(main.popups[1].controls.simulate:IsEnabled(),"Fracture and corruption are not available");ui:choose("first",1009,"val");ui:choose("second",1022,"val");ui:text("cost","20 Grand Broken Circle Artifacts");assert(main.popups[1].controls.simulate:IsEnabled());ui:click("simulate")
		ui:click("tab_settings");ui:click("configure");assert(main.popups[1].controls.first:GetSelValueByKey("val")==1009 and main.popups[1].controls.second:GetSelValueByKey("val")==1022 and main.popups[1].controls.cost.buf=="20 Grand Broken Circle Artifacts","Gwennen configuration was not restored");ui:click("simulate")
		ui:click("item");assert(main.popups[1].controls.intro.label:find("Gwennen modeled outcome",1,true),"Modeled outcome was not identified");frame("crafting-gwennen-modeled");ui:click("undo");ui:click("close")
	end
end
