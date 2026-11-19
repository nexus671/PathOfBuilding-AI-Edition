local ui=require("Modules.PlanningUI")
local M={}
local function button(c,key,x,y,w,label,run) c[key]=new("ButtonControl"):ButtonControl(ui.anchor,{x,y,w,28},label,run) end
function M.Performance(build)
	local perf=require("Modules.PlanningPerformance");local c={};local w,h=math.min(920,main.screenW-40),math.min(620,main.screenH-48)
	ui.description(c,"help",16,28,w-32,70,{"Observed processing time in this session, ordered by worst slice. Long slices identify work that can still pause input; background work is cooperative, not a separate CPU thread."},16)
	c.entries=new("TextListControl"):TextListControl(ui.anchor,{16,112,w-32,h-200},{{x=8},{x=w*0.48},{x=w*0.64},{x=w*0.80}},{})
	local function refresh()
		local rows={{height=30,textSize=16,"^7Work","^7Last / ms","^7Mean / ms","^7Worst / ms"}}
		for _,row in ipairs(perf.rows(build)) do rows[#rows+1]={height=30,textSize=15,"^7"..ui.fit(row.name,w*0.46-24,15),"^7"..string.format("%.1f",row.last),"^7"..string.format("%.1f",row.mean),"^7"..string.format("%.1f",row.worst)} end
		if #rows==1 then rows[#rows+1]={height=28,"^7Recalculate the build or measure an upgrade to collect timings."} end
		c.entries.list=rows
	end
	button(c,"refresh",16,h-48,140,"Refresh timings",refresh)
	button(c,"copy",172,h-48,140,"Copy timings",function() local lines={};for _,row in ipairs(perf.rows(build)) do lines[#lines+1]=string.format("%s: %d samples; last %.2fms, mean %.2fms, worst %.2fms",row.name,row.count,row.last,row.mean,row.worst) end;Copy(table.concat(lines,"\n")) end)
	button(c,"reset",328,h-48,140,"Reset timings",function() perf.clear(build);refresh() end)
	button(c,"close",w-156,h-48,140,"Close",function() main:ClosePopup() end)
	refresh();ui.style(c);main:OpenPopup(w,h,"Performance diagnostics",c,nil,nil,"close")
end
function M.Bundle(build)
	local bundles=require("Modules.PlanningBundle");local c={};local w,h=math.min(900,main.screenW-40),math.min(620,main.screenH-48);local imported,contents
	ui.description(c,"help",16,28,w-32,88,{"Copy a complete planning bundle, or paste one to review it as a new build. The bundle carries saved crafting guides, checkpoints, Atlas strategies and Journey plans with the character."},16)
	c.text=new("EditControl"):EditControl(ui.anchor,{16,124,w-32,112},"",nil,"^%C\t\n",bundles.limit,nil,14)
	c.text.shown=false
	local cardWidth=math.floor((w-64)/3)
	for i,entry in ipairs({{"crafts","CRAFTING GUIDES"},{"checkpoints","WORKING CHECKPOINTS"},{"atlas","ATLAS PLANS"}}) do
		local key,label=unpack(entry);ui.card(c,key,16+(i-1)*(cardWidth+16),124,cardWidth,label,function() return contents and tostring(contents[key]) or "-" end,"Kept planning data")
	end
	c.details=new("TextListControl"):TextListControl(ui.anchor,{16,252,w-32,h-330},nil,ui.rows({"Keep working crafts and Atlas drafts before exporting. Importing goes through native proposal review; it does not overwrite a saved build."},w-56))
	button(c,"export",16,h-48,172,"Copy complete bundle",function() local raw;raw,contents=bundles.export(build);Copy(raw);local lines=bundles.lines(contents);table.insert(lines,1,"Complete bundle copied to clipboard.");c.details.list=ui.rows(lines,w-56) end)
	button(c,"paste",204,h-48,140,"Paste / inspect",function() c.text:SetText(Paste());imported=bundles.import(c.text.buf);contents=imported.contents;local lines=bundles.lines(contents);table.insert(lines,1,"Ready to review: "..imported.buildName);c.details.list=ui.rows(lines,w-56) end)
	button(c,"review",360,h-48,210,"Review as new build",function()
		imported=bundles.import(c.text.buf);local bridge=require("Modules.DesktopBuildBridge");local prepared=bridge.prepareBundle(build,imported);prepared.id="bundle-"..require("sha1")(tostring({})..os.time()):sub(1,16)
		bridge.remember(prepared);bridge.prepared=prepared;bridge.status=bridge.summary(prepared);bridge.status.status="review";main:ClosePopup();require("Classes.BuildProposalControl").Review()
	end)
	c.review.enabled=function() return c.text.buf:match("%S")~=nil end
	button(c,"close",w-156,h-48,140,"Close",function() main:ClosePopup() end)
	ui.style(c,{review=true});main:OpenPopup(w,h,"Portable planning bundle",c,nil,"export","close")
end
function M.Recovery(build)
	local recovery=require("Modules.PlanningRecovery");local entries={}
	local function add(kind,record)
		if record and not recovery.isCurrent(build,kind,record.entry) then
			local details={"Saved locally: "..os.date("%Y-%m-%d %H:%M",record.at),"Restore opens a working draft. Review it, then Keep and Save.","An earlier-session draft is preserved until you restore or discard it."}
			if kind=="atlas" and record.entry.view and record.entry.view.stageResume then details[#details+1]="Choose Resume stages to recover unfinished stage inputs." end
			local projectId=kind=="uniqueQuality" and record.entry.plan.project.id or nil
			if projectId then
				local item,info=require("Modules.CraftingUniqueQuality").inspect(record.entry.plan.itemText)
				table.insert(details,1,(item.title or item.baseName).." | "..record.entry.plan.project.slot.." | "..info.quality.."% quality")
				details[#details+1]="Up to 64 undo steps are retained."
			end
			local label=kind=="uniqueQuality" and ("Unique crafting: "..record.entry.plan.project.title) or ({filters="Loot-filter draft",atlas="Atlas draft",crafting="Working craft"})[kind]
			entries[#entries+1]={id=projectId and kind..":"..projectId or kind,kind=kind,projectId=projectId,label=label,details=details,record=record}
		end
	end
	for _,kind in ipairs({"filters","atlas","crafting"}) do add(kind,recovery.load(build,kind)) end
	for _,record in ipairs(recovery.listUnique(build)) do add("uniqueQuality",record) end
	if recovery.lastError then entries[#entries+1]={id="error",label="Draft recovery needs attention",details={recovery.lastError,"Keep your working project and save the build."}} end
	require("Classes.PlanningBrowserControl").Open("Recover local drafts",entries,{action="Restore draft",closeOnChoose=false,choose=function(entry)
		assert(entry.record,"Choose a valid draft");local clean=recovery.clean(entry.kind,entry.record.entry)
		local page=entry.kind=="uniqueQuality" and "crafting" or entry.kind
		if entry.kind=="uniqueQuality" then
			local match
			for _,project in ipairs(build.savers.CraftingProjects.projects) do
				if project.id==clean.plan.project.id then
					assert(project.startingItem==clean.plan.project.startingItem and project.slot==clean.plan.project.slot,"A different project uses this ID; restore the matching project before recovering this preview")
					match=project;break
				end
			end
			local project=match or clean.plan.project;local item=require("Modules.CraftingUniqueQuality").inspect(project.startingItem)
			assert(build.itemsTab.slots[project.slot] and build.itemsTab:IsItemValidForSlot(item,project.slot),"Recovered project does not fit its equipment slot")
			clean.plan.project=copyTable(project)
		end
		main:ClosePopup();recovery.acknowledge(build,entry.kind,entry.projectId);build.planningWorkspace.cache[page]=nil;build.planningWorkspace.drafts[page]=clean;build.planningWorkspace:Show(page,clean.plan)
	end,secondary={label="Discard draft",run=function(entry) if entry and entry.record then recovery.clear(build,entry.kind,entry.projectId);main:ClosePopup();M.Recovery(build) end end}})
end
function M.Open(build)
	require("Classes.PlanningBrowserControl").Open("Planning tools",{
		{id="performance",label="Performance diagnostics",details={"See observed calculation and background-slice times. Refresh, copy or reset the session measurements."}},
		{id="bundle",label="Export / import complete bundle",details={"Carry the character, crafting guides, working checkpoints, Atlas stages and Journey plans together.","Imports open through native review as a new build."}},
		{id="recovery",label="Recover local drafts",details={"Resume an interrupted filter, Atlas or crafting draft.","Earlier-session drafts are preserved until reviewed."}},
	},{action="Open",closeOnChoose=false,choose=function(entry) main:ClosePopup();if entry.id=="performance" then M.Performance(build) elseif entry.id=="recovery" then M.Recovery(build) else M.Bundle(build) end end})
end
return M
