local ui=require("Modules.PlanningUI")
local visual=require("Modules.LootFilterVisuals")
local M={}
function M.Open(routes)
	local c={};local w,h=math.min(900,main.screenW-40),math.min(650,main.screenH-60);local page=1;local pageSize=8;local rows={};local maximum=0
	local choices={};for i,route in ipairs(routes) do if route.result then choices[#choices+1]={label=route.label,val=i} end end
	if #choices==0 then choices[1]={label="No simulations",val=0} end
	c.route=new("DropDownControl"):DropDownControl(ui.anchor,{16,28,w-32,28},choices)
	local graph=new("Control"):Control(ui.anchor,{16,104,w-32,h-226});c.chart=graph
	local function selected() local i=c.route:GetSelValueByKey("val");return i and routes[i] end
	local function refresh()
		rows={};maximum=0;local route=selected();local result=route and route.result
		if result then for i,entry in pairsSortByKey(result.routeCounts or {}) do
			local amount=type(entry.pricedCost)=="number" and type(entry.unpricedComponents)=="number" and entry.unpricedComponents==0 and result.trials>0 and entry.pricedCost/result.trials or nil
			local step=route.recipe and route.recipe.steps and route.recipe.steps[i]
			local method=step and (require("Modules.CraftingSimulator").labels[step.method] or step.method)
			rows[#rows+1]={step=i,method=method,amount=amount};if amount then maximum=math.max(maximum,amount) end
		end end
		page=math.max(1,math.min(page,math.max(1,math.ceil(#rows/pageSize))))
	end
	function graph:Draw()
		local x,y=self:GetPos();SetViewport(x,y,self.width,self.height);visual.box(0,0,self.width,self.height,"^x101822")
		local route=selected();local unit=route and route.result.costCurrency or "units";local barX=240;local barWidth=math.max(20,self.width-400)
		if #rows==0 then visual.text(16,18,16,"No visited steps to chart.","^xD5DEE8",self.width-32) end
		for index=1,pageSize do local entry=rows[(page-1)*pageSize+index];if entry then
			local y=12+(index-1)*math.floor((self.height-24)/pageSize)
			visual.text(12,y+4,14,"Step "..entry.step..(entry.method and ": "..entry.method or ""),"^xD5DEE8",barX-24)
			if entry.amount~=nil then
				SetDrawColor("^x79D8A0");DrawImage(nil,barX,y+5,maximum>0 and barWidth*entry.amount/maximum or 0,16)
				visual.text(barX+barWidth+10,y+4,14,string.format("%.2f %s",entry.amount,unit or "units"),"^xD5DEE8",self.width-barX-barWidth-20)
			else visual.text(barX,y+4,14,"Unavailable: missing prices or older result","^xDDBB78",self.width-barX-12) end
		end end
		SetViewport()
	end
	ui.description(c,"hint",16,64,w-32,32,{"Average spending per trial, including unsuccessful trials. Starting items and restart costs are separate."},14)
	ui.label(c,"pageLabel",180,h-79,"",14);c.pageLabel.label=function() return string.format("^7Page %d / %d | %d visited steps",page,math.max(1,math.ceil(#rows/pageSize)),#rows) end
	c.previous=new("ButtonControl"):ButtonControl(ui.anchor,{16,h-84,72,24},"Previous",function() page=page-1 end);c.previous.enabled=function() return page>1 end
	c.next=new("ButtonControl"):ButtonControl(ui.anchor,{96,h-84,72,24},"Next",function() page=page+1 end);c.next.enabled=function() return page<math.ceil(#rows/pageSize) end
	c.copy=new("ButtonControl"):ButtonControl(ui.anchor,{16,h-42,200,28},"Copy step costs (CSV)",function()
		local route=selected();local result=route.result
		local function quote(value) return '"'..tostring(value or ""):gsub('"','""')..'"' end
		local warnings={};for _,warning in ipairs(result.warnings or {}) do if warning.message then warnings[#warnings+1]=warning.message end end
		for _,limitation in ipairs(result.limitations or {}) do warnings[#warnings+1]=limitation end
		local failed=0;for _,count in pairs(result.transitionErrors or {}) do failed=failed+count end
		local lines={"route,step,action,mean_per_trial,unit,status,trials,seed,action_limit,data_patch,modifier_patch,failed_transitions,model_notes,note"}
		for _,entry in ipairs(rows) do
			local amount=entry.amount~=nil and (string.format("%.17g",entry.amount):gsub(",",".")) or ""
			lines[#lines+1]=table.concat({quote(route.label),tostring(entry.step),quote(entry.method),amount,quote(result.costCurrency or "units"),quote(entry.amount~=nil and "priced" or "unavailable"),tostring(result.trials),tostring(result.seed or ""),tostring(result.maxActions or ""),quote(result.dataPatch),quote(result.modifierPatch),tostring(failed),quote(table.concat(warnings,"\n")),quote("Includes unsuccessful trials; excludes starting items and restart costs. Failed transitions are not charged.")},",")
		end
		Copy(table.concat(lines,"\n"))
	end)
	c.copy.enabled=function() return #rows>0 end
	c.copy.tooltipText="Copy every visited step for the selected route, including steps with unavailable prices."
	c.close=new("ButtonControl"):ButtonControl(ui.anchor,{w-156,h-42,140,28},"Close",function() main:ClosePopup() end)
	c.route.selFunc=function() page=1;refresh() end;refresh();ui.style(c);for _,control in pairs(c) do control.layoutAudit="crafting-step-costs" end
	main:OpenPopup(w,h,"Crafting step spending",c,nil,nil,"close");return c
end
return M
