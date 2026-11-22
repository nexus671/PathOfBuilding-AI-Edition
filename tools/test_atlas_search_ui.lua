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
	assert(selected,"Allocated search result lost its selection or state");ui:click("undo")
	ui:choose("mechanic","All mechanics");ui:text("search","Unwavering Vision");ui:click("find")
	local function result() for _,row in ipairs(c.results.list) do if row.val==65225 then return row end end end
	assert(result() and result().subtitle:find("+",1,true),"Search did not show the connection cost")
	ui:click("allocate");assert(result().subtitle:find("Allocated",1,true),"Search cost stayed stale after connecting")
	ui:click("undo");assert(not result().subtitle:find("Allocated",1,true),"Search cost stayed stale after undo")
	ui:click("avoid");assert(result().subtitle:find("Blocked",1,true),"Search did not show the avoided node")
	ui:click("clearAvoid");assert(result().subtitle:find("+",1,true),"Search cost stayed blocked after clearing avoidance")
	ui:restore()
end
print("ATLAS_SEARCH_UI_OK")
