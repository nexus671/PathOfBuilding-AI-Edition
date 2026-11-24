local output, reviewWidth = arg[1], tonumber(arg[2]) or 960
arg = {}
dofile("HeadlessWrapper.lua")
main.disableDevAutoSave = true

local sync = require("Modules.LootFilterDailySync")
local headless = require("Modules.HeadlessUI")
local task = require("Modules.LootFilterBackgroundTask")
local selected = "C:/PoE/selected.filter"
local configured, backgroundEnabled, notifyEnabled, reviewFixture
local namedId = string.rep("b",40)
local currentProfile

function GetUserPath() return "C:/Users/QA/Documents" end
sync.selectedLocalFilter = function(dir)
	assert(dir == "C:/Users/QA/Documents/My Games/Path of Exile")
	return selected
end
sync.configuration = function(id)
	currentProfile = id
	if reviewFixture then return reviewFixture end
	return {hour=9, minute=15, enabled=true, backgroundEnabled=backgroundEnabled, backgroundNotifications=notifyEnabled, league=configured and "New Season" or nil}
end
sync.diagnosticReport = function()
	return '{"version":1}'
end
sync.configure = function(target, baseline, league, options)
	assert(target == selected and baseline == "C:/PoE/baseline.filter" and league == "New Season")
	assert(options.hour == 12 and options.minute == 37 and options.intervalDays == 3)
	assert(options.profileId == namedId)
	assert(options.pickupPolicy.campaign == 0.25 and options.pickupPolicy.maps == 2)
	assert(options.pickupPolicy.caps["Orb of Alteration"] == 7)
	assert(options.pickupPolicy.highlightChaos == 10 and options.pickupPolicy.strongHighlightChaos == 50)
	assert(options.pickupPolicy.highlightStyle == "cyan-diamond" and options.pickupPolicy.strongHighlightStyle == "purple-star")
	assert(options.pickupPolicy.confirmTightening)
	configured = true
end

sync.profiles = function() return {{id="default",name="Default"}} end
sync.createProfile = function(name)
	assert(name == "Endgame prices")
	return namedId
end
require("Classes.LootFilterFileBrowser").Open = function(_, selectedPath)
	selectedPath("C:/PoE/baseline.filter")
end
task.change = function(wanted, callback, id)
	assert(id == namedId)
	backgroundEnabled = wanted
	callback(true)
end
task.inspect = function(callback)
	callback(true,backgroundEnabled and "ready" or "missing")
end
sync.setBackgroundNotifications = function(wanted)
	notifyEnabled = wanted
end

