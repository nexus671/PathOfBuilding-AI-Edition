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
local ringTemplate
for _,entries in pairs(data.uniques) do for _,raw in ipairs(entries) do if raw:match("^%s*Berek's Grip\n") then ringTemplate=raw end end end
local function catalystRing(index)
 return "Rarity: UNIQUE\n"..assert(ringTemplate):gsub("^([^\r\n]+\n[^\r\n]+\n)","%1Selected Variant: "..index.."\nItem Level: 83\nCatalyst: Fertile\nCatalystQuality: 20\n",1)
end
for index=1,3 do
 local raw=catalystRing(index);local options=assert(unique.divineOptions(raw));local life
 for _,row in ipairs(options) do if row.line=="+(30-40) to maximum Life" then life=row end end
 assert(life and life.min==36 and life.max==48 and life.current==42,"Catalyst-scaled range was not preserved")
 for seed=1,12 do
  local result=unique.divine(raw,require("Modules.CalcEncounter").seed(104729,seed,47));local item=unique.inspect(result.itemText)
  assert(item.variant==index and item.catalystQuality==20 and result.catalystModeled,"Variant or catalyst changed")
  if index~=1 then assert(result.itemText:find("{variant:1}{tags:elemental_damage}(10-15)% increased Cold Damage",1,true),"Inactive variant changed") end
  local reopened=assert(unique.divineOptions(result.itemText));local rolledLife
  for _,row in ipairs(reopened) do if row.line=="+(30-40) to maximum Life" then rolledLife=row end end
  assert(rolledLife and rolledLife.current>=36 and rolledLife.current<=48,"Scaled roll did not reopen")
  local switched=result.itemText:gsub("Selected Variant: "..index,"Selected Variant: "..(index==1 and 2 or 1))
  assert(unique.divineOptions(switched),"Switching variants lost catalyst support")
 end
end
local doedre
for _,entries in pairs(data.uniques) do for _,raw in ipairs(entries) do if raw:match("^%s*Doedre's Damning\n") then doedre=raw end end end
local function catalystDoedre(index)
 return "Rarity: UNIQUE\n"..assert(doedre):gsub("^([^\r\n]+\n[^\r\n]+\n)","%1Selected Variant: "..index.."\nItem Level: 83\n",1)
end
for index=1,2 do
 local raw=catalystDoedre(index)
 local result=unique.catalystPreview(raw,4,20)
 assert(result.itemText:find("{variant:1}{tags:attribute}+(5-10) to Intelligence",1,true),"Catalyst preview changed an inactive variant")
 for variant=1,2 do
  local switched=result.itemText:gsub("Selected Variant: "..index,"Selected Variant: "..variant)
  local item=unique.inspect(switched);assert(item.variant==variant and item.catalystQuality==20)
  local implicit=item.implicitModLines[1];local shown=itemLib.applyRange(implicit.line,implicit.range or 0.5,item:GetModLineValueScalar(implicit,"implicit"))
  assert(shown=="+30 to maximum Mana","Catalyst preview lost implicit scaling: "..shown)
  local options=assert(unique.divineOptions(switched));assert(#options>0,"Catalyst preview did not preserve variant rolls")
 end
end
local missingTag=catalystDoedre(2):gsub("{variant:1}{tags:attribute}","{variant:1}",1)
assert(not pcall(unique.catalystPreview,missingTag,4,20),"Missing inactive variant tags were accepted")
for _,entry in ipairs({
 {name="Berek's Grip",tags="elemental,cold,lightning,resistance",text="Cold and Lightning"},
}) do
 local template
 for _,entries in pairs(data.uniques) do for _,raw in ipairs(entries) do if raw:match("^%s*"..entry.name.."\n") then template=raw end end end
 local raw="Rarity: UNIQUE\n"..assert(template):gsub("^([^\r\n]+\n[^\r\n]+\n)","%1Selected Variant: 1\nItem Level: 83\n",1)
 local result=unique.catalystPreview(raw,8,20);local item=unique.inspect(result.itemText)
 local implicit=item.implicitModLines[1];local shown=itemLib.applyRange(implicit.line,implicit.range or 0.5,item:GetModLineValueScalar(implicit,"implicit"))
 assert(shown=="+16% to "..entry.text.." Resistances","Two-Stone implicit scaled incorrectly: "..shown)
 assert(result.itemText:find("{tags:"..entry.tags.."}",1,true),"Two-Stone implicit used the wrong base tags")
 local bad=raw:gsub("%(12%-16%)%% to "..entry.text,"(1-2)%% to "..entry.text,1)
 assert(not pcall(unique.catalystPreview,bad,8,20),"Invalid Two-Stone implicit was accepted")
end
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
newBuild();main.popups={};local ui=UI.install({width=1024,height=768});ui:bind(build)
local project={id="variant-catalyst",title="Variant catalyst",slot="Ring 1",startingItem=catalystDoedre(2),goals={},steps={}}
build.savers.CraftingProjects:Upsert(project);local control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
ui:click("catalystPlan");ui:click("preview")
local found=false;for _,row in ipairs(control.itemMods.list) do if table.concat(row):find("+30 to maximum Mana",1,true) then found=true end end
assert(found,"Catalyst preview did not update the unique item display");ui:restore()
newBuild();main.popups={};ui=UI.install({width=1024,height=768});ui:bind(build)
local grip=catalystRing(3):gsub("\nCatalyst: Fertile\nCatalystQuality: 20","")
project={id="two-stone-catalyst",title="Two-Stone catalyst",slot="Ring 1",startingItem=grip,goals={},steps={}}
build.savers.CraftingProjects:Upsert(project);control=require("Classes.CraftingUniqueQualityControl").Open(build,project)
ui:click("catalystPlan");ui:choose("kind",8,"val");ui:click("preview")
found=false;for _,row in ipairs(control.itemMods.list) do if table.concat(row):find("+16% to Cold and Lightning Resistances",1,true) then found=true end end
assert(found,"Two-Stone catalyst preview did not update the item display");ui:restore()
print("UNIQUE_VARIANT_DIVINE_UI_OK")
