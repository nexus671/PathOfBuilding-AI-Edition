-- Quality guidance for a copied English-language skill or support gem.
-- Does not apply currency or modify a build.
local M={}
local vaalOwner,vaalByEffect
local function vaalCandidates(effect)
 if vaalOwner~=data.gems then
  vaalOwner=data.gems;vaalByEffect={}
  for _,candidate in pairs(data.gems) do if candidate.vaalGem and candidate.secondaryGrantedEffectId then
   local name=candidate.baseTypeName or candidate.name;local key=candidate.secondaryGrantedEffectId
   if name then vaalByEffect[key]=vaalByEffect[key] or {};vaalByEffect[key][name]=true end
  end end
 end
 local result={};for name in pairs(vaalByEffect[effect] or {}) do result[#result+1]=name end;table.sort(result);return result
end
local function clean(line) return (line:gsub("^%s+",""):gsub("%s+$","")) end
function M.inspect(raw,target)
 assert(type(raw)=="string" and #raw>0 and #raw<=24000 and not raw:find("%z"),"Paste one copied gem up to 24 KiB")
 assert(type(target)=="number" and target==math.floor(target) and target>=0 and target<=100,"Choose a whole quality target from 0 to 100")
 raw=raw:gsub("\r\n","\n"):gsub("\r","\n")
 local lines={};for line in (raw.."\n"):gmatch("([^\n]*)\n") do line=clean(line);if line~="" then lines[#lines+1]=line end end
 local class=lines[1] and lines[1]:match("^Item Class:%s*(.+)$")
 assert(class=="Active Skill Gems" or class=="Skill Gems" or class=="Support Skill Gems" or class=="Support Gems","Copy an active or support skill gem with its item class")
 assert(lines[2] and lines[2]:lower()=="rarity: gem","The copied item must be a gem")
 local name=lines[3];assert(name and #name<=160 and not name:find("[%c%^]"),"The copied gem needs a visible name")
 local id=data.gemForBaseName[name:lower()];local gem=id and data.gems[id]
 assert(gem,"The copied gem is not in the bundled gem data")
 local support=class=="Support Skill Gems" or class=="Support Gems"
 local actualSupport=gem.tagString and gem.tagString:find("Support",1,true)~=nil
 assert(support==actualSupport,"The gem name does not match its copied item class")
 local quality,level,corrupted,twice=nil,nil,false,false
 for _,line in ipairs(lines) do
  local q=line:match("^Quality:%s*%+?(%d+)%%")
  if q then assert(quality==nil,"Copied gem has multiple quality values");quality=tonumber(q) end
  local l=line:match("^Level:%s*(%d+)")
  if l then assert(level==nil,"Copied gem has multiple levels");level=tonumber(l) end
  if line=="Corrupted" then corrupted=true elseif line=="Twice Corrupted" then corrupted=true;twice=true end
 end
 quality=quality or 0
 if gem.vaalGem then corrupted=true end
 assert(quality<=100 and (not level or level>=1 and level<=40),"Copied gem level or quality is outside the supported range")
 local plan={name=name,gemId=id,support=support,level=level,quality=quality,corrupted=corrupted,twiceCorrupted=twice,target=target}
 if quality>=target then plan.status="complete";plan.prisms=0
 elseif corrupted then plan.status="unavailable";plan.reason="Gemcutter's Prisms cannot modify a corrupted gem."
 elseif target>20 then plan.status="unavailable";plan.reason="Gemcutter's Prisms stop at 20% quality. Higher quality requires a different method."
 else plan.status="available";plan.prisms=target-quality end
 plan.note="A Gemcutter's Prism adds 1% quality to an eligible uncorrupted gem, up to 20%. Corruption outcomes are reference ranges, not a simulation."
 local corruption={vaalOrb={available=not corrupted},lapidaryLens={available=corrupted and not twice,canDestroy=true},maxQuality=23,
  note="Conditional ranges use historical Vaal Orb effects. Availability checks corruption state only; other eligibility, current outcome weights and Lapidary Lens effects need verification."}
 if corrupted then corruption.vaalOrb.reason="A Vaal Orb cannot normally be used on an already-corrupted gem."
 else corruption.lapidaryLens.reason="The Lapidary Lens requires an already-corrupted gem." end
 if twice then corruption.lapidaryLens.reason="The Lapidary Lens cannot corrupt a twice-corrupted gem again." end
 if quality<=23 then corruption.historicalQualityRange={min=math.max(0,quality-10),max=math.min(23,quality+10)} end
 if type(gem.naturalMaxLevel)=="number" and gem.naturalMaxLevel>=1 then
  corruption.maxLevel=gem.naturalMaxLevel+1
  if level and level<=corruption.maxLevel then corruption.historicalLevelRange={min=math.max(1,level-1),max=math.min(corruption.maxLevel,level+1)} end
 end
 corruption.vaalCandidates=not support and not gem.vaalGem and vaalCandidates(gem.grantedEffectId) or {}
 plan.corruption=corruption
 if plan.status=="available" then
  local title="Quality: "..name;if #title>120 then title="Improve gem quality" end
  plan.milestoneDraft={title=title,kind="gems",priority=3,done=false,dependencies={},notes=string.format("%s was copied at %d%% quality%s. Use %d Gemcutter's Prism%s to reach %d%% quality. Recheck the gem if it changes; this is a saved plan, not recorded spending.",name,quality,level and " and level "..level or "",plan.prisms,plan.prisms==1 and "" or "s",target)}
 end
 return plan
end
return M
