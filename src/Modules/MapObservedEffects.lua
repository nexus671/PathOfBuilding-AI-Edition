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
-- Only a unique, complete pair of copied explicit lines is interpreted.
function M.delirium(effects)
 local percent,reward
 for _,effect in ipairs(effects or {}) do if effect.kind=="explicit" then
  local depth=effect.text:match("^Players in Area are (%d+)%% Delirious$")
  local kind=effect.text:match("^Delirium Reward Type: (.+)$")
  if depth then
   if percent then return nil end
   percent=tonumber(depth);if percent<1 or percent>100 then return nil end
  elseif kind then
   if reward or not kind:match("%S") then return nil end
   reward=kind
  end
 end end
 if not percent or not reward then return nil end
 return {percent=percent,rewardType=reward,baseRewardCount=1+math.floor(percent/20)}
end
-- This visible implicit identifies a Blighted or Blight-ravaged map. Do not
-- infer the variant merely from a map's name or an ordinary Blight encounter.
function M.isBlighted(effects)
 for _,effect in ipairs(effects or {}) do
  if effect.kind=="implicit" and effect.text=="Area is infested with Fungal Growths" then return true end
 end
 return false
end
function M.note(effects)
 if not effects then return "" end
 if M.isBlighted(effects) then return " Blighted rare-only encounter modifiers are excluded; other mechanics of observed effects are not modeled and can change results." end
 if M.delirium(effects) then return " Base Delirium reward count follows the 3.30 notes; other observed effects and modifier interactions are not modeled and can change results." end
 return " Observed effects are not modeled and can change results."
end
return M
