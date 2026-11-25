-- Saved multi-selection uniques must retain their selected modifiers through Divine plans.
arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local unique=require("Modules.CraftingUniqueQuality");local template
for _,group in pairs(data.uniques) do for _,entry in ipairs(group) do
	if entry:match("^%s*Watcher's Eye[\r\n]") then template=entry end
end end
local raw="Rarity: UNIQUE\n"..assert(template).."\nItem Level: 86"
local options=assert(unique.divineOptions(raw));assert(#options==5,"Expected five supported modifier rolls")
local original=raw
for seed=1,50 do
	local result=unique.divine(raw,seed*7919);local after=assert(unique.divineOptions(result.itemText))
	assert(#after==#options,"Divine roll changed modifier count")
	for i,row in ipairs(options) do assert(after[i].line==row.line,"Divine roll changed modifier identity") end
	local item=new("Item"):Item(result.itemText)
	assert(item.variant==5 and item.variantAlt==30 and item.variantAlt2==1,"Divine roll changed the selected modifiers")
	raw=result.itemText
end
assert(unique.divineReason(original:gsub("Selected Alt Variant: 30\n","")),"Missing selection was accepted")
assert(unique.divineReason(original:gsub("Selected Alt Variant: 30","Selected Alt Variant: 5")),"Duplicate selection was accepted")
local three=original:gsub("Selected Alt Variant Two: 1\n","Selected Alt Variant Two: 10\n")
local threeOptions=assert(unique.divineOptions(three));assert(#threeOptions==6,"Expected three selected aura modifiers")
for seed=1,20 do
	local result=unique.divine(three,seed*7919);local after=assert(unique.divineOptions(result.itemText));assert(#after==#threeOptions)
	for i,row in ipairs(threeOptions) do assert(after[i].line==row.line,"Three-modifier roll changed modifier identity") end
	three=result.itemText
end
local pasted="Rarity: UNIQUE\nWatcher's Eye\nPrismatic Jewel\nItem Level: 86\n5% increased maximum Energy Shield\n5% increased maximum Life\n5% increased maximum Mana\n50% increased Fire Damage while affected by Anger\n40% chance to Blind Enemies which Hit you while affected by Grace"
local pastedOriginal=pasted
assert(unique.divineReason(pasted:gsub("40%% chance to Blind Enemies which Hit you while affected by Grace", "")),"Copied Watcher's Eye with a missing aura modifier was accepted")
local copied=assert(unique.divineOptions(pasted));assert(#copied==5 and not unique.divineReason(pasted))
local catalog=unique.catalog(pasted,"divine",10);assert(table.concat(catalog.limitations," "):find("missing third aura",1,true),"Copied-item completeness limitation was omitted")
for seed=1,20 do
	local result=unique.divine(pasted,seed*7919);local after=assert(unique.divineOptions(result.itemText));assert(#after==#copied)
	for i,row in ipairs(copied) do assert(after[i].line==row.line,"Copied modifier identity changed") end
	pasted=result.itemText
end
local ambiguous="Rarity: UNIQUE\nWatcher's Eye\nPrismatic Jewel\nItem Level: 86\n5% increased maximum Energy Shield\n5% increased maximum Life\n5% increased maximum Mana\n1.1% of Damage leeched as Life while affected by Vitality\n50% increased Fire Damage while affected by Anger"
local reason=unique.divineReason(ambiguous);assert(reason and reason:find("multiple unique variants",1,true),"Overlapping legacy rolls were not reported as ambiguous")
assert(unique.divineReason(ambiguous:gsub("1.1%% of Damage", "9%% of Damage")),"Out-of-range copied modifier was accepted")
assert(unique.divineReason(ambiguous:gsub("5%% increased maximum Life\n", "")),"Incomplete copied item was accepted")
local project={id="watcher-divine",title="Watcher's Eye",slot="Jewel 2311",startingItem=original,goals={},steps={}}
build.savers.CraftingProjects:Upsert(project)
local ui=require("Modules.HeadlessUI").install({width=960,height=640});ui:bind(build)
local controls=require("Classes.CraftingUniqueQualityControl").Open(build,project);assert(controls.divine:IsEnabled());ui:click("divine")
local picker=main.popups[1].controls;picker.stat:SelByValue("modifier:1","val");ui:text("target",tostring(options[1].max));assert(picker.plan:IsEnabled());ui:click("plan")
local xml=build:SaveDB("Watcher Divine");loadBuildFromXML(xml,"Watcher Divine");ui:bind(build)
local saved=assert(build.savers.CraftingProjects.projects[1]);assert(saved.nativeRecipe.requirements.uniqueModifier.line==options[1].line,"Reopening lost the modifier target")
local result=require("Modules.CraftingSimulator").simulate(saved.startingItem,saved.nativeRecipe,{trials=4,maxActions=4,seed=12345});assert(result.sampled and result.trials==4)
main.popups={};ui:restore();newBuild()
local copiedProject={id="copied-watcher",title="Copied Watcher's Eye",slot="Jewel 2311",startingItem=pastedOriginal,goals={},steps={}}
build.savers.CraftingProjects:Upsert(copiedProject);local copiedUI=require("Modules.HeadlessUI").install({width=960,height=640});copiedUI:bind(build)
local copiedControls=require("Classes.CraftingUniqueQualityControl").Open(build,copiedProject);assert(copiedControls.divine:IsEnabled());copiedUI:click("divine")
local copiedPicker=main.popups[1].controls;copiedPicker.stat:SelByValue("modifier:1","val");copiedUI:text("target",tostring(copied[1].max));assert(copiedPicker.plan:IsEnabled());copiedUI:click("plan")
local copiedXML=build:SaveDB("Copied Watcher");loadBuildFromXML(copiedXML,"Copied Watcher");copiedUI:bind(build)
local copiedSaved=assert(build.savers.CraftingProjects.projects[1]);assert(copiedSaved.nativeRecipe.requirements.uniqueModifier.line==copied[1].line)
local copiedResult=require("Modules.CraftingSimulator").simulate(copiedSaved.startingItem,copiedSaved.nativeRecipe,{trials=4,maxActions=4,seed=12345});assert(copiedResult.sampled and copiedResult.trials==4)
local warned=false;for _,warning in ipairs(copiedResult.warnings) do if warning.code=="unique_copied_modifiers" then warned=true end end;assert(warned,"Simulation omitted the copied-item completeness warning")
main.popups={};copiedUI:restore();print("UNIQUE_MULTIPLE_VARIANT_DIVINE_OK")
