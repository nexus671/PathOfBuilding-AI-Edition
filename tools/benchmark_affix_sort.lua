-- Compare one crafted ring modifier sort without opening a native window.
-- The fixture is read-only; conversion and Full DPS selection happen in memory.
local fixture=assert(arg[1],"Supply a build XML path")
local stat=arg[2] or "Life"
arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local file=assert(io.open(fixture,"rb"));local raw=file:read("*a");file:close()
loadBuildFromXML(raw,"Read-only modifier sort benchmark");assert(not main.popups[1],"The fixture needs interactive conversion")
build.treeTab:ConvertToVersion(latestTreeVersion,true,false)
for _,group in ipairs(build.skillsTab.socketGroupList) do if group.enabled~=false then group.includeInFullDPS=true end end
build.buildFlag=true;runCallback("OnFrame")
local tab=build.itemsTab
local item=new("Item"):Item("Rarity: RARE\nNew Item\nGold Ring\nItem Level: 86\nCrafted: true\nPrefix: None\nPrefix: None\nSuffix: None\nSuffix: None\nQuality: 0\nLevelReq: 0\nImplicits: 0")
tab.displayItem=item;tab.controls.craftingSorting:SelByValue(stat,"stat")
assert(tab.controls.craftingSorting:GetSelValue().stat==stat,"Unknown modifier sort stat")
local original=build.calcsTab.GetMiscCalculator;local candidates,full=0,0;local values={}
build.calcsTab.GetMiscCalculator=function(self)
 local calc,base=original(self)
 return function(override,useFull) candidates=candidates+1;if useFull~=false then full=full+1 end;local output=calc(override,useFull);values[tostring(data.powerStatList.GetFromOutput(output,tab.controls.craftingSorting:GetSelValue()))]=true;return output end,base
end
local start=os.clock();tab:UpdateAffixControl(tab.controls.displayItemAffix1,item,"Prefix","prefixes",1,{});local seconds=os.clock()-start
local groups={};for _,entry in ipairs(tab.controls.displayItemAffix1.list) do if type(entry)=="table" then groups[#groups+1]=table.concat(entry.modList,",") end end
local distinct=0;for _ in pairs(values) do distinct=distinct+1 end
print("AFFIX_SORT_BENCHMARK "..require("dkjson").encode({distinctValues=distinct,stat=stat,candidates=candidates,fullDPSCalculations=full,seconds=seconds,groups=#groups,orderHash=require("sha1")(table.concat(groups,"\n")),treeVersion=build.spec.treeVersion,limitations="Synthetic in-memory fixture; CPU time is not native desktop latency."}))
