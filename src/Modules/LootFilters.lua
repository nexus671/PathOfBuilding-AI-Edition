-- Build-owned visual filter profiles; pinned base filters stay outside build XML.
-- cspell:ignore jsontype
local json=require("dkjson")
local parser=require("Modules.LootFilterParser")
local M={limit=2*1024*1024,strictness={"Soft","Regular","Semi-strict","Strict","Very strict","Uber strict","Uber plus strict"}}
local cache={}
local recipeResourceCache,recipeResourceOrder={},{}
local craftingResourceNames
local function craftingResources()
	if not craftingResourceNames then
		local file=assert(io.open("Assets/Crafting/currencies.json","rb"));local raw=file:read("*a");file:close()
		local catalog=assert(json.decode(raw));craftingResourceNames={}
		for _,item in pairs(catalog.items) do craftingResourceNames[item.name]=true end
	end
	return craftingResourceNames
end
-- Prefer a longer known item name when names overlap, and do not match a
-- word inside a larger word. Matches are collected before rules are created.
local function mentionedItems(text,names,found)
	local lower=text:lower();local occupied={}
	local function word(char) return char~="" and char:match("[%w_]")~=nil end
	for _,name in ipairs(names) do
		local needle=name:lower();local offset=1
		while true do
			local first,last=lower:find(needle,offset,true);if not first then break end
			local finish=last
			if lower:sub(last+1,last+1)=="s" and not word(lower:sub(last+2,last+2)) then finish=last+1 end
			local overlap=false;for i=first,finish do if occupied[i] then overlap=true;break end end
			if not overlap and not word(lower:sub(first-1,first-1)) and not word(lower:sub(finish+1,finish+1)) then
				found[name]=true;for i=first,finish do occupied[i]=true end
			end
			offset=first+1
		end
	end
end
local function read(name)
	if not cache[name] then local f=assert(io.open("Data/LootFilters/"..name,"rb"));cache[name]=f:read("*a");f:close() end
	return cache[name]
