-- A reference for observed client wording, not a simulated crafting method.
local M={}
local cache
local function data()
	if not cache then
		local root=GetScriptPath();local path=(root ~= "" and root.."/" or "").."Data/Crafting/GwennenReference.json"
		local file=assert(io.open(path,"rb"));local raw=file:read("*a");file:close()
		cache=assert(require("dkjson").decode(raw))
	end
	return cache
end
function M.search(query,limit)
	local source=data();local rows={};query=(query or ""):lower();limit=math.max(0,math.min(limit or 50,100))
	local count=0
	for _,entry in ipairs(source.offers) do
		local description=entry.description:gsub("%[([^|%]]+)|([^%]]+)%]","%2")
		local haystack=(description.." "..entry.id.." "..(entry["function"] or "").." "..(entry.arguments or "")):lower()
		if haystack:find(query,1,true) then
			count=count+1
			if #rows<limit then
				local row={id=entry.id,description=description,functionName=entry["function"],arguments=entry.arguments,family=entry.family}
				if entry.id==1030 then row.note="The displayed 100 rerolls conflict with the listed function argument of 50; behavior is unverified." end
				if entry.id==1018 or entry.id==1019 then row.note="The model assumes the number of modifiers on this side stays the same; Gwennen's behavior is unverified." end
				rows[#rows+1]=row
			end
		end
	end
	return {offers=rows,total=count,source=source.source,sourceSha256=source.sourceSha256,reportedPatch=source.reportedPatch,
		note="Reference only: not available crafting actions. Item eligibility, pair generation, coin odds, costs and modifier interactions are not modeled or verified."}
end
return M
