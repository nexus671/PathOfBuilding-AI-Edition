local json = require("dkjson")
local sha = require("sha1")
local M = {}
local maxAge,maxRequest=30,160000
local current, nextPoll, nextPublish
local sent={}

local function read(path,limit)
	local file=io.open(path,"rb")
	if not file then return end
	local raw=file:read(limit+1)
	file:close()
	if not raw or #raw>limit then return end
	local object,position=json.decode(raw)
	if type(object)=="table" and position and not raw:sub(position):find("%S") then return object end
end

local function write(path,record)
	local temporary=path..".tmp"
	local file=assert(io.open(temporary,"wb"),"Could not write the local comparison request")
	local written=file:write(json.encode(record))
	local closed=file:close()
	local success=written and closed and pcall(require("Modules.LootTradeOverlayWindows").replaceFile,temporary,path)
	if not success then os.remove(temporary);error("Could not save the local comparison request",0) end
end

local function targetPath(root) return root.."LootTradeBuildTarget.json" end
local function requestPath(root,ticket) return root.."LootTradeBuild-"..ticket..".json" end
local function fresh(value,now)
	return type(value)=="number" and value>=now-maxAge and value<=now+2 and value==math.floor(value)
end

local function target(root,now)
	local value=read(targetPath(root),2048)
	if value and value.version==1 and type(value.ticket)=="string" and #value.ticket==40 and value.ticket:match("^%x+$")
		and type(value.name)=="string" and #value.name<=160 and fresh(value.seen,now) then return value end
end

local function itemText(raw)
	return type(raw)=="string" and #raw<=24000 and raw:find("%S") and not raw:find("%z")
end

function M.send(root,raw,now)
	assert(itemText(raw),"Copy one equippable item to compare")
	local peer=assert(target(root,now),"Open and select a build in the PoB AI Edition desktop first")
	local path=requestPath(root,peer.ticket)
	write(path,{version=1,ticket=peer.ticket,created=now,item=raw})
	sent[path]=now
	return StripEscapes(peer.name):gsub("[%c]"," ")
end

function M.expire(now)
	for path,created in pairs(sent) do
		if now-created>maxAge then
			os.remove(path)
			sent[path]=nil
		end
	end
end

local function slotAvailable(gear,item,slot)
	return slot:IsShown() and not slot.inactive
		and (not slot.weaponSet or slot.weaponSet==(gear.activeItemSet.useSecondWeaponSet and 2 or 1))
		and gear:IsItemValidForSlot(item,slot.slotName)
end

function M.open(build,raw)
	assert(itemText(raw),"Invalid copied item")
	local item=new("Item"):Item(raw)
	assert(item.base and not item.unidentifiedMarker,"This item has no supported identified equipment base")
	local gear=assert(build.itemsTab,"Open a build in PoB first")
	local calcs=build.calcsTab
	gear:UpdateSockets()
	local entries={}
	for _, slot in ipairs(gear.orderedSlots) do
		if slotAvailable(gear,item,slot) then
			local name=slot.label or slot.slotName
			local equipped=gear.items[slot.selItemId]
			entries[#entries+1]={id=slot.slotName,label=name,category="Equipment slots",slot=slot,
				details={item.name,"Current item in "..name,equipped and equipped.name or "Empty slot"}}
		end
	end
	assert(#entries>0,"This build has no available slot for the inspected item")
	require("Classes.PlanningBrowserControl").Open("Compare in PoB",entries,{
		action="Preview stats",closeOnChoose=false,choose=function(entry)
			local ui=require("Modules.PlanningUI")
			local ok,lines=pcall(function()
				assert(build.calcsTab==calcs and build.itemsTab==gear and slotAvailable(gear,item,entry.slot),
					"The build or slot changed. Send the item again.")
				local calcFunc,baseline=calcs:GetMiscCalculator()
				local equipped,output=gear:PreviewItemReplacement(calcFunc,item,entry.slot)
				local lines={item.name,"Slot: "..entry.label,"Replaces: "..(equipped and equipped.name or "Empty slot")}
				local collector={AddLine=function(_,_,line) lines[#lines+1]=line end}
				if build:AddStatComparesToTooltip(collector,baseline,output,"Hypothetical stat changes")==0 then
					lines[#lines+1]="No displayed stats change for this slot."
				end
				return lines
			end)
			if not ok then ui.errorPopup("Build comparison",lines);return end
			require("Classes.PlanningBrowserControl").Open("Build comparison",{
				{id="stats",label=entry.label,details=lines}
			})
		end,
	})
end

function M.close()
	if not current then return end
	local peer=read(targetPath(current.root),2048)
	if peer and peer.ticket==current.ticket then os.remove(targetPath(current.root)) end
	os.remove(requestPath(current.root,current.ticket))
	current=nil
end

function M.tick(root,build,now)
	if nextPoll==now then return end
	nextPoll=now
	if not (root and build and build.calcsTab and build.calcsTab.mainEnv and build.itemsTab) then
		M.close()
		return
	end
	local windows=require("Modules.LootTradeOverlayWindows")
	if not current or current.calcs~=build.calcsTab or current.root~=root then
		M.close()
		local ticket=sha(tostring(build.calcsTab)..tostring({})..now..GetTime()..windows.processId())
		current={root=root,calcs=build.calcsTab,ticket=ticket}
		nextPublish=nil
	end
	local foreground=windows.foregroundProcess()==windows.processId()
	if not nextPublish or now>=nextPublish or foreground and not current.foreground then
		nextPublish=now+5
		local peer=target(root,now)
		if not peer or peer.ticket==current.ticket or foreground then
			local name=StripEscapes(build.buildName or "Current build"):gsub("[%c]"," "):sub(1,160)
			pcall(write,targetPath(root),{version=1,ticket=current.ticket,seen=now,name=name})
		end
	end
	current.foreground=foreground
	local path=requestPath(root,current.ticket)
	local claimed=path..".claimed"
	-- Claim a complete request before reading, so a newer send cannot be removed with the old one.
	if os.rename(path,claimed) then
		local request=read(claimed,maxRequest)
		os.remove(claimed)
		if request and request.version==1 and request.ticket==current.ticket and fresh(request.created,now)
			and itemText(request.item) then current.pending=request end
	end
	local request=current.pending
	if not request then return end
	if not fresh(request.created,now) then current.pending=nil;return end
	if main.popups[1] then return end
	current.pending=nil
	local ok,problem=pcall(M.open,build,request.item)
	if not ok then require("Modules.PlanningUI").errorPopup("Compare in PoB",problem) end
	pcall(SetForeground)
end

return M
