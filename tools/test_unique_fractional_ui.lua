-- Plan and retain a fractional Divine target for a current unique item.
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local uiModule=require("Modules.HeadlessUI");local unique=require("Modules.CraftingUniqueQuality");local sim=require("Modules.CraftingSimulator")
local raw="Rarity: UNIQUE\nVeil of Flesh\nCallous Mask\nItem Level: 83\n+0.4% to Critical Strike Chance\n130% increased Evasion and Energy Shield\n17% increased maximum Life\nSkills Cost Life instead of 100% of Mana Cost\nGain Bitterblood equal to Life spent\nMaximum Bitterblood is equal to your Maximum Life"
local options=assert(unique.divineOptions(raw));local target
for _,row in ipairs(options) do if row.line=="+(0.3-0.5)% to Critical Strike Chance" then target=row end end
assert(target and target.min==0.3 and target.max==0.5 and target.step==0.01 and target.current==0.4,"Incorrect fractional bounds")
local seen={};for seed=1,100 do local result=unique.divine(raw,require("Modules.CalcEncounter").seed(104729,seed,31));for _,row in ipairs(assert(unique.divineOptions(result.itemText))) do if row.line==target.line then seen[string.format("%.2f",row.current)]=true end end end
local count=0;for _ in pairs(seen) do count=count+1 end;assert(count==21 and seen["0.35"],"Fractional range outcomes were incomplete")
assert(unique.divineReason(raw:gsub("130%% increased Evasion","130.5%% increased Evasion")),"Fractional copy matched an integer range")
local wholeRaw="Rarity: UNIQUE\nTanu Ahi\nWyrmscale Gauntlets\nItem Level: 83\n10% increased Attack Speed\n125% increased Armour and Evasion\n2.5% of Physical Attack Damage Leeched as Life\n10% chance to gain Adrenaline for 2 Seconds when Leech is\nremoved by Filling Unreserved Life\n10% chance to gain Onslaught for 4 Seconds when Leech is\nremoved by Filling Unreserved Life"
local wholeOptions=assert(unique.divineOptions(wholeRaw));local wholeTarget,wholeIndex
for index,row in ipairs(wholeOptions) do if row.line=="(2-3)% of Physical Attack Damage Leeched as Life" then wholeTarget=row;wholeIndex=index end end
assert(wholeTarget and wholeTarget.min==2 and wholeTarget.max==3 and wholeTarget.step==0.01 and wholeTarget.current==2.5,"Whole endpoints lost their fractional precision")
local wholeSeen={};for seed=1,150 do local result=unique.divine(wholeRaw,require("Modules.CalcEncounter").seed(104729,seed,31));for _,row in ipairs(assert(unique.divineOptions(result.itemText))) do if row.line==wholeTarget.line then wholeSeen[string.format("%.2f",row.current)]=true end end end
local wholeCount=0;for _ in pairs(wholeSeen) do wholeCount=wholeCount+1 end;assert(wholeCount>50,"Whole endpoints were sampled as whole numbers")
local fractionalGoal={uniqueModifier={line=wholeTarget.line,minValue=2.75}};assert(not unique.matches(wholeRaw,fractionalGoal))
assert(not pcall(unique.matches,wholeRaw,{uniqueModifier={line=wholeTarget.line,minValue=2.755}}),"Off-grid goal was accepted")
local catalystRaw="Rarity: UNIQUE\nTainted Pact\nCoral Amulet\nItem Level: 83\nCatalyst: Fertile\nCatalystQuality: 20\nImplicits: 1\nRegenerate 3.6 Life per second\n+25 to Strength\n3% of Physical Attack Damage Leeched as Life\n1.44% of Physical Attack Damage Leeched as Mana\nTaking Chaos Damage over Time heals you instead while Leeching Life"
local catalystOptions=assert(unique.divineOptions(catalystRaw));local catalystTarget,catalystIndex
for index,row in ipairs(catalystOptions) do if row.line=="(2-3)% of Physical Attack Damage Leeched as Life" then catalystTarget=row;catalystIndex=index end end
assert(catalystTarget and catalystTarget.min==2.4 and catalystTarget.max==3.6 and catalystTarget.current==3 and catalystTarget.step==0.01,"Catalyst-scaled fractional bounds were incorrect")
local catalystSeen={};for seed=1,60 do
 local result=unique.divine(catalystRaw,require("Modules.CalcEncounter").seed(104729,seed,31))
 assert(result.itemText:find("{tags:attribute}",1,true) and result.itemText:find("{tags:resource,attack}",1,true),"Divine roll lost catalyst tags")
 for _,row in ipairs(assert(unique.divineOptions(result.itemText))) do if row.line==catalystTarget.line then catalystSeen[string.format("%.2f",row.current)]=true end end
