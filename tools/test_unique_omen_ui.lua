return function(build,ui,frame)
		local project={id="unique-omen-jeweller-ui",title="Unique sockets",slot="Helmet",startingItem="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B",goals={},steps={}}
		build.savers.CraftingProjects:Upsert(project);local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
		assert(control.omenJeweller:IsEnabled(),"Unique Jeweller Omen is unavailable");ui:click("omenJeweller");frame("crafting-unique-omen-jeweller")
		ui:click("guide");ui:click("recipe");local saved;for _,entry in ipairs(build.savers.CraftingProjects.projects) do if entry.id==project.id then saved=entry end end
		assert(saved and saved.steps[1].uniqueCraft.method=="omen_jeweller" and saved.nativeRecipe.steps[1].method=="omen_jeweller","Unique Jeweller Omen guide or recipe was not kept");main.popups={}
end
