-- Review a bounded estimate before optionally using an example result.
-- cspell:ignore AABBD
local ui=require("Modules.PlanningUI")
local map=require("Modules.MapCraftingData")
local browser=require("Classes.PlanningBrowserControl")
local tasks=require("Modules.CraftingTasks")
local M={}
function M.Open(build,options)
	local state=copyTable(options.state);local wanted=copyTable(options.wanted or {});local groups={}
	if options.settings then groups=copyTable(options.settings.wantedGroups) else for _,id in ipairs(wanted) do groups[#groups+1]={id} end end
	local avoid=copyTable(options.settings and options.settings.avoid or options.avoid or {});local result;local active;local alive=true;local settingsKept=options.settings~=nil
	local width=math.min(840,main.screenW-40);local height=math.min(590,main.screenH-60);local column=math.floor((width-48)/2);local right=column+32
	local controls={};local report
	local function invalidate()
		if result or settingsKept then
			local wasKept=settingsKept;result=nil;settingsKept=false
			if report then report({wasKept and "Inputs changed. Keep targets again to update the map draft." or "Inputs changed. Run a new estimate."}) end
		end
	end
	local function button(key,x,y,w,label,fn) controls[key]=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{x,y,w,28},label,fn)) end
	ui.description(controls,"intro",16,28,width-32,48,{"Match one option in each wanted target and no avoided modifier.","Rerolls replace current modifiers; rules and weights are unverified estimates."},14)
	ui.label(controls,"wantedLabel",16,86,"Wanted targets",16);ui.label(controls,"avoidLabel",right,86,"Avoid exact modifiers",16)
	controls.wanted=new("TextListControl"):TextListControl(ui.anchor,{16,112,column,140},nil,{})
	controls.avoid=new("TextListControl"):TextListControl(ui.anchor,{right,112,column,140},nil,{})
	local function refresh()
		local function rows(ids,empty)
			local lines={};for _,id in ipairs(ids) do
				local mod=map.source().mods[id];lines[#lines+1]=mod and "^xE0C586"..mod.name.." | "..mod.generation_type or id
				if mod then for _,line in ipairs(map.summarize({id}).effects[1].lines) do lines[#lines+1]="^7"..line end end
			end
			if #lines==0 then lines={empty} end;return ui.rows(lines,column-25,14)
		end
		local lines={};for index,group in ipairs(groups) do
			lines[#lines+1]="^xAABBD0Target "..index.." (any one):"
			for _,id in ipairs(group) do local mod=map.source().mods[id];lines[#lines+1]=mod and "^xE0C586"..mod.name.." | "..mod.generation_type or id;if mod then for _,line in ipairs(map.summarize({id}).effects[1].lines) do lines[#lines+1]="^7"..line end end end
		end
		if #lines==0 then lines={"No wanted modifiers. Use the map card to add some."} end
		controls.wanted.list=ui.rows(lines,column-25,14)
		controls.avoid.list=rows(avoid,"No avoided modifiers.")
	end
	local function entries()
		local entries,offset={},0
		repeat
			local page=map.inspect(state.baseId,state.tier,state.itemLevel,{},"",offset,100,nil,state.rarity,nil,nil,nil,nil,nil,map.isNightmare(state.baseId))
			for _,entry in ipairs(page.candidates) do
				local details={entry.name.." | "..entry.side};for _,line in ipairs(map.summarize({entry.id}).effects[1].lines) do details[#details+1]=line end
				if map.isNightmare(state.baseId) then details[#details+1]="Includes modifiers unlocked later in the experimental roll." end
				details[#details+1]="This selection matches this exact modifier, not other tiers."
				entries[#entries+1]={id=entry.id,label=entry.name.." | "..entry.side,search=entry.id,details=details}
			end
			offset=page.nextOffset
		until not offset
		return entries
	end
	local function alreadyUsed(id)
		for _,group in ipairs(groups) do for _,other in ipairs(group) do if id==other then return true end end end
		for _,other in ipairs(avoid) do if id==other then return true end end
		return false
	end
	local function optionCount() local count=0;for _,group in ipairs(groups) do count=count+#group end;return count end
	local function removePicker(ids,title,action)
		local choices={}
		for index,id in ipairs(ids) do
			local mod=map.source().mods[id];local label=mod and mod.name.." | "..mod.generation_type or id
			local details={label};if mod then for _,line in ipairs(map.summarize({id}).effects[1].lines) do details[#details+1]=line end end
			choices[#choices+1]={id=id,index=index,label=label,search=id,details=details}
		end
		browser.Open(title,choices,{action=action,choose=function(entry) table.remove(ids,entry.index);invalidate();refresh() end})
	end
	local groupChoices={};for i=1,#groups do groupChoices[#groupChoices+1]={label="Target "..i,val=i} end
	if #groupChoices==0 then groupChoices={{label="No targets",val=0}} end
	controls.targetGroup=new("DropDownControl"):DropDownControl(ui.anchor,{16,260,85,28},groupChoices)
	controls.targetGroup.enabled=function() return not active and #groups>0 end
	local function selectGroup(index)
		local choices={};for i=1,#groups do choices[#choices+1]={label="Target "..i,val=i} end
		if #choices==0 then choices={{label="No targets",val=0}};index=0 else index=math.max(1,math.min(index,#choices)) end
		controls.targetGroup:SetList(choices);controls.targetGroup:SelByValue(index,"val")
	end
	button("addAlternative",109,260,140,"Add option",function()
		local index=controls.targetGroup:GetSelValueByKey("val")
		browser.Open("Choose an alternative",entries(),{action="Add option",canChoose=function(entry)
			return #groups[index]<100 and optionCount()<200 and not alreadyUsed(entry.id)
		end,choose=function(entry) groups[index][#groups[index]+1]=entry.id;invalidate();refresh() end})
	end)
	button("removeAlternative",257,260,column-241,"Remove option",function() local index=controls.targetGroup:GetSelValueByKey("val");removePicker(groups[index],"Remove an option","Remove option") end)
	controls.addAlternative.enabled=function() return not active and #groups>0 end
	controls.removeAlternative.enabled=function() local index=controls.targetGroup:GetSelValueByKey("val");return not active and index>0 and #groups[index]>1 end
	button("addAvoid",right,260,190,"Add avoided modifier",function()
		browser.Open("Choose an avoided modifier",entries(),{action="Avoid modifier",canChoose=function(entry)
			if #avoid>=100 then return false end
			return not alreadyUsed(entry.id)
		end,choose=function(entry) avoid[#avoid+1]=entry.id;invalidate();refresh() end})
	end)
	button("removeAvoid",right+198,260,column-198,"Remove avoided",function() removePicker(avoid,"Remove an avoided modifier","Remove modifier") end)
	controls.addAvoid.enabled=function() return not active end;controls.removeAvoid.enabled=function() return not active and #avoid>0 end
	button("addTarget",16,294,190,"Add wanted target",function()
		browser.Open("Choose a wanted target",entries(),{action="Add target",canChoose=function(entry) return #groups<6 and optionCount()<200 and not alreadyUsed(entry.id) end,
			choose=function(entry) groups[#groups+1]={entry.id};selectGroup(#groups);invalidate();refresh() end})
	end)
	button("removeTarget",214,294,column-198,"Remove target",function() local index=controls.targetGroup:GetSelValueByKey("val");table.remove(groups,index);selectGroup(index);invalidate();refresh() end)
	controls.addTarget.enabled=function() return not active and #groups<6 end;controls.removeTarget.enabled=function() return not active and #groups>0 end
	ui.label(controls,"trialsLabel",right,300,"Trials",14);controls.trials=new("EditControl"):EditControl(ui.anchor,{right+50,295,100,26},tostring(options.settings and options.settings.trials or 20),nil,"%D",4)
	ui.label(controls,"attemptsLabel",right+160,300,"Max per trial",14);controls.attempts=new("EditControl"):EditControl(ui.anchor,{right+288,295,column-288,26},tostring(options.settings and options.settings.maxAttempts or 5),nil,"%D",4)
	report=function(lines) controls.report.list=ui.rows(lines,width-55,14);controls.report.controls.scrollBar.offset=0 end
	controls.report=new("TextListControl"):TextListControl(ui.anchor,{16,374,width-32,height-434},nil,{})
	controls.trials.enabled=function() return not active end;controls.attempts.enabled=function() return not active end
	controls.trials.changeFunc=invalidate;controls.attempts.changeFunc=invalidate
	button("run",16,333,180,"Estimate rerolls",function()
		local request={wanted={},wantedGroups=copyTable(groups),avoid=copyTable(avoid),trials=tonumber(controls.trials.buf),maxAttempts=tonumber(controls.attempts.buf),seed=os.time()%2147483646+1}
		local ok,job=pcall(tasks.start,build,function(checkpoint) return require("Modules.MapCraftEstimate").run(state,request,checkpoint) end,
			function(value)
				if not alive then return end
				active=nil;result=value
				local lines={string.format("%.1f%% succeeded within %d rolls (%d / %d trials)",value.successChance,value.maxAttempts,value.successes,value.trials),string.format("95%% sampling interval %.1f%% to %.1f%% | mean %.2f %s per trial",value.confidenceLow,value.confidenceHigh,value.meanAttempts,value.action=="chaos" and "Chaos Orbs" or "Alteration Orbs"),"Model estimates only; interval does not measure uncertainty in game rules or prices."}
				for _,id in ipairs(value.unavailableAvoid or {}) do
					local effect=map.summarize({id}).effects[1]
					lines[#lines+1]="Cannot appear in modeled pool: "..effect.name
					for _,line in ipairs(effect.lines) do lines[#lines+1]=line end
				end
				if map.isNightmare(state.baseId) then lines[#lines+1]="Nightmare model: exclusive prefix and suffix first, then four weighted draws; order and odds are unverified." end
				if state.observedEffects then lines[#lines+1]="Observed effects are not modeled and can change results." end
				report(lines)
			end,
			function(err) if not alive then return end;active=nil;result=nil;report({"Estimate stopped: "..ui.errorText(err)}) end,
			function(progress) if alive and progress and progress.trial then report({"Estimating trial "..progress.trial.." / "..progress.trials.."..."}) end end,"Map reroll estimate slice")
		if not ok then result=nil;report({ui.errorText(job)});return end
		active=job;result=nil;report({"Estimating..."})
	end)
	controls.run.enabled=function() return not active and #groups+#avoid>0 end
	controls.run.tooltipText="Select at least one wanted or avoided modifier before estimating."
	button("cancel",204,333,120,"Cancel",function() if active and tasks.job==active then tasks.cancel() end end);controls.cancel.enabled=function() return active~=nil end
	button("fromMap",16,height-48,150,"Use map modifiers",function()
		for _,id in ipairs(wanted) do for _,blocked in ipairs(avoid) do if id==blocked then main:OpenMessagePopup("Wanted targets","Remove the matching avoided modifier first.");return end end end
		groups={};for _,id in ipairs(wanted) do groups[#groups+1]={id} end;selectGroup(1);invalidate();refresh()
	end)
	controls.fromMap.enabled=function() return not active and #wanted>0 end
	controls.fromMap.tooltipText="Replace wanted targets with the modifiers currently on the map."
	button("keepSettings",174,height-48,170,"Keep targets",function()
		local settings={wantedGroups=copyTable(groups),avoid=copyTable(avoid),trials=tonumber(controls.trials.buf),maxAttempts=tonumber(controls.attempts.buf)}
		local ok,value=pcall(require("Modules.AtlasPlanner").validateMapEstimate,settings)
		if not ok then main:OpenMessagePopup("Map targets",ui.errorText(value));return end
		options.saveSettings(value);settingsKept=true;report({"Targets ready. Keep the map draft, keep the Atlas plan, then save the build."})
	end)
	controls.keepSettings.shown=options.saveSettings~=nil;controls.keepSettings.enabled=function() return not active and options.saveSettings~=nil end
	button("use",width-324,height-48,180,"Use example result",function() if result and result.sampleSuccess then options.apply(result.sampleSuccess);alive=false;main:ClosePopup() end end)
	controls.use.enabled=function() return not active and result and result.sampleSuccess~=nil end
	button("close",width-132,height-48,116,"Close",function() alive=false;if active and tasks.job==active then tasks.cancel() end;main:ClosePopup() end)
	ui.style(controls,{run=true});refresh();report({"Choose targets, then run an estimate. Up to 20,000 attempts across all trials."})
	main:OpenPopup(width,height,"Estimate map rerolls",controls,nil,nil,"close");return controls
end
return M
