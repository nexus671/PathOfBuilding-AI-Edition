-- Read visible clipboard properties and unambiguous pinned base properties.
-- Hidden affix identities remain unknown.
-- cspell:ignore RGBWAD
local M={}
-- A displayed gem name can have multiple data records. Infer Exceptional only
-- when all records for that name and class agree, and leave unknown names unset.
local exceptionalNames,ordinaryNames
local function exceptionalGem(name,class)
	if not exceptionalNames then
		exceptionalNames={};ordinaryNames={}
		for _,gem in pairs(data.gems) do
			local classes=gem.grantedEffect and {gem.grantedEffect.support and "Support Gems" or "Skill Gems"} or {"Skill Gems","Support Gems"}
			local value=gem.grantedEffect and type(gem.tags)=="table" and (gem.tags.exceptional and "yes" or "no") or "ambiguous"
			for _,gemClass in ipairs(classes) do for _,base in pairs({gem.itemBaseName,gem.baseTypeName}) do
				if base then
					local key=gemClass.."\0"..base:lower();local existing=exceptionalNames[key]
					exceptionalNames[key]=existing and existing~=value and "ambiguous" or value
					local ordinary=gem.grantedEffect and not gem.grantedEffect.support and not gem.vaalGem and type(gem.id)=="string" and not gem.id:match("Alt[XYZ]$") and type(gem.variantId)=="string" and type(gem.grantedEffectId)=="string" and gem.variantId:lower()==gem.grantedEffectId:lower() and gem.itemBaseName==base
					local kind=ordinary and "ordinary" or "other";local prior=ordinaryNames[key]
					ordinaryNames[key]=prior and prior~=kind and "ambiguous" or kind
				end
			end end
		end
	end
	local result=name and exceptionalNames[class.."\0"..name:lower()]
	if result=="yes" then return true elseif result=="no" then return false end
