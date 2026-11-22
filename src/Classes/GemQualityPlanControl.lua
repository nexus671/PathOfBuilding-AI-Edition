local ui=require("Modules.PlanningUI")
local planner=require("Modules.GemQualityPlan")
local M={}
function M.Open(build)
 assert(build,"Open a build before planning a gem")
 local c={};local raw,result,savedKey,currentKey;local route="prisms";local w,h=math.min(720,main.screenW-40),math.min(430,main.screenH-60)
 ui.description(c,"intro",16,28,w-32,48,{"Paste a copied skill or support gem to plan its quality.","This is a local guide; it does not change the gem or spend currency."},14)
 ui.label(c,"targetLabel",16,90,"Target quality (%)",14)
 c.target=new("EditControl"):EditControl(ui.anchor,{16,110,128,26},"20",nil,nil,3)
 c.result=new("TextListControl"):TextListControl(ui.anchor,{16,152,w-32,h-224},nil,{})
 local function planKey() return currentKey end
 local function refresh()
  currentKey=raw and require("sha1")(raw..":"..c.target.buf..":"..route) or nil
  local lines
  if not raw then result=nil;lines={"Paste a gem copied from the game to begin."}
  else
   local ok,value=pcall(planner.inspect,raw,tonumber(c.target.buf))
   if not ok then result=nil;lines={ui.errorText(value)}
   else
    result=value;if route=="vendor" and not value.vendorRecipe.available then route="prisms";currentKey=raw and require("sha1")(raw..":"..c.target.buf..":"..route) or nil end
    lines={value.name.." | "..(value.level and "Level "..value.level or "Level unknown").." | Quality "..value.quality.."%",value.corrupted and "Corrupted" or "Uncorrupted"}
    if value.status=="complete" then lines[#lines+1]="Target already reached."
    elseif route=="vendor" then lines[#lines+1]="Vendor route: 1 Gemcutter's Prism; returns a level 1, 20% quality gem.";lines[#lines+1]="Releveling is required. Verify the vendor offer and special properties."
    elseif value.status=="available" then lines[#lines+1]="Use "..value.prisms.." Gemcutter's Prism"..(value.prisms==1 and "" or "s").." to reach "..value.target.."% quality."
    else lines[#lines+1]=value.reason end
    lines[#lines+1]=value.note
    if savedKey and savedKey==planKey() then lines[#lines+1]="Added to Journey. Save the build to keep it." end
   end
  end
  c.result.list=ui.rows(lines,w-60,14)
 end
 c.target.changeFunc=refresh
 local function selectedDraft() return result and (route=="vendor" and result.vendorMilestoneDraft or result.milestoneDraft) end
 c.routes=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{w-424,110,190,26},"Compare quality routes",function()
  if not result then return end
  local direct=result.status=="available" and ("Use "..result.prisms.." Gemcutter's Prism"..(result.prisms==1 and "" or "s").." and keep the gem's level.") or (result.reason or "Target already reached.")
  local vendor=result.vendorRecipe
  local entries={{id="prisms",label="Use Prisms",enabled=result.status=="available",details={direct,"The gem retains its level."}},
   {id="vendor",label="Vendor and relevel",enabled=vendor.available,details={vendor.available and vendor.note or vendor.reason,"Check the actual vendor offer before trading."}}}
  require("Classes.PlanningBrowserControl").Open("Compare gem quality routes",entries,{action="Use route",canChoose=function(entry) return entry.enabled end,choose=function(entry) route=entry.id;refresh() end})
 end))
 c.routes.enabled=function() return result~=nil end
 c.routes.tooltipText="Compare Prism use with the support-gem vendor recipe."
 c.outcomes=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{w-218,110,202,26},"Corruption reference",function()
  if not result then return end
  local info=result.corruption;local vaal={info.vaalOrb.available and "This gem is uncorrupted; other eligibility is unverified." or info.vaalOrb.reason,
   "Historical Vaal outcomes include no change, level or quality changes, and conversion for eligible gems."}
  if info.historicalLevelRange then vaal[#vaal+1]="Historical level outcome range: "..info.historicalLevelRange.min.."–"..info.historicalLevelRange.max.."." end
  if info.historicalQualityRange then vaal[#vaal+1]="Historical quality outcome range: "..info.historicalQualityRange.min.."–"..info.historicalQualityRange.max.."%." end
  if #info.vaalCandidates>0 then vaal[#vaal+1]="Bundled related Vaal gem: "..table.concat(info.vaalCandidates,", ")..". Eligibility is unverified." end
  vaal[#vaal+1]=info.note
  local lens={info.lapidaryLens.available and "This gem is once-corrupted; other eligibility is unverified." or info.lapidaryLens.reason,
   "The Lapidary Lens can destroy the gem. The 3.30 notes cap quality at 23% and level at one above its natural maximum.",info.note}
  require("Classes.PlanningBrowserControl").Open("Gem corruption reference",{{id="vaal",label="Vaal Orb",details=vaal},{id="lens",label="Lapidary Lens",details=lens}})
 end))
 c.outcomes.enabled=function() return result~=nil end
 c.outcomes.tooltipText="Review conditional outcomes and current known limits; no currency is used."
 local function button(key,x,width,label,run) c[key]=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{x,h-54,width,28},label,run)) end
 button("paste",16,150,"Paste gem",function() raw=Paste();refresh() end)
 button("copy",178,150,"Copy guide",function() if result then local draft=selectedDraft();local text=draft and draft.notes or result.name..": "..(result.reason or "target already reached.");Copy(text) end end)
 c.copy.enabled=function() return result~=nil end
 button("keep",340,150,"Add to Journey",function()
  if not result or not selectedDraft() then return end
  local key=planKey()
  local entry=copyTable(selectedDraft());entry.id="gem-"..require("sha1")(os.time()..tostring({})):sub(1,20)
  local ok,err=pcall(function() build.savers.BuildJourney:Put("milestones",entry) end)
  if not ok then ui.errorPopup("Add to Journey",err);return end
  savedKey=key;refresh()
 end)
 c.keep.enabled=function() return result and selectedDraft()~=nil and not build.savers.BuildJourney.unreadable and savedKey~=planKey() end
 c.keep.tooltipText=function() if not result then return "Paste a gem and choose a target first." elseif not selectedDraft() then return "An available quality plan is needed." elseif build.savers.BuildJourney.unreadable then return build.savers.BuildJourney.warning elseif savedKey==planKey() then return "This plan was already added during this session." end;return "Add a gem milestone to Journey, then save the build." end
 button("close",w-146,130,"Close",function() main:ClosePopup() end)
 refresh();ui.style(c);main:OpenPopup(w,h,"Gem quality planner",c,nil,"target","close")
end
return M
