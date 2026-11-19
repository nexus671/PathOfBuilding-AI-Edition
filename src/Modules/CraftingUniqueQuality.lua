-- cspell:ignore RGBW RGBWA
-- A deliberately bounded unique-item quality operation. It never edits a build.
local M={}
-- Partial item text can omit socket restrictions. Derive known restrictions
-- from bundled unique data, including legacy variants, and keep hidden cases.
local socketRestrictions={["Tabula Rasa"]="fixed",["Oni-Goroshi"]="fixed"}
local uniquesByName
local function uniqueSocketRestriction(title)
	if socketRestrictions[title]~=nil then return socketRestrictions[title] end
	if not uniquesByName then
		uniquesByName={}
		for _,entries in pairs(data.uniques or {}) do for _,raw in ipairs(entries) do
			local name=raw:match("^%s*([^\r\n]+)")
			if name then uniquesByName[name]=uniquesByName[name] or {};uniquesByName[name][#uniquesByName[name]+1]=raw end
		end end
	end
	local restriction=false
	for _,raw in ipairs(uniquesByName[title] or {}) do for line in raw:gmatch("[^\r\n]+") do
		while line:match("^%b{}") do line=line:gsub("^%b{}","") end
		line=line:lower():match("^%s*(.-)%s*$"):gsub("%s*%(hidden%)$","")
		if line=="sockets cannot be modified" then restriction="locked"
		elseif restriction~="locked" and line:match("^has %d+ abyssal sockets?$") then restriction="abyss"
		elseif restriction~="locked" and (line:match("^has %d+ sockets?$") or line:match("^has %d+ linked sockets?$")) and restriction~="abyss" then restriction="fixed" end
	end end
	socketRestrictions[title]=restriction
	return socketRestrictions[title]
end
-- Only infer a permanent corruption restriction when every matching bundled
-- entry for the same title and base explicitly carries the marker.
local function alwaysCorrupted(title,baseName)
	uniqueSocketRestriction(title) -- Populate the shared unique index.
	local matched=false
	for _,raw in ipairs(uniquesByName[title] or {}) do
		local base=raw:match("^%s*[^\r\n]+[\r\n]+([^\r\n]+)")
		if base==baseName then
			matched=true
			if not ("\n"..raw:gsub("\r\n","\n").."\n"):find("\nCorrupted\n",1,true) then return false end
		end
	end
	return matched
end
function M.guideAction(method,count,resource,corrupted,socketCount)
	if method=="quality" then return "Use "..count.." "..resource..(count==1 and "" or "s") end
	if method=="beast_max_links" then return "Link existing sockets with a Black Morrigan and a Craicic Sand Spitter" end
	if method=="omen_connections" then return "Link existing sockets with an Omen of Connections and an Orb of Fusing" end
	if method=="socket_count_bench" then
		local components=require("Modules.CraftingSimulator").components({method="socket_bench",count=count},{sockets={},corrupted=corrupted})
		local amount=components["Metadata/Items/Currency/CurrencyRerollSocketNumbers"]
		return "Set "..count.." sockets at the crafting bench ("..amount.." Jeweller's Orb"..(amount==1 and "" or "s")..(corrupted and " and "..amount.." Vaal Orb"..(amount==1 and "" or "s") or "")..")"
	end
	if method=="socket_bench" then
		if not socketCount or socketCount<2 or socketCount>6 then return "Link existing sockets at the crafting bench" end
		local sockets={};for i=1,socketCount do sockets[i]={} end
		local components=require("Modules.CraftingSimulator").components({method=method,count=socketCount,linked=true},{sockets=sockets,corrupted=corrupted})
		local amount=components["Metadata/Items/Currency/CurrencyRerollSocketLinks"]
		return "Link existing sockets at the crafting bench ("..amount.." Orb"..(amount==1 and "" or "s").." of Fusing"..(corrupted and " and "..amount.." Vaal Orb"..(amount==1 and "" or "s") or "")..")"
	end
	if method=="socket_white_bench" then return "Use the crafting bench to make all sockets white (1 Orb of Scouring"..(corrupted and " and 1 Vaal Orb" or "")..")" end
end
function M.matchesGuideAction(method,count,resource,corrupted,action,socketCount)
	return action==M.guideAction(method,count,resource,corrupted,socketCount) or method=="socket_white_bench" and action=="Use the crafting bench to make all sockets white"
end
local function withoutQuality(raw)
	local lines={};for line in (raw.."\n"):gmatch("([^\n]*)\n") do if not line:match("^Quality: ") then lines[#lines+1]=line end end
	return table.concat(lines,"\n")
end
function M.inspect(raw)
	assert(type(raw)=="string" and #raw<=24000 and not raw:find("\0"),"Invalid starting item")
	assert(not raw:find("\nUnidentified",1,true),"Identify the starting item before using unique quality tools")
	local item=new("Item"):Item(raw)
	assert(item.base and item.baseName and item.itemLevel,"A recognized base and explicit Item Level are required")
	assert(item.rarity=="UNIQUE","Unique quality tools require a unique item")
	assert(item.itemLevel>=1 and item.itemLevel<=100 and item.itemLevel==math.floor(item.itemLevel),"Invalid item level")
	local weapon=data.weaponTypeInfo[item.type]~=nil
	local flask=item.type=="Flask" or item.type=="Tincture"
	assert(weapon or item.base.armour or flask,"Unique quality tools currently support armour, weapons, flasks and tinctures")
	assert(not item.mirrored,"Mirrored items cannot be crafted")
	assert(item.corrupted or not alwaysCorrupted(item.title,item.baseName),"This unique is always corrupted; include its Corrupted line in the starting item")
	-- These immutable Breach uniques always have six linked sockets. Only
	-- validate an explicitly supplied layout; missing sockets remain unknown.
	if item.baseName=="Simple Robe" and (item.title=="Skin of the Loyal" or item.title=="Skin of the Lords") and raw:find("\nSockets:",1,true) then
		local sockets=item.sockets or {};local linked=#sockets==6
		for _,socket in ipairs(sockets) do linked=linked and (socket.color=="R" or socket.color=="G" or socket.color=="B" or socket.color=="W") and socket.group==sockets[1].group end
		assert(linked,"This unique has six linked sockets; correct the starting socket layout")
	end
	assert(not item.foulborn,"Foulborn items need a separate modifier-mutation model")
	local quality=item.quality or 0;assert(type(quality)=="number" and quality>=0 and quality==math.floor(quality),"Invalid item quality")
	return item,{quality=quality,available=quality<20 and not item.corrupted,resource=flask and "Glassblower's Bauble" or weapon and "Blacksmith's Whetstone" or "Armourer's Scrap",resourceKey=flask and "Metadata/Items/Currency/CurrencyFlaskQuality" or weapon and "Metadata/Items/Currency/CurrencyWeaponQuality" or "Metadata/Items/Currency/CurrencyArmourQuality"}
end
function M.apply(raw)
	local item,info=M.inspect(raw);assert(not item.corrupted,"Ordinary quality currency cannot modify a corrupted item");assert(info.available,"Ordinary quality currency cannot exceed 20%")
	local padded="\n"..raw
	local output,count=padded:gsub("\nQuality:[^\r\n]*","\nQuality: "..(info.quality+1))
	assert(count<=1,"Item text contains multiple quality lines")
	output=output:sub(2)
	if count==0 then
		local newline=raw:find("\r\n",1,true) and "\r\n" or "\n"
		output=raw..(raw:sub(-1)=="\n" and "" or newline).."Quality: "..(info.quality+1)
	end
	if count>0 then assert(withoutQuality(raw)==withoutQuality(output),"Unique item properties changed while applying quality") end
	-- Game-copied tincture values already include the original quality. Keep
	-- that baseline explicit before changing quality, so later calculations
	-- do not treat the old displayed values as if they used the new quality.
	if item.type=="Tincture" and item.tinctureValues=="Final" and item.tinctureImportedQuality~=nil and not ("\n"..raw):find("\nTincture Imported Quality:",1,true) then
		local newline=raw:find("\r\n",1,true) and "\r\n" or "\n"
		output=output..(output:sub(-1)=="\n" and "" or newline).."Tincture Imported Quality: "..item.tinctureImportedQuality
	end
	if item.type=="Tincture" and item.tinctureValues=="Final" and item.tinctureImportedEffect~=nil and not ("\n"..raw):find("\nTincture Imported Effect:",1,true) then
		local newline=raw:find("\r\n",1,true) and "\r\n" or "\n"
		output=output..(output:sub(-1)=="\n" and "" or newline).."Tincture Imported Effect: "..item.tinctureImportedEffect
	end
	local checked,after=M.inspect(output)
	if item.type=="Tincture" and item.tinctureValues=="Final" then assert(checked.tinctureValues=="Final" and checked.tinctureImportedQuality==item.tinctureImportedQuality and checked.tinctureImportedEffect==item.tinctureImportedEffect,"Tincture baseline changed unexpectedly") end
	assert(after.quality==info.quality+1 and checked.title==item.title and checked.baseName==item.baseName,"Unique item did not round-trip after applying quality")
	return {itemText=output,beforeQuality=info.quality,quality=after.quality,resource=info.resource,resourceKey=info.resourceKey}
end

-- Known unique restrictions still apply when a saved item has partial text.
function M.socketModificationReason(raw,item)
	item=item or M.inspect(raw)
	if raw:lower():find("sockets cannot be modified",1,true) or uniqueSocketRestriction(item.title)=="locked" then return "This item's sockets cannot be modified" end
end

-- Preserve the original item text: rebuilding a unique can lose imported
-- properties that the item editor does not understand.
function M.linkReason(raw,method)
	local ok,item=pcall(M.inspect,raw)
	if not ok then return tostring(item) end
	if item.type=="Flask" or item.type=="Tincture" then return "Flasks and tinctures have no sockets" end
	if item.corrupted and method~="socket_bench" then return "Use the bench or tainted currency on corrupted items" end
	local immutable=M.socketModificationReason(raw,item);if immutable then return immutable end
	local sockets=item.sockets or {}
	local line,count=raw:match("\nSockets: ([^\r\n]*)"),0
	for _ in ("\n"..raw):gmatch("\nSockets:") do count=count+1 end
	if count~=1 or not line or not line:match("^[RGBWA][RGBWA%-%s]*$") then return "A single explicit ordinary socket layout is required" end
	if #sockets<2 or #sockets>6 then return "Link crafting needs two to six existing sockets" end
	local linked=true
	for _,socket in ipairs(sockets) do
		if socket.color=="A" then return "Abyssal sockets need a separate socket model" end
		linked=linked and socket.group==sockets[1].group
	end
	if linked then return "The item is already fully linked" end
	local colours=line:gsub("[^RGBW]","")
	if #colours~=#sockets then return "The socket layout could not be verified" end
end

function M.whiteReason(raw)
	local ok,item=pcall(M.inspect,raw)
	if not ok then return tostring(item) end
	if item.type=="Flask" or item.type=="Tincture" then return "Flasks and tinctures have no sockets" end
	local immutable=M.socketModificationReason(raw,item);if immutable then return immutable end
	local sockets=item.sockets or {}
	local line,count=raw:match("\nSockets: ([^\r\n]*)"),0
	for _ in ("\n"..raw):gmatch("\nSockets:") do count=count+1 end
	if count~=1 or not line or not line:match("^[RGBWA][RGBWA%-%s]*$") then return "A single explicit ordinary socket layout is required" end
	if #sockets<1 or #sockets>6 then return "White socket crafting needs one to six existing sockets" end
	local white=true
	for _,socket in ipairs(sockets) do
		if socket.color=="A" then return "Abyssal sockets need a separate socket model" end
		white=white and socket.color=="W"
	end
	if white then return "The item's sockets are already white" end
	local colours=line:gsub("[^RGBW]","")
	if #colours~=#sockets then return "The socket layout could not be verified" end
end

-- Socket-count recipes preserve the modeled existing groups and add white,
-- unlinked sockets, matching the ordinary equipment bench model.
function M.socketCountReason(raw,count)
	local ok,item=pcall(M.inspect,raw);if not ok then return tostring(item) end
	if item.type=="Flask" or item.type=="Tincture" then return "Flasks and tinctures have no sockets" end
	local immutable=M.socketModificationReason(raw,item);if immutable then return immutable end
	local restriction=uniqueSocketRestriction(item.title)
	if restriction=="fixed" then return "This unique fixes its socket count" end
	if raw:lower():find("has %d+ sockets?%f[^%a]") or raw:lower():find("has %d+ linked sockets?%f[^%a]") then return "This unique fixes its socket count" end
	if restriction=="abyss" or (item.abyssalSocketCount or 0)>0 or raw:lower():find("has %d+ abyssal sockets?%f[^%a]") then return "Abyssal sockets or variants need a separate socket model" end
	local line,lines=raw:match("\nSockets: ([^\r\n]*)"),0
	for _ in ("\n"..raw):gmatch("\nSockets:") do lines=lines+1 end
	if lines~=1 or not line or not line:match("^[RGBWA][RGBWA%-%s]*$") then return "A single explicit ordinary socket layout is required" end
	for _,socket in ipairs(item.sockets or {}) do if socket.color=="A" then return "Abyssal sockets need a separate socket model" end end
	if #line:gsub("[^RGBW]","")~=#item.sockets then return "The socket layout could not be verified" end
	local limit=require("Modules.CraftingSimulator").socketLimit({item=item})
	if type(count)~="number" or count~=math.floor(count) or count<2 or count>limit then return "Choose a socket count supported by this base" end
	if #item.sockets==count then return "The item already has this many sockets" end
end

function M.socketCount(raw,count)
	local reason=M.socketCountReason(raw,count);assert(not reason,reason)
	local before=M.inspect(raw);local parts={}
	for i=1,count do
		local socket=before.sockets[i]
		if i>1 then local previous=before.sockets[i-1];parts[#parts+1]=socket and previous and socket.group==previous.group and "-" or " " end
		parts[#parts+1]=socket and socket.color or "W"
	end
	local output,n=raw:gsub("(\nSockets: )([^\r\n]*)",function(prefix) return prefix..table.concat(parts) end)
	assert(n==1,"The socket layout could not be updated")
	local after=M.inspect(output);assert(after.title==before.title and after.baseName==before.baseName and #after.sockets==count and after.corrupted==before.corrupted,"Unique item did not round-trip after socket crafting")
	for i=1,math.min(count,#before.sockets) do assert(after.sockets[i].color==before.sockets[i].color and (i==1 or (after.sockets[i].group==after.sockets[i-1].group)==(before.sockets[i].group==before.sockets[i-1].group)),"Existing sockets changed unexpectedly") end
	local components=require("Modules.CraftingSimulator").components({method="socket_bench",count=count},{sockets=before.sockets,corrupted=before.corrupted})
	return {itemText=output,components=components}
end

function M.white(raw)
	local reason=M.whiteReason(raw);assert(not reason,reason)
	local before=M.inspect(raw)
	local output,count=raw:gsub("(\nSockets: )([^\r\n]*)",function(prefix,line) return prefix..line:gsub("[RGB]","W") end)
	assert(count==1,"The socket layout could not be updated")
	local after=M.inspect(output)
	assert(before.title==after.title and before.baseName==after.baseName and #before.sockets==#after.sockets and before.corrupted==after.corrupted,"Unique item did not round-trip after socket crafting")
	for i,socket in ipairs(after.sockets) do assert(socket.color=="W" and socket.group==before.sockets[i].group,"Socket links changed unexpectedly") end
	local components={["Metadata/Items/Currency/CurrencyConvertToNormal"]=1}
	if before.corrupted then components["Metadata/Items/Currency/CurrencyCorrupt"]=1 end
	return {itemText=output,components=components}
end

function M.catalog(raw,query,limit)
	local item,info=M.inspect(raw)
	query=(query or ""):lower();limit=limit or 50
	local linkReason=M.linkReason(raw);local benchLinkReason=M.linkReason(raw,"socket_bench");local whiteReason=M.whiteReason(raw)
	local qualityReason=item.corrupted and "Ordinary quality currency cannot modify a corrupted item" or not info.available and "Ordinary quality currency cannot exceed 20%" or nil
	local whiteComponents={["Metadata/Items/Currency/CurrencyConvertToNormal"]=1}
	if item.corrupted then whiteComponents["Metadata/Items/Currency/CurrencyCorrupt"]=1 end
	local sim=require("Modules.CraftingSimulator")
	local definitions={{method="quality",label="Ordinary quality",reason=qualityReason,components={[info.resourceKey]=1}}}
	if sim.socketLimit({item=item})>0 then
		local socketDefinitions={
		{method="beast_max_links",label="Bestiary: maximum links",reason=linkReason,components={beast_black_morrigan=1,beast_craicic_sand_spitter=1}},
		{method="omen_connections",label="Omen of Connections + Orb of Fusing",reason=linkReason,components={["Metadata/Items/Currency/AncestralOmenOnFusingMakeFullLinks"]=1,["Metadata/Items/Currency/CurrencyRerollSocketLinks"]=1}},
		{method="socket_bench",label="Bench: link existing sockets",reason=benchLinkReason,components=not benchLinkReason and require("Modules.CraftingSimulator").components({method="socket_bench",count=#item.sockets,linked=true},{sockets=item.sockets,corrupted=item.corrupted}) or {}},
		{method="socket_white_bench",label="Bench: white sockets",reason=whiteReason,components=whiteComponents},
		}
		for _,entry in ipairs(socketDefinitions) do definitions[#definitions+1]=entry end
	end
	for count=2,sim.socketLimit({item=item}) do
		local request={method="socket_bench",count=count}
		definitions[#definitions+1]={method="socket_bench",guideMethod="socket_count_bench",guideCount=count,request=request,label="Bench: "..count.." sockets",reason=M.socketCountReason(raw,count),components=sim.components(request,{sockets=item.sockets,corrupted=item.corrupted})}
	end
	local result={uniqueCrafting=true,methods={},uniqueActions={},socketCrafts={},quality={value=info.quality,available=info.available,resource=info.resource},nativeStats=require("Modules.CraftingItemStats").itemValues(item),limitations={"Only the listed unique actions are modeled. Continue by passing the returned item text, not an ordinary affix state.","Socket-count previews retain existing groups, remove sockets from the end and add white unlinked sockets; position and link behavior are unverified."}}
	local seen={}
	for _,entry in ipairs(definitions) do
		if not seen[entry.method] then result.methods[#result.methods+1]=entry.method;seen[entry.method]=true end
		if #result.uniqueActions<limit and (entry.method.." "..entry.label):lower():find(query,1,true) then
			local request=entry.request or (entry.method=="socket_bench" and {method=entry.method,count=#item.sockets,linked=true} or {method=entry.method})
			local action={method=entry.method,label=entry.label,action=request,priceKey=entry.method=="socket_bench" and require("Modules.CraftingSimulator").priceKey(request) or entry.method,available=entry.reason==nil,unavailableReason=entry.reason,deterministic=true,components=entry.components}
			local guideMethod,guideCount=entry.guideMethod or entry.method,entry.guideCount or 1
			action.guideStep={action=M.guideAction(guideMethod,guideCount,info.resource,item.corrupted,#item.sockets),uniqueCraft={method=guideMethod,count=guideCount}}
			result.uniqueActions[#result.uniqueActions+1]=action
			if entry.method~="quality" then result.socketCrafts[#result.socketCrafts+1]=copyTable(action) end
		end
	end
	return result
end

function M.matches(raw,requirements)
	local item,info=M.inspect(raw);requirements=requirements or {}
	local supported={uniqueName=true,minQuality=true,corrupted=true,twiceCorrupted=true,sockets=true,exactSockets=true,links=true,socketColours=true,linkedColours=true,minAbyssSockets=true,nativeStats=true}
	for key in pairs(requirements) do assert(supported[key],"This unique item property is not supported: "..tostring(key)) end
	if requirements.uniqueName and item.title~=requirements.uniqueName then return false end
	if requirements.minQuality and info.quality<requirements.minQuality then return false end
	if requirements.corrupted~=nil and (not not item.corrupted)~=requirements.corrupted then return false end
	if requirements.twiceCorrupted~=nil and (not not item.twiceCorrupted)~=requirements.twiceCorrupted then return false end
	if requirements.nativeStats then
		local stats=require("Modules.CraftingItemStats");stats.validate(requirements.nativeStats)
		local values=stats.itemValues(item);for key,minimum in pairs(requirements.nativeStats) do if values[key]==nil or values[key]<minimum then return false end end
	end
	local socketGoal=requirements.sockets~=nil or requirements.exactSockets~=nil or requirements.links~=nil or requirements.socketColours~=nil or requirements.minAbyssSockets~=nil
	if socketGoal then
		local line,count=raw:match("\nSockets: ([^\r\n]*)"),0
		for _ in ("\n"..raw):gmatch("\nSockets:") do count=count+1 end
		assert(count==1 and line and line:match("^[RGBWA][RGBWA%-%s]*$"),"An explicit socket layout is required for unique socket goals")
	end
	local sockets=item.sockets or {}
	if requirements.sockets and #sockets<requirements.sockets then return false end
	if requirements.exactSockets and #sockets~=requirements.exactSockets then return false end
	local groups,previous={},nil;local abyss=0
	for _,socket in ipairs(sockets) do
		if socket.color=="A" then abyss=abyss+1;previous=nil
		else
			if previous~=socket.group then groups[#groups+1]={};previous=socket.group end
			groups[#groups][#groups[#groups]+1]=socket
		end
	end
	if requirements.minAbyssSockets and abyss<requirements.minAbyssSockets then return false end
	if requirements.links then local best=0;for _,group in ipairs(groups) do best=math.max(best,#group) end;if best<requirements.links then return false end end
	if requirements.socketColours then
		local needed={};for color in requirements.socketColours:gmatch(".") do needed[color]=(needed[color] or 0)+1 end
		local candidates=requirements.linkedColours and groups or {sockets};local found=false
		for _,group in ipairs(candidates) do
			local colors={};for _,socket in ipairs(group) do colors[socket.color]=(colors[socket.color] or 0)+1 end
			local enough=true;for color,count in pairs(needed) do if (colors[color] or 0)<count then enough=false end end
			if enough then found=true;break end
		end
		if not found then return false end
	end
	return true
end

function M.link(raw,method)
	method=method or "beast_max_links"
	assert(method=="beast_max_links" or method=="omen_connections" or method=="socket_bench","Unsupported unique linking method")
	local reason=M.linkReason(raw,method);assert(not reason,reason)
	local before=M.inspect(raw)
	local output,count=raw:gsub("(\nSockets: )([^\r\n]*)",function(prefix,line)
		local colours={};for colour in line:gmatch("[RGBW]") do colours[#colours+1]=colour end
		return prefix..table.concat(colours,"-")
	end)
	assert(count==1,"The socket layout could not be updated")
	local after=M.inspect(output)
	assert(before.title==after.title and before.baseName==after.baseName and #before.sockets==#after.sockets,"Unique item did not round-trip after linking")
	for i,socket in ipairs(after.sockets) do assert(socket.color==before.sockets[i].color and socket.group==after.sockets[1].group,"Socket colours or links changed unexpectedly") end
	local components=method=="socket_bench" and require("Modules.CraftingSimulator").components({method=method,count=#before.sockets,linked=true},{sockets=before.sockets,corrupted=before.corrupted}) or method=="beast_max_links" and {beast_black_morrigan=1,beast_craicic_sand_spitter=1} or {
		["Metadata/Items/Currency/AncestralOmenOnFusingMakeFullLinks"]=1,
		["Metadata/Items/Currency/CurrencyRerollSocketLinks"]=1,
	}
	return {itemText=output,components=components}
end
return M
