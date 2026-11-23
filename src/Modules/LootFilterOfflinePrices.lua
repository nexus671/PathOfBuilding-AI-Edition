local json = require("dkjson")
local sha = require("sha1")
local market = require("Modules.LootFilterEconomy")
local maxBody = market.maxFeedBytes()
local maxHeader = 16*1024
local maxFeeds = 16
local M = {maxSize=(maxFeeds-1)*maxBody+market.maxFeedBytes("SkillGem")+maxHeader}

function M.encode(config, bodies, feeds, checkedAt, recordedAt, day, confirmation)
	assert(#bodies==#feeds and #feeds<=maxFeeds, "Invalid offline price feed list")
	local header = {version=1,league=config.league,baselineHash=config.baselineHash,output=config.current,
		checkedAt=checkedAt,recordedAt=recordedAt,day=day,feeds={},confirmation=confirmation}
	for index, body in ipairs(bodies) do
		local feed = feeds[index]
		assert(type(body)=="string" and #body>0 and #body<=market.maxFeedBytes(feed.category), "Invalid offline price response size")
		header.feeds[index] = {category=feed.category,age=feed.age,size=#body,digest=sha(body)}
	end
	local record = assert(json.encode(header))
	assert(#record<maxHeader, "Offline price metadata exceeds the size limit")
	return record.."\n"..table.concat(bodies)
end

function M.decode(raw, config, categories, now)
	local separator = raw:find("\n",1,true)
	assert(separator and separator<=maxHeader, "Invalid offline price metadata")
	local header = json.decode(raw:sub(1,separator-1))
	assert(type(header)=="table" and header.version==1 and header.league==config.league
		and header.baselineHash==config.baselineHash and header.output==config.current
		and header.checkedAt==config.lastSuccess and type(header.checkedAt)=="number" and header.checkedAt<=now
		and type(header.recordedAt)=="number" and header.recordedAt>=header.checkedAt and header.recordedAt<=now
		and type(header.day)=="string" and header.day:match("^%d%d%d%d%-%d%d%-%d%d$")
		and type(header.feeds)=="table" and #header.feeds==#categories and #categories<=maxFeeds,
		"Offline prices no longer match the current verified refresh")
	local bodies, cursor, oldest = {}, separator+1, 0
	for index, category in ipairs(categories) do
		local feed = header.feeds[index]
		assert(type(feed)=="table" and feed.category==category and type(feed.age)=="number"
			and feed.age>=0 and feed.age<=3600 and type(feed.size)=="number"
			and feed.size>0 and feed.size<=market.maxFeedBytes(category) and feed.size==math.floor(feed.size),
			"Invalid offline price feed record")
		local body = raw:sub(cursor,cursor+feed.size-1)
		assert(#body==feed.size and sha(body)==feed.digest, "Offline price response checksum mismatch")
		bodies[index], cursor = body, cursor+feed.size
		oldest = math.max(oldest,feed.age)
	end
	assert(cursor==#raw+1, "Invalid offline price record length")
	local age = now-header.recordedAt+oldest
	assert(age<=config.offlinePriceDays*86400, "Offline prices exceed this profile's age limit")
	return bodies, header, age
end

return M