end
function M.source() return assert(json.decode(read("source.json"))) end
function M.patch() return assert(json.decode(read("patch-3.30.json"))) end
function M.needsSafety(profile) return profile.template~=nil or M.source().nativePatch~="3.30" end
local function text(value,limit,label)
	assert(type(value)=="string" and #value<=limit and not value:find("\0"),"Invalid "..label);return value
end
local function array(value)
	assert(type(value)=="table" and value~=json.null,"Expected array")
	assert(not getmetatable(value) or getmetatable(value).__jsontype~="object","Expected array")
	for k in pairs(value) do assert(type(k)=="number" and k==math.floor(k) and k>=1 and k<=#value,"Expected dense array") end
	return value
end
local function quote(value) assert(not value:find('["\r\n]'),"Filter values cannot contain quotes or newlines");return '"'..value..'"' end
M.quote=quote
function M.empty() return {schemaVersion=1,activeId="",profiles={}} end
function M.profile(id,title,preset)
	return {id=id,title=title,preset=preset or "early_maps",strictness=preset=="campaign" and 1 or preset=="endgame" and 4 or 2,theme="default",mode="Normal",baseCommit=M.source().commit,rules={}}
end
function M.validate(data)
	assert(type(data)=="table" and data.schemaVersion==1,"Unsupported loot-filter data")
	local result=M.empty();result.activeId=text(data.activeId or "",64,"active filter");local ids={}
	for _,p in ipairs(array(data.profiles)) do
		local entry={id=text(p.id,64,"profile ID"),title=text(p.title,120,"profile title"),preset=p.preset,strictness=p.strictness,theme=p.theme or "default",mode=p.mode or "Normal",rules={}}
		assert(entry.id:match("^[%w_-]+$") and not ids[entry.id] and entry.title:match("%S") and not entry.title:find("[%c]"),"Invalid or duplicate filter ID/title");ids[entry.id]=true
		assert(entry.preset=="campaign" or entry.preset=="early_maps" or entry.preset=="endgame","Unknown progression preset")
		assert(type(p.strictness)=="number" and p.strictness==math.floor(p.strictness) and p.strictness>=0 and p.strictness<=6,"Strictness must be 0 to 6")
		assert(entry.theme=="default" or entry.theme=="contrast","Unknown filter theme")
		assert(entry.mode=="Normal" or entry.mode=="Ruthless","Unknown filter mode")
		if p.appearance~=nil then
			entry.appearance=require("Modules.LootFilterAppearanceSettings").validate(p.appearance)
		end
		if p.campaign~=nil then entry.campaign=require("Modules.LootFilterCampaign").validate(p.campaign) end
		if p.sampleSets~=nil then entry.sampleSets=require("Modules.LootFilterCollections").sampleSets(p.sampleSets) end
		if p.palettes~=nil then entry.palettes=require("Modules.LootFilterCollections").palettes(p.palettes) end
		if p.categoryStyles~=nil then entry.categoryStyles=require("Modules.LootFilterCategoryStyles").validate(p.categoryStyles) end
		entry.baseCommit=p.baseCommit and text(p.baseCommit,40,"template revision") or M.source().commit
		if p.template then entry.template=text(p.template,M.limit,"imported filter");local parsed=parser.parse(p.template);assert(#parsed.rules>0 or #parsed.imports>0,"Imported filter has no rules or imports") end
		if p.importFiles~=nil then
			entry.importFiles={};local names={}
			for _,file in ipairs(array(p.importFiles)) do
				assert(type(file)=="table","Invalid imported filter file")
				local name=text(file.name,240,"import filename");assert(name:match("%S") and not name:find('[%c"]') and not names[name],"Invalid or duplicate import filename");names[name]=true
				entry.importFiles[#entry.importFiles+1]={name=name,text=text(file.text,M.limit,"imported filter text")}
			end
		end
		local seen={}
		for _,rule in ipairs(array(p.rules)) do
			local r={id=text(rule.id,100,"rule ID"),title=text(rule.title,160,"rule title"),text=text(rule.text,24000,"rule text"),enabled=rule.enabled~=false}
			assert(r.id:match("^[%w_-]+$") and not seen[r.id] and not r.title:find("[%c]"),"Invalid or duplicate rule ID/title");seen[r.id]=true
			local parsed=parser.parse(r.text);assert(#parsed.rules==1 and #parsed.imports==0,"Use exactly one Show/Hide/Minimal block per personal rule")
			for _,d in ipairs(parsed.diagnostics) do assert(not d.error,d.error) end
			if rule.origin then r.origin=text(rule.origin,240,"rule origin");assert(not r.origin:find("[%c]"),"Invalid rule origin") end
			entry.rules[#entry.rules+1]=r
		end
		result.profiles[#result.profiles+1]=entry
		if p.tiers~=nil then entry.tiers=require("Modules.LootFilterEditing").validateTiers(p.tiers) end
		if p.modules~=nil then entry.modules=require("Modules.LootFilterEditing").validateModules(p.modules) end
	end
	assert(result.activeId=="" or ids[result.activeId],"Active loot filter is missing")
	assert(#json.encode(result)<=M.limit,"Loot-filter metadata exceeds 2 MiB");return result
end
function M.find(data,id) for _,p in ipairs(data.profiles) do if p.id==(id or data.activeId) then return p end end end
local themes={default={text="255 235 175",border="105 195 245",background="20 30 45",sound="2"},contrast={text="255 255 255",border="255 220 0",background="0 0 0",sound="6"}}
function M.rule(id,title,conditions,origin,theme)
	local style=themes[theme or "default"];local lines={"Show"}
	for _,c in ipairs(conditions) do lines[#lines+1]="    "..c end
	for _,pair in ipairs({{"SetTextColor",style.text},{"SetBorderColor",style.border},{"SetBackgroundColor",style.background},{"SetFontSize","42"},{"PlayAlertSound",style.sound.." 200"},{"MinimapIcon","1 Cyan Diamond"},{"PlayEffect","Cyan"}}) do lines[#lines+1]="    "..pair[1].." "..pair[2] end
	return {id=id,title=title,text=table.concat(lines,"\n"),enabled=true,origin=origin}
end
function M.generate(build,profile,checkpoint)
	local result={};local used={};local ids={};local warnings={};local recipeModels={}
	local sliceStart=os.clock()
	local function checkpointIfNeeded()
		if checkpoint and os.clock()-sliceStart>=0.008 then checkpoint();sliceStart=os.clock() end
	end
	for _,rule in ipairs(profile.rules) do if not rule.origin then ids[rule.id]=true end end
	local function add(id,title,conditions,origin)
		-- Identical pickups can belong to different plans. Keep each source
		-- linked, while collapsing repeated requirements within that source.
		local signature=(origin or "").."\0"..table.concat(conditions,"\n");if used[signature] then return end;used[signature]=true
		local base=id;local suffix=1;while ids[id] do suffix=suffix+1;id=base.."-"..suffix end;ids[id]=true
		result[#result+1]=M.rule(id,title,conditions,origin,profile.theme)
	end
	local function base(raw,id,title,origin)
		local ok,item=pcall(require("Modules.CraftingProjects").item,raw or "")
		if not ok then return false end
		local baseName=item.baseName;local conditions
		local uniqueTarget=item.rarity=="UNIQUE"
		if item.type == "Viscera" or item.type and item.type:match("^Wickerman ") then
			-- GGG's filter list names the underlying Viscera base without its
			-- Lesser/Greater display prefix. Do not apply equipment rarity tests.
			local canonical=baseName:gsub("^Lesser ",""):gsub("^Greater ","")
			local known=false;for _,name in ipairs(M.patch().added.Viscera or {}) do if name==canonical then known=true;break end end
			if not known then return false end
			conditions={"Class == \"Viscera\"","BaseType == "..quote(canonical)}
		else conditions={"BaseType == "..quote(baseName),uniqueTarget and "Rarity == Unique" or "Rarity <= Rare"} end
		-- A copied unique's item level describes that particular copy, not the
		-- minimum level of another drop of the same unique.
		local level=not uniqueTarget and tonumber((raw or ""):match("Item Level: (%d+)")) or nil
		if level then conditions[#conditions+1]="ItemLevel >= "..level end
		if type(id)=="function" then id=id(item,level) end
		if type(title)=="function" then title=title(item) end
		add(id,title,conditions,origin)
		return true
	end
	local function preserveBase(origin,id,title,description)
		warnings[#warnings+1]={origin=origin,title=title,message="Could not read "..description..". Previous base pickups were kept; review the saved item."}
		for _,rule in ipairs(profile.rules) do
			local suffix=rule.id:sub(#id+1)
			if rule.origin==origin and rule.id:sub(1,#id)==id and (suffix=="" or suffix:match("^%-%d+$")) and not ids[rule.id] then
				result[#result+1]=copyTable(rule);ids[rule.id]=true
			end
		end
	end
	for _,p in ipairs(build.savers.CraftingProjects.projects) do
		local origin="craft:"..p.id;local id="craft-"..p.id
		if not base(p.startingItem,id,p.title.." base",origin) then preserveBase(origin,id,p.title,"the crafting base") end
		local initial=p.nativeRecipe and p.nativeRecipe.initialState
		if initial and initial.baseItem then
			local workingId="craft-working-"..p.id
			if checkpoint and not recipeModels[p.startingItem] then require("Modules.CraftingAdvanced").prepare(checkpoint) end
			local ok=pcall(function()
				local sim=require("Modules.CraftingSimulator");local model=recipeModels[p.startingItem]
				if not model then model=sim.model(p.startingItem);recipeModels[p.startingItem]=model end
				local state=sim.validateState(model,initial);assert(state.baseItem and sim.context(model,state).item.baseName)
				assert(base(state.baseItem,workingId,p.title.." recipe starting base",origin),"Invalid recipe starting base")
			end)
			if not ok then preserveBase(origin,workingId,p.title,"the recipe starting base") end
		end
		if p.targetItem and p.targetItem:match("%S") then
			local targetId="craft-target-"..p.id
			local ok,target=pcall(require("Modules.CraftingProjects").item,p.targetItem)
			if not ok then preserveBase(origin,targetId,p.title,"the crafting target")
			elseif target.rarity=="UNIQUE" then base(p.targetItem,targetId,p.title.." unique target",origin) end
		end
		local invalidDonor=false
		for _,step in ipairs(p.nativeRecipe and p.nativeRecipe.steps or {}) do
			if (step.method=="awakener" or step.method=="recombine" or step.method=="recombine_predictable") and step.donorItem and step.donorItem~="" then
				local ok=base(step.donorItem,function(item,level) return "craft-donor-"..p.id.."-"..require("sha1")(item.baseName..":"..tostring(level or 0)):sub(1,12) end,function(item) return "Donor base: "..item.baseName end,origin)
				invalidDonor=invalidDonor or not ok
			end
		end
		if invalidDonor then
			warnings[#warnings+1]={origin=origin,title=p.title,message="Could not read a configured donor base. Previous donor pickups were kept; review the crafting guide."}
			for _,rule in ipairs(profile.rules) do if rule.origin==origin and rule.id:match("^craft%-donor%-") and not ids[rule.id] then result[#result+1]=copyTable(rule);ids[rule.id]=true end end
		end
		checkpointIfNeeded()
	end
	for _,e in ipairs(build.savers.BuildJourney.data.wishlist) do
		if e.status=="planned" and e.targetItem and e.targetItem:match("%S") then
			local origin="gear:"..e.id;local id="gear-"..e.id
			if not base(e.targetItem,id,e.title.." base",origin) then preserveBase(origin,id,e.title,"the gear target") end
		end
		checkpointIfNeeded()
	end
	for i,group in ipairs(build.skillsTab.socketGroupList) do
		local slot=group.slot and build.itemsTab.slots[group.slot]
		local activeWeaponSet=build.itemsTab.activeItemSet.useSecondWeaponSet and 2 or 1
		if group.enabled~=false and (not slot or not slot.weaponSet or slot.weaponSet==activeWeaponSet) then
			local socketCount=0
			for j,gem in ipairs(group.gemList) do if gem.enabled~=false and gem.nameSpec and gem.nameSpec~="" then
				local name=gem.nameSpec
				if gem.gemData and gem.gemData.tags and gem.gemData.tags.support and not name:match(" Support$") then name=name.." Support" end
				add("gem-"..i.."-"..j,gem.nameSpec,{"Class == \"Skill Gems\" \"Support Gems\"","BaseType == "..quote(name)},"gems")
				local data=gem.grantedEffect or gem.gemData and gem.gemData.grantedEffect;local color=data and data.color;if type(color)=="number" then color=({"R","G","B","W"})[color] end
				if color=="R" or color=="G" or color=="B" or color=="W" then socketCount=socketCount+1 end
			end end
			if socketCount>=2 and socketCount<=6 and profile.preset=="campaign" then
				-- Since 3.29, any ordinary socket can hold any gem colour.
				add("links-"..i,"Links for skill group "..i,{"LinkedSockets >= "..socketCount,"Rarity <= Rare"},"gems")
			end
		end
	end
	local patch=M.patch();local names={};for class,items in pairs(patch.added) do for _,name in ipairs(items) do names[name]=class end end
	local removed={};for _,name in ipairs(patch.removed) do removed[name]=true end
	-- The bundled crafting art catalogue contains item identities, unlike
	-- service names or whole-action price quotes. User-entered budget titles
	-- still need an exact name (or its simple plural) to become pickup rules.
	for name in pairs(craftingResources()) do if not removed[name] then names[name]=names[name] or "Crafting resource" end end
	-- Ordinary Atlas areas are no longer item bases in current gameplay. Keep
	-- their names for recognizing strategy text, but never create exact-base
	-- pickups from them. Special maps still have their own items.
	local specialMaps={["Abomination Map"]=true,["Citadel Map"]=true,["Fortress Map"]=true,["Sanctuary Map"]=true,["Ziggurat Map"]=true,["Vaal Temple Map"]=true,["Synthesised Map"]=true}
	local layoutNames={}
	for _,name in ipairs(assert(json.decode(read("map-names.json"))).names) do if not removed[name] then
		names[name]=names[name] or "Map";if not specialMaps[name] then layoutNames[name]=true end
	end end
	for tier=1,16 do names["Map (Tier "..tier..")"]="Map" end
	-- Map-device supplies explicitly named in a strategy are pickups too. The
	-- pinned client catalogue excludes removed and legacy non-currency variants.
	for _,name in ipairs(assert(json.decode(read("atlas-supplies-3.30.json"))).names) do if not removed[name] then names[name]=names[name] or "Atlas supply" end end
	for _,name in ipairs({"Orb of Alchemy","Chaos Orb","Divine Orb","Orb of Alteration","Orb of Augmentation","Regal Orb","Exalted Orb","Orb of Annulment","Chromatic Orb","Jeweller's Orb","Orb of Fusing","Vaal Orb"}) do names[name]="Stackable Currency" end
	-- Only concrete currency items from modeled recipe components become drops.
	-- Unknown prices, beasts and whole-service prices are not item identities.
	for _,project in ipairs(build.savers.CraftingProjects.projects) do if project.nativeRecipe then
		local key=require("sha1")(project.startingItem.."\0"..require("Modules.PlanningData").encode(project.nativeRecipe))
		local coverage=recipeResourceCache[key];local needsInspection=not coverage;local ok=true
		if not coverage and checkpoint then require("Modules.CraftingAdvanced").prepare(checkpoint) end
		if not coverage then ok,coverage=pcall(function()
			local sim=require("Modules.CraftingSimulator");local model=recipeModels[project.startingItem]
			if not model then model=sim.model(project.startingItem);recipeModels[project.startingItem]=model end
			local state=project.nativeRecipe.initialState and sim.validateState(model,project.nativeRecipe.initialState) or model.initial
			local result={items={},unknown={}};for _,entry in ipairs(require("Modules.CraftingPrices").entries(model,state,project.nativeRecipe.steps,nil,state)) do
				if entry.required and entry.kind=="Currency" then result.items[#result.items+1]={key=entry.key,name=entry.name}
				elseif entry.required and entry.kind=="Whole action" then result.unknown[#result.unknown+1]=entry.name end
			end;return result
		end)
			if ok then recipeResourceCache[key]=coverage;recipeResourceOrder[#recipeResourceOrder+1]=key;if #recipeResourceOrder>128 then recipeResourceCache[table.remove(recipeResourceOrder,1)]=nil end end
		end
		if ok then for _,entry in ipairs(coverage.items) do if not removed[entry.name] then
			add("craft-resource-"..project.id.."-"..require("sha1")(entry.key):sub(1,12),entry.name,{"BaseType == "..quote(entry.name)},"craft:"..project.id)
		end end end
		if not ok or #coverage.unknown>0 then
			local message=not ok and "Could not inspect this recipe's resources." or "Some actions have no item ingredient breakdown: "..table.concat(coverage.unknown,", ").."."
			warnings[#warnings+1]={origin="craft:"..project.id,title=project.title,message=message.." Previous recipe pickups were kept; review the crafting guide.",retry=not ok}
			for _,rule in ipairs(profile.rules) do if rule.origin=="craft:"..project.id and rule.id:match("^craft%-resource%-") and not ids[rule.id] then result[#result+1]=copyTable(rule);ids[rule.id]=true end end
		end
		if checkpoint and needsInspection then checkpoint();sliceStart=os.clock() end
	end end
	local aliases={chaos="Chaos Orb",divine="Divine Orb",divines="Divine Orb",alchemy="Orb of Alchemy",alteration="Orb of Alteration",exalt="Exalted Orb",annul="Orb of Annulment",fusing="Orb of Fusing",chromatic="Chromatic Orb",jeweller="Jeweller's Orb"}
	for name in pairs(names) do aliases[name:lower()]=name;aliases[name:lower().."s"]=name end
	-- Exact budget entries may name currencies outside the artwork catalogue.
	-- Keep these out of free-text Atlas matching, where generic names could
	-- accidentally match an unrelated strategy description.
	local budgetNames={};for _,name in ipairs(assert(json.decode(read("budget-items-3.30.json"))).names) do
		if not removed[name] then budgetNames[name]=true;aliases[name:lower()]=name;aliases[name:lower().."s"]=name end
	end
	local renamedAliases={};for old,new in pairs(patch.renamed) do
		if (names[new] or budgetNames[new]) and not removed[new] then renamedAliases[old:lower()]=new;renamedAliases[old:lower().."s"]=new end
	end
	for _,resource in ipairs(build.savers.BuildJourney.data.resources) do
		local name=renamedAliases[resource.title:lower()] or aliases[resource.title:lower()] or resource.title
		if layoutNames[name] then
			warnings[#warnings+1]={origin="budget:"..resource.id,title=resource.title,message="This is an Atlas layout, not a current ordinary map item. Use an explicit item such as Map (Tier 16) for a tiered map pickup."}
		elseif (names[name] or budgetNames[name]) and not removed[name] then add("resource-"..resource.id,name,{"BaseType == "..quote(name)},"budget:"..resource.id) end
	end
	local strategyNames={};for name in pairs(names) do strategyNames[#strategyNames+1]=name end
	-- Older saved strategies may still use a renamed item's former name. Match
	-- both spellings, but emit and compare exclusions using the current name.
	local strategyRenames={};for old,new in pairs(patch.renamed) do if names[new] and not names[old] then strategyRenames[old]=new;strategyNames[#strategyNames+1]=old end end
	table.sort(strategyNames,function(a,b) return #a==#b and a<b or #a>#b end)
	local threadMechanics={};for _,name in ipairs(patch.added["Map Fragments"] or {}) do
		local mechanic=name:match("^(%a+) Thread$");if mechanic then threadMechanics[#threadMechanics+1]=mechanic end
	end
	table.sort(threadMechanics,function(a,b) return #a==#b and a<b or #a>#b end)
	for _,plan in ipairs(build.savers.AtlasPlans.plans) do
		local atlas=require("Modules.AtlasPlanner");local keywords,excludedThreads={},{};local graph=atlas.tree(plan.version)
		local atlasStrategy=require("Modules.AtlasStrategy")
		for _,id in ipairs(plan.nodes) do local node=graph.nodes[id];if node then
			local rule=atlasStrategy.threadRule(plan,node)
			if rule then
				if rule.kind=="exclude" then excludedThreads[rule.mechanic]=true
				elseif rule.kind=="increase" then keywords[rule.mechanic]=true end
			end
			local selected=atlasStrategy.selectedNode(plan,node)
			-- Encounter blockers mention a mechanic to turn it off, not to
			-- request that mechanic's Thread as an automatic pickup.
			if #atlasStrategy.blocking(selected)==0 then for _,mechanic in ipairs(atlasStrategy.allMechanics(selected)) do keywords[mechanic]=true end end
		end end
		local mentioned,avoided,avoidedMechanics,unmatched={},{},{},{}
		for _,field in ipairs({"scarabs","maps","avoid"}) do
			local value=plan.strategy and plan.strategy[field] or "";local found={}
			mentionedItems(value,strategyNames,found)
			if field=="avoid" then mentionedItems(value,threadMechanics,avoidedMechanics) end
			for name in pairs(found) do (field=="avoid" and avoided or mentioned)[name]=true end
			if value:match("%S") and not next(found) and not (field=="avoid" and next(avoidedMechanics)) then unmatched[#unmatched+1]=({scarabs="supplies",maps="maps",avoid="avoid"})[field] end
		end
		if #unmatched>0 then warnings[#warnings+1]={origin="atlas:"..plan.id,title=plan.title or "Atlas strategy",message="No known item name was found in the Atlas strategy's "..table.concat(unmatched,", ").." field(s). Notes are fine, but only recognized item names generate or exclude pickups."} end
		for old,new in pairs(strategyRenames) do if mentioned[old] then mentioned[new]=true end;if avoided[old] then avoided[new]=true end end
		local hasLayouts=false
		for name in pairs(layoutNames) do if mentioned[name] and not avoided[name] then hasLayouts=true;break end end
		for _,region in ipairs(plan.shapedRegions or {}) do if #(region.maps or {})>0 then hasLayouts=true;break end end
		if hasLayouts then warnings[#warnings+1]={origin="atlas:"..plan.id,title=plan.title or "Atlas strategy",message="Named Atlas layouts and Shaped Regions do not identify ordinary map drops. To highlight a specific tier, add an item such as Map (Tier 16) to the strategy; layout names do not create pickups."} end
		for _,name in ipairs(strategyNames) do if not strategyRenames[name] and not layoutNames[name] and mentioned[name] and not avoided[name] and not avoidedMechanics[name:match("^(%a+) Thread$")] then add("atlas-item-"..plan.id.."-"..require("sha1")(name):sub(1,12),name,{"BaseType == "..quote(name)},"atlas:"..plan.id) end end
		for _,name in ipairs(patch.added["Map Fragments"] or {}) do local mechanic=name:match("^(%a+) Thread$");if mechanic and keywords[mechanic] and not excludedThreads[mechanic] and not avoided[name] and not avoidedMechanics[mechanic] then add("atlas-"..plan.id.."-"..mechanic,name,{"BaseType == "..quote(name)},"atlas:"..plan.id) end end
	end
	local rules={};for _,rule in ipairs(profile.rules) do if not rule.origin then rules[#rules+1]=copyTable(rule) end end
	for _,rule in ipairs(result) do rules[#rules+1]=rule end
	return rules,warnings
end
-- Only rewrite BaseType token lists. Removing every value removes the whole rule,
-- rather than broadening a Hide block. Original imports remain saved verbatim.
function M.migrate(raw)
	local patch=M.patch();local removed={};for _,name in ipairs(patch.removed) do removed[name]=true end
	local out,block,skip,changes={}, {},false,{}
	local function flush() if not skip then for _,line in ipairs(block) do out[#out+1]=line end end;block={};skip=false end
	for line in (raw.."\n"):gmatch("([^\n]*)\n") do
		if line:match("^%s*Show%s*") or line:match("^%s*Hide%s*") or line:match("^%s*Minimal%s*") or line:match("^%s*Import%s") then flush() end
		if line:match("^%s*BaseType%s") then
			local changed=false;local quoted=false;local commentAt
			for i=1,#line do local char=line:sub(i,i);if char=='"' then quoted=not quoted elseif char=="#" and not quoted then commentAt=i;break end end
			local body=commentAt and line:sub(1,commentAt-1) or line;local comment=commentAt and line:sub(commentAt) or ""
			body=body:gsub('"([^"\r\n]+)"',function(name)
				if removed[name] then changed=true;changes[name]="removed";return "" end
				local nextName=patch.renamed[name] or name;if nextName~=name then changed=true;changes[name]=nextName end;return quote(nextName)
			end)
			line=body..comment
			if changed then local parsed=parser.parse("Show\n"..body);local condition=parsed.rules[1].conditions[1];if condition and #condition.values==0 then skip=true end end
		end
		block[#block+1]=line
	end
	flush();return table.concat(out,"\n"),changes
end
function M.base(profile)
	if profile.template then return profile.template end
	assert(profile.baseCommit==M.source().commit,"The bundled base changed. Review Audit / update before exporting this profile.")
	return read(profile.strictness..".filter")
end
function M.migratedBase(profile)
	local raw=M.base(profile)
	if profile.template then return M.migrate(require("Modules.LootFilterImports").expand(raw,profile.importFiles,M.limit)) end
	-- A reviewed native 3.30 preset already encodes the author's current rules.
	if M.source().nativePatch=="3.30" then return raw,{} end
	-- Bundled presets and the patch map are immutable until the next restart.
	local key="migrated-"..profile.strictness
	if not cache[key] then cache[key]={M.migrate(raw)} end
	return cache[key][1],copyTable(cache[key][2])
end
function M.compile(profile,includeParsed)
	local checked=M.validate({schemaVersion=1,activeId=profile.id,profiles={profile}}).profiles[1]
	local function styled(text,category) return require("Modules.LootFilterCategoryStyles").apply(text,checked.categoryStyles,category) end
	local output={"# Path of Building AI Edition | "..checked.title,"# PoE 3.30 | NeverSink base "..checked.baseCommit,"# NeverSink templates: MIT. Personal rules precede the base filter."}
	output[#output+1]="# "..read("LICENSE-NeverSink.txt"):gsub("\r\n","\n"):gsub("\n","\n# ")
	for _,r in ipairs(checked.rules) do if r.enabled then output[#output+1]="\n# PoB rule: "..r.title..(r.origin and " ["..r.origin.."]" or "");output[#output+1]=styled(r.text,r.origin and "Build targets") end end
	for _,rule in ipairs(require("Modules.LootFilterEditing").tierRules(checked.tiers)) do output[#output+1]="\n# PoB rule: Tier / "..rule.title;output[#output+1]=styled(rule.text) end
	for _,module in ipairs(checked.modules or {}) do if module.enabled then for _,rule in ipairs(module.rules) do if rule.enabled then output[#output+1]="\n# PoB rule: "..module.title.." / "..rule.title;output[#output+1]=styled(rule.text,rule.origin and "Build targets") end end end end
	for _,rule in ipairs(require("Modules.LootFilterCampaign").rules(checked.campaign,checked.theme,checked.mode)) do output[#output+1]="\n# PoB rule: Campaign / "..rule.title;output[#output+1]=styled(rule.text,"Campaign") end
	-- New league items are shown until a later pinned base can tier them.
	if M.needsSafety(checked) then
		local patch=M.patch();local classes={};for class in pairs(patch.added) do classes[#classes+1]=class end;table.sort(classes)
		for _,class in ipairs(classes) do local values={};for _,name in ipairs(patch.added[class]) do values[#values+1]=quote(name) end
			local kind=require("Modules.LootFilterLibrary").category({text='Class == "'..class..'"'})
			output[#output+1]=styled("\n# 3.30 new-item safety: "..class.."\nShow\n    BaseType == "..table.concat(values," ").."\n    SetTextColor 255 235 175\n    SetBorderColor 175 110 230\n    SetFontSize 40",kind)
		end
	end
	local base,changes=M.migratedBase(checked);output[#output+1]="\n# Pinned base filter\n"..styled(base)
	local raw=require("Modules.LootFilterDecorators").apply(table.concat(output,"\n"),checked.appearance);assert(#raw<=M.limit,"Compiled filter exceeds 2 MiB")
	if checked.mode=="Ruthless" then raw=raw:gsub("\n([ \t]*)Hide(%f[%W])","\n%1Minimal%2") end
	local parsed=parser.parse(raw)
	for _,rule in ipairs(parsed.rules) do for _,condition in ipairs(rule.conditions) do
		if parser.poe2Only[condition.keyword] then parsed.diagnostics[#parsed.diagnostics+1]={line=condition.line,error=condition.keyword.." is a Path of Exile 2-only condition; remove it for Path of Exile 1."} end
	end end
	for _,diagnostic in ipairs(require("Modules.LootFilterDiagnostics").shadowing(parsed)) do parsed.diagnostics[#parsed.diagnostics+1]=diagnostic end
	if checked.mode=="Normal" then for _,rule in ipairs(parsed.rules) do if rule.action=="Minimal" then parsed.diagnostics[#parsed.diagnostics+1]={line=rule.line,error="Minimal blocks require Ruthless mode"} end end end
	if checked.mode=="Ruthless" then for _,rule in ipairs(parsed.rules) do local text=rule.styles.SetTextColor;if text and tonumber(text[4]) and tonumber(text[4])<80 then parsed.diagnostics[#parsed.diagnostics+1]={line=rule.line,error="Ruthless text opacity must be at least 80"} end end end
	local report={changes=changes,diagnostics=parsed.diagnostics,imports=parsed.imports,unresolvedImports=require("Modules.LootFilterImports").summarize(parsed,checked.importFiles),rules=#parsed.rules,baseCommit=checked.baseCommit,currentCommit=M.source().commit,imported=checked.template~=nil}
	if includeParsed then return raw,report,parsed end
	return raw,report
end
function M.variants(profile)
	assert(not profile.template,"An imported filter has no bundled strictness variants")
	local variants={}
	for strictness=0,6 do
		local nextProfile=copyTable(profile);nextProfile.strictness=strictness
		local raw,report=M.compile(nextProfile)
		for _,d in ipairs(report.diagnostics) do assert(not d.error,d.error) end
		variants[#variants+1]={strictness=strictness,label=M.strictness[strictness+1],text=raw}
	end
	return variants
end
function M.simulate(profile,item)
	local raw,report,parsed=M.compile(profile,true)
	for _,d in ipairs(report.diagnostics) do if d.error then return {status="invalid",action="Unknown",styles={},matches={},reasons={d.error}} end end
	return parser.simulate(parsed,item)
end
-- Reuse one compiled filter for a page. Offsets are zero-based.
local function truncateUTF8(value,limit)
	if #value<=limit then return value end
	local last=limit
	while last>0 do
		local nextByte=value:byte(last+1)
		if not nextByte or nextByte<128 or nextByte>=192 then break end
		last=last-1
	end
	return value:sub(1,last)
end
local function simulatePage(profile,selected,offset,limit,checkpoint,includeSample)
	offset=offset or 0;limit=limit or 20
	local total=selected.total or #selected.samples
	assert(type(offset)=="number" and offset==math.floor(offset) and offset>=0 and offset<=total,"Invalid example offset")
	assert(type(limit)=="number" and limit==math.floor(limit) and limit>=1 and limit<=50,"Use 1 to 50 examples per page")
	local _,report,parsed=M.compile(profile,true);local invalid
	for _,diagnostic in ipairs(report.diagnostics) do if diagnostic.error then invalid=diagnostic.error;break end end
	local results={};local last=math.min(total,offset+limit)
	for i=offset+1,last do
		local sample=selected.sampleAt and selected.sampleAt(i) or selected.samples[i]
		local evaluated=invalid and {status="invalid",action="Unknown",styles={},matches={},reasons={invalid}} or parser.simulate(parsed,sample)
		-- Keep a page bounded even when an imported filter has thousands of
		-- Continue blocks or unusually long custom sound paths. The single-item
		-- evaluator remains available for complete style details.
		local summary={status=evaluated.status,action=evaluated.action,line=evaluated.line,ruleTitle=evaluated.ruleTitle and truncateUTF8(evaluated.ruleTitle,160),matches={},reasons={}}
		if evaluated.ruleTitle and #evaluated.ruleTitle>160 then summary.ruleTitleTruncated=true end
		for n=1,math.min(#(evaluated.matches or {}),30) do summary.matches[n]=evaluated.matches[n] end
		if #(evaluated.matches or {})>30 then summary.matchesTruncated=true end
		for n=1,math.min(#(evaluated.reasons or {}),10) do local reason=tostring(evaluated.reasons[n]);summary.reasons[n]=truncateUTF8(reason,240);if #reason>240 then summary.reasonsTruncated=true end end
		if #(evaluated.reasons or {})>10 then summary.reasonsTruncated=true end
		local baseType=type(sample.BaseType)=="string" and truncateUTF8(sample.BaseType,240) or nil
		results[#results+1]={index=i-1,baseType=baseType,baseTypeTruncated=baseType and #sample.BaseType>240 or nil,sample=includeSample and copyTable(sample) or nil,result=summary}
		if checkpoint then checkpoint({completed=i-offset,total=last-offset}) end
	end
	return {setId=selected.id,title=selected.title,total=total,offset=offset,nextOffset=last<total and last or nil,results=results}
end
-- Saved sets retain their existing compact result format.
function M.simulateExamples(profile,setId,offset,limit,checkpoint)
	local selected;for _,entry in ipairs(profile.sampleSets or {}) do if entry.id==setId then selected=entry;break end end
	assert(selected,"Choose a saved example set")
	return simulatePage(profile,selected,offset,limit,checkpoint,false)
end
local sceneKinds={ ["Mixed drops"]=true,["Build targets"]=true,Currency=true,["Preset highlights"]=true,["Tiered gear"]=true,["Covens & Threads"]=true,["Maps & threads"]=true,["Map tiers"]=true,["Flasks & tinctures"]=true,["Divination cards"]=true,Essences=true,["Crafting materials"]=true,["Heist & Expedition"]=true }
function M.simulateScene(profile,kind,seed,areaLevel,itemLevel,offset,limit,checkpoint,build)
	assert(sceneKinds[kind],"Choose a supported built-in filter scene")
	seed=seed or 0;areaLevel=areaLevel or 83;itemLevel=itemLevel or 86
	assert(type(seed)=="number" and seed==math.floor(seed) and seed>=0 and seed<=1000000,"Invalid scene seed")
	assert(type(areaLevel)=="number" and areaLevel==math.floor(areaLevel) and areaLevel>=1 and areaLevel<=100,"Invalid area level")
	assert(type(itemLevel)=="number" and itemLevel==math.floor(itemLevel) and itemLevel>=1 and itemLevel<=100,"Invalid item level")
	local selected={id="builtin",title=kind};local warnings
	local library=require("Modules.LootFilterLibrary")
	if kind=="Build targets" then
		assert(build,"Build targets require an open build")
		local targets;targets,warnings=M.generate(build,profile,checkpoint)
		local rules={};for _,rule in ipairs(targets) do if rule.origin then rules[#rules+1]=rule end end
		selected.total=#rules
		selected.sampleAt=function(index)
			local item=library.sample(rules[index]);item.AreaLevel=areaLevel;item.ItemLevel=itemLevel;return item
		end
	else
		selected.samples=library.scene(profile,build,kind,seed,areaLevel,itemLevel)
	end
	local result=simulatePage(profile,selected,offset,limit,checkpoint,true)
	if warnings then
		result.warningCount=#warnings;result.warnings={}
		for i=1,math.min(#warnings,20) do
			local warning=warnings[i];local entry={retry=warning.retry}
			for _,key in ipairs({"origin","title","message"}) do
				if type(warning[key])=="string" then entry[key]=truncateUTF8(warning[key],240);if #warning[key]>240 then entry.truncated=true end end
			end
			result.warnings[i]=entry
		end
		if #warnings>20 then result.warningsTruncated=true end
	end
	result.seed=seed;result.areaLevel=areaLevel;result.itemLevel=itemLevel
	result.note="Deterministic examples, not live prices, drop rates or encounter probabilities."
	return result
end
function M.update(profile)
	local nextProfile=copyTable(profile);nextProfile.baseCommit=M.source().commit
	return nextProfile,{previous=profile.baseCommit,current=nextProfile.baseCommit,personalRules=#profile.rules,imported=profile.template~=nil}
end
function M.new(build)
	local self={build=build,data=M.empty()}
	function self:Load(xml)
		local raw=table.concat(xml);if raw:match("^%s*$") then return end
		local ok,result=pcall(function() assert(#raw<=M.limit,"Too large");return M.validate(assert(json.decode(raw,1,json.null))) end)
		if ok then self.data=result else self.unreadable=raw;self.warning="Loot filters could not be read and will be preserved unchanged." end
	end
	function self:Save(xml) xml[#xml+1]=self.unreadable or json.encode(self.data) end
	function self:Replace(data) assert(not self.unreadable,self.warning);self.data=M.validate(data);build.modFlag=true;require("Modules.PlanningUI").kept(build,"filters");return self.data end
	function self:Upsert(profile)
		local data=copyTable(self.data);local found=false;for i,p in ipairs(data.profiles) do if p.id==profile.id then data.profiles[i]=profile;found=true end end
		if not found then data.profiles[#data.profiles+1]=profile end;data.activeId=profile.id;return self:Replace(data)
	end
	return self
end
return M
