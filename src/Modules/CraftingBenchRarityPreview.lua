-- Conditional examples only: no rarity outcome probabilities are assumed.
local sim=require("Modules.CraftingSimulator")
local M={}
local function input(raw,initialState)
	local model=sim.model(raw)
	local state=initialState and sim.validateState(model,initialState) or model.initial
	assert(not state.corrupted and not state.mirrored and not state.destroyed and not state.veil,"Requires an intact, uncorrupted, non-mirrored item without a pending unveil")
	assert(not model.item.synthesised and not model.item.fractured and #(state.influences or {})==0,"Special item interactions are not modeled in this preview")
	assert(not state.implicits and not state.corruptedImplicits and not state.synthRolls and not state.synthRetained and not state.baseItem and not state.imprint and (state.memoryStrands or 0)==0 and (state.intangibility or 0)==0,"Special item interactions are not modeled in this preview")
	for _,entry in ipairs(state.affixes) do assert(not entry.fractured and not entry.crafted,"Fractured and crafted modifier interactions are not modeled in this preview") end
	return model,state
end
local uniqueCache={}
local function uniqueEntries(baseName)
	if uniqueCache[baseName] then return uniqueCache[baseName] end
	local result={}
	for _,entries in pairs(data.uniques or {}) do for _,raw in ipairs(entries) do
		local title,base=raw:match("^%s*([^\r\n]+)\r?\n([^\r\n]+)")
		if base==baseName then result[#result+1]={title=title,source=raw:match("\nSource: ([^\r\n]+)"),raw=raw} end
	end end
	table.sort(result,function(a,b) return a.title<b.title end);uniqueCache[baseName]=result;return result
end
function M.uniqueCandidates(raw,initialState)
	local model=input(raw,initialState);local result={}
	for _,entry in ipairs(uniqueEntries(model.item.baseName)) do result[#result+1]={title=entry.title,source=entry.source} end
	return {candidates=result,note="Bundled same-base references may include legacy or unavailable items. Chance eligibility and outcome odds are not established."}
end
function M.preview(raw,outcome,seed,initialState,uniqueTitle)
	assert(outcome=="MAGIC" or outcome=="RARE" or outcome=="UNIQUE","Choose a conditional outcome")
	local model,state=input(raw,initialState)
	if outcome=="UNIQUE" then
		assert(type(uniqueTitle)=="string" and #uniqueTitle>0,"Choose a bundled unique reference")
		for _,entry in ipairs(uniqueEntries(model.item.baseName)) do if entry.title==uniqueTitle then
			local item=new("Item"):Item(entry.raw,"UNIQUE",true);assert(item.baseName==model.item.baseName and item.title==uniqueTitle,"Invalid unique reference")
			item.itemLevel=model.item.itemLevel;item:BuildAndParseRaw()
			return {itemText=item.raw,outcome="UNIQUE",conditional=true,referenceSource=entry.source,
				note="Bundled same-base reference only, not proof of chance eligibility. Rarity odds and price are unknown; item values, sockets and quality are illustrative and may differ from the starting item."}
		end end
		error("Unique reference does not match this base")
	end
	-- The selected outcome is hypothetical. Ordinary scour and currency models
	-- provide an illustrative modifier roll; this does not establish bench odds.
	if state.rarity~="NORMAL" then state=sim.perform(raw,{method="scour"},seed,state).state end
	assert(state.rarity=="NORMAL" and #state.affixes==0,"The item could not be cleared under this model")
	local result=sim.perform(raw,{method=outcome=="MAGIC" and "transmute" or "alchemy"},seed,state)
	return {itemText=result.itemText,state=result.state,outcome=outcome,conditional=true,dataPatch=result.dataPatch,
		note="Conditional example only; no rarity outcome probability or price is modeled. Ordinary modifier counts, weights and values are assumptions, and bench eligibility and interactions are unverified."}
end
-- Turn an explicitly chosen example into a separate project. The warning is
-- saved with it; no rarity roll, price, or equipped-item change is inferred.
function M.project(raw,result,slot,title,id)
	assert(type(result)=="table" and result.conditional==true and type(result.note)=="string","Choose a conditional example first")
	assert(result.outcome=="MAGIC" or result.outcome=="RARE" or result.outcome=="UNIQUE","Invalid example outcome")
	local project={id=id,title=title,slot=slot,startingItem=result.outcome=="UNIQUE" and result.itemText or raw,goals={},steps={},
		notes="Conditional bench-rarity example; not an observed craft. "..result.note}
	if result.referenceSource then project.notes=project.notes.." Bundled source: "..result.referenceSource:sub(1,500) end
	if result.outcome~="UNIQUE" then project.run=require("Modules.CraftingInventory").run(assert(result.state,"Missing example state")) end
	return require("Modules.CraftingProjects").validate(project)
end
-- The MCP proposal schema accepts portable inventory snapshots rather than
-- desktop workbench checkpoints. A user can resume that snapshot after review.
function M.proposal(raw,result,slot,title,id)
	local project=M.project(raw,result,slot,title,id)
	if project.run then
		project.inventory={require("Modules.CraftingInventory").capture(project,project.run.state,"Conditional bench-rarity example")}
		project.run=nil
	end
	return require("Modules.CraftingProjects").validate(project)
end
return M
