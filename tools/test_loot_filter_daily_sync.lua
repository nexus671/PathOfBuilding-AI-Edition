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
local editedSuffix = original .. "\n# A personal edit after the economy section\n"
write(target,editedSuffix)
local adopted, adoptionError = pcall(sync.configure,target,baseline,"Covens",options)
assert(not adopted and adoptionError:find("different rules outside the economy section",1,true))
assert(read(target)==editedSuffix and not sync.configuration())
write(target,original)
sync.configure(target,baseline,"Covens",options)
local configFile = dir.."/LootFilterDailySync.json"
local verifiedConfig = read(configFile)
local oldConfig = require("dkjson").decode(verifiedConfig)
oldConfig.current = require("sha1")(editedSuffix)
write(configFile,assert(require("dkjson").encode(oldConfig)))
write(target,editedSuffix)
sync.tick(now,true)
assert(calls==0 and read(target)==editedSuffix and sync.status:find("different rules outside the economy section",1,true))
write(configFile,verifiedConfig)
write(target,original)
sync.tick(now,true)
assert(sync.status:find("stale",1,true) and read(target)==original,sync.status)
assert(sync.configuration().lastFailure)
local afterRestart = assert(loadfile("Modules/LootFilterDailySync.lua"))()
local failedStatus = afterRestart.publicStatus(now)
assert(failedStatus.state=="error" and failedStatus.lastFailure and not failedStatus.warning:find("target.filter",1,true))

stale=false
sync.tick(now,true)
assert(sync.status:find("Protected drops verified",1,true) and read(target):find("StackSize <= 4",1,true),sync.status)
assert(calls==9 and not sync.configuration().lastFailure)
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

