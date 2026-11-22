-- Review bounded ordinary base implicits as hypothetical starting rolls.
local M={}
local function displayed(item,index)
 local line=item.implicitModLines[index]
 return line and StripEscapes(itemLib.formatModLine(line,false) or "") or nil
end
local function sameMetadata(left,right)
 if not left or not right then return false end
 for _,key in ipairs({"unscalable","disabled","corrupted","crafted","fractured","enchant","exarch","eater"}) do
  if not not left[key]~=not not right[key] then return false end
 end
 if left.modGroup~=right.modGroup or left.extra~=right.extra then return false end
 local function tags(line)
  local result={};for _,tag in ipairs(line.modTags or {}) do if type(tag)~="string" then return nil end;result[#result+1]=tag end
  table.sort(result);return table.concat(result,"\0")
 end
 local a,b=tags(left),tags(right);return a~=nil and a==b
end
function M.options(sim,model,state)
 if state.corrupted or state.mirrored or model.item.synthesised or state.implicits or state.corruptedImplicits or state.vendorImplicit or state.baseImplicitRetained or state.fossilImplicitReplacement then
  return nil,"Only uncorrupted ordinary base implicits are supported."
 end
 if model.blessed330 or model.blessed330Unresolved or model.baseImplicitUnresolved or state.baseImplicit330 or #(model.item.modMagnitudeMods or {})>0 then
  return nil,"This implicit needs a separate model before selecting a roll."
 end
 local templates=model.baseImplicitTemplates
 if not templates or #templates==0 or #templates~=#model.item.implicitModLines then return nil,"The ordinary base implicits are not recognized." end
 local item=sim.toItem(model,state)
 if #(item.modMagnitudeMods or {})>0 then return nil,"Modifier-magnitude effects need a separate implicit model." end
 if #item.implicitModLines~=#templates then return nil,"The current implicits differ from the base." end
 local ranges={}
 for i=1,#templates do
  local range=state.baseImplicitRanges and state.baseImplicitRanges[i] or model.normalizedBaseImplicitRanges and model.normalizedBaseImplicitRanges[i] or model.item.implicitModLines[i].range or 0.5
  ranges[i]=type(range)=="table" and copyTable(range) or range
 end
 local options={}
 for index,template in ipairs(templates) do
  local bounds={};local combinations=1
  for low,high in template:gmatch("%((%-?%d+)%-(%-?%d+)%)") do
   low,high=tonumber(low),tonumber(high);bounds[#bounds+1]={low,high}
   if high<=low or high-low>100 then combinations=513 else combinations=combinations*(high-low+1) end
  end
  local _,count=template:gsub("%(%-?%d+%.?%d*%-%-?%d+%.?%d*%)","")
  if count==#bounds and count>=1 and count<=2 and combinations<=512 then
   local scalar=item:GetModLineValueScalar(item.implicitModLines[index],"implicit");local seen={}
   for choice=0,combinations-1 do
    local remaining=choice;local values,rolls={},{}
    for i,bound in ipairs(bounds) do
     local width=bound[2]-bound[1]+1;values[i]=bound[1]+remaining%width
     remaining=math.floor(remaining/width);rolls[i]=(values[i]-bound[1])/(bound[2]-bound[1])
    end
    local roll=count==1 and rolls[1] or rolls;local label=itemLib.applyRange(template,roll,scalar)
    if seen[label] then return nil,"Multiple base rolls display the same value; use a recognized source item." end
    seen[label]=true;local nextRanges=copyTable(ranges);nextRanges[index]=roll
    local candidate=copyTable(state);candidate.baseImplicitRanges=nextRanges;candidate.baseImplicitReconstructed=true
    local valid,staged=pcall(sim.validateState,model,candidate)
    if not valid then return nil,"The other base implicits cannot be preserved safely." end
    local rendered,changed=pcall(sim.toItem,model,staged)
    if not rendered or #changed.implicitModLines~=#templates or displayed(changed,index)~=label then return nil,"This implicit value cannot be represented safely." end
    for other=1,#templates do
     if not sameMetadata(item.implicitModLines[other],changed.implicitModLines[other]) then return nil,"Implicit modifier tags or properties cannot be preserved safely." end
     if other~=index and displayed(changed,other)~=displayed(item,other) then return nil,"The other base implicits cannot be preserved safely." end
    end
    local value=table.concat(values,",");local id=#templates==1 and value or index..":"..value
    options[#options+1]={id=id,label=label,category=#templates>1 and "Implicit "..index or nil,lineIndex=index,roll=roll,
     statePatch={baseImplicitRanges=nextRanges,baseImplicitReconstructed=true},details={label,"Hypothetical starting implicit. No currency is spent and equipped gear is unchanged.","Other base implicits stay at their current modeled values. Confirm values on the actual item; game rounding and catalyst behavior may differ."}}
   end
  end
 end
 if #options==0 then return nil,"No supported variable ordinary base implicit was found." end
 return options
end
local function sameRoll(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~="table" then return a==b end
 if #a~=#b then return false end
 for i=1,#a do if a[i]~=b[i] then return false end end
 return true
end
function M.apply(sim,model,state,roll,lineIndex)
 local options,reason=M.options(sim,model,state);assert(options,reason);lineIndex=lineIndex or 1
 for _,entry in ipairs(options) do if sameRoll(entry.roll,roll) and entry.lineIndex==lineIndex then
  local candidate=copyTable(state);candidate.baseImplicitRanges=copyTable(entry.statePatch.baseImplicitRanges);candidate.baseImplicitReconstructed=true
  return sim.validateState(model,candidate)
 end end
 error("Choose a listed base implicit roll")
end
return M
