-- Windows integration check. Runs the actual native file operations using
-- synthetic exchange responses and an isolated destination.
local dir = assert(arg[1], "Supply an existing temporary directory")
local function write(path, value)
	local file = assert(io.open(path, "wb"))
	assert(file:write(value))
	assert(file:close())
end
local function read(path)
	local file = assert(io.open(path,"rb"))
	local value = file:read("*a")
	file:close()
	return value
end
local original = [[Show
    BaseType == "Cord Belt"

# PoB economy: begin
Hide
    Class == "Stackable Currency"
    BaseType == "Orb of Alteration"
    StackSize <= 6

# PoB economy: end
Show
    Class == "Stackable Currency"
]]
local target, baseline, protections = dir.."/target.filter", dir.."/baseline.filter", dir.."/protect.json"
write(target,original)
write(baseline,original)
write(protections,'[{"BaseType":"Cord Belt","Rarity":"Magic"}]')
main = {userPath=dir.."/"}
function urlEncode(value) return value end
local sync = require("Modules.LootFilterDailySync")
local now = os.time()
local header = "HTTP/1.1 200 OK\r\nDate: "..os.date("!%a, %d %b %Y %H:%M:%S GMT",now).."\r\nAge: 5\r\n\r\n"
local calls, stale = 0, true
launch = {DownloadPage=function(_, _, callback, params)
	calls = calls + 1
	assert(params.timeout == 20)
	callback({
		header=stale and header:gsub("Age: 5","Age: 4001") or header,
		body='{"core":{"primary":"chaos"},"items":[{"id":"alt","name":"Orb of Alteration"}],"lines":[{"id":"alt","primaryValue":0.21,"volumePrimaryValue":1000}]}',
	})
end}
local options = {hour=0,targetValue=1,protectionFile=protections}
stale=false
local proposed
sync.preview(target,baseline,"Covens",options,function(before, after)
	assert(before==original)
	proposed=after
end)
assert(proposed and proposed:find("StackSize <= 4",1,true))
assert(read(target)==original and not sync.configuration())
calls, stale = 0, true
sync.configure(target,baseline,"Covens",options)
sync.tick(now,true)
assert(sync.status:find("stale",1,true) and read(target)==original,sync.status)
stale=false
sync.tick(now,true)
assert(sync.status:find("Protected drops verified",1,true) and read(target):find("StackSize <= 4",1,true),sync.status)
assert(calls==9)
local sample = sync.configuration().review.changes[1].sample
assert(sample.action=="Show" and sample.count==5)
local exposed = sync.publicStatus(now)
assert(exposed.state=="enabled" and exposed.adjustmentCount==1 and exposed.latestChanges[1].proposedCutoff==4)
local payload=require("dkjson").encode(exposed)
assert(not payload:find("target.filter",1,true) and not payload:find("protect.json",1,true))
sync.tick(now+60)
assert(calls==9)
sync.tick(now+60,true)
assert(calls==17)
sync.rollback()
assert(read(target)==original and sync.configuration().paused)
sync.tick(now+86400,true)
assert(calls==17)
sync.pause(false)
launch.noSSL=true
sync.tick(now+86400,true)
assert(calls==17 and sync.status:find("HTTPS",1,true))
launch.noSSL=false
sync.disable()
sync.tick(now+86400,true)
assert(calls==17 and not sync.configuration().enabled)
write(target,original .. "# external edit")
local expected, edited = sync.externalDiff()
assert(expected==original and edited==original .. "# external edit")
assert(read(target)==edited)
write(target,original)
assert(not pcall(sync.externalDiff))
local market = require("Modules.LootFilterEconomy")
local function quote(price)
	return {["Orb of Alteration"]={id="alt",price=price,volume=1000,source="Currency"}}
end
local _, first = market.remember(quote(0.2), {}, "day 1", now)
local spike, second = market.remember(quote(2), first, "day 2", now+86400)
assert(spike["Orb of Alteration"].price==0.2 and spike["Orb of Alteration"].currentPrice==2)
local lower = market.remember(quote(0.1), second, "day 3", now+2*86400)
assert(lower["Orb of Alteration"].price==0.1)
local _, repeatDay = market.remember(quote(2), second, "day 2", now+86400)
assert(#repeatDay==2)
-- Ambiguous identities stay ineligible even when the conflicting quote has more volume.
local ambiguous = market.quotes([[{"core":{"primary":"chaos"},"items":[{"id":"a","name":"Shared"},{"id":"b","name":"Shared"}],"lines":[{"id":"a","primaryValue":1,"volumePrimaryValue":100},{"id":"b","primaryValue":10,"volumePrimaryValue":10000}]}]], "Currency")
assert(ambiguous.Shared == false)
local joined = {Shared={id="a",price=1,volume=100,source="Currency"}}
market.merge(joined, {Shared={id="b",price=10,volume=10000,source="Oil"}})
assert(joined.Shared == false)
assert(market.liquid({source="Currency",volume=120}) and not market.liquid({source="Omen",volume=120}))

-- Timed retry and conditional cache use do not touch the filter during preview.
local systemTime = os.time
local clock = now
os.time = function() return clock end
local networkCount, conditional, transient = 0, 0, true
local cachedHeader = header:gsub("Age: 5", 'Age: 5\r\nETag: W/"fixture"')
launch.DownloadPage = function(_, _, callback, params)
	networkCount = networkCount + 1
	assert(not params.header:find("no-cache",1,true))
	if transient then
		transient = false
		callback({header="HTTP/1.1 429 Too Many Requests\r\nRetry-After: 20\r\n\r\n"}, "Response code: 429")
	elseif params.header:find('If-None-Match: W/"fixture"',1,true) then
		conditional = conditional+1
		callback({header="HTTP/1.1 304 Not Modified\r\n\r\n",body=""}, "Response code: 304")
	else
		callback({header=cachedHeader,body='{"core":{"primary":"chaos"},"items":[{"id":"alt","name":"Orb of Alteration"}],"lines":[{"id":"alt","primaryValue":0.21,"volumePrimaryValue":1000}]}'})
	end
end
local reviewed
sync.preview(target,baseline,"Covens",options,function(_, candidate) reviewed=candidate end)
assert(not reviewed and networkCount==1 and sync.busy)
clock=now+19
sync.tick(clock)
assert(networkCount==1)
clock=now+20
sync.tick(clock)
assert(reviewed and networkCount==9 and read(target)==original)
reviewed=nil
sync.preview(target,baseline,"Covens",options,function(_, candidate) reviewed=candidate end)
assert(reviewed and conditional==8 and networkCount==17)
os.time=systemTime
local browser = require("Modules.LootFilterMarketBrowse")
local gear = browser.rows([[{"lines":[{"name":"Example gear","baseType":"Cord Belt","variant":"A","chaosValue":20,"listingCount":17},{"name":"Example gear","baseType":"Cord Belt","variant":"B","chaosValue":32,"listingCount":1}]}]], {id="UniqueAccessory"})
assert(#gear==2 and gear[1].variant=="B" and gear[2].listings==17)
local cards = browser.rows([[{"core":{"primary":"chaos"},"items":[{"id":"card","name":"Example card"}],"lines":[{"id":"card","primaryValue":12,"volumePrimaryValue":500}]}]], {id="DivinationCard",feed="exchange"})
assert(#cards==1 and cards[1].price==12 and cards[1].volume==500)
assert(not pcall(browser.rows, '{"lines":[{"name":"Bad","chaosValue":-1}]}', {id="Map"}))
print("Native daily sync: fresh/stale data, manual rerun, rollback, pause, TLS and disable passed")
