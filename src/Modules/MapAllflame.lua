-- Pinned client descriptions for hypothetical map Allflame plans.
local M={}
local loaded,byId
local function load()
 if loaded then return end
 local root=GetScriptPath();local file=assert(io.open((root~="" and root.."/" or "").."Data/Atlas/map-allflame-3.30.json","rb"))
 local raw=file:read("*a");file:close();loaded=assert(require("dkjson").decode(raw))
 assert(loaded.clientVersion=="3.30.0.4" and type(loaded.items)=="table" and #loaded.items==11,"Invalid map Allflame reference")
 byId={};for _,item in ipairs(loaded.items) do assert(type(item.id)=="string" and not byId[item.id],"Invalid map Allflame ID");byId[item.id]=item end
end
function M.list() load();return copyTable(loaded.items) end
function M.reference() load();return {clientVersion=loaded.clientVersion,sourceCommit=loaded.sourceCommit,baseItemsSha256=loaded.baseItemsSha256,items=copyTable(loaded.items),note="Client descriptions only; current availability, eligibility, stacking, replacement and pack outcomes are unverified."} end
function M.validate(id)
 if id==nil then return nil end
 assert(type(id)=="string" and #id<=240,"Invalid planned Allflame")
 load();assert(byId[id],"Unknown map Allflame");return id
end
function M.describe(id)
 if not id then return nil end
 M.validate(id);local result=copyTable(byId[id]);result.provenance="planned"
 result.note="Conditional plan from 3.30.0.4 client descriptions. Item eligibility, stacking, replacement, other enchantments, corruption order and actual pack outcomes need in-game verification."
 return result
end
return M
