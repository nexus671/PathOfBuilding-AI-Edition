-- cspell:ignore Deepwater Katakohi ockets tatt
-- Pinned modifier descriptions for reviewing socket enchantments. Random rolls
-- are deliberately not inferred from the individual spawn-weight tags.
local K={}
local cached
function K.data()
 if not cached then
  local root=GetScriptPath();local file=assert(io.open((root~="" and root.."/" or "").."Data/Crafting/Katakohi.json","rb"))
  local raw=file:read("*a");file:close();cached=assert(require("dkjson").decode(raw))
 end
 return cached
end
function K.catalog(query,limit,model)
 local rows={};query=(query or ""):lower();local eligible
 if model then eligible={};for _,entry in ipairs(K.pool(model)) do eligible[entry.id]=true end end
 for id,entry in pairs(K.data().mods) do
  if (id.." "..entry.text):lower():find(query,1,true) then
   local row={id=id,lines=copyTable(entry.text:split("\n")),requiredLevel=entry.required_level,groups=copyTable(entry.groups)}
   if eligible then row.modeledEligible=eligible[id]==true end;rows[#rows+1]=row
  end
 end
 table.sort(rows,function(a,b) return a.id<b.id end)
 for i=#rows,(limit or 50)+1,-1 do rows[i]=nil end
 return rows
end
-- Candidate pools follow the base's attribute requirements. The client tags
-- describe the pools, but do not establish server-side roll probabilities.
function K.pool(model)
 local req=model.item.base.req or {};local tags={deepwater_str_tatt=(req.str or 0)>0,deepwater_dex_tatt=(req.dex or 0)>0,deepwater_int_tatt=(req.int or 0)>0}
 local result={}
 for id,entry in pairs(K.data().mods) do if entry.required_level<=model.item.itemLevel then
  for _,weight in ipairs(entry.spawn_weights) do if tags[weight.tag] and weight.weight>0 then result[#result+1]={id=id,weight=weight.weight};break end end
 end end
 table.sort(result,function(a,b) return a.id<b.id end);return result
end
-- Recognize only complete, unambiguous imports. Unknown enchantments must not
-- be silently presented as an empty set in the hypothetical editor.
function K.identify(item)
 if item.type~="Gloves" then return nil end
 local lines=item.enchantModLines or {};if #lines==0 then return {} end
 local effects={}
 for id,entry in pairs(K.data().mods) do
  local parts=entry.text:split("\n");local text=parts[2]
  if effects[text] then effects[text]=false else effects[text]=id end
 end
 local ids,seen,reduction={}, {},0
 for _,entry in ipairs(lines) do
  local line=entry.line or "";local count=line:match("^%-(%d+) to maximum [Ss]ockets$")
  if count then reduction=reduction+tonumber(count)
  else
   local id=effects[line]
   if not id or seen[id] then return nil end
   seen[id]=true;ids[#ids+1]=id
  end
 end
 if #ids==0 or #ids>3 or reduction~=#ids then return nil end
 return ids
end
function K.extend(M)
 local catalog,decorate,validate=M.catalog,M.decorateItem,M.validateState
 local action=M.action
 M.methods[#M.methods+1]="ducat_katakohi";M.labels.ducat_katakohi="Katakohi's Ducat";table.sort(M.methods)
 M.methodChecks.ducat_katakohi=function(model,state)
  if model.item.type~="Gloves" then return "Katakohi's Ducat requires gloves." end
  if state.destroyed or state.corrupted or state.mirrored or state.veil then return "Katakohi's Ducat requires an uncorrupted, usable item without a pending unveil." end
  if #(state.sockets or {})==0 then return "Add at least one ordinary socket before etching." end
  for _,socket in ipairs(state.sockets) do if socket.color=="A" then return "Abyssal socket interactions are not modeled for this Ducat." end end
  if #K.pool(model)==0 then return "No eligible socket enchantments were found for this base and item level." end
 end
 function M.action(model,state,craft,random)
  if craft.method~="ducat_katakohi" then return action(model,state,craft,random) end
  local reason=M.methodChecks.ducat_katakohi(model,state);assert(not reason,reason)
  local next=copyTable(state);local pool=K.pool(model)
  -- All distributions and retained socket/link rules are model assumptions.
  local count=math.floor(random()*math.min(3,#next.sockets))+1;local removed={}
  for _=1,count do
   local choices={};for i in ipairs(next.sockets) do if not removed[i] then choices[#choices+1]=i end end
   removed[choices[math.floor(random()*#choices)+1]]=true
  end
  local retained,previous,group={},nil,-1
  for i,socket in ipairs(next.sockets) do if not removed[i] then
   if not previous or previous.index~=i-1 or previous.group~=socket.group then group=group+1 end
   retained[#retained+1]={color=socket.color,group=group};previous={index=i,group=socket.group}
  end end
  local ids={}
  for _=1,count do
   local total=0;for _,entry in ipairs(pool) do total=total+entry.weight end
   assert(total>0,"Not enough modeled socket enchantments for this base")
   local roll=random()*total;local chosen
   for i,entry in ipairs(pool) do roll=roll-entry.weight;if roll<0 then chosen=i;break end end
   local entry=table.remove(pool,assert(chosen,"Could not select a socket enchantment"));ids[#ids+1]=entry.id
  end
  next.sockets=retained;next.katakohiEnchants=ids;next.harvestEnchant=nil;next.enchantCleared=nil
  return next
 end
 local targetReason=M.implicitTargetReason
 function M.implicitTargetReason(model,state,targets)
  local reason=targetReason(model,state,targets);if reason then return reason end
  if model and model.item and model.item.type=="Gloves" and not state.destroyed and not state.veil and not state.enchantCleared and not state.katakohiEnchants and not state.harvestEnchant and not model.importedSocketEnchants then
   for _,group in ipairs(targets) do if group.scope=="enchant" then return "The imported enchantments could not be identified. Set observed socket enchantments in the hypothetical item editor before using an enchantment target." end end
  end
 end
 local originalModel=M.model
 function M.model(raw)
  local model=originalModel(raw)
  if model.item.type=="Gloves" then
   for id,entry in pairs(K.data().mods) do
    if entry.required_level<=model.item.itemLevel then
     local parts=entry.text:split("\n")
     model.byId[id]={type="Enchant",level=entry.required_level,group=entry.groups[1],modTags={},parts[2]}
     model.special[id]=true
    end
   end
   model.importedSocketEnchants=K.identify(model.item)
  end
  return model
 end
 function M.decorateItem(model,state,item)
  decorate(model,state,item)
  if state.katakohiEnchants then
   item.enchantModLines={}
   for _,id in ipairs(state.katakohiEnchants) do
    local entry=assert(K.data().mods[id],"Unknown socket enchantment")
    for _,line in ipairs(entry.text:split("\n")) do item.enchantModLines[#item.enchantModLines+1]={line=line,enchant=true} end
   end
  end
 end
 function M.validateState(model,state)
  if state.katakohiEnchants then
   assert(model.item.type=="Gloves" and type(state.katakohiEnchants)=="table" and #state.katakohiEnchants<=3,"Invalid socket enchantments")
   local seen={}
   for _,id in ipairs(state.katakohiEnchants) do
    local entry=assert(K.data().mods[id],"Unknown socket enchantment")
    assert(not seen[id] and entry.required_level<=model.item.itemLevel,"Duplicate or unavailable socket enchantment")
    seen[id]=true
   end
  end
  return validate(model,state)
 end
 function M.setKatakohi(model,state,ids)
  assert(model.item.type=="Gloves" and not state.destroyed and not state.veil,"Socket enchantments require usable gloves")
  assert(type(ids)=="table" and #ids<=3,"Choose up to three socket enchantments")
  local next=copyTable(state);next.katakohiEnchants=copyTable(ids);next.harvestEnchant=nil;next.enchantCleared=nil
  local limit=M.socketLimit(model,next)
  while #(next.sockets or {})>limit do table.remove(next.sockets) end
  return M.validateState(model,next)
 end
 function M.catalog(raw,query,limit,initialState,...)
  local result=catalog(raw,query,limit,initialState,...)
  local item=new("Item"):Item(initialState and initialState.baseItem or raw)
  if item.type=="Gloves" then
   result.katakohiEnchants=K.catalog(query,limit,{item=item})
   result.katakohiNote="These are possible socket enchantments, not probabilities. The experimental historical Ducat simulation assumes attribute pools, socket selection and modifier weights; those rules remain unverified."
  end
  return result
 end
end
return K
