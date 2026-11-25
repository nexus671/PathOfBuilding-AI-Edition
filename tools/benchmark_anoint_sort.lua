-- Compare anoint sorting against the prior always-Full-DPS behavior on an in-memory fixture.
-- Run from src; the supplied build is never saved. Timings exclude native rendering.
local fixture=assert(arg[1]);arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true
local f=assert(io.open(fixture,'rb'));local raw=f:read('*a');f:close();loadBuildFromXML(raw,'Synthetic anoint sort');assert(not main.popups[1])
for _,group in ipairs(build.skillsTab.socketGroupList) do if group.enabled~=false then group.includeInFullDPS=true end end
build.buildFlag=true;runCallback('OnFrame')
local tab=build.itemsTab;tab:SetDisplayItem(new('Item'):Item('Rarity: NORMAL\nAmber Amulet\nItem Level: 86'))
local list={};for _,node in pairsSortByKey(build.spec.tree.nodes) do if node.recipe and #node.recipe>0 and node.modKey~='' then list[#list+1]=node;if #list==30 then break end end end
assert(#list==30)
local control=new('NotableDBControl'):NotableDBControl(nil,{0,0,360,360},tab,list,'ANOINT')
local get=build.calcsTab.GetMiscCalculator
for _,stat in ipairs({'Life','CombinedDPS','FullDPS','PhysicalTakenHit','ProjectileAvoidChance','EffectiveMovementSpeedMod','MinionLife'}) do
 control:SetSortMode(stat);assert(control.sortDetail and control.sortDetail.stat==stat,"Unknown anoint sort stat: "..stat)
 local snapshots={};for _,force in ipairs({true,false}) do
 local calls,full=0,0
 build.calcsTab.GetMiscCalculator=function(self) local f,b=get(self);return function(override,flag) calls=calls+1;local use=force or flag;if use~=false then full=full+1 end;return f(override,use) end,b end
 local start=os.clock();local co=coroutine.create(control.ListBuilder);repeat local ok,err=coroutine.resume(co,control);assert(ok,err) until coroutine.status(co)=='dead'
 local elapsed=os.clock()-start;local values={};local order={};for i,node in ipairs(control.list) do values[node.id]=node.measuredPower;order[i]=node.id end
 snapshots[#snapshots+1]={values=values,order=order,seconds=elapsed,calls=calls,full=full}
 end
 for id,value in pairs(snapshots[1].values) do local other=snapshots[2].values[id];assert(value==other or math.abs(value-other)<1e-8,'Power changed for '..stat..' '..id..': '..value..' '..tostring(other)) end
 for i,id in ipairs(snapshots[1].order) do assert(id==snapshots[2].order[i],'Order changed for '..stat) end
 print('ANOINT_SORT',stat,'baseline',snapshots[1].seconds,'candidate',snapshots[2].seconds,'calls',snapshots[2].calls,'full_before',snapshots[1].full,'full_after',snapshots[2].full)
end
build.calcsTab.GetMiscCalculator=get
