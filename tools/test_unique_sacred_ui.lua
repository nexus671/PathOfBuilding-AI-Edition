-- Exercise the unique Sacred preview, its guide, recipe and linked filter pickup.
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI")
for _,size in ipairs({{960,640},{1024,768},{1280,720}}) do
    newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
    local raw="Rarity: UNIQUE\nThe Apostate\nSavant's Robe\nItem Level: 86\nEnergy Shield: 132\nImplicits: 0\nGain Maximum Life instead of Maximum Energy Shield from Equipped Armour Items"
    local malformed={id="sacred-bad",title="Ambiguous item",slot="Body Armour",startingItem=raw.."\nEnergy Shield: 100",goals={},steps={}}
    local unavailable=require("Classes.CraftingUniqueQualityControl").Open(build,malformed)
    assert(not unavailable.sacred:IsEnabled(),"Ambiguous Sacred preview was offered")
    assert(unavailable.sacred.tooltipText()=="Duplicate base defence property","Sacred preview did not explain the ambiguity")
    ui:click("close")
    local project={id="sacred-ui",title="Sacred guide",slot="Body Armour",startingItem=raw,goals={},steps={}}
    build.savers.CraftingProjects:Upsert(project);local controls=require("Classes.CraftingUniqueQualityControl").Open(build,project)
    assert(controls.sacred:IsEnabled(),"Sacred preview unavailable")
	assert(controls.sacred.tooltipText():find("shared",1,true) and controls.sacred.tooltipText():find("unverified",1,true),"Sacred tooltip omitted the model and its uncertainty")
    ui:click("sacred");if output then ui:frame():write(output.."/"..size[1].."-unique-sacred.json") end
    ui:click("apply")
    ui:click("guide");assert(controls.recipe:IsEnabled(),"Sacred recipe unavailable");ui:click("recipe")
    local saved=build.savers.CraftingProjects.projects[1]
    assert(saved.steps[1].uniqueCraft.method=="sacred" and saved.nativeRecipe.steps[1].method=="sacred" and saved.nativeRecipe.steps[2].method=="quality","Sacred guide or recipe not kept")
    local run=require("Modules.CraftingSimulator").simulate(raw,saved.nativeRecipe,{trials=2,maxActions=101,seed=104729})
    assert(run.successes>0,"Sacred then quality recipe could not reproduce its preview")
    local filters=require("Modules.LootFilters");local rules=filters.generate(build,filters.profile("sacred","Filter"));local found=false
    for _,rule in ipairs(rules) do if rule.origin=="craft:sacred-ui" and rule.text:find("Sacred Orb",1,true) then found=true end end
    assert(found,"Sacred Orb pickup was not generated")
    ui:click("close");local xml=build:SaveDB("Sacred guide");loadBuildFromXML(xml,"Sacred guide");saved=build.savers.CraftingProjects.projects[1]
    assert(saved.steps[1].uniqueCraft.method=="sacred" and saved.nativeRecipe.steps[1].method=="sacred","Sacred guide or recipe did not survive reopening")
end
print("UNIQUE_SACRED_UI_OK")
