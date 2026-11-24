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
    LinkedSockets >= 6

Hide
    Class == "Stackable Currency"
    HasCruciblePassiveTree True

Hide
    BaseType == "Orb of Chance"
    ItemLevel >= 70

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
	assert(params.timeout == 20 and params.followRedirects == false)
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
assert(sync.configuration().review.changes[1].priceId=="alt")
local exposed = sync.publicStatus(now)
assert(exposed.state=="enabled" and exposed.adjustmentCount==1 and exposed.latestChanges[1].proposedCutoff==4)
local payload=require("dkjson").encode(exposed)
assert(not payload:find("target.filter",1,true) and not payload:find("protect.json",1,true))
local diff = sync.publicDiff(now)
assert(diff.verifiedProtection and diff.protectedChecks==1 and diff.changeCount==1 and #diff.changes==1)
assert(#diff.feeds==8 and diff.feeds[1].category=="Currency" and not diff.feeds[1].revalidated
	and diff.feeds[1].responseAge==diff.responseAges[1])
assert(diff.changes[1].item=="Orb of Alteration" and diff.changes[1].sample.action=="Show")
do
	local output=read(target)
	local settings=read(configFile)
	local before,after=sync.compareObservedStack("default","Orb of Alteration",5,83)
	assert(before.action=="Hide" and after.action=="Show" and before.line and after.line)
	before,after=sync.compareObservedStack("default","Orb of Chance",5,83)
	assert(before.action=="Unknown" and after.action=="Unknown" and after.missingProperties[1]=="ItemLevel")
	before,after=sync.compareObservedStack("default","Orb of Chance",5,83,69)
	assert(before.action=="Show" and after.action=="Show")
	assert(not pcall(sync.compareObservedStack,"default","Orb of Alteration",1.5,83))
	assert(not pcall(sync.compareObservedStack,"default","Orb of Alteration",5,83,nil,"Map Fragments"))
	assert(read(target)==output and read(configFile)==settings)
	write(target,output.."\n# External edit")
	assert(not pcall(sync.compareObservedStack,"default","Orb of Alteration",5,83))
	write(target,output)
end
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
assert(market.resolveEndpoint("https://prices.example.test:9443/pob-market/")=="https://prices.example.test:9443/pob-market/")
assert(not market.resolveEndpoint("http://localhost:9410") and not market.resolveEndpoint("https://prices.example.test/?token=secret"))
assert(not market.resolveEndpoint("https://login@prices.example.test") and not market.resolveEndpoint("https://prices.example.test:100000"))
local function quote(price)
	return {["Orb of Alteration"]={id="alt",price=price,volume=1000,source="Currency"}}
end
local _, first = market.remember(quote(0.2), {}, "day 1", now)
local spike, second = market.remember(quote(2), first, "day 2", now+86400)
assert(spike["Orb of Alteration"].price==0.2 and spike["Orb of Alteration"].currentPrice==2)
local lower = market.remember(quote(0.1), second, "day 3", now+2*86400)
assert(lower["Orb of Alteration"].price==0.1)
do
	local raw = market.addManagedSection([[Hide
    Class == "Stackable Currency"
    BaseType == "Chaos Orb"
    StackSize <= 2
]], {
		{name="Orb of Alteration",class="Stackable Currency",scope="campaign",cutoff=4},
		{name="Orb of Alteration",class="Stackable Currency",scope="maps",cutoff=7},
	})
	local caps = {["Orb of Alteration"]=6,["orb of alteration"]=10,["Chaos Orb"]=5}
	local after, changes, skipped = market.review(raw,{},1,{caps=caps})
	assert(after==raw and #changes==0)
	assert(skipped[3].name=="Chaos Orb" and skipped[3].policyCap==5 and not skipped[3].old)
	assert(skipped[4].name=="orb of alteration" and skipped[4].policyCap==10 and not skipped[4].old)
	caps["Orb of Alteration"]=4
	local _, _, bounded = market.review(raw,{},1,{caps=caps})
	assert(bounded[4].name=="Orb of Alteration" and bounded[4].old==4 and bounded[4].policyCap==4)
end
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
	assert(not pcall(market.pickupPolicy,100,{highlightStyle="invalid"}))
	style.highlightStyle, style.strongHighlightStyle = "cyan-diamond", "purple-star"
	local themed = market.review(raw,quotes,100,style)
	local themedRules = parser.parse(themed)
	assert(#themedRules.diagnostics==0 and appearance.strip(themed)==raw)
	for stack=1,30 do
		for _, area in ipairs({60,83}) do
			local item = {BaseType="Orb of Alteration",Class="Stackable Currency",StackSize=stack,AreaLevel=area}
			local before, after = parser.simulate(candidate,item), parser.simulate(themedRules,item)
			assert(before.action==after.action)
			if area==83 and stack==10 then
				assert(table.concat(after.styles.MinimapIcon," ")=="0 Cyan Diamond")
				assert(after.styles.PlayEffect[1]=="Cyan")
			elseif area==83 and stack==15 then
				assert(table.concat(after.styles.MinimapIcon," ")=="0 Purple Star")
				assert(after.styles.PlayEffect[1]=="Purple")
			else
				local expected = table.concat(before.styles.MinimapIcon or {}," ")
				if area==83 and stack>=10 and stack<20 and stack~=18 then
					expected = stack<15 and "0 Cyan Diamond" or "0 Purple Star"
				end
				assert(table.concat(after.styles.MinimapIcon or {}," ")==expected)
			end
		end
	end
	local validation = require("Modules.LootFilterSyncValidation")
	local bodies = {}
	local body = [[{"core":{"primary":"chaos"},"items":[{"id":"alt","name":"Orb of Alteration"}],"lines":[{"id":"alt","primaryValue":0.2,"volumePrimaryValue":1000}]}]]
	for index = 1, #market.feedCategories(raw) do bodies[index] = body end
	local _, _, reviewed = validation(raw,bodies,false,100,{{BaseType="Cord Belt",Rarity="Magic",Class="Belts"}},nil,nil,nil,style)
	local medium, strong = reviewed[1].samples[1], reviewed[1].samples[2]
	assert(medium.area==83 and medium.count==10 and medium.marker=="0 Cyan Diamond")
	assert(strong.area==83 and strong.count==15 and strong.marker=="0 Purple Star")
	local mismatched = themed:gsub("cyan%-diamond","red-diamond",1)
	assert(not pcall(appearance.strip,mismatched))
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
do
	local _, first = market.remember(quoteBatch(8,"Map"),{},"maps one",now)
	local _, second = market.remember(quoteBatch(8,"Map"),first,"maps two",now+86400)
	local ok, failure = pcall(market.remember,quoteBatch(3,"Map"),second,"thin maps",now+2*86400)
	assert(not ok and failure:find("Map feed has fewer than half",1,true),failure)
	assert(pcall(market.remember,quoteBatch(4,"Map"),second,"four map tiers",now+2*86400))
end

local _, repeatDay = market.remember(quote(2), second, "day 2", now+86400)
assert(#repeatDay==2)
-- Ambiguous identities stay ineligible even when the conflicting quote has more volume.
local ambiguous = market.quotes([[{"core":{"primary":"chaos"},"items":[{"id":"a","name":"Shared"},{"id":"b","name":"Shared"}],"lines":[{"id":"a","primaryValue":1,"volumePrimaryValue":100},{"id":"b","primaryValue":10,"volumePrimaryValue":10000}]}]], "Currency")
assert(ambiguous.Shared == false)
do
	local mixed = market.quotes([[{"core":{"primary":"chaos"},"items":[{"id":"x","name":"Repeated"}],
		"lines":[{"id":"x","primaryValue":1,"volumePrimaryValue":500},{"id":"x","primaryValue":2,"volumePrimaryValue":900}]}]],"Currency")
	assert(mixed.Repeated==false)
	local merged = {}
	market.merge(merged,{Overlap={id="same",price=1,volume=200,source="Currency"}},"Currency")
	market.merge(merged,{Overlap={id="same",price=1,volume=2000,source="Oil"}},"Oil")
	assert(merged.Overlap.source=="Currency" and merged.Overlap.volume==200)
	market.merge(merged,{Overlap={id="same",price=2,volume=2000,source="Oil"}},"Oil")
	assert(merged.Overlap==false)
	assert(not pcall(market.quotes,[[{"core":{"primary":"chaos"},"items":[{"id":"a\u0000b","name":"Unsafe"}],"lines":[]}]],"Currency"))
	local mapQuotes = market.quotes([[{"lines":[
		{"name":"Map (Tier 12)","detailsId":"same-tier","chaosValue":2,"count":40,"listingCount":40},
		{"name":"Map (Tier 13)","detailsId":"same-tier","chaosValue":2,"count":40,"listingCount":40}
	]}]],"Map")
	assert(mapQuotes["Map (Tier 12)"]==false and mapQuotes["Map (Tier 13)"]==false)

	local function exchange(first, second)
		return assert(json.encode({
			core={primary="chaos"}, items={{id="x",name="Repeated"}},
			lines={{id="x",primaryValue=1,volumePrimaryValue=first},{id="x",primaryValue=1,volumePrimaryValue=second}},
		}))
	end
	for _, body in ipairs({exchange(2000,10),exchange(10,2000)}) do
		local quote = market.quotes(body,"Currency").Repeated
		assert(quote.volume==10 and not market.liquid(quote))
	end
	assert(market.quotes(exchange(2000,0),"Currency").Repeated==false)
	assert(not pcall(market.quotes,exchange(2000,2000).."{}","Currency"))

	local function mapRow(name, volume, base)
		return {name=name,detailsId="tier-price",chaosValue=2,count=volume,listingCount=40,baseType=base}
	end
	local function mapBody(first, second)
		return assert(json.encode({lines={first,second}}))
	end
	local large, small = mapRow("Map (Tier 12)",100), mapRow("Map (Tier 12)",5)
	for _, body in ipairs({mapBody(large,small),mapBody(small,large)}) do
		local quote = market.quotes(body,"Map")["Map (Tier 12)"]
		assert(quote.volume==5 and not market.liquid(quote))
	end
	local namedMap = mapRow("Cemetery Map",40,"Cemetery Map")
	local noListings = mapRow("Map (Tier 12)",0)
	for _, other in ipairs({namedMap,noListings}) do
		assert(market.quotes(mapBody(other,large),"Map")["Map (Tier 12)"]==false)
		assert(market.quotes(mapBody(large,other),"Map")["Map (Tier 12)"]==false)
	end
	assert(not pcall(market.quotes,mapBody(large,large).."{}","Map"))
end
local joined = {Shared={id="a",price=1,volume=100,source="Currency"}}
market.merge(joined, {Shared={id="b",price=10,volume=10000,source="Oil"}})
assert(joined.Shared == false)
assert(market.liquid({source="Currency",volume=120}) and not market.liquid({source="Omen",volume=120}))

-- Timed retry and conditional cache use do not touch the filter during preview.
local testEndpoint = market.endpoint
local systemTime = os.time
do
	market.endpoint = testEndpoint.."test-timed/"
	local clock = now
	os.time = function() return clock end
	local networkCount, conditional, transient = 0, 0, true
	local cachedHeader = header:gsub("Age: 5", 'Age: 5\r\nETag: W/"fixture"')
	launch.DownloadPage = function(_, _, callback, params)
		networkCount = networkCount + 1
		assert(params.followRedirects == false and not params.header:find("no-cache",1,true))
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
	assert(not reviewed and networkCount==1 and sync.busy and sync.providerWait(clock)==20)
	clock=now+19
	sync.tick(clock)
	assert(networkCount==1 and sync.providerWait(clock)==1)
	clock=now+20
	sync.tick(clock)
	assert(reviewed and networkCount==9 and sync.providerWait(clock)==0 and read(target)==original)
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
	market.endpoint=testEndpoint
	package.loaded["Modules.LootFilterDailySync"]=nil
	sync=require("Modules.LootFilterDailySync")
end

-- An expired season yields an empty successful price response. Confirm
-- against the fresh provider list and retain the user's chosen profile.
local obsolete = "Ended Fixture"
local leagueChecks = 0
local markets = '[{"id":"Covens","name":"Covens"},{"id":"Standard","name":"Standard"}]'
launch.DownloadPage = function(_,url,callback,params)
	assert(params.followRedirects == false)
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
		{"name":"Conflicted result","baseType":"Cord Belt","detailsId":"conflicted","chaosValue":5,"count":100,"listingCount":70},
		{"name":"No identifier","baseType":"Cord Belt","chaosValue":400,"count":100,"listingCount":70},
		{"name":"Wrong base","baseType":"Heavy Belt","detailsId":"collision","chaosValue":500,"count":100,"listingCount":70},
		{"name":"Wrong base","baseType":"Cord Belt","detailsId":"collision","chaosValue":500,"count":100,"listingCount":70}
	]}]],{id="UniqueAccessory"},"Named result",nil,{
		{title="NAMED RESULT",baseName="Cord Belt"},
		{title="Missing result",baseName="Cord Belt"},
		{title="Missing result",baseName="Cord Belt"},
		{title="Thin result",baseName="Cord Belt"},
		{title="Different base",baseName="Leather Belt"},
		{title="Alternate base",baseName="Leather Belt",baseLines={["Leather Belt"]={},["Cord Belt"]={}}},
	})
	assert(#sharedBase==1 and sharedBase[1].corrupted==false)
	local evidence = sharedBase[1].baseEvidence
	assert(evidence.names==6 and evidence.variants==6 and evidence.priced==2 and evidence.minimum==30 and evidence.maximum==120)
	assert(#evidence.unquoted==3 and evidence.unquoted[1]=="Alternate base"
		and evidence.unquoted[2]=="Missing result" and evidence.unquoted[3]=="Thin result")
	local collision = browser.rows([[{"lines":[
		{"name":"Same name","baseType":"Cord Belt","detailsId":"shared-id","chaosValue":300,"count":100,"listingCount":70},
		{"name":"Different name","baseType":"Cord Belt","detailsId":"shared-id","chaosValue":300,"count":100,"listingCount":70}
	]}]],{id="UniqueAccessory"},"=Same name")[1]
	assert(collision.conflicting and not collision.price and collision.baseEvidence.priced==0)
	local unmodifiedGem = browser.rows([[{"lines":[{"name":"Example gem","chaosValue":1,"gemLevel":1,"gemQuality":0}]}]],{id="SkillGem"})[1]
	assert(unmodifiedGem.gemQuality==0 and unmodifiedGem.corrupted==nil and unmodifiedGem.incomplete)
	local gems = [[{"lines":[
		{"name":"Example gem","detailsId":"example-gem-1-0","chaosValue":1,"gemLevel":1,"gemQuality":0,"corrupted":false,"count":30,"listingCount":25},
		{"name":"Example gem","detailsId":"example-gem-21-20","chaosValue":41,"gemLevel":21,"gemQuality":20,"corrupted":true,"count":35,"listingCount":18},
		{"name":"Example gem of Testing","detailsId":"transfigured-gem","chaosValue":710,"gemLevel":1,"gemQuality":0,"corrupted":false}
	]}]]
	local exact = browser.rows(gems,{id="SkillGem"},"=Example gem")
	assert(#exact==2 and exact[1].price==41 and exact[1].corrupted and not exact[1].supported)
	assert(exact[2].supported and exact[2].corrupted==false and not exact[2].incomplete)
	assert(browser.rows(gems,{id="SkillGem"},"=example-gem-1-0")[1].gemQuality==0)
	local base = browser.rows([[{"lines":[
		{"name":"Example base","detailsId":"example-base","chaosValue":12,"count":50,"listingCount":25},
		{"name":"Example base","detailsId":"example-base","chaosValue":40,"count":50,"listingCount":25}
	]}]],{id="BaseType"},"=example-base")
	assert(#base==1 and base[1].conflicting and not base[1].price)
	assert(browser.rows(gems,{id="ImbuedGem"},"=transfigured-gem")[1].incomplete==nil)
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

do
	-- Fail the settings commit only after the target was atomically replaced.
	secondWindow.pause(false)
	local json = require("dkjson")
	local settingsFile = dir.."/LootFilterDailySync.json"
	local receiptFile = dir.."/LootFilterDailySync-PendingRefresh.json"
	-- A legitimate settings file and new review can exceed the size limit together.
	local prior = secondWindow.configuration()
	prior.priceHistory = {}
	for day=1,4 do
		local values = {}
		for index=1,1600 do values["SkillGem:"..index..string.rep("x",185)] = 1 end
		prior.priceHistory[day] = {day="prior "..day,time=now-day*86400,values=values}
	end
	write(settingsFile,assert(json.encode(prior)))
	local failedCommit = false
	io.open = function(path, mode)
		if not failedCommit and path==settingsFile..".tmp" and mode=="wb" and read(target)==refreshed then
			failedCommit = true
			return nil,"Injected final settings write failure"
		end
		return openFile(path,mode)
	end
	secondWindow.tick(now+1,true)
	io.open = openFile
	local interrupted = secondWindow.configuration()
	assert(failedCommit and read(target)==refreshed and interrupted.pendingRefresh and interrupted.pending)
	local receiptBytes = read(receiptFile)
	local receipt = assert(json.decode(receiptBytes))
	assert(#read(settingsFile)+#receiptBytes>2*1024*1024)
	assert(interrupted.current~=interrupted.pending and interrupted.pendingRefresh==require("sha1")(receiptBytes))
	assert(receipt.review.checkedAt==now+1)
	assert(not pcall(secondWindow.verifiedOutput,"default"))
	-- Make the retry eligible and simulate restarting with an active provider hold.
	interrupted.lastFailure = nil
	write(settingsFile,assert(json.encode(interrupted)))
	local replacementWindow = assert(loadfile("Modules/LootFilterDailySync.lua"))()
	local priorEndpoint = market.endpoint
	market.endpoint = priorEndpoint.."local-recovery-test/"
	replacementWindow.noteProviderLimit({header="HTTP/1.1 429 Too Many Requests\r\nRetry-After: 3600\r\n\r\n"},429,os.time())
	assert(replacementWindow.providerWait(os.time())>0 and #replacementWindow.dueProfiles(now+1,false)==1)
	local recoveryRequests = 0
	launch.DownloadPage = function() recoveryRequests = recoveryRequests+1; error("Provider unavailable") end
	-- A corrupt expected snapshot cannot be treated as a verified installation.
	local expected = dir.."/LootFilterExpected-"..interrupted.pending..".filter"
	write(expected,"Corrupt expected snapshot")
	replacementWindow.tick(now+2,true)
	assert(recoveryRequests==0 and read(target)==refreshed and replacementWindow.configuration().pendingRefresh)
	assert(replacementWindow.status:find("snapshot could not be verified",1,true),replacementWindow.status)
	write(expected,refreshed)
	local external = refreshed.."\n# Outside edit"
	local edited = false
	io.open = function(path, mode)
		if not edited and path==interrupted.baseline and mode=="rb" then
			edited = true
			write(target,external)
		end
		return openFile(path,mode)
	end
	replacementWindow.tick(now+3,true)
	io.open = openFile
	assert(edited and read(target)==external and replacementWindow.configuration().pendingRefresh)
	assert(replacementWindow.status:find("Target changed during the interrupted refresh",1,true))
	write(target,refreshed)
	local recoveryTime = now+1804
	assert(replacementWindow.providerWait(recoveryTime)>0 and #replacementWindow.dueProfiles(recoveryTime,false)==1)
	replacementWindow.tick(recoveryTime,false)
	local recovered = replacementWindow.configuration()
	assert(recoveryRequests==0 and read(target)==refreshed and not recovered.pending and not recovered.pendingRefresh)
	assert(recovered.lastSuccess==now+1 and recovered.review.checkedAt==now+1 and not recovered.lastFailure)
	assert(recovered.marketSourceHash==receipt.sourceHash and not io.open(receiptFile,"rb"))
	assert(#recovered.history==#interrupted.history+1 and replacementWindow.verifiedOutput("default")==refreshed)
	assert(replacementWindow.archivedReviews("default")[recovered.history[1].reviewKey].checkedAt==now+1)
	market.endpoint = priorEndpoint
end
print("Windows refresh recovery passed across a partial write, sharing violation, final commit failure, and provider cooldown")


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
market.endpoint=testEndpoint.."test-background/"
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
market.endpoint=testEndpoint
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
assert(mapChanges[1].sample.before=="Hide" and mapChanges[1].sample.action=="Show" and mapChanges[1].priceId=="ordinary-16")
-- Every map rarity gets an independent impact result, including custom shadowing.
for _, late in ipairs({false,true}) do
	local rareHide = 'Hide\n    Class == "Maps"\n    Rarity == Rare\n'
	local commonShow = 'Show\n    Class == "Maps"\n    Rarity <= Magic\n'
	local rules = 'Show\n    BaseType == "Cord Belt"\n' .. (late and commonShow..rareHide or rareHide..commonShow)
	local baseline = market.addManagedSection(rules,{{class="Maps",tier=16,mapType="Map"}})
	local feeds = {}
	for index, category in ipairs(market.feedCategories(baseline)) do feeds[index]=category=="Map" and normalMap or commodityBody end
	local _, _, changes = validate(baseline,feeds,false,1,mapSamples,nil,nil,nil,{maps=5})
	local change = changes[1]
	assert(change.sample==change.samples[1] and change.sample.rarity=="Normal" and not change.samplesLimited)
	local seen = {}
	for _, sample in ipairs(change.samples) do
		seen[sample.rarity]=true
		assert(sample.before=="Hide" and type(sample.beforeLine)=="number" and type(sample.line)=="number")
		assert(sample.action==(sample.rarity=="Rare" and "Hide" or "Show"))
		assert(sample.beforeLine~=sample.line)
	end
	assert(seen.Normal and seen.Magic and seen.Rare and #change.samples==3)
end
-- The global simulation bound marks both partial and wholly deferred decisions.
do
	local baseline = market.addManagedSection('Show\n    BaseType == "Cord Belt"\nShow\n    Class == "Maps"\n',{{class="Maps",tier=16,mapType="Map"}})
	baseline=baseline:gsub("(# PoB economy: begin\n)(.-)(# PoB economy: end)",function(first,blocks,last) return first..blocks:rep(170)..last end)
	local feeds = {}
	for index, category in ipairs(market.feedCategories(baseline)) do feeds[index]=category=="Map" and normalMap or commodityBody end
	local _, _, changes = validate(baseline,feeds,false,1,mapSamples,nil,nil,nil,{maps=5})
	local total, partial, empty = 0,false,false
	for _, change in ipairs(changes) do
		total=total+#change.samples
		if #change.samples<3 then
			assert(change.samplesLimited==true)
			partial=partial or #change.samples>0
			empty=empty or #change.samples==0
		else assert(not change.samplesLimited) end
	end
	assert(total==500 and partial and empty)
end
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
local publicMaps = marketSync.publicDiff(now)
local publicRarities = {}
for _, sample in ipairs(publicMaps.changes[1].samples) do
	publicRarities[sample.rarity]=true
	assert(type(sample.beforeLine)=="number" and type(sample.line)=="number")
end
assert(publicRarities.Normal and publicRarities.Magic and publicRarities.Rare)

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
	launch.DownloadPage=function(_,url,callback,params)
		assert(params.followRedirects == false)
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
	assert(params.timeout == 20 and params.followRedirects == false)
	if url:match("/leagues$") then callback({header=header,body='[{"id":"Covens","name":"Covens"}]'}); return end
	reply(url,callback)
end
require("Classes.LootFilterEconomyControl").Open({},cardBaseline,function(_, value) exported=value end)
controls.fetch.action()
assert(manualReview and manualReview.canChoose())
manualReview.choose()
assert(exported==refreshed)

launch.DownloadPage = function(_, url, callback)
	if url:match("/leagues$") then callback({header=header,body='[{"id":"Covens","name":"Covens"}]'}); return end
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
manualReview, exported = nil,nil
do
	local direct = market.endpoint
	market.endpoint = market.resolveEndpoint("https://prices.example.test/pob-market")
	local relayRequests = 0
	launch.DownloadPage = function(_,url,callback)
		relayRequests = relayRequests+1
		assert(url=="https://prices.example.test/pob-market/leagues")
		callback(nil,"Response code: 403")
	end
	manual.Open({},cardBaseline,function(_, value) exported=value end)
	controls.fetch.action()
	assert(relayRequests==1 and not manualReview and not exported)
	market.endpoint = direct
end

market.endpoint=testEndpoint.."test-review/"
local limitedReviewCalls = 0
launch.DownloadPage = function(_,url,callback)
	limitedReviewCalls = limitedReviewCalls+1
	if url:match("/leagues$") then
		callback({header=header,body='[{"id":"Covens","name":"Covens"}]'})
	else
		callback({header="HTTP/1.1 503 Unavailable\r\nRetry-After: 60\r\n\r\n"},"Response code: 503")
	end
end
manual.Open({},cardBaseline,function(_, value) exported=value end)
controls.fetch.action()
assert(limitedReviewCalls==2 and not manualReview and not exported)
controls.fetch.action()
assert(limitedReviewCalls==2 and controls.status.list[1]:find("provider cooldown",1,true))
market.endpoint=testEndpoint
print("Manual review applies the native price freshness, liquidity checks and provider cooldown")

local function checkExternalAdoption()
	local adoptionTarget = dir .. "/external-adoption.filter"
	local fixture = assert(loadfile("Modules/LootFilterDailySync.lua"))()
	local id = fixture.createProfile("External edits fixture")
	local settings = {profileId=id,hour=9,targetValue=1,protectionFile=protections}
	local adoptionBaseline = dir .. "/external-baseline.filter"
	write(adoptionBaseline,original)
	write(adoptionTarget,proposed)
	fixture.configure(adoptionTarget,adoptionBaseline,"Covens",settings)
	local prior = fixture.configuration(id)
	local edited = "# Personal changes\n" .. proposed .. "# Personal footer\n"
	write(adoptionTarget,edited)
	local review = fixture.previewExternalAdoption(id)
	assert(review.before==proposed and review.after==edited)
	assert(review.baseline=="# Personal changes\n" .. original .. "# Personal footer\n")
	assert(read(adoptionTarget)==edited and fixture.configuration(id).baselineHash==prior.baselineHash)
	write(adoptionTarget,edited .. "# Changed after review\n")
	local applied, why = pcall(fixture.adoptExternalEdits,id,review)
	assert(not applied and why:find("changed after the review",1,true))
	write(adoptionTarget,edited:gsub("StackSize <= 4","StackSize <= 40"))
	applied, why = pcall(fixture.previewExternalAdoption,id)
	assert(not applied and why:find("managed economy section changed",1,true))
	write(adoptionTarget,edited:gsub("Show\n    BaseType","Hide\n    BaseType",1))
	applied, why = pcall(fixture.previewExternalAdoption,id)
	assert(not applied and why:find("Protected drop failed",1,true))
	write(adoptionTarget,edited)
	fixture.adoptExternalEdits(id,review)
	local accepted = fixture.configuration(id)
	assert(accepted.revision~=prior.revision and accepted.baselineHash~=prior.baselineHash
		and accepted.target==prior.target and accepted.hour==prior.hour and accepted.league==prior.league)
	assert(read(prior.baseline)==original and read(accepted.baseline)==review.baseline and read(adoptionTarget)==edited)
	assert(not pcall(fixture.verifiedOutput,id))
	launch.noSSL = false
	launch.DownloadPage = function(_, url, callback)
		local body = url:match("/leagues$") and '[{"id":"Covens"}]' or commodityBody
		callback({header=header,body=body})
	end
	fixture.tick(now,true,false,id)
	assert(fixture.status:find("Protected drops verified",1,true),fixture.status)
	assert(fixture.verifiedOutput(id)==edited)
	print("External edit adoption preserved the fixed cutoff, rejected stale review and protected drops, and kept the live file intact")

	local reviewNow = now
	local realClock = os.time
	os.time = function() return reviewNow end
	launch.DownloadPage = function(_, url, callback)
		local body = url:match("/leagues$") and '[{"id":"Covens"}]' or commodityBody
		local date = os.date("!%a, %d %b %Y %H:%M:%S GMT",reviewNow)
		callback({header="HTTP/1.1 200 OK\r\nDate: "..date.."\r\n\r\n",body=body})
	end
	for index=1,7 do
		reviewNow = now+index*86400
		fixture.tick(reviewNow,true,false,id)
		assert(fixture.status:find("Protected drops verified",1,true),fixture.status)
	end
	os.time = realClock
	local restart = assert(loadfile("Modules/LootFilterDailySync.lua"))()
	local runs, archive = restart.configuration(id).history, restart.archivedReviews(id)
	assert(#runs==8 and not archive[runs[8].reviewKey])
	for index=1,7 do
		local detail = assert(archive[runs[index].reviewKey])
		assert(detail.league=="Covens" and detail.checkedAt==runs[index].checkedAt and #detail.feeds==8)
	end
	local newest = archive[runs[1].reviewKey]
	assert(newest.changes[1].price and newest.changes[1].sample and not restart.archivedReviews()[runs[1].reviewKey])
	print("Seven exact archived reviews persist after restarting and remain isolated to their sync profile")
end
checkExternalAdoption()

do
	local function checkInvalidCooldown()
		market.endpoint=testEndpoint.."test-overflow/"
		local fixture = assert(loadfile("Modules/LootFilterDailySync.lua"))()
		local id = fixture.createProfile("Invalid cooldown fixture")
		local live, fixed = dir.."/invalid-cooldown.filter", dir.."/invalid-cooldown-fixed.filter"
		write(live,original);write(fixed,original)
		fixture.configure(live,fixed,"Covens",{profileId=id,protectionFile=protections})
		local download, systemTime = launch.DownloadPage, os.time
		local clock, requests = now, 0
		os.time = function() return clock end
		launch.DownloadPage = function(_,_,callback)
			requests = requests+1
			callback({header="HTTP/1.1 429 Too Many Requests\r\nRetry-After: "..string.rep("9",400).."\r\n\r\n"}, "Response code: 429")
		end
		fixture.tick(clock,true,false,id)
		assert(requests==1 and fixture.busy)
		clock=now+59
		fixture.tick(clock)
		assert(requests==1 and fixture.busy)
		clock=now+60
		fixture.tick(clock)
		os.time, launch.DownloadPage = systemTime, download
		assert(requests==2 and not fixture.busy and fixture.configuration(id).providerRetryAfter==now+120)
		assert(read(live)==original and not fixture.configuration(id).lastSuccess)
		market.endpoint=testEndpoint
	end
	checkInvalidCooldown()
end

do
	local function checkTruncatedMap()
		local fixture = assert(loadfile("Modules/LootFilterDailySync.lua"))()
		local id = fixture.createProfile("Map coverage fixture")
		local live, fixed = dir.."/map-coverage.filter", dir.."/map-coverage-fixed.filter"
		local samplePath = dir.."/map-coverage.json"
		local json = require("dkjson")
		write(live,mapBase);write(fixed,mapBase);write(samplePath,assert(json.encode(mapSamples)))
		fixture.configure(live,fixed,"Covens",{profileId=id,protectionFile=samplePath,pickupPolicy={maps=5}})
		local clock, systemTime, download = now, os.time, launch.DownloadPage
		os.time = function() return clock end
		local complete = {}
		for tier=13,16 do
			complete[#complete+1] = {name=mapMarket.quoteName("Map",tier),detailsId="ordinary-"..tier,
				chaosValue=12,count=40,listingCount=400}
		end
		local truncate = false
		launch.DownloadPage = function(_, url, callback)
			local kind = url:match("&type=(%w+)$")
			local body = kind=="Map" and assert(json.encode({lines=truncate and {complete[1]} or complete}))
				or stash[kind] or commodityBody
			local date = "HTTP/1.1 200 OK\r\nDate: "..os.date("!%a, %d %b %Y %H:%M:%S GMT",clock).."\r\n\r\n"
			callback({header=date,body=body})
		end
		for day=1,2 do
			fixture.tick(clock,true,false,id)
			assert(fixture.status:find("Protected drops verified",1,true),fixture.status)
			clock=clock+86400
		end
		local good, installed = fixture.configuration(id), read(live)
		assert(installed~=mapBase and #good.priceHistory==2)
		truncate = true
		fixture.tick(clock,true,false,id)
		os.time, launch.DownloadPage = systemTime, download
		local failed = fixture.configuration(id)
		assert(fixture.status:find("Map feed has fewer than half",1,true),fixture.status)
		assert(read(live)==installed and failed.lastSuccess==good.lastSuccess and #failed.priceHistory==2)
	end
	checkTruncatedMap()
end

do
	local function checkOfflinePrices()
		local fixture = assert(loadfile("Modules/LootFilterDailySync.lua"))()
		local id = fixture.createProfile("Offline price review fixture")
		local live, fixed = dir.."/offline-live.filter", dir.."/offline-fixed.filter"
		local sampleFile = dir.."/offline-protection.json"
		write(live,original);write(fixed,original)
		write(sampleFile,'[{"BaseType":"Cord Belt","Rarity":"Magic"}]')
		fixture.configure(live,fixed,"Covens",{profileId=id,protectionFile=sampleFile})
		assert(not pcall(fixture.previewOffline,now,id))
		local revision = fixture.configuration(id).revision
		fixture.setOfflinePriceDays(id,1,revision)
		assert(not pcall(fixture.setOfflinePriceDays,id,3,revision))
		local download, systemTime = launch.DownloadPage, os.time
		os.time = function() return now end
		launch.DownloadPage = function(_,_,callback) callback({header=header,body=commodityBody}) end
		fixture.tick(now,true,false,id)
		os.time = systemTime
		local verified = fixture.configuration(id)
		assert(verified.lastSuccess==now)
		local installed = read(live)
		local retained = dir.."/LootFilterDailySync-"..id.."-OfflinePrices.cache"
		local prices = read(retained)
		local restart = assert(loadfile("Modules/LootFilterDailySync.lua"))()
		launch.DownloadPage = function() error("Offline preview made a network request") end
		local review = restart.previewOffline(now+7200,id)
		assert(review.age>=7200 and review.before==installed and review.after==installed)
		local whatIf = restart.previewOffline(now+7200,id,{targetValue=10})
		assert(whatIf.before==installed and whatIf.after==original and read(live)==installed)
		assert(not pcall(restart.previewOffline,now+86400,id))
		assert(not pcall(restart.previewOffline,now+7200))
		write(retained,prices:sub(1,-2).."!")
		local intact, failure = pcall(restart.previewOffline,now+7200,id)
		assert(not intact and failure:find("checksum mismatch",1,true),failure)
		write(retained,prices)
		write(live,installed.."\n# External edit")
		assert(not pcall(restart.previewOffline,now+7200,id))
		write(live,installed)
		launch.DownloadPage = function(_,_,callback) callback(nil,"Response code: 403") end
		restart.tick(now+7200,true,false,id)
		assert(not restart.busy and restart.configuration(id).lastSuccess==now and read(live)==installed)
		assert(restart.previewOffline(now+7200,id).after==installed)
		local open, clock = io.open, now+7300
		io.open = function(path, mode)
			if path==retained..".tmp" and mode=="wb" then return nil,"Offline cache is read-only" end
			return open(path,mode)
		end
		os.time = function() return clock end
		launch.DownloadPage = function(_,_,callback)
			local date = os.date("!%a, %d %b %Y %H:%M:%S GMT",clock)
			callback({header="HTTP/1.1 200 OK\r\nDate: "..date.."\r\n\r\n",body=commodityBody})
		end
		restart.tick(clock,true,false,id)
		io.open, os.time = open, systemTime
		assert(restart.configuration(id).lastSuccess==clock and read(live)==installed)
		assert(read(retained)==prices and not pcall(restart.previewOffline,clock,id))
		restart.setOfflinePriceDays(id,0,restart.configuration(id).revision)
		assert(not pcall(restart.previewOffline,now+7200,id))
		launch.DownloadPage = download
		print("Offline review replays only an intact matching snapshot and leaves the live filter untouched")
	end
	checkOfflinePrices()
end

do
	local fixture = assert(loadfile("Modules/LootFilterDailySync.lua"))()
	local id = fixture.createProfile("Custom protection order fixture")
	local live, fixed = dir.."/custom-order.filter", dir.."/custom-order-fixed.filter"
	local raw = [[# CUSTOM: Always show Cord Belts
Show
    BaseType == "Cord Belt" "Agate Amulet" "Amethyst Ring"
    MinimapIcon 0 Purple Star
Show
    BaseType == "Royal Plate"
    MinimapIcon 0 Red Diamond
Show
    BaseType == "Iron Ring"
    MinimapIcon 0 Yellow Diamond
# CUSTOM: Hide Wisdom and Portal Scrolls
Hide
    BaseType == "Scroll of Wisdom" "Portal Scroll"
# PoB economy: begin
Hide
    Class == "Stackable Currency"
    BaseType == "Orb of Alteration"
    StackSize <= 6
# PoB economy: end
Show
]]
	write(live,raw);write(fixed,raw)
	fixture.configure(live,fixed,"Covens",{profileId=id})
	for _, edited in ipairs({
		raw:gsub(' "Amethyst Ring"',''),
		raw:gsub(' "Portal Scroll"',''),
		'Hide\n    BaseType == "Amethyst Ring"\n' .. raw,
	}) do
		write(live,edited)
		local ok, why = pcall(fixture.previewExternalAdoption,id)
		assert(not ok and why:find("custom protection rules or their precedence",1,true),why)
	end
	write(live,"# New personal comment\n"..raw)
	assert(fixture.previewExternalAdoption(id))
end

local function checkManagedGemPrices()
	local raw = market.addManagedSection(original..'\nShow\n    Class == "Skill Gems" "Support Gems"\n',{
		{name="Arc",class="Skill Gems",scope="maps",gemLevel=20,gemQuality=20,corrupted=false},
		{name="Arc",class="Skill Gems",scope="maps",gemLevel=20,gemQuality=20,corrupted=true},
		{name="Freezing Pulse",class="Skill Gems",scope="all",gemLevel=20,gemQuality=0,corrupted=false},
		{name="Fireball",class="Skill Gems",scope="all",gemLevel=20,gemQuality=20,corrupted=false},
		{name="Added Fire Damage Support",class="Support Gems",scope="all",gemLevel=20,gemQuality=20,corrupted=false},
	})
	local categories, requests = market.feedCategories(raw)
	assert(#categories==9 and categories[9]=="SkillGem")
	assert(#market.feedCategories(raw:gsub("Imbued False","Imbued True"))==8)
	assert(market.maxFeedBytes("SkillGem")==12*1024*1024)
	assert(not pcall(market.validateManagedRules,{{name="Arc",class="Skill Gems",scope="maps",gemLevel=20,gemQuality=20}}))
	local gems = require("Modules.LootFilterGemMarket")
	local overview = [[{"lines":[
		{"name":"Arc","detailsId":"arc-exact","gemLevel":20,"gemQuality":20,"corrupted":false,"chaosValue":50,"count":100,"listingCount":100},
		{"name":"Arc","detailsId":"arc-corrupt-19","gemLevel":20,"gemQuality":19,"corrupted":true,"chaosValue":500,"count":100,"listingCount":100},
		{"name":"Freezing Pulse","detailsId":"thin-pulse","gemLevel":20,"gemQuality":0,"corrupted":false,"chaosValue":500,"count":5,"listingCount":100},
		{"name":"Fireball","detailsId":"fireball-one","gemLevel":20,"gemQuality":20,"corrupted":false,"chaosValue":500,"count":100,"listingCount":100},
		{"name":"Fireball","detailsId":"fireball-two","gemLevel":20,"gemQuality":20,"corrupted":false,"chaosValue":500,"count":100,"listingCount":100},
		{"name":"Added Fire Damage Support","detailsId":"support","gemLevel":20,"gemQuality":20,"corrupted":false,"chaosValue":9,"count":100,"listingCount":100}
	]}]]
	local actual = market.quotes(overview,"SkillGem",requests)
	assert(actual[gems.key("Arc",20,20,false)].price==50)
	assert(not actual[gems.key("Arc",20,19,true)])
	local rememberedGems=market.remember(actual,{},"gem identity day",now)
	assert(rememberedGems[gems.key("Arc",20,20,false)].providerId=="arc-exact")
	assert(actual[gems.key("Fireball",20,20,false)]==false)
	local reused = overview:gsub("arc%-corrupt%-19","arc-exact")
	assert(market.quotes(reused,"SkillGem",requests)[gems.key("Arc",20,20,false)]==false)
	assert(not pcall(market.quotes,overview.."broken","SkillGem",requests))
	do
		local json = require("dkjson")
		local function row(variant,quality,corrupted)
			return {name="Arc",detailsId="arc-canonical",gemLevel=20,gemQuality=quality,corrupted=corrupted,
				variant=variant,chaosValue=50,count=40,listingCount=40}
		end
		local function quote(value)
			local key,quality,corrupted = gems.variant(value)
			return gems.quotes(assert(json.encode({lines={value}})),{[key or gems.key("Arc",20,0,false)]=true})[key or gems.key("Arc",20,0,false)],quality,corrupted
		end
		for _, value in ipairs({row("20",nil,nil),row("20c",nil,true),row("20/20",20,nil),row("20/20c",20,true)}) do
			assert(quote(value))
			local shown=browser.rows(assert(json.encode({lines={value}})),{id="SkillGem"},"=Arc",{name="Arc",level=20,quality=value.gemQuality or 0})[1]
			assert(shown and shown.gemQuality==(value.gemQuality or 0) and shown.corrupted==(value.corrupted or false) and not shown.incomplete)
		end
		for _, value in ipairs({row(nil,nil,nil),row("20/0",0,false),row("020",0,false),row("20C",0,true),row("20/20",0,false),row("19",0,false)}) do
			assert(not quote(value))
		end
		for _, field in ipairs({"Imbued","imbued","TransfiguredGem","transfiguredGem","transfigured"}) do
			local value=row("20",nil,nil);value[field]=true;assert(quote(value)==false)
		end
		for _,kind in ipairs({"transfigured","imbued"}) do
			local value=row("20",nil,nil);value.metadata={gemKind=kind};assert(quote(value)==false)
		end
		-- Read-only build comparisons include named transfigured gems, while
		-- their complete typed/canonical tuples remain excluded from managed rules.
		for _, labeled in ipairs({false,true}) do
			local value=row(labeled and "20" or nil,0,false)
			if labeled then value.gemQuality,value.corrupted=nil,nil end
			value.name="Arc of Surging";value.metadata={gemKind="transfigured"};value.TransfiguredGem=true
			local target={name=value.name,level=20,quality=0}
			local function compared() return browser.rows(assert(json.encode({lines={value}})),{id="SkillGem"},"",target) end
			local shown=compared()[1]
			assert(shown and shown.gemQuality==0 and shown.corrupted==false and not shown.incomplete)
			local key,_,_,regular,validTuple=gems.variant(value)
			assert(validTuple and not regular and gems.quotes(assert(json.encode({lines={value}})),{[key]=true})[key]==false)
			value.variant="20/0"
			assert(not pcall(compared))
			assert(browser.rows(assert(json.encode({lines={value}})),{id="SkillGem"},"=Arc of Surging")[1].incomplete)
		end
		local invalid=row("20",nil,nil);invalid.detailsId="bad/id";assert(quote(invalid)==false)
		local good,bad=row("20",nil,nil),row("20/0",0,false)
		local key=gems.key("Arc",20,0,false)
		for _, lines in ipairs({{good,bad},{bad,good}}) do
			assert(gems.quotes(assert(json.encode({lines=lines})),{[key]=true})[key]==false)
		end
	end
	local setup = assert(loadfile("Modules/LootFilterDailySync.lua"))()
	local id = setup.createProfile("Managed gem prices")
	local target, baseline = dir.."/gem-target.filter",dir.."/gem-baseline.filter"
	write(target,raw); write(baseline,raw)
	setup.configure(target,baseline,"Covens",{profileId=id,hour=0,targetValue=20,protectionFile=protections})
	setup.setOfflinePriceDays(id,1,setup.configuration(id).revision)
	local clock, requestsSent, denied = systemTime(), 0, false
	os.time = function() return clock end
	launch.DownloadPage = function(_,url,callback,params)
		requestsSent=requestsSent+1
		local headers="HTTP/1.1 200 OK\r\nDate: "..os.date("!%a, %d %b %Y %H:%M:%S GMT",clock).."\r\n\r\n"
		if url:find("type=SkillGem",1,true) then
			assert(url:find("stash/current/item/overview",1,true) and params.maxBytes==12*1024*1024)
			if denied then callback(nil,"Response code: 403") else callback({header=headers,body=overview}) end
		else callback({header=headers,body=commodityBody}) end
	end
	setup.tick(clock,true,false,id)
	local state = setup.configuration(id)
	assert(state.review and requestsSent==9 and state.review.protectedChecks==1,setup.status)
	local decision
	for _, change in ipairs(state.review.changes) do if change.gemLevel then decision=change end end
	assert(decision and decision.name=="Arc" and decision.gemLevel==20 and decision.gemQuality==20 and decision.corrupted==false)
	assert(decision.sample.before=="Hide" and decision.sample.action=="Show" and decision.priceId=="arc-exact")
	local function testItem(candidate,name,quality,corrupted,imbued,transfigured,area)
		local parser = require("Modules.LootFilterParser")
		return parser.simulate(parser.parse(candidate),{
			BaseType=name,Class="Skill Gems",GemLevel=20,Quality=quality,Corrupted=corrupted,
			Imbued=imbued,TransfiguredGem=transfigured,AreaLevel=area,
		}).action
	end
	local targetOutput = read(target)
	assert(testItem(targetOutput,"Arc",20,false,false,false,83)=="Show")
	assert(testItem(targetOutput,"Arc",20,true,false,false,83)=="Hide")
	assert(testItem(targetOutput,"Fireball",20,false,false,false,83)=="Hide")
	assert(testItem(targetOutput,"Freezing Pulse",0,false,false,false,83)=="Hide")
	assert(testItem(raw,"Arc",20,false,true,false,83)=="Show" and testItem(raw,"Arc",20,false,false,"Arc",83)=="Show")
	local replay = setup.previewOffline(clock,id,{targetValue=1000})
	assert(replay.before==targetOutput and replay.after==raw and requestsSent==9)
	denied, clock = true, clock+20
	setup.tick(clock,true,false,id)
	assert(requestsSent==18 and read(target)==targetOutput and setup.configuration(id).lastFailure.message:find("403",1,true))
	os.time=systemTime
end
checkManagedGemPrices()
print("Exact managed gems preserve other variants, replay offline, and retain verified output when the feed is denied")

local function checkSharedProviderHold()
	local now = os.time()
	local endpoint = testEndpoint.."test-shared/"
	market.endpoint = endpoint
	local first = assert(loadfile("Modules/LootFilterDailySync.lua"))()
	local second = assert(loadfile("Modules/LootFilterDailySync.lua"))()
	local suffix = require("sha1")(endpoint)
	local statePath = dir.."/LootFilterProviderCooldown-"..suffix..".json"
	local function note(service,delay,at)
		return service.noteProviderLimit({header="HTTP/1.1 429 Too Many Requests\r\nRetry-After: "..delay.."\r\n\r\n"},429,at)
	end
	local id = second.createProfile("Shared provider fixture")
	local live, fixed = dir.."/shared-provider.filter",dir.."/shared-provider-fixed.filter"
	write(live,original); write(fixed,original)
	second.configure(live,fixed,"Covens",{profileId=id,hour=0,protectionFile=protections})
	second.setBackground(true,second.configuration(id).revision,id)
	assert(second.isDue(second.configuration(id),now))
	assert(note(first,120,now)==120)
	assert(second.providerWait(now+10)==110)
	local diagnostic = second.publicStatus(now+10,id)
	assert(diagnostic.providerWaitSeconds==110 and diagnostic.priceSource=="shared_cache")
	assert(not pcall(second.preview,target,baseline,"Covens",options,function() end))
	assert(#second.dueProfiles(now+10,true)==0)
	local calls, download = 0,launch.DownloadPage
	launch.DownloadPage = function() calls=calls+1 end
	second.tick(now+10,true,true,id)
	launch.DownloadPage = download
	assert(calls==0 and read(live)==original and not second.configuration(id).lastFailure)
	assert(note(second,30,now+10)==110)
	assert(first.providerWait(now+119)==1 and second.providerWait(now+120)==0)
	market.endpoint=testEndpoint.."test-alternate-provider/"
	assert(second.providerWait(now+10)==0)
	assert(note(second,15,now+10)==15)
	market.endpoint=endpoint
	assert(first.providerWait(now+10)==110 and second.providerWait(now+10)==110)

	-- A corrupt record can be replaced, and its contents cannot manufacture a hold.
	write(statePath,string.rep("x",513))
	local restarted = assert(loadfile("Modules/LootFilterDailySync.lua"))()
	assert(restarted.providerWait(now)==0)
	assert(note(restarted,45,now)==45)
	assert(assert(loadfile("Modules/LootFilterDailySync.lua"))().providerWait(now)==45)
	market.endpoint=testEndpoint
end
checkSharedProviderHold()
print("Provider retry deadlines survive independent instances, preserve the longest wait, and isolate endpoints")


local function checkMarketSourceBinding()
	local service = assert(loadfile("Modules/LootFilterDailySync.lua"))()
	local json, sha = require("dkjson"), require("sha1")
	local endpoint = market.endpoint
	local alternate = endpoint.."test-source-binding/"
	local id = service.createProfile("Price source binding")
	local live, fixed = dir.."/source-bound.filter",dir.."/source-bound-fixed.filter"
	local settings = dir.."/LootFilterDailySync-"..id..".json"
	local options = {profileId=id,hour=0,protectionFile=protections}
	write(live,original); write(fixed,original)
	service.configure(live,fixed,"Covens",options)
	assert(service.configuration(id).marketSourceHash==sha(endpoint))
	local requests, held = 0,nil
	local function reply(_,url,callback)
		requests=requests+1
		callback({header=header,body=commodityBody})
	end
	launch.DownloadPage = reply
	service.tick(now,true,false,id)
	local verified = read(live)
	local historySource=service.configuration(id)
	historySource.priceHistory={{day="other-source",time=now-86400,values={["Currency:alt"]=100}}}
	write(settings,assert(json.encode(historySource)))
	assert(service.configuration(id).lastSuccess and #service.configuration(id).priceHistory==1)
	service.setBackground(true,service.configuration(id).revision,id)
	market.endpoint=alternate
	local task = require("Modules.LootFilterBackgroundTask")
	local launchTask, register = LaunchSubScript, launch.RegisterSubScript
	local taskStarts = 0
	LaunchSubScript=function() taskStarts=taskStarts+1; return 12345 end
	launch.RegisterSubScript=function(_,_,callback) callback(true) end
	local enabled, reason=pcall(task.change,true,function() end,id)
	assert(not enabled and reason:find("price source changed",1,true) and taskStarts==0 and not task.busy)
	local disabled
	task.change(false,function(ok) disabled=ok end,id)
	assert(disabled and not service.configuration(id).backgroundEnabled)
	LaunchSubScript, launch.RegisterSubScript=launchTask, register
	requests=0
	service.tick(now+1,true,false,id)
	assert(requests==0 and read(live)==verified and service.configuration(id).lastFailure.message:find("price source changed",1,true))
	local proposed
	service.preview(live,fixed,"Covens",options,function(_,after) proposed=after end)
	assert(proposed==verified and requests==8 and read(live)==verified)
	service.configure(live,fixed,"Covens",options)
	assert(service.configuration(id).marketSourceHash==sha(alternate) and not service.configuration(id).priceHistory)
	service.tick(now+2,true,false,id)
	assert(service.configuration(id).lastSuccess and #service.configuration(id).priceHistory==1)
	service.configure(live,fixed,"Covens",options)
	assert(#service.configuration(id).priceHistory==1)

	-- An in-flight request cannot mix sources or publish after the source changes.
	requests=0
	launch.DownloadPage=function(_,url,callback) requests=requests+1; held=callback end
	local before = read(live)
	service.tick(now+3,true,false,id)
	assert(held and service.busy and requests==1)
	market.endpoint=endpoint
	held({header="HTTP/1.1 429 Too Many Requests\r\nRetry-After: 120\r\n\r\n"},"Response code: 429")
	assert(service.providerWait(now)==0)
	assert(not service.busy and requests==1 and read(live)==before and service.status:find("price source changed",1,true))

	-- Older profiles remain usable, then bind only verified prices from this source.
	local legacy=service.configuration(id)
	legacy.marketSourceHash=nil
	legacy.priceHistory={{day="old-source",time=now-86400,values={["Currency:alt"]=100}}}
	write(settings,assert(json.encode(legacy)))
	launch.DownloadPage=reply
	service.tick(now+4,true,false,id)
	local migrated=service.configuration(id)
	assert(migrated.lastSuccess==now+4 and migrated.marketSourceHash==sha(endpoint) and #migrated.priceHistory==1)
	assert(migrated.priceHistory[1].day~="old-source")
	legacy=service.configuration(id)
	legacy.marketSourceHash=nil
	write(settings,assert(json.encode(legacy)))
	service.configure(live,fixed,"Covens",options)
	assert(service.configuration(id).marketSourceHash==sha(endpoint) and not service.configuration(id).priceHistory)
end
checkMarketSourceBinding()
print("Daily profiles bind verified sources, reset changed or legacy histories, and stop mismatched asynchronous requests")


local function checkManagedExchangeSelections()
	local core={}
	for _,category in ipairs(market.categories) do core[category]=true end
	assert(#market.exchangeCategories==18 and #market.categories==8 and market.maxFeedCount==23)
	assert(market.evidencePriceId("harbinger-scarab_1.0")=="harbinger-scarab_1.0")
	for _,id in ipairs({"",string.rep("a",201),"internal\0composite","C:/private/id","quote name"}) do
		assert(not market.evidencePriceId(id))
	end
	assert(not market.evidencePriceId(false))
	for _,category in ipairs(market.exchangeCategories) do
		local entry={name="Fixture "..category,class="Stackable Currency",scope="maps",cutoff=6,exchangeCategory=category}
		assert(market.validateManagedRules({entry})[1].exchangeCategory==category)
		local raw=market.addManagedSection(original,{entry})
		local feeds=market.feedCategories(raw)
		assert(#feeds==(core[category] and 8 or 9))
		local occurrences=0
		for _,feed in ipairs(feeds) do if feed==category then occurrences=occurrences+1 end end
		assert(occurrences==1 and raw:find("# PoB economy: exchange "..category.."\nHide",1,true))
	end
	for _,invalid in ipairs({
		{name="Fixture",class="Stackable Currency",scope="all",cutoff=6,exchangeCategory="Invented"},
		{name="Fixture",class="Divination Cards",scope="all",exchangeCategory="DivinationCard"},
		{name="Arc",class="Skill Gems",scope="all",gemLevel=20,gemQuality=20,corrupted=false,exchangeCategory="Currency"},
		{name="Harbinger Scarab",class="Stackable Currency",scope="all",cutoff=6,exchangeCategory="Scarab"},
		{name="Allflame Ember of Abyss",class="Embers of the Allflame",scope="all",cutoff=1,exchangeCategory="AllflameEmber"},
		{name="Allflame Ember of Abyss",class="Embers of the Allflame",scope="all"},
	}) do assert(not pcall(market.validateManagedRules,{invalid})) end
	local entry={name="Harbinger Scarab",class="Map Fragments",scope="all",cutoff=6,exchangeCategory="Scarab"}
	local raw=market.addManagedSection(original,{entry})
	local quotes={}
	local function merge(category,price,name,id)
		market.merge(quotes,{[name or "Harbinger Scarab"]={id=id or "scarab",price=price,volume=1000,source=category}},category)
	end
	merge("Currency",0.01)
	merge("Scarab",0.3)
	assert(quotes["Harbinger Scarab"].source=="Currency")
	local after,changes=market.review(raw,quotes,1)
	assert(#changes==1 and changes[1].source=="Scarab" and changes[1].cutoff==3 and changes[1].priceId=="scarab")
	assert(after:find("# PoB economy: exchange Scarab\nHide",1,true) and #market.feedCategories(after)==9)
	local second=market.review(after,quotes,1)
	assert(second==after)
	local remembered,snapshots=market.remember(quotes,{},"source day",now)
	assert(snapshots[1].values["Currency:scarab"]==0.01 and snapshots[1].values["Scarab:scarab"]==0.3)
	assert(market.review(raw,remembered,1)==after)
	local missing,missingChanges,missingSkips=market.review(raw,{["Harbinger Scarab"]={id="wrong",price=100,volume=1000,source="Currency"}},1)
	assert(missing==raw and #missingChanges==0 and missingSkips[1].source=="Scarab" and not missingSkips[1].priceId)
	local _,_,ambiguousSkips=market.review(raw,{["\0Scarab:Harbinger Scarab"]=false},1)
	assert(ambiguousSkips[1].source=="Scarab" and ambiguousSkips[1].reason=="Ambiguous price mapping" and not ambiguousSkips[1].priceId)
	local _,_,unchanged=market.review(raw,{["\0Scarab:Harbinger Scarab"]={id="scarab-stable",price=0.01,volume=1000,source="Scarab"}},1)
	assert(unchanged[1].source=="Scarab" and unchanged[1].priceId=="scarab-stable")
	quotes={};merge("Scarab",2)
	local removed,removedChanges=market.review(raw,quotes,1)
	assert(#removedChanges==1 and not removed:find("# PoB economy: exchange Scarab",1,true) and #market.feedCategories(removed)==8)
	assert(market.review(removed,quotes,1)==removed)
	for _,broken in ipairs({
		raw:gsub("exchange Scarab","exchange Invented"),
		raw:gsub("exchange Scarab\nHide","exchange Scarab\n\nHide"),
		raw:gsub("exchange Scarab\nHide","exchange Scarab\n# Different rule\nHide"),
		raw:gsub("exchange Scarab\nHide","exchange Scarab\nShow"),
	}) do
		assert(not pcall(market.feedCategories,broken))
		assert(not pcall(market.review,broken,quotes,1))
	end
	local allflame=market.addManagedSection(original,{{name="Allflame Ember of Abyss",class="Embers of the Allflame",
		scope="maps",exchangeCategory="AllflameEmber"}})
	local emberRule=require("Modules.LootFilterParser").parse(allflame).rules[2]
	assert(emberRule.conditions[1].values[1]=="Embers of the Allflame")
	for _,condition in ipairs(emberRule.conditions) do assert(condition.keyword~="StackSize") end
	quotes={};merge("AllflameEmber",0.1,"Allflame Ember of Abyss","allflame")
	assert(market.review(allflame,quotes,1,{caps={["Allflame Ember of Abyss"]=10}})==allflame)
	quotes={};merge("AllflameEmber",3,"Allflame Ember of Abyss","allflame")
	local shown,allflameChanges=market.review(allflame,quotes,1,{highlightChaos=2,strongHighlightChaos=4})
	assert(#allflameChanges==1 and allflameChanges[1].cutoff==0 and not allflameChanges[1].highlights)
	assert(not shown:find("# PoB economy: exchange AllflameEmber",1,true) and #market.feedCategories(shown)==8)

	local allRules={}
	for _,category in ipairs(market.exchangeCategories) do
		allRules[#allRules+1]={name="Fixture "..category,class="Stackable Currency",scope="all",cutoff=6,exchangeCategory=category}
	end
	allRules[#allRules+1]={name="Fixture Card",class="Divination Cards",scope="all"}
	for _,category in ipairs(require("Modules.LootFilterMapMarket").feeds) do
		allRules[#allRules+1]={class="Maps",tier=16,mapType=category}
	end
	allRules[#allRules+1]={name="Arc",class="Skill Gems",scope="all",gemLevel=20,gemQuality=20,corrupted=false}
	local allFeeds=market.feedCategories(market.addManagedSection(original,allRules))
	assert(#allFeeds==23)
	local bodies,feeds={},{}
	for index,category in ipairs(allFeeds) do bodies[index]=category;feeds[index]={category=category,age=0} end
	local state={league="Covens",baselineHash="fixed",current="verified",lastSuccess=now,offlinePriceDays=1}
	local offline=require("Modules.LootFilterOfflinePrices")
	local packed=offline.encode(state,bodies,feeds,now,now,os.date("%Y-%m-%d",now))
	local decoded=offline.decode(packed,state,allFeeds,now)
	assert(#decoded==23 and decoded[23]==allFeeds[23])
end
checkManagedExchangeSelections()
print("Explicit exchange selections bind exact adjacent rules, isolate category prices, preserve rewrite metadata, and support Allflame embers")


local function checkManagedExchangeDailySync()
	local fixture=assert(loadfile("Modules/LootFilterDailySync.lua"))()
	local id=fixture.createProfile("Optional exchange refresh")
	local live,fixed=dir.."/selected-exchange.filter",dir.."/selected-exchange-fixed.filter"
	local raw=market.addManagedSection(original,{
		{name="Harbinger Scarab",class="Map Fragments",scope="maps",cutoff=6,exchangeCategory="Scarab"},
		{name="Allflame Ember of Abyss",class="Embers of the Allflame",scope="maps",exchangeCategory="AllflameEmber"},
	})
	write(live,raw);write(fixed,raw)
	fixture.configure(live,fixed,"Covens",{profileId=id,hour=0,protectionFile=protections})
	fixture.setOfflinePriceDays(id,1,fixture.configuration(id).revision)
	local sent,denied={},false
	local savedDownload=launch.DownloadPage
	launch.DownloadPage=function(_,url,callback,params)
		assert(params.followRedirects==false)
		local category=assert(url:match("type=([%w]+)$"))
		sent[#sent+1]=category
		local body=commodityBody
		if category=="Scarab" then
			if denied then callback(nil,"Response code: 403");return end
			body='{"core":{"primary":"chaos"},"items":[{"id":"harbinger","name":"Harbinger Scarab"}],"lines":[{"id":"harbinger","primaryValue":0.3,"volumePrimaryValue":1000}]}'
		elseif category=="AllflameEmber" then
			body='{"core":{"primary":"chaos"},"items":[{"id":"abyss","name":"Allflame Ember of Abyss"}],"lines":[{"id":"abyss","primaryValue":3,"volumePrimaryValue":1000}]}'
		end
		callback({header=header,body=body})
	end
	fixture.tick(now,true,false,id)
	local state=fixture.configuration(id)
	assert(#sent==10 and state.lastSuccess==now and state.review.protectedChecks==1,fixture.status)
	local diff=fixture.publicDiff(now,id)
	local identities={}
	for _,change in ipairs(diff.changes) do identities[change.source]=change.priceId end
	assert(identities.Scarab=="harbinger" and identities.AllflameEmber=="abyss" and identities.Currency=="alt")
	local output=read(live)
	assert(output~=raw and output:find("# PoB economy: exchange Scarab",1,true))
	assert(not output:find("# PoB economy: exchange AllflameEmber",1,true))
	local replay=fixture.previewOffline(os.time(),id)
	assert(replay.after==output and replay.before==output and #sent==10)
	denied=true
	fixture.tick(now+1,true,false,id)
	assert(read(live)==output and fixture.configuration(id).lastSuccess==now and fixture.configuration(id).lastFailure.message:find("403",1,true))
	fixture.rollback(id)
	assert(read(live)==raw and fixture.configuration(id).paused)
	launch.DownloadPage=savedDownload
end
checkManagedExchangeDailySync()
print("Optional Scarab and Allflame prices use verified daily sync, offline replay, safe failure retention and rollback")


local function checkStructuredFeedFailures()
	local realTime,realDownload,endpoint=os.time,launch.DownloadPage,market.endpoint
	local json=require("dkjson")
	local cases={
		{mode="empty",category="Currency",reason="empty_response",status=200},
		{mode="empty",category="Scarab",reason="empty_response",status=200},
		{mode="invalid",category="Scarab",reason="invalid_response",status=200},
		{mode="partial",category="Scarab",reason="invalid_response",status=200},
		{mode="stale",category="Scarab",reason="stale",status=200},
		{mode="denied",category="Scarab",reason="access_denied",status=403},
		{mode="limited",category="Scarab",reason="rate_limited",status=429},
		{mode="unavailable",category="Scarab",reason="provider_unavailable",status=503},
		{mode="redirect",category="Scarab",reason="redirect",status=302},
		{mode="transport",category="Scarab",reason="transport_error"},
		{mode="retry",category="Scarab",reason="provider_unavailable",status=500},
		{mode="relay",detail="stale",category="Scarab",reason="stale",status=502},
		{mode="relay",detail="invalid_response",category="Scarab",reason="invalid_response",status=502},
		{mode="relay",detail="oversized",category="Scarab",reason="invalid_response",status=502},
		{mode="relay",detail="C:/private/filter",category="Scarab",reason="provider_unavailable",status=502},
		{mode="relay",detail="stale\r\nX-PoB-Market-Failure: oversized",category="Scarab",reason="provider_unavailable",status=502},
		{mode="relay",detail="stale",category="Scarab",reason="provider_unavailable",status=503},
		{mode="relay",interim=true,category="Scarab",reason="provider_unavailable",status=502},
		{mode="relay",detail="stale",direct=true,category="Scarab",reason="provider_unavailable",status=502},
		{mode="timeout",category="Scarab",reason="timeout"},
		{mode="uncached",category="Scarab",reason="invalid_response",status=304},
		{mode="oversized",category="Scarab",reason="invalid_response"},
		{mode="cooldown",category="Oil",reason="cooldown"},
	}
	local profile=assert(loadfile("Modules/LootFilterDailySync.lua"))().createProfile("Structured failure evidence")
	for index,case in ipairs(cases) do
		market.endpoint=case.direct and market.resolveEndpoint(nil) or endpoint.."test-feed-failure-"..index.."/"
		local fixture=assert(loadfile("Modules/LootFilterDailySync.lua"))()
		local id=profile
		local live,fixed=dir.."/failure-"..index..".filter",dir.."/failure-fixed-"..index..".filter"
		local raw=market.addManagedSection(original,{{name="Harbinger Scarab",class="Map Fragments",scope="maps",cutoff=6,exchangeCategory="Scarab"}})
		write(live,raw);write(fixed,raw)
		fixture.configure(live,fixed,"Covens",{profileId=id,hour=0,protectionFile=protections})
		local clock,fail,attempts=realTime()+index*10000,false,0
		os.time=function() return clock end
		launch.DownloadPage=function(_,url,callback,params)
			assert(params.followRedirects==false)
			local date="HTTP/1.1 200 OK\r\nDate: "..os.date("!%a, %d %b %Y %H:%M:%S GMT",clock).."\r\n\r\n"
			if url:match("/leagues$") then callback({header=date,body='[{"id":"Covens","name":"Covens"}]'});return end
			local category=url:match("type=([%w]+)$")
			if fail and case.mode=="cooldown" and category=="Currency" then
				fixture.noteProviderLimit({header="HTTP/1.1 429 Too Many Requests\r\nRetry-After: 3600\r\n\r\n"},429,clock)
			elseif fail and category==case.category then
				attempts=attempts+1
				if case.mode=="empty" then callback({header=date,body='{"core":{"primary":"chaos"},"items":[],"lines":[]}'});return
				elseif case.mode=="invalid" then callback({header=date,body='{"core":'});return
				elseif case.mode=="partial" then
					callback({header=date,body='{"core":{"primary":"chaos"},"items":[{"id":"scarab","name":"Harbinger Scarab"}],"lines":[{"id":"scarab","primaryValue":0.05,"volumePrimaryValue":1000},null,{"id":"scarab","primaryValue":0.4,"volumePrimaryValue":1000}]}'})
					return
				elseif case.mode=="stale" then callback({header=date:gsub("\r\n\r\n","\r\nAge: 4001\r\n\r\n"),body=commodityBody});return
				elseif case.mode=="timeout" then return
				elseif case.mode=="oversized" then callback(nil,"Response exceeds the size limit");return
				elseif case.mode=="transport" then callback(nil,"Private transport https://private.example.test C:/private/filter");return
				else
					local status=case.status
					local hold=(status==429 or status==503) and "Retry-After: 120\r\n" or ""
					local evidence=case.detail and "X-PoB-Market-Failure: "..case.detail.."\r\n" or ""
					local interim=case.interim and "HTTP/1.1 200 Connection established\r\nX-PoB-Market-Failure: stale\r\n\r\n" or ""
					callback({header=interim.."HTTP/1.1 "..status.." Error\r\n"..hold..evidence.."\r\n",body="private provider detail"},"Response code: "..status);return
				end
			end
			local body=category=="Scarab" and '{"core":{"primary":"chaos"},"items":[{"id":"scarab","name":"Harbinger Scarab"}],"lines":[{"id":"scarab","primaryValue":0.3,"volumePrimaryValue":1000}]}' or commodityBody
			callback({header=date,body=body})
		end
		fixture.tick(clock,true,false,id)
		local verified=fixture.configuration(id)
		assert(verified.lastSuccess==clock,fixture.status)
		local output,review=read(live),assert(json.encode(verified.review))
		fail,clock=true,clock+2
		fixture.tick(clock,true,false,id)
		if fixture.busy then clock=clock+(case.mode=="timeout" and 301 or 5);fixture.tick(clock) end
		assert(not fixture.busy,case.mode)
		local failed=fixture.configuration(id)
		assert(failed.lastSuccess==verified.lastSuccess and read(live)==output and json.encode(failed.review)==review,case.mode)
		local feed=assert(failed.lastFailure.failedFeed,case.mode)
		assert(feed.category==case.category and feed.reason==case.reason and feed.httpStatus==case.status,case.mode.." "..json.encode(feed))
		if case.mode=="transport" or case.mode=="retry" then assert(attempts==2) end
		local public=fixture.publicStatus(clock+1,id)
		assert(public.state=="error" and json.encode(public.failedFeed)==json.encode(feed))
		assert(not json.encode(public):find("private",1,true))
		local restarted=assert(loadfile("Modules/LootFilterDailySync.lua"))()
		assert(restarted.publicStatus(clock+2,id).failedFeed.reason==case.reason)
		fixture.pause(true,id)
		local paused=fixture.publicStatus(clock+3,id)
		assert(paused.state=="paused" and paused.failedFeed.reason==case.reason and paused.lastFailure==failed.lastFailure.checkedAt)
		fixture.disable(id)
		local disabled=fixture.publicStatus(clock+4,id)
		assert(disabled.state=="disabled" and disabled.failedFeed.reason==case.reason and disabled.lastFailure==failed.lastFailure.checkedAt)
	end
	os.time,launch.DownloadPage,market.endpoint=realTime,realDownload,endpoint
	local clean=sync.failedFeedEvidence({category="Currency",reason="access_denied",httpStatus=403,raw="C:/private"})
	assert(clean.category=="Currency" and clean.httpStatus==403 and not clean.raw)
	assert(not sync.failedFeedEvidence({category="C:/private",reason="timeout"}))
	assert(not sync.failedFeedEvidence({category="Currency",reason="private detail"}))
	assert(not sync.failedFeedEvidence("legacy message"))
	assert(not sync.failedFeedEvidence({category="Currency",reason="timeout",httpStatus=403.5}).httpStatus)
end
checkStructuredFeedFailures()
print("Failed feed evidence survives restart, covers retries and timeouts, preserves verified output, and excludes private errors")

local function checkMarketCollectionContracts()
	local browse = require("Modules.LootFilterMarketBrowse")
	local name = "Added Cold Damage Support"
	local gem = '{"detailsId":"added-cold-damage-support","name":"'..name..'","gemLevel":20,"gemQuality":20,"corrupted":false,"chaosValue":15,"count":40,"listingCount":35,"variant":null,"baseType":null}'
	local map = '{"name":"Map (Tier 16)","detailsId":"tier-16-map","mapTier":16,"chaosValue":10,"count":40,"listingCount":35,"baseType":null}'
	local league = '{"id":"Covens","name":"Covens of Umbra"}'
	local commodity = '{"id":"alt","primaryValue":0.2,"volumePrimaryValue":400}'
	local item = '{"id":"alt","name":"Orb of Alteration","icon":null}'
	local stash = {id="SkillGem",feed="stash"}
	local function overview(lines) return '{"lines":'..lines..'}' end
	local function exchange(items,lines) return '{"core":{"primary":"chaos"},"items":'..items..',"lines":'..lines..'}' end
	local function verify(parser,row)
		parser("["..row.."]")
		for _, bad in ipairs({"[null,"..row.."]","["..row..",null,"..row.."]","["..row..",null]","["..row..",[]]","["..row..",false]","{\"1\":"..row.."}"}) do
			assert(not pcall(parser,bad),bad)
		end
	end
	verify(function(list) return market.quotes(exchange(list,"["..commodity.."]"),"Currency") end,item)
	verify(function(list) return market.quotes(exchange("["..item.."]",list),"Currency") end,commodity)
	verify(function(list) return market.quotes(overview(list),"Map") end,map)
	local gemKey = require("Modules.LootFilterGemMarket").key(name,20,20,false)
	verify(function(list) return market.quotes(overview(list),"SkillGem",{[gemKey]=true}) end,gem)
	local valid = market.quotes(overview("["..gem.."]"),"SkillGem",{[gemKey]=true})
	assert(valid[gemKey].price==15)
	verify(function(list) return browse.rows(overview(list),stash,"",nil) end,gem)
	assert(not pcall(browse.rows,overview("["..gem.."]").."{}",stash,""))
	verify(market.tradeLeagues,league)
end
checkMarketCollectionContracts()
print("Market decoders reject malformed rows in exchange, map, gem, stash and league collections")


local function checkExactManagedQuoteInspection()
	local browse=require("Modules.LootFilterMarketBrowse")
	local json=require("dkjson")
	local function exchange(name,price,volume)
		return assert(json.encode({core={primary="chaos"},items={{id="exact-id",name=name}},
			lines={{id="exact-id",primaryValue=price or 3,volumePrimaryValue=volume or 1000}}}))
	end
	local scarab=assert(browse.managedTarget({name="Harbinger Scarab",class="Map Fragments",scope="maps",cutoff=6,exchangeCategory="Scarab"}))
	assert(scarab.managed and scarab.category=="Scarab" and scarab.name=="Harbinger Scarab")
	local quote=browse.managedQuote(exchange("Harbinger Scarab"),scarab)
	assert(quote.state=="quoted" and quote.row.identity=="exact-id" and quote.row.source=="Scarab")
	assert(browse.managedQuote(exchange("harbinger scarab"),scarab).state=="missing")
	assert(browse.managedQuote(exchange("Harbinger Scarab",3,1),scarab).state=="thin")
	assert(browse.managedQuote('{"core":{"primary":"chaos"},"items":[],"lines":[]}',scarab).state=="empty")
	local ambiguous='{"core":{"primary":"chaos"},"items":[{"id":"a","name":"Harbinger Scarab"},{"id":"b","name":"Harbinger Scarab"}],"lines":[{"id":"a","primaryValue":3,"volumePrimaryValue":1000},{"id":"b","primaryValue":5,"volumePrimaryValue":1000}]}'
	assert(browse.managedQuote(ambiguous,scarab).state=="ambiguous")
	assert(not browse.managedTarget({name="Orb of Alteration",class="Stackable Currency",scope="maps",cutoff=6}))
	local card=browse.managedTarget({name="The Doctor",class="Divination Cards",scope="maps"})
	assert(card.category=="DivinationCard" and browse.managedQuote(exchange("The Doctor",3,499),card).state=="thin")
	local ember=browse.managedTarget({name="Allflame Ember of Abyss",class="Embers of the Allflame",scope="maps",exchangeCategory="AllflameEmber"})
	assert(ember.category=="AllflameEmber" and browse.managedQuote(exchange("Allflame Ember of Abyss"),ember).state=="quoted")
	local map=browse.managedTarget({class="Maps",tier=16,mapType="Map"})
	local mapRow={name="Map (Tier 16)",detailsId="tier-16-exact",chaosValue=3,count=30,listingCount=30}
	quote=browse.managedQuote(assert(json.encode({lines={mapRow}})),map)
	assert(quote.state=="quoted" and quote.row.mapTier==16 and quote.row.identity=="tier-16-exact")
	mapRow.name="Map (Tier 15)"
	assert(browse.managedQuote(assert(json.encode({lines={mapRow}})),map).state=="missing")
	assert(browse.managedQuote('{"lines":[]}',map).state=="empty")
	local blighted=browse.managedTarget({class="Maps",tier=16,mapType="BlightedMap"})
	assert(blighted.category=="BlightedMap" and browse.managedQuote(assert(json.encode({lines={mapRow}})),blighted).state=="missing")
	local gem=browse.managedTarget({name="Arc",class="Skill Gems",scope="maps",gemLevel=20,gemQuality=20,corrupted=false})
	local gemRow={name="Arc",detailsId="arc-exact",gemLevel=20,gemQuality=20,corrupted=false,chaosValue=5,count=50,listingCount=50}
	local function gemResult(row) return browse.managedQuote(assert(json.encode({lines={row}})),gem) end
	quote=gemResult(gemRow)
	assert(quote.state=="quoted" and quote.row.identity=="arc-exact" and quote.row.corrupted==false and quote.row.gemLevel==20)
	for key,value in pairs({gemLevel=19,gemQuality=19,corrupted=true,name="Arc of Surging"}) do
		local row={}
		for field,entry in pairs(gemRow) do row[field]=entry end
		row[key]=value
		assert(gemResult(row).state=="missing",key)
	end
	gemRow.variant="Imbued"
	assert(gemResult(gemRow).state=="ambiguous")
	gemRow.variant=nil;gemRow.count=1
	assert(gemResult(gemRow).state=="thin")
	assert(browse.managedQuote('{"lines":[]}',gem).state=="empty")
	assert(not pcall(browse.managedQuote,'{"lines":[]} trailing',gem))
	assert(not pcall(browse.managedQuote,'{"core":{"primary":"divine"},"items":[],"lines":[]}',scarab))
end
checkExactManagedQuoteInspection()
print("Managed quote inspection uses exact exchange, card, map, gem and Allflame identities with shared liquidity checks")


local function replaceWorkerExit(worker, onExit)
	for index=1,20 do
		if debug.getupvalue(worker.frame,index)=="exitStatus" then
			debug.setupvalue(worker.frame,index,onExit)
			return
		end
	end
	error("Could not intercept the worker process exit")
end

local function checkWindowsWorkerResult()
	local module = "Modules.LootFilterDailySync"
	local engine = assert(loadfile("Modules/LootFilterDailySync.lua"))()
	local worker = assert(loadfile("Modules/LootFilterBackground.lua"))()
	local root = dir.."/worker-result"
	assert(require("lfs").mkdir(root))
	local oldMain, oldTime, oldDownload, oldPrint = main, os.time, launch.DownloadPage, ConPrintf
	local openFile = io.open
	local clock = oldTime()
	main = {userPath=root.."/"}
	os.time = function(date) return date and oldTime(date) or clock end
	ConPrintf = function() end
	local live = root.."/failed.filter"
	local healthy = root.."/healthy.filter"
	local settings = root.."/LootFilterDailySync.json"
	local fixed = root.."/baseline.filter"
	write(fixed,original)
	write(live,original)
	write(healthy,original)
	local other = engine.createProfile("Healthy scheduled profile")
	engine.createProfile("Never configured")
	engine.configure(live,fixed,"Covens",{hour=0,protectionFile=protections})
	engine.configure(healthy,fixed,"Covens",{profileId=other,hour=0,protectionFile=protections})
	engine.setBackground(true,engine.configuration().revision)
	engine.setBackground(true,engine.configuration(other).revision,other)

	-- Replace only the process exit, leaving the real worker and sync paths intact.
	local exitFailed, exited
	replaceWorkerExit(worker,function(failed) exitFailed,exited=not not failed,true end)
	local function frameUntilExit(app)
		for _=1,8 do
			worker.frame(app)
			if exited then return end
		end
		error("Windows worker did not exit")
	end
	local function makeApp()
		local due = engine.dueProfiles(clock,true)
		return {lootSync=engine,lootSyncDue=due,lootSyncScheduled=true,lootSyncIndex=0,lootSyncStarted=clock}
	end

	local failCallback, injected, healthyCalls
	healthyCalls = 0
	launch.DownloadPage = function(_,url,callback)
		assert(url:find("league=Covens",1,true))
		if not failCallback then failCallback=callback; return end
		healthyCalls = healthyCalls + 1
		local date = "HTTP/1.1 200 OK\r\nDate: "..os.date("!%a, %d %b %Y %H:%M:%S GMT",clock).."\r\n\r\n"
		callback({header=date,body=commodityBody})
	end
	local app = makeApp()
	assert(#app.lootSyncDue==2 and app.lootSyncDue[1].id=="default")
	worker.frame(app)
	assert(engine.busy and failCallback and not exited)
	io.open = function(path,mode)
		if path==settings..".tmp" and mode=="wb" then
			injected = true
			return nil,"No space left on device",28
		end
		return openFile(path,mode)
	end
	failCallback(nil,"Response code: 403")
	io.open = openFile
	assert(injected and not engine.configuration().lastFailure and read(live)==original)
	frameUntilExit(app)
	assert(exitFailed,"Windows task reported success after a failure that could not be saved")
	assert(healthyCalls==8 and engine.configuration(other).lastSuccess==clock and read(healthy)~=original)

	-- The same process result must survive a timed-out async request.
	clock, exited, exitFailed = clock+86400,nil,nil
	app = makeApp()
	launch.DownloadPage = function() end
	worker.frame(app)
	assert(engine.busy and not exited)
	clock = clock+301
	-- Keep the healthy profile out of this timeout case.
	io.open = function(path,mode)
		if path==settings..".tmp" and mode=="wb" then return nil,"Access denied",13 end
		return openFile(path,mode)
	end
	table.remove(app.lootSyncDue,2)
	frameUntilExit(app)
	io.open = openFile
	assert(exitFailed and not engine.configuration().lastFailure and read(live)==original)

	-- A profile that became paused after discovery is an ordinary skip.
	clock, exited, exitFailed = clock+86400,nil,nil
	app = makeApp()
	table.remove(app.lootSyncDue,2)
	assert(#app.lootSyncDue==1 and app.lootSyncDue[1].id=="default")
	engine.pause(true)
	launch.DownloadPage = function() error("Paused profile requested prices") end
	frameUntilExit(app)
	assert(not exitFailed)
	engine.pause(false)

	-- An unreadable configuration must not quietly look like an idle worker.
	clock, exited, exitFailed = clock+86400,nil,nil
	local oldLoad, oldGetScriptPath, oldRender, oldGetTime = LoadModule, GetScriptPath, RenderInit, GetTime
	GetTime = function() return 0 end
	local originalEngine = package.loaded[module]
	package.loaded[module] = engine
	LoadModule = function() end
	GetScriptPath = function() return root end
	RenderInit = function() end
	engine.pause(true,other)
	io.open = function(path,mode)
		if path==settings and mode=="rb" then return nil,"Access denied",13 end
		return openFile(path,mode)
	end
	worker.start({devMode=true},true)
	io.open = openFile
	assert(exited and exitFailed,"Unreadable settings produced a successful Windows task result")

	-- Default is independently usable when the profile list cannot be decoded.
	clock, exited, exitFailed = clock+86400,nil,nil
	write(root.."/LootFilterSyncProfiles.json","{}")
	app = {devMode=true}
	local defaultCalls = 0
	launch.DownloadPage = function(_,_,callback)
		defaultCalls = defaultCalls + 1
		local date = "HTTP/1.1 200 OK\r\nDate: "..os.date("!%a, %d %b %Y %H:%M:%S GMT",clock).."\r\n\r\n"
		callback({header=date,body=commodityBody})
	end
	worker.start(app,true)
	assert(not exited and #app.lootSyncDue==1 and app.lootSyncDue[1].id=="default")
	frameUntilExit(app)
	assert(exitFailed and defaultCalls==8 and engine.configuration().lastSuccess==clock and read(live)~=original)
	LoadModule,GetScriptPath,RenderInit,GetTime,package.loaded[module] = oldLoad,oldGetScriptPath,oldRender,oldGetTime,originalEngine
	main,os.time,launch.DownloadPage,ConPrintf = oldMain,oldTime,oldDownload,oldPrint
end

checkWindowsWorkerResult()
print("Windows worker result survives unsaved failures and processes other due profiles")


local function checkScheduledWorkerBudget()
	local module = "Modules.LootFilterDailySync"
	local originalEngine = package.loaded[module]
	local oldMain, oldTime, oldDownload, oldPrint = main, os.time, launch.DownloadPage, ConPrintf
	local oldLoad, oldGetScriptPath, oldRender, oldGetTime = LoadModule, GetScriptPath, RenderInit, GetTime
	local calendar = os.date("*t")
	calendar.hour, calendar.min, calendar.sec, calendar.isdst = 12, 0, 0, nil
	local epoch = oldTime(calendar)
	local elapsed, wallElapsed = 0,0
	os.time = function(date) return date and oldTime(date) or epoch+wallElapsed end
	GetTime = function() return elapsed*1000 end
	ConPrintf = function() end
	LoadModule = function() end
	RenderInit = function() end
	local root = dir.."/worker-budget"
	assert(require("lfs").mkdir(root))
	GetScriptPath = function() return root end
	main = {userPath=root.."/"}

	local engine = assert(loadfile("Modules/LootFilterDailySync.lua"))()
	local fixed = root.."/fixed.filter"
	write(fixed,original)
	local ids = {"default",engine.createProfile("Second budget profile"),engine.createProfile("Third budget profile")}
	local targets = {}
	for index,id in ipairs(ids) do
		targets[id] = root.."/profile-"..index..".filter"
		write(targets[id],original)
		engine.configure(targets[id],fixed,"Covens",{profileId=id,hour=0,protectionFile=protections})
		engine.setBackground(true,engine.configuration(id).revision,id)
	end

	local worker = assert(loadfile("Modules/LootFilterBackground.lua"))()
	local exitFailed, exited, pending
	replaceWorkerExit(worker,function(failed) exitFailed,exited=not not failed,true end)
	local requests = 0
	local function reply(callback)
		local date = "HTTP/1.1 200 OK\r\nDate: "..os.date("!%a, %d %b %Y %H:%M:%S GMT",os.time()).."\r\n\r\n"
		callback({header=date,body=commodityBody})
	end
	launch.DownloadPage = function(_,url,callback)
		requests = requests+1
		if url:find("type=Currency",1,true) then
			assert(not pending)
			pending = callback
		else reply(callback) end
	end
	local function start(scheduled, at)
		exited,exitFailed,elapsed,wallElapsed = nil,nil,at,at
		engine = assert(loadfile("Modules/LootFilterDailySync.lua"))()
		package.loaded[module] = engine
		local app = {devMode=true,startTime=elapsed*1000}
		worker.start(app,scheduled)
		assert(not exited)
		worker.frame(app)
		assert(pending and engine.busy)
		return app
	end
	local function finish(elapsedAt, wallAt)
		elapsed,wallElapsed = elapsedAt,wallAt
		local callback = assert(pending)
		pending = nil
		reply(callback)
		assert(not engine.busy)
	end

	package.loaded[module] = engine
	local lateStartup = {devMode=true,startTime=0}
	elapsed,wallElapsed = 90,90
	worker.start(lateStartup,true)
	worker.frame(lateStartup)
	assert(exited and not exitFailed and not pending and requests==0)
	assert(#engine.dueProfiles(os.time(),true)==3)

	for index,id in ipairs(ids) do
		local startAt = (index-1)*300
		local app = start(true,startAt)
		assert(#app.lootSyncDue==4-index and app.lootSyncDue[1].id==id)
		local deadline = startAt+240
		-- A wall-clock change cannot expand the Windows process budget.
		finish(deadline,startAt+60)
		local completed = engine.configuration(id)
		assert(completed.review and completed.review.protectedChecks==1 and read(targets[id])~=original)
		for later=index+1,#ids do
			assert(not engine.configuration(ids[later]).lastSuccess and read(targets[ids[later]])==original)
		end
		worker.frame(app)
		assert(exited and not exitFailed and not pending and requests==index*8)
	end

	local app = start(false,86400)
	finish(86640,86640)
	worker.frame(app)
	assert(not exited and engine.busy and pending,"Manual worker should continue the remaining profiles")
	finish(86880,86880)
	worker.frame(app)
	assert(not exited and engine.busy and pending)
	finish(87120,87120)
	worker.frame(app)
	assert(exited and not exitFailed and not pending and requests==48)
	for _,id in ipairs(ids) do assert(#engine.configuration(id).history==2) end
	LoadModule,GetScriptPath,RenderInit,GetTime,package.loaded[module] = oldLoad,oldGetScriptPath,oldRender,oldGetTime,originalEngine
	main,os.time,launch.DownloadPage,ConPrintf = oldMain,oldTime,oldDownload,oldPrint
end

checkScheduledWorkerBudget()
print("Windows task budget defers slow profiles and completes each on later triggers")


local function checkIndividualQuoteContinuity()
	local json = require("dkjson")
	local module = "Modules/LootFilterDailySync.lua"
	local service = assert(loadfile(module))()
	local oldDownload, oldTime = launch.DownloadPage, os.time
	local clock, mode = oldTime(), "liquid"
	os.time = function(date) return date and oldTime(date) or clock end
	local id = service.createProfile("Individual quote continuity")
	local live, fixed = dir.."/quote-continuity.filter",dir.."/quote-continuity-fixed.filter"
	local grouped = original:gsub('"Orb of Alteration"','"Orb of Alteration" "Orb of Fusing" "Orb of Transmutation"',1)
	local raw = market.addManagedSection(grouped,{
		{name="The Doctor",class="Divination Cards",scope="all"},
		{class="Maps",tier=16,mapType="Map"},
		{name="Arc",class="Skill Gems",scope="maps",gemLevel=20,gemQuality=20,corrupted=false},
		{name="Arc",class="Skill Gems",scope="maps",gemLevel=20,gemQuality=20,corrupted=true},
	})
	write(live,raw)
	write(fixed,raw)
	local options = {profileId=id,hour=0,targetValue=1,protectionFile=protections}
	service.configure(live,fixed,"Covens",options)
	service.setOfflinePriceDays(id,1,service.configuration(id).revision)
	local function exchange(rows)
		local names, quotes = {}, {}
		for index, row in ipairs(rows) do
			names[index] = {id=row[1],name=row[2]}
			quotes[index] = {id=row[1],primaryValue=row[3],volumePrimaryValue=row[4] or 1000}
		end
		return assert(json.encode({core={primary="chaos"},items=names,lines=quotes}))
	end
	local auxiliary = exchange({{"auxiliary","Auxiliary token",1}})
	launch.DownloadPage = function(_,url,callback)
		local category = assert(url:match("type=(%w+)$"))
		local body
		if category=="Currency" then
			local rows = {{"alt","Orb of Alteration",0.21},{"trans","Orb of Transmutation",mode=="liquid" and 0.01 or 0.5}}
			if mode~="missing" then rows[#rows+1] = {"fusing","Orb of Fusing",mode=="liquid" and 1.3 or 0.01} end
			body = exchange(rows)
		elseif category=="DivinationCard" then
			body = exchange({{"doctor","The Doctor",mode=="cheap" and 0.1 or 8,mode=="missing" and 1 or 1000}})
		elseif category=="Map" then
			local rows = {{name="Map (Tier 15)",detailsId="tier-15",chaosValue=1,count=50,listingCount=50}}
			if mode~="missing" then
				rows[#rows+1] = {name="Map (Tier 16)",detailsId="tier-16",chaosValue=mode=="cheap" and 0.1 or 8,count=50,listingCount=50}
			end
			body = assert(json.encode({lines=rows}))
		elseif category=="SkillGem" then
			local rows = {{name="Arc",detailsId="corrupted-arc",gemLevel=20,gemQuality=20,corrupted=true,chaosValue=0.1,count=50,listingCount=50}}
			rows[#rows+1] = {name="Arc",detailsId="regular-arc",gemLevel=20,gemQuality=20,corrupted=false,chaosValue=mode=="cheap" and 0.1 or 8,count=50,listingCount=50}
			if mode=="missing" then
				rows[#rows+1] = {name="Arc",detailsId="competing-arc",gemLevel=20,gemQuality=20,corrupted=false,chaosValue=0.1,count=50,listingCount=50}
			end
			body = assert(json.encode({lines=rows}))
		else body = auxiliary end
		local date = "HTTP/1.1 200 OK\r\nDate: "..os.date("!%a, %d %b %Y %H:%M:%S GMT",clock).."\r\n\r\n"
		callback({header=date,body=body})
	end
	local function decisions(changes)
		local result = {}
		for _, value in ipairs(changes) do result[value.name or value.item] = value end
		return result
	end
	service.tick(clock,true,false,id)
	local initial = service.configuration(id)
	assert(initial.review and initial.cutoffContinuity and initial.review.protectedChecks==1,service.status)
	assert(decisions(initial.review.changes)["Orb of Fusing"].cutoff==0)
	local firstOutput = read(live)

	mode,clock = "missing",clock+1
	-- A matching read-only review and the scheduled publish agree.
	local proposed
	service.preview(live,fixed,"Covens",options,function(_,candidate) proposed = candidate end)
	assert(proposed and read(live)==firstOutput)
	service.tick(clock,true,false,id)
	local retained = service.configuration(id)
	local byName = decisions(retained.review.changes)
	assert(retained.lastSuccess==clock and retained.review.protectedChecks==1)
	for _,name in ipairs({"Orb of Fusing","The Doctor","Map (Tier 16)","Arc"}) do
		local value = assert(byName[name],name)
		assert(value.cutoff==0 and value.retainedReason and not value.price and not value.currentPrice and not value.volume)
	end
	assert(byName.Arc.corrupted==false and byName.Arc.gemQuality==20)
	assert(byName["Orb of Transmutation"].cutoff==1 and not byName["Orb of Transmutation"].retainedReason)
	local output = read(live)
	assert(output==proposed and output~=firstOutput and read(fixed)==raw)
	local offline = assert(service.previewOffline(clock,id,{targetValue=1,pickupPolicy={}}))
	assert(offline.after==output and offline.before==output)
	local changedPolicy = service.previewOffline(clock,id,{targetValue=2})
	assert(changedPolicy.after:find('"Orb of Fusing"',1,true))
	local bridge = decisions(assert(service.publicDiff(clock,id)).changes)
	assert(bridge["Orb of Fusing"].retainedReason and not bridge["Orb of Fusing"].quotedPrice)
	-- A restarted worker retains the same visibility without an older price.
	clock = clock+1
	service = assert(loadfile(module))()
	service.tick(clock,true,false,id)
	assert(read(live)==output and decisions(service.configuration(id).review.changes).Arc.retainedReason)

	-- Saving an unchanged pickup policy with a new schedule keeps verified visibility.
	options.hour = 8
	service.configure(live,fixed,"Covens",options)
	assert(service.configuration(id).cutoffContinuity and read(live)==output)
	clock = clock+1
	service.tick(clock,true,false,id)
	assert(read(live)==output and decisions(service.configuration(id).review.changes).Arc.retainedReason)

	mode,clock = "cheap",clock+1
	service.tick(clock,true,false,id)
	assert(read(live):find('"Orb of Fusing"',1,true) and not decisions(service.configuration(id).review.changes)["Orb of Fusing"])
	mode,clock = "missing",clock+1
	service.tick(clock,true,false,id)
	assert(read(live):find('"Orb of Fusing"',1,true) and not decisions(service.configuration(id).review.changes)["Orb of Fusing"])

	mode,clock = "liquid",clock+1
	service.tick(clock,true,false,id)
	assert(service.configuration(id).cutoffContinuity and not read(live):find('"Orb of Fusing"',1,true))
	options.targetValue = 2
	service.configure(live,fixed,"Covens",options)
	assert(not service.configuration(id).cutoffContinuity)
	mode,clock = "missing",clock+1
	service.tick(clock,true,false,id)
	assert(read(live):find('"Orb of Fusing"',1,true))
	os.time,launch.DownloadPage = oldTime,oldDownload
end

checkIndividualQuoteContinuity()
print("Missing, thin, and ambiguous quotes retain only the exact previously verified lower cutoff")


local function checkReviewedLeagueRollover()
	local json = require("dkjson")
	local service = assert(loadfile("Modules/LootFilterDailySync.lua"))()
	local oldTime, download, endpoint = os.time, launch.DownloadPage, market.endpoint
	market.endpoint = "https://league-review.example.test/"
	local clock, mode = oldTime(), "active"
	os.time = function(date) return date and oldTime(date) or clock end
	local id = service.createProfile("Reviewed rollover profile")
	local live, fixed = dir.."/rollover.filter",dir.."/rollover-base.filter"
	write(live,original)
	write(fixed,original)
	local settings = {profileId=id,hour=0,minute=15,protectionFile=protections}
	service.configure(live,fixed,"Old League",settings)
	local requests = {}
	local leagues = '[{"id":"New League","name":"New Challenge League"},{"id":"Standard","name":"Standard"}]'
	launch.DownloadPage = function(_,url,callback,options)
		assert(options.followRedirects==false)
		requests[#requests+1] = url
		local date = "HTTP/1.1 200 OK\r\nDate: "..os.date("!%a, %d %b %Y %H:%M:%S GMT",clock)
		if url:match("/leagues$") then
			if mode=="relay failure" then
				callback({header="HTTP/1.1 502 Error\r\nX-PoB-Market-Failure: stale\r\n\r\n"},"Response code: 502")
				return
			end
			callback({header=date..(mode=="stale" and "\r\nAge: 4000" or "").."\r\n\r\n",
				body=mode=="malformed" and leagues.."{}" or mode=="listed" and
					'[{ "id":"New League","name":"New Challenge League" },{"id":"Old League","name":"Old League"}]' or leagues})
			return
		end
		if url:find("league=Old League",1,true) and mode~="active" then
			callback(nil,"Response code: 404")
			return
		end
		local body = url:find("league=New League",1,true) and commodityBody:gsub("0%.21","0.6") or commodityBody
		callback({header=date.."\r\n\r\n",body=body})
	end
	service.tick(clock,true,false,id)
	local verified = read(live)
	assert(verified~=original and service.configuration(id).lastSuccess==clock)

	for _, failure in ipairs({"stale","malformed","listed","retired"}) do
		mode,clock=failure,clock+1
		local previousRequests=#requests
		service.tick(clock,true,false,id)
		local state = assert(service.configuration(id))
		assert(#requests==previousRequests+2 and state.league=="Old League" and read(live)==verified)
		local evidence = assert(service.publicStatus(clock,id).failedFeed)
		assert(evidence.httpStatus==404)
		if failure=="retired" then
			assert(evidence.reason=="league_unavailable" and evidence.currentLeague.id=="New League" and evidence.verifiedAt==clock)
			assert(json.decode(service.diagnosticReport(clock,id)).status.failedFeed.currentLeague.id=="New League")
		else
			assert(evidence.reason=="http_error" and not evidence.currentLeague)
		end
	end

	settings.reviewLeague = true
	mode = "relay failure"
	local failure, requested = nil, #requests
	service.preview(live,fixed,"New League",settings,function() error("Unexpected approved rollover") end,
		function(_, evidence) failure=evidence end)
	assert(failure and failure.category=="leagues" and failure.httpStatus==502 and failure.reason=="stale")
	assert(#requests==requested+1 and read(live)==verified and service.configuration(id).league=="Old League")
	mode = "retired"
	local otherReceipt
	service.preview(live,fixed,"Standard",settings,function(_,_,receipt) otherReceipt = receipt end)
	assert(otherReceipt and service.configuration(id).league=="Old League" and read(live)==verified,service.status)
	local function review()
		local result
		service.preview(live,fixed,"New League",settings,function(before, after, receipt)
			assert(before==verified and after~=before)
			result = receipt
		end,function(message) error(message) end)
		assert(result and read(live)==verified and service.configuration(id).league=="Old League",service.status)
		return result
	end
	settings.expectedLeagueReview = review()
	settings.minute = 16
	assert(not pcall(service.configure,live,fixed,"New League",settings))
	assert(service.configuration(id).league=="Old League" and read(live)==verified)
	settings.minute,settings.expectedLeagueReview=15,nil

	settings.expectedLeagueReview = review()
	clock = settings.expectedLeagueReview.expiresAt + 1
	assert(not pcall(service.configure,live,fixed,"New League",settings))
	assert(service.configuration(id).league=="Old League" and read(live)==verified)
	settings.expectedLeagueReview = nil

	settings.expectedLeagueReview = review()
	service.pause(true,id)
	assert(not pcall(service.configure,live,fixed,"New League",settings))
	assert(service.configuration(id).paused and read(live)==verified)
	settings.expectedLeagueReview = nil

	settings.expectedLeagueReview = review()
	service.configure(live,fixed,"New League",settings)
	local moved = service.configuration(id)
	assert(moved.league=="New League" and moved.paused and not moved.lastSuccess and not moved.priceHistory)
	assert(moved.minute==15 and not moved.cutoffContinuity and read(live)==verified and read(fixed)==original)
	assert(not pcall(service.configure,live,fixed,"New League",settings))
	settings.expectedLeagueReview,settings.expectedSavedLeague = nil,"Old League"
	local staleSave, why = pcall(service.configure,live,fixed,"Old League",settings)
	assert(not staleSave and tostring(why):find("The saved league changed",1,true))
	assert(service.configuration(id).league=="New League" and read(live)==verified)
	service.pause(false,id)
	clock=clock+1
	service.tick(clock,true,false,id)
	local result = service.configuration(id)
	assert(result.lastSuccess==clock and result.review.league=="New League" and result.review.protectedChecks==1)
	assert(read(live)~=verified and read(fixed)==original)
	os.time,launch.DownloadPage,market.endpoint=oldTime,download,endpoint
end

checkReviewedLeagueRollover()
print("Retired league diagnosis, guarded rollover save, and a fresh new-league sync passed")
