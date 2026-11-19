-- Check published restrictions without predicting encounter offers or odds.
local ui=require("Modules.PlanningUI")
local strategy=require("Modules.AtlasStrategy")
local M={}
function M.Open(options)
	options=options or {}
	local w,h=math.min(800,main.screenW-40),math.min(600,main.screenH-60)
	local c={}
	local intro=options.mechanic and {"Starting with recorded free "..options.mechanic.." Threads. Add spent or bonus Threads; review area level.","Other Thread types and odds are not modeled."} or {"Enter applied and spent counts for one Thread type; each listed type uses the same inputs separately.","Applied includes free Threads; interactions with other types are unverified."}
	ui.description(c,"intro",16,28,w-32,42,intro,16)
	ui.label(c,"levelLabel",16,82,"Area level",15)
	c.level=new("EditControl"):EditControl(ui.anchor,{16,106,140,28},"83",nil,"^%d",3)
	ui.label(c,"threadsLabel",180,82,"Threads per type",15)
	c.threads=new("EditControl"):EditControl(ui.anchor,{180,106,140,28},tostring(options.threads or 2),nil,"^%d",3)
	ui.label(c,"spentLabel",344,82,"Threads spent per type (optional)",15)
	c.spent=new("EditControl"):EditControl(ui.anchor,{344,106,140,28},"",nil,"^%d",3)
	c.status=ui.label(c,"status",16,146,"",14)
	c.results=new("TextListControl"):TextListControl(ui.anchor,{16,176,w-32,h-250},nil,{})
	local function refresh()
		local spent=c.spent.buf~="" and tonumber(c.spent.buf) or nil
		local ok,result=pcall(strategy.threadRestrictions,tonumber(c.level.buf),tonumber(c.threads.buf),(not options.mechanic or options.mechanic=="Abyss") and spent or nil,spent)
		if not ok then c.status.label="^xE9BE7B"..ui.fit(ui.errorText(result),w-32,14);c.results.list={};return end
		local lines={result.threads==0 and "No Threads applied; no modifier guarantee modeled." or "When spending Threads: "..result.guaranteedModifiers.." guaranteed modifiers | 3.30.0c", "Free-only guarantees are not established."}
		if result.milestones.threshold then
			lines[#lines+1]="Published bonus at "..result.milestones.threshold.." Threads (stacking not assumed):"
			for _,entry in ipairs(result.milestones.mechanics) do if not options.mechanic or entry.mechanic==options.mechanic then lines[#lines+1]=entry.mechanic..": "..entry.current end end
		else lines[#lines+1]="No published 3/6/8 Thread milestone reached." end
		if not options.mechanic or options.mechanic=="Abyss" then
			lines[#lines+1]=result.abyssalConsort.restricted and "Abyssal Consorts: restricted with one spent Thread." or "Abyssal Consorts: other eligibility is not evaluated."
			lines[#lines+1]="    Spending exactly one Abyss Thread prevents Consorts; free Threads are separate."
		end
		lines[#lines+1]="Modifier restrictions:"
		local shown=0;for _,row in ipairs(result.modifiers) do if not options.mechanic or row.mechanic==options.mechanic then
			shown=shown+1
			local status=row.conditionStatus=="conditions_met" and "^x85D6A6Conditions met" or row.conditionStatus=="restricted" and "^xE9BE7BRestricted" or "^xE9BE7BSpend unresolved"
			lines[#lines+1]=status.."^7 | "..row.mechanic..": "..row.effect
			lines[#lines+1]="    Area level "..row.areaLevel.."+; cannot occur with exactly one spent Thread."
		end end
		if shown==0 then lines[#lines+1]="No listed restrictions for "..options.mechanic.."; other conditions may apply." end
		c.status.label="^7Conditions met does not guarantee an offer."
		c.results.list=ui.rows(lines,w-56,15)
	end
	c.level.changeFunc=refresh;c.threads.changeFunc=refresh;c.spent.changeFunc=refresh
	c.close=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{w-156,h-48,140,28},"Close",function() main:ClosePopup() end))
	ui.style(c,{keep=true});for _,control in pairs(c) do control.layoutAudit="atlas-thread-restrictions" end
	refresh();main:OpenPopup(w,h,"Thread restrictions",c,nil,"level","close")
	return c
end
return M
