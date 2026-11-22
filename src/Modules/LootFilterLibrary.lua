-- Searchable base-filter catalogue and deterministic example drops. No drop-rate model.
-- cspell:ignore RGBW WRGB scurr
local filters=require("Modules.LootFilters")
local parser=require("Modules.LootFilterParser")
local sha1=require("sha1")
-- cspell:ignore RRGGBB RRRRGB
local M={categories={"All items","Build targets","Campaign","Currency","Special currency","Equipment","Unique items","Flasks","Tinctures","Jewels","Divination cards","Maps & fragments","Gems","Recipes","League items","Other"}}
local baseMetadata,baseClasses
local noSockets={ ["Stackable Currency"]=true,Gold=true,Contracts=true,Blueprints=true,["Expedition Logbooks"]=true,["Map Fragments"]=true,Maps=true,["Divination Cards"]=true,["Skill Gems"]=true,["Support Gems"]=true }
function M.hasNoSockets(class) return noSockets[class]==true end
local equipment={Helmet=true,["Body Armour"]=true,Gloves=true,Boots=true,Shield=true,Quiver=true,Amulet=true,Ring=true,Belt=true}
-- These item classes are not wearable equipment. This is separate from socket
-- inference: knowing a defence percentile does not establish socket properties.
local nonEquipmentDefenceZero={Incubators=true,Breachstones=true,["Heist Targets"]=true,["Quest Items"]=true,
	["Metamorph Samples"]=true,["Embers of the Allflame"]=true,["Incursion Items"]=true,
	["Sanctum Research"]=true,["Atlas Upgrade Items"]=true,["Vault Keys"]=true,["Labyrinth Items"]=true}
-- Unknown bases, unique equipment and random defence rolls remain unresolved.
function M.baseDefencePercentile(name,class,rarity)
	-- Resonators have fossil sockets, but are currency rather than equipment.
	if noSockets[class] or nonEquipmentDefenceZero[class] or class=="Delve Socketable Currency" or class=="Delve Stackable Socketable Currency" then return 0 end
	local native=data and data.itemBases and data.itemBases[name]
	if native and (equipment[native.type] or data.weaponTypeInfo[native.type]) and rarity~="Unique" then
		for _,kind in ipairs({"Armour","Evasion","EnergyShield","Ward"}) do
			local armour=native.armour or {};local min,max=armour[kind.."BaseMin"],armour[kind.."BaseMax"]
			if min and max and min~=max then return nil,true end
		end
		return 100
	end
end
function M.baseProperties(name,rarity)
	if not baseMetadata then
		local file=assert(io.open("Data/LootFilters/base-metadata.json","rb"));local raw=file:read("*a");file:close()
		baseMetadata=assert(require("dkjson").decode(raw)).bases
	end
	local base=baseMetadata[name] or {}
	-- A missing or ambiguous client record is unknown, rather than a generic 1.
	-- A unique item's drop level can differ from its base, and the scene does
	-- not identify the unique. Keep it unknown rather than using the base level.
	return {DropLevel=rarity~="Unique" and base.DropLevel or nil,Width=base.Width,Height=base.Height}
end
local function applyBaseProperties(item,preserveSockets,preserveDefence)
	local base=M.baseProperties(item.BaseType,item.Rarity)
	item.DropLevel=base.DropLevel;item.Width=base.Width;item.Height=base.Height
	local native=data and data.itemBases and data.itemBases[item.BaseType]
	local percentile,random=M.baseDefencePercentile(item.BaseType,item.Class,item.Rarity)
	if not (random and preserveDefence) then item.BaseDefencePercentile=percentile end
	local limit=native and (native.socketLimit or 0)
	local coherent=preserveSockets and type(item.Sockets)=="number" and (native and item.Sockets<=limit or not native and noSockets[item.Class] and item.Sockets==0)
	if not coherent and (native and limit>0 or not native and not noSockets[item.Class] or preserveSockets) then
		item.Sockets=nil;item.SocketGroup=nil;item.SocketColours=nil;item.LinkedSockets=nil
	end
