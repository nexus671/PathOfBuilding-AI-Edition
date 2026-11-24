local json = require("dkjson")
local currencyNames = require("Data.CurrencyNames")
local M = {endpoint="https://web.poecdn.com/api/currency-exchange/"}
local chaos = "Metadata/Items/Currency/CurrencyRerollRare"
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
	local data = json.decode(raw)
	assert(type(data)=="table" and data.next_change_id==hour+3600 and type(data.markets)=="table",
		"GGG did not return the requested completed hour")
	return data.markets
end

local function quantity(value)
	return type(value)=="number" and value>0 and value<=9007199254740991 and value==math.floor(value)
end

function M.compare(markets, league, name)
	local id = M.itemId(name)
	if not id then return nil, "No unambiguous game item ID for this name." end
	local match
	for _, entry in ipairs(markets) do
		local pair = type(entry)=="table" and entry.market_pair
		if type(pair)=="table" and #pair==2 and entry.league==league
			and ((pair[1]==id and pair[2]==chaos) or (pair[2]==id and pair[1]==chaos)) then
			if match then return nil, "GGG returned duplicate markets for this item." end
			match = entry
		end
	end
	if not match then return nil, "No direct chaos trades for this item and league in that hour." end
	local volumes = match.volume_traded
	local count, chaosVolume
	if type(volumes)=="table" then count, chaosVolume = volumes[id], volumes[chaos] end
	if not quantity(count) or not quantity(chaosVolume) or count<5 or chaosVolume<100 then
		return nil, "GGG trade volume was too low for comparison."
	end
	return {price=chaosVolume/count, count=count, chaosVolume=chaosVolume}
end

local cachedHour, cachedMarkets
function M.fetch(hour, callback)
	if hour==cachedHour then callback(cachedMarkets); return end
	launch:DownloadPage(M.endpoint..string.format("%.0f",hour),function(response,err)
		if err then callback(nil,"Could not retrieve that completed hour from GGG."); return end
		local ok, markets = pcall(M.decode,response and response.body,hour)
		if not ok then callback(nil,markets); return end
		cachedHour, cachedMarkets = hour, markets
		callback(markets)
	end,{followRedirects=false,header="Accept: application/json",timeout=15,maxBytes=12*1024*1024})
end

return M
