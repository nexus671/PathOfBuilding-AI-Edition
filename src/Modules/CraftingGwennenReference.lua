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
				if entry.id==1031 then row.note="The model assumes equal influence chances and accepts only uninfluenced, non-synthesised items without Eldritch implicits." end
				if entry.id==1013 then row.note="The model uses Brinehook's four Pantheon Aspects, assumed equally likely, and requires an open suffix; Gwennen's rules are unverified." end
				if entry.id==1010 or entry.id==1011 then row.note="Uses estimated Chromatic Orb rolls and keeps the first result tied for most non-white ordinary sockets. Gwennen's tie rule and odds are unverified." end
				if entry.id==1016 or entry.id==1017 then row.note="Uses the experimental Fusing model with independent rolls from the starting item and first-on-tie selection. Gwennen's rules and odds are unverified." end
				if entry.id==1027 then row.note="The retained modifier is assumed uniformly selected; modifier count and new rolls use the ordinary rare-item model. Gwennen's rules are unverified." end
				rows[#rows+1]=row
			end
		end
	end
	return {offers=rows,total=count,source=source.source,sourceSha256=source.sourceSha256,reportedPatch=source.reportedPatch,
		note="Reference only: not available crafting actions. Item eligibility, pair generation, coin odds, costs and modifier interactions are not modeled or verified."}
end
return M
