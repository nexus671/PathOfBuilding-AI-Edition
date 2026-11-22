-- Review a bounded ordinary base implicit as a hypothetical starting roll.
local M={}
function M.options(sim,model,state)
 if state.corrupted or state.mirrored or model.item.synthesised or state.implicits or state.corruptedImplicits or state.vendorImplicit or state.baseImplicitRetained or state.fossilImplicitReplacement then
  return nil,"Only an uncorrupted ordinary base implicit is supported."
 end
 if model.blessed330 or model.blessed330Unresolved or model.baseImplicitUnresolved or state.baseImplicit330 or #(model.item.modMagnitudeMods or {})>0 then
  return nil,"This implicit needs a separate model before selecting a roll."
 end
 local templates=model.baseImplicitTemplates
 if not templates or #templates~=1 or #model.item.implicitModLines~=1 then return nil,"This base does not have one recognized ordinary implicit." end
 local template=templates[1];local low,high=template:match("%((%-?%d+)%-(%-?%d+)%)");low,high=tonumber(low),tonumber(high)
 local _,count=template:gsub("%(%-?%d+%-%-?%d+%)","")
 if count~=1 or not low or not high or high<=low or high-low>100 then return nil,"This implicit needs a separate multi-value or wide-range model." end
 local item=sim.toItem(model,state)
 if #(item.modMagnitudeMods or {})>0 then return nil,"Modifier-magnitude effects need a separate implicit model." end
 local line=item.implicitModLines[1]
 if not line then return nil,"The base implicit is not present in this state." end
 local scalar=item:GetModLineValueScalar(line,"implicit");local seen,options={},{}
 for value=low,high do
  local roll=(value-low)/(high-low);local label=itemLib.applyRange(template,roll,scalar)
  if seen[label] then return nil,"Multiple base rolls display the same value; use a recognized source item." end
  seen[label]=true;options[#options+1]={id=tostring(value),label=label,roll=roll,details={label,"Hypothetical starting implicit. No currency is spent and equipped gear is unchanged.","Confirm the value on the actual base; game rounding and catalyst behavior may differ."}}
 end
 return options
end
function M.apply(sim,model,state,roll)
 local options,reason=M.options(sim,model,state);assert(options,reason)
 local found=false;for _,entry in ipairs(options) do if entry.roll==roll then found=true;break end end
 assert(found,"Choose a listed base implicit roll")
 local candidate=copyTable(state);candidate.baseImplicitRanges={roll};candidate.baseImplicitReconstructed=true
 return sim.validateState(model,candidate)
end
return M
