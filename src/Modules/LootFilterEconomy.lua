local json = require("dkjson")
local parser = require("Modules.LootFilterParser")
local M = {}
M.categories = {"Currency", "Oil", "Omen", "Essence", "Thread", "Fragment", "Resonator", "Artifact"}
M.endpoint = "https://poe.ninja/poe1/api/economy/"
local classes = {
	["Stackable Currency"] = true,
	["Map Fragments"] = true,
	["Misc Map Items"] = true,
	["Delve Stackable Socketable Currency"] = true,
}

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
	return category == "DivinationCard" and "\0card:" .. name or name
end

function M.merge(destination, source, category)
	for name, quote in pairs(source) do
		addQuote(destination, quoteKey(name, category), quote)
	end
end

-- Floors are total quoted volume in chaos equivalents, not trade counts.
local minimumVolume = { Currency=100, Oil=150, Omen=200, Essence=150, Thread=150, Fragment=200, Resonator=150, Artifact=150, DivinationCard=500 }

function M.liquid(quote)
	return quote and quote.volume >= (minimumVolume[quote.source] or 100)
end

-- A price increase only loosens a hide once it is supported by recent history.
-- A current lower quote still takes effect immediately against the fixed baseline.
function M.remember(quotes, history, day, now)
	local previous, snapshot = {}, {day=day, time=now, values={}}
	for _, entry in ipairs(history or {}) do
		if type(entry.time) == "number" and entry.day ~= day and entry.time <= now and now-entry.time <= 7*86400
			and #previous < 6 then previous[#previous+1] = entry end
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
				volume=quote.volume, id=quote.id, source=quote.source, observations=#prices}
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

-- Add the card feed only for an explicitly managed card rule. Legacy filters
-- keep the same category set and cannot opt in through a similar item name.
function M.feedCategories(raw)
	local first, last, tagged = M.sectionBounds(raw)
	if tagged and last then
		for _, rule in ipairs(parser.parse(raw:sub(first,last-1)).rules) do
			if rule.action == "Hide" then
				for _, condition in ipairs(rule.conditions) do
					if condition.keyword == "Class" and condition.operator == "==" and #condition.values == 1
						and condition.values[1] == "Divination Cards" then
						local categories = {}
						for i, category in ipairs(M.categories) do categories[i] = category end
						categories[#categories+1] = "DivinationCard"
						return categories
					end
				end
			end
		end
	end
	return M.categories
end

-- Only rewrite the personal stack section, and only exact, simple Hide rules.
-- Retain the complete original text for every unsupported rule.
function M.review(raw, quotes, target)
	target = target or 1
	assert(finite(target) and target <= 1000, "Invalid chaos per stack target")
	local start, stop, tagged = M.sectionBounds(raw)
	if not start or not stop then return raw, {} end
	local section = raw:sub(start, stop - 1)
	local changes, skipped = {}, {}
	local function rewrite(block)
		local parsed = parser.parse(block)
		local rule = parsed.rules[1]
		if #parsed.rules ~= 1 or #parsed.diagnostics ~= 0 or not rule or rule.action ~= "Hide"
			or rule.continue or next(rule.styles) or #parsed.imports > 0 then return block end
		local conditions = {}
		for _, condition in ipairs(rule.conditions) do
			local key = condition.keyword
			if conditions[key] or (key ~= "Class" and key ~= "BaseType" and key ~= "StackSize" and key ~= "AreaLevel") then return block end
			conditions[key] = condition
		end
		local class, base, stack, area = conditions.Class, conditions.BaseType, conditions.StackSize, conditions.AreaLevel
		if not class or not base or class.operator ~= "==" or base.operator ~= "=="
			or stack and (stack.operator ~= "<=" or #stack.values ~= 1)
			or area and (area.operator ~= ">=" or #area.values ~= 1 or area.values[1] ~= "68") then return block end
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
		for _, name in ipairs(base.values) do
			local quote = quotes[quoteKey(name, card and "DivinationCard")]
			local cutoff = old
			if M.liquid(quote) then
				-- Require the old cutoff to be at least 15% above target before changing it.
				if old * quote.price >= target * 1.15 then
					cutoff = math.max(0, math.ceil(target / quote.price - 1e-12) - 1)
				end
			end
			if cutoff == old then
				local reason = quote == false and "Ambiguous price mapping"
					or not quote and "Missing quote"
					or not M.liquid(quote) and "Quoted volume below this category floor"
					or "Current cutoff is within the price margin"
				skipped[#skipped + 1] = { name = name, old = old, reason = reason, maps = area ~= nil }
			else
				changed = true
				changes[#changes + 1] = { name = name, old = old, cutoff = cutoff, price = quote.price, currentPrice = quote.currentPrice, source = quote.source, observations = quote.observations, classes = class.values, volume = quote.volume, maps = area ~= nil }
			end
			group[cutoff] = group[cutoff] or {}
			table.insert(group[cutoff], '"' .. name .. '"')
		end
		if not changed then return block end
		local newline = block:find("\r\n", 1, true) and "\r\n" or "\n"
		local output = {}
		for cutoff = 1, old do
			if group[cutoff] then
				local lines = { "Hide", '    Class == "' .. table.concat(class.values, '" "') .. '"', "    BaseType == " .. table.concat(group[cutoff], " ") }
				if area then lines[#lines + 1] = "    AreaLevel >= 68" end
				if stack then lines[#lines + 1] = "    StackSize <= " .. cutoff end
				output[#output + 1] = table.concat(lines, newline) .. newline
			end
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

return M
