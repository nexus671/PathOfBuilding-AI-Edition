-- cspell:ignore Katakohi ockets
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
function K.catalog(query,limit)
 local rows={};query=(query or ""):lower()
 for id,entry in pairs(K.data().mods) do
  if (id.." "..entry.text):lower():find(query,1,true) then
   rows[#rows+1]={id=id,lines=copyTable(entry.text:split("\n")),requiredLevel=entry.required_level,groups=copyTable(entry.groups)}
  end
 end
 table.sort(rows,function(a,b) return a.id<b.id end)
 for i=#rows,(limit or 50)+1,-1 do rows[i]=nil end
 return rows
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
 local targetReason=M.implicitTargetReason
 function M.implicitTargetReason(model,state,targets)
  local reason=targetReason(model,state,targets);if reason then return reason end
  if model and model.item and model.item.type=="Gloves" and not state.destroyed and not state.veil and not state.katakohiEnchants and not state.harvestEnchant and not model.importedSocketEnchants then
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
   result.katakohiEnchants=K.catalog(query,limit)
   result.katakohiNote="These are possible socket enchantments, not probabilities or a simulated Ducat outcome. Socket and modifier selection rules remain unverified."
  end
  return result
 end
end
return K
