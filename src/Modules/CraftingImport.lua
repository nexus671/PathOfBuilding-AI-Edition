-- Resolve plain copied values only when the complete affix assignment is unique.
local I={}
function I.prepareDropOnly(model)
	-- These identities may occur in imported or structured states, but they do
	-- not belong to the ordinary modifier roll pool.
	local base=model.item.base;local subtype=base.subType and base.type..": "..base.subType
	model.dropOnlyIds={}
	for _,source in ipairs({{require("Data.IncursionDropOnly"),data.itemMods.Explicit},{require("Data.DelveDropOnly"),data.itemMods.Delve}}) do
		for id,entry in pairs(source[1]) do
			local mod=source[2][id]
			if mod and mod.level<=model.item.itemLevel and (isValueInTable(entry.categories,base.type) or subtype and isValueInTable(entry.categories,subtype)) then
				model.byId[id]=model.byId[id] or mod;model.dropOnlyIds[#model.dropOnlyIds+1]=id
			end
		end
	end
end
function I.inferRange(template,line)
	local pattern,ranges,at="",{},1
	local function escape(text) return text:gsub("([^%w])","%%%1") end
	for first,low,high,last in template:gmatch("()%((%-?%d+%.?%d*)%-(%-?%d+%.?%d*)%)()") do
		pattern=pattern..escape(template:sub(at,first-1)).."(%-?%d+%.?%d*)";at=last;ranges[#ranges+1]={tonumber(low),tonumber(high)}
	end
	pattern="^"..pattern..escape(template:sub(at)).."$"
	if #ranges == 0 then return template == line and {} or nil end
	local values={line:match(pattern)};if #values ~= #ranges then return nil end
	local result={}
	for i,bounds in ipairs(ranges) do
		local value=tonumber(values[i]);local low,high=math.min(unpack(bounds)),math.max(unpack(bounds))
		if not value or value < low or value > high then return nil end
		result[i]=bounds[1] == bounds[2] and 0.5 or (value-bounds[1])/(bounds[2]-bounds[1])
	end
	return result
end
function I.resolve(M,model,state)
	local rows={}
	for _,line in ipairs(model.item.explicitModLines) do rows[#rows+1]={text=itemLib.applyRange(line.line,line.range or 0.5),crafted=line.crafted or false,fractured=line.fractured or false,prefix=line.prefix,suffix=line.suffix} end
	local used={}
	for _,entry in ipairs(state.affixes) do local mod=M.entryMod(model,entry);for _,text in ipairs(M.rolledLines(mod,entry.range)) do
		local found
		-- Preserve explicitly labelled prefix/suffix rows for the matching side;
		-- prefer a labelled row over an otherwise equivalent unlabelled row.
		for _,labelled in ipairs({true,false}) do
			for i,row in ipairs(rows) do if not used[i] and row.text == text and row.crafted == (entry.crafted or false) and row.fractured == (entry.fractured or false)
				and (not row.prefix or mod.type == "Prefix") and (not row.suffix or mod.type == "Suffix") and (not not (row.prefix or row.suffix)) == labelled then found=i;break end end
			if found then break end
		end
		assert(found,"A native modifier identity does not match the imported values")
		used[found]=true
	end end
	local candidates,seen,contributorMods={},{ },{}
	local function consider(id,crafted,legacy,description330)
		local key=id..(legacy and ":legacy" or description330 and ":description330" or ":current");if seen[key] then return end;seen[key]=true
		local mod=legacy and model.legacyLightRadius[id] or description330 and model.descriptions330[id] or model.byId[id];if not mod or #mod == 0 then return end
		if not crafted then contributorMods[#contributorMods+1]={id=id,mod=mod} end
		local indices,ranges={},{}
		local function matchLine(lineIndex,fractured)
			if lineIndex>#mod then
				if legacy then for _,candidate in ipairs(candidates) do if candidate.entry.id==id and not candidate.entry.legacyLightRadius and table.concat(candidate.indices,",")==table.concat(indices,",") then return end end end
				assert(#candidates<10000,"Import has too many ambiguous modifier assignments; use advanced copy text")
				candidates[#candidates+1]={indices=copyTable(indices),entry={id=id,range=#ranges == 0 and 0.5 or #ranges == 1 and ranges[1] or copyTable(ranges),crafted=crafted or nil,fractured=fractured or nil,legacyLightRadius=legacy or nil,description330=description330 or nil}}
				return
			end
			for i,row in ipairs(rows) do if not used[i] and row.crafted == crafted and (fractured == nil or fractured == row.fractured) and (not row.prefix or mod.type == "Prefix") and (not row.suffix or mod.type == "Suffix") then
				local already=false;for _,index in ipairs(indices) do if index == i then already=true end end
				local inferred=not already and I.inferRange(mod[lineIndex],row.text)
				if inferred then
					indices[#indices+1]=i;local previous=#ranges
					for _,value in ipairs(inferred) do ranges[#ranges+1]=value end
					matchLine(lineIndex+1,row.fractured)
					indices[#indices]=nil;while #ranges>previous do ranges[#ranges]=nil end
				end
			end end
		end
		matchLine(1,nil)
	end
	for _,entry in ipairs(model.mods) do consider(entry.id,false) end
	for id in pairs(model.legacyAbyss or {}) do consider(id,false) end
	for id in pairs(model.unveiledJewels or {}) do consider(id,false) end
	for _,entry in ipairs(model.mods) do if model.legacyLightRadius[entry.id] then consider(entry.id,false,true) end end
	for _,entry in ipairs(model.essences) do consider(entry.modId,false) end
	for _,entry in ipairs(model.essences) do if model.descriptions330[entry.modId] then consider(entry.modId,false,false,true) end end
	for _,id in ipairs(model.dropOnlyIds) do consider(id,false) end
	for _,entry in ipairs(model.bench) do consider(entry.id,true) end
	for _,id in ipairs(model.benchImportAliases or {}) do consider(id,true) end
	for _,list in ipairs({data.veiledMods,data.beastCraft}) do for id,mod in pairs(list) do
		if (mod.type == "Prefix" or mod.type == "Suffix") and mod.level <= model.item.itemLevel and model.item:GetModSpawnWeight(mod) > 0 then model.byId[id]=mod;consider(id,false) end
	end end
	local metadata=require("Modules.CraftingAdvanced").data().mods
	local function groups(id) return metadata[id] and metadata[id].groups or {model.byId[id].group} end
	local occupied,counts={},{Prefix=0,Suffix=0}
	for _,entry in ipairs(state.affixes) do counts[model.byId[entry.id].type]=counts[model.byId[entry.id].type]+1;for _,group in ipairs(groups(entry.id)) do occupied[group]=true end end
	local caps=M.capacities(model,state);local selected,solutions,solutionKeys={},{},{};local visits=0
	local function search()
		visits=visits+1;assert(visits <= 10000,"Import has too many ambiguous modifier assignments; use advanced copy text")
		if #solutions > 1 then return end
		local first;for i=1,#rows do if not used[i] then first=i;break end end
		if not first then
			local parts={};for _,entry in ipairs(selected) do
				local range=type(entry.range)=="table" and table.concat(entry.range,",") or tostring(entry.range)
				parts[#parts+1]=table.concat({entry.id,range,tostring(entry.crafted),tostring(entry.fractured),tostring(entry.legacyLightRadius),tostring(entry.description330)},"|")
			end
			table.sort(parts);local key=table.concat(parts,";")
			if not solutionKeys[key] then solutionKeys[key]=true;solutions[#solutions+1]=copyTable(selected) end
			return
		end
		for _,candidate in ipairs(candidates) do
			local contains,legal=false,true;local entry=candidate.entry;local kind=model.byId[entry.id].type
			for _,i in ipairs(candidate.indices) do if used[i] then legal=false end;if i == first then contains=true end end
			if counts[kind] >= caps[kind] then legal=false end
			for _,group in ipairs(groups(entry.id)) do if occupied[group] then legal=false end end
			if contains and legal then
				for _,i in ipairs(candidate.indices) do used[i]=true end
				for _,group in ipairs(groups(entry.id)) do occupied[group]=true end
				counts[kind]=counts[kind]+1;selected[#selected+1]=entry
				search()
				table.remove(selected);counts[kind]=counts[kind]-1
				for _,group in ipairs(groups(entry.id)) do occupied[group]=nil end
				for _,i in ipairs(candidate.indices) do used[i]=nil end
				if #solutions > 1 then return end
			end
		end
	end
	search()
	-- Native item text can combine contributions from two modifiers into one
	-- displayed stat. A direct line match alone is therefore not proof that
	-- the modifier assignment is unique. Check two- and three-contributor integer single-stat overlaps
	-- against the rest of the item before accepting that assignment.
	local function hasCombinedAlternative()
		local examined=0
		local function budget()
			examined=examined+1
			assert(examined<=100000,"Import has too many possible combined modifiers; use advanced copy text")
		end
		local function sideFits(row,kind)
			return not row.crafted and not row.fractured and (not row.prefix or kind=="Prefix") and (not row.suffix or kind=="Suffix")
		end
		local function cover()
			budget()
			local first;for i=1,#rows do if not used[i] then first=i;break end end
			if not first then return true end
			for _,candidate in ipairs(candidates) do
				local entry=candidate.entry;local kind=model.byId[entry.id].type;local contains,legal=false,counts[kind]<caps[kind] and counts.Prefix+counts.Suffix<caps.total
				for _,i in ipairs(candidate.indices) do if used[i] then legal=false end;if i==first then contains=true end end
				for _,group in ipairs(groups(entry.id)) do if occupied[group] then legal=false end end
				if contains and legal then
					for _,i in ipairs(candidate.indices) do used[i]=true end
					for _,group in ipairs(groups(entry.id)) do occupied[group]=true end
					counts[kind]=counts[kind]+1;local found=cover();counts[kind]=counts[kind]-1
					for _,group in ipairs(groups(entry.id)) do occupied[group]=nil end
					for _,i in ipairs(candidate.indices) do used[i]=nil end
					if found then return true end
				end
			end
			return false
		end
		local function escape(text) return text:gsub("([^%w])","%%%1") end
		for rowIndex,row in ipairs(rows) do if not used[rowIndex] and not row.crafted and not row.fractured then
			local byPattern={}
			for _,entry in ipairs(contributorMods) do local mod=entry.mod
				if sideFits(row,mod.type) then for lineIndex,line in ipairs(mod) do
					local first,last,low,high=line:find("%((%-?%d+)%-(%-?%d+)%)")
					if first and not line:sub(last+1):find("%(%-?%d+%-%-?%d+%)") then
						local pattern="^"..escape(line:sub(1,first-1)).."(%-?%d+)"..escape(line:sub(last+1)).."$"
						local value=tonumber(row.text:match(pattern))
						if value then byPattern[pattern]=byPattern[pattern] or {};byPattern[pattern][#byPattern[pattern]+1]={id=entry.id,mod=mod,line=lineIndex,low=tonumber(low),high=tonumber(high),value=value} end
					end
				end end
			end
			for _,list in pairs(byPattern) do for a=1,#list do for b=a+1,#list do
				budget();local left,right=list[a],list[b]
				local order=left.mod.statOrder and left.mod.statOrder[left.line]
				local legal=left.id~=right.id and order~=nil and right.mod.statOrder and order==right.mod.statOrder[right.line] and counts.Prefix+counts.Suffix+2<=caps.total
				local sides={Prefix=0,Suffix=0};sides[left.mod.type]=sides[left.mod.type]+1;sides[right.mod.type]=sides[right.mod.type]+1
				for side,n in pairs(sides) do if counts[side]+n>caps[side] then legal=false end end
				local pairGroups={};for _,part in ipairs({left,right}) do for _,group in ipairs(groups(part.id)) do if occupied[group] or pairGroups[group] then legal=false end;pairGroups[group]=true end end
				local min=math.min(left.low,left.high)+math.min(right.low,right.high);local max=math.max(left.low,left.high)+math.max(right.low,right.high)
				if legal and left.value>=min and left.value<=max then
					used[rowIndex]=true;for group in pairs(pairGroups) do occupied[group]=true end;for side,n in pairs(sides) do counts[side]=counts[side]+n end
					local rest={};for _,part in ipairs({left,right}) do for index,line in ipairs(part.mod) do if index~=part.line then rest[#rest+1]={line=line,kind=part.mod.type} end end end
					local function matchRest(index)
						if index>#rest then return cover() end
						local part=rest[index]
						for i,other in ipairs(rows) do if not used[i] and sideFits(other,part.kind) and I.inferRange(part.line,other.text) then
							used[i]=true;local found=matchRest(index+1);used[i]=nil;if found then return true end
						end end
						return false
					end
					local found=matchRest(1)
					for side,n in pairs(sides) do counts[side]=counts[side]-n end;for group in pairs(pairGroups) do occupied[group]=nil end;used[rowIndex]=nil
					if found then return true end
				end
			end end end
			-- A third contributing modifier can make a combined value possible
			-- even when no pair of modifiers can reach it.
			if counts.Prefix+counts.Suffix+3<=caps.total then
				for _,list in pairs(byPattern) do for a=1,#list do for b=a+1,#list do for c=b+1,#list do
					budget();local parts={list[a],list[b],list[c]};local order=parts[1].mod.statOrder and parts[1].mod.statOrder[parts[1].line]
					local legal=order~=nil;local ids,partGroups,sides={},{},{Prefix=0,Suffix=0};local min,max=0,0
					for _,part in ipairs(parts) do
						if ids[part.id] or not part.mod.statOrder or part.mod.statOrder[part.line]~=order then legal=false end
						ids[part.id]=true;sides[part.mod.type]=sides[part.mod.type]+1
						min=min+math.min(part.low,part.high);max=max+math.max(part.low,part.high)
						for _,group in ipairs(groups(part.id)) do if occupied[group] or partGroups[group] then legal=false end;partGroups[group]=true end
					end
					for side,n in pairs(sides) do if counts[side]+n>caps[side] then legal=false end end
					if legal and parts[1].value>=min and parts[1].value<=max then
						used[rowIndex]=true;for group in pairs(partGroups) do occupied[group]=true end;for side,n in pairs(sides) do counts[side]=counts[side]+n end
						local rest={};for _,part in ipairs(parts) do for index,line in ipairs(part.mod) do if index~=part.line then rest[#rest+1]={line=line,kind=part.mod.type} end end end
						local function matchRest(index)
							if index>#rest then return cover() end
							local part=rest[index]
							for i,other in ipairs(rows) do if not used[i] and sideFits(other,part.kind) and I.inferRange(part.line,other.text) then
								used[i]=true;local found=matchRest(index+1);used[i]=nil;if found then return true end
							end end
							return false
						end
						local found=matchRest(1)
						for side,n in pairs(sides) do counts[side]=counts[side]-n end;for group in pairs(partGroups) do occupied[group]=nil end;used[rowIndex]=nil
						if found then return true end
					end
				end end end end
			end
		end end
		return false
	end
	if #solutions==1 and hasCombinedAlternative() then solutions[2]=true end
	local failure=#solutions == 0 and "Imported values do not resolve to legal affixes at this item level; use advanced copy text or a blank base with a structured starting state" or "Imported values match several modifier identities; use advanced copy text or a blank base with a structured starting state"
	if model.item.type=="Tincture" and model.item.tinctureValues=="Final" and ((model.item.tinctureImportedQuality or 0)~=0 or (model.item.tinctureImportedEffect or 0)~=0) then
		failure="Copied tincture values may include quality or effect scaling, so their modifier tiers cannot be identified reliably. Start with a blank tincture and enter base-value rolls."
	end
	assert(#solutions == 1,failure)
	for _,entry in ipairs(solutions[1]) do state.affixes[#state.affixes+1]=entry end
	return state
end
return I
