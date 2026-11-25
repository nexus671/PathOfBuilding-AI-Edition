-- Search results must track edits and distinguish repeated node names.
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
	newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
	local plan={id="search-test",title="Search test",version="3.29.3",budget=138,nodes={},notes=""}
	local c=require("Classes.AtlasPlannerControl").Open(build,plan)
	ui:choose("mechanic","Essence");local duplicates=0
	for _,row in ipairs(c.results.list) do if row.duplicate then assert(row.subtitle:find("#"..row.val,1,true),"Repeated result lacks an identifier");duplicates=duplicates+1 end end
	assert(duplicates>1,"Expected repeated Essence search results")
	if output then ui:frame():write(output.."/"..size[1].."-atlas-search-duplicates.json") end
	local first=c.results.list[1];local id=first.val;c.results.selFunc(1,first);ui:click("allocate")
	local connected=require("Modules.AtlasPlanner").connect(plan,{id},{});local costs=require("Modules.AtlasStrategy").costs(connected,{})
	local prior=-1;local selected=false
	for _,row in ipairs(c.results.list) do
		assert(row.cost==costs[row.val],"A search result retained an outdated cost")
		local cost=row.cost or math.huge;assert(cost>=prior,"Search results are not sorted by updated cost");prior=cost
		if row.val==id then selected=row.selected and row.subtitle:find("Allocated",1,true)~=nil end
	end
	assert(selected,"Allocated search result lost its selection or state")
	ui:click("routes");assert(main.popups[1].title=="Compare Atlas routes" and not main.popups[1].controls.choose:IsEnabled(),"An allocated target must not offer a no-op route");main:ClosePopup()
	ui:click("undo");ui:click("routes");assert(main.popups[1].controls.choose:IsEnabled(),"A new route must remain available");ui:click("choose");local routed=false;for _,row in ipairs(c.results.list) do if row.val==id then routed=row.selected end end;assert(routed,"Using a route must allocate its target");ui:click("undo")
	ui:choose("mechanic","All mechanics");ui:text("search","Unwavering Vision");ui:click("find")
	local function result() for _,row in ipairs(c.results.list) do if row.val==65225 then return row end end end
	assert(result() and result().subtitle:find("+",1,true),"Search did not show the connection cost")
	ui:click("allocate");assert(result().subtitle:find("Allocated",1,true),"Search cost stayed stale after connecting")
	ui:click("undo");assert(not result().subtitle:find("Allocated",1,true),"Search cost stayed stale after undo")
	ui:click("avoid");assert(result().subtitle:find("Blocked",1,true),"Search did not show the avoided node")
	ui:click("clearAvoid");assert(result().subtitle:find("+",1,true),"Search cost stayed blocked after clearing avoidance")
	ui:text("search","a")
	local expected=require("Modules.AtlasStrategy").results(plan,"a",nil,{})
	assert(#expected>100 and #c.results.list==#expected,"Broad Atlas search did not include every match")
	ui:frame();local scroll=c.results.controls.scrollBar;assert(scroll.enabled and scroll.offsetMax>0,"Broad Atlas results cannot be scrolled")
	local first,last=c.results.list[1],c.results.list[#c.results.list];local x,y=c.results:GetPos();local _,h=c.results:GetSize()
	ui:clickAt(x+8,y+20);assert(c.canvas.focus==first.val,"Could not focus the first Atlas result")
	ui:key("END");assert(c.canvas.focus==last.val,"End did not select the final Atlas result");ui:frame();assert(scroll.offset>0,"End did not scroll the selection into view")
	ui:key("HOME");assert(c.canvas.focus==first.val,"Home did not select the first Atlas result")
	ui:key("PAGEDOWN");assert(c.canvas.focus~=first.val,"Page Down did not advance the selection")
	ui:key("PAGEUP");assert(c.canvas.focus==first.val,"Page Up did not return to the first result")
	ui.keys.ALT=true;ui:key("END");ui.keys.ALT=nil;assert(c.canvas.focus==first.val,"Modified End unexpectedly moved the selection")
	ui:click("search");ui:key("HOME");ui:key("END");assert(c.canvas.focus==first.val and c.search.buf=="a","Text-field navigation changed the Atlas selection")
	scroll:SetOffset(scroll.offsetMax)
	if output then ui:frame():write(output.."/"..size[1].."-atlas-search-all-tail.json") end
	ui:clickAt(x+8,y+h-20);assert(c.canvas.focus==last.val,"Last Atlas result could not be selected after scrolling")
	ui:text("search","Essence");assert(scroll.offset==0,"Changing the query did not return to the first result")
	ui:restore()
end
print("ATLAS_SEARCH_UI_OK")
