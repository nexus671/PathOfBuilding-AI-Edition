local ui=require("Modules.PlanningUI")
local vendor=require("Modules.VendorRarePairs")
local M={}
function M.Open()
 local c={};local w,h=math.min(820,main.screenW-40),math.min(560,main.screenH-48);local items={};local totalBytes=0
 ui.description(c,"intro",16,28,w-32,64,{"Paste identified rare items to compare their names. Two matching rares can yield a Chaos Orb; three can yield an Exalted Orb.","Session only: each paste counts as one item. Verify items and the vendor offer in game."},14)
 c.entries=new("TextListControl"):TextListControl(ui.anchor,{16,106,w-32,h-210},{{x=8},{x=math.floor(w*0.46)},{x=math.floor(w*0.67)}},{})
 c.status=new("LabelControl"):LabelControl(ui.anchor,{16,h-94,0,14},"^7No items pasted")
 local function refresh()
  local review=vendor.review(items);local rows={{height=28,textSize=14,"^7Rare item name","^7Count","^7Possible offer"}}
  for _,group in ipairs(review.groups) do
   local offers={};if group.exalted>0 then offers[#offers+1]=group.exalted.." Exalted" end;if group.chaos>0 then offers[#offers+1]=group.chaos.." Chaos" end
   rows[#rows+1]={height=26,textSize=14,"^7"..ui.fit(group.name,math.floor(w*0.43),14),"^7"..group.count,"^7"..(#offers>0 and table.concat(offers," + ") or "Need a match")}
  end
  c.entries.list=rows;c.status.label="^7"..review.totalItems.." pasted item"..(review.totalItems==1 and "" or "s").." | Triples are prioritised"
 end
 local function button(key,x,width,label,run) c[key]=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{x,h-54,width,28},label,run)) end
 button("paste",16,150,"Paste rare item",function()
  local raw=Paste();local ok,result=pcall(vendor.parse,raw)
  if not ok then c.status.label="^1"..ui.fit(ui.errorText(result),w-32,14);return end
  if totalBytes+#raw>vendor.maxBytes then c.status.label="^1Copied items exceed the 4 MiB review limit.";return end
  items[#items+1]=raw;totalBytes=totalBytes+#raw;refresh()
 end)
 button("undo",182,120,"Undo last",function() if #items>0 then totalBytes=totalBytes-#items[#items];table.remove(items);refresh() end end)
 c.undo.enabled=function() return #items>0 end
 button("clear",318,110,"Clear",function() items={};totalBytes=0;refresh() end);c.clear.enabled=function() return #items>0 end
 button("close",w-146,130,"Close",function() main:ClosePopup() end)
 refresh();ui.style(c);main:OpenPopup(w,h,"Same-name rare review",c,nil,nil,"close")
end
return M
