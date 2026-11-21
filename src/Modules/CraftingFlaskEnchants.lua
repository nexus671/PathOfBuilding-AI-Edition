-- Utility-flask enchantments from the pinned 3.30 client export.
-- cspell:ignore katakohi
local E={}
local catalog
function E.data()
 if not catalog then
  local root=GetScriptPath();local f=assert(io.open((root~="" and root.."/" or "").."Data/Crafting/FlaskEnchants330.json","rb"))
  local raw=f:read("*a");f:close();catalog=assert(require("dkjson").decode(raw))
 end
 return catalog
end
local methods={instilling="INSTILLING",enkindling="ENKINDLING"}
function E.eligible(model) return model.item.type=="Flask" and model.item.base.tags.utility_flask==true end
function E.entry(id)
 for group,entries in pairs(E.data().pools) do for _,entry in ipairs(entries) do if entry.id==id then return entry,group end end end
end
local function template(entry,group)
 return assert(data.enchantments.UtilityFlask[group][entry.index],"Missing native flask enchantment text")
end
function E.label(id) local entry,group=E.entry(id);return entry and template(entry,group):gsub("/.*$","") or id end
local function bounds(entry,group)
 local a,b=template(entry,group):match("%((%d+)%-(%d+)%)")
 return tonumber(a),tonumber(b)
end
function E.bounds(id) local entry,group=E.entry(id);if entry then return bounds(entry,group) end end
local function identity(lines) local sorted=copyTable(lines);table.sort(sorted);return table.concat(sorted,"\n") end
function E.lines(entry,group,roll)
 local text=template(entry,group)
 if roll~=nil then text=text:gsub("%(%d+%-%d+%)",tostring(roll),1) end
 local lines={};for line in text:gmatch("[^/]+") do lines[#lines+1]=line end
 return lines
end
function E.identify(item)
 local lines={};for _,line in ipairs(item.enchantModLines or {}) do
  local text=StripEscapes(itemLib.formatModLine(line,false) or line.line or ""):gsub(" %(Not supported in PoB yet%)$","")
  lines[#lines+1]=text
 end
 local text=identity(lines);if text=="" then return end
 for group,pool in pairs(E.data().pools) do for _,entry in ipairs(pool) do
  local lo,hi=bounds(entry,group)
  if not lo and text==identity(E.lines(entry,group)) then return {id=entry.id} end
  if lo then for roll=lo,hi do if text==identity(E.lines(entry,group,roll)) then return {id=entry.id,roll=roll} end end end
 end end
end
function E.roll(method,random)
 local group=assert(methods[method],"Unknown flask enchantment currency")
 local pool=E.data().pools[group];local total=0;for _,entry in ipairs(pool) do total=total+entry.weight end
 local pick=random()*total;local selected=pool[#pool]
 for _,entry in ipairs(pool) do pick=pick-entry.weight;if pick<0 then selected=entry;break end end
 local lo,hi=bounds(selected,group)
 return {id=selected.id,roll=lo and lo+math.floor(random()*(hi-lo+1)) or nil}
end
function E.list(query,limit)
 local result={};local search=(query or ""):lower()
 for group,pool in pairs(E.data().pools) do for _,entry in ipairs(pool) do
  local text=template(entry,group)
  if (entry.id.." "..text.." "..group.." orb"):lower():find(search,1,true) then
   local lo,hi=bounds(entry,group);result[#result+1]={id=entry.id,method=group:lower(),text=text,weight=entry.weight,minRoll=lo,maxRoll=hi,rollable=entry.weight>0}
  end
 end end
 table.sort(result,function(a,b) return a.id<b.id end)
 for i=#result,(limit or 50)+1,-1 do result[i]=nil end
 return result
end
function E.validate(model,value)
 assert(E.eligible(model) and type(value)=="table","Invalid utility flask enchantment")
 local entry,group=E.entry(value.id);assert(entry,"Unknown utility flask enchantment")
 local lo,hi=bounds(entry,group)
 if lo then assert(type(value.roll)=="number" and value.roll==math.floor(value.roll) and value.roll>=lo and value.roll<=hi,"Invalid flask enchantment roll")
 else assert(value.roll==nil,"This flask enchantment has no roll") end
 for key in pairs(value) do assert(key=="id" or key=="roll","Unknown flask enchantment field") end
 return entry,group
end
function E.extend(M)
 for method,group in pairs(methods) do M.methods[#M.methods+1]=method;M.labels[method]=group=="INSTILLING" and "Instilling Orb" or "Enkindling Orb" end
 table.sort(M.methods)
 local action,decorate,validate,originalModel,originalCatalog=M.action,M.decorateItem,M.validateState,M.model,M.catalog
 function M.model(raw)
  local model=originalModel(raw)
  if E.eligible(model) then model.initial.flaskEnchant=E.identify(model.item) end
  return model
 end
 function M.catalog(raw,query,limit,initialState,...)
  local result=originalCatalog(raw,query,limit,initialState,...);local model={item=new("Item"):Item(initialState and initialState.baseItem or raw)}
  result.flaskEnchants=E.eligible(model) and E.list(query,limit) or {}
  return result
 end
 local function reason(model,state)
  if state.destroyed or state.corrupted or state.mirrored or state.veil then return "Requires an uncorrupted, usable utility flask." end
  if not E.eligible(model) then return "Requires a utility flask." end
 end
 for method in pairs(methods) do M.methodChecks[method]=reason end
 function M.action(model,state,craft,random)
  local group=methods[craft.method];if not group then return action(model,state,craft,random) end
  local why=reason(model,state);assert(not why,why)
  local result=copyTable(state);result.flaskEnchant=E.roll(craft.method,random)
  result.enchantCleared=nil;result.harvestEnchant=nil;result.katakohiEnchants=nil
  return result
 end
 function M.decorateItem(model,state,item)
  decorate(model,state,item)
  if state.flaskEnchant then
   local entry,group=E.validate(model,state.flaskEnchant);item.enchantModLines={}
   for _,line in ipairs(E.lines(entry,group,state.flaskEnchant.roll)) do item.enchantModLines[#item.enchantModLines+1]={line=line,enchant=true} end
  end
 end
 function M.validateState(model,state)
  if state.flaskEnchant then assert(not state.enchantCleared and not state.harvestEnchant and not state.katakohiEnchants,"Conflicting enchantments");E.validate(model,state.flaskEnchant) end
  local result=validate(model,state)
  if not result.flaskEnchant and not result.enchantCleared and model.initial.flaskEnchant then result.flaskEnchant=copyTable(model.initial.flaskEnchant) end
  return result
 end
 M.limits[#M.limits+1]="Instilling and Enkindling pools use pinned client weights. Replacement and uniformly sampled numerical rolls are experimental; current in-game behavior is unverified."
end
return E