end
function M.parse(raw,area)
	assert(type(raw)=="string" and #raw>0 and #raw<=24000 and not raw:find("\0"),"Paste a copied game item (up to 24 KiB)")
	raw=raw:gsub("\r\n","\n");local rarity=assert(raw:match("Rarity: (%a+)"),"The clipboard has no item rarity")
	local class=raw:match("Item Class: ([^\n]+)")
	local header=raw:match("Rarity: [^\n]+\n(.-)\n%-%-%-%-%-%-%-%-") or raw:match("Rarity: [^\n]+\n(.*)")
	-- Base names such as "Contract: Bunker" also contain a colon.
	local fields={["Item Level"]=true,Quality=true,Sockets=true,["Stack Size"]=true,Level=true,["Map Tier"]=true}
	local names={};for line in (header or ""):gmatch("[^\n]+") do if line=="--------" or fields[line:match("^([%w ]+): ") or ""] then break end;names[#names+1]=line end
	assert(#names>0,"The clipboard has no item name")
	local markers={};for line in raw:gmatch("[^\n]+") do markers[line]=true end
	local ok,native=pcall(function() return new("Item"):Item(raw) end)
	local base=ok and native.base and native.baseName or nil
	-- Current ordinary map items encode their tier in the base name. Magic map
	-- names may have affixes around that base, even when native data is older.
	local tierInName
	if class=="Maps" and (rarity=="Normal" or rarity=="Magic" or rarity=="Rare") then
		local name=names[#names]
		if rarity=="Magic" then tierInName=name and (name:match("^Map %(Tier (%d+)%)$") or name:match("^Map %(Tier (%d+)%) .+$") or name:match("^.+ Map %(Tier (%d+)%)$") or name:match("^.+ Map %(Tier (%d+)%) .+$"))
		else tierInName=name and (name:match("^Map %(Tier (%d+)%)$") or name:match("^Blighted Map %(Tier (%d+)%)$") or name:match("^Blight%-ravaged Map %(Tier (%d+)%)$")) end
		if tierInName then
			tierInName=tonumber(tierInName);assert(tierInName>=1 and tierInName<=16,"Invalid copied map tier")
			base="Map (Tier "..tierInName..")"
		end
	end
	if not base then
		assert(rarity:lower()~="magic","The magic item's base could not be identified; configure it explicitly")
		-- An identified rare or unique normally has a separate name and base.
		-- A truncated single-line copy cannot establish which one it contains.
		local unidentified=markers.Unidentified
		for line in pairs(markers) do if line:match("^Unidentified %(Tier %d+%)$") then unidentified=true;break end end
		if #names>1 or (rarity:lower()~="rare" and rarity:lower()~="unique" and rarity:lower()~="relic") or unidentified then base=names[#names] end
	end
	-- The clipboard's gem labels differ from the filter language's class names.
	class=({["Active Skill Gems"]="Skill Gems",["Support Skill Gems"]="Support Gems"})[class] or class
	local library=require("Modules.LootFilterLibrary")
	-- An explicit clipboard class wins. Infer only when the item base itself is
	-- known, or the visible normal/currency/gem name is the base name.
	local baseRarity=rarity:lower()
	if not class and (ok and native.base or baseRarity=="normal" or baseRarity=="currency" or baseRarity=="gem") then class=library.baseClass(base) end
	local tier
	for line in pairs(markers) do
		local value=line:match("^Unidentified %(Tier (%d+)%)$")
		if value then
			value=tonumber(value);assert(value and value<=1e9,"Invalid clipboard unidentified tier")
			assert(tier==nil or tier==value,"Conflicting clipboard unidentified tier");tier=value
		end
	end
	local mapped={normal="Normal",magic="Magic",rare="Rare",unique="Unique",relic="Unique",currency="Normal",gem="Normal",quest="Normal"}
	local item={BaseType=base,Class=class,Rarity=assert(mapped[rarity:lower()],"Unsupported clipboard rarity"),AreaLevel=area,
		Identified=not markers.Unidentified and tier==nil,Corrupted=markers.Corrupted==true or markers["Twice Corrupted"]==true,
		TwiceCorrupted=markers["Twice Corrupted"]==true,Mirrored=markers.Mirrored==true}
	-- A recognizable Blight map header and its visible implicit establish
	-- the variant. Missing evidence remains unknown; magic names may have affixes.
	if class=="Maps" and tierInName and markers["Area is infested with Fungal Growths (implicit)"] then
		local name=names[#names];local function hasBase(prefix)
			local base=prefix.." Map (Tier "..tierInName..")"
			return name==base or rarity=="Magic" and (name:sub(1,#base+1)==base.." " or name:sub(-#base-1)==" "..base or name:find(" "..base.." ",1,true)~=nil)
		end
		if hasBase("Blighted") then item.BlightedMap=true;item.UberBlightedMap=false
		elseif hasBase("Blight-ravaged") then item.UberBlightedMap=true end
	end
	for line in raw:gmatch("[^\n]+") do
		-- Stash notes are player-written text, not item modifier evidence.
		local note=line:match("^Note:") ~= nil
		-- A marked implicit proves its presence; an absent marker may mean the
		-- clipboard text is incomplete and cannot prove the opposite.
		if not note and line:match("%S.+ %(implicit%)%s*$") then item.HasImplicitMod=true end
		-- Visible enchant markers prove an enchantment exists; their absence in
		-- a possibly incomplete copy does not prove that none exists.
		if not note and line:match("%S.+ %(enchant%)%s*$") then item.AnyEnchantment=true end
		if not note and line:lower():find("(fractured)",1,true) then item.FracturedItem=true end
		-- GGG's filter property counts the specific "Adds X Passive Skills"
		-- cluster enchant, not jewel sockets or other added-passive lines.
		if base=="Small Cluster Jewel" or base=="Medium Cluster Jewel" or base=="Large Cluster Jewel" then
			local count=line:match("^Adds (%d+) Passive Skills %(enchant%)%s*$")
			if count then
				count=tonumber(count);assert(count and count==count and count<=1e9,"Invalid clipboard passive count")
				assert(item.EnchantmentPassiveNum==nil or item.EnchantmentPassiveNum==count,"Conflicting clipboard passive counts")
				item.EnchantmentPassiveNum=count
			end
		end
		-- Advanced item descriptions can identify some explicit modifier names.
		-- Keep them separate from a complete list: the copy may be truncated.
		if item.Identified and line:match("^%{%s*.-%}%s*$") then
			local name=line:match('Modifier%s+"([^"]+)"')
			if name and (line:find("Prefix Modifier",1,true) or line:find("Suffix Modifier",1,true)) then
				assert(#name<=240,"Invalid clipboard modifier name")
				item.KnownExplicitMods=item.KnownExplicitMods or {};item.KnownExplicitMods[#item.KnownExplicitMods+1]=name
				assert(#item.KnownExplicitMods<=40,"Too many clipboard modifier names")
			end
		end
		local strands=line:match("^Memory Strands: (%d+)$")
		if strands then
			strands=tonumber(strands);assert(strands<=100,"Invalid clipboard memory strands")
			assert(item.MemoryStrands==nil or item.MemoryStrands==strands,"Conflicting clipboard memory strands")
			item.MemoryStrands=strands
		end
	end
	local properties=library.baseProperties(item.BaseType,item.Rarity)
	item.DropLevel=properties.DropLevel;item.Width=properties.Width;item.Height=properties.Height
	item.BaseDefencePercentile=library.baseDefencePercentile(item.BaseType,item.Class,item.Rarity)
	if tier and tier>=0 and tier<=5 then item.UnidentifiedItemTier=tier end
	-- Ordinary equipment copies list each influence on a separate marker line.
	-- Unique items and maps can carry special influence effects; do not infer
	-- their complete influence set from the absence of these markers.
	local equipment={Helmet=true,["Body Armour"]=true,Gloves=true,Boots=true,Shield=true,Quiver=true,Amulet=true,Ring=true,Belt=true}
	if ok and native.base and (rarity=="Normal" or rarity=="Magic" or rarity=="Rare") and (equipment[native.type] or data.weaponTypeInfo[native.type]) then
		item.HasInfluence={}
		for _,name in ipairs({"Shaper","Elder","Crusader","Hunter","Redeemer","Warlord"}) do
			if markers[name.." Item"] then item.HasInfluence[#item.HasInfluence+1]=name end
		end
		if #item.HasInfluence==0 then item.HasInfluence={"None"} end
		item.ShaperItem=markers["Shaper Item"]==true;item.ElderItem=markers["Elder Item"]==true
	end
	for key,field in pairs({ItemLevel="Item Level",Quality="Quality",StackSize="Stack Size",MapTier="Map Tier"}) do
		for line in raw:gmatch("[^\n]+") do
			local text=line:match("^"..field..":%s*([%+%-]?%d+)")
			if key=="Quality" and not text then text=line:match("^Quality %([%w '%-]+%)%s*:%s*([%+%-]?%d+)") end
			if text then
				local value=tonumber(text);assert(value and value==value and math.abs(value)<=1e9,"Invalid clipboard "..field)
				assert(item[key]==nil or item[key]==value,"Conflicting clipboard "..field)
				item[key]=value
			end
		end
	end
	if tierInName then
		assert(item.MapTier==nil or item.MapTier==tierInName,"Conflicting clipboard map tier")
		item.MapTier=tierInName
	end
	if class and class:find("Gems",1,true) then
		if rarity:lower()=="gem" and (class=="Skill Gems" or class=="Support Gems") then
			item.Exceptional=exceptionalGem(item.BaseType,class)
		end
		for line in raw:gmatch("[^\n]+") do
			local level=line:match("^Level:%s*(%d+)")
			if level then
				level=tonumber(level);assert(level and level<=1e9,"Invalid clipboard gem level")
				assert(item.GemLevel==nil or item.GemLevel==level,"Conflicting clipboard gem level")
				item.GemLevel=level
			end
		end
		-- Only infer a transfigured base when the bundled gem data identifies
		-- one unambiguous ordinary gem with a matching displayed-name prefix.
		local id=item.BaseType and data.gemForBaseName[item.BaseType:lower()];local gem=id and data.gems[id]
		if gem and not gem.vaalGem then
			if id:match("Alt[XYZ]$") then
				local found,ambiguous
				for _,candidate in pairs(data.gemsByGameId[gem.gameId] or {}) do
					if not candidate.vaalGem and not candidate.id:match("Alt[XYZ]$") and gem.name:sub(1,#candidate.name+4)==candidate.name.." of " then
						if found and found~=candidate.name then ambiguous=true else found=candidate.name end
					end
				end
				if found and not ambiguous then item.TransfiguredGem=found end
			elseif class=="Skill Gems" and ordinaryNames and ordinaryNames[class.."\0"..item.BaseType:lower()]=="ordinary" then item.TransfiguredGem=false end
		end
	end
	local sockets
	for line in raw:gmatch("[^\n]+") do
		local value=line:match("^Sockets:[ \t]*(.*)$")
		if value~=nil then
			value=value:gsub("%s+$",""):gsub("%s+"," ")
			assert(sockets==nil or sockets==value,"Conflicting clipboard socket layouts")
			sockets=value
		end
	end
	if sockets~=nil or library.hasNoSockets(class) then
		local groups,colours,linked={},{},0;sockets=sockets or ""
		if sockets~="" and sockets~="0" then for group in sockets:gmatch("%S+") do
			assert(group:match("^[RGBWAD%-]+$") and not group:find("^%-") and not group:find("%-$") and not group:find("%-%-"),"Invalid clipboard socket layout")
			-- Abyss and Delve sockets cannot link adjacent ordinary sockets.
			local separated=group:gsub("([AD])"," %1 "):gsub("%-","")
			for colors in separated:gmatch("%S+") do groups[#groups+1]=colors;colours[#colours+1]=colors;linked=math.max(linked,#colors) end
		end end
		item.SocketColours=table.concat(colours);item.Sockets=#item.SocketColours;item.SocketGroup=table.concat(groups," ");item.LinkedSockets=linked
	end
	if markers["Fractured Item"] then item.FracturedItem=true end
	if markers["Synthesised Item"] then item.SynthesisedItem=true end
	return item
end
return M