for _, size in ipairs({{1280,720}, {960,640}, {720,600}}) do
	newBuild()
	main.popups = {}
	configured, backgroundEnabled, notifyEnabled = false, false, false
	local harness = headless.install({width=size[1], height=size[2]})
	harness:bind(build)
	require("Classes.LootFilterDailySyncControl").Open()
	harness:click("profiles")
	harness:text("search","Create profile")
	harness:click("choose")
	harness:text("name","Endgame prices")
	harness:click("create")
	assert(currentProfile == namedId and main.popups[1].controls.time.buf == "09:15")
	harness:click("detectTarget")
	assert(main.popups[1].controls.target.buf == selected)
	harness:click("baselineBrowse")
	assert(main.popups[1].controls.baseline.buf == "C:/PoE/baseline.filter")
	assert(main.popups[1].controls.league.buf=="")
	local downloadPage = launch.DownloadPage
	local age = 3601
	launch.DownloadPage = function(_,url,callback,options)
		assert(url=="https://poe.ninja/poe1/api/economy/leagues" and options.maxBytes==65536 and options.followRedirects==false)
		local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
		callback({header="HTTP/1.1 200 OK\r\nDate: "..date.."\r\nAge: "..age.."\r\n\r\n",
			body='[{"id":"New Season","name":"New Season Trade"},{"id":"Standard","name":"Standard"}]'})
	end
	harness:click("chooseLeague")
	assert(main.popups[1].title=="Choose league")
	harness:click("close")
	assert(main.popups[1].controls.league.buf=="")
	age = 0
	harness:click("chooseLeague")
	harness:text("search","New Season Trade")
	harness:click("choose")
	assert(main.popups[1].controls.league.buf=="New Season")
	launch.DownloadPage = downloadPage
	harness:text("time", "12:37")
	harness:text("intervalDays", "3")
	harness:click("pickupPolicy")
	assert(main.popups[1].title == "Pickup policy")
	harness:text("campaign", "0.25")
	harness:text("maps", "2")
	harness:click("addCap")
	assert(main.popups[1].title == "Add item cap")
	harness:text("item","Orb of Alteration")
	harness:text("limit","10001")
	harness:click("apply")
	assert(main.popups[1].title == "Item cap")
	harness:click("close")
	harness:text("limit","6")
	harness:click("apply")
	assert(main.popups[1].title == "Pickup policy")
	harness:click("editCap")
	assert(main.popups[1].controls.item.buf=="Orb of Alteration" and main.popups[1].controls.limit.buf=="6")
	harness:text("limit","7")
	harness:click("apply")
	harness:click("addCap")
	harness:text("item","Orb of Augmentation")
	harness:text("limit","4")
	harness:click("apply")
	assert(main.popups[1].controls.caps:GetSelValueByKey("name")=="Orb of Augmentation")
	harness:click("removeCap")
	assert(#main.popups[1].controls.caps.list==1 and main.popups[1].controls.caps:GetSelValueByKey("name")=="Orb of Alteration")
	harness:click("editCap")
	harness:text("item","Orb of Transmutation")
	harness:click("cancel")
	harness:text("highlightChaos","10")
	harness:text("strongHighlightChaos","50")
	harness:choose("highlightStyle","Cyan diamond","label")
	harness:choose("strongHighlightStyle","Purple star","label")
	harness:click("confirmTightening")
	harness:click("apply")
	harness:click("enable")
	assert(configured and main.popups[1].title == "Daily filter sync" and main.popups[1].controls.league.buf=="New Season")
	harness:click("backgroundStatus")
	assert(main.popups[1].title=="Windows background task" and main.popups[1].controls[2].label:find("missing",1,true))
	harness:click("close")
	harness:click("background")
	assert(backgroundEnabled)
	harness:click("backgroundStatus")
	assert(main.popups[1].title=="Windows background task" and main.popups[1].controls[2].label:find("expected",1,true))
	harness:click("close")
	do
		local original = task.inspect
		task.inspect = function(callback) callback(true,"disabled") end
		harness:click("backgroundStatus")
		assert(main.popups[1].controls.confirm and main.popups[1].controls[2].label:find("disabled",1,true))
		harness:click("confirm")
		assert(main.popups[1].controls[1].label:find("accepted",1,true))
		harness:click("close")
		task.inspect = original
	end
	harness:click("backgroundNotify")
	assert(notifyEnabled)
	harness:click("background")
	assert(not backgroundEnabled)
	harness:click("copyReport")
	assert(harness.clipboard == '{"version":1}' and main.popups[1].title == "Sync diagnostics")
	harness:frame()
	harness:click("close")
	main.popups = {}
	reviewFixture = {enabled=true,target=selected,lastSuccess=1795449900,lastFailure={
		checkedAt=1795453500,message="C:/private/filter",
		failedFeed={category="Scarab",reason="empty_response",httpStatus=200,rawError="C:/private/filter"},
	}}
	require("Classes.LootFilterDailySyncControl").Open()
	harness:click("lastAttempt")
	local attempt = main.popups[1]
	local rows = attempt.controls.message.list
	assert(attempt.title=="Last sync attempt" and attempt.width<=size[1]-40 and rows[2][1]:find("Scarab",1,true)
		and rows[2][1]:find("HTTP 200",1,true))
	assert(StripEscapes(rows[3][1])=="The feed returned no usable prices."
		and rows[4][1]:find("Last verified refresh",1,true))
	harness:frame()
	reviewFixture = nil
	print(string.format("Native setup and diagnostics controls passed at %dx%d.", unpack(size)))
end

newBuild();main.popups={};local reviewUI=headless.install({width=reviewWidth,height=reviewWidth==720 and 600 or 640});reviewUI:bind(build)
reviewFixture={hour=9,minute=15,enabled=true,summary='Review ready',history={},review={changes={{name='Orb of Alteration',old=6,cutoff=4,price=.2,volume=1000,samples={{area=83,count=5,class='Stackable Currency',before='Unknown',action='Unknown',beforeMissing={'DropLevel','C:/private/filter'},afterMissing={'ItemLevel'}}}}},skipped={}}}
reviewFixture.review.changes[2]={name='Orb of Chance',old=6,cutoff=4,price=.2,volume=1000,samples={{area=83,count=5,class='Stackable Currency',before='Hide',action='Unknown'}}}
reviewFixture.review.changes[3]={name="Map (Tier 16)",old=1,cutoff=0,price=8,volume=40,scope="maps",maps=true,samplesLimited=true,
	samples={{area=83,count=1,class="Maps",rarity="Normal",before="Hide",beforeLine=21,action="Show",line=29},
		{area=83,count=1,class="Maps",rarity="Rare",before="Hide",beforeLine=21,action="Hide",line=26}}}
reviewFixture.review.changes[4]={name="Blighted Map (Tier 16)",old=1,cutoff=0,price=12,volume=40,samplesLimited=true}
reviewFixture.review.protectedChecks=600
require('Classes.LootFilterDailySyncControl').Open();reviewUI:click('review')
local statusRows = {}
for _, row in ipairs(main.popups[1].controls.details.list) do statusRows[#statusRows+1] = StripEscapes(row[1] or "") end
local proof = table.concat(statusRows," "):gsub("%s+"," ")
assert(proof:find("600 protected filter checks passed.",1,true))
reviewUI:text('search','Orb of Alteration')
local details={};for _,row in ipairs(main.popups[1].controls.details.list) do details[#details+1]=StripEscapes(row[1] or '') end;local shown=table.concat(details,' ')
assert(shown:find('Before: needs DropLevel',1,true) and shown:find('After: needs ItemLevel',1,true) and not shown:find('C:/private',1,true),'Missing-property reasons were not shown safely')
if output then reviewUI:frame():write(output..'/'..reviewWidth..'-filter-impact-reasons.json') end
reviewUI:text("search","Orb of Chance")
local generic = {}
for _, row in ipairs(main.popups[1].controls.details.list) do
	generic[#generic+1] = StripEscapes(row[1] or "")
end
local reason = table.concat(generic," "):gsub("%s+"," ")
assert(reason:find("preview cannot resolve a filter rule or included file",1,true),"Other uncertainty was not explained")
local function impactText(query)
	reviewUI:text("search",query)
	local lines={}
	for _, row in ipairs(main.popups[1].controls.details.list) do lines[#lines+1]=StripEscapes(row[1] or "") end
	return table.concat(lines," "):gsub("%s+"," ")
end
local mapProof=impactText("Map (Tier 16)")
assert(mapProof:find("Normal Maps",1,true) and mapProof:find("Rare Maps",1,true)
	and mapProof:find("baseline line 21",1,true) and mapProof:find("result line 26",1,true))
assert(mapProof:find("still hidden",1,true) and mapProof:find("Some cases were omitted",1,true))
if output then reviewUI:frame():write(output.."/"..reviewWidth.."-filter-map-rarity-impact.json") end
assert(impactText("Blighted Map"):find("No samples for this decision",1,true))
reviewUI:click('close');main.popups={};reviewFixture=nil

do
	local raw = 'Show\n    BaseType == "Cord Belt"\n'
	local chosen, save, originalPreview = nil, sync.setOfflinePriceDays, sync.previewOffline
	reviewFixture={target=selected,enabled=true,revision="offline-review"}
	sync.setOfflinePriceDays=function(id,days,revision)
		assert(id=="default" and revision=="offline-review")
		chosen=days
		reviewFixture.offlinePriceDays=days
	end
	sync.previewOffline=function(_,id)
		assert(id=="default" and chosen==3)
		return {before=raw,after=raw.."# cached example\n",age=7201,checkedAt=1795449900}
	end
	require("Classes.LootFilterDailySyncControl").Open()
	reviewUI:click("offlinePrices")
	assert(not main.popups[1].controls.preview:IsEnabled())
	reviewUI:choose("days","3 days")
	reviewUI:click("save")
	reviewUI:click("offlinePrices")
	reviewUI:click("preview")
	assert(main.popups[1].title=="Offline price preview" and not main.popups[1].controls.copyAfter)
	reviewUI:click("copyReview")
	assert(reviewUI.clipboard:find("Oldest quote is 121 minutes old.",1,true))
	main.popups={};reviewFixture=nil
	sync.setOfflinePriceDays, sync.previewOffline = save, originalPreview
end

do
	local review = {before='Show\n    BaseType == "Cord Belt"\n',after='Show\n    BaseType == "Cord Belt"\n# personal edit\n'}
	local adopted
	reviewFixture = {target=selected,enabled=true}
	sync.externalDiff = function() return review.before,review.after end
	sync.previewExternalAdoption = function() return review end
	sync.adoptExternalEdits = function(id, seen)
		assert(id=="default" and seen==review)
		adopted = true
	end
	require("Classes.LootFilterDailySyncControl").Open()
	reviewUI:click("externalEdits")
	assert(main.popups[1].title=="Filter file changes")
	reviewUI:click("reviewAction")
	assert(main.popups[1].title=="Adopt filter edits" and not adopted)
	reviewUI:click("confirm")
	assert(main.popups[1].title=="Daily filter sync" and adopted)
	main.popups={};reviewFixture=nil
end

do
	local old = {checkedAt=1795449900, adjustments=1,oldest=300,reviewKey="archive-fixture"}
	local mock = sync.archivedReviews
	reviewFixture = {target=selected,enabled=true,history={old}}
	sync.archivedReviews = function()
		return {[old.reviewKey]={checkedAt=old.checkedAt,league="Covens",changes={
			{name="Orb of Alteration",old=6,cutoff=4,price=.21,volume=1000},
		}}}
	end
	require("Classes.LootFilterDailySyncControl").Open()
	reviewUI:click("review")
	reviewUI:text("search",os.date("%Y-%m-%d %H:%M",old.checkedAt))
	reviewUI:click("choose")
	assert(main.popups[1].title=="Archived filter sync review")
	reviewUI:text("search","Orb of Alteration")
	local lines = main.popups[1].controls.details.list
	assert(lines[2][1]:find("0.21 chaos used",1,true))
	main.popups={};reviewFixture=nil
	sync.archivedReviews = mock
end

-- Use the real GGG parser and a deterministic network response through the native review.
newBuild()
main.popups = {}
local feedUI = headless.install({width=960,height=640})
feedUI:bind(build)
local ggg = require("Modules.LootFilterExchangeCrossCheck")
local reviewTime = 1795449900
local hour = ggg.hour(reviewTime)
local itemId = assert(ggg.itemId("Orb of Alteration"))
local chaosId = "Metadata/Items/Currency/CurrencyRerollRare"
local trade = {league="Covens",market_pair={chaosId,itemId},volume_traded={[itemId]=500,[chaosId]=120}}
local encode = require("dkjson").encode
local valid = encode({next_change_id=hour+3600,markets={trade}})
assert(not pcall(ggg.decode,valid,hour-3600))
local quote = assert(ggg.compare(ggg.decode(valid,hour),"Covens","Orb of Alteration"))
assert(quote.price==0.24 and quote.count==500)
assert(not ggg.compare({trade,trade},"Covens","Orb of Alteration"))
assert(not ggg.compare({trade},"Standard","Orb of Alteration"))
assert(not ggg.compare({trade},"Covens","Chaos Orb"))
trade.volume_traded[chaosId] = 20
assert(not ggg.compare({trade},"Covens","Orb of Alteration"))
local configMock, originalFetch = sync.configuration, launch.DownloadPage
sync.configuration = function()
	return {league="Covens", target=selected, enabled=true, hour=9, summary="Protected drops verified.",
		review={checkedAt=reviewTime,changes={{name="Orb of Alteration",old=10,cutoff=6,price=0.21,volume=1000,maps=true,
			source="Currency",priceId="orb-of-alteration"},
			{name="Orb of Fusing",old=6,cutoff=0,retainedReason="Missing quote"}},
			feeds={{category="Currency",age=128,revalidated=true}}}}
end
launch.DownloadPage = function(_, url, callback)
	assert(url==ggg.endpoint..hour)
	callback({body=valid})
end
require("Classes.LootFilterDailySyncControl").Open()
feedUI:click("review")
assert(main.popups[1].title=="Daily filter sync review")
feedUI:text("search","Orb of Fusing")
local retainedDetails = {}
for _, entry in ipairs(main.popups[1].controls.details.list) do retainedDetails[#retainedDetails+1] = StripEscapes(entry[1] or "") end
local retainedText = table.concat(retainedDetails," "):gsub("%s+"," ")
assert(retainedText:find("Kept the last verified lower cutoff. Missing quote.",1,true))
assert(not retainedText:find("chaos used",1,true))
feedUI:text("search","Orb of Alteration")
assert(main.popups[1].controls.details.list[4][1]:find("orb-of-alteration",1,true))
feedUI:click("secondary")
assert(main.popups[1].title=="GGG trade comparison")
sync.configuration, launch.DownloadPage = configMock, originalFetch
print("Native review compares exact direct-chaos historical trade volumes with the primary quote")

-- Add a price-managed rule through the normal workspace and round-trip the
-- profile through its build saver and compiler without editing filter text.
newBuild()
main.popups = {}
local rulesUI = headless.install({width=960,height=640})
rulesUI:bind(build)
local filters = require("Modules.LootFilters")
local market = require("Modules.LootFilterEconomy")
local profile = filters.profile("managed-rules-test","Managed rules")
profile.template = "Show\n    Class == \"Stackable Currency\"\n"
build.savers.LootFilters:Upsert(profile)
build.planningWorkspace = require("Modules.PlanningWorkspace").new(build)
build.viewMode = "PLANNER"
build.planningWorkspace:Show("filters")
rulesUI:click("manage")
rulesUI:text("search","Managed price rules")
rulesUI:click("choose")
assert(main.popups[1].title == "Managed price rules")
rulesUI:click("choose")
rulesUI:text("name","Orb of Alteration")
rulesUI:text("cutoff","6")
rulesUI:click("save")
assert(main.popups[1].title == "Managed price rules")
rulesUI:text("search","Add a managed price rule")
rulesUI:click("choose")
local mapForm = main.popups[1].controls
rulesUI:choose("class","Maps","label")
assert(mapForm.scope:GetSelValueByKey("val") == "Map")
mapForm.scope:SetSel(2)
rulesUI:text("name","16")
rulesUI:click("save")
assert(main.popups[1].title == "Managed price rules")
rulesUI:text("search","Add a managed price rule")
rulesUI:click("choose")
rulesUI:choose("class","Support Gems","label")
rulesUI:text("name","Added Fire Damage Support")
rulesUI:text("gemLevel","20")
rulesUI:text("gemQuality","20")
rulesUI:choose("corruption","Corrupted")
rulesUI:click("save")
assert(main.popups[1].title == "Managed price rules")
rulesUI:text("search","Add a managed price rule")
rulesUI:click("choose")
rulesUI:choose("class","Map Fragments","label")
rulesUI:choose("exchangeCategory","Scarab","val")
rulesUI:text("name","Harbinger Scarab")
rulesUI:text("cutoff","4")
do
	local savedDownload = launch.DownloadPage
	local requests, empty = 0, false
	launch.DownloadPage = function(_, url, callback, opts)
		requests = requests + 1
		assert(url:find("league=Covens&type=Scarab",1,true) and opts.followRedirects==false)
		local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
		callback({header="HTTP/1.1 200 OK\r\nDate: "..date.."\r\n\r\n",
			body=empty and '{"core":{"primary":"chaos"},"items":[],"lines":[]}'
				or '{"core":{"primary":"chaos"},"items":[{"id":"supported","name":"Harbinger Scarab"},{"id":"other","name":"harbinger scarab"}],'
				..'"lines":[{"id":"supported","primaryValue":8,"volumePrimaryValue":400},{"id":"other","primaryValue":200,"volumePrimaryValue":400}]}'})
	end
	rulesUI:click("checkQuote")
	assert(requests==0 and main.popups[1].controls.query.buf=="=Harbinger Scarab")
	rulesUI:text("league","Covens")
	rulesUI:click("get")
	assert(requests==1)
	local details = {}
	for _, row in ipairs(main.popups[1].controls.details.list) do details[#details+1] = StripEscapes(row[1] or "") end
	local shown = table.concat(details," ")
	assert(shown:find("8 chaos",1,true) and shown:find("supported",1,true) and not shown:find("200 chaos",1,true))
	rulesUI:click("close")
	empty = true
	rulesUI:click("get")
	assert(requests==2 and main.popups[1].controls.status.label:find("no current price rows",1,true))
	rulesUI:click("close")
	assert(main.popups[1].title=="Edit managed price rule" and main.popups[1].controls.name.buf=="Harbinger Scarab")
	launch.DownloadPage = savedDownload
end
rulesUI:click("save")
rulesUI:text("search","Harbinger Scarab")
rulesUI:click("choose")
assert(main.popups[1].controls.exchangeCategory:GetSelValueByKey("val")=="Scarab")
rulesUI:click("save")
rulesUI:text("search","Add a managed price rule")
rulesUI:click("choose")
rulesUI:choose("class","Embers of the Allflame","label")
assert(not main.popups[1].controls.cutoff:IsShown())
rulesUI:text("name","Allflame Ember of Abyss")
rulesUI:click("save")
rulesUI:click("close")
rulesUI:click("keep")
local saved = filters.find(build.savers.LootFilters.data,profile.id)
assert(#saved.economyRules == 5 and saved.economyRules[1].cutoff == 6 and saved.economyRules[1].exchangeCategory==nil)
assert(saved.economyRules[2].mapType == "BlightedMap" and saved.economyRules[2].tier == 16)
assert(saved.economyRules[3].gemLevel==20 and saved.economyRules[3].gemQuality==20 and saved.economyRules[3].corrupted)
assert(saved.economyRules[4].exchangeCategory=="Scarab" and saved.economyRules[4].cutoff==4)
assert(saved.economyRules[5].exchangeCategory=="AllflameEmber" and saved.economyRules[5].cutoff==nil)
local raw = filters.compile(saved)
assert(raw:find('GemLevel == 20\n    Quality == 20\n    Corrupted True\n    Imbued False\n    TransfiguredGem False',1,true))
assert(market.supports(raw) and raw:find('BaseType == "Orb of Alteration"\n    StackSize <= 6',1,true))
local overlap = {saved.economyRules[1],{name="Orb of Alteration",class="Stackable Currency",scope="maps",cutoff=7}}
assert(not pcall(market.validateManagedRules,overlap))
local existing = '# PoB economy: begin\nHide\n    Class == "Divination Cards"\n    BaseType == "The Apothecary"\n# PoB economy: end\n'
local merged = market.addManagedSection(existing,saved.economyRules)
assert(market.supports(merged) and #market.feedCategories(merged) == 13)
assert(merged:find('BaseType == "The Apothecary"',1,true))
print("Managed price rules round-tripped through the native workspace and compiled into the existing price engine")

-- A bundled-base update is an explicit review, not an immediate profile write.
newBuild()
main.popups = {}
local refreshUI = headless.install({width=960,height=640})
refreshUI:bind(build)
local baseRefresh = require("Modules.LootFilterBaseRefresh")
local parser = require("Modules.LootFilterParser")
local protected = require("Modules.LootFilterProtectedDrops")
local sixLinks = parser.parse([[Show
    LinkedSockets 6
    MinimapIcon 0 Red Diamond
Hide
]])
for _, sample in ipairs(protected.samples()) do
	if sample.item.BaseType=="Royal Plate" then
		assert(sample.item.SocketGroup=="WWWWWW" and protected.explicitlyShown(parser.simulate(sixLinks,sample.item)))
	end
end
local before = parser.parse([[Show
    BaseType == "Cord Belt"
    MinimapIcon 0 Purple Star
]])
local after = parser.parse([[Hide
    BaseType == "Cord Belt"
]])
assert(#baseRefresh.evaluate(before,after).blocks == 16)
assert(baseRefresh.evaluate(before,before).checked == 16)
local revision = "9f94f4bd120574b4aa5a3366ceac461f8b733264"
local legacy = filters.profile("base-review","Base review")
legacy.baseCommit = revision
legacy.rules = {{id="personal",title="Personal",text='Show\n    BaseType == "Cord Belt"\n    MinimapIcon 0 Purple Star',enabled=true}}
local actualDownload = launch.DownloadPage
launch.DownloadPage = function(_, url, callback)
	assert(url:find(revision,1,true))
	callback({body=filters.base(filters.profile("latest","Latest"))})
end
local accepted
require("Classes.LootFilterControl").Audit(legacy,{},function(updated) accepted=updated end)
refreshUI:click("choose")
assert(main.popups[1].title=="NeverSink base review" and not accepted)
refreshUI:click("secondary")
assert(main.popups[1].title=="Filter file changes" and not accepted)
refreshUI:click("close")
refreshUI:click("choose")
assert(accepted and accepted.baseCommit==filters.source().commit and #accepted.rules==1 and accepted.rules[1].text==legacy.rules[1].text)
launch.DownloadPage=actualDownload
print("NeverSink refresh previews and validates the compiled candidate before preserving personal rules in the draft")

do
	local profile = filters.profile("imported-baseline","Imported baseline")
	local files = require("Modules.LootFilterImports")
	local originalReader = files.readFile
	local previous = table.concat({"# Prior upstream",'Show','    BaseType == "Cord Belt"',
		'    MinimapIcon 0 Purple Star','# Currency','Show','    Class == "Stackable Currency"',
		'    SetFontSize 30',''}, "\r\n")
	local finalText = previous:gsub("SetFontSize 30","SetFontSize 40")
	local mine = '# Personal exception\r\nShow\r\n    LinkedSockets 6\r\n    MinimapIcon 0 Red Diamond\r\n'
	profile.template = mine..previous
	profile.rules = {{id="personal",title="Personal",text='Hide\n    BaseType == "Portal Scroll"',enabled=true}}
	local affected = baseRefresh.planImported(profile,previous,finalText)
	assert(#affected.blocks==0 and affected.profile.template==mine..finalText)
	assert(affected.profile.upstreamDigest==require("sha1")(finalText))
	assert(affected.after:find("# PoE 3.30 | Imported baseline "..affected.profile.upstreamDigest,1,true))
	assert(not pcall(baseRefresh.planImported,affected.profile,previous,finalText))
	local newer = finalText:gsub("SetFontSize 40","SetFontSize 41")
	assert(baseRefresh.planImported(affected.profile,finalText,newer).profile.template==mine..newer)
	local hidden = previous:gsub("\r\nShow\r\n","\r\nHide\r\n",1)
	local unsafe = baseRefresh.planImported(profile,previous,hidden)
	assert(#unsafe.blocks==16)
	local edited = copyTable(profile)
	edited.template = edited.template:gsub("SetFontSize 30","SetFontSize 50")
	local collision = baseRefresh.planImported(edited,previous,finalText)
	assert(#collision.blocks==1 and not collision.profile and collision.blocks[1]:find("both change old lines",1,true))
	local custom = copyTable(profile)
	custom.template = mine..previous..[[# CUSTOM: Hide Wisdom and Portal Scrolls
Hide
    BaseType == "Scroll of Wisdom" "Portal Scroll"
# PoB economy: begin
Hide
    Class == "Stackable Currency"
    BaseType == "Orb of Alteration"
    StackSize <= 6
# PoB economy: end
]]
	local removedScroll = custom.template:gsub(' "Portal Scroll"','',1)
	local changedPolicy = baseRefresh.planImported(custom,custom.template,removedScroll)
	assert(changedPolicy.blocks[#changedPolicy.blocks]:find("custom drop protection rules",1,true))
	local withoutEconomy = copyTable(custom)
	withoutEconomy.template = custom.template:match("^(.-)# PoB economy: begin").."Show\n    SetFontSize 30\n"
	withoutEconomy.template = withoutEconomy.template:gsub("\r\n","\n"):gsub("\n","\r\n")
	local unrelated = withoutEconomy.template:gsub("SetFontSize 30\r\n$","SetFontSize 32\r\n")
	local refreshed = baseRefresh.planImported(withoutEconomy,withoutEconomy.template,unrelated)
	assert(#refreshed.blocks==0 and refreshed.profile.template==unrelated)
	local missingScroll = withoutEconomy.template:gsub(' "Portal Scroll"','',1)
	local unsafeUpdate = baseRefresh.planImported(withoutEconomy,withoutEconomy.template,missingScroll)
	assert(unsafeUpdate.blocks[#unsafeUpdate.blocks]:find("custom drop protection rules",1,true))
	local lateScroll = copyTable(custom)
	local title, section = "# CUSTOM: Hide Wisdom and Portal Scrolls", "# PoB economy: begin"
	local first = custom.template:find(title,1,true)
	local start = custom.template:find(section,first,true)
	lateScroll.template = custom.template:sub(1,first-1)..custom.template:sub(start)..custom.template:sub(first,start-1)
	local changedLateScroll = lateScroll.template:gsub(' "Portal Scroll"','',1)
	local unsafeLateScroll = baseRefresh.planImported(lateScroll,lateScroll.template,changedLateScroll)
	assert(unsafeLateScroll.blocks[#unsafeLateScroll.blocks]:find("custom drop protection rules",1,true))
	local imports = copyTable(profile)
	imports.template = 'Import "old.filter"\n'
	imports.importFiles = {{name="old.filter",text=previous},{name="new.filter",text=finalText}}
	local importOnly = baseRefresh.planImported(imports,imports.template,'Import "new.filter"\n')
	assert(importOnly.profile.template=='Import "new.filter"\n' and importOnly.after:find("SetFontSize 40",1,true))
	assert(not pcall(baseRefresh.planImported,imports,imports.template,'Import "missing.filter"\n'))
	imports.importFiles = {{name="old.filter",text=custom.template},{name="new.filter",text=removedScroll}}
	local changedAttachment = baseRefresh.planImported(imports,imports.template,'Import "new.filter"\n')
	assert(changedAttachment.blocks[#changedAttachment.blocks]:find("custom drop protection rules",1,true))
	files.readFile = function(path)
		if path=="old.filter" then return previous end
		assert(path=="new.filter")
		return finalText
	end
	main.popups = {}
	local changed
	require("Classes.LootFilterControl").Audit(profile,{},function(updated) changed=updated end)
	refreshUI:click("choose")
	assert(main.popups[1].title=="Update imported baseline")
	refreshUI:text("previous","old.filter")
	refreshUI:text("latest","new.filter")
	refreshUI:click("preview")
	assert(main.popups[1].title=="Imported base review" and not changed)
	refreshUI:click("secondary")
	assert(main.popups[1].title=="Filter file changes")
	refreshUI:click("close")
	refreshUI:click("choose")
	assert(changed and changed.template==mine..finalText and changed.rules[1].text==profile.rules[1].text)
	files.readFile = originalReader
	print("Imported baseline review preserves personal edits and blocks conflicts and lost visibility")
end

do
	local control = require("Classes.LootFilterControl")
	local function replaceVia(label, method)
		newBuild();main.popups={}
		local harness = headless.install({width=960,height=640})
		harness:bind(build)
		local profile = filters.profile("replace-source","Replace source")
		profile.template, profile.upstreamDigest = 'Show\n    BaseType == "Cord Belt"', string.rep("a",40)
		build.savers.LootFilters:Upsert(profile)
		build.planningWorkspace = require("Modules.PlanningWorkspace").new(build)
		build.viewMode = "PLANNER"
		build.planningWorkspace:Show("filters")
		local replacement, original = 'Show\n    BaseType == "Agate Amulet"', control[method]
		control[method] = function(first, second)
			local import = method=="Account" and second or first
			import(replacement)
		end
		harness:click("manage")
		harness:text("search",label)
		harness:click("choose")
		control[method] = original
		local active = build.planningWorkspace.cache.filters.layout.snapshot().data.profiles[1]
		assert(active.template==replacement and not active.upstreamDigest)
	end
	replaceVia("Import filter","Import")
	replaceVia("Account filters","Account")
end

-- Open a historical backup in the usual workspace and require the exact
-- source review before the restore action can be clicked.
newBuild()
main.popups = {}
local backupUI = headless.install({width=720,height=600})
backupUI:bind(build)
local oldConfig, oldBackups, oldPreview, oldRollback = sync.configuration, sync.backups, sync.previewBackup, sync.rollback
local oldBackupLimit = sync.setBackupLimit
local selectedLimit
local backupId = string.rep("a",40)
local selectedReview
local sampleReview = {digest=backupId,before="Show\n",after="Hide\n"}
sync.configuration = function() return {hour=9,enabled=true,backup=backupId,target=selected,revision="backup revision"} end
sync.setBackupLimit = function(id,limit,revision)
	assert(id=="default" and revision=="backup revision")
	selectedLimit = limit
end
sync.backups = function() return {{digest=backupId,checkedAt=1795449900}} end
sync.previewBackup = function(_,id)
	assert(id==backupId)
	return sampleReview
end
sync.rollback = function(_,review)
	selectedReview = review
end
require("Classes.LootFilterDailySyncControl").Open()
backupUI:click("rollback")
assert(main.popups[1].title=="Filter backups" and not main.popups[1].controls.secondary:IsEnabled())
backupUI:click("choose")
assert(main.popups[1].title=="Filter file changes" and not selectedReview)
backupUI:click("close")
assert(main.popups[1].controls.secondary:IsEnabled())
backupUI:click("secondary")
assert(main.popups[1].title=="Restore filter backup" and not selectedReview)
backupUI:click("confirm")
assert(selectedReview==sampleReview and main.popups[1].title=="Daily filter sync")
backupUI:click("backupRetention")
backupUI:text("count","3")
backupUI:click("keep")
assert(not selectedLimit and main.popups[1].title=="Limit recorded backups")
backupUI:click("confirm")
assert(selectedLimit==3 and main.popups[1].title=="Daily filter sync")
sync.setBackupLimit = oldBackupLimit
sync.configuration, sync.backups, sync.previewBackup, sync.rollback = oldConfig, oldBackups, oldPreview, oldRollback
print("Review backups requires the diff and a separate restore confirmation")

-- Searching for one unique still displays evidence for all values on its base.
newBuild()
main.popups = {}
local marketUI = headless.install({width=960,height=640})
marketUI:bind(build)
local originalMarketDownload = launch.DownloadPage
launch.DownloadPage = function(_,url,callback,options)
	assert(options.followRedirects==false)
	assert(url:find("type=UniqueAccessory",1,true))
	local header = "HTTP/1.1 200 OK\r\nDate: "..os.date("!%a, %d %b %Y %H:%M:%S GMT").."\r\n\r\n"
	callback({header=header,body=[[{"lines":[
		{"name":"Named result","baseType":"Cord Belt","detailsId":"named-result","chaosValue":30,"count":50,"listingCount":40},
		{"name":"Competing result","baseType":"Cord Belt","detailsId":"competing-result","chaosValue":120,"count":80,"listingCount":62}
	]}]]})
end
require("Classes.LootFilterMarketBrowseControl").Open()
marketUI:text("league","Covens")
marketUI:choose("category","Unique accessories")
marketUI:text("query","Named result")
local originalUniqueDB = main.uniqueDB
main.uniqueDB = {list={
	{title="Named result",baseName="Cord Belt"},
	{title="Catalogue-only unique",baseName="Leather Belt",baseLines={["Leather Belt"]={},["Cord Belt"]={}}},
}}
marketUI:click("get")
main.uniqueDB = originalUniqueDB
assert(main.popups[1].title=="Unique accessories market prices")
local marketDetails={}
for _, row in ipairs(main.popups[1].controls.details.list) do marketDetails[#marketDetails+1]=StripEscapes(row[1] or "") end
local coverage = table.concat(marketDetails," ")
assert(coverage:find("30 to 120 chaos",1,true) and coverage:find("PoB catalogue entries without a supported quote (1)",1,true),coverage)
assert(coverage:find("Unpriced: Catalogue-only unique",1,true))
do
	main.popups = {}
	launch.DownloadPage = function(_,url,callback)
		assert(url:find("type=ImbuedGem",1,true))
		local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
		callback({header="HTTP/1.1 200 OK\r\nDate: "..date.."\r\n\r\n",body=[[{"lines":[
			{"name":"Example support","detailsId":"example-support-1-0","chaosValue":3,"gemLevel":1,"gemQuality":0,
				"corrupted":false,"count":7,"listingCount":9},
			{"name":"Example support of Testing","detailsId":"example-support-variant","chaosValue":700}
		]}]]})
	end
	require("Classes.LootFilterMarketBrowseControl").Open()
	marketUI:text("league","Covens")
	marketUI:choose("category","Imbued gems")
	marketUI:text("query","=Example support")
	marketUI:click("get")
	assert(main.popups[1].title=="Imbued gems market prices")
	local detail = {}
	for _, row in ipairs(main.popups[1].controls.details.list) do detail[#detail+1]=StripEscapes(row[1] or "") end
	local text = table.concat(detail," ")
	assert(text:find("3 chaos estimated",1,true) and text:find("Gem quality: 0",1,true) and text:find("at least 20 consistent listings",1,true))
end
launch.DownloadPage = originalMarketDownload
print("Unique market review includes competing variants for the selected base")

do
	local collection = {
		skillsTab={socketGroupList={{gemList={
			{gemData=data.gems["Metadata/Items/Gems/SkillGemSupportAddedFireDamage"],level=20,quality=0,enabled=true},
			{gemData={name="Disabled gem"},level=20,quality=0,enabled=false},
		}}, {imbuedSupport="Test support",gemList={
			{gemData={name="Imbued test skill",grantedEffect={support=false}},level=20,quality=20},
		}}}},
		itemsTab={
			orderedSlots={{slotName="Body Armour",label="Body Armour"},{slotName="Ring 1",label="Ring 1"},
				{nodeId=100,label="Socket #1"},{nodeId=200,label="Socket #2"}},
			activeItemSet={["Body Armour"]={selItemId=1},["Ring 1"]={selItemId=2}},
			items={{baseName="Royal Plate",type="Body Armour",rarity="RARE"},
				{baseName="Iron Ring",title="Test unique",type="Ring",rarity="UNIQUE"},
				{baseName="Cobalt Jewel",title="Hidden Potential",type="Jewel",rarity="UNIQUE"},
				{baseName="Viridian Jewel",type="Jewel",rarity="RARE"}},
		},
		spec={allocNodes={[100]=true},jewels={[100]=3,[200]=4}},
	}
	local targets = require("Modules.LootFilterMarketBrowse").buildTargets(collection)
	assert(#targets==5 and targets[1].name=="Added Fire Damage Support" and targets[1].level==20 and targets[1].quality==0)
	assert(data.gems["Metadata/Items/Gems/SkillGemSupportBarrage"].itemBaseName=="Barrage Support")
	assert(targets[2].category=="ImbuedGem" and targets[2].imbuedSupport=="Test support")
	assert(targets[3].category=="BaseType" and targets[3].name=="Royal Plate")
	assert(targets[4].category=="UniqueAccessory" and targets[4].name=="Test unique")
	assert(targets[5].category=="UniqueJewel" and targets[5].name=="Hidden Potential")
	main.popups = {}
	local requested
	launch.DownloadPage = function(_,url,callback)
		assert(url:find("type=SkillGem",1,true))
		requested = true
		local date=os.date("!%a, %d %b %Y %H:%M:%S GMT")
		callback({header="HTTP/1.1 200 OK\r\nDate: "..date.."\r\n\r\n",body=[[{"lines":[
			{"name":"Added Fire Damage Support","detailsId":"support-20-0","chaosValue":3,"gemLevel":20,"gemQuality":0,"corrupted":false},
			{"name":"Added Fire Damage Support","detailsId":"support-20-0-corrupt","chaosValue":7,"gemLevel":20,"gemQuality":0,"corrupted":true},
			{"name":"Added Fire Damage Support","detailsId":"support-21-20","chaosValue":80,"gemLevel":21,"gemQuality":20,"corrupted":true},
			{"name":"Awakened Added Fire Damage Support","baseType":"Added Fire Damage Support","detailsId":"alternate","chaosValue":90,"gemLevel":20,"gemQuality":0}
		]}]]})
	end
	require("Classes.LootFilterMarketBrowseControl").Open(collection)
	marketUI:text("league","Covens")
	marketUI:click("buildTarget")
	marketUI:text("search","Added Fire Damage Support")
	marketUI:click("choose")
	assert(not requested and main.popups[1].controls.query.buf=="=Added Fire Damage Support")
	marketUI:click("get")
	assert(requested and main.popups[1].controls.count.label:find("2 results",1,true))
	local shown={}
	for _, row in ipairs(main.popups[1].controls.details.list) do shown[#shown+1]=StripEscapes(row[1] or "") end
	local detail=table.concat(shown," "):gsub("%s+"," ")
	assert(detail:find("7 chaos estimated",1,true) and detail:find("available corruption states",1,true))
	marketUI:click("close")
	marketUI:text("query","Added Fire Damage Support")
	marketUI:click("get")
	assert(main.popups[1].controls.count.label:find("4 results",1,true))
	launch.DownloadPage = originalMarketDownload
end

-- Real-shaped Imbued rows compare only the verified gem/support dimensions.
do
	local browser=require("Modules.LootFilterMarketBrowse")
	local json=require("dkjson")
	local target={category="ImbuedGem",name="Cyclone",level=20,quality=20,imbuedSupport="Power Charge On Critical Support"}
	local row={name="Cyclone",variant="power charge on critical",detailsId="cyclone-power-charge-on-critical",chaosValue=50,count=1,listingCount=1}
	local function compare(value) return browser.rows(assert(json.encode({lines={value}})),{id="ImbuedGem"},"",target) end
	local result=compare(row)[1]
	assert(result.partialGemMatch and result.gemLevel==nil and result.gemQuality==nil and result.corrupted==nil and not result.incomplete)
	local duplicate={};for key,entry in pairs(row) do duplicate[key]=entry end
	duplicate.detailsId="duplicate-id"
	local conflicts=browser.rows(assert(json.encode({lines={row,duplicate}})),{id="ImbuedGem"},"",target)
	assert(#conflicts==2)
	for _, conflict in ipairs(conflicts) do assert(conflict.conflicting and not conflict.price and not conflict.supported) end
	for _, patch in ipairs({{variant="Alternate Support"},{gemLevel=19},{gemQuality=19},{gemLevel="20"},{gemQuality=false},{corrupted="false"}}) do
		local value={};for key,entry in pairs(row) do value[key]=entry end
		for key,entry in pairs(patch) do value[key]=entry end
		assert(not pcall(compare,value))
	end
	row.gemLevel=20;assert(compare(row)[1].partialGemMatch)
	row.gemQuality=20;row.variant="Alternate Support"
	assert(not compare(row)[1].partialGemMatch) -- Existing complete alternate comparisons survive.
	row.corrupted="false";assert(not pcall(compare,row));row.corrupted=nil
	row.gemLevel=nil;row.gemQuality=nil;row.variant="Power Charge On Critical"
	do
		local function variant(id,level,quality,corrupted)
			return {name="Cyclone",variant="Power Charge On Critical",detailsId=id,chaosValue=50,
				count=40,listingCount=40,gemLevel=level,gemQuality=quality,corrupted=corrupted}
		end
		local variants={variant("unknown"),variant("corrupt",nil,nil,true),variant("uncorrupted",nil,nil,false),
			variant("level-only",20,nil,false),variant("quality-only",nil,20,false),variant("complete",20,20,false)}
		local function compareAll(lines)
			local results=browser.rows(assert(json.encode({lines=lines})),{id="ImbuedGem"},"",target)
			local indexed={};for _,value in ipairs(results) do indexed[value.identity]=value end
			return indexed
		end
		local separate=compareAll(variants)
		for _,value in ipairs(variants) do assert(separate[value.detailsId].price==50 and not separate[value.detailsId].conflicting) end
		assert(separate.unknown.corrupted==nil and separate.corrupt.corrupted==true and separate.uncorrupted.corrupted==false)
		assert(not separate.complete.partialGemMatch)
		variants[#variants+1]=variant("duplicate-uncorrupted",nil,nil,false)
		local grouped=compareAll(variants)
		assert(grouped.uncorrupted.conflicting and grouped.uncorrupted.price==nil)
		assert(grouped["duplicate-uncorrupted"].conflicting and grouped["duplicate-uncorrupted"].price==nil)
		for _,id in ipairs({"unknown","corrupt","level-only","quality-only","complete"}) do
			assert(grouped[id].price==50 and not grouped[id].conflicting,id)
		end
	end
	local collection={skillsTab={socketGroupList={{imbuedSupport=target.imbuedSupport,gemList={{gemData={name="Cyclone",grantedEffect={support=false}},level=20,quality=20}}}}}}
	main.popups={}
	launch.DownloadPage=function(_,url,callback)
		assert(url:find("type=ImbuedGem",1,true))
		callback({header="HTTP/1.1 200 OK\r\nDate: "..os.date("!%a, %d %b %Y %H:%M:%S GMT").."\r\n\r\n",body=assert(json.encode({lines={row}}))})
	end
	require("Classes.LootFilterMarketBrowseControl").Open(collection)
	marketUI:text("league","Covens");marketUI:click("buildTarget");marketUI:text("search","Cyclone");marketUI:click("choose")
	marketUI:click("get")
	local shown={};for _,line in ipairs(main.popups[1].controls.details.list) do shown[#shown+1]=StripEscapes(line[1] or "") end
	local detail=table.concat(shown," "):gsub("%s+"," ")
	assert(detail:find("Advisory match: exact gem name and Imbued support",1,true),detail)
	assert(detail:find("Not provided by this quote: level, quality, corruption",1,true),detail)
	assert(not detail:find("lacks verifiable price ID",1,true),detail)
	assert(detail:find("at least 20 consistent listings and observations",1,true),detail)
	if output then marketUI:frame():write(output.."/"..reviewWidth.."-imbued-partial-advisory.json") end
	launch.DownloadPage=originalMarketDownload
end

-- Exercise the exact publish workflow with a simulated account response.
newBuild()
main.popups = {}
local accountUI = headless.install({width=960,height=640})
accountUI:bind(build)
local account = require("Modules.LootFilterAccount")
local confirmedRaw = "Show\n    Class == \"Maps\"\n"
local existingRaw = "Hide\n    Class == \"Maps\"\n"
local tokenRequests = 0
local writes = 0
local remoteBody = existingRaw
sync.verifiedOutput = function(id)
	assert(id == "default")
	return confirmedRaw,{digest=string.rep("a",40),revision=string.rep("b",40),realm="pc"}
end
account.request = function(_,method,id,payload,callback)
	tokenRequests = tokenRequests+1
	if not id then
		assert(method=="GET")
		callback({filters={{id="verified-target",realm="pc",filter_name="Account mapping"},{id="console",realm="xbox",filter_name="Console"}}})
	elseif method=="GET" then
		assert(id=="verified-target")
		callback({filter={id=id,realm="pc",filter_name="Account mapping",filter=remoteBody}})
	else
		assert(method=="POST" and id=="verified-target" and payload.filter==confirmedRaw)
		for key in pairs(payload) do assert(key=="filter") end
		writes = writes+1
		callback({filter={id=id,realm="pc",filter_name="Account mapping",filter=payload.filter,validation={valid=true}}})
	end
end
local function openAccount()
	require("Classes.LootFilterSyncAccountControl").Open("default")
	accountUI:click("list")
	assert(main.popups[1].title=="Choose an account filter")
	local selection = main.popups[1].controls
	for _, row in ipairs(selection.results.list) do assert(not row.entry or row.entry.id ~= "console") end
	accountUI:click("choose")
	assert(main.popups[1].title=="Review verified account output")
	assert(not main.popups[1].controls.publish:IsEnabled())
	accountUI:click("diff")
	assert(main.popups[1].title=="Filter file changes")
	accountUI:click("close")
	assert(main.popups[1].controls.publish:IsEnabled())
end
openAccount()
remoteBody = remoteBody .. "# account has changed"
accountUI:click("publish")
assert(writes==0 and tokenRequests==3 and main.popups[1].title=="Account filter publication")
main.popups = {}
remoteBody = existingRaw
openAccount()
accountUI:click("publish")
assert(account.pending and writes==0)
account.tick(os.time())
assert(writes==1 and main.popups[1].title=="Account filter published")
print("Reviewed account publication preserves the realm, rejects remote drift and sends the exact approved file")

-- Manual browsing, league discovery, and the scheduler share the server cooldown.
do
	newBuild()
	main.popups = {}
	local ui = headless.install({width=720,height=600})
	ui:bind(build)
	local oldTime, oldDownload = os.time, launch.DownloadPage
	local oldDirectory = main.userPath
	-- This block tests shared in-process cooldown behavior. Keep it independent
	-- of persisted holds from other runs writing frames to the same directory.
	main.userPath = nil
	local time, requests = os.time(), 0
	os.time = function() return time end
	launch.DownloadPage = function(_,url,callback)
		requests = requests+1
		if requests==1 then
			callback({header="HTTP/1.1 429 Too Many Requests\r\nRetry-After: 30\r\n\r\n"},"Response code: 429")
		elseif requests==2 then
			callback(nil,"Response code: 403")
		else
			assert(url:find("/leagues",1,true))
			local date = os.date("!%a, %d %b %Y %H:%M:%S GMT",time)
			callback({header="HTTP/1.1 200 OK\r\nDate: "..date.."\r\nAge: 3601\r\n\r\n",
				body='[{"id":"Covens","name":"Covens"}]'})
		end
	end
	require("Classes.LootFilterMarketBrowseControl").Open()
	ui:text("league","Covens")
	ui:click("get")
	assert(requests==1 and sync.providerWait(time)==30)
	ui:click("get")
	assert(requests==1 and main.popups[1].controls.status.label:find("cooldown",1,true))
	ui:click("close")
	require("Classes.LootFilterDailySyncControl").Open()
	ui:click("chooseLeague")
	assert(requests==1 and main.popups[1].title=="Choose league")
	ui:click("close")
	main:ClosePopup()
	time = time+30
	require("Classes.LootFilterMarketBrowseControl").Open()
	ui:text("league","Covens")
	ui:click("get")
	assert(requests==2 and main.popups[1].controls.status.label:find("denied access",1,true))
	assert(sync.providerWait(time)==0)
	ui:text("league","")
	ui:click("get")
	assert(requests==3 and main.popups[1].controls.status.label:find("Could not verify",1,true))
	os.time, launch.DownloadPage = oldTime, oldDownload
	main.userPath = oldDirectory
end
print("Manual price review and league selection honor the same provider cooldown as sync")


-- Exercise the production download subscript with controlled curl responses.
local function checkDownloadRedirectPolicy()
	local originalRequire, originalLaunch = require, LaunchSubScript
	local originalScripts = launch.subScripts
	local responseCode, follow, received, request = 302
	local curl = {OPT_FOLLOWLOCATION="follow",INFO_RESPONSE_CODE="code"}
	function curl.easy()
		local easy = {}
		function easy:setopt(key,value) if key==curl.OPT_FOLLOWLOCATION then follow=value end end
		function easy:setopt_url(url) assert(url=="https://source.example.test/prices") end
		function easy:setopt_headerfunction(callback) self.header=callback end
		function easy:setopt_writefunction(callback) self.write=callback end
		function easy:perform()
			local code = follow==1 and responseCode==302 and 200 or responseCode
			self.code=code
			self.header("HTTP/1.1 "..code.." Fixture\r\nLocation: https://other.example.test/prices\r\n\r\n")
			if code~=304 then self.write(code==200 and "verified prices" or "redirect") end
			return true
		end
		function easy:getinfo(key) assert(key==curl.INFO_RESPONSE_CODE); return self.code end
		function easy:close() end
		return easy
	end
	require=function(name) if name=="lcurl.safe" then return curl end; return originalRequire(name) end
	LaunchSubScript=function(script,_,_,...)
		request={assert(loadstring(script))(...)}
		return 98123
	end
	launch.subScripts={}
	local function download(options)
		received=nil
		launch:DownloadPage("https://source.example.test/prices",function(response,why) received={response,why} end,options)
		launch.subScripts[98123].callback(unpack(request))
		return received[1],received[2]
	end
	local response, why=download()
	assert(follow==1 and response.body=="verified prices" and not why)
	response,why=download({followRedirects=true})
	assert(follow==1 and response.body=="verified prices" and not why)
	for _, code in ipairs({301,302,303,307,308}) do
		responseCode=code
		response,why=download({followRedirects=false})
		assert(follow==0 and why=="Response code: "..code and response.body=="redirect")
	end
	responseCode=304
	response,why=download({followRedirects=false})
	assert(follow==0 and why=="Response code: 304" and response.body=="" and response.header:find("304",1,true))
	responseCode=200
	response,why=download({followRedirects=false})
	assert(follow==0 and response.body=="verified prices" and not why)
	require, LaunchSubScript, launch.subScripts=originalRequire, originalLaunch, originalScripts
end
checkDownloadRedirectPolicy()
print("Economy downloads reject redirects while ordinary downloads retain redirect following and conditional 304 headers survive")


local function checkExchangeMarketCategories()
	local browser=require("Modules.LootFilterMarketBrowse")
	local expected={"Currency","Fragment","Runegraft","AllflameEmber","Tattoo","Omen","DjinnCoin","Ducat",
		"EnshroudingCrystal","DivinationCard","Artifact","Oil","DeliriumOrb","Scarab","Astrolabe","Thread","Fossil","Resonator","Essence"}
	local original={"DivinationCard","UniqueWeapon","UniqueArmour","UniqueAccessory","UniqueJewel","UniqueFlask",
		"Map","BlightedMap","BlightRavagedMap","UniqueMap","SkillGem","BaseType","ImbuedGem"}
	for index,id in ipairs(original) do assert(browser.categories[index].id==id) end
	local categories={}
	for _,category in ipairs(browser.categories) do
		assert(not categories[category.id]); categories[category.id]=category
	end
	local body=[[{"core":{"primary":"chaos"},"items":[
		{"id":"supported-id","name":"Supported fixture"},{"id":"thin-id","name":"Thin fixture"},
		{"id":"ambiguous-one","name":"Ambiguous fixture"},{"id":"ambiguous-two","name":"Ambiguous fixture"}],
		"lines":[{"id":"supported-id","primaryValue":10,"volumePrimaryValue":1000},
		{"id":"thin-id","primaryValue":2,"volumePrimaryValue":1},
		{"id":"ambiguous-one","primaryValue":3,"volumePrimaryValue":1000},
		{"id":"ambiguous-two","primaryValue":4,"volumePrimaryValue":1000}]}]]
	local originalDownload=launch.DownloadPage
	newBuild()
	local harness=headless.install({width=720,height=600})
	harness:bind(build)
	local requests=0
	for _,id in ipairs(expected) do
		local category=assert(categories[id])
		assert(category.feed=="exchange")
		local rows=browser.rows(body,category)
		assert(#rows==3 and rows[1].identity=="supported-id" and rows[1].supported)
		assert(rows[2].identity=="thin-id" and not rows[2].supported)
		assert(rows[3].ambiguous and not rows[3].price and not rows[3].identity)
		assert(browser.rows(body,category,"=supported-id")[1].name=="Supported fixture")
		assert(not pcall(browser.rows,'{"core":{"primary":"divine"},"items":[],"lines":[]}',category))
		main.popups={}
		launch.DownloadPage=function(_,url,callback,options)
			requests=requests+1
			assert(url==require("Modules.LootFilterEconomy").endpoint.."exchange/current/overview?league=Covens&type="..id)
			assert(options.followRedirects==false and options.timeout==20)
			callback({header="HTTP/1.1 200 OK\r\nDate: "..os.date("!%a, %d %b %Y %H:%M:%S GMT").."\r\n\r\n",body=body})
		end
		require("Classes.LootFilterMarketBrowseControl").Open()
		harness:text("league","Covens")
		harness:choose("category",category.label)
		harness:text("query","=thin-id")
		harness:click("get")
		assert(main.popups[1].title==category.label.." market prices")
		local details={}
		for _,row in ipairs(main.popups[1].controls.details.list) do details[#details+1]=StripEscapes(row[1] or "") end
		local evidence=table.concat(details," ")
		assert(evidence:find("Price ID: thin-id",1,true) and evidence:find("liquidity threshold",1,true))
	end
	assert(requests==19 and #browser.categories==48)
	assert(#require("Modules.LootFilterEconomy").categories==8)
	launch.DownloadPage=originalDownload
end
checkExchangeMarketCategories()
print("All 19 documented exchange categories browse through native controls with exact identities, ambiguity and liquidity evidence")


local function checkAdvisoryStashCoverage()
	local browser=require("Modules.LootFilterMarketBrowse")
	local json=require("dkjson")
	local added={"Wombgift","Corpse","Viscera","Incubator","ForbiddenJewel","ShrineBelt","UniqueTincture","UniqueRelic",
		"ClusterJewel","ValdoMap","Invitation","Memory","IncursionTemple","ScryingOrb","Flask","Beast","Vial"}
	local categories,stashCount={},0
	for _,category in ipairs(browser.categories) do
		categories[category.id]=category
		if category.feed~="exchange" then stashCount=stashCount+1 end
	end
	assert(stashCount==29 and #browser.categories==48)
	local function row(id)
		return {name="Fixture item",baseType="Royal Plate",detailsId=id,variant="A",chaosValue=10,count=50,listingCount=40,
			itemType="Body Armour",itemClass=3,levelRequired=64,stackSize=10,mapTier=16,mapRegion="Atlas region",
			implicitModifiers={{text="^1+10 to maximum Life"}},explicitModifiers={{text="+20 to maximum Mana"}},
			mutatedModifiers={{text="+1 to Level of all Skills"}},metadata={notable="One Step Ahead",ascendancy="Trickster"},
			tradeInfo={url="https://private.example.test/secret"},tradeFilter={secret="SECRET_TRADE_FILTER"},icon="https://private.example.test/icon"}
	end
	newBuild()
	local harness=headless.install({width=720,height=600})
	harness:bind(build)
	local oldDownload=launch.DownloadPage
	for index,id in ipairs(added) do
		local category=assert(categories[id])
		assert(browser.categories[index+31].id==id and browser.advisory(category))
		local good=row("fixture-exact")
		local rows=browser.rows(assert(json.encode({lines={good}})),category,"Fixture")
		assert(#rows==1 and rows[1].supported and rows[1].identity=="fixture-exact")
		local details=table.concat(rows[1].providerEvidence," ")
		assert(details:find("Required character level: 64",1,true) and details:find("Listed implicit: +10",1,true))
		assert(not details:find("^1",1,true) and not details:find("SECRET",1,true) and not details:find("https://",1,true))
		local duplicate=row("fixture-exact");duplicate.metadata.notable="Escape Artist"
		local conflict=browser.rows(assert(json.encode({lines={good,duplicate}})),category,"Fixture")
		assert(#conflict==1 and conflict[1].conflicting and not conflict[1].price and not conflict[1].supported)
		duplicate=row("fixture-exact");duplicate.implicitModifiers=nil;duplicate.explicitModifiers={{text="^1+10 to maximum Life"}}
		assert(browser.rows(assert(json.encode({lines={good,duplicate}})),category,"Fixture")[1].conflicting)
		duplicate=row("different-exact-id")
		local ambiguous=browser.rows(assert(json.encode({lines={good,duplicate}})),category,"Fixture")
		assert(#ambiguous==2 and ambiguous[1].conflicting and ambiguous[2].conflicting)
		local thin=row("thin-id");thin.count=1
		assert(not browser.rows(assert(json.encode({lines={thin}})),category,"Fixture")[1].supported)
		local incomplete=row("https://private.example.test/id")
		local unsafe=browser.rows(assert(json.encode({lines={incomplete}})),category,"Fixture")[1]
		assert(unsafe.incomplete and not unsafe.supported and not unsafe.identity)
		local malformed=row("malformed-id");malformed.variant="https://private.example.test/variant"
		local unverified=browser.rows(assert(json.encode({lines={malformed}})),category,"Fixture")[1]
		assert(unverified.incomplete and not unverified.supported and not unverified.variant)
		main.popups={}
		local requests=0
		launch.DownloadPage=function(_,url,callback,options)
			requests=requests+1
			assert(url==require("Modules.LootFilterEconomy").endpoint.."stash/current/item/overview?league=Covens&type="..id)
			assert(options.followRedirects==false)
			local date=os.date("!%a, %d %b %Y %H:%M:%S GMT")
			callback({header="HTTP/1.1 200 OK\r\nDate: "..date.."\r\n\r\n",body=assert(json.encode({lines={good}}))})
		end
		require("Classes.LootFilterMarketBrowseControl").Open()
		harness:text("league","Covens")
		harness:choose("category",category.label)
		harness:click("get")
		assert(requests==0 and main.popups[1].controls.status.label:find("at least two",1,true))
		harness:text("query","Fixture")
		harness:click("get")
		assert(requests==1 and main.popups[1].title==category.label.." market prices")
		local lines={}
		for _,entry in ipairs(main.popups[1].controls.details.list) do lines[#lines+1]=StripEscapes(entry[1] or "") end
		local shown=table.concat(lines," ")
		assert(shown:find("Required character level: 64",1,true) and shown:find("Listed mutated:",1,true))
		assert(not shown:find("SECRET",1,true) and not shown:find("https://",1,true))
		if index == 1 then
			main.popups={}
			good.variant="https://private.example.test/variant"
			require("Classes.LootFilterMarketBrowseControl").Open()
			harness:text("league","Covens")
			harness:choose("category",category.label)
			harness:text("query","Fixture")
			harness:click("get")
			local warning={}
			for _,entry in ipairs(main.popups[1].controls.details.list) do warning[#warning+1]=StripEscapes(entry[1] or "") end
			local evidence=table.concat(warning," "):gsub("%s+"," ")
			assert(evidence:find("lacks verifiable price ID or variant details",1,true), evidence)
			assert(not evidence:find("at least 20",1,true))
		end
	end
	launch.DownloadPage=oldDownload
	local collection={itemsTab={orderedSlots={},activeItemSet={},items={}}}
	for index,item in ipairs({
		{type="Tincture",rarity="UNIQUE",baseName="Oakbranch Tincture",title="The Battle Within"},
		{type="Jewel",rarity="UNIQUE",baseName="Crimson Jewel",title="Forbidden Flame"},
		{type="Jewel",rarity="RARE",baseName="Large Cluster Jewel"},
		{type="Viscera",rarity="NORMAL",baseName="Scorched Arm"},
		{type="Flask",rarity="MAGIC",baseName="Divine Life Flask"},
	}) do
		local slot="Slot "..index
		collection.itemsTab.orderedSlots[index]={slotName=slot,label=slot}
		collection.itemsTab.activeItemSet[slot]={selItemId=index}
		collection.itemsTab.items[index]=item
	end
	local targets=browser.buildTargets(collection)
	assert(targets[1].category=="UniqueTincture" and targets[2].category=="ForbiddenJewel")
	assert(targets[3].category=="ClusterJewel" and targets[4].category=="Viscera" and targets[5].category=="Flask")
	local first=row("forbidden-one");first.name="Forbidden Flame";first.baseType="Crimson Jewel"
	local second=row("forbidden-two");second.name="Forbidden Flame";second.baseType="Crimson Jewel";second.metadata.notable="Escape Artist"
	local variants=browser.rows(assert(json.encode({lines={first,second}})),categories.ForbiddenJewel,"=Forbidden Flame",targets[2])
	assert(#variants==2 and variants[1].supported and variants[2].supported)
end
checkAdvisoryStashCoverage()
print("All 29 stash market types preserve scoped native inspection, safe provider evidence, variant ambiguity and build routes")


local function checkReviewedRolloverControls()
	local oldConfig, oldPreview, oldConfigure, oldDownload = sync.configuration, sync.preview, sync.configure, launch.DownloadPage
	local market = require("Modules.LootFilterEconomy")
	local endpoint = market.endpoint
	local live, fixed = "C:/PoE/rollover.filter", "C:/PoE/rollover-baseline.filter"
	local saved, saves, previews = "Retired League", 0, 0
	local receipt = {proof="fixture-receipt"}
	local checkedAt = os.time()
	sync.configuration = function()
		return {enabled=true,league=saved,hour=9,target=live,baseline=fixed,
			lastFailure={checkedAt=checkedAt,failedFeed={category="Currency",reason="league_unavailable",httpStatus=404,
				currentLeague={id="New League",name="New Challenge League"},verifiedAt=checkedAt}}}
	end
	sync.preview = function(target,baseline,league,draft,onReview)
		assert(target==live and baseline==fixed and league=="New League" and draft.reviewLeague==true)
		assert(saved=="Retired League")
		previews = previews+1
		onReview("Hide\n    Class == \"Stackable Currency\"\n","Show\n    Class == \"Stackable Currency\"\n",receipt)
	end
	sync.configure = function(target,baseline,league,draft)
		assert(target==live and baseline==fixed and league=="New League" and draft.expectedLeagueReview==receipt)
		assert(draft.expectedSavedLeague==saved)
		saves = saves+1
		saved = league
	end
	local pending
	launch.DownloadPage = function(_,url,callback,params)
		assert(url==endpoint.."leagues" and params.followRedirects==false)
		pending = callback
	end
	local reply = {header="HTTP/1.1 200 OK\r\nDate: "..os.date("!%a, %d %b %Y %H:%M:%S GMT",checkedAt).."\r\n\r\n",
		body='[{"id":"New League","name":"New Challenge League"},{"id":"Standard","name":"Standard"}]'}
	newBuild()
	main.popups = {}
	local harness = headless.install({width=720,height=600})
	harness:bind(build)
	require("Classes.LootFilterDailySyncControl").Open()
	harness:click("lastAttempt")
	assert(main.popups[1].title=="Last sync attempt")
	harness:click("close")
	harness:click("chooseLeague")
	market.endpoint=endpoint.."changed/"
	pending(reply)
	assert(main.popups[1].title=="Choose league" and saved=="Retired League")
	market.endpoint=endpoint
	harness:click("close")
	harness:click("chooseLeague")
	pending(reply)
	assert(main.popups[1].title=="Choose PC trade league")
	harness:text("search","New Challenge League")
	local evidence = {}
	for _, row in ipairs(main.popups[1].controls.details.list) do evidence[#evidence+1] = StripEscapes(row[1] or "") end
	assert(table.concat(evidence," "):find("Current PC challenge league",1,true))
	harness:click("choose")
	assert(main.popups[1].controls.league.buf=="New League" and saved=="Retired League")
	harness:click("enable")
	assert(main.popups[1].title=="Review league change" and saves==0 and previews==1)
	harness:click("close")
	assert(main.popups[1].title=="Daily filter sync" and saved=="Retired League")
	harness:click("preview")
	assert(main.popups[1].title=="Review league change" and saves==0 and previews==2)
	harness:click("reviewAction")
	assert(main.popups[1].title=="Daily filter sync" and saved=="New League" and saves==1)
	sync.configuration,sync.preview,sync.configure,launch.DownloadPage=oldConfig,oldPreview,oldConfigure,oldDownload
end

checkReviewedRolloverControls()
print("Native league selection and preview keep the current profile until explicit review approval")
