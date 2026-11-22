-- Guide-only planning; no modifier values are simulated.
return function(build,ui,frame)
	local raw="Rarity: UNIQUE\nProfane Proxy\nUnset Ring\nItem Level: 86\nImplicits: 1\nHas 1 Socket\n+3 to Level of Socketed Curse Gems\n+25% to Cold Resistance\n+25% to Lightning Resistance\nLeft Ring Slot: Your Chilling Skitterbot's Aura applies Socketed Hex Curse instead\nRight Ring Slot: Your Shocking Skitterbot's Aura applies Socketed Hex Curse instead"
	local project={id="unique-catalyst-ui",title="Catalyst guide",slot="Ring 1",startingItem=raw,goals={},steps={}}
	build.savers.CraftingProjects:Upsert(project);require("Classes.CraftingUniqueQualityControl").Open(build,project)
	frame("crafting-unique-jewellery");ui:click("catalystPlan");frame("crafting-unique-catalyst-guide");ui:choose("kind",3,"val");assert(main.popups[1].controls.warning:IsShown(),"Prefix/suffix warning was not shown");frame("crafting-unique-catalyst-warning");ui:choose("kind",8,"val");ui:click("keep")
	local saved;for _,entry in ipairs(build.savers.CraftingProjects.projects) do if entry.id==project.id then saved=entry;break end end
	assert(saved and saved.steps[1].uniqueCraft.catalyst==8 and saved.steps[1].uniqueCraft.count==20 and not saved.targetItem,"Catalyst guide was not kept correctly")
	main.popups={}
end
