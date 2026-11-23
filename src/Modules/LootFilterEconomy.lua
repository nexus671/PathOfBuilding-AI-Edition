local json = require("dkjson")
local parser = require("Modules.LootFilterParser")
local maps = require("Modules.LootFilterMapMarket")
local M = {}
M.categories = {"Currency", "Oil", "Omen", "Essence", "Thread", "Fragment", "Resonator", "Artifact"}
M.endpoint = "https://poe.ninja/poe1/api/economy/"
M.managedClasses = {"Stackable Currency", "Map Fragments", "Misc Map Items", "Delve Stackable Socketable Currency", "Divination Cards", "Maps"}
M.managedAreas = {{label="All areas", val="all"}, {label="Campaign", val="campaign"}, {label="Maps", val="maps"}}
local classes = {}
for _, class in ipairs(M.managedClasses) do
	if class ~= "Divination Cards" and class ~= "Maps" then classes[class] = true end
end

local function finite(value)
	return type(value) == "number" and value > 0 and value < math.huge
end

local function addQuote(quotes, name, quote)
	local existing = quotes[name]
	if existing == false or quote == false then
		quotes[name] = false
	elseif existing and existing.id ~= quote.id then
		quotes[name] = false
	elseif not existing or quote.volume > existing.volume then
		quotes[name] = quote
	elseif quote.volume == existing.volume and quote.price ~= existing.price then
		quotes[name] = false
	end
end