end
local catalystCount=0;for _ in pairs(catalystSeen) do catalystCount=catalystCount+1 end;assert(catalystCount>20,"Catalyst-scaled fractional rolls did not vary")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=uiModule.install({width=size[1],height=size[2]});ui:bind(build)
 local project={id="fractional",title="Fractional Divine",slot="Helmet",startingItem=raw,goals={},steps={}}
 build.savers.CraftingProjects:Upsert(project);local control=require("Classes.CraftingUniqueQualityControl").Open(build,project);assert(control.divine:IsEnabled());ui:click("divine")
 ui:choose("stat","modifier:1","val");ui:text("target","0.455");assert(not main.popups[1].controls.plan:IsEnabled() and main.popups[1].controls.targetHelp.label():find("steps of 0.01",1,true),"Off-grid target lacked useful guidance")
 ui:text("target","0.45");assert(main.popups[1].controls.plan:IsEnabled(),"Valid fractional target was rejected")
 if output then ui:frame():write(output.."/"..size[1].."-unique-fractional.json") end
 ui:click("plan");local saved=build.savers.CraftingProjects.projects[1];assert(saved.nativeRecipe.requirements.uniqueModifier.minValue==0.45,"Target was not saved")
 local result=sim.simulate(raw,saved.nativeRecipe,{trials=10,maxActions=4,seed=104729});assert(result.sampled and result.trials==10)
 local xml=build:SaveDB("Fractional test");loadBuildFromXML(xml,"Fractional test");ui:bind(build);assert(build.savers.CraftingProjects.projects[1].nativeRecipe.requirements.uniqueModifier.minValue==0.45,"Reopen lost fractional target")
 main.popups={};newBuild();ui:bind(build)
 local wholeProject={id="whole-endpoint",title="Leech roll",slot="Gloves",startingItem=wholeRaw,goals={},steps={}}
 build.savers.CraftingProjects:Upsert(wholeProject);local wholeControl=require("Classes.CraftingUniqueQualityControl").Open(build,wholeProject);assert(wholeControl.divine:IsEnabled());ui:click("divine")
 ui:choose("stat","modifier:"..wholeIndex,"val");ui:text("target","2.75");assert(main.popups[1].controls.plan:IsEnabled(),"Whole-endpoint fractional target was rejected")
 if output then ui:frame():write(output.."/"..size[1].."-unique-whole-endpoint.json") end
 ui:click("plan");local wholeSaved=build.savers.CraftingProjects.projects[1];assert(wholeSaved.nativeRecipe.requirements.uniqueModifier.minValue==2.75,"Whole-endpoint target was not saved")
 local wholeResult=sim.simulate(wholeRaw,wholeSaved.nativeRecipe,{trials=10,maxActions=4,seed=104729});assert(wholeResult.sampled and wholeResult.trials==10)
 main.popups={};newBuild();ui:bind(build)
 local catalystProject={id="catalyst-fraction",title="Catalyst leech",slot="Amulet",startingItem=catalystRaw,goals={},steps={}}
 build.savers.CraftingProjects:Upsert(catalystProject);local catalystControl=require("Classes.CraftingUniqueQualityControl").Open(build,catalystProject);assert(catalystControl.divine:IsEnabled());ui:click("divine")
 ui:choose("stat","modifier:"..catalystIndex,"val");ui:text("target","3.1");assert(main.popups[1].controls.plan:IsEnabled(),"Catalyst-scaled target was rejected")
 if output then ui:frame():write(output.."/"..size[1].."-unique-catalyst-fraction.json") end
 ui:click("plan");local catalystSaved=build.savers.CraftingProjects.projects[1];assert(catalystSaved.nativeRecipe.requirements.uniqueModifier.minValue==3.1,"Catalyst target was not saved")
 local catalystResult=sim.simulate(catalystRaw,catalystSaved.nativeRecipe,{trials=10,maxActions=4,seed=104729});assert(catalystResult.sampled and catalystResult.trials==10)
 local catalystXml=build:SaveDB("Catalyst fraction test");loadBuildFromXML(catalystXml,"Catalyst fraction test");ui:bind(build);assert(build.savers.CraftingProjects.projects[1].nativeRecipe.requirements.uniqueModifier.minValue==3.1,"Reopening lost catalyst target")
 ui:restore()
end
print("UNIQUE_FRACTIONAL_UI_OK")
