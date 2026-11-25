-- Intrinsic item goals use the same native properties as the workbench cards.
local M={}
M.fields={
	{"PhysicalDPS","Physical DPS"},{"ElementalDPS","Elemental DPS"},
	{"ChaosDPS","Chaos DPS"},{"TotalDPS","Total weapon DPS"},
	{"AttackRate","Attacks per second"},{"CritChance","Critical chance (%)"},
	{"Armour","Armour"},{"Evasion","Evasion"},
	{"EnergyShield","Energy shield"},{"Ward","Ward"},
	{"ItemLife","Flat life"},{"ItemMana","Flat mana"},
	{"ItemFireResist","Fire resistance (%)"},{"ItemColdResist","Cold resistance (%)"},
	{"ItemLightningResist","Lightning resistance (%)"},{"ItemChaosResist","Chaos resistance (%)"},
	{"ItemStrength","Strength"},{"ItemDexterity","Dexterity"},
	{"ItemIntelligence","Intelligence"},{"ItemAccuracy","Accuracy"},
	{"ItemSpellSuppression","Spell suppression (%)"},{"ItemAttackBlock","Attack block from mods (%)"},
	{"ItemSpellBlock","Spell block from mods (%)"},{"ItemAvoidElementalAilments","Avoid elemental ailments (%)"},
	{"ItemAvoidShock","Avoid shock (%)"},{"ItemAvoidFreeze","Avoid freeze (%)"},
	{"ItemAvoidIgnite","Avoid ignite (%)"},{"ItemAvoidChill","Avoid chill (%)"},
	{"ItemAvoidBleed","Avoid bleeding (%)"},{"ItemAvoidPoison","Avoid poison (%)"},
	{"ItemAvoidAllHitDamage","Avoid all hit damage (%)"},{"ItemAvoidPhysicalHitDamage","Avoid physical hit damage (%)"},
	{"ItemAvoidFireHitDamage","Avoid fire hit damage (%)"},{"ItemAvoidColdHitDamage","Avoid cold hit damage (%)"},
	{"ItemAvoidLightningHitDamage","Avoid lightning hit damage (%)"},{"ItemAvoidChaosHitDamage","Avoid chaos hit damage (%)"},
}
local known={};for _,field in ipairs(M.fields) do known[field[1]]=true end
local flat={Life="ItemLife",Mana="ItemMana",FireResist="ItemFireResist",ColdResist="ItemColdResist",LightningResist="ItemLightningResist",ChaosResist="ItemChaosResist",Str="ItemStrength",Dex="ItemDexterity",Int="ItemIntelligence",Accuracy="ItemAccuracy"}
flat.SpellSuppressionChance="ItemSpellSuppression";flat.BlockChance="ItemAttackBlock";flat.SpellBlockChance="ItemSpellBlock"
flat.AvoidElementalAilments="ItemAvoidElementalAilments";flat.AvoidShock="ItemAvoidShock";flat.AvoidFreeze="ItemAvoidFreeze";flat.AvoidIgnite="ItemAvoidIgnite";flat.AvoidChill="ItemAvoidChill";flat.AvoidBleed="ItemAvoidBleed";flat.AvoidPoison="ItemAvoidPoison"
flat.AvoidAllDamageFromHitsChance="ItemAvoidAllHitDamage";flat.AvoidPhysicalDamageChance="ItemAvoidPhysicalHitDamage";flat.AvoidFireDamageChance="ItemAvoidFireHitDamage";flat.AvoidColdDamageChance="ItemAvoidColdHitDamage";flat.AvoidLightningDamageChance="ItemAvoidLightningHitDamage";flat.AvoidChaosDamageChance="ItemAvoidChaosHitDamage"
local flatKeys={};for _,key in pairs(flat) do flatKeys[key]=true end
function M.validate(goals)
	assert(type(goals)=="table" and next(goals),"Choose at least one minimum item stat")
	for key,value in pairs(goals) do
		assert(known[key],"Unknown item stat")
		assert(type(value)=="number" and value==value and value>=0 and value<=10000000,"Enter a minimum item stat between 0 and 10000000")
	end
	return goals
end
function M.itemValues(item)
	local weapon=item.weaponData and item.weaponData[1];local result={}
	for i,field in ipairs(M.fields) do if i<=10 then
		local key=field[1];local source=i<=6 and weapon or i>6 and item.armourData
		if source then result[key]=source[key] or 0 end
	end end
	-- A partially parsed line could contain an additional stat. Do not turn an
	-- incomplete item into a definite zero or claim a complete total.
	for _,name in ipairs({"implicitModLines","explicitModLines","enchantModLines","scourgeModLines","crucibleModLines"}) do
		for _,line in ipairs(item[name] or {}) do
			if not line.disabled and item:CheckModLineVariant(line) and line.extra and line.extra~="" then return result end
		end
	end
	local function totals(mods)
		local values={};for key in pairs(flatKeys) do values[key]=0 end
		local function add(key,value)
			if type(value)~="number" or value~=value or math.abs(value)==math.huge then values[key]=nil
			elseif values[key]~=nil then values[key]=values[key]+value end
		end
		for _,mod in ipairs(mods) do
			if mod.type=="BASE" and (mod.flags or 0)==0 and (mod.keywordFlags or 0)==0 and mod[1]==nil then
				local key=flat[mod.name];if key then add(key,mod.value) end
				if mod.name=="ElementalResist" then for _,element in ipairs({"ItemFireResist","ItemColdResist","ItemLightningResist"}) do add(element,mod.value) end end
				if mod.name=="AvoidElementalAilments" or mod.name=="AvoidAilments" then
					for _,ailment in ipairs({"ItemAvoidShock","ItemAvoidFreeze","ItemAvoidIgnite","ItemAvoidChill"}) do add(ailment,mod.value) end
				end
				if mod.name=="AvoidAilments" then for _,ailment in ipairs({"ItemAvoidElementalAilments","ItemAvoidBleed","ItemAvoidPoison"}) do add(ailment,mod.value) end end
				if mod.name=="AvoidAllDamageFromHitsChance" then for _,kind in ipairs({"ItemAvoidPhysicalHitDamage","ItemAvoidFireHitDamage","ItemAvoidColdHitDamage","ItemAvoidLightningHitDamage","ItemAvoidChaosHitDamage"}) do add(kind,mod.value) end end
			end
		end
		return values
	end
	local lists={};if item.modList then lists[1]=item.modList elseif item.slotModList then for _,mods in pairs(item.slotModList) do lists[#lists+1]=mods end end
	if #lists>0 then
		local values=totals(lists[1]);for i=2,#lists do local other=totals(lists[i]);for key in pairs(flatKeys) do if values[key]~=other[key] then values[key]=nil end end end
		for key,value in pairs(values) do result[key]=value end
	end
	return result
end
function M.values(sim,model,state)
	if state.destroyed or state.veil then return {} end
	return M.itemValues(sim.toItem(model,state))
end
function M.matchesValues(values,goals)
	for key in pairs(goals) do if flatKeys[key] and values[key]==nil then error("Flat item bonuses cannot be determined from this item's unparsed or slot-dependent modifiers.",0) end end
	for key,minimum in pairs(goals) do if values[key]==nil or values[key]<minimum then return false end end
	return true
end
function M.matches(sim,model,state,goals) return M.matchesValues(M.values(sim,model,state),goals) end
return M
