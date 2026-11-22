-- Verify Divine plans preserve a saved single unique variant and inactive lines.
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI");local unique=require("Modules.CraftingUniqueQuality");local sim=require("Modules.CraftingSimulator")
local template
for _,entries in pairs(data.uniques) do for _,raw in ipairs(entries) do if raw:match("^%s*Abyssus\n") then template=raw end end end
assert(template,"Missing Abyssus template")
local function itemFor(index) return "Rarity: UNIQUE\n"..template.."\nSelected Variant: "..index.."\nItem Level: 83" end
local inactive={"{variant:1}+(100-150)% to Melee Critical Strike Multiplier","{variant:2}+(150-225)% to Melee Critical Strike Multiplier","{variant:3}+(100-125)% to Melee Critical Strike Multiplier"}
for index=1,3 do
 local raw=itemFor(index);local choices=assert(unique.divineOptions(raw));assert(#choices==4)
 for seed=1,12 do local result=unique.divine(raw,require("Modules.CalcEncounter").seed(104729,seed,31));local after=unique.inspect(result.itemText);assert(after.variant==index and #after.variantList==3,"Variant selection changed");assert(unique.divineOptions(result.itemText),"Rolled item could not be reopened");for other=1,3 do if other~=index then assert(result.itemText:find(inactive[other],1,true),"Inactive variant changed") end end;assert(result.itemText:find("{variant:"..index.."}{range:",1,true),"Active variant tag was lost") end
end
local selectedRoll=unique.divine(itemFor(3),104729).itemText
local switched=selectedRoll:gsub("Selected Variant: 3","Selected Variant: 1")
local switchedOptions=assert(unique.divineOptions(switched));local legacyFound=false
for _,row in ipairs(switchedOptions) do if row.line=="+(100-150)% to Melee Critical Strike Multiplier" then legacyFound=true end end
assert(legacyFound,"Switching variants after a roll lost the inactive variant")
local taggedTemplate
for _,entries in pairs(data.uniques) do for _,raw in ipairs(entries) do if raw:match("^%s*Ascent From Flesh\n") then taggedTemplate=raw end end end
local taggedRaw="Rarity: UNIQUE\n"..assert(taggedTemplate):gsub("^([^\r\n]+\n[^\r\n]+\n)","%1Selected Variant: 3\nItem Level: 83\n",1)
local taggedResult=unique.divine(taggedRaw,104729);assert(taggedResult.itemText:find("{variant:2,3}{range:[^}]+}{tags:defences}%+%(75%-80%)"),"Selected modifier lost its variant or tags")
assert(unique.divineOptions(taggedResult.itemText),"Tagged variant could not be reopened")
assert(unique.divineReason(itemFor(999)),"Invalid saved variant was accepted")
assert(unique.divineReason(itemFor(3):gsub("Variant: Pre 2.2.0\n",""):gsub("Variant: Pre 3.0.0\n",""):gsub("Variant: Current\n","")),"Variant lines without a saved list were accepted")
assert(unique.divineReason(itemFor(3):gsub("Variant: Current","Variant: Unrelated")),"Changed variant names were accepted")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
 local raw=itemFor(3);local project={id="variant-divine",title="Selected variant",slot="Helmet",startingItem=raw,goals={},steps={}}
 build.savers.CraftingProjects:Upsert(project);local control=require("Classes.CraftingUniqueQualityControl").Open(build,project);assert(control.divine:IsEnabled());ui:click("divine");ui:choose("stat","modifier:2","val");ui:text("target","120");assert(main.popups[1].controls.plan:IsEnabled(),"Variant target was rejected")
 if output then ui:frame():write(output.."/"..size[1].."-unique-variant-divine.json") end
 ui:click("plan");local saved=build.savers.CraftingProjects.projects[1];assert(saved.nativeRecipe.requirements.uniqueModifier.minValue==120)
 local result=sim.simulate(raw,saved.nativeRecipe,{trials=10,maxActions=4,seed=104729});assert(result.sampled and result.trials==10)
 local xml=build:SaveDB("Variant Divine test");loadBuildFromXML(xml,"Variant Divine test");ui:bind(build);saved=build.savers.CraftingProjects.projects[1];assert(saved.startingItem:find("Selected Variant: 3",1,true) and saved.nativeRecipe.requirements.uniqueModifier.minValue==120,"Saved variant guide did not reopen")
 ui:restore()
end
print("UNIQUE_VARIANT_DIVINE_UI_OK")
