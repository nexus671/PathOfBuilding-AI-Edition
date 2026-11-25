local parser = require("Modules.LootFilterParser")
local M = {}
local rarities = {Normal=true,Magic=true,Rare=true,Unique=true}

function M.validateSamples(samples)
	assert(type(samples)=="table" and #samples>=1 and #samples<=500,"Provide 1 to 500 protected sample items")
	local count = 0
	for index, item in pairs(samples) do
		count=count+1
		assert(type(index)=="number" and index==math.floor(index) and index>=1 and index<=#samples,
			"Provide a complete list of protected samples")
		assert(type(item)=="table" and type(item.BaseType)=="string" and #item.BaseType<=200
			and item.BaseType:match("%S") and not item.BaseType:find("[%c]") and rarities[item.Rarity],
			"Each protected sample needs an exact BaseType and a known Rarity")
		local action, marker = item.ExpectedAction,item.ExpectedMarker
		assert(action==nil or action=="Show" or action=="Hide","Choose Show or Hide for the expected action")
		if marker~=nil then
			assert(action~="Hide" and type(marker)=="string" and #marker<=40 and not marker:find("[%c]"),
				"Set a valid expected minimap icon on a visible sample")
			local mock = parser.parse("Show\n    MinimapIcon "..marker.."\n")
			assert(#mock.diagnostics==0 and mock.rules[1].styles.MinimapIcon
				and table.concat(mock.rules[1].styles.MinimapIcon," ")==marker, "Enter a valid minimap icon such as 0 Red Star")
		end
	end
	assert(count==#samples,"Provide a complete list of protected samples")
	return samples
end

local scrollMarker = "# CUSTOM: Hide Wisdom and Portal Scrolls"
local fracturedMarker = "# CUSTOM: Show fractured magic equipment"
local fatedMarker = "# CUSTOM: Show Fated equipment on rank A and B bases"
local tierMarker = "# CUSTOM: Highlight item tier 5 rare equipment on rank A and B bases"
local rareFallbackMarker = "# CUSTOM: Suppress other unidentified rare bases before broad tiered gear rules"
local identifiedMarker = "# CUSTOM: Identified corrupted rare modifier rules copied from the filter"
local hideCorruptedMarker = "# CUSTOM: Hide other identified corrupted rare equipment"
local personalMarkers = {
	"# CUSTOM: Always show Cord Belts",
	"# CUSTOM: Show six-linked items before equipment hides",
	fracturedMarker,
	fatedMarker,
	scrollMarker,
}
local ruleStarts = {Show=true,Hide=true,Minimal=true,Import=true}

function M.hasPersonalMarkerSet(raw)
	local comments = {}
	for line in raw:gmatch("[^\r\n]+") do
		local comment = line:match("^%s*(# CUSTOM: .-)%s*$")
		if comment then comments[comment] = true end
	end
	for _, marker in ipairs(personalMarkers) do if not comments[marker] then return false end end
	return true
end

local function personalRuleText(raw)
	local rules = {}
	for line in raw:gmatch("[^\r\n]+") do
		local text = line:match("^%s*(.-)%s*$")
		if text ~= "" and (text:sub(1,1) ~= "#" or text:find("# CUSTOM:",1,true)==1) then
			rules[#rules+1] = line
		end
	end
	return table.concat(rules,"\n")
end

local function afterMarkedRule(raw, marker, action)
	local marked, inRule = false, false
	for offset, line in raw:gmatch("()([^\n]*)\n?") do
		local text = line:match("^%s*(.-)%s*$")
		local keyword = text:match("^[^%s#]+")
		if text==marker then
			marked = true
		elseif marked and ruleStarts[keyword] then
			if inRule then return offset end
			if keyword~=action then return nil end
			inRule = true
		end
	end
	return inRule and #raw+1 or nil
end

local function originalPrefixPreserved(previous, candidate)
	if not previous:find(scrollMarker,1,true) then return true end
	local oldStop = afterMarkedRule(previous,scrollMarker,"Hide")
	local newStop = afterMarkedRule(candidate,scrollMarker,"Hide")
	if not oldStop or not newStop then return false end
	local market = require("Modules.LootFilterEconomy")
	local oldStart, oldEnd = market.sectionBounds(previous)
	if oldStart and oldEnd then
		local newStart, newEnd = market.sectionBounds(candidate)
		if not newStart or not newEnd then return false end
		oldStop, newStop = math.max(oldStart,oldStop), math.max(newStart,newStop)
	end
	return personalRuleText(previous:sub(1,oldStop-1))==personalRuleText(candidate:sub(1,newStop-1))
end

local function sample(item)
	local base = require("Modules.LootFilterLibrary").baseProperties(item.BaseType,item.Rarity)
	assert(base.Width and base.Height, "Protected sample is missing base dimensions: "..item.BaseType)
	-- A level 85 item can drop from a rare monster in an area-level 83 map.
	-- Unique drop levels are not established by the base alone.
	item.AreaLevel, item.ItemLevel, item.StackSize = item.AreaLevel or 83, item.ItemLevel or 85, item.StackSize or 1
	item.Width, item.Height, item.DropLevel, item.HasInfluence = base.Width, base.Height, base.DropLevel, {"None"}
	-- Non-unique jewellery has no random base defence. For the ordinary
	-- plate, exercise the lowest roll; unique defence remains unknown.
	if item.Rarity ~= "Unique" then item.BaseDefencePercentile = item.BaseType == "Royal Plate" and 0 or 100 end
	item.HasExplicitMod, item.HasEnchantment = {}, {}
	item.SocketGroup = item.SocketGroup or ""
	item.EnchantmentPassiveNode = ""
	for key in pairs(parser.numeric) do if item[key] == nil and key ~= "DropLevel" and key ~= "BaseDefencePercentile" then item[key] = 0 end end
	for key in pairs(parser.booleans) do if item[key] == nil then item[key] = false end end
	return item
end

function M.samples()
	local output = {}
	local function add(item, marker)
		output[#output+1] = {item=sample(item), marker=marker}
	end
	for _, corrupted in ipairs({true,false}) do
		for _, identified in ipairs({true,false}) do
			for _, rarity in ipairs({"Normal","Magic","Rare","Unique"}) do
				add({BaseType="Cord Belt",Class="Belts",Rarity=rarity,Corrupted=corrupted,Identified=identified},"0 Purple Star")
				add({BaseType="Royal Plate",Class="Body Armours",Rarity=rarity,LinkedSockets=6,Sockets=6,SocketGroup="WWWWWW",
					Corrupted=corrupted,Identified=identified},"0 Red Diamond")
				if rarity ~= "Unique" then
					add({BaseType="Agate Amulet",Class="Amulets",Rarity=rarity,Fated=true,Corrupted=corrupted,Identified=identified},"0 Purple Star")
				end
			end
			add({BaseType="Iron Ring",Class="Rings",Rarity="Magic",FracturedItem=true,Corrupted=corrupted,Identified=identified},"0 Yellow Diamond")
		end
	end
	return output
end

local function declaredValues(raw, marker, keyword)
	local _, markerEnd = raw:find(marker,1,true)
	if not markerEnd then return {} end
	local block, started = {}
	for line in raw:sub(markerEnd+1):gmatch("[^\n]+") do
		local statement = line:match("^%s*([^%s#]+)")
		if ruleStarts[statement] then
			if started then break end
			assert(statement=="Show", "Expected a Show block after "..marker)
			started = true
		end
		if started then block[#block+1] = line end
	end
	local rule = parser.parse(table.concat(block,"\n")).rules[1]
	for _, condition in ipairs(rule and rule.conditions or {}) do
		if condition.keyword==keyword and condition.operator=="==" then return condition.values end
	end
	error("Use an exact "..keyword.." list after "..marker)
end

local function markedRules(raw, firstMarker, lastMarker, lastAction)
	local first = raw:find(firstMarker,1,true)
	local stop = afterMarkedRule(raw,lastMarker,lastAction)
	if first and stop and first<stop then return personalRuleText(raw:sub(first,stop-1)) end
end

function M.personalRulesPreserved(previous, candidate)
	if not originalPrefixPreserved(previous,candidate) then return false end
	local tiered = previous:find(tierMarker,1,true)
	local identified = previous:find(identifiedMarker,1,true)
	if not tiered and not identified then return true end
	if tiered then
		local rules = markedRules(previous,tierMarker,tierMarker,"Show")
		if not rules or rules~=markedRules(candidate,tierMarker,tierMarker,"Show") then return false end
		if previous:find(rareFallbackMarker,1,true) then
			local fallback = markedRules(previous,rareFallbackMarker,rareFallbackMarker,"Hide")
			if not fallback or fallback~=markedRules(candidate,rareFallbackMarker,rareFallbackMarker,"Hide") then return false end
		end
	end
	if identified then
		local rules = markedRules(previous,identifiedMarker,hideCorruptedMarker,"Hide")
		if not rules or rules~=markedRules(candidate,identifiedMarker,hideCorruptedMarker,"Hide") then return false end
	end
	local before, after = parser.parse(previous), parser.parse(candidate)
	local encode = require("Modules.PlanningData").encodeExact
	local function sameDecision(item)
		local old, new = parser.simulate(before,item), parser.simulate(after,item)
		return old.action~="Unknown" and old.action==new.action
			and (old.action~="Show" or encode(old.styles)==encode(new.styles))
	end
	if tiered then
		local library = require("Modules.LootFilterLibrary")
		local seen = {}
		for _, name in ipairs(declaredValues(previous,tierMarker,"BaseType")) do
			if not seen[name] then
				seen[name] = true
				local class = assert(library.baseClass(name), "Protected rare base has no known class: "..name)
				local item = sample({BaseType=name,Class=class,Rarity="Rare",UnidentifiedItemTier=5})
				if not sameDecision(item) then return false end
				item.UnidentifiedItemTier = 4
				if not sameDecision(item) then return false end
			end
		end
		if not sameDecision(sample({BaseType="Plate Vest",Class="Body Armours",Rarity="Rare",UnidentifiedItemTier=5})) then return false end
	end
	if identified then
		local item = sample({BaseType="Vaal Axe",Class="Two Hand Axes",Rarity="Rare",Identified=true,Corrupted=true,CorruptedMods=1})
		if not sameDecision(item) then return false end
		item.HasExplicitMod = {"Merciless","Flaring","of Celebration"}
		if not sameDecision(item) then return false end
		item.HasExplicitMod, item.CorruptedMods = {}, 2
		if not sameDecision(item) then return false end
	end
	return true
end

function M.hasRareTierPolicy(raw)
	return raw and raw:find(tierMarker,1,true)~=nil
end

function M.rareTierExceptions(raw, parsed, checkpoint)
	assert(M.hasRareTierPolicy(raw), "This filter has no marked Tier 5 Rank A/B policy")
	local ranked, classes, rules = {}, {}, {}
	for _, name in ipairs(declaredValues(raw,tierMarker,"BaseType")) do ranked[name] = true end
	for _, class in ipairs(declaredValues(raw,tierMarker,"Class")) do classes[class] = true end
	for _, rule in ipairs(parsed.rules) do rules[rule.line] = rule end
	local library = require("Modules.LootFilterLibrary")
	local result = {rows={},shown=0,hidden=0,unknown=0,missing=0}
	local names = {}
	for name in pairs(data.itemBases) do
		if not ranked[name] then names[#names+1] = name end
	end
	table.sort(names)
	for _, name in ipairs(names) do
		if checkpoint then checkpoint() end
		local class = library.baseClass(name)
		if classes[class] then
			local base = library.baseProperties(name,"Rare")
			if not base.Width or not base.Height or not base.DropLevel then
				result.missing = result.missing+1
			elseif base.DropLevel<=86 then
				local item = sample({BaseType=name,Class=class,Rarity="Rare",ItemLevel=86,UnidentifiedItemTier=5})
				item.BaseDefencePercentile = library.baseDefencePercentile(name,class,"Rare")
				local decision = parser.simulate(parsed,item)
				if decision.action=="Hide" then
					result.hidden = result.hidden+1
				else
					local key = decision.action=="Show" and "shown" or "unknown"
					result[key] = result[key]+1
					result.rows[#result.rows+1] = {item=item,decision=decision,rule=rules[decision.line]}
				end
			end
		end
	end
	return result
end

function M.checkPersonalSamples(raw, check)
	local library = require("Modules.LootFilterLibrary")
	local seen = {}
	for _, name in ipairs(declaredValues(raw,fatedMarker,"BaseType")) do
		if not seen[name] then
			seen[name] = true
			local class = assert(library.baseClass(name),"Protected Fated base has no known class: "..name)
			for _, rarity in ipairs({"Normal","Magic","Rare"}) do
				check(sample({BaseType=name,Class=class,Rarity=rarity,Fated=true}),"0 Purple Star")
			end
		end
	end
	seen = {}
	for _, class in ipairs(declaredValues(raw,fracturedMarker,"Class")) do
		if not seen[class] then
			seen[class] = true
			local name = assert(library.baseExampleForClass(class),"Protected fractured class has no known sample: "..class)
			check(sample({BaseType=name,Class=class,Rarity="Magic",FracturedItem=true}),"0 Yellow Diamond")
		end
	end
	if raw:find(scrollMarker,1,true) then
		for _, name in ipairs({"Scroll of Wisdom","Portal Scroll"}) do
			for _, area in ipairs({1,68,83}) do
				for _, size in ipairs({1,40}) do
					check(sample({BaseType=name,Class="Stackable Currency",Rarity="Normal",AreaLevel=area,StackSize=size}),nil,"Hide")
				end
			end
		end
	end
end

function M.explicitlyShown(result)
	return result.action == "Show" and #result.matches > 0
end

function M.marker(result)
	local icon = result.styles.MinimapIcon
	return icon and table.concat(icon," ")
end

return M
