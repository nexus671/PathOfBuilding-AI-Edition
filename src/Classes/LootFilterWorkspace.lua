-- cspell:ignore RGBWAD
-- A visual catalogue and loot scene, backed by the same native filter compiler.
local ui=require("Modules.PlanningUI")
local filters=require("Modules.LootFilters")
local parser=require("Modules.LootFilterParser")
local library=require("Modules.LootFilterLibrary")
local visual=require("Modules.LootFilterVisuals")
local M={}
local function trackingEnabled(profile)
	if profile.trackBuildPickups~=nil then return profile.trackBuildPickups end
	for _,rule in ipairs(profile.rules) do if rule.origin then return true end end
	return false
end
-- The generation job owns its immutable rules; discard this cache whenever a
-- new job or scene level is selected. Return a fresh list because the caller
-- inserts the current test item into it.
function M.targetScene(state,profile,build,settings)
	if not state or not state.rules then return {},{} end
	local cached=state.sceneCache
	if not cached or cached.rules~=state.rules or cached.area~=settings.areaLevel or cached.level~=settings.itemLevel then
		local samples=library.scene(profile,build,"Build targets",0,settings.areaLevel,settings.itemLevel,state.rules)
		local keys={};local encode=require("Modules.PlanningData").encode
		for _,sample in ipairs(samples) do keys[encode(sample)]=true end
		cached={rules=state.rules,area=settings.areaLevel,level=settings.itemLevel,samples=samples,keys=keys};state.sceneCache=cached
	end
	local samples={};for i,sample in ipairs(cached.samples) do samples[i]=sample end
	return samples,cached.keys
end
function M.dropOutcome(result)
	local action=result and result.action
	return (action=="Show" or action=="Hide" or action=="Minimal") and action or "Unknown"
end
function M.vendorLabel(sample)
	local linked,sockets,quality=tonumber(sample.LinkedSockets),tonumber(sample.Sockets),tonumber(sample.Quality)
	if linked and linked>=6 then return "6 linked" end
	if sockets and sockets>=6 then return "6 sockets" end
	if type(sample.SocketGroup)=="string" then for group in sample.SocketGroup:gmatch("%S+") do
		if group:find("R",1,true) and group:find("G",1,true) and group:find("B",1,true) then return "3 linked colours" end
	end end
	if (sample.Class=="Skill Gems" or sample.Class=="Support Gems") and quality and quality>0 then return "Quality gem" end
	if quality and quality>0 then
		if sample.Class=="Tinctures" then return "Quality tincture" end
		if sample.Class=="Life Flasks" or sample.Class=="Mana Flasks" or sample.Class=="Hybrid Flasks" or sample.Class=="Utility Flasks" or sample.Class=="Critical Utility Flasks" then return "Quality flask" end
	end
	if sample.Rarity=="Rare" and sample.Identified==false then return "Rare piece" end
	if quality and quality>0 then return require("Modules.LootFilterCampaign").qualityCategory(sample.Class) end
end
local function itemTier(sample)
	if sample.Identified==false and (sample.Rarity=="Magic" or sample.Rarity=="Rare") then return sample.UnidentifiedItemTier end
