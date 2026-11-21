local ui=require("Modules.PlanningUI")
local charts=require("Modules.CraftingChartData")
local visual=require("Modules.LootFilterVisuals")
local M={}
local colors={"^x79D8A0","^xDDBB78","^x94B9ED"}
function M.Open(routes)
	local c={};local w,h=math.min(1080,main.screenW-40),math.min(720,main.screenH-60);local data,allData;local pinned;local page=1
	c.mode=new("DropDownControl"):DropDownControl(ui.anchor,{16,28,#routes>3 and w-360 or w-32,28},charts.modes)
	local graph=new("Control"):Control(ui.anchor,{16,100,w-32,h-292});c.chart=graph
	function graph:IsMouseOver() return self:IsShown() and self:IsMouseInBounds() end
	local function line(x1,y1,x2,y2,color)
		local dx,dy=x2-x1,y2-y1;local length=math.max(1,math.sqrt(dx*dx+dy*dy));local ox,oy=-dy/length,dx/length
		SetDrawColor(color);DrawImageQuad(nil,x1+ox,y1+oy,x2+ox,y2+oy,x2-ox,y2-oy,x1-ox,y1-oy)
	end
	local function value()
		if pinned then return pinned end
		if graph:IsMouseOver() then local x=graph:GetPos();local px=GetCursorPos();return math.max(0,math.min(1,(px-x-54)/(graph.width-80)))*data.maximum end
		return data.maximum
	end
	function graph:Draw()
		local x,y=self:GetPos();SetViewport(x,y,self.width,self.height);visual.box(0,0,self.width,self.height,"^x101822")
		local gx,gy,gw,gh=54,18,self.width-80,self.height-64;local maximum=math.max(1,data.maximum)
		for percent=0,100,25 do local py=gy+gh*(1-percent/100);line(gx,py,gx+gw,py,"^x344253");visual.text(8,py-7,12,percent.."%","^xD5DEE8") end
		for i=0,4 do local px=gx+gw*i/4;visual.text(math.max(8,math.min(self.width-72,px-12)),gy+gh+10,12,string.format("%.3g",maximum*i/4),"^xD5DEE8") end
		-- Draw the selection behind the data so a jump at the selected value
		-- remains visible, including at the default right-edge selection.
		local selected=value();local px=gx+gw*selected/maximum;line(px,gy,px,gy+gh,"^xD5DEE8")
		for i,series in ipairs(data.series) do local previous={x=0,y=0};local color=colors[(i-1)%#colors+1]
			for _,point in ipairs(series.points) do local ax,ay=gx+gw*previous.x/maximum,gy+gh*(1-previous.y/100);local bx,by=gx+gw*point.x/maximum,gy+gh*(1-point.y/100);line(ax,ay,bx,ay,color);line(bx,ay,bx,by,color);previous=point end
			line(gx+gw*previous.x/maximum,gy+gh*(1-previous.y/100),gx+gw,gy+gh*(1-previous.y/100),color)
		end
		if #data.series==0 then visual.text(gx+16,gy+24,16,"No routes available to chart.","^xD5DEE8",gw-32) end
		visual.text(gx,gy+gh+30,12,data.unit.." | Hover to inspect; click to pin / unpin.","^xA6B3C6",gw)
		SetViewport()
	end
	function graph:OnKeyUp(key) if key=="LEFTBUTTON" and self:IsMouseOver() then if pinned then pinned=nil else pinned=value() end;return self end end
	for i=1,3 do ui.label(c,"legend"..i,16+(i-1)*math.floor((w-32)/3),72,"",14);c["legend"..i].label=function() local series=data.series[i];return series and colors[i]..ui.fit(series.label,math.floor((w-32)/3)-12,14) or "" end end
	ui.description(c,"readout",16,h-180,w-32,96,{},14)
	local drawReadout=c.readout.Draw
	function c.readout:Draw(...)
		local x=value();local lines={string.format("At %.4g %s",x,data.unit)}
		for _,series in ipairs(data.series) do local point=charts.at(series.points,x);lines[#lines+1]=string.format("%s: %.2f%% (%d / %d trials)",series.label,point.y,point.count,point.trials) end
		if #data.omitted>0 then lines[#lines+1]=#data.omitted.." routes omitted; see Model notes." end
		self.list=ui.rows(lines,w-60,14);drawReadout(self,...)
	end
	ui.label(c,"assumption",16,h-76,"",12);c.assumption.label=function() return "^7"..ui.fit((data.hasTransitionErrors and "Failed transitions were not charged. " or (#data.warnings>0 or #data.omitted>0) and "Model notes available. " or "")..data.note,w-32,12) end
	c.copy=new("ButtonControl"):ButtonControl(ui.anchor,{16,h-42,180,28},"Copy chart data (CSV)",function() Copy(charts.csv(allData)) end)
	c.notes=new("ButtonControl"):ButtonControl(ui.anchor,{208,h-42,160,28},"Model notes",function()
		local popup={};local width,height=math.min(780,main.screenW-40),math.min(420,main.screenH-60)
		local lines=copyTable(data.warnings);for _,message in ipairs(data.omitted) do lines[#lines+1]="Omitted: "..message end
		popup.messages=new("TextListControl"):TextListControl(ui.anchor,{16,28,width-32,height-92},nil,ui.rows(lines,width-60,14))
		popup.close=new("ButtonControl"):ButtonControl(ui.anchor,{width-156,height-48,140,28},"Close",function() main:ClosePopup() end)
		ui.style(popup);main:OpenPopup(width,height,"Chart model notes",popup,nil,nil,"close")
	end)
	c.notes.enabled=function() return #data.warnings>0 or #data.omitted>0 end
	c.stepCosts=new("ButtonControl"):ButtonControl(ui.anchor,{380,h-42,180,28},"Step spending",function() require("Classes.CraftingStepCostsControl").Open(routes) end)
	c.stepCosts.tooltipText="Compare the average modeled spending of each visited step in one route."
	c.close=new("ButtonControl"):ButtonControl(ui.anchor,{w-156,h-42,140,28},"Close",function() main:ClosePopup() end)
	local function showPage()
		page=math.max(1,math.min(page,math.max(1,math.ceil(#allData.series/3))))
		data={};for key,value in pairs(allData) do data[key]=value end;data.series={}
		for index=(page-1)*3+1,math.min(page*3,#allData.series) do data.series[#data.series+1]=allData.series[index] end
		pinned=nil
	end
	c.previousPage=new("ButtonControl"):ButtonControl(ui.anchor,{w-332,28,80,28},"Prev",function() page=page-1;showPage() end)
	c.nextPage=new("ButtonControl"):ButtonControl(ui.anchor,{w-244,28,80,28},"Next",function() page=page+1;showPage() end)
	c.previousPage.shown=function() return #routes>3 end;c.nextPage.shown=c.previousPage.shown
	c.previousPage.enabled=function() return page>1 end;c.nextPage.enabled=function() return page<math.ceil(#allData.series/3) end
	ui.label(c,"page",w-148,36,"",12);c.page.shown=c.previousPage.shown
	c.page.label=function() return "^7"..(#allData.series==0 and 0 or (page-1)*3+1).."-"..math.min(page*3,#allData.series).." / "..#allData.series end
	c.mode.selFunc=function() allData=charts.series(routes,c.mode:GetSelValue());page=1;showPage() end;c.mode.selFunc()
	ui.style(c);for _,control in pairs(c) do control.layoutAudit="crafting-charts" end;main:OpenPopup(w,h,"Crafting results and budget charts",c,nil,nil,"close");return c
end
return M
