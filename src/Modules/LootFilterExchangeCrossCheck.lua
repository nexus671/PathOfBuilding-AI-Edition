local marketJSON = require("Modules.LootFilterMarketJSON")
local currencyNames = require("Data.CurrencyNames")
local M = {endpoint="https://web.poecdn.com/api/currency-exchange/"}
local chaos = "Metadata/Items/Currency/CurrencyRerollRare"
local realms = {pc="", xbox="xbox/", sony="sony/"}
local ids = {}

for id, name in pairs(currencyNames) do
	if ids[name] == nil then ids[name] = id else ids[name] = false end
end

function M.itemId(name)
	local id = ids[name]
	return id ~= chaos and id or nil
end

function M.hour(checkedAt)
	return math.floor(checkedAt / 3600) * 3600 - 7200
end

function M.decode(raw, hour)
	assert(type(raw)=="string" and #raw<=12*1024*1024, "Invalid GGG exchange response size")
	local data = marketJSON.decode(raw,{"markets"})
	assert(data and data.next_change_id==hour+3600,
		"GGG did not return the requested completed hour")
	return data.markets
end

local function quantity(value)
	return type(value)=="number" and value>0 and value<=9007199254740991 and value==math.floor(value)
end

local function directItem(entry)
	local pair = type(entry)=="table" and entry.market_pair
	if type(pair)~="table" or #pair~=2 then return end
	if pair[1]==chaos and pair[2]~=chaos and type(pair[2])=="string" then return pair[2] end
	if pair[2]==chaos and pair[1]~=chaos and type(pair[1])=="string" then return pair[1] end
end

local function tradedQuote(entry, id)
	local volumes = entry.volume_traded
	local count, chaosVolume
	if type(volumes)=="table" then count, chaosVolume = volumes[id], volumes[chaos] end
	if not quantity(count) or not quantity(chaosVolume) or count<5 or chaosVolume<100 then return end
	return {price=chaosVolume/count, count=count, chaosVolume=chaosVolume}
end

function M.compare(markets, league, name)
	local id = M.itemId(name)
	if not id then return nil, "No unambiguous game item ID for this name." end
	local match
	for _, entry in ipairs(markets) do
		if directItem(entry)==id and entry.league==league then
			if match then return nil, "GGG returned duplicate markets for this item." end
			match = entry
		end
	end
	if not match then return nil, "No direct chaos trades for this item and league in that hour." end
	local quote = tradedQuote(match,id)
	return quote, not quote and "GGG trade volume was too low for comparison." or nil
end

function M.review(markets, league)
	local candidates, results = {}, {}
	for _, entry in ipairs(markets) do
		local id = directItem(entry)
		local name = id and currencyNames[id]
		local scope = id and entry.league
		if name and ids[name]==id and type(scope)=="string" and #scope<=80 and scope:match("^[%w][%w _-]*$")
			and not scope:match(" $") and (not league or scope==league) then
			local key = scope.."\0"..id
			if candidates[key]==nil then candidates[key]=entry else candidates[key]=false end
		end
	end
	for _, entry in pairs(candidates) do
		if entry then
			local id = directItem(entry)
			local quote = tradedQuote(entry,id)
			if quote then
				quote.league, quote.name = entry.league, currencyNames[id]
				results[#results+1] = quote
			end
		end
	end
	table.sort(results,function(a,b)
		if a.name==b.name then return a.league<b.league end
		return a.name<b.name
	end)
	return results
end

local cache = {}
function M.fetch(hour, callback, realm)
	realm = realm or "pc"
	local path = assert(realms[realm],"Choose a PoE 1 trade realm")
	assert(type(hour)=="number" and hour>0 and hour<=9007199254740991 and hour%3600==0,"Choose a completed exchange hour")
	local cached = cache[realm]
	if cached and hour==cached.hour then callback(cached.markets); return end
	launch:DownloadPage(M.endpoint..path..string.format("%.0f",hour),function(response,err)
		if err then callback(nil,"Could not retrieve that completed hour from GGG."); return end
		local ok, markets = pcall(M.decode,response and response.body,hour)
		if not ok then callback(nil,markets); return end
		cache[realm] = {hour=hour,markets=markets}
		callback(markets)
	end,{followRedirects=false,header="Accept: application/json",timeout=15,maxBytes=12*1024*1024})
end

return M
