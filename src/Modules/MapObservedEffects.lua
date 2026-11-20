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
-- Project the published stacking rule using a user-supplied example gain.
-- This does not model map reforging, eligibility or the gain distribution.
function M.projectDelirium(currentPercent,currentType,nextType,gain)
 local function number(value,low,high,label)
  assert(type(value)=="number" and value==math.floor(value) and value>=low and value<=high,"Invalid "..label);return value
 end
 local function name(value,label,optional)
  if optional and (value==nil or value=="") then return nil end
  assert(type(value)=="string" and #value<=80 and not value:find("[%c%^]"),"Invalid "..label)
  value=value:match("^%s*(.-)%s*$");assert(value~="","Invalid "..label);return value
 end
 currentPercent=number(currentPercent,0,100,"current Delirium percentage")
 gain=number(gain,5,50,"example Delirium gain")
 currentType=name(currentType,"current reward type",currentPercent==0)
 nextType=name(nextType,"next reward type")
 local same=currentPercent>0 and currentType:lower()==nextType:lower()
 local start=same and currentPercent or 0
 local function outcome(add)
  local percent=math.min(100,start+add)
  return {percent=percent,baseRewardCount=1+math.floor(percent/20)}
 end
 return {currentPercent=currentPercent,currentType=currentType,nextType=nextType,exampleGain=gain,sameType=same,
  minimum=outcome(5),maximum=outcome(50),example=outcome(gain),
  note="Projection only. No map is modified. GGG fixed Delirium Orb use on Nightmare Maps in 3.30.0d. Reward names, specific item eligibility, reforged modifiers, other rewards and gain probabilities are not verified."}
end
-- This visible implicit identifies a Blighted or Blight-ravaged map. Do not
-- infer the variant merely from a map's name or an ordinary Blight encounter.
function M.isBlighted(effects)
 for _,effect in ipairs(effects or {}) do
  if effect.kind=="implicit" and effect.text=="Area is infested with Fungal Growths" then return true end
 end
 return false
end
function M.isBlightRavaged(effects)
 if not M.isBlighted(effects) then return false end
 for _,effect in ipairs(effects or {}) do
  if effect.kind=="implicit" and effect.text=="Can be Anointed up to 9 times" then return true end
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
