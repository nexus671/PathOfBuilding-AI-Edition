-- cspell:ignore RGBW RGBWA
-- A deliberately bounded unique-item quality operation. It never edits a build.
local M={}
M.catalysts={"Abrasive","Accelerating","Dextral","Fertile","Imbued","Intrinsic","Noxious","Prismatic","Sinistral","Tempering","Turbulent","Unstable"}
-- Partial item text can omit socket restrictions. Derive known restrictions
-- from bundled unique data, including legacy variants, and keep hidden cases.
local socketRestrictions={["Tabula Rasa"]="fixed",["Oni-Goroshi"]="fixed"}
local uniquesByName
local function uniqueSocketRestriction(title)
	if not uniquesByName then
		uniquesByName={}
		for _,entries in pairs(data.uniques or {}) do for _,raw in ipairs(entries) do
			local name=raw:match("^%s*([^\r\n]+)")
			if name then uniquesByName[name]=uniquesByName[name] or {};uniquesByName[name][#uniquesByName[name]+1]=raw end
		end end
	end
	if socketRestrictions[title]~=nil then return socketRestrictions[title] end
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
function M.guideAction(method,count,resource,corrupted,socketCount,enchantId,catalyst)
	if method=="catalyst" then local name=M.catalysts[catalyst];if not name then return nil end;return "Use "..count.." "..name.." Catalyst"..(count==1 and "" or "s") end
	if method=="bench_flask_enchant" then
		local flask=require("Modules.CraftingFlaskEnchants");local cost=flask.benchCost(enchantId)
		if not cost then return nil end
		local instilling=cost["Metadata/Items/Currency/CurrencyInstillingOrb"] or 0
		local baubles=cost["Metadata/Items/Currency/CurrencyFlaskQuality"] or 0
		return "Enchant at the crafting bench: "..flask.label(enchantId).." ("..instilling.." Instilling Orb"..(instilling==1 and "" or "s").." and "..baubles.." Glassblower's Bauble"..(baubles==1 and "" or "s")..")"
	end
	if method=="instilling" then return "Use an Instilling Orb to roll a utility flask enchantment" end
	if method=="enkindling" then return "Use an Enkindling Orb to roll a utility flask enchantment" end
	if method=="quality" then return "Use "..count.." "..resource..(count==1 and "" or "s") end
	if method=="divine" then return "Use a Divine Orb to reroll explicit modifier values" end
	if method=="tainted_quality" then return "Use a Tainted "..resource.." to reroll quality" end
	if method=="beast_max_links" then return "Link existing sockets with a Black Morrigan and a Craicic Sand Spitter" end
	if method=="omen_connections" then return "Link existing sockets with an Omen of Connections and an Orb of Fusing" end
	if method=="jeweller" then return "Use a Jeweller's Orb to reroll socket count" end
	if method=="tainted_jeweller" then return "Use a Tainted Jeweller's Orb to change socket count" end
	if method=="fusing" then return "Use an Orb of Fusing to reroll socket links" end
	if method=="tainted_fusing" then return "Use a Tainted Orb of Fusing to change socket links" end
	if method=="chromatic" then return "Use a Chromatic Orb to reroll socket colours" end
	if method=="tainted_chromatic" then return "Use a Tainted Chromatic Orb to reroll socket colours" end
	if method=="omen_trichromatism" then return "Use an Omen of Trichromatism and a Chromatic Orb to guarantee red, green and blue sockets" end
	if method=="omen_jeweller" then return "Add white sockets with an Omen of the Jeweller and a Jeweller's Orb" end
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
function M.matchesGuideAction(method,count,resource,corrupted,action,socketCount,enchantId,catalyst)
	return action==M.guideAction(method,count,resource,corrupted,socketCount,enchantId,catalyst) or method=="socket_white_bench" and action=="Use the crafting bench to make all sockets white"
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
	local jewellery=item.type=="Ring" or item.type=="Amulet" or item.type=="Belt"
	assert(weapon or item.base.armour or flask or jewellery,"Unique crafting supports armour, weapons, flasks, tinctures and jewellery")
	assert(not item.mirrored,"Mirrored items cannot be crafted")
	assert(item.corrupted or not alwaysCorrupted(item.title,item.baseName),"This unique is always corrupted; include its Corrupted line in the starting item")
	-- These uniques have hidden fixed six-link layouts. Only validate an
	-- explicitly supplied layout; missing sockets remain unknown.
	local tabula=item.baseName=="Simple Robe" and item.title=="Tabula Rasa"
	local fixedSix=tabula or item.baseName=="Simple Robe" and (item.title=="Skin of the Loyal" or item.title=="Skin of the Lords") or item.baseName=="Charan's Sword" and item.title=="Oni-Goroshi"
	if fixedSix and raw:find("\nSockets:",1,true) then
		local sockets=item.sockets or {};local linked=#sockets==6;local white=true
		for _,socket in ipairs(sockets) do
			linked=linked and (socket.color=="R" or socket.color=="G" or socket.color=="B" or socket.color=="W") and socket.group==sockets[1].group
			white=white and socket.color=="W"
		end
		assert(linked,"This unique has six linked sockets; correct the starting socket layout")
		assert(not tabula or white,"This unique has six linked white sockets; correct the starting socket layout")
	end
	assert(not item.foulborn,"Foulborn items need a separate modifier-mutation model")
	local quality=jewellery and (item.catalystQuality or (item.catalyst and 20) or item.quality or 0) or (item.quality or 0);assert(type(quality)=="number" and quality>=0 and quality==math.floor(quality),"Invalid item quality")
	return item,{quality=quality,qualitySupported=not jewellery,available=not jewellery and quality<20 and not item.corrupted,resource=not jewellery and (flask and "Glassblower's Bauble" or weapon and "Blacksmith's Whetstone" or "Armourer's Scrap") or nil,resourceKey=not jewellery and (flask and "Metadata/Items/Currency/CurrencyFlaskQuality" or weapon and "Metadata/Items/Currency/CurrencyWeaponQuality" or "Metadata/Items/Currency/CurrencyArmourQuality") or nil}
end
-- A guide only: the item and modifier values are not rewritten or simulated.
local function catalystGuideForItem(raw,item,info,catalyst,target)
	assert(item.type=="Ring" or item.type=="Amulet" or item.type=="Belt","Catalysts require a ring, amulet or belt")
	assert(not item.corrupted,"Ordinary catalysts cannot modify a corrupted item")
	assert(type(catalyst)=="number" and catalyst==math.floor(catalyst) and M.catalysts[catalyst],"Choose a catalyst type")
	assert(type(target)=="number" and target==math.floor(target) and target>=1 and target<=20,"Choose a quality target from 1 to 20")
	assert(not ("\n"..raw):find("\nCatalyst:",1,true) or item.catalyst,"The existing catalyst type could not be identified")
	assert(info.quality==0 or item.catalyst,"The existing quality type could not be identified")
	local start=item.catalyst==catalyst and info.quality or 0
	assert(start<target,"The item already has at least that quality of this type")
	local count=target-start
	local warning="Check that this catalyst affects the intended modifiers; effects are not previewed."
	if catalyst==3 or catalyst==9 then warning=warning.." Prefix/suffix catalysts may not affect fixed unique modifiers." end
	return {action=M.guideAction("catalyst",count,nil,nil,nil,nil,catalyst),stopWhen=target.."% "..M.catalysts[catalyst].." quality. "..warning,uniqueCraft={method="catalyst",count=count,catalyst=catalyst},done=false}
end
function M.catalystGuide(raw,catalyst,target)
	local item,info=M.inspect(raw);return catalystGuideForItem(raw,item,info,catalyst,target)
end

-- Imported armour lines are totals, which PoB uses to infer the base roll.
-- Keep that inferred roll when an operation changes modifiers or quality;
-- otherwise the old displayed total would be inferred again after the edit.
local function preserveArmourBaseline(raw,output,item)
	if not item.base.armour or not item.armourData then return output end
	local source="\n"..raw:gsub("\r\n","\n");local newline=raw:find("\r\n",1,true) and "\r\n" or "\n"
	for _,entry in ipairs({{"Armour","Armour"},{"Evasion","Evasion"},{"Evasion Rating","Evasion"},{"Energy Shield","EnergyShield"},{"Ward","Ward"}}) do
		local label,key=entry[1],entry[2];local marker=key.."BasePercentile"
		if source:find("\n"..label..":",1,true) and not source:find("\n"..marker..":",1,true) then
			local value=item.armourData[marker];assert(type(value)=="number" and value==value and value>=0 and value<=1,"The imported armour baseline could not be preserved")
			local inserted=0;local prefix=label..":"
			output=output:gsub("[^\r\n]+",function(line)
				if line:sub(1,#prefix)==prefix then inserted=inserted+1;return line..newline..marker..": "..tostring(value) end
				return line
			end)
			assert(inserted==1,"The imported armour property could not be located safely")
			source=source.."\n"..marker..":"
		end
	end
	return output
end
-- Game-copy metadata must stay in the property section. Appending a missing
-- quality line after the modifiers would make it look like a modifier.
local function addQuality(raw,value)
	local newline=raw:find("\r\n",1,true) and "\r\n" or "\n"
	local _,last=raw:find("\n%-%-%-%-%-%-%-%-\r?\n")
	if last then return raw:sub(1,last).."Quality: "..value..newline..raw:sub(last+1) end
	return raw..(raw:sub(-1)=="\n" and "" or newline).."Quality: "..value
end
function M.apply(raw)
	local item,info=M.inspect(raw);assert(info.qualitySupported,"Jewellery quality requires a catalyst");assert(not item.corrupted,"Ordinary quality currency cannot modify a corrupted item");assert(info.available,"Ordinary quality currency cannot exceed 20%")
	local padded="\n"..raw
	local output,count=padded:gsub("\nQuality:[^\r\n]*","\nQuality: "..(info.quality+1))
	assert(count<=1,"Item text contains multiple quality lines")
	output=output:sub(2)
	if count==0 then output=addQuality(raw,info.quality+1) end
	if count>0 then assert(withoutQuality(raw)==withoutQuality(output),"Unique item properties changed while applying quality") end
	output=preserveArmourBaseline(raw,output,item)
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

-- Replace only explicitly marked enchantment lines. Preserve all other copied
-- item text, including fields PoB does not interpret.
function M.flaskEnchantReason(raw,method)
	local ok,item=pcall(M.inspect,raw);if not ok then return tostring(item) end
	if method~="instilling" and method~="enkindling" and method~="bench_flask_enchant" then return "Choose a flask enchantment currency" end
	if item.corrupted then return "Flask enchantment currency requires an uncorrupted item" end
	if not require("Modules.CraftingFlaskEnchants").eligible({item=item}) then return "Requires a utility flask" end
	local text=raw:gsub("\r\n","\n");if text:find("\r",1,true) then return "The item has mixed line endings" end
	local marked,counts=0,0
	for line in (text.."\n"):gmatch("([^\n]*)\n") do
		if line:find("{enchant}",1,true) or line:match(" %(enchant%)%s*$") then marked=marked+1 end
		if line:match("^Implicits:%s*%d+%s*$") then counts=counts+1 end
	end
	if counts>1 then return "The item has more than one implicit-count line" end
	if marked~=#item.enchantModLines then return "Existing enchantment lines could not be identified safely" end
end
function M.flaskEnchant(raw,method,seed,enchantId)
	local reason=M.flaskEnchantReason(raw,method);assert(not reason,reason)
	assert(type(seed)=="number" and seed==math.floor(seed) and seed>=1 and seed<=2147483646,"Invalid seed")
	local before=M.inspect(raw);local flask=require("Modules.CraftingFlaskEnchants")
	local cost=method=="bench_flask_enchant" and flask.benchCost(enchantId)
	if method=="bench_flask_enchant" then assert(cost,"Choose an available flask bench enchantment") end
	local selected=cost and {id=enchantId} or flask.roll(method,require("Modules.CalcTime").random(seed))
	local entry,group=flask.validate({item=before},selected);local replacements=flask.lines(entry,group,selected.roll)
	local newline=raw:find("\r\n",1,true) and "\r\n" or "\n";local source=raw:gsub("\r\n","\n");local ended=source:sub(-1)=="\n"
	local lines={};local insertion,countIndex,implicitCount;local removed=0
	for line in (source..(ended and "" or "\n")):gmatch("([^\n]*)\n") do
		if line:find("{enchant}",1,true) or line:match(" %(enchant%)%s*$") then insertion=insertion or #lines+1;removed=removed+1
		else
			local count=line:match("^Implicits:%s*(%d+)%s*$")
			if count then countIndex=#lines+1;implicitCount=tonumber(count) end
			lines[#lines+1]=line
		end
	end
	if countIndex then assert(implicitCount>=removed,"The implicit count does not match the enchantment lines");lines[countIndex]="Implicits: "..(implicitCount-removed+#replacements) end
	insertion=insertion or (countIndex and countIndex+1) or #lines+1
	for i=#replacements,1,-1 do table.insert(lines,insertion,"{enchant}"..replacements[i]) end
	local output=table.concat(lines,newline)..(ended and newline or "")
	local after=M.inspect(output);assert(after.title==before.title and after.baseName==before.baseName and not after.corrupted,"Unique flask did not round-trip")
	local function linesOf(item,key) local result={};for _,line in ipairs(item[key] or {}) do result[#result+1]=line.line end;return result end
	assert(tableDeepEquals(linesOf(before,"explicitModLines"),linesOf(after,"explicitModLines")) and tableDeepEquals(linesOf(before,"implicitModLines"),linesOf(after,"implicitModLines")),"The flask's other modifiers could not be preserved safely")
	assert(tableDeepEquals(selected,flask.identify(after)),"The flask enchantment did not round-trip")
	return {itemText=output,components=cost or {[method]=1},flaskEnchant=selected}
end

-- Tainted quality uses the same estimated range as ordinary equipment.
-- Preserve the original unique text instead of reconstructing its modifiers.
function M.taintedQualityReason(raw)
	local ok,item=pcall(M.inspect,raw);if not ok then return tostring(item) end
	if not item.corrupted then return "Tainted currency requires a corrupted item" end
	if not item.base.armour and not data.weaponTypeInfo[item.type] then return "Tainted quality requires armour or a weapon" end
end
function M.taintedQuality(raw,seed)
	local reason=M.taintedQualityReason(raw);assert(not reason,reason)
	assert(type(seed)=="number" and seed==math.floor(seed) and seed>=1 and seed<=2147483646,"Invalid seed")
	local before=M.inspect(raw);local sim=require("Modules.CraftingSimulator")
	local state={affixes={},sockets=copyTable(before.sockets),quality=before.quality,corrupted=true}
	local model={item=before,byId={}}
	local rolled=sim.action(model,state,{method="tainted_quality"},require("Modules.CalcTime").random(seed))
	local padded="\n"..raw;local output,count=padded:gsub("\nQuality:[^\r\n]*","\nQuality: "..rolled.quality)
	assert(count<=1,"Item text contains multiple quality lines");output=output:sub(2)
	if count==0 then output=addQuality(raw,rolled.quality) end
	if count>0 then assert(withoutQuality(raw)==withoutQuality(output),"Unique item properties changed while applying quality") end
	output=preserveArmourBaseline(raw,output,before)
	local after,info=M.inspect(output)
	assert(after.title==before.title and after.baseName==before.baseName and after.corrupted and info.quality==rolled.quality,"Unique item did not round-trip after tainted quality")
	return {itemText=output,quality=info.quality,components=sim.components({method="tainted_quality"},state,model)}
end

-- A bounded Divine preview for complete, unambiguous unique templates.
-- Numeric copies are matched to single integer ranges before rerolling.
local function divinePlanForReference(raw,item,reference)
	local expected={};for _,line in ipairs(reference.explicitModLines or {}) do if reference:CheckModLineVariant(line) then
		if reference.catalyst and (not line.modTags or #line.modTags==0) then return nil,"Catalyst-scaled or untagged explicit modifiers need a separate Divine model" end
		local scalar=reference.catalyst and reference:GetModLineValueScalar(line,"explicit") or 1
		local text=line.line;local ranges,parts={},{};local pos=1
		while true do
			local first,last,low,high=text:find("%((%-?%d+)%-(%-?%d+)%)",pos);if not first then break end
			low,high=tonumber(low),tonumber(high);if high<=low or high-low>100000 or low< -100000 or high>100000 then return nil,"This modifier range needs a separate Divine model" end
			parts[#parts+1]=text:sub(pos,first-1);ranges[#ranges+1]={low=low,high=high};pos=last+1
		end
		parts[#parts+1]=text:sub(pos)
		local profile,fixed
		if scalar~=1 then
			if #ranges==0 then fixed=itemLib.applyRange(text,0,scalar)
			elseif #ranges==1 then
				profile=require("Modules.CraftingUniqueCatalyst").profile(text,ranges[1].low,ranges[1].high,scalar)
				if not profile then return nil,"This catalyst-scaled modifier needs a separate Divine model" end
			else
				profile=require("Modules.CraftingUniqueCatalyst").multiProfile(text,ranges,scalar)
				if not profile then return nil,"This catalyst-scaled multi-range modifier needs a separate Divine model" end
			end
		end
		local _,allRanges=text:gsub("%(%-?[%d%.]+%-%-?[%d%.]+%)","")
		if allRanges~=#ranges or #ranges>6 then return nil,"Fractional or complex ranges need a separate Divine model" end
		-- Advanced copied values cannot safely encode an external sign combined
		-- with a signed range in a multi-range line.
		if #ranges>1 then for i,range in ipairs(ranges) do if range.low<0 or parts[i]:sub(-1)=="-" then return nil,"This signed multi-range modifier needs a separate Divine model" end end end
		local pattern={"^"}
		for i,part in ipairs(parts) do
			local optionalPlus=i<=#ranges and ranges[i].low<=0 and part:sub(-1)=="+"
			if optionalPlus then part=part:sub(1,-2) end
			pattern[#pattern+1]=part:gsub("([^%w])","%%%1");if optionalPlus then pattern[#pattern+1]="%+?" end
			if i<=#ranges then pattern[#pattern+1]="(%-?%d+)" end
		end
		pattern[#pattern+1]="$";expected[#expected+1]={line=text,ranges=ranges,pattern=table.concat(pattern),scalar=scalar,profile=profile,fixed=fixed,tags=line.modTags}
	end end
	local rows,seen={},{}
	for _,line in ipairs(item.explicitModLines or {}) do
		if line.disabled or line.custom or line.crafted or line.fractured or line.mutated or line.scourge or line.crucible or line.unscalable then return nil,"Special modifier lines need a separate Divine model" end
		local text=line.line;local match,matchedValues
		for _,candidate in ipairs(expected) do if not candidate.used then
			local matches=text==candidate.line;local numbers
			if candidate.scalar~=1 then
				local effective=text
				if line.modTags and #line.modTags>0 and (not candidate.profile or text~=candidate.line) then effective=itemLib.applyRange(text,1,candidate.scalar) end
				if candidate.profile then
					local displayed=candidate.profile.lookup[effective]
					if displayed~=nil then matches=true;numbers=type(displayed)=="table" and copyTable(displayed) or {displayed}
					elseif text==candidate.line and line.modTags and tableDeepEquals(line.modTags,candidate.tags) and line.valueScalar==candidate.scalar then
						local rendered=itemLib.applyRange(candidate.line,line.range or 0.5,candidate.scalar)
						displayed=candidate.profile.lookup[rendered];matches=displayed~=nil;if matches then numbers=type(displayed)=="table" and copyTable(displayed) or {displayed} end
					else matches=false end
				else matches=effective==candidate.fixed end
			end
			if not matches and candidate.scalar==1 and #candidate.ranges>0 then
				local captures={text:match(candidate.pattern)}
				if #captures==#candidate.ranges then
					numbers={};matches=true
					for i,value in ipairs(captures) do local number=tonumber(value);local range=candidate.ranges[i];if not number or number<range.low or number>range.high then matches=false;break end;numbers[i]=number end
				end
			end
			if matches and line.modTags and #line.modTags>0 and not tableDeepEquals(line.modTags,candidate.tags or {}) then matches=false end
			if matches then if match then return nil,"This modifier matches multiple bundled ranges" end;match=candidate;matchedValues=numbers end
		end end
		if not match then return nil,"Use complete modifiers matching the bundled unique template" end
		match.used=true
		if #match.ranges>0 then
			local source,count=nil,0
			for rawLine in raw:gmatch("[^\r\n]+") do
				local plain=rawLine:gsub("^%{range:[^}]+%}",""):gsub("^%{tags:[^}]+%}","")
				local advanced=plain:gsub("(%-?%d+)(%(%-?%d+%-%-?%d+%))","%2")
				local advancedValues=plain:gsub("(%-?%d+)(%(%-?%d+%-%-?%d+%))","%1")
				if plain==text or line.rangeFromValue and text==match.line and advanced==match.line or advanced==match.line and advancedValues==text then source=plain;count=count+1 end
			end
			if count~=1 then return nil,"The original modifier line cannot be identified safely" end
			if seen[source] then return nil,"Repeated modifier lines need a separate Divine model" end
			local current=matchedValues
			if text==match.line and not match.profile then
				local range=line.range or 0.5;if type(range)~="number" or range~=range or range<0 or range>1 then return nil,"The current modifier roll is outside its supported range" end
				current={};for i,part in ipairs(match.ranges) do current[i]=math.floor(part.low+range*(part.high-part.low)+0.5) end
			end
			seen[source]=true;rows[#rows+1]={input=source,line=match.line,ranges=match.ranges,current=current,profile=match.profile,tags=match.profile and match.tags or nil}
		end
	end
	for _,row in ipairs(expected) do if not row.used then return nil,"Use complete modifiers matching the bundled unique template" end end
	if #rows==0 then return nil,"No supported variable explicit modifiers were found" end
	return {item=item,rows=rows}
end
local function divinePlan(raw)
	local ok,item=pcall(M.inspect,raw);if not ok then return nil,tostring(item) end
	if item.corrupted then return nil,"Divine Orbs cannot modify a corrupted item" end
	if item.type=="Tincture" and item.tinctureValues=="Final" then return nil,"Copied tincture values need a separate scaling model for Divine rolls" end
	local jewellery=item.type=="Ring" or item.type=="Amulet" or item.type=="Belt"
	if jewellery and ("\n"..raw):find("\nCatalyst:",1,true) and not item.catalyst then return nil,"Unrecognized jewellery catalyst needs a separate Divine model" end
	local catalystQuality=item.catalystQuality or (item.catalyst and 20) or 0
	if (jewellery and (item.quality or 0)>0) or catalystQuality>0 and (not jewellery or not item.catalyst or item.catalyst==3 or item.catalyst==9) then return nil,"Catalyst-scaled jewellery needs a separate Divine model" end
	if item.variantList or item.usesVariantGroups then return nil,"Items with saved variant selections need a separate Divine model" end
	uniqueSocketRestriction(item.title)
	local candidates={}
	for _,template in ipairs(uniquesByName[item.title] or {}) do
		local base=template:match("^%s*[^\r\n]+[\r\n]+([^\r\n]+)")
		if base==item.baseName then candidates[#candidates+1]=template end
	end
	if #candidates~=1 then return nil,"This unique's variant needs identification before Divine rolls" end
	local template=candidates[1];local levelAsModifier=false
	for _,line in ipairs(item.explicitModLines or {}) do if line.line=="Item Level: "..item.itemLevel then levelAsModifier=true end end
	if levelAsModifier then template=template.."\nItem Level: "..item.itemLevel
	else template=template:gsub("^(%s*[^\r\n]+[\r\n]+[^\r\n]+)","%1\nItem Level: "..item.itemLevel,1) end
	local parsed,reference=pcall(function() return new("Item"):Item("Rarity: UNIQUE\n"..template) end)
	if not parsed or not reference.base then return nil,"The bundled unique template could not be verified" end
	if reference.usesVariantGroups then return nil,"This unique's variant groups need a separate Divine model" end
	if catalystQuality>0 then
		if #(reference.modMagnitudeMods or {})>0 then return nil,"Modifier magnitude changes need a separate Divine model" end
		reference.catalyst=item.catalyst;reference.catalystQuality=catalystQuality
	end
	local selected,reason
	for variant=1,reference.variantList and #reference.variantList or 1 do
		if reference.variantList then reference.variant=variant end
		local plan,why=divinePlanForReference(raw,item,reference)
		if plan then
			if selected then return nil,"This item matches multiple unique variants" end
			selected=plan
		else reason=reason or why end
	end
	if selected then return selected end
	return nil,reason
end

function M.divineReason(raw) local _,reason=divinePlan(raw);return reason end
function M.divineOptions(raw)
	local plan,reason=divinePlan(raw);if not plan then return nil,reason end
	local result={};for _,row in ipairs(plan.rows) do for index,part in ipairs(row.ranges) do result[#result+1]={line=row.line,component=index,components=#row.ranges,min=row.profile and (row.profile.minima and row.profile.minima[index] or row.profile.min) or part.low,max=row.profile and (row.profile.maxima and row.profile.maxima[index] or row.profile.max) or part.high,current=row.current[index]} end end
	return result
end
function M.divine(raw,seed)
	local plan,reason=divinePlan(raw);assert(plan,reason)
	assert(type(seed)=="number" and seed==math.floor(seed) and seed>=1 and seed<=2147483646,"Invalid seed")
	local random=require("Modules.CalcTime").random(seed);local replacements={}
	for _,row in ipairs(plan.rows) do
		if #row.ranges==1 then
			local part=row.ranges[1];local value=part.low+math.floor(random()*(part.high-part.low+1));local range=(value-part.low)/(part.high-part.low)
			replacements[row.input]="{range:"..string.format("%.6f",range).."}"..(row.tags and "{tags:"..table.concat(row.tags,",").."}" or "")..row.line
		else
			local index=0;local rendered=row.line:gsub("([%+%-]?)%((%-?%d+)%-(%-?%d+)%)",function(sign,low,high)
				index=index+1;local part=row.ranges[index];local value=part.low+math.floor(random()*(part.high-part.low+1))
				local shown=sign=="-" and -value or value;local prefix=sign=="+" and shown>0 and "+" or ""
				return prefix..shown.."("..low.."-"..high..")"
			end)
			replacements[row.input]=(row.tags and "{tags:"..table.concat(row.tags,",").."}" or "")..rendered
		end
	end
	local changed=0
	local output=raw:gsub("[^\r\n]+",function(line)
		local plain=line:gsub("^%{range:[^}]+%}",""):gsub("^%{tags:[^}]+%}","");local replacement=replacements[plain]
		if replacement then changed=changed+1;return replacement end
		return line
	end)
	assert(changed==#plan.rows,"The unique modifier lines could not be updated safely")
	output=preserveArmourBaseline(raw,output,plan.item)
	local after=M.inspect(output);assert(after.title==plan.item.title and after.baseName==plan.item.baseName and not after.corrupted,"Unique item did not round-trip after Divine crafting")
	local catalystModeled=plan.item.catalyst and (plan.item.catalystQuality or 20)>0 or nil
	return {itemText=output,components={divine=1},catalystModeled=catalystModeled}
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

function M.omenCount(item)
	local level=item.itemLevel
	return math.min(require("Modules.CraftingSimulator").socketLimit({item=item}),level >= 50 and 6 or level >= 35 and 5 or level >= 25 and 4 or level >= 2 and 3 or 2)
end
function M.omenReason(raw)
	local ok,item=pcall(M.inspect,raw);if not ok then return tostring(item) end
	if item.corrupted then return "Ordinary currency cannot modify a corrupted item" end
	local count=M.omenCount(item)
	if #item.sockets>=count then return "The item already has its maximum natural socket count" end
	return M.socketCountReason(raw,count)
end

function M.socketCount(raw,count,method)
	assert(method==nil or method=="omen_jeweller","Unsupported unique socket-count method")
	if method=="omen_jeweller" then
		local reason=M.omenReason(raw);assert(not reason,reason)
		assert(count==M.omenCount(M.inspect(raw)),"The Jeweller Omen must use the maximum natural socket count")
	end
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
	local components=require("Modules.CraftingSimulator").components(method=="omen_jeweller" and {method=method} or {method="socket_bench",count=count},{sockets=before.sockets,corrupted=before.corrupted})
	return {itemText=output,components=components}
end

-- Reuse the ordinary socket-colour model while retaining the unique item text.
-- These are sampled outcomes; a single result is not a probability estimate.
function M.colourReason(raw,method)
	local ok,item=pcall(M.inspect,raw);if not ok then return tostring(item) end
	if method~="chromatic" and method~="tainted_chromatic" and method~="omen_trichromatism" then return "Unsupported unique socket colour method" end
	if item.type=="Flask" or item.type=="Tincture" then return "Flasks and tinctures have no sockets" end
	if (not not item.corrupted)~=(method=="tainted_chromatic") then return item.corrupted and "Use tainted currency on corrupted items" or "Tainted currency requires a corrupted item" end
	local immutable=M.socketModificationReason(raw,item);if immutable then return immutable end
	local line,lines=raw:match("\nSockets: ([^\r\n]*)"),0
	for _ in ("\n"..raw):gmatch("\nSockets:") do lines=lines+1 end
	if lines~=1 or not line or not line:match("^[RGBWA][RGBWA%-%s]*$") then return "A single explicit socket layout is required" end
	if #item.sockets<1 or #item.sockets>6 then return "Colour crafting needs one to six existing sockets" end
	for _,socket in ipairs(item.sockets) do if socket.color=="A" then return "Abyssal sockets need a separate socket model" end end
	if #line:gsub("[^RGBW]","")~=#item.sockets then return "The socket layout could not be verified" end
	if method=="omen_trichromatism" and #item.sockets<3 then return "At least three sockets are required for the RGB guarantee" end
end
-- Check whether any modeled colour outcome can satisfy a direct target.
function M.colourTargetReason(item,method,target,linked,forceRoll)
	if type(target)~="string" or target=="" or not target:match("^[RGBW]+$") then return "Enter one or more socket colours using R, G, B or W." end
	local sockets=item.sockets or {}
	if #target>#sockets then return "The target has more colours than the item has sockets." end
	local groups={};local best=0
	if linked then
		local byGroup={};for _,socket in ipairs(sockets) do local group=byGroup[socket.group];if not group then group={};byGroup[socket.group]=group;groups[#groups+1]=group end;group[#group+1]=socket;best=math.max(best,#group) end
		if #target>best then return "No existing linked group has enough sockets for this target." end
	else groups={sockets} end
	-- A goal already met needs no currency, even if a new roll cannot recreate it.
	local needed={};for colour in target:gmatch(".") do needed[colour]=(needed[colour] or 0)+1 end
	if not forceRoll then for _,group in ipairs(groups) do local available={};for _,socket in ipairs(group) do available[socket.color]=(available[socket.color] or 0)+1 end
		local matched=true;for colour,count in pairs(needed) do if (available[colour] or 0)<count then matched=false;break end end
		if matched then return nil,true end
	end end
	if method=="omen_trichromatism" then
		local missing=0;for _,colour in ipairs({"R","G","B"}) do if not target:find(colour,1,true) then missing=missing+1 end end
		if #sockets-#target<missing then return "This target conflicts with the Omen's guaranteed red, green and blue sockets." end
	elseif (method=="chromatic" or method=="tainted_chromatic") and #target==#sockets and not target:find("[RGB]") then
		return "This target conflicts with the currency's guaranteed non-white socket."
	end
end
function M.colour(raw,method,seed)
	local reason=M.colourReason(raw,method);assert(not reason,reason)
	assert(type(seed)=="number" and seed==math.floor(seed) and seed>=1 and seed<=2147483646,"Invalid seed")
	local before=M.inspect(raw)
	local sim=require("Modules.CraftingSimulator")
	local state={affixes={},sockets=copyTable(before.sockets),quality=before.quality,corrupted=before.corrupted}
	local result=sim.action({item=before,byId={}},state,{method=method},require("Modules.CalcTime").random(seed))
	local parts={};for i,socket in ipairs(result.sockets) do
		if i>1 then parts[#parts+1]=socket.group==result.sockets[i-1].group and "-" or " " end
		parts[#parts+1]=socket.color
	end
	local output,n=raw:gsub("(\nSockets: )([^\r\n]*)",function(prefix) return prefix..table.concat(parts) end)
	assert(n==1,"The socket layout could not be updated")
	local after=M.inspect(output)
	assert(after.title==before.title and after.baseName==before.baseName and #after.sockets==#before.sockets and after.corrupted==before.corrupted,"Unique item did not round-trip after colour crafting")
	for i,socket in ipairs(after.sockets) do assert(i==1 or (socket.group==after.sockets[i-1].group)==(before.sockets[i].group==before.sockets[i-1].group),"Socket links changed unexpectedly") end
	return {itemText=output,components=sim.components({method=method})}
end

-- Socket-link rolls use the same estimated model as ordinary equipment.
function M.randomLinkReason(raw,method)
	local ok,item=pcall(M.inspect,raw);if not ok then return tostring(item) end
	if method~="fusing" and method~="tainted_fusing" then return "Unsupported unique link method" end
	if item.type=="Flask" or item.type=="Tincture" then return "Flasks and tinctures have no sockets" end
	if (not not item.corrupted)~=(method=="tainted_fusing") then return item.corrupted and "Use tainted currency on corrupted items" or "Tainted currency requires a corrupted item" end
	local immutable=M.socketModificationReason(raw,item);if immutable then return immutable end
	local line,lines=raw:match("\nSockets: ([^\r\n]*)"),0
	for _ in ("\n"..raw):gmatch("\nSockets:") do lines=lines+1 end
	if lines~=1 or not line or not line:match("^[RGBWA][RGBWA%-%s]*$") then return "A single explicit socket layout is required" end
	if #item.sockets<2 or #item.sockets>6 then return "Link crafting needs two to six existing sockets" end
	local linked=true
	for _,socket in ipairs(item.sockets) do
		if socket.color=="A" then return "Abyssal sockets need a separate socket model" end
		linked=linked and socket.group==item.sockets[1].group
	end
	if #line:gsub("[^RGBW]","")~=#item.sockets then return "The socket layout could not be verified" end
	if linked and (method=="tainted_fusing" or #item.sockets>=5) then return "The item is already fully linked" end
end
function M.randomLinks(raw,method,seed)
	local reason=M.randomLinkReason(raw,method);assert(not reason,reason)
	assert(type(seed)=="number" and seed==math.floor(seed) and seed>=1 and seed<=2147483646,"Invalid seed")
	local before=M.inspect(raw);local sim=require("Modules.CraftingSimulator")
	local state={affixes={},sockets=copyTable(before.sockets),quality=before.quality,corrupted=before.corrupted}
	local result=sim.action({item=before,byId={}},state,{method=method},require("Modules.CalcTime").random(seed))
	local parts={};for i,socket in ipairs(result.sockets) do
		if i>1 then parts[#parts+1]=socket.group==result.sockets[i-1].group and "-" or " " end
		parts[#parts+1]=socket.color
	end
	local output,n=raw:gsub("(\nSockets: )([^\r\n]*)",function(prefix) return prefix..table.concat(parts) end)
	assert(n==1,"The socket layout could not be updated")
	local after=M.inspect(output)
	assert(after.title==before.title and after.baseName==before.baseName and #after.sockets==#before.sockets and after.corrupted==before.corrupted,"Unique item did not round-trip after link crafting")
	for i,socket in ipairs(after.sockets) do assert(socket.color==before.sockets[i].color,"Socket colours changed unexpectedly") end
	return {itemText=output,components=sim.components({method=method})}
end

-- Sample socket-count currency while retaining imported unique properties.
-- The underlying currency probabilities are estimates, as for ordinary items.
function M.randomSocketReason(raw,method)
	if method~="jeweller" and method~="tainted_jeweller" then return "Unsupported unique socket-count method" end
	local ok,item=pcall(M.inspect,raw);if not ok then return tostring(item) end
	if (not not item.corrupted)~=(method=="tainted_jeweller") then return item.corrupted and "Use tainted currency on corrupted items" or "Tainted currency requires a corrupted item" end
	-- Validate the existing layout and unique restrictions independently of
	-- whether the chosen bench target is already present.
	local reason=M.socketCountReason(raw,2)
	if reason and reason~="The item already has this many sockets" then return reason end
	local sim=require("Modules.CraftingSimulator")
	local state={affixes={},sockets=copyTable(item.sockets),quality=item.quality,corrupted=item.corrupted}
	return sim.methodReason({item=item,byId={}},state,method)
end
function M.randomSockets(raw,method,seed)
	local reason=M.randomSocketReason(raw,method);assert(not reason,reason)
	assert(type(seed)=="number" and seed==math.floor(seed) and seed>=1 and seed<=2147483646,"Invalid seed")
	local before=M.inspect(raw);local sim=require("Modules.CraftingSimulator")
	local state={affixes={},sockets=copyTable(before.sockets),quality=before.quality,corrupted=before.corrupted}
	local result=sim.action({item=before,byId={}},state,{method=method},require("Modules.CalcTime").random(seed))
	local parts={};for i,socket in ipairs(result.sockets) do
		if i>1 then parts[#parts+1]=socket.group==result.sockets[i-1].group and "-" or " " end
		parts[#parts+1]=socket.color
	end
	local output,n=raw:gsub("(\nSockets: )([^\r\n]*)",function(prefix) return prefix..table.concat(parts) end)
	assert(n==1,"The socket layout could not be updated")
	local after=M.inspect(output)
	assert(after.title==before.title and after.baseName==before.baseName and #after.sockets==#result.sockets and after.corrupted==before.corrupted,"Unique item did not round-trip after socket crafting")
	for i,socket in ipairs(after.sockets) do
		assert(socket.color==result.sockets[i].color and (i==1 or (socket.group==after.sockets[i-1].group)==(result.sockets[i].group==result.sockets[i-1].group)),"Socket layout changed unexpectedly")
	end
	return {itemText=output,components=sim.components({method=method})}
end

-- Summarise only a complete recorded preview; loading an item does not record
-- the actions that made it, and older snapshots may have unknown actions.
function M.previewResources(startingItem,history,actions,currentItem,historyTruncated)
	if historyTruncated then return nil,"Earlier preview actions are unavailable after recovery." end
	if type(history)~="table" or type(actions)~="table" or #history~=#actions then return nil,"The preview action history is incomplete." end
	if #actions==0 then
		if currentItem and currentItem~=startingItem then return nil,"The current preview has no recorded path from the starting item." end
		return {}
	end
	if history[1]~=startingItem then return nil,"The preview does not start from this project's starting item." end
	local sim=require("Modules.CraftingSimulator");local prices=require("Modules.CraftingPrices");local totals={};local firstItem
	local allowed={quality=true,tainted_quality=true,divine=true,instilling=true,enkindling=true,beast_max_links=true,omen_connections=true,omen_jeweller=true,fusing=true,tainted_fusing=true,jeweller=true,tainted_jeweller=true,chromatic=true,tainted_chromatic=true,omen_trichromatism=true,socket_white_bench=true,socket_bench=true}
	for index,encoded in ipairs(actions) do
		if type(encoded)~="string" or type(history[index])~="string" then return nil,"The preview contains an unknown action." end
		local count=tonumber(encoded:match("^socket_count_bench:([2-6])$"));local enchant=encoded:match("^bench_flask_enchant:(.+)$")
		if not count and not enchant and not allowed[encoded] then return nil,"Loaded or older previews do not record every action." end
		local ok,item=pcall(M.inspect,history[index]);if not ok then return nil,"A recorded preview item could not be read." end;firstItem=firstItem or item
		local action=count and {method="socket_bench",count=count} or enchant and {method="bench_flask_enchant",enchantId=enchant} or {method=encoded}
		if encoded=="socket_bench" then action.count=#item.sockets;action.linked=true end
		local model={item=item};local valid,components=pcall(sim.components,action,{sockets=item.sockets,corrupted=item.corrupted},model)
		if not valid then return nil,"The resources for a recorded action could not be determined." end
		for key,amount in pairs(components) do local canonical=prices.key(key,model);totals[canonical]=(totals[canonical] or 0)+amount end
	end
	local result={};for key,amount in pairs(totals) do local name=prices.describe(key,{item=firstItem});result[#result+1]={key=key,name=name,amount=amount} end
	table.sort(result,function(a,b) if a.name~=b.name then return a.name<b.name end;return a.key<b.key end)
	return result
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
	local definitions={{method="divine",label="Divine Orb",reason=M.divineReason(raw),sampled=true,components={divine=1}}}
	local flask=require("Modules.CraftingFlaskEnchants")
	if flask.eligible({item=item}) then
		for _,method in ipairs({"instilling","enkindling"}) do definitions[#definitions+1]={method=method,label=sim.labels[method],reason=M.flaskEnchantReason(raw,method),sampled=true,components=sim.components({method=method})} end
	end
	if info.qualitySupported then table.insert(definitions,1,{method="quality",label="Ordinary quality",reason=qualityReason,components={[info.resourceKey]=1}}) end
	if item.base.armour or data.weaponTypeInfo[item.type] then definitions[#definitions+1]={method="tainted_quality",label="Tainted quality: "..info.resource,reason=M.taintedQualityReason(raw),sampled=true,components=sim.components({method="tainted_quality"},nil,{item=item})} end
	if sim.socketLimit({item=item})>0 then
		local socketDefinitions={
		{method="beast_max_links",label="Bestiary: maximum links",reason=linkReason,components={beast_black_morrigan=1,beast_craicic_sand_spitter=1}},
		{method="fusing",label="Orb of Fusing",reason=M.randomLinkReason(raw,"fusing"),sampled=true,components=sim.components({method="fusing"})},
		{method="tainted_fusing",label="Tainted Orb of Fusing",reason=M.randomLinkReason(raw,"tainted_fusing"),sampled=true,components=sim.components({method="tainted_fusing"})},
		{method="jeweller",label="Jeweller's Orb",reason=M.randomSocketReason(raw,"jeweller"),sampled=true,components=sim.components({method="jeweller"})},
		{method="tainted_jeweller",label="Tainted Jeweller's Orb",reason=M.randomSocketReason(raw,"tainted_jeweller"),sampled=true,components=sim.components({method="tainted_jeweller"})},
		{method="chromatic",label="Chromatic Orb",reason=M.colourReason(raw,"chromatic"),sampled=true,components=sim.components({method="chromatic"})},
		{method="tainted_chromatic",label="Tainted Chromatic Orb",reason=M.colourReason(raw,"tainted_chromatic"),sampled=true,components=sim.components({method="tainted_chromatic"})},
		{method="omen_trichromatism",label="Omen of Trichromatism + Chromatic Orb",reason=M.colourReason(raw,"omen_trichromatism"),sampled=true,components=sim.components({method="omen_trichromatism"})},
		{method="omen_jeweller",label="Omen of the Jeweller + Jeweller's Orb",reason=M.omenReason(raw),components=sim.components({method="omen_jeweller"})},
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
	if item.type=="Ring" or item.type=="Amulet" or item.type=="Belt" then
		result.catalystGuides={}
		for id,name in ipairs(M.catalysts) do if #result.catalystGuides<limit and (name.." catalyst"):lower():find(query,1,true) then
			local ok,step=pcall(catalystGuideForItem,raw,item,info,id,20)
			result.catalystGuides[#result.catalystGuides+1]={catalyst=id,name=name.." Catalyst",targetQuality=20,guideOnly=true,warning=(id==3 or id==9) and "Prefix/suffix catalysts may not affect fixed unique modifiers." or "Check whether the catalyst affects the intended modifiers; effects are not previewed.",available=ok,guideStep=ok and step or nil,unavailableReason=not ok and tostring(step):gsub("^.-:%d+: ","") or nil}
		end end
		result.limitations[#result.limitations+1]="Catalyst guides count currency only; modifier changes and item previews are not modeled."
	end
	if item.catalyst and info.quality>0 and not M.divineReason(raw) then result.limitations[#result.limitations+1]="Catalyst eligibility and scaling use bundled modifier tags and PoB rounding; tag completeness and current game behavior are unverified." end
	local seen={}
	for _,entry in ipairs(definitions) do
		if not seen[entry.method] then result.methods[#result.methods+1]=entry.method;seen[entry.method]=true end
		if #result.uniqueActions<limit and (entry.method.." "..entry.label):lower():find(query,1,true) then
			local request=entry.request or (entry.method=="socket_bench" and {method=entry.method,count=#item.sockets,linked=true} or {method=entry.method})
			local action={method=entry.method,label=entry.label,action=request,priceKey=entry.method=="socket_bench" and require("Modules.CraftingSimulator").priceKey(request) or entry.method,available=entry.reason==nil,unavailableReason=entry.reason,deterministic=not entry.sampled,components=entry.components}
			if entry.method=="divine" and action.available then action.modifierTargets=M.divineOptions(raw) end
			local guideMethod,guideCount=entry.guideMethod or entry.method,entry.guideCount or 1
			action.guideStep={action=M.guideAction(guideMethod,guideCount,info.resource,item.corrupted,#item.sockets),uniqueCraft={method=guideMethod,count=guideCount}}
			result.uniqueActions[#result.uniqueActions+1]=action
			if entry.method~="quality" and entry.method~="tainted_quality" and entry.method~="divine" and entry.method~="instilling" and entry.method~="enkindling" then result.socketCrafts[#result.socketCrafts+1]=copyTable(action) end
		end
	end
	result.flaskEnchants=flask.eligible({item=item}) and flask.list(query,limit) or {}
	if flask.eligible({item=item}) then
		result.flaskEnchant=flask.identify(item)
		local reason=M.flaskEnchantReason(raw,"bench_flask_enchant")
		for _,entry in ipairs(result.flaskEnchants) do if entry.benchAction then entry.benchAvailable=not reason;entry.benchUnavailableReason=reason end end
	end
	return result
end

function M.matches(raw,requirements)
	local item,info=M.inspect(raw);requirements=requirements or {}
	local supported={uniqueName=true,uniqueModifier=true,minQuality=true,corrupted=true,twiceCorrupted=true,mirrored=true,sockets=true,exactSockets=true,links=true,socketColours=true,linkedColours=true,minAbyssSockets=true,nativeStats=true,flaskEnchant=true,flaskEnchantMin=true}
	for key in pairs(requirements) do assert(supported[key],"This unique item property is not supported: "..tostring(key)) end
	if requirements.uniqueName and item.title~=requirements.uniqueName then return false end
	if requirements.flaskEnchant or requirements.flaskEnchantMin then
		local flask=require("Modules.CraftingFlaskEnchants");assert(flask.eligible({item=item}),"Flask enchantment goals require a utility flask")
		local enchant=flask.identify(item);assert(enchant or #item.enchantModLines==0,"The existing flask enchantment could not be identified")
		if requirements.flaskEnchant and (not enchant or enchant.id~=requirements.flaskEnchant) then return false end
		if requirements.flaskEnchantMin and (not enchant or not enchant.roll or enchant.roll<requirements.flaskEnchantMin) then return false end
	end
	if requirements.minQuality then assert(info.qualitySupported,"Jewellery catalyst-quality goals need a separate model");if info.quality<requirements.minQuality then return false end end
	if requirements.corrupted~=nil and (not not item.corrupted)~=requirements.corrupted then return false end
	if requirements.twiceCorrupted~=nil and (not not item.twiceCorrupted)~=requirements.twiceCorrupted then return false end
	if requirements.mirrored~=nil and (not not item.mirrored)~=requirements.mirrored then return false end
	if requirements.uniqueModifier then
		local goal=requirements.uniqueModifier;assert(type(goal)=="table" and type(goal.line)=="string" and (goal.minValue~=nil)~=(goal.maxValue~=nil),"Invalid unique modifier target")
		local value=goal.minValue or goal.maxValue;assert(type(value)=="number","Invalid unique modifier target")
		local options,reason=M.divineOptions(raw);assert(options,reason);local selected
		local component=goal.component or 1;assert(type(component)=="number" and component==math.floor(component) and component>=1 and component<=6,"Invalid unique modifier component")
		for _,option in ipairs(options) do if option.line==goal.line and option.component==component then selected=option;break end end
		assert(selected,"The selected unique modifier is not available on this item")
		assert(value==math.floor(value) and value>=selected.min and value<=selected.max,"The unique modifier target is outside its roll range")
		if goal.minValue and selected.current<value or goal.maxValue and selected.current>value then return false end
	end
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
