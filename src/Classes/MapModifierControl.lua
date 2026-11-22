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
		assert(map.acceptsDraftVersion(initial.patch),"This map draft uses a different data version")
		map.inspect(initial.baseId,initial.tier,initial.itemLevel,initial.selected,"",0,1,nil,initial.rarity,initial.rolls,initial.corrupted,initial.implicit,initial.quality,initial.observedEffects)
	end
	local draftNeedsUpdate=initial and initial.patch~=map.source().patch or false
	local width=math.min(900,main.screenW-40);local height=math.min(600,main.screenH-60)
	local left=math.floor(width*0.38);local right=left+32;local rightWidth=width-right-16
	local controls={};local function isCorrupted() return controls.rarity and (controls.rarity:GetSelValueByKey("val") or ""):match("^corrupted_")~=nil or false end
	local function getRarity() local value=controls.rarity:GetSelValueByKey("val");return value and value:gsub("^corrupted_","") end
	local mirrored=initial and initial.mirrored or nil
	local twiceCorrupted=initial and initial.twiceCorrupted or nil
	local unidentified=initial and initial.unidentified or nil
	local plannedAllflame=initial and require("Modules.MapAllflame").validate(initial.plannedAllflame) or nil
	local plannedDeified=initial and initial.plannedDeified or nil
	local plannedDelirium=initial and require("Modules.MapObservedEffects").validateDeliriumPlan(initial.plannedDelirium) or nil
	local vaalPreview=initial and initial.vaalPreview or nil
	local implicit=initial and initial.implicit and copyTable(initial.implicit) or nil
	local quality=initial and require("Modules.MapQuality").validate(initial.quality) or nil
	local observedEffects=initial and require("Modules.MapObservedEffects").validate(initial.observedEffects) or nil
	local selected=initial and copyTable(initial.selected) or {};local rolls=initial and copyTable(initial.rolls or {}) or {};local candidate,selectedAffix;local previousRarity;local baseId=initial and initial.baseId or "Metadata/Items/Maps/MapKeyTier16";local refresh,syncRarity;local offset,nextOffset=0,nil
	local estimateSettings=initial and initial.estimate and copyTable(initial.estimate) or nil
	local draftId=initial and initial.id
	local rollSeed=os.time()%2147483646+1
	local artManifest;do local f=assert(io.open("Assets/MapCrafting/art.json","rb"));artManifest=assert(require("dkjson").decode(f:read("*a")));f:close() end
	local itemArt;do local f=assert(io.open("Assets/MapCrafting/items.json","rb"));itemArt=assert(require("dkjson").decode(f:read("*a")));f:close() end
	local variantArt;do local f=assert(io.open("Assets/MapCrafting/variants.json","rb"));variantArt=assert(require("dkjson").decode(f:read("*a")));f:close() end
	local artCache={}
	local nightmareFrame
	local function art()
		local base=map.source().bases[baseId];local identity=base and base.visual_identity
		local effects=require("Modules.MapObservedEffects");local tier=baseId:match("^Metadata/Items/Maps/MapKeyTier(%d+)$")
		local variant=effects.isBlightRavaged(observedEffects) and "ravaged" or effects.isBlighted(observedEffects) and "blighted"
		local entry=tier and variant and variantArt.images[variant..":"..tier] or itemArt.images[baseId] or (type(identity)=="table" and artManifest.images[identity.dds_file])
		if not entry then return nil end
		if not artCache[entry.path] then local handle=NewImageHandle();handle:Load(entry.path);artCache[entry.path]=handle end
		return artCache[entry.path],entry
	end
	local function button(key,x,y,w,label,fn)
		controls[key]=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{x,y,w,28},label,fn))
	end
	ui.description(controls,"intro",16,28,width-32,34,{"Hypothetical map: rolls are estimates; some values remain ranges.","Corrupted side limits are unverified. Marking a map corrupted keeps its modifiers."},14)
	button("base",16,66,left-204,"Choose map",function()
		local rows={};local baseOffset=0
		repeat
			local page=map.searchBases("",baseOffset,100)
			for _,entry in ipairs(page.results) do
				local tier=entry.id:match("^Metadata/Items/Maps/MapKeyTier(%d+)$")
				local historical=entry.id:match("^Metadata/Items/Maps/MapWorlds")
				local nightmare=map.isNightmare(entry.id)
				if nightmare or not entry.special and (tier or historical) then
					rows[#rows+1]={id=entry.id,label=entry.name..(nightmare and historical and " (legacy Nightmare)" or nightmare and " (Nightmare)" or historical and " (legacy)" or ""),search=entry.id,details={entry.id,nightmare and "Nightmare map: Chaos rerolls use an experimental model." or tier and "Current tier-based map item." or "Historical named map; availability is not verified."}}
				end
			end
			baseOffset=page.nextOffset
		until not baseOffset
		browser.Open("Choose map base",rows,{action="Use map",choose=function(entry)
			local wasNightmare=map.isNightmare(baseId);baseId=entry.id;local tier=baseId:match("^Metadata/Items/Maps/MapKeyTier(%d+)$")
			if tier or map.isNightmare(baseId) or wasNightmare then controls.tier:SelByValue(tier and tonumber(tier) or map.isNightmare(baseId) and 17 or 16,"val") end;syncRarity()
			if map.isNightmare(baseId) and not wasNightmare then controls.level:SetText("84") end
			selected={};rolls={};implicit=nil;mirrored=nil;twiceCorrupted=nil;unidentified=nil;vaalPreview=nil;quality=nil;observedEffects=nil;plannedDelirium=nil;estimateSettings=nil;candidate=nil;offset=0;main:ClosePopup();refresh()
		end,closeOnChoose=false})
	end)
	button("pasteMap",16+left-196,66,96,"Paste map",function()
		local ok,result=pcall(require("Modules.MapClipboard").parse,Paste())
		if not ok then ui.errorPopup("Paste map",result);return end
		local state=result.state;local popup={}
		local label=map.source().bases[state.baseId].name.." | Tier "..state.tier.." | "..(state.unidentified and "Modifiers unknown" or #state.selected.." modifiers")..(state.twiceCorrupted and " | Twice Corrupted" or state.corrupted and " | Corrupted" or "")..(state.mirrored and " | Mirrored" or "")..(state.unidentified and " | Unidentified" or "")
		ui.description(popup,"review",16,28,608,108,{label,result.notes[1],result.notes[2],result.notes[3],"Using this map replaces the current draft's working modifiers and targets."},14)
		popup.keep=new("ButtonControl"):ButtonControl(ui.anchor,{16,154,200,28},"Use copied map",function()
			baseId=state.baseId;syncRarity();mirrored=state.mirrored or nil;twiceCorrupted=state.twiceCorrupted or nil;unidentified=state.unidentified or nil;selected=copyTable(state.selected);rolls=copyTable(state.rolls);implicit=state.implicit and copyTable(state.implicit) or nil;quality=state.quality and copyTable(state.quality) or nil;observedEffects=state.observedEffects and copyTable(state.observedEffects) or nil
			controls.tier:SelByValue(state.tier,"val");controls.level:SetText(tostring(state.itemLevel))
			previousRarity=state.corrupted and "corrupted_"..state.rarity or state.rarity;controls.rarity:SelByValue(previousRarity,"val")
			estimateSettings=nil;vaalPreview=nil;plannedDeified=nil;plannedAllflame=nil;plannedDelirium=nil;candidate=nil;offset=0;controls.search:SetText("");main:ClosePopup();refresh()
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
			if not ok then ui.errorPopup("Check quality",result);return end
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
		local rarity=getRarity();local base=map.source().bases[baseId];local name=(require("Modules.MapObservedEffects").isBlightRavaged(observedEffects) and "Blight-ravaged: " or require("Modules.MapObservedEffects").isBlighted(observedEffects) and "Blighted: " or "")..base.name;SetDrawColor(rarity=="magic" and "^x8888FF" or rarity=="normal" and "^7" or "^xE0C586");DrawString(x+w/2,y+12,"CENTER_X",18,"VAR",ui.fit(name,w-20,18))
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
		SetDrawColor(isCorrupted() and "^xE07070" or "^xAABBD0");DrawString(x+w/2,y+142,"CENTER_X",14,"VAR","Tier "..tostring(controls.tier:GetSelValueByKey("val"))..(twiceCorrupted and isCorrupted() and " | Twice Corrupted" or isCorrupted() and " | Corrupted" or "")..(mirrored and " | Mirrored" or "")..(unidentified and " | Unidentified" or ""))
	end
	controls.affixes=new("TextListControl"):TextListControl(ui.anchor,{28,310,left-24,height-390},nil,{})
	-- Controls are visited in hash order, so draw the list above the card even
	-- when the card happens to be drawn later.
	local drawAffixes=controls.affixes.Draw
	function controls.affixes:Draw(viewPort)
		SetDrawLayer(nil,1);drawAffixes(self,viewPort);SetDrawLayer(nil,0)
	end
	local cardButtonWidth=math.floor((left-32)/5)
	button("remove",16,height-62,cardButtonWidth,"Remove",function()
		local index=#selected;for i,id in ipairs(selected) do if id==selectedAffix then index=i;break end end
		local id=table.remove(selected,index);for i=#rolls,1,-1 do if rolls[i].id==id then table.remove(rolls,i) end end
		selectedAffix=nil;candidate=nil;offset=0;refresh()
	end)
	controls.remove.enabled=function() return not unidentified and #selected>0 end
	controls.remove.tooltipText="Select a modifier on the item to remove it, or remove the last one."
	button("estimate",24+cardButtonWidth,height-62,cardButtonWidth,"Rerolls",function()
		local state={baseId=baseId,tier=controls.tier:GetSelValueByKey("val"),itemLevel=tonumber(controls.level.buf),rarity=getRarity(),mirrored=mirrored,unidentified=unidentified,selected=copyTable(selected),rolls=copyTable(rolls),quality=quality and copyTable(quality) or nil,observedEffects=observedEffects and copyTable(observedEffects) or nil,plannedDeified=plannedDeified,plannedAllflame=plannedAllflame,plannedDelirium=plannedDelirium}
		require("Classes.MapCraftEstimateControl").Open(options.build,{state=state,wanted=selected,settings=estimateSettings,saveSettings=function(settings) estimateSettings=copyTable(settings) end,apply=function(sample)
			selected=copyTable(sample.selected);rolls=copyTable(sample.rolls);offset=0;candidate=nil;controls.search:SetText("");refresh()
		end})
	end)
	controls.estimate.enabled=function()
		local level=tonumber(controls.level.buf)
		return options.build~=nil and getRarity()~="normal" and not isCorrupted() and not mirrored and not unidentified and not require("Modules.MapObservedEffects").hasExplicit(observedEffects) and level~=nil and not levelProblem()
	end
	controls.estimate.tooltipText="Estimate Chaos or Alteration rerolls using selected modifiers as wanted targets. The item level must support those modifiers. Saved targets remain when the tier changes and may need editing. Corrupted or mirrored maps and unsupported explicit modifiers cannot be rerolled here. Nightmare estimates use unverified draw-order assumptions."
	button("delirium",32+2*cardButtonWidth,height-62,cardButtonWidth,"Delirium",function()
		local module=require("Modules.MapObservedEffects");local known=module.delirium(observedEffects)
		local uncertain=unidentified or module.hasExplicit(observedEffects) and not known
		for _,effect in ipairs(observedEffects or {}) do if effect.kind=="enchant" and (effect.text:lower():find("delirious",1,true) or effect.text:lower():find("delirium",1,true)) then uncertain=true end end
		local c={};local w,h=math.min(640,main.screenW-40),430
		ui.description(c,"intro",16,24,w-32,40,{map.isNightmare(baseId) and "3.30.0d fixed Delirium Orbs on Nightmare Maps. Preview only; reforging is not modeled." or "Preview Delirium Orb stacking. Legacy maps with Delirium layers cannot use these orbs."},14)
		ui.label(c,"currentLabel",16,76,"Starting %",14);ui.label(c,"currentTypeLabel",128,76,"Starting reward type",14)
		ui.label(c,"nextTypeLabel",344,76,"Next reward type",14)
		c.current=new("EditControl"):EditControl(ui.anchor,{16,100,96,26},plannedDelirium and tostring(plannedDelirium.currentPercent) or known and tostring(known.percent) or uncertain and "" or "0",nil,"%D",3)
		c.currentType=new("EditControl"):EditControl(ui.anchor,{128,100,200,26},plannedDelirium and (plannedDelirium.currentType or "") or known and known.rewardType or "",nil,nil,80)
		c.nextType=new("EditControl"):EditControl(ui.anchor,{344,100,w-360,26},plannedDelirium and plannedDelirium.nextType or known and known.rewardType or "Currency Items",nil,nil,80)
		ui.label(c,"gainLabel",16,180,"Example gain (5-50%)",14)
		c.gain=new("EditControl"):EditControl(ui.anchor,{16,204,120,26},plannedDelirium and tostring(plannedDelirium.gain) or "10",nil,"%D",2)
		ui.label(c,"targetLabel",16,240,"Target %",14)
		c.target=new("EditControl"):EditControl(ui.anchor,{16,264,120,26},plannedDelirium and tostring(plannedDelirium.targetPercent) or "100",nil,"%D",3)
		c.results=new("TextListControl"):TextListControl(ui.anchor,{152,180,w-168,120},nil,{})
		local function update()
			local ok,result=pcall(module.projectDelirium,tonumber(c.current.buf),c.currentType.buf,c.nextType.buf,tonumber(c.gain.buf),tonumber(c.target.buf))
			if not ok then c.results.list=ui.rows({ui.errorText(result)},w-190,14);return end
			local function line(label,value) return label..": "..value.percent.."% | "..value.baseRewardCount..(value.baseRewardCount==1 and " base reward" or " base rewards") end
			c.results.list=ui.rows({line("Example",result.example),"Possible: "..result.minimum.percent.."-"..result.maximum.percent.."% | "..result.minimum.baseRewardCount.."-"..result.maximum.baseRewardCount.." base rewards",result.sameType and "Same type: percentage accumulates." or "Different or new type: percentage starts over.",result.target and ("Target "..result.target.percent.."%: "..result.target.minimumOrbs.."-"..result.target.maximumOrbs.." orbs (5-50% per orb).") or "Enter a target from 1-100%."},w-190,14)
		end
		for _,key in ipairs({"current","currentType","nextType","gain","target"}) do c[key].changeFunc=update end
		local function chooseReward(target)
			local entries={};for _,choice in ipairs(module.orbReference().choices) do
				entries[#entries+1]={id=choice.name,label=choice.name,search=choice.reward,reward=choice.reward,details={"Reward type: "..choice.reward,"Client data 3.30.0.4; item availability and reforge behavior are not verified."}}
			end
			require("Classes.PlanningBrowserControl").Open("Choose Delirium Orb",entries,{action="Select orb",choose=function(entry) target:SetText(entry.reward);update() end})
		end
		c.chooseCurrentOrb=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{128,136,200,26},"Choose current...",function() chooseReward(c.currentType) end))
		c.chooseOrb=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{344,136,w-360,26},"Choose next...",function() chooseReward(c.nextType) end))
		c.chooseCurrentOrb.tooltipText="Choose the reward already on the map from pinned client data."
		c.chooseOrb.tooltipText="Choose the next reward from pinned client data, or enter a listed orb or reward name."
		ui.description(c,"scope",16,320,w-32,42,{"A saved plan is hypothetical; the map is unchanged. Eligibility, rerolled modifiers, other rewards and roll odds are not modeled."},12)
		c.keepPlan=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{16,h-42,125,28},"Keep plan",function()
			local ok,plan=pcall(module.validateDeliriumPlan,{currentPercent=tonumber(c.current.buf),currentType=c.currentType.buf,nextType=c.nextType.buf,gain=tonumber(c.gain.buf),targetPercent=tonumber(c.target.buf)})
			if not ok then ui.errorPopup("Delirium plan",plan);return end
			plannedDelirium=plan;main:ClosePopup();refresh()
		end))
		c.clearPlan=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{149,h-42,125,28},"Clear plan",function() plannedDelirium=nil;main:ClosePopup();refresh() end))
		c.clearPlan.enabled=function() return plannedDelirium~=nil end
		c.close=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{w-132,h-42,116,28},"Close",function() main:ClosePopup() end))
		ui.style(c);for _,control in pairs(c) do control.layoutAudit="map-delirium-projection" end
		update();main:OpenPopup(w,h,"Delirium projection",c,nil,"gain","close")
	end)
	controls.delirium.tooltipText="Project same-type stacking or a reward-type switch using a chosen example gain. Legacy maps with Delirium layers cannot use these orbs. Does not modify the map."
	button("deifiedPlan",40+3*cardButtonWidth,height-62,cardButtonWidth,"Deified",function()
		local popup={};local observed=require("Modules.MapObservedEffects").deified(observedEffects)
		ui.description(popup,"help",16,28,568,90,{"Plan a Divine Vessel enchantment for this map. This is hypothetical, not an observed effect.","Bosses: +25% damage, attack/cast speed and area; +100% toughness; +50% item rarity.","Eligibility, other enchantments, corruption order and Pantheon capture need in-game verification."},14)
		popup.plan=new("ButtonControl"):ButtonControl(ui.anchor,{16,136,175,28},"Plan Divine Vessel",function() plannedDeified=true;main:ClosePopup();refresh() end)
		popup.plan.enabled=not observed and not plannedDeified;popup.plan.tooltipText=observed and "The copied map already has Deified." or plannedDeified and "Deified is already planned." or "Add a hypothetical Divine Vessel plan."
		popup.clear=new("ButtonControl"):ButtonControl(ui.anchor,{208,136,175,28},"Remove plan",function() plannedDeified=nil;main:ClosePopup();refresh() end);popup.clear.enabled=not not plannedDeified
		popup.close=new("ButtonControl"):ButtonControl(ui.anchor,{484,136,100,28},"Close",function() main:ClosePopup() end)
		ui.style(popup,{plan=true});main:OpenPopup(600,180,"Deified map plan",popup,nil,nil,"close")
	end)
	controls.deifiedPlan.tooltipText="Plan or remove a hypothetical Divine Vessel enchantment without changing copied map effects."
	button("allflamePlan",48+4*cardButtonWidth,height-62,cardButtonWidth,"Allflame",function()
		local entries={}
		for _,item in ipairs(require("Modules.MapAllflame").list()) do
			entries[#entries+1]={id=item.id,label=item.name,icon=item.icon,search=item.description,details={item.name,item.description:gsub("\n"," "),"Conditional plan only. Eligibility, stacking, replacement, other enchantments and corruption order are unverified.","Descriptions are from the pinned 3.30.0.4 client data; drops and actual pack outcomes are not simulated."}}
		end
		browser.Open("Plan map Allflame",entries,{action="Use plan",choose=function(entry) plannedAllflame=entry.id;refresh() end,secondary={label="Clear plan",run=function() plannedAllflame=nil;main:ClosePopup();refresh() end}})
	end)
	controls.allflamePlan.tooltipText="Choose or clear a hypothetical map Allflame. Copied effects stay separate."
	ui.label(controls,"resultsLabel",right,68,"Available modifiers",16)
	ui.label(controls,"rarityLabel",right+180,68,"Rarity",14)
	local allRarities={{label="Normal",val="normal"},{label="Magic",val="magic"},{label="Rare",val="rare"},{label="Corrupted normal",val="corrupted_normal"},{label="Corrupted magic",val="corrupted_magic"},{label="Corrupted rare",val="corrupted_rare"}}
	local nightmareRarities={{label="Rare",val="rare"},{label="Corrupted rare",val="corrupted_rare"}}
	controls.rarity=new("DropDownControl"):DropDownControl(ui.anchor,{right+235,64,150,26},copyTable(allRarities));controls.rarity:SelByValue(initial and (initial.corrupted and "corrupted_"..initial.rarity or initial.rarity) or "rare","val")
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
				local ok,reason=pcall(module.describe,next,tonumber(controls.level.buf));if not ok then ui.errorPopup("Check implicit",reason);return end
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
	controls.add.enabled=function() return not unidentified and candidate~=nil end
	button("currency",right+math.floor(rightWidth/2)+6,height-88,math.floor(rightWidth/2)-6,"Use currency",function()
		local current={baseId=baseId,tier=controls.tier:GetSelValueByKey("val"),itemLevel=tonumber(controls.level.buf),rarity=getRarity(),mirrored=mirrored,unidentified=unidentified,selected=selected,rolls=rolls,quality=quality,observedEffects=observedEffects,plannedDeified=plannedDeified,plannedAllflame=plannedAllflame,plannedDelirium=plannedDelirium}
		local ok,actions=pcall(require("Modules.MapCurrency").options,current)
		if not ok then ui.errorPopup("Map currency",actions);return end
		local rows={};for _,entry in ipairs(actions) do rows[#rows+1]={id=entry.id,label=entry.label..(entry.available and "" or " (unavailable)"),available=entry.available,icon=(entry.id=="divine_vessel" or entry.id=="clear_deified_plan") and require("Modules.CraftingWorkbench").icon("divine_vessel") or "Assets/Crafting/"..(entry.id:match("^vaal_") and "vaal" or entry.id)..".png",details={entry.reason or entry.detail or (entry.id=="clear_deified_plan" and "Remove only the hypothetical plan; copied enchantments remain unchanged." or entry.id=="divine_vessel" and "Plan Deified boss bonuses; eligibility and enchantment interactions are unverified." or entry.id=="originator" and "Removes a random suffix and samples a rare-only replacement; some outcomes and weights are unverified." or entry.id:match("^vaal_") and "Conditional outcome only, not a full Vaal Orb roll; outcome odds are unknown." or "Available for this modeled map."),"Experimental map crafting; no real currency is consumed.",map.isNightmare(baseId) and "Six modifiers: exclusive prefix and suffix first, then four weighted draws; order is unverified." or "Counts, selection and independent uniform stat rolls are estimates.",observedEffects and "Observed effects are not modeled and can change results." or "Unmatched translations remain ranges; some restrictions are unverified."}} end
		browser.Open("Use currency on hypothetical map",rows,{action="Apply estimate",canChoose=function(entry) return entry.available end,choose=function(entry)
			local state={baseId=baseId,tier=controls.tier:GetSelValueByKey("val"),itemLevel=tonumber(controls.level.buf),rarity=getRarity(),mirrored=mirrored,unidentified=unidentified,selected=selected,rolls=rolls,quality=quality,observedEffects=observedEffects,plannedDeified=plannedDeified,plannedAllflame=plannedAllflame,plannedDelirium=plannedDelirium}
			local attemptSeed=rollSeed;rollSeed=rollSeed*16807%2147483647
			local ok,result=pcall(require("Modules.MapCurrency").perform,state,entry.id,attemptSeed)
			if not ok then ui.errorPopup("Currency unavailable",result);return end
			selected=result.state.selected;rolls=result.state.rolls;implicit=result.state.implicit and copyTable(result.state.implicit) or nil
			local rarityValue=result.state.corrupted and "corrupted_"..result.state.rarity or result.state.rarity
			local clearedEstimate=result.state.corrupted and estimateSettings~=nil
			if result.state.corrupted then estimateSettings=nil end
			vaalPreview=result.state.vaalPreview or nil;plannedDeified=result.state.plannedDeified or nil;plannedAllflame=result.state.plannedAllflame
			controls.rarity:SelByValue(rarityValue,"val");previousRarity=rarityValue;candidate=nil;offset=0
			main:ClosePopup();controls.search:SetText("");refresh()
			if entry.id=="originator" then controls.status.label="^xE9BE7BOriginator preview | replacement weights and interactions unverified" end
			if entry.id:match("^vaal_") then controls.status.label=clearedEstimate and "^xE9BE7BConditional Vaal outcome | reroll settings cleared" or "^xE9BE7BConditional Vaal outcome | overall odds not modeled" end
		end,closeOnChoose=false})
	end)
	controls.currency.enabled=function() return not isCorrupted() and not mirrored and not unidentified and not require("Modules.MapObservedEffects").hasExplicit(observedEffects) and not levelProblem() end
	controls.currency.tooltipText="Currency simulation requires a valid item level for the selected modifiers and is unavailable for corrupted, mirrored or unidentified maps or unsupported explicit modifiers. Nightmare Chaos rerolls use unverified draw-order assumptions."
	button("close",width-132,height-48,116,"Close",function() main:ClosePopup() end)
	if options.keep then
		ui.label(controls,"draftNameLabel",right,height-42,"Name",14)
		controls.draftName=new("EditControl"):EditControl(ui.anchor,{right+46,height-48,160,26},initial and initial.title or "Map draft",nil,nil,120)
		button("keep",right+218,height-48,150,"Keep map draft",function()
			local entry={id=draftId,title=controls.draftName.buf,patch=map.source().patch,baseId=baseId,tier=controls.tier:GetSelValueByKey("val"),itemLevel=tonumber(controls.level.buf),rarity=getRarity(),selected=copyTable(selected),rolls=copyTable(rolls),corrupted=isCorrupted() or nil,twiceCorrupted=twiceCorrupted and isCorrupted() or nil,mirrored=mirrored or nil,unidentified=unidentified or nil,vaalPreview=vaalPreview or nil,plannedDeified=plannedDeified or nil,plannedAllflame=plannedAllflame,plannedDelirium=plannedDelirium,implicit=implicit and copyTable(implicit) or nil,quality=quality and copyTable(quality) or nil,observedEffects=observedEffects and copyTable(observedEffects) or nil}
			if estimateSettings then entry.estimate=copyTable(estimateSettings) end
			local ok,result=pcall(options.keep,entry)
			if not ok then ui.errorPopup("Map draft",result);return end
			draftId=result;draftNeedsUpdate=false;controls.status.label="^7Draft kept. Keep the plan and save the build."
		end)
		controls.keep.tooltipText="Keep this draft using current map data in the Atlas plan; keep the plan and save the build to persist it."
	end
	local function show(entry)
		candidate=entry
		local lines=entry and {entry.name.." | "..entry.side,"Spawn weight "..entry.spawnWeight.." (not a probability)",readable(entry.text)} or {"Choose a modifier to inspect it."}
		controls.details.list=ui.rows(lines,rightWidth-24,14);controls.details.controls.scrollBar.offset=0
	end
	refresh=function()
		local tier=controls.tier:GetSelValueByKey("val");local level=tonumber(controls.level.buf)
		local rarity=getRarity()
		local ok,result=pcall(map.inspect,baseId,tier,level,selected,controls.search.buf,offset,30,nil,rarity,rolls,isCorrupted(),implicit,quality,observedEffects)
		if not ok then nextOffset=nil;controls.list.list={};controls.status.label="^xE9BE7B"..ui.fit(ui.errorText(result),rightWidth,14);show(nil);return end
		if rarity=="normal" or unidentified then result.candidates={};result.total=0;result.nextOffset=nil end
		nextOffset=result.nextOffset
		local lines={};for _,entry in ipairs(result.candidates) do
			local rows=ui.rows({entry.name.." | "..entry.side},rightWidth-30,14)
			for _,row in ipairs(rows) do row.entry=entry;lines[#lines+1]=row end
		end
		controls.list.list=lines;controls.list.controls.scrollBar.offset=0;controls.status.label=rarity=="normal" and (isCorrupted() and "^xE07070Corrupted normal map | No explicit modifiers" or "^7Normal map | Use currency to add modifiers") or map.isNightmare(baseId) and "^xE9BE7BNightmare | Experimental | "..result.total.." candidates | Page "..(math.floor(offset/30)+1) or (isCorrupted() and "^xE07070Corrupted "..#selected.."/"..(rarity=="magic" and 2 or 9).." | " or "^7")..result.total.." candidates | Page "..(math.floor(offset/30)+1).." | weights are not odds"
		if unidentified then controls.status.label="^xE9BE7BUnidentified | unknown modifiers; identify and paste again"
		elseif vaalPreview then controls.status.label="^xE9BE7BBased on conditional Vaal preview | outcome odds not modeled" end
		local problem=levelProblem();if problem then controls.status.label="^xE9BE7B"..ui.fit(problem,rightWidth,14) end
		if draftNeedsUpdate and not problem and not unidentified and not vaalPreview and not isCorrupted() and not map.isNightmare(baseId) then controls.status.label=ui.fit(controls.status.label.." | "..map.source().patch.." on keep",rightWidth,14) end
		local found=false;for _,id in ipairs(selected) do if id==selectedAffix then found=true;break end end
		if not found then selectedAffix=nil end
		controls.remove.label="Remove"
		local affixes,affixIds={},{};local prefixLines=0
		if unidentified then affixes={"^xE9BE7BUnidentified: explicit modifiers and totals are unknown.","^xAABBD0Opening unidentified: +30% Atlas Drops."}
		elseif #selected==0 and not result.implicit and not (result.summary.qualityEffect and result.summary.qualityEffect.supported) then affixes={"No hypothetical modifiers selected."} else
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
		if plannedAllflame then
			local planned=require("Modules.MapAllflame").describe(plannedAllflame)
			table.insert(affixes,1,"^xE9BE7BPlanned "..planned.name..": "..planned.description:gsub("\n"," "))
			table.insert(affixes,2,"^xE9BE7BEligibility and stacking unverified.")
			prefixLines=prefixLines+2
		end
		if plannedDeified then
			table.insert(affixes,1,"^xE9BE7BPlanned Deified bosses: +25% damage, attack/cast speed and area; +100% toughness; +50% item rarity. Eligibility unverified.")
			prefixLines=prefixLines+1
		end
		if observedEffects then
			local blighted=require("Modules.MapObservedEffects").isBlighted(observedEffects)
			table.insert(affixes,1,(blighted or result.delirium or result.deified) and "^xE9BE7BObserved effects are not fully modeled:" or "^xE9BE7BObserved effects are not modeled:")
			for i=#observedEffects,1,-1 do local effect=observedEffects[i];table.insert(affixes,2,"^xB4B4FF"..effect.text.." ("..effect.kind..")") end
			prefixLines=prefixLines+1+#observedEffects
			if result.delirium then
				table.insert(affixes,2,"^xAABBD0Base Delirium rewards: "..result.delirium.baseRewardCount.." | "..result.delirium.rewardType)
				prefixLines=prefixLines+1
			end
			if result.deified then
				table.insert(affixes,2,"^xAABBD0Deified bosses: +25% damage, attack/cast speed and area; +100% toughness; +50% item rarity.")
				prefixLines=prefixLines+1
			end
			if blighted then
				table.insert(affixes,1,"^xE9BE7BBlighted: rare-only encounter modifiers are excluded.")
				prefixLines=prefixLines+1
			end
		end
		if plannedDelirium then
			table.insert(affixes,1,"^xE9BE7BPlanned Delirium: "..plannedDelirium.targetPercent.."% "..plannedDelirium.nextType.." (hypothetical)")
			prefixLines=prefixLines+1
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
		if tier==17 and not map.isNightmare(baseId) then baseId="Metadata/Items/Maps/MapKeyNightmareBoss";controls.level:SetText("84")
		elseif tier<17 and (map.isNightmare(baseId) or baseId:match("^Metadata/Items/Maps/MapKeyTier%d+$")) then baseId="Metadata/Items/Maps/MapKeyTier"..tier end
		syncRarity()
		selected={};rolls={};implicit=nil;mirrored=nil;twiceCorrupted=nil;unidentified=nil;vaalPreview=nil;plannedDeified=nil;plannedAllflame=nil;plannedDelirium=nil;observedEffects=nil;offset=0;refresh()
	end
	controls.rarity.selFunc=function()
		local current=controls.rarity:GetSelValueByKey("val")
		if current~=previousRarity then unidentified=nil;vaalPreview=nil;twiceCorrupted=nil end
		if current~="corrupted_"..previousRarity then selected={};rolls={};implicit=nil end
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
