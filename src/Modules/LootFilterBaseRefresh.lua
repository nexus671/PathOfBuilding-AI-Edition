local filters = require("Modules.LootFilters")
local parser = require("Modules.LootFilterParser")
local protected = require("Modules.LootFilterProtectedDrops")
local M = {}

function M.previousURL(profile)
	assert(not profile.template, "An imported filter has its own source")
	local revision = profile.baseCommit
	assert(type(revision) == "string" and #revision == 40 and revision:match("^[a-f0-9]+$"), "The saved NeverSink revision is unavailable")
	local current = filters.source()
	local source = assert(current.files[profile.strictness..".filter"], "The selected strictness has no source").source
	local prefix, suffix = source:match("^(https://raw%.githubusercontent%.com/NeverSinkDev/NeverSink%-Filter/)[a-f0-9]+(/[^?#]+)$")
	assert(prefix and suffix and source == prefix..current.commit..suffix, "The bundled NeverSink source is invalid")
	return prefix..revision..suffix
end

local function conditions(parsed)
	local result = {}
	for _, rule in ipairs(parsed.rules) do
		for _, condition in ipairs(rule.conditions) do
			local key = rule.action.." "..condition.keyword.." "..condition.operator.." "..table.concat(condition.values," ")
			result[key] = (result[key] or 0) + 1
		end
	end
	return result
end

local function changesBetween(before, after)
	local old, new = conditions(before), conditions(after)
	local summary, removed, added = {}, 0, 0
	for condition, count in pairs(old) do
		local delta = count - (new[condition] or 0)
		if delta > 0 then
			removed = removed + delta
			summary[#summary+1] = {text=condition, count=delta}
		end
	end
	for condition, count in pairs(new) do added = added + math.max(count - (old[condition] or 0),0) end
	table.sort(summary,function(a,b) return a.text < b.text end)
	while #summary > 80 do table.remove(summary) end
	return summary, removed, added
end

function M.evaluate(previous, candidate, sampleSets)
	local summary, removed, added = changesBetween(previous,candidate)
	local result = {removedConditions=summary,removedCount=removed,addedCount=added,warnings={},blocks={},checked=0,examplesChecked=0}
	for _, sample in ipairs(protected.samples()) do
		local item = sample.item
		local old = parser.simulate(previous,item)
		if protected.explicitlyShown(old) then
			result.checked = result.checked+1
			local new = parser.simulate(candidate,item)
			local marker = protected.marker(old)
			if not protected.explicitlyShown(new) or marker == sample.marker and protected.marker(new) ~= marker then
				result.blocks[#result.blocks+1] = string.format("%s %s (identified %s, corrupted %s): %s",
					item.Rarity,item.BaseType,tostring(item.Identified),tostring(item.Corrupted),new.action)
			end
		end
	end
	for _, set in ipairs(sampleSets or {}) do
		for _, item in ipairs(set.samples) do
			if result.examplesChecked >= 100 then break end
			result.examplesChecked = result.examplesChecked+1
			local old, new = parser.simulate(previous,item), parser.simulate(candidate,item)
			if old.action ~= new.action then
				result.warnings[#result.warnings+1] = string.format("%s: %s, %s to %s",set.title,item.BaseType or "Example",old.action,new.action)
			end
		end
	end
	return result
end

function M.plan(profile, previousBase)
	assert(type(previousBase) == "string" and #previousBase <= filters.limit, "Could not read the prior NeverSink filter")
	assert(not profile.template and profile.baseCommit ~= filters.source().commit, "This profile has no pending NeverSink base update")
	local updated = filters.update(profile)
	local before, oldReport, oldParsed = filters.compile(profile,true,{commit=profile.baseCommit,raw=previousBase})
	local after, report, parsed = filters.compile(updated,true)
	for _, compiled in ipairs({oldReport,report}) do
		for _, d in ipairs(compiled.diagnostics) do assert(not d.error,d.error) end
	end
	local evaluation = M.evaluate(oldParsed,parsed,profile.sampleSets)
	evaluation.profile = updated
	evaluation.before = before
	evaluation.after = after
	return evaluation
end

return M