-- An exact card rule opts in to the ninth feed. Its quote cannot cross over
-- to a commodity rule for the same name, even when the provider IDs differ.
local cardRules = [[Hide
    Class == "Divination Cards"
    BaseType == "Orb of Alteration" "Cheap Card" "Thin Card"

Hide
    Class == "Divination Cards"
    BaseType == "Compound Card"
    Identified True

]]
local cardBaseline = original:gsub("# PoB economy: end", cardRules.."# PoB economy: end")
local cardBody = [[{"core":{"primary":"chaos"},"items":[{"id":"card","name":"Orb of Alteration"},{"id":"cheap","name":"Cheap Card"},{"id":"thin","name":"Thin Card"},{"id":"compound","name":"Compound Card"}],"lines":[{"id":"card","primaryValue":3,"volumePrimaryValue":900},{"id":"cheap","primaryValue":0.4,"volumePrimaryValue":900},{"id":"thin","primaryValue":10,"volumePrimaryValue":499},{"id":"compound","primaryValue":10,"volumePrimaryValue":900}]}]]
local commodityBody = [[{"core":{"primary":"chaos"},"items":[{"id":"alt","name":"Orb of Alteration"}],"lines":[{"id":"alt","primaryValue":0.21,"volumePrimaryValue":1000}]}]]
local validate = require("Modules.LootFilterSyncValidation")
local missing = {}
for index = 1, #market.categories do missing[index] = commodityBody end
local samples = {{BaseType="Cord Belt", Rarity="Magic"}}
local validationOK, validationError = pcall(validate, cardBaseline, missing, false, 1, samples)
assert(not validationOK and validationError:find("category responses are missing",1,true))
assert(#market.feedCategories(original) == 8 and #market.feedCategories(cardBaseline) == 9)
local malformed = cardBaseline:gsub("# PoB economy: end", "# PoB economy: begin\n# PoB economy: end")
assert(not market.supports(malformed))
write(target,cardBaseline)
write(baseline,cardBaseline)
local cardRequests, unavailable = 0, true
launch.DownloadPage = function(_, url, callback)
	if url:match("&type=DivinationCard$") then
		cardRequests = cardRequests + 1
		callback({header=header,body=unavailable and "{}" or cardBody})
	else
		callback({header=header,body=commodityBody})
	end
end
sync.configure(target,baseline,"Covens",options)
sync.tick(now,true)
assert(cardRequests==1 and read(target)==cardBaseline and not sync.busy,sync.status)
unavailable=false
sync.tick(now,true)
assert(cardRequests==2 and sync.status:find("Protected drops verified",1,true),sync.status)
local refreshed = read(target)
assert(refreshed:find('BaseType == "Orb of Alteration"\n    StackSize <= 4',1,true))
assert(refreshed:find('BaseType == "Cheap Card" "Thin Card"',1,true))
assert(not refreshed:find('BaseType == "Orb of Alteration" "Cheap Card"',1,true))
assert(refreshed:find('BaseType == "Compound Card"\n    Identified True',1,true))
print("Managed cards: required category, broken feed, class-scoped same-name quotes and liquidity passed")

-- A second window can pause while the first has an in-flight response.
-- Load a second instance of the sync module to give each its own busy state.
local secondWindow = assert(loadfile("Modules/LootFilterDailySync.lua"))()
write(target,cardBaseline)
sync.configure(target,baseline,"Covens",options)
local waiting
local function reply(url, callback)
	callback({header=header,body=url:match("&type=DivinationCard$") and cardBody or commodityBody})
end
launch.DownloadPage = function(_, url, callback)
	if not waiting then
		waiting = function() reply(url, callback) end
	else
		reply(url, callback)
	end
end
sync.tick(now,true)
assert(sync.busy and waiting)
secondWindow.pause(true)
waiting()
assert(not sync.busy and sync.status:find("settings changed",1,true),sync.status)
assert(read(target)==cardBaseline and sync.configuration().paused)
secondWindow.pause(false)

-- A sharing violation must keep the original and leave a usable journal.
-- The handle permits readers but denies the atomic replacement.
local ffi = require("ffi")
local kernel = ffi.load("kernel32")
local targetPath = target:gsub("/","\\")
local size = kernel.MultiByteToWideChar(65001,8,targetPath,-1,nil,0)
local widePath = ffi.new("uint16_t[?]",size)
assert(kernel.MultiByteToWideChar(65001,8,targetPath,-1,widePath,size)==size)
local locked = kernel.CreateFileW(widePath,0x80000000,1,nil,3,0x80,nil)
assert(locked~=ffi.cast("void *",-1))
launch.DownloadPage = function(_, url, callback) reply(url,callback) end
sync.tick(now,true)
local closed = kernel.CloseHandle(locked)
assert(closed~=0 and sync.status:find("Check access and file locks",1,true),sync.status)
local pending = sync.configuration()
assert(read(target)==cardBaseline and pending.current and pending.pending and pending.current~=pending.pending)
secondWindow.tick(now,true)
assert(read(target)==refreshed and secondWindow.status:find("Protected drops verified",1,true),secondWindow.status)
assert(not secondWindow.configuration().pending)
secondWindow.rollback()
assert(read(target)==cardBaseline and secondWindow.configuration().paused)

-- Simulate termination after the atomic replace and before the final
-- settings commit. A new window must recognize the installed candidate.
secondWindow.pause(false)
write(target,refreshed)
write(dir.."/LootFilterDailySync.json",assert(require("dkjson").encode(pending)))
local replacementWindow = assert(loadfile("Modules/LootFilterDailySync.lua"))()
replacementWindow.tick(now,true)
assert(read(target)==refreshed and not replacementWindow.configuration().pending,replacementWindow.status)
print("Windows fault recovery: concurrent pause, locked target, and both pending-journal states passed")


-- Old hour-only settings still trigger on the hour. The new minute is used
-- both by the due check and the UI's next eligible time.
local localTime = os.date("*t",now)
localTime.hour, localTime.min, localTime.sec, localTime.isdst = 12, 37, 0, nil
local scheduled = os.time(localTime)
local clockSync = assert(loadfile("Modules/LootFilterDailySync.lua"))()
local legacy = {enabled=true,hour=12}
assert(clockSync.nextEligible(legacy,scheduled-3600)==os.date("%Y-%m-%d 12:00",scheduled))
local scheduleOptions = {hour=12,minute=37,targetValue=1,protectionFile=protections}
assert(not pcall(clockSync.configure,target,baseline,"Covens",{hour=12,minute=60}))
clockSync.configure(target,baseline,"Covens",scheduleOptions)
assert(clockSync.configuration().minute==37)
assert(clockSync.nextEligible(clockSync.configuration(),scheduled-60)==os.date("%Y-%m-%d %H:%M",scheduled))
local scheduledRequests = 0
launch.DownloadPage = function(_, url, callback)
	scheduledRequests = scheduledRequests + 1
	reply(url,callback)
end
clockSync.tick(scheduled-60)
assert(scheduledRequests==0)
clockSync.tick(scheduled)
assert(scheduledRequests==9)
localTime.day = localTime.day + 1
assert(clockSync.nextEligible(clockSync.configuration(),scheduled)==os.date("%Y-%m-%d %H:%M",os.time(localTime)))
local reportText = clockSync.diagnosticReport(scheduled)
assert(not reportText:find("target.filter",1,true) and not reportText:find("protect.json",1,true))
local diagnostics = require("dkjson").decode(reportText)
assert(diagnostics.status.state=="enabled" and diagnostics.dailyTime=="12:37")
assert(diagnostics.lastReview.verifiedProtection and #diagnostics.lastReview.responseAges==9)
assert(#diagnostics.lastReview.changes==2 and #diagnostics.successfulRuns==1)
assert(not diagnostics.successfulRuns[1].backup)
print("Daily scheduler respects minute precision and continues to read older hour-only settings")

local gameConfig = dir.."/production_Config.ini"
write(gameConfig,"[GENERAL]\r\nitem_filter=account-reference\r\n[UI]\r\nitem_filter=target.filter\r\n")
assert(clockSync.selectedLocalFilter(dir)==target)
write(gameConfig,"[UI]\nitem_filter=someone@example\n")
assert(not pcall(clockSync.selectedLocalFilter,dir))
write(gameConfig,"[UI]\nitem_filter=../target.filter\n")
assert(not pcall(clockSync.selectedLocalFilter,dir))
write(gameConfig,"[UI]\nitem_filter=target.filter\nitem_filter=other.filter\n")
assert(not pcall(clockSync.selectedLocalFilter,dir))
write(gameConfig,"[UI]\nitem_filter=missing.filter\n")
assert(not pcall(clockSync.selectedLocalFilter,dir))
print("PoE selection handles local filters and rejects stale or ambiguous selections")


-- A Task Scheduler run needs opt-in. Its retry budget follows the profile
-- across process restarts and even after reconfiguring the display schedule.
local jobSync = assert(loadfile("Modules/LootFilterDailySync.lua"))()
jobSync.configure(target,baseline,"Covens",options)
local jobNow = os.time()
local jobRequests = 0
launch.DownloadPage = function(_, _, callback)
	jobRequests = jobRequests + 1
	callback({header="HTTP/1.1 429 Too Many Requests\r\nRetry-After: 3600\r\n\r\n"}, "Response code: 429")
end
jobSync.tick(jobNow,false,true)
assert(jobRequests==0 and not jobSync.configuration().backgroundEnabled)
local revision = jobSync.configuration().revision
jobSync.setBackground(true,revision)
assert(jobSync.configuration().backgroundEnabled and jobSync.configuration().revision~=revision)
assert(not pcall(jobSync.setBackground,false,revision))
jobSync.setBackgroundNotifications(true)
local runner = assert(loadfile("Modules/LootFilterDailySync.lua"))()
runner.tick(jobNow,false,true)
local limited = runner.configuration()
assert(jobRequests==1 and limited.lastFailure and limited.providerRetryAfter>=jobNow+3600)
local newRunner = assert(loadfile("Modules/LootFilterDailySync.lua"))()
newRunner.tick(jobNow+600,true,true)
assert(jobRequests==1 and not newRunner.isDue(limited,jobNow+1800))
newRunner.configure(target,baseline,"Covens",options)
local reconfigured = newRunner.configuration()
assert(reconfigured.backgroundEnabled and reconfigured.backgroundNotifications and reconfigured.providerRetryAfter==limited.providerRetryAfter)
newRunner.setBackground(false,reconfigured.revision)
assert(not newRunner.configuration().backgroundEnabled)
print("Background opt-in and provider cooldown persist across independent Windows sync instances")

-- Campaign and map policies only apply to the matching managed rules.
-- A cap is a ceiling, and a recent liquid spike prevents tightening.
local scoped = [[Show
    BaseType == "Cord Belt"

# PoB economy: begin
Hide
    Class == "Stackable Currency"
    BaseType == "Orb of Alteration"
    AreaLevel < 68
    StackSize <= 3

Hide
    Class == "Stackable Currency"
    BaseType == "Orb of Alteration"
    AreaLevel >= 68
    StackSize <= 3

# PoB economy: end
Hide
    Class == "Stackable Currency"
    BaseType == "Orb of Alteration"
    AreaLevel < 68
    StackSize <= 2

Show
    Class == "Stackable Currency"
]]
local policy = {campaign=0.30,maps=3,caps={["Orb of Alteration"]=7}}
local history = {}
for days=1,3 do
	history[days] = {day="day "..days,time=now-days*86400,values={["Currency:alt"]=0.21}}
end
local applied, count, decisions = validate(scoped,missing,false,1,samples,history,"today",now,policy)
assert(count==2 and applied:find("AreaLevel < 68\n    StackSize <= 1",1,true))
assert(applied:find("AreaLevel >= 68\n    StackSize <= 7",1,true))
assert(decisions[1].scope=="campaign" and decisions[1].sample.area==60
	and decisions[1].sample.before=="Hide" and decisions[1].sample.action=="Hide")
assert(decisions[2].scope=="maps" and decisions[2].sample.before=="Show" and decisions[2].sample.action=="Hide")
local _, withoutHistory, _, skips = validate(scoped,missing,false,1,samples,{},"today",now,policy)
assert(withoutHistory==1 and skips[1].reason:find("three earlier",1,true))
history[3].values["Currency:alt"]=0.8
local _, withSpike, _, moreSkips = validate(scoped,missing,false,1,samples,history,"today",now,policy)
assert(withSpike==1 and moreSkips[1].reason:find("Recent high price",1,true))
assert(not pcall(market.pickupPolicy,1,{caps={["Orb of Alteration"]=7.5}}))
local young = {history[1],history[1],history[2]}
local _, duplicateDays = validate(scoped,missing,false,1,samples,young,"today",now,policy)
assert(duplicateDays==1)

-- Exercise the scheduler and the read-only preview with saved daily history.
local policySync = assert(loadfile("Modules/LootFilterDailySync.lua"))()
local ownSettings = policySync.configuration()
ownSettings.providerRetryAfter = nil
write(configFile,assert(require("dkjson").encode(ownSettings)))
write(target,scoped)
write(baseline,scoped)
policySync.configure(target,baseline,"Covens",{hour=0,targetValue=1,protectionFile=protections,pickupPolicy=policy})
history[3].values["Currency:alt"] = 0.21
local saved = policySync.configuration()
saved.priceHistory = history
write(configFile,assert(require("dkjson").encode(saved)))
launch.DownloadPage = function(_, _, callback) callback({header=header,body=commodityBody}) end
local policyPreview
policySync.preview(target,baseline,"Covens",{hour=0,targetValue=1,protectionFile=protections,pickupPolicy=policy},
	function(_, candidate) policyPreview=candidate end)
assert(policyPreview==applied and read(target)==scoped)
policySync.tick(now,true)
assert(read(target)==policyPreview and policySync.configuration().review.changes[2].sample.action=="Hide")

print("Pickup policy applies area thresholds, requires distinct daily observations, and shows shadowed outcomes")


-- Stash maps often use aggregate names and omit the mapTier property.
-- Keep ordinary, blighted and ravaged feeds separate.
local mapSamples = {{BaseType="Cord Belt",Class="Belts",Rarity="Magic"}}
local mapMarket = require("Modules.LootFilterMapMarket")
local normalMap = [[{"lines":[{"name":"Map (Tier 16)","detailsId":"ordinary-16","variant":"Gen-24","chaosValue":12,"count":40,"listingCount":400},{"name":"Map (Tier 15)","detailsId":"old-15","variant":"Gen-22","chaosValue":50,"count":40,"listingCount":400},{"name":"Map (Tier 15)","detailsId":"current-15","variant":"Gen-24","chaosValue":3,"count":50,"listingCount":400}]}]]
local blightMap = [[{"lines":[{"name":"Blighted Map (Tier 16)","detailsId":"blight-16","variant":"Gen-24","chaosValue":3,"count":40,"listingCount":400}]}]]
local ravagedMap = [[{"lines":[{"name":"Blight-ravaged Map (Tier 16)","detailsId":"ravaged-16","variant":"Gen-24","chaosValue":50,"count":19,"listingCount":500}]}]]
assert(mapMarket.quotes(normalMap,"Map")["Map (Tier 15)"]==false)
assert(browser.rows(normalMap,{id="Map"})[1].mapTier==15)
local mapBase = market.addManagedSection([[Show
    BaseType == "Cord Belt"
Show
    Class == "Maps"
]], {
	{class="Maps",tier=16,mapType="Map"},
	{class="Maps",tier=15,mapType="Map"},
	{class="Maps",tier=16,mapType="BlightedMap"},
	{class="Maps",tier=16,mapType="BlightRavagedMap"},
})
local drop = {BaseType="Vaal Temple Map",Class="Maps",Rarity="Rare",MapTier=16}
local mapParser = require("Modules.LootFilterParser")
for flag in pairs(mapParser.booleans) do drop[flag] = false end
local mapParsed = mapParser.parse(mapBase)
assert(mapParser.simulate(mapParsed,drop).action=="Hide")
for _, flag in ipairs(mapMarket.excludedFlags) do
	drop[flag] = true
	assert(mapParser.simulate(mapParsed,drop).action=="Show",flag)
	drop[flag] = false
end
drop.Rarity="Unique"
assert(mapParser.simulate(mapParsed,drop).action=="Show")
local feedKinds = market.feedCategories(mapBase)
assert(#feedKinds==11 and feedKinds[9]=="Map" and feedKinds[10]=="BlightedMap" and feedKinds[11]=="BlightRavagedMap")
local stash = {Map=normalMap,BlightedMap=blightMap,BlightRavagedMap=ravagedMap}
local mapBodies = {}
for index, category in ipairs(feedKinds) do mapBodies[index] = stash[category] or commodityBody end
local promoted, mapCount, mapChanges, mapSkips = validate(mapBase,mapBodies,false,1,mapSamples,nil,nil,nil,{maps=5})
assert(mapCount==1 and mapChanges[1].name=="Map (Tier 16)" and mapChanges[1].liquidityUnit=="listing samples")
assert(mapChanges[1].sample.before=="Hide" and mapChanges[1].sample.action=="Show")
assert(#mapSkips==3 and mapSkips[1].reason:find("Ambiguous",1,true) and mapSkips[3].reason:find("floor",1,true))
assert(not pcall(validate,mapBase,missing,false,1,mapSamples))
write(target,mapBase)
write(baseline,mapBase)
write(protections,assert(require("dkjson").encode(mapSamples)))
local marketSync = assert(loadfile("Modules/LootFilterDailySync.lua"))()
marketSync.configure(target,baseline,"Covens",{hour=0,protectionFile=protections,pickupPolicy={maps=5}})
local pathCount=0
launch.DownloadPage = function(_, url, callback)
	local kind = url:match("&type=(%w+)$")
	if stash[kind] then assert(url:find("stash/current/item/overview",1,true)); pathCount=pathCount+1
	else assert(url:find("exchange/current/overview",1,true)) end
	callback({header=header,body=stash[kind] or commodityBody})
end
marketSync.tick(now,true)
assert(read(target)==promoted and pathCount==3)
print("Managed maps use separate stash feeds, reject ambiguous variants, and preserve thin markets")

-- Exercise the manual screen through its Fetch and Export actions. It must
-- enforce the same freshness and liquidity criteria as the scheduler.
local controls, manualReview, exported
package.loaded["Modules.PlanningUI"] = {
	description=function() end, label=function() end, style=function() end,
	rows=function(value) return value end, errorText=tostring,
}
package.loaded["Classes.PlanningBrowserControl"] = {Open=function(_, _, options) manualReview=options end}
function new()
	return {
		ButtonControl=function(_, _, _, _, action) return {action=action} end,
		EditControl=function(_, _, _, value) return {buf=value} end,
		TextListControl=function() return {} end,
	}
end
function copyTable(value) return {} end
main.popups = {}
function main:OpenPopup(_, _, _, currentControls)
	controls = currentControls
	self.popups[1] = {}
	return self.popups[1]
end
function main:ClosePopup() self.popups[1]=nil end
main.screenW = 1024
launch.DownloadPage = function(_, url, callback, params)
	assert(params.timeout == 20)
	if url:match("/leagues$") then callback({body='[{"id":"Covens"}]'}); return end
	reply(url,callback)
end
require("Classes.LootFilterEconomyControl").Open({},cardBaseline,function(_, value) exported=value end)
controls.fetch.action()
assert(manualReview and manualReview.canChoose())
manualReview.choose()
assert(exported==refreshed)

launch.DownloadPage = function(_, url, callback)
	if url:match("/leagues$") then callback({body='[{"id":"Covens"}]'}); return end
	if url:match("&type=DivinationCard$") then reply(url,callback); return end
	callback({header=header:gsub("Age: 5","Age: 4001"),body=commodityBody})
end
local manual = require("Classes.LootFilterEconomyControl")
manual.Open({},cardBaseline,function(_, value) exported=value end)
controls.fetch.action()
assert(manualReview.canChoose())
manualReview.choose()
assert(exported:find("StackSize <= 6",1,true))
assert(exported:find('BaseType == "Cheap Card" "Thin Card"',1,true))
print("Manual review applies the native price freshness and class-specific liquidity checks")
