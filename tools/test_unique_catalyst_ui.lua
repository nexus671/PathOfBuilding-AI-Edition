-- Exercise catalyst preview, undo, and guide-only planning.
return function(build,ui,frame)
	local raw="Rarity: UNIQUE\nProfane Proxy\nUnset Ring\nItem Level: 86\nImplicits: 1\nHas 1 Socket\n+3 to Level of Socketed Curse Gems\n+25% to Cold Resistance\n+25% to Lightning Resistance\nLeft Ring Slot: Your Chilling Skitterbot's Aura applies Socketed Hex Curse instead\nRight Ring Slot: Your Shocking Skitterbot's Aura applies Socketed Hex Curse instead"
	local project={id="unique-catalyst-ui",title="Catalyst guide",slot="Ring 1",startingItem=raw,goals={},steps={}}
	build.savers.CraftingProjects:Upsert(project);require("Classes.CraftingUniqueQualityControl").Open(build,project)
	frame("crafting-unique-jewellery");ui:click("catalystPlan");frame("crafting-unique-catalyst-guide");ui:choose("kind",3,"val");assert(main.popups[1].controls.warning:IsShown(),"Prefix/suffix warning was not shown");frame("crafting-unique-catalyst-warning");ui:choose("kind",8,"val");ui:click("preview");frame("crafting-unique-catalyst-preview");local found=false;for _,row in ipairs(main.popups[1].controls.itemMods.list) do if table.concat(row):find("+30%% to Cold Resistance") then found=true end end;assert(found,"Catalyst-scaled modifier was not displayed");ui:click("undo");ui:click("catalystPlan");ui:choose("kind",8,"val");ui:click("keep")
	local saved;for _,entry in ipairs(build.savers.CraftingProjects.projects) do if entry.id==project.id then saved=entry;break end end
	assert(saved and saved.steps[1].uniqueCraft.catalyst==8 and saved.steps[1].uniqueCraft.count==20 and not saved.targetItem,"Catalyst guide was not kept correctly")
	-- Saved and comparison cards must display the same scaled values as the workbench.
	local original=require("Modules.CraftingUniqueQuality").inspect(raw)
	local scaled=require("Modules.CraftingUniqueQuality").inspect(require("Modules.CraftingUniqueQuality").catalystPreview(raw,8,20).itemText)
	local controls={};local show=require("Classes.JourneyItemControl").new(controls,"savedCard",16,30,440,220,"PLANNED UPGRADE")
	show(scaled,original);local text={};for _,row in ipairs(controls.savedCardMods.list) do text[#text+1]=StripEscapes(row[1] or "") end
	assert(table.concat(text," "):find("+ +30% to Cold Resistance",1,true),"Saved target comparison did not show its catalyst-scaled modifier")
	show(original,scaled);text={};for _,row in ipairs(controls.savedCardMods.list) do text[#text+1]=StripEscapes(row[1] or "") end
	assert(table.concat(text," "):find("+ +25% to Cold Resistance",1,true),"Unscaled comparison modifier changed unexpectedly")
	main.popups={}
	local savedProject={id="saved-catalyst-card",title="Saved catalyst target",slot="Ring 1",startingItem=raw,targetItem=scaled.raw,goals={},steps={}}
	build.savers.CraftingProjects:Upsert(savedProject);build.planningWorkspace=build.planningWorkspace or require("Modules.PlanningWorkspace").new(build);local workspace=build.planningWorkspace;workspace.selections.crafting=savedProject.id;workspace.cache.crafting=nil;workspace.drafts.crafting=nil
	build.viewMode="PLANNER";workspace:Show("crafting");ui:frame()
	local savedText={};for _,row in ipairs(workspace.controls.projectItemMods.list) do savedText[#savedText+1]=StripEscapes(row[1] or "") end
	assert(table.concat(savedText," "):find("+30% to Cold Resistance",1,true),"Saved project did not show its catalyst-scaled modifier")
	local summary={};for _,row in ipairs(workspace.controls.summary.list) do summary[#summary+1]=StripEscapes(row[1] or "") end
	assert(table.concat(summary," "):gsub("%s+"," "):find("jewellery has experimental catalyst previews",1,true),"Saved project help omitted catalyst previews: "..table.concat(summary," | "))
	local narrow={};local render=require("Classes.JourneyItemControl").new(narrow,"narrow",16,30,260,220,"PLANNED UPGRADE")
	local socketed=require("Modules.CraftingUniqueQuality").inspect(require("Modules.CraftingUniqueQuality").catalystPreview(raw:gsub("Implicits: 1","Sockets: R\nImplicits: 1"),8,20).itemText)
	render(socketed);main:OpenPopup(292,270,"Narrow comparison",narrow);ui:frame();local foundNarrow=false
	for _,command in ipairs(ui.commands) do if command.text and command.text:find("Prismatic 20%",1,true) then foundNarrow=true end end
	assert(foundNarrow,"Narrow socketed card did not retain catalyst and quality");main:ClosePopup()
	frame("crafting-saved-catalyst-target");local foundQuality=false;for _,command in ipairs(ui.commands) do if command.text and command.text:find("Prismatic 20%",1,true) then foundQuality=true end end;assert(foundQuality,"Saved target did not identify catalyst and quality")
	local conditions;require("Classes.CraftingTargetControl").Open({},{catalyst=8,minCatalystQuality=20},nil,function(_,value) conditions=value end)
	ui:click("catalystGoal");frame("crafting-catalyst-goal");ui:choose("kind",4,"val");ui:text("quality","12");ui:click("keep");frame("crafting-catalyst-goal-edited");ui:click("keep")
	assert(conditions.catalyst==4 and conditions.minCatalystQuality==12,"Catalyst goal edits were not kept")
	local normal="Rarity: NORMAL\nRuby Ring\nItem Level: 86\nCatalyst: Prismatic\nImplicits: 1\n{tags:resistance}+25% to Fire Resistance"
	for _,entry in ipairs({{raw=normal,expected="Prismatic quality: +20%",frame="crafting-default-catalyst-quality"},{raw=normal:gsub("Catalyst: Prismatic","Catalyst: Prismatic\nCatalystQuality: 0"),expected="Prismatic quality: +0%",frame="crafting-zero-catalyst-quality"}}) do
		local draft={id="ordinary-catalyst-quality",title="Ring quality",slot="Ring 1",startingItem=entry.raw,goals={},steps={}}
		require("Classes.CraftingSimulatorControl").Open(build,draft);frame(entry.frame);local shown=false;for _,command in ipairs(ui.commands) do if command.text and command.text:find(entry.expected,1,true) then shown=true end end
		assert(shown,"Workbench did not display "..entry.expected);ui:click("close")
	end
end
