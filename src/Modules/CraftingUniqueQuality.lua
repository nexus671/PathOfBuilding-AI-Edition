-- cspell:ignore RGBW
-- A deliberately bounded unique-item quality operation. It never edits a build.
local M={}
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
	assert(weapon or item.base.armour,"Unique quality tools currently support armour and weapons")
	assert(not item.corrupted,"Ordinary quality currency cannot modify a corrupted item")
	assert(not item.mirrored,"Mirrored items cannot be crafted")
	assert(not item.foulborn,"Foulborn items need a separate modifier-mutation model")
	local quality=item.quality or 0;assert(type(quality)=="number" and quality>=0 and quality==math.floor(quality),"Invalid item quality")
	return item,{quality=quality,available=quality<20,resource=weapon and "Blacksmith's Whetstone" or "Armourer's Scrap",resourceKey=weapon and "Metadata/Items/Currency/CurrencyWeaponQuality" or "Metadata/Items/Currency/CurrencyArmourQuality"}
end
function M.apply(raw)
	local item,info=M.inspect(raw);assert(info.available,"Ordinary quality currency cannot exceed 20%")
	local padded="\n"..raw
	local output,count=padded:gsub("\nQuality:[^\r\n]*","\nQuality: "..(info.quality+1))
	assert(count<=1,"Item text contains multiple quality lines")
	output=output:sub(2)
	if count==0 then
		local newline=raw:find("\r\n",1,true) and "\r\n" or "\n"
		output=raw..(raw:sub(-1)=="\n" and "" or newline).."Quality: "..(info.quality+1)
	end
	if count>0 then assert(withoutQuality(raw)==withoutQuality(output),"Unique item properties changed while applying quality") end
	local checked,after=M.inspect(output)
	assert(after.quality==info.quality+1 and checked.title==item.title and checked.baseName==item.baseName,"Unique item did not round-trip after applying quality")
	return {itemText=output,beforeQuality=info.quality,quality=after.quality,resource=info.resource,resourceKey=info.resourceKey}
end

-- Preserve the original item text: rebuilding a unique can lose imported
-- properties that the item editor does not understand.
function M.linkReason(raw)
	local ok,item=pcall(M.inspect,raw)
	if not ok then return tostring(item) end
	if raw:lower():find("sockets cannot be modified",1,true) then return "This item's sockets cannot be modified" end
	local sockets=item.sockets or {}
	if #sockets<2 or #sockets>6 then return "Link crafting needs two to six existing sockets" end
	local linked=true
	for _,socket in ipairs(sockets) do
		if socket.color=="A" then return "Abyssal sockets need a separate socket model" end
		linked=linked and socket.group==sockets[1].group
	end
	if linked then return "The item is already fully linked" end
	local line,count=raw:match("\nSockets: ([^\r\n]*)"),0
	for _ in ("\n"..raw):gmatch("\nSockets:") do count=count+1 end
	if count~=1 or not line or not line:match("^[RGBW][RGBW%-%s]*$") then return "A single explicit ordinary socket layout is required" end
	local colours=line:gsub("[^RGBW]","")
	if #colours~=#sockets then return "The socket layout could not be verified" end
end

function M.link(raw)
	local reason=M.linkReason(raw);assert(not reason,reason)
	local before=M.inspect(raw)
	local output,count=raw:gsub("(\nSockets: )([^\r\n]*)",function(prefix,line)
		local colours={};for colour in line:gmatch("[RGBW]") do colours[#colours+1]=colour end
		return prefix..table.concat(colours,"-")
	end)
	assert(count==1,"The socket layout could not be updated")
	local after=M.inspect(output)
	assert(before.title==after.title and before.baseName==after.baseName and #before.sockets==#after.sockets,"Unique item did not round-trip after linking")
	for i,socket in ipairs(after.sockets) do assert(socket.color==before.sockets[i].color and socket.group==after.sockets[1].group,"Socket colours or links changed unexpectedly") end
	return {itemText=output,components={beast_black_morrigan=1,beast_craicic_sand_spitter=1}}
end
return M
