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

function M.quotes(body)
	assert(type(body) == "string" and #body <= 2 * 1024 * 1024, "Invalid exchange response size")
	local data = json.decode(body)
	assert(type(data) == "table" and type(data.core) == "table" and data.core.primary == "chaos"
		and type(data.items) == "table" and type(data.lines) == "table", "Invalid chaos-denominated exchange response")
	local names, quotes = {}, {}
	for _, item in ipairs(data.items) do
		assert(type(item) == "table" and type(item.id) == "string" and type(item.name) == "string", "Invalid exchange item")
		names[item.id] = item.name
	end
	for _, line in ipairs(data.lines) do
		local name = names[line.id]
		if name and finite(line.primaryValue) and finite(line.volumePrimaryValue) then
			quotes[name] = { price = line.primaryValue, volume = line.volumePrimaryValue }
		end
	end
	assert(next(quotes), "No priced exchange items")
	return quotes
end

function M.merge(destination, source)
	for name, quote in pairs(source) do
		local existing = destination[name]
		if existing == nil or existing and quote.volume > existing.volume then
			destination[name] = quote
		elseif existing and quote.volume == existing.volume and quote.price ~= existing.price then
			destination[name] = false
		end
	end
end

local function sectionBounds(raw)
	local first = raw:find("# PoB economy: begin", 1, true)
	if first then return first, raw:find("# PoB economy: end", first, true) end
	first = raw:find("# CUSTOM: Hide low-value currency and oil stacks", 1, true)
	return first, first and raw:find("# CUSTOM: Show special magic bases named in the 3.30 patch notes", first, true)
end

function M.supports(raw)
	local first, last = sectionBounds(raw)
	return first ~= nil and last ~= nil
end

-- Only rewrite the personal stack section, and only exact, simple Hide rules.
-- Retain the complete original text for every unsupported rule.
function M.review(raw, quotes, target)
	target = target or 1
	assert(finite(target) and target <= 1000, "Invalid chaos per stack target")
	local start, stop = sectionBounds(raw)
	if not start or not stop then return raw, {} end
	local section = raw:sub(start, stop - 1)
	local changes = {}
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
		if not class or not base or not stack or class.operator ~= "==" or base.operator ~= "=="
			or stack.operator ~= "<=" or #stack.values ~= 1 or area and (area.operator ~= ">=" or #area.values ~= 1 or area.values[1] ~= "68") then return block end
		for _, name in ipairs(class.values) do if not classes[name] then return block end end
		local old = tonumber(stack.values[1])
		if not old or old < 1 or old > 10000 or old ~= math.floor(old) then return block end
		local group, changed = {}, false
		for _, name in ipairs(base.values) do
			if name:find('[%c"\\]') then return block end
		end
		for _, name in ipairs(base.values) do
			local quote = quotes[name]
			local cutoff = old
			if quote and quote.volume >= 100 then
				-- Require the old cutoff to be at least 15% above target before changing it.
				if old * quote.price >= target * 1.15 then
					cutoff = math.max(0, math.ceil(target / quote.price - 1e-12) - 1)
				end
			end
			if cutoff ~= old then
				changed = true
				changes[#changes + 1] = { name = name, old = old, cutoff = cutoff, price = quote.price, volume = quote.volume, maps = area ~= nil }
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
				lines[#lines + 1] = "    StackSize <= " .. cutoff
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
	return raw:sub(1, start - 1) .. section .. raw:sub(stop), changes
end

return M
