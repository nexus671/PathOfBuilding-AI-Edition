local marketJSON = require("Modules.LootFilterMarketJSON")
local parser = require("Modules.LootFilterParser")
local maps = require("Modules.LootFilterMapMarket")
local exchange = require("Modules.LootFilterExchangeCrossCheck")
local gems = require("Modules.LootFilterGemMarket")
local appearance = require("Modules.LootFilterPriceAppearance")
local areas = require("Modules.LootFilterPickupAreas")
local cardRewards = require("Data.LootFilters.DivinationRewards")
local uniques = require("Modules.LootFilterUniqueMarket")
local stackPolicy = require("Modules.LootFilterStackPolicy")
local M = {}
M.categories = {"Currency", "Oil", "Omen", "Essence", "Thread", "Fragment", "Resonator", "Artifact"}
M.exchangeCategories = {"Currency", "Fragment", "Runegraft", "AllflameEmber", "Tattoo", "Omen", "DjinnCoin", "Ducat",
	"EnshroudingCrystal", "Artifact", "Oil", "DeliriumOrb", "Scarab", "Astrolabe", "Thread", "Fossil", "Resonator", "Essence"}
M.maxFeedCount = #M.exchangeCategories + #maps.feeds + #uniques.feeds + 2
function M.evidencePriceId(value)
	return type(value)=="string" and #value>=1 and #value<=200 and value:match("^[A-Za-z0-9_.%-]+$") and value or nil
end
local exchangeCategories, coreCategories = {}, {}
for _, category in ipairs(M.exchangeCategories) do exchangeCategories[category] = true end
for _, category in ipairs(M.categories) do coreCategories[category] = true end
local exchangeMarker = "# PoB economy: exchange "
function M.resolveEndpoint(value)
	if not value or value=="" then return "https://poe.ninja/poe1/api/economy/" end
	if type(value)~="string" or #value>400 then return nil end
	local authority, path = (value.."/"):match("^https://([^/]+)(/[%w_/%-]*)$")
	if not authority then return nil end
	local host, port = authority:match("^([%w%.%-]+):(%d+)$")
	host = host or authority
	if not host:match("^%w[%w%.%-]*$") or host:find("..",1,true)
		or port and (tonumber(port)<1 or tonumber(port)>65535) then return nil end
	return "https://"..authority..path:gsub("/+$","").."/"
end

M.endpoint = M.resolveEndpoint(os.getenv("POB_MARKET_CACHE_URL"))
M.endpointError = "The configured PoB market cache must be an HTTPS URL without a query or credentials."
M.managedClasses = {"Stackable Currency", "Map Fragments", "Misc Map Items", "Delve Stackable Socketable Currency", "Divination Cards", "Skill Gems", "Support Gems", "Maps", "Embers of the Allflame", uniques.class}
M.managedAreas = {{label="All areas", val="all"}, {label="Campaign", val="campaign"}, {label="Maps", val="maps"}}
M.exchangeItemClasses = {["Embers of the Allflame"]="AllflameEmber"}
local classes = {}
for _, class in ipairs(M.managedClasses) do
	if class ~= "Divination Cards" and class ~= "Maps" and class ~= uniques.class and not gems.classes[class] and not M.exchangeItemClasses[class] then classes[class] = true end
end

function M.stackClass(class)
	return classes[class]==true or class=="Divination Cards"
end

local function finite(value)
	return type(value) == "number" and value > 0 and value < math.huge
end

local function addQuote(quotes, name, quote)
	local existing = quotes[name]
	if existing == false or quote == false then
		quotes[name] = false
	elseif existing and (existing.id ~= quote.id or existing.price ~= quote.price) then
		quotes[name] = false
	elseif not existing or existing.source == quote.source and quote.volume < existing.volume then
		quotes[name] = quote
	end
end

local function quoteText(value)
	return type(value)=="string" and #value<=200 and value:match("%S") and not value:find("[%c]")
end

function M.maxFeedBytes(category)
	return category==gems.feed and gems.maxBytes or uniques.feed[category] and uniques.maxBytes or 2*1024*1024
end

