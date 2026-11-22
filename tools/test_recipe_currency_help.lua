-- Check recipe-step descriptions without requiring the craft to be valid yet.
arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI");local sim=require("Modules.CraftingSimulator")
for _,width in ipairs({960,1024,1280}) do
	newBuild();main.popups={};local ui=UI.install({width=width,height=768});ui:bind(build)
	local model=sim.model("Rarity: NORMAL\nPlate Vest\nItem Level: 86")
	require("Classes.CraftingRecipeControl").Open({steps={{method="alchemy"}},targets={},requirements={maxAffixes=0}},{method="alchemy"},function() end,model)
	for _,case in ipairs({{"Eldritch Chaos Orb","Reroll modifiers on one side"},{"Tainted Chaos Orb","Attempt to reforge or remove"},
		{"Fracturing Orb","Fracture one modifier"},{"Orb of Remembrance","Add memory strands"},{"Foulborn Exalted Orb","experimental Foulborn model"}}) do
		ui:click("addCurrency");ui:text("search",case[1]);local details={}
		for _,row in ipairs(main.popups[1].controls.details.list) do details[#details+1]=StripEscapes(row[1] or "") end
		assert(table.concat(details," "):find(case[2],1,true),"Recipe picker omitted "..case[1].." help")
		ui:click("close")
	end
	ui:click("addCurrency");ui:text("search","Chaos Orb")
	local controls=main.popups[1].controls;local details={}
	for _,row in ipairs(controls.details.list) do details[#details+1]=StripEscapes(row[1] or "") end
	local text=table.concat(details," ")
	assert(text:find("Reroll the modifiers on a rare item",1,true) and text:find("requirements when this step runs",1,true),"Recipe picker should explain the craft and future requirements")
	ui:click("choose");assert(main.popups[1].controls.graph.list[2],"Recipe step was not added")
	ui:restore();main.popups={}
end
print("RECIPE_CURRENCY_HELP_OK")
