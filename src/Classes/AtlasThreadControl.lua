-- Check published restrictions without predicting encounter offers or odds.
local ui=require("Modules.PlanningUI")
local strategy=require("Modules.AtlasStrategy")
local M={}
function M.Open()
	local w,h=math.min(800,main.screenW-40),math.min(600,main.screenH-60)
	local c={}
	ui.description(c,"intro",16,28,w-32,42,{"Enter one Thread type's applied count, including free or bonus Threads. Other conditions and odds are not modeled."},16)
	ui.label(c,"levelLabel",16,82,"Area level",15)
	c.level=new("EditControl"):EditControl(ui.anchor,{16,106,140,28},"83",nil,"^%d",3)
	ui.label(c,"threadsLabel",180,82,"Threads per type",15)
	c.threads=new("EditControl"):EditControl(ui.anchor,{180,106,140,28},"2",nil,"^%d",3)
	c.status=ui.label(c,"status",16,146,"",14)
	c.results=new("TextListControl"):TextListControl(ui.anchor,{16,176,w-32,h-250},nil,{})
	local function refresh()
		local ok,result=pcall(strategy.threadRestrictions,tonumber(c.level.buf),tonumber(c.threads.buf))
		if not ok then c.status.label="^xE9BE7B"..ui.fit(ui.errorText(result),w-32,14);c.results.list={};return end
		local lines={"Guaranteed modifiers: "..result.guaranteedModifiers.." | 3.30.0c"}
		if result.milestones.threshold then
			lines[#lines+1]="Published bonus at "..result.milestones.threshold.." Threads (stacking not assumed):"
			for _,entry in ipairs(result.milestones.mechanics) do lines[#lines+1]=entry.mechanic..": "..entry.current end
		else lines[#lines+1]="No published 3/6/8 Thread milestone reached." end
		lines[#lines+1]="Modifier restrictions:"
		for _,row in ipairs(result.modifiers) do
			lines[#lines+1]=(row.restrictionsMet and "^x85D6A6Conditions met" or "^xE9BE7BRestricted").."^7 | "..row.mechanic..": "..row.effect
			lines[#lines+1]="    Requires area level "..row.areaLevel.."+ and at least 2 Threads."
		end
		c.status.label="^7Conditions met does not guarantee an offer."
		c.results.list=ui.rows(lines,w-56,15)
	end
	c.level.changeFunc=refresh;c.threads.changeFunc=refresh
	c.close=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{w-156,h-48,140,28},"Close",function() main:ClosePopup() end))
	ui.style(c,{keep=true});for _,control in pairs(c) do control.layoutAudit="atlas-thread-restrictions" end
	refresh();main:OpenPopup(w,h,"Thread restrictions",c,nil,"level","close")
	return c
end
return M