function M.quotes(body, source)
	if maps.variants[source] then return maps.quotes(body,source) end
	assert(type(body) == "string" and #body <= 2 * 1024 * 1024, "Invalid exchange response size")
	local data = json.decode(body)
	assert(type(data) == "table" and type(data.core) == "table" and data.core.primary == "chaos"
		and type(data.items) == "table" and type(data.lines) == "table", "Invalid chaos-denominated exchange response")
	local names, quotes, priced = {}, {}, false
	for _, item in ipairs(data.items) do
		assert(type(item) == "table" and type(item.id) == "string" and #item.id > 0
			and type(item.name) == "string" and #item.name > 0, "Invalid exchange item")
		assert(not names[item.id] or names[item.id] == item.name, "Exchange identifier has conflicting names")
		names[item.id] = item.name
	end
	for _, line in ipairs(data.lines) do
		assert(type(line) == "table" and type(line.id) == "string", "Invalid exchange price line")
		local name = names[line.id]
		if name and finite(line.primaryValue) and finite(line.volumePrimaryValue) then
			addQuote(quotes, name, { price=line.primaryValue, volume=line.volumePrimaryValue, id=line.id, source=source })
			priced = true
		end
	end
	assert(priced, "No priced exchange items")
	return quotes
end

local function quoteKey(name, category)
	if category == "DivinationCard" or maps.variants[category] then return "\0" .. category .. ":" .. name end
	return name
end

function M.merge(destination, source, category)
	for name, quote in pairs(source) do
		addQuote(destination, quoteKey(name, category), quote)
	end
end

-- Exchange floors use quoted chaos volume. Stash map floors use listing samples.
local minimumVolume = { Map=20, BlightedMap=20, BlightRavagedMap=20, Currency=100, Oil=150, Omen=200, Essence=150, Thread=150, Fragment=200, Resonator=150, Artifact=150, DivinationCard=500 }

function M.liquid(quote)
	return quote and quote.volume >= (minimumVolume[quote.source] or 100)
end

-- A price increase only loosens a hide once it is supported by recent history.
-- A current lower quote still takes effect immediately against the fixed baseline.
function M.remember(quotes, history, day, now)
	local previous, snapshot = {}, {day=day, time=now, values={}}
	local seen = {[day]=true}
	for _, entry in ipairs(history or {}) do
		if type(entry.day) == "string" and not seen[entry.day] and type(entry.time) == "number"
			and entry.time <= now and now-entry.time <= 7*86400 and #previous < 6 then
			previous[#previous+1], seen[entry.day] = entry, true
		end
	end
	local adjusted = {}
	for name, quote in pairs(quotes) do
		if M.liquid(quote) and quote.id then
			local key = (quote.source or "") .. ":" .. quote.id
			snapshot.values[key] = quote.price
			local prices = {}
			for _, entry in ipairs(previous) do
				local value = entry.values and entry.values[key]
				if finite(value) then prices[#prices+1] = value end
			end
			table.sort(prices)
			local midpoint = math.floor(#prices/2)
			local median = #prices == 0 and quote.price or #prices%2 == 1 and prices[midpoint+1]
				or (prices[midpoint]+prices[midpoint+1])/2
			adjusted[name] = {price=math.min(quote.price, median), currentPrice=quote.price,
				highPrice=#prices >= 3 and math.max(quote.price, prices[#prices]) or nil,
				volume=quote.volume, id=quote.id, source=quote.source, observations=#prices, liquidityUnit=quote.liquidityUnit}
		else
			adjusted[name] = quote
		end
	end
	table.insert(previous, 1, snapshot)
	return adjusted, previous
end

function M.sectionBounds(raw)
	local first, last
	local tagged = false
	for index, line in raw:gmatch("()([^\n]*)\n?") do
		if line:match("^# PoB economy: begin[ \t]*\r?$") then
			if tagged then return nil, nil, true end
			first, tagged = index, true
		elseif line:match("^# PoB economy: end[ \t]*\r?$") then
			if not first or last then return nil, nil, true end
			last = index
		end
	end
	if tagged then return first, last, true end
	first = raw:find("# CUSTOM: Hide low-value currency and oil stacks", 1, true)
	return first, first and raw:find("# CUSTOM: Show special magic bases named in the 3.30 patch notes", first, true)
end

function M.supports(raw)
	local first, last = M.sectionBounds(raw)
	return first ~= nil and last ~= nil
end

local supportedConditions = {
	Class=true, BaseType=true, StackSize=true, AreaLevel=true, MapTier=true, Rarity=true,
	BlightedMap=true, UberBlightedMap=true,
}
for _, key in ipairs(maps.excludedFlags) do supportedConditions[key] = true end
local function ruleConditions(rule)
	if rule.action ~= "Hide" or rule.continue or next(rule.styles) then return end
	local conditions = {}
	for _, condition in ipairs(rule.conditions) do
		local key = condition.keyword
		if conditions[key] or not supportedConditions[key] then return end
		conditions[key] = condition
	end
	return conditions
end

-- Select the extra feeds only when the fixed baseline explicitly manages them.
function M.feedCategories(raw)
	local first, last, tagged = M.sectionBounds(raw)
	if not tagged or not last then return M.categories end
	local required = {}
	for _, rule in ipairs(parser.parse(raw:sub(first,last-1)).rules) do
		local conditions = ruleConditions(rule)
		if conditions then
			local category = maps.rule(conditions)
			if category then
				required[category] = true
			else
				local class = conditions.Class
				if class and class.operator == "==" and #class.values == 1 and class.values[1] == "Divination Cards" then
					required.DivinationCard = true
				end
			end
		end
	end
	local categories = {}
	for _, category in ipairs(M.categories) do categories[#categories+1] = category end
	if required.DivinationCard then categories[#categories+1] = "DivinationCard" end
	for _, category in ipairs(maps.feeds) do
		if required[category] then categories[#categories+1] = category end
	end
	return categories
end

function M.tradeLeagues(raw)
	assert(type(raw)=="string" and #raw<=65536, "Invalid PC trade league list size")
	local data = json.decode(raw)
	assert(type(data)=="table" and #data>0 and #data<=100, "No PC trade leagues returned")
	local seen = {}
	for _, league in ipairs(data) do
		assert(type(league)=="table" and type(league.id)=="string" and #league.id<=80 and league.id:match("^[%w%s_-]+$")
			and type(league.name)=="string" and #league.name<=160 and not league.name:find("[%c]")
			and not seen[league.id], "Invalid PC trade league list")
		seen[league.id] = true
	end
	return data, seen
end

function M.feedPath(league, category)
	local resource = maps.variants[category] and "stash/current/item/overview" or "exchange/current/overview"
	return resource .. "?league=" .. urlEncode(league) .. "&type=" .. category
end

function M.pickupPolicy(target, preferences)
	target, preferences = target or 1, preferences or {}
	assert(type(preferences) == "table", "Invalid pickup policy")
	assert(finite(target) and target <= 1000, "Invalid chaos per stack target")
	local policy = {target=target, caps={}}
	for _, key in ipairs({"campaign", "maps"}) do
		local value = preferences[key]
		assert(value == nil or finite(value) and value <= 1000, "Invalid " .. key .. " chaos target")
		policy[key] = value
	end
	local caps = preferences.caps or {}
	assert(type(caps) == "table", "Provide a table of maximum hide cutoffs")
	local count = 0
	for name, limit in pairs(caps) do
		count = count + 1
		assert(count <= 250 and type(name) == "string" and #name > 0 and #name <= 200
			and not name:find('[%c"\\]') and type(limit) == "number" and limit >= 1
			and limit <= 10000 and limit == math.floor(limit), "Invalid item name or maximum hide cutoff")
		policy.caps[name] = limit
	end
	return policy
end

local function scopeOf(area, tagged)
	if not area then return "all" end
	if #area.values == 1 and area.values[1] == "68" then
		if area.operator == ">=" then return "maps" end
		if tagged and area.operator == "<" then return "campaign" end
	end
end

local function cutoffFor(quote, old, target, limit)
	if quote == false then return old, "Ambiguous price mapping" end
	if not quote then return old, "Missing quote" end
	if not M.liquid(quote) then return old, "Quoted volume below this category floor" end
	-- The two directions use separate margins. Higher prices must clear the
	-- baseline by 15%, while newly hidden stacks must be below 85% of target.
	if old * quote.price >= target * 1.15 then
		return math.max(0, math.ceil(target / quote.price - 1e-12) - 1), nil, quote.price
	end
	if limit and limit > old then
		if not quote.highPrice then return old, "Tightening needs three earlier liquid daily quotes" end
		local higher = math.min(limit, math.ceil(target * 0.85 / quote.highPrice - 1e-12) - 1)
		if higher > old then return higher, nil, quote.highPrice end
		return old, "Recent high price keeps the cutoff"
	end
	return old, "Current cutoff is within the price margin"
end

-- Only rewrite the personal stack section, and only exact, simple Hide rules.
-- Retain the complete original text for every unsupported rule.
function M.review(raw, quotes, target, preferences)
	local policy = M.pickupPolicy(target, preferences)
	local start, stop, tagged = M.sectionBounds(raw)
	if not start or not stop then return raw, {} end
	local section = raw:sub(start, stop - 1)
	local changes, skipped = {}, {}
	local function rewrite(block)
		local parsed = parser.parse(block)
		local rule = parsed.rules[1]
		if #parsed.rules ~= 1 or #parsed.diagnostics ~= 0 or not rule or #parsed.imports > 0 then return block end
		local conditions = ruleConditions(rule)
		if not conditions then return block end
		local category, tier, variant
		if tagged then category, tier, variant = maps.rule(conditions) end
		if category then
			local name = maps.quoteName(category,tier)
			local quote = quotes[quoteKey(name,category)]
			local cutoff, reason, price = cutoffFor(quote,1,policy.maps or policy.target)
			if cutoff == 1 then
				skipped[#skipped+1] = {name=name,old=1,reason=reason,maps=true,scope="maps"}
				return block
			end
			changes[#changes+1] = {name=name,old=1,cutoff=0,price=price,currentPrice=quote.currentPrice,
				source=quote.source,observations=quote.observations,classes={"Maps"},volume=quote.volume,
				liquidityUnit=quote.liquidityUnit,maps=true,scope="maps",tier=tier,blighted=variant.blighted,ravaged=variant.ravaged}
			return ""
		end
		if conditions.MapTier or conditions.Rarity or conditions.BlightedMap or conditions.UberBlightedMap then return block end
		for _, key in ipairs(maps.excludedFlags) do if conditions[key] then return block end end
		local class, base, stack, area = conditions.Class, conditions.BaseType, conditions.StackSize, conditions.AreaLevel
		local scope = scopeOf(area, tagged)
		if not class or not base or not scope or class.operator ~= "==" or base.operator ~= "=="
			or stack and (stack.operator ~= "<=" or #stack.values ~= 1) then return block end
		local card = tagged and #class.values == 1 and class.values[1] == "Divination Cards"
		if not card then
			if not stack then return block end
			for _, name in ipairs(class.values) do if not classes[name] then return block end end
		end
		local old = stack and tonumber(stack.values[1]) or 1
		if not old or old < 1 or old > 10000 or old ~= math.floor(old) then return block end
		local group, changed = {}, false
		for _, name in ipairs(base.values) do
			if name:find('[%c"\\]') then return block end
		end
		local pickupTarget = policy[scope] or policy.target
		for _, name in ipairs(base.values) do
			local quote = quotes[quoteKey(name, card and "DivinationCard")]
			local cutoff, reason, usedPrice = cutoffFor(quote, old, pickupTarget, not card and policy.caps[name])
			if cutoff == old then
				skipped[#skipped + 1] = {name=name, old=old, reason=reason, maps=scope=="maps", scope=scope}
			else
				changed = true
				changes[#changes + 1] = {name=name, old=old, cutoff=cutoff, price=usedPrice, currentPrice=quote.currentPrice,
					source=quote.source, observations=quote.observations, classes=class.values,
					volume=quote.volume, maps=scope=="maps", scope=scope}
			end
			group[cutoff] = group[cutoff] or {}
			table.insert(group[cutoff], '"' .. name .. '"')
		end
		if not changed then return block end
		local newline = block:find("\r\n", 1, true) and "\r\n" or "\n"
		local output, cutoffs = {}, {}
		for cutoff in pairs(group) do if cutoff > 0 then cutoffs[#cutoffs+1] = cutoff end end
		table.sort(cutoffs)
		for _, cutoff in ipairs(cutoffs) do
			local lines = {"Hide", '    Class == "' .. table.concat(class.values, '" "') .. '"', "    BaseType == " .. table.concat(group[cutoff], " ")}
			if area then lines[#lines + 1] = "    AreaLevel " .. area.operator .. " 68" end
			if stack then lines[#lines + 1] = "    StackSize <= " .. cutoff end
			output[#output + 1] = table.concat(lines, newline) .. newline
		end
		return table.concat(output, newline)
	end
	local output, lines = {}, {}
	for line in section:gmatch("[^\n]*\n?") do
		if line ~= "" then lines[#lines + 1] = line end
	end
	local blocks = {}
	for _, rule in ipairs(parser.parse(section).rules) do
		local last = rule.line + #rule.rawLines - 1
		local original = table.concat(lines, "", rule.line, last)
		-- A formatting gap or inline comment makes the exact text unsafe to replace.
		local contiguous = true
		for offset, line in ipairs(rule.rawLines) do
			local source = lines[rule.line + offset - 1]
			if not source or source:gsub("\n$", "") ~= line then contiguous = false; break end
		end
		if contiguous and not original:find("#", 1, true) then
			blocks[rule.line] = { last = last, text = rewrite(original) }
		end
	end
	local index = 1
	while index <= #lines do
		local block = blocks[index]
		if block then
			output[#output + 1] = block.text
			index = block.last + 1
		else
			output[#output + 1] = lines[index]
			index = index + 1
		end
	end
	section = table.concat(output)
	return raw:sub(1, start - 1) .. section .. raw:sub(stop), changes, skipped
end

function M.validateManagedRules(rules)
	assert(type(rules) == "table" and #rules <= 150, "Use up to 150 managed item rules")
	local checked, seen = {}, {}
	for index in pairs(rules) do
		assert(type(index) == "number" and index == math.floor(index) and index >= 1 and index <= #rules, "Expected a list of managed rules")
	end
	for index=1,#rules do
		local rule = rules[index]
		assert(type(rule) == "table" and (classes[rule.class] or rule.class == "Divination Cards" or rule.class == "Maps"), "Invalid economy item class")
		local entry
		if rule.class == "Maps" then
			local tier = rule.tier
			assert(type(tier) == "number" and tier >= 1 and tier <= 16 and tier == math.floor(tier)
				and maps.variants[rule.mapType], "Choose a valid atlas map tier and variant")
			entry = {name=maps.quoteName(rule.mapType,tier),class="Maps",scope="maps",tier=tier,mapType=rule.mapType}
		else
			assert(type(rule.name) == "string" and #rule.name <= 200 and rule.name:match("%S") and not rule.name:find('[%c"\\]'),
				"Enter an exact item name")
			assert(rule.scope == "all" or rule.scope == "campaign" or rule.scope == "maps", "Choose an area")
			local cutoff = rule.cutoff
			assert(cutoff == nil and rule.class == "Divination Cards" or
				type(cutoff) == "number" and cutoff >= 1 and cutoff <= 10000 and cutoff == math.floor(cutoff), "Enter a hide cutoff from 1 to 10,000")
			entry = {name=rule.name,class=rule.class,scope=rule.scope,cutoff=cutoff}
		end
		local key = entry.class .. "\0" .. entry.name
		local scopes = seen[key] or {}
		assert(not (scopes.all or scopes[entry.scope] or entry.scope == "all" and next(scopes)), "This item already has a managed rule covering that area")
		scopes[entry.scope], seen[key] = true, scopes
		checked[#checked+1] = entry
	end
	return checked
end

local function managedText(rules)
	local blocks = {}
	for _, rule in ipairs(rules) do
		local lines = {"Hide", '    Class == "' .. rule.class .. '"'}
		if rule.mapType then
			local variant = maps.variants[rule.mapType]
			lines[#lines+1] = "    MapTier == " .. rule.tier
			lines[#lines+1] = "    Rarity <= Rare"
			for _, key in ipairs(maps.excludedFlags) do lines[#lines+1] = "    " .. key .. " False" end
			if variant.blighted ~= nil then lines[#lines+1] = "    BlightedMap " .. (variant.blighted and "True" or "False") end
			lines[#lines+1] = "    UberBlightedMap " .. (variant.ravaged and "True" or "False")
		else
			lines[#lines+1] = '    BaseType == "' .. rule.name .. '"'
			if rule.scope == "campaign" then lines[#lines+1] = "    AreaLevel < 68" end
			if rule.scope == "maps" then lines[#lines+1] = "    AreaLevel >= 68" end
			if rule.cutoff then lines[#lines+1] = "    StackSize <= " .. rule.cutoff end
		end
		blocks[#blocks+1] = table.concat(lines, "\n")
	end
	return table.concat(blocks, "\n\n") .. "\n\n"
end

-- Insert after a compiled profile's personal Show rules. If its imported
-- base is already managed, preserve that prefix and extend the existing section.
function M.addManagedSection(base, rules)
	local blocks = managedText(M.validateManagedRules(rules))
	local first, last, tagged = M.sectionBounds(base)
	if tagged then
		assert(first and last, "Fix the incomplete or duplicate managed price section in the imported base")
		local lineEnd = assert(base:find("\n",first,true))
		return base:sub(1,lineEnd) .. blocks .. base:sub(lineEnd+1)
	elseif first and last then
		return base:sub(1,first-1) .. "# PoB economy: begin\n" .. blocks ..
			base:sub(first,last-1) .. "# PoB economy: end\n" .. base:sub(last)
	end
	return "# PoB economy: begin\n" .. blocks .. "# PoB economy: end\n\n" .. base
end

return M
