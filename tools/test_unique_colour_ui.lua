return function(build,ui,frame)
	local project={id="unique-colour-ui",title="Unique colours",slot="Helmet",startingItem="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: W-W W W",goals={},steps={}}
	local store=build.savers.CraftingProjects;store:Upsert(project)
	local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
	ui:click("socketCount");frame("crafting-unique-socket-menu");ui:click("colours");frame("crafting-unique-colour-picker")
	ui:click("apply");frame("crafting-unique-colour-preview");ui:click("guide");ui:click("recipe")
	local saved;for _,entry in ipairs(store.projects) do if entry.id==project.id then saved=entry end end
	assert(saved and saved.steps[1].uniqueCraft.method=="chromatic" and saved.nativeRecipe.steps[1].method=="chromatic","Unique colour guide or recipe was not kept")
	ui:click("recipe");local colourTasks=require("Modules.CraftingTasks");assert(colourTasks.job,"Sampled colour recipe did not use a background task");while colourTasks.job do colourTasks.tick(build) end;frame("crafting-unique-colour-result");ui:click("close")
	main.popups={}
	local direct={id="unique-direct-colour-ui",title="Desired colours",slot="Helmet",startingItem=project.startingItem,goals={},steps={}}
	store:Upsert(direct);require("Classes.CraftingUniqueQualityControl").Open(build,direct)
	ui:click("socketCount");ui:click("colours");local picker=main.popups[1].controls
	ui:text("target","WWWW");assert(picker.plan:IsEnabled() and picker.targetHelp.label():find("Already met",1,true),"Already-satisfied colour target was not explained");frame("crafting-unique-colour-already")
	picker.method:SelByValue("omen_trichromatism","val");picker.target:SetText("RRW");assert(not picker.plan:IsEnabled(),"Impossible colour target was enabled");frame("crafting-unique-colour-impossible")
	picker.method:SelByValue("chromatic","val");picker.target:SetText("RG");picker.placement:SelByValue("In one linked group");ui:text("attempts","250");frame("crafting-unique-colour-target");ui:click("plan")
	local planned;for _,entry in ipairs(store.projects) do if entry.id==direct.id then planned=entry end end
	assert(planned and planned.nativeRecipe.requirements.socketColours=="RG" and planned.nativeRecipe.requirements.linkedColours and planned.nativeRecipe.steps[1].maxAttempts==250 and planned.steps[1].onFailure=="Stop after 250 attempts." and planned.steps[1].uniqueCraft.method=="chromatic","Direct colour plan was not kept")
	ui:click("socketCount");ui:click("colours");ui:text("target","RR");ui:click("plan");frame("crafting-unique-colour-replace");ui:click("confirm")
	for _,entry in ipairs(store.projects) do if entry.id==direct.id then planned=entry end end
	assert(planned.nativeRecipe.requirements.socketColours=="RR" and #planned.steps==1 and planned.steps[1].stopWhen=="At least RR sockets in any order","Colour guide did not follow the replacement");main.popups={}
	local divineRaw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B\n+(30-50) to Evasion Rating\n+10% to Item Rarity\n+(30-40)% to all Elemental Resistances\nReflects 4 Physical Damage to Melee Attackers"
	local divineProject={id="unique-divine-ui",title="Divine target",slot="Helmet",startingItem=divineRaw,goals={},steps={}}
	store:Upsert(divineProject);require("Classes.CraftingUniqueQualityControl").Open(build,divineProject);ui:click("divine");local divinePicker=main.popups[1].controls
	divinePicker.stat:SelByValue("Evasion","val");ui:text("target","100");ui:text("attempts","3");frame("crafting-unique-divine-target");ui:click("plan")
	local divineSaved;for _,entry in ipairs(store.projects) do if entry.id==divineProject.id then divineSaved=entry end end
	assert(divineSaved and divineSaved.nativeRecipe.requirements.nativeStats.Evasion==100 and divineSaved.steps[1].uniqueCraft.method=="divine","Divine target was not kept")
	ui:click("recipe");local divineTasks=require("Modules.CraftingTasks");assert(divineTasks.job,"A Divine recipe must use sampled background trials");while divineTasks.job do divineTasks.tick(build) end
	local summary="";for _,row in ipairs(main.popups[1].controls.details.list) do summary=summary..StripEscapes(row[1] or "").." " end
	assert(summary:find("20 trials",1,true),"Divine recipe used only one sampled trial");ui:click("close")
	ui:click("divine");divinePicker=main.popups[1].controls;divinePicker.stat:SelByValue("modifier:2","val");divinePicker.direction:SelByValue("At most");ui:text("target","30");assert(divinePicker.selectedInfo.label():find("Elemental Resistances",1,true),"Selected modifier description is truncated");frame("crafting-unique-divine-modifier");ui:click("plan");ui:click("confirm")
	for _,entry in ipairs(store.projects) do if entry.id==divineProject.id then divineSaved=entry end end
	assert(#divineSaved.steps==1 and divineSaved.nativeRecipe.requirements.uniqueModifier.maxValue==30,"Divine modifier target was not kept");main.popups={}
	local divinePreview={id="unique-divine-preview-ui",title="Divine preview",slot="Helmet",startingItem="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B\n+40 to Evasion Rating\n+10% to Item Rarity\n+35% to all Elemental Resistances\nReflects 4 Physical Damage to Melee Attackers",goals={},steps={}}
	store:Upsert(divinePreview);require("Classes.CraftingUniqueQualityControl").Open(build,divinePreview);ui:click("divine");ui:click("apply");frame("crafting-unique-divine-preview");ui:click("guide")
	for _,entry in ipairs(store.projects) do if entry.id==divinePreview.id then divineSaved=entry end end;assert(divineSaved.steps[1].uniqueCraft.method=="divine","Divine preview guide was not kept");main.popups={}
	local multiTemplate;for _,group in pairs(data.uniques) do for _,entry in ipairs(group) do if entry:match("^%s*Dreadarc[\r\n]") then multiTemplate=entry end end end
	assert(multiTemplate,"Missing multi-range unique fixture");local multiProject={id="unique-divine-multi-ui",title="Weapon rolls",slot="Weapon 1",startingItem="Rarity: UNIQUE\n"..multiTemplate.."\nItem Level: 86",goals={},steps={}}
	store:Upsert(multiProject);require("Classes.CraftingUniqueQualityControl").Open(build,multiProject);ui:click("divine");local multiPicker=main.popups[1].controls;multiPicker.stat:SelByValue("modifier:2","val");ui:text("target","25");frame("crafting-unique-divine-multi");ui:click("plan")
	local multiSaved;for _,entry in ipairs(store.projects) do if entry.id==multiProject.id then multiSaved=entry end end
	assert(multiSaved and multiSaved.nativeRecipe.requirements.uniqueModifier.component==2,"Multi-range target component was not kept");main.popups={}
	local variantRaw="Rarity: UNIQUE\nThe Blood Reaper\nHeadsman Axe\nItem Level: 86\n190% increased Physical Damage\n+100 to maximum Life\nRegenerate 20 Life per second\n1% of Physical Attack Damage Leeched as Life\n50% increased Mana Cost of Skills\n50% chance to cause Bleeding on Hit"
	local variantProject={id="unique-divine-variant-ui",title="Variant rolls",slot="Weapon 1",startingItem=variantRaw,goals={},steps={}}
	store:Upsert(variantProject);require("Classes.CraftingUniqueQualityControl").Open(build,variantProject);ui:click("divine");local variantPicker=main.popups[1].controls;variantPicker.stat:SelByValue("modifier:1","val");ui:text("target","200");ui:click("plan")
	local variantSaved;for _,entry in ipairs(store.projects) do if entry.id==variantProject.id then variantSaved=entry end end
	assert(variantSaved and variantSaved.nativeRecipe.requirements.uniqueModifier.minValue==200,"Variant target was not kept");main.popups={}
	local ringRaw="Rarity: UNIQUE\nAndvarius\nGold Ring\nItem Level: 86\nImplicits: 1\n+10% to Item Rarity\n+10 to Dexterity\n+60% to Item Rarity\n-20% to all Elemental Resistances"
	local ringProject={id="unique-divine-ring-ui",title="Ring rolls",slot="Ring 1",startingItem=ringRaw,goals={},steps={}}
	store:Upsert(ringProject);require("Classes.CraftingUniqueQualityControl").Open(build,ringProject);local ringControls=main.popups[1].controls;assert(not ringControls.apply:IsShown() and not ringControls.socketCount:IsShown() and ringControls.divine:IsShown(),"Jewellery layout should focus on available crafting");frame("crafting-unique-ring");ui:click("divine");local ringPicker=main.popups[1].controls;ringPicker.stat:SelByValue("modifier:1","val");ui:text("target","70");ui:click("plan")
	local ringSaved;for _,entry in ipairs(store.projects) do if entry.id==ringProject.id then ringSaved=entry end end
	assert(ringSaved and ringSaved.nativeRecipe.requirements.uniqueModifier.minValue==70,"Ring Divine target was not kept");main.popups={}
	local defaultCatalyst={id="unique-catalyst-ring-ui",title="Catalyst ring",slot="Ring 1",startingItem=ringRaw:gsub("Item Level: 86","Item Level: 86\nCatalyst: Prismatic"),goals={},steps={}}
	store:Upsert(defaultCatalyst);require("Classes.CraftingUniqueQualityControl").Open(build,defaultCatalyst);local catalystControls=main.popups[1].controls
	assert(not catalystControls.divine:IsEnabled() and catalystControls.status.label:find("20%%"),"Implicit catalyst quality must be shown and Divine disabled");frame("crafting-unique-ring-catalyst");main.popups={}

	local taggedCatalyst="Rarity: UNIQUE\nProfane Proxy\nUnset Ring\nItem Level: 86\nCatalyst: Fertile\nCatalystQuality: 20\nImplicits: 1\nHas 1 Socket\n+3 to Level of Socketed Curse Gems\n+25% to Cold Resistance\n+25% to Lightning Resistance\nLeft Ring Slot: Your Chilling Skitterbot's Aura applies Socketed Hex Curse instead\nRight Ring Slot: Your Shocking Skitterbot's Aura applies Socketed Hex Curse instead"
	local taggedProject={id="unique-unaffected-catalyst-ui",title="Unaffected rolls",slot="Ring 1",startingItem=taggedCatalyst,goals={},steps={}}
	store:Upsert(taggedProject);require("Classes.CraftingUniqueQualityControl").Open(build,taggedProject);local taggedControls=main.popups[1].controls
	assert(taggedControls.divine:IsEnabled() and taggedControls.divine.tooltipText():find("bundled modifier tags",1,true),"Unaffected catalyst case should explain its assumption");frame("crafting-unique-unaffected-catalyst");ui:click("divine");local taggedPicker=main.popups[1].controls;taggedPicker.stat:SelByValue("modifier:1","val");ui:text("target","30");ui:click("plan")
	local taggedSaved;for _,entry in ipairs(store.projects) do if entry.id==taggedProject.id then taggedSaved=entry end end;assert(taggedSaved and taggedSaved.nativeRecipe.requirements.uniqueModifier.minValue==30,"Catalyst-independent target was not kept");main.popups={}
	local scaledCatalyst=taggedCatalyst:gsub("Catalyst: Fertile","Catalyst: Prismatic"):gsub("+25%% to Cold Resistance","+30%% to Cold Resistance"):gsub("+25%% to Lightning Resistance","+30%% to Lightning Resistance")
	local scaledProject={id="unique-scaled-catalyst-ui",title="Scaled rolls",slot="Ring 1",startingItem=scaledCatalyst,goals={},steps={}}
	store:Upsert(scaledProject);require("Classes.CraftingUniqueQualityControl").Open(build,scaledProject);ui:click("divine");local scaledPicker=main.popups[1].controls;scaledPicker.stat:SelByValue("modifier:1","val");ui:text("target","36");assert(scaledPicker.selectedRange.label():find("Displayed roll: 24-36 | current: 30",1,true),"Scaled current value is missing");frame("crafting-unique-scaled-catalyst");ui:click("plan")
	local scaledSaved;for _,entry in ipairs(store.projects) do if entry.id==scaledProject.id then scaledSaved=entry end end;assert(scaledSaved and scaledSaved.nativeRecipe.requirements.uniqueModifier.minValue==36,"Scaled target was not kept");main.popups={}

	local multiProject={id="unique-scaled-multi-catalyst-ui",title="Prismweave",slot="Belt",startingItem="Rarity: UNIQUE\nPrismweave\nRustic Sash\nItem Level: 86\nCatalyst: Turbulent\nCatalystQuality: 20\nImplicits: 1\n18% increased Global Physical Damage\nAdds 18 to 37 Fire Damage to Attacks\nAdds 13 to 31 Cold Damage to Attacks\nAdds 1 to 76 Lightning Damage to Attacks\n+11% to all Elemental Resistances\n36% increased Elemental Damage with Attack Skills during any Flask Effect",goals={},steps={}}
	store:Upsert(multiProject);require("Classes.CraftingUniqueQualityControl").Open(build,multiProject);ui:click("divine");local multiPicker=main.popups[1].controls;multiPicker.stat:SelByValue("modifier:2","val");ui:text("target","38");assert(multiPicker.selectedRange.label():find("Displayed roll: 36-38 | current: 37",1,true),"Multi-range target missing");frame("crafting-unique-scaled-multi");ui:click("plan")
	local multiSaved;for _,entry in ipairs(store.projects) do if entry.id==multiProject.id then multiSaved=entry end end;assert(multiSaved and multiSaved.nativeRecipe.requirements.uniqueModifier.component==2 and multiSaved.nativeRecipe.requirements.uniqueModifier.minValue==38,"Multi-range target not saved");main.popups={}
	local corruptRing={id="unique-corrupt-ring-ui",title="Corrupted ring",slot="Ring 1",startingItem=ringRaw.."\nCorrupted",goals={},steps={}}
	store:Upsert(corruptRing);require("Classes.CraftingUniqueQualityControl").Open(build,corruptRing);local corruptControls=main.popups[1].controls
	assert(not corruptControls.divine:IsShown() and not corruptControls.apply:IsShown(),"Corrupted jewellery cannot use Divine Orbs or ordinary quality currency");frame("crafting-unique-ring-corrupted");main.popups={}

	local taintedQuality={id="unique-tainted-quality-ui",title="Tainted quality",slot="Helmet",startingItem="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nQuality: 0\nSockets: R-G B\nCorrupted",goals={},steps={}}
	store:Upsert(taintedQuality);require("Classes.CraftingUniqueQualityControl").Open(build,taintedQuality);frame("crafting-unique-tainted-quality")
	ui:click("qualityPlan");ui:text("target","20");ui:text("attempts","1000");frame("crafting-unique-quality-target");ui:click("plan")
	local qualityDirect;for _,entry in ipairs(store.projects) do if entry.id==taintedQuality.id then qualityDirect=entry end end
	assert(qualityDirect and qualityDirect.nativeRecipe.requirements.minQuality==20 and qualityDirect.nativeRecipe.steps[1].maxAttempts==1000,"Direct quality plan was not kept")
	main.popups={};local rolledQuality={id="unique-tainted-quality-preview-ui",title="Tainted preview",slot="Helmet",startingItem=taintedQuality.startingItem,goals={},steps={}}
	store:Upsert(rolledQuality);require("Classes.CraftingUniqueQualityControl").Open(build,rolledQuality);ui:click("apply");ui:click("guide");ui:click("recipe")
	local qualityPlan;for _,entry in ipairs(store.projects) do if entry.id==rolledQuality.id then qualityPlan=entry end end
	assert(qualityPlan and qualityPlan.steps[1].uniqueCraft.method=="tainted_quality" and qualityPlan.nativeRecipe.steps[1].method=="tainted_quality","Tainted quality guide or recipe was not kept")
	ui:click("recipe");local qualityTasks=require("Modules.CraftingTasks");assert(qualityTasks.job,"Tainted quality check did not use a background task");while qualityTasks.job do qualityTasks.tick(build) end;frame("crafting-unique-tainted-quality-result");ui:click("close");main.popups={}
	local socketProject={id="unique-random-sockets-ui",title="Desired sockets",slot="Helmet",startingItem="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B",goals={},steps={}}
	store:Upsert(socketProject);require("Classes.CraftingUniqueQualityControl").Open(build,socketProject)
	ui:click("socketCount");ui:click("roll");ui:text("target","4");ui:text("attempts","250");frame("crafting-unique-socket-target");ui:click("plan")
	local sockets;for _,entry in ipairs(store.projects) do if entry.id==socketProject.id then sockets=entry end end
	assert(sockets and sockets.nativeRecipe.requirements.exactSockets==4 and sockets.nativeRecipe.steps[1].maxAttempts==250 and sockets.steps[1].uniqueCraft.method=="jeweller","Unique socket plan was not kept")
	ui:click("socketCount");ui:click("roll");ui:text("target","2");assert(main.popups[1].controls.targetHelp.label():find("Maximum sockets stop",1,true),"Socket reset risk was not explained");ui:click("plan");ui:click("confirm")
	for _,entry in ipairs(store.projects) do if entry.id==socketProject.id then sockets=entry end end
	assert(#sockets.steps==1 and sockets.steps[1].stopWhen=="Exactly 2 sockets" and sockets.nativeRecipe.requirements.exactSockets==2,"Socket guide did not follow replacement")
	ui:click("recipe");local socketTasks=require("Modules.CraftingTasks");assert(socketTasks.job,"Socket recipe did not use a background task");while socketTasks.job do socketTasks.tick(build) end;frame("crafting-unique-socket-result");ui:click("close");main.popups={}
	local completeLink={id="unique-complete-link-ui",title="Completed links",slot="Body Armour",startingItem="Rarity: UNIQUE\nBelly of the Beast\nFull Wyrmscale\nItem Level: 86\nSockets: R-G-B-W-R-G",goals={},steps={}}
	store:Upsert(completeLink);require("Classes.CraftingUniqueQualityControl").Open(build,completeLink)
	ui:click("socketCount");ui:click("links");ui:text("target","6");local completePicker=main.popups[1].controls
	assert(not completePicker.apply:IsEnabled() and completePicker.plan:IsEnabled() and completePicker.targetHelp.label():find("Already met",1,true),"Fully linked item did not offer its completed plan");ui:click("plan");main.popups={}
	local linkProject={id="unique-random-links-ui",title="Desired links",slot="Helmet",startingItem="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B W",goals={},steps={}}
	store:Upsert(linkProject);require("Classes.CraftingUniqueQualityControl").Open(build,linkProject)
	ui:click("socketCount");ui:click("links");ui:text("target","4");ui:text("attempts","1000");frame("crafting-unique-link-target");ui:click("plan")
	local linked;for _,entry in ipairs(store.projects) do if entry.id==linkProject.id then linked=entry end end
	assert(linked and linked.nativeRecipe.requirements.links==4 and linked.nativeRecipe.steps[1].maxAttempts==1000 and linked.steps[1].uniqueCraft.method=="fusing","Unique link plan was not kept")
	ui:click("recipe");frame("crafting-unique-link-progress");local tasks=require("Modules.CraftingTasks");assert(tasks.job,"Long unique recipe did not use a background task");while tasks.job do tasks.tick(build) end;frame("crafting-unique-link-result");local details={};for _,row in ipairs(main.popups[1].controls.details.list) do details[#details+1]=row[1] end;assert(table.concat(details," "):find("10 trials",1,true),"Long link budget was not checked");ui:click("close")
	ui:click("socketCount");ui:click("links");ui:click("apply");frame("crafting-unique-link-preview");main.popups={}
end
