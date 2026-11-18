-- cspell:ignore RRBG
local sim=require("Modules.CraftingSimulator")
local Panel={}
function Panel.Open(targets,requirements,requiredGroups,onKeep,groupIndex,baseName)
	local groups=copyTable(targets);local conditions=copyTable(requirements or {});local controls={}
	local function edit(key,x,y,value,prompt)
		controls[key.."Label"]=new("LabelControl"):LabelControl({"TOPLEFT",nil,"TOPLEFT"},{x,y,0,14},prompt)
		controls[key]=new("EditControl"):EditControl({"TOPLEFT",nil,"TOPLEFT"},{x,y+16,180,24},tostring(value or ""),nil,nil,8)
	end
	local function button(key,x,y,w,text,callback)
		controls[key]=new("ButtonControl"):ButtonControl({"TOPLEFT",nil,"TOPLEFT"},{x,y,w,24},text,function()
			local ok,message=pcall(callback);if not ok then main:OpenMessagePopup("Crafting targets",require("Modules.PlanningUI").errorText(message)) end
		end)
	end
	groupIndex=groupIndex or #groups
	controls.info=new("LabelControl"):LabelControl({"TOPLEFT",nil,"TOPLEFT"},{16,28,0,14},"Edit group "..groupIndex..". Blank item-property fields impose no condition.")
	local group=groups[groupIndex]
	if not group then controls.info.label="Set item properties. Blank fields impose no condition." end
	edit("count",16,64,group and group.atLeast or 1,"Matching mods in group")
	edit("roll",212,64,group and group.minRoll and group.minRoll*100 or nil,"Minimum roll % (0-100)")
	controls.mode=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{408,80,200,24},{"Require group","Exclude group"})
	controls.mode:SelByValue(group and group.negate and "Exclude group" or "Require group")
	controls.scope=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,124,376,24},{"Explicit modifiers","Implicit modifiers","Enchantments"})
	controls.scope:SelByValue(group and group.scope == "enchant" and "Enchantments" or group and group.scope == "implicit" and "Implicit modifiers" or "Explicit modifiers")
	edit("groups",408,108,requiredGroups,"Required groups (blank=all)")
	for i,key in ipairs({"fractured","crafted"}) do
		local title=key == "fractured" and "Fractured" or "Crafted"
		controls[key]=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16+(i-1)*294,164,278,24},{"Any "..key.." state",title.." only","Not "..key})
		controls[key]:SelByValue(group and group[key] == true and title.." only" or group and group[key] == false and "Not "..key or "Any "..key.." state")
	end
	local properties={{"openPrefixes","Open prefixes"},{"openSuffixes","Open suffixes"},{"minAffixes","Minimum affixes"},{"maxAffixes","Maximum affixes"},{"minQuality","Minimum quality"},{"sockets","Minimum sockets"},{"links","Minimum linked sockets"},{"minMemoryStrands","Minimum memory strands"},{"maxMemoryStrands","Maximum memory strands"},{"minFractured","Minimum fractured mods"},{"maxFractured","Maximum fractured mods"},{"minIntangibility","Minimum Intangibility"},{"maxIntangibility","Maximum Intangibility"}}
	for i,entry in ipairs(properties) do edit(entry[1],16+(i-1)%3*196,214+math.floor((i-1)/3)*42,conditions[entry[1]],entry[2]) end
	edit("socketColours",212,382,conditions.socketColours,"Socket colours (e.g. RRBG)")
	controls.linkedColours=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{408,398,180,24},{"Anywhere on item","In one linked group"})
	controls.linkedColours:SelByValue(conditions.linkedColours and "In one linked group" or "Anywhere on item")
	controls.corrupted=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,438,572,24},{"Any corruption state","Must be corrupted","Must be uncorrupted","Must be twice corrupted","Must be corrupted once","Must not be twice corrupted"})
	controls.corrupted:SelByValue(conditions.twiceCorrupted==true and "Must be twice corrupted" or conditions.corrupted==false and "Must be uncorrupted" or conditions.twiceCorrupted==false and (conditions.corrupted==true and "Must be corrupted once" or "Must not be twice corrupted") or conditions.corrupted==true and "Must be corrupted" or "Any corruption state")
	local enchantments={{label="Any Harvest enchantment",val=false}}
	for id,craft in pairs(require("Modules.CraftingEnchants").data().crafts) do enchantments[#enchantments+1]={label=(id:find("Body",1,true) and "Body: " or "Weapon: ")..craft.lines[#craft.lines],val=id} end
	table.sort(enchantments,function(a,b) if not a.val then return not not b.val elseif not b.val then return false else return a.label<b.label end end)
	controls.harvestEnchant=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,478,376,24},enchantments)
	controls.harvestEnchant:SelByValue(conditions.harvestEnchant or false,"val")
	edit("minAbyssSockets",408,462,conditions.minAbyssSockets,"Minimum Abyss sockets")
	controls.minAbyssSockets.tooltipText="Counts actual Abyssal sockets, independently of modifier text. Modeled layout changes can be experimental."
	local influences={{label="Any influence",val=false}}
	for _,info in ipairs(itemLib.influenceInfo.default) do influences[#influences+1]={label=info.display.." influence",val=info.key} end
	controls.influence=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,518,376,24},influences)
	controls.influence:SelByValue(conditions.influence or false,"val")
	controls.uniqueNameLabel=new("LabelControl"):LabelControl({"TOPLEFT",nil,"TOPLEFT"},{408,502,0,14},"Unique jewel name (exact)")
	local uniqueCandidates=require("Modules.CraftingJewelCorruption").candidates(baseName)
	controls.uniqueName=new("EditControl"):EditControl({"TOPLEFT",nil,"TOPLEFT"},{408,518,#uniqueCandidates>0 and 120 or 180,24},conditions.uniqueName or "",nil,nil,160)
	if #uniqueCandidates>0 then
		button("chooseUnique",536,518,52,"Pick",function()
			local entries={};for _,candidate in ipairs(uniqueCandidates) do
				entries[#entries+1]={id=candidate.title,label=candidate.title,details=function()
					local item=require("Modules.CraftingJewelCorruption").item(baseName,candidate.title,83,104729)
					local lines={candidate.title,baseName,"Example rolls; eligibility and odds are unverified.",""}
					for _,line in ipairs(item.explicitModLines or {}) do lines[#lines+1]=itemLib.formatModLine(line,false) or line.line end
					return lines
				end}
			end
			require("Classes.PlanningBrowserControl").Open("Choose a unique jewel",entries,{action="Use name",choose=function(entry) controls.uniqueName:SetText(entry.id,true) end})
		end)
	end
	button("keep",16,568,220,"Keep target conditions",function()
		if group then
			group.atLeast=assert(tonumber(controls.count.buf),"Enter a matching-mod count")
			group.minRoll=controls.roll.buf ~= "" and assert(tonumber(controls.roll.buf),"Enter a minimum roll percent")/100 or nil
			group.negate=controls.mode:GetSelValue() == "Exclude group";local scope=controls.scope:GetSelValue();group.scope=scope == "Enchantments" and "enchant" or scope == "Implicit modifiers" and "implicit" or "explicit"
			for _,key in ipairs({"fractured","crafted"}) do local value=controls[key]:GetSelValue();group[key]=nil;if not value:match("^Any ") then group[key]=not value:match("^Not ") end end
		end
		local result={nativeStats=conditions.nativeStats and copyTable(conditions.nativeStats)};for _,entry in ipairs(properties) do local value=controls[entry[1]].buf;if value ~= "" then result[entry[1]]=assert(tonumber(value),"Enter a number for "..entry[2]:lower()) end end
		if controls.uniqueName.buf:match("%S") then result.uniqueName=controls.uniqueName.buf end
		if controls.minAbyssSockets.buf~="" then result.minAbyssSockets=assert(tonumber(controls.minAbyssSockets.buf),"Enter a number for Abyss sockets") end
		local corruption=controls.corrupted:GetSelValue()
		if corruption=="Must be corrupted" or corruption=="Must be corrupted once" then result.corrupted=true elseif corruption=="Must be uncorrupted" then result.corrupted=false end
		if corruption=="Must be twice corrupted" then result.twiceCorrupted=true elseif corruption=="Must be corrupted once" or corruption=="Must not be twice corrupted" then result.twiceCorrupted=false end
		result.harvestEnchant=controls.harvestEnchant:GetSelValueByKey("val") or nil
		result.influence=controls.influence:GetSelValueByKey("val") or nil
		if controls.socketColours.buf~="" then result.socketColours=controls.socketColours.buf:upper();result.linkedColours=controls.linkedColours:GetSelValue()=="In one linked group" end
		local required=controls.groups.buf ~= "" and assert(tonumber(controls.groups.buf),"Invalid required group count") or nil
		if not next(result) then result=nil end
		sim.validateRecipe({steps={{method="chaos"}},targets=groups,requirements=result,requiredGroups=required})
		onKeep(groups,result,required);main:ClosePopup()
	end)
	button("close",492,568,116,"Close",function() main:ClosePopup() end)
	button("itemStats",250,568,224,"Weapon and defence goals",function()
		require("Classes.CraftingItemStatsControl").Open(conditions.nativeStats,function(value) conditions.nativeStats=value end)
	end)
	if not group then
		for _,key in ipairs({"count","countLabel","roll","rollLabel","mode","scope","groups","groupsLabel","fractured","crafted"}) do controls[key].enabled=false;controls[key].shown=false end
		for _,control in pairs(controls) do if type(control.y)=="number" and control.y>=214 then control.y=control.y-150 end end
		controls.keep.label="Keep item properties"
	end
	require("Modules.PlanningUI").style(controls,{keep=true})
	main:OpenPopup(624,group and 616 or 466,group and "Crafting target conditions" or "Item properties",controls,nil,nil,"close")
	return controls
end
return Panel
