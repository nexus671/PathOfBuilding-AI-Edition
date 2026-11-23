-- cspell:ignore eimport jsontype
-- Build-owned crafting plans. External simulator exports are data, never code.
local json = require("dkjson")
local M = { }
M.home = "https://beta.craftofexile.com/?game=poe1"
M.developers = "https://beta.craftofexile.com/developers?game=poe1"

local function text(value,limit,label,optional)
	if value == nil and optional then return nil end
	assert(type(value) == "string" and #value <= limit and (optional or value:match("%S")),"Invalid "..label)
	return value
end
local function number(value,low,high,label)
	assert(type(value) == "number" and value == value and value >= low and value <= high,"Invalid "..label)
	return value
end
function M.item(raw)
	local item = new("Item"):Item(text(raw,24000,"item text"))
	assert(item.base and item.baseName,"Item text needs a recognized base")
	return item
end

-- Create an explicit hypothetical starting point without carrying over item
-- properties that cannot be inferred from the base and item level alone.
function M.blankBase(raw)
	local item=M.item(raw);local level=item.itemLevel
	assert(type(level)=="number" and level==math.floor(level) and level>=1 and level<=100,"The copied item needs an explicit item level from 1 to 100")
	assert(#item.baseName<=160 and not item.baseName:find("[%c%^]"),"Invalid item base")
	local base="Rarity: NORMAL\n"..item.baseName.."\nItem Level: "..level
	require("Modules.CraftingSimulator").model(base)
	return base
end

function M.workbenchReason(project)
	local ok,item=pcall(M.item,project.startingItem)
	if ok and (item.rarity=="UNIQUE" or item.rarity=="RELIC") then
		local inspected,reason=false,nil
		if item.rarity=="UNIQUE" then
			inspected,reason=pcall(require("Modules.CraftingUniqueQuality").inspect,project.startingItem)
			if not inspected then
				return require("Modules.PlanningUI").errorText(reason),false
			end
		end
		return "Unique and relic starting items can have written guides; full workbench simulation is unavailable. Eligible unique armour, weapons, flasks and tinctures have quality previews; jewellery has experimental catalyst previews, and socketed items have socket previews.",inspected
	end
end

function M.validate(project)
	assert(type(project) == "table","Invalid crafting project")
	local result = {id=text(project.id,64,"project ID"),title=text(project.title,120,"project title"),slot=text(project.slot,80,"slot"),
		startingItem=text(project.startingItem,24000,"starting item"),targetItem=text(project.targetItem,24000,"target item",true),
		notes=text(project.notes,8000,"project notes",true),originNote=text(project.originNote,1000,"project source note",true),simulatorExport=text(project.simulatorExport,128000,"simulator export",true),goals={},steps={}}
	-- Older conditional examples stored their provenance only in editable notes.
	if not result.originNote and result.notes and result.notes:find("Conditional bench-rarity example;",1,true)==1 then result.originNote=result.notes:sub(1,1000) end
	assert(result.id:match("^[%w%-_]+$"),"Project ID must use letters, numbers, underscores or hyphens")
	local function denseArray(value,label)
		assert(type(value)=="table" and value~=json.null,"Invalid "..label)
		local meta=getmetatable(value);assert(not meta or meta.__jsontype~="object","Invalid "..label)
		local count=0;for key in pairs(value) do assert(type(key)=="number" and key==math.floor(key) and key>=1 and key<=#value,"Invalid "..label);count=count+1 end
		assert(count==#value,"Invalid "..label)
	end
	denseArray(project.goals,"target modifiers")
	for _,goal in ipairs(project.goals) do result.goals[#result.goals+1]=text(goal,300,"target modifier") end
	denseArray(project.steps,"crafting steps")
	local uniqueItem,uniqueInfo,uniqueChecked,uniqueSocketCount
	for _,step in ipairs(project.steps) do
		assert(type(step) == "table","Invalid crafting step")
		local entry={action=text(step.action,1000,"step action"),stopWhen=text(step.stopWhen,500,"stop condition",true),onFailure=text(step.onFailure,500,"failure route",true),done=step.done == true}
		if step.uniqueCraft~=nil then
			local craft=step.uniqueCraft;assert(type(craft)=="table" and (craft.method=="catalyst" or craft.method=="instilling" or craft.method=="enkindling" or craft.method=="bench_flask_enchant" or craft.method=="divine" or craft.method=="blessed" or craft.method=="sacred" or craft.method=="tainted_quality" or craft.method=="jeweller" or craft.method=="tainted_jeweller" or craft.method=="quality" or craft.method=="beast_max_links" or craft.method=="beast_max_sockets" or craft.method=="omen_connections" or craft.method=="omen_jeweller" or craft.method=="fusing" or craft.method=="tainted_fusing" or craft.method=="chromatic" or craft.method=="tainted_chromatic" or craft.method=="omen_trichromatism" or craft.method=="socket_colour_bench" or craft.method=="socket_white_bench" or craft.method=="socket_bench" or craft.method=="socket_count_bench") and type(craft.count)=="number" and craft.count==math.floor(craft.count) and craft.count>=((craft.method=="socket_count_bench" or craft.method=="socket_colour_bench") and 2 or 1) and craft.count<=((craft.method=="quality" or craft.method=="catalyst") and 20 or craft.method=="socket_count_bench" and 6 or craft.method=="socket_colour_bench" and 4 or 1),"Invalid unique crafting step")
			assert(craft.method=="catalyst" and type(craft.catalyst)=="number" and craft.catalyst==math.floor(craft.catalyst) and require("Modules.CraftingUniqueQuality").catalysts[craft.catalyst] or craft.method~="catalyst" and craft.catalyst==nil,"Invalid unique catalyst choice")
			assert(craft.method=="bench_flask_enchant" and require("Modules.CraftingFlaskEnchants").benchCost(craft.enchantId) or craft.method~="bench_flask_enchant" and craft.enchantId==nil,"Invalid unique enchantment choice")
			if not uniqueChecked then local ok,item,info=pcall(require("Modules.CraftingUniqueQuality").inspect,result.startingItem);uniqueItem=ok and item or nil;uniqueInfo=ok and info or nil;uniqueSocketCount=ok and #item.sockets or nil;uniqueChecked=true end
			local compatible=uniqueInfo and (craft.method=="socket_white_bench" or craft.method=="socket_bench" or craft.method=="socket_count_bench" or craft.method=="socket_colour_bench" or (craft.method=="tainted_quality" or craft.method=="tainted_chromatic" or craft.method=="tainted_fusing" or craft.method=="tainted_jeweller") and uniqueItem.corrupted or craft.method~="tainted_quality" and craft.method~="tainted_chromatic" and craft.method~="tainted_fusing" and craft.method~="tainted_jeweller" and not uniqueItem.corrupted and (craft.method~="quality" or uniqueInfo.quality+craft.count<=20))
			if compatible and craft.method=="sacred" then compatible=not require("Modules.CraftingUniqueQuality").sacredReason(result.startingItem) end
			if compatible and craft.method=="blessed" then compatible=not require("Modules.CraftingUniqueBlessed").reason(result.startingItem) end
			if compatible and craft.method=="quality" then compatible=uniqueInfo.qualitySupported and uniqueInfo.resource~=nil end
			if compatible and craft.method=="tainted_quality" then compatible=not require("Modules.CraftingUniqueQuality").taintedQualityReason(result.startingItem) end
			if compatible and craft.method=="catalyst" then
				local jewellery=uniqueItem.type=="Ring" or uniqueItem.type=="Amulet" or uniqueItem.type=="Belt"
				-- Earlier guide steps can change the catalyst type and reset quality.
				compatible=jewellery and (uniqueInfo.quality==0 or uniqueItem.catalyst~=nil)
			end
			if compatible and (craft.method=="instilling" or craft.method=="enkindling" or craft.method=="bench_flask_enchant") then compatible=require("Modules.CraftingFlaskEnchants").eligible({item=uniqueItem}) end
			-- Keep typed steps for a unique that cannot be inspected until its item text is
			-- corrected. Consumers must inspect the item and verify the action text
			-- before using these unverified steps.
			local rarity=result.startingItem:match("^Rarity:%s*(%a+)") or result.startingItem:match("\nRarity:%s*(%a+)")
			local pending=not uniqueInfo and rarity and rarity:upper()=="UNIQUE"
			if pending or compatible and require("Modules.CraftingUniqueQuality").matchesGuideAction(craft.method,craft.count,uniqueInfo.resource,uniqueItem.corrupted,entry.action,uniqueSocketCount,craft.enchantId,craft.catalyst) then entry.uniqueCraft={method=craft.method,count=craft.count,enchantId=craft.enchantId,catalyst=craft.catalyst};if not pending and craft.method=="socket_count_bench" then uniqueSocketCount=craft.count elseif not pending and (craft.method=="omen_jeweller" or craft.method=="beast_max_sockets") then uniqueSocketCount=require("Modules.CraftingUniqueQuality").omenCount(uniqueItem) elseif not pending and (craft.method=="jeweller" or craft.method=="tainted_jeweller") then uniqueSocketCount=nil end end
		end
		result.steps[#result.steps+1]=entry
	end
	if project.priceBook then
		local prices=require("Modules.CraftingPrices")
		result.priceBook=prices.validate(project.priceBook)
		-- Reject conflicting aliases before saving, preserving the supplied keys.
		prices.normalized(result.priceBook,{item=M.item(result.startingItem)})
	end
	if project.nativeRecipe then result.nativeRecipe=require("Modules.CraftingSimulator").validateRecipe(project.nativeRecipe) end
	if project.primarySimulation~=nil and project.primarySimulation~=false then
		local settings=project.primarySimulation;assert(type(settings)=="table","Invalid primary simulation settings")
		for key in pairs(settings) do assert(key=="trials" or key=="maxActions" or key=="seed","Invalid primary simulation setting") end
		local trials=number(settings.trials,1,2000,"simulation trials");local maxActions=number(settings.maxActions,1,2000,"simulation action budget");local seed=number(settings.seed,1,2147483646,"simulation seed")
		assert(trials==math.floor(trials) and maxActions==math.floor(maxActions) and seed==math.floor(seed) and trials*maxActions<=20000,"Invalid primary simulation budget")
		result.primarySimulation={trials=trials,maxActions=maxActions,seed=seed}
	end
	if project.recipeAlternatives~=nil then
		denseArray(project.recipeAlternatives,"recipe alternatives");result.recipeAlternatives={};local names={}
		for _,alternative in ipairs(project.recipeAlternatives) do
			assert(type(alternative)=="table","Invalid recipe alternative")
			local name=text(alternative.name,120,"recipe name"):match("^%s*(.-)%s*$")
			assert(name~="" and not name:find("[%c%^]"),"Invalid recipe name")
			assert(not names[name:lower()],"Recipe names must be unique");names[name:lower()]=true
			assert(alternative.trackPickups==nil or type(alternative.trackPickups)=="boolean","Invalid recipe pickup tracking")
			result.recipeAlternatives[#result.recipeAlternatives+1]={name=name,recipe=require("Modules.CraftingSimulator").validateRecipe(alternative.recipe),trackPickups=alternative.trackPickups}
		end
	end
	if project.preferredMethod then
		local valid=false;for _,method in ipairs(require("Modules.CraftingSimulator").methods) do if project.preferredMethod==method then valid=true end end
		assert(valid,"Unknown starting currency");result.preferredMethod=project.preferredMethod
	end
	if project.run then result.run=require("Modules.CraftingCheckpoint").validate(result.startingItem,project.run) end
	if project.inventory~=nil then result.inventory=require("Modules.CraftingInventory").validate(project.inventory) end
	if project.estimate then
		local quote = project.estimate
		result.estimate = {amount=number(quote.amount,0,1e12,"estimated cost"),currency=text(quote.currency,24,"currency"),source=text(quote.source,240,"price source"),quotedAt=number(quote.quotedAt,0,4102444800,"quote time")}
	end
	if project.simulation then
		local sim = project.simulation
		assert(type(sim.trials) == "number" and sim.trials == math.floor(sim.trials) and type(sim.successes) == "number" and sim.successes == math.floor(sim.successes),"Simulation counts must be integers")
		result.simulation = {source="Craft of Exile (supplied result)",patch=text(sim.patch,40,"simulation patch"),observedAt=number(sim.observedAt,0,4102444800,"simulation time"),
			trials=number(sim.trials,1,1e9,"simulation trials"),successes=number(sim.successes,0,sim.trials,"simulation successes"),notes=text(sim.notes,4000,"simulation notes",true)}
	end
	return result
end

-- Preserve JSON dictionary shape after the generic native table copy.
function M.copy(projects)
	local result=copyTable(projects)
	for _,project in ipairs(result) do
		if project.priceBook then project.priceBook=require("Modules.CraftingPrices").validate(project.priceBook) end
	end
	return result
end

-- A saved recipe may start from an edited state rather than the pasted item.
-- When that item changes, reject stale states before an AI or other caller can
-- save a project that the workbench and simulator cannot execute.
function M.checkStartingStateChange(previous,project)
	if not previous or previous.startingItem==project.startingItem then return end
	local recipes={};local oldStates={}
	local function collect(target,entry,label)
		if entry and entry.initialState then target[#target+1]={state=entry.initialState,label=label} end
	end
	collect(oldStates,previous.nativeRecipe,"Primary recipe")
	for _,entry in ipairs(previous.recipeAlternatives or {}) do collect(oldStates,entry.recipe,entry.name) end
	collect(recipes,project.nativeRecipe,"Primary recipe")
	for _,entry in ipairs(project.recipeAlternatives or {}) do collect(recipes,entry.recipe,entry.name) end
	if #recipes==0 then return end
	local sim=require("Modules.CraftingSimulator");local ok,model=pcall(sim.model,project.startingItem)
	assert(ok,"Cannot verify recipe starting states for the new item. Reset or replace them before keeping this project.")
	for _,entry in ipairs(recipes) do
		local state=entry.state
		assert(type(state)=="table",entry.label.." has an invalid starting state. Reset or replace it before keeping this project.")
		if not state.origin then for _,old in ipairs(oldStates) do
			assert(not (tableDeepEquals(state,old.state) and tableDeepEquals(old.state,state)),entry.label.." has an unbound starting state from the previous item. Reset or replace it before keeping this project.")
		end end
		local valid=pcall(sim.validateState,model,copyTable(state))
		assert(valid,entry.label.." has a starting state incompatible with the new item. Reset or replace it before keeping this project.")
	end
end

-- AI proposals can introduce recipe states without changing the pasted item.
-- Validate changed recipes, while allowing unchanged legacy recipes to be
-- retained during ordinary project edits.
function M.checkProposedRecipeStates(previous,project)
	local oldStates,pending={},{}
	local function collect(target,recipe,label,key)
		if recipe and recipe.initialState then target[#target+1]={state=recipe.initialState,recipe=recipe,label=label,key=key} end
	end
	if previous and previous.startingItem==project.startingItem then
		collect(oldStates,previous.nativeRecipe,"Primary recipe","primary")
		for _,entry in ipairs(previous.recipeAlternatives or {}) do collect(oldStates,entry.recipe,entry.name,"alternative:"..entry.name) end
	end
	collect(pending,project.nativeRecipe,"Primary recipe","primary")
	for _,entry in ipairs(project.recipeAlternatives or {}) do collect(pending,entry.recipe,entry.name,"alternative:"..entry.name) end
	local changed={}
	for _,entry in ipairs(pending) do
		local same=false
		if type(entry.state)=="table" then for _,old in ipairs(oldStates) do
			if entry.key==old.key and type(old.state)=="table" and tableDeepEquals(entry.recipe,old.recipe) and tableDeepEquals(old.recipe,entry.recipe) then same=true;break end
		end end
		if not same then changed[#changed+1]=entry end
	end
	if #changed==0 then return end
	local sim=require("Modules.CraftingSimulator");local ok,model=pcall(sim.model,project.startingItem)
	assert(ok,"Cannot verify new recipe starting states for this item. Correct the item or remove the states before proposing the project.")
	for _,entry in ipairs(changed) do
		local valid=type(entry.state)=="table" and pcall(sim.validateState,model,copyTable(entry.state))
		assert(valid,entry.label.." has an invalid starting state for this item. Reset or replace it before proposing the project.")
	end
end

function M.new(build)
	local self = {projects={},build=build}
	function self:Load(xml)
		local raw = table.concat(xml)
		if raw:match("^%s*$") then return end
		local ok,projects = pcall(function()
			local decoded = assert(json.decode(raw,1,json.null),"Invalid crafting project data")
			assert(decoded.schemaVersion == 1 and type(decoded.projects) == "table" and decoded.projects ~= json.null,"Unsupported crafting project data")
			local meta=getmetatable(decoded.projects)
			assert(not meta or meta.__jsontype ~= "object","Crafting projects must be an array")
			for key in pairs(decoded.projects) do assert(type(key)=="number" and key==math.floor(key) and key>=1 and key<=#decoded.projects,"Crafting projects must be an array") end
			local result,ids = {},{}
			for _,project in ipairs(decoded.projects) do local entry=M.validate(project); assert(not ids[entry.id],"Duplicate crafting project ID"); ids[entry.id]=true; result[#result+1]=entry end
			return result
		end)
		if ok then self.projects=projects else self.unreadable=raw; self.warning="Crafting metadata could not be read. It is preserved unchanged when saving." end
	end
	function self:Save(xml)
		if self.unreadable then xml[#xml+1]=self.unreadable
		elseif #self.projects > 0 then xml[#xml+1]=require("Modules.PlanningData").encodeExact({schemaVersion=1,projects=self.projects}) end
	end
	function self:Upsert(project)
		assert(not self.unreadable,self.warning)
		local entry=M.validate(project)
		assert(build.itemsTab.slots[entry.slot],"Unknown project equipment slot")
		local start=M.item(entry.startingItem)
		assert(build.itemsTab:IsItemValidForSlot(start,entry.slot),"Starting item cannot use this slot")
		for _,item in ipairs(entry.inventory or {}) do
			assert(build.itemsTab.slots[item.slot] and build.itemsTab:IsItemValidForSlot(M.item(item.state.baseItem or item.baseItem),item.slot),"Inventory item cannot use its equipment slot")
		end
		if entry.targetItem and entry.targetItem ~= "" then
			local target=M.item(entry.targetItem)
			assert(target.type == start.type and build.itemsTab:IsItemValidForSlot(target,entry.slot),"Crafting target must use the same item class and equipment slot")
		end
		local replacement=M.copy(self.projects)
		local found=false
		for index,existing in ipairs(replacement) do if existing.id == entry.id then
			if not entry.run and existing.run and entry.startingItem==existing.startingItem then entry.run=copyTable(existing.run) end
			if project.originNote==nil and existing.originNote and entry.startingItem==existing.startingItem then entry.originNote=existing.originNote end
			if project.primarySimulation==nil and existing.primarySimulation then entry.primarySimulation=copyTable(existing.primarySimulation) end
			if project.inventory==nil and existing.inventory then entry.inventory=copyTable(existing.inventory) end
			if project.recipeAlternatives==nil and existing.recipeAlternatives then entry.recipeAlternatives=copyTable(existing.recipeAlternatives) end
			M.checkStartingStateChange(existing,entry)
			replacement[index]=entry; found=true; break
		end end
		if not found then replacement[#replacement+1]=entry end
		self.projects=replacement;self.notice=nil; build.modFlag=true
		require("Modules.PlanningUI").kept(build,"crafting")
		return entry
	end
	function self:References(id)
		local result={}
		for _,collection in ipairs({"wishlist","milestones"}) do for _,entry in ipairs(build.savers.BuildJourney.data[collection]) do if entry.projectId==id then result[#result+1]={id=entry.id,title=entry.title} end end end
		return result
	end
	function self:Remove(id)
		assert(not self.unreadable,self.warning)
		local replacement=M.copy(self.projects);local removed,index
		for i,entry in ipairs(replacement) do if entry.id==id then removed=table.remove(replacement,i);index=i;break end end
		assert(removed,"Unknown crafting project")
		local ui=require("Modules.PlanningUI")
		local pending=ui.hasDraft(build,"workingCraft",id)
		local qualityPending=ui.hasDraft(build,"uniqueQuality",id)
		require("Modules.CraftingAnalysis").forget(build,id)
		local qualityDraft=build.planningWorkspace and build.planningWorkspace:UniqueQualityDraft(id) or build.planningUniqueQualityDrafts and build.planningUniqueQualityDrafts[id]
		local draft=build.planningWorkspace and build.planningWorkspace:ForgetCraftingProject(id)
		if build.planningUniqueQualityDrafts then build.planningUniqueQualityDrafts[id]=nil end
		self.lastRemoved={project=removed,index=index,draft=draft,qualityDraft=qualityDraft and copyTable(qualityDraft),qualityPending=qualityPending,pending=pending}
		self.projects=replacement;ui.discard(build,"workingCraft",id);ui.discard(build,"uniqueQuality",id);ui.kept(build,"crafting");build.modFlag=true
		self.notice="Removed project: "..removed.title..". Use Undo removal to restore."
		return removed
	end
	function self:UndoRemove()
		assert(not self.unreadable,self.warning)
		local removed=assert(self.lastRemoved,"No removed project to restore")
		for _,entry in ipairs(self.projects) do assert(entry.id~=removed.project.id,"A project with this ID already exists; undo will not replace it") end
		local entry=self:Upsert(removed.project)
		for i,project in ipairs(self.projects) do if project.id==entry.id then table.remove(self.projects,i);break end end
		table.insert(self.projects,math.min(removed.index,#self.projects+1),entry)
		if removed.draft then
			if build.planningWorkspace then build.planningWorkspace.craftDrafts[entry.id]=copyTable(removed.draft)
			else build.planningCraftDrafts=build.planningCraftDrafts or {};build.planningCraftDrafts[entry.id]=copyTable(removed.draft) end
		end
		if removed.qualityDraft then build.planningUniqueQualityDrafts=build.planningUniqueQualityDrafts or {};build.planningUniqueQualityDrafts[entry.id]=copyTable(removed.qualityDraft) end
		if removed.qualityPending then require("Modules.PlanningUI").draft(build,"uniqueQuality",entry.id) end
		if removed.pending then require("Modules.PlanningUI").draft(build,"workingCraft",entry.id) end
		self.lastRemoved=nil;self.notice="Restored project: "..entry.title..". Use build Save to persist."
		return entry,removed.draft
	end
	return self
end

function M.handoff(raw)
	local item = M.item(raw)
	local warnings,lines = {},{}
	local advanced = raw:match("Item Class:") and raw:match("{[^\n]*Modifier")
	if advanced then
		return {url=M.home.."&eimport="..urlEncode(raw:gsub("\r\n","\n"):gsub("\n","\r\n")),mode="advanced-item",itemText=raw,
			warnings={"Check the imported base, modifiers, item level, influences and patch in Craft of Exile before simulating."}}
	end
	-- CoE requires game-format headers. Never imply a lossy modifier transfer was exact.
	local rarity = item.rarity:lower():gsub("^%l",string.upper)
	lines={"Rarity: "..rarity,item.title or item.baseName}
	if item.title then lines[#lines+1]=item.baseName end
	lines[#lines+1]="--------"
	lines[#lines+1]="Item Level: "..tostring(item.itemLevel or 1)
	lines[#lines+1]="--------"
	for _,info in ipairs(itemLib.influenceInfo.all) do if item[info.key] then lines[#lines+1]=info.display.." Item" end end
	warnings[#warnings+1]="Base-only handoff: existing modifiers, quality and special states are not transferred. Paste an advanced in-game copy in Craft of Exile to transfer the full item."
	if not item.itemLevel then warnings[#warnings+1]="Item level is unknown; the handoff uses level 1. Set the actual item level in Craft of Exile." end
	local paste = table.concat(lines,"\r\n")
	return {url=M.home.."&eimport="..urlEncode(paste),mode="base-only",itemText=paste,warnings=warnings}
end

function M.inspect(raw,query,limit)
	local item=M.item(raw)
	query=(query or ""):lower(); limit=math.min(limit or 30,100)
	local matches,total = {},0
	for id,mod in pairsSortByKey(item.affixes or { }) do
		local lines=table.concat(mod," / ")
		if (id.." "..lines):lower():find(query,1,true) and (not item.itemLevel or (mod.level or 0) <= item.itemLevel) and item:CanHaveMod(mod) then
			total=total+1
			if #matches < limit then matches[#matches+1] = {id=id,text=lines,type=mod.type,level=mod.level,group=mod.group,tags=mod.modTags,spawnWeight=item:GetModSpawnWeight(mod)} end
		end
	end
	return {base=item.baseName,itemLevel=item.itemLevel,rarity=item.rarity,total=total,matches=matches,handoff=M.handoff(raw),
		limitations={"This is PoB's item-editor affix pool, not Craft of Exile's probability engine.","Spawn weights are not success probabilities. Method-specific pools, existing group blocking, fractures, crafted modifiers and special rules require simulator validation.","If item level is unknown, listed modifier levels are not filtered. Unique off-base pools may not have a meaningful spawn weight."}}
end

-- Summarize actual saved-project changes before a candidate is applied.
function M.reviewChanges(before,after)
	local summary,details={},{}
	local function same(a,b)
		if type(a)=="table" and type(b)=="table" then return tableDeepEquals(a,b) and tableDeepEquals(b,a) end
		return a==b
	end
	local function value(v) if v==nil then return "(not saved)" end;if type(v)=="table" then return json.encode(v) end;if v=="" then return "(empty)" end;return tostring(v) end
	for _,field in ipairs({{"title","Name"},{"slot","Slot"},{"preferredMethod","Preferred action"},{"notes","Notes"},{"originNote","Source note"},{"estimate","Cost estimate"},{"simulation","Supplied simulation"},{"primarySimulation","Primary simulation defaults"}}) do
		local key,label=field[1],field[2]
		local function format(v)
			if not v then return "(not saved)" end
			if key=="primarySimulation" then return v.trials.." trials, "..v.maxActions.." actions, seed "..v.seed end
			if key=="estimate" then return v.amount.." "..v.currency.." | "..v.source.." | quoted "..v.quotedAt end
			if key=="simulation" then return v.successes.." / "..v.trials.." successes | patch "..v.patch.." | observed "..v.observedAt end
			return value(v)
		end
		if not same(before[key],after[key]) then summary[#summary+1]=label..": "..format(before[key]).." -> "..format(after[key]) end
	end
	local oldNotes=before.simulation and before.simulation.notes
	local newNotes=after.simulation and after.simulation.notes
	if oldNotes~=newNotes then details[#details+1]="Supplied simulation notes: "..value(oldNotes).." -> "..value(newNotes) end
	for _,field in ipairs({{"startingItem","Starting item"},{"targetItem","Target item"}}) do
		local key,label=field[1],field[2];if before[key]~=after[key] then summary[#summary+1]=label.." changed";details[#details+1]=label.." before: "..value(before[key]);details[#details+1]=label.." after: "..value(after[key]) end
	end
	if before.simulatorExport~=after.simulatorExport then summary[#summary+1]="External simulator attachment changed ("..#(before.simulatorExport or "").." -> "..#(after.simulatorExport or "").." bytes)." end
	local function indexed(label,old,new,format)
		for index=1,math.max(#old,#new) do local a,b=old[index],new[index]
			if not same(a,b) then
				if a and not b then summary[#summary+1]="Removed "..label.." "..index..": "..format(a)
				elseif b and not a then summary[#summary+1]="Added "..label.." "..index..": "..format(b)
				else summary[#summary+1]="Changed "..label.." "..index..": "..format(a).." -> "..format(b) end
			end
		end
	end
	indexed("goal",before.goals,after.goals,tostring)
	local function guide(step)
		return (step.done and "[done] " or "[todo] ")..step.action..(step.stopWhen and step.stopWhen~="" and " | Stop: "..step.stopWhen or "")..(step.onFailure and step.onFailure~="" and " | On failure: "..step.onFailure or "")..(step.uniqueCraft and " | Linked action: "..json.encode(step.uniqueCraft) or "")
	end
	indexed("guide step",before.steps,after.steps,guide)
	local function recipeStep(step)
		local simulator=require("Modules.CraftingSimulator");local parts={simulator.labels[step.method] or step.method}
		for key in pairsSortByKey(step) do if key~="method" then parts[#parts+1]=key..": "..value(step[key]) end end
		return table.concat(parts," | ")
	end
	local function recipe(label,a,b)
		if same(a,b) then return end
		summary[#summary+1]=label..(not a and " added" or not b and " removed" or " changed")
		if a and b then
			indexed(label.." step",a.steps,b.steps,recipeStep)
			for _,field in ipairs({"targets","requirements","requiredGroups","rarity","initialState"}) do if not same(a[field],b[field]) then details[#details+1]=label.." "..field..": "..value(a[field]).." -> "..value(b[field]) end end
		else
			local selected=b or a;local side=b and "after" or "before"
			for index,step in ipairs(selected.steps) do details[#details+1]=label.." "..side.." step "..index..": "..recipeStep(step) end
			for _,field in ipairs({"targets","requirements","requiredGroups","rarity","initialState"}) do if selected[field]~=nil then details[#details+1]=label.." "..side.." "..field..": "..value(selected[field]) end end
		end
	end
	recipe("Primary recipe",before.nativeRecipe,after.nativeRecipe)
	local oldAlt,newAlt={},{};for _,entry in ipairs(before.recipeAlternatives or {}) do oldAlt[entry.name]=entry end;for _,entry in ipairs(after.recipeAlternatives or {}) do newAlt[entry.name]=entry end
	for _,entry in ipairs(after.recipeAlternatives or {}) do local prior=oldAlt[entry.name]
		if not prior then recipe("Alternative recipe '"..entry.name.."'",nil,entry.recipe)
		else
			if prior.trackPickups~=entry.trackPickups then summary[#summary+1]="Alternative pickup tracking for "..entry.name..": "..value(prior.trackPickups).." -> "..value(entry.trackPickups) end
			recipe("Alternative recipe '"..entry.name.."'",prior.recipe,entry.recipe)
		end
	end
	for _,entry in ipairs(before.recipeAlternatives or {}) do if not newAlt[entry.name] then recipe("Alternative recipe '"..entry.name.."'",entry.recipe,nil) end end
	local function order(label,a,b,key)
		local old,new={},{};for _,entry in ipairs(a or {}) do old[#old+1]=entry[key] end;for _,entry in ipairs(b or {}) do new[#new+1]=entry[key] end
		if #old==#new then local oldSet,newSet={},{};for _,id in ipairs(old) do oldSet[id]=true end;for _,id in ipairs(new) do newSet[id]=true end
			if same(oldSet,newSet) and table.concat(old,"\0")~=table.concat(new,"\0") then summary[#summary+1]="Reordered "..label..": "..table.concat(old,", ").." -> "..table.concat(new,", ") end
		end
	end
	order("alternative recipes",before.recipeAlternatives,after.recipeAlternatives,"name")
	order("saved items",before.inventory,after.inventory,"id")
	local oldItems,newItems={},{};for _,entry in ipairs(before.inventory or {}) do oldItems[entry.id]=entry end;for _,entry in ipairs(after.inventory or {}) do newItems[entry.id]=entry end
	for _,entry in ipairs(after.inventory or {}) do local prior=oldItems[entry.id]
		if not prior then summary[#summary+1]="Added saved item: "..entry.title.." ["..entry.id.."]";details[#details+1]="Saved item "..entry.id.." base: "..entry.baseItem;details[#details+1]="Saved item "..entry.id.." state: "..json.encode(entry.state);if entry.originNote then details[#details+1]="Saved item "..entry.id.." source note: "..entry.originNote end
		elseif not same(prior,entry) then
			summary[#summary+1]="Changed saved item: "..prior.title.." -> "..entry.title.." ["..entry.id.."]"
			for _,field in ipairs({"slot","baseItem","at","state","originNote"}) do if not same(prior[field],entry[field]) then details[#details+1]="Saved item "..entry.id.." "..field..": "..value(prior[field]).." -> "..value(entry[field]) end end
		end
	end
	for _,entry in ipairs(before.inventory or {}) do if not newItems[entry.id] then summary[#summary+1]="Removed saved item: "..entry.title.." ["..entry.id.."]" end end
	if not same(before.run,after.run) then
		summary[#summary+1]="Working craft checkpoint "..(not before.run and "added" or not after.run and "removed" or "changed").."."
		if before.run and after.run then
			local fields={};for key in pairs(before.run) do fields[key]=true end;for key in pairs(after.run) do fields[key]=true end
			local changed={};for key in pairsSortByKey(fields) do if not same(before.run[key],after.run[key]) then changed[#changed+1]=key end end
			if #changed>0 then details[#details+1]="Working craft fields changed: "..table.concat(changed,", ") end
			if not same(before.run.state,after.run.state) then details[#details+1]="Working craft state: "..value(before.run.state).." -> "..value(after.run.state) end
		end
	end
	if not same(before.priceBook,after.priceBook) then
		summary[#summary+1]="Resource price book "..(not before.priceBook and "added" or not after.priceBook and "removed" or "changed")
		local a,b=before.priceBook or {},after.priceBook or {}
		for _,field in ipairs({"currency","source","quotedAt"}) do if not same(a[field],b[field]) then details[#details+1]="Price "..field..": "..value(a[field]).." -> "..value(b[field]) end end
		local keys={};for key in pairs(a.values or {}) do keys[key]=true end;for key in pairs(b.values or {}) do keys[key]=true end
		for key in pairsSortByKey(keys) do local x,y=(a.values or {})[key],(b.values or {})[key];if x~=y then details[#details+1]="Price "..key..": "..value(x).." -> "..value(y) end end
	end
	for _,line in ipairs(details) do summary[#summary+1]=line end
	return summary
end

function M.lines(project)
	local lines={project.title.." | "..project.slot,"Starting item: "..M.item(project.startingItem).baseName,"Target modifiers"}
	for _,goal in ipairs(project.goals) do lines[#lines+1]="- "..goal end
	lines[#lines+1]="Crafting plan (proposed steps; validate the method and costs)"
	for index,step in ipairs(project.steps) do
		lines[#lines+1]=string.format("%d. [%s] %s",index,step.done and "done" or "todo",step.action)
		if step.stopWhen and step.stopWhen ~= "" then lines[#lines+1]="   Stop when: "..step.stopWhen end
		if step.onFailure and step.onFailure ~= "" then lines[#lines+1]="   On failure: "..step.onFailure end
	end
	if project.priceBook then
		local quote=project.priceBook;local count=0;for _ in pairs(quote.values) do count=count+1 end
		lines[#lines+1]=string.format("Resource quotes: %d in %s | %s | %s",count,quote.currency,quote.source,os.date("%Y-%m-%d",quote.quotedAt))
	end
	if project.estimate then local q=project.estimate; lines[#lines+1]=string.format("Estimated total: %.2f %s | %s | quote age %.0fh",q.amount,q.currency,q.source,math.max(0,os.time()-q.quotedAt)/3600) end
	if project.simulation then local s=project.simulation; lines[#lines+1]=string.format("Supplied CoE result: %.0f / %.0f successes | patch %s | observed %.0fh ago",s.successes,s.trials,s.patch,math.max(0,os.time()-s.observedAt)/3600); lines[#lines+1]="External result recorded as supplied; PoB has not rerun or verified this simulation." end
	if project.simulatorExport and project.simulatorExport ~= "" then lines[#lines+1]="Simulator export attached for manual import into Craft of Exile; never executed by PoB." end
	if project.nativeRecipe then
		lines[#lines+1]="Native recipe: "..#project.nativeRecipe.steps.." steps. Open Native crafting to simulate it."
		local edges=require("Modules.CraftingRoutes").edges(project.nativeRecipe)
		local function destination(edge)
			if edge.label=="Restart" then return "restart with starting item at step 1" end
			if edge.label=="Stop" then return "stop" end
			if edge.label=="Salvage" then return "salvage and stop" end
			return edge.target>#project.nativeRecipe.steps and "finish" or "step "..edge.target
		end
		for index,step in ipairs(project.nativeRecipe.steps) do
			lines[#lines+1]=string.format("%d. %s%s | attempts %d | success -> %s | failure -> %s",index,step.method,step.modId and " ("..step.modId..")" or step.essenceId and " ("..step.essenceId..")" or "",step.maxAttempts or 1,destination(edges[index*2-1]),destination(edges[index*2]))
			if step.untilTargets then lines[#lines+1]=string.format("   Step target groups: %d of %d required",step.untilRequiredGroups or #step.untilTargets,#step.untilTargets) end
		end
	end
	for _,alternative in ipairs(project.recipeAlternatives or {}) do lines[#lines+1]="Alternative recipe: "..alternative.name.." ("..#alternative.recipe.steps.." steps"..(alternative.trackPickups and "; filter pickups tracked" or "")..")" end
	if project.originNote and project.originNote ~= "" and project.originNote ~= project.notes then lines[#lines+1]="Source: "..project.originNote end
	if project.notes and project.notes ~= "" then lines[#lines+1]=project.notes end
	return lines
end

return M
