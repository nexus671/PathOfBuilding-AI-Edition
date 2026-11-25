local ui=require('Modules.PlanningUI')
local vendor=require('Modules.VendorBaseSets')
local M={}
function M.Open(build)
 assert(build,'Open a build before reviewing items')
 build.planningVendorBaseItems=build.planningVendorBaseItems or {}
 local items=build.planningVendorBaseItems;local bytes=0;for _,raw in ipairs(items) do bytes=bytes+#raw end
 local history,redo;local selectedBase,selectedIndex
 local c={};local w,h=math.min(820,main.screenW-40),math.min(560,main.screenH-48);local left=math.floor(w*0.52)
 ui.description(c,'intro',16,28,w-32,64,{'Paste one normal, magic, rare and unique item of the same base for a possible Orb of Chance.','Each paste is one item. Check the actual vendor offer; the stash is not read.','Other vendor reviews can use the same items; do not count them twice.'},14)
 c.entries=new('TextListControl'):TextListControl(ui.anchor,{16,106,left-24,h-210},{{x=8},{x=math.floor(left*0.57)},{x=math.floor(left*0.79)}},{})
 c.details=new('TextListControl'):TextListControl(ui.anchor,{left+8,106,w-left-24,h-210},nil,{})
 c.status=new('LabelControl'):LabelControl(ui.anchor,{16,h-94,0,14},'^7No items pasted')
 local function refresh()
  local review=vendor.review(items);local chosen
  for _,group in ipairs(review.groups) do if group.base==selectedBase then chosen=group;break end end
  chosen=chosen or review.groups[1];selectedBase=chosen and chosen.base or nil
  local rows={{height=28,textSize=14,'^7Base','^7N / M / R / U','^7Sets'}}
  for _,group in ipairs(review.groups) do
   local counts=group.counts;local colour=group.base==selectedBase and '^xEED49C' or '^7'
   rows[#rows+1]={height=26,textSize=14,base=group.base,colour..ui.fit(group.base,math.floor(left*0.54)-20,14),colour..counts.NORMAL..' / '..counts.MAGIC..' / '..counts.RARE..' / '..counts.UNIQUE,colour..group.sets}
  end
  c.entries.list=rows;local detail={}
  if chosen then
   local missing=#chosen.missing>0 and ('Missing for next set: '..table.concat(chosen.missing,', ')) or 'No items left over'
   for _,row in ipairs(ui.rows({'Selected: '..chosen.base,'Possible Chance Orbs: '..chosen.sets,missing,'Select an item to remove it from this review.'},w-left-56,14)) do detail[#detail+1]=row end
   for _,entry in ipairs(chosen.items) do local colour=entry.index==selectedIndex and '^xEED49C' or '^7';detail[#detail+1]={height=25,textSize=14,itemIndex=entry.index,colour..ui.fit('#'..entry.index..'  '..entry.rarity..'  '..entry.name,w-left-58,14)} end
  else detail=ui.rows({'Paste copied items to start a review.'},w-left-56,14) end
  c.details.list=detail;c.status.label='^7'..review.totalItems..' pasted | Kept while this build is open'
 end
 c.entries.onClick=function(row) local base=row and row.line and row.line.base;if base then selectedBase=base;selectedIndex=nil;refresh() end end
 c.details.onClick=function(row) local index=row and row.line and row.line.itemIndex;if index then selectedIndex=index;refresh() end end
 local function saveHistory() history={items=copyTable(items),bytes=bytes};redo=false end
 local function button(key,x,width,label,run) c[key]=ui.styleButton(new('ButtonControl'):ButtonControl(ui.anchor,{x,h-54,width,28},label,run)) end
 button('paste',16,146,'Paste item',function()
  local raw=Paste();local ok,result=pcall(vendor.parse,raw)
  if not ok then c.status.label='^1'..ui.fit(ui.errorText(result),w-32,14);return end
  if bytes+#raw>vendor.maxBytes then c.status.label='^1Copied items exceed the 4 MiB review limit.';return end
  saveHistory();items[#items+1]=raw;bytes=bytes+#raw;selectedBase=result.base;selectedIndex=#items;refresh()
 end)
 button('remove',174,130,'Remove selected',function() if selectedIndex and items[selectedIndex] then saveHistory();bytes=bytes-#items[selectedIndex];table.remove(items,selectedIndex);selectedIndex=nil;refresh() end end)
 c.remove.enabled=function() return selectedIndex~=nil and items[selectedIndex]~=nil end
 button('undo',316,110,function() return redo and 'Redo' or 'Undo' end,function()
  if not history then return end;local current={items=items,bytes=bytes};items,bytes=history.items,history.bytes;history=current;redo=not redo;build.planningVendorBaseItems=items;selectedIndex=nil;refresh()
 end);c.undo.enabled=function() return history~=nil end
 button('clear',438,90,'Clear',function() saveHistory();items={};bytes=0;build.planningVendorBaseItems=items;selectedBase=nil;selectedIndex=nil;refresh() end);c.clear.enabled=function() return #items>0 end
 button('close',w-146,130,'Close',function() main:ClosePopup() end)
 refresh();ui.style(c);main:OpenPopup(w,h,'Same-base vendor review',c,nil,nil,'close');return c
end
return M
