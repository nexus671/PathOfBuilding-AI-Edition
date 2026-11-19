-- Manual region observations stay in the Atlas draft until explicitly kept.
local ui=require("Modules.PlanningUI")
local regions=require("Modules.AtlasRegions")
local M={}
function M.Open(plan,keep)
	local w,h=math.min(900,main.screenW-40),math.min(620,main.screenH-60)
	local draft=regions.validate(plan.shapedRegions or {});local selected;local c={}
	local function button(key,x,y,width,label,fn)
		c[key]=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{x,y,width,28},label,function()
			local ok,err=pcall(fn);if not ok then c.status.label="^xE9BE7B"..ui.fit(ui.errorText(err),w-32,14) end
		end))
	end
	ui.description(c,"intro",16,28,w-32,42,{"Record the maps and free Threads you can see in game. Unlisted maps are not predicted or imported."},16)
	ui.label(c,"regionLabel",16,80,"Thread type",15)
	c.region=new("DropDownControl"):DropDownControl(ui.anchor,{16,104,180,28},regions.types)
	ui.label(c,"mapLabel",212,80,"Map name",15)
	c.map=new("EditControl"):EditControl(ui.anchor,{212,104,w-388,28},"","Map name",nil,160)
	ui.label(c,"countLabel",w-160,80,"Free Threads",15)
	c.count=new("EditControl"):EditControl(ui.anchor,{w-160,104,144,28},"0",nil,"^%d",4)
	c.list=new("TextListControl"):TextListControl(ui.anchor,{16,158,w-32,h-330},nil,{})
	c.status=ui.label(c,"status",16,h-164,"",14)
	local function findRegion(value)
		for _,region in ipairs(draft) do if region.mechanic==value then return region end end
	end
	local function refresh()
		local region=findRegion(c.region:GetSelValue());local rows={}
		for _,map in ipairs(region and region.maps or {}) do
			local lines=ui.rows({map.name.." | "..map.freeThreads.." free Threads"},w-60,16)
			for _,line in ipairs(lines) do line.entry=map;rows[#rows+1]=line end
		end
		if #rows==0 then rows=ui.rows({"No maps recorded for this Thread type."},w-60,16) end
		c.list.list=rows;c.list.controls.scrollBar.offset=0
		c.status.label="^7Select a map to edit it or record a run. Changes stay in this draft."
	end
	c.region.selFunc=function() selected=nil;refresh() end
	c.list.onClick=function(hit)
		if hit and hit.line and hit.line.entry then selected=hit.line.entry.name;c.map:SetText(selected);c.count:SetText(tostring(hit.line.entry.freeThreads));refresh() end
	end
	button("upsert",16,h-126,180,"Add / update map",function()
		local candidate=copyTable(draft);local mechanic=c.region:GetSelValue();local target
		for _,region in ipairs(candidate) do if region.mechanic==mechanic then target=region end end
		if not target then target={mechanic=mechanic,maps={}};candidate[#candidate+1]=target end
		local name=c.map.buf:match("^%s*(.-)%s*$");local found
		for _,map in ipairs(target.maps) do if map.name:lower()==name:lower() then map.name=name;map.freeThreads=tonumber(c.count.buf);found=true;break end end
		if not found then target.maps[#target.maps+1]={name=name,freeThreads=tonumber(c.count.buf)} end
		draft=regions.validate(candidate);selected=name;refresh()
	end)
	button("remove",208,h-126,150,"Remove map",function()
		local target=assert(findRegion(c.region:GetSelValue()),"No region is recorded")
		local found=false;for i=#target.maps,1,-1 do if selected and target.maps[i].name==selected then table.remove(target.maps,i);found=true;break end end
		assert(found,"Select a map to remove");selected=nil;refresh()
	end)
	c.remove.enabled=function() return selected~=nil end
	local function recordRun(name)
		local involved={}
		for _,region in ipairs(draft) do for _,map in ipairs(region.maps) do if map.name:lower()==name:lower() then involved[#involved+1]=region.mechanic;break end end end
		local pw,ph=math.min(600,main.screenW-40),math.min(500,main.screenH-60);local confirm={}
		ui.description(confirm,"intro",16,26,pw-32,66,{"Select every region objective completed in "..name..". The map leaves all tracked regions; unchecked objectives do not add Threads."},16)
		for i,mechanic in ipairs(involved) do
			local check=new("CheckBoxControl"):CheckBoxControl(ui.anchor,{24,104+(i-1)*30,18},mechanic,nil,nil,false);check.labelRight=true;confirm["objective"..i]=check
		end
		confirm.apply=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{16,ph-48,180,28},"Record run",function()
			local completed={};for i,mechanic in ipairs(involved) do if confirm["objective"..i].state then completed[#completed+1]=mechanic end end
			local ok,result=pcall(regions.complete,draft,name,completed)
			if not ok then main:OpenMessagePopup("Shaped Regions",ui.errorText(result));return end
			draft=result;selected=nil;main:ClosePopup();refresh()
		end),"primary")
		confirm.close=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{pw-156,ph-48,140,28},"Cancel",function() main:ClosePopup() end))
		ui.style(confirm,{apply=true});for _,control in pairs(confirm) do control.layoutAudit="shaped-region-run" end
		main:OpenPopup(pw,ph,"Record map run",confirm,nil,nil,"close")
	end
	button("run",370,h-126,180,"Record map run",function() recordRun(assert(selected,"Select a map first")) end)
	c.run.enabled=function() return selected~=nil end
	button("threadCheck",562,h-126,150,"Check Threads",function()
		local region=assert(findRegion(c.region:GetSelValue()),"No region is recorded")
		for _,map in ipairs(region.maps) do if map.name==selected then
			assert(map.freeThreads<=100,"The Thread checker supports up to 100; review the recorded count")
			require("Classes.AtlasThreadControl").Open({mechanic=region.mechanic,threads=map.freeThreads});return
		end end
		error("Select a map first")
	end)
	c.threadCheck.enabled=function() return selected~=nil end
	c.threadCheck.tooltipText="Start with this map's recorded free Threads; add spent or bonus Threads and check the area level."
	button("overview",16,h-88,180,"All recorded maps",function()
		local entries={};for _,map in ipairs(regions.overview(draft)) do
			local details={"Recorded regions for "..map.name..":", "Unlisted regions are unknown; counts are observations, not guaranteed totals."}
			for _,region in ipairs(map.regions) do details[#details+1]=region.mechanic..": "..region.freeThreads.." free Threads" end
			entries[#entries+1]={id=map.name,label=map.name.." | "..#map.regions..(#map.regions==1 and " region" or " regions"),details=details}
		end
		require("Classes.PlanningBrowserControl").Open("Recorded region maps",entries,{action="Record run",closeOnChoose=false,choose=function(entry) main:ClosePopup();recordRun(entry.id) end})
	end)
	c.overview.tooltipText="Compare recorded region overlaps by map and record a run."
	button("removeRegion",w-176,h-126,160,"Remove region",function()
		local mechanic=c.region:GetSelValue();for i=#draft,1,-1 do if draft[i].mechanic==mechanic then table.remove(draft,i);break end end
		selected=nil;refresh()
	end)
	button("keep",16,h-48,200,"Use in Atlas draft",function() keep(regions.validate(draft));main:ClosePopup() end)
	button("close",w-156,h-48,140,"Cancel",function() main:ClosePopup() end)
	ui.style(c,{keep=true});for _,control in pairs(c) do control.layoutAudit="shaped-regions" end
	refresh();main:OpenPopup(w,h,"Shaped Regions",c,nil,"map","close")
	return c
end
return M
