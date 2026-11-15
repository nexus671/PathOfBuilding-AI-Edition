-- cspell:ignore Katakohi
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
function K.extend(M)
 local catalog,decorate,validate=M.catalog,M.decorateItem,M.validateState
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
  local next=copyTable(state);next.katakohiEnchants=copyTable(ids);next.harvestEnchant=nil
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
