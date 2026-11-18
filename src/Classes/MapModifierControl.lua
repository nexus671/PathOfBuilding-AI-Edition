-- Inspect pinned map modifiers and estimate currency outcomes without using an item.
-- cspell:ignore AABBD
local ui=require("Modules.PlanningUI")
local map=require("Modules.MapCraftingData")
local browser=require("Classes.PlanningBrowserControl")
local M={}

local function readable(text)
	return ((text or ""):gsub("%[[^%]|]+|([^%]]+)%]","%1"):gsub("%[([^%]]+)%]","%1"))
end
local function range(value)
	return value.min==value.max and string.format("%+g%%",value.min) or string.format("(%+g to %+g)%%",value.min,value.max)
end

function M.Open(options)
	options=options or {};local initial=options.initial
	if initial then
		assert(initial.patch==map.source().patch,"This map draft uses a different data version")
		map.inspect(initial.baseId,initial.tier,initial.itemLevel,initial.selected,"",0,1,nil,initial.rarity=="normal" and "rare" or initial.rarity,initial.rolls,initial.corrupted,initial.implicit,initial.quality,initial.observedEffects)
	end
	local width=math.min(900,main.screenW-40);local height=math.min(600,main.screenH-60)
	local left=math.floor(width*0.38);local right=left+32;local rightWidth=width-right-16
	local controls={};local function isCorrupted() return controls.rarity and controls.rarity:GetSelValueByKey("val")=="corrupted_rare" or false end
	local function getRarity() local value=controls.rarity:GetSelValueByKey("val");return value=="corrupted_rare" and "rare" or value end
	local implicit=initial and initial.implicit and copyTable(initial.implicit) or nil
	local quality=initial and require("Modules.MapQuality").validate(initial.quality) or nil
	local observedEffects=initial and require("Modules.MapObservedEffects").validate(initial.observedEffects) or nil
	local selected=initial and copyTable(initial.selected) or {};local rolls=initial and copyTable(initial.rolls or {}) or {};local candidate,selectedAffix;local previousRarity;local baseId=initial and initial.baseId or "Metadata/Items/Maps/MapKeyTier16";local refresh,syncRarity;local offset,nextOffset=0,nil
	local estimateSettings=initial and initial.estimate and copyTable(initial.estimate) or nil
	local draftId=initial and initial.id
	local rollSeed=os.time()%2147483646+1
	local artManifest;do local f=assert(io.open("Assets/MapCrafting/art.json","rb"));artManifest=assert(require("dkjson").decode(f:read("*a")));f:close() end
	local itemArt;do local f=assert(io.open("Assets/MapCrafting/items.json","rb"));itemArt=assert(require("dkjson").decode(f:read("*a")));f:close() end
	local artCache={}
	local nightmareFrame
	local function art()
		local base=map.source().bases[baseId];local identity=base and base.visual_identity
		local entry=itemArt.images[baseId] or (type(identity)=="table" and artManifest.images[identity.dds_file])
		if not entry then return nil end
		if not artCache[entry.path] then local handle=NewImageHandle();handle:Load(entry.path);artCache[entry.path]=handle end
		return artCache[entry.path],entry
	end
	local function button(key,x,y,w,label,fn)
		controls[key]=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{x,y,w,28},label,fn))
	end
	ui.description(controls,"intro",16,28,width-32,34,{"Hypothetical map: rolls are estimates; some values remain ranges.","Corrupted side limits are unverified. Marking a rare map corrupted keeps its modifiers."},14)
	button("base",16,66,left-204,"Choose map",function()
		local rows={};local baseOffset=0
		repeat
			local page=map.searchBases("",baseOffset,100)
			for _,entry in ipairs(page.results) do
				local tier=entry.id:match("^Metadata/Items/Maps/MapKeyTier(%d+)$")
				local historical=entry.id:match("^Metadata/Items/Maps/MapWorlds")
				local nightmare=map.isNightmare(entry.id)
				if nightmare or not entry.special and (tier or historical) then
					rows[#rows+1]={id=entry.id,label=entry.name..(nightmare and " (Nightmare)" or historical and " (legacy)" or ""),search=entry.id,details={entry.id,nightmare and "Nightmare map: Chaos rerolls use an experimental model." or tier and "Current tier-based map item." or "Historical named map; availability is not verified."}}
				end
			end
			baseOffset=page.nextOffset
		until not baseOffset
		browser.Open("Choose map base",rows,{action="Use map",choose=function(entry)
			local wasNightmare=map.isNightmare(baseId);baseId=entry.id;local tier=baseId:match("^Metadata/Items/Maps/MapKeyTier(%d+)$")
			if tier or map.isNightmare(baseId) or wasNightmare then controls.tier:SelByValue(tier and tonumber(tier) or map.isNightmare(baseId) and 17 or 16,"val") end;syncRarity()
			if map.isNightmare(baseId) and not wasNightmare then controls.level:SetText("84") end
			selected={};rolls={};implicit=nil;quality=nil;observedEffects=nil;estimateSettings=nil;candidate=nil;offset=0;main:ClosePopup();refresh()
		end,closeOnChoose=false})
	end)
	button("pasteMap",16+left-196,66,96,"Paste map",function()
		local ok,result=pcall(require("Modules.MapClipboard").parse,Paste())
		if not ok then main:OpenMessagePopup("Paste map",ui.errorText(result));return end
		local state=result.state;local popup={}
		local label=map.source().bases[state.baseId].name.." | Tier "..state.tier.." | "..#state.selected.." modifiers"..(state.corrupted and " | Corrupted" or "")
		ui.description(popup,"review",16,28,608,108,{label,result.notes[1],result.notes[2],result.notes[3],"Using this map replaces the current draft's working modifiers and targets."},14)
		popup.keep=new("ButtonControl"):ButtonControl(ui.anchor,{16,154,200,28},"Use copied map",function()
			baseId=state.baseId;syncRarity();selected=copyTable(state.selected);rolls=copyTable(state.rolls);implicit=state.implicit and copyTable(state.implicit) or nil;quality=state.quality and copyTable(state.quality) or nil;observedEffects=state.observedEffects and copyTable(state.observedEffects) or nil
			controls.tier:SelByValue(state.tier,"val");controls.level:SetText(tostring(state.itemLevel))
			previousRarity=state.corrupted and "corrupted_rare" or state.rarity;controls.rarity:SelByValue(previousRarity,"val")
			estimateSettings=nil;candidate=nil;offset=0;controls.search:SetText("");main:ClosePopup();refresh()
		end)
		popup.close=new("ButtonControl"):ButtonControl(ui.anchor,{524,154,100,28},"Cancel",function() main:ClosePopup() end)
		ui.style(popup,{keep=true});main:OpenPopup(640,200,"Review copied map",popup,nil,nil,"close")
	end)
	button("quality",16+left-96,66,96,"Quality...",function()
		local popup={}
		ui.description(popup,"help",16,28,608,48,{"Record map quality as shown on the item.","Known 20% effects are shown; other effects are not modeled."},14)
		ui.label(popup,"kindLabel",16,92,"Quality type",14)
		popup.kind=new("EditControl"):EditControl(ui.anchor,{16,116,300,26},quality and quality.kind or "Pack Size",nil,nil,80)
		ui.label(popup,"valueLabel",340,92,"Quality %",14)
		popup.value=new("EditControl"):EditControl(ui.anchor,{340,116,120,26},quality and tostring(quality.value) or "20",nil,"%D",3)
		popup.keep=new("ButtonControl"):ButtonControl(ui.anchor,{16,164,180,28},"Keep quality",function()
			local ok,result=pcall(require("Modules.MapQuality").validate,{kind=popup.kind.buf,value=tonumber(popup.value.buf)})
			if not ok then main:OpenMessagePopup("Check quality",ui.errorText(result));return end
			quality=result;main:ClosePopup();refresh()
		end)
		popup.clear=new("ButtonControl"):ButtonControl(ui.anchor,{208,164,150,28},"Clear quality",function() quality=nil;main:ClosePopup();refresh() end)
		popup.close=new("ButtonControl"):ButtonControl(ui.anchor,{524,164,100,28},"Cancel",function() main:ClosePopup() end)
		ui.style(popup,{keep=true});main:OpenPopup(640,210,"Map quality",popup,nil,"kind","close")
	end)
	ui.label(controls,"tierLabel",16,108,"Map tier",14)
	local tiers={};for i=1,17 do tiers[#tiers+1]={label=tostring(i),val=i} end
	controls.tier=new("DropDownControl"):DropDownControl(ui.anchor,{90,103,80,26},tiers);controls.tier:SelByValue(initial and initial.tier or 16,"val")
	ui.label(controls,"levelLabel",182,108,"Item level",14)
	controls.level=new("EditControl"):EditControl(ui.anchor,{254,103,left-238,26},tostring(initial and initial.itemLevel or 83),nil,"%D",3)
	local function levelProblem()
		local level=tonumber(controls.level.buf)
		if not level or level~=math.floor(level) or level<1 or level>100 then return "Enter an item level from 1 to 100." end
		local required=0;for _,id in ipairs(selected) do local mod=map.source().mods[id];if mod then required=math.max(required,mod.required_level or 0) end end
		if required>level then return "A selected modifier requires item level "..required.." in the pinned data." end
	end
	local card=new("Control"):Control(ui.anchor,{16,144,left,height-216});controls.card=card
	function card:Draw()
		local x,y=self:GetPos();local w,h=self:GetSize();SetDrawColor("^x716046");DrawImage(nil,x,y,w,h)
		SetDrawColor("^x15141A");DrawImage(nil,x+1,y+1,w-2,h-2)
		local rarity=getRarity();local base=map.source().bases[baseId];local name=(require("Modules.MapObservedEffects").isBlighted(observedEffects) and "Blighted: " or "")..base.name;SetDrawColor(rarity=="magic" and "^x8888FF" or rarity=="normal" and "^7" or "^xE0C586");DrawString(x+w/2,y+12,"CENTER_X",18,"VAR",ui.fit(name,w-20,18))
		local handle,entry=art();if handle and map.isNightmare(baseId) then
			if not nightmareFrame then nightmareFrame=NewImageHandle();nightmareFrame:Load("Assets/MapCrafting/Items/NightmareFrame.png") end
			-- Nightmare artwork is a transparent symbol rendered on the map frame.
			-- Keep both full canvases aligned instead of enlarging the symbol's bounds.
			local size=95;local ax=x+(w-size)/2;local ay=y+40
			SetDrawColor(1,1,1);DrawImage(nightmareFrame,ax,ay,size,size);DrawImage(handle,ax,ay,size,size)
		elseif handle then
			local bounds=entry.bounds or {0,0,entry.width,entry.height};local bw,bh=bounds[3]-bounds[1],bounds[4]-bounds[2]
			local scale=math.min(95/bw,95/bh);local aw,ah=bw*scale,bh*scale
			SetDrawColor(1,1,1);DrawImage(handle,x+(w-aw)/2,y+40,aw,ah,bounds[1]/entry.width,bounds[2]/entry.height,bounds[3]/entry.width,bounds[4]/entry.height)
		end
		SetDrawColor(isCorrupted() and "^xE07070" or "^xAABBD0");DrawString(x+w/2,y+142,"CENTER_X",14,"VAR","Tier "..tostring(controls.tier:GetSelValueByKey("val"))..(isCorrupted() and " | Corrupted" or ""))
	end
	controls.affixes=new("TextListControl"):TextListControl(ui.anchor,{28,310,left-24,height-390},nil,{})
	-- Controls are visited in hash order, so draw the list above the card even
	-- when the card happens to be drawn later.
	local drawAffixes=controls.affixes.Draw
	function controls.affixes:Draw(viewPort)
		SetDrawLayer(nil,1);drawAffixes(self,viewPort);SetDrawLayer(nil,0)
	end
	button("remove",16,height-62,math.floor((left-8)/2),"Remove last",function()
		local index=#selected;for i,id in ipairs(selected) do if id==selectedAffix then index=i;break end end
		local id=table.remove(selected,index);for i=#rolls,1,-1 do if rolls[i].id==id then table.remove(rolls,i) end end
		selectedAffix=nil;candidate=nil;offset=0;refresh()
	end)
	controls.remove.enabled=function() return #selected>0 end
	controls.remove.tooltipText="Select a modifier on the item to remove it, or remove the last one."
	button("estimate",24+math.floor((left-8)/2),height-62,math.floor((left-8)/2),"Estimate rerolls",function()
		local state={baseId=baseId,tier=controls.tier:GetSelValueByKey("val"),itemLevel=tonumber(controls.level.buf),rarity=getRarity(),selected=copyTable(selected),rolls=copyTable(rolls),quality=quality and copyTable(quality) or nil,observedEffects=observedEffects and copyTable(observedEffects) or nil}
		require("Classes.MapCraftEstimateControl").Open(options.build,{state=state,wanted=selected,settings=estimateSettings,saveSettings=function(settings) estimateSettings=copyTable(settings) end,apply=function(sample)
			selected=copyTable(sample.selected);rolls=copyTable(sample.rolls);offset=0;candidate=nil;controls.search:SetText("");refresh()
		end})
	end)
	controls.estimate.enabled=function()
		local level=tonumber(controls.level.buf)
		return options.build~=nil and getRarity()~="normal" and not isCorrupted() and not require("Modules.MapObservedEffects").hasExplicit(observedEffects) and level~=nil and not levelProblem()
	end
	controls.estimate.tooltipText="Estimate Chaos or Alteration rerolls using selected modifiers as wanted targets. The item level must support those modifiers. Corrupted maps and unsupported explicit modifiers cannot be rerolled here. Nightmare estimates use unverified draw-order assumptions."
	ui.label(controls,"resultsLabel",right,68,"Available modifiers",16)
	ui.label(controls,"rarityLabel",right+180,68,"Rarity",14)
	local allRarities={{label="Normal",val="normal"},{label="Magic",val="magic"},{label="Rare",val="rare"},{label="Corrupted rare",val="corrupted_rare"}}
	local nightmareRarities={{label="Rare",val="rare"},{label="Corrupted rare",val="corrupted_rare"}}
	controls.rarity=new("DropDownControl"):DropDownControl(ui.anchor,{right+235,64,150,26},copyTable(allRarities));controls.rarity:SelByValue(initial and (initial.corrupted and "corrupted_rare" or initial.rarity) or "rare","val")
	syncRarity=function()
		local value=controls.rarity:GetSelValueByKey("val")
		if map.isNightmare(baseId) and value~="corrupted_rare" then value="rare" end
		controls.rarity:SetList(copyTable(map.isNightmare(baseId) and nightmareRarities or allRarities));controls.rarity:SelByValue(value,"val");previousRarity=value
	end
	syncRarity()
	button("implicit",right+393,64,rightWidth-393,"Implicit...",function()
		local module=require("Modules.MapCorruptionImplicits");local entries={{label="No implicit recorded",val=""}}
		for _,entry in ipairs(module.list()) do entries[#entries+1]={label=entry.label,val=entry.id} end
		local popup={};ui.description(popup,"help",16,28,608,40,{"Record an observed or hypothetical corruption implicit. Totals are estimates and omit unsupported effects."},14)
		popup.choice=new("DropDownControl"):DropDownControl(ui.anchor,{16,76,608,26},entries)
		popup.choice:SelByValue(implicit and implicit.id or "","val")
		ui.label(popup,"valueLabel",16,120,"Exact value (optional; leave blank for the range)",14)
		popup.value=new("EditControl"):EditControl(ui.anchor,{16,144,180,26},implicit and implicit.value and tostring(implicit.value) or "",nil,"%D",8)
		popup.choice.selFunc=function() popup.value:SetText("") end
		popup.keep=new("ButtonControl"):ButtonControl(ui.anchor,{16,194,200,28},"Keep implicit",function()
			local id=popup.choice:GetSelValueByKey("val");local next
			if id~="" then
				next={id=id};if popup.value.buf~="" then next.value=tonumber(popup.value.buf) end
				local ok,reason=pcall(module.describe,next,tonumber(controls.level.buf));if not ok then main:OpenMessagePopup("Check implicit",ui.errorText(reason));return end
			end
			implicit=next;main:ClosePopup();refresh()
		end)
		popup.close=new("ButtonControl"):ButtonControl(ui.anchor,{524,194,100,28},"Cancel",function() main:ClosePopup() end)
		ui.style(popup,{keep=true});main:OpenPopup(640,240,"Map corruption implicit",popup,nil,nil,"close")
	end)
	controls.implicit.enabled=function() return isCorrupted() end
	controls.implicit.tooltipText="Record a corruption implicit. Estimated totals exclude unsupported effects."
	previousRarity=controls.rarity:GetSelValueByKey("val")
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
		local current={baseId=baseId,tier=controls.tier:GetSelValueByKey("val"),itemLevel=tonumber(controls.level.buf),rarity=getRarity(),selected=selected,rolls=rolls,quality=quality,observedEffects=observedEffects}
		local ok,actions=pcall(require("Modules.MapCurrency").options,current)
		if not ok then main:OpenMessagePopup("Map currency",ui.errorText(actions));return end
		local rows={};for _,entry in ipairs(actions) do rows[#rows+1]={id=entry.id,label=entry.label..(entry.available and "" or " (unavailable)"),available=entry.available,icon="Assets/Crafting/"..entry.id..".png",details={entry.reason or "Available for this modeled map.","Experimental map crafting; no real currency is consumed.",map.isNightmare(baseId) and "Six modifiers: exclusive prefix and suffix first, then four weighted draws; order is unverified." or "Counts, selection and independent uniform stat rolls are estimates.",observedEffects and "Observed effects are not modeled and can change results." or "Unmatched translations remain ranges; some restrictions are unverified."}} end
		browser.Open("Use currency on hypothetical map",rows,{action="Apply estimate",canChoose=function(entry) return entry.available end,choose=function(entry)
			local state={baseId=baseId,tier=controls.tier:GetSelValueByKey("val"),itemLevel=tonumber(controls.level.buf),rarity=getRarity(),selected=selected,rolls=rolls,quality=quality,observedEffects=observedEffects}
			local ok,result=pcall(require("Modules.MapCurrency").perform,state,entry.id,rollSeed)
			if not ok then main:OpenMessagePopup("Currency unavailable",ui.errorText(result));return end
			rollSeed=rollSeed*16807%2147483647;selected=result.state.selected;rolls=result.state.rolls;controls.rarity:SelByValue(result.state.rarity,"val");previousRarity=result.state.rarity;candidate=nil;offset=0
			main:ClosePopup();controls.search:SetText("");refresh()
		end,closeOnChoose=false})
	end)
	controls.currency.enabled=function() return not isCorrupted() and not require("Modules.MapObservedEffects").hasExplicit(observedEffects) and not levelProblem() end
	controls.currency.tooltipText="Currency simulation requires a valid item level for the selected modifiers and is unavailable for corrupted maps or unsupported explicit modifiers. Nightmare Chaos rerolls use unverified draw-order assumptions."
	button("close",width-132,height-48,116,"Close",function() main:ClosePopup() end)
	if options.keep then
		ui.label(controls,"draftNameLabel",right,height-42,"Name",14)
		controls.draftName=new("EditControl"):EditControl(ui.anchor,{right+46,height-48,160,26},initial and initial.title or "Map draft",nil,nil,120)
		button("keep",right+218,height-48,150,"Keep map draft",function()
			local entry={id=draftId,title=controls.draftName.buf,patch=map.source().patch,baseId=baseId,tier=controls.tier:GetSelValueByKey("val"),itemLevel=tonumber(controls.level.buf),rarity=getRarity(),selected=copyTable(selected),rolls=copyTable(rolls),corrupted=isCorrupted() or nil,implicit=implicit and copyTable(implicit) or nil,quality=quality and copyTable(quality) or nil,observedEffects=observedEffects and copyTable(observedEffects) or nil}
			if estimateSettings then entry.estimate=copyTable(estimateSettings) end
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
		local rarity=getRarity()
		local ok,result=pcall(map.inspect,baseId,tier,level,selected,controls.search.buf,offset,30,nil,rarity=="normal" and "rare" or rarity,rolls,isCorrupted(),implicit,quality,observedEffects)
		if not ok then nextOffset=nil;controls.list.list={};controls.status.label="^xE9BE7B"..ui.fit(ui.errorText(result),rightWidth,14);show(nil);return end
		if rarity=="normal" then result.candidates={};result.total=0;result.nextOffset=nil end
		nextOffset=result.nextOffset
		local lines={};for _,entry in ipairs(result.candidates) do
			local rows=ui.rows({entry.name.." | "..entry.side},rightWidth-30,14)
			for _,row in ipairs(rows) do row.entry=entry;lines[#lines+1]=row end
		end
		controls.list.list=lines;controls.list.controls.scrollBar.offset=0;controls.status.label=rarity=="normal" and "^7Normal map | Use currency to add modifiers" or map.isNightmare(baseId) and "^xE9BE7BNightmare | Experimental | "..result.total.." candidates | Page "..(math.floor(offset/30)+1) or (isCorrupted() and "^xE07070Corrupted "..#selected.."/9 | " or "^7")..result.total.." candidates | Page "..(math.floor(offset/30)+1).." | weights are not odds"
		local problem=levelProblem();if problem then controls.status.label="^xE9BE7B"..ui.fit(problem,rightWidth,14) end
		local found=false;for _,id in ipairs(selected) do if id==selectedAffix then found=true;break end end
		if not found then selectedAffix=nil end
		controls.remove.label=selectedAffix and "Remove selected" or "Remove last"
		local affixes,affixIds={},{};local prefixLines=0
		if #selected==0 and not result.implicit and not (result.summary.qualityEffect and result.summary.qualityEffect.supported) then affixes={"No hypothetical modifiers selected."} else
			local summary=result.summary;local totals=summary.estimatedTotals or summary.totals
			affixes={summary.estimatedTotals and "^xAABBD0Estimated bonuses:" or "^xAABBD0Modifier bonuses (excludes quality):","^7Atlas Drops "..range(totals.atlasDrops),"Rarity "..range(totals.rarity).." | Pack size "..range(totals.packSize)}
			if summary.estimatedTotals then affixes[#affixes+1]="^xA6B3C6Excludes Atlas and other effects." end
			if result.implicit then affixes[#affixes+1]="^xB4B4FFImplicit: "..result.implicit.text end
			if result.implicit and result.implicit.id=="MapCorruptionModEffect" then affixes[#affixes+1]="^xE9BE7BMagnitude rounding is estimated; effect lines are unscaled." end
			for _,effect in ipairs(summary.effects) do
				local lines=#effect.lines==0 and {effect.name} or effect.lines
				for _,line in ipairs(lines) do affixes[#affixes+1]=line;affixIds[#affixes]=effect.id end
			end
		end
		if quality then
			local effect=result.summary.qualityEffect
			table.insert(affixes,1,"^xAABBD0Quality ("..quality.kind.."): +"..quality.value.."%")
			table.insert(affixes,2,effect.supported and "^xAABBD0"..effect.text or "^xE9BE7BQuality effect not modeled")
			prefixLines=prefixLines+2
		end
		if observedEffects then
			local blighted=require("Modules.MapObservedEffects").isBlighted(observedEffects)
			table.insert(affixes,1,blighted and "^xE9BE7BObserved effects are not fully modeled:" or "^xE9BE7BObserved effects are not modeled:")
			for i=#observedEffects,1,-1 do local effect=observedEffects[i];table.insert(affixes,2,"^xB4B4FF"..effect.text.." ("..effect.kind..")") end
			prefixLines=prefixLines+1+#observedEffects
			if blighted then
				table.insert(affixes,1,"^xE9BE7BBlighted: rare-only encounter modifiers are excluded.")
				prefixLines=prefixLines+1
			end
		end
		local rows={};for index,line in ipairs(affixes) do for _,row in ipairs(ui.rows({line},left-48,14)) do
			row.modifierId=affixIds[index-prefixLines];row.selected=row.modifierId~=nil and row.modifierId==selectedAffix;rows[#rows+1]=row
		end end
		controls.affixes.list=rows;show(nil)
	end
	controls.affixes.onClick=function(hit)
		local id=hit and hit.line and hit.line.modifierId
		if id then if selectedAffix==id then selectedAffix=nil else selectedAffix=id end;refresh() end
	end
	controls.list.onClick=function(hit) if hit and hit.line then show(hit.line.entry) end end
	controls.search.changeFunc=function() offset=0;refresh() end
	controls.level.changeFunc=function() candidate=nil;offset=0;refresh() end
	controls.tier.selFunc=function()
		local tier=controls.tier:GetSelValueByKey("val")
		if tier==17 and not map.isNightmare(baseId) then baseId="Metadata/Items/Maps/MapWorldsAbomination";controls.level:SetText("84")
		elseif tier<17 and (map.isNightmare(baseId) or baseId:match("^Metadata/Items/Maps/MapKeyTier%d+$")) then baseId="Metadata/Items/Maps/MapKeyTier"..tier end
		syncRarity()
		selected={};rolls={};implicit=nil;observedEffects=nil;estimateSettings=nil;offset=0;refresh()
	end
	controls.rarity.selFunc=function()
		local current=controls.rarity:GetSelValueByKey("val")
		if not (previousRarity=="rare" and current=="corrupted_rare") then selected={};rolls={};implicit=nil end
		if current~="rare" and current~="corrupted_rare" and observedEffects then
			local kept={};for _,effect in ipairs(observedEffects) do if effect.kind~="explicit" then kept[#kept+1]=effect end end
			observedEffects=require("Modules.MapObservedEffects").validate(kept)
		end
		previousRarity=current;estimateSettings=nil;candidate=nil;offset=0;refresh()
	end
	if controls.draftName then controls.draftName.changeFunc=function() if draftId then controls.status.label="^7Name changed. Keep the map draft again." end end end
	ui.style(controls,{add=true});refresh()
	main:OpenPopup(width,height,"Map modifier explorer",controls,nil,"search","close")
	return controls
end
return M
