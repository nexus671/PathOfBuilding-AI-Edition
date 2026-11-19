-- Run with: python tools/run_headless_lupa.py tools/check_crafting_imports.lua
-- This samples legal combinations; it is not an exhaustive crafting audit.
arg={};dofile("HeadlessWrapper.lua")
main.disableDevAutoSave=true
newBuild()

local sim=require("Modules.CraftingSimulator")
local bases={"Iron Hat","Plate Vest","Rusted Sword","Gold Ring","Turquoise Amulet"}
local total,accepted,rejected=0,0,0

for _,size in ipairs({2,3}) do
	for _,base in ipairs(bases) do
		local model=sim.model("Rarity: NORMAL\n"..base.."\nItem Level: 86")
		local mods={};for _,entry in ipairs(model.mods) do mods[#mods+1]=entry end
		table.sort(mods,function(a,b) return a.id<b.id end)
		local tested=0
		for n=1,200 do
			local selected={mods[(n*13)%#mods+1],mods[(n*37+7)%#mods+1]}
			if size==3 then selected[3]=mods[(n*61+23)%#mods+1] end
			local state=copyTable(model.initial);state.rarity="RARE";state.affixes={}
			for _,entry in ipairs(selected) do state.affixes[#state.affixes+1]={id=entry.id,range=0.5} end
			if pcall(sim.validateState,model,state) then
				local item=sim.toItem(model,state);local lines={}
				for _,line in ipairs(item.explicitModLines) do lines[#lines+1]=line.line end
				local plain="Rarity: RARE\nExample Item\n"..base.."\nItem Level: 86\nImplicits: 0\n"..table.concat(lines,"\n")
				-- Preserve PoB's line labels, but remove the stored affix IDs so
				-- the importer must infer them from the displayed values.
				local labelled=item.raw:gsub("\nPrefix:[^\n]*",""):gsub("\nSuffix:[^\n]*",""):gsub("\nCrafted: true","")
				for _,raw in ipairs({plain,labelled}) do
					local ok,result=pcall(sim.model,raw)
					total=total+1;tested=tested+1
					if ok then
						accepted=accepted+1;local ids={}
						for _,entry in ipairs(result.initial.affixes) do ids[entry.id]=true end
						for _,entry in ipairs(selected) do
							assert(ids[entry.id],"Incorrect import for "..base..": expected "..entry.id.." from "..table.concat(lines," | "))
						end
					else
						local message=tostring(result)
						assert(message:find("Imported values ",1,true) or message:find("Starting modifiers could not be resolved",1,true) or message:find("A native modifier identity does not match",1,true),"Unexpected import error: "..message)
						rejected=rejected+1
					end
				end
			end
		end
		assert(tested>0,"No legal items sampled for "..base)
		print(base.." ("..size.." modifiers): "..tested.." legal samples")
	end
end
assert(accepted>0 and rejected>0,"The sample must exercise both accepted and unresolved imports")
print("CRAFTING_IMPORT_SWEEP_OK: "..total.." legal samples, "..accepted.." accepted, "..rejected.." unresolved")
