-- Capture read-only scalar outputs from five node edits for cross-checkout comparison.
-- Run from src with an input build XML and an output JSON path outside the build directory.
local path=assert(arg[1]);local outfile=assert(arg[2]);arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true
local f=assert(io.open(path,'rb'));local raw=f:read('*a');f:close();loadBuildFromXML(raw,'Comparison equivalence');assert(not main.popups[1]);build.treeTab:ConvertToVersion(latestTreeVersion,true,false)
for _,group in ipairs(build.skillsTab.socketGroupList) do if group.enabled~=false then group.includeInFullDPS=true end end
build.buildFlag=true;runCallback('OnFrame');local ui=require('Modules.HeadlessUI').install({width=1280,height=720});build.viewMode='TREE';ui:bind(build)
local viewer=build.treeTab.viewer;viewer.showStatDifferences=false;local draw,viewport=viewer.Draw;viewer.Draw=function(self,host,rect,events) viewport=rect;return draw(self,host,rect,events) end;ui:frame()
local nodes={};for _,node in pairsSortByKey(build.spec.nodes) do if not node.alloc and (node.type=='Normal' or node.type=='Notable') and not node.ascendancyName and node.path and #node.path==1 and node.rsq and not node.isProxy and node.group and not node.group.isProxy then nodes[#nodes+1]=node end end
local function scalar(t) local out={};for k,v in pairs(t or {}) do if type(k)=='string' and (type(v)=='number' or type(v)=='boolean' or type(v)=='string') then out[k]=v end end;return out end
assert(#nodes>=5,"Need five adjacent passive nodes")
local results={};for i=1,5 do local node=nodes[i];viewer:Focus(node.x,node.y,viewport,build);ui:frame();local x,y=viewport.x+viewport.width/2,viewport.y+viewport.height/2;ui:clickAt(x,y);ui:frame();assert(node.alloc)
 local calc,base=build.calcsTab:GetMiscCalculator();local again,base2=build.calcsTab:GetMiscCalculator();assert(calc==again and base==base2)
 results[#results+1]={base=scalar(base),removed=scalar(calc({removeNodes={[node]=true}})),main=scalar(build.calcsTab.mainOutput),detailed=scalar(build.calcsTab.calcsOutput)}
 ui:clickAt(x,y);ui:frame();assert(not node.alloc)
end
local file=assert(io.open(outfile,'wb'));file:write(require('dkjson').encode(results));file:close();print('COMPARE_CAPTURE_OK '..#results)
