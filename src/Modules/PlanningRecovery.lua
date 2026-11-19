-- Two rotating local draft slots survive an interrupted write. Never applies a build.
local json=require("dkjson")
local data=require("Modules.PlanningData")
local M={cache={},limit=4*1024*1024,session=require("sha1")(os.time()..tostring({}))}
local kinds={filters=true,atlas=true,crafting=true,uniqueQuality=true}
local function buildIdentity(build) return (build.dbFileName or "untitled:"..(build.buildName or ""))..":"..GetScriptPath() end
local function path(build,kind,slot,projectId,hashed)
	assert(kinds[kind],"Unsupported draft type")
	if kind=="uniqueQuality" then
		assert(type(projectId)=="string" and (hashed and #projectId==40 and projectId:match("^[a-f0-9]+$") or not hashed and #projectId<=64 and projectId:match("^[%w%-_]+$")),"Invalid recovery project ID")
	end
	if launch.headless and not M.testDirectory then return end
	local directory=M.testDirectory or main.userPath.."PlanningDrafts"
	local id=require("sha1")(buildIdentity(build))
	local projectKey=projectId and (hashed and projectId or require("sha1")(projectId))
	return directory.."/"..id.."-"..kind.."-"..(projectKey and projectKey.."-" or "")..slot..".json",directory
end
-- The stage editor is temporarily closed while its route is shown on the tree.
-- Preserve its raw inputs, including values that are not yet valid for saving.
local function cleanAtlasStage(stage)
	if stage==nil then return nil end
	assert(type(stage)=="table" and (stage.page=="Progression" or stage.page=="Strategy"),"Invalid Atlas stage view")
	assert(({starter=true,intermediate=true,final=true})[stage.stage],"Invalid Atlas stage")
	local function text(value,limit)
		assert(type(value)=="string" and #value<=limit,"Invalid Atlas stage input");return value
	end
	assert(type(stage.fields)=="table","Invalid Atlas strategy inputs")
	local result={page=stage.page,stage=stage.stage,previous=text(stage.previous,64),fields={}}
	for _,key in ipairs({"maps","scarabs","requirements","avoid"}) do result.fields[key]=text(stage.fields[key],4000) end
	for _,key in ipairs({"amount","currency","source"}) do result[key]=text(stage[key],240) end
	return result
end
local function atlasStageIsCurrent(saved,stage)
	local progression=saved.progression or {};local strategy=saved.strategy or {}
	if stage.stage~=(progression.stage or "starter") or stage.previous~=(progression.previousId or "") then return false end
	for _,key in ipairs({"maps","scarabs","requirements","avoid"}) do if stage.fields[key]~=(strategy[key] or "") then return false end end
	local cost=strategy.setupCost
	if not cost then return stage.amount=="" and stage.currency=="chaos" and stage.source=="" end
	return tonumber(stage.amount)==cost.amount and stage.currency==cost.currency and stage.source==(cost.source or "")
end
function M.clean(kind,entry)
	local value=assert(entry.plan,"Missing draft")
	if kind=="filters" then return {plan={data=require("Modules.LootFilters").validate(value.data),selected=value.selected,page=value.page,dirty=true}}
	elseif kind=="atlas" then
		local view=entry.view;local savedView
		if view then
			savedView={};for _,key in ipairs({"title","notes","budgetText","search"}) do assert(type(view[key])=="string" and #view[key]<=8000,"Invalid Atlas draft text");savedView[key]=view[key] end
			for _,key in ipairs({"centerX","centerY","scale","focus","inspectorWidth"}) do local v=view[key];assert(v==nil or type(v)=="number" and v==v and math.abs(v)<1e7,"Invalid Atlas view");savedView[key]=v end
			assert(savedView.scale and savedView.scale>0,"Invalid Atlas scale")
			savedView.page=view.page=="Notes & sharing" and view.page or "Tree";savedView.mechanic=view.mechanic;savedView.avoided=copyTable(value.avoided or {});savedView.undo={};savedView.redo={}
			savedView.stageResume=cleanAtlasStage(view.stageResume)
		end
		return {plan=require("Modules.AtlasPlanner").validate(value),view=savedView}
	elseif kind=="uniqueQuality" then
		assert(value.kind=="uniqueQuality","Invalid unique quality preview")
		local project=require("Modules.CraftingProjects").validate(value.project)
		local unique=require("Modules.CraftingUniqueQuality")
		local original=unique.inspect(project.startingItem)
		local function item(raw)
			local checked=unique.inspect(raw)
			assert(checked.title==original.title and checked.baseName==original.baseName and (not not checked.corrupted)==(not not original.corrupted),"Unique preview does not match its starting item")
			return raw
		end
		assert(type(value.history)=="table","Invalid unique quality history")
		assert(value.actions==nil or type(value.actions)=="table" and #value.actions==#value.history,"Invalid unique crafting actions")
		assert(value.redo==nil or type(value.redo)=="table","Invalid unique crafting redo history")
		assert(value.savedTrace==nil or type(value.savedTrace)=="string" and #value.savedTrace==40 and value.savedTrace:match("^[0-9a-f]+$"),"Invalid unique crafting trace")
		assert(value.savedGuideHash==nil and value.savedGuideLength==nil or value.savedTrace and type(value.savedGuideHash)=="string" and #value.savedGuideHash==40 and value.savedGuideHash:match("^[0-9a-f]+$") and type(value.savedGuideLength)=="number" and value.savedGuideLength==math.floor(value.savedGuideLength) and value.savedGuideLength>=0 and value.savedGuideLength<=40,"Invalid saved guide marker")
		local allowed={quality=true,beast_max_links=true,omen_connections=true,socket_white_bench=true,load=true,unknown=true}
		local history,actions={},{}
		for i=math.max(1,#value.history-63),#value.history do
			history[#history+1]=item(value.history[i]);local action=value.actions and value.actions[i] or "unknown"
			assert(allowed[action],"Invalid unique crafting action");actions[#actions+1]=action
		end
		local redo={};for i=math.max(1,#(value.redo or {})-63),#(value.redo or {}) do
			local next=value.redo[i];assert(type(next)=="table" and allowed[next.action],"Invalid unique crafting redo action")
			redo[#redo+1]={itemText=item(next.itemText),action=next.action}
		end
		return {plan={kind="uniqueQuality",project=project,itemText=item(value.itemText),history=history,actions=actions,redo=redo,savedTrace=value.savedTrace,savedGuideHash=value.savedGuideHash,savedGuideLength=value.savedGuideLength}}
	elseif kind=="crafting" then
		assert(value.kind=="workbench","Only working crafts need draft recovery")
		local project=require("Modules.CraftingProjects").validate(value.project);local run=copyTable(value);run.schemaVersion=1
		local result=require("Modules.CraftingCheckpoint").validate(project.startingItem,run);result.project=project;result.kind="workbench"
		return {plan=result}
	end
	error("Unsupported draft type")
end
function M.isCurrent(build,kind,entry)
	local ok,result=pcall(function()
		if kind=="filters" then return data.hash(entry.plan.data)==data.hash(build.savers.LootFilters.data)
		elseif kind=="atlas" then
			local plan=copyTable(entry.plan);local view=entry.view
			if view then plan.title=view.title;plan.notes=view.notes;plan.budget=tonumber(view.budgetText) end
			plan=require("Modules.AtlasPlanner").validate(plan)
			for _,saved in ipairs(build.savers.AtlasPlans.plans) do if saved.id==plan.id then return data.hash(saved)==data.hash(plan) and (not view or not view.stageResume or atlasStageIsCurrent(saved,view.stageResume)) end end
		elseif kind=="uniqueQuality" then
			local working=entry.plan
			for _,project in ipairs(build.savers.CraftingProjects.projects) do
				if project.id==working.project.id and project.startingItem==working.project.startingItem and project.slot==working.project.slot then
					return working.itemText==project.startingItem or working.itemText==project.targetItem
				end
			end
		elseif kind=="crafting" then
			local working=entry.plan;local run=copyTable(working);run.project=nil;run.kind=nil
			for _,project in ipairs(build.savers.CraftingProjects.projects) do if project.id==working.project.id and project.startingItem==working.project.startingItem and project.run then
				return data.hash(project.run)==data.hash(run)
			end end
		end
		return false
	end)
	return ok and result==true
end
local function readRecord(build,kind,slot,projectId,hashed)
	local filePath=path(build,kind,slot,projectId,hashed);if not filePath then return end
	local file=io.open(filePath,"rb");if not file then return end
	local raw=file:read(M.limit+1);file:close();if #raw>M.limit then return end
	local ok,value=pcall(function()
		local record=assert(json.decode(raw));assert(record.schemaVersion==1 and record.kind==kind and type(record.generation)=="number" and record.generation==math.floor(record.generation) and record.generation>=1 and record.generation<1e12,"Invalid recovery record")
		assert(type(record.at)=="number" and record.at>=0 and record.at<4102444800,"Invalid recovery date")
		assert(record.digest==data.hash(record.entry),"Incomplete recovery record");record.entry=M.clean(kind,record.entry);if kind=="uniqueQuality" then assert((hashed and require("sha1")(record.entry.plan.project.id)==projectId) or (not hashed and record.entry.plan.project.id==projectId),"Recovery project ID mismatch") end;record.path=filePath;return record
	end)
	if ok then return value end
end
function M.load(build,kind,projectId)
	local best
	for slot=1,2 do local value=readRecord(build,kind,slot,projectId);if value and (not best or value.generation>best.generation) then best=value end end
	return best
end
-- Each unique project has its own rotating pair; browsing one item never
-- replaces the interrupted preview of another item in the same build.
function M.listUnique(build,visit,checkpoint)
	local sample,directory=path(build,"uniqueQuality",1,"_");if not sample then return {} end
	local suffix=require("sha1")("_").."%-1%.json$"
	local prefix=assert(sample:match("([^/\\]+)"..suffix));local escaped=prefix:gsub("(%W)","%%%1")
	local ids={};local scanned=0
	local function add(name)
		local id=name:match("^"..escaped.."([a-f0-9]+)%-[12]%.json$");if id and #id==40 then ids[id]=true end
		scanned=scanned+1;if checkpoint and scanned%32==0 then checkpoint() end
	end
	if launch.headless and M.testDirectory then
		local ok,iterator,state=pcall(require("lfs").dir,directory)
		if ok then for name in iterator,state do add(name) end end
	else
		local handle=NewFileSearch(directory.."/"..prefix.."*.json")
		while handle do add(handle:GetFileName());if not handle:NextFile() then break end end
	end
	local result={}
	for id in pairs(ids) do
		local first=readRecord(build,"uniqueQuality",1,id,true);local second=readRecord(build,"uniqueQuality",2,id,true)
		local record=first and second and (first.generation>second.generation and first or second) or first or second
		if record then result[#result+1]=record;if visit then visit(record) end end
	end
	table.sort(result,function(a,b) return a.entry.plan.project.id<b.entry.plan.project.id end);return result
end
function M.forCraftingProject(build,id)
	local best
	for slot=1,2 do local record=readRecord(build,"crafting",slot);if record and record.entry.plan.project.id==id and (not best or record.generation>best.generation) then best=record end end
	if best then return {draft=best.entry.plan,pending=not M.isCurrent(build,"crafting",best.entry)} end
end
function M.forgetCraftingProject(build,id)
	local removed=M.forCraftingProject(build,id)
	for slot=1,2 do
		local record=readRecord(build,"crafting",slot)
		if record and record.entry.plan.project.id==id then local ok,why,code=os.remove(record.path);assert(ok or code==2,why) end
	end
	local _,directory=path(build,"crafting",1);if not directory then return removed end
	local cache=M.cache[directory..":"..(build.dbFileName or build.buildName or "")..":crafting"]
	if cache then cache.digest=nil;cache.checked=nil;if not M.load(build,"crafting") then cache.pending=false end end
	return removed
end
-- Discard only copies written by this session; older recovery records may
-- contain work the user has not reviewed yet, even for the same plan ID.
function M.forgetAtlasSessionDraft(build,id)
	for slot=1,2 do
		local record=readRecord(build,"atlas",slot)
		if record and record.session==M.session and record.entry.plan.id==id then local ok,why,code=os.remove(record.path);assert(ok or code==2,why) end
	end
	local _,directory=path(build,"atlas",1);if not directory then return end
	local cache=M.cache[directory..":"..(build.dbFileName or build.buildName or "")..":atlas"]
	if cache then
		cache.digest=nil;cache.checked=nil;local remaining=M.load(build,"atlas")
		if remaining and remaining.session~=M.session and not M.isCurrent(build,"atlas",remaining.entry) then cache.pending=true;cache.acknowledged=false
		elseif not remaining then cache.pending=false end
	end
end
local function noticeKey(build,kind,projectId)
	local identity=require("sha1")(buildIdentity(build))
	return "scan:"..tostring(build)..":"..identity..":"..kind..":"..(projectId or "")
end
function M.save(build,kind,entry,force)
	local projectId=kind=="uniqueQuality" and entry and entry.plan and entry.plan.project and entry.plan.project.id or nil
	if kind=="uniqueQuality" and (type(projectId)~="string" or #projectId>64 or not projectId:match("^[%w%-_]+$")) then return false,"Invalid recovery project ID" end
	local _,directory=path(build,kind,1,projectId);if not directory then return end
	local key=directory..":"..(build.dbFileName or build.buildName or "")..":"..kind..(projectId and ":"..projectId or "");local cache=M.cache[key] or {};cache.build=build;cache.identity=buildIdentity(build);M.cache[key]=cache
	local now=GetTime();if not force and cache.checked and now-cache.checked<2000 then return end;cache.checked=now
	local ok,message=pcall(function()
		local clean=M.clean(kind,entry);local digest=data.hash(clean);if digest==cache.digest then return end
		local old=M.load(build,kind,projectId)
		if old and old.session~=M.session and not cache.acknowledged and not M.isCurrent(build,kind,old.entry) then cache.pending=true;return end
		cache.pending=false
		local notice=M.cache[noticeKey(build,kind,projectId)];if notice then notice.pending=false end
		local generation=(old and old.generation or 0)+1
		local record={schemaVersion=1,kind=kind,generation=generation,at=os.time(),digest=digest,entry=clean,session=M.session}
		local raw=json.encode(record);assert(#raw<=M.limit,"Recovery draft exceeds 4 MiB; keep the working project in the build")
		MakeDir(directory);local target=path(build,kind,generation%2+1,projectId);local file=assert(io.open(target,"wb"),"Could not create recovery draft")
		local written=file:write(raw);local closed=file:close();assert(written and closed,"Could not finish recovery draft");cache.digest=digest
	end)
	M.lastError=not ok and tostring(message) or nil;return ok,message
end
-- Scan a little at a time so reopening a build with many projects stays responsive.
function M.startScan(build)
	if launch.headless and not M.testDirectory then return end
	return coroutine.create(function()
		local function visit(kind,record,projectId)
			if record and record.session~=M.session and not M.isCurrent(build,kind,record.entry) then
				local key=noticeKey(build,kind,projectId);local notice=M.cache[key] or {};notice.build=build;notice.identity=buildIdentity(build);M.cache[key]=notice
				if not notice.acknowledged then notice.pending=true end
			end
		end
		for _,kind in ipairs({"filters","atlas","crafting"}) do visit(kind,M.load(build,kind));coroutine.yield() end
		M.listUnique(build,function(record) visit("uniqueQuality",record,record.entry.plan.project.id);coroutine.yield() end,coroutine.yield)
	end)
end
function M.acknowledge(build,kind,projectId)
	local _,directory=path(build,kind,1,projectId);if not directory then return end
	local key=directory..":"..(build.dbFileName or build.buildName or "")..":"..kind..(projectId and ":"..projectId or "")
	M.cache[key]=M.cache[key] or {};M.cache[key].build=build;M.cache[key].identity=buildIdentity(build);M.cache[key].acknowledged=true;M.cache[key].pending=false
	local notice=noticeKey(build,kind,projectId);M.cache[notice]=M.cache[notice] or {};M.cache[notice].build=build;M.cache[notice].identity=buildIdentity(build);M.cache[notice].acknowledged=true;M.cache[notice].pending=false
end
function M.clear(build,kind,projectId)
	for slot=1,2 do local target=path(build,kind,slot,projectId);if target then local ok,why,code=os.remove(target);assert(ok or code==2,why) end end
	M.acknowledge(build,kind,projectId)
	for _,cache in pairs(M.cache) do if cache.build==build then cache.digest=nil;cache.checked=nil end end
end
function M.hasPending(build)
	local identity=buildIdentity(build)
	for _,cache in pairs(M.cache) do if cache.build==build and cache.identity==identity and cache.pending then return true end end;return false
end
return M
