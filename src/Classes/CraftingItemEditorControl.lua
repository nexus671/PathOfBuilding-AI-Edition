-- cspell:ignore Katakohi
-- A staged hypothetical starting item; edits never equip gear or spend currency.
local sim=require("Modules.CraftingSimulator")
local Panel={}
function Panel.Open(model,input,onKeep)
	assert(not input.destroyed and not input.veil,"Reset destruction or finish the unveil before editing")
	model=sim.context(model,input)
	local state=copyTable(input);local controls={};local socketAdjusted=false
	local hasOffers=model.unveiledJewels and next(model.unveiledJewels)~=nil
	local hasKatakohi=model.item.type=="Gloves"
	local extra=(hasOffers or hasKatakohi) and 34 or 0
	local function fitNestedPopup(popup,originalWidth)
		local width=math.min(originalWidth,main.screenW-24)
		if width<originalWidth then
			local factor=(width-32)/(originalWidth-32)
			for _,control in pairs(popup) do
				if type(control.x)=="number" then control.x=16+math.floor((control.x-16)*factor) end
				if type(control.width)=="number" and control.width>0 then control.width=math.floor(control.width*factor) end
				if type(control.label)=="string" and control.width==0 then control.tooltipText=control.label;control.label=require("Modules.PlanningUI").fit(control.label,width-control.x-16,14) end
			end
		end
		return width
	end
	local function button(key,x,y,w,text,callback)
		controls[key]=new("ButtonControl"):ButtonControl({"TOPLEFT",nil,"TOPLEFT"},{x,y,w,24},text,function()
			local ok,message=pcall(callback);if not ok then require("Modules.PlanningUI").errorPopup("Edit hypothetical item",message) end
		end)
	end
	local function edit(key,x,y,w,value,prompt)
		controls[key]=new("EditControl"):EditControl({"TOPLEFT",nil,"TOPLEFT"},{x,y,w,24},tostring(value or ""),prompt,nil,12)
	end
	controls.info=new("LabelControl"):LabelControl({"TOPLEFT",nil,"TOPLEFT"},{16,28,0,14},"Manual edits establish a new recipe start. Cancel discards all edits.")
	controls.current=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,62,744,24},{})
	local candidates={};local seen={};local dropOnly={};for _,id in ipairs(model.dropOnlyIds or {}) do dropOnly[id]=true end
	local function source(id)
		if dropOnly[id] then return "Drop-only / may be legacy | " end
		if model.legacyAbyss and model.legacyAbyss[id] then return "Legacy | " end
		if model.unveiledJewels and model.unveiledJewels[id] then
			local eye=id:match("^JunMasterVeiledAbyss(Murderous)ImpaleEffect$") or id:match("^JunMasterVeiledAbyss(Searching)ImpaleEffect$")
			return eye and "Unveiled ("..eye..") | " or "Unveiled | "
		end
		return ""
	end
	local function add(id)
		if not seen[id] then
			local mod=assert(model.byId[id]);local label=mod.type.." | "..source(id)..table.concat(mod," / ")
			candidates[#candidates+1]={label=label,searchFilter=label.." "..id,val=id};seen[id]=true
		end
	end
	for _,entry in ipairs(model.mods) do add(entry.id) end
	for _,entry in ipairs(model.bench) do add(entry.id) end
	for _,entry in ipairs(model.essences) do add(entry.modId) end
	for _,id in ipairs(model.dropOnlyIds or {}) do add(id) end
	for id in pairs(model.unveiledJewels or {}) do add(id) end
	for _,entry in ipairs(state.affixes) do add(entry.id) end
	table.sort(candidates,function(a,b) return a.label < b.label end)
	controls.modifier=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,108,744,24},candidates)
	controls.modifier.tooltipFunc=function(tooltip)
		local id=controls.modifier:GetSelValueByKey("val");local mod=id and model.byId[id]
		if mod then
			if dropOnly[id] then tooltip:AddLine(14,"Drop-only modifier; current availability is not verified.") end
			for _,line in ipairs(mod) do tooltip:AddLine(14,line) end
		end
	end
	edit("roll",16,154,180,50,"Roll % (0-100)")
	controls.roll.tooltipText="Position in the modifier's range. Recognized regeneration rolls use the nearest raw tick."
	controls.fractured=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{212,154,220,24},{"Not fractured","Fractured"})
	controls.searchHint=new("LabelControl"):LabelControl({"TOPLEFT",nil,"TOPLEFT"},{448,159,0,14},"Open the list and type to search")
	local function refresh()
		controls.info.label=state.veil and ("Recorded unveil choices: "..#state.veil.choices..". Use them as the recipe start.") or socketAdjusted and "Abyss socket layout is experimental. Cancel discards all edits." or "Manual edits establish a new recipe start. Cancel discards all edits."
		local list={}
		for i,entry in ipairs(state.affixes) do list[#list+1]={label=i.." | "..(entry.fractured and "Fractured | " or "")..source(entry.id)..table.concat(sim.entryMod(model,entry)," / "),val=i} end
		if #list == 0 then list={{label="No explicit modifiers",val=0}} end
		controls.current:SetList(list)
	end
	local function selected()
		local id=assert(controls.modifier:GetSelValueByKey("val"),"Select a modifier")
		local roll=assert(tonumber(controls.roll.buf),"Enter a roll percentage")
		assert(roll >= 0 and roll <= 100,"Use a roll from zero to 100 percent")
		local position=roll/100;local mod=model.byId[id]
		return {id=id,range=mod and sim.rawRegenAtPosition(mod,position) or position,crafted=id:match("^bench:") ~= nil,fractured=controls.fractured:GetSelValue() == "Fractured"}
	end
	local function commit(candidate) local adjusted=sim.syncAbyssSocket(state,candidate);state=sim.validateState(model,candidate);socketAdjusted=socketAdjusted or adjusted;refresh() end
	button("add",16,202,180,"Add modifier",function() local candidate=copyTable(state);candidate.affixes[#candidate.affixes+1]=selected();commit(candidate) end)
	button("replace",212,202,180,"Replace selected",function()
		local index=controls.current:GetSelValueByKey("val");assert(state.affixes[index],"Choose an existing modifier")
		local candidate=copyTable(state);candidate.affixes[index]=selected();commit(candidate)
	end)
	button("remove",408,202,180,"Remove selected",function()
		local index=controls.current:GetSelValueByKey("val");assert(state.affixes[index],"Choose an existing modifier")
		local candidate=copyTable(state);table.remove(candidate.affixes,index);commit(candidate)
	end)
	controls.current.selFunc=function()
		local entry=state.affixes[controls.current:GetSelValueByKey("val")];if not entry then return end
		controls.modifier:SelByValue(entry.id,"val")
		local range=type(entry.range) == "table" and math.min(unpack(entry.range)) or entry.range or 0.5
		local mod=model.byId[entry.id];local position=mod and sim.rawRegenPosition(mod,range)
		if position then range=position end
		controls.roll:SetText(tostring(range*100));controls.fractured:SelByValue(entry.fractured and "Fractured" or "Not fractured")
	end
	for _,entry in ipairs({{"rarityLabel",16,"Rarity"},{"qualityLabel",212,"Quality %"},{"intangibilityLabel",408,"Intangibility %"},{"memoryLabel",584,"Memory strands"}}) do
		controls[entry[1]]=new("LabelControl"):LabelControl({"TOPLEFT",nil,"TOPLEFT"},{entry[2],240,0,14},entry[3])
	end
	controls.rarity=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,260,180,24},{"NORMAL","MAGIC","RARE"})
	controls.rarity:SelByValue(state.rarity)
	edit("quality",212,260,180,state.quality or model.item.quality or 0,nil)
	edit("intangibility",408,260,160,state.intangibility or 0,nil)
	edit("memoryStrands",584,260,176,state.memoryStrands or 0,nil)
	controls.corrupted=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,308,376,24},{"Uncorrupted","Corrupted","Twice Corrupted"})
	controls.corrupted:SelByValue(state.twiceCorrupted and "Twice Corrupted" or state.corrupted and "Corrupted" or "Uncorrupted")
	local hint=require("Modules.PlanningUI").description(controls,"corruptionHint",16,340+extra,744,20,{"Marker only. This editor does not roll second-corruption outcomes."},14)
	hint.shown=function() return controls.corrupted:GetSelValue()=="Twice Corrupted" end
	local function applyProperties()
		local candidate=copyTable(state);candidate.rarity=controls.rarity:GetSelValue();candidate.corrupted=controls.corrupted:GetSelValue() ~= "Uncorrupted"
		if controls.corrupted:GetSelValue()=="Twice Corrupted" then candidate.twiceCorrupted=true
		elseif state.twiceCorrupted~=nil or model.initial.twiceCorrupted then candidate.twiceCorrupted=false end
		for _,key in ipairs({"quality","intangibility","memoryStrands"}) do candidate[key]=assert(tonumber(controls[key].buf),"Invalid "..key) end
		commit(candidate)
	end
	button("properties",408,308,352,"Apply properties to draft",applyProperties)
	if hasOffers then button("offers",16,340,376,"Record jewel unveil choices",function()
		applyProperties()
		local popup={};local options={{label="No choice",val=""}}
		for id,mod in pairs(model.unveiledJewels) do options[#options+1]={label=mod.type.." | "..source(id)..table.concat(mod," / "),val=id} end
		table.sort(options,function(a,b) if a.val=="" then return b.val~="" elseif b.val=="" then return false end;return a.label<b.label end)
		popup.info=new("LabelControl"):LabelControl({"TOPLEFT",nil,"TOPLEFT"},{16,26,0,14},"Enter observed or hypothetical choices. Offer probabilities are not simulated.")
		for i=1,3 do
			popup["choice"..i]=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,58+(i-1)*36,744,26},options)
			popup["choice"..i]:SelByValue(state.veil and state.veil.choices[i] or "","val")
		end
		popup.fractured=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,174,360,26},{"Ordinary veil","Fractured veil"})
		popup.fractured:SelByValue(state.veil and state.veil.fractured and "Fractured veil" or "Ordinary veil")
		popup.use=new("ButtonControl"):ButtonControl({"TOPLEFT",nil,"TOPLEFT"},{16,222,200,28},"Use these choices",function()
			local ok,result=pcall(function()
				local choices={};for i=1,3 do local id=popup["choice"..i]:GetSelValueByKey("val");if id and id~="" then choices[#choices+1]=id end end
				return sim.recordJewelOffers(model,state,choices,popup.fractured:GetSelValue()=="Fractured veil")
			end)
			if not ok then require("Modules.PlanningUI").errorPopup("Jewel unveil choices",result);return end
			state=result;refresh();main:ClosePopup()
		end)
		popup.clear=new("ButtonControl"):ButtonControl({"TOPLEFT",nil,"TOPLEFT"},{232,222,200,28},"Clear choices",function() state=copyTable(state);state.veil=nil;refresh();main:ClosePopup() end)
		popup.clear.enabled=function() return state.veil~=nil end
		popup.close=new("ButtonControl"):ButtonControl({"TOPLEFT",nil,"TOPLEFT"},{644,222,116,28},"Cancel",function() main:ClosePopup() end)
		main:OpenPopup(fitNestedPopup(popup,776),268,"Jewel unveil choices",popup,nil,nil,"close")
	end) end
	if hasKatakohi then button("katakohi",16,340,376,"Set socket enchantments",function()
		local katakohi=require("Modules.CraftingKatakohi");local rows=katakohi.catalog("",100,model);local popup={};local options={{label="No enchantment",val=""}}
		local selected=state.katakohiEnchants or katakohi.identify(sim.toItem(model,state))
		for _,row in ipairs(rows) do options[#options+1]={label=(row.lines[2] or row.id)..(row.modeledEligible and "" or " (outside modeled pool)"),val=row.id} end
		popup.info=new("LabelControl"):LabelControl({"TOPLEFT",nil,"TOPLEFT"},{16,26,0,14},selected and "Choose observed or hypothetical enchantments; each removes one maximum socket." or "Existing enchantments could not be identified; choosing these will replace them.")
		for i=1,3 do
			popup["choice"..i]=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,58+(i-1)*34,744,26},options)
			popup["choice"..i]:SelByValue(selected and selected[i] or "","val")
		end
		popup.note=new("LabelControl"):LabelControl({"TOPLEFT",nil,"TOPLEFT"},{16,171,0,14},"Manual preview replaces enchantments and removes extra sockets from the end.")
		popup.use=new("ButtonControl"):ButtonControl({"TOPLEFT",nil,"TOPLEFT"},{16,208,230,28},"Use these enchantments",function()
			local ok,result=pcall(function()
				local ids={};for i=1,3 do local id=popup["choice"..i]:GetSelValueByKey("val");if id and id~="" then ids[#ids+1]=id end end
				return sim.setKatakohi(model,state,ids)
			end)
			if not ok then require("Modules.PlanningUI").errorPopup("Socket enchantments",result);return end
			state=result;refresh();main:ClosePopup()
		end)
		popup.close=new("ButtonControl"):ButtonControl({"TOPLEFT",nil,"TOPLEFT"},{644,208,116,28},"Cancel",function() main:ClosePopup() end)
		local width=fitNestedPopup(popup,776);if width<776 then popup.use.label="Use enchantments" end
		main:OpenPopup(width,254,"Socket enchantments",popup,nil,nil,"close")
	end) end
	button("editSockets",16,368+extra,260,"Set socket layout",function()
		require("Classes.CraftingSocketControl").Open(model,state,function(candidate) commit(candidate) end)
	end)
	controls.editSockets.enabled=function() return math.max(sim.socketLimit(model,state),#(state.sockets or {}))>0 end
	controls.editSockets.tooltipText="Set observed colours and links without consuming currency."
	local implicit=require("Modules.CraftingBaseImplicit");local implicitState,implicitChoices,implicitReason
	local function implicitOptions()
		if implicitState~=state then
			implicitState=state;local ok,choices,reason=pcall(implicit.options,sim,model,state)
			implicitChoices=ok and choices or nil;implicitReason=ok and reason or "This implicit cannot be inspected safely."
		end
		return implicitChoices,implicitReason
	end
	button("baseImplicit",292,368+extra,260,"Set base implicit",function()
		local choices,reason=implicitOptions();assert(choices,reason)
		require("Classes.PlanningBrowserControl").Open("Choose base implicit",choices,{action="Use value",choose=function(entry) commit(implicit.apply(sim,model,state,entry.roll,entry.lineIndex)) end})
	end)
	controls.baseImplicit.enabled=function() local choices=implicitOptions();return choices~=nil end
	controls.baseImplicit.tooltipText=function() local choices,reason=implicitOptions();return choices and "Set a hypothetical ordinary base implicit without spending currency." or reason end
	button("keep",16,402+extra,260,"Use as recipe starting item",function() applyProperties();onKeep(sim.validateState(model,state));main:ClosePopup() end)
	button("close",644,402+extra,116,"Cancel",function() main:ClosePopup() end)
	local popupWidth=math.min(776,main.screenW-24);local popupHeight=math.min(450+extra,main.screenH-24)
	if popupHeight<450+extra then
		local factor=(popupHeight-30)/(420+extra)
		for _,control in pairs(controls) do if type(control.y)=="number" and control.y>28 then control.y=28+math.floor((control.y-28)*factor) end end
	end
	if popupWidth<776 then
		local factor=(popupWidth-32)/744
		for _,control in pairs(controls) do
			if type(control.x)=="number" then control.x=16+math.floor((control.x-16)*factor) end
			if type(control.width)=="number" and control.width>0 then control.width=math.floor(control.width*factor) end
		end
		controls.searchHint.label="Type to search";controls.roll.prompt="Roll %";controls.keep.label="Use starting item"
		local originalRefresh=refresh
		refresh=function() originalRefresh();controls.info.label=require("Modules.PlanningUI").fit(controls.info.label,popupWidth-32,14) end
	end
	refresh();main:OpenPopup(popupWidth,popupHeight,"Edit hypothetical item",controls,nil,nil,"close")
	return controls
end
return Panel
