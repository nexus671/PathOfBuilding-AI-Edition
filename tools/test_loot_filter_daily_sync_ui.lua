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
	return {hour=9, minute=15, enabled=true, backgroundEnabled=backgroundEnabled, backgroundNotifications=notifyEnabled}
end
sync.diagnosticReport = function()
	return '{"version":1}'
end
sync.configure = function(target, baseline, _, options)
	assert(target == selected and baseline == "C:/PoE/baseline.filter")
	assert(options.hour == 12 and options.minute == 37 and options.intervalDays == 3)
	assert(options.profileId == namedId)
	assert(options.pickupPolicy.campaign == 0.25 and options.pickupPolicy.maps == 2)
	assert(options.pickupPolicy.caps["Orb of Alteration"] == 7)
	assert(options.pickupPolicy.highlightChaos == 10 and options.pickupPolicy.strongHighlightChaos == 50)
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
	harness:text("time", "12:37")
	harness:text("intervalDays", "3")
	harness:click("pickupPolicy")
	assert(main.popups[1].title == "Pickup policy")
	harness:text("campaign", "0.25")
	harness:text("maps", "2")
	harness:text("caps", '{"Orb of Alteration":7}')
	harness:text("highlightChaos","10")
	harness:text("strongHighlightChaos","50")
	harness:click("confirmTightening")
	harness:click("apply")
	harness:click("enable")
	assert(configured and main.popups[1].title == "Daily filter sync")
	harness:click("background")
	assert(backgroundEnabled)
	harness:click("backgroundNotify")
	assert(notifyEnabled)
	harness:click("background")
	assert(not backgroundEnabled)
	harness:click("copyReport")
	assert(harness.clipboard == '{"version":1}' and main.popups[1].title == "Sync diagnostics")
	harness:frame()
	print(string.format("Native setup and diagnostics controls passed at %dx%d.", unpack(size)))
end

newBuild();main.popups={};local reviewUI=headless.install({width=reviewWidth,height=reviewWidth==720 and 600 or 640});reviewUI:bind(build)
reviewFixture={hour=9,minute=15,enabled=true,summary='Review ready',history={},review={changes={{name='Orb of Alteration',old=6,cutoff=4,price=.2,volume=1000,samples={{area=83,count=5,class='Stackable Currency',before='Unknown',action='Unknown',beforeMissing={'DropLevel','C:/private/filter'},afterMissing={'ItemLevel'}}}}},skipped={}}}
reviewFixture.review.changes[2]={name='Orb of Chance',old=6,cutoff=4,price=.2,volume=1000,samples={{area=83,count=5,class='Stackable Currency',before='Hide',action='Unknown'}}}
require('Classes.LootFilterDailySyncControl').Open();reviewUI:click('review');reviewUI:text('search','Orb of Alteration')
local details={};for _,row in ipairs(main.popups[1].controls.details.list) do details[#details+1]=StripEscapes(row[1] or '') end;local shown=table.concat(details,' ')
assert(shown:find('Before: needs DropLevel',1,true) and shown:find('After: needs ItemLevel',1,true) and not shown:find('C:/private',1,true),'Missing-property reasons were not shown safely')
if output then reviewUI:frame():write(output..'/'..reviewWidth..'-filter-impact-reasons.json') end
reviewUI:text('search','Orb of Chance');local generic={};for _,row in ipairs(main.popups[1].controls.details.list) do generic[#generic+1]=StripEscapes(row[1] or '') end;assert(table.concat(generic,' '):find('preview cannot resolve a filter rule or included file',1,true),'Other uncertainty was not explained')
reviewUI:click('close');main.popups={};reviewFixture=nil

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
		review={checkedAt=reviewTime,changes={{name="Orb of Alteration",old=10,cutoff=6,price=0.21,volume=1000,maps=true}},
			feeds={{category="Currency",age=128,revalidated=true}}}}
end
launch.DownloadPage = function(_, url, callback)
	assert(url==ggg.endpoint..hour)
	callback({body=valid})
end
require("Classes.LootFilterDailySyncControl").Open()
feedUI:click("review")
assert(main.popups[1].title=="Daily filter sync review")
feedUI:text("search","Orb of Alteration")
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
mapForm.class:SetSel(#mapForm.class.list)
assert(mapForm.scope:GetSelValueByKey("val") == "Map")
mapForm.scope:SetSel(2)
rulesUI:text("name","16")
rulesUI:click("save")
assert(main.popups[1].title == "Managed price rules")
rulesUI:click("close")
rulesUI:click("keep")
local saved = filters.find(build.savers.LootFilters.data,profile.id)
assert(#saved.economyRules == 2 and saved.economyRules[1].cutoff == 6)
assert(saved.economyRules[2].mapType == "BlightedMap" and saved.economyRules[2].tier == 16)
local raw = filters.compile(saved)
assert(market.supports(raw) and raw:find('BaseType == "Orb of Alteration"\n    StackSize <= 6',1,true))
local overlap = {saved.economyRules[1],{name="Orb of Alteration",class="Stackable Currency",scope="maps",cutoff=7}}
assert(not pcall(market.validateManagedRules,overlap))
local existing = '# PoB economy: begin\nHide\n    Class == "Divination Cards"\n    BaseType == "The Apothecary"\n# PoB economy: end\n'
local merged = market.addManagedSection(existing,saved.economyRules)
assert(market.supports(merged) and #market.feedCategories(merged) == 10)
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
launch.DownloadPage = function(_,url,callback)
	assert(url:find("type=UniqueAccessory",1,true))
	local header = "HTTP/1.1 200 OK\r\nDate: "..os.date("!%a, %d %b %Y %H:%M:%S GMT").."\r\n\r\n"
	callback({header=header,body=[[{"lines":[
		{"name":"Named result","baseType":"Cord Belt","chaosValue":30,"count":50,"listingCount":40},
		{"name":"Competing result","baseType":"Cord Belt","chaosValue":120,"count":80,"listingCount":62}
	]}]]})
end
require("Classes.LootFilterMarketBrowseControl").Open()
marketUI:text("league","Covens")
marketUI:choose("category","Unique accessories")
marketUI:text("query","Named result")
marketUI:click("get")
assert(main.popups[1].title=="Unique accessories market prices")
local marketDetails={}
for _, row in ipairs(main.popups[1].controls.details.list) do marketDetails[#marketDetails+1]=StripEscapes(row[1] or "") end
assert(table.concat(marketDetails," "):find("30 to 120 chaos",1,true))
launch.DownloadPage = originalMarketDownload
print("Unique market review includes competing variants for the selected base")

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
