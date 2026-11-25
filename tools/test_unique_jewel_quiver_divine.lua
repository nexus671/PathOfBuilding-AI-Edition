-- Unique jewels and quivers can use Divine plans without gaining quality or socket crafts.
arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local unique=require("Modules.CraftingUniqueQuality")
local simulator=require("Modules.CraftingSimulator")
build.itemsTab:CreateDisplayItemFromRaw("Test Bow\nShort Bow");build.itemsTab:AddDisplayItem()
for _,case in ipairs({{name="Anatomical Knowledge",slot="Jewel 2311"},{name="Ahuana's Bite",slot="Weapon 2"}}) do
	local template
	for _,group in pairs(data.uniques) do for _,entry in ipairs(group) do
		if entry:match("^%s*"..case.name:gsub("([^%w])","%%%1").."[\r\n]") then template=entry end
	end end
	assert(template,"Missing fixture "..case.name)
	local raw="Rarity: UNIQUE\n"..template.."\nItem Level: 86"
	local item,info=unique.inspect(raw);assert(not info.qualitySupported and not info.available and not info.resource)
	local qualityOK,qualityError=pcall(unique.apply,raw)
	assert(not qualityOK and tostring(qualityError):find("cannot use ordinary quality currency",1,true),"Ordinary quality lacked the correct restriction")
	assert(unique.socketCountReason(raw,2) and unique.colourReason(raw,"chromatic") and unique.randomLinkReason(raw,"fusing"),"Socket craft was allowed")
	local forged=raw.."\nSockets: R G B"
	assert(unique.socketCountReason(forged,2) and unique.colourReason(forged,"chromatic") and unique.linkReason(forged,"socket_bench") and unique.whiteReason(forged),"A forged socket layout enabled a socket craft")
	assert(unique.divineReason(raw.."\nCorrupted"),"Corrupted item accepted a Divine Orb")
	assert(unique.divineReason(raw.."\nMirrored"),"Mirrored item accepted a Divine Orb")
	local options=assert(unique.divineOptions(raw));assert(#options>0)
	local rolled=unique.divine(raw,12345);assert(unique.divineOptions(rolled.itemText),"Divine result did not round trip")
	local project={id="unique-divine-"..item.type,title=case.name,slot=case.slot,startingItem=raw,goals={},steps={}}
	build.savers.CraftingProjects:Upsert(project)
	local ui=require("Modules.HeadlessUI").install({width=960,height=640});ui:bind(build)
	local controls=require("Classes.CraftingUniqueQualityControl").Open(build,project)
	assert(controls.divine:IsShown() and controls.divine:IsEnabled())
	assert(controls.status.label:find("Divine preview available",1,true) and not controls.status.label:find("Catalyst",1,true),"Incorrect item status")
	assert(not controls.apply:IsShown() and not controls.socketCount:IsShown(),"Unsupported controls were shown")
	ui:click("divine");local picker=main.popups[1].controls
	picker.stat:SelByValue("modifier:1","val");ui:text("target",tostring(options[1].max));assert(picker.plan:IsEnabled());ui:click("plan")
	local saved;for _,entry in ipairs(build.savers.CraftingProjects.projects) do if entry.id==project.id then saved=entry end end
	assert(saved and saved.nativeRecipe and saved.nativeRecipe.requirements.uniqueModifier,"Divine goal was not saved")
	local result=simulator.simulate(raw,saved.nativeRecipe,{trials=4,maxActions=4,seed=12345});assert(result.sampled and result.trials==4)
	local xml=build:SaveDB("Unique Divine");loadBuildFromXML(xml,"Unique Divine");ui:bind(build)
	local reopened;for _,entry in ipairs(build.savers.CraftingProjects.projects) do if entry.id==project.id then reopened=entry end end
	assert(reopened and reopened.nativeRecipe.requirements.uniqueModifier.line==options[1].line,"Reopen lost the Divine goal")
	main.popups={};ui:restore()
end
print("UNIQUE_JEWEL_QUIVER_DIVINE_OK")
