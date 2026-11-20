local ui=require("Modules.PlanningUI")
local policy=require("Modules.LootFilterCampaign")
local visual=require("Modules.LootFilterVisuals")
local art=require("Modules.CraftingWorkbench")
local M={}
local names={
	["One Handed Axe"]="1H axes",["One Handed Mace"]="1H maces",["One Handed Sword"]="1H swords",["Two Handed Axe"]="2H axes",["Two Handed Mace"]="2H maces",["Two Handed Sword"]="2H swords",
	["Thrusting Sword"]="Thrusting swords",["Rune Dagger"]="Rune daggers",["Fishing Rod"]="Fishing rods",["Energy shield"]="Energy shield",["Armour / Energy shield"]="Armour / ES",["Evasion / Energy shield"]="Evasion / ES",["All three defences"]="Armour / Evasion / ES",
}
function M.Open(build,value,onKeep,mode)
	local current=policy.validate(value or policy.defaults());local selected={weapons={},defences={},recipes={}};local c={};local custom={}
	local w,h=math.min(1080,main.screenW-40),math.min(700,main.screenH-60);local column=math.floor((w-48)/2);local right=column+32
	local function selections(next) for key in pairs(selected) do selected[key]={};for _,name in ipairs(next[key]) do selected[key][name]=true end end end;selections(current)
	local function button(key,x,y,width,label,run) c[key]=new("ButtonControl"):ButtonControl(ui.anchor,{x,y,width,28},label,run) end
	ui.description(c,"help",16,28,w-212,48,{"Choose the base families and recipe pickups you want. These Show rules supplement your preset; personal rules and tiers keep priority. Nothing is automatically hidden."},14)
	button("enabled",w-180,28,164,"",function() current.enabled=not current.enabled end);c.enabled.label=function() return current.enabled and "Policy enabled" or "Policy disabled" end;c.enabled.locked=function() return current.enabled end
	local fields={{"minAreaLevel","From area",1,100},{"maxAreaLevel","Through area",1,100},{"minDropLevel","Minimum base level",0,100},{"minLinks","Minimum links",0,6},{"upgradeWindow","Upgrade window",0,100}}
	local fieldWidth=math.floor((w-48)/6)
	for i,field in ipairs(fields) do local key,title=field[1],field[2];local x=16+(i-1)*(fieldWidth+4);ui.label(c,key.."Label",x,96,title,12)
		c[key]=new("EditControl"):EditControl(ui.anchor,{x,120,fieldWidth-4,28},tostring(current[key]),nil,"%D",3)
	end
	button("equipped",16+5*(fieldWidth+4),120,w-32-5*(fieldWidth+4),"Use equipped",function()
		local equipped=policy.equipped(build)
		for _,key in ipairs({"weapons","defences"}) do selected[key]={};for _,name in ipairs(equipped[key]) do selected[key][name]=true end end
	end)
	c.upgradeWindow.tooltipText="0 keeps every selected base. Otherwise, five-area bands raise the required base DropLevel as you progress. A band starts at area level minus this window."
	c.minDropLevel.tooltipText="The game's base DropLevel, rather than the item's character requirements. Applies to base families, not recipe pickups."
	ui.label(c,"weaponsLabel",16,162,"Weapons, shields and quivers",16);ui.label(c,"defencesLabel",right,162,"Armour families",16)
	local families=policy.families()
	for _,group in ipairs({{"weapons",policy.weapons,16,column,3},{"defences",policy.defences,right,column,2}}) do
		local key,choices,x,width,cols=unpack(group);local tile=math.floor((width-(cols-1)*6)/cols)
		for i,name in ipairs(choices) do local id=key..i;local px,py=x+(i-1)%cols*(tile+6),188+math.floor((i-1)/cols)*44
			button(id,px,py,tile,"",function() selected[key][name]=not selected[key][name] or nil end);local control=c[id];control.height=38;control.planningFocusable=true;custom[id]=true;control.tooltipText=name.." | "..#(families[key][name] or {}).." bundled bases"
			local path,iw,ih;local baseName=(families[key][name] or {})[1];if baseName then local base=data.itemBases[baseName];path,iw,ih=art.itemArt({baseName=baseName,type=base.type}) end
			function control:Draw()
				local x,y=self:GetPos();local active=selected[key][name];visual.box(x,y,tile,38,self.hasFocus and "^x83C8EF" or active and "^xC7AD74" or "^x3F566F");visual.box(x+1,y+1,tile-2,36,active and "^x302B20" or "^x192635")
				if path then local scale=24/math.max(iw,ih);SetDrawColor(1,1,1);DrawImage(visual.image(path),x+6+(24-iw*scale)/2,y+7,iw*scale,ih*scale) end
				visual.text(x+36,y+12,12,names[name] or name,active and "^xF3D89D" or "^xD5DEE8",tile-42)
			end
		end
	end
	ui.label(c,"recipesLabel",right,378,"Recipe and socket pickups",14)
	local function updateSummary()
		if not c.summary then return end
		local lines={}
		if mode~="Ruthless" and selected.recipes["Low-level unidentified rare set pieces"] then lines[#lines+1]="Purple: item level below 60. One low-level piece makes a rare set an Alchemy recipe." end
		if mode~="Ruthless" and selected.recipes["Unidentified rare set pieces"] then lines[#lines+1]="Gold: 60-74; blue: 75+. For Chaos, at least one piece must be 60-74." end
		if #lines==0 then lines={"Upgrade windows use five-area bands. Recipe pickups follow only the area range. No vendor proceeds, hidden modifiers or economy value are assumed."} end
		c.summary.list=ui.rows(lines,column,13)
	end
	for i,name in ipairs(policy.recipes) do
		local x,y,width=right,396+(i-1)*20,column
		if name=="Vaal skill gems" then x,y,width=right+column-98,456,98 elseif i>=8 then width=math.floor((column-12)/3);x=right+(i-8)*(width+6);y=516 end
		local caption=name=="Vaal skill gems" and "Vaal gems" or name=="Quality flasks and tinctures" and "Quality flasks" or name
		button("recipe"..i,x,y,width,caption,function() selected.recipes[name]=not selected.recipes[name] or nil;updateSummary() end);c["recipe"..i].height=20;c["recipe"..i].locked=function() return selected.recipes[name] end
		if name=="Quality flasks and tinctures" then c["recipe"..i].tooltipText="Highlights quality flasks and tinctures for the Glassblower's Bauble recipe. Several items generally need 40% total quality; check the vendor offer." end
		if name=="Quality weapons" or name=="Quality armour" then c["recipe"..i].tooltipText="Highlights non-unique quality "..(name=="Quality weapons" and "weapons for Blacksmith's Whetstones" or "armour and shields for Armourer's Scraps")..". Several items need 40% total quality; check the vendor offer." end
		if name=="Vaal skill gems" then
			c["recipe"..i].enabled=function() return mode~="Ruthless" end
			c["recipe"..i].tooltipText=mode=="Ruthless" and "Not emitted in Ruthless: recipe availability has not been verified." or "Highlights Vaal skill gems. Vendor five Vaal skill gems for a Vaal Orb in 3.30."
		end
		if name=="Unidentified rare set pieces" or name=="Low-level unidentified rare set pieces" then
			c["recipe"..i].enabled=function() return mode~="Ruthless" end
			c["recipe"..i].tooltipText=mode=="Ruthless" and "Not emitted in Ruthless: recipe availability has not been verified." or name=="Low-level unidentified rare set pieces" and "Shows unidentified rare equipment below item level 60. A complete rare set with at least one such piece yields Alchemy Orbs." or "Shows unidentified rare equipment at item level 60+. Gold marks 60-74; blue marks 75+. A full set needs at least one 60-74 item for Chaos Orbs."
		end
	end
	c.recipe4.width=column-106;c.recipe5.width=column-106;c.recipe6.width=column-106
	button("rareSetSlots",right+column-98,476,98,"Slots...",function()
		local chosen={};for _,name in ipairs(current.rareSetSlots) do chosen[name]=true end
		local popup={};ui.description(popup,"help",16,30,428,44,{"Choose which rare-set pieces to highlight. A complete set still needs every required slot."},14)
		for i,name in ipairs(policy.rareSetSlots) do
			local key="slot"..i
			popup[key]=new("ButtonControl"):ButtonControl(ui.anchor,{16,88+(i-1)*36,428,28},name,function() chosen[name]=not chosen[name] or nil end)
			popup[key].locked=function() return chosen[name] end
		end
		popup.keep=new("ButtonControl"):ButtonControl(ui.anchor,{16,210,200,28},"Keep slot groups",function()
			local values={};for _,name in ipairs(policy.rareSetSlots) do if chosen[name] then values[#values+1]=name end end
			if #values==0 then main:OpenMessagePopup("Rare-set slots","Choose at least one slot group, or turn off rare-set pickups.");return end
			current.rareSetSlots=values;main:ClosePopup()
		end)
		popup.close=new("ButtonControl"):ButtonControl(ui.anchor,{328,210,116,28},"Cancel",function() main:ClosePopup() end)
		ui.style(popup,{keep=true});main:OpenPopup(460,256,"Rare-set slot groups",popup,nil,nil,"close")
	end)
	c.rareSetSlots.height=40;c.rareSetSlots.label=function() return #current.rareSetSlots.."/3 slots" end;c.rareSetSlots.enabled=function() return mode~="Ruthless" and (selected.recipes["Unidentified rare set pieces"] or selected.recipes["Low-level unidentified rare set pieces"]) end
	c.rareSetSlots.tooltipText="Choose jewellery, armour, and weapon/shield groups independently."
	local function read()
		local next=copyTable(current)
		for key,values in pairs(selected) do next[key]={};for name in pairs(values) do next[key][#next[key]+1]=name end end
		for _,field in ipairs(fields) do
			local n=tonumber(c[field[1]].buf)
			assert(n and n==math.floor(n) and n>=field[3] and n<=field[4],field[2].." must be between "..field[3].." and "..field[4]..".")
			next[field[1]]=n
		end
		assert(next.minAreaLevel<=next.maxAreaLevel,"From area cannot exceed Through area.")
		return policy.validate(next)
	end
	ui.description(c,"summary",16,h-112,column,64,{"Upgrade windows use five-area bands. Recipe pickups follow only the area range. No vendor proceeds, hidden modifiers or economy value are assumed."},13)
	updateSummary()
	button("keep",16,h-42,220,"Keep pickup policy",function()
		local ok,next=pcall(function() local value=read();policy.rules(value,nil,mode);return value end)
		if not ok then main:OpenMessagePopup("Check pickup policy",ui.errorText(next));return end
		onKeep(next);main:ClosePopup()
	end)
	button("reset",252,h-42,180,"Remove policy",function() onKeep(nil);main:ClosePopup() end)
	button("close",w-156,h-42,140,"Cancel",function() main:ClosePopup() end)
	ui.style(c,{keep=true},custom);for _,control in pairs(c) do control.layoutAudit="filter-campaign-policy" end;main:OpenPopup(w,h,"Campaign and base-family pickups",c,nil,nil,"close");return c
end
return M
