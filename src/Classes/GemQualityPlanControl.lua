local ui=require("Modules.PlanningUI")
local planner=require("Modules.GemQualityPlan")
local M={}
function M.Open(build)
 assert(build,"Open a build before planning a gem")
 local c={};local raw,result;local w,h=math.min(720,main.screenW-40),math.min(430,main.screenH-60)
 ui.description(c,"intro",16,28,w-32,48,{"Paste a copied skill or support gem to plan its quality.","This is a local guide; it does not change the gem or spend currency."},14)
 ui.label(c,"targetLabel",16,90,"Target quality (%)",14)
 c.target=new("EditControl"):EditControl(ui.anchor,{16,110,128,26},"20",nil,nil,3)
 c.result=new("TextListControl"):TextListControl(ui.anchor,{16,152,w-32,h-224},nil,{})
 local function refresh()
  local lines
  if not raw then result=nil;lines={"Paste a gem copied from the game to begin."}
  else
   local ok,value=pcall(planner.inspect,raw,tonumber(c.target.buf))
   if not ok then result=nil;lines={ui.errorText(value)}
   else
    result=value;lines={value.name.." | "..(value.level and "Level "..value.level or "Level unknown").." | Quality "..value.quality.."%",value.corrupted and "Corrupted" or "Uncorrupted"}
    if value.status=="complete" then lines[#lines+1]="Target already reached."
    elseif value.status=="available" then lines[#lines+1]="Use "..value.prisms.." Gemcutter's Prism"..(value.prisms==1 and "" or "s").." to reach "..value.target.."% quality."
    else lines[#lines+1]=value.reason end
    lines[#lines+1]=value.note
   end
  end
  c.result.list=ui.rows(lines,w-60,14)
 end
 c.target.changeFunc=refresh
 local function button(key,x,width,label,run) c[key]=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{x,h-54,width,28},label,run)) end
 button("paste",16,150,"Paste gem",function() raw=Paste();refresh() end)
 button("copy",178,150,"Copy guide",function() if result then local text=result.name..": ";if result.status=="available" then text=text..result.prisms.." Gemcutter's Prisms to reach "..result.target.."% quality." elseif result.status=="complete" then text=text.."target already reached." else text=text..result.reason end;Copy(text) end end)
 c.copy.enabled=function() return result~=nil end
 button("close",w-146,130,"Close",function() main:ClosePopup() end)
 refresh();ui.style(c);main:OpenPopup(w,h,"Gem quality planner",c,nil,"target","close")
end
return M
