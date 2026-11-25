-- Saved projects refer to the original 3.29 bench indices. Keep those IDs
-- bound to their original meanings when upstream regenerates master mods.
local legacy = require("Data.Crafting.LegacyBench329")
local M = {}

local function key(mod)
	local lines = {}
	for i, line in ipairs(mod) do
		line = line:gsub("^Prefix Modifiers cannot be changed$", "Prefixes Cannot Be Changed")
		line = line:gsub("^Suffix Modifiers cannot be changed$", "Suffixes Cannot Be Changed")
		lines[i] = line
	end
	return table.concat({mod.type or "", mod.group or "", tostring(mod.level or ""), table.concat(lines, "\n")}, "\0")
end

function M.prepare(model, itemType, current)
	local byKey, consumed = {}, {}
	model.benchImportAliases = {}
	for index, mod in ipairs(current) do
		if mod.types and mod.types[itemType] then
			local k = key(mod)
			byKey[k] = byKey[k] or {}
			byKey[k][#byKey[k] + 1] = index
		end
	end
	local function add(id, mod)
		model.byId[id] = mod
		model.bench[#model.bench + 1] = {id = id, mod = mod}
	end
	for index, old in ipairs(legacy) do
		if old.types and old.types[itemType] and (old.type == "Prefix" or old.type == "Suffix") then
			local matches = byKey[key(old)]
			local mod
			if matches and #matches > 0 then
				mod = current[matches[1]]
				for _, match in ipairs(matches) do consumed[match] = true end
				if old[1] == "Prefixes Cannot Be Changed" or old[1] == "Suffixes Cannot Be Changed" then
					local side = old[1] == "Prefixes Cannot Be Changed" and "prefix" or "suffix"
					local alias = "bench:full-" .. side .. "-330"
					model.byId[alias] = copyTable(mod); model.byId[alias].benchImportOnly = true
					model.benchImportAliases[#model.benchImportAliases + 1] = alias
					mod = copyTable(mod); mod[1] = old[1]
				end
			else
				mod = copyTable(old); mod.legacyBenchUnavailable = true
			end
			add("bench:" .. index, mod)
		end
	end
	for index, mod in ipairs(current) do
		if not consumed[index] and mod.types and mod.types[itemType] and (mod.type == "Prefix" or mod.type == "Suffix")
			and not (mod[1] or ""):match("^[12] Prefix Modifiers? cannot be changed$")
			and not (mod[1] or ""):match("^[12] Suffix Modifiers? cannot be changed$") then
			add("bench:330:" .. index, mod)
		end
	end
end

return M
