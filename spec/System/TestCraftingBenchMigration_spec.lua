describe("saved crafting bench identities", function()
	local sim = require("Modules.CraftingSimulator")
	local legacy = require("Data.Crafting.LegacyBench329")
	it("keeps each saved index attached to its original modifier across regenerated data", function()
		for _, base in ipairs({"Iron Hat", "Iron Ring", "Rusted Sword"}) do
			local model = sim.model("Rarity: NORMAL\n" .. base .. "\nItem Level: 86")
			for index, old in ipairs(legacy) do
				if old.types and old.types[model.item.type] and (old.type == "Prefix" or old.type == "Suffix") then
					local mod = assert(model.byId["bench:" .. index])
					assert.equal(old.group, mod.group)
					assert.equal(old[1], mod[1])
					if mod.legacyBenchUnavailable then
						assert.is_truthy(sim.benchReason(model, model.initial, "bench:" .. index))
					end
				end
			end
		end
	end)
	it("imports the current full-lock wording without losing its protection", function()
		for _, side in ipairs({"Prefix", "Suffix"}) do
			local line = side .. " Modifiers cannot be changed"
			local raw = "Rarity: RARE\nTest Item\nIron Hat\nItem Level: 86\n{crafted}" .. line
			local model = sim.model(raw)
			assert.is_truthy(sim.toItem(model, model.initial).raw:find(line, 1, true))
			assert.equal(1, #model.initial.affixes)
			local protected
			for _, entry in ipairs(model.mods) do
				if entry.mod.type == side and entry.mod.group ~= model.byId[model.initial.affixes[1].id].group then protected = entry.id; break end
			end
			assert.is_truthy(protected)
			local state = copyTable(model.initial)
			state.affixes[#state.affixes + 1] = {id = protected, range = 0.5}
			local result = sim.perform(raw, {method = "annul"}, 1, state)
			assert.equal(protected, result.state.affixes[1].id)
		end
	end)
end)
