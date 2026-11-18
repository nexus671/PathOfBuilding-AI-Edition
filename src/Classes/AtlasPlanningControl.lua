-- Progression and farming inputs belong to the saved Atlas plan.
local ui=require("Modules.PlanningUI")
local atlas=require("Modules.AtlasPlanner")
local M={}
function M.Open(build,plan,keep,inspectRoute,view,onEdit,onCancel)
	local draft=copyTable(plan);local c={};local routeLines,routeReport,routeSource;local w,h=math.min(920,main.screenW-40),math.min(680,main.screenH-48)
	local function button(key,x,y,width,label,run)
		c[key]=new("ButtonControl"):ButtonControl(ui.anchor,{x,y,width,28},label,function()
			local ok,result=pcall(run)
			if not ok then main:OpenMessagePopup("Atlas strategy",ui.errorText(result)) else return result end
		end)
	end
	c.page=new("DropDownControl"):DropDownControl(ui.anchor,{16,24,220,28},{"Progression","Strategy"})
	ui.tabs(c,c.page,{{"progressionTab","Progression","Progression"},{"strategyTab","Strategy","Strategy requirements"}},16,24,w-32)
	ui.label(c,"stageLabel",16,76,"Stage")
	c.stage=new("DropDownControl"):DropDownControl(ui.anchor,{16,102,240,28},{{label="Starter",val="starter"},{label="Intermediate",val="intermediate"},{label="Final",val="final"}});c.stage:SelByValue(view and view.stage or draft.progression and draft.progression.stage or "starter","val")
	ui.label(c,"previousLabel",280,76,"Previous saved Atlas plan")
	local previous={{label="No previous plan",val=""}};local savedPrevious=view and view.previous or draft.progression and draft.progression.previousId or "";local found=savedPrevious==""
	for _,p in ipairs(require("Modules.AtlasStrategy").previousCandidates(plan,build.savers.AtlasPlans.plans)) do previous[#previous+1]={label=p.title,val=p.id};if p.id==savedPrevious then found=true end end
	local unavailable=not found and savedPrevious or nil
	if unavailable then previous[#previous+1]={label="Unavailable previous plan (review)",val=unavailable} end
	c.previous=new("DropDownControl"):DropDownControl(ui.anchor,{280,102,w-296,28},previous);c.previous:SelByValue(savedPrevious,"val")
	c.previous.tooltipText="Only saved plans from this tree that do not create a progression loop are offered."
	c.transition=new("TextListControl"):TextListControl(ui.anchor,{16,156,w-32,h-230},nil,{})
	local function refresh()
		routeLines=nil;routeReport=nil;routeSource=nil
		local lines={"Keep each stage as its own saved plan. Choose the prior stage to review the respec.","Later stages that depend on this plan cannot be selected as its previous stage.","No prior stage selected."}
		local selected=c.previous:GetSelValueByKey("val")
		if unavailable and selected==unavailable then
			lines={"Previous plan is unavailable or would make an invalid progression chain.","Saved plan ID: "..unavailable,"Choose another saved stage or No previous plan to resolve it. The original link stays in the draft until you choose."}
		else
			for _,p in ipairs(build.savers.AtlasPlans.plans) do if p.id==selected then routeReport=require("Modules.PlanningPerformance").measure(build,"Atlas respec route",require("Modules.AtlasStrategy").transition,p,draft);routeSource=copyTable(p);lines=routeReport.lines;routeLines=lines end end
		end
		c.transition.list=ui.rows(lines,w-56)
	end
	c.previous.selFunc=refresh
	local s=draft.strategy or {};local fields={{"maps","Maps and rolling requirements"},{"scarabs","Map supplies and consumables"},{"requirements","Character / unlock requirements"},{"avoid","Mechanics or map modifiers to avoid"}}
	local col=math.floor((w-48)/2)
	for i,field in ipairs(fields) do local x=16+(i-1)%2*(col+16);local y=78+math.floor((i-1)/2)*144
		ui.label(c,field[1].."Label",x,y,field[2],15);c[field[1]]=new("EditControl"):EditControl(ui.anchor,{x,y+26,col,100},view and view.fields[field[1]] or s[field[1]] or "",nil,"^%C\t\n",4000,nil,16)
	end
	ui.label(c,"costLabel",16,378,"Setup estimate / currency / source",15)
	for _,entry in ipairs({{"amount",16,120,s.setupCost and tostring(s.setupCost.amount) or ""},{"currency",148,140,s.setupCost and s.setupCost.currency or "chaos"},{"source",300,w-316,s.setupCost and s.setupCost.source or ""}}) do c[entry[1]]=new("EditControl"):EditControl(ui.anchor,{entry[2],404,entry[3],28},entry[4],nil,nil,240) end
	if view then c.amount:SetText(view.amount);c.currency:SetText(view.currency);c.source:SetText(view.source);c.page:SelByValue(view.page) end
	local function snapshot()
		local values={};for _,field in ipairs(fields) do values[field[1]]=c[field[1]].buf end
		return {page=c.page:GetSelValue(),stage=c.stage:GetSelValueByKey("val"),previous=c.previous:GetSelValueByKey("val"),fields=values,amount=c.amount.buf,currency=c.currency.buf,source=c.source.buf}
	end
	local function changed() if onEdit then onEdit(snapshot()) end end
	c.previous.selFunc=function() refresh();changed() end
	c.stage.selFunc=changed;c.page.selFunc=changed
	for _,key in ipairs({"maps","scarabs","requirements","avoid","amount","currency","source"}) do c[key].changeFunc=changed end
	ui.description(c,"costHint",16,448,w-32,48,{"Costs use your supplied currency and source, dated when edited. They do not reserve or spend Journey resources automatically."},14)
	button("mapTier",16,510,180,"Add map tier",function()
		local choices={};for tier=1,16 do local name="Map (Tier "..tier..")";choices[#choices+1]={id=name,label=name,details={"Adds a tiered map item to the strategy.","Filter build pickups can highlight this tier; the Atlas area is chosen separately."}} end
		require("Classes.PlanningBrowserControl").Open("Choose a map tier",choices,{action="Add tier",closeOnChoose=false,choose=function(entry)
			local existing=c.maps.buf
			if not existing:lower():find(entry.id:lower(),1,true) then
				local updated=existing..(existing:match("%S") and ", " or "")..entry.id
				if #updated>4000 then main:OpenMessagePopup("Atlas strategy","There is not enough room in the maps field. Shorten it and try again.");return end
				c.maps:SetText(updated,true)
			end
			main:ClosePopup()
		end})
	end)
	c.mapTier.tooltipText="Add a current tiered map item for filter build pickups."
	ui.label(c,"mapTierHint",210,516,"Add a tier for linked filter pickups.",14)

	for _,key in ipairs({"stageLabel","stage","previousLabel","previous","transition"}) do c[key].shown=function() return c.page:GetSelValue()=="Progression" end end
	for _,key in ipairs({"maps","scarabs","requirements","avoid","mapsLabel","scarabsLabel","requirementsLabel","avoidLabel","costLabel","amount","currency","source","costHint","mapTier","mapTierHint"}) do c[key].shown=function() return c.page:GetSelValue()=="Strategy" end end
	button("keep",16,h-48,200,"Use in Atlas draft",function()
		draft.progression={stage=c.stage:GetSelValueByKey("val"),previousId=c.previous:GetSelValueByKey("val")};draft.strategy=copyTable(s)
		for _,field in ipairs(fields) do draft.strategy[field[1]]=c[field[1]].buf end
		if c.amount.buf~="" then local amount=assert(tonumber(c.amount.buf),"Enter a numeric setup cost");local old=s.setupCost;draft.strategy.setupCost={amount=amount,currency=c.currency.buf,source=c.source.buf,quotedAt=old and old.amount==amount and old.currency==c.currency.buf and old.source==c.source.buf and old.quotedAt or os.time()} else draft.strategy.setupCost=nil end
		local validated=atlas.validate(draft);keep(validated);main:ClosePopup()
	end)
	button("copyRoute",228,h-48,150,"Copy route",function() if routeLines then Copy(table.concat(routeLines,"\n")) end end)
	c.copyRoute.enabled=function() return routeLines~=nil end
	c.copyRoute.shown=function() return c.page:GetSelValue()=="Progression" end
	c.copyRoute.tooltipText="Copy the shown refund and allocation steps, including their budget assumptions."
	button("inspectRoute",390,h-48,160,"Show on tree",function()
		if not inspectRoute or not routeReport or not routeReport.steps or #routeReport.steps==0 then return end
		local saved=snapshot()
		local steps=copyTable(routeReport.steps);local initial=copyTable(routeSource.nodes);local budget=math.max(routeSource.budget,draft.budget)
		local warnings={};if routeReport.startingReachable==nil then warnings[#warnings+1]="Starting allocation unverified" end
		if routeReport.choiceReselectionCostUnknown then warnings[#warnings+1]="Choice cost unverified" elseif #routeReport.choiceChanges>0 then warnings[#warnings+1]="Review choice effects" end
		local warning=#warnings>0 and table.concat(warnings," | ").."; see stages." or nil
		main:ClosePopup();inspectRoute(steps,saved,initial,budget,warning)
	end)
	c.inspectRoute.shown=function() return inspectRoute~=nil and c.page:GetSelValue()=="Progression" end
	c.inspectRoute.enabled=function() return inspectRoute~=nil and routeReport~=nil and routeReport.steps~=nil and #routeReport.steps>0 end
	c.inspectRoute.tooltipText="Step through a found route with allocation or refund steps; return to resume these edits."

	button("close",w-156,h-48,140,"Cancel",function() if onCancel then onCancel() end;main:ClosePopup() end)
	refresh();ui.style(c,{keep=true});main:OpenPopup(w,h,"Atlas stages and strategy",c,nil,nil,"close")
end
return M
