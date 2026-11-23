local json = require("dkjson")
local M = {
	feed = "SkillGem",
	maxBytes = 12*1024*1024,
	classes = {["Skill Gems"]=true,["Support Gems"]=true},
}

local function integer(value,minimum,maximum)
	return type(value)=="number" and value>=minimum and value<=maximum and value==math.floor(value)
end

local function text(value)
	return type(value)=="string" and #value<=200 and value:match("%S") and not value:find('[%c"\\]')
end

function M.key(name,level,quality,corrupted)
	if text(name) and integer(level,1,40) and integer(quality,0,100) and type(corrupted)=="boolean" then
		return table.concat({name,level,quality,tostring(corrupted)},"\0")
	end
end

local allowed = {
	Class=true,BaseType=true,GemLevel=true,Quality=true,
	Corrupted=true,Imbued=true,TransfiguredGem=true,AreaLevel=true,
}

function M.rule(rule)
	if rule.action~="Hide" or rule.continue or next(rule.styles) then return nil end
	local conditions = {}
	for _, condition in ipairs(rule.conditions) do
		if not allowed[condition.keyword] or conditions[condition.keyword] or #condition.values~=1 then return nil end
		conditions[condition.keyword] = condition
	end
	local function exact(name,operator)
		local condition = conditions[name]
		return condition and (condition.operator=="==" or operator=="=" and condition.operator=="=") and condition.values[1]
	end
	local class, name = exact("Class"), exact("BaseType")
	local level, quality = tonumber(exact("GemLevel","=") or ""), tonumber(exact("Quality","=") or "")
	local corrupt = exact("Corrupted","=")
	if not M.classes[class] or exact("Imbued","=")~="False" or exact("TransfiguredGem","=")~="False"
		or corrupt~="True" and corrupt~="False" then return nil end
	local key = M.key(name,level,quality,corrupt=="True")
	if not key then return nil end
	local area = conditions.AreaLevel
	local scope = "all"
	if area then
		if area.values[1]~="68" then return nil end
		if area.operator==">=" then scope="maps"
		elseif area.operator=="<" then scope="campaign"
		else return nil end
	end
	return {key=key,name=name,class=class,scope=scope,gemLevel=level,gemQuality=quality,corrupted=corrupt=="True"}
end

local function positive(value)
	return type(value)=="number" and value>0 and value<math.huge
end

-- Keep only exact requested quotes so an entire stash overview never enters price history.
function M.quotes(body,requested)
	assert(type(body)=="string" and #body<=M.maxBytes,"Invalid gem market response size")
	local data, position = json.decode(body)
	assert(type(data)=="table" and type(data.lines)=="table" and #data.lines>0
		and not body:sub(position):find("%S"),"Invalid gem market overview")
	local ids, result = {}, {}
	for _, row in ipairs(data.lines) do
		assert(type(row)=="table","Invalid gem market entry")
		local key = M.key(row.name,row.gemLevel,row.gemQuality,row.corrupted)
		local id = text(row.detailsId) and row.detailsId
		local volume = positive(row.count) and positive(row.listingCount) and math.min(row.count,row.listingCount)
		local exact = key and id and volume and positive(row.chaosValue) and (row.baseType==nil or row.baseType=="" or row.baseType==row.name)
			and (row.variant==nil or row.variant=="")
		if id then
			local signature = exact and key.."\0"..tostring(row.chaosValue) or false
			if ids[id]~=nil and ids[id]~=signature then signature=false end
			ids[id] = signature
		end
		if key and requested and requested[key] then
			local existing = result[key]
			if not exact or existing==false or existing and (existing.providerId~=id or existing.price~=row.chaosValue) then
				result[key] = false
			else
				result[key] = {id=id.."\0"..key,providerId=id,price=row.chaosValue,source=M.feed,
					volume=existing and math.min(existing.volume,volume) or volume,liquidityUnit="listing samples"}
			end
		end
	end
	for key, quote in pairs(result) do
		if quote and not ids[quote.providerId] then result[key]=false end
	end
	return result
end

return M
