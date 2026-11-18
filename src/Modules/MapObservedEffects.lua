-- Preserve copied map lines whose mechanics are not yet modeled.
local M={}
function M.validate(effects)
 if effects==nil then return nil end
 assert(type(effects)=="table" and #effects<=30,"Use at most 30 observed map effects")
 for key in pairs(effects) do
  assert(type(key)=="number" and key==math.floor(key) and key>=1 and key<=#effects,"Invalid observed map effects")
 end
 local result={}
 for _,effect in ipairs(effects) do
  assert(type(effect)=="table" and (effect.kind=="implicit" or effect.kind=="enchant" or effect.kind=="explicit"),"Invalid observed map effect kind")
  assert(type(effect.text)=="string" and #effect.text>=1 and #effect.text<=400 and effect.text:match("%S")
   and not effect.text:find("[%c%^]"),"Invalid observed map effect text")
  result[#result+1]={kind=effect.kind,text=effect.text}
 end
 return #result>0 and result or nil
end
function M.hasExplicit(effects)
 for _,effect in ipairs(effects or {}) do if effect.kind=="explicit" then return true end end
 return false
end
-- This visible implicit identifies a Blighted or Blight-ravaged map. Do not
-- infer the variant merely from a map's name or an ordinary Blight encounter.
function M.isBlighted(effects)
 for _,effect in ipairs(effects or {}) do
  if effect.kind=="implicit" and effect.text=="Area is infested with Fungal Growths" then return true end
 end
 return false
end
return M