end
function M.category(rule)
	if rule.origin then return "Build targets" end
	local text=(rule.text or ""):lower()
	if text:find("divination cards",1,true) or text:find("%$type%-%>cards") then return "Divination cards" end
	if text:find("tinctures",1,true) then return "Tinctures" end
	if text:find("flasks",1,true) then return "Flasks" end
	if text:find("jewels",1,true) then return "Jewels" end
	if text:find("%$type%-%>recipes") or text:find("%$type%-%>recipe") then return "Recipes" end
	if text:find("%$type%-%>currency") and (text:find("fossil",1,true) or text:find("essence",1,true) or text:find("resonator",1,true) or text:find("catalyst",1,true)) then return "Special currency" end
	if text:find("%$type%-%>uniques") or text:find("rarity == unique",1,true) or text:find("rarity unique",1,true) then return "Unique items" end
	-- Gold is a distinct item class, but belongs alongside currencies in the
	-- catalogue. Match exact conditions so Gold Rings are not reclassified.
	if text:find("gold",1,true) then
		local parsed=parser.parse(rule.text);local block=parsed.rules[1]
		for _,condition in ipairs(block and block.conditions or {}) do
			if (condition.keyword=="BaseType" or condition.keyword=="Class") and condition.operator=="==" and #condition.values==1 and condition.values[1]:lower()=="gold" then return "Currency" end
		end
	end
	if text:find("%$type%-%>currency") or text:find("stackable currency",1,true) then return "Currency" end
	if text:find("%$type%-%>maps") or text:find("%$type%-%>fragments") or text:find("%$type%-%>scarab") or text:find('"maps"',1,true) or text:find("map fragments",1,true) then return "Maps & fragments" end
	if text:find("%$type%-%>gems") or text:find("skill gems",1,true) or text:find("support gems",1,true) then return "Gems" end
	if text:find("contract",1,true) or text:find("blueprint",1,true) or text:find("expedition logbook",1,true) then
		local block=parser.parse(rule.text).rules[1];local classes={contracts=true,blueprints=true,["expedition logbooks"]=true}
		for _,condition in ipairs(block and block.conditions or {}) do
			if condition.operator=="==" and condition.keyword=="Class" and #condition.values>0 then
				local all=true;for _,value in ipairs(condition.values) do if not classes[value:lower()] then all=false;break end end
				if all then return "League items" end
			elseif condition.operator=="==" and condition.keyword=="BaseType" and #condition.values==1 and condition.values[1]:lower()=="expedition logbook" then return "League items" end
		end
	end
	if text:find("viscera",1,true) or text:find("enshrouded",1,true) or text:find("%$type%-%>league") then return "League items" end
	if text:find("rarity",1,true) or text:find("%$type%-%>rares") or text:find("%$type%-%>uniques") or text:find("sockets",1,true) then return "Equipment" end
	return "Other"
end
local classExamples={["Body Armours"]="Vaal Regalia",Helmets="Iron Hat",Gloves="Wool Gloves",Boots="Wool Shoes",Wands="Driftwood Wand",Shields="Splintered Tower Shield",Rings="Iron Ring",Amulets="Amber Amulet",Belts="Leather Belt",Jewels="Cobalt Jewel",Maps="Strand Map",["Map Fragments"]="Breach Thread",["Skill Gems"]="Arcane Link",["Support Gems"]="Added Fire Damage Support",["Stackable Currency"]="Chaos Orb",Gold="Gold",Contracts="Contract: Bunker",Blueprints="Blueprint: Bunker",["Expedition Logbooks"]="Expedition Logbook",Tinctures="Prismatic Tincture"}
-- Filter class names from the pinned RePoE item_classes.json (ae6d85a5).
-- Native base types use different names for several weapon families.
local nativeClasses={Helmet="Helmets",["Body Armour"]="Body Armours",Gloves="Gloves",Boots="Boots",Shield="Shields",Ring="Rings",Amulet="Amulets",Belt="Belts",Quiver="Quivers",Bow="Bows",Claw="Claws",Dagger="Daggers",["Rune Dagger"]="Rune Daggers",Wand="Wands",Sceptre="Sceptres",Staff="Staves",Warstaff="Warstaves",["Thrusting Sword"]="Thrusting One Hand Swords",["One Handed Sword"]="One Hand Swords",["One Handed Axe"]="One Hand Axes",["One Handed Mace"]="One Hand Maces",["Two Handed Sword"]="Two Hand Swords",["Two Handed Axe"]="Two Hand Axes",["Two Handed Mace"]="Two Hand Maces",Tincture="Tinctures"}
local function baseClass(name)
	if not baseClasses then
		local file=assert(io.open("Data/LootFilters/base-classes.json","rb"));local raw=file:read("*a");file:close()
		baseClasses=assert(require("dkjson").decode(raw))
	end
	-- Some names, such as resonators, exist in more than one class. A named
	-- base cannot resolve those cases; retain a separately supplied class.
	if baseClasses.ambiguous[name] then return nil end
	if baseClasses.classes[name] then return baseClasses.classes[name] end
	local base=data and data.itemBases and data.itemBases[name]
	if base then
		local kind=base.subType=="Thrusting" and "Thrusting Sword" or (base.subType=="Rune Dagger" or base.subType=="Warstaff") and base.subType or base.type
		if nativeClasses[kind] then return nativeClasses[kind] end
	end
	for class,example in pairs(classExamples) do if example==name then return class end end
