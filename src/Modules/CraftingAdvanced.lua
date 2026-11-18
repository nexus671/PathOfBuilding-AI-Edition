-- cspell:ignore Ukatoa Katakohi
-- Independent rules layered on native PoB modifiers. No third-party engine code.
-- cspell:ignore jsontype
local json=require("dkjson")
local A={}
local cached
local function finishData(data)
	assert(data.patch=="3.30.0.2.2" and type(data.mods)=="table" and type(data.bench)=="table" and #data.bench==782 and type(data.benchMods)=="table","Invalid crafting data")
	data.modifierPatch=data.patch;data.benchPatch=data.patch
	return data
end
local function readData(name)
	local root=GetScriptPath();local f=assert(io.open((root ~= "" and root.."/" or "").."Data/Crafting/"..name,"rb"))
	local raw=f:read("*a");f:close();return raw
end
function A.data()
	if not cached then
		cached=finishData(assert(json.decode(readData("3.30.json"))))
	end
	return cached
end
-- Decode the large generated catalogue in bounded batches when a caller can
-- yield between frames. Publish it only after the whole document is valid.
function A.prepare(checkpoint)
	if cached then return end
	local raw=readData("3.30.json");local pos=1;local started=os.clock()
	local function space() pos=raw:find("%S",pos) or #raw+1 end
	local function expect(char) space();assert(raw:sub(pos,pos)==char,"Invalid crafting data at "..pos);pos=pos+1 end
	local function value()
		space();local result,nextPos,err=json.decode(raw,pos);assert(not err,err);pos=nextPos;return result
	end
	local function pause()
		if os.clock()-started>=0.008 then checkpoint();started=os.clock() end
	end
	local function container()
		space();local opening=raw:sub(pos,pos)
		if opening~="{" and opening~="[" then return value() end
		pos=pos+1;local object=opening=="{";local closing=object and "}" or "]"
		local result=setmetatable({},{__jsontype=object and "object" or "array"});local index=0;space()
		if raw:sub(pos,pos)==closing then pos=pos+1;return result end
		while true do
			if object then local key=value();assert(type(key)=="string","Invalid crafting data key");expect(":");result[key]=value()
			else index=index+1;result[index]=value() end
			pause();space();local char=raw:sub(pos,pos);pos=pos+1
			if char==closing then break end
			assert(char==",","Invalid crafting data at "..(pos-1))
		end
		return result
	end
	local function document()
		expect("{");local result=setmetatable({},{__jsontype="object"});space()
		if raw:sub(pos,pos)~="}" then repeat
			local key=value();assert(type(key)=="string","Invalid crafting data key");expect(":");result[key]=container();pause();space()
			local char=raw:sub(pos,pos);pos=pos+1
			if char=="}" then break end
			assert(char==",","Invalid crafting data at "..(pos-1))
		until false else pos=pos+1 end
		space();assert(pos>#raw,"Trailing crafting data");return result
	end
	local result=document();cached=cached or finishData(result)
end
local methods={
	fossil="Fossil resonator",harvest_reforge="Harvest: reforge with a tagged modifier",harvest_augment="Harvest: add tagged / remove random",
	harvest_resistance="Harvest: change elemental resistance",harvest_damage="Harvest: change elemental damage",fracture="Fracturing Orb",influence_exalt="Influenced Exalted Orb",awakener="Awakener's Orb",
	veiled_orb="Veiled Exalted Orb",veiled_chaos="Veiled Chaos Orb",unveil="Choose an unveil",dominance="Orb of Dominance",beast_aspect="Bestiary: Aspect skill",beast_prefix_suffix="Bestiary: prefix to suffix",
	beast_suffix_prefix="Bestiary: suffix to prefix",beast_imprint="Bestiary: create magic imprint",beast_talisman_imprint="Bestiary: imprint rare Talisman",restore_imprint="Restore imprint",
	bench_reroll="Bench: reroll 1 or 3 modifiers",eldritch_implicit="Eldritch Ember / Ichor",eldritch_exalt="Eldritch Exalted Orb",eldritch_annul="Eldritch Orb of Annulment",
	eldritch_chaos="Eldritch Chaos Orb",blessed="Blessed Orb",sacred="Sacred Orb",socket_bench="Bench: socket count / links",binding="Orb of Binding",
	ducat_cyaxan="Cyaxan's Ducat",ducat_brinehook="Brinehook's Ducat",ducat_genteel="The Genteel's Ducat",ducat_merrick="Merrick's Ducat",
	ducat_rotmother="Rotmother's Ducat",ducat_ukatoa="Ukatoa's Ducat",
	beast_meta="Bestiary: add a crafted meta modifier",beast_influence="Bestiary: add a modifier to an influenced item",
}
A.methods=methods
local influences={shaper=true,elder=true,adjudicator=true,basilisk=true,crusader=true,eyrie=true}
local tags={attack=true,caster=true,physical=true,fire=true,cold=true,lightning=true,chaos=true,life=true,defences=true,speed=true,critical=true,influence=true,minion=true,elemental=true,attribute=true,mana=true,drop=true}
-- HarvestCraftOptions, client 3.30.0.1.4: currency, reforge, augment.
local harvestCosts={fire={"wild_lifeforce",50,15000},cold={"vivid_lifeforce",50,15000},lightning={"primal_lifeforce",50,15000},
	physical={"vivid_lifeforce",50,15000},life={"wild_lifeforce",75,17500},defences={"primal_lifeforce",75,17500},
	chaos={"vivid_lifeforce",100,17500},attack={"wild_lifeforce",75,17500},caster={"primal_lifeforce",75,17500},
	speed={"vivid_lifeforce",150,20000},critical={"primal_lifeforce",150,20000},influence={"primal_lifeforce",5000},
	minion={"primal_lifeforce",200,nil,3},elemental={"wild_lifeforce",200,nil,1},attribute={"vivid_lifeforce",200,nil,2},
	mana={"primal_lifeforce",200,nil,2},drop={"vivid_lifeforce",200,nil,1}}
local function contains(list,wanted) for _,value in ipairs(list or {}) do if value == wanted then return true end end end
local function influenced(model,id)
	local mod=model.byId[id]
	for _,tag in ipairs(mod.weightKey or {}) do for key in pairs(influences) do if model.item.base.influenceTags and model.item.base.influenceTags[key] == tag then return key end end end
end
local function groups(model,id)
	local meta=A.data().mods[id]
	local result=meta and meta.groups or {model.byId[id].group}
	if model.item.clusterJewel then local sim=require("Modules.CraftingSimulator");if sim.isClusterSpeedMod(model,id) then
		local normalized={};for _,group in ipairs(result) do if group~="AfflictionJewelAttackOrCastSpeed" and group~=sim.clusterSpeedGroup then normalized[#normalized+1]=group end end
		normalized[#normalized+1]=sim.clusterSpeedGroup;result=normalized
	end end
	return result
end
local function hasTag(model,id,tag)
	if tag == "influence" then return influenced(model,id) ~= nil end
	local meta=A.data().mods[id]
	return contains(meta and meta.implicit_tags or model.byId[id].modTags,tag)
end
local function shadowItem(model,state)
	local item=setmetatable({},{__index=model.item})
	if state.influences then
		for key in pairs(influences) do item[key]=false end
		for _,key in ipairs(state.influences) do item[key]=true end
	end
	return item
end
local function choose(list,random)
	local total=0; for _,entry in ipairs(list) do total=total+entry.weight end
	assert(total > 0,"No legal modifier is available for this craft")
	local pick=random()*total
	for _,entry in ipairs(list) do pick=pick-entry.weight; if pick < 0 then return entry.id end end
	error("Modifier selection failed")
end
local function inferRange(template,line)
	local pattern,ranges,at="",{},1
	local function escape(text) return text:gsub("([^%w])","%%%1") end
	for first,low,high,last in template:gmatch("()%((%-?%d+%.?%d*)%-(%-?%d+%.?%d*)%)()") do
		pattern=pattern..escape(template:sub(at,first-1)).."(%-?%d+%.?%d*)";at=last;ranges[#ranges+1]={tonumber(low),tonumber(high)}
	end
	pattern="^"..pattern..escape(template:sub(at)).."$"
	if #ranges == 0 then return template == line and 0.5 or nil end
	local values={line:match(pattern)};if #values ~= #ranges then return nil end
	local result={}
	for i,bounds in ipairs(ranges) do
		local value=tonumber(values[i]);local low,high=math.min(unpack(bounds)),math.max(unpack(bounds))
		if not value or value < low or value > high then return nil end
		result[i]=bounds[1] == bounds[2] and 0.5 or (value-bounds[1])/(bounds[2]-bounds[1])
	end
	return #result == 1 and result[1] or result
end
-- A game copy may show catalyst-scaled values. Check that a bounded set of
-- integer base rolls actually renders to the observed line using native scaling.
local function matchesScaledBase(model,template,line,index)
	local item=model.item
	if not item.catalyst or not item.catalystQuality or item.catalystQuality<=0 then return false end
	local ranges,total={},1
	for candidate in template:gmatch("%b()") do
		local low,high=candidate:match("^%((%-?%d+)%-(%-?%d+)%)$")
		if not low then if candidate:match("%d%-%d") then return false end
		else
			low,high=tonumber(low),tonumber(high);if high<low then return false end
			total=total*(high-low+1);if total>4096 then return false end
			ranges[#ranges+1]={low,high}
		end
	end
	if #ranges==0 or #ranges>4 then return false end
	local mod={line=template,modTags=copyTable(item.base.implicitModTypes and item.base.implicitModTypes[index] or {})}
	local scalar=item:GetModLineValueScalar(mod,"IMPLICIT")
	if math.abs(scalar-(1+item.catalystQuality/100))>1e-9 then return false end
	local rolls={}
	local function match(index)
		if index>#ranges then if StripEscapes(itemLib.applyRange(template,rolls,scalar))==line then return copyTable(rolls) end;return nil end
		local low,high=unpack(ranges[index])
		for value=low,high do rolls[index]=high==low and 0.5 or (value-low)/(high-low);local found=match(index+1);if found then return found end end
		return nil
	end
	return match(1)
end
local function matchesScaledBounds(model,template,line,index)
	local item=model.item
	if not item.catalyst or not item.catalystQuality or item.catalystQuality<=0 then return false end
	local mod={line=template,modTags=copyTable(item.base.implicitModTypes and item.base.implicitModTypes[index] or {})}
	local scalar=item:GetModLineValueScalar(mod,"IMPLICIT")
	if math.abs(scalar-(1+item.catalystQuality/100))>1e-9 then return false end
	for _,roll in ipairs({0,1}) do
		if StripEscapes(itemLib.applyRange(template,roll,scalar))~=StripEscapes(itemLib.applyRange(line,roll)) then return false end
	end
	return true
end
local function hasNativeTaggedLine(raw,visible)
	for rawLine in raw:gmatch("[^\r\n]+") do
		local tagged=rawLine:match("^{tags:[^}]*}(.+)$")
		if tagged and StripEscapes(tagged)==visible then return true end
	end
	return false
end
function A.extend(M,api)
	local originalModel,originalAction,originalPool,originalValidate=M.model,M.action,M.pool,M.validateState
	local beastModels=setmetatable({},{__mode="k"})
	local function beastModel(model,level)
		api.integer(level,1,100,"beast level")
		if level==model.item.itemLevel then return model end
		local cache=beastModels[model];if not cache then cache={};beastModels[model]=cache end
		if not cache[level] then
			local raw,count=model.raw:gsub("(\nItem Level:%s*)%d+",function(prefix) return prefix..level end,1)
			assert(count==1,"Cannot construct the beast-level modifier pool for this item")
			local alternate=M.model(raw);assert(alternate.item.baseName==model.item.baseName,"Beast-level pool changed the base")
			cache[level]=alternate
		end
		return cache[level]
	end
	local function beastSource(model,state,level)
		local alternate=beastModel(model,level)
		local source=state.influences and #state.influences>0 and alternate.influencePool or alternate.mods
		for _,entry in ipairs(source) do if not model.byId[entry.id] then model.byId[entry.id]=alternate.byId[entry.id] or entry.mod end end
		return source
	end
	M.beastSource=beastSource
	-- Target choices should include only modifiers whose spawn tags match the
	-- current item. The broader influenced source is still needed by the draw
	-- engine, which applies its normal slot, group and lock rules separately.
	function M.beastTargetSource(model,state,level)
		local item=shadowItem(model,state);local tags=copyTable(model.extraTags or {})
		for _,entry in ipairs(state.affixes or {}) do local metadata=A.data().mods[entry.id];for _,tag in ipairs(metadata and metadata.adds_tags or {}) do tags[tag]=true end end
		local result={}
		for _,entry in ipairs(beastSource(model,state,level)) do if item:GetModSpawnWeight(entry.mod,tags)>0 then result[#result+1]=entry end end
		return result
	end
	function M.beastCatalog(model,state,action,query,limit,offset)
		assert(type(action)=="table" and (action.method=="beast_prefix_suffix" or action.method=="beast_suffix_prefix"),"Select a Bestiary modifier swap")
		limit=api.integer(limit or 50,1,100,"catalogue limit");offset=api.integer(offset or 0,0,1000000000,"catalogue offset")
		assert(query==nil or type(query)=="string" and #query<=160,"Invalid catalogue query")
		if M.context then model=M.context(model,state) end
		local level=api.integer(action.beastLevel or model.item.itemLevel,1,100,"beast level")
		local side=action.method=="beast_prefix_suffix" and "Suffix" or "Prefix";local matches={};query=(query or ""):lower()
		for _,entry in ipairs(M.beastTargetSource(model,state,level)) do
			local mod=entry.mod;local text=table.concat(mod," / ")
			if mod.type==side and (entry.id.." "..text):lower():find(query,1,true) then
				local metadata=A.data().mods[entry.id]
				matches[#matches+1]={id=entry.id,text=text,type=mod.type,level=mod.level,groups=copyTable(metadata and metadata.groups or {mod.group or entry.id})}
			end
		end
		local rows={};for i=offset+1,math.min(offset+limit,#matches) do rows[#rows+1]=matches[i] end
		return {beastLevel=level,usesItemLevel=action.beastLevel==nil,side=side,total=#matches,offset=offset,hasMore=offset+#rows<#matches,rows=rows,
			note="Potential base modifiers matching the current influence and tags before removal. Slot limits, locks and conflicting groups are not applied; removal may change tags and the resulting pool. These are not probabilities. Use calculation or simulation for the complete action.",warnings=M.actionWarnings(action,model)}
	end
	-- Tainted affix currencies reuse the basic transitions without dropping the
	-- corrupted state, which can affect the item's modifier capacity.
	api.taintedAffixAction=originalAction
	local originalCatalog=M.catalog
	local originalRoll=M.rollRange
	local identities=setmetatable({},{__mode="k"})
	local veiledCache={}
	function M.rollRange(mod,random)
		local metadata=A.data().mods[identities[mod]] or mod.clientStats and {stats=mod.clientStats}
		local varying={};for _,stat in ipairs(metadata and metadata.stats or {}) do if stat.max ~= stat.min then varying[#varying+1]=stat end end
		local display=0;for _,line in ipairs(mod) do for range in line:gmatch("%b()") do if range:match("%-?%d+%.?%d*%-%-?%d+%.?%d*") then display=display+1 end end end
		if #varying == 1 and display == 1 then
			local stat=varying[1];return math.floor(random()*(stat.max-stat.min+1))/(stat.max-stat.min)
		end
		return originalRoll(mod,random)
	end
	for method,label in pairs(methods) do M.methods[#M.methods+1]=method; M.labels[method]=label end
	table.sort(M.methods)
	local function cap(model,state) return M.capacities(model,state) end
	function M.model(raw)
		M.dataPatch=A.data().patch;M.modifierPatch=A.data().modifierPatch
		local model=originalModel(raw)
		if not model.item.corrupted and not model.item.synthesised and #model.item.implicitModLines == 0 and type(model.item.base.implicit) == "string" then
			for line in model.item.base.implicit:gmatch("[^\n]+") do local i=#model.item.implicitModLines+1;model.item.implicitModLines[i]={line=line,range=0.5,modTags=copyTable(model.item.base.implicitModTypes and model.item.base.implicitModTypes[i] or {})} end
		end
		local changed=model.item.base.blessed330
		if changed and not model.item.synthesised and #model.item.implicitModLines==1 and not model.item.implicitModLines[1].exarch and not model.item.implicitModLines[1].eater and not model.item.implicitModLines[1].corrupted then
			local line=model.item.implicitModLines[1];local visible=StripEscapes(line.line)
			local ranged=visible:match("%(%-?%d+%.?%d*%-%-?%d+%.?%d*%)")~=nil
			local displayed=ranged and StripEscapes(itemLib.applyRange(visible,line.range or 0.5)) or visible
			local template,rolls
			if not hasNativeTaggedLine(raw,visible) then for _,candidate in ipairs({changed.old,changed.current}) do
				if visible~=candidate and (not ranged or matchesScaledBounds(model,candidate,visible,1)) then
					local scaled=matchesScaledBase(model,candidate,displayed,1)
					if scaled then template,rolls=candidate,scaled;break end
				end
			end end
			if not template then for _,candidate in ipairs({changed.old,changed.current}) do
				if visible==candidate then template=candidate;break end
				local inferred=not ranged and inferRange(candidate,visible)
				if inferred~=nil and inferred~=false then template,rolls=candidate,inferred;break end
			end end
			if template then
				model.blessed330=changed.current
				if rolls then model.baseImplicitTemplates={template};model.normalizedBaseImplicitRanges={[1]=rolls}
				elseif not line.modTags or #line.modTags==0 then model.baseImplicitTagLines={[1]=true} end
			else model.blessed330Unresolved=true end
		end
		-- A game copy normally contains a rolled number, not the base range.
		-- Reconstruct only complete ordinary base implicits that match the
		-- native templates; keep the imported value until a reroll is applied.
		if not changed and not model.item.synthesised and not model.item.corrupted and type(model.item.base.implicit)=="string" then
			local templates={};for line in model.item.base.implicit:gmatch("[^\n]+") do templates[#templates+1]=line end
			local recognized=#templates==#model.item.implicitModLines and #templates>0;local ordinary=true;local normalized,tagLines={},{}
			for i,line in ipairs(model.item.implicitModLines) do
				local visible=StripEscapes(line.line)
				if line.exarch or line.eater or line.corrupted then ordinary=false end
				if not templates[i] then recognized=false
				elseif visible==templates[i] then if not line.modTags or #line.modTags==0 then tagLines[i]=true end
				else
					local ranged=visible:match("%(%-?%d+%.?%d*%-%-?%d+%.?%d*%)")~=nil
					local displayed=ranged and StripEscapes(itemLib.applyRange(visible,line.range or 0.5)) or visible
					-- PoB serializes unscaled rolls with explicit tags; game copies
					-- instead show the already scaled value.
					local nativeTagged=hasNativeTaggedLine(raw,visible)
					local scaled=not nativeTagged and (not ranged or matchesScaledBounds(model,templates[i],visible,i)) and matchesScaledBase(model,templates[i],displayed,i)
					local rolls=scaled or (not ranged and inferRange(templates[i],visible))
					if not rolls then recognized=false else normalized[i]=rolls end
				end
			end
			if recognized and ordinary then model.baseImplicitTemplates=templates;if next(normalized) then model.normalizedBaseImplicitRanges=normalized end;if next(tagLines) then model.baseImplicitTagLines=tagLines end
			elseif ordinary then for _,template in ipairs(templates) do if template:match("%(%-?%d+%.?%d*%-%-?%d+%.?%d*%)") then model.baseImplicitUnresolved=true;break end end end
		end
		if model.item.type == "Flask" or model.item.type == "Tincture" then assert(model.initial.rarity ~= "RARE","Flasks and tinctures cannot be rare") end
		model.extraTags={}
		if model.item.clusterJewel then
			local skill=assert(model.item.clusterJewel.skills[model.item.clusterJewelSkill],"Cluster crafting requires its small-passive skill enchantment")
			model.extraTags[skill.tag]=true;model.mods={}
			for id,mod in pairs(model.item.affixes) do
				if (mod.type == "Prefix" or mod.type == "Suffix") and mod.level <= model.item.itemLevel then
					local weight=model.item:GetModSpawnWeight(mod,model.extraTags);if weight > 0 then model.mods[#model.mods+1]={id=id,mod=mod,weight=weight} end
				end
			end
			table.sort(model.mods,function(a,b) return a.id < b.id end)
		end
		model.special={}; model.veiled={}; model.fossils={}
		for id in pairs(model.unveiledJewels or {}) do model.special[id]=true end
		for id in pairs(model.trickery330 or {}) do model.special[id]=true end
		for i=#model.mods,1,-1 do local meta=A.data().mods[model.mods[i].id];if meta and meta.is_essence_only then table.remove(model.mods,i) end end
		for _,list in ipairs({data.itemMods.Item,data.veiledMods,data.beastCraft}) do for id,mod in pairs(list) do
			if not model.byId[id] then model.byId[id]=mod end
		end end
		for id,mod in pairs(model.byId) do identities[mod]=id end
		local all=setmetatable({},{__index=model.item})
		for key in pairs(influences) do all[key]=true end
		model.influencePool={}
		for id,original in pairs(data.itemMods.Explicit) do
			local mod=model.legacyLightRadius[id] and model.byId[id] or original
			if mod.affix:find("Elevated",1,true) and influenced(model,id) then model.special[id]=true end
			if (mod.type == "Prefix" or mod.type == "Suffix") and mod.level <= model.item.itemLevel and not mod.affix:find("Elevated",1,true) and all:GetModSpawnWeight(mod) > 0 then
				model.influencePool[#model.influencePool+1]={id=id,mod=mod,weight=all:GetModSpawnWeight(mod)}
			end
		end
		table.sort(model.influencePool,function(a,b) return a.id < b.id end)
		for _,entry in ipairs(model.influencePool) do if influenced(model,entry.id) then model.special[entry.id]=true end end
		for id,native in pairs(data.veiledMods) do
			local mod=native;local meta=A.data().mods[id]
			if meta and meta.spawn_weights then
				-- Keep native descriptions and tags, but use the reviewed client
				-- ordering for eligibility and later dynamic weight recalculations.
				mod=veiledCache[id]
				if not mod then
					mod={};for key,value in pairs(native) do mod[key]=value end;mod.weightKey={};mod.weightVal={}
					for _,entry in ipairs(meta.spawn_weights) do mod.weightKey[#mod.weightKey+1]=entry.tag;mod.weightVal[#mod.weightVal+1]=entry.weight end
					veiledCache[id]=mod
				end
				-- Jewel-specific imports may carry a newer client description for
				-- the same ID; preserve that independent representation.
				if not model.unveiledJewels[id] then model.byId[id]=mod end
				identities[mod]=id
			end
			if mod.level <= model.item.itemLevel then
				local weight=model.item:GetModSpawnWeight(mod)
				if weight > 0 then model.veiled[#model.veiled+1]={id=id,mod=mod,weight=weight}; model.special[id]=true end
			end
		end
		table.sort(model.veiled,function(a,b) return a.id < b.id end)
		for id,mod in pairs(data.beastCraft) do if mod.type == "Suffix" then model.special[id]=true end end
		for id,mod in pairs(data.itemMods.Mercenary) do if mod.level <= model.item.itemLevel and model.item:GetModSpawnWeight(mod) > 0 then model.special[id]=true end end
		if model.item.type == "Belt" then for id,mod in pairs(data.itemMods.Ducat) do if mod.level <= model.item.itemLevel then model.special[id]=true end end end
		for id,mod in pairs(data.itemMods.Eldritch) do if model.item:GetModSpawnWeight(mod) > 0 then model.special[id]=true end end
		for id,fossil in pairs(A.data().fossils) do if fossil.name ~= "" then model.fossils[#model.fossils+1]={id=id,name=fossil.name} end end
		table.sort(model.fossils,function(a,b) return a.name < b.name end)
		for _,fossil in pairs(A.data().fossils) do for _,id in ipairs(fossil.added_mods) do if model.byId[id] then model.special[id]=true end end; for _,id in ipairs(fossil.forced_mods) do if model.byId[id] then model.special[id]=true end end end
		model.initial.influences={}
		for key in pairs(influences) do if model.item[key] then model.initial.influences[#model.initial.influences+1]=key end end
		table.sort(model.initial.influences)
		model.initial.corrupted=model.item.corrupted or false; model.initial.mirrored=model.item.mirrored or false
		model.initial.origin=require("sha1")(model.raw)
		model.initial.quality=model.item.quality or 0
		-- PoB supplies display sockets for minimal item text. They are not crafted sockets.
		model.initial.sockets=raw:find("\nSockets:",1,true) and copyTable(model.item.sockets or {}) or {}
		local imported,tagged={},0
		for _,side in ipairs({"Exarch","Eater"}) do
			local lines={};for _,line in ipairs(model.item.implicitModLines) do if line[side:lower()] then lines[#lines+1]=line end end
			if #lines > 0 then
				tagged=tagged+1;local candidates={}
				for id,mod in pairs(data.itemMods.Eldritch) do if mod.type == side and #mod == #lines and model.item:GetModSpawnWeight(mod) > 0 then
					local valid,ranges,exact=true,{},true
					for i,template in ipairs(mod) do
						local group=lines[i].modGroup
						if group and group:sub(1,9)=="crafting_" and group~="crafting_"..id then valid=false;break end
						if template ~= lines[i].line then exact=false end
						local range=template == lines[i].line and (lines[i].range or 0.5) or inferRange(template,itemLib.applyRange(lines[i].line,lines[i].range or 0.5))
						if range == nil then valid=false;break end
						if type(range) == "table" then for _,value in ipairs(range) do ranges[#ranges+1]=value end else ranges[#ranges+1]=range end
					end
					if valid then candidates[#candidates+1]={id=id,side=side,tier=tonumber(id:match("(%d+)$")),range=#ranges == 1 and ranges[1] or ranges,exact=exact} end
				end end
				local exact={};for _,candidate in ipairs(candidates) do if candidate.exact then exact[#exact+1]=candidate end;candidate.exact=nil end
				if #exact > 0 then candidates=exact end
				if #candidates == 1 then imported[#imported+1]=candidates[1] else model.unresolvedEldritch=true end
			end
		end
		if tagged > 0 and not model.unresolvedEldritch then model.initial.implicits=imported end
		return model
	end
	local function pool(model,state,options)
		options=options or {}; local counts=api.counts(model,state); local blocked=api.flags(model,state)
		for key,value in pairs(state.rollBlock or {}) do blocked[key]=value end
		local used={}
		for _,entry in ipairs(state.affixes) do for _,group in ipairs(groups(model,entry.id)) do used[group]=true end end
		local item=shadowItem(model,state); local result={}
		for tag in pairs(model.extraTags or {}) do counts.tags[tag]=true end
		for _,entry in ipairs(state.affixes) do local metadata=A.data().mods[entry.id];for _,tag in ipairs(metadata and metadata.adds_tags or {}) do counts.tags[tag]=true end end
		local source=options.source or (state.influences and #state.influences > 0 and model.influencePool or model.mods)
		for _,entry in ipairs(source) do
			local id,mod=entry.id,entry.mod or model.byId[entry.id]
			local occupied=counts[mod.type]+(options.reservedVeilType==mod.type and 1 or 0)
			local legal=occupied < cap(model,state)[mod.type] and (not options.type or mod.type == options.type)
			if state.maxEssenceModLevel and mod.level>state.maxEssenceModLevel then legal=false end
			for _,group in ipairs(groups(model,id)) do if used[group] then legal=false end end
			if options.tag and not hasTag(model,id,options.tag) then legal=false end
			if options.influence and influenced(model,id) ~= options.influence then legal=false end
			if not options.ignoreBlocks and (blocked.attack and hasTag(model,id,"attack") or blocked.caster and hasTag(model,id,"caster")) then legal=false end
			if legal then
				local weight=entry.weight
				if not options.fixedWeights and (source == model.influencePool or options.recompute or next(counts.tags)) then weight=item:GetModSpawnWeight(mod,counts.tags) end
				if options.fossils then
					local positive,negative=0,1
					for _,fossil in ipairs(options.fossils) do
						for _,change in ipairs(fossil.positive_mod_weights) do if hasTag(model,id,change.tag) then positive=positive+change.weight/100 end end
						for _,change in ipairs(fossil.negative_mod_weights) do if hasTag(model,id,change.tag) then negative=negative*change.weight/100 end end
					end
					weight=weight*(positive > 0 and positive or 1)*negative
					for _,fossil in ipairs(options.fossils) do if fossil.rolls_lucky then weight=weight*(0.6+mod.level/100) end end
				end
				if weight > 0 then result[#result+1]={id=id,weight=weight} end
			end
		end
		if M.adjustPool then result=M.adjustPool(model,state,result,options,source,item,counts.tags) end
		return result
	end
	function M.pool(model,state)
		if not model.influencePool then return originalPool(model,state) end
		local result=pool(model,state,state.poolOptions); local total=0
		for _,entry in ipairs(result) do total=total+entry.weight end
		return result,total
	end
	local function append(model,state,random,options)
		local id=choose(pool(model,state,options),random)
		local range=M.rollRange(model.byId[id],random)
		for _,fossil in ipairs(options and options.fossils or {}) do if fossil.rolls_lucky then
			local other=M.rollRange(model.byId[id],random)
			if type(range) == "table" then for i,value in ipairs(range) do range[i]=math.max(value,other[i]) end else range=math.max(range,other) end
		end end
		state.affixes[#state.affixes+1]={id=id,range=range}
		return id
	end
	local function removable(model,state,options)
		options=options or {}; local f=api.flags(model,state); local eligible={}
		for i,entry in ipairs(state.affixes) do
			local mod=model.byId[entry.id]
			local legal=not api.protected(entry,mod,f) and (not options.type or options.type == mod.type)
			if options.attackProtection and (f.attack and hasTag(model,entry.id,"attack") or f.caster and hasTag(model,entry.id,"caster")) then legal=false end
			if legal then eligible[#eligible+1]=i end
		end
		return eligible
	end
	local function remove(model,state,random,options)
		local eligible=removable(model,state,options)
		assert(#eligible > 0,"No removable modifier for this craft")
		local index=eligible[math.floor(random()*#eligible)+1]; local removed=state.affixes[index]
		table.remove(state.affixes,index); return removed
	end
	-- Removal may itself remove a meta modifier, changing the next candidate set.
	-- Backtrack over distinct removals, preserving partial-lock markers on entries.
	local function canRemove(model,state,count)
		if count==0 then return true end
		for _,index in ipairs(removable(model,state,{attackProtection=true})) do
			local entry=table.remove(state.affixes,index)
			local ok=canRemove(model,state,count-1)
			table.insert(state.affixes,index,entry)
			if ok then return true end
		end
		return false
	end
	function M.benchRerollChoices(model,state)
		local possible={};if state.rarity~="RARE" then return possible end
		local function check(shadow)
			for _,count in ipairs({1,3}) do if not possible[count] and canRemove(model,shadow,count) then possible[count]=true end end
			return possible[1] and possible[3]
		end
		if M.hasPartialLock(model,state) then M.eachPartialSelection(model,state,check) else check(copyTable(state)) end
		return possible
	end
	M.methodChecks.bench_reroll=function(model,state)
		if state.rarity~="RARE" then return "Requires a rare item." end
		if not M.benchRerollChoices(model,state)[1] then return "No modeled selection leaves a removable modifier." end
	end
	local function targetCount(model,state,random)
		local value=random(); return math.min(cap(model,state).total,value < 8/12 and 4 or value < 11/12 and 5 or 6)
	end
	local function fill(model,state,random,options,target)
		target=target or targetCount(model,state,random)
		while #state.affixes < target do append(model,state,random,options) end
	end
	local function baseInfluences(state) return #(state.influences or {}) > 0 end
	local function fractured(state) for _,entry in ipairs(state.affixes) do if entry.fractured then return true end end end
	local function metaCandidates(model,state)
		local c,f=api.counts(model,state),api.flags(model,state)
		if not (c.crafted==0 or f.multipleCrafts and c.crafted<3) then return {},"Remove existing crafted modifiers or allow multiple crafted modifiers first" end
		local result={}
		for _,entry in ipairs(model.bench) do local mod=entry.mod
			if #mod==1 and contains({"Prefixes Cannot Be Changed","Suffixes Cannot Be Changed","Cannot roll Attack Modifiers","Cannot roll Caster Modifiers","Can have up to 3 Crafted Modifiers"},mod[1]) and c[mod.type]<cap(model,state)[mod.type] and not c.groups[mod.group] then result[#result+1]=entry.id end
		end
		return result,#result==0 and "No legal crafted meta modifier" or nil
	end
	local function ducatSource(model,method)
		local result={}
		if method=="ducat_rotmother" then
			for id,mod in pairs(data.itemMods.Ducat) do if mod.level<=model.item.itemLevel then
				local weight=0;for i,key in ipairs(mod.weightKey) do if key=="deepwater_hazard_belt" then weight=mod.weightVal[i] end end
				if weight>0 then result[#result+1]={id=id,mod=mod,weight=weight} end
			end end
		elseif method=="ducat_cyaxan" then
			for id,mod in pairs(data.itemMods.Mercenary) do local weight=model.item:GetModSpawnWeight(mod);if mod.level<=model.item.itemLevel and weight>0 then result[#result+1]={id=id,mod=mod,weight=weight} end end
		else
			for id,mod in pairs(data.beastCraft) do if contains(mod.weightKey,"deepwater_pantheon_aspect") then result[#result+1]={id=id,mod=mod,weight=100} end end
		end
		table.sort(result,function(a,b) return a.id<b.id end);return result
	end
	local function genteelCandidates(model,state)
		if api.flags(model,state).suffixes then return {},{},"Suffixes are locked" end
		local eligible,choices={},{};local any=false
		for i,entry in ipairs(state.affixes) do if not entry.fractured and contains({"Strength","Dexterity","Intelligence"},model.byId[entry.id].group) then
			eligible[#eligible+1]=i;local from=model.byId[entry.id].group;local candidates={}
			for _,to in ipairs({"Strength","Dexterity","Intelligence"}) do if to~=from then
				local id=entry.id:gsub(from,to)
				if model.byId[id] then
					local valid=true;for _,other in ipairs(state.affixes) do for _,group in ipairs(groups(model,other.id)) do if contains(groups(model,id),group) then valid=false end end end
					if valid then candidates[#candidates+1]=id end
				end
			end end
			choices[i]=candidates;any=any or #candidates>0
		end end
		return eligible,choices,#eligible==0 and "No single-attribute modifier to change" or not any and "No compatible other attribute tier" or nil
	end
	M.methodChecks.beast_meta=function(model,state) local _,reason=metaCandidates(model,state);return reason end
	M.methodChecks.beast_influence=function(model,state)
		if state.rarity~="RARE" or not baseInfluences(state) then return "Choose an influence already present on this rare item" end
		if #state.affixes>=cap(model,state).total then return "There is no open modifier slot" end
	end
	for _,method in ipairs({"ducat_rotmother","ducat_cyaxan","ducat_brinehook"}) do
		local selected=method
		M.methodChecks[method]=function(model,state)
			local f=api.flags(model,state)
			if selected=="ducat_rotmother" and (model.item.type~="Belt" or state.rarity~="RARE") then return "Rotmother requires a rare belt" end
			if selected=="ducat_cyaxan" and (state.rarity~="RARE" or f.prefixes or f.suffixes or f.explicitAttack or f.explicitCaster) then return "Cyaxan requires a rare item without meta modifiers in this model" end
			if selected=="ducat_rotmother" and (f.prefixes or f.suffixes or f.explicitAttack or f.explicitCaster) then return "Remove meta modifiers before using Rotmother in this model" end
			if selected=="ducat_brinehook" and model.item.type=="Jewel" then return "Pantheon Aspects require equipment" end
			local prepared=copyTable(state)
			if selected=="ducat_cyaxan" then api.clear(model,prepared,true) elseif selected=="ducat_brinehook" and prepared.rarity=="NORMAL" then prepared.rarity="MAGIC" end
			if #pool(model,prepared,{source=ducatSource(model,selected),fixedWeights=selected~="ducat_cyaxan"})==0 then return "No legal modifier is available for this craft" end
		end
	end
	M.methodChecks.ducat_merrick=function(model,state)
		if model.item.type~="Jewel" or model.item.base.subType~="Abyss" or state.rarity~="RARE" then return "Merrick requires a rare Abyssal Jewel" end
	end
	M.methodChecks.ducat_genteel=function(model,state) local _,_,reason=genteelCandidates(model,state);return reason end
	local function ukatoaChoices(model,side,tier)
		model.ukatoaPools=model.ukatoaPools or {}
		local key=side..tier
		if model.ukatoaPools[key] then return model.ukatoaPools[key] end
		local choices={}
		for id,mod in pairs(data.itemMods.Eldritch) do
			if mod.type==side and tonumber(id:match("(%d+)$"))==tier then
				local weight=model.item:GetModSpawnWeight(mod)
				if weight>0 and model.byId[id] then choices[#choices+1]={id=id,weight=weight} end
			end
		end
		table.sort(choices,function(a,b) return a.id<b.id end)
		model.ukatoaPools[key]=choices
		return choices
	end
	M.methodChecks.ducat_ukatoa=function(model,state)
		if model.item.type~="Amulet" then return "Ukatoa requires an amulet." end
		if state.implicits or model.unresolvedEldritch then return "The amulet already has an Eldritch implicit." end
		if baseInfluences(state) then return "Influenced amulet interactions are not modeled." end
		if model.item.baseName=="Simplex Amulet" or model.item.baseName=="Focused Amulet" then return "This amulet has a fixed implicit that cannot be replaced." end
		if #model.item.implicitModLines==0 and not state.vendorImplicit then return "The amulet has no implicit modifier to replace." end
		for _,side in ipairs({"Exarch","Eater"}) do for tier=1,4 do
			if #ukatoaChoices(model,side,tier)==0 then return "The amulet has an incomplete Eldritch modifier pool." end
		end end
	end
	M.methodChecks.awakener=function(model,state)
		if state.rarity~="RARE" or #(state.influences or {})~=1 or fractured(state) then return "Awakener requires a rare item with one influence and no fractured modifiers." end
		for _,entry in ipairs(state.affixes) do if influenced(model,entry.id) then return end end
		return "The target needs at least one influenced modifier."
	end
	function M.awakenerDonorReason(model,state,donor)
		local other=donor.initial
		if model.item.type~=donor.item.type or state.rarity~="RARE" or other.rarity~="RARE" then return "Awakener inputs must be rare items of the same item class" end
		if #(state.influences or {})~=1 or #(other.influences or {})~=1 or state.influences[1]==other.influences[1] or fractured(state) or fractured(other) then return "Awakener requires different single influences and no fractured mods" end
		local found=false;for _,entry in ipairs(other.affixes) do if influenced(donor,entry.id) then found=true;break end end
		if not found then return "Each item needs an influenced modifier" end
	end
	M.methodChecks.dominance=function(model,state)
		if not contains({"Helmet","Body Armour","Gloves","Boots"},model.item.type) or state.rarity~="RARE" then return "Dominance requires rare influenced armour" end
		local count=0;for _,entry in ipairs(state.affixes) do if influenced(model,entry.id) then count=count+1 end end
		if count<2 or fractured(state) then return "Dominance requires at least two influenced modifiers" end
	end
	for _,method in ipairs({"beast_prefix_suffix","beast_suffix_prefix"}) do
		local selected=method
		M.methodChecks[method]=function(model,state)
			if state.rarity~="RARE" then return "Bestiary conversion requires a rare item" end
			local from=selected=="beast_prefix_suffix" and "Prefix" or "Suffix";local to=from=="Prefix" and "Suffix" or "Prefix"
			if api.counts(model,state)[to]>=cap(model,state)[to] then return "No open affix for this conversion" end
			local f=api.flags(model,state)
			if not (from=="Prefix" and f.prefixes or from=="Suffix" and f.suffixes) then
				local found=false;for _,entry in ipairs(state.affixes) do if model.byId[entry.id].type==from and not api.protected(entry,model.byId[entry.id],f) then found=true;break end end
				if not found then return "No removable modifier for this craft" end
			end
		end
	end
	M.methodChecks.blessed=function(model,state) if (model.blessed330Unresolved or model.baseImplicitUnresolved) and not state.implicits then return "This base implicit could not be identified. Supply a recognized original or current implicit before using a Blessed Orb." end end
	M.methodChecks.binding=function(model,state) if M.socketLimit(model,state)==0 then return "This base cannot have equipment sockets" end end
	M.methodChecks.veiled_chaos=function(model,state)
		if model.item.type=="Jewel" then return "Veiled Chaos requires rare equipment, not a jewel" end
		if #model.veiled==0 then return "This base has no supported veiled modifiers" end
		local f=api.flags(model,state)
		if state.veil and (state.veil.fractured or state.veil.type=="Prefix" and f.prefixes or state.veil.type=="Suffix" and f.suffixes) then return "The existing veiled modifier is protected" end
		for _,entry in ipairs(state.affixes) do
			if contains(model.byId[entry.id].modTags,"unveiled_mod") and api.protected(entry,model.byId[entry.id],f) then return "The existing unveiled modifier is protected" end
		end
	end
	M.methodChecks.veiled_orb=function(model,state)
		if #model.veiled==0 then return "This base has no supported veiled modifiers" end
		local f=api.flags(model,state);local removable=false
		for _,entry in ipairs(state.affixes) do
			if contains(model.byId[entry.id].modTags,"unveiled_mod") then return "The item already has an unveiled modifier" end
			if not api.protected(entry,model.byId[entry.id],f) then removable=true end
		end
		if not removable then return "No removable modifier for this craft" end
	end
	local shieldMaximum={fire={"MaximumFireResist1","MaximumFireResist2_","MaximumFireResist3"},cold={"MaximumColdResist1","MaximumColdResist2","MaximumColdResist3"},lightning={"MaximumLightningResist1","MaximumLightningResist2___","MaximumLightningResist3"}}
	-- Client families have matching roll tiers, but several IDs have suffixes.
	local clusterResistance={
		fire={{"AfflictionJewelSmallPassivesGrantFireRes","AfflictionJewelSmallPassivesGrantFireRes2","AfflictionJewelSmallPassivesGrantFireRes3"},
			{"AfflictionJewelSmallPassivesGrantFireResSmall","AfflictionJewelSmallPassivesGrantFireResSmall2","AfflictionJewelSmallPassivesGrantFireResSmall3_","AfflictionJewelSmallPassivesGrantFireResSmall4","AfflictionJewelSmallPassivesGrantFireResSmall5"}},
		cold={{"AfflictionJewelSmallPassivesGrantColdRes_","AfflictionJewelSmallPassivesGrantColdRes2","AfflictionJewelSmallPassivesGrantColdRes3"},
			{"AfflictionJewelSmallPassivesGrantColdResSmall","AfflictionJewelSmallPassivesGrantColdResSmall2","AfflictionJewelSmallPassivesGrantColdResSmall3","AfflictionJewelSmallPassivesGrantColdResSmall4","AfflictionJewelSmallPassivesGrantColdResSmall5_"}},
		lightning={{"AfflictionJewelSmallPassivesGrantLightningRes","AfflictionJewelSmallPassivesGrantLightningRes2_","AfflictionJewelSmallPassivesGrantLightningRes3"},
			{"AfflictionJewelSmallPassivesGrantLightningResSmall","AfflictionJewelSmallPassivesGrantLightningResSmall2__","AfflictionJewelSmallPassivesGrantLightningResSmall3","AfflictionJewelSmallPassivesGrantLightningResSmall4_","AfflictionJewelSmallPassivesGrantLightningResSmall5"}},
	}
	local function clusterResistanceTarget(model,id,from,to)
		if not model.item.clusterJewel then return end
		for size,list in ipairs(clusterResistance[from] or {}) do for tier,source in ipairs(list) do
			if source==id then return clusterResistance[to][size][tier] end
		end end
	end
	local function shieldResistanceTarget(model,id,from,to)
		if model.item.type~="Shield" then return end
		for tier,source in ipairs(shieldMaximum[from] or {}) do if source==id then return shieldMaximum[to][tier] end end
	end
	-- These drop-only counterparts share resistance tiers and equipment types;
	-- the cross-element mapping is a model, not verified in-game behavior.
	local incursionResistance={
		{fire="FireResistEnhancedLevel50ModAilments_",cold="ColdResistEnhancedModAilments__",lightning="LightningResistEnhancedLevel50ModAilments"},
		{fire="FireResistEnhancedLevel50ModPhys",cold="ColdResistEnhancedLevel50ModPhys_",lightning="LightningResistEnhancedLevel50ModPhys"},
		{fire="FireResistEnhancedLevel50ModLeech",cold="ColdResistEnhancedModLeech",lightning="LightningResistEnhancedLevel50ModLeech"},
		{fire="FireResistEnhancedLevel50ModLeechInverted",cold="ColdResistEnhancedLevel50ModLeechInverted",lightning="LightningResistEnhancedLevel50ModLeechInverted"},
	}
	local function incursionResistanceTarget(id,from,to)
		for _,family in ipairs(incursionResistance) do if family[from]==id then return family[to] end end
	end
	local function resistanceTarget(model,id,from,to)
		return incursionResistanceTarget(id,from,to) or clusterResistanceTarget(model,id,from,to) or shieldResistanceTarget(model,id,from,to) or id:gsub(from:gsub("^%l",string.upper),to:gsub("^%l",string.upper))
	end
	function M.resistanceReason(model,state,from,to)
		if from==to or not contains({"fire","cold","lightning"},from) or not contains({"fire","cold","lightning"},to) then return "Choose different elemental resistance types" end
		local f=api.flags(model,state)
		local matches={};local element=from:gsub("^%l",string.upper)
		-- HarvestCraftOptions lists these families as eligible, including
		-- hybrids we cannot convert yet. Never ignore an eligible modifier:
		-- the game could select it instead of the one we know how to model.
		local sourceGroups={element.."Resistance",element.."ResistanceAilments",element.."ResistanceForJewel",element.."ResistanceLeech",
			"Maximum"..element..(from=="lightning" and "Resistance" or "Resist"),element.."ResistancePhysTakenAs"..element,
			element.."ResistancePrefix","AfflictionJewelSmallPassivesGrant"..element.."Res","Maximum"..element.."ResistanceForJewel"}
		for i,entry in ipairs(state.affixes) do
			local jewel=model.item.type=="Jewel" and (entry.id==element.."ResistanceJewel" or entry.id=="Maximum"..element.."ResistanceJewel" or entry.id=="Abyss"..element.."ResistanceJewel1")
			local shield=shieldResistanceTarget(model,entry.id,from,to)
			local cluster=clusterResistanceTarget(model,entry.id,from,to)
			local incursion=incursionResistanceTarget(entry.id,from,to)
			local delvePrefix=entry.id=="DelveArmour"..element.."Resistance1"
			local eligible=false;for _,group in ipairs(groups(model,entry.id)) do if contains(sourceGroups,group) then eligible=true;break end end
			if not api.protected(entry,model.byId[entry.id],f) and eligible then
				if not (model.byId[entry.id].group==element.."Resistance" or jewel or shield or cluster or delvePrefix or incursion) then return "An eligible resistance modifier has an unsupported conversion family" end
				matches[#matches+1]=i
			end
		end
		if #matches==0 then return f.suffixes and "Suffixes are locked" or "No swappable single-element resistance" end
		for _,index in ipairs(matches) do
			local id=resistanceTarget(model,state.affixes[index].id,from,to)
			if not model.byId[id] then return "No matching resistance tier on this base" end
			if incursionResistanceTarget(state.affixes[index].id,from,to) and not contains(model.dropOnlyIds,id) then return "The replacement modifier is unavailable on this base or item level" end
			if (model.item.type=="Jewel" or shieldResistanceTarget(model,state.affixes[index].id,from,to)) and model.item:GetModSpawnWeight(model.byId[id],model.extraTags or {})<=0 then return "The replacement modifier cannot occur on this base" end
			for otherIndex,entry in ipairs(state.affixes) do if otherIndex~=index then
				for _,group in ipairs(groups(model,entry.id)) do
					if contains(groups(model,id),group) then return "That resistance group is already present" end
				end
			end end
		end
		return nil,matches
	end
	function M.resistanceOptions(model,state)
		local result={};local unsupported
		for _,from in ipairs({"fire","cold","lightning"}) do for _,to in ipairs({"fire","cold","lightning"}) do
			local reason
			if M.hasPartialLock(model,state) then
				local viable=false;M.eachPartialSelection(model,state,function(candidate)
					reason=M.resistanceReason(model,candidate,from,to);if not reason then viable=true;return true end
				end)
				if viable then reason=nil end
			else reason=M.resistanceReason(model,state,from,to) end
			if not reason then result[#result+1]={label=from.." to "..to,action={method="harvest_resistance",from=from,to=to}}
			elseif reason=="An eligible resistance modifier has an unsupported conversion family" then unsupported=reason end
		end end
		return result,#result==0 and (unsupported or (api.flags(model,state).suffixes and "Suffixes are locked." or "No swappable single-element resistance is available.")) or nil
	end
	local damageData
	-- Models finish building their modifier table before actions are exposed.
	-- Keep the index weak so closing an item releases its catalogue too.
	local damageIndexes=setmetatable({},{__mode="k"})
	local function harvestDamageData()
		if not damageData then
			damageData=assert(json.decode(readData("3.30-harvest-damage.json")))
			assert(damageData.schemaVersion==1 and damageData.clientVersion=="3.30.0.2" and type(damageData.groups)=="table" and type(damageData.costs)=="table","Invalid Harvest damage data")
		end
		return damageData
	end
	local function damageTarget(model,id,from,to)
		local source=from:gsub("^%l",string.upper);local target=to:gsub("^%l",string.upper)
		local wanted=id:gsub(source,target):gsub(from,to):gsub("_+$","")
		if wanted==id:gsub("_+$","") then return end
		local index=damageIndexes[model.byId]
		if not index then
			index={}
			for candidate in pairs(model.byId) do
				if candidate:find("Fire",1,true) or candidate:find("Cold",1,true) or candidate:find("Lightning",1,true)
					or candidate:find("fire",1,true) or candidate:find("cold",1,true) or candidate:find("lightning",1,true) then
					local key=candidate:gsub("_+$","");local list=index[key]
					if not list then list={};index[key]=list end
					list[#list+1]=candidate
				end
			end
			damageIndexes[model.byId]=index
		end
		local found
		for _,candidate in ipairs(index[wanted] or {}) do
			local mod=model.byId[candidate]
			if mod and mod.type==model.byId[id].type then
				local eligible=false;for _,group in ipairs(groups(model,candidate)) do if contains(harvestDamageData().groups[to],group) then eligible=true;break end end
				if eligible then if found then return end;found=candidate end
			end
		end
		return found
	end
	function M.damageReason(model,state,from,to)
		local data=harvestDamageData();if not data.groups[from] or not data.groups[to] or from==to then return "Choose different elemental damage types" end
		local flags=api.flags(model,state);local matches={}
		for index,entry in ipairs(state.affixes) do
			local eligible=false;for _,group in ipairs(groups(model,entry.id)) do
				-- The 3.28 hotfix removed critical multiplier conversion, even
				-- though this group remains in the client command parameters.
				if group~=from:gsub("^%l",string.upper).."CritMultiplierForJewel" and contains(data.groups[from],group) then eligible=true;break end
			end
			if eligible and not api.protected(entry,model.byId[entry.id],flags) then
				local target=damageTarget(model,entry.id,from,to)
				if not target then return "An eligible damage modifier has no supported matching conversion" end
				if model.item:GetModSpawnWeight(model.byId[target],model.extraTags or {})<=0 then return "The replacement damage modifier cannot occur on this base" end
				for otherIndex,other in ipairs(state.affixes) do if otherIndex~=index then
					for _,group in ipairs(groups(model,other.id)) do if contains(groups(model,target),group) then return "The replacement damage group is already present" end end
				end end
				matches[#matches+1]={index=index,id=target}
			end
		end
		if #matches==0 then return "No swappable elemental damage modifier" end
		return nil,matches
	end
	function M.damageOptions(model,state)
		local result={};local reason
		for _,from in ipairs({"fire","cold","lightning"}) do for _,to in ipairs({"fire","cold","lightning"}) do if from~=to then
			local why
			if M.hasPartialLock(model,state) then
				local viable=false;M.eachPartialSelection(model,state,function(candidate)
					why=M.damageReason(model,candidate,from,to);if not why then viable=true;return true end
				end)
				if viable then why=nil end
			else why=M.damageReason(model,state,from,to) end
			if not why then result[#result+1]={label=from.." to "..to,action={method="harvest_damage",from=from,to=to}}
			elseif why~="No swappable elemental damage modifier" then reason=why end
		end end end
		return result,#result==0 and (reason or "No swappable elemental damage modifier") or nil
	end
	function M.harvestChoices(model,state,method)
		if state.rarity~="RARE" then return {},"Requires a rare item." end
		local augment=method=="harvest_augment"
		if augment and baseInfluences(state) then return {},"Harvest augment requires a non-influenced item." end
		local prepared=copyTable(state);local f=api.flags(model,state);local partial=M.hasPartialLock(model,state)
		if augment then
			local removable=false
			local function check(candidate)
				for _,entry in ipairs(candidate.affixes) do if not api.protected(entry,model.byId[entry.id],f) then removable=true;return true end end
			end
			if partial then M.eachPartialSelection(model,state,check) else check(state) end
			if not removable then return {},"Requires an original modifier that can be removed." end
		end
		local available={}
		local function collect(candidate)
			local entries=pool(model,candidate)
			for tag in pairs(tags) do if not available[tag] and (not augment or harvestCosts[tag][3]) then
				local found=false
				if candidate.memoryActive or candidate.memoryFoulborn then found=#pool(model,candidate,{tag=tag})>0
				else for _,entry in ipairs(entries) do if hasTag(model,entry.id,tag) then found=true;break end end end
				if found then available[tag]=true end
			end end
		end
		if not augment and partial then
			local seen={}
			M.eachPartialSelection(model,state,function(candidate)
				api.clear(model,candidate);candidate.rollBlock={attack=f.attack,caster=f.caster}
				local ids={};for _,entry in ipairs(candidate.affixes) do ids[#ids+1]=entry.id end;table.sort(ids)
				local key=table.concat(ids,"\0")
				if not seen[key] then seen[key]=true;collect(candidate) end
			end)
		else
			if not augment then api.clear(model,prepared);prepared.rollBlock={attack=f.attack,caster=f.caster} end
			collect(prepared)
		end
		local result={};for tag in pairs(available) do result[#result+1]={label=tag,action={method=method,tag=tag}} end
		table.sort(result,function(a,b) return a.label<b.label end)
		return result,#result==0 and "No legal modifier is available for this craft." or nil
	end
	function M.decorateItem(model,state,item)
		if #item.implicitModLines == 0 and not item.corrupted and not item.synthesised and type(item.base.implicit) == "string" then
			for line in item.base.implicit:gmatch("[^\n]+") do local i=#item.implicitModLines+1;item.implicitModLines[i]={line=line,range=0.5,modTags=copyTable(item.base.implicitModTypes and item.base.implicitModTypes[i] or {})} end
		end
		if state.influences then
			for key in pairs(influences) do item[key]=false end
			for _,key in ipairs(state.influences) do item[key]=true end
		end
		if state.corrupted ~= nil then item.corrupted=state.corrupted end
		if state.mirrored ~= nil then item.mirrored=state.mirrored end
		if state.quality then item.quality=state.quality end
		if state.sockets then item.sockets=copyTable(state.sockets) end
		for kind,value in pairs(state.percentiles or {}) do item.armourData[kind.."BasePercentile"]=value end
		if state.baseImplicit330 then
			assert(model.blessed330 and item.implicitModLines[1],"Invalid updated base implicit")
			item.implicitModLines[1].line=model.blessed330;item.implicitModLines[1].modTags=copyTable(item.base.implicitModTypes and item.base.implicitModTypes[1] or {})
		end
		if model.baseImplicitTagLines then for i in pairs(model.baseImplicitTagLines) do
			if item.implicitModLines[i] then item.implicitModLines[i].modTags=copyTable(item.base.implicitModTypes and item.base.implicitModTypes[i] or {}) end
		end end
		if model.normalizedBaseImplicitRanges and not state.baseImplicitRanges then for i,range in pairs(model.normalizedBaseImplicitRanges) do
			if item.implicitModLines[i] then item.implicitModLines[i].line=itemLib.applyRange(model.baseImplicitTemplates[i],range);item.implicitModLines[i].range=nil;item.implicitModLines[i].modTags=copyTable(item.base.implicitModTypes and item.base.implicitModTypes[i] or {}) end
		end end
		if state.baseImplicitRanges then for i,range in ipairs(state.baseImplicitRanges) do if item.implicitModLines[i] then
			local template=state.baseImplicitReconstructed and model.baseImplicitTemplates[i] or item.implicitModLines[i].line
			if state.baseImplicitReconstructed then item.implicitModLines[i].modTags=copyTable(item.base.implicitModTypes and item.base.implicitModTypes[i] or {}) end
			item.implicitModLines[i].line=itemLib.applyRange(template,range);item.implicitModLines[i].range=nil
		end end end
		if state.vendorImplicit then
			for _,line in ipairs(assert(model.byId[state.vendorImplicit],"Unknown vendor implicit")) do item.implicitModLines[#item.implicitModLines+1]={line=line} end
		end
		if state.implicits then
			item.implicitModLines={}
			for _,entry in ipairs(state.implicits) do
				local mod=model.byId[entry.id]
				for _,line in ipairs(M.rolledLines(mod,entry.range)) do item.implicitModLines[#item.implicitModLines+1]={line=line,modGroup="crafting_"..entry.id,exarch=entry.side == "Exarch",eater=entry.side == "Eater"} end
			end
		end
	end
	function M.action(model,input,action,random)
		assert(type(action) == "table" and type(action.method) == "string","Select a crafting method")
		if action.beastLevel~=nil then assert(action.method=="beast_prefix_suffix" or action.method=="beast_suffix_prefix","Beast level only applies to Bestiary modifier swaps");api.integer(action.beastLevel,1,100,"beast level") end
		assert(not input.mirrored,"Mirrored items cannot be crafted")
		assert(not input.corrupted or action.method == "socket_bench","This method cannot modify a corrupted item")
		assert(not input.veil or action.method == "unveil" or action.method == "veiled_chaos","Choose the pending unveil first")
		local state=copyTable(input); local method=action.method; local f=api.flags(model,state)
		if model.item.type == "Flask" or model.item.type == "Tincture" then
			assert(contains({"transmute","alteration","augmentation","annul","scour","divine","blessed"},method),"This method is unavailable for flasks and tinctures")
		end
		-- In 3.30, attack/caster roll blockers no longer protect those modifiers
		-- from an Orb of Annulment. Prefix/suffix locks and fractures still apply.
		if method == "annul" then return originalAction(model,state,action,random) end
		if not methods[method] then return originalAction(model,state,action,random) end
		if method == "beast_meta" then
			local candidates,reason=metaCandidates(model,state)
			assert(not reason,reason)
			return M.action(model,state,{method="bench",modId=candidates[math.floor(random()*#candidates)+1]},random)
		elseif method == "beast_influence" then
			assert(state.rarity == "RARE" and contains(state.influences,action.influence),"Choose an influence already present on this rare item")
			append(model,state,random)
		elseif method == "ducat_rotmother" then
			assert(model.item.type == "Belt" and state.rarity == "RARE","Rotmother requires a rare belt")
			assert(not (f.prefixes or f.suffixes or f.explicitAttack or f.explicitCaster),"Remove meta modifiers before using Rotmother in this model")
			append(model,state,random,{source=ducatSource(model,method),fixedWeights=true})
		elseif method == "ducat_cyaxan" then
			assert(state.rarity == "RARE" and not (f.prefixes or f.suffixes or f.explicitAttack or f.explicitCaster),"Cyaxan requires a rare item without meta modifiers in this model")
			api.clear(model,state,true);append(model,state,random,{source=ducatSource(model,method)});fill(model,state,random)
		elseif method == "ducat_brinehook" then
			assert(model.item.type ~= "Jewel","Pantheon Aspects require equipment")
			if state.rarity == "NORMAL" then state.rarity="MAGIC" end
			append(model,state,random,{source=ducatSource(model,method),fixedWeights=true})
		elseif method == "ducat_merrick" then
			assert(model.item.type == "Jewel" and model.item.base.subType == "Abyss" and state.rarity == "RARE","Merrick requires a rare Abyssal Jewel")
			state.corrupted=true;append(model,state,random);state.imprint=nil
		elseif method == "ducat_genteel" then
			local eligible,choices,reason=genteelCandidates(model,state)
			assert(not reason,reason)
			local index=eligible[math.floor(random()*#eligible)+1];local entry=state.affixes[index];local candidates=choices[index]
			assert(#candidates > 0,"No compatible other attribute tier");entry.id=candidates[math.floor(random()*#candidates)+1]
		elseif method == "harvest_reforge" then
			assert(state.rarity == "RARE" and tags[action.tag],"Select a supported Harvest tag on a rare item")
			if M.hasPartialLock(model,state) then api.selectPartialLocks(model,state,random) end
			api.clear(model,state); state.rollBlock={attack=f.attack,caster=f.caster}
			append(model,state,random,{tag=action.tag}); state.rollBlock=nil; fill(model,state,random)
		elseif method == "harvest_augment" then
			assert(state.rarity == "RARE" and tags[action.tag] and harvestCosts[action.tag][3],"Select a supported Harvest augment tag on a rare item")
			assert(not baseInfluences(state),"Harvest augment requires a non-influenced item")
			if M.hasPartialLock(model,state) then api.selectPartialLocks(model,state,random) end
			-- Harvest adds first, then removes one of the original removable affixes.
			local added=append(model,state,random,{tag=action.tag})
			local last=table.remove(state.affixes); remove(model,state,random); state.affixes[#state.affixes+1]=last
			assert(last.id == added)
		elseif method == "fossil" then
			assert(not (f.prefixes or f.suffixes or f.explicitAttack or f.explicitCaster),"Remove meta modifiers before using a resonator")
			assert(type(action.fossils) == "table" and #action.fossils >= 1 and #action.fossils <= 4,"Select one to four different fossils")
			local fossils,seen,extras={},{},{}
			for _,id in ipairs(action.fossils) do
				local fossil=assert(A.data().fossils[id],"Unknown fossil")
				assert(fossil.name ~= "" and not seen[id],"Use different named fossils")
				if fossil.name == "Fractured Fossil" then assert(not baseInfluences(state) and not fractured(state) and not model.item.synthesised,"Fractured Fossil requires a non-fractured, non-influenced, non-synthesised base") end
				if fossil.name == "Tangled Fossil" then
					fossil=assert(A.data().fossils[action.tangledOutcome],"Select the Tangled effect revealed by the socketed resonator")
					assert(fossil.name == "" and action.tangledOutcome:find("RandomFossilOutcome",1,true),"Invalid revealed Tangled outcome")
				end
				for _,tag in ipairs(fossil.forbidden_tags) do assert(not model.item.base.tags[tag],"This fossil cannot use this base") end
				if #fossil.allowed_tags > 0 then local allowed=false; for _,tag in ipairs(fossil.allowed_tags) do if model.item.base.tags[tag] then allowed=true end end; assert(allowed,"This fossil cannot use this base") end
				seen[id]=true; fossils[#fossils+1]=fossil
				for _,modId in ipairs(fossil.added_mods) do extras[modId]=true end
			end
			api.clear(model,state,true); state.rarity="RARE"
			local source=copyTable(baseInfluences(state) and model.influencePool or model.mods)
			for id in pairs(extras) do local mod=assert(model.byId[id],"Fossil modifier data missing"); local weight=model.item:GetModSpawnWeight(mod); if weight > 0 then source[#source+1]={id=id,mod=mod,weight=weight} end end
			table.sort(source,function(a,b) return a.id < b.id end)
			local options={fossils=fossils,source=source,recompute=baseInfluences(state)}
			for _,fossil in ipairs(fossils) do
				for _,id in ipairs(fossil.forced_mods) do local mod=assert(model.byId[id]);local c=api.counts(model,state);assert(c[mod.type] < cap(model,state)[mod.type] and not c.groups[mod.group],"No legal slot for forced fossil modifier"); state.affixes[#state.affixes+1]={id=id,range=M.rollRange(mod,random)} end
				if fossil.corrupted_essence_chance > 0 and random()*100 < fossil.corrupted_essence_chance then
					local candidates={}; for _,essence in ipairs(model.essences) do if essence.type > 0 then candidates[#candidates+1]={id=essence.modId,mod=model.byId[essence.modId],weight=1} end end
					append(model,state,random,{source=candidates,fossils=fossils,fixedWeights=true})
				end
				if #fossil.sell_price_mods > 0 then state.vendorImplicit=fossil.sell_price_mods[math.floor(random()*#fossil.sell_price_mods)+1] end
			end
			fill(model,state,random,options)
			for _,id in ipairs(action.fossils) do
				local name=A.data().fossils[id].name
				if name == "Fractured Fossil" then state.affixes[math.floor(random()*#state.affixes)+1].fractured=true end
				if name == "Bloodstained Fossil" then M.rollCorrupted(model,state,random) end
			end
		elseif method == "fracture" then
			assert(state.rarity == "RARE" and #state.affixes >= 4 and not baseInfluences(state) and not fractured(state),"Fracturing requires at least four rare affixes and no influence or fracture")
			assert(not model.item.synthesised,"Cannot fracture a synthesised item")
			state.affixes[math.floor(random()*#state.affixes)+1].fractured=true
		elseif method == "influence_exalt" then
			assert(state.rarity == "RARE" and influences[action.influence] and not baseInfluences(state) and not fractured(state),"Select an influence on an uninfluenced, non-fractured rare")
			assert(not model.item.synthesised and model.item.itemLevel >= 68,"Influenced Exalted Orbs require a non-synthesised item of level 68 or higher")
			assert(model.item.base.influenceTags and model.item.base.influenceTags[action.influence],"This base cannot receive influence")
			state.influences={action.influence}; append(model,state,random,{influence=action.influence})
		elseif method == "awakener" then
			assert(type(action.donorItem) == "string" and #action.donorItem <= 24000,"Paste an influenced donor item")
			local donor=M.model(action.donorItem); local other=donor.initial
			local reason=M.awakenerDonorReason(model,state,donor);assert(not reason,reason)
			local function select(from,source)
				local entries={}; for _,entry in ipairs(source.affixes) do if influenced(from,entry.id) then entries[#entries+1]=entry end end
				assert(#entries > 0,"Each item needs an influenced modifier"); return copyTable(entries[math.floor(random()*#entries)+1])
			end
			local left,right=select(model,state),select(donor,other)
			state.affixes={left}; state.influences={state.influences[1],other.influences[1]}
			local conflict=false; for _,a in ipairs(groups(model,left.id)) do for _,b in ipairs(groups(model,right.id)) do if a == b then conflict=true end end end
			if not conflict then state.affixes[#state.affixes+1]=right elseif random() < 0.5 then state.affixes={right} end
			fill(model,state,random)
		elseif method == "veiled_chaos" then
			assert(state.rarity=="RARE" and model.item.type~="Jewel","Veiled Chaos requires rare equipment")
			local pending=state.veil
			-- A pending veil occupies a real affix slot. Temporarily represent it
			-- during partial-lock selection, then remove the marker before reforge.
			local marker
			if pending then marker={id=pending.choices[1],fractured=pending.fractured};state.affixes[#state.affixes+1]=marker end
			if M.hasPartialLock(model,state) then api.selectPartialLocks(model,state,random) end
			for _,entry in ipairs(state.affixes) do
				if entry==marker or contains(model.byId[entry.id].modTags,"unveiled_mod") then
					assert(not api.protected(entry,model.byId[entry.id],f),"The existing veiled modifier is protected")
				end
			end
			if marker then table.remove(state.affixes,#state.affixes);state.veil=nil end
			api.clear(model,state);state.rollBlock={attack=f.attack,caster=f.caster}
			-- Choose the veil side first and reserve that slot while rolling the
			-- ordinary affixes. Offer generation follows after those rolls.
			local possible=pool(model,state,{source=model.veiled,ignoreBlocks=true})
			local types={};for _,entry in ipairs(possible) do types[model.byId[entry.id].type]=true end
			assert(types.Prefix or types.Suffix,"No legal veiled modifier can be added")
			local kind=types.Prefix and types.Suffix and (random()<0.5 and "Prefix" or "Suffix") or types.Prefix and "Prefix" or "Suffix"
			fill(model,state,random,{reservedVeilType=kind},targetCount(model,state,random)-1)
			local candidates=pool(model,state,{source=model.veiled,ignoreBlocks=true})
			local choices={}
			while #choices<3 do
				local options={};for _,entry in ipairs(candidates) do
					local valid=model.byId[entry.id].type==kind
					for _,id in ipairs(choices) do for _,a in ipairs(groups(model,id)) do for _,b in ipairs(groups(model,entry.id)) do if a==b then valid=false end end end end
					if valid then options[#options+1]=entry end
				end
				if #options==0 then break end
				choices[#choices+1]=choose(options,random)
			end
			assert(#choices>0,"No legal veiled modifier remains after the reforge")
			state.veil={type=kind,choices=choices}
		elseif method == "veiled_orb" then
			assert(state.rarity == "RARE" and #state.affixes > 0,"Veiled Exalted Orb requires a rare item with modifiers")
			for _,entry in ipairs(state.affixes) do assert(not contains(model.byId[entry.id].modTags,"unveiled_mod"),"The item already has an unveiled modifier") end
			remove(model,state,random)
			local choices={}; local candidates=pool(model,state,{source=model.veiled,ignoreBlocks=true})
			local types={}; for _,entry in ipairs(candidates) do types[model.byId[entry.id].type]=true end
			local kind=types.Prefix and types.Suffix and (random() < 0.5 and "Prefix" or "Suffix") or types.Prefix and "Prefix" or "Suffix"
			local first={}; for _,entry in ipairs(candidates) do if model.byId[entry.id].type == kind then first[#first+1]=entry end end
			local selected=choose(first,random)
			while #choices < 3 do
				local options={}; for _,entry in ipairs(candidates) do
					local valid=model.byId[entry.id].type == kind
					for _,id in ipairs(choices) do for _,a in ipairs(groups(model,id)) do for _,b in ipairs(groups(model,entry.id)) do if a == b then valid=false end end end end
					if valid then options[#options+1]=entry end
				end
				if #options == 0 then break end
				choices[#choices+1]=#choices == 0 and selected or choose(options,random)
			end
			state.veil={type=kind,choices=choices}
		elseif method == "dominance" then
			assert(contains({"Helmet","Body Armour","Gloves","Boots"},model.item.type) and state.rarity == "RARE","Dominance requires rare influenced armour")
			local eligible={};for i,entry in ipairs(state.affixes) do if influenced(model,entry.id) then eligible[#eligible+1]=i end end
			assert(#eligible >= 2 and not fractured(state),"Dominance requires at least two influenced modifiers")
			local selected=eligible[math.floor(random()*#eligible)+1];local entry=state.affixes[selected];local original=model.byId[entry.id]
			local upgraded
			if original.affix:find("Elevated",1,true) then upgraded=entry.id
			else
				local candidates={};local item=shadowItem(model,state)
				local function family(id) return id:gsub("_+$",""):gsub("Maven.*$",""):gsub("%d+$","") end
				for id,mod in pairs(data.itemMods.Explicit) do
					local elevated=mod.affix:find("Elevated",1,true) ~= nil
					if family(id) == family(entry.id) and mod.type == original.type and influenced(model,id) == influenced(model,entry.id) and (elevated or item:GetModSpawnWeight(mod) > 0) then
						if elevated or mod.level > original.level then candidates[#candidates+1]={id=id,level=mod.level,elevated=elevated} end
					end
				end
				table.sort(candidates,function(a,b) if a.elevated ~= b.elevated then return not a.elevated end;if a.level ~= b.level then return a.level < b.level end;return a.id < b.id end)
				assert(candidates[1],"No verified higher tier in this modifier family");upgraded=candidates[1].id
			end
			local others={};for _,index in ipairs(eligible) do if index ~= selected then others[#others+1]=index end end
			local removed=others[math.floor(random()*#others)+1]
			entry.id=upgraded;entry.range=M.rollRange(model.byId[upgraded],random);table.remove(state.affixes,removed)
		elseif method == "unveil" then
			local veil=assert(state.veil,"The item has no pending unveil"); local id
			if action.preferredMods then
				for _,wanted in ipairs(action.preferredMods) do if contains(veil.choices,wanted) then id=wanted; break end end
			elseif action.modId then
				assert(contains(veil.choices,action.modId),"The selected modifier is not an offered unveil choice");id=action.modId
			end
			id=id or veil.choices[1]; state.affixes[#state.affixes+1]={id=id,range=M.rollRange(model.byId[id],random),fractured=veil.fractured or nil}; state.veil=nil
		elseif method == "beast_aspect" then
			assert(model.item.type ~= "Jewel","Aspect crafts require equipment")
			local mod=assert(data.beastCraft[action.modId],"Select a native Aspect modifier")
			assert(mod.type == "Suffix" and not contains(mod.weightKey,"deepwater_pantheon_aspect"),"Pantheon Aspects require Brinehook's Ducat")
			assert(api.counts(model,state).Suffix < cap(model,state).Suffix,"No open suffix")
			for _,entry in ipairs(state.affixes) do for _,group in ipairs(groups(model,entry.id)) do assert(not contains(groups(model,action.modId),group),"An incompatible granted skill is already present") end end
			if state.rarity == "NORMAL" then state.rarity="MAGIC" end
			state.affixes[#state.affixes+1]={id=action.modId,range=0.5}
		elseif method == "beast_prefix_suffix" or method == "beast_suffix_prefix" then
			assert(state.rarity == "RARE","Bestiary conversion requires a rare item")
			local from=method == "beast_prefix_suffix" and "Prefix" or "Suffix"; local to=from == "Prefix" and "Suffix" or "Prefix"
			assert(api.counts(model,state)[to] < cap(model,state)[to],"No open affix for this conversion")
			if not (from == "Prefix" and f.prefixes or from == "Suffix" and f.suffixes) then remove(model,state,random,{type=from}) end
			local source=action.beastLevel and beastSource(model,state,action.beastLevel) or nil
			append(model,state,random,{type=to,source=source,recompute=source~=nil})
		elseif method == "beast_imprint" then
			assert(state.rarity == "MAGIC" and not fractured(state),"Imprinting requires a non-fractured magic item")
			state.imprint=nil; state.imprint=copyTable(state)
		elseif method == "beast_talisman_imprint" then
			assert(model.item.base.tags.talisman and state.rarity == "RARE" and not fractured(state),"Imprinting requires a non-fractured rare Talisman")
			state.imprint=nil; state.imprint=copyTable(state)
		elseif method == "restore_imprint" then
			local imprint=assert(state.imprint,"No saved imprint in this state")
			assert(not fractured(state),"Imprints cannot be applied to fractured items")
			assert(imprint.origin == model.initial.origin,"Imprint belongs to another starting item")
			state=copyTable(imprint)
		elseif method == "bench_reroll" then
			assert(state.rarity == "RARE" and (action.count == 1 or action.count == 3),"Choose one or three rare modifiers to reroll")
			-- Model the protection selection once for the whole bench action.
			if M.hasPartialLock(model,state) then api.selectPartialLocks(model,state,random) end
			for _=1,action.count do remove(model,state,random,{attackProtection=true}) end
			for _=1,action.count do append(model,state,random) end
		elseif method == "ducat_ukatoa" then
			local reason=M.methodChecks.ducat_ukatoa(model,state);assert(not reason,reason)
			-- The game does not publish side or tier odds; use an explicit assumption.
			local side=random()<0.5 and "Exarch" or "Eater"
			local tier=math.floor(random()*4)+1
			local id=choose(ukatoaChoices(model,side,tier),random)
			state.implicits={{id=id,side=side,tier=tier,range=M.rollRange(model.byId[id],random)}}
			state.baseImplicitRanges=nil;state.baseImplicit330=nil;state.baseImplicitReconstructed=nil;state.vendorImplicit=nil
		elseif method == "eldritch_implicit" then
			assert(not model.unresolvedEldritch or state.implicits,"Imported Eldritch tiers could not be identified; provide their structured implicit state")
			assert(model.item.type == "Helmet" or model.item.type == "Body Armour" or model.item.type == "Gloves" or model.item.type == "Boots","Eldritch currency requires helmet, body armour, gloves or boots")
			assert(not baseInfluences(state) and not model.item.synthesised,"Cannot combine Eldritch implicits with this influence or synthesis")
			assert(action.side == "Exarch" or action.side == "Eater","Choose Exarch or Eater")
			api.integer(action.tier,1,4,"Ember or Ichor tier")
			local choices={}
			for id,mod in pairs(data.itemMods.Eldritch) do if mod.type == action.side and tonumber(id:match("(%d+)$")) == action.tier then
				local weight=model.item:GetModSpawnWeight(mod); if weight > 0 then choices[#choices+1]={id=id,weight=weight} end
			end end
			table.sort(choices,function(a,b) return a.id < b.id end)
			local id=choose(choices,random); local kept={}
			for _,entry in ipairs(state.implicits or {}) do if entry.side ~= action.side then kept[#kept+1]=entry end end
			kept[#kept+1]={id=id,side=action.side,tier=action.tier,range=M.rollRange(model.byId[id],random)}; state.implicits=kept;state.baseImplicitRanges=nil;state.baseImplicit330=nil;state.baseImplicitReconstructed=nil
		elseif method == "eldritch_exalt" or method == "eldritch_annul" or method == "eldritch_chaos" then
			assert(not model.unresolvedEldritch or state.implicits,"Imported Eldritch tiers could not be identified; provide their structured implicit state")
			assert(state.rarity == "RARE","Eldritch affix currency requires a rare item")
			local exarch,eater=0,0
			for _,entry in ipairs(state.implicits or {}) do if entry.side == "Exarch" then exarch=entry.tier elseif entry.side == "Eater" then eater=entry.tier end end
			assert(exarch ~= eater,"The item needs an Eldritch influence to be dominant")
			local kind=exarch > eater and "Prefix" or "Suffix"
			if method == "eldritch_annul" then remove(model,state,random,{type=kind,attackProtection=true})
			elseif method == "eldritch_exalt" then append(model,state,random,{type=kind})
			else
				for i=#state.affixes,1,-1 do local entry=state.affixes[i]; if model.byId[entry.id].type == kind and not api.protected(entry,model.byId[entry.id],f) then table.remove(state.affixes,i) end end
				local target=math.min(cap(model,state)[kind],random() < 0.5 and 2 or 3)
				while api.counts(model,state)[kind] < target do append(model,state,random,{type=kind}) end
			end
		elseif method == "harvest_resistance" then
			if M.hasPartialLock(model,state) then api.selectPartialLocks(model,state,random) end
			local reason,matches=M.resistanceReason(model,state,action.from,action.to);assert(not reason,reason)
			local index=matches[math.floor(random()*#matches)+1]; local old=state.affixes[index]
			local id=resistanceTarget(model,old.id,action.from,action.to)
			old.id=id;old.range=M.rollRange(model.byId[id],random)
		elseif method == "harvest_damage" then
			if M.hasPartialLock(model,state) then api.selectPartialLocks(model,state,random) end
			local reason,matches=M.damageReason(model,state,action.from,action.to);assert(not reason,reason)
			local selected=matches[math.floor(random()*#matches)+1];local old=state.affixes[selected.index]
			old.id=selected.id;old.range=M.rollRange(model.byId[selected.id],random)
		elseif method == "blessed" then
			assert(#model.item.implicitModLines > 0 and not state.implicits,"No base implicit to reroll")
			state.baseImplicitRanges={}
			if model.blessed330 then state.baseImplicit330=true;state.baseImplicitRanges[1]=M.rollRange({model.blessed330},random)
			else
				state.baseImplicit330=nil;state.baseImplicitReconstructed=model.baseImplicitTemplates and true or nil
				for i,line in ipairs(model.item.implicitModLines) do state.baseImplicitRanges[i]=M.rollRange({model.baseImplicitTemplates and model.baseImplicitTemplates[i] or line.line},random) end
			end
		elseif method == "sacred" then
			assert(model.item.base.armour,"Sacred Orbs require armour")
			state.percentiles={}; for _,kind in ipairs({"Armour","Evasion","EnergyShield","Ward"}) do
				local low,high=model.item.base.armour[kind.."BaseMin"],model.item.base.armour[kind.."BaseMax"]
				if low and high and high > low then state.percentiles[kind]=math.floor(random()*(high-low+1))/(high-low) end
			end
			assert(next(state.percentiles),"This armour has no base defence variance")
		elseif method == "socket_bench" or method == "binding" then
			for _,socket in ipairs(state.sockets or {}) do assert(socket.color~="A","Abyssal sockets need a separate socket model") end
			local limit=M.socketLimit(model,state)
			assert(limit > 0,"This base cannot have equipment sockets")
			local count=method == "binding" and math.min(4,limit) or api.integer(action.count,2,limit,"socket count")
			-- Binding and socket bench recipes ignore the natural item-level limit;
			-- both remain constrained by the base's maximum socket count.
			local previous=state.sockets or {};local free=0;for _,socket in ipairs(previous) do free=math.max(free,socket.group+1) end
			state.sockets={};for i=1,count do
				state.sockets[i]=previous[i] and copyTable(previous[i]) or {color="W",group=free+i}
				if action.linked or method == "binding" then state.sockets[i].group=0 end
			end
			local old,group=nil,-1;for _,socket in ipairs(state.sockets) do local value=socket.group;if value ~= old then group=group+1;old=value end;socket.group=group end
			if method == "binding" then assert(state.rarity == "NORMAL","Binding requires a normal item"); state.rarity="RARE"; fill(model,state,random) end
		end
		api.clearPartialLocks(state);state.rollBlock=nil; return state
	end
	function M.validateState(model,state)
		-- Validate supported properties before the legacy affix and range checks.
		assert(type(state) == "table","Invalid crafting state")
		assert(not state.origin or state.origin == model.initial.origin,"Crafting state belongs to another starting item")
		if state.influences then
			assert(type(state.influences) == "table" and #state.influences <= 2,"Use at most two influences")
			local seen={}; for _,key in ipairs(state.influences) do assert(influences[key] and not seen[key] and model.item.base.influenceTags and model.item.base.influenceTags[key],"Invalid influence state"); seen[key]=true end
		end
		if model.item.type == "Flask" or model.item.type == "Tincture" then assert(state.rarity ~= "RARE","Flasks and tinctures cannot be rare") end
		if state.veil then
			local veil=state.veil
			assert(not state.corrupted and not state.mirrored and state.rarity~="NORMAL","A pending unveil requires an uncorrupted magic or rare item")
			assert(veil.type=="Prefix" or veil.type=="Suffix","Invalid unveil side")
			assert(veil.fractured==nil or type(veil.fractured)=="boolean","Invalid fractured unveil marker")
			assert(type(veil.choices)=="table" and #veil.choices>=1 and #veil.choices<=3,"Invalid unveil choices")
			local seen={};for _,id in ipairs(veil.choices) do
				local mod=model.byId[id]
				assert(not seen[id] and model.special[id] and (data.veiledMods[id] or model.unveiledJewels and model.unveiledJewels[id]) and mod and mod.type==veil.type,"Invalid unveil modifier")
				seen[id]=true
				if model.unveiledJewels and model.unveiledJewels[id] then
					for _,existing in ipairs(state.affixes or {}) do for _,left in ipairs(groups(model,id)) do for _,right in ipairs(groups(model,existing.id)) do assert(left~=right,"Unveil choice conflicts with an existing modifier") end end end
				end
			end
			if veil.fractured then for _,entry in ipairs(state.affixes or {}) do assert(not entry.fractured,"An item cannot have another fractured modifier") end end
		end
		for _,key in ipairs({"corrupted","mirrored"}) do assert(state[key] == nil or type(state[key]) == "boolean","Invalid item flag") end
		if state.quality then api.integer(state.quality,0,model.item.type=="Flask" and state.corrupted and 40 or 30,"item quality") end
		if state.baseImplicit330~=nil then assert(state.baseImplicit330==true and model.blessed330 and state.baseImplicitRanges,"Invalid updated base implicit") end
		if state.baseImplicitReconstructed~=nil then assert(state.baseImplicitReconstructed==true and model.baseImplicitTemplates and state.baseImplicitRanges and not state.baseImplicit330,"Invalid reconstructed base implicit") end
		if state.baseImplicitRanges then
			assert(type(state.baseImplicitRanges)=="table" and #state.baseImplicitRanges>0 and #state.baseImplicitRanges<=#model.item.implicitModLines,"Invalid base implicit range count")
			for _,value in ipairs(state.baseImplicitRanges) do
				local ranges=type(value)=="table" and value or {value}
				assert(#ranges>0 and #ranges<=20,"Invalid base implicit roll count")
				for _,range in ipairs(ranges) do assert(type(range)=="number" and range>=0 and range<=1,"Invalid base implicit roll") end
			end
		end
		if state.sockets then
			local base=model.item.base;local intrinsic=type(base.implicit)=="string" and tonumber(base.implicit:match("Has (%d+) Abyssal Sockets?")) or 0
			local limit=math.max(M.socketLimit(model,state),model.item.abyssalSocketCount or 0,intrinsic or 0)
			assert(type(state.sockets) == "table" and #state.sockets <= limit,"Invalid socket count")
			local ended,previous,previousColour,ordinary={},nil,nil,0
			for _,socket in ipairs(state.sockets) do
				assert(contains({"R","G","B","W","A"},socket.color),"Invalid socket colour");api.integer(socket.group,0,6,"socket group")
				if socket.color~="A" then ordinary=ordinary+1 end
				if socket.group==previous then assert(socket.color~="A" and previousColour~="A","Abyssal sockets cannot be linked") end
				if socket.group~=previous then
					assert(not ended[socket.group],"Linked sockets must form a contiguous group")
					if previous~=nil then ended[previous]=true end;previous=socket.group
				end
				previousColour=socket.color
			end
			assert(ordinary <= M.socketLimit(model,state),"Invalid ordinary socket count")
		end
		if state.implicits then
			assert(type(state.implicits) == "table" and #state.implicits <= 2 and not baseInfluences(state),"Invalid Eldritch implicit state")
			local seen={}
			for _,entry in ipairs(state.implicits) do
				local mod=assert(data.itemMods.Eldritch[entry.id],"Unknown Eldritch implicit")
				assert(mod.type == entry.side and not seen[entry.side] and tonumber(entry.id:match("(%d+)$")) == entry.tier and model.item:GetModSpawnWeight(mod) > 0,"Implicit tier, side or base does not match")
				seen[entry.side]=true;local ranges=type(entry.range) == "table" and entry.range or {entry.range or 0.5};assert(#ranges >= 1 and #ranges <= 20,"Invalid implicit range count")
				for _,range in ipairs(ranges) do assert(type(range) == "number" and range >= 0 and range <= 1,"Invalid implicit roll") end
			end
		end
		for kind,value in pairs(state.percentiles or {}) do assert(contains({"Armour","Evasion","EnergyShield","Ward"},kind) and type(value) == "number" and value >= 0 and value <= 1,"Invalid base defence roll") end
		local permitted=copyTable(model.initial)
		local seenGroups={};local legacySpeed={};local allLegacySpeed=true
		for _,entry in ipairs(model.initial.affixes or {}) do if M.isClusterSpeedMod(model,entry.id) then legacySpeed[entry.id]=(legacySpeed[entry.id] or 0)+1 end end
		local beastAllowed
		for _,entry in ipairs(state.affixes or {}) do
			local existing=model.byId[entry.id]
			if not existing or (existing.level or 0)>model.item.itemLevel then
				if not beastAllowed then beastAllowed={};for _,candidate in ipairs(beastSource(model,state,100)) do beastAllowed[candidate.id]=true end end
			end
			if M.isClusterSpeedMod(model,entry.id) then
				if (legacySpeed[entry.id] or 0)>0 then legacySpeed[entry.id]=legacySpeed[entry.id]-1 else allLegacySpeed=false end
			end
			for _,group in ipairs(groups(model,entry.id)) do assert(not seenGroups[group] or group==M.clusterSpeedGroup and allLegacySpeed,"State has conflicting modifier groups");seenGroups[group]=true end
			local mod=model.byId[entry.id]
			if model.special[entry.id] or influenced(model,entry.id) or entry.fractured or beastAllowed and beastAllowed[entry.id] or state.baseItem and mod.weightKey and model.item:GetModSpawnWeight(mod,model.extraTags) > 0 then permitted.affixes[#permitted.affixes+1]=copyTable(entry) end
		end
		local old=model.initial; model.initial=permitted
		local ok,result=pcall(originalValidate,model,state); model.initial=old; assert(ok,result)
		if state.veil then assert(api.counts(model,state)[state.veil.type] < cap(model,state)[state.veil.type],"No slot for the pending unveil") end
		return result
	end
	-- Record choices already observed by the user, or a hypothetical offer. This
	-- does not generate a veil or estimate the chance of seeing these choices.
	function M.recordJewelOffers(model,state,choices,fractured)
		assert(model.item.type=="Jewel" and model.unveiledJewels and next(model.unveiledJewels),"This jewel has no supported unveil choices")
		assert(type(choices)=="table" and #choices>=1 and #choices<=3,"Select one to three observed choices")
		assert(fractured==nil or type(fractured)=="boolean","Invalid fractured unveil marker")
		local first=assert(model.unveiledJewels[choices[1]],"Choose an eligible jewel modifier")
		local next=copyTable(state);next.veil={type=first.type,choices=copyTable(choices),fractured=fractured or nil}
		return M.validateState(model,next)
	end
	function M.catalog(raw,query,limit,initialState)
		local result=originalCatalog(raw,query,limit); local model=M.model(raw)
		if model.item.clusterJewel then for _,entry in ipairs(result.modifiers) do if M.isClusterSpeedMod(model,entry.id) then entry.group=M.clusterSpeedGroup end end end
		local state=initialState and M.validateState(model,initialState) or model.initial
		local modifiers=require("Modules.CraftingModifiers");local inspection=modifiers.inspect(model,state);local rows=modifiers.filter(inspection,query,nil,nil,nil,"Eligible first")
		result.modifierTable={total=#rows,totalWeight=inspection.totalWeight,note=inspection.note,rows={}}
		for i=1,math.min(limit or 50,#rows) do result.modifierTable.rows[i]=copyTable(rows[i]) end
		result.fossils=copyTable(model.fossils);for _,entry in ipairs(result.fossils) do entry.priceKey=M.priceKey({method="fossil",fossils={entry.id}}) end; result.harvestTags=copyTable(tags); result.influences=copyTable(influences)
		result.veiled={}; for i=1,math.min(limit or 50,#model.veiled) do local entry=model.veiled[i]; result.veiled[#result.veiled+1]={id=entry.id,text=table.concat(entry.mod," / "),weight=entry.weight,type=entry.mod.type} end
		result.potentialInfluenced={}
		for _,entry in ipairs(model.influencePool) do if influenced(model,entry.id) and #result.potentialInfluenced < (limit or 50) and (entry.id.." "..table.concat(entry.mod," / ")):lower():find((query or ""):lower(),1,true) then
			result.potentialInfluenced[#result.potentialInfluenced+1]={id=entry.id,text=table.concat(entry.mod," / "),influence=influenced(model,entry.id),level=entry.mod.level}
		end end
		result.dataPatch=A.data().patch;result.modifierPatch=A.data().modifierPatch
		result.benchCostSource=copyTable(A.data().source)
		result.benchCostClient={version="3.30.0.1.4",benchSha256="d664372c28784a65f9c10c1b8d36608d084ac698a6caaafbaf4be40be8b6f76a"}
		result.benchCostOverlays={{patch="3.30",description="Full prefix/suffix lock costs vary by item type",source="https://www.pathofexile.com/forum/view-thread/4013680"}}
		result.initialState=copyTable(state)
		result.nativeStats=require("Modules.CraftingItemStats").values(M,model,state)
		local available=require("Modules.CraftingAvailability").check
		result.methodAvailability={};for _,method in ipairs(M.methods) do
			local allowed,reason=available(method,state,model)
			local configuration=allowed and M.configurationReason and M.configurationReason(model,state,{method=method})
			result.methodAvailability[#result.methodAvailability+1]={method=method,label=M.labels[method],available=allowed,unavailableReason=not allowed and reason or nil,configurationRequired=configuration}
		end
		result.methodAvailabilityNote="Availability checks general item prerequisites; individual options and outcomes may have further restrictions."
		for _,catalog in ipairs({{method="bench",rows=result.bench},{method="essence",rows=result.essences}}) do
			local allowed,reason=available(catalog.method,state,model)
			for _,entry in ipairs(catalog.rows) do
				local why=reason
				if allowed then
					if catalog.method=="bench" then why=M.benchReason(model,state,entry.id) else why=M.essenceReason(model,state,entry.id) end
				end
				entry.available=not why;entry.unavailableReason=why or nil
				entry.priceKey=entry.id
				if catalog.method=="bench" then
					local cost,sources=require("Modules.CraftingBenchCosts").cost(M.context(model,state),entry.id)
					entry.components=cost or {[entry.id]=1};entry.ingredientCostsKnown=cost~=nil;entry.costSources=sources
				end
			end
		end
		result.benchServiceCosts={};local rerollAllowed,rerollReason,rerollPossible
		for _,action in ipairs({{method="remove_crafted"},{method="bench_remove_enchant"},{method="bench_reroll",count=1},{method="bench_reroll",count=3}}) do
			local label=M.labels[action.method]..(action.count and " / "..action.count or "")
			if #result.benchServiceCosts<(limit or 50) and (action.method.." "..label):lower():find((query or ""):lower(),1,true) then
				local cost,sources=require("Modules.CraftingBenchCosts").service(M.context(model,state),action)
				local allowed,reason
				if action.method=="bench_reroll" then
					if rerollAllowed==nil then rerollAllowed,rerollReason=available(action.method,state,model);if rerollAllowed then rerollPossible=M.benchRerollChoices(M.context(model,state),state) end end
					allowed,reason=rerollAllowed,rerollReason
					if allowed and not rerollPossible[action.count] then allowed=false;reason="No modeled removal sequence can reroll "..action.count.." modifiers." end
				else allowed,reason=available(action.method,state,model) end
				result.benchServiceCosts[#result.benchServiceCosts+1]={action=action,label=label,priceKey=M.priceKey(action),components=cost or {[M.priceKey(action)]=1},ingredientCostsKnown=cost~=nil,costSources=sources,available=allowed,unavailableReason=not allowed and reason or nil,
					selectionNote=allowed and action.method=="bench_reroll" and "A modeled removal sequence exists; other selections or later rolls can fail." or nil}
			end
		end
		result.harvestOptions={}
		for _,method in ipairs({"harvest_reforge","harvest_augment","harvest_resistance","harvest_damage"}) do
			local allowed,reason=available(method,state,model);local choices=allowed and M.actionOptions(model,state,method) or {};local selected={}
			for i=1,math.max(0,math.min(limit or 50,#choices)) do
				selected[i]=copyTable(choices[i]);selected[i].priceKey=M.priceKey(selected[i].action)
				selected[i].components=M.components(selected[i].action,state,model)
			end
			local conditional=allowed and M.hasPartialLock(M.context(model,state),state)
			local conversion=method=="harvest_resistance" or method=="harvest_damage"
			result.harvestOptions[#result.harvestOptions+1]={method=method,available=allowed,unavailableReason=not allowed and reason or nil,options=selected,total=#choices,
				selectionNote=conditional and (conversion and "A conversion is offered if a modeled protection selection leaves an eligible modifier. Other selections can fail."
					or "A tag is offered if a modeled protection selection leaves a legal tagged modifier and removable original when required. Other selections or later rolls can fail.") or nil}
		end
		if model.synthesisGroups then
			result.synthesisGroups={}
			for index,group in ipairs(model.synthesisGroups) do
				local lines={};for _,line in ipairs(require("Modules.CraftingSynthesisGroups").lines(model,state,index)) do lines[#lines+1]=itemLib.applyRange(line.line,line.range or 0.5) end
				local retained=not state.corruptedImplicits
				for _,value in ipairs(state.synthRetained or {}) do if value==index then retained=true end end
				local ids={};for _,candidate in ipairs(require("Modules.CraftingSynthesisGroups").candidates(group,state,index)) do ids[#ids+1]=candidate.id end
				result.synthesisGroups[#result.synthesisGroups+1]={index=index,lines=lines,retained=retained,candidates=ids,ambiguous=#ids>1}
			end
		end
		if model.unresolvedEldritch and not state.implicits then result.importWarning="At least one imported Eldritch implicit has an ambiguous tier; supply a structured implicit state before changing Eldritch implicits or using dominance." end
		if model.unresolvedCorruption and not state.corruptedImplicits then
			local warning="A corruption implicit could not be identified uniquely. It remains on the item, but implicit targets cannot be evaluated until it is identified."
			result.importWarning=result.importWarning and (result.importWarning.." "..warning) or warning
		end
		return result
	end
	function M.actionOptions(model,state,method)
		local result={}
		local function option(label,values) values.method=method; result[#result+1]={label=label,action=values} end
		if method == "bench" then for _,entry in ipairs(model.bench) do if not M.benchReason(model,state,entry.id) then option(table.concat(entry.mod," / "),{modId=entry.id}) end end
		elseif method == "essence" then for _,entry in ipairs(model.essences) do if not M.essenceReason(model,state,entry.id) then option(entry.name,{essenceId=entry.id}) end end
		elseif method == "fossil" then for _,entry in ipairs(model.fossils) do option(entry.name,{fossils={entry.id}}) end
		elseif method == "harvest_reforge" or method == "harvest_augment" then result=M.harvestChoices(model,state,method)
		elseif method == "influence_exalt" or method == "beast_influence" then for key in pairs(influences) do if method == "influence_exalt" or contains(state.influences,key) then option(key,{influence=key}) end end
		elseif method == "unveil" then for _,id in ipairs(state.veil and state.veil.choices or {}) do option(table.concat(model.byId[id]," / "),{modId=id}) end
		elseif method == "beast_aspect" then for id,mod in pairs(data.beastCraft) do if id:find("AspectCrafted",1,true) and not contains(mod.weightKey,"deepwater_pantheon_aspect") then option(table.concat(mod," / "),{modId=id}) end end
		elseif method == "bench_reroll" then local possible=M.benchRerollChoices(model,state);if possible[1] then option("Reroll one random modifier",{count=1}) end;if possible[3] then option("Reroll three random modifiers",{count=3}) end
		elseif method == "eldritch_implicit" then for _,side in ipairs({"Exarch","Eater"}) do for tier=1,4 do option(side.." | "..({"Lesser","Greater","Grand","Exceptional"})[tier],{side=side,tier=tier}) end end
		elseif method == "harvest_resistance" then result=M.resistanceOptions(model,state)
		elseif method == "harvest_damage" then result=M.damageOptions(model,state)
		elseif method == "socket_bench" then for count=2,M.socketLimit(model,state) do option(count.." sockets (added sockets white)",{count=count}); option("Set "..count.." sockets and link them",{count=count,linked=true}) end
		end
		table.sort(result,function(a,b) return a.label < b.label end)
		return result
	end
	function M.priceKey(action)
		if action.method == "bench" then return action.modId end
		if action.method == "essence" then return action.essenceId end
		if action.method == "fossil" then local ids=copyTable(action.fossils or {});table.sort(ids);return "fossil:"..table.concat(ids,"+") end
		if action.method == "harvest_reforge" or action.method == "harvest_augment" then return action.method..":"..tostring(action.tag) end
		if action.method == "harvest_damage" then return action.method..":"..tostring(action.from)..":"..tostring(action.to) end
		if action.method == "influence_exalt" then return action.method..":"..tostring(action.influence) end
		if action.method == "eldritch_implicit" then return action.method..":"..tostring(action.side)..":"..tostring(action.tier) end
		if action.method == "bench_reroll" then return action.method..":"..tostring(action.count) end
		if action.method == "socket_bench" then return action.method..":"..tostring(action.count)..":"..tostring(action.linked or false) end
		return action.method
	end
	function M.components(action,state,model)
		if (action.method=="awakener" or action.method=="recombine" or action.method=="recombine_predictable") and type(action.donorItem)=="string" and action.donorItem~="" then
			return {[M.priceKey(action)]=1,["donor:"..require("sha1")(action.donorItem)]=1}
		end
		if action.method == "harvest_reforge" or action.method == "harvest_augment" then
			-- Influence is a separate reforge with no corresponding augment.
			local entry=assert(harvestCosts[action.tag],"Select a supported Harvest tag")
			local augment=action.method=="harvest_augment"
			assert(not augment or entry[3],"No Harvest augment for that tag")
			local result={[entry[1]]=augment and entry[3] or entry[2]}
			if augment or action.tag=="influence" then result.sacred_lifeforce=1 end
			if entry[4] then result.crystallised_rancour=entry[4] end
			return result
		end
		if action.method == "harvest_resistance" then
			-- HarvestCraftOptions, client 3.30.0.1.4: the two resource types
			-- follow the source and destination elements, each at 300.
			local lifeforce={fire="wild_lifeforce",cold="primal_lifeforce",lightning="vivid_lifeforce"}
			local from,to=lifeforce[action.from],lifeforce[action.to]
			assert(from and to and from~=to,"Choose two different elemental resistances")
			return {[from]=300,[to]=300}
		end
		if action.method == "harvest_damage" then
			return copyTable(assert(harvestDamageData().costs[tostring(action.from)..":"..tostring(action.to)],"Choose different elemental damage types"))
		end
		if model and (action.method=="bench" or action.method=="remove_crafted" or action.method=="bench_reroll") then
			local context=state and M.context(model,state) or model;local bench=require("Modules.CraftingBenchCosts")
			local cost=action.method=="bench" and bench.cost(context,action.modId) or bench.service(context,action)
			if cost then return cost end
		end
		if action.method == "unveil" or action.method == "restore_imprint" then return {} end
		if action.method == "fossil" then
			local result={["resonator:"..#action.fossils]=1};for _,id in ipairs(action.fossils) do result[id]=(result[id] or 0)+1 end;return result
		end
		if action.method == "socket_bench" then
			local result={}
			-- The legacy combined action sets the count before linking. Do not
			-- charge for that preparation when the input already has the count.
			local changeCount=not action.linked or not state or #(state.sockets or {})~=action.count
			for _,bench in ipairs(A.data().bench) do if changeCount and bench.actions.change_socket_count == action.count or action.linked and bench.actions.link_sockets == action.count then
				for id,amount in pairs(bench.cost) do result[id]=(result[id] or 0)+amount end
			end end
			if next(result) then
				if state and state.corrupted then local amount=0;for _,value in pairs(result) do amount=amount+value end;result["Metadata/Items/Currency/CurrencyCorrupt"]=amount end
				return result
			end
		end
		return {[M.priceKey(action)]=1}
	end
	function M.optimizeFossils(raw,targets,options)
		options=options or {};local fossils=options.fossils
		assert(type(fossils) == "table" and #fossils >= 1 and #fossils <= 8,"Choose one to eight candidate fossils")
		local sockets=api.integer(options.maxSockets or 2,1,4,"maximum resonator sockets")
		local trials=api.integer(options.trials or 100,1,2000,"trials per combination")
		local seen={};for _,id in ipairs(fossils) do assert(A.data().fossils[id] and not seen[id],"Unknown or duplicate candidate fossil");seen[id]=true end
		local combinations={}
		local function visit(at,selected)
			if #selected > 0 then combinations[#combinations+1]=copyTable(selected) end
			if #selected == sockets then return end
			for i=at,#fossils do selected[#selected+1]=fossils[i];visit(i+1,selected);table.remove(selected) end
		end
		visit(1,{})
		assert(#combinations*trials <= 20000,"Use at most 20000 total optimizer trials")
		local result={combinations={},trialsPerCombination=trials,limitations={"Exhaustive over the supplied fossil subset only.","Subsets with complete prices and observed successes rank first by cost per observed success. Remaining subsets rank by sampled success chance; zero observations are not impossibility.","Nearby estimates with overlapping sampling intervals do not establish a reliable ordering."}}
		for index,ids in ipairs(combinations) do
			local action={method="fossil",fossils=ids}
			local ok,simulation=pcall(M.simulate,raw,{steps={action},targets=targets,initialState=options.initialState,requirements=options.requirements,requiredGroups=options.requiredGroups},{trials=trials,maxActions=1,forceFirstAction=true,seed=((options.seed or 104729)+index-2)%2147483646+1,prices=options.prices,actionPrices=options.actionPrices,priceBook=options.priceBook,currency=options.currency,
				checkpoint=options.checkpoint and function(progress) progress.combination=index;progress.combinations=#combinations;options.checkpoint(progress) end})
			if ok then result.costCurrency=simulation.costCurrency;result.priceSource=simulation.priceSource;result.priceQuotedAt=simulation.priceQuotedAt;result.resourcePriceOverridesSupplied=simulation.resourcePriceOverridesSupplied;result.actionPriceOverridesSupplied=simulation.actionPriceOverridesSupplied end
			result.combinations[#result.combinations+1]=ok and {fossils=ids,priceKey=M.priceKey(action),successChance=simulation.successChance,successes=simulation.successes,confidenceLow=simulation.confidenceLow,confidenceHigh=simulation.confidenceHigh,meanCost=simulation.meanCost,costPerSuccess=simulation.costPerSuccess,costCurrency=simulation.costCurrency,unpriced=simulation.unpriced,actionPriceOverridesApplied=simulation.actionPriceOverridesApplied} or {fossils=ids,priceKey=M.priceKey(action),error=tostring(simulation):match("^[^\n]+")}
		end
		result.combinations=require("Modules.CraftingFossilResults").sort(result.combinations)
		return result
	end
	function M.calculate(raw,action,targets,initialState)
		local model=M.model(raw);local state=initialState and M.validateState(model,initialState) or copyTable(model.initial)
		if M.context then model=M.context(model,state) end
		local method=M.baseCurrency and M.baseCurrency(action) or action.method
		assert(method == "exalt" or method == "augmentation" or method == "regal" or method == "influence_exalt","Exact next-mod odds support augmentation, regal, exalt and influence slams")
		M.validateRecipe({steps={action},targets=targets})
		for _,group in ipairs(targets) do assert(not group.minRoll,"Use simulation for roll-value thresholds") end
		-- Validate the transition independently, then enumerate every legal next modifier.
		M.action(model,state,action,function() return 0.5 end)
		if method == "regal" then state.rarity="RARE" end
		local options={}
		if M.consumesStrands and M.consumesStrands(action) and (state.memoryStrands or 0) > 0 then state.memoryActive=state.memoryStrands end
		if M.isFoulbornCurrency and M.isFoulbornCurrency(action) then state.memoryFoulborn=true end
		if action.method == "influence_exalt" then state.influences={action.influence};options.influence=action.influence end
		local entries=pool(model,state,options);local total,success=0,0;local outcomes={}
		for _,entry in ipairs(entries) do
			local nextState=copyTable(state);nextState.affixes[#nextState.affixes+1]={id=entry.id,range=0.5}
			local hit=M.matches(nextState,targets,nil,model);total=total+entry.weight;if hit then success=success+entry.weight end
			outcomes[#outcomes+1]={id=entry.id,weight=entry.weight,matches=hit,text=table.concat(model.byId[entry.id]," / ")}
		end
		assert(total > 0,"No legal next modifier")
		for _,entry in ipairs(outcomes) do entry.chance=entry.weight/total*100 end
		return {exactFor="One weighted affix draw, conditional on the supplied state and native pool",successChance=success/total*100,totalWeight=total,matchingWeight=success,outcomes=outcomes,dataPatch=A.data().patch,modifierPatch=A.data().modifierPatch,limitations=copyTable(M.limits)}
	end
	M.limits={"Independent PoE 1 crafting model uses 3.30.0.2.2 supplemental data; this is not complete Craft of Exile parity.",
		"Harvest damage conversion uses client eligibility groups and ingredient costs, but assumes matching elemental modifier IDs correspond to tiers and chooses eligible modifiers uniformly. The mapping and selection odds are unverified; unmatched families are rejected.",
		"Light Radius accuracy modifiers use 3.30 crafting ranges; existing legacy values are retained until rerolled.",
		"Abyss jewel crafting uses the 3.30 client weight changes, including the Assembled Eye pool and seven removed natural modifiers. Existing removed modifiers are retained until removed.",
		"The 3.30 unveiled jewel modifiers can be imported, inspected and added to hypothetical items. Unveil offers and their acquisition are not simulated; native calculation support varies by modifier.",
		"Current coverage includes core currencies, ordinary jewels/flasks/tinctures, bench crafts, essences, weighted fossils, Harvest tag crafts, influence slams, Awakener, fractures, veiled choices, Bestiary, Eldritch crafts, base implicit/defence rerolls and deterministic socket/link bench crafts.",
		"Tangled Fossils require a revealed resonator outcome. Automatic predictable recombination odds, unique generation and many 3.30 rules are not implemented.",
		"The standard Orb of Annulment uses the announced 3.30 attack/caster blocker rule. Some specialized supplemental sources remain pinned to 3.29.3.6 where not explicitly updated.",
		"Partial locks use uniform random selection from all modifiers on the protected side, including fractures; group conflicts and other interactions are assumptions. Core affix actions, Harvest reforge/augment and elemental conversions, and independent socket, quality, implicit and enchantment crafts are supported; other interactions are rejected.",
		"Bench ingredient prices use the 3.30.0.1.4 client catalogue, which matches the 3.30.0.2.2 export.",
		"Rare modifier counts and Eldritch Chaos counts are model assumptions. Numeric display rolls and sampling intervals do not establish exact in-game odds.",
		"Abyssal socket modifier changes use an experimental last-socket and unlinked-white restoration model; placement, zero-socket behavior and removal are unverified.",
		"Every result is a separate hypothetical item. Costs use supplied prices; no game currency is spent."}
	require("Modules.CraftingProperties").extend(M,A,api)
	require("Modules.CraftingCorruption").extend(M,A,api)
	require("Modules.CraftingSockets").extend(M,A,api)
	require("Modules.CraftingEnchants").extend(M,A,api)
	require("Modules.CraftingKatakohi").extend(M)
	require("Modules.CraftingMemory").extend(M,A,api)
	require("Modules.CraftingRecombination").extend(M,A,api)
	require("Modules.CraftingPredictable").extend(M,A,api)
	require("Modules.CraftingLeague").extend(M,A,api)
	require("Modules.CraftingAllflame").extend(M,A,api)
	require("Modules.CraftingGwennen").extend(M,api)
end
return A