end
local function button(c,key,x,y,w,label,run) c[key]=new("ButtonControl"):ButtonControl(ui.anchor,{x,y,w,28},label,run);return c[key] end
local function identifier() return "filter-"..require("sha1")(os.time()..tostring({})):sub(1,20) end
function M.Open(build,source,layout,controller)
	local saver=build.savers.LootFilters;local c={};local custom={};local backgrounds={};local w,h=layout.width,layout.height
	local state=source or {};local data=state.data or copyTable(saver.data);local profile=filters.find(data,state.selected) or data.profiles[1]
	local baseHash=state.baseHash;if baseHash==nil then baseHash=require("Modules.PlanningData").hash(saver.data) end
	local page=state.page or "Overview";local category=state.category or "All items";local scope=state.scope or (profile and #profile.rules>0 and "My rules" or "Base filter");local query=state.query or "";local selected=state.rule
	local item=state.sample or library.sample();local dirty=state.dirty or false;local sceneKind=state.sceneKind or "Mixed drops";local seed=state.seed or 0;local showHidden=state.showHidden~=false
	local settings=state.sceneSettings or {areaLevel=83,itemLevel=86,background="Stone"};local samples=state.sampleHistory or {}
	local sampleSetId=state.sampleSetId
	local scenePage=state.scenePage or 1
	local function rememberSample(next)
		item=copyTable(next);local encode=require("Modules.PlanningData").encode;local raw=encode(item);local size=0
		for i=#samples,1,-1 do if encode(samples[i])==raw then table.remove(samples,i) end end;samples[#samples+1]=copyTable(item)
		for _,sample in ipairs(samples) do size=size+#encode(sample) end;while size>1024*1024 and #samples>1 do size=size-#encode(table.remove(samples,1)) end
	end
	local catalog,entries,parsed,raw,report,result={},{};local selectedEntry;local scene={}
	local function sampleDetails(sample,evaluated,selected)
		local deciding=evaluated and (evaluated.ruleTitle or (evaluated.line and "Filter line "..evaluated.line or evaluated.status=="matched" and "No matching block: default Show" or "Resolve missing properties or filter errors.")) or "Select a drop to inspect the rule."
		local lines={(selected and "Selected: " or "")..visual.sampleName(sample),"iLvl "..tostring(sample.ItemLevel or "?").." / area "..tostring(sample.AreaLevel or "?"),evaluated and evaluated.action or "Choose a drop"}
		local firstError=evaluated and evaluated.status=="invalid" and evaluated.reasons and evaluated.reasons[1]
		if firstError then table.insert(lines,1,"Filter error: "..firstError) end
		local copied=not sample.HasExplicitMod and sample.KnownExplicitMods
		if copied and copied[1] then lines[#lines+1]="Copied: "..copied[1] end
		local tier=itemTier(sample);if tier~=nil then lines[#lines+1]="Unidentified item tier: "..tier
		elseif sample.Identified==false and (sample.Rarity=="Magic" or sample.Rarity=="Rare") then lines[#lines+1]="Unidentified item tier: unknown" end
		if type(sample.SocketGroup)=="string" and sample.SocketGroup:find("[RGBWAD]") then lines[#lines+1]="Sockets: "..sample.SocketGroup end
		if type(sample.Quality)=="number" and sample.Quality>0 then lines[#lines+1]="Quality: "..sample.Quality.."%" end
		if sample.Rarity=="Rare" and sample.Identified==false then lines[#lines+1]="Unidentified rare" end
		lines[#lines+1]=deciding;for index,reason in ipairs(evaluated and evaluated.reasons or {}) do if not firstError or index>1 then lines[#lines+1]=reason end end
		if evaluated and evaluated.status=="matched" then
			local sound=require("Modules.LootFilterAudio").dropSound(evaluated.styles or {})
			if sound then lines[#lines+1]=sound end
		end
		if evaluated and evaluated.missingProperties and evaluated.missingProperties[1] then lines[#lines+1]="Configure opens "..evaluated.missingProperties[1].."." end
		if copied then
			for index=2,#copied do lines[#lines+1]="Copied: "..copied[index] end
			lines[#lines+1]="Copied names may be incomplete."
		end
		return lines
	end
	local history=require("Modules.PlanningHistory").new(data,state.history);local tierView;local tierState=state.tierState
	local transient=layout.transient or {};local dependencies;local dependencyTime;local dependencyJob;local dependencyError;local generationJob=transient.filterGeneration
	if not profile then transient.filterSceneTargets=nil end
	local function advanceDependencies()
		if not dependencyJob then return end
		local done,result,err=require("Modules.LootFilterDependencies").poll(dependencyJob)
		if done then
			dependencyJob=nil
			if err=="changed" then dependencies=nil;dependencyTime=nil
			elseif err then dependencies=nil;dependencyError=ui.errorText(err);dependencyTime=GetTime()
			else dependencies=result;dependencyError=nil;dependencyTime=GetTime() end
		end
	end
	local function refreshDependencies()
		if dependencyJob or generationJob then return end
		local targets=transient.filterSceneTargets
		if page=="Simulate" and sceneKind=="Build targets" and targets and not targets.rules and not targets.error then return end
		if profile then dependencyJob=require("Modules.LootFilterDependencies").begin(build,profile);advanceDependencies() else dependencies=nil;dependencyTime=GetTime() end
	end
	local function draft(field) dirty=true;history:record(data,field);ui.draft(build,"filters") end
	local function snapshot() return {data=data,baseHash=baseHash,selected=profile and profile.id,page=page,category=category,scope=scope,query=query,rule=selected,sample=item,dirty=dirty,seed=seed,sceneKind=sceneKind,showHidden=showHidden,history=history:snapshot(),tierState=tierView and tierView.snapshot() or tierState,sceneSettings=settings,sampleHistory=samples,sampleSetId=sampleSetId,scenePage=scenePage} end
	local function reopen() layout.navigate("filters",snapshot()) end
	local function openSource(origin,openGuide)
		local ok,reason=require("Modules.LootFilterDependencies").open(build,layout,origin,openGuide)
		if not ok then ui.errorPopup("Linked source",reason) end
	end
	local function acknowledgeGuide(entry)
		local id=entry.origin and entry.origin:match("^craft:(.+)$");local project
		for _,candidate in ipairs(build.savers.CraftingProjects.projects) do if candidate.id==id then project=candidate;break end end
		if not project or filters.manualGuideSignature(build,project)~=entry.manualGuideSignature then ui.errorPopup("Review build pickups","The guide or budget changed. Refresh build pickups and review it again.");return end
		local reviews={};for _,review in ipairs(profile.manualGuideReviews or {}) do if review.projectId~=id then reviews[#reviews+1]=review end end
		reviews[#reviews+1]={projectId=id,signature=entry.manualGuideSignature};profile.manualGuideReviews=reviews
		dependencies=nil;dependencyJob=nil;dependencyTime=nil;draft();reopen();return true
	end
	local function showPickupWarnings(entries)
		if #entries==0 then return end
		require("Classes.PlanningBrowserControl").Open("Review build pickups",entries,{action="Open source",canChoose=function(entry) return type(entry.origin)=="string" and entry.origin~="" end,choose=function(entry) main:ClosePopup();openSource(entry.origin,entry.openGuide) end,closeOnChoose=false,
			secondary={label="Mark guide reviewed",canRun=function(entry) return entry.manualGuideSignature~=nil end,run=function(entry)
				main:ClosePopup();if acknowledgeGuide(entry) then local remaining={};for _,other in ipairs(entries) do if other~=entry then remaining[#remaining+1]=other end end;showPickupWarnings(remaining) end
			end}})
	end
	local function targetPreview()
		local state=transient.filterSceneTargets;local dependency=require("Modules.LootFilterDependencies")
		if state and (state.job.profile~=profile or not dependency.current(state.job)) then state=nil;transient.filterSceneTargets=nil end
		if not state then state={job=dependency.beginGenerate(build,profile)};transient.filterSceneTargets=state end
		return state
	end
	local function advanceTargetPreview()
		local state=targetPreview();if state.rules or state.error then return end
		local done,result,err=require("Modules.LootFilterDependencies").poll(state.job)
		if not done then return end
		if err=="changed" then transient.filterSceneTargets=nil
		elseif err then state.error=ui.errorText(err)
		else state.rules=result.rules;state.warnings=result.warnings end
		reopen()
	end
	local function advanceGeneration()
		if not generationJob then return end
		local done,result,err
		if profile~=generationJob.profile then done=true;err="changed"
		else done,result,err=require("Modules.LootFilterDependencies").poll(generationJob) end
		if not done then return end
		local original=generationJob.profile;generationJob=nil;transient.filterGeneration=nil
		if err or profile~=original then
			dependencyTime=nil
			ui.errorPopup("Build pickups",(err=="changed" or profile~=original) and "The build or filter changed. Please try again." or err)
			return
		end
		profile.rules=result.rules;profile.trackBuildPickups=true;draft();reopen()
		if #result.warnings>0 then
			local entries={};for _,warning in ipairs(result.warnings) do entries[#entries+1]={id=warning.origin,origin=warning.origin,openGuide=warning.openGuide,manualGuideSignature=warning.manualGuideSignature,label=warning.title,details={warning.message}} end
			showPickupWarnings(entries)
		end
	end
	local function generatePickups()
		if generationJob then return end
		dependencyJob=nil;generationJob=require("Modules.LootFilterDependencies").beginGenerate(build,profile);transient.filterGeneration=generationJob;advanceGeneration()
	end
	local function replaceProfile(next)
		for i,value in ipairs(data.profiles) do if value.id==next.id then data.profiles[i]=next end end;profile=next;draft();reopen()
	end
	local function openAudit(focusErrors)
		controller.Audit(profile,report,function(next) replaceProfile(next) end,focusErrors)
	end
	local function collection(kind)
		local activeScene=page=="Simulate" and #scene>0
		local examples=activeScene and scene or library.scene(profile,build,"Mixed drops",seed,settings.areaLevel,settings.itemLevel)
		local sources={{title="Current item",samples={item}},{title="Tested item history",samples=samples},{title=activeScene and "Current scene" or "Mixed examples",samples=examples}}
		require("Classes.LootFilterCollectionControl").Open(profile,kind,sources,function(next,chosen)
			if chosen then page="Simulate";sceneKind="Saved examples";sampleSetId=chosen.id;scenePage=1;item=copyTable(chosen.samples[1]) end;replaceProfile(next)
		end)
	end
	local invalidFilterReason,invalidFilterResult
	local function compile()
		parsed=nil;invalidFilterReason=nil;invalidFilterResult=nil
		if not profile then return end
		local key=require("Modules.PlanningData").encode(profile);local cached=transient.filterCompiled
		if not cached or cached.key~=key then
			local ok,value,details,compiled=pcall(filters.compile,profile,true)
			if not ok then raw=nil;invalidFilterReason=value;report={error=value};result={action="Unknown",status="invalid",styles={},reasons={value}};invalidFilterResult=result;return end
			cached={key=key,raw=value,report=details,parsed=compiled};transient.filterCompiled=cached
		end
		raw,report,parsed=cached.raw,cached.report,cached.parsed;result=parser.simulate(parsed,item)
		for _,d in ipairs(report.diagnostics) do if d.error then raw=nil;result=parser.invalidResult(d);invalidFilterResult=result;invalidFilterReason=result.reasons[1];break end end
	end
	local evaluationScope
	local function evaluateDrop(drop)
		if invalidFilterResult then return invalidFilterResult end
		if not parsed then return {action="Unknown",status="unknown",styles={},reasons={"Filter is unavailable."}} end
		local encode=require("Modules.PlanningData").encodeExact
		evaluationScope=evaluationScope or sceneKind.."\0"..(sampleSetId or "").."\0"..encode(settings)
		local cache=transient.filterEvaluations
		if not cache or cache.parsed~=parsed or cache.scope~=evaluationScope then cache={parsed=parsed,scope=evaluationScope,values={},count=0};transient.filterEvaluations=cache end
		-- Use round-trip precision: distinct numeric thresholds must never share
		-- a cached outcome. Bound both key length and retained entries.
		local key=encode(drop);local cached=cache.values[key]
		if cached then return cached end
		local evaluated=parser.simulate(parsed,drop)
		if cache.count<1024 and #key<=8192 and #(evaluated.matches or {})<=64 then
			cache.values[key]=evaluated;cache.count=cache.count+1
		end
		return evaluated
	end
	local function selectedRule() return selectedEntry and selectedEntry.rule end
	local function keepRule(rule)
		local found=false;for i,r in ipairs(profile.rules) do if r.id==rule.id then profile.rules[i]=rule;found=true end end
		if not found then profile.rules[#profile.rules+1]=rule end
		selected=rule.id;scope="My rules";category="All items";query="";draft();reopen()
	end
	local function editRule(rule,save) controller.EditRule(rule,save,profile.mode) end
	local function edit() if selectedRule() then editRule(selectedRule(),keepRule) end end
	local function inspectMatches()
		local outline=require("Modules.LootFilterStructure").outline(profile,raw,report,parsed)
		local wanted={};for _,line in ipairs(result.matches or {}) do wanted[line]=true end;if result.line then wanted[result.line]=true end
		local entries={};for i,block in ipairs(parsed.rules) do if wanted[block.line] then
			local rule=outline.entries[i].rule
			entries[#entries+1]={id=block.line,label=(block.title or rule.title).." | "..block.action,details={"Compiled line "..block.line,"Editing a preset or module match creates a personal override.",table.concat(block.rawLines,"\n")},rule=rule}
		end end
		require("Classes.PlanningBrowserControl").Open("Matched filter rules",entries,{action="Edit matched rule",choose=function(entry) main:ClosePopup();editRule(entry.rule,keepRule) end,closeOnChoose=false})
	end
	local function updateDetail()
		if c.detail then local lines={}
			if selectedEntry then
				local entry=selectedEntry
				lines={entry.rule.title,entry.category.." / "..entry.tier,(entry.rule.enabled==false and "Disabled. The base preset still applies." or entry.base and "Base preset. Editing creates a personal override." or entry.rule.origin and "Linked to "..require("Modules.LootFilterDependencies").sourceLabel(build,entry.rule.origin) or "Personal rule"),result and result.action=="Unknown" and (result.reasons[1] or "Resolve the sample properties to preview this drop.") or "Preview uses this profile's complete filter.","",#entry.block.conditions>0 and "Matching conditions (all required):" or "Matches any item."}
				for _,condition in ipairs(library.conditionSummaries(entry.block)) do lines[#lines+1]=condition end
			else lines={"Choose a rule or a drop to inspect it.","Personal rules take priority over the base preset."} end
			c.detail.list=ui.rows(lines,c.detail.width-28,14)
		end
	end
	local function updateSelection(entry)
		if c.detail then c.detail.controls.scrollBar:SetOffset(0) end
		selectedEntry=entry;selected=entry and entry.rule.id;item=entry and copyTable(entry.sample) or item;if parsed then result=evaluateDrop(item) end
		updateDetail()
	end
	local function card(key,x,y,width,title,value,caption,icon)
		local control=new("Control"):Control(ui.anchor,{x,y,width,74});c[key]=control
		function control:Draw() local px,py=self:GetPos();visual.box(px,py,width,74,"^x293B4B");visual.box(px+1,py+1,width-2,72,"^x152331");visual.text(px+14,py+10,12,title,"^x98ADC2",width-70);visual.text(px+14,py+28,24,type(value)=="function" and value() or value,"^xEED49C",width-70);visual.text(px+14,py+56,12,caption,"^xAEBECA",width-28);if icon then SetDrawColor(1,1,1);DrawImage(visual.image(icon),px+width-54,py+12,38,38) end end
	end
	local function sceneControl(key,x,y,width,height,drops,selectable,caption)
		local canvas=new("Control"):Control(ui.anchor,{x,y,width,height});c[key]=canvas;backgrounds[key]=true
		local columns=width>700 and 4 or width>460 and 3 or 2;local reserve=selectable and 98 or 46;local rows=math.max(2,math.floor((height-reserve)/70));local capacity=columns*rows;local cells={};local visible=0;local eligible={}
		if selectable and (sceneKind=="Fated gear" or sceneKind=="Foulborn gear") then columns=math.min(columns,2);capacity=columns*rows end
		if selectable and (sceneKind=="Essences" or sceneKind=="Preset highlights" or sceneKind=="Breach" or sceneKind=="Beyond" or sceneKind=="Incursion" or sceneKind=="Legion" or sceneKind=="Delirium" or sceneKind=="Harvest" or sceneKind=="Abyss" or sceneKind=="Ultimatum" or sceneKind=="Ritual" or sceneKind=="Sanctum" or sceneKind=="Pinnacle bosses") then columns=math.min(columns,3);capacity=columns*rows end
		local function evaluate(drop) return evaluateDrop(drop) end
		for _,drop in ipairs(drops) do local evaluated=not showHidden and evaluate(drop) or nil;if showHidden or evaluated.action~="Hide" then eligible[#eligible+1]={item=drop,result=evaluated} end end
		local pages=math.max(1,math.ceil(#eligible/capacity));if selectable then scenePage=math.max(1,math.min(scenePage,pages)) end
		local first=selectable and (scenePage-1)*capacity+1 or 1;local encode=require("Modules.PlanningData").encode
		for index=first,math.min(#eligible,first+capacity-1) do local entry=eligible[index];local drop=entry.item;local evaluated=entry.result or evaluate(drop)
			visible=visible+1;local cellW=(width-24)/columns;local cellH=(height-reserve)/rows;local cx=x+12+((visible-1)%columns)*cellW;local cy=y+12+math.floor((visible-1)/columns)*cellH
			cells[#cells+1]={x=cx,y=cy,w=cellW,h=cellH,item=drop,result=evaluated,key=encode(drop)}
			if selectable then local control=new("ButtonControl"):ButtonControl(ui.anchor,{cx,cy,cellW,cellH},"",function() rememberSample(drop);compile();if c.selection then c.selection.list=ui.rows(sampleDetails(drop,result,true),c.selection.width-28,14) end end)
				c["drop"..visible]=control;custom["drop"..visible]=true;control.planningFocusable=true;control.tooltipText=table.concat(sampleDetails(drop,evaluated),"\n")
				function control:Draw(viewport) if self:IsMouseOver() then local px,py=self:GetPos();SetDrawLayer(nil,100);self:DrawTooltip(px,py,cellW,cellH,viewport or main.viewPort);SetDrawLayer(nil,0) end end
			end
		end
		if selectable then
			button(c,"scenePrevious",x+12,y+height-74,80,"Previous",function() scenePage=scenePage-1;reopen() end);c.scenePrevious.height=26;c.scenePrevious.enabled=scenePage>1
			button(c,"sceneNext",x+100,y+height-74,80,"Next",function() scenePage=scenePage+1;reopen() end);c.sceneNext.height=26;c.sceneNext.enabled=scenePage<pages
			ui.label(c,"scenePage",x+196,y+height-66,"Page "..scenePage.." / "..pages,13)
		end
		function canvas:Draw() local px,py=self:GetPos();visual.floor(px,py,width,height,settings.background)
			local selectedKey=encode(item);for _,cell in ipairs(cells) do
				local cx,cy=px+cell.x-x,py+cell.y-y;visual.chip(cx,cy,cell.w,cell.h,cell.item,cell.result,selectedKey==cell.key)
				if sceneKind=="Tiered gear" and cell.item.Identified==false and cell.item.UnidentifiedItemTier~=nil then visual.text(cx+5,cy+2,12,cell.item.UnidentifiedItemTier==0 and "No tier" or "Tier "..cell.item.UnidentifiedItemTier,"^xEED49C",cell.w-10) end
				if sceneKind=="Fated gear" or sceneKind=="Foulborn gear" then local property=sceneKind=="Fated gear" and "Fated" or "Foulborn";visual.text(cx+5,cy+2,12,cell.item[property] and property or "Other", "^xEED49C",cell.w-10) end
				if sceneKind=="Map tiers" then visual.text(cx+5,cy+2,12,"Tier "..cell.item.MapTier,"^xEED49C",cell.w-10) end
				if sceneKind=="Vendor recipes" then local note=M.vendorLabel(cell.item);if note then visual.text(cx+5,cy+2,12,note,"^xEED49C",cell.w-10) end end
			end
			if #cells==0 then visual.text(px+14,py+height/2,14,"No visible examples. Show hidden drops or choose another scene.","^xAABBBE",width-28) end
			visual.text(px+14,py+height-26,12,(caption or "EXAMPLE DROPS").."  /  "..visible.." displayed  /  click an item to inspect",caption=="FILTER INVALID - SEE DETAILS" and "^xFFC477" or "^xAABBBE",page=="Simulate" and width-224 or width-28)
		end
	end
	compile()
	ui.label(c,"heading",16,14,"Loot filter",26)
	ui.label(c,"subtitle",16,48,"Customise pickups, preview loot, export to PoE.",14)
	local profiles={};for _,p in ipairs(data.profiles) do profiles[#profiles+1]={label=p.title,val=p.id} end;if #profiles==0 then profiles={{label="No saved profile",val=""}} end
	c.profile=new("DropDownControl"):DropDownControl(ui.anchor,{w-430,14,232,28},profiles,function(_,value) profile=filters.find(data,value.val);selected=nil;reopen() end);c.profile:SelByValue(profile and profile.id or "","val")
	button(c,"keep",w-182,14,166,"Keep in build",function()
		local hash=require("Modules.PlanningData").hash;local current=hash(saver.data)
		local function keep() if profile then data.activeId=profile.id end;saver:Replace(data);dirty=false;baseHash=hash(saver.data) end
		if current~=baseHash then
			main:OpenConfirmPopup("Saved filters changed","Saved filters changed while this draft was open. Review changes in Profile tools. Keeping this draft replaces the current saved filters.","Keep draft",function()
				if hash(saver.data)~=current then ui.errorPopup("Saved filters changed","Saved filters changed again. Review them and try again.");return end
				keep()
			end)
		else keep() end
	end)
	for i,name in ipairs({"Overview","Customize","Tiers","Simulate","Style","Modules"}) do local control=button(c,"view"..name,16+(i-1)*126,76,118,name,function() page=name;reopen() end);control.locked=page==name end
	button(c,"manage",w-172,76,156,"Profile tools",function()
		local choices={
			{id="new",label="Create profile",details={"Start from a pinned NeverSink preset."}},
			{id="duplicate",label="Duplicate profile",details={"Keep a separate version for another character or stage."}},
			{id="import",label="Import filter",details={"Preserve the original file and edit with personal overrides."}},
			{id="importFiles",label="Included filter files",details={"Attach copies of files referenced by Import for offline preview and export."}},
			{id="account",label="Account filters",details={"Import or review an explicit account publication."}},
			{id="audit",label="Audit and update",details={"Inspect patch migrations, diagnostics and base updates."}},
			{id="changes",label="Review changes",details={"Compare the working draft with the profiles kept in this build."}},
			{id="links",label="Linked build targets",details={"Review changed craft, gear, resource, skill and Atlas pickups; open their source plans."}},
			{id="tracking",label=profile and trackingEnabled(profile) and "Disable pickup update notices" or "Enable pickup update notices",details={"Choose whether this profile reports changes to build pickups. Existing rules remain unchanged."}},
			{id="campaign",label="Campaign and base-family pickups",details={"Choose weapon and armour families, upgrade windows and recipe pickups without changing preset files."}},
			{id="structure",label="Filter structure and priority",details={"Browse compiled sections, nested item families, Continue blocks, diagnostics and exact source text."}},
			{id="sampleSets",label="Saved example sets",details={"Keep exact test items with the build and reuse them after filter edits."}},
			{id="palettes",label="Saved palettes",details={"Name and reuse whole-filter appearance snapshots."}},
			{id="categoryStyles",label="Category appearance",details={"Change colours, fonts and alerts for selected item families while keeping rule priority."}},
			{id="dailySync",label="Daily price sync",details={"Set up the fixed baseline and update your local filter while PoB is open."}},
			{id="marketBrowse",label="Browse market prices",details={"Inspect cards, maps, uniques, gems and crafting bases by league."}},
			{id="economy",label="Review exchange prices",details={"Compare tagged stack hides with current PC trade prices and export a separate candidate."}},
			{id="fileChanges",label="Full file changes",details={"Compare the kept and working compiled filter or original base text, then copy exact sources."}},
			{id="delete",label="Delete this profile",details={"This changes the working draft. Keep and Save to persist."}},
		}
		if not profile then for i=#choices,1,-1 do if choices[i].id~="new" and choices[i].id~="import" then table.remove(choices,i) end end end
		local blocked={economy=not raw or not profile or profile.mode~="Normal"};if report and report.error then blocked.structure=true;blocked.categoryStyles=true;blocked.economy=true;for _,entry in ipairs(choices) do if blocked[entry.id] then entry.details[#entry.details+1]="Unavailable: resolve the compilation error in Overview or use Audit and update first." end end end
		require("Classes.PlanningBrowserControl").Open("Filter profile tools",choices,{action="Open",canChoose=function(entry) return not blocked[entry.id] end,choose=function(entry)
			main:ClosePopup()
			if entry.id=="new" then profile=filters.profile(identifier(),"My loot filter");data.profiles[#data.profiles+1]=profile;data.activeId=profile.id;page="Overview";selected=nil;draft();reopen()
			elseif entry.id=="duplicate" and profile then profile=copyTable(profile);profile.id=identifier();profile.title=profile.title.." copy";data.profiles[#data.profiles+1]=profile;draft();reopen()
			elseif entry.id=="import" then controller.Import(function(text,linked)
				if not profile then profile=filters.profile(identifier(),"Imported filter");data.profiles[#data.profiles+1]=profile end
				profile.template=text
				if linked then
					profile.importFiles=require("Modules.LootFilterImports").merge(profile.importFiles,linked)
				end
				draft();reopen()
			end,profile and profile.importFiles)
			elseif entry.id=="importFiles" and profile then require("Classes.LootFilterImportControl").Open(profile,function(files) profile.importFiles=files;draft();reopen() end)
			elseif entry.id=="account" and profile then controller.Account(profile,function(text) profile.template=text;draft();reopen() end)
			elseif entry.id=="audit" and profile then openAudit()
			elseif entry.id=="changes" then require("Classes.PlanningBrowserControl").Open("Filter changes",require("Modules.LootFilterEditing").review(saver.data,data))
			elseif entry.id=="links" and profile then
				refreshDependencies();if not dependencies or dependencyJob then main:OpenMessagePopup("Linked filter targets",dependencyError or "Checking build pickups. Please try again shortly.");return end
				require("Classes.PlanningBrowserControl").Open("Linked filter targets",dependencies.entries,{action="Open source",choose=function(entry) main:ClosePopup();openSource(entry.origin,entry.openGuide) end,closeOnChoose=false,
					secondary={label="Refresh build pickups",run=function() main:ClosePopup();generatePickups() end}})
			elseif entry.id=="campaign" and profile then require("Classes.LootFilterCampaignControl").Open(build,profile.campaign,function(value) profile.campaign=value;draft();reopen() end,profile.mode)
			elseif entry.id=="structure" and profile then require("Classes.LootFilterStructureControl").Open(profile,function(rule) editRule(rule,keepRule) end)
			elseif (entry.id=="sampleSets" or entry.id=="palettes") and profile then collection(entry.id)
			elseif entry.id=="tracking" and profile then profile.trackBuildPickups=not trackingEnabled(profile);dependencyTime=nil;draft();reopen()
			elseif entry.id=="dailySync" then require("Classes.LootFilterDailySyncControl").Open()
			elseif entry.id=="marketBrowse" then require("Classes.LootFilterMarketBrowseControl").Open()
			elseif entry.id=="economy" and raw and profile.mode=="Normal" then require("Classes.LootFilterEconomyControl").Open(profile,raw,controller.Export)
			elseif entry.id=="categoryStyles" and profile then require("Classes.LootFilterCategoryControl").Open(profile,replaceProfile)
			elseif entry.id=="fileChanges" and profile then require("Classes.LootFilterDiffControl").Open(filters.find(saver.data,profile.id),profile)
			elseif entry.id=="delete" and profile then for i,p in ipairs(data.profiles) do if p.id==profile.id then table.remove(data.profiles,i);break end end;profile=data.profiles[1];data.activeId=profile and profile.id or "";draft();reopen() end
		end,closeOnChoose=false})
	end)
	if not profile then
		local cw=math.floor((w-64)/3)
		for i,entry in ipairs({{"Campaign","Start a new journey","campaign","Assets/Crafting/transmute.png"},{"Early maps","Build a useful pickup list","early_maps","Assets/Crafting/chaos.png"},{"Endgame","Keep the drops that matter","endgame","Assets/Crafting/exalt.png"}}) do
			local x=16+(i-1)*(cw+16);local key="create"..i;local control=button(c,key,x,164,cw,entry[1],function() profile=filters.profile(identifier(),entry[1].." loot",entry[3]);data.profiles[#data.profiles+1]=profile;data.activeId=profile.id;draft();reopen() end);control.height=220;custom[key]=true;control.planningFocusable=true
			function control:Draw() local px,py=self:GetPos();visual.box(px,py,cw,220,self:IsMouseOver() and "^x829AB1" or "^x394D60");visual.box(px+1,py+1,cw-2,218,"^x152B43");SetDrawColor(1,1,1);DrawImage(visual.image(entry[4]),px+(cw-64)/2,py+28,64,64);visual.text(px+20,py+116,24,entry[1],"^xF2D69E",cw-40);visual.text(px+20,py+158,14,entry[2],"^xBECFDC",cw-40);visual.text(px+20,py+192,14,"Create profile  >","^xA6D8EF",cw-40) end
		end
		ui.label(c,"emptyTitle",16,124,"Choose where you are in your build",20)
		ui.description(c,"emptyHelp",16,410,w-32,70,{saver.warning or "Start with a ready-made preset, then customise the labels, sounds and pickups for your character."},16)
	elseif page=="Overview" then
		local cw=math.floor((w-64)/3)
		card("strictCard",16,120,cw,"STRICTNESS",filters.strictness[profile.strictness+1],"Choose how much loot gets through","Assets/Crafting/chaos.png")
		card("targetCard",32+cw,120,cw,"PERSONAL PICKUPS",tostring(#profile.rules),"Crafting, gear and Atlas targets","Assets/Crafting/exalt.png")
		card("baseCard",48+cw*2,120,cw,"BASE PRESET",profile.template and "Imported" or "NeverSink","PoE 3.30 / "..profile.mode,"Assets/Crafting/vaal.png")
		local left=math.max(274,math.floor(w*0.31));local right=w-left-48
		ui.label(c,"setupLabel",16,214,"Your profile",18)
		ui.label(c,"titleLabel",16,246,"Name",12);c.title=new("EditControl"):EditControl(ui.anchor,{16,264,left,28},profile.title,nil,nil,120,function(value) profile.title=value;for _,entry in ipairs(c.profile.list) do if entry.val==profile.id then entry.label=value end end;draft("title") end)
		c.preset=new("DropDownControl"):DropDownControl(ui.anchor,{16,306,left/2-6,26},{{label="Campaign",val="campaign"},{label="Early maps",val="early_maps"},{label="Endgame",val="endgame"}},function(_,value) profile.preset=value.val;draft() end);c.preset:SelByValue(profile.preset,"val")
		c.mode=new("DropDownControl"):DropDownControl(ui.anchor,{28+left/2-6,306,left/2-6,26},{"Normal","Ruthless"},function(_,value) profile.mode=value;draft();reopen() end);c.mode:SelByValue(profile.mode)
		ui.label(c,"strictLabel",16,346,"Strictness",12);c.strictness=new("DropDownControl"):DropDownControl(ui.anchor,{16,364,left,26},filters.strictness,function(index) profile.strictness=index-1;draft();reopen() end);c.strictness.selIndex=profile.strictness+1
		button(c,"generate",16,406,left,"Auto-adjust for this build",generatePickups)
		c.generate.label=function() return generationJob and "Updating build pickups..." or dependencyJob and "Checking build pickups..." or dependencies and dependencies.needsReview and "Build pickups need review *" or dependencies and dependencies.stale and "Refresh build pickups *" or "Auto-adjust for this build" end
		c.generate.enabled=function() return not dependencyJob and not generationJob end
		c.generate.tooltipText="* means linked targets changed or need review. Profile tools > Linked build targets shows the sources. Refreshing preserves personal overrides."
		button(c,"customize",16,448,left,"Customize pickups  >",function() page="Customize";reopen() end)
		sceneControl("preview",left+32,214,right,h-288,library.scene(profile,build,"Mixed drops",0,83),true)
		ui.description(c,"sceneHint",left+32,h-68,right,24,{"Live filter appearance. Open Simulate for drop inspection."},14)
	elseif page=="Tiers" then
		tierView=require("Classes.LootFilterTierControl").Mount(c,profile,w,h,tierState,{id=identifier,change=replaceProfile,reopen=reopen,edit=editRule})
	elseif page=="Modules" then
		require("Classes.LootFilterModuleControl").Mount(c,data,profile,w,h,{id=identifier,change=function() draft();reopen() end,edit=editRule})
	elseif page=="Customize" then
		local sidebar=152;local listX=184;local listW=math.floor((w-216)*0.51);local detailX=listX+listW+16;local detailW=w-detailX-16
		local ok,base=pcall(library.catalog,profile);catalog=ok and base or {}
		local sourceEntries=scope=="Base filter" and catalog or scope=="Policies" and library.campaign(profile) or library.personal(profile)
		local categoryRows={};for _,name in ipairs(library.categories) do categoryRows[#categoryRows+1]={height=36,textSize=14,"^7"..name,name=name} end
		c.categories=new("TextListControl"):TextListControl(ui.anchor,{16,120,sidebar,h-180},nil,categoryRows)
		ui.selectable(c.categories,function(row) return row.name end,function(row) category=row.name;if category=="Campaign" then scope="Policies" end;selected=nil;reopen() end)
		c.categories.selectedKey=category
		local offset=0;for _,row in ipairs(categoryRows) do row.selected=row.name==category;if row.selected then c.categories.controls.scrollBar.offset=math.max(0,offset-(h-240)) end;offset=offset+row.height end
		c.search=new("EditControl"):EditControl(ui.anchor,{listX,120,listW-138,26},query,"Find an item or rule",nil,160,function(value) query=value end)
		c.source=new("DropDownControl"):DropDownControl(ui.anchor,{listX+listW-130,120,130,26},{"My rules","Base filter","Policies"},function(_,value) scope=value;selected=nil;query="";if scope=="Policies" then category="Campaign" elseif category=="Campaign" then category="All items" end;reopen() end);c.source:SelByValue(scope)
		c.rules=new("TextListControl"):TextListControl(ui.anchor,{listX,170,listW,h-274},nil,{})
		ui.label(c,"ruleCount",listX,152,"",12)
		local function refreshList()
			entries=library.entries(profile,sourceEntries,category,query);local rows={};selectedEntry=nil
			for _,entry in ipairs(entries) do if entry.rule.id==selected then selectedEntry=entry end;rows[#rows+1]={height=76,textSize=14,"",entry=entry} end
			if not selectedEntry then selectedEntry=entries[1];selected=selectedEntry and selectedEntry.rule.id end
			if #rows==0 then rows=ui.rows({scope=="My rules" and "No personal pickups here yet." or "No matching base rules.","Try another category or search."},listW-28,14) end
			c.rules.list=rows;c.rules.selectedKey=selected;updateSelection(selectedEntry)
			c.ruleCount.label="^7"..#entries.." rules"..(scope=="My rules" and #entries>1 and " | drag or Alt+arrows" or "")
		end
		local draw=c.rules.Draw
		function c.rules:Draw(viewport)
			draw(self,viewport);local x,y=self:GetPos();local width,height=self:GetSize();SetViewport(x+2,y+2,width-20,height-4);local top=-self.controls.scrollBar.offset
			for _,row in ipairs(self.list) do if row.entry and top+row.height>0 and top<height then local entry=row.entry
				visual.box(2,top+2,width-24,70,selected==entry.rule.id and "^x293D50" or "^x17232E")
				if not entry.base then visual.text(8,top+8,14,"::","^x9DB0C1",14) end
				visual.text(entry.base and 12 or 24,top+8,14,entry.rule.title,selected==entry.rule.id and "^xF0D49B" or "^xDCE5EC",width-(entry.base and 44 or 56))
				local styles=entry.block.styles;visual.chip(8,top+24,width-34,32,entry.sample,{action=entry.block.action,styles={SetTextColor=styles.SetTextColor,SetBorderColor=styles.SetBorderColor,SetBackgroundColor=styles.SetBackgroundColor,SetFontSize={"24"}}})
				visual.text(12,top+58,12,(entry.rule.enabled==false and "DISABLED / " or "")..entry.category.." / "..entry.tier,"^x9DB0C1",width-44)
				if self.dragRule and self.dragRule~=entry.rule.id and self.hoveredLine and self.hoveredLine.line==row then
					local _,mouseY=GetCursorPos();local after=mouseY>=self.hoveredLine.y+row.height/2
					visual.box(4,top+(after and row.height-3 or 0),width-28,3,"^xF0D49B")
				end
			end;top=top+row.height end;SetViewport()
		end
		ui.selectable(c.rules,function(row) return row.entry and row.entry.rule.id end,function(row) updateSelection(row.entry) end,edit)
		c.rules.onClick=function(hit) if hit then c.rules.planningSelect(hit.line,false) end end
		local function reorder(source,target,after)
			if require("Modules.LootFilterRuleOrder").move(profile.rules,source,target,after) then
				local focused=c.rules.hasFocus;selected=source;draft();reopen()
				local workspace=build.planningWorkspace
				if focused and workspace and workspace.page=="filters" and workspace.body and workspace.controls.rules then workspace.body:SelectControl(workspace.controls.rules) end
				return true
			end
		end
		local down,up=c.rules.OnKeyDown,c.rules.OnKeyUp
		function c.rules:OnKeyDown(key,doubleClick,...)
			local hit=self.hoveredLine;local result=down(self,key,doubleClick,...)
			if key=="LEFTBUTTON" and doubleClick and hit and hit.line.entry then edit();return self end
			if key=="LEFTBUTTON" and scope=="My rules" and hit and hit.line.entry and not hit.line.entry.base then
				local x,y=GetCursorPos();self.dragRule=hit.line.entry.rule.id;self.dragX=x;self.dragY=y
			end
			return result
		end
		function c.rules:OnKeyUp(key,...)
			if key=="LEFTBUTTON" and self.dragRule then
				local source=self.dragRule;self.dragRule=nil;local x,y=GetCursorPos();local hit=self.hoveredLine
				local moved=math.abs(x-self.dragX)>4 or math.abs(y-self.dragY)>4
				if self:IsMouseOver() and hit and hit.line.entry and not hit.line.entry.base then
					if moved and reorder(source,hit.line.entry.rule.id,y>=hit.y+hit.line.height/2) then return self end
				end
			end
			return up(self,key,...)
		end
		c.search.changeFunc=function(value) query=value;refreshList() end
		local bw=math.floor((listW-24)/4)
		button(c,"add",listX,h-94,bw,scope=="Policies" and "Set policy" or "+ Rule",function()
			if scope=="Policies" then require("Classes.LootFilterCampaignControl").Open(build,profile.campaign,function(value) profile.campaign=value;draft();reopen() end,profile.mode)
			else editRule(filters.rule("rule-"..identifier(),"New pickup",{'BaseType == "Iron Hat"'}),keepRule) end
		end)
		button(c,"edit",listX+bw+8,h-94,bw,"Edit",edit)
		c.edit.enabled=function() return selectedEntry~=nil end
		c.edit.tooltipText=function() return selectedEntry and "Edit the selected rule." or "Select a rule to edit it." end
		button(c,"toggle",listX+(bw+8)*2,h-94,bw,"On / off",function() if selectedEntry then local rule=copyTable(selectedEntry.rule)
			if selectedEntry.base then rule.text=rule.text:gsub("^%a+",selectedEntry.block.action=="Show" and (profile.mode=="Ruthless" and "Minimal" or "Hide") or "Show");rule.enabled=true else rule.enabled=not rule.enabled end
			keepRule(rule)
		end end)
		c.toggle.label=function() return selectedEntry and (selectedEntry.base and (selectedEntry.block.action=="Show" and "Hide" or "Show") or selectedEntry.rule.enabled==false and "Enable" or "Disable") or "On / off" end
		c.toggle.enabled=function() return selectedEntry~=nil end
		c.toggle.tooltipText=function() return selectedEntry and "Change the selected rule's visibility." or "Select a rule to change its visibility." end
		button(c,"remove",listX+(bw+8)*3,h-94,bw,"Delete",function() if selectedEntry and not selectedEntry.base then for i,r in ipairs(profile.rules) do if r.id==selected then table.remove(profile.rules,i);break end end;selected=nil;draft();reopen() end end)
		c.remove.enabled=function() return selectedEntry~=nil and not selectedEntry.base end
		local function visibleNeighbour(delta)
			if not selectedEntry or selectedEntry.base then return end
			for i,entry in ipairs(entries) do if entry.rule.id==selected then return entries[i+delta] end end
		end
		local function move(delta) local target=visibleNeighbour(delta);if target and not target.base then reorder(selected,target.rule.id,delta>0) end end
		local navigate=c.rules.planningMove
		c.rules.planningMove=function(delta) if IsKeyDown("ALT") then move(delta) else navigate(delta) end end
		button(c,"up",listX+listW-62,148,26,"^",function() move(-1) end);c.up.height=20
		button(c,"down",listX+listW-30,148,26,"v",function() move(1) end);c.down.height=20
		c.up.enabled=function() return visibleNeighbour(-1)~=nil end;c.down.enabled=function() return visibleNeighbour(1)~=nil end
		c.up.tooltipText="Move before the previous visible rule. Hidden rules between them will also be crossed."
		c.down.tooltipText="Move after the next visible rule. Hidden rules between them will also be crossed."
		c.rules.tooltipText="Drag a personal rule, use the arrows, or press Alt+Up/Down. Rule order determines priority."
		c.preview=new("Control"):Control(ui.anchor,{detailX,120,detailW,126});backgrounds.preview=true
		function c.preview:Draw() local x,y=self:GetPos();visual.floor(x,y,detailW,126);visual.chip(x+8,y+8,detailW-16,112,item,result) end
		c.detail=new("TextListControl"):TextListControl(ui.anchor,{detailX,260,detailW,h-382},nil,{})
		button(c,"appearance",detailX,h-110,detailW,"Colours, sound & size",edit)
		c.appearance.width=math.floor((detailW-12)/2);c.appearance.label="Appearance"
		c.appearance.enabled=function() return selectedEntry~=nil end
		c.appearance.tooltipText=function() return selectedEntry and "Edit the selected rule's appearance." or "Select a rule to edit its appearance." end
		button(c,"openSource",detailX+math.floor((detailW-12)/2)+12,h-110,math.floor((detailW-12)/2),"Open source",function() openSource(assert(selectedRule().origin)) end)
		c.openSource.enabled=function() return selectedRule() and selectedRule().origin~=nil end;c.openSource.tooltipText="Open the craft, gear, resource, skill guide or Atlas plan that generated this pickup."
		button(c,"sampleEdit",detailX,h-72,detailW,"Test sample properties",function() controller.EditSample(item,function(next) rememberSample(next);compile();updateDetail() end) end)
		refreshList()
	elseif page=="Simulate" then
		local left=208;local groundX=240;local groundW=w-256
		ui.label(c,"sceneTitle",16,124,"Loot simulator",20)
		local kinds={"Mixed drops","Build targets","Currency","Preset highlights","Tiered gear","Fated gear","Foulborn gear","Vendor recipes","Covens & Threads","Maps & threads","Map tiers","Flasks & tinctures","Divination cards","Essences","Crafting materials","Heist & Expedition","Blight & oils","Breach","Beyond","Incursion","Legion","Delirium","Harvest","Abyss","Ultimatum","Ritual","Sanctum","Pinnacle bosses"};local savedSets=profile.sampleSets or {};if #savedSets>0 then kinds[#kinds+1]="Saved examples" elseif sceneKind=="Saved examples" then sceneKind="Mixed drops" end
		local function selectScene(value,savedId)
			if savedId then sampleSetId=savedId end
			sceneKind=value;scenePage=1;if value=="Saved examples" then local chosen=savedSets[1];for _,entry in ipairs(savedSets) do if entry.id==sampleSetId then chosen=entry end end;item=copyTable(chosen.samples[1]) elseif value~="Build targets" then item=library.scene(profile,build,value,seed,settings.areaLevel,settings.itemLevel)[1] or item end;reopen()
		end
		c.sceneKind=new("DropDownControl"):DropDownControl(ui.anchor,{16,162,left,26},kinds,function(_,value) selectScene(value) end);c.sceneKind:SelByValue(sceneKind)
		button(c,"browseScenes",146,120,78,"Browse",function()
			local descriptions={
				["Mixed drops"]="Compare a variety of example items.",["Build targets"]="Test pickups generated from your build and plans.",
				Currency="Compare currency examples.",["Preset highlights"]="Review high-emphasis currency in the pinned preset, not live prices.",
				["Tiered gear"]="Compare unidentified item tiers on the same base.",["Fated gear"]="Compare matching rare gear examples at tier 4 (no tier in Ruthless).",["Foulborn gear"]="Compare matched examples with and without Foulborn.",["Vendor recipes"]="Test sample recipe items and their socket or quality properties.",
				["Covens & Threads"]="Compare Threads and other Covens items.",["Maps & threads"]="Compare map bases, Threads and special map examples.",
				["Map tiers"]="Compare map tier conditions from tier 1 through 17.",["Flasks & tinctures"]="Compare life, mana and utility flasks with tinctures.",
				["Divination cards"]="Compare example divination cards.",Essences="Compare essence tiers and special essences.",
				["Crafting materials"]="Compare fossils, resonators, Eldritch currency and Lifeforce.",["Heist & Expedition"]="Compare contracts, blueprints, a logbook and vendor currency.",
				["Blight & oils"]="Compare oils, a Thread and Blighted map examples.",Breach="Compare splinters, a Breachstone and Threads.",
				Beyond="Compare tainted currency for corrupted items.",Incursion="Compare Royal Visage, Soul Cores and Threads.",Legion="Compare splinters, emblems, incubators and a Thread.",Delirium="Compare Simulacrum items, Delirium Orbs and Refracting Fog.",
				Harvest="Compare Lifeforce and Sacred Blossom.",Abyss="Compare eye jewels, a Stygian Vise and Threads.",
				Ultimatum="Compare an inscribed item, catalysts and Threads.",Ritual="Compare vessels, Omens and Threads.",
				Sanctum="Compare a Forbidden Tome, relic bases and invocations.",["Pinnacle bosses"]="Compare boss fragments and related currency.",
				["Saved examples"]="Reopen your saved sets of exact example properties.",
			}
			local encounters={Breach=true,Beyond=true,Incursion=true,Legion=true,Delirium=true,Harvest=true,Abyss=true,Ultimatum=true,Ritual=true,Sanctum=true,["Pinnacle bosses"]=true,["Blight & oils"]=true,["Heist & Expedition"]=true,["Covens & Threads"]=true}
			local entries={};for _,kind in ipairs(kinds) do
				local description=descriptions[kind] or "Compare example items."
				local category=encounters[kind] and "Encounters" or kind=="Saved examples" and "Saved" or kind=="Build targets" and "Build" or "Items and comparisons"
				local names,seen={},{}
				if kind~="Build targets" and kind~="Saved examples" and kind~="Preset highlights" then
					for _,sample in ipairs(library.scene(profile,build,kind,seed,settings.areaLevel,settings.itemLevel)) do
						local name=sample.BaseType;if name and not seen[name] then seen[name]=true;names[#names+1]=name end
					end
				end
				local details={kind,description,"Examples are not predicted drops, odds or prices."}
				if #names>0 then
					details[#details+1]="Example items:"
					for i=1,math.min(#names,8) do details[#details+1]="  "..names[i] end
					if #names>8 then details[#details+1]="  And "..(#names-8).." more" end
				end
				if kind=="Saved examples" then
					for _,saved in ipairs(savedSets) do
						local sampleNames,seenSaved={},{}
						for _,sample in ipairs(saved.samples) do local name=sample.BaseType;if name and not seenSaved[name] then seenSaved[name]=true;sampleNames[#sampleNames+1]=name end end
						local savedDetails={saved.title,"Saved example set",#saved.samples.." items retain their saved properties.","Example items:"}
						for i=1,math.min(#sampleNames,8) do savedDetails[#savedDetails+1]="  "..sampleNames[i] end
						if #sampleNames>8 then savedDetails[#savedDetails+1]="  And "..(#sampleNames-8).." more" end
						entries[#entries+1]={id=kind,savedId=saved.id,label=saved.title,category="Saved",search=description.." "..table.concat(sampleNames," "),details=savedDetails}
					end
				else entries[#entries+1]={id=kind,label=kind,category=category,search=description.." "..table.concat(names," "),details=details} end
			end
			require("Classes.PlanningBrowserControl").Open("Choose example scene",entries,{action="Use scene",choose=function(entry) selectScene(entry.id,entry.savedId) end})
		end)
		c.browseScenes.tooltipText="Search examples by name or item, and read what each scene contains."
		c.sceneKind.tooltipText="Preset highlights use exact names from the pinned NeverSink currency snapshot. They are not live prices or drop rates."
		button(c,"regenerate",16,202,100,"Regenerate",function() seed=seed+1;scenePage=1;if sceneKind=="Build targets" then transient.filterSceneTargets=nil end;reopen() end)
		c.regenerate.enabled=sceneKind~="Saved examples" and sceneKind~="Tiered gear" and sceneKind~="Fated gear" and sceneKind~="Foulborn gear" and sceneKind~="Map tiers";c.regenerate.tooltipText="Reorder generated examples. Saved and tier-comparison examples keep their exact properties; examples are not drop-rate estimates."
		button(c,"savedSamples",124,202,100,"Saved sets",function() collection("sampleSets") end)
		local savedSet
		if sceneKind=="Saved examples" then
			local choices={};for _,entry in ipairs(savedSets) do choices[#choices+1]={label=entry.title,val=entry.id};if entry.id==sampleSetId then savedSet=entry end end;savedSet=savedSet or savedSets[1];sampleSetId=savedSet.id
			c.sceneSet=new("DropDownControl"):DropDownControl(ui.anchor,{groundX+16,130,groundW-32,26},choices,function(_,entry) sampleSetId=entry.val;scenePage=1;for _,value in ipairs(savedSets) do if value.id==sampleSetId then item=copyTable(value.samples[1]) end end;reopen() end);c.sceneSet:SelByValue(sampleSetId,"val")
		end
		button(c,"hidden",16,242,left,showHidden and "Hidden drops: visible" or "Hidden drops: off",function() showHidden=not showHidden;scenePage=1;reopen() end)
		button(c,"sampleEdit",16,282,100,"Configure",function() controller.EditSample(item,function(next) rememberSample(next);scenePage=1;compile();reopen() end,result and result.missingProperties and result.missingProperties[1]) end)
		button(c,"pasteDrop",124,282,100,"Paste item",function()
			local ok,sample=pcall(function() return require("Modules.LootFilterClipboard").parse(Paste(),settings.areaLevel) end)
			if not ok then ui.errorPopup("Paste item",sample);return end
			rememberSample(sample);scenePage=1;compile();reopen()
		end)
		button(c,"sceneSettings",16,322,100,"Scene",function() require("Classes.LootFilterSceneControl").Open(settings,function(next) settings=next;reopen() end) end)
		if savedSet then c.sceneSettings.tooltipText="Background settings apply here. Saved examples retain their recorded item and area levels." end
		button(c,"sampleHistory",124,322,100,"History",function() local entries={};for i=#samples,1,-1 do local sample=samples[i];entries[#entries+1]={id=i,label=visual.sampleName(sample),details={"Item level: "..tostring(sample.ItemLevel or "unknown"),"Area level: "..tostring(sample.AreaLevel or "unknown"),"Missing properties remain unknown."},sample=sample} end
			require("Classes.PlanningBrowserControl").Open("Tested item history",entries,{action="Test again",choose=function(entry) rememberSample(entry.sample);scenePage=1;compile();reopen() end})
		end)
		button(c,"sound",16,362,100,"Play sound",function()
			local ok,message=require("Modules.LootFilterAudio").play(result and result.styles or {})
			local lines=sampleDetails(item,result,true);lines[#lines+1]=message;c.selection.list=ui.rows(lines,left-28,14)
			if not ok then ui.errorPopup("Sound preview",message) end
		end)
		c.sound.tooltipText="Preview a reference tone or local WAV; the game's numbered alert may sound different."
		button(c,"sceneStats",124,362,100,"Drop review",function()
			local counts={Show=0,Hide=0,Minimal=0,Unknown=0};local entries={}
			for index,drop in ipairs(scene) do
				local evaluated=evaluateDrop(drop)
				local action=M.dropOutcome(evaluated)
				counts[action]=counts[action]+1
				local value=itemTier(drop);local tier=(sceneKind=="Fated gear" or sceneKind=="Foulborn gear") and (drop[sceneKind=="Fated gear" and "Fated" or "Foulborn"] and " ("..(sceneKind=="Fated gear" and "Fated" or "Foulborn")..")" or " (other)") or value~=nil and (value==0 and " (no tier)" or " (tier "..value..")") or (drop.Identified==false and (drop.Rarity=="Magic" or drop.Rarity=="Rare") and " (tier unknown)" or "")
				entries[#entries+1]={id=index,label=visual.sampleName(drop)..tier.." - "..action,category=action,details=sampleDetails(drop,evaluated),sample=drop}
			end
			local title=string.format("Examples: %d shown, %d minimal, %d hidden, %d unknown",counts.Show,counts.Minimal,counts.Hide,counts.Unknown)
			local saved=filters.find(saver.data,profile.id)
			require("Classes.PlanningBrowserControl").Open(title,entries,{action="Inspect item",choose=function(entry) rememberSample(entry.sample);scenePage=1;compile();reopen() end,
				secondary=saved and {label="Compare saved",run=function() main:ClosePopup();require("Classes.LootFilterImpactControl").Open(saved,profile,scene,function(sample) rememberSample(sample);scenePage=1;compile();reopen() end) end} or nil})
		end)
		c.sceneStats.tooltipText="Review every example in this scene, including hidden and uncertain results. Counts are not drop-rate predictions."
		c.selection=new("TextListControl"):TextListControl(ui.anchor,{16,410,left,h-474},nil,ui.rows(sampleDetails(item,result,true),left-28,14))
		local extraTest=false
		if savedSet then
			scene=copyTable(savedSet.samples);local encode=require("Modules.PlanningData").encode;local present=false;local current=encode(item);for _,sample in ipairs(scene) do if encode(sample)==current then present=true;break end end
			if not present then table.insert(scene,1,item);extraTest=true end
		else local targets=sceneKind=="Build targets" and targetPreview() or nil
			local targetKeys
			if targets then scene,targetKeys=M.targetScene(targets,profile,build,settings)
			else scene=library.scene(profile,build,sceneKind,seed,settings.areaLevel,settings.itemLevel) end
			if sceneKind~="Tiered gear" and sceneKind~="Fated gear" and sceneKind~="Foulborn gear" and sceneKind~="Map tiers" and (not targetKeys or not targetKeys[require("Modules.PlanningData").encode(item)]) then table.insert(scene,1,item) end
		end
		if not savedSet and sceneKind~="Tiered gear" and sceneKind~="Fated gear" and sceneKind~="Foulborn gear" and sceneKind~="Map tiers" then
			if sceneKind~="Build targets" then
				local encode=require("Modules.PlanningData").encode;local selected=encode(item)
				for i=#scene,2,-1 do if encode(scene[i])==selected then table.remove(scene,1);break end end
			end
		end
		local targets=sceneKind=="Build targets" and transient.filterSceneTargets or nil
		local caption=invalidFilterReason and "FILTER INVALID - SEE DETAILS" or sceneKind=="Preset highlights" and "PINNED SNAPSHOT - NOT LIVE PRICES" or sceneKind=="Map tiers" and "MAP TIER COMPARISON" or sceneKind=="Fated gear" and "FATED GEAR COMPARISON" or sceneKind=="Foulborn gear" and "FOULBORN GEAR COMPARISON" or sceneKind=="Tiered gear" and (profile.mode=="Ruthless" and "RUTHLESS: NO ITEM TIERS" or "TIER COMPARISON") or savedSet and (extraTest and "SAVED SET + CURRENT TEST" or "SAVED EXAMPLES") or targets and (targets.error and "TARGETS UNAVAILABLE" or not targets.rules and "CHECKING BUILD TARGETS..." or #targets.warnings>0 and "SOME TARGETS NEED REVIEW" or "BUILD TARGETS")
		sceneControl("preview",groundX,savedSet and 168 or 120,groundW,h-(savedSet and 230 or 182),scene,true,caption)
		if targets then c.preview.tooltipText=targets.error or (#(targets.warnings or {})>0 and "Some build targets need review. Open linked build targets for details." or "Build target examples update as the build changes. The current test item is also shown.") end
		button(c,"inspectMatch",w-216,h-96,184,invalidFilterReason and "Review filter errors" or "Inspect matched rules",function() if invalidFilterReason then openAudit(true) else inspectMatches() end end)
		c.inspectMatch.enabled=function() return invalidFilterReason~=nil or parsed~=nil end
	else
		ui.label(c,"styleHeading",16,128,"A palette for your pickups",22)
		ui.description(c,"styleHelp",16,164,w-32,44,{"Choose the default style for generated targets, or edit a specific pickup in Customize. Existing base-preset colours are preserved."},14)
		local sw=math.floor((w-48)/2)
		for i,entry in ipairs({{"Gold / cyan","default",{255,235,175},{105,195,245},{20,30,45}},{"High contrast","contrast",{255,255,255},{255,220,0},{0,0,0}}}) do
			local x=16+(i-1)*(sw+16);local key="style"..i;local control=button(c,key,x,226,sw,entry[1],function() profile.theme=entry[2];draft();reopen() end);control.height=180;custom[key]=true;control.planningFocusable=true
			function control:Draw() local px,py=self:GetPos();visual.box(px,py,sw,180,profile.theme==entry[2] and "^xD1B579" or "^x384A5B");visual.box(px+1,py+1,sw-2,178,"^x14202C");visual.floor(px+12,py+12,sw-24,94);visual.chip(px+20,py+20,sw-40,76,{BaseType="Crafting base"},{action="Show",styles={SetTextColor=entry[3],SetBorderColor=entry[4],SetBackgroundColor=entry[5],SetFontSize={"42"}}});visual.text(px+18,py+124,20,entry[1],"^xEED39D",sw-36);visual.text(px+18,py+154,14,profile.theme==entry[2] and "Selected for new build targets" or "Use this palette","^xAFC2D3",sw-36) end
		end
		button(c,"applyStyle",16,438,260,"Restyle personal pickups",function() local template=parser.parse(filters.rule("style","Style",{},nil,profile.theme).text).rules[1].styles;for i,rule in ipairs(profile.rules) do profile.rules[i]=library.appearance(rule,template);profile.rules[i].origin=rule.origin end;draft();reopen() end)
		button(c,"globalStyle",292,438,260,"Whole-filter appearance",function() require("Classes.LootFilterGlobalControl").Open(profile,function(next) profile.appearance=next.appearance;draft();reopen() end) end)
		button(c,"savedPalettes",568,438,math.min(260,w-584),"Saved palettes",function() collection("palettes") end)
		button(c,"categoryStyles",16,478,260,"Category appearance",function() require("Classes.LootFilterCategoryControl").Open(profile,replaceProfile) end);c.categoryStyles.enabled=not report.error;c.categoryStyles.tooltipText="Resolve compilation errors in Overview before opening category styles."
	end
	if profile then
		button(c,"undo",w-332,h-38,68,"Undo",function() local id=profile.id;data=history:step(true);profile=filters.find(data,id) or data.profiles[1];dirty=true;reopen() end);c.undo.enabled=#history.undo>0
		button(c,"redo",w-256,h-38,68,"Redo",function() local id=profile.id;data=history:step(false);profile=filters.find(data,id) or data.profiles[1];dirty=true;reopen() end);c.redo.enabled=#history.redo>0
		button(c,"export",w-172,h-38,156,"Export to PoE",function() if raw then controller.Export(profile,raw,report) end end)
		c.export.enabled=function() return raw~=nil end
		c.export.tooltipText=function()
			if raw then return "Export or copy the compiled filter." end
			local reason=report and report.error and ui.errorText(report.error)
			if not reason then for _,entry in ipairs(report and report.diagnostics or {}) do if entry.error then reason="Line "..entry.line..": "..entry.error;break end end end
			reason=reason or "The filter could not be compiled."
			return reason..(reason:lower():find("audit",1,true) and "" or " Review Audit and update for details.")
		end
		ui.label(c,"saveHint",16,h-30,dirty and "Working draft / Keep in build, then Save" or "Kept profiles travel with your build",12)
		c.saveHint.label=function() return "^7"..(dirty and "Working draft / Keep in build, then Save" or "Kept profiles travel with your build") end
	end
	layout.snapshot=snapshot
	layout.onShow=function() if not generationJob then refreshDependencies() end end
	layout.tick=function()
		if generationJob then advanceGeneration()
		elseif page=="Simulate" and sceneKind=="Build targets" and transient.filterSceneTargets and not transient.filterSceneTargets.rules and not transient.filterSceneTargets.error then advanceTargetPreview()
		elseif dependencyJob then advanceDependencies()
		elseif not dependencyTime or GetTime()-dependencyTime>2000 then
			if page=="Simulate" and sceneKind=="Build targets" and transient.filterSceneTargets and (transient.filterSceneTargets.job.profile~=profile or not require("Modules.LootFilterDependencies").current(transient.filterSceneTargets.job)) then transient.filterSceneTargets=nil;reopen();return end
			refreshDependencies()
		end
	end
	refreshDependencies()
	for _,control in pairs(c) do control.layoutAudit="loot-filter-workspace" end
	ui.style(c,{keep=true,export=true},custom);visual.layers(c,backgrounds);layout.mount(w,h,"Loot filter",c)
end
return M
