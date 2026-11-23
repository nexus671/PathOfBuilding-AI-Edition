arg={};dofile('HeadlessWrapper.lua');newBuild()
local recovery=require('Modules.PlanningRecovery');local inv=require('Modules.CraftingInventory');local sim=require('Modules.CraftingSimulator')
local lfs=require('lfs');local dir=os.tmpname();os.remove(dir);assert(lfs.mkdir(dir));recovery.testDirectory=dir;recovery.cache={}
local function craft(id)
 local p={id=id,title='Project '..id,slot='Helmet',startingItem='Rarity: NORMAL\nIron Hat\nItem Level: 86',goals={},steps={}}
 local run=inv.run(sim.model(p.startingItem).initial);run.project=p;run.kind='workbench';return {plan=run}
end
for _,id in ipairs({'a','b','c'}) do assert(recovery.save(build,'crafting',craft(id),true)) end
assert(#recovery.listCrafting(build)==3,'All projects must retain separate recovery files')
for _,id in ipairs({'a','b','c'}) do assert(recovery.load(build,'crafting',id).entry.plan.project.id==id) end
local changed=craft('b');changed.plan.project.title='Updated B';assert(recovery.save(build,'crafting',changed,true))
local latest=recovery.load(build,'crafting','b');local f=assert(io.open(latest.path,'wb'));f:write('{');f:close()
assert(recovery.load(build,'crafting','b').entry.plan.project.title=='Project b')
assert(recovery.forCraftingProject(build,'a').draft.project.id=='a')
recovery.session='next-session';recovery.cache={};local scan=assert(recovery.startScan(build));while coroutine.status(scan)~='dead' do assert(coroutine.resume(scan)) end
assert(recovery.hasPending(build),'Earlier project drafts should be discoverable')
local ui=require('Modules.HeadlessUI').install({width=1024,height=768});ui:bind(build);build.planningWorkspace=require('Modules.PlanningWorkspace').new(build)
require('Classes.PlanningToolsControl').Recovery(build);local rows=main.popups[1].controls.results.list;local labels={};for _,row in ipairs(rows) do labels[#labels+1]=StripEscapes(row[1] or '') end;local text=table.concat(labels,' ')
for _,id in ipairs({'a','b','c'}) do assert(text:find('Project '..id,1,true),'Recovery browser omitted project '..id) end
main.popups={};ui:restore();local removed=recovery.forgetCraftingProject(build,'a');assert(removed and not recovery.forCraftingProject(build,'a'));assert(recovery.forCraftingProject(build,'b') and recovery.forCraftingProject(build,'c'))
for _,id in ipairs({'b','c'}) do recovery.clear(build,'crafting',id) end
-- Older shared-slot records remain discoverable after upgrading.
recovery.session='old-session';recovery.cache={};assert(recovery.save(build,'crafting',craft('legacy'),true));local record=recovery.load(build,'crafting','legacy');local file=assert(io.open(record.path,'rb'));local raw=file:read('*a');file:close()
local legacy=record.path:gsub('%-crafting%-[a-f0-9]+%-%d%.json$','-crafting-1.json');assert(legacy~=record.path);file=assert(io.open(legacy,'wb'));assert(file:write(raw));file:close();recovery.clear(build,'crafting','legacy');assert(recovery.forCraftingProject(build,'legacy'))
recovery.clear(build,'crafting');assert(lfs.rmdir(dir));recovery.testDirectory=nil;print('CRAFT_PROJECT_RECOVERY_OK')