end
M.baseClass=baseClass
function M.sample(rule,block)
	local item={BaseType="Chaos Orb",Class="Stackable Currency",Rarity="Normal",ItemLevel=86,AreaLevel=83,DropLevel=1,Quality=0,StackSize=1,Sockets=0,SocketGroup="",LinkedSockets=0,Width=1,Height=1,UnidentifiedItemTier=0,HasInfluence={"None"},HasExplicitMod={},HasEnchantment={},EnchantmentPassiveNode=""}
	for key in pairs(parser.booleans) do if key~="AlwaysShow" then item[key]=false end end
	local hasBase,hasClass,hasRarity,hasIdentified,hasDefence,hasTier,modifier=false,false,false,false,false,false,nil
	local baseCondition,dropConditions,classCondition=nil,{},nil
	local socketConditions={}
	if rule then block=block or parser.parse(rule.text).rules[1];if block then for _,c in ipairs(block.conditions) do
		local value=c.values[1]
		if c.keyword=="Sockets" or c.keyword=="SocketGroup" or c.keyword=="LinkedSockets" then socketConditions[#socketConditions+1]=c end
		if c.keyword=="BaseType" then hasBase=true;baseCondition=c elseif c.keyword=="Class" then hasClass=true;classCondition=c end
		if c.keyword=="DropLevel" then dropConditions[#dropConditions+1]=c end
		if c.keyword=="Rarity" then hasRarity=true elseif c.keyword=="Identified" then hasIdentified=true end
		if c.keyword=="BaseDefencePercentile" then hasDefence=true end
		if c.keyword=="UnidentifiedItemTier" then hasTier=true end
		if c.keyword=="HasExplicitMod" and (c.operator=="=" or c.operator=="==" or c.operator==">=" or c.operator==">") then modifier=c end
		if parser.numeric[c.keyword] then local n=tonumber(value);item[c.keyword]=n and (c.operator==">" and n+1 or c.operator=="<" and n-1 or n) or value
		elseif c.keyword=="Rarity" then item.Rarity=value
		elseif c.keyword=="TransfiguredGem" then if value=="True" then item[c.keyword]=true elseif value=="False" then item[c.keyword]=false else item[c.keyword]=value end
		elseif parser.booleans[c.keyword] then item[c.keyword]=value=="True"
		elseif c.keyword=="HasInfluence" then item[c.keyword]=copyTable(c.values)
		elseif c.keyword=="BaseType" or c.keyword=="Class" or c.keyword=="SocketGroup" then item[c.keyword]=value end
	end end end
	-- Construct a coherent example for a single ordinary socket requirement.
	-- More complicated combinations are left to the simulator instead of guessing.
	if #socketConditions==1 then
		local c=socketConditions[1];local pattern=c.values[1] or ""
		local number=tonumber(pattern:match("^%d+"));local colors=pattern:match("[RGBW]+$") or ""
		if (c.operator=="=" or c.operator=="==" or c.operator==">=") and pattern:match("^%d*[RGBW]*$") then
			local count=number or #colors
			local padding="W"
			if c.operator=="==" and count>#colors then
				padding=nil;for color in ("WRGB"):gmatch(".") do if not colors:find(color,1,true) then padding=color;break end end
			end
			if count>=#colors and count<=6 and padding then
				colors=colors..string.rep(padding,count-#colors)
				item.Sockets=count;item.SocketColours=colors;item.SocketGroup=colors;item.LinkedSockets=count
			end
		end
	end
	if modifier then
		local count=not (modifier.quoted and modifier.quoted[1]) and tonumber(modifier.values[1]);local start=count and 2 or 1
		if parser.countExactMarker(modifier,start) then start=start+1 end
		local needed=count and (modifier.operator==">" and count+1 or count) or 1
		item.HasExplicitMod={};for i=start,math.min(#modifier.values,start+math.min(needed,6)-1) do item.HasExplicitMod[#item.HasExplicitMod+1]=modifier.values[i] end
		if not hasIdentified then item.Identified=true end
		if not hasRarity and not hasBase and not hasClass then item.Rarity="Rare" end
	end
	if not hasBase then
		if hasClass then if item.TransfiguredGem and item.Class=="Skill Gems" then item.BaseType=nil else item.BaseType=classExamples[item.Class] or item.Class end
		elseif item.TransfiguredGem then item.BaseType=nil;item.Class="Skill Gems"
		elseif #socketConditions>0 or item.LinkedSockets>=5 or type(item.SocketGroup)=="string" and item.SocketGroup~="" then item.BaseType="Vaal Regalia";item.Class="Body Armours"
		elseif item.Rarity=="Unique" then item.BaseType="Leather Belt";item.Class="Belts"
		elseif item.Rarity=="Rare" or item.Rarity=="Magic" then item.BaseType="Iron Hat";item.Class="Helmets" end
	else
		-- Family policies list many exact bases. Pick one that actually meets
		-- the requested base drop-level band instead of always using the first.
		if baseCondition and baseCondition.operator=="==" and #dropConditions>0 and item.Rarity~="Unique" then
			local chosen
			for _,name in ipairs(baseCondition.values) do
				local class=baseClass(name);local level=M.baseProperties(name,item.Rarity).DropLevel;local area=tonumber(item.AreaLevel)
				local valid=level~=nil and (not area or level<=area) and (not classCondition or class and parser.condition(classCondition,{Class=class})==true)
				local native=data and data.itemBases and data.itemBases[name]
				if valid and #socketConditions==1 and native and type(item.Sockets)=="number" and item.Sockets>(native.socketLimit or 0) then valid=false end
				if valid then for _,condition in ipairs(dropConditions) do if parser.condition(condition,{DropLevel=level})~=true then valid=false;break end end end
				if valid then chosen=name;break end
			end
			item.BaseType=chosen
		end
		item.Class=baseClass(item.BaseType) or (hasClass and item.Class or nil)
	end
	-- A generated unidentified magic or rare item can have any drop tier. A
	-- rule-specific example retains an explicitly requested hypothetical tier.
	if not hasTier and item.Identified==false and (item.Rarity=="Magic" or item.Rarity=="Rare") then item.UnidentifiedItemTier=nil end
	applyBaseProperties(item,#socketConditions==1,hasDefence)
	return item
end
-- Show every parsed condition so similarly named rules can be distinguished.
-- Preserve quoted values: they are significant for filter matching.
function M.conditionSummaries(block)
	local lines={}
	for _,condition in ipairs(block.conditions or {}) do
		local values={}
		for i,value in ipairs(condition.values) do
			values[#values+1]=condition.quoted and condition.quoted[i] and '"'..value..'"' or value
		end
		local operator=condition.operator.." "
		if (condition.keyword=="HasExplicitMod" or condition.keyword=="HasEnchantment") and not (condition.quoted and condition.quoted[1]) and tonumber(condition.values[1]) then operator=condition.operator end
		lines[#lines+1]=condition.keyword:gsub("(%l)(%u)","%1 %2").." "..operator..table.concat(values," ")
	end
	return lines
end
function M.catalog(profile)
	local raw=filters.migratedBase(profile);local entries={};local ids={}
	for i,block in ipairs(parser.parse(raw).rules) do
		local text=table.concat(block.rawLines,"\n");local example
		local tier=block.rawLines[1]:match("%$tier%-%>([%w_-]+)") or "Base rule"
		local title;local chosen
		for _,key in ipairs({"BaseType","Class","HasExplicitMod","HasEnchantment","SocketGroup","LinkedSockets","Sockets","Rarity"}) do
			for _,condition in ipairs(block.conditions) do if condition.keyword==key then chosen=condition;break end end
			if chosen then break end
		end
		chosen=chosen or block.conditions[1]
		if chosen then
			local values=chosen.values;local first=values[1] or "?";local more=#values>1 and " +"..(#values-1) or ""
			if chosen.keyword=="BaseType" and (chosen.operator=="=" or chosen.operator=="==") then title=first..more
			else
				local count=(chosen.keyword=="HasExplicitMod" or chosen.keyword=="HasEnchantment") and not (chosen.quoted and chosen.quoted[1]) and tonumber(first)
				local name=chosen.keyword:gsub("(%l)(%u)","%1 %2")
				if count and values[2] then title=name.." "..chosen.operator..first.." "..values[2]..(#values>2 and " +"..(#values-2) or "")
				else title=name.." "..chosen.operator.." "..first..more end
			end
		else title=block.continue and "Style remaining items" or block.action.." remaining items" end
		tier=tier:match("^t%d+$") and "Tier "..tier:sub(2) or "Preset rule"
		title=title:gsub("%-%>"," / "):gsub("_"," ")
		local key="base-"..sha1(text):sub(1,20);ids[key]=(ids[key] or 0)+1
		local rule={id=key..(ids[key]>1 and "-"..ids[key] or ""),title=title,text=text,enabled=true}
		local entry={rule=rule,category=M.category(rule),tier=tier,sample=example,block=block,base=true}
		-- Most views need names and conditions only. Materialise example properties on demand.
		setmetatable(entry,{__index=function(self,key) if key=="sample" then local value=M.sample(self.rule,self.block);rawset(self,key,value);return value end end});entries[#entries+1]=entry
	end
	return entries
end
function M.personal(profile)
	local entries={};for _,rule in ipairs(profile.rules) do entries[#entries+1]={rule=rule,category=M.category(rule),tier=rule.origin and "Build target" or "Personal rule",sample=M.sample(rule),block=parser.parse(rule.text).rules[1]} end;return entries
end
function M.campaign(profile)
	local entries={};for _,rule in ipairs(require("Modules.LootFilterCampaign").rules(profile.campaign,profile.theme,profile.mode)) do entries[#entries+1]={rule=rule,category="Campaign",tier="Pickup policy",sample=M.sample(rule),block=parser.parse(rule.text).rules[1],base=true} end;return entries
end
function M.entries(profile,source,category,query)
	local result={};for _,entry in ipairs(source or {}) do
		if (category==nil or category=="All items" or entry.category==category) and (entry.rule.title.." "..entry.rule.text):lower():find((query or ""):lower(),1,true) then result[#result+1]=entry end
	end;return result
end
-- Keep untouched commands in their original order, including repeated actions.
function M.appendStyleLines(lines,block,changes)
	local continues={}
	for _,line in ipairs(block.rawLines) do
		local tokens=parser.tokens(line);local key=tokens[1]
		if parser.actions[key] and changes[key]==nil then lines[#lines+1]=line
		elseif key=="Continue" then continues[#continues+1]=line end
	end
	local keys={};for key,value in pairs(changes) do if value~=false then keys[#keys+1]=key end end;table.sort(keys)
	for _,key in ipairs(keys) do local value=changes[key];local output=key:match("^CustomAlertSound") and (filters.quote(value[1])..(#value>1 and " "..table.concat(value," ",2) or "")) or table.concat(value," ");lines[#lines+1]="    "..key.." "..output end
	for _,line in ipairs(continues) do lines[#lines+1]=line end
end
function M.appearance(rule,changes)
	local block=assert(parser.parse(rule.text).rules[1]);local lines={block.action}
	for _,condition in ipairs(block.conditions) do
		local values={};for i,value in ipairs(condition.values) do values[#values+1]=not parser.countExactMarker(condition,i) and ((condition.quoted and condition.quoted[i]) or (parser.strings[condition.keyword] and not tonumber(value)) or value:find("%s")) and filters.quote(value) or value end
		local count=(condition.keyword=="HasExplicitMod" or condition.keyword=="HasEnchantment") and not (condition.quoted and condition.quoted[1]) and tonumber(condition.values[1])
		lines[#lines+1]="    "..condition.keyword.." "..condition.operator..(count and "" or " ")..table.concat(values," ")
	end
	M.appendStyleLines(lines,block,changes)
	local nextRule=copyTable(rule);nextRule.text=table.concat(lines,"\n");nextRule.origin=nil;return nextRule
end
local examples={
	{"Divine Orb","Stackable Currency"},{"Chaos Orb","Stackable Currency"},{"Orb of Alchemy","Stackable Currency"},{"Orb of Alteration","Stackable Currency"},
	{"Frayed Thread","Stackable Currency"},{"Breach Thread","Map Fragments"},{"Enshrouded Quiver","Enshrouded Items"},{"Coven Queen's Crown","Viscera"},
	{"Iron Hat","Helmets","Rare"},{"Vaal Regalia","Body Armours","Rare"},{"Leather Belt","Belts","Unique"},{"Iron Ring","Rings","Magic"},
	{"Arcane Link","Skill Gems"},{"Orb of Fusing","Stackable Currency"},{"Scroll of Wisdom","Stackable Currency"},{"Chromatic Orb","Stackable Currency"},
	{"Originator's Exalted Orb","Stackable Currency"},{"Primordial Exalted Orb","Stackable Currency"},
}
-- Exact examples from GGG's published 3.30 item-filter changes. These are
-- deliberately varied test items, not an estimate of encounter drops.
local covensExamples={
	{"Frayed Thread","Stackable Currency"},{"Breach Thread","Map Fragments"},{"Expedition Thread","Map Fragments"},
	{"Abyss Thread","Map Fragments"},{"Ritual Thread","Map Fragments"},{"Ultimatum Thread","Map Fragments"},
	{"Legion Thread","Map Fragments"},{"Blight Thread","Map Fragments"},{"Bestiary Thread","Map Fragments"},
	{"Betrayal Thread","Map Fragments"},{"Incursion Thread","Map Fragments"},{"Cursed Poppet","Map Fragments"},
	{"Enshrouded Quiver","Enshrouded Items"},{"Scorched Arm","Viscera"},{"Severed Rhoa Head","Viscera"},
	{"Afarud Enshrouding Crystal","Stackable Currency"},
}
-- Base names and classes are present in the pinned 3.30.0.1.4 client export.
-- They are examples for testing rules, not recommendations or drop odds.
local cardExamples={
	{"The Apothecary","Divination Cards"},{"The Doctor","Divination Cards"},{"The Nurse","Divination Cards"},
	{"The Patient","Divination Cards"},{"The Gambler","Divination Cards"},{"The Fortunate","Divination Cards"},
	{"The Scholar","Divination Cards"},{"The Hermit","Divination Cards"},{"Seven Years Bad Luck","Divination Cards"},
	{"The Dragon's Heart","Divination Cards"},{"The Void","Divination Cards"},{"House of Mirrors","Divination Cards"},
}
local essenceExamples={
	{"Deafening Essence of Greed","Stackable Currency"},{"Deafening Essence of Contempt","Stackable Currency"},
	{"Deafening Essence of Scorn","Stackable Currency"},{"Deafening Essence of Anger","Stackable Currency"},
	{"Screaming Essence of Greed","Stackable Currency"},{"Shrieking Essence of Greed","Stackable Currency"},
	{"Essence of Horror","Stackable Currency"},{"Essence of Delirium","Stackable Currency"},
	{"Essence of Insanity","Stackable Currency"},{"Essence of Hysteria","Stackable Currency"},
	{"Essence of Trickery","Stackable Currency"},{"Remnant of Corruption","Stackable Currency"},
}
-- Released 3.30 client base names and filter classes. These are independent
-- comparison examples, not a prediction of what an encounter will drop.
local mapExamples={
	{"Map (Tier 1)","Maps","Normal"},{"Map (Tier 5)","Maps","Magic"},
	{"Map (Tier 10)","Maps","Rare"},{"Map (Tier 14)","Maps","Rare"},
	{"Map (Tier 16)","Maps","Rare"},{"Frayed Thread","Stackable Currency"},
	{"Breach Thread","Map Fragments"},{"Expedition Thread","Map Fragments"},
	{"Abyss Thread","Map Fragments"},{"Ritual Thread","Map Fragments"},
	{"Timeless Maraketh Emblem","Map Fragments"},{"Chaos Orb","Stackable Currency"},
	{"Nightmare Map","Maps","Rare",{MapTier=17}},
	{"Shaper Guardian Map","Maps","Rare"},{"Valdo Map","Maps","Rare"},
	{"Map (Tier 16)","Maps","Rare",{BlightedMap=true,UberBlightedMap=false}},
	{"Map (Tier 16)","Maps","Rare",{UberBlightedMap=true}},
}
local flaskExamples={
	{"Sacred Life Flask","Life Flasks"},{"Divine Life Flask","Life Flasks"},
	{"Divine Mana Flask","Mana Flasks"},{"Granite Flask","Utility Flasks"},
	{"Quicksilver Flask","Utility Flasks"},{"Amethyst Flask","Utility Flasks"},
	{"Silver Flask","Utility Flasks"},{"Bismuth Flask","Utility Flasks"},
	{"Prismatic Tincture","Tinctures"},{"Oakbranch Tincture","Tinctures"},
	{"Rosethorn Tincture","Tinctures"},{"Instilling Orb","Stackable Currency"},
}
-- Released base names and filter classes from the pinned client and RePoE
-- class export. These examples do not model encounter or item probabilities.
local craftingExamples={
	{"Hollow Fossil","Stackable Currency"},{"Pristine Fossil","Stackable Currency"},
	{"Fractured Fossil","Stackable Currency"},{"Faceted Fossil","Stackable Currency"},
	{"Sanctified Fossil","Stackable Currency"},{"Dense Fossil","Stackable Currency"},
	{"Primitive Chaotic Resonator","Delve Stackable Socketable Currency"},{"Powerful Chaotic Resonator","Delve Stackable Socketable Currency"},
	{"Exceptional Eldritch Ember","Stackable Currency"},{"Exceptional Eldritch Ichor","Stackable Currency"},
	{"Wild Crystallised Lifeforce","Stackable Currency"},{"Sacred Crystallised Lifeforce","Stackable Currency"},
}
-- Oil tiers and map flags are explicit comparison samples, not drop rates.
local blightExamples={
	{"Clear Oil","Stackable Currency"},{"Sepia Oil","Stackable Currency"},{"Amber Oil","Stackable Currency"},
	{"Verdant Oil","Stackable Currency"},{"Teal Oil","Stackable Currency"},{"Azure Oil","Stackable Currency"},
	{"Violet Oil","Stackable Currency"},{"Crimson Oil","Stackable Currency"},{"Black Oil","Stackable Currency"},
	{"Opalescent Oil","Stackable Currency"},{"Silver Oil","Stackable Currency"},{"Golden Oil","Stackable Currency"},
	{"Tainted Oil","Stackable Currency"},{"Blight Thread","Map Fragments"},
	{"Map (Tier 16)","Maps","Rare",{MapTier=16,BlightedMap=true,UberBlightedMap=false}},
	{"Map (Tier 16)","Maps","Rare",{MapTier=16,UberBlightedMap=true}},
}
local heistExpeditionExamples={
	{"Blueprint: Underbelly","Blueprints"},{"Blueprint: Repository","Blueprints"},
	{"Contract: Underbelly","Contracts"},{"Contract: Repository","Contracts"},
	{"Expedition Logbook","Expedition Logbooks","Rare"},{"Rogue's Marker","Stackable Currency"},
	{"Burial Medallion","Stackable Currency"},{"Astragali","Stackable Currency"},
	{"Exotic Coinage","Stackable Currency"},{"Scrap Metal","Stackable Currency"},
	{"Lesser Broken Circle Artifact","Stackable Currency"},{"Lesser Black Scythe Artifact","Stackable Currency"},
}
-- Comparison samples from the pinned base/class catalogue; presence in the
-- catalogue does not establish current drop availability or encounter odds.
local breachExamples={
	{"Splinter of Xoph","Stackable Currency"},{"Splinter of Tul","Stackable Currency"},
	{"Splinter of Esh","Stackable Currency"},{"Splinter of Uul-Netol","Stackable Currency"},
	{"Splinter of Chayula","Stackable Currency"},{"Chayula's Flawless Breachstone","Breachstones"},
	{"Breach Ring","Rings","Rare"},{"Breach Thread","Map Fragments"},
	{"Frayed Thread","Stackable Currency"},
}
-- 3.30 Beyond and Incursion examples do not imply drop rates.
local beyondExamples={
 {"Tainted Chromatic Orb","Stackable Currency"},{"Tainted Jeweller's Orb","Stackable Currency"},
 {"Tainted Orb of Fusing","Stackable Currency"},{"Tainted Chaos Orb","Stackable Currency"},
 {"Tainted Exalted Orb","Stackable Currency"},{"Tainted Divine Teardrop","Stackable Currency"},
 {"Tainted Mythic Orb","Stackable Currency"},{"Tainted Armourer's Scrap","Stackable Currency"},
 {"Tainted Blacksmith's Whetstone","Stackable Currency"},
}
local incursionExamples={
 {"Royal Visage","Stackable Currency"},{"Soul Core of Finesse","Stackable Currency"},
 {"Soul Core of Instability","Stackable Currency"},{"Soul Core of Intellect","Stackable Currency"},
 {"Soul Core of Might","Stackable Currency"},{"Incursion Thread","Map Fragments"},
 {"Frayed Thread","Stackable Currency"},
}
local legionExamples={
	{"Timeless Karui Splinter","Stackable Currency"},{"Timeless Maraketh Splinter","Stackable Currency"},
	{"Timeless Eternal Empire Splinter","Stackable Currency"},{"Timeless Templar Splinter","Stackable Currency"},
	{"Timeless Vaal Splinter","Stackable Currency"},{"Timeless Karui Emblem","Map Fragments"},
	{"Timeless Maraketh Emblem","Map Fragments"},{"Timeless Eternal Emblem","Map Fragments"},
	{"Timeless Templar Emblem","Map Fragments"},{"Timeless Vaal Emblem","Map Fragments"},
	{"Diviner's Incubator","Incubators"},{"Ornate Incubator","Incubators"},{"Legion Thread","Map Fragments"},
}
-- Named encounter comparisons use pinned base classes, not drop distributions.
local deliriumExamples={
 {"Simulacrum Splinter","Stackable Currency"},{"Simulacrum","Map Fragments"},
 {"Fine Delirium Orb","Stackable Currency"},{"Threaded Delirium Orb","Stackable Currency"},{"Diviner's Delirium Orb","Stackable Currency"},
 {"Fossilised Delirium Orb","Stackable Currency"},{"Blighted Delirium Orb","Stackable Currency"},
 {"Refracting Fog","Stackable Currency"},
}
local harvestExamples={
 {"Wild Crystallised Lifeforce","Stackable Currency"},{"Vivid Crystallised Lifeforce","Stackable Currency"},
 {"Primal Crystallised Lifeforce","Stackable Currency"},{"Sacred Crystallised Lifeforce","Stackable Currency"},
 {"Sacred Blossom","Map Fragments"},
}
local abyssExamples={
 {"Murderous Eye Jewel","Abyss Jewels","Rare"},{"Searching Eye Jewel","Abyss Jewels","Rare"},
 {"Hypnotic Eye Jewel","Abyss Jewels","Rare"},{"Ghastly Eye Jewel","Abyss Jewels","Rare"},
 {"Stygian Vise","Belts","Rare"},{"Abyss Thread","Map Fragments"},
 {"Frayed Thread","Stackable Currency"},
}
local ultimatumExamples={
 {"Inscribed Ultimatum","Misc Map Items"},{"Fertile Catalyst","Stackable Currency"},
 {"Prismatic Catalyst","Stackable Currency"},{"Intrinsic Catalyst","Stackable Currency"},
 {"Turbulent Catalyst","Stackable Currency"},{"Noxious Catalyst","Stackable Currency"},
 {"Accelerating Catalyst","Stackable Currency"},{"Ultimatum Thread","Map Fragments"},
 {"Frayed Thread","Stackable Currency"},
}
local ritualExamples={
 {"Ritual Vessel","Stackable Currency"},{"Omen of Fortune","Stackable Currency"},
 {"Omen of Connections","Stackable Currency"},{"Omen of the Jeweller","Stackable Currency"},
 {"Omen of Trichromatism","Stackable Currency"},{"Omen of Amelioration","Stackable Currency"},
 {"Ritual Thread","Map Fragments"},{"Frayed Thread","Stackable Currency"},
}
-- Catalogue examples for testing filters; these do not imply current drops.
local sanctumExamples={
 {"Forbidden Tome","Sanctum Research"},{"Candlestick Relic","Relics"},{"Censer Relic","Relics"},
 {"Coffer Relic","Relics"},{"Papyrus Relic","Relics"},{"Processional Relic","Relics"},
 {"Tome Relic","Relics"},{"Urn Relic","Relics"},{"Lycia's Invocation of Acrobatics","Stackable Currency"},
 {"Lycia's Invocation of Divine Shield","Stackable Currency"},{"Lycia's Invocation of Eldritch Battery","Stackable Currency"},
}
local bossExamples={
 {"Crescent Splinter","Stackable Currency"},{"The Maven's Writ","Map Fragments"},
 {"Fragment of the Hydra","Map Fragments"},{"Fragment of the Phoenix","Map Fragments"},
 {"Fragment of the Minotaur","Map Fragments"},{"Fragment of the Chimera","Map Fragments"},
 {"Fragment of Purification","Map Fragments"},{"Fragment of Constriction","Map Fragments"},
 {"Fragment of Eradication","Map Fragments"},{"Fragment of Enslavement","Map Fragments"},
 {"Orb of Conflict","Stackable Currency"},
}
-- Deliberate test items for the campaign recipe policies, not a simulated set
-- of actual drops. Socket layouts are explicit so their preview is decisive.
local vendorExamples={
	{"Iron Hat","Helmets","Normal",{Sockets=3,SocketColours="RGB",SocketGroup="R-G-B",LinkedSockets=3}},
	{"Vaal Regalia","Body Armours","Normal",{Sockets=6,SocketColours="RRGGBB",SocketGroup="R R G G B B",LinkedSockets=1}},
	{"Glorious Plate","Body Armours","Normal",{Sockets=6,SocketColours="RRRRGB",SocketGroup="R-R-R-R-G-B",LinkedSockets=6}},
	{"Arcane Link","Skill Gems","Normal",{Quality=20}},
	{"Iron Ring","Rings","Rare"},{"Amber Amulet","Amulets","Rare"},{"Leather Belt","Belts","Rare"},
	{"Wool Gloves","Gloves","Rare"},{"Wool Shoes","Boots","Rare"},{"Driftwood Wand","Wands","Rare"},
	{"Driftwood Wand","Wands","Normal",{Quality=12}},{"Iron Hat","Helmets","Normal",{Quality=12}},
	{"Divine Life Flask","Life Flasks","Normal",{Quality=20}},{"Granite Flask","Utility Flasks","Normal",{Quality=12}},
	{"Prismatic Tincture","Tinctures","Normal",{Quality=12}},
	-- Same-base rarity comparison for the Chance Orb vendor recipe. These are
	-- synthetic examples, not a claim that the four items drop together.
	{"Jade Amulet","Amulets","Normal",{Identified=true}},
	{"Jade Amulet","Amulets","Magic"},
	{"Jade Amulet","Amulets","Rare"},
	{"Jade Amulet","Amulets","Unique"},
}
-- Use exact names from NeverSink's pinned high-emphasis currency blocks. This
-- is a snapshot of filter styling, not a price feed or a drop distribution.
local presetHighlights
local function highlights()
	if presetHighlights then return presetHighlights end
	local found,rows={},{}
	local raw=filters.base(filters.profile("highlight-snapshot","Highlight snapshot"))
	for _,block in ipairs(parser.parse(raw).rules) do
		local heading=block.rawLines[1] or ""
		if block.action=="Show" and heading:find("$type->currency",1,true) and heading:find("!apex_scurr",1,true) then
			for _,condition in ipairs(block.conditions) do if condition.keyword=="BaseType" and condition.operator=="==" then
				for _,name in ipairs(condition.values) do local class=baseClass(name)
					if class and not found[name] then found[name]=true;rows[#rows+1]={name,class} end
				end
			end end
		end
	end
	presetHighlights=rows;return rows
end
function M.scene(profile,build,kind,seed,area,itemLevel,targetRules)
	local list={}
	if kind=="Map tiers" then
		-- Explicit synthetic tiers allow direct comparison of MapTier rules.
		for tier=1,17 do
			local item=M.sample();item.BaseType=tier==17 and "Nightmare Map" or "Map (Tier "..tier..")"
			item.Class="Maps";item.Rarity=tier==17 and "Rare" or "Normal";item.MapTier=tier;item.UnidentifiedItemTier=nil
			item.AreaLevel=area or 83;item.ItemLevel=itemLevel or 86;applyBaseProperties(item);list[#list+1]=item
		end
		return list
	end
	if kind=="Fated gear" or kind=="Foulborn gear" then
		-- Paired examples differ only in the selected property; they do not predict drops.
		local property=kind=="Fated gear" and "Fated" or "Foulborn"
		for _,base in ipairs({{"Iron Hat","Helmets"},{"Titan Greaves","Boots"},{"Titanium Spirit Shield","Shields"},{"Imperial Bow","Bows"},{"Ruby Ring","Rings"}}) do
			for _,enabled in ipairs({true,false}) do
				local item=M.sample();item.BaseType=base[1];item.Class=base[2];item.Rarity="Rare";item.Identified=false;item[property]=enabled
				item.UnidentifiedItemTier=profile and profile.mode=="Ruthless" and 0 or 4
				item.AreaLevel=area or 83;item.ItemLevel=itemLevel or 86;applyBaseProperties(item)
				item.MemoryStrands=0
				if base[2]~="Rings" then item.Sockets=1;item.SocketColours="R";item.SocketGroup="R";item.LinkedSockets=1 end
				list[#list+1]=item
			end
		end
		return list
	end
	if kind=="Tiered gear" then
		-- Identical base and rarity make the explicit tier the useful difference.
		-- These are comparison samples, not a model of drop probabilities.
		local tiers=profile and profile.mode=="Ruthless" and {0} or {0,2,3,4,5}
		for _,tier in ipairs(tiers) do
			local item=M.sample();item.BaseType="Iron Hat";item.Class="Helmets";item.Rarity="Rare";item.Identified=false;item.UnidentifiedItemTier=tier
			item.AreaLevel=area or 83;item.ItemLevel=itemLevel or 86;applyBaseProperties(item);list[#list+1]=item
		end
		return list
	end
	if kind=="Build targets" then
		for _,rule in ipairs(targetRules or filters.generate(build,profile)) do if rule.origin then
			local item=M.sample(rule);item.AreaLevel=area or 83;item.ItemLevel=itemLevel or 86;list[#list+1]=item
		end end
		return list
	end
	local source=kind=="Preset highlights" and highlights() or ({["Covens & Threads"]=covensExamples,["Divination cards"]=cardExamples,["Essences"]=essenceExamples,["Maps & threads"]=mapExamples,["Flasks & tinctures"]=flaskExamples,["Crafting materials"]=craftingExamples,["Heist & Expedition"]=heistExpeditionExamples,["Blight & oils"]=blightExamples,["Breach"]=breachExamples,["Beyond"]=beyondExamples,["Incursion"]=incursionExamples,["Legion"]=legionExamples,["Delirium"]=deliriumExamples,["Harvest"]=harvestExamples,["Abyss"]=abyssExamples,["Ultimatum"]=ultimatumExamples,["Ritual"]=ritualExamples,["Sanctum"]=sanctumExamples,["Pinnacle bosses"]=bossExamples,["Vendor recipes"]=vendorExamples})[kind] or examples
	for i=1,#source do local example=source[(i+(seed or 0)-1)%#source+1];local item=M.sample();item.BaseType=example[1];item.Class=example[2];item.Rarity=example[3] or "Normal";item.AreaLevel=area or 83
		if item.Identified==false and (item.Rarity=="Magic" or item.Rarity=="Rare") then item.UnidentifiedItemTier=profile and profile.mode=="Ruthless" and 0 or nil end
		applyBaseProperties(item)
		for key,value in pairs(example[4] or {}) do item[key]=value end
		if kind=="Vendor recipes" and item.Rarity=="Unique" then item.UnidentifiedItemTier=nil end
		-- Current ordinary map bases explicitly name their tier.
		if kind=="Maps & threads" and item.Class=="Maps" then item.MapTier=item.MapTier or tonumber(item.BaseType:match("^Map %(Tier (%d+)%)$")) end
		if kind~="Currency" or item.Class=="Stackable Currency" then list[#list+1]=item end
	end
	for _,item in ipairs(list) do item.AreaLevel=area or 83;item.ItemLevel=itemLevel or 86 end
	return list
end
return M
