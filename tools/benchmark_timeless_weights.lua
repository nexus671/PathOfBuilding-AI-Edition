-- Compare Timeless fallback weights and calculations on a read-only build fixture.
-- Run from src; timings are headless CPU measurements, not native UI latency.
local fixture=assert(arg[1]);arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true
local f=assert(io.open(fixture,'rb'));local raw=f:read('*a');f:close();loadBuildFromXML(raw,'Synthetic timeless benchmark');assert(not main.popups[1])
for _,group in ipairs(build.skillsTab.socketGroupList) do if group.enabled~=false then group.includeInFullDPS=true end end
build.buildFlag=true;runCallback('OnFrame');build.timelessData.jewelType={id=11};build.timelessData.conquerorType={};build.timelessData.jewelSocket={id=26196};build.treeTab:FindTimelessJewel()
local controls=assert(main.popups[1]).controls;local get=build.calcsTab.GetMiscCalculator
for _,stat in ipairs({'Life','CombinedDPS','FullDPS','ProjectileAvoidChance'}) do
 controls.fallbackWeightsList:SelByValue(stat,'stat');assert(controls.fallbackWeightsList:GetSelValue().stat==stat)
 local previous
 for _,force in ipairs({true,false}) do
  local calls,full=0,0;build.calcsTab.GetMiscCalculator=function(self) local calc,base=get(self);return function(override,flag) calls=calls+1;local enabled=force or flag;if enabled~=false then full=full+1 end;return calc(override,enabled) end,base end
  local start=os.clock();controls.fallbackWeightsButton.onClick();local duration=os.clock()-start;local result=build.timelessData.searchListFallback
  if previous and result~=previous then print('BEFORE\n'..previous..'\nAFTER\n'..result);error('Fallback weights changed for '..stat) else previous=result end
  print('TIMELESS_WEIGHTS',stat,force and 'baseline' or 'candidate',duration,'calls',calls,'full',full,'length',#result)
 end
end
build.calcsTab.GetMiscCalculator=get
