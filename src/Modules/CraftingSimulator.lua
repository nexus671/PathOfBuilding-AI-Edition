-- cspell:ignore Ukatoa Ukatoas Katakohi unmodeled
-- cspell:ignore RGBW
-- Independent, bounded crafting model using PoB's game-data modifier tables.
local encounter = require("Modules.CalcEncounter")
local M = {methodChecks={}}
-- GGG 3.30: these cluster small-passive speed modifiers share one family.
-- Socket-reducing enchantments occupy a glove socket even after later crafts.
function M.socketLimit(model,state)
	local item=model.item;local limit=item.base.socketLimit or 0
	if state and state.katakohiEnchants then return math.max(0,limit-#state.katakohiEnchants) end
	if item.type=="Gloves" then
		for _,line in ipairs(item.enchantModLines or {}) do
			local value=StripEscapes(line.line or ""):match("^%-(%d+) to maximum Sockets$")
			if value then limit=limit-tonumber(value) end
		end
	end
	return math.max(0,limit)
end
M.clusterSpeedGroup="3.30 cluster small-passive speed family"
function M.isClusterSpeedMod(model,id)
	if not model.item.clusterJewel then return false end
	local mod=model.byId[id]
	if not id:match("^AfflictionJewelSmallPassivesGrant") or not mod then return false end
	for _,line in ipairs(mod) do
		if line:find("Added Small Passive Skills also grant:",1,true) and (line:find("Attack Speed",1,true) or line:find("Cast Speed",1,true) or line:find("Attack and Cast Speed",1,true)) then return true end
	end
	return false
end
M.methods = {"transmute","alteration","augmentation","regal","alchemy","chaos","exalt","annul","scour","divine","bench","remove_crafted","essence"}
M.labels = {transmute="Orb of Transmutation",alteration="Orb of Alteration",augmentation="Orb of Augmentation",regal="Regal Orb",alchemy="Orb of Alchemy",chaos="Chaos Orb",exalt="Exalted Orb",annul="Orb of Annulment",scour="Orb of Scouring",divine="Divine Orb",bench="Crafting bench",remove_crafted="Remove crafted modifiers",essence="Essence"}
function M.withTreeContext(result,version)
	result.dataPatch=result.dataPatch or M.dataPatch
	result.modifierPatch=result.modifierPatch or M.modifierPatch
	if version~=nil then
		assert(type(version)=="string" and treeVersions[version],"Unknown build tree version")
		result.treeVersion=version;result.treeVersionScope="build_context_only"
	end
	result.latestAvailableTreeVersion=latestTreeVersion
	return result
end
local partialWarningMessage="Partial locks assume uniform selection; bench rerolls select once, Harvest augment selects before adding, and conversions select before changing a modifier. Unpredictable recombination treats locks as non-exclusive. Some selections fail and are not charged in this model; actual behavior is unverified. Other interactions remain unsupported."
function M.actionWarnings(action,model)
	local result={}
	if action.method=="vorici_socket_count" then result[#result+1]={code="vorici_socket_assumptions",message="Vorici samples 100 independent rolls using the experimental Jeweller model and keeps the greatest socket count. Odds, retained socket positions and eligibility are unverified.",source="https://www.pathofexile.com/forum/view-thread/3985332"} end
	if action.method=="vorici_socket_colours" then result[#result+1]={code="vorici_colour_assumptions",message="Vorici samples 25 independent rolls using the experimental Chromatic model and keeps the first tied result with the most non-white sockets. Colour probabilities and tie behavior are unverified.",source="https://www.pathofexile.com/forum/view-thread/3985332"} end
	local abyss=false
	for _,id in ipairs(action.fossils or {}) do if id=="Metadata/Items/Currency/CurrencyDelveCraftingAbyss" then abyss=true end end
	for _,entry in ipairs(model and model.initial and model.initial.affixes or {}) do if entry.id=="DelveAbyssJewelSocket1" then abyss=true end end
	if not abyss and (action.method=="recombine" or action.method=="recombine_predictable") and type(action.donorItem)=="string" then
		local ok,donor=pcall(M.model,action.donorItem)
		if ok then for _,entry in ipairs(donor.initial.affixes) do if entry.id=="DelveAbyssJewelSocket1" then abyss=true;break end end end
	end
	if abyss then result[#result+1]={code="abyss_socket_layout",message="Experimental: adding the Abyssal socket modifier replaces the final socket; removing it restores an unlinked white socket. Placement, zero-socket behavior and removal are not verified.",source="https://www.poewiki.net/wiki/Abyssal_socket"} end
	if action.method=="bench" and type(action.modId)=="string" and action.modId:match("^bench:partial%-") then result[#result+1]={code="partial_lock_model",message=partialWarningMessage} end
	if action.method=="recombine" then result[#result+1]={code="recombination_count_odds",message="Recombination uses preliminary 3.30 small-pool observations, older larger-pool estimates and assumed square-root modifier weights. Crafted and non-rollable modifiers default to 1000; partial locks count as non-exclusive and do not protect other affixes. Special cases and weights are uncertain.",source="https://www.reddit.com/r/pathofexile/comments/1xxt2jr/330_recombinator_updated_oddsstrategies/",asOfPatch="3.30"} end
	if action.method=="recombine" and model and data.weaponTypeInfo[model.item.type] then result[#result+1]={code="recombination_weapon_crafted",message="Crafted weapon modifiers are treated as exclusive except partial locks, based on preliminary community testing; this classification may change.",source="https://www.reddit.com/r/pathofexile/comments/1xxt2jr/330_recombinator_updated_oddsstrategies/",asOfPatch="3.30"} end
	if action.method=="harvest_damage" then result[#result+1]={code="harvest_damage_assumptions",message="Experimental: matching elemental modifier IDs are treated as corresponding tiers, and eligible modifiers are selected uniformly. The game's tier mapping and selection odds are not verified; unsupported families are rejected."} end
	if action.method=="harvest_resistance" then result[#result+1]={code="harvest_resistance_assumptions",message="Resistance conversion assumes matching elemental tiers and uniform selection among eligible modifiers. The game's tier mapping and selection odds are not verified; unsupported families are rejected."} end
	if action.method=="tainted_exalt" then result[#result+1]={code="tainted_exalt_branch_limits",message="The model chooses add or remove equally. A branch can fail if no modifier can be added or removed; failed transitions are not charged. Behavior at these limits and branch odds are unverified in game."} end
	if action.method=="tainted_chaos" then result[#result+1]={code="tainted_chaos_branch_odds",message="The model assumes equal chances to reforge or remove modifiers. The game's branch odds are unverified; the reforge uses the ordinary rare-item modifier model."} end
	if action.method=="ducat_ukatoa" then result[#result+1]={code="ukatoa_assumptions",message="Ukatoa assumes equal Exarch/Eater and tier 1-4 chances; these odds are unverified. Modifier selection uses pinned spawn weights.",source="https://poedb.tw/us/Ukatoas_Ducat"} end
	if action.method=="ducat_katakohi" then result[#result+1]={code="katakohi_assumptions",message="Experimental: base-attribute pools, uniform one-to-three socket counts and selection, weighted distinct modifiers, replacement of existing enchantments, and retained socket links are assumptions. Actual roll rules are unverified.",source="https://poedb.tw/us/Katakohis_Ducat"} end
	if action.method=="locus" then result[#result+1]={code="locus_assumptions",message=model and model.item.type=="Jewel" and "Jewel Locus assumes 25% implicit, 25% no change and 50% destruction; these outcomes, odds and replacement selection are unverified." or "Locus assumes 25% implicit, 25% socket and 50% destruction outcomes; these are not verified 3.30 odds. Socket conversion and replacement selection are also assumptions.",source="https://www.pathofexile.com/forum/view-thread/4013680",asOfPatch="3.30"} end
	if action.method=="vaal" and model and model.item.type=="Flask" then result[#result+1]={code="flask_vaal_weights",message="Flask quality changes from -10 to +10; equal outcome weights are assumed and unverified.",source="https://www.pathofexile.com/forum/view-thread/3496784"} end
	if action.method=="vaal" and model and model.item.type=="Jewel" and model.item.base.subType=="Abyss" then result[#result+1]={code="abyss_vaal_assumptions",message="Abyss jewel corruption assumes equal branch weights and a rare reroll of up to four modifiers. The unique-jewel outcome is modeled as no change; actual outcomes and odds are unverified.",source="https://www.poewiki.net/wiki/Vaal_Orb"} end
	if action.method=="vaal" and model and model.item.clusterJewel then result[#result+1]={code="cluster_vaal_assumptions",message="Cluster jewel corruption assumes equal branch weights and a rare reroll of up to four modifiers. The unique-jewel outcome is modeled as no change; actual outcomes and odds are unverified.",source="https://www.poewiki.net/wiki/Vaal_Orb"} end
	if action.method=="vaal" and model and model.item.baseName=="Prismatic Jewel" then result[#result+1]={code="prismatic_vaal_assumptions",message="Prismatic jewel corruption assumes equal branch weights and a rare reroll of up to four modifiers. The unique-jewel outcome is modeled as no change; actual outcomes and odds are unverified.",source="https://www.poewiki.net/wiki/Jewel"} end
	if action.method=="vaal" and model and M.socketLimit(model,model.initial)>0 then result[#result+1]={code="vaal_socket_reroll_unmodeled",message="The rare corruption outcome can reroll sockets and links in game; the resulting layout is unknown in this model. Set an observed or hypothetical layout before socket crafts or exporting the item.",source="https://www.poewiki.net/wiki/Vaal_Orb"} end
	if action.method=="vaal" then result[#result+1]={code="vaal_implicit_selection",message="When replacing one of several Eldritch or synthesised implicits, the model assumes each is equally likely. Synthesised modifier boundaries use the bundled catalogue; its coverage and the game's selection odds are unverified.",source="https://www.poewiki.net/wiki/Corrupted"} end
	if action.method=="binding" then result[#result+1]={code="binding_legacy",message="Orbs of Binding are no longer generated in 3.30; existing orbs still work.",source="https://www.pathofexile.com/forum/view-thread/4013680",asOfPatch="3.30"} end
	if action.method=="jeweller" then result[#result+1]={code="jeweller_estimate",message="Experimental: historical weapon socket weights are assumed for all bases. Quality increases only the maximum-count chance in this model; weights, quality and retained socket/link positions are unverified.",source="https://www.poewiki.net/wiki/Jeweller%27s_Orb"} end
	if action.method=="tainted_quality" then result[#result+1]={code="tainted_quality_estimate",message="Tainted armour and weapon quality uses an assumed uniform 1-20% range. GGG confirmed the 20% maximum; the minimum and distribution are unverified.",source="https://www.pathofexile.com/forum/view-thread/3531661",asOfPatch="3.25"} end
	if action.method=="fusing" then result[#result+1]={code="fusing_estimate",message="Experimental: link-group weights use historical 20% quality observations; applying them to shorter items, quality scaling and excluding the current layout are assumptions. Current game odds are unverified.",source="https://www.reddit.com/r/pathofexile/comments/75t1c9/i_used_100000_fusings_for_science_statistics/"} end
	if action.method=="gwennen" then result[#result+1]={code="gwennen_estimate",message="Experimental: assumes a fair coin, uniform selection and removal counts, normalized maximum-roll checks and ordinary currency transitions. Offer generation, costs and special interactions are not verified.",source="https://www.pathofexile.com/forum/view-thread/4013680",asOfPatch="3.30"} end
	if action.method=="gwennen" and (action.firstOutcome==1018 or action.firstOutcome==1019 or action.secondOutcome==1018 or action.secondOutcome==1019) then result[#result+1]={code="gwennen_side_reroll_assumptions",message="Side rerolls preserve the original number of modifiers on that side, based on comparable Rog research. Applying that rule and the ordinary modifier weights to Gwennen is unverified; some modeled selections can fail.",source="https://www.sirgog.com/wp-content/uploads/2022/12/rog.pdf"} end
	if action.method=="gwennen" and (action.firstOutcome==1031 or action.secondOutcome==1031) then result[#result+1]={code="gwennen_influence_assumptions",message="Influence types are assumed equally likely among supported types. Eligibility and interactions with influence, synthesis, fractures and Eldritch implicits are not verified.",source="https://poe-datamine.phelnaxgaming.workers.dev/"} end
	if action.method=="gwennen" and (action.firstOutcome==1013 or action.secondOutcome==1013) then result[#result+1]={code="gwennen_pantheon_assumptions",message="Pantheon Aspect uses the Brinehook model: four eligible modifiers are assumed equally likely and an open suffix is required. Gwennen eligibility, weights and interactions are unverified.",source="https://poe-datamine.phelnaxgaming.workers.dev/"} end
	if action.method=="gwennen" and (action.firstOutcome==1010 or action.firstOutcome==1011 or action.secondOutcome==1010 or action.secondOutcome==1011) then result[#result+1]={code="gwennen_socket_colour_assumptions",message="Socket colour rerolls use the estimated Chromatic Orb model. The first result tied for the most non-white ordinary sockets is kept; Gwennen's tie rule, eligibility and probabilities are unverified.",source="https://poe-datamine.phelnaxgaming.workers.dev/"} end
	if action.method=="gwennen" and (action.firstOutcome==1016 or action.firstOutcome==1017 or action.secondOutcome==1016 or action.secondOutcome==1017) then result[#result+1]={code="gwennen_socket_link_assumptions",message="Link rerolls use the experimental Fusing model, drawing independent layouts from the starting item and keeping the first tied result with the longest link. Gwennen's repeat rule, tie rule, eligibility and odds are unverified.",source="https://poe-datamine.phelnaxgaming.workers.dev/"} end
	if action.method=="gwennen" and (action.firstOutcome==1028 or action.secondOutcome==1028) then result[#result+1]={code="gwennen_socket_count_assumptions",message="Socket count rerolls use 50 independent draws from the experimental Jeweller model, keeping the greatest count. Gwennen's repeat rule, eligibility, retained sockets and probabilities are unverified.",source="https://poe-datamine.phelnaxgaming.workers.dev/"} end
	if action.method=="gwennen" and (action.firstOutcome==1030 or action.secondOutcome==1030) then result[#result+1]={code="gwennen_socket_count_disputed",message="The offer text says 100 socket rerolls while its listed function argument says 50. This scenario assumes "..tostring(action.gwennenSocketRerolls).." independent Jeweller-model rolls; the actual count, probabilities, eligibility and retained sockets are unverified.",source="https://poe-datamine.phelnaxgaming.workers.dev/"} end
	if action.method=="gwennen" and (action.firstOutcome==1027 or action.secondOutcome==1027) then result[#result+1]={code="gwennen_preserve_assumptions",message="The retained modifier is selected uniformly; the resulting modifier count and new rolls use the ordinary rare-item model. Gwennen's selection, count distribution and interactions are unverified.",source="https://poe-datamine.phelnaxgaming.workers.dev/"} end
	if action.method=="gwennen" and (action.firstOutcome==1012 or action.secondOutcome==1012) then result[#result+1]={code="gwennen_corruption",message="Corruption uses the existing Vaal model; rare-reroll socket and link changes are not modeled."} end
	if action.allflame or action.method=="ducat_kishara" or action.method=="ducat_katakohi" then result[#result+1]={code="allflame_historical",message="Allflame is historical and did not return to core in 3.30."} end
	if model and model.item.type=="Jewel" and model.item.base.subType=="Abyss" and (action.method=="tainted_exalt" or action.method=="tainted_chaos") then
		result[#result+1]={code="abyss_capacity_assumption",message="This model assumes every corrupted Abyss jewel can have three prefixes and three suffixes. Whether that capacity depends on the jewel's corruption source is unverified."}
	end
	return result
end
local function partialWarning(warnings)
	for _,warning in ipairs(warnings) do if warning.code=="partial_lock_model" then return warnings end end
	warnings[#warnings+1]={code="partial_lock_model",message=partialWarningMessage}
	return warnings
end
function M.recipeWarnings(recipe,model)
	local result,seen={},{}
	for _,action in ipairs(recipe and recipe.steps or {}) do for _,warning in ipairs(M.actionWarnings(action,model)) do
		if not seen[warning.code] then result[#result+1]=warning;seen[warning.code]=true end
	end end
	return result
end
M.limits = {"Experimental PoE 1 model, not a complete game crafting implementation.",
	"Supported: ordinary equipment, known modifier IDs, fractured modifiers, basic currencies, bench modifiers and essences. Meta modifiers protect/remap only the supported actions.",
	"Supported crafts include fossils, Harvest, recombination, influence, corruption, sockets and veiled crafts; unsupported combinations fail explicitly. Review each action's model notes.",
	"Rerolls model 4/5/6 rare modifiers with weights 8/3/1, and 1/2 magic modifiers equally. These distribution assumptions and PoB data coverage affect estimates.",
	"Integer roll ranges use inclusive integer draws. Fractional display ranges use illustrative normalized rolls because the underlying stat precision is not present in this data export.",
	"Modifier targets match IDs and optional normalized minimum rolls, not exact individual stat values. Wilson intervals measure sampling uncertainty only. Results describe the bounded recipe, not guaranteed in-game costs."}

local function integer(value,low,high,label)
	assert(type(value) == "number" and value == math.floor(value) and value >= low and value <= high,"Invalid "..label)
	return value
end
local function rng(seed)
	local value=seed
	return function() value=value*16807%2147483647; return value/2147483647 end
end
local function copyState(state)
	return copyTable(state)
end
local function renderLines(item)
	local lines={ }
	for _,line in ipairs(item.explicitModLines) do lines[#lines+1]=StripEscapes(itemLib.formatModLine(line,false) or "") end
	table.sort(lines)
	return table.concat(lines,"\n")
end
local function flags(model,state)
	local result={ }
	local function rollBlock(line)
		if line == "Cannot roll Attack Modifiers" then result.attack=true end
		if line == "Cannot roll Caster Modifiers" then result.caster=true end
	end
	for _,entry in ipairs(state.affixes) do
		local mod=model.byId[entry.id]
		if mod.partialLock then result[mod.partialLock.side]=mod.partialLock.count end
		for _,line in ipairs(mod) do
			if line == "Prefixes Cannot Be Changed" or line == "Prefix Modifiers cannot be changed" then result.prefixes=true end
			if line == "Suffixes Cannot Be Changed" or line == "Suffix Modifiers cannot be changed" then result.suffixes=true end
			if line == "Cannot roll Attack Modifiers" then result.explicitAttack=true end
			if line == "Cannot roll Caster Modifiers" then result.explicitCaster=true end
			rollBlock(line)
			if line == "Can have up to 3 Crafted Modifiers" then result.multipleCrafts=true end
		end
	end
	-- Replaced implicits take precedence over the starting item's base implicit.
	local replacement=state.corruptedImplicits or state.implicits
	if replacement then
		for _,entries in ipairs({state.corruptedImplicits or {},state.implicits or {}}) do for _,entry in ipairs(entries) do for _,line in ipairs(model.byId[entry.id] or {}) do rollBlock(line) end end end
		for _,index in ipairs(state.synthRetained or {}) do for _,line in ipairs(model.synthesisGroups[index]) do rollBlock(StripEscapes(line.line or "")) end end
	else
		for _,line in ipairs(model.item.implicitModLines or {}) do rollBlock(StripEscapes(line.line or "")) end
		if state.vendorImplicit then for _,line in ipairs(model.byId[state.vendorImplicit] or {}) do rollBlock(line) end end
	end
	return result
end
M.blockFlags=flags
local function counts(model,state)
	local result={Prefix=0,Suffix=0,crafted=0,total=#state.affixes,groups={},tags={}}
	for _,entry in ipairs(state.affixes) do
		local mod=assert(model.byId[entry.id],"Unknown modifier ID: "..tostring(entry.id))
		result[mod.type]=result[mod.type]+1
		if mod.group then result.groups[mod.group]=true end
		if model.item.clusterJewel and M.isClusterSpeedMod(model,entry.id) then result.groups[M.clusterSpeedGroup]=true end
		if entry.crafted then result.crafted=result.crafted+1 end
		for _,tag in ipairs(mod.tags or { }) do result.tags[tag]=true end
	end
	return result
end

-- Use the native renderer so every preview retains the same independent rolls.
function M.rolledLines(mod,range) return itemLib.applyModRanges(mod,range) end
function M.entryMod(model,entry)
	return entry.legacyLightRadius and assert(model.legacyLightRadius[entry.id],"Unknown legacy Light Radius modifier") or entry.description330 and assert(model.descriptions330[entry.id],"Unknown 3.30 modifier description") or entry.corruption330 and assert(model.corruptions330[entry.id],"Unknown 3.30 corruption modifier") or model.byId[entry.id]
end

function M.toItem(model,state)
	local item=new("Item"):Item(model.raw)
	item.affixes=model.byId
	for _,entry in ipairs(state.affixes) do if entry.legacyLightRadius or entry.description330 then
		if item.affixes==model.byId then item.affixes={};for id,mod in pairs(model.byId) do item.affixes[id]=mod end end
		item.affixes[entry.id]=M.entryMod(model,entry)
	end end
	if M.decorateItem then M.decorateItem(model,state,item) end
	item.rarity=state.rarity; item.title=state.rarity == "RARE" and "Simulated craft" or nil
	item.name=item.title or item.baseName
	item.crafted=true; item.prefixes={}; item.suffixes={}; item.explicitModLines={}
	local caps=M.capacities(model,state)
	item.affixLimit=caps.Prefix+caps.Suffix
	item.prefixes.limit=caps.Prefix
	item.suffixes.limit=caps.Suffix
	for _,entry in ipairs(state.affixes) do
		local mod=model.byId[entry.id]
		if not entry.crafted then
			local list=mod.type == "Prefix" and item.prefixes or item.suffixes
			list[#list+1]={modId=entry.id,range=type(entry.range) == "table" and copyTable(entry.range) or {entry.range or 0.5},fractured=entry.fractured}
		end
	end
	for _,list in ipairs({item.prefixes,item.suffixes}) do for i=#list+1,list.limit do list[i]={modId="None"} end end
	item:Craft()
	local hasBench=false
	for _,entry in ipairs(state.affixes) do if entry.crafted then
		hasBench=true
		local mod=model.byId[entry.id]
		item.requirements.level=math.max(item.requirements.level or 0,math.floor((mod.level or 0)*0.8))
		for _,line in ipairs(M.rolledLines(mod,entry.range)) do item.explicitModLines[#item.explicitModLines+1]={line=line,crafted=true,fractured=entry.fractured,prefix=mod.type == "Prefix",suffix=mod.type == "Suffix"} end
	end end
	if hasBench then
		for _,list in ipairs({item.prefixes,item.suffixes}) do for _,entry in ipairs(list) do if type(entry.range) == "number" then entry.range={entry.range} end end end
		item:BuildAndParseRaw()
	end
	return item
end

-- Item text has no representation for an unknown socket layout. Keep the
-- structured state available, but do not export a guessed layout as fact.
function M.itemText(model,state)
	if state.destroyed or state.veil or state.socketLayoutUnknown then return nil end
	return M.toItem(model,state).raw
end
local function unknownSocketWarning(warnings)
	warnings[#warnings+1]={code="socket_layout_unknown",message="The starting item's socket layout is unknown. Set an observed or hypothetical layout before socket actions, socket goals or exporting item text."}
end

function M.model(raw)
	assert(type(raw) == "string" and #raw <= 24000,"Invalid starting item")
	local item=new("Item"):Item(raw)
	assert(item.base and item.itemLevel,"A recognized base and explicit Item Level are required")
	assert(not raw:find("\nUnidentified",1,true),"Identify the starting item before importing its modifiers")
	integer(item.itemLevel,1,100,"item level")
	assert(item.rarity == "NORMAL" or item.rarity == "MAGIC" or item.rarity == "RARE","Unique and relic crafting is not supported")
	assert(not item.foulborn,"Foulborn items need a separate modifier-mutation model")
	local equipment={Helmet=true,["Body Armour"]=true,Gloves=true,Boots=true,Shield=true,Quiver=true,Amulet=true,Ring=true,Belt=true}
	assert(equipment[item.type] or item.type == "Jewel" or item.type == "Flask" or item.type == "Tincture" or data.weaponTypeInfo[item.type],"This engine currently supports ordinary equipment; this item type is unsupported")
	if item.fractured then for _,info in ipairs(itemLib.influenceInfo.all) do assert(not item[info.key],"Fractured and influenced combinations are unsupported") end end
	local model={raw=item.raw,item=item,byId={},mods={},bench={},essences={}}
	model.legacyAbyss=require("Modules.CraftingAbyss330").prepare(item)
	local extraTags={}
	if item.clusterJewel and item.clusterJewel.skills[item.clusterJewelSkill] then extraTags[item.clusterJewel.skills[item.clusterJewelSkill].tag]=true end
	for id,mod in pairs(item.affixes or { }) do model.byId[id]=mod end
	require("Modules.CraftingImport").prepareDropOnly(model)
	require("Modules.CraftingDescriptions330").prepare(model)
	require("Modules.CraftingUnveiledJewel330").prepare(model)
	require("Modules.CraftingUnveiledJewel330").restoreIdentities(model,raw)
	model.trickery330={}
	if item.type=="Belt" then
		local id="PlayerIsDeliriousEssence1"
		local mod={type="Prefix",affix="Trickster's",level=85,group="PlayerIsDelirious",weightKey={},weightVal={},modTags={},statOrder={100001000},"You are affected by Delirium Fog"}
		model.byId[id]=mod;model.trickery330[id]=mod
		require("Modules.CraftingUnveiledJewel330").restoreIdentities(model,raw,model.trickery330)
	end
	for id,mod in pairs((item.type == "Jewel" or item.type == "Flask" or item.type == "Tincture") and item.affixes or data.itemMods.Explicit) do
		if (mod.type == "Prefix" or mod.type == "Suffix") and mod.level <= item.itemLevel and not mod.affix:find("Elevated",1,true) then
			local weight=item:GetModSpawnWeight(mod,extraTags)
			if weight > 0 then model.mods[#model.mods+1]={id=id,mod=mod,weight=weight} end
		end
	end
	require("Modules.CraftingLightRadius330").prepare(model)
	table.sort(model.mods,function(a,b) return a.id < b.id end)
	require("Modules.CraftingBenchMigration").prepare(model,item.type,data.masterMods)
	-- The 3.30 lock texts and prices are published by GGG; the affix sides
	-- follow the 3.30 client modifier records. Keep these separate from pinned
	-- 3.29 master-mod rows so saved IDs do not shift on a data update.
	for _,side in ipairs({"Prefix","Suffix"}) do
		local templateText=side=="Prefix" and "Prefixes Cannot Be Changed" or "Suffixes Cannot Be Changed"
		local template
		for _,entry in ipairs(model.bench) do if entry.mod[1]==templateText then template=entry.mod;break end end
		if template then for count=1,2 do
			local id="bench:partial-"..side:lower().."-"..count;local mod=copyTable(template)
			mod[1]=count.." "..side.." Modifier"..(count==1 and "" or "s").." cannot be changed"
			mod.partialLock={side=side,count=count};model.byId[id]=mod;model.bench[#model.bench+1]={id=id,mod=mod}
		end end
	end
	for id,essence in pairs(data.essences) do
		local modId=essence.mods[item.type]
		if modId and model.byId[modId] then model.essences[#model.essences+1]={id=id,name=essence.name,modId=modId,tier=essence.tier,type=essence.type,maxModLevel=({35,45,60,75})[essence.tier]} end
	end
	if next(model.trickery330) then model.essences[#model.essences+1]={id="Metadata/Items/Currency/CurrencyEssenceUber1",name="Essence of Trickery",modId="PlayerIsDeliriousEssence1",tier=8,type=24} end
	local desolation=require("Modules.CraftingDesolation330")[item.type]
	if desolation and model.byId[desolation] then model.essences[#model.essences+1]={id="Metadata/Items/Currency/CurrencyEssenceFaridun1",name="Essence of Desolation",modId=desolation,tier=0,canReforgeRare=true,maxModLevel=15} end
	table.sort(model.essences,function(a,b) return a.id < b.id end)
	local state={rarity=item.rarity,affixes={},corrupted=item.corrupted or false}
	for _,list in ipairs({item.prefixes,item.suffixes}) do for _,entry in ipairs(list) do
		if entry.modId ~= "None" then
			assert(model.byId[entry.modId],"Starting item has an unknown modifier")
			local current=model.descriptions330[entry.modId]
			state.affixes[#state.affixes+1]={id=entry.modId,range=type(entry.range) == "table" and copyTable(entry.range) or entry.range,fractured=entry.fractured or false,legacyLightRadius=model.legacyLightRadius[entry.modId] and true or nil,description330=current and raw:find(current[1],1,true) and true or nil}
		end
	end end
	-- A legacy Delve resistance prefix may be converted to its corresponding
	-- elemental prefix, even though none of these modifiers currently rolls.
	-- Permit those results only when this exact starting item had one already.
	model.legacyDelveResistance={}
	for _,entry in ipairs(state.affixes) do
		if entry.id=="DelveArmourFireResistance1" or entry.id=="DelveArmourColdResistance1" or entry.id=="DelveArmourLightningResistance1" then
			for _,element in ipairs({"Fire","Cold","Lightning"}) do
				local id="DelveArmour"..element.."Resistance1";if model.byId[id] then model.legacyDelveResistance[#model.legacyDelveResistance+1]=id end
			end
			break
		end
	end
	local reconstructed=M.toItem(model,state)
	if renderLines(reconstructed) ~= renderLines(item) then
		local indices={};for index,entry in ipairs(state.affixes) do if entry.legacyLightRadius then indices[#indices+1]=index end end
		-- An item can contain more than one affected modifier and each may be
		-- legacy or current. There are at most six explicit modifiers.
		for mask=1,2^#indices-1 do
			local current=copyTable(state)
			for bit,index in ipairs(indices) do if math.floor(mask/2^(bit-1))%2==1 then current.affixes[index].legacyLightRadius=nil end end
			local candidate=M.toItem(model,current)
			if renderLines(candidate)==renderLines(item) then state=current;reconstructed=candidate;break end
		end
	end
	if renderLines(reconstructed) ~= renderLines(item) then
		state=require("Modules.CraftingImport").resolve(M,model,state)
		reconstructed=M.toItem(model,state)
	end
	local c=counts(model,state)
	for _,entry in ipairs(state.affixes) do if entry.fractured then for _,info in ipairs(itemLib.influenceInfo.all) do assert(not item[info.key],"Fractured and influenced combinations are unsupported") end end end
	local caps=M.capacities(model,state)
	assert(c.Prefix <= caps.Prefix and c.Suffix <= caps.Suffix,"Starting item exceeds affix limits")
	assert(renderLines(reconstructed) == renderLines(item),"Starting modifiers could not be resolved exactly. Use a blank base or advanced item text with recognized modifier IDs.")
	model.initial=state
	return model
end

function M.pool(model,state)
	local c,f=counts(model,state),flags(model,state)
	for key,value in pairs(state.rollBlock or { }) do f[key]=value end
	local caps=M.capacities(model,state)
	local result,total={},0
	for _,entry in ipairs(model.mods) do
		local mod=entry.mod
		local blocked=c[mod.type] >= caps[mod.type] or c.groups[mod.group] or state.maxEssenceModLevel and mod.level>state.maxEssenceModLevel or model.item.clusterJewel and M.isClusterSpeedMod(model,entry.id) and c.groups[M.clusterSpeedGroup]
		for _,tag in ipairs(mod.modTags or { }) do if f[tag] then blocked=true end end
		if not blocked then
			local weight=next(c.tags) and model.item:GetModSpawnWeight(mod,c.tags) or entry.weight
			if weight > 0 then result[#result+1]={id=entry.id,weight=weight}; total=total+weight end
		end
	end
	return result,total
end
local function rollRange(mod,random)
	local ranges={ }
	for _,line in ipairs(mod) do for range in line:gmatch("%b()") do
		local low,high=range:match("(%-?%d+%.?%d*)%-(%-?%d+%.?%d*)")
		if low and high then
			low,high=tonumber(low),tonumber(high)
			local value=random()
			if low < high and low == math.floor(low) and high == math.floor(high) then value=math.floor(value*(high-low+1))/(high-low) end
			ranges[#ranges+1]=value
		end
	end end
	return #ranges > 1 and ranges or ranges[1] or 0.5
end
local function add(model,state,random)
	local pool,total=M.pool(model,state)
	assert(total > 0,"No legal modifier can be added")
	local pick=random()*total
	for _,entry in ipairs(pool) do
		pick=pick-entry.weight
		if pick < 0 then state.affixes[#state.affixes+1]={id=entry.id,range=M.rollRange(model.byId[entry.id],random)}; return end
	end
	error("Could not select a modifier")
end
local partialSelected=setmetatable({},{__mode="k"})
local function protected(entry,mod,f) return entry.fractured or partialSelected[entry] or mod.type == "Prefix" and f.prefixes or mod.type == "Suffix" and f.suffixes end
function M.hasPartialLock(model,state)
	local f=flags(model,state);return f.Prefix~=nil or f.Suffix~=nil
end
local function selectPartialLocks(model,state,random)
	local f=flags(model,state)
	for _,side in ipairs({"Prefix","Suffix"}) do if f[side] then
		local choices={};for _,entry in ipairs(state.affixes) do if model.byId[entry.id].type==side then choices[#choices+1]=entry end end
		for _=1,math.min(f[side],#choices) do
			local index=math.floor(random()*#choices)+1;partialSelected[table.remove(choices,index)]=true
		end
	end end
end
local function clearPartialLocks(state)
	for _,entry in ipairs(state.affixes) do partialSelected[entry]=nil end
end
function M.annulCandidates(model,state)
	local f=flags(model,state);local eligible={}
	for index,entry in ipairs(state.affixes) do if not protected(entry,model.byId[entry.id],f) then eligible[#eligible+1]=index end end
	return eligible
end
-- Visit each possible selection using the same routine as an action. The
-- protected markers exist only while the callback is running.
function M.eachPartialSelection(model,state,callback)
	local f=flags(model,state);local sizes={}
	for _,side in ipairs({"Prefix","Suffix"}) do if f[side] then
		local n=0;for _,entry in ipairs(state.affixes) do if model.byId[entry.id].type==side then n=n+1 end end
		for i=1,math.min(f[side],n) do sizes[#sizes+1]=n-i+1 end
	end end
	local draws={}
	local function visit(depth,probability)
		if depth<=#sizes then
			local n=sizes[depth]
			for i=1,n do draws[depth]=(i-0.5)/n;if visit(depth+1,probability/n) then draws[depth]=nil;return true end end
			draws[depth]=nil;return
		end
		local shadow=copyState(state);local cursor=0
		selectPartialLocks(model,shadow,function() cursor=cursor+1;return assert(draws[cursor],"Missing partial-lock draw") end)
		local ok,stop=pcall(callback,shadow,probability,draws)
		clearPartialLocks(shadow)
		if not ok then error(stop) end
		return stop==true
	end
	return visit(1,1)
end
-- Return nil if any selection leaves no removable modifier: that case needs
-- transition-error handling rather than a fabricated Annulment outcome.
function M.partialAnnulBranches(model,state)
	local result={};local invalid=false
	M.eachPartialSelection(model,state,function(shadow,probability,draws)
		local eligible=M.annulCandidates(model,shadow)
		if #eligible==0 then invalid=true;return true end
		for i,index in ipairs(eligible) do
			local branch=result[index]
			if not branch then branch={index=index,probability=0,draws=copyTable(draws),removalDraw=(i-0.5)/#eligible};result[index]=branch end
			branch.probability=branch.probability+probability/#eligible
		end
	end)
	if invalid then return nil end
	local ordered={};for _,branch in pairs(result) do ordered[#ordered+1]=branch end
	table.sort(ordered,function(a,b) return a.index<b.index end);return ordered
end
local function clear(model,state,ignoreMeta)
	local f=ignoreMeta and {} or flags(model,state)
	for i=#state.affixes,1,-1 do if not protected(state.affixes[i],model.byId[state.affixes[i].id],f) then table.remove(state.affixes,i) end end
end

local function benchReason(model,state,id,c,f)
	local mod=model.byId[id]
	if not mod then return "Unknown bench modifier" end
	if not id:match("^bench:") then return "Select a bench modifier" end
	if mod.benchImportOnly then return "This modifier is available for imported items only" end
	if mod.legacyBenchUnavailable then return "This saved bench modifier is not available in current data" end
	if c.crafted >= (f.multipleCrafts and 3 or 1) then return "Crafted modifier limit reached" end
	if c.groups[mod.group] then return "A modifier from this group is already present" end
	-- Native drop-only labels can differ from the underlying game groups used
	-- by an ordinary bench modifier (for example, a resistance hybrid).
	local metadata=require("Modules.CraftingAdvanced").data().mods
	for _,entry in ipairs(state.affixes) do
		local record=metadata[entry.id]
		for _,group in ipairs(record and record.groups or {}) do if group==mod.group then return "A modifier from this group is already present" end end
	end
	if c[mod.type] >= M.capacities(model,state)[mod.type] then return "No open affix for this bench craft" end
end
function M.benchReason(model,state,id)
	return benchReason(model,state,id,counts(model,state),flags(model,state))
end
function M.benchAvailable(model,state)
	local c,f=counts(model,state),flags(model,state)
	if c.crafted >= (f.multipleCrafts and 3 or 1) then return false,"Remove a crafted modifier or allow more crafted modifiers first." end
	if c.total >= M.capacities(model,state).total then return false,"There is no open modifier slot." end
	for _,entry in ipairs(model.bench) do if not benchReason(model,state,entry.id,c,f) then return true end end
	return false,"No legal bench modifier is available for this item."
end
function M.essenceReason(model,state,id)
	local selected
	for _,entry in ipairs(model.essences) do if entry.id==id then selected=entry;break end end
	if not selected then return "This essence cannot be used on this base" end
	local f=flags(model,state)
	if f.prefixes or f.suffixes or f.explicitAttack or f.explicitCaster then return "Remove meta modifiers before applying an essence" end
	if not (state.rarity=="NORMAL" or state.rarity=="RARE" and (selected.tier>=5 or selected.canReforgeRare)) then return "This essence cannot be used on the current rarity" end
	local metadata=require("Modules.CraftingAdvanced").data().mods
	local function groups(modId) local meta=metadata[modId];return meta and meta.groups or {model.byId[modId].group} end
	for _,entry in ipairs(state.affixes) do if entry.fractured then
		for _,left in ipairs(groups(selected.modId)) do for _,right in ipairs(groups(entry.id)) do if left==right then return "The essence modifier conflicts with a fractured modifier" end end end
	end end
	return nil,selected
end
function M.essenceAvailable(model,state)
	if state.rarity=="MAGIC" then return false,"Essences require a normal or eligible rare item." end
	for _,entry in ipairs(model.essences) do if not M.essenceReason(model,state,entry.id) then return true end end
	return false,"No supported Essence can modify this item in its current state."
end

function M.action(model,input,action,random)
	local state=copyState(input)
	local method=action.method
	if (method=="annul" or method=="chaos" or method=="alteration" or method=="scour" or method=="divine") and M.hasPartialLock(model,state) then selectPartialLocks(model,state,random) end
	local c,f=counts(model,state),flags(model,state)
	if method == "transmute" or method == "alteration" or method == "alchemy" or method == "chaos" then
		local magic=method == "transmute" or method == "alteration"
		local required=(method == "transmute" or method == "alchemy") and "NORMAL" or magic and "MAGIC" or "RARE"
		assert(state.rarity == required,"This currency cannot be used on the current rarity")
		clear(model,state)
		state.rollBlock={attack=f.attack,caster=f.caster}
		state.rarity=magic and "MAGIC" or "RARE"
		local value=random()
		local target=magic and (value < 0.5 and 1 or 2) or (value < 8/12 and 4 or value < 11/12 and 5 or 6)
		target=math.min(target,M.capacities(model,state).total)
		while #state.affixes < target do add(model,state,random) end
	elseif method == "augmentation" or method == "regal" or method == "exalt" then
		assert(state.rarity == (method == "exalt" and "RARE" or "MAGIC"),"This currency cannot be used on the current rarity")
		local capacityState=copyState(state);capacityState.rarity="RARE"
		assert(c.total < (method == "augmentation" and 2 or M.capacities(model,capacityState).total),"The item has no open affix")
		if method == "regal" then state.rarity="RARE" end
		add(model,state,random)
	elseif method == "annul" then
		assert(state.rarity ~= "NORMAL","Annulment requires a magic or rare item")
		local eligible=M.annulCandidates(model,state)
		assert(#eligible > 0,"No modifier can be removed")
		table.remove(state.affixes,eligible[math.floor(random()*#eligible)+1])
	elseif method == "scour" then
		assert(state.rarity ~= "NORMAL","Scouring requires a magic or rare item")
		clear(model,state)
		local left=counts(model,state)
		state.rarity=left.total == 0 and "NORMAL" or left.Prefix <= 1 and left.Suffix <= 1 and "MAGIC" or "RARE"
	elseif method == "divine" then
		assert(state.rarity ~= "NORMAL","Divine requires a magic or rare item")
		for _,entry in ipairs(state.affixes) do if not protected(entry,model.byId[entry.id],f) then entry.legacyLightRadius=nil;entry.range=M.rollRange(model.byId[entry.id],random) end end
	elseif method == "bench" then
		local reason=M.benchReason(model,state,action.modId);assert(not reason,reason)
		local mod=model.byId[action.modId]
		if state.rarity == "NORMAL" then state.rarity="MAGIC" end
		state.affixes[#state.affixes+1]={id=action.modId,range=M.rollRange(mod,random),crafted=true}
	elseif method == "remove_crafted" then
		assert(c.crafted > 0,"The item has no crafted modifiers")
		for i=#state.affixes,1,-1 do if state.affixes[i].crafted then table.remove(state.affixes,i) end end
	elseif method == "essence" then
		local reason,selected=M.essenceReason(model,state,action.essenceId);assert(not reason,reason)
		clear(model,state,true); state.rarity="RARE"
		local mod=model.byId[selected.modId]
		state.affixes[#state.affixes+1]={id=selected.modId,range=M.rollRange(mod,random),description330=model.descriptions330[selected.modId] and true or nil}
		state.maxEssenceModLevel=selected.maxModLevel
		local value=random(); local target=value < 8/12 and 4 or value < 11/12 and 5 or 6
		target=math.min(target,M.capacities(model,state).total)
		while #state.affixes < target do add(model,state,random) end
	else error("Unsupported crafting action: "..tostring(method)) end
	clearPartialLocks(state)
	state.rollBlock=nil
	state.maxEssenceModLevel=nil
	return state
end

local function gemSocketGroups(sockets)
 local groups,previous={},nil
 for _,socket in ipairs(sockets) do
  if socket.color == "A" then previous=nil
  else
   if previous ~= socket.group then groups[#groups+1]={};previous=socket.group end
   local group=groups[#groups];group[#group+1]=socket
  end
 end
 return groups
end

function M.matches(state,targets,rarity,model,requirements,requiredGroups)
 if state.veil or state.destroyed then return false end
 if state.socketLayoutUnknown and requirements and (requirements.sockets~=nil or requirements.links~=nil or requirements.minAbyssSockets~=nil or requirements.socketColours~=nil) then error("Set the unknown socket layout before checking socket or link goals.") end
 if rarity and state.rarity ~= rarity then return false end
 local matched=0
 for _,group in ipairs(targets) do
  local count=0
  local unknown=false
  local entries=state.affixes
  if group.scope == "implicit" then
   entries={};for _,list in ipairs({state.corruptedImplicits or {},state.implicits or {}}) do for _,entry in ipairs(list) do entries[#entries+1]=entry end end
   local active=state.synthRetained
   if active then assert(model and model.synthesisGroups,"A synthesised item model is required for implicit targets") end
   if model and model.synthesisGroups and not active and not state.corruptedImplicits and not state.implicits then active={};for index in ipairs(model.synthesisGroups) do active[#active+1]=index end end
   for _,index in ipairs(active or {}) do local item=model.synthesisGroups[index];if require("Modules.CraftingSynthesisGroups").targetStatus(item,group) then entries[#entries+1]=item.candidates[1] end end
  end
  if group.scope == "enchant" then
   assert(model,"A native item model is required for enchantment targets")
   local ids=state.katakohiEnchants or (not state.harvestEnchant and model.importedSocketEnchants)
   -- An unrecognized import cannot prove either a positive or negative target.
   unknown=not ids
   entries={};for _,id in ipairs(ids or {}) do entries[#entries+1]={id=id,range=1} end
  end
  for _,entry in ipairs(entries) do
   local roll=type(entry.range) == "table" and math.min(unpack(entry.range)) or entry.range or 0.5
   for _,id in ipairs(group.anyOf) do if entry.id == id and roll >= (group.minRoll or 0) and (group.fractured == nil or (entry.fractured or false) == group.fractured) and (group.crafted == nil or (entry.crafted or false) == group.crafted) then count=count+1; break end end
  end
  local hit=count >= (group.atLeast or 1)
  if group.negate and not unknown then hit=not hit end
  if hit then matched=matched+1 end
 end
 if matched < (requiredGroups or #targets) then return false end
 if requirements then
  assert(model,"A native item model is required for property conditions")
  local c=counts(model,state); local caps=M.capacities(model,state)
  local prefix=c.Prefix+(state.veil and state.veil.type == "Prefix" and 1 or 0)
  local suffix=c.Suffix+(state.veil and state.veil.type == "Suffix" and 1 or 0)
  if requirements.openPrefixes and caps.Prefix-prefix < requirements.openPrefixes then return false end
  if requirements.openSuffixes and caps.Suffix-suffix < requirements.openSuffixes then return false end
  if requirements.minAffixes and c.total < requirements.minAffixes or requirements.maxAffixes and c.total > requirements.maxAffixes then return false end
  local fractures=0;for _,entry in ipairs(state.affixes) do if entry.fractured then fractures=fractures+1 end end
  if requirements.minFractured and fractures < requirements.minFractured or requirements.maxFractured and fractures > requirements.maxFractured then return false end
  if requirements.minIntangibility and (state.intangibility or 0) < requirements.minIntangibility or requirements.maxIntangibility and (state.intangibility or 0) > requirements.maxIntangibility then return false end
  if requirements.minQuality and (state.quality or model.item.quality or 0) < requirements.minQuality then return false end
  if requirements.minMemoryStrands and (state.memoryStrands or 0) < requirements.minMemoryStrands then return false end
  if requirements.maxMemoryStrands and (state.memoryStrands or 0) > requirements.maxMemoryStrands then return false end
  if requirements.corrupted ~= nil and (state.corrupted or false) ~= requirements.corrupted then return false end
  if requirements.twiceCorrupted ~= nil and (state.twiceCorrupted or false) ~= requirements.twiceCorrupted then return false end
	  if requirements.influence then
	   local found=false;for _,key in ipairs(state.influences or model.initial.influences or {}) do if key==requirements.influence then found=true;break end end
	   if not found then return false end
	  end
  if requirements.harvestEnchant and state.harvestEnchant~=requirements.harvestEnchant then return false end
  if requirements.nativeStats and not require("Modules.CraftingItemStats").matches(M,model,state,requirements.nativeStats) then return false end
  if requirements.sockets and #(state.sockets or model.item.sockets or {}) < requirements.sockets then return false end
  if requirements.minAbyssSockets then
   local count=0;for _,socket in ipairs(state.sockets or model.item.sockets or {}) do if socket.color=="A" then count=count+1 end end
   if count < requirements.minAbyssSockets then return false end
  end
  if requirements.socketColours then
   local groups={};local needed={}
   for color in requirements.socketColours:gmatch(".") do needed[color]=(needed[color] or 0)+1 end
   local sockets=state.sockets or model.item.sockets or {}
   local segments=requirements.linkedColours and gemSocketGroups(sockets) or {sockets}
   for _,segment in ipairs(segments) do local colors={};groups[#groups+1]=colors;for _,socket in ipairs(segment) do colors[socket.color]=(colors[socket.color] or 0)+1 end end
   local matched=false
   for _,colors in pairs(groups) do local enough=true;for color,count in pairs(needed) do if (colors[color] or 0)<count then enough=false end end;if enough then matched=true;break end end
   if not matched then return false end
  end
  if requirements.links then
   local best=0
   for _,group in ipairs(gemSocketGroups(state.sockets or model.item.sockets or {})) do best=math.max(best,#group) end
   if best < requirements.links then return false end
  end
 end
 return true
end
function M.validateRecipe(recipe)
	assert(type(recipe) == "table" and type(recipe.steps) == "table" and #recipe.steps >= 1 and #recipe.steps <= 20,"Use one to twenty recipe steps")
	assert(type(recipe.targets) == "table" and #recipe.targets <= 6,"Choose up to six target groups")
	assert(#recipe.targets > 0 or recipe.requirements,"Choose targets or item property conditions")
	assert(not recipe.rarity or recipe.rarity == "MAGIC" or recipe.rarity == "RARE","Invalid target rarity")
	local methods={ }
	for _,method in ipairs(M.methods) do methods[method]=true end
	local function validateRequirements(requirements)
		if not requirements then return end
		assert(type(requirements) == "table" and next(requirements),"Choose at least one property condition")
		local limits={openPrefixes=3,openSuffixes=3,minAffixes=6,maxAffixes=6,minQuality=40,sockets=6,links=6,minAbyssSockets=6,minMemoryStrands=100,maxMemoryStrands=100,minFractured=6,maxFractured=6,minIntangibility=100,maxIntangibility=100}
		for key,value in pairs(requirements) do
			if key == "nativeStats" then require("Modules.CraftingItemStats").validate(value)
			elseif key == "harvestEnchant" then assert(type(value)=="string" and require("Modules.CraftingEnchants").data().crafts[value],"Choose a known Harvest enchantment")
			elseif key == "corrupted" or key == "twiceCorrupted" or key == "linkedColours" then assert(type(value) == "boolean","Invalid boolean property condition")
			elseif key == "influence" then assert(({shaper=true,elder=true,adjudicator=true,basilisk=true,crusader=true,eyrie=true})[value],"Choose a supported influence")
			elseif key == "socketColours" then assert(type(value)=="string" and #value>=1 and #value<=6 and not value:find("[^RGBW]"),"Use one to six socket colours: R, G, B or W")
			else integer(value,0,assert(limits[key],"Unknown property condition"),key) end
		end
		assert(not requirements.linkedColours or requirements.socketColours,"Linked colours require a socket colour target")
		assert(not (requirements.corrupted==false and requirements.twiceCorrupted==true),"A twice corrupted item cannot be uncorrupted")
		for _,pair in ipairs({{"minAffixes","maxAffixes"},{"minMemoryStrands","maxMemoryStrands"},{"minFractured","maxFractured"},{"minIntangibility","maxIntangibility"}}) do
			assert(not requirements[pair[1]] or not requirements[pair[2]] or requirements[pair[1]] <= requirements[pair[2]],"Minimum property condition exceeds maximum")
		end
	end
	validateRequirements(recipe.requirements)
	if recipe.requiredGroups then integer(recipe.requiredGroups,0,#recipe.targets,"required target groups") end
	local function validateTargets(targets)
	assert(type(targets) == "table" and #targets >= 1 and #targets <= 6,"Choose one to six target groups")
	for _,group in ipairs(targets) do
		assert(type(group.anyOf) == "table" and #group.anyOf >= 1 and #group.anyOf <= 30,"Use one to thirty modifier IDs per target group")
		for _,id in ipairs(group.anyOf) do assert(type(id) == "string" and #id <= 160,"Invalid target modifier ID") end
		if group.atLeast then integer(group.atLeast,1,6,"matching modifiers") end
		if group.minRoll then assert(type(group.minRoll) == "number" and group.minRoll >= 0 and group.minRoll <= 1,"Invalid minimum roll") end
		assert(not group.scope or group.scope == "explicit" or group.scope == "implicit" or group.scope == "enchant","Invalid target scope")
		for _,key in ipairs({"fractured","crafted"}) do assert(group[key] == nil or type(group[key]) == "boolean","Invalid modifier condition") end
		assert(group.negate == nil or type(group.negate) == "boolean","Invalid exclusion condition")
	end
	end
	if #recipe.targets > 0 then validateTargets(recipe.targets) end
	for _,step in ipairs(recipe.steps) do
		assert(methods[step.method],"Unsupported crafting action: "..tostring(step.method))
		assert(step.onFailureAction==nil or ({route=true,stop=true,restart=true,salvage=true})[step.onFailureAction],"Unknown failure recovery action")
		assert(step.recoveryNotes==nil or type(step.recoveryNotes)=="string" and #step.recoveryNotes<=1000,"Recovery notes are too long")
		integer(step.maxAttempts or 1,1,200,"step attempt limit")
		if (step.maxAttempts or 1) > 1 then assert(step.untilTargets or step.untilRequirements,"Repeated steps need target or property conditions") end
		if step.untilTargets then validateTargets(step.untilTargets) end
		validateRequirements(step.untilRequirements)
		for _,key in ipairs({"onSuccess","onFailure"}) do if step[key] then integer(step[key],1,#recipe.steps+1,"recipe route") end end
	end
	return copyTable(recipe)
end
local function socketGoal(requirements)
	return requirements and (requirements.sockets~=nil or requirements.links~=nil or requirements.minAbyssSockets~=nil or requirements.socketColours~=nil)
end
local function validateCorruptionSocketGoals(model,recipe)
	if M.socketLimit(model,model.initial)==0 then return end
	local socketTarget=socketGoal(recipe.requirements)
	for _,step in ipairs(recipe.steps) do socketTarget=socketTarget or socketGoal(step.untilRequirements) end
	if not socketTarget then return end
	assert(not model.initial.socketLayoutUnknown,"Set the unknown socket layout before checking socket or link goals.")
	for _,step in ipairs(recipe.steps) do
		assert(step.method~="vaal" and not (step.method=="gwennen" and (step.firstOutcome==1012 or step.secondOutcome==1012)),
			"Cannot calculate socket or link goals with Vaal corruption: rare-reroll socket changes are not modeled.")
	end
end
local function priceKey(action) return action.method == "bench" and action.modId or action.method == "essence" and action.essenceId or action.method end

function M.validateState(model,state)
	assert(type(state) == "table" and type(state.affixes) == "table" and #state.affixes <= 6,"Invalid crafting state")
	assert(state.socketLayoutUnknown==nil or type(state.socketLayoutUnknown)=="boolean","Invalid unknown socket layout marker")
	assert(state.rarity == "NORMAL" or state.rarity == "MAGIC" or state.rarity == "RARE","Invalid state rarity")
	local groups,allowed,fractured,legacy={},{},{},{}
	for _,entry in ipairs(model.mods) do allowed[entry.id]=true end
	for _,entry in ipairs(model.bench) do allowed[entry.id]=true end
	for _,entry in ipairs(model.essences) do allowed[entry.modId]=true end
	for _,id in ipairs(model.dropOnlyIds) do allowed[id]=true end
	for _,id in ipairs(model.legacyDelveResistance or {}) do allowed[id]=true end
	for _,entry in ipairs(model.initial.affixes) do allowed[entry.id]=true; if entry.fractured then fractured[entry.id]=true end;if entry.legacyLightRadius then legacy[entry.id]=entry end end
	for _,entry in ipairs(state.affixes) do
		local mod=assert(model.byId[entry.id],"Unknown state modifier")
		assert(allowed[entry.id],"State modifier is unavailable on this base")
		assert(not entry.fractured or fractured[entry.id],"This recipe cannot create fractured modifiers")
		assert((entry.id:match("^bench:") ~= nil) == (entry.crafted == true),"State crafted flag does not match its modifier")
		assert(entry.crafted == nil or type(entry.crafted) == "boolean","Invalid crafted flag")
		assert(entry.fractured == nil or type(entry.fractured) == "boolean","Invalid fractured flag")
		assert(entry.legacyLightRadius == nil or type(entry.legacyLightRadius) == "boolean","Invalid legacy modifier flag")
		assert(entry.description330 == nil or type(entry.description330) == "boolean" and model.descriptions330[entry.id],"Invalid 3.30 modifier description")
		assert(not entry.legacyLightRadius or legacy[entry.id] and model.legacyLightRadius[entry.id],"Legacy Light Radius values must come from the starting item")
		if entry.legacyLightRadius then
			local initial=legacy[entry.id];local current=type(entry.range)=="table" and entry.range or {entry.range or 0.5}
			local original=type(initial.range)=="table" and initial.range or {initial.range or 0.5}
			assert(#current==#original,"Legacy Light Radius rolls cannot be changed without rerolling")
			for index,value in ipairs(current) do assert(value==original[index],"Legacy Light Radius rolls cannot be changed without rerolling") end
		end
		assert(mod.type == "Prefix" or mod.type == "Suffix","Unsupported state modifier type")
		assert(not groups[mod.group],"State has conflicting modifier groups"); groups[mod.group]=true
		local ranges=type(entry.range) == "table" and entry.range or {entry.range or 0.5}
		assert(#ranges >= 1 and #ranges <= 20,"Invalid modifier roll range count")
		for _,value in ipairs(ranges) do assert(type(value) == "number" and value == value and math.abs(value) <= 100,"Invalid modifier roll range") end
	end
	local c=counts(model,state)
	local caps=M.capacities(model,state)
	assert(c.Prefix <= caps.Prefix and c.Suffix <= caps.Suffix and (state.rarity ~= "NORMAL" or c.total == 0),"State exceeds rarity affix limits")
	return copyState(state)
end

function M.validateTargetAvailability(model,targets,steps)
	local available={}
	for _,entry in ipairs(model.mods) do available[entry.id]=true end
	for _,entry in ipairs(model.bench) do available[entry.id]=true end
	for _,entry in ipairs(model.essences) do available[entry.modId]=true end
	for _,entry in ipairs(model.initial.affixes) do available[entry.id]=true end
	for _,id in ipairs(model.dropOnlyIds or {}) do available[id]=true end
	for _,id in ipairs(model.legacyDelveResistance or {}) do available[id]=true end
	for id in pairs(model.special or {}) do available[id]=true end
	for _,step in ipairs(steps or {}) do if (step.method=="recombine" or step.method=="recombine_predictable") and step.donorItem then
		local donor=M.model(step.donorItem)
		for _,entry in ipairs(donor.mods) do available[entry.id]=true end
		for _,entry in ipairs(donor.initial.affixes) do available[entry.id]=true end
	end end
	local function check(groups) for _,group in ipairs(groups) do for _,id in ipairs(group.anyOf) do assert(available[id],"Target modifier ID is unavailable for this base: "..id) end end end
	check(targets)
	for _,step in ipairs(steps or {}) do if step.untilTargets then check(step.untilTargets) end end
end

function M.simulate(raw,recipe,options)
	options=options or { }
	for _,key in ipairs({"prices","actionPrices"}) do if options[key]~=nil then assert(type(options[key])=="table","Invalid supplied prices") end end
	local suppliedPrices=options.prices and next(options.prices)~=nil or false
	local suppliedActions=options.actionPrices and next(options.actionPrices)~=nil or false
	if options.priceBook or options.prices or options.actionPrices then options=copyTable(options) end
	if options.priceBook then
		options.priceBook=require("Modules.CraftingPrices").validate(options.priceBook)
		options.currency=options.currency or options.priceBook.currency
	end
	recipe=M.validateRecipe(recipe)
	for _,step in ipairs(recipe.steps) do
		if step.method=="recombine_predictable" then
			assert(type(step.observedRecipientState)=="table","Predictable recombination recipes require the recipient state used for the observed success percentage")
		end
	end
	local trials=integer(options.trials or 200,1,2000,"trial count")
	local baseCost=options.baseCost or 0
	assert(type(baseCost) == "number" and baseCost == baseCost and baseCost >= 0 and baseCost <= 1e12,"Invalid starting item cost")
	assert(baseCost == 0 or type(options.currency) == "string" and #options.currency > 0,"Name the currency for the starting item cost")
	local retain=integer(options.retainSuccesses or 0,0,100,"retained successful items")
	local maxActions=integer(options.maxActions or 100,1,2000,"action budget")
	assert(trials*maxActions <= 20000,"Use at most 20000 total budgeted actions per simulation")
	local seed=integer(options.seed or 104729,1,2147483646,"seed")
	if suppliedPrices or suppliedActions then assert(type(options.currency) == "string" and options.currency:match("%S"),"Specify a common currency for supplied prices") end
	for key,value in pairs(options.prices or { }) do assert(type(key) == "string" and type(value) == "number" and value == value and value >= 0 and value <= 1e12,"Invalid currency price") end
	local actionPriceCount=0
	for key,value in pairs(options.actionPrices or {}) do
		assert(type(key)=="string" and #key>0 and #key<=1024 and not key:find("[%c]") and type(value)=="number" and value==value and value>=0 and value<=1e12,"Invalid action price")
		actionPriceCount=actionPriceCount+1
	end
	assert(actionPriceCount<=100,"Use at most 100 action price overrides")
	local model=M.model(raw)
	if options.initialState or recipe.initialState then model.initial=M.validateState(model,options.initialState or recipe.initialState) end
	validateCorruptionSocketGoals(model,recipe)
	if options.priceBook or options.prices then
		options.prices=require("Modules.CraftingPrices").forSimulation(options.priceBook,options.currency,M.context(model,model.initial),options.prices)
	end
	M.validateTargetAvailability(model,recipe.targets,recipe.steps)
	for _,step in ipairs(recipe.steps) do
		if (step.method == "ducat_kishara" or step.method == "ducat_katakohi") and not step.allflame then step.allflame={auto=true,upgradeTier=2} end
		if step.allflame and not step.allflame.preferredTargets and #recipe.targets > 0 then step.allflame.preferredTargets=copyTable(step.untilTargets or recipe.targets) end
	end
	local successes,totalCost,totalActions,totalExecuted=0,0,0,0
	local spent,missing,errors,times={},{},{},{}
	local resourceUsage={}
	local pricing=require("Modules.CraftingPrices")
	local actionPriceUses=0
	local actionHistogram,executedHistogram,costHistogram,costSamples,successfulCosts,routes={},{},{},{},{},{}
	local budgetExhausted,destroyedTrials=0,0
	local recovery={restarts=0,stopped=0,salvaged=0}
	local sample,sampleSuccess
	local retained,affixDistribution,propertyDistribution={},{},{affixes={},fractured={},intangibility={},memoryStrands={}}
	for trial=1,trials do
		if options.checkpoint then options.checkpoint({trial=trial,trials=trials,successes=successes}) end
		local state=copyState(model.initial)
		local random=rng(encounter.seed(seed,trial,31))
		local at,actions,cost,trialExecuted=1,0,baseCost,0
		local trialUnpriced=false
		while at <= #recipe.steps and actions < maxActions and not state.destroyed and (options.forceFirstAction and actions == 0 or not M.matches(state,recipe.targets,recipe.rarity,model,recipe.requirements,recipe.requiredGroups)) do
			local step=recipe.steps[at]
			local route=routes[at] or {visits=0,success=0,failure=0,executed=0};routes[at]=route;route.visits=route.visits+1
			local success=false
			for _=1,(step.maxAttempts or 1) do
				if actions >= maxActions then break end
				if options.checkpoint then options.checkpoint({trial=trial,trials=trials,actions=actions,successes=successes}) end
				actions=actions+1
				local before=state
				local ok,nextState=pcall(M.action,model,state,step,random)
				if not ok then local message=tostring(nextState):match("[^:]+$") or tostring(nextState); errors[message]=(errors[message] or 0)+1; break end
				state=nextState
				trialExecuted=trialExecuted+1
				route.executed=route.executed+1
				totalExecuted=totalExecuted+1
				local setupKey=(M.priceKey or priceKey)(step)
				local actionPrice=options.actionPrices and options.actionPrices[setupKey]
				if actionPrice~=nil then actionPriceUses=actionPriceUses+1 end
				local ingredients=M.components and M.components(step,before,model) or {[setupKey]=1}
				local context=M.context(model,before)
				for key,amount in pairs(ingredients) do
					local canonical=pricing.key(key,context)
					local entry=resourceUsage[canonical]
					if not entry then
						local name,_,kind=pricing.describe(canonical,context,step)
						entry={key=canonical,name=name,kind=kind=="Whole action" and "service" or "resource",amount=0};resourceUsage[canonical]=entry
					end
					entry.amount=entry.amount+amount
				end
				local components=(actionPrice~=nil or options.prices and options.prices[setupKey]~=nil) and {[setupKey]=1} or ingredients
				-- Resource quotes for the service or currency do not include the
				-- consumed donor. Only an explicit whole-action price includes it.
				if actionPrice==nil and components~=ingredients then for key,amount in pairs(ingredients) do if key:match("^donor:") then components[key]=amount end end end
				for key,amount in pairs(components) do
					spent[key]=(spent[key] or 0)+amount
					local price=actionPrice~=nil and actionPrice or options.prices and options.prices[key]
					if price then cost=cost+price*amount else missing[key]=true;trialUnpriced=true end
				end
				if state.destroyed then break end
				if M.matches(state,recipe.targets,recipe.rarity,model,recipe.requirements,recipe.requiredGroups) then success=true;break end
				if not (step.untilTargets or step.untilRequirements) or M.matches(state,step.untilTargets or {},nil,model,step.untilRequirements) then success=true; break end
			end
			route[success and "success" or "failure"]=route[success and "success" or "failure"]+1
			if not success and step.onFailureAction=="restart" then
				if actions<maxActions then recovery.restarts=recovery.restarts+1;state=copyState(model.initial);cost=cost+baseCost end;at=1
			elseif not success and (step.onFailureAction=="stop" or step.onFailureAction=="salvage") then
				local key=step.onFailureAction=="stop" and "stopped" or "salvaged";recovery[key]=recovery[key]+1;at=#recipe.steps+1
			else at=success and (step.onSuccess or at+1) or (step.onFailure or at+1) end
		end
		local hit=(not options.forceFirstAction or trialExecuted>0) and M.matches(state,recipe.targets,recipe.rarity,model,recipe.requirements,recipe.requiredGroups)
		if hit then successes=successes+1; times[#times+1]=actions end
		if hit and #retained < retain then retained[#retained+1]={trial=trial,actions=actions,cost=not trialUnpriced and cost or nil,state=copyTable(state),itemText=M.itemText(model,state)} end
		local fractures=0
		for _,entry in ipairs(state.affixes) do
			local bucket=affixDistribution[entry.id] or {trials=0,successes=0,fractured=0,crafted=0};affixDistribution[entry.id]=bucket
			bucket.trials=bucket.trials+1;if hit then bucket.successes=bucket.successes+1 end
			if entry.fractured then bucket.fractured=bucket.fractured+1;fractures=fractures+1 end
			if entry.crafted then bucket.crafted=bucket.crafted+1 end
		end
		if not state.destroyed then
			for key,value in pairs({affixes=#state.affixes,fractured=fractures,intangibility=state.intangibility or 0,memoryStrands=state.memoryStrands or 0}) do
				local histogram=propertyDistribution[key];histogram[value]=(histogram[value] or 0)+1
			end
		end
		if state.destroyed then destroyedTrials=destroyedTrials+1 end
		if not hit and not state.destroyed and at <= #recipe.steps and actions >= maxActions then budgetExhausted=budgetExhausted+1 end
		local bucket=actionHistogram[actions] or {actions=actions,trials=0,successes=0};actionHistogram[actions]=bucket;bucket.trials=bucket.trials+1;if hit then bucket.successes=bucket.successes+1 end
		local executed=executedHistogram[trialExecuted] or {actions=trialExecuted,trials=0,successes=0};executedHistogram[trialExecuted]=executed;executed.trials=executed.trials+1;if hit then executed.successes=executed.successes+1 end
		costSamples[#costSamples+1]=cost;if hit then successfulCosts[#successfulCosts+1]=cost end
		local costBucket=costHistogram[cost] or {cost=cost,trials=0,successes=0};costHistogram[cost]=costBucket;costBucket.trials=costBucket.trials+1;if hit then costBucket.successes=costBucket.successes+1 end
		if not sample or hit and not sampleSuccess then sample,sampleSuccess=state,hit end
		totalActions=totalActions+actions; totalCost=totalCost+cost
	end
	local low,high=encounter.wilson(successes,trials)
	local function quantiles(values)
		if #values == 0 then return nil end
		table.sort(values)
		local result={};for _,percent in ipairs({10,25,50,75,90,95,99}) do result["p"..percent]=values[math.max(1,math.ceil(#values*percent/100))] end
		return result
	end
	local distribution={};for _,bucket in pairs(actionHistogram) do distribution[#distribution+1]=bucket end;table.sort(distribution,function(a,b) return a.actions < b.actions end)
	local executedDistribution={};for _,bucket in pairs(executedHistogram) do executedDistribution[#executedDistribution+1]=bucket end;table.sort(executedDistribution,function(a,b) return a.actions < b.actions end)
	local usage={};for _,entry in pairs(resourceUsage) do entry.meanPerTrial=entry.amount/trials;usage[#usage+1]=entry end;table.sort(usage,function(a,b) return a.key<b.key end)
	assert(totalExecuted > 0 or successes > 0,next(errors) or "Recipe could not execute a supported action; inspect its starting rarity and open affixes")
	local result={trials=trials,successes=successes,successChance=successes/trials*100,confidenceLow=low,confidenceHigh=high,seed=seed,maxActions=maxActions,
		meanActions=totalActions/trials,meanExecutedActions=totalExecuted/trials,failedAttempts=totalActions-totalExecuted,executedActionDistribution=executedDistribution,currencySpent=spent,resourceUsage=usage,unpriced=missing,transitionErrors=errors,warnings=M.hasPartialLock(M.context(model,model.initial),model.initial) and partialWarning(M.recipeWarnings(recipe,model)) or M.recipeWarnings(recipe,model),limitations=copyTable(M.limits),sampleSuccess=sampleSuccess,sampleItem=M.itemText(model,sample),sampleState=sample,
		engineVersion=2,dataPatch=M.dataPatch,sourceVersion=launch.versionNumber,costCurrency=options.currency or "supplied price units",
		baseCost=baseCost,retainedSuccesses=retained,retentionLimit=retain,affixDistribution=affixDistribution,propertyDistribution=propertyDistribution,actionDistribution=distribution,successfulActionQuantiles=quantiles(times),routeCounts=routes,budgetExhausted=budgetExhausted,destroyedTrials=destroyedTrials}
	if model.initial.socketLayoutUnknown then unknownSocketWarning(result.warnings) end
	if not next(missing) then
		result.meanCost=totalCost/trials;result.costPerSuccess=successes>0 and totalCost/successes or nil;result.spendingQuantiles=quantiles(costSamples);result.successfulSpendingQuantiles=quantiles(successfulCosts)
		result.costDistribution={};for _,bucket in pairs(costHistogram) do result.costDistribution[#result.costDistribution+1]=bucket end;table.sort(result.costDistribution,function(a,b) return a.cost<b.cost end)
	end
	if options.priceBook then result.priceSource=options.priceBook.source;result.priceQuotedAt=options.priceBook.quotedAt end
	result.stepPriceKeys={}
	for i,step in ipairs(recipe.steps) do result.stepPriceKeys[#result.stepPriceKeys+1]={step=i,method=step.method,priceKey=(M.priceKey or priceKey)(step)} end
	result.priceOverridesSupplied=suppliedPrices or suppliedActions
	result.resourcePriceOverridesSupplied=suppliedPrices
	result.actionPriceOverridesSupplied=suppliedActions;result.actionPriceOverridesApplied=actionPriceUses
	result.recovery=recovery
	return M.withTreeContext(result,options.treeVersion)
end

function M.perform(raw,action,seed,initialState,treeVersion)
	local model=M.model(raw)
	if initialState then model.initial=M.validateState(model,initialState) end
	local state,details=M.action(model,model.initial,action,rng(encounter.seed(integer(seed or 104729,1,2147483646,"seed"),1,31)))
	local warnings=M.actionWarnings(action,model)
	if state.socketLayoutUnknown then unknownSocketWarning(warnings) end
	if M.hasPartialLock(M.context(model,model.initial),model.initial) then partialWarning(warnings) end
	return M.withTreeContext({priceKey=(M.priceKey or priceKey)(action),itemText=M.itemText(model,state),state=state,choices=details and details.choices,allflame=details and details.allflame,gwennen=details and details.gwennen,dataPatch=M.dataPatch,warnings=warnings,limitations=copyTable(M.limits)},treeVersion)
end

function M.catalog(raw,query,limit)
	local model=M.model(raw)
	query=(query or ""):lower(); limit=limit or 50
	local result={methods=copyTable(M.methods),methodWarnings={},modifiers={},bench={},essences={},limitations=copyTable(M.limits)}
	for _,method in ipairs(M.methods) do local warnings=M.actionWarnings({method=method},model);if #warnings>0 then result.methodWarnings[method]=warnings end end
	for _,entry in ipairs(model.mods) do if #result.modifiers < limit and (entry.id.." "..table.concat(entry.mod," / ")):lower():find(query,1,true) then result.modifiers[#result.modifiers+1]={id=entry.id,text=table.concat(entry.mod," / "),level=entry.mod.level,type=entry.mod.type,weight=entry.weight,group=entry.mod.group} end end
	for _,entry in ipairs(model.bench) do if #result.bench < limit and (entry.id.." "..table.concat(entry.mod," / ")):lower():find(query,1,true) then result.bench[#result.bench+1]={id=entry.id,text=table.concat(entry.mod," / "),type=entry.mod.type} end end
	for _,entry in ipairs(model.essences) do if #result.essences < limit and entry.name:lower():find(query,1,true) then result.essences[#result.essences+1]=copyTable(entry) end end
	return result
end
M.rollRange=rollRange
function M.capacities(model,state)
 local prefix,suffix=3,3
 if model.item.type == "Jewel" then prefix,suffix=2,2 end
 if model.item.type == "Jewel" and model.item.base.subType == "Abyss" and state.corrupted then prefix,suffix=3,3 end
 if model.item.type == "Flask" or model.item.type == "Tincture" then prefix,suffix=1,1 end
 if state.rarity == "MAGIC" then prefix,suffix=1,1 end
 local active={}
 if state.corruptedImplicits or state.implicits then
  for _,index in ipairs(state.synthRetained or {}) do for _,line in ipairs(model.synthesisGroups[index]) do active[#active+1]=line end end
  for _,list in ipairs({state.corruptedImplicits or {},state.implicits or {}}) do for _,entry in ipairs(list) do
   for _,line in ipairs(M.rolledLines(M.entryMod(model,entry),entry.range)) do active[#active+1]={line=line} end
  end end
 else active=model.item.implicitModLines or {} end
 for _,line in ipairs(active) do
  local value=tonumber(line.line:match("(%d+) additional Prefix"));if value then prefix=prefix+value end
  value=tonumber(line.line:match("(%d+) fewer Prefix"));if value then prefix=prefix-value end
  value=tonumber(line.line:match("(%d+) additional Suffix"));if value then suffix=suffix+value end
  value=tonumber(line.line:match("(%d+) fewer Suffix"));if value then suffix=suffix-value end
 end
 prefix,suffix=math.max(0,prefix),math.max(0,suffix)
 return {Prefix=prefix,Suffix=suffix,total=prefix+suffix}
end
require("Modules.CraftingAdvanced").extend(M,{counts=counts,flags=flags,clear=clear,protected=protected,selectPartialLocks=selectPartialLocks,clearPartialLocks=clearPartialLocks,add=add,integer=integer,priceKey=priceKey})
local allflameConfigurationReason=M.configurationReason
local cachedDonorText,cachedDonorModel
function M.configurationReason(model,state,craft)
	if craft.method=="gwennen" then
		local valid=pcall(require("Modules.CraftingGwennen").validate,craft)
		if not valid then return "Configure a supported Gwennen pair and valid artifact cost in Craft settings." end
	end
	if craft.method=="awakener" or craft.method=="recombine" or craft.method=="recombine_predictable" then
		if type(craft.donorItem)~="string" or not craft.donorItem:match("%S") then return "Configure a donor item in Craft settings." end
		if cachedDonorText~=craft.donorItem then
			cachedDonorText=craft.donorItem;local ok,donor=pcall(M.model,craft.donorItem);cachedDonorModel=ok and donor or nil
		end
		if not cachedDonorModel then return "The donor item could not be read. Choose a valid donor in Craft settings." end
		if craft.method=="awakener" then
			local reason=M.awakenerDonorReason(M.context(model,state),state,cachedDonorModel)
			if reason then return reason..". Update the donor in Craft settings." end
		else
			local donor=cachedDonorModel
			if not M.sameRecombinationClass(M.context(model,state).item,donor.item) then return "Recombination requires the same item class. Update the donor in Craft settings." end
			if donor.initial.corrupted or donor.initial.mirrored or donor.item.synthesised then return "Donor must be uncorrupted, non-mirrored and non-synthesised. Update the donor in Craft settings." end
			if craft.method=="recombine_predictable" then
				if donor.initial.destroyed or donor.initial.veil then return "Use a donor without a pending unveil. Update the donor in Craft settings." end
				if M.hasPartialLock(donor,donor.initial) then return "Predictable recombination with a partial affix lock on the donor is not yet modeled. Update the donor in Craft settings." end
			end
		end
	end
	return allflameConfigurationReason(model,state,craft)
end
require("Modules.CraftingCalculator").extend(M)
do
	local calculate=M.calculate
	function M.calculate(raw,craft,targets,initialState,options)
		if socketGoal(options and options.requirements) and (craft.method=="vaal" or craft.method=="gwennen" and (craft.firstOutcome==1012 or craft.secondOutcome==1012)) then
			local checkedModel=M.model(raw);if initialState then checkedModel.initial=M.validateState(checkedModel,initialState) end
			validateCorruptionSocketGoals(checkedModel,{steps={craft},requirements=options.requirements})
		end
		local result=calculate(raw,craft,targets,initialState,options)
		if not result.warnings or not result.sampled and targets and #targets>0 then
			local model=M.model(raw);if initialState then model.initial=M.validateState(model,initialState) end
			if not result.sampled and targets and #targets>0 then M.validateTargetAvailability(model,targets,{craft}) end
			if not result.warnings then result.warnings=M.actionWarnings(craft,model) end
		end
		if initialState then for _,entry in ipairs(initialState.affixes or {}) do if entry.id:match("^bench:partial%-") then partialWarning(result.warnings);break end end end
		if initialState and initialState.socketLayoutUnknown then unknownSocketWarning(result.warnings) end
		if raw:find("Modifier cannot be changed",1,true) or raw:find("Modifiers cannot be changed",1,true) then partialWarning(result.warnings) end
		return M.withTreeContext(result,options and options.treeVersion)
	end
	local catalog=M.catalog
	function M.catalog(raw,query,limit,initialState,treeVersion)
		local result=catalog(raw,query,limit,initialState)
		result.gwennenReference=require("Modules.CraftingGwennenReference").search(query,limit)
		return M.withTreeContext(result,treeVersion)
	end
	local optimize=M.optimizeFossils
	function M.optimizeFossils(raw,targets,options)
		return M.withTreeContext(optimize(raw,targets,options),options and options.treeVersion)
	end
end
-- Extensions register state prerequisites once for both execution and browsing.
local partialLockActions={recombine=true,bench=true,bench_reroll=true,remove_crafted=true,annul=true,chaos=true,alteration=true,scour=true,divine=true,exalt=true,augmentation=true,regal=true,harvest_reforge=true,harvest_augment=true,harvest_resistance=true,harvest_damage=true,beast_imprint=true,beast_talisman_imprint=true,
	socket_bench=true,socket_white_bench=true,socket_colour_bench=true,vorici_socket_count=true,vorici_socket_colours=true,chromatic=true,beast_max_links=true,ducat_ukatoa=true,ducat_katakohi=true,jeweller=true,fusing=true,omen_jeweller=true,omen_connections=true,omen_trichromatism=true,tainted_chromatic=true,tainted_jeweller=true,tainted_fusing=true,
	quality=true,tainted_quality=true,catalyst=true,tainted_catalyst=true,blessed=true,sacred=true,harvest_enchant=true,bench_remove_enchant=true,eldritch_implicit=true,conflict=true}
local socketDependent={socket_bench=true,socket_white_bench=true,socket_colour_bench=true,vorici_socket_count=true,vorici_socket_colours=true,chromatic=true,beast_max_links=true,jeweller=true,fusing=true,omen_jeweller=true,omen_connections=true,omen_trichromatism=true,tainted_chromatic=true,tainted_jeweller=true,tainted_fusing=true,vaal=true,locus=true,binding=true,gwennen=true,fossil=true,ducat_katakohi=true,recombine=true,recombine_predictable=true}
function M.methodReason(model,state,method)
	if state.socketLayoutUnknown and socketDependent[method] then return "Set the unknown socket layout before using this action." end
	if M.hasPartialLock(M.context(model,state),state) and not partialLockActions[method] then
		return "This action is not yet modeled with partial affix locks."
	end
	local check=M.methodChecks[method]
	if check then return check(M.context(model,state),state) end
end
local transition=M.action
local function abyssModifier(state)
	for _,entry in ipairs(state.affixes or {}) do if entry.id=="DelveAbyssJewelSocket1" then return true end end
	return false
end
-- Socket placement and restoration are explicit assumptions; keep the actual
-- simulated socket layout consistent with the modifier instead of retaining a
-- false full link. Existing unusual layouts are not rewritten on import.
function M.syncAbyssSocket(before,after)
	if after.destroyed or abyssModifier(before)==abyssModifier(after) then return end
	local sockets=after.sockets or {};after.sockets=sockets
	local group=0;for _,socket in ipairs(sockets) do group=math.max(group,socket.group+1) end
	if abyssModifier(after) then
		for _,socket in ipairs(sockets) do if socket.color=="A" then return end end
		if #sockets==0 then sockets[1]={color="A",group=group}
		else sockets[#sockets]={color="A",group=group} end
	else
		local replaced=false
		for i=#sockets,1,-1 do if sockets[i].color=="A" then sockets[i]={color="W",group=group};replaced=true;break end end
		if not replaced then return end
	end
	local previous,normalized=nil,-1
	for _,socket in ipairs(sockets) do local old=socket.group;if old~=previous then normalized=normalized+1;previous=old end;socket.group=normalized end
	return true
end
function M.action(model,state,craft,random)
	if type(state)=="table" and type(craft)=="table" then local reason=M.methodReason(model,state,craft.method);assert(not reason,reason) end
	local result,details=transition(model,state,craft,random)
	local function startingState(candidate)
		if not candidate.destroyed and candidate.baseItem and (craft.method=="recombine" or craft.method=="recombine_predictable") then return M.context(model,candidate).initial end
		return state
	end
	local updated=M.syncAbyssSocket(startingState(result),result)
	if details and details.choices then for _,choice in ipairs(details.choices) do
		if choice.state and (M.syncAbyssSocket(startingState(choice.state),choice.state) or updated and choice.state==result) then choice.itemText=M.itemText(model,choice.state) end
	end end
	return result,details
end
return M
