local output=assert(arg[1]);arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local estimate=require("Modules.MapCraftEstimate");local state={baseId="Metadata/Items/Maps/MapWorldsStrand",tier=16,itemLevel=83,rarity="rare",selected={}}
local opts={avoid={"MapMonsterAreaOfEffectMapWorlds"},trials=20,maxAttempts=10,seed=42,price={amount=0.5,currency="chaos"}}
local result=estimate.run(state,opts);assert(result.successes==20 and result.attempts==20 and result.cost.maxPerTrial==0.5 and result.cost.p99==0.5,"Maximum must reflect sampled trials")
local map=require("Modules.MapCraftingData");local nightmare={baseId="Metadata/Items/Maps/MapWorldsAbomination",tier=17,itemLevel=84,rarity="rare",selected={}}
local avoid={};local page=map.inspect(nightmare.baseId,17,84,{},"",0,100,nil,"rare");for _,entry in ipairs(page.candidates) do avoid[#avoid+1]=entry.id end
local failed=estimate.run(nightmare,{avoid=avoid,trials=3,maxAttempts=2,seed=42,price={amount=0.5,currency="chaos"}});assert(failed.successes==0 and failed.cost.maxPerTrial==1,"Unsuccessful trials must contribute their full spent amount")
local valid=copyTable(state);valid.selected={"MapContainsMirageWorlds"}
local updates=0;estimate.run(valid,{avoid=opts.avoid,trials=1,maxAttempts=1,seed=42},function(progress) assert(progress.trial);updates=updates+1 end);assert(updates>0 and valid.selected[1]=="MapContainsMirageWorlds")
local function rejected(input,expected)
 local ok,err=pcall(estimate.run,input,{avoid=opts.avoid,trials=1,maxAttempts=1,seed=42});assert(not ok and tostring(err):find(expected,1,true),tostring(err))
end
local low=copyTable(valid);low.itemLevel=1;rejected(low,"not eligible")
local unknown=copyTable(valid);unknown.selected={"NonexistentMapModifier"};rejected(unknown,"Unknown selected")
local rolls=copyTable(valid);rolls.rolls={{id="MapMonsterAreaOfEffectMapWorlds",values={}}};rejected(rolls,"Invalid map roll modifier")
local sparse=copyTable(valid);sparse.selected={[2]="MapContainsMirageWorlds"};rejected(sparse,"Invalid selected map modifiers")
local badRolls=copyTable(valid);badRolls.rolls=false;rejected(badRolls,"Invalid map rolls")
local sparseRolls=copyTable(valid);sparseRolls.rolls={[2]={id="MapContainsMirageWorlds",values={}}};rejected(sparseRolls,"Invalid map rolls")
local UI=require("Modules.HeadlessUI");local tasks=require("Modules.CraftingTasks")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
 local settings={wantedGroups={},avoid=opts.avoid,trials=2,maxAttempts=10,price=opts.price}
 local c=require("Classes.MapCraftEstimateControl").Open(build,{state=state,settings=settings,apply=function() end})
 ui:click("run");for _=1,10000 do if not tasks.job then break end;tasks.tick(build) end;assert(not tasks.job,"Map estimate did not finish")
 local text="";for _,row in ipairs(c.report.list) do text=text..StripEscapes(row[1] or "").." " end
 assert(text:find("observed maximum: 0.5 chaos",1,true),text);assert(text:find("Configured cost limit per trial: 5 chaos",1,true),text)
 ui:frame():write(output.."/"..size[1].."-map-cost-maximum.json");ui:click("close");ui:restore();main.popups={}
end
print("MAP_COST_MAXIMUM_OK")
