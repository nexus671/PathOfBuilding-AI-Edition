-- Identify modifier boundaries without guessing between different partitions.
local M={}
function M.candidates(group,state,index)
	return state.synthRolls and {state.synthRolls[index]} or group.candidates
end
function M.lines(model,state,index)
	local group=model.synthesisGroups[index];local entry=state.synthRolls and state.synthRolls[index]
	if not entry then return copyTable(group) end
	local ranges=type(entry.range)=="table" and entry.range or {entry.range};local encoded={};for _,value in ipairs(ranges) do encoded[#encoded+1]=string.format("%.17g",value) end
	local mod=assert(model.byId[entry.id]);local result={};for index,line in ipairs(itemLib.applyModRanges(mod,entry.range)) do
		local value=copyTable(group[index] or {});value.line=line;value.range=nil;value.modTags=copyTable(mod.modTags or {});value.modGroup="synth_id_"..entry.id.."~"..table.concat(encoded,",");result[#result+1]=value
	end
	return result
end
function M.targetStatus(group,target)
	local yes,no=false,false
	for _,candidate in ipairs(group.candidates) do
		local roll=type(candidate.range)=="table" and math.min(unpack(candidate.range)) or candidate.range or 0.5
		local hit=false
		for _,id in ipairs(target.anyOf) do if candidate.id==id and roll >= (target.minRoll or 0) and target.fractured~=true and target.crafted~=true then hit=true;break end end
		yes=yes or hit;no=no or not hit
	end
	if yes and no then return nil end
	return yes
end
function M.resolve(lines,modifiers)
	if #lines==0 or #lines>12 then return nil end
	local infer=require("Modules.CraftingImport").inferRange
	local lengths={}
	for start=1,#lines do lengths[start]={} end
	for id,mod in pairs(modifiers) do
		if #mod>0 and #mod<=#lines then
			for start=1,#lines-#mod+1 do
				local tag=lines[start].modGroup;local tagged,encoded;if tag then tagged,encoded=tag:match("^synth_id_([^~]+)~(.+)$") end
				if tag and not tagged then tagged=tag:match("^synth_id_(.+)$") end
				local valid,exact,hasRange,ranges=not tagged or tagged==id,true,false,{}
				for offset,template in ipairs(mod) do
					local line=lines[start+offset-1]
					if template~=line.line then exact=false end
					local values=infer(template,itemLib.applyRange(line.line,line.range or 0.5))
					if not values then valid=false;break end
					if template==line.line and line.range~=nil and #values>0 then hasRange=true end
					for _,value in ipairs(values) do ranges[#ranges+1]=template==line.line and line.range or value end
				end
				if valid and encoded then
					local decoded={};for part in (encoded..","):gmatch("(.-),") do local value=tonumber(part);if not value or value~=value or value<0 or value>1 then valid=false;break end;decoded[#decoded+1]=value end
					if #decoded<1 or #decoded>20 or (#ranges>0 and #decoded~=1 and #decoded~=#ranges) then valid=false end
					if valid then
						local roll=#decoded==1 and decoded[1] or decoded;local displayed=itemLib.applyModRanges(mod,roll)
						for offset,line in ipairs(displayed) do if StripEscapes(line)~=StripEscapes(itemLib.applyRange(lines[start+offset-1].line,lines[start+offset-1].range or 0.5)) then valid=false;break end end
						if valid then ranges=decoded end
					end
				end
				if valid then
					local matches=lengths[start][#mod] or {};lengths[start][#mod]=matches
					matches[#matches+1]={id=id,range=#ranges==0 and 0.5 or #ranges==1 and ranges[1] or ranges,exact=exact and hasRange}
				end
			end
		end
	end
	local solutions,chosen={},{}
	local function search(start)
		if #solutions>1 then return end
		if start>#lines then solutions[#solutions+1]=copyTable(chosen);return end
		if #chosen>=3 then return end
		for length in pairs(lengths[start]) do
			local group=lines[start].modGroup
			local valid=true
			for i=start,start+length-1 do
				local current=lines[i].modGroup
				if (group or current) and group~=current then valid=false;break end
			end
			if valid and group and start+length<=#lines and lines[start+length].modGroup==group then valid=false end
			if valid then chosen[#chosen+1]=length;search(start+length);chosen[#chosen]=nil end
		end
	end
	search(1)
	if #solutions~=1 then return nil end
	local result,start={},1
	for _,length in ipairs(solutions[1]) do
		local group={};for index=start,start+length-1 do group[#group+1]=copyTable(lines[index]) end
		local candidates=lengths[start][length];local hasExact=false
		for _,candidate in ipairs(candidates) do if candidate.exact then hasExact=true;break end end
		group.candidates={};for _,candidate in ipairs(candidates) do if not hasExact or candidate.exact then candidate.exact=nil;group.candidates[#group.candidates+1]=candidate end end
		table.sort(group.candidates,function(a,b) return tostring(a.id)<tostring(b.id) end)
		result[#result+1]=group;start=start+length
	end
	return result
end
return M
