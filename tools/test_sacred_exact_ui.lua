-- Verify the workbench shows the finite Sacred estimate and its uncertainty.
arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI")
for _,width in ipairs({960,1024,1280}) do
	newBuild();main.popups={};local ui=UI.install({width=width,height=768});ui:bind(build)
	local project={id="sacred-exact-ui",title="Sacred estimate",slot="Body Armour",startingItem="Rarity: NORMAL\nCarnal Armour\nItem Level: 86",goals={},steps={},nativeRecipe={steps={},targets={},requirements={nativeStats={EnergyShield=105}}}}
	local controls=require("Classes.CraftingSimulatorControl").Open(build,project)
	controls.method:SelByValue("sacred","val");controls.method.selFunc()
	ui:choose("page","Craft settings");ui:click("exact");local jobs=require("Modules.CraftingTasks")
	for i=1,100 do if not jobs.job then break end;jobs.tick(build) end
	local result=build.craftingAnalyses[project.id].results.odds.result
	assert(not jobs.job and result.sampled==false and result.successChance==84.375,"Sacred estimate did not enumerate the modeled rolls")
	ui:choose("page","Simulate recipe");local details={}
	for _,row in ipairs(controls.resultSummary.list) do details[#details+1]=StripEscapes(row[1] or "") end
	local text=table.concat(details," ")
	assert(text:find("84.375%",1,true) and text:find("unverified",1,true),"Sacred estimate or uncertainty is missing")
	local visible,used={},0
	for _,row in ipairs(controls.resultSummary.list) do
		if used+(row.textSize or 14)<=controls.resultSummary.height then visible[#visible+1]=StripEscapes(row[1] or "") end
		used=used+row.height
	end
	assert(table.concat(visible," "):find("Energy shield",1,true),"The modeled outcomes are hidden below the initial results area")
	ui:restore();main.popups={}
end
print("SACRED_EXACT_UI_OK")
