-- Compare the same supplied examples under two compiled filter profiles.
local filters=require("Modules.LootFilters")
local parser=require("Modules.LootFilterParser")
local stable=require("Modules.PlanningData")
local M={}
local function short(value,limit)
	value=tostring(value);if #value<=limit then return value end
	local last=limit;while last>0 do local byte=value:byte(last+1);if not byte or byte<128 or byte>=192 then break end;last=last-1 end
	return value:sub(1,last).."..."
end
local function prepare(profile)
	local ok,raw,report,parsed=pcall(filters.compile,profile,true)
	if not ok then return {invalid={status="invalid",action="Unknown",styles={},reasons={(tostring(raw):gsub("^.-:%d+: ",""))}}} end
	for _,diagnostic in ipairs(report.diagnostics) do if diagnostic.error then return {invalid=parser.invalidResult(diagnostic)} end end
	return {parsed=parsed}
end
function M.prepare(before,after) return {before=prepare(before),after=prepare(after)} end
local function outcome(source,sample)
	local value=source.invalid or parser.simulate(source.parsed,sample)
	local reasons={};for i=1,math.min(3,#(value.reasons or {})) do reasons[i]=short(value.reasons[i],300) end
	return {status=value.status,action=value.action,line=value.line,ruleTitle=value.ruleTitle and short(value.ruleTitle,160),styles=value.styles or {},reasons=reasons}
end
function M.page(prepared,samples,offset,limit,checkpoint,includeStyles)
	offset=offset or 0;limit=limit or 20
	assert(type(samples)=="table" and type(offset)=="number" and offset==math.floor(offset) and offset>=0 and offset<=#samples,"Invalid example offset")
	assert(type(limit)=="number" and limit==math.floor(limit) and limit>=1 and limit<=50,"Use 1 to 50 examples per page")
	local rows={};local last=math.min(#samples,offset+limit)
	for i=offset+1,last do
		local before,after=outcome(prepared.before,samples[i]),outcome(prepared.after,samples[i]);local changed={}
		local keys={};for key in pairs(before.styles) do keys[key]=true end;for key in pairs(after.styles) do keys[key]=true end
		for key in pairs(keys) do if stable.encodeExact(before.styles[key])~=stable.encodeExact(after.styles[key]) then changed[#changed+1]=key end end;table.sort(changed)
		local styles={};for index=1,math.min(#changed,30) do local key=changed[index]
			styles[#styles+1]={name=key,before=before.styles[key] and short(stable.encodeExact(before.styles[key]),160) or "Not set",after=after.styles[key] and short(stable.encodeExact(after.styles[key]),160) or "Not set"}
		end
		local uncertain=before.status~="matched" or after.status~="matched" or #before.reasons>0 or #after.reasons>0
		local category=uncertain and "Needs review" or before.action~=after.action and "Visibility changed" or #changed>0 and "Style changed" or "Unchanged"
		if not includeStyles then before.styles=nil;after.styles=nil end
		rows[#rows+1]={index=i-1,category=category,before=before,after=after,changedStyles=styles,stylesTruncated=#changed>30 or nil}
		if checkpoint then checkpoint({completed=i-offset,total=last-offset}) end
	end
	return {total=#samples,offset=offset,nextOffset=last<#samples and last or nil,results=rows}
end
return M
