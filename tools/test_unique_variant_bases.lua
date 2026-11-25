-- The item's actual base must select a compatible unique variant.
arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local unique=require("Modules.CraftingUniqueQuality")
local current="Rarity: UNIQUE\nAsphyxia's Wrath\nFeathered Arrow Quiver\nItem Level: 86\nImplicits: 1\n25% increased Projectile Speed\nGrants Level 5 Frostbite\n10% increased Attack Speed\n+35% to Cold Resistance\n35% increased Chill Duration on Enemies\nGain 20% of Physical Damage as Extra Cold Damage\n8% chance to Freeze\nHexes Transfer to all Enemies within 3 metres when Hexed Enemy dies"
local legacy=current:gsub("Feathered Arrow Quiver","Two-Point Arrow Quiver"):gsub("25%% increased Projectile Speed","25%% increased Global Accuracy Rating"):gsub("Grants Level 5 Frostbite\n",""):gsub("8%% chance to Freeze","8%% chance to Freeze\n40%% reduced Area of Effect of Hex Skills")
for _,raw in ipairs({current,legacy}) do
	local options=assert(unique.divineOptions(raw));assert(#options==4)
	for seed=1,20 do local result=unique.divine(raw,seed*7919);assert(unique.divineOptions(result.itemText));raw=result.itemText end
end
local mismatched=legacy:gsub("Two%-Point Arrow Quiver","Feathered Arrow Quiver")
local mismatchReason=unique.divineReason(mismatched)
assert(mismatchReason and mismatchReason:find("complete modifiers",1,true),"A current base accepted legacy-only modifiers or reported an unrelated variant error")
build.itemsTab:CreateDisplayItemFromRaw("Test Bow\nShort Bow");build.itemsTab:AddDisplayItem()
local project={id="variant-quiver",title="Variant quiver",slot="Weapon 2",startingItem=current,goals={},steps={}}
build.savers.CraftingProjects:Upsert(project)
local ui=require("Modules.HeadlessUI").install({width=960,height=640});ui:bind(build)
local controls=require("Classes.CraftingUniqueQualityControl").Open(build,project);assert(controls.divine:IsEnabled());ui:click("divine")
local picker=main.popups[1].controls;local options=assert(unique.divineOptions(current));picker.stat:SelByValue("modifier:1","val");ui:text("target",tostring(options[1].max));assert(picker.plan:IsEnabled());ui:click("plan")
local xml=build:SaveDB("Variant quiver");loadBuildFromXML(xml,"Variant quiver");ui:bind(build)
local saved=assert(build.savers.CraftingProjects.projects[1]);assert(saved.nativeRecipe.requirements.uniqueModifier.line==options[1].line,"Reopening lost the variant modifier target")
local result=require("Modules.CraftingSimulator").simulate(saved.startingItem,saved.nativeRecipe,{trials=4,maxActions=4,seed=12345});assert(result.sampled and result.trials==4)
main.popups={};ui:restore()
print("UNIQUE_VARIANT_BASES_OK")
