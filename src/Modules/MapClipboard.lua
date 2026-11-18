-- Import only uniquely resolved ordinary-map clipboard text. No guessing.
local map=require("Modules.MapCraftingData")
local M={}
local function readable(s)
 return (s:gsub("%[[^%]|]+|([^%]]+)%]","%1"):gsub("%[([^%]]+)%]","%1"))
end
local function clean(s)
 return readable(s):gsub("(%-?%d+)%(%-?%d+%-%-?%d+%)","%1"):gsub("^%s+",""):gsub("%s+$","")
end
local function matcher(template)
 local parts,ranges={},{};local at=1
 local function escaped(value) return (value:gsub("([^%w])","%%%1")) end
 while true do
  local first,last,low,high=template:find("%((%-?%d+)%-(%-?%d+)%)",at)
  if not first then parts[#parts+1]=escaped(template:sub(at));break end
  parts[#parts+1]=escaped(template:sub(at,first-1));parts[#parts+1]="(%-?%d+)"
  ranges[#ranges+1]={tonumber(low),tonumber(high)};at=last+1
 end
 local pattern="^"..table.concat(parts).."$"
 return function(line)
  local captures={line:match(pattern)};if #captures==0 then return false end
  local values={};for i,range in ipairs(ranges) do local value=tonumber(captures[i]);if not value or value<range[1] or value>range[2] then return false end;values[#values+1]=value end
  return true,values
 end
end
local function implicitFrom(line,level)
 local module=require("Modules.MapCorruptionImplicits");local matches={}
 for _,entry in ipairs(module.list()) do
  local display=module.describe({id=entry.id},level);local template=display.text:gsub(" %(legacy%)$","")
  if matcher(template)(line) then
   local value=display.min~=display.max and tonumber(line:match("%-?%d+")) or nil
   matches[#matches+1]={id=entry.id,value=value}
  end
 end
 assert(#matches<=1,"The map implicit matches multiple identities")
 return matches[1]
end
function M.parse(raw,checkpoint)
 assert(type(raw)=="string" and #raw>0 and #raw<=24000 and not raw:find("\0"),"Paste a copied map up to 24 KiB")
 raw=raw:gsub("\r\n","\n"):gsub("\r","\n")
 local class=raw:match("Item Class: ([^\n]+)");assert(not class or class=="Maps","Only ordinary maps are supported")
 local rarity=assert(raw:match("Rarity: (%a+)"),"The copied map has no rarity"):lower()
 assert(rarity=="normal" or rarity=="magic" or rarity=="rare","Only normal, magic and rare maps are supported")
 assert(not raw:find("\nUnidentified",1,true),"Identify the map before importing it")
 assert(not raw:find("\nMirrored",1,true),"Mirrored maps are not supported")
 local itemTier=tonumber(raw:match("Rarity: [^\n]+\n[^\n]*Map %(Tier (%d+)%)") or raw:match("Rarity: [^\n]+\n[^\n]+\n[^\n]*Map %(Tier (%d+)%)"))
 local displayedTier=tonumber(raw:match("\nMap Tier:%s*(%d+)"))
 assert(not itemTier or not displayedTier or itemTier==displayedTier,"The map item's tier does not match its displayed tier")
 local tier=displayedTier or itemTier;local level=tonumber(raw:match("\nItem Level:%s*(%d+)"))
 assert(tier and tier>=1 and tier<=17,"Use a map with tier 1 to 17")
 assert(level and level>=1 and level<=100,"The copied map needs its item level")
 local quality
 for line in raw:gmatch("[^\n]+") do
  if line:match("^Quality[%s:(]") then
   assert(not quality,"The copied map has multiple quality lines")
   local kind,value=line:match("^Quality %(([%w '%-]+)%)%s*:%s*%+?(%d+)%%")
   if not kind then value=line:match("^Quality%s*:%s*%+?(%d+)%%");kind=value and "Unspecified" or nil end
   assert(kind and value,"The map quality line is not supported")
   quality=require("Modules.MapQuality").validate({kind=kind,value=tonumber(value)})
  end
 end
 local header=assert(raw:match("Rarity: [^\n]+\n(.-)\n%-%-%-%-%-%-%-%-"),"The copied map has no item header")
 if itemTier and header:find("Blighted Map (Tier ",1,true) then
  local marked=false
  for line in raw:gmatch("[^\n]+") do if line=="Area is infested with Fungal Growths (implicit)" then marked=true;break end end
  assert(marked,"A copied Blighted map needs its visible Blight implicit; paste the complete item text")
 end
 local matches,exact,longest={},false,0
 if itemTier then
  local id="Metadata/Items/Maps/MapKeyTier"..itemTier
  assert(map.source().bases[id],"The tier-based map item is not in the current catalogue")
  if rarity~="magic" then
   local name=header:match("([^\n]+)$")
   local blighted=raw:find("\nArea is infested with Fungal Growths (implicit)",1,true)
   assert(name=="Map (Tier "..itemTier..")" or blighted and name=="Blighted Map (Tier "..itemTier..")","The map item header is not supported")
  end
  matches={id}
 end
 for id,base in pairs(map.source().bases) do
  if not itemTier and id:match("^Metadata/Items/Maps/MapWorlds") and base.name then
   local whole=false;for line in header:gmatch("[^\n]+") do if line==base.name then whole=true;break end end
   local hit=header:find(base.name,1,true)~=nil
   if whole and not exact then matches={};exact=true;longest=0 end
   if (whole or hit and not exact) and #base.name>=longest then
    if #base.name>longest then matches={};longest=#base.name end
    matches[#matches+1]=id
   end
  end
 end
 assert(#matches==1,#matches==0 and "The map base is not in the supported map catalogue" or "The copied map base is ambiguous")
 local nightmare=map.isNightmare(matches[1]);assert(nightmare == (tier==17),"Nightmare maps require tier 17; ordinary maps require tier 1 to 16")
 assert(not nightmare or rarity=="rare","Nightmare maps require rare rarity")
 local corrupted=raw:match("\nCorrupted\n")~=nil or raw:match("\nCorrupted$")~=nil
 assert(not corrupted or rarity=="rare","Corrupted magic and normal maps are not yet supported")
 local _,levelEnd=raw:find("\nItem Level:%s*%d+");local tail=raw:sub(assert(levelEnd,"The copied map needs its item level")+1)
 local lines,implicit,observed={},nil,{}
 local deliriumDepth,deliriumReward
 for rawLine in tail:gmatch("[^\n]+") do
  local line=clean(rawLine)
  if line:match(" %(enchant%)$") then
   observed[#observed+1]={kind="enchant",text=line:gsub(" %(enchant%)$","")}
  elseif line:match(" %(implicit%)$") then
   local value=line:gsub(" %(implicit%)$","")
   local known=corrupted and implicitFrom(value,level) or nil
   if known and not implicit then implicit=known else observed[#observed+1]={kind="implicit",text=value} end
  elseif line:match("^Players in Area are %d+%% Delirious$") then
   assert(not deliriumDepth,"The copied map has multiple Delirious percentages")
   local depth=tonumber(line:match("(%d+)%%"));assert(depth>=1 and depth<=100,"The copied Delirious percentage is out of range")
   deliriumDepth=line
  elseif line:match("^Delirium Reward Type: .+$") then
   assert(not deliriumReward,"The copied map has multiple Delirium reward types");deliriumReward=line
  elseif line~="" and not line:match("^%-+$") and not line:match("^%b{}$") and not line:match("^Monster Level:") and not line:match("^Modifiable only with ") and line~="Corrupted" and not line:match("^Travel to this Map") then
   lines[#lines+1]=line
  end
 end
 if deliriumDepth or deliriumReward then
  assert(rarity=="rare" and deliriumDepth and deliriumReward,"A Delirious map needs both its percentage and reward type")
  observed[#observed+1]={kind="explicit",text=deliriumDepth};observed[#observed+1]={kind="explicit",text=deliriumReward}
 end
 observed=require("Modules.MapObservedEffects").validate(observed)
 assert(#lines<=60,"The copied map has too many modifier lines")
 assert(rarity=="normal" or #lines>0,"The copied magic or rare map has no supported visible modifiers")
 local candidates,offset={},0
 if nightmare then
  -- Client spawn tags split Nightmare modifiers into initial and unlocked
  -- pools. A copied item is already rolled, so search both pools without
  -- assuming the order in which its modifiers were generated.
  local tags=map.baseTags(matches[1]);tags.uber_tier_map=true
  for _,mod in pairs(map.source().mods) do for _,tag in ipairs(mod.adds_tags or {}) do if tag:match("^has_uber_map_") then tags[tag]=true end end end
  local entries=map.candidates(tags,level,{},checkpoint)
  for _,entry in ipairs(entries) do
   local effect=map.summarize({entry.id}).effects[1];local tests={}
   for _,line in ipairs(effect.lines) do local template=clean(line);tests[#tests+1]={match=matcher(template),template=template,variable=template:find("%((%-?%d+)%-(%-?%d+)%)")~=nil} end
   if #tests>0 then candidates[#candidates+1]={id=entry.id,side=entry.side,groups=entry.groups,tests=tests} end
  end
 elseif rarity~="normal" then repeat
  local page=map.inspect(matches[1],tier,level,{},"",offset,100,checkpoint,rarity,nil,corrupted,nil,nil,observed)
  for _,entry in ipairs(page.candidates) do
   local effect=map.summarize({entry.id}).effects[1];local tests={}
   for _,line in ipairs(effect.lines) do local template=clean(line);tests[#tests+1]={match=matcher(template),template=template,variable=template:find("%((%-?%d+)%-(%-?%d+)%)")~=nil} end
   if #tests>0 then candidates[#candidates+1]={id=entry.id,side=entry.side,groups=entry.groups,tests=tests} end
  end
  offset=page.nextOffset
 until not offset end
 local starts,covered={},{};for pos=1,#lines do starts[pos]={};for _,entry in ipairs(candidates) do
  local ok=pos+#entry.tests-1<=#lines;local captures={}
  if ok then for i,test in ipairs(entry.tests) do
   local matched,values=test.match(lines[pos+i-1]);if not matched then ok=false;break end
   for _,value in ipairs(values) do captures[#captures+1]=value end
  end end
  if ok then
   local mod=map.source().mods[entry.id];local values,variables={},{}
   for i,stat in ipairs(mod.stats or {}) do values[i]=stat.min;if stat.min~=stat.max then variables[#variables+1]=i end end
   local known=#variables==0
   if #variables>0 and #variables==#captures and #variables<=4 then
    -- Try only range-compatible assignments, then require the native stat
    -- renderer to reproduce every variable line. Multiple distinct valid
    -- assignments remain unknown rather than guessing a stat ordering.
    local assigned,solutions={},{};local seen={}
    local function assign(index)
     if #solutions>1 then return end
     if index>#variables then
      local replacements=require("Modules.MapRollValues").render(mod,values)
      for i,test in ipairs(entry.tests) do if test.variable then
       local matched=false;for source,rendered in pairs(replacements) do if clean(source)==test.template and clean(rendered)==lines[pos+i-1] then matched=true;break end end
       if not matched then return end
      end end
      local key=table.concat(values,":");if not seen[key] then seen[key]=true;solutions[#solutions+1]=copyTable(values) end
      return
     end
     local statIndex=variables[index];local stat=mod.stats[statIndex]
     for i,value in ipairs(captures) do if not assigned[i] and value>=stat.min and value<=stat.max then
      assigned[i]=true;values[statIndex]=value;assign(index+1);assigned[i]=nil
     end end
    end
    assign(1);if #solutions==1 then values=solutions[1];known=true end
   end
   starts[pos][#starts[pos]+1]={id=entry.id,side=entry.side,groups=entry.groups,tests=entry.tests,values=known and values or nil}
   for i=pos,pos+#entry.tests-1 do covered[i]=true end
  end
 end;if checkpoint and pos%4==0 then checkpoint() end end
 for index,line in ipairs(lines) do if not covered[index] then error("Unrecognized map modifier: "..line:sub(1,180),0) end end
 local solutions,used,groups,chosen={}, {},{},{};local counts={prefix=0,suffix=0};local visited=0
 local function search(pos)
  visited=visited+1;assert(visited<=20000,"Map modifier matching exceeded its safety limit")
  if pos>#lines then
   local ids,rolls={},{};for _,entry in ipairs(chosen) do ids[#ids+1]=entry.id;if entry.values then rolls[#rolls+1]={id=entry.id,values=copyTable(entry.values)} end end
   solutions[#solutions+1]={ids=ids,rolls=rolls};return #solutions>=2
  end
  for _,entry in ipairs(starts[pos]) do
   local legal=not used[entry.id] and #chosen<(corrupted and 9 or rarity=="magic" and 2 or 6) and (corrupted or counts[entry.side]<(rarity=="magic" and 1 or 3))
   for _,group in ipairs(entry.groups or {}) do if groups[group] then legal=false end end
   if legal then
    used[entry.id]=true;counts[entry.side]=counts[entry.side]+1;for _,group in ipairs(entry.groups or {}) do groups[group]=true end;chosen[#chosen+1]=entry
    local stop=search(pos+#entry.tests)
    chosen[#chosen]=nil;used[entry.id]=nil;counts[entry.side]=counts[entry.side]-1;for _,group in ipairs(entry.groups or {}) do groups[group]=nil end
    if stop then return true end
   end
  end
 end
 search(1)
 assert(#solutions>0,"Some copied modifier lines could not be matched to the current map data; the existing draft was not changed")
 assert(#solutions==1,"The copied modifiers match multiple identities; select them manually instead")
 local state={baseId=matches[1],tier=tier,itemLevel=level,rarity=rarity,selected=solutions[1].ids,rolls=solutions[1].rolls,corrupted=corrupted or nil,implicit=implicit,quality=quality,observedEffects=observed}
 if rarity~="normal" then map.inspect(state.baseId,tier,level,state.selected,"",0,1,checkpoint,rarity,nil,corrupted,implicit,nil,observed) end
 local qualityEffect=require("Modules.MapQuality").effect(quality)
 return {state=state,notes={"Modifier identities match pinned data. Verified exact values are retained; other values remain ranges.",quality and ("Quality: "..quality.kind.." +"..quality.value.."%. "..(qualityEffect.supported and qualityEffect.text or "Effect not modeled")..".") or "No quality recorded.",observed and (#observed.." additional effect lines are recorded but not modeled; they can change results.") or (nightmare and "Nightmare Chaos estimates use an experimental draw order and unverified odds." or itemTier and "The tier-based map item is independent of the Atlas destination." or "This named map base is historical; verify older items separately.")}}
end
return M
