-- Local, portable editing primitives shared by the UI, compiler and AI proposals.
-- cspell:ignore jsontype
local parser=require("Modules.LootFilterParser")
local json=require("dkjson")
local encode=require("Modules.PlanningData").encode
local M={}
local function list(value)
	assert(type(value)=="table" and value~=json.null,"Expected an array")
	local meta=getmetatable(value);assert(not meta or meta.__jsontype~="object","Expected an array")
	for k in pairs(value) do assert(type(k)=="number" and k>=1 and k<=#value and k==math.floor(k),"Expected a dense array") end
	return value
end
local function label(value,limit)
	assert(type(value)=="string" and #value<=limit and value:match("%S") and not value:find("[%c]"),"Invalid name")
	return value
end
local function identity(value)
	assert(label(value,100):match("^[%w_-]+$"),"Invalid identity");return value
end
function M.items(text)
	local block=parser.parse(text).rules[1];local values
	assert(block,"A tier needs a filter block")
	for _,c in ipairs(block.conditions) do if c.keyword=="BaseType" then
		assert(not values and c.operator=="==","Tier editing requires one exact BaseType condition")
		values=copyTable(c.values)
	end end
	return assert(values,"This block has no exact item list")
end
function M.withItems(text,items)
	M.items(text);local values={};for _,name in ipairs(items) do values[#values+1]=require("Modules.LootFilters").quote(name) end
	assert(#values>0,"An empty tier does not produce a filter rule")
	local lines={};for line in (text.."\n"):gmatch("([^\n]*)\n") do
		if line:match("^%s*BaseType%s") then line="    BaseType == "..table.concat(values," ") end
		lines[#lines+1]=line
	end
	return table.concat(lines,"\n")
end
function M.validateTiers(tiers)
	local result,seen={},{}
	for _,tier in ipairs(list(tiers)) do
		local next={id=identity(tier.id),title=label(tier.title,160),items={},text=tier.text,enabled=tier.enabled~=false}
		assert(not seen[next.id],"Duplicate tier identity");seen[next.id]=true
		assert(type(next.text)=="string" and #next.text<=24000,"Invalid tier template")
		local parsed=parser.parse(next.text);assert(#parsed.rules==1 and #parsed.imports==0,"Use one block per tier")
		for _,d in ipairs(parsed.diagnostics) do assert(not d.error,d.error) end;M.items(next.text)
		local names={};for _,name in ipairs(list(tier.items)) do name=label(name,240);require("Modules.LootFilters").quote(name);assert(not names[name],"Duplicate item in tier");names[name]=true;next.items[#next.items+1]=name end
		if tier.stackRules~=nil then
			next.stackRules={};local thresholds={}
			for _,rule in ipairs(list(tier.stackRules)) do
				assert(type(rule)=="table","Invalid stack rule")
				local minimum=rule.minimum;assert(type(minimum)=="number" and minimum==math.floor(minimum) and minimum>=2 and minimum<=1000000000,"Invalid stack size")
				assert(not thresholds[minimum],"Duplicate stack threshold");thresholds[minimum]=true
				next.stackRules[#next.stackRules+1]={minimum=minimum,styleTierId=identity(rule.styleTierId)}
			end
		end
		result[#result+1]=next
	end
	local byId={};for _,tier in ipairs(result) do byId[tier.id]=tier end
	for _,tier in ipairs(result) do for _,rule in ipairs(tier.stackRules or {}) do
		local target=assert(byId[rule.styleTierId],"Stack style tier is missing")
		assert(target.id~=tier.id,"Choose a different tier for a stack style")
		require("Modules.LootFilterStackTiers").rule(tier.text,target.text,rule.minimum)
	end end
	return result
end
-- Apply a threshold atomically: a tier with incompatible conditions must not
-- leave the rest of the profile partially changed.
function M.setStackStyle(tiers,ids,minimum,styleId)
	local next=copyTable(M.validateTiers(tiers));local byId={}
	for _,tier in ipairs(next) do byId[tier.id]=tier end
	local target=assert(byId[styleId],"Choose a style tier")
	local seen={};for _,id in ipairs(list(ids)) do
		local tier=assert(byId[id],"A selected tier no longer exists")
		assert(not seen[id],"A tier was selected more than once");seen[id]=true
		assert(tier.id~=target.id,"A tier cannot use its own stack style")
		local ok,why=pcall(require("Modules.LootFilterStackTiers").rule,tier.text,target.text,minimum)
		assert(ok,tier.title..": "..tostring(why):match("[^:]+$"))
		tier.stackRules=tier.stackRules or {};local replaced=false
		for _,rule in ipairs(tier.stackRules) do if rule.minimum==minimum then rule.styleTierId=styleId;replaced=true;break end end
		if not replaced then tier.stackRules[#tier.stackRules+1]={minimum=minimum,styleTierId=styleId} end
	end
	assert(#ids>0,"Choose at least one tier")
	for _,id in ipairs(ids) do
		local tier=byId[id];local rules=copyTable(tier.stackRules);table.sort(rules,function(a,b) return a.minimum>b.minimum end)
		if parser.parse(tier.text).rules[1].continue then for index,rule in ipairs(rules) do
			local upper=index>1 and rules[index-1].minimum or nil
			local ok,why=pcall(require("Modules.LootFilterStackTiers").rule,tier.text,byId[rule.styleTierId].text,rule.minimum,upper)
			assert(ok,tier.title..": "..tostring(why):match("[^:]+$"))
		end end
	end
	return M.validateTiers(next)
end
function M.rule(tier)
	if #tier.items==0 or tier.enabled==false then return end
	return {id=tier.id,title=tier.title,text=M.withItems(tier.text,tier.items),enabled=true}
end
-- Emit largest stacks first so that thresholds are never shadowed by smaller ones.
function M.tierRules(tiers)
	local byId={};for _,tier in ipairs(tiers or {}) do byId[tier.id]=tier end
	local result={}
	for _,tier in ipairs(tiers or {}) do
		local base=M.rule(tier)
		if base then
			local rules=copyTable(tier.stackRules or {});table.sort(rules,function(a,b) return a.minimum>b.minimum end)
			local continuing=parser.parse(base.text).rules[1].continue
			for index,rule in ipairs(rules) do
				local target=assert(byId[rule.styleTierId],"Stack style tier is missing")
				local upper=continuing and index>1 and rules[index-1].minimum or nil
				local text=require("Modules.LootFilterStackTiers").rule(base.text,target.text,rule.minimum,upper)
				result[#result+1]={id="stack-"..require("sha1")(tier.id..":"..rule.minimum):sub(1,20),title=tier.title.." / "..rule.minimum.."+ stack",text=text,enabled=true}
			end
			if continuing and #rules>0 then base.text=base.text.."\n    StackSize < "..rules[#rules].minimum end
			result[#result+1]=base
		end
	end
	return result
end
function M.newTier(id,title,source)
	local text=source or require("Modules.LootFilters").rule(id,title,{'Class == "Stackable Currency"','BaseType == "Chaos Orb"'}).text
	M.items(text);return {id=id,title=title,text=text,items={},enabled=true}
end
function M.assignmentIssue(profile,id,name,sourceText)
	local destination;for _,tier in ipairs(profile.tiers or {}) do if tier.id==id then destination=tier end end
	if not destination then return "Choose a destination tier" end
	local function classes(text)
		if not text then return end
		for _,condition in ipairs(parser.parse(text).rules[1].conditions) do if condition.keyword=="Class" and condition.operator=="==" then return condition.values end end
	end
	if not sourceText then for _,tier in ipairs(profile.tiers or {}) do for _,item in ipairs(tier.items) do if item==name then sourceText=tier.text;break end end;if sourceText then break end end end
	-- Check the actual known item class against every destination class predicate.
	-- A shared class in two multi-class tiers does not prove this item matches.
	local knownClass=require("Modules.LootFilterLibrary").baseClass(name)
	if knownClass then
		local resolved=true
		for _,condition in ipairs(parser.parse(destination.text).rules[1].conditions) do
			if condition.keyword=="Class" then
				local matches=parser.condition(condition,{Class=knownClass})
				if matches==false then return "This item's class ("..knownClass..") does not match the destination tier. Edit its class conditions or choose another tier." end
				if matches==nil then resolved=false end
			end
		end
		-- A known compatible class is stronger evidence than a source tier's
		-- class condition, which may itself be the mistake the user is fixing.
		if resolved then return end
	end
	local from,to=classes(sourceText),classes(destination.text)
	if from and to then local overlap=false;for _,a in ipairs(from) do for _,b in ipairs(to) do if a==b then overlap=true end end end
		if not overlap then return "These tiers require different item classes. Edit the destination conditions or use a compatible tier." end
	end
end
function M.assign(profile,id,name,sourceText)
	label(name,240);local issue=M.assignmentIssue(profile,id,name,sourceText);assert(not issue,issue)
	local next=copyTable(profile);local destination;for _,tier in ipairs(next.tiers or {}) do if tier.id==id then destination=tier end end
	for _,tier in ipairs(next.tiers) do for i=#tier.items,1,-1 do if tier.items[i]==name then table.remove(tier.items,i) end end end
	destination.items[#destination.items+1]=name
	M.validateTiers(next.tiers);return next
end
function M.validateModules(modules)
	local result,seen={},{};local filters=require("Modules.LootFilters")
	for _,module in ipairs(list(modules)) do
		local next={id=identity(module.id),title=label(module.title,160),enabled=module.enabled~=false}
		assert(not seen[next.id],"Duplicate module identity");seen[next.id]=true
		local p=filters.profile("module","Module");p.rules=module.rules
		next.rules=filters.validate({schemaVersion=1,activeId=p.id,profiles={p}}).profiles[1].rules
		for _,rule in ipairs(next.rules) do rule.origin=nil end
		result[#result+1]=next
	end
	return result
end
function M.module(profile,id,title)
	local rules=copyTable(profile.rules)
	for _,rule in ipairs(M.tierRules(profile.tiers)) do rule.id="tier-"..require("sha1")(rule.id):sub(1,20);rules[#rules+1]=rule end
	return M.validateModules({{id=id,title=title,rules=rules}})[1]
end
function M.install(profile,module)
	module=M.validateModules({module})[1];local next=copyTable(profile);next.modules=next.modules or {}
	for i,value in ipairs(next.modules) do if value.id==module.id then next.modules[i]=module;return next end end
	next.modules[#next.modules+1]=module;return next
end
function M.share(module) return json.encode({schemaVersion=1,lootFilterModule=M.validateModules({module})[1]},{indent=true}) end
function M.import(raw)
	assert(type(raw)=="string" and #raw<=require("Modules.LootFilters").limit,"Module exceeds 2 MiB")
	local data=assert(json.decode(raw));assert(data.schemaVersion==1 and data.lootFilterModule,"Use an AI Edition rule module")
	return M.validateModules({data.lootFilterModule})[1]
end
local function stackSummary(rules,tiers)
	local names={};for _,tier in ipairs(tiers or {}) do names[tier.id]=tier.title end
	local rows={};for _,rule in ipairs(rules or {}) do rows[#rows+1]=rule.minimum.."+ uses "..(names[rule.styleTierId] or rule.styleTierId) end
	return #rows>0 and table.concat(rows,", ") or "None"
end
function M.review(before,after)
	local entries={};local old={};for _,p in ipairs(before.profiles) do old[p.id]=p end
	local function profileLabel(data,id)
		if not id or id=="" then return "None" end
		for _,profile in ipairs(data.profiles) do if profile.id==id then return profile.title.." ["..id.."]" end end
		return id.." (unavailable)"
	end
	local function tracking(value) if value==nil then return "Automatic (legacy)" end;return value and "Enabled" or "Disabled" end
	if before.activeId~=after.activeId then
		entries[#entries+1]={id="$active",label="Active profile changed",details={"Before: "..profileLabel(before,before.activeId),"After: "..profileLabel(after,after.activeId)}}
	end
	for _,p in ipairs(after.profiles) do
		local previous=old[p.id];old[p.id]=nil
		if not previous then
			local lines={"New profile", "Preset: "..p.preset.." | Strictness: "..p.strictness.." | Mode: "..p.mode, "Build pickup notices: "..tracking(p.trackBuildPickups)}
			for _,review in ipairs(p.manualGuideReviews or {}) do lines[#lines+1]="Reviewed crafting guide: "..review.projectId end
			if p.template then lines[#lines+1]="Imported base filter: "..#p.template.." bytes" end
			for _,file in ipairs(p.importFiles or {}) do lines[#lines+1]="Included file: "..file.name.." ("..#file.text.." bytes)" end
			for _,name in ipairs(p.absentOptionalImports or {}) do lines[#lines+1]="Preview assumes optional file absent: "..name end
			for _,rule in ipairs(p.rules) do lines[#lines+1]=(rule.enabled~=false and "Enabled: " or "Disabled: ")..rule.title;lines[#lines+1]=rule.text end
			entries[#entries+1]={id=p.id,label="+ "..p.title,details=lines}
		elseif encode(previous)~=encode(p) then
			local lines={}
			if previous.title~=p.title then lines[#lines+1]="Name: "..previous.title.." -> "..p.title end
			if previous.strictness~=p.strictness then lines[#lines+1]="Strictness: "..previous.strictness.." -> "..p.strictness end
			if previous.mode~=p.mode then lines[#lines+1]="Mode: "..previous.mode.." -> "..p.mode end
			if previous.preset~=p.preset then lines[#lines+1]="Preset: "..previous.preset.." -> "..p.preset end
			if previous.theme~=p.theme then lines[#lines+1]="Theme: "..tostring(previous.theme or "default").." -> "..tostring(p.theme or "default") end
			if previous.trackBuildPickups~=p.trackBuildPickups then lines[#lines+1]="Build pickup notices: "..tracking(previous.trackBuildPickups).." -> "..tracking(p.trackBuildPickups) end
			local reviews={};for _,review in ipairs(previous.manualGuideReviews or {}) do reviews[review.projectId]=review.signature end
			for _,review in ipairs(p.manualGuideReviews or {}) do local prior=reviews[review.projectId];reviews[review.projectId]=nil;if prior~=review.signature then lines[#lines+1]=(prior and "Updated reviewed crafting guide: " or "Reviewed crafting guide: ")..review.projectId end end
			for id in pairsSortByKey(reviews) do lines[#lines+1]="Removed guide review: "..id end
			local included={};for _,file in ipairs(previous.importFiles or {}) do included[file.name]=file end
			for _,file in ipairs(p.importFiles or {}) do
				local prior=included[file.name];included[file.name]=nil
				if not prior then lines[#lines+1]="Included file added: "..file.name.." ("..#file.text.." bytes)"
				elseif prior.text~=file.text then lines[#lines+1]="Included file changed: "..file.name.." ("..#prior.text.." -> "..#file.text.." bytes)" end
			end
			for name in pairsSortByKey(included) do lines[#lines+1]="Included file removed: "..name end
			local absent={};for _,name in ipairs(previous.absentOptionalImports or {}) do absent[name]=true end
			for _,name in ipairs(p.absentOptionalImports or {}) do if absent[name] then absent[name]=nil else lines[#lines+1]="Preview now assumes optional file absent: "..name end end
			for name in pairsSortByKey(absent) do lines[#lines+1]="Removed absent-file preview assumption: "..name end
			if previous.template~=p.template then lines[#lines+1]="Base filter changed: "..(previous.template and "imported ("..#previous.template.." bytes)" or "pinned preset").." -> "..(p.template and "imported ("..#p.template.." bytes)" or "pinned preset") end
			if previous.baseCommit~=p.baseCommit then lines[#lines+1]="Base revision: "..tostring(previous.baseCommit).." -> "..tostring(p.baseCommit) end
			if encode(previous.economyRules or {})~=encode(p.economyRules or {}) then lines[#lines+1]="Managed price rules changed" end
			for _,key in ipairs({"rules","tiers","modules"}) do local a,b={},{};for _,v in ipairs(previous[key] or {}) do a[#a+1]=v.id end;for _,v in ipairs(p[key] or {}) do b[#b+1]=v.id end;if #a==#b and table.concat(a,"/")~=table.concat(b,"/") then lines[#lines+1]="Priority order changed: "..key end end
			for _,key in ipairs({"rules","tiers","modules","sampleSets","palettes"}) do
				local map={};for _,v in ipairs(previous[key] or {}) do map[v.id]=v end
				for _,v in ipairs(p[key] or {}) do local prior=map[v.id];map[v.id]=nil
					if not prior or encode(prior)~=encode(v) then
						lines[#lines+1]=(prior and "Changed " or "Added ")..key..": "..v.title
						if prior and prior.text then lines[#lines+1]="Before:\n"..prior.text end;if v.text then lines[#lines+1]="After:\n"..v.text end
						if key=="rules" and prior and (prior.enabled~=v.enabled or prior.origin~=v.origin) then
							if prior.enabled~=v.enabled then lines[#lines+1]="Rule enabled: "..tostring(prior.enabled~=false).." -> "..tostring(v.enabled~=false) end
							if prior.origin~=v.origin then lines[#lines+1]="Linked source: "..tostring(prior.origin or "Manual").." -> "..tostring(v.origin or "Manual") end
						end
						if key=="tiers" then lines[#lines+1]="Items before: "..table.concat(prior and prior.items or {},", ");lines[#lines+1]="Items after: "..table.concat(v.items,", ");if encode(prior and prior.stackRules)~=encode(v.stackRules) then lines[#lines+1]="Stack styles before: "..stackSummary(prior and prior.stackRules,previous.tiers);lines[#lines+1]="Stack styles after: "..stackSummary(v.stackRules,p.tiers) end end
						if key=="modules" then lines[#lines+1]="Module before: "..(prior and encode(prior) or "not installed");lines[#lines+1]="Module after: "..encode(v) end
						if key=="sampleSets" or key=="palettes" then lines[#lines+1]="Before: "..(prior and encode(prior) or "not saved");lines[#lines+1]="After: "..encode(v) end
					end
				end
				for _,v in pairsSortByKey(map) do lines[#lines+1]="Removed "..key..": "..v.title end
			end
			if encode(previous.appearance)~=encode(p.appearance) then lines[#lines+1]="Appearance before: "..json.encode(previous.appearance);lines[#lines+1]="Appearance after: "..json.encode(p.appearance) end
			if encode(previous.campaign)~=encode(p.campaign) then lines[#lines+1]="Campaign policy before: "..encode(previous.campaign);lines[#lines+1]="Campaign policy after: "..encode(p.campaign) end
			if encode(previous.categoryStyles)~=encode(p.categoryStyles) then lines[#lines+1]="Category styles before: "..encode(previous.categoryStyles);lines[#lines+1]="Category styles after: "..encode(p.categoryStyles) end
			if encode(previous.sharedStyles)~=encode(p.sharedStyles) then lines[#lines+1]="Shared styles before: "..encode(previous.sharedStyles);lines[#lines+1]="Shared styles after: "..encode(p.sharedStyles) end
			if #lines==0 then lines[1]="Profile metadata changed; inspect the draft for details." end
			entries[#entries+1]={id=p.id,label="Changed: "..p.title,details=lines}
		end
	end
	for id,p in pairsSortByKey(old) do entries[#entries+1]={id=id,label="- "..p.title,details={"Profile removed"}} end
	return entries
end
return M
