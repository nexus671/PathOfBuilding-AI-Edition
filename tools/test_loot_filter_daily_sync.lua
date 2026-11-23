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
stale=true
local previewFailure
sync.preview(target,baseline,"Covens",options,function() error("Stale data cannot produce a preview") end,
	function(reason) previewFailure=reason end)
assert(previewFailure and previewFailure:find("stale",1,true) and not sync.configuration())
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
local diff = sync.publicDiff(now)
assert(diff.verifiedProtection and diff.changeCount==1 and #diff.changes==1)
assert(#diff.feeds==8 and diff.feeds[1].category=="Currency" and not diff.feeds[1].revalidated
	and diff.feeds[1].responseAge==diff.responseAges[1])
assert(diff.changes[1].item=="Orb of Alteration" and diff.changes[1].sample.action=="Show")
local diffPayload=require("dkjson").encode(diff)
assert(not diffPayload:find("target.filter",1,true) and not diffPayload:find("protect.json",1,true))
local configPath=dir.."/LootFilterDailySync.json";local originalConfig=read(configPath);local json=require("dkjson");local edited=json.decode(originalConfig)
edited.review.changes[1].sample.before="Unknown";edited.review.changes[1].sample.action="Unknown"
edited.review.changes[1].sample.beforeMissing={"ItemLevel","C:/private/filter","ItemLevel"};edited.review.changes[1].sample.afterMissing={"DropLevel","UntrustedPrivateName"}
edited.review.changes[1].samples={edited.review.changes[1].sample,{area=60,class='Stackable Currency',count=5,before='Hide',action='Unknown',afterMissing={'ItemLevel'}}}
for i=3,25 do edited.review.changes[1].samples[i]={area=83,class='Stackable Currency',count=i,before='Hide',action='Show'} end
write(configPath,assert(json.encode(edited)));local publicChange=assert(sync.publicDiff(now+1)).changes[1];local redacted=publicChange.sample
assert(#redacted.beforeMissing==1 and redacted.beforeMissing[1]=="ItemLevel" and #redacted.afterMissing==1 and redacted.afterMissing[1]=="DropLevel")
assert(#publicChange.samples==20 and publicChange.samplesTruncated and publicChange.samples[2].area==60 and publicChange.samples[2].afterMissing[1]=='ItemLevel')
local redactedText=json.encode(publicChange);assert(not redactedText:find("private",1,true) and not redactedText:find("Untrusted",1,true));write(configPath,originalConfig)
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
do
	local raw = [[# PoB economy: begin
Hide
    Class == "Stackable Currency"
    BaseType == "Orb of Alteration"
    StackSize <= 6
    AreaLevel >= 68
# PoB economy: end
Hide
    Class == "Stackable Currency"
    StackSize >= 20
Show
    Class == "Stackable Currency"
    StackSize == 18
    MinimapIcon 2 White Square
Show
    Class == "Stackable Currency"
    BaseType == "Orb of Alteration" "Chaos Orb"
    MinimapIcon 2 White Circle
Show
]]
	local quotes = {["Orb of Alteration"]={price=0.2,volume=300,id="alt",source="Currency"}}
	local style = {highlightChaos=2,strongHighlightChaos=3}
	assert(not pcall(market.pickupPolicy,100,{highlightChaos=3,strongHighlightChaos=2}))
	local unchanged = market.review(raw,quotes,100)
	assert(unchanged==raw)
	local styled, decisions = market.review(raw,quotes,100,style)
	assert(#decisions==1 and decisions[1].old==decisions[1].cutoff and #decisions[1].highlights==2)
	local parser = require("Modules.LootFilterParser")
	local old, candidate = parser.parse(raw), parser.parse(styled)
	assert(#candidate.diagnostics==0)
	for stack=1,30 do
		for _, area in ipairs({60,83}) do
			local item = {BaseType="Orb of Alteration",Class="Stackable Currency",StackSize=stack,AreaLevel=area}
			local before, after = parser.simulate(old,item), parser.simulate(candidate,item)
			assert(before.action==after.action)
			if area==83 and stack==10 then assert(table.concat(after.styles.MinimapIcon," ")=="1 Yellow Circle") end
			if area==83 and stack==15 then assert(table.concat(after.styles.MinimapIcon," ")=="0 Orange Star") end
			if area==83 and stack==18 then assert(table.concat(after.styles.MinimapIcon," ")=="2 White Square") end
			if area==60 and stack==10 then assert(table.concat(after.styles.MinimapIcon," ")=="2 White Circle") end
		end
	end
	local appearance = require("Modules.LootFilterPriceAppearance")
	local boundaryQuotes = quote(0.01)
	local _, decimal = market.review(raw,boundaryQuotes,100,{highlightChaos=0.07,strongHighlightChaos=0.08000001})
	assert(decimal[1].highlights[1].firstStack==7 and decimal[1].highlights[2].firstStack==9)
	assert(appearance.strip(styled)==raw)
	local bom = "\239\187\191"
	local plain = bom..'Show\r\n    Class == "Stackable Currency"\r\n    BaseType == "Orb of Alteration"\r\n'
	local marked = appearance.apply(plain,{["Stackable Currency"]={["Orb of Alteration"]={{name="Orb of Alteration",firstStack=10,tier=1}}}})
	assert(marked~=plain and marked:sub(1,3)==bom and #parser.parse(marked).diagnostics==0 and appearance.strip(marked)==plain)
	local tampered = styled:gsub("StackSize >= 15","StackSize >= 7",1)
	assert(not pcall(appearance.strip,tampered))
	local continuingHide = "Hide\n    Class == \"Stackable Currency\"\n    Continue\n\n" .. raw
	local styledAfterHide = market.review(continuingHide,quotes,100,style)
	assert(appearance.strip(styledAfterHide)==continuingHide)
	local withImport='Import "custom.filter"\n'..raw
	local guarded, guardedDecisions, skipped = market.review(withImport,quotes,100,style)
	assert(guarded==withImport and #guardedDecisions==0 and skipped[1].styleOnly)
	print("Opt-in highlights preserve visibility, apply at exact stack values, and respect later styles")
end

do
	local raw = [[# PoB economy: begin
Hide
    Class == "Divination Cards"
    BaseType == "Expensive Card" "Cheap Card"
# PoB economy: end
Show
    Class == "Divination Cards"
    BaseType == "Expensive Card" "Cheap Card"
    MinimapIcon 2 White Circle
Show
]]
	local quotes = {}
	market.merge(quotes,{["Expensive Card"]={price=3,volume=800,id="expensive",source="DivinationCard"},
		["Cheap Card"]={price=0.2,volume=800,id="cheap",source="DivinationCard"}},"DivinationCard")
	local output, changes = market.review(raw,quotes,1,{highlightChaos=2,strongHighlightChaos=10})
	assert(#changes==1 and changes[1].name=="Expensive Card")
	local parser=require("Modules.LootFilterParser")
	local compiled=parser.parse(output)
	local cheap=parser.simulate(compiled,{Class="Divination Cards",BaseType="Cheap Card",StackSize=12})
	assert(cheap.action=="Hide")
	local expensive=parser.simulate(compiled,{Class="Divination Cards",BaseType="Expensive Card",StackSize=1})
	assert(expensive.action=="Show" and table.concat(expensive.styles.MinimapIcon," ")=="1 Yellow Circle")
end

local function quoteBatch(count, source)
	local batch = {}
	for index=1,count do
		batch["Fixture "..index] = {price=0.21,volume=1000,id=tostring(index),source=source or "Currency"}
	end
	return batch
end
local _, completeDay = market.remember(quoteBatch(24), {}, "complete one", now)
local _, completeHistory = market.remember(quoteBatch(24), completeDay, "complete two", now+86400)
local coverage, coverageError = pcall(market.remember, quoteBatch(5), completeHistory, "truncated", now+2*86400)
assert(not coverage and coverageError:find("fewer than a quarter",1,true))
assert(pcall(market.remember, quoteBatch(6), completeHistory, "still sufficient", now+2*86400))
assert(pcall(market.remember, quoteBatch(5), completeDay, "first comparison", now+2*86400))
do
	local _, cardFirst = market.remember(quoteBatch(24,"DivinationCard"),{},"cards one",now)
	local _, cardHistory = market.remember(quoteBatch(24,"DivinationCard"),cardFirst,"cards two",now+86400)
	local valid, failure = pcall(market.remember,quoteBatch(5,"DivinationCard"),cardHistory,"cards three",now+2*86400)
	assert(not valid and failure:find("DivinationCard feed has fewer",1,true))
end

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
sync.configure(target,baseline,"Covens",options)
sync.tick(clock,true)
local revalidated = sync.publicDiff(clock)
assert(#revalidated.feeds==8 and revalidated.feeds[1].category=="Currency" and revalidated.feeds[1].revalidated
	and revalidated.feeds[1].responseAge==revalidated.responseAges[1])
local originalAge = revalidated.feeds[1].responseAge
clock=clock+61
sync.tick(clock,true)
assert(sync.publicDiff(clock).feeds[1].responseAge==originalAge+61)
local successfulOutput = read(target)
launch.DownloadPage = function(_, _, callback, params)
	assert(params.header:find('If-None-Match: W/"fixture"',1,true))
	callback({header="HTTP/1.1 304 Not Modified\r\nAge: 3601\r\n\r\n", body=""}, "Response code: 304")
end
clock=clock+1
sync.tick(clock,true)
assert(sync.status:find("snapshot is stale",1,true) and read(target)==successfulOutput)
sync.rollback()
sync.disable()
os.time=systemTime

-- An expired season yields an empty successful price response. Confirm
-- against the fresh provider list and retain the user's chosen profile.
local obsolete = "Ended Fixture"
local leagueChecks = 0
local markets = '[{"id":"Covens","name":"Covens"},{"id":"Standard","name":"Standard"}]'
launch.DownloadPage = function(_,url,callback)
	if url:match("/leagues$") then
		leagueChecks = leagueChecks+1
		callback({header=header,body=markets})
	else
		callback({header=header,body='{"core":{"primary":"chaos"},"items":[],"lines":[]}'})
	end
end
sync.configure(target,baseline,obsolete,options)
sync.tick(now,true)
assert(leagueChecks==1 and sync.configuration().league==obsolete and read(target)==original)
assert(sync.status:find("no longer listed",1,true) and sync.configuration().lastFailure)
sync.configure(target,baseline,"Covens",options)
sync.tick(now,true)
assert(leagueChecks==2 and sync.status:find("No priced exchange items",1,true) and read(target)==original)
sync.disable()
local browser = require("Modules.LootFilterMarketBrowse")
local gear = browser.rows([[{"lines":[{"name":"Example gear","baseType":"Cord Belt","variant":"A","chaosValue":20,"listingCount":17},{"name":"Example gear","baseType":"Cord Belt","variant":"B","chaosValue":32,"listingCount":1}]}]], {id="UniqueAccessory"})
assert(#gear==2 and gear[1].variant=="B" and gear[2].listings==17)
do
	local sharedBase = browser.rows([[{"lines":[
		{"name":"Named result","baseType":"Cord Belt","detailsId":"named","chaosValue":30,"count":50,"listingCount":40,"corrupted":false},
		{"name":"Competing result","baseType":"Cord Belt","detailsId":"competing","chaosValue":120,"count":80,"listingCount":62},
		{"name":"Thin result","baseType":"Cord Belt","detailsId":"thin","chaosValue":9000,"count":2,"listingCount":5},
		{"name":"Conflicted result","baseType":"Cord Belt","detailsId":"conflicted","chaosValue":700,"count":50,"listingCount":55},
		{"name":"Conflicted result","baseType":"Cord Belt","detailsId":"conflicted","chaosValue":5,"count":100,"listingCount":70}
	]}]],{id="UniqueAccessory"},"Named result")
	assert(#sharedBase==1 and sharedBase[1].corrupted==false)
	local evidence = sharedBase[1].baseEvidence
	assert(evidence.names==4 and evidence.variants==4 and evidence.priced==2 and evidence.minimum==30 and evidence.maximum==120)
	local unmodifiedGem = browser.rows([[{"lines":[{"name":"Example gem","chaosValue":1,"gemLevel":1,"gemQuality":0}]}]],{id="SkillGem"})[1]
	assert(unmodifiedGem.gemQuality==0 and unmodifiedGem.corrupted==nil)
end
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

-- Inject a partial write at the same point a full volume can reject a
-- buffered write. The real target and its recovery journal stay usable.
local openFile = io.open
local injected = false
io.open = function(path, mode)
	local file, why = openFile(path, mode)
	if path ~= target .. ".tmp" or mode ~= "wb" or not file then return file, why end
	injected = true
	return {
		write=function(_, value)
			assert(file:write(value:sub(1,13)))
			return nil,"No space left on device"
		end,
		close=function() return file:close() end,
	}
end
launch.DownloadPage = function(_, url, callback) reply(url,callback) end
sync.tick(now,true)
io.open = openFile
assert(injected and read(target)==cardBaseline and sync.status:find("No space left",1,true),sync.status)
assert(sync.configuration().pending and not io.open(target..".tmp","rb"))

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
assert(not io.open(target..".tmp","rb"))
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

-- Named profiles preserve existing default settings and isolate their live
-- paths, league seasons, protection files and recurrence.
local profiles = assert(loadfile("Modules/LootFilterDailySync.lua"))()
local id = profiles.createProfile("Mapping")
assert(not pcall(profiles.createProfile,"mapping"))
assert(#profiles.profiles()==2 and profiles.profiles()[2].id==id)
local namedTarget = dir.."/named.filter"
write(namedTarget,cardBaseline)
write(baseline,cardBaseline)
local namedOptions = {hour=0,intervalDays=3,profileId=id,protectionFile=protections}
local alias = dir:gsub("\\","/").."/./target.filter"
local shared, sharedError = pcall(profiles.configure,alias,alias,"Standard",namedOptions)
assert(not shared and sharedError:find("already belongs to Default",1,true))
profiles.configure(namedTarget,baseline,"Standard",namedOptions)
assert(profiles.configuration(id).league=="Standard" and profiles.configuration().league=="Covens")
assert(profiles.configuration(id).intervalDays==3 and profiles.configuration().intervalDays==1)
assert(not pcall(profiles.configure,namedTarget,baseline,"Standard",{profileId=string.rep("a",40),protectionFile=protections}))
local current = profiles.configuration(id)
profiles.setBackground(true,current.revision,id)
local due = profiles.dueProfiles(now,true)
assert(#due==1 and due[1].id==id)
local standardFeeds = 0
launch.DownloadPage = function(_, url, callback)
	assert(url:find("league=Standard",1,true))
	standardFeeds = standardFeeds+1
	reply(url,callback)
end
local defaultState = read(configFile)
profiles.tickAll(now)
assert(standardFeeds==9 and read(namedTarget)==refreshed and read(configFile)==defaultState)
local config = profiles.configuration(id)
assert(config.lastSuccess and config.day and #config.priceHistory==1)
local nextDate = os.date("*t",now)
nextDate.day, nextDate.hour, nextDate.min, nextDate.sec, nextDate.isdst = nextDate.day+3,0,0,0,nil
assert(not profiles.isDue(config,os.time(nextDate)-1) and profiles.isDue(config,os.time(nextDate)))
profiles.pause(true,id)
assert(profiles.configuration(id).paused and not profiles.configuration().paused)
profiles.rollback(id)
assert(read(namedTarget)==cardBaseline and read(configFile)==defaultState)
local report = require("dkjson").decode(profiles.diagnosticReport(now,id))
assert(report.status.league=="Standard" and report.intervalDays==3)
print("Named profiles isolate destinations, history, schedule, rollback, and background opt-in")

local verifiedRaw, verifiedState = profiles.verifiedOutput("default")
assert(verifiedRaw==read(target) and verifiedState.realm=="pc" and verifiedState.digest==profiles.configuration().current)
write(target,verifiedRaw.."# local edit")
assert(not pcall(profiles.verifiedOutput,"default"))
write(target,verifiedRaw)
assert(not pcall(profiles.verifiedOutput,id))
print("Account publication can only read the latest verified, unchanged local output")


local function checkBackupHistory()
	-- Review an older recorded backup, refuse checksum and revision drift,
	-- then retain the previously active bytes as an undo point after restore.
	local recorded = profiles.configuration()
	local fixedAtReview = read(recorded.baseline)
	local olderRule = table.concat({"Hide", '    Class == "Stackable Currency"', '    BaseType == "Orb of Transmutation"',
		"    StackSize <= 3", "", "# PoB economy: end"}, "\n")
	local olderBytes, changed = fixedAtReview:gsub("# PoB economy: end",olderRule,1)
	assert(changed == 1)
	local digestOf = require("sha1")
	local oldDigest = digestOf(olderBytes)
	local oldPath = target .. ".before-pob-sync-" .. oldDigest .. ".bak"
	local configurationCodec = require("dkjson")
	assert(oldDigest ~= recorded.current and oldDigest ~= recorded.backup)
	table.insert(recorded.history,{backup=oldDigest,checkedAt=now-86400})
	write(configFile,assert(configurationCodec.encode(recorded)))
	write(oldPath,olderBytes.."# edited")
	local canReview, reason = pcall(profiles.previewBackup,"default",oldDigest)
	assert(not canReview and reason:find("checksum mismatch",1,true))
	write(oldPath,olderBytes)
	local reviewedBackup = profiles.previewBackup("default",oldDigest)
	assert(reviewedBackup.before == verifiedRaw and reviewedBackup.after == olderBytes)
	profiles.setBackground(false,recorded.revision)
	assert(not pcall(profiles.rollback,"default",reviewedBackup) and read(target)==verifiedRaw)
	reviewedBackup = profiles.previewBackup("default",oldDigest)
	profiles.rollback("default",reviewedBackup)
	local restoredConfig = profiles.configuration()
	assert(restoredConfig.paused and not restoredConfig.review and read(target)==olderBytes)
	assert(profiles.previewBackup("default",restoredConfig.backup).after==verifiedRaw)
	-- Simulate a restart after replacing the target but before finishing its journal.
	local interrupted = profiles.configuration()
	interrupted.pending = interrupted.backup
	interrupted.pendingRestore = {undo=interrupted.current}
	local intended = interrupted.pending
	write(configFile,assert(configurationCodec.encode(interrupted)))
	write(target,verifiedRaw)
	local availableBackups = profiles.backups("default")
	local reconciled = profiles.configuration()
	assert(reconciled.paused and reconciled.current==intended and not reconciled.pending and not reconciled.pendingRestore)
	assert(availableBackups[1].digest==oldDigest and read(target)==verifiedRaw)
	-- Once another restore changes the latest undo pointer, the earlier
	-- undo-only snapshot remains available from the persistent list.
	local third = olderBytes:gsub("StackSize <= 3","StackSize <= 8",1)
	local thirdDigest = digestOf(third)
	local thirdPath = target..".before-pob-sync-"..thirdDigest..".bak"
	write(thirdPath,third)
	table.insert(reconciled.history,{backup=thirdDigest,checkedAt=now-86400})
	write(configFile,assert(configurationCodec.encode(reconciled)))
	profiles.rollback("default",profiles.previewBackup("default",thirdDigest))
	assert(read(target)==third and profiles.configuration().backup~=oldDigest)
	assert(profiles.previewBackup("default",oldDigest).after==olderBytes)
	profiles.rollback("default",profiles.previewBackup("default",profiles.configuration().backup))
	reconciled = profiles.configuration()
	assert(read(target)==verifiedRaw)
	print("Reviewed backup restore checks historical bytes and recovers an interrupted restore")

	-- A new limit becomes effective after a successful refresh. Reclaim
	-- only recorded backup bytes that still match their original digest.
	local retired = olderBytes:gsub("StackSize <= 3","StackSize <= 2",1)
	local suspect = olderBytes:gsub("StackSize <= 3","StackSize <= 7",1)
	local retiredDigest, suspectDigest = digestOf(retired), digestOf(suspect)
	assert(retiredDigest~=oldDigest and suspectDigest~=oldDigest and retiredDigest~=suspectDigest)
	local retiredPath = target..".before-pob-sync-"..retiredDigest..".bak"
	local suspectPath = target..".before-pob-sync-"..suspectDigest..".bak"
	write(retiredPath,retired)
	write(suspectPath,suspect.."# modified")
	table.insert(reconciled.history,{backup=retiredDigest,checkedAt=now-2*86400})
	table.insert(reconciled.history,{backup=suspectDigest,checkedAt=now-3*86400})
	local heldBytes = olderBytes:gsub("StackSize <= 3","StackSize <= 9",1)
	local heldDigest = digestOf(heldBytes)
	local heldPath = target..".before-pob-sync-"..heldDigest..".bak"
	write(heldPath,heldBytes)
	table.insert(reconciled.history,{backup=heldDigest,checkedAt=now-4*86400})
	write(configFile,assert(configurationCodec.encode(reconciled)))
	assert(not pcall(profiles.setBackupLimit,"default",1,"stale revision"))
	profiles.setBackupLimit("default",1,reconciled.revision)
	assert(read(retiredPath)==retired and read(suspectPath)==suspect.."# modified")
	local otherProfileBytes = read(namedTarget)
	profiles.pause(false)
	launch.DownloadPage = function(_,url,callback)
		local mapBody = stash[url:match("&type=(%w+)$")]
		if mapBody then callback({header=header,body=mapBody}); return end
		reply(url,callback)
	end
	local size = kernel.MultiByteToWideChar(65001,8,heldPath,-1,nil,0)
	local wide = ffi.new("uint16_t[?]",size)
	assert(kernel.MultiByteToWideChar(65001,8,heldPath,-1,wide,size)==size)
	local holding = kernel.CreateFileW(wide,0x80000000,1,nil,3,0x80,nil)
	assert(holding~=ffi.cast("void *",-1))
	profiles.tick(now,true)
	assert(kernel.CloseHandle(holding)~=0)
	assert(read(heldPath)==heldBytes and profiles.status:find("Protected drops verified",1,true),profiles.status)
	assert(profiles.verifiedOutput("default")==read(target))
	assert(not io.open(retiredPath,"rb") and read(suspectPath)==suspect.."# modified")
	assert(read(reconciled.baseline)==fixedAtReview and read(namedTarget)==otherProfileBytes)
	assert(profiles.configuration().retentionSkipped==2)
	print("Opt-in retention preserves unverifiable files, the baseline and other profiles")

	local afterRetention = profiles.configuration()
	profiles.setBackupLimit("default",0,afterRetention.revision)
	local aged = olderBytes:gsub("StackSize <= 3","StackSize <= 12",1)
	local agedDigest = digestOf(aged)
	local agedPath = target..".before-pob-sync-"..agedDigest..".bak"
	write(agedPath,aged)
	local state = profiles.configuration()
	table.insert(state.history,{backup=agedDigest,checkedAt=now-7*86400})
	write(configFile,assert(configurationCodec.encode(state)))
	for _=1,31 do
		profiles.tick(now,true)
		assert(profiles.status:find("Protected drops verified",1,true),profiles.status)
	end
	state=profiles.configuration()
	assert(#state.history==30 and state.backupRecords[agedDigest] and read(agedPath)==aged)
	for _, run in ipairs(state.history) do assert(run.backup~=agedDigest) end
	profiles.setBackupLimit("default",1,state.revision)
	profiles.tick(now,true)
	assert(profiles.status:find("Protected drops verified",1,true),profiles.status)
	assert(not io.open(agedPath,"rb") and not profiles.configuration().backupRecords[agedDigest])
	print("The backup catalog survives repeated unchanged refreshes and still supports retention")
end
checkBackupHistory()
-- A successful-looking but severely incomplete feed must keep the last
-- verified file and its publication record.
local coverageTarget = dir.."/coverage-target.filter"
write(coverageTarget,cardBaseline)
local coverageProfile = profiles.createProfile("Coverage fixture")
profiles.configure(coverageTarget,baseline,"Covens",{profileId=coverageProfile,hour=0,targetValue=1,protectionFile=protections})
local exchangeClock, originalClock, extra = now, os.time, 23
os.time = function() return exchangeClock end
local codec = require("dkjson")
launch.DownloadPage = function(_,url,callback)
	local body = url:match("&type=DivinationCard$") and cardBody or commodityBody
	if url:match("&type=Currency$") then
		local data = assert(codec.decode(body))
		for index=1,extra do
			local id = "fixture-"..index
			data.items[#data.items+1] = {id=id,name="Fixture currency "..index}
			data.lines[#data.lines+1] = {id=id,primaryValue=0.21,volumePrimaryValue=1000}
		end
		body = codec.encode(data)
	end
	callback({header="HTTP/1.1 200 OK\r\nDate: "..os.date("!%a, %d %b %Y %H:%M:%S GMT",exchangeClock).."\r\nAge: 5\r\n\r\n",body=body})
end
profiles.tick(exchangeClock,true,false,coverageProfile)
exchangeClock = exchangeClock+86400
profiles.tick(exchangeClock,true,false,coverageProfile)
local verifiedCoverage = profiles.configuration(coverageProfile)
assert(verifiedCoverage.lastSuccess==exchangeClock and #verifiedCoverage.priceHistory==2)
local coverageBytes = read(coverageTarget)
extra, exchangeClock = 4, exchangeClock+86400
profiles.tick(exchangeClock,true,false,coverageProfile)
os.time = originalClock
local incomplete = profiles.configuration(coverageProfile)
assert(incomplete.lastSuccess==verifiedCoverage.lastSuccess and #incomplete.priceHistory==2 and read(coverageTarget)==coverageBytes)
assert(incomplete.lastFailure and incomplete.lastFailure.message:find("Currency feed has fewer than a quarter",1,true))
print("A severe loss of exchange coverage retains the last verified output")

local function checkAppearanceRoundTrip()
	local styleBase, styleTarget=dir.."/appearance-baseline.filter",dir.."/appearance-live.filter"
	local raw=table.concat({
		'Show','    BaseType == "Cord Belt"', '# PoB economy: begin','Hide',
		'    Class == "Stackable Currency"','    BaseType == "Orb of Alteration"','    StackSize <= 6',
		'# PoB economy: end','Show','    Class == "Stackable Currency"',
		'    BaseType == "Orb of Alteration"','    MinimapIcon 2 White Circle','',
	},"\n")
	write(styleBase,raw)
	write(styleTarget,raw)
	local profileId=profiles.createProfile("Appearance fixture")
	local settings={profileId=profileId,hour=0,targetValue=100,protectionFile=protections,pickupPolicy={highlightChaos=2,strongHighlightChaos=3}}
	profiles.configure(styleTarget,styleBase,"Covens",settings)
	launch.DownloadPage=function(_,url,callback) reply(url,callback) end
	profiles.tick(now,true,false,profileId)
	local highlighted=read(styleTarget)
	assert(highlighted~=raw and profiles.verifiedOutput(profileId)==highlighted)
	profiles.tick(now,true,false,profileId)
	assert(profiles.status:find("Protected drops verified",1,true) and read(styleTarget)==highlighted)
	local edited=highlighted:gsub("MinimapIcon 1 Yellow Circle","MinimapIcon 2 Purple Circle",1)
	write(styleTarget,edited)
	assert(not pcall(profiles.configure,styleTarget,styleBase,"Covens",settings))
	write(styleTarget,highlighted)
	settings.pickupPolicy=nil
	profiles.configure(styleTarget,styleBase,"Covens",settings)
	profiles.tick(now,true,false,profileId)
	assert(profiles.status:find("Protected drops verified",1,true) and read(styleTarget)==raw and read(styleBase)==raw)
	print("Price highlights survive a second refresh and are reversibly removed from the target")
end
checkAppearanceRoundTrip()

local function checkConfirmedTightening()
	local target=dir.."/confirmed-live.filter"
	local fixed=dir.."/confirmed-fixed.filter"
	local raw=table.concat({
		'Show','    BaseType == "Cord Belt"','# PoB economy: begin','Hide',
		'    Class == "Stackable Currency"','    BaseType == "Orb of Alteration"',
		'    StackSize <= 2','# PoB economy: end','Show','',
	},"\n")
	write(target,raw);write(fixed,raw)
	local id=profiles.createProfile("GGG confirmation fixture")
	profiles.configure(target,fixed,"Covens",{profileId=id,hour=0,targetValue=1,protectionFile=protections,
		pickupPolicy={caps={["Orb of Alteration"]=7},confirmTightening=true}})
	local clock, systemTime, chaosVolume=now,os.time,nil
	os.time=function() return clock end
	local exchange=require("Modules.LootFilterExchangeCrossCheck")
	local itemId=assert(exchange.itemId("Orb of Alteration"))
	local chaosId="Metadata/Items/Currency/CurrencyRerollRare"
	launch.DownloadPage=function(_,url,callback)
		if url:find(exchange.endpoint,1,true)==1 then
			if not chaosVolume then callback(nil,"Temporary outage"); return end
			callback({body=require("dkjson").encode({next_change_id=exchange.hour(clock)+3600,markets={{
				league="Covens",market_pair={itemId,chaosId},volume_traded={[itemId]=500,[chaosId]=chaosVolume}
			}}})})
			return
		end
		callback({header="HTTP/1.1 200 OK\r\nDate: "..os.date("!%a, %d %b %Y %H:%M:%S GMT",clock).."\r\n\r\n",body=commodityBody})
	end
	for _=1,4 do
		profiles.tick(clock,true,false,id)
		assert(profiles.status:find("Protected drops verified",1,true) and read(target)==raw)
		clock=clock+86400
	end
	local skipped=profiles.configuration(id).review.skipped[1]
	assert(skipped.reason:find("GGG trade",1,true))
	chaosVolume=450
	profiles.tick(clock,true,false,id)
	assert(read(target)==raw)
	clock, chaosVolume = clock+86400, 100
	profiles.tick(clock,true,false,id)
	os.time=systemTime
	local review=profiles.configuration(id).review
	assert(read(target):find("StackSize <= 4",1,true) and review.changes[1].confirmedPrice==0.2)
	print("GGG confirmation vetoes a new hide on missing or higher historical trades")
end
checkConfirmedTightening()

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