function M.quotes(body, source, gemRequests, floors)
	if uniques.feed[source] then return uniques.quotes(body,source,floors) end
	if source==gems.feed then return gems.quotes(body,gemRequests) end
	if maps.variants[source] then return maps.quotes(body,source) end
	assert(type(body) == "string" and #body <= 2 * 1024 * 1024, "Invalid exchange response size")
	local data = marketJSON.decode(body, {"items", "lines"})
	assert(data and type(data.core) == "table" and data.core.primary == "chaos", "Invalid chaos-denominated exchange response")
	local names, quotes, priced = {}, {}, false
	for _, item in ipairs(data.items) do
		assert(quoteText(item.id) and quoteText(item.name), "Invalid exchange item")
		assert(not names[item.id] or names[item.id] == item.name, "Exchange identifier has conflicting names")
		names[item.id] = item.name
	end
	for _, line in ipairs(data.lines) do
		assert(quoteText(line.id), "Invalid exchange price line")
		local name = names[line.id]
		if name then
			if finite(line.primaryValue) and finite(line.volumePrimaryValue) then
				addQuote(quotes, name, { price=line.primaryValue, volume=line.volumePrimaryValue, id=line.id, source=source })
				priced = true
			else
				addQuote(quotes, name, false)
			end
		end
	end
	assert(priced, "No priced exchange items")
	return quotes
end

local function quoteKey(name, category)
	if category then return "\0" .. category .. ":" .. name end
	return name
end

function M.merge(destination, source, category)
	for name, quote in pairs(source) do
		addQuote(destination, quoteKey(name, category), quote)
		if coreCategories[category] then addQuote(destination, name, quote) end
	end
end

-- Exchange floors use quoted chaos volume. Stash map floors use listing samples.
local minimumVolume = { SkillGem=20, Map=20, BlightedMap=20, BlightRavagedMap=20, Currency=100, Oil=150, Omen=200, Essence=150, Thread=150, Fragment=200, Resonator=150, Artifact=150, DivinationCard=500 }

local listingFeeds = {[gems.feed]=true}
for _, category in ipairs(maps.feeds) do listingFeeds[category]=true end

function M.liquidityDefault(category)
	if listingFeeds[category] or uniques.feed[category] then return minimumVolume[category] or 20, "listing samples" end
	if exchangeCategories[category] or category=="DivinationCard" then
		return minimumVolume[category] or 100, "chaos volume"
	end
end

function M.liquidityCategories()
	local categories = {}
	for _, category in ipairs(M.exchangeCategories) do categories[#categories+1]=category end
	for _, category in ipairs(maps.feeds) do categories[#categories+1]=category end
	categories[#categories+1] = gems.feed
	for _, category in ipairs(uniques.feeds) do categories[#categories+1]=category end
	categories[#categories+1] = "DivinationCard"
	table.sort(categories)
	return categories
end

function M.liquidityFloors(values)
	assert(values==nil or type(values)=="table", "Invalid category liquidity settings")
	local floors = {}
	for category, floor in pairs(values or {}) do
		local default, unit = M.liquidityDefault(category)
		assert(default, "Choose a supported market category")
		assert(finite(floor) and floor>=1 and floor<=1000000000
			and (unit~="listing samples" or floor==math.floor(floor)),
			"Enter a liquidity minimum from 1 to 1,000,000,000. Listing samples require a whole number.")
		if floor~=default then floors[category]=floor end
	end
	return next(floors) and floors or nil
end

function M.sameLiquidity(left, right)
	left = M.liquidityFloors(left and left.liquidity)
	right = M.liquidityFloors(right and right.liquidity)
	for category, floor in pairs(left or {}) do
		if not right or right[category]~=floor then return false end
	end
	for category in pairs(right or {}) do
		if not left or not left[category] then return false end
	end
	return true
end

function M.liquid(quote, floors)
	return quote and quote.volume >= (floors and floors[quote.source] or M.liquidityDefault(quote.source) or 100)
end

local function cardReward(name, quote, quotes, floors)
	local entry = cardRewards[name]
	if not entry or not M.liquid(quote,floors) or quote.id~=entry[1] then return end
	local setSize, currency, priceId, count = entry[2], entry[3], entry[4], entry[5]
	local unitPrice
	if currency=="Chaos Orb" then
		unitPrice = 1 -- The exchange overview is explicitly denominated in chaos.
	else
		local reward = quotes[quoteKey(currency,"Currency")]
		if not M.liquid(reward,floors) or reward.id~=priceId then return end
		unitPrice = reward.price
	end
	local perCard = (unitPrice/setSize)*count
	if finite(perCard) and perCard>quote.price then
		return {currency=currency,priceId=priceId,setSize=setSize,count=count,perCard=perCard}
	end
end

function M.rewardDescription(reward)
	return string.format("Redeem %d for %dx %s (%.4g chaos per card)",reward.setSize,reward.count,reward.currency,reward.perCard)
end

local function countLiquidQuotes(values)
	local counts = {}
	if type(values) ~= "table" then return counts end
	for key, price in pairs(values) do
		local source = type(key) == "string" and key:match("^([^:]+):")
		if source and finite(price) then counts[source] = (counts[source] or 0) + 1 end
	end
	return counts
end

function M.coverageFailure(source, available, reference)
	local minimum, divisor, description = 20, 4, "a quarter"
	if maps.variants[source] then
		minimum, divisor, description = 4, 2, "half"
	elseif not exchangeCategories[source] and source~="DivinationCard" then
		return
	end
	if type(available)~="number" or type(reference)~="number" or reference~=math.floor(reference)
		or available~=math.floor(available) or reference<minimum or reference>1000000
		or available<0 or available*divisor>=reference then return end
	return {category=source,reason="coverage_drop",availableQuotes=available,usualQuotes=reference}, description
end

local function verifyCoverage(current, previous, onCoverageFailure)
	if #previous < 2 then return end
	local dailyCounts = {}
	for index, entry in ipairs(previous) do
		dailyCounts[index] = countLiquidQuotes(entry.values)
	end
	local latest = countLiquidQuotes(current)
	local function check(source)
		local counts = {}
		for index, day in ipairs(dailyCounts) do counts[index] = day[source] or 0 end
		table.sort(counts)
		local reference = counts[math.ceil(#counts / 2)]
		local available = latest[source] or 0
		local failure, description = M.coverageFailure(source,available,reference)
		if failure then
			if onCoverageFailure then onCoverageFailure(failure) end
			error(string.format("%s feed has fewer than %s of its usual liquid quotes (%d available, recent median %d). The existing filter was kept.",
				source, description, available, reference))
		end
	end
	for _, source in ipairs(M.exchangeCategories) do check(source) end
	check("DivinationCard")
	for _, source in ipairs(maps.feeds) do check(source) end
end

-- A price increase only loosens a hide once it is supported by recent history.
-- A current lower quote still takes effect immediately against the fixed baseline.
function M.remember(quotes, history, day, now, onCoverageFailure, floors, recovered)
	local previous, snapshot = {}, {day=day, time=now, values={}}
	local coverage = {}
	local seen = {[day]=true}
	local sameDay
	for _, entry in ipairs(history or {}) do
		if not sameDay and entry.day==day and type(entry.time)=="number" and entry.time<=now then sameDay=entry end
		if type(entry.day) == "string" and not seen[entry.day] and type(entry.time) == "number"
			and entry.time <= now and now-entry.time <= 7*86400 and #previous < 6 then
			previous[#previous+1], seen[entry.day] = entry, true
		end
	end
	local adjusted = {}
	for name, quote in pairs(quotes) do
		if M.liquid(quote,floors) and quote.id then
			local marketName = name:gsub("^%z[^:]+:", "")
			-- A scoped quote and its default lookup describe the same item. The
			-- exact name binds its ID to this item, even if the provider reuses it.
			local key = (quote.source or "") .. ":\0" .. #marketName .. ":" .. marketName .. quote.id
			coverage[key] = quote.price
			if recovered and recovered[quote.source] then
				local prior=sameDay and sameDay.values and sameDay.values[key]
				if finite(prior) then snapshot.values[key]=prior end
			else
				snapshot.values[key]=quote.price
			end
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
				volume=quote.volume, id=quote.id, providerId=quote.providerId, source=quote.source, observations=#prices, liquidityUnit=quote.liquidityUnit, uniqueName=quote.uniqueName}
		else
			adjusted[name] = quote
		end
	end
	verifyCoverage(coverage, previous, onCoverageFailure)
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
		if not supportedConditions[key] or key~="AreaLevel" and conditions[key] then return end
		conditions[key] = condition
	end
	if conditions.AreaLevel then
		conditions.AreaLevel = areas.read(rule.conditions) or false
	end
	return conditions
end

local function exchangeSelections(section, parsed)
	local rules, selections = {}, {}
	for _, rule in ipairs(parsed.rules) do rules[rule.line] = rule end
	local lineNumber = 0
	for line in section:gmatch("[^\n]*\n?") do
		if line~="" then
			lineNumber = lineNumber+1
			local text = line:match("^%s*(.-)%s*$")
			if text:sub(1,#exchangeMarker-1)==exchangeMarker:sub(1,-2) then
				local category = text:match("^# PoB economy: exchange ([%w]+)$")
				assert(exchangeCategories[category], "Choose a documented commodity exchange category")
				local rule = rules[lineNumber+1]
				local conditions = rule and ruleConditions(rule)
				assert(conditions, "Attach the exchange category immediately before a simple Hide rule")
				for key in pairs(conditions) do
					assert(key=="Class" or key=="BaseType" or key=="StackSize" or key=="AreaLevel",
						"Exchange selection only supports exact commodity stack rules")
				end
				local class,base,stack = conditions.Class,conditions.BaseType,conditions.StackSize
				local cutoff = stack and tonumber(stack.values[1])
				local itemClass = class and class.values[1]
				local singleItem = M.exchangeItemClasses[itemClass]==category
				local stackRule = stack and stack.operator=="<=" and #stack.values==1 and cutoff and cutoff>=1
					and cutoff<=10000 and cutoff==math.floor(cutoff)
				assert(class and class.operator=="==" and #class.values==1 and (classes[itemClass] or singleItem)
					and base and base.operator=="==" and #base.values==1
					and conditions.AreaLevel~=false and (singleItem and not stack or not singleItem and stackRule),
					"Exchange selection only supports exact commodity stack rules")
				selections[rule.line] = category
			end
		end
	end
	return selections
end

-- Select the extra feeds only when the fixed baseline explicitly manages them.
function M.feedCategories(raw)
	local first, last, tagged = M.sectionBounds(raw)
	if not tagged or not last then return M.categories end
	local required, gemRequests = {}, {}
	local section = raw:sub(first,last-1)
	local parsed = parser.parse(section)
	local selected = exchangeSelections(section,parsed)
	for _, entry in pairs(uniques.selections(section,parsed)) do required[entry.source]=true end
	for _, rule in ipairs(parsed.rules) do
		if selected[rule.line] then required[selected[rule.line]] = true end
		local gem = gems.rule(rule)
		if gem then gemRequests[gem.key] = true end
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
	for _, category in ipairs(M.exchangeCategories) do
		if required[category] and not coreCategories[category] then categories[#categories+1] = category end
	end
	if required.DivinationCard then categories[#categories+1] = "DivinationCard" end
	for _, category in ipairs(maps.feeds) do
		if required[category] then categories[#categories+1] = category end
	end
	if next(gemRequests) then categories[#categories+1] = gems.feed end
	for _, category in ipairs(uniques.feeds) do
		if required[category] then categories[#categories+1]=category end
	end
	return categories, gemRequests
end

function M.tradeLeague(value)
	if type(value)~="table" or type(value.id)~="string" or #value.id==0 or #value.id>80
		or not value.id:match("^[A-Za-z0-9 _-]+$") or not value.id:match("%S")
		or value.id:match("^ ") or value.id:match(" $") or type(value.name)~="string" or #value.name>160
		or not value.name:match("%S") or value.name:find("[%c/\\%^]") then return nil end
	return {id=value.id,name=value.name}
end

function M.tradeLeagues(raw)
	assert(type(raw)=="string" and #raw<=65536, "Invalid PC trade league list size")
	local data = marketJSON.decode(raw, nil, true)
	assert(data and #data>0 and #data<=100, "No PC trade leagues returned")
	local list, seen = {}, {}
	for _, value in ipairs(data) do
		local league = M.tradeLeague(value)
		assert(league and not seen[league.id], "Invalid PC trade league list")
		list[#list+1], seen[league.id] = league, true
	end
	return list, seen
end

function M.feedPath(league, category)
	local resource = (maps.variants[category] or uniques.feed[category] or category==gems.feed) and "stash/current/item/overview" or "exchange/current/overview"
	return resource .. "?league=" .. urlEncode(league) .. "&type=" .. category
end

function M.pickupPolicy(target, preferences)
	target, preferences = target or 1, preferences or {}
	assert(type(preferences) == "table", "Invalid pickup policy")
	assert(finite(target) and target <= 1000, "Invalid chaos per stack target")
	assert(preferences.confirmTightening==nil or type(preferences.confirmTightening)=="boolean","Invalid confirmation setting")
	local policy = {target=target,caps={},confirmTightening=preferences.confirmTightening==true or nil,
		liquidity=M.liquidityFloors(preferences.liquidity),observedStacks=stackPolicy.normalize(preferences.observedStacks,M.stackClass)}
	for _, key in ipairs({"campaign", "maps", "earlyMaps", "endgame"}) do
		local value = preferences[key]
		assert(value == nil or finite(value) and value <= 1000, "Invalid " .. key .. " chaos target")
		policy[key] = value
	end
	for _, key in ipairs({"highlightChaos","strongHighlightChaos"}) do
		local value = preferences[key]
		assert(value == nil or finite(value) and value <= 100000, "Enter a highlight threshold above 0 and up to 100,000 chaos")
		policy[key] = value
	end
	for _, key in ipairs({"highlightStyle","strongHighlightStyle"}) do
		local value = preferences[key]
		assert(value==nil or appearance.validPalette(value), "Choose a valid price highlight style")
		policy[key] = value
	end
	policy.highlightActions = appearance.settings(preferences.highlightActions)
	policy.strongHighlightActions = appearance.settings(preferences.strongHighlightActions)
	assert(not (policy.highlightChaos and policy.strongHighlightChaos)
		or policy.strongHighlightChaos > policy.highlightChaos, "The strong highlight threshold must be larger")
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

local function cutoffFor(quote, old, target, floors, limit, confirmedPrice, reward)
	if quote == false then return old, "Ambiguous price mapping" end
	if not quote then return old, "Missing quote" end
	if not M.liquid(quote,floors) then
		local default, unit = M.liquidityDefault(quote.source)
		local floor = floors and floors[quote.source] or default or 100
		return old, string.format("Below the category floor (%.6g of %.6g %s)",quote.volume,floor,unit or "chaos volume")
	end
	-- The two directions use separate margins. Higher prices must clear the
	-- baseline by 15%, while newly hidden stacks must be below 85% of target.
	local price = reward and reward.perCard or quote.price
	if old * price >= target * 1.15 then
		return math.max(0, math.ceil(target / price - 1e-12) - 1), nil, price
	end
	if limit and limit > old then
		if not quote.highPrice then return old, "Tightening needs three earlier liquid daily quotes" end
		if confirmedPrice==false then return old, "No liquid direct-chaos GGG trade to confirm a higher hide cutoff" end
		local protectivePrice = math.max(quote.highPrice,confirmedPrice or 0)
		local higher = math.min(limit, math.ceil(target * 0.85 / protectivePrice - 1e-12) - 1)
		if higher > old then return higher, nil, protectivePrice end
		return old, "Recent high price keeps the cutoff"
	end
	return old, "Current cutoff is within the price margin"
end

local function appearanceSafe(raw)
	local parsed = parser.parse(raw)
	if #parsed.imports>0 or #parsed.diagnostics>0 then return false end
	return true
end

local function highlightBoundaries(policy, highlight, strong, name, area, band, normalHeld, strongHeld)
	local blocks = {}
	local function add(minimum,upper,tier,style,actions,held)
		if not minimum or minimum>10000 or upper and upper<=minimum then return end
		blocks[#blocks+1] = {firstStack=minimum,upper=upper and upper<=10000 and upper or nil,
			tier=tier,name=name,area=not band and (area=="maps" and ">=" or area=="campaign" and "<") or nil,
			band=band or (area=="earlyMaps" or area=="endgame") and area or nil,style=style,actions=actions,held=held or nil}
	end
	add(highlight,strong,1,policy.highlightStyle,policy.highlightActions,normalHeld)
	add(strong,nil,2,policy.strongHighlightStyle,policy.strongHighlightActions,strongHeld)
	return blocks
end

local function priceHighlights(policy, quote, cutoff, name, area, band, reward, prior)
	if not M.liquid(quote,policy.liquidity) or not finite(quote.price) then return {} end
	local price = reward and reward.perCard or quote.price
	local function stackAt(threshold, retained)
		if not threshold then return nil end
		local stack = threshold / price
		local whole = math.floor(stack)
		-- An exact decimal multiple can land a few binary rounding steps above a whole stack.
		local first = stack-whole <= whole*4.44e-16 and whole or math.ceil(stack)
		local entry = math.max(cutoff+1,first)
		local exit = retained and math.max(cutoff+1,retained)
		local held = exit and exit<entry and exit*price >= threshold*0.85
		return held and exit or entry, held
	end
	local highlight, normalHeld = stackAt(policy.highlightChaos,prior and prior.normal)
	local strong, strongHeld = stackAt(policy.strongHighlightChaos,prior and prior.strong)
	return highlightBoundaries(policy,highlight,strong,name,area,band,normalHeld,strongHeld)
end

local continuityLimit = 5000
local function validCutoff(value)
	return type(value)=="number" and value>=0 and value<=10000 and value==math.floor(value)
end

local function checkedContinuity(previous)
	if previous==nil then return {} end
	assert(type(previous)=="table", "Invalid verified cutoff continuity")
	local count = 0
	for key, state in pairs(previous) do
		count=count+1
		assert(count<=continuityLimit and type(key)=="string" and #key<=24
			and (key:match("^[1-9]%d*:[1-9]%d*$") or key:match("^[1-9]%d*:[1-9]%d*:[123]$")),
			"Invalid verified cutoff continuity")
		if type(state)=="table" then
			assert(type(state.source)=="string" and #state.source<=40 and state.source:match("^%w+$")
				and M.evidencePriceId(state.priceId), "Invalid verified price identity")
			assert((state.cutoff==nil or validCutoff(state.cutoff))
				and (state.normal==nil or type(state.normal)=="number" and state.normal<=10000 and validCutoff(state.normal-1))
				and (state.strong==nil or type(state.strong)=="number" and state.strong<=10000 and validCutoff(state.strong-1))
				and (state.cutoff~=nil or state.normal~=nil or state.strong~=nil), "Invalid verified price boundaries")
		else
			assert(validCutoff(state), "Invalid verified cutoff continuity")
		end
	end
	return previous
end

-- Only rewrite the personal stack section, and only exact, simple Hide rules.
-- Retain the complete original text for every unsupported rule.
function M.review(raw, quotes, target, preferences, confirmation, priorContinuity, pinnedCategories)
	local policy = M.pickupPolicy(target, preferences)
	local previous = checkedContinuity(priorContinuity)
	local stackGroups = stackPolicy.index(policy.observedStacks)
	local continuity, continuityCount = {}, 0
	local function replayQuote(name, category)
		local quote = quotes[quoteKey(name,category)]
		if pinnedCategories and (category and pinnedCategories[category] or not category and next(pinnedCategories)) then
			assert(quote, "Saved category quote is missing; the existing filter was kept")
		end
		return quote
	end
	local function rememberDecision(key, state)
		if continuity[key] then return end
		assert(continuityCount<continuityLimit,
			"Too many verified price decisions; the existing filter was kept")
		continuityCount=continuityCount+1
		continuity[key] = state
	end
	local function decisionState(ordinal, position, band, quote)
		local key = ordinal..":"..position
		if band then key=key..":"..areas.bands[band].id end
		local prior = previous[key]
		-- A thin quote can still identify the unchanged baseline decision.
		-- Its price is not used until it meets the liquidity policy.
		if type(quote)~="table" then return key, nil, prior end
		local priceId = M.evidencePriceId(quote.providerId or quote.id)
		local source = quote.source
		if not priceId or type(source)~="string" or #source>40 or not source:match("^%w+$") then return key, nil, prior end
		local current = {source=source,priceId=priceId}
		local matching = type(prior)=="table" and prior.source==source and prior.priceId==priceId and prior or nil
		return key, current, prior, matching
	end
	local function retain(ordinal, position, quote, old, cutoff, reason, band, pickupTarget, effectivePrice)
		local key, current, prior, matching = decisionState(ordinal,position,band,quote)
		local priorCutoff = type(prior)=="table" and prior.cutoff or type(prior)=="number" and prior or nil
		local held, retainedReason
		if quote and pinnedCategories and pinnedCategories[quote.source] then
			assert(matching and priorCutoff~=nil, "Saved category decision is missing or has changed identity")
			rememberDecision(key,prior)
			return priorCutoff, "Retained the verified category decision", nil, key, nil, matching
		end
		if priorCutoff~=nil and priorCutoff<old then
			if not M.liquid(quote,policy.liquidity) then
				cutoff, retainedReason = priorCutoff, reason
			elseif cutoff>priorCutoff and matching and (priorCutoff+1)*effectivePrice >= pickupTarget*0.85 then
				cutoff, held = priorCutoff, true
			end
		end
		if retainedReason then
			if type(prior)=="table" then
				rememberDecision(key,{cutoff=priorCutoff,source=prior.source,priceId=prior.priceId})
			else
				rememberDecision(key,prior)
			end
		elseif current then
			-- Record the verified boundary even when it matches or exceeds the
			-- baseline. Future category recovery needs the actual decision,
			-- not just the boundaries that relaxed the original filter.
			current.cutoff=cutoff
			rememberDecision(key,current)
		elseif cutoff<old then
			rememberDecision(key,cutoff)
		end
		return cutoff, retainedReason, held, key, current, matching
	end
	raw = appearance.strip(raw)
	local start, stop, tagged = M.sectionBounds(raw)
	if not start or not stop then return raw, {}, nil, continuity end
	local section = raw:sub(start, stop - 1)
	local _, precedingLines = raw:sub(1, start - 1):gsub("\n", "")
	local changes, skipped, highlights = {}, {}, {}
	local capCutoffs = {}
	local useHighlights = (policy.highlightChaos or policy.strongHighlightChaos) and appearanceSafe(raw)
	if (policy.highlightChaos or policy.strongHighlightChaos) and not useHighlights then
		skipped[#skipped+1] = {name="Price highlights",styleOnly=true,
			reason="This filter has imports or unverified syntax."}
	end
	local function split(block, exchangeCategory, originalScope, evaluate)
		local newline = block:find("\r\n",1,true) and "\r\n" or "\n"
		local pieces, changed = {}, false
		for _, band in ipairs(areas.split(originalScope)) do
			local rule = evaluate(band)
			changed = changed or rule~=block
			if rule~="" then
				if exchangeCategory and rule==block then rule=exchangeMarker..exchangeCategory..newline..rule end
				if originalScope=="maps" then
					rule = rule:gsub("\n[ \t]*AreaLevel[ \t]+>=[ \t]+68[ \t]*\r?\n","\n")
				end
				local conditions = newline..table.concat(areas.bands[band].conditions,newline)
				rule = rule:gsub("^Hide(\r?\n)",function(ending) return "Hide"..conditions..ending end)
				rule = rule:gsub("(\nHide)(\r?\n)",function(hide,ending) return hide..conditions..ending end)
				pieces[#pieces+1] = rule:gsub("\r?\n$","")..newline
			end
		end
		return changed and table.concat(pieces,newline) or block
	end
	local useBands = policy.earlyMaps or policy.endgame
	local function rewrite(block, exchangeCategory, ordinal, band)
		local parsed = parser.parse(block)
		local rule = parsed.rules[1]
		if #parsed.rules ~= 1 or #parsed.diagnostics ~= 0 or not rule or #parsed.imports > 0 then
			return block, "PoB could not verify the rule syntax for price adjustments."
		end
		local gem = tagged and gems.rule(rule)
		if gem then
			if useBands and not band and (gem.scope=="all" or gem.scope=="maps") then
				return split(block,nil,gem.scope,function(part) return rewrite(block,exchangeCategory,ordinal,part) end)
			end
			local quote = replayQuote(gem.key,gems.feed)
			gem.key = nil
			gem.source, gem.priceId = gems.feed, M.evidencePriceId(quote and quote.providerId)
			local pickupTarget = areas.target(policy,gem.scope,band)
			local cutoff, reason, price = cutoffFor(quote,1,pickupTarget,policy.liquidity)
			gem.scope = band or gem.scope
			local retainedReason, held
			cutoff, retainedReason, held = retain(ordinal,1,quote,1,cutoff,reason,band,pickupTarget,quote and quote.price)
			if held then price = quote.price end
			if cutoff==1 then
				gem.old, gem.reason, gem.maps = 1, retainedReason or reason, areas.mapScope(gem.scope)
				if retainedReason then gem.priceId=nil end
				skipped[#skipped+1] = gem
				return block
			end
			gem.old, gem.cutoff, gem.price = 1, 0, not retainedReason and price or nil
			gem.retainedReason, gem.heldByMargin = retainedReason, held
			gem.classes, gem.maps = {gem.class}, areas.mapScope(gem.scope)
			if retainedReason then gem.priceId = nil
			else
				gem.source, gem.currentPrice, gem.observations = quote.source, quote.currentPrice, quote.observations
				gem.volume, gem.liquidityUnit = quote.volume, quote.liquidityUnit
			end
			changes[#changes+1] = gem
			return ""
		end
		local conditions = ruleConditions(rule)
		if not conditions then
			return block, "The rule uses Continue, appearance settings, or conditions outside the supported price rules."
		end
		local category, tier, variant, mapType
		if tagged then category, tier, variant, mapType = maps.rule(conditions) end
		if category then
			if useBands and not band and not conditions.AreaLevel then
				return split(block,nil,"all",function(part) return rewrite(block,exchangeCategory,ordinal,part) end)
			end
			local scope = band or conditions.AreaLevel or "maps"
			local name = maps.quoteName(mapType,tier)
			local quote = replayQuote(name,category)
			local pickupTarget = areas.target(policy,conditions.AreaLevel or "maps",band)
			local cutoff, reason, price = cutoffFor(quote,1,pickupTarget,policy.liquidity)
			local retainedReason, held
			cutoff, retainedReason, held = retain(ordinal,1,quote,1,cutoff,reason,band,pickupTarget,quote and quote.price)
			if held then price = quote.price end
			if cutoff == 1 then
				skipped[#skipped+1] = {name=name,old=1,reason=retainedReason or reason,maps=areas.mapScope(scope),scope=scope,source=category,priceId=not retainedReason and M.evidencePriceId(quote and quote.id) or nil}
				return block
			end
			local evidenceQuote = not retainedReason and quote or nil
			changes[#changes+1] = {name=name,old=1,cutoff=0,price=not retainedReason and price or nil,currentPrice=evidenceQuote and evidenceQuote.currentPrice,
				source=category,priceId=M.evidencePriceId(evidenceQuote and evidenceQuote.id),observations=evidenceQuote and evidenceQuote.observations,
				classes={"Maps"},volume=evidenceQuote and evidenceQuote.volume,liquidityUnit=evidenceQuote and evidenceQuote.liquidityUnit,
				maps=areas.mapScope(scope),scope=scope,tier=tier,blighted=variant.blighted,ravaged=variant.ravaged,retainedReason=retainedReason,heldByMargin=held}
			return ""
		end
		if conditions.MapTier or conditions.Rarity or conditions.BlightedMap or conditions.UberBlightedMap then
			return block, "The rule does not match a supported exact map variant."
		end
		for _, key in ipairs(maps.excludedFlags) do
			if conditions[key] then return block, "The rule does not match a supported exact map variant." end
		end
		local class, base, stack, area = conditions.Class, conditions.BaseType, conditions.StackSize, conditions.AreaLevel
		local scope = area or "all"
		if not class or not base or area==false or area=="campaign" and not tagged or class.operator ~= "==" or base.operator ~= "=="
			or stack and (stack.operator ~= "<=" or #stack.values ~= 1) then
			return block, "Price rules require exact Class and BaseType, a supported area, and an upper stack cutoff where applicable."
		end
		local card = tagged and #class.values == 1 and class.values[1] == "Divination Cards"
		local singleItem = exchangeCategory and #class.values==1 and M.exchangeItemClasses[class.values[1]]==exchangeCategory
		if not card and not singleItem then
			if not stack then return block, "This item class requires an upper stack cutoff for price adjustments." end
			for _, name in ipairs(class.values) do
				if not classes[name] then return block, "This item class is not supported for stack price adjustments." end
			end
		end
		local old = stack and tonumber(stack.values[1]) or 1
		if not old or old < 1 or old > 10000 or old ~= math.floor(old) then
			return block, "A stack cutoff must be a whole number from 1 to 10,000."
		end
		local group, changed = {}, false
		for _, name in ipairs(base.values) do
			if name:find('[%c"\\]') then return block, "PoB could not safely rewrite an exact base name." end
		end
		if useBands and not band and (scope=="maps" or scope=="all") then
			return split(block,exchangeCategory,scope,function(part) return rewrite(block,exchangeCategory,ordinal,part) end)
		end
		local pickupTarget = areas.target(policy,scope,band)
		scope = band or scope
		for position, name in ipairs(base.values) do
			local quote = replayQuote(name, card and "DivinationCard" or exchangeCategory)
			local reward = card and cardReward(name,quote,quotes,policy.liquidity) or nil
			if card and pinnedCategories and pinnedCategories.Currency and not pinnedCategories.DivinationCard then
				error("A card decision depends on a saved currency price; the existing filter was kept")
			end
			if card and pinnedCategories and pinnedCategories.DivinationCard then reward=nil end
			local limit = not card and not singleItem and policy.caps[name]
			if limit then capCutoffs[name] = math.min(capCutoffs[name] or old,old) end
			local stackEvidence = stack and stackPolicy.forRule(stackGroups,class.values,name,scope)
			local firstVisible = stackPolicy.firstVisible(stackEvidence)
			local bounded = firstVisible and limit and limit>old and limit>=firstVisible
			if bounded then limit=firstVisible-1 end
			local comparison, tradeEvidence
			if policy.confirmTightening and limit and limit>old then
				local confirmed = confirmation and confirmation[name]
				tradeEvidence = exchange.evidence(confirmed)
				-- Earlier offline snapshots stored only the price.
				comparison = tradeEvidence and tradeEvidence.chaosVolume/tradeEvidence.count or finite(confirmed) and confirmed or false
			end
			local cutoff, reason, usedPrice = cutoffFor(quote,old,pickupTarget,policy.liquidity,limit,comparison,reward)
			if bounded and limit<=old and reason=="Current cutoff is within the price margin" then
				reason = "Recorded stack evidence prevents a stricter cutoff"
			end
			local valuation = reward and reward.perCard or quote and quote.price
			local verified, retainedReason, held, key, current, matching =
				retain(ordinal,position,quote,old,cutoff,reason,band,pickupTarget,valuation)
			cutoff = verified
			if held then usedPrice = valuation end
			local styles = not retainedReason and not singleItem and useHighlights and (stack or cutoff==0)
				and priceHighlights(policy,quote,cutoff,name,area,band,reward,matching) or {}
			local prior = previous[key]
			if (not M.liquid(quote,policy.liquidity) or quote and pinnedCategories and pinnedCategories[quote.source])
				and not singleItem and useHighlights and (stack or cutoff==0)
				and type(prior)=="table" and prior.cutoff==cutoff and (prior.normal or prior.strong) then
				styles = highlightBoundaries(policy,prior.normal,prior.strong,name,area,band)
				if #styles>0 then
					retainedReason = retainedReason or reason or "Retained verified highlight because the current quote is unavailable"
					if continuity[key] then continuity[key]=prior else rememberDecision(key,prior) end
				end
			end
			if current and #styles>0 then
				for _, style in ipairs(styles) do current[style.tier==2 and "strong" or "normal"] = style.firstStack end
				rememberDecision(key,current)
			end
			local highlightHeld
			if #styles>0 then
				for _, style in ipairs(styles) do
					highlightHeld = highlightHeld or style.held
					style.held = nil
				end
				for _, itemClass in ipairs(class.values) do
					local byName = highlights[itemClass] or {}
					local specs = byName[name] or {}
					for _, spec in ipairs(styles) do specs[#specs+1]=spec end
					byName[name], highlights[itemClass] = specs, byName
				end
			end
			if cutoff == old and #styles==0 then
				skipped[#skipped + 1] = {name=name, old=old, reason=retainedReason or reason, maps=areas.mapScope(scope), scope=scope,
					stackEvidence=stackEvidence or nil,source=exchangeCategory or card and "DivinationCard" or quote and quote.source or nil,
					priceId=not retainedReason and M.evidencePriceId(quote and quote.id) or nil}
			else
				changed = changed or cutoff~=old
				local icons = {}
				for index, style in ipairs(styles) do icons[index] = {firstStack=style.firstStack,icon=appearance.icon(style.tier,style.style),actions=style.actions} end
				local evidenceQuote = not retainedReason and quote or nil
				changes[#changes + 1] = {name=name, old=old, cutoff=cutoff, price=evidenceQuote and (usedPrice or reward and reward.perCard or evidenceQuote.price),
					currentPrice=evidenceQuote and (evidenceQuote.currentPrice or evidenceQuote.price),reward=reward,source=exchangeCategory or card and "DivinationCard" or evidenceQuote and evidenceQuote.source,
					priceId=M.evidencePriceId(evidenceQuote and evidenceQuote.id),observations=evidenceQuote and evidenceQuote.observations,classes=class.values,stackEvidence=stackEvidence or nil,
					volume=evidenceQuote and evidenceQuote.volume,maps=areas.mapScope(scope),scope=scope,highlights=#icons>0 and icons or nil,
					confirmedPrice=not retainedReason and cutoff>old and comparison or nil,confirmedTrade=not retainedReason and cutoff>old and tradeEvidence or nil,retainedReason=retainedReason,heldByMargin=held,highlightHeldByMargin=highlightHeld}
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
			if exchangeCategory then table.insert(lines,1,exchangeMarker..exchangeCategory) end
			for _, condition in ipairs(areas.conditions(area)) do lines[#lines+1] = condition end
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
	local parsed = parser.parse(section)
	local uniqueRules = tagged and uniques.selections(section,parsed) or {}
	local selections = tagged and exchangeSelections(section,parsed) or {}
	for ordinal, rule in ipairs(parsed.rules) do
		local last = rule.line + #rule.rawLines - 1
		local original = table.concat(lines, "", rule.line, last)
		-- A formatting gap or inline comment makes the exact text unsafe to replace.
		local contiguous = true
		for offset, line in ipairs(rule.rawLines) do
			local source = lines[rule.line + offset - 1]
			if not source or source:gsub("\n$", "") ~= line then contiguous = false; break end
		end
		local reason
		local unique = uniqueRules[rule.line]
		if unique then
			local quote = quotes[quoteKey(unique.base,unique.source)]
			local liquid = M.liquid(quote,policy.liquidity)
			local key, current, saved, prior = decisionState(ordinal,1,nil,quote)
			local thinIdentity = not liquid and current or nil
			if not liquid then current=nil end
			local pinned = pinnedCategories and pinnedCategories[unique.source]
			if pinned then
				assert(prior and (prior.cutoff==0 or prior.normal or prior.strong), "Saved unique category decision is missing or has changed identity")
				current = nil
			end
			local recover = (pinned or not liquid) and type(saved)=="table" and saved.source==unique.source and (saved.normal or saved.strong)
			local fresh = liquid and not pinned
			if contiguous and (liquid or recover or pinned or thinIdentity) and not rule.styles.MinimapIcon and not rule.styles.PlayEffect then
				local strong = policy.strongHighlightChaos or 100
				local normal = policy.highlightChaos or math.min(25,strong)
				local tier = recover and (saved.strong and 2 or saved.normal and 1)
					or fresh and ((quote.price>=strong or prior and prior.strong and quote.price>=strong*0.85) and 2
					or (quote.price>=normal or prior and prior.normal and quote.price>=normal*0.85) and 1)
				if tier then
					if current then
						current[tier==2 and "strong" or "normal"] = 1
						rememberDecision(key,current)
					elseif recover then
						rememberDecision(key,saved)
					end
					local palette = tier==2 and policy.strongHighlightStyle or tier==1 and policy.highlightStyle or nil
					local actions = tier==2 and policy.strongHighlightActions or tier==1 and policy.highlightActions or nil
					local icon = appearance.icon(tier,palette)
					local newline = original:find("\r\n",1,true) and "\r\n" or "\n"
					local text = appearance.styleUnique(rule,tier,palette,actions,newline)
					blocks[rule.line] = {last=last,text=text}
					changes[#changes+1] = {name=unique.base,old=0,cutoff=0,price=fresh and quote.price or nil,currentPrice=fresh and quote.currentPrice or nil,
						priceId=fresh and M.evidencePriceId(quote.id) or nil,source=unique.source,volume=fresh and quote.volume or nil,liquidityUnit=fresh and quote.liquidityUnit or nil,
						retainedReason=recover and "Retained verified highlight because the current quote is unavailable" or nil,
						uniqueBase=true,exampleUnique=fresh and quote.uniqueName or nil,highlightHeldByMargin=fresh and quote.price<(tier==2 and strong or normal) or nil,classes={unique.class},scope=unique.scope,maps=areas.mapScope(unique.scope),
						highlights={{firstStack=1,icon=icon,actions=actions}}}
				elseif current then
					current.cutoff=0
					rememberDecision(key,current)
				elseif pinned and saved.cutoff==0 then
					rememberDecision(key,saved)
				elseif thinIdentity then
					thinIdentity.cutoff=0
					rememberDecision(key,thinIdentity)
				end
			end
		elseif contiguous and not original:find("#", 1, true) then
			local category = selections[rule.line]
			local rewritten
			rewritten, reason = rewrite(original,category,ordinal)
			local first = category and rule.line-1 or rule.line
			if category and rewritten==original then rewritten=lines[first]..rewritten end
			blocks[first] = { last = last, text = rewritten }
		else
			reason = "PoB preserved this rule because it contains a comment or a gap between conditions."
		end
		if tagged and rule.action=="Hide" and reason then
			local line = precedingLines + rule.line
			skipped[#skipped+1] = {name="Managed Hide at baseline line "..line,reason=reason}
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
	local unusedCaps = {}
	for name, limit in pairs(policy.caps) do
		if not capCutoffs[name] or limit<=capCutoffs[name] then unusedCaps[#unusedCaps+1]=name end
	end
	table.sort(unusedCaps)
	for _, name in ipairs(unusedCaps) do
		local old = capCutoffs[name]
		skipped[#skipped+1] = {name=name,policyCap=policy.caps[name],old=old,
			reason=old and "No managed stack cutoff is below the cap. Price-based tightening needs room above the baseline."
				or "No eligible managed stack rule matches this exact item name in the fixed baseline."}
	end
	local candidate = raw:sub(1, start - 1) .. section .. raw:sub(stop)
	return appearance.apply(candidate,highlights), changes, skipped, continuity
end

function M.validateManagedRules(rules)
	assert(type(rules) == "table" and #rules <= 150, "Use up to 150 managed item rules")
	local checked, seen = {}, {}
	for index in pairs(rules) do
		assert(type(index) == "number" and index == math.floor(index) and index >= 1 and index <= #rules, "Expected a list of managed rules")
	end
	for index=1,#rules do
		local rule = rules[index]
		assert(type(rule) == "table" and (classes[rule.class] or rule.class == "Divination Cards" or rule.class == "Maps" or gems.classes[rule.class] or M.exchangeItemClasses[rule.class] or rule.class==uniques.class), "Invalid economy item class")
		assert(rule.exchangeCategory==nil and not M.exchangeItemClasses[rule.class]
			or classes[rule.class] and exchangeCategories[rule.exchangeCategory]
			or M.exchangeItemClasses[rule.class] and rule.exchangeCategory==M.exchangeItemClasses[rule.class],
			"Choose a documented commodity exchange category")
		local entry
		if rule.class == "Maps" then
			local tier = rule.tier
			assert(maps.validTier(rule.mapType,tier), "Choose a valid atlas map tier and variant")
			entry = {name=maps.quoteName(rule.mapType,tier),class="Maps",scope="maps",tier=tier,mapType=rule.mapType}
		else
			assert(type(rule.name) == "string" and #rule.name <= 200 and rule.name:match("%S") and not rule.name:find('[%c"\\]'),
				"Enter an exact item name")
			if rule.exchangeCategory then
				local knownClass = require("Modules.LootFilterLibrary").baseClass(rule.name)
				assert(not knownClass or knownClass==rule.class, "The exact item name belongs to a different filter class")
			end
			assert(rule.scope == "all" or rule.scope == "campaign" or rule.scope == "maps", "Choose an area")
			local cutoff = rule.cutoff
			if rule.class==uniques.class then
				local baseClass, uniqueFeed = uniques.base(rule.name)
				assert(not cutoff and uniqueFeed,"Choose an exact supported unique base")
				entry={name=rule.name,class=rule.class,scope=rule.scope,baseClass=baseClass,uniqueFeed=uniqueFeed}
			elseif gems.classes[rule.class] then
				assert(cutoff==nil and gems.key(rule.name,rule.gemLevel,rule.gemQuality,rule.corrupted),
					"Choose exact gem level, quality, and corruption")
				entry = {name=rule.name,class=rule.class,scope=rule.scope,gemLevel=rule.gemLevel,
					gemQuality=rule.gemQuality,corrupted=rule.corrupted}
			else
				assert(cutoff == nil and (rule.class == "Divination Cards" or M.exchangeItemClasses[rule.class]) or
					not M.exchangeItemClasses[rule.class] and
					type(cutoff) == "number" and cutoff >= 1 and cutoff <= 10000 and cutoff == math.floor(cutoff), "Enter a hide cutoff from 1 to 10,000")
				entry = {name=rule.name,class=rule.class,scope=rule.scope,cutoff=cutoff,exchangeCategory=rule.exchangeCategory}
			end
		end
		local variant = entry.gemLevel and gems.key(entry.name,entry.gemLevel,entry.gemQuality,entry.corrupted)
		local key = entry.class .. "\0" .. (variant or entry.name)
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
		if rule.uniqueFeed then
			blocks[#blocks+1] = uniques.block(rule.name,rule.baseClass,rule.uniqueFeed,rule.scope)
		else
			local lines = {"Hide", '    Class == "' .. rule.class .. '"'}
			if rule.exchangeCategory then table.insert(lines,1,exchangeMarker..rule.exchangeCategory) end
			if rule.mapType then
				local variant = maps.variants[rule.mapType]
				lines[#lines+1] = "    MapTier == " .. rule.tier
				if variant.exactBase then lines[#lines+1] = '    BaseType == "'..variant.exactBase..'"' end
				lines[#lines+1] = "    Rarity <= Rare"
				for _, key in ipairs(maps.excludedFlags) do lines[#lines+1] = "    " .. key .. " False" end
				if variant.blighted ~= nil then lines[#lines+1] = "    BlightedMap " .. (variant.blighted and "True" or "False") end
				lines[#lines+1] = "    UberBlightedMap " .. (variant.ravaged and "True" or "False")
			else
				lines[#lines+1] = '    BaseType == "' .. rule.name .. '"'
				if rule.scope == "campaign" then lines[#lines+1] = "    AreaLevel < 68" end
				if rule.scope == "maps" then lines[#lines+1] = "    AreaLevel >= 68" end
				if rule.gemLevel then
					lines[#lines+1] = "    GemLevel == "..rule.gemLevel
					lines[#lines+1] = "    Quality == "..rule.gemQuality
					lines[#lines+1] = "    Corrupted "..(rule.corrupted and "True" or "False")
					lines[#lines+1] = "    Imbued False"
					lines[#lines+1] = "    TransfiguredGem False"
				end
				if rule.cutoff then lines[#lines+1] = "    StackSize <= " .. rule.cutoff end
			end
			blocks[#blocks+1] = table.concat(lines, "\n")
		end
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
