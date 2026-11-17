-- Inspect pinned map modifiers and estimate currency outcomes without using an item.
local ui=require("Modules.PlanningUI")
local map=require("Modules.MapCraftingData")
local browser=require("Classes.PlanningBrowserControl")
local M={}

local function readable(text)
	return (text or ""):gsub("%[[^%]|]+|([^%]]+)%]","%1")
end

function M.Open(options)
	options=options or {};local initial=options.initial
	if initial then
		assert(initial.patch==map.source().patch,"This map draft uses a different data version")
		map.inspect(initial.baseId,initial.tier,initial.itemLevel,initial.selected,"",0,1,nil,initial.rarity=="normal" and "rare" or initial.rarity)
	end
	local width=math.min(900,main.screenW-40);local height=math.min(600,main.screenH-60)
	local left=math.floor(width*0.38);local right=left+32;local rightWidth=width-right-16
	local controls={};local selected=initial and copyTable(initial.selected) or {};local candidate;local baseId=initial and initial.baseId or "Metadata/Items/Maps/MapWorldsStrand";local refresh;local offset,nextOffset=0,nil
	local draftId=initial and initial.id
	local rollSeed=os.time()%2147483646+1
	local artManifest;do local f=assert(io.open("Assets/MapCrafting/art.json","rb"));artManifest=assert(require("dkjson").decode(f:read("*a")));f:close() end
	local artCache={}
	local function art()
		local base=map.source().bases[baseId];local identity=base and base.visual_identity
		local entry=type(identity)=="table" and artManifest.images[identity.dds_file]
		if not entry then return nil end
		if not artCache[entry.path] then local handle=NewImageHandle();handle:Load(entry.path);artCache[entry.path]=handle end
		return artCache[entry.path],entry
	end
	local function button(key,x,y,w,label,fn)
		controls[key]=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{x,y,w,28},label,fn))
	end
	ui.description(controls,"intro",16,28,width-32,34,{"Hypothetical map: currency results are estimates; numerical values are not rolled.","Changing map, rarity, tier or item level clears selected modifiers."},14)
	button("base",16,66,left,"Choose map",function()
		local rows={};local baseOffset=0
		repeat
			local page=map.searchBases("MapWorlds",baseOffset,100)
			for _,entry in ipairs(page.results) do if not entry.special then rows[#rows+1]={id=entry.id,label=entry.name,search=entry.id,details={entry.id,"Availability in the current Atlas is not verified."}} end end
			baseOffset=page.nextOffset
		until not baseOffset
		browser.Open("Choose map base",rows,{action="Use map",choose=function(entry)
			baseId=entry.id;selected={};candidate=nil;offset=0;main:ClosePopup();refresh()
		end,closeOnChoose=false})
	end)
	ui.label(controls,"tierLabel",16,108,"Map tier",14)
	local tiers={};for i=1,16 do tiers[#tiers+1]={label=tostring(i),val=i} end
	controls.tier=new("DropDownControl"):DropDownControl(ui.anchor,{90,103,80,26},tiers);controls.tier:SelByValue(initial and initial.tier or 16,"val")
	ui.label(controls,"levelLabel",182,108,"Item level",14)
	controls.level=new("EditControl"):EditControl(ui.anchor,{254,103,left-238,26},tostring(initial and initial.itemLevel or 83),nil,"%D",3)
	local card=new("Control"):Control(ui.anchor,{16,144,left,height-216});controls.card=card
	function card:Draw()
		local x,y=self:GetPos();local w,h=self:GetSize();SetDrawColor("^x716046");DrawImage(nil,x,y,w,h)
		SetDrawColor("^x15141A");DrawImage(nil,x+1,y+1,w-2,h-2)
		local rarity=controls.rarity:GetSelValueByKey("val");local base=map.source().bases[baseId];SetDrawColor(rarity=="magic" and "^x8888FF" or rarity=="normal" and "^7" or "^xE0C586");DrawString(x+w/2,y+12,"CENTER_X",18,"VAR",ui.fit(base.name,w-20,18))
		local handle,entry=art();if handle then
			local bounds=entry.bounds or {0,0,entry.width,entry.height};local bw,bh=bounds[3]-bounds[1],bounds[4]-bounds[2]
			local scale=math.min(95/bw,95/bh);local aw,ah=bw*scale,bh*scale
			SetDrawColor(1,1,1);DrawImage(handle,x+(w-aw)/2,y+40,aw,ah,bounds[1]/entry.width,bounds[2]/entry.height,bounds[3]/entry.width,bounds[4]/entry.height)
		end
		SetDrawColor("^xAABBD0");DrawString(x+w/2,y+142,"CENTER_X",14,"VAR","Tier "..tostring(controls.tier:GetSelValueByKey("val")))
	end
	controls.affixes=new("TextListControl"):TextListControl(ui.anchor,{28,310,left-24,height-390},nil,{})
	button("remove",16,height-62,left,"Remove last modifier",function() table.remove(selected);candidate=nil;offset=0;refresh() end)
	controls.remove.enabled=function() return #selected>0 end
	ui.label(controls,"resultsLabel",right,68,"Available modifiers",16)
	ui.label(controls,"rarityLabel",right+180,68,"Rarity",14)
	controls.rarity=new("DropDownControl"):DropDownControl(ui.anchor,{right+235,64,100,26},{{label="Normal",val="normal"},{label="Magic",val="magic"},{label="Rare",val="rare"}});controls.rarity:SelByValue(initial and initial.rarity or "rare","val")
	controls.search=new("EditControl"):EditControl(ui.anchor,{right,96,rightWidth,26},"","Search modifiers",nil,160)
	controls.list=new("TextListControl"):TextListControl(ui.anchor,{right,132,rightWidth,height-410},nil,{})
	button("previous",right,height-270,100,"Previous",function() offset=math.max(0,offset-30);refresh() end)
	controls.previous.enabled=function() return offset>0 end
	button("next",right+108,height-270,100,"Next",function() if nextOffset then offset=nextOffset;refresh() end end)
	controls.next.enabled=function() return nextOffset~=nil end
	controls.details=new("TextListControl"):TextListControl(ui.anchor,{right,height-226,rightWidth,100},nil,{})
	ui.label(controls,"status",right,height-118,"",14)
	button("add",right,height-88,math.floor(rightWidth/2)-6,"Add modifier",function() if candidate then selected[#selected+1]=candidate.id;candidate=nil;offset=0;controls.search:SetText("");refresh() end end)
	controls.add.enabled=function() return candidate~=nil end
	button("currency",right+math.floor(rightWidth/2)+6,height-88,math.floor(rightWidth/2)-6,"Use currency",function()
		local actions={{"transmute","Orb of Transmutation"},{"alchemy","Orb of Alchemy"},{"alteration","Orb of Alteration"},{"chaos","Chaos Orb"},{"augmentation","Orb of Augmentation"},{"regal","Regal Orb"},{"exalt","Exalted Orb"},{"annul","Orb of Annulment"},{"scour","Orb of Scouring"}}
		local rows={};for _,entry in ipairs(actions) do rows[#rows+1]={id=entry[1],label=entry[2],icon="Assets/Crafting/"..entry[1]..".png",details={"Experimental map modifier identities; no real currency is consumed.","Count distribution and weighted selection are estimates. Numerical values are not rolled.","Base availability and some map restrictions are unverified."}} end
		browser.Open("Use currency on hypothetical map",rows,{action="Apply estimate",choose=function(entry)
			local state={baseId=baseId,tier=controls.tier:GetSelValueByKey("val"),itemLevel=tonumber(controls.level.buf),rarity=controls.rarity:GetSelValueByKey("val"),selected=selected}
			local ok,result=pcall(require("Modules.MapCurrency").perform,state,entry.id,rollSeed)
			if not ok then main:OpenMessagePopup("Currency unavailable",ui.errorText(result));return end
			rollSeed=rollSeed*16807%2147483647;selected=result.state.selected;controls.rarity:SelByValue(result.state.rarity,"val");candidate=nil;offset=0
			main:ClosePopup();controls.search:SetText("");refresh()
		end,closeOnChoose=false})
	end)
	button("close",width-132,height-48,116,"Close",function() main:ClosePopup() end)
	if options.keep then
		ui.label(controls,"draftNameLabel",right,height-42,"Name",14)
		controls.draftName=new("EditControl"):EditControl(ui.anchor,{right+46,height-48,160,26},initial and initial.title or "Map draft",nil,nil,120)
		button("keep",right+218,height-48,150,"Keep map draft",function()
			local entry={id=draftId,title=controls.draftName.buf,patch=map.source().patch,baseId=baseId,tier=controls.tier:GetSelValueByKey("val"),itemLevel=tonumber(controls.level.buf),rarity=controls.rarity:GetSelValueByKey("val"),selected=copyTable(selected)}
			local ok,result=pcall(options.keep,entry)
			if not ok then main:OpenMessagePopup("Map draft",ui.errorText(result));return end
			draftId=result;controls.status.label="^7Draft kept. Keep the plan and save the build."
		end)
		controls.keep.tooltipText="Keep this draft in the Atlas plan; keep the plan and save the build to persist it."
	end
	local function show(entry)
		candidate=entry
		local lines=entry and {entry.name.." | "..entry.side,"Spawn weight "..entry.spawnWeight.." (not a probability)",readable(entry.text)} or {"Choose a modifier to inspect it."}
		controls.details.list=ui.rows(lines,rightWidth-24,14);controls.details.controls.scrollBar.offset=0
	end
	refresh=function()
		local tier=controls.tier:GetSelValueByKey("val");local level=tonumber(controls.level.buf)
		local rarity=controls.rarity:GetSelValueByKey("val")
		local ok,result=pcall(map.inspect,baseId,tier,level,selected,controls.search.buf,offset,30,nil,rarity=="normal" and "rare" or rarity)
		if not ok then nextOffset=nil;controls.list.list={};controls.status.label="^xE9BE7B"..ui.fit(ui.errorText(result),rightWidth,14);show(nil);return end
		if rarity=="normal" then result.candidates={};result.total=0;result.nextOffset=nil end
		nextOffset=result.nextOffset
		local lines={};for _,entry in ipairs(result.candidates) do
			local rows=ui.rows({entry.name.." | "..entry.side},rightWidth-30,14)
			for _,row in ipairs(rows) do row.entry=entry;lines[#lines+1]=row end
		end
		controls.list.list=lines;controls.list.controls.scrollBar.offset=0;controls.status.label=rarity=="normal" and "^7Normal map | Use currency to add modifiers" or "^7"..result.total.." candidates | Page "..(math.floor(offset/30)+1).." | weights are not odds"
		local affixes={};for _,id in ipairs(selected) do local mod=map.source().mods[id];affixes[#affixes+1]=readable(type(mod.text)=="string" and mod.text or "") end
		if #affixes==0 then affixes={"No hypothetical modifiers selected."} end
		controls.affixes.list=ui.rows(affixes,left-48,14);show(nil)
	end
	controls.list.onClick=function(hit) if hit and hit.line then show(hit.line.entry) end end
	controls.search.changeFunc=function() offset=0;refresh() end
	controls.level.changeFunc=function() selected={};offset=0;refresh() end
	controls.tier.selFunc=function() selected={};offset=0;refresh() end
	controls.rarity.selFunc=function() selected={};offset=0;refresh() end
	if controls.draftName then controls.draftName.changeFunc=function() if draftId then controls.status.label="^7Name changed. Keep the map draft again." end end end
	ui.style(controls,{add=true});refresh()
	main:OpenPopup(width,height,"Map modifier explorer",controls,nil,"search","close")
	return controls
end
return M
