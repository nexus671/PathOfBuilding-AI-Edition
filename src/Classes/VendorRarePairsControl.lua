local ui=require("Modules.PlanningUI")
local vendor=require("Modules.VendorRarePairs")
local M={}
function M.Open()
 local c={};local w,h=math.min(820,main.screenW-40),math.min(560,main.screenH-48);local items={};local totalBytes=0
 local selectedName,selectedIndex
 ui.description(c,"intro",16,28,w-32,64,{"Paste identified rare items to compare their names. Two matching rares can yield a Chaos Orb; three can yield an Exalted Orb.","Session only: each paste counts as one item. Verify items and the vendor offer in game."},14)
 local left=math.floor(w*0.52);local listHeight=h-210
 c.entries=new("TextListControl"):TextListControl(ui.anchor,{16,106,left-24,listHeight},{{x=8},{x=math.floor(left*0.52)},{x=math.floor(left*0.67)}},{})
 c.details=new("TextListControl"):TextListControl(ui.anchor,{left+8,106,w-left-24,listHeight},nil,{})
 c.status=new("LabelControl"):LabelControl(ui.anchor,{16,h-94,0,14},"^7No items pasted")
 local function refresh()
  local review=vendor.review(items);local chosen
  for _,group in ipairs(review.groups) do if group.name==selectedName then chosen=group;break end end
  chosen=chosen or review.groups[1];selectedName=chosen and chosen.name or nil
  local rows={{height=28,textSize=14,"^7Rare item name","^7Count","^7Possible offer"}}
  for _,group in ipairs(review.groups) do
   local offers={};if group.exalted>0 then offers[#offers+1]=group.exalted.." Exalted" end;if group.chaos>0 then offers[#offers+1]=group.chaos.." Chaos" end
   local color=group.name==selectedName and "^xEED49C" or "^7"
   rows[#rows+1]={height=26,textSize=14,groupName=group.name,color..ui.fit(group.name,math.floor(left*0.49)-20,14),color..group.count,color..ui.fit(#offers>0 and table.concat(offers," + ") or "Need a match",left-math.floor(left*0.67)-48,14)}
  end
  c.entries.list=rows
  local detailRows={}
  if chosen then
   local offers={};if chosen.exalted>0 then offers[#offers+1]=chosen.exalted.." Exalted" end;if chosen.chaos>0 then offers[#offers+1]=chosen.chaos.." Chaos" end
   for _,row in ipairs(ui.rows({"Selected: "..chosen.name,"Possible: "..(#offers>0 and table.concat(offers," + ") or "Need a match"),"Select an item to remove it from this review."},w-left-56,14)) do detailRows[#detailRows+1]=row end
   for _,entry in ipairs(chosen.items) do
    local color=entry.index==selectedIndex and "^xEED49C" or "^7"
    detailRows[#detailRows+1]={height=25,textSize=14,itemIndex=entry.index,color..ui.fit("#"..entry.index.."  "..entry.base,w-left-58,14)}
   end
  else detailRows=ui.rows({"Paste an item to start a review."},w-left-56,14) end
  c.details.list=detailRows;c.status.label="^7"..review.totalItems.." pasted item"..(review.totalItems==1 and "" or "s").." | Triples are prioritised"
 end
 c.entries.onClick=function(row) local name=row and row.line and row.line.groupName;if name then selectedName=name;selectedIndex=nil;refresh() end end
 c.details.onClick=function(row) local index=row and row.line and row.line.itemIndex;if index then selectedIndex=index;refresh() end end
 local function button(key,x,width,label,run) c[key]=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{x,h-54,width,28},label,run)) end
 button("paste",16,146,"Paste rare item",function()
  local raw=Paste();local ok,result=pcall(vendor.parse,raw)
  if not ok then c.status.label="^1"..ui.fit(ui.errorText(result),w-32,14);return end
  if totalBytes+#raw>vendor.maxBytes then c.status.label="^1Copied items exceed the 4 MiB review limit.";return end
  items[#items+1]=raw;totalBytes=totalBytes+#raw;selectedName=result.name;selectedIndex=#items;refresh()
 end)
 button("remove",174,130,"Remove selected",function()
  if selectedIndex and items[selectedIndex] then totalBytes=totalBytes-#items[selectedIndex];table.remove(items,selectedIndex);selectedIndex=nil;refresh() end
 end);c.remove.enabled=function() return selectedIndex~=nil and items[selectedIndex]~=nil end
 button("undo",316,110,"Undo last",function() if #items>0 then totalBytes=totalBytes-#items[#items];table.remove(items);selectedIndex=nil;refresh() end end)
 c.undo.enabled=function() return #items>0 end
 button("clear",438,90,"Clear",function() items={};totalBytes=0;selectedName=nil;selectedIndex=nil;refresh() end);c.clear.enabled=function() return #items>0 end
 button("close",w-146,130,"Close",function() main:ClosePopup() end)
 refresh();ui.style(c);main:OpenPopup(w,h,"Same-name rare review",c,nil,nil,"close")
end
return M
