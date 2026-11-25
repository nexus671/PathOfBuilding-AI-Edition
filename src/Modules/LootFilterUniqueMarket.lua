local json = require("Modules.LootFilterMarketJSON")
local areas = require("Modules.LootFilterPickupAreas")
local M = {class="Unidentified unique",maxBytes=12*1024*1024}
M.feeds = {"UniqueWeapon","UniqueArmour","UniqueAccessory","UniqueFlask","UniqueJewel","UniqueTincture"}
local classFeed = {}
for feed, classes in pairs({
	UniqueWeapon={"Bows","Claws","Daggers","Fishing Rods","One Hand Axes","One Hand Maces","One Hand Swords","Rune Daggers",
		"Sceptres","Staves","Thrusting One Hand Swords","Two Hand Axes","Two Hand Maces","Two Hand Swords","Wands","Warstaves"},
	UniqueArmour={"Body Armours","Boots","Gloves","Helmets","Shields","Quivers"},
	UniqueAccessory={"Amulets","Belts","Rings"},
	UniqueFlask={"Hybrid Flasks","Life Flasks","Mana Flasks","Utility Flasks","Critical Utility Flasks"},
	UniqueJewel={"Jewels","Abyss Jewels"},
	UniqueTincture={"Tinctures"},
}) do
	for _, class in ipairs(classes) do classFeed[class]=feed end
end
M.feed = {}
for _, feed in ipairs(M.feeds) do M.feed[feed]=true end

function M.base(name)
	local class = require("Modules.LootFilterLibrary").baseClass(name)
	return class,classFeed[class]
end

local function positive(value)
	return type(value)=="number" and value>0 and value<math.huge
end

-- Keep stable, uncorrupted listing variants distinct. A high linked-socket
-- price cannot characterize an arbitrary unidentified drop of the same base.
function M.quotes(body, source, floors)
	assert(type(body)=="string" and #body<=M.maxBytes,"Unique market response exceeds the size limit")
	local overview = assert(json.decode(body,{"lines"}),"Invalid unique market overview")
	local ids, ambiguous, result = {}, {}, {}
	for _, row in ipairs(overview.lines) do
		local id = type(row.detailsId)=="string" and #row.detailsId<=200 and row.detailsId:match("^[A-Za-z0-9_.%-]+$")
		local hasBase = type(row.baseType)=="string" and #row.baseType<=200 and row.baseType:match("%S")
		local name = type(row.name)=="string" and #row.name<=200 and not row.name:find("[%c^]") and row.name
		if id and hasBase and name then
			local prior = ids[id]
			if prior and (prior.name~=row.name or prior.baseType~=row.baseType or prior.chaosValue~=row.chaosValue
				or prior.variant~=row.variant or prior.links~=row.links or prior.corrupted~=row.corrupted) then
				ambiguous[id]=true
			elseif not prior or not positive(row.listingCount) or not positive(row.count)
				or positive(prior.listingCount) and positive(prior.count)
					and math.min(row.count,row.listingCount)<math.min(prior.count,prior.listingCount) then
				ids[id]=row
			end
		end
	end
	local minimum = floors and floors[source] or 20
	for id, row in pairs(ids) do
		if not ambiguous[id] and positive(row.chaosValue) and positive(row.count) and positive(row.listingCount)
			and (row.corrupted==nil or row.corrupted==false) and (row.links==nil or row.links==0 or row.links==1)
			and (row.itemClass==nil or row.itemClass==3)
			and not row.name:match("^Replica ") and not row.name:match("^Foulborn ") then
			local volume = math.min(row.count,row.listingCount)
			local previous = result[row.baseType]
			if volume>=minimum and (not previous or row.chaosValue>previous.price or row.chaosValue==previous.price and id<previous.id) then
				result[row.baseType] = {price=row.chaosValue,id=id,source=source,volume=volume,uniqueName=row.name,liquidityUnit="listing samples"}
			end
		end
	end
	return result
end

local prefix = "# PoB economy: unique"
function M.block(base, class, feed, scope)
	local lines = {prefix.." "..feed, "Show", '    Class == "'..class..'"', '    BaseType == "'..base..'"',
		"    Rarity == Unique","    Identified False"}
	for _, condition in ipairs(areas.conditions(scope)) do lines[#lines+1]=condition end
	return table.concat(lines,"\n")
end

function M.selections(section, parsed)
	local rules, selected = {}, {}
	for _, rule in ipairs(parsed.rules) do rules[rule.line]=rule end
	local index = 0
	for line in section:gmatch("[^\n]*\n?") do
		if line=="" then break end
		index=index+1
		local text = line:match("^%s*(.-)%s*$")
		if text:sub(1,#prefix)==prefix then
			local category = text:match("^# PoB economy: unique ([%w]+)$")
			local rule = rules[index+1]
			assert(M.feed[category] and rule and rule.action=="Show" and not rule.continue,"Attach a unique feed to an exact Show rule")
			local fields = {}
			for _, condition in ipairs(rule.conditions) do
				local key = condition.keyword
				if key~="AreaLevel" then
					assert((key=="Class" or key=="BaseType" or key=="Identified" or key=="Rarity")
						and not fields[key] and #condition.values==1,"Managed unique rules require an exact unidentified unique base")
					fields[key]=condition
				end
			end
			local base = fields.BaseType and fields.BaseType.operator=="==" and fields.BaseType.values[1]
			local class, feed
			if base then class,feed=M.base(base) end
			local scope = areas.read(rule.conditions)
			assert(feed==category and fields.Class and fields.Class.operator=="==" and fields.Class.values[1]==class
				and fields.Rarity and fields.Rarity.operator=="==" and fields.Rarity.values[1]=="Unique"
				and fields.Identified and (fields.Identified.operator=="=" or fields.Identified.operator=="==")
				and fields.Identified.values[1]=="False" and scope,
				"Managed unique rules require a known exact base and Identified False")
			selected[rule.line]={base=base,class=class,source=feed,scope=scope}
		end
	end
	return selected
end

return M
