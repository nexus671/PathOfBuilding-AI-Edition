-- Preserve the observed quality without guessing patch-specific effects.
local M={}
function M.validate(quality)
 if quality==nil then return nil end
 assert(type(quality)=="table" and type(quality.kind)=="string" and #quality.kind>=1 and #quality.kind<=80
  and quality.kind:match("^[%w '%-]+$"),"Invalid map quality type")
 assert(type(quality.value)=="number" and quality.value==math.floor(quality.value)
  and quality.value>=0 and quality.value<=100,"Map quality must be a whole number from 0 to 100")
 return {kind=quality.kind,value=quality.value}
end
return M
