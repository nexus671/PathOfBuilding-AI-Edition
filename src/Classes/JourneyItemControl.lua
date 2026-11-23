-- Compact comparison cards for ordinary and unique items, using local artwork.
local ui=require("Modules.PlanningUI")
local itemArt=require("Modules.CraftingWorkbench")
local M={}
local artwork
local socketColors={R="^x713338",G="^x285B3E",B="^x304C7D",W="^x555B65",A="^x644873"}
function M.new(controls,key,x,y,w,h,label,options)
	if not artwork then local file=assert(io.open("Assets/Crafting/items.json","r"));artwork=require("dkjson").decode(file:read("*a")).bases;file:close() end
	local expanded=options and options.expanded;local header=expanded and 152 or 108;local artSize=expanded and 72 or 48
	local item,art,artW,artH,artSprite,socketLabel
	local equipped=label=="EQUIPPED NOW"
	local starting=label=="STARTING ITEM"
	local card=new("Control"):Control(ui.anchor,{x,y,w,header});controls[key]=card
	local mods=new("TextListControl"):TextListControl(ui.anchor,{x,y+header,w,h-header},nil,{});controls[key.."Mods"]=mods
	local function fit(value,size,width) while #value>0 and DrawStringWidth(size,"VAR",value)>width do value=value:sub(1,-2) end;return value end
	function card:Draw()
		local cx,cy=self:GetPos();SetDrawColor("^x756647");DrawImage(nil,cx,cy,w,header);SetDrawColor("^x111923");DrawImage(nil,cx+1,cy+1,w-2,header-2)
		SetDrawColor("^x9BA9BA");DrawString(cx+10,cy+7,"LEFT",12,"VAR",label)
		SetDrawColor(item and (item.rarity=="UNIQUE" and "^xAF6025" or item.rarity=="RARE" and "^xFFFF77" or item.rarity=="MAGIC" and "^x8888FF") or "^xD5DEE8")
		DrawString(cx+10,cy+27,"LEFT",15,"VAR",fit(item and (item.title or item.baseName) or equipped and "Empty equipment slot" or starting and "No starting item" or "No target selected",15,w-20))
		if art then SetDrawColor(1,1,1);itemArt.drawArt(art,cx+10+(artSize-artW)/2,cy+52+(artSize-artH)/2,artW,artH,artSprite) end
		local propertyX=expanded and 94 or 68
		SetDrawColor("^xD5DEE8");DrawString(cx+propertyX,cy+54,"LEFT",13,"VAR",fit(item and item.baseName or equipped and "No item equipped" or starting and "Paste your starting item" or "Choose a target item",13,w-propertyX-10))
		local jewellery=item and (item.type=="Ring" or item.type=="Amulet" or item.type=="Belt")
		local quality=item and (jewellery and (item.catalystQuality or (item.catalyst and 20) or item.quality or 0) or (item.quality or 0))
		local catalyst=item and item.catalyst and require("Modules.CraftingUniqueQuality").catalysts[item.catalyst]
		local property=item and ("Item level "..tostring(item.itemLevel or "unknown")) or equipped and "Current baseline" or starting and "Or use the equipped item" or "Paste an item or link a craft"
		if not expanded and jewellery and catalyst then property=catalyst.." "..tostring(quality).."% | "..property end
		local propertyWidth=w-propertyX-10
		if not expanded and socketLabel and #item.sockets<=6 then
			local start=w-12-(#item.sockets*20-4)
			if start>=180 then propertyWidth=math.min(propertyWidth,start-propertyX-8) end
		end
		if not expanded and jewellery and catalyst and DrawStringWidth(13,"VAR",property)>propertyWidth then
			property=catalyst.." "..tostring(quality).."% | iLvl "..tostring(item.itemLevel or "?")
			if DrawStringWidth(13,"VAR",property)>propertyWidth then property=catalyst.." "..tostring(quality).."%" end
		end
		DrawString(cx+propertyX,cy+76,"LEFT",13,"VAR",fit(property,13,math.max(0,propertyWidth)))
		if expanded and item then
			local qualityLabel=jewellery and (catalyst and (catalyst.." catalyst: +") or "Catalyst quality: +") or "Quality: +"
			DrawString(cx+propertyX,cy+98,"LEFT",13,"VAR",fit(qualityLabel..tostring(quality).."%",13,w-propertyX-10))
		end
		if expanded and item and item.armourData then
			local parts={};for _,entry in ipairs({{"Armour","Armour"},{"Evasion","Evasion"},{"EnergyShield","Energy shield"},{"Ward","Ward"}}) do
				local value=item.armourData[entry[1]];if value and value>0 then parts[#parts+1]=entry[2].." "..value end
			end
			local room=w-propertyX-10-(socketLabel and math.min(#item.sockets,6)*20+8 or 0)
			if #parts>0 and room>=70 then DrawString(cx+propertyX,cy+122,"LEFT",13,"VAR",fit(table.concat(parts," | "),13,room)) end
		end
		if socketLabel and #item.sockets<=6 then
			local start=cx+w-12-(#item.sockets*20-4)
			if start>=cx+180 then
				local socketY=cy+(expanded and 125 or 77)
				for i=2,#item.sockets do if item.sockets[i].group==item.sockets[i-1].group then
					SetDrawColor("^xC9B77D");DrawImage(nil,start+(i-1)*20-5,socketY+6,7,3)
				end end
				for i,socket in ipairs(item.sockets) do
					local sx=start+(i-1)*20;SetDrawColor("^xC9B77D");DrawImage(nil,sx,socketY,16,16)
					SetDrawColor(socketColors[socket.color] or "^x555B65");DrawImage(nil,sx+1,socketY+1,14,14)
					SetDrawColor("^xFFFFFF");DrawString(sx+8,socketY+1,"CENTER_X",12,"VAR",socket.color)
				end
			end
		end
	end
	return function(value,other)
		item=value;socketLabel=nil;local lines={}
		if item then
			-- Item parsing can synthesize default sockets when none were supplied;
			-- only present a layout when the item text actually records one.
			if item.raw and ("\n"..item.raw):match("\n%s*Sockets:%s*[RGBWA]") and #(item.sockets or {})>0 then
				local parts={};for i,socket in ipairs(item.sockets) do
					if i>1 then parts[#parts+1]=socket.group==item.sockets[i-1].group and "-" or " " end
					parts[#parts+1]=socket.color
				end
				socketLabel=table.concat(parts);lines[#lines+1]={text="Sockets: "..socketLabel}
			end
			local entry=artwork[item.baseName];local path=entry and entry.path or "Assets/icon_weapon.png"
			art=NewImageHandle();art:Load(path);artW,artH,artSprite=itemArt.artDimensions(item,entry and entry.width or 84,entry and entry.height or 84,artSize)
			local function display(owner,mod,index)
				if index==1 then return StripEscapes(itemLib.formatModLine(mod,false) or mod.line) end
				if owner.catalyst and #(mod.modTags or {})>0 then
					local scalar=owner:GetModLineValueScalar(mod,index==2 and "implicit" or "explicit")
					return itemLib.applyRange(mod.line,mod.range or 1,scalar,mod.corruptedRange)
				end
				return mod.line
			end
			local peer={};if other then for i,group in ipairs({other.enchantModLines or {},other.implicitModLines or {},other.explicitModLines or {}}) do for _,mod in ipairs(group) do peer[display(other,mod,i)]=true end end end
			for i,group in ipairs({item.enchantModLines or {},item.implicitModLines or {},item.explicitModLines or {}}) do for _,mod in ipairs(group) do local text=display(item,mod,i);lines[#lines+1]={text=text,changed=other and not peer[text]} end end
		else art=nil;lines={equipped and "This slot is empty in the current build." or starting and "The base and its modifiers will appear here." or "An exact target item enables native upgrade measurements."} end
		local rows={};for _,line in ipairs(lines) do local changed=type(line)=="table" and line.changed;local text=type(line)=="table" and line.text or line
			for _,row in ipairs(ui.rows({(changed and (equipped and "- " or "+ ") or "")..text},w-24,13)) do if changed then row[1]=(equipped and "^xE58F8F" or "^x92D39C")..StripEscapes(row[1]) end;rows[#rows+1]=row end
		end
		mods.list=rows;mods.controls.scrollBar.offset=0
	end
end
return M
