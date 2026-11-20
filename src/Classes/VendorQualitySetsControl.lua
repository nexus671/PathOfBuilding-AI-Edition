local ui=require("Modules.PlanningUI")
local vendor=require("Modules.VendorQualitySets")
local M={}
function M.Open(build)
	assert(build,"Open a build before reviewing quality items")
	build.planningVendorQualityItems=build.planningVendorQualityItems or {}
	local items=build.planningVendorQualityItems;local bytes=0;for _,raw in ipairs(items) do bytes=bytes+#raw end
	local c={};local w,h=math.min(880,main.screenW-40),math.min(580,main.screenH-48);local left=math.floor(w*0.49);local selected
	ui.description(c,"intro",16,28,w-32,64,{"Paste quality weapons, armour or shields to make possible vendor groups.","Suggestions are not optimal; each paste must be a different item. Check the actual vendor offer."},14)
	c.entries=new("TextListControl"):TextListControl(ui.anchor,{16,106,left-24,h-210},{{x=8},{x=math.floor(left*0.68)}},{})
	c.details=new("TextListControl"):TextListControl(ui.anchor,{left+8,106,w-left-24,h-210},nil,{})
	c.status=new("LabelControl"):LabelControl(ui.anchor,{16,h-94,0,14},"^7No items pasted")
	local function refresh()
		local review=vendor.review(items);local rows={{height=28,textSize=14,"^7Copied item","^7Quality"}}
		for _,category in ipairs(review.categories) do for _,item in ipairs(category.items) do
			local colour=item.index==selected and "^xEED49C" or "^7"
			rows[#rows+1]={height=25,textSize=14,itemIndex=item.index,colour..ui.fit("#"..item.index.." "..item.base,math.floor(left*0.65)-18,14),colour..item.quality.."%"}
		end end
		c.entries.list=rows;local lines={}
		for _,category in ipairs(review.categories) do
			lines[#lines+1]=category.name.." - "..category.reward..": "..#category.groups.." possible"
			for index,group in ipairs(category.groups) do
				local ids={};for _,item in ipairs(group.items) do ids[#ids+1]="#"..item.index end
				lines[#lines+1]="  "..index..". "..table.concat(ids,", ").." ("..group.quality.."%"..(group.single and ", normal item" or "")..")"
			end
			if #category.leftover>0 then local ids={};for _,item in ipairs(category.leftover) do ids[#ids+1]="#"..item.index end;lines[#lines+1]="  Remaining: "..table.concat(ids,", ").." ("..category.leftoverQuality.."%)" end
		end
		if #items==0 then lines[#lines+1]="Paste a copied item to start." end
		c.details.list=ui.rows(lines,w-left-42,14);c.status.label="^7"..review.totalItems.." pasted item"..(review.totalItems==1 and "" or "s").." | Suggestions are not optimal"
	end
	c.entries.onClick=function(row) local index=row and row.line and row.line.itemIndex;if index then selected=index;refresh() end end
	local function button(key,x,width,label,run) c[key]=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{x,h-54,width,28},label,run)) end
	button("paste",16,146,"Paste item",function()
		local raw=Paste();local ok,item=pcall(vendor.parse,raw)
		if not ok then c.status.label="^1"..ui.fit(ui.errorText(item),w-32,14);return end
		if bytes+#raw>vendor.maxBytes then c.status.label="^1Copied items exceed the 4 MiB review limit.";return end
		items[#items+1]=raw;bytes=bytes+#raw;selected=#items;refresh()
	end)
	button("remove",174,130,"Remove selected",function() if selected and items[selected] then bytes=bytes-#items[selected];table.remove(items,selected);selected=nil;refresh() end end)
	c.remove.enabled=function() return selected~=nil and items[selected]~=nil end
	button("undo",316,110,"Undo last",function() if #items>0 then bytes=bytes-#items[#items];table.remove(items);selected=nil;refresh() end end);c.undo.enabled=function() return #items>0 end
	button("clear",438,90,"Clear",function() items={};build.planningVendorQualityItems=items;bytes=0;selected=nil;refresh() end);c.clear.enabled=function() return #items>0 end
	button("close",w-146,130,"Close",function() main:ClosePopup() end)
	refresh();ui.style(c);main:OpenPopup(w,h,"Quality vendor review",c,nil,nil,"close");return c
end
return M
