local economy = require("Modules.LootFilterEconomy")
local parser = require("Modules.LootFilterParser")
local function read(path)
	local file = assert(io.open(path, "rb"))
	local raw = file:read("*a")
	file:close()
	return raw
end

local input, output = arg[1], arg[2]
assert(input and output and arg[3], "Supply source filter, new output filter, and exchange JSON files")
local quotes = {}
for index = 3, #arg do economy.merge(quotes, economy.quotes(read(arg[index]))) end
local raw = read(input)
assert(raw:find("# CUSTOM: Hide low%-value currency and oil stacks"), "Missing tagged personal currency section")
local candidate, changes = economy.review(raw, quotes)
local parsed = parser.parse(candidate)
local function shown(item)
	local result = parser.simulate(parsed, item)
	assert(result.action == "Show", "Protected item failed: " .. (item.BaseType or "") .. " " .. tostring(result.action))
end
shown({BaseType="Cord Belt", Class="Belts", Rarity="Rare", Corrupted=true, Identified=true})
shown({BaseType="Cord Belt", Class="Belts", Rarity="Magic"})
shown({BaseType="Royal Plate", Class="Body Armours", Rarity="Magic", LinkedSockets=6})
shown({BaseType="Iron Ring", Class="Rings", Rarity="Magic", LinkedSockets=0, FracturedItem=true})
shown({BaseType="Agate Amulet", Class="Amulets", Rarity="Magic", LinkedSockets=0, FracturedItem=false, Fated=true})
local function errors(filter)
	local count = 0
	for _, diagnostic in ipairs(filter.diagnostics) do
		if diagnostic.error then count = count + 1 end
	end
	return count
end
assert(errors(parsed) == errors(parser.parse(raw)), "Parser error count changed")
local rerun, repeated = economy.review(candidate, quotes)
assert(candidate == rerun and #repeated == 0, "Repeat review must be idempotent")
assert(not io.open(output, "rb"), "Choose a new output file")
local file = assert(io.open(output,"wb"))
assert(file:write(candidate))
assert(file:close())
for _, change in ipairs(changes) do
	print(string.format("%s: %d -> %d (%.4g chaos each)", change.name, change.old, change.cutoff, change.price))
end
print(string.format("%d reductions; %d parser errors; protected examples passed", #changes, errors(parsed)))
