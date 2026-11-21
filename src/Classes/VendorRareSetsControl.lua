local ui=require("Modules.PlanningUI")
local vendor=require("Modules.VendorRarePairs")
local M={}
function M.Open(build)
 assert(build,"Open a build before reviewing rare sets")
 build.planningVendorRareSetItems=build.planningVendorRareSetItems or {}
 local items=build.planningVendorRareSetItems;local bytes=0;for _,raw in ipairs(items) do bytes=bytes+#raw end
 local c={};local w,h=math.min(880,main.screenW-40),math.min(580,main.screenH-48);local left=math.floor(w*0.49);local selected
 ui.description(c,"intro",16,28,w-32,64,{"Paste copied rare equipment to suggest full vendor sets. Each paste represents one item.","Weapon combinations and bonuses are unverified. Check the actual vendor offer."},14)
 c.entries=new("TextListControl"):TextListControl(ui.anchor,{16,106,left-24,h-210},{{x=8},{x=math.floor(left*0.68)}},{})
 c.details=new("TextListControl"):TextListControl(ui.anchor,{left+8,106,w-left-24,h-210},nil,{})
 c.status=new("LabelControl"):LabelControl(ui.anchor,{16,h-94,0,14},"^7No items pasted")
 local function refresh()
  local review=vendor.reviewSets(items);local rows={{height=28,textSize=14,"^7Copied rare","^7Item level"}}
  local all={};for _,group in ipairs(review.groups) do for _,item in ipairs(group.items) do all[#all+1]=item end end;for _,item in ipairs(review.remaining) do all[#all+1]=item end
  table.sort(all,function(a,b) return a.index<b.index end)
  for _,item in ipairs(all) do local colour=item.index==selected and "^xEED49C" or "^7";rows[#rows+1]={height=25,textSize=14,itemIndex=item.index,colour..ui.fit("#"..item.index.." "..item.base,math.floor(left*0.65)-18,14),colour..item.level} end
  c.entries.list=rows;local lines={}
  for index,group in ipairs(review.groups) do
   lines[#lines+1]="Set "..index..": possible "..group.reward.." (lowest level "..group.minLevel..")"
   local ids={};for _,item in ipairs(group.items) do ids[#ids+1]="#"..item.index end;lines[#lines+1]="  "..table.concat(ids,", ")
   lines[#lines+1]="  "..(group.unidentified and "All unidentified" or "Includes identified")..(group.quality20 and "; all 20% quality" or "").."; verify bonus."
  end
  if #review.remaining>0 then local ids={};for _,item in ipairs(review.remaining) do ids[#ids+1]="#"..item.index end;lines[#lines+1]="Remaining: "..table.concat(ids,", ") end
  if #items==0 then lines[#lines+1]="Paste a copied rare to start." elseif #review.groups==0 then lines[#lines+1]="No complete set yet." end
  c.details.list=ui.rows(lines,w-left-42,14);c.status.label="^7"..review.totalItems.." pasted | "..#review.groups.." suggested sets"
 end
 c.entries.onClick=function(row) local index=row and row.line and row.line.itemIndex;if index then selected=index;refresh() end end
 local function button(key,x,width,label,run) c[key]=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{x,h-54,width,28},label,run)) end
 button("paste",16,146,"Paste rare",function()
  local raw=Paste();local ok,item=pcall(vendor.parseSet,raw)
  if not ok then c.status.label="^1"..ui.fit(ui.errorText(item),w-32,14);return end
  if bytes+#raw>vendor.maxBytes then c.status.label="^1Copied items exceed the 4 MiB review limit.";return end
  items[#items+1]=raw;bytes=bytes+#raw;selected=#items;refresh()
 end)
 button("remove",174,130,"Remove selected",function() if selected and items[selected] then bytes=bytes-#items[selected];table.remove(items,selected);selected=nil;refresh() end end);c.remove.enabled=function() return selected~=nil and items[selected]~=nil end
 button("undo",316,110,"Undo last",function() if #items>0 then bytes=bytes-#items[#items];table.remove(items);selected=nil;refresh() end end);c.undo.enabled=function() return #items>0 end
 button("clear",438,90,"Clear",function() items={};build.planningVendorRareSetItems=items;bytes=0;selected=nil;refresh() end);c.clear.enabled=function() return #items>0 end
 button("close",w-146,130,"Close",function() main:ClosePopup() end)
 refresh();ui.style(c);main:OpenPopup(w,h,"Rare equipment sets",c,nil,nil,"close");return c
end
return M
