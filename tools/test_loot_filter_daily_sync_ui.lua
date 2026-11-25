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
	harness:click("close")
	reviewFixture.lastFailure.failedFeed={category="Currency",reason="coverage_drop",availableQuotes=3,usualQuotes=24}
	harness:click("lastAttempt")
	local coverageRows=main.popups[1].controls.message.list
	assert(coverageRows[2][1]:find("Currency price feed",1,true))
	assert(coverageRows[3][1]:find("PoB kept the verified filter.",1,true))
	assert(coverageRows[4][1]:find("3 available, 24 recent median",1,true))
	assert(coverageRows[5][1]:find("Last verified refresh",1,true))
	harness:frame()
	harness:click("close")
	local originalStack=sync.compareObservedStack
	local previousStatus, verifiedFixture=sync.status, reviewFixture
	main.popups={}
	reviewFixture={enabled=true,target=selected}
	require("Classes.LootFilterDailySyncControl").Open()
	assert(not main.popups[1].controls.observedStack:IsEnabled())
	reviewFixture=verifiedFixture
	sync.status="Verified test refresh"
	assert(main.popups[1].controls.observedStack:IsEnabled())
	sync.compareObservedStack=function(id,name,count,area,level,class)
		assert(id=="default" and name=="Orb of Alteration" and count==5 and area==83 and level==nil and class==nil)
		return {action="Hide",line=17,styles={}}, {action="Show",line=26,styles={MinimapIcon={"1","Cyan","Diamond"},
			PlayEffect={"Blue"},SetTextColor={"255","100","50","255"},SetBorderColor={"1","2","3","255"},
			SetBackgroundColor={"4","5","6","255"},SetFontSize={"40"},PlayAlertSound={"2","250"},
			CustomAlertSound={"sound.ogg","100"},DisableDropSound={}}}
	end
	harness:click("observedStack")
	harness:text("name","Orb of Alteration")
	harness:text("size","5")
	harness:text("area","83")
	harness:click("test")
	local compared=main.popups[1]
	assert(compared.title=="Observed stack result")
	local evidence={}
	for _, comparison in ipairs(compared.controls.details.list) do evidence[#evidence+1]=StripEscapes(comparison[1] or "") end
	local shown=table.concat(evidence," ")
	assert(shown:find("Hide at line 17",1,true) and shown:find("Show at line 26",1,true) and shown:find("1 Cyan Diamond",1,true),shown)
	assert(shown:find("Beam: Blue",1,true) and shown:find("Text color (RGBA): 255 100 50 255",1,true)
		and shown:find("Alert sound: 2 250",1,true) and shown:find("Drop sound disabled",1,true),shown)
	local x,y=compared.controls.close:GetPos();local w,h=compared.controls.close:GetSize()
	assert(x>=0 and y>=0 and x+w<=size[1] and y+h<=size[2],"Long comparison must keep Close on screen")
	harness:frame()
	local previewLabels={}
	for _,command in ipairs(harness.commands) do if command.kind=="text" then previewLabels[StripEscapes(command.text)]=true end end
	assert(previewLabels["Fixed baseline | Hide"] and previewLabels["Verified filter | Show"],"Preview must identify both filter outcomes")
	if output then harness:frame():write(output.."/"..size[1].."-observed-stack-review.json") end
	if size[1]==720 then
		harness:click("close")
		local warning=string.rep("Check the included filter before using this result. ",35)
		sync.compareObservedStack=function() return {action="Unknown",reasons={warning,warning,warning}}, {action="Show",styles={}} end
		harness:click("test")
		local long=main.popups[1].controls
		harness:frame()
		local scroll=long.details.controls.scrollBar
		assert(scroll.enabled and scroll.offsetMax>0,"Long warnings must remain scrollable")
		scroll:SetOffset(scroll.offsetMax)
		assert(scroll.offset>0,"Could not reach the end of the warning")
		local cx,cy=long.close:GetPos();local cw,ch=long.close:GetSize()
		assert(cx>=0 and cy>=0 and cx+cw<=size[1] and cy+ch<=size[2],"Long warnings pushed Close off screen")
		harness:click("close")
		local capture = main.popups[1].controls
		assert(not capture.saveStacks:IsEnabled())
		local oldPaste = Paste
		Paste = function() return "Item Class: Stackable Currency\r\nRarity: Currency\r\nOrb of Alteration\r\n--------\r\nStack Size: 5/20" end
		harness:click("pasteStack")
		assert(capture.name.buf=="Orb of Alteration" and capture.size.buf=="5" and capture.area.buf=="83")
		assert(capture.class:GetSelValueByKey("class")=="Stackable Currency")
		Paste = function() return "no stack here" end
		harness:click("pasteStack")
		assert(main.popups[1].title=="Paste stack" and capture.name.buf=="Orb of Alteration")
		harness:click("close")
		Paste = oldPaste
		harness:click("recordStack")
		harness:click("recordStack")
		assert(capture.saveStacks:IsEnabled() and StripEscapes(capture.captureStatus.label()):find("2 of 250",1,true))
		Paste = function() return "Item Class: Divination Cards\nRarity: Divination Card\nThe Doctor\n--------\nStack Size: 2/8" end
		harness:click("pasteStack")
		Paste = oldPaste
		assert(capture.name.buf=="The Doctor" and capture.size.buf=="2" and capture.area.buf=="83")
		harness:click("recordStack")
		if output then harness:frame():write(output.."/720-observed-stack-capture.json") end
		harness:click("close")
		assert(main.popups[1].title=="Discard unsaved stacks")
		main:ClosePopup()
		local exports = require("Modules.LootFilterExports")
		local originalWrite, written, savedPath = exports.writeNew
		exports.writeNew = function() error("Existing observation file") end
		harness:click("saveStacks")
		assert(main.popups[1].title=="Save stacks" and capture.saveStacks:IsEnabled())
		harness:click("close")
		exports.writeNew = function(path, payload)
			assert(path:match("Loot stack observations .+%.json$"))
			written = require("dkjson").decode(payload)
			if output then
				savedPath = output.."/"..path:match("Loot stack observations .+%.json$")
				originalWrite(savedPath,payload)
			end
		end
		harness:click("saveStacks")
		exports.writeNew = originalWrite
		assert(main.popups[1].title=="Stack observations saved" and not capture.saveStacks:IsEnabled())
		assert(#written==3 and written[1].BaseType=="Orb of Alteration" and written[1].StackSize==5
			and written[1].AreaLevel==83 and written[1].Class=="Stackable Currency" and written[1].Rarity==nil)
		assert(written[2].BaseType==written[1].BaseType and written[2].StackSize==written[1].StackSize)
		assert(written[3].BaseType=="The Doctor" and written[3].Class=="Divination Cards" and written[3].StackSize==2)
		if savedPath then
			local result = sync.compareObservedStackBatch('Hide\n    BaseType == "Orb of Alteration"\n\nShow\n','Show\n',savedPath)
			assert(result.count==3 and result.shown==2 and result.unchanged==1 and result.units==12)
		end
	end
	sync.compareObservedStack,sync.status=originalStack,previousStatus
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
reviewFixture.review.skipped={
	{name="Chaos Orb",policyCap=5,reason="No eligible managed stack rule matches this exact item name in the fixed baseline."},
	{name="Vaal Orb",policyCap=4,old=6,reason="No managed stack cutoff is below the cap. Price-based tightening needs room above the baseline."},
}
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
local capProof=impactText("Chaos Orb")
assert(capProof:find("No eligible managed stack rule",1,true) and capProof:find("Configured cap: 5",1,true),capProof)
if output then reviewUI:frame():write(output.."/"..reviewWidth.."-filter-cap-coverage.json") end
local boundedCap=impactText("Vaal Orb")
assert(boundedCap:find("Configured cap: 4",1,true) and boundedCap:find("Lowest baseline cutoff: 6",1,true),boundedCap)
reviewUI:click('close');main.popups={};reviewFixture=nil

local function testPreviewStack(harness)
	local preview=main.popups[1]
	harness:click("inspectStack")
	harness:text("name","Orb of Alteration")
	harness:text("size","5")
	harness:text("area","83")
	harness:click("test")
	assert(main.popups[1].title=="Observed stack result")
	local rows={}
	for _, row in ipairs(main.popups[1].controls.details.list) do rows[#rows+1]=StripEscapes(row[1] or "") end
	local shown=table.concat(rows," ")
	assert(shown:find("Current filter | Hide at line 1",1,true)
		and shown:find("Proposed filter | Show at line 1",1,true),shown)
	harness:click("close")
	harness:click("close")
	assert(main.popups[1]==preview)
end

do
	local raw = 'Hide\n    BaseType == "Orb of Alteration"\n'
	local chosen, save, originalPreview = nil, sync.setOfflinePriceDays, sync.previewOffline
	reviewFixture={target=selected,enabled=true,revision="offline-review"}
	sync.setOfflinePriceDays=function(id,days,revision)
		assert(id=="default" and revision=="offline-review")
		chosen=days
		reviewFixture.offlinePriceDays=days
	end
	sync.previewOffline=function(_,id)
		assert(id=="default" and chosen==3)
		return {before=raw,after=raw:gsub("^Hide","Show"),age=7201,checkedAt=1795449900}
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
	if output then reviewUI:frame():write(output.."/"..reviewWidth.."-offline-observed-stack.json") end
	testPreviewStack(reviewUI)
	local picker=require("Classes.LootFilterFileBrowser")
	local originalChoose,originalBatch=picker.Open,sync.compareObservedStackBatch
	picker.Open=function(_,choose,options)
		assert(options.accept("recorded.JSON") and not options.accept("filter.filter"))
		choose("C:/PoE/recorded.JSON")
	end
	sync.compareObservedStackBatch=function(before,after,path)
		assert(before==raw and after==raw:gsub("^Hide","Show") and path=="C:/PoE/recorded.JSON")
		return {count=1,units=5,shown=1,hidden=0,unchanged=0,unknown=0,
			byClass={{key="Stackable Currency",count=1,units=5,shown=1,hidden=0,unchanged=0,unknown=0}},
			byArea={{key=83,count=1,units=5,shown=1,hidden=0,unchanged=0,unknown=0}}},{
			{item={BaseType="Orb of Alteration",StackSize=5,AreaLevel=83,Class="Stackable Currency"},
				before={action="Hide",line=4,matches={1,4},reasons={"Included file needs review."}},after={action="Show",line=1,styles={}},group="shown"},
		}
	end
	reviewUI:click("inspectStack")
	reviewUI:click("importStacks")
	assert(main.popups[1].title=="Recorded stack comparison")
	local facts={}
	for _, row in ipairs(main.popups[1].controls.details.list) do facts[#facts+1]=StripEscapes(row[1] or "") end
	local summary=table.concat(facts," "):gsub("%s+"," ")
	assert(summary:find("1 recorded stack, 5 items in total",1,true) and summary:find("Became visible: 1",1,true))
	assert(summary:find("they do not estimate drop rates",1,true))
	assert(not main.popups[1].controls.choose:IsEnabled(),"Summary cannot be previewed as an item")
	if output then reviewUI:frame():write(output.."/"..reviewWidth.."-batch-observed-stack.json") end
	reviewUI:choose("category","Became visible")
	local filtered=main.popups[1].controls
	assert(filtered.count.label:find("1 result |",1,true))
	assert(filtered.results.list[1].entry.label:find("Orb of Alteration",1,true))
	local warning={}
	for _,row in ipairs(filtered.details.list) do warning[#warning+1]=StripEscapes(row[1] or "") end
	assert(table.concat(warning," "):gsub("%s+"," "):find("Included file needs review.",1,true))
	assert(table.concat(warning," "):gsub("%s+"," "):find("Matched lines in order: 1, 4",1,true))
	assert(filtered.choose:IsEnabled())
	reviewUI:click("choose")
	assert(main.popups[1].title=="Observed stack result" and main.popups[1].controls.preview)
	reviewUI:click("close")
	assert(main.popups[1].title=="Recorded stack comparison","Preview must return to the selected observations")
	reviewUI:choose("category","By area level")
	assert(main.popups[1].controls.results.list[1].entry.label=="Area level 83")
	reviewUI:choose("category","By item class")
	assert(main.popups[1].controls.results.list[1].entry.label=="Stackable Currency")
	picker.Open,sync.compareObservedStackBatch=originalChoose,originalBatch
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
do
	local fixtures = {
		["Breach Thread"] = "Metadata/Items/Threads/ThreadBreach",
		["Expedition Thread"] = "Metadata/Items/Threads/ThreadExpedition",
		["Potent Chaotic Resonator"] = "Metadata/Items/Delve/DelveStackableSocketableCurrencyReroll2",
	}
	for name, id in pairs(fixtures) do
		assert(ggg.itemId(name)==id)
		local trades = {{
			league="Covens",market_pair={chaosId,id},volume_traded={[id]=20,[chaosId]=100},
		}}
		local result = assert(ggg.compare(trades,"Covens",name))
		assert(result.price==5 and result.count==20)
		assert(ggg.review(trades,"Covens")[1].name==name)
		assert(not ggg.compare(trades,"Standard",name))
	end
end
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
			source="Currency",priceId="orb-of-alteration",
			samples={{area=68,count=7,class="Stackable Currency",before="Hide",beforeLine=11,action="Hide",line=21}}},
			{name="Orb of Fusing",old=6,cutoff=0,retainedReason="Missing quote"}},
			skipped={{name="Managed Hide at baseline line 27",reason="Price rules require exact Class and BaseType."}},
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
feedUI:text("search","baseline line 27")
local skipDetails = {}
for _, entry in ipairs(main.popups[1].controls.details.list) do skipDetails[#skipDetails+1] = StripEscapes(entry[1] or "") end
assert(table.concat(skipDetails," "):gsub("%s+"," "):find("Price rules require exact Class and BaseType.",1,true))
feedUI:text("search","Orb of Alteration")
assert(main.popups[1].controls.details.list[4][1]:find("orb-of-alteration",1,true))
local boundaryDetails = {}
for _, entry in ipairs(main.popups[1].controls.details.list) do boundaryDetails[#boundaryDetails+1] = StripEscapes(entry[1] or "") end
local boundaryText = table.concat(boundaryDetails," "):gsub("%s+"," ")
assert(boundaryText:find("Maps (area 68), 7 as Stackable Currency",1,true))
assert(boundaryText:find("Hide at baseline line 11 to Hide at result line 21",1,true))
feedUI:click("secondary")
assert(main.popups[1].title=="GGG trade comparison")
sync.configuration, launch.DownloadPage = configMock, originalFetch
print("Native review compares exact direct-chaos historical trade volumes with the primary quote")

do
	local compact=headless.install({width=640,height=480})
	compact:bind(build)
	main.popups={}
	local tradedHour=ggg.hour(os.time())
	local function pair(league,id,count,chaosVolume)
		return {league=league,market_pair={id,chaosId},volume_traded={[id]=count,[chaosId]=chaosVolume}}
	end
	local fusing=assert(ggg.itemId("Orb of Fusing"))
	local regal=assert(ggg.itemId("Regal Orb"))
	local rows={
		pair("Covens",itemId,500,125),pair("Standard",itemId,250,150),
		pair("Covens",fusing,100,100),pair("Covens",fusing,100,100),
		pair("Covens",regal,100,33),pair("Invalid^league",itemId,500,125),
	}
	local xbox=encode({next_change_id=tradedHour+3600,markets=rows})
	local sony=encode({next_change_id=tradedHour+3600,markets={pair("Covens",itemId,400,300)}})
	assert(#ggg.review(ggg.decode(xbox,tradedHour))==2)
	assert(not pcall(ggg.decode,xbox.." false",tradedHour))
	assert(not pcall(ggg.decode,'{"markets":{},"next_change_id":'..(tradedHour+3600)..'}',tradedHour))
	local calls={}
	launch.DownloadPage=function(_,url,callback,options)
		assert(options.followRedirects==false)
		calls[#calls+1]=url
		if url==ggg.endpoint.."xbox/"..tradedHour then callback({body=xbox})
		elseif url==ggg.endpoint.."sony/"..tradedHour then callback({body=sony})
		else error("Unexpected trade history URL "..url) end
	end
	require("Classes.LootFilterMarketBrowseControl").Open({itemsTab={}})
	compact:click("tradeHistory")
	assert(main.popups[1].title=="GGG trade history")
	compact:choose("realm","Xbox")
	if output then compact:frame():write(output.."/ggg-trade-history-source.json") end
	compact:click("load")
	assert(main.popups[1].title=="Xbox completed trades")
	compact:choose("category","League Covens")
	local function resultText()
		local lines={}
		for _,row in ipairs(main.popups[1].controls.details.list) do lines[#lines+1]=StripEscapes(row[1] or "") end
		return table.concat(lines," "):gsub("%s+"," ")
	end
	assert(resultText():find("Xbox | Covens",1,true) and resultText():find("Average 0.25 chaos",1,true))
	assert(main.popups[1].controls.count.label:find("1 result",1,true))
	if output then compact:frame():write(output.."/ggg-trade-history-results.json") end
	compact:click("close")
	compact:choose("realm","PlayStation")
	compact:text("league","Covens")
	compact:click("load")
	assert(main.popups[1].title=="PlayStation completed trades")
	assert(resultText():find("PlayStation | Covens",1,true) and resultText():find("Average 0.75 chaos",1,true))
	compact:click("close")
	compact:choose("realm","Xbox")
	compact:text("league","Standard")
	compact:click("load")
	assert(resultText():find("Xbox | Standard",1,true) and resultText():find("Average 0.6 chaos",1,true))
	compact:click("close")
	compact:text("league","Absent")
	compact:click("load")
	assert(#calls==2 and main.popups[1].controls.status.label:find("No matching",1,true))
	launch.DownloadPage=originalFetch
	compact:restore()
	print("Native trade history isolates Xbox and PlayStation completed trades by realm and league")
end

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
	local rare = copyTable(custom)
	local tierMarker = "# CUSTOM: Highlight item tier 5 rare equipment on rank A and B bases"
	rare.template = custom.template..tierMarker..[[

Show
    Identified False
    Rarity Rare
    UnidentifiedItemTier 5
    BaseType == "Royal Plate"
    MinimapIcon 0 Red Diamond
Hide
    Identified False
    Rarity Rare
]]
	local shadowed = rare.template:gsub(tierMarker,'Hide\n    BaseType == "Royal Plate"\n'..tierMarker)
	local unsafeRare = baseRefresh.planImported(rare,rare.template,shadowed)
	assert(unsafeRare.blocks[#unsafeRare.blocks]:find("custom drop protection rules",1,true))
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
	main.popups = {}
	local baseUI=headless.install({width=reviewWidth,height=reviewWidth==720 and 600 or 640})
	baseUI:bind(build)
	local originalOpenURL=OpenURL
	local opened
	OpenURL=function(url) opened=url end
	local collection={itemsTab={
		orderedSlots={{slotName="Ring 1"},{slotName="Ring 2"},{slotName="Ring 3"},{slotName="Boots"}},
		activeItemSet={["Ring 1"]={selItemId=1},["Ring 2"]={selItemId=2},["Ring 3"]={selItemId=3},Boots={selItemId=4}},
		items={{baseName="Unset Ring",type="Ring",rarity="RARE",itemLevel=84},
			{baseName="Unset Ring",type="Ring",rarity="RARE",itemLevel=86},
			{baseName="Moonstone Ring",type="Ring",rarity="RARE",itemLevel="85"},
			{baseName="Two-Toned Boots (Armour/Evasion)",type="Boots",rarity="RARE",itemLevel=85}},
	}}
	local function checkUrl(league,level,base,implicit)
		local prefix="https://www.pathofexile.com/trade/search/"..urlEncode(league).."/"
		assert(opened and opened:sub(1,#prefix)==prefix,tostring(opened))
		local json=require("dkjson")
		local payload=assert(json.decode(require("Classes.TradeHelpers").B64GzipDecode(opened:sub(#prefix+1))))
		local filter=payload.filters.misc_filters.filters.ilvl
		assert(payload.type==(base or "Unset Ring") and filter.min==level and filter.max==level)
		local stat=payload.stats[1].filters[1]
		assert((stat and stat.id)==implicit)
	end
	launch.DownloadPage=function(_,url,callback)
		local date=os.date("!%a, %d %b %Y %H:%M:%S GMT")
		local body
		if url:find("type=BaseType",1,true) then
			assert(url:find("league=Covens%20of%20Umbra",1,true))
			body='{"lines":[{"name":"Unset Ring","variant":"Elder","detailsId":"unset-ring-85-elder","levelRequired":85,"chaosValue":15,"count":45,"listingCount":50}]}'
		else
			assert(url:match("leagues$"))
			body='[{"id":"Covens of Umbra","name":"Covens of Umbra"}]'
		end
		callback({header="HTTP/1.1 200 OK\r\nDate: "..date.."\r\n\r\n",body=body})
	end
	require("Classes.LootFilterMarketBrowseControl").Open(collection)
	baseUI:text("league","Covens")
	baseUI:click("buildTarget")
	baseUI:text("search","Two-Toned Boots")
	baseUI:click("choose")
	assert(main.popups[1].controls.query.buf=="=Two-Toned Boots")
	baseUI:click("exactBase")
	checkUrl("Covens",85,"Two-Toned Boots","implicit.stat_2915988346")
	opened=nil
	baseUI:click("buildTarget")
	baseUI:text("search","Moonstone Ring")
	baseUI:click("choose")
	assert(not main.popups[1].controls.exactBase:IsEnabled())
	baseUI:click("buildTarget")
	baseUI:text("search","Item level 86")
	baseUI:click("choose")
	assert(main.popups[1].controls.exactBase:IsEnabled())
	baseUI:text("league","https://wrong.example")
	baseUI:click("exactBase")
	assert(opened==nil)
	baseUI:text("league","Covens")
	baseUI:click("exactBase")
	checkUrl("Covens",86)
	baseUI:text("league","")
	baseUI:click("get")
	assert(main.popups[1].title=="Crafting bases market prices")
	local lines={}
	for _, row in ipairs(main.popups[1].controls.details.list) do lines[#lines+1]=StripEscapes(row[1] or "") end
	local details=table.concat(lines," "):gsub("%s+"," ")
	assert(details:find("Build item level: 86",1,true) and details:find("Unverified provider level: 85",1,true),details)
	assert(not details:find("Required character level",1,true),details)
	if output then baseUI:frame():write(output.."/"..reviewWidth.."-filter-exact-base-trade.json") end
	baseUI:click("secondary")
	checkUrl("Covens of Umbra",86)
	launch.DownloadPage,OpenURL=originalMarketDownload,originalOpenURL
	marketUI=headless.install({width=960,height=640})
	marketUI:bind(build)
end

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

do
	local listings=require("Modules.LootFilterGearListings")
	local raw=[[Rarity: RARE
Fixture Ring
Amethyst Ring
--------
Item Level: 86
--------
+23% to Chaos Resistance (implicit)
--------
+79 to maximum Life
+41% to Cold Resistance
]]
	local item=new("Item"):Item(raw)
	local target=assert(listings.target(item),"Expected a comparable rare ring")
	assert(target.implicitMods:find("23%% to Chaos Resistance"))
	assert(not listings.target(new("Item"):Item(raw:gsub("Item Level: 86","Item Level: 86\nUnidentified"))))
	local function row(id,note)
		return {id=string.format("%064x",id),baseType="Amethyst Ring",rarity="Rare",identified=true,ilvl=86,note=note,
			implicitMods={{description="+23% to Chaos Resistance"}},
			explicitMods={{description="+41% to Cold Resistance"},{description="+79 to maximum Life"}}}
	end
	local function stash(id,seller,items,note)
		return {id=string.format("%064x",id),accountName=seller,items=items,stash=note,league="Covens",public=true}
	end
	do
		item.crucible=true;assert(not listings.target(item),"A target with a Crucible tree needs review");item.crucible=nil
		item.vestigial=true;assert(not listings.target(item),"A vestigial target needs review");item.vestigial=false
		local json=require("dkjson")
		local cases={
			{"crucible",{nodes={}}}, {"scourged",{tier=1}}, {"incubatedItem",{name="Test"}},
			{"vestigial",true}, {"delve",true}, {"foreseeing",true}, {"builtInSupport","Support"}, {"monsterLevel",1},
			{"notableProperties",{{name="Unknown",values={}}}}, {"additionalProperties",{{name="Unknown",values={}}}},
			{"utilityMods",{"Unknown"}}, {"ultimatumMods",{{type="Unknown",tier=1}}}, {"additionalProperties","invalid"},
		}
		for index,case in ipairs(cases) do
			local listed=row(100+index,"~price 1 chaos");listed[case[1]]=case[2]
			local snapshot={next_change_id="cursor",stashes={stash(100+index,"Seller#0001",{listed})}}
			assert(listings.compare(json.encode(snapshot),target,"Covens").matched==0,case[1].." must not be treated as an exact match")
		end
		for index,flags in ipairs({{unknown=true},{fractured="yes"},{crafted=false}}) do
			local listed=row(200+index,"~price 1 chaos");listed.explicitMods[1].flags=flags
			local snapshot={next_change_id="cursor",stashes={stash(200+index,"Seller#0001",{listed})}}
			assert(listings.compare(json.encode(snapshot),target,"Covens").matched==0,"Unknown or invalid modifier flags need review")
		end
		local contradiction=row(210,"~price 1 chaos");contradiction.frameType=3
		local snapshot={next_change_id="cursor",stashes={stash(210,"Seller#0001",{contradiction})}}
		assert(listings.compare(json.encode(snapshot),target,"Covens").matched==0,"A contradictory item frame needs review")
	end
	local low, early, high = row(1,"~price 20 chaos"),row(2,"~price 10 chaos"),row(3,"~b/o 30 chaos")
	early.explicitMods={{description="+41% to Cold Resistance\n+79 to maximum Life"}}
	local wrongRoll, wrongLevel, wrongState, wrongChannel = row(4,"~price 1 chaos"),row(5,"~price 2 chaos"),row(6,"~price 3 chaos"),row(7,"~price 4 chaos")
	wrongRoll.explicitMods[2].description="+78 to maximum Life"
	wrongLevel.ilvl=85
	wrongState.corrupted=true
	wrongChannel.explicitMods[1].flags={crafted=true}
	local other = stash(7,"Other Realm#0000",{row(11,"~price 1 chaos")})
	other.league="Standard"
	local wrongIntangibility, wrongLegacy = row(15,"~price 1 chaos"),row(16,"~price 1 chaos")
	wrongIntangibility.properties={{name="Intangibility",values={{"20%",0}}}}
	local wrongMemory = row(19,"~price 1 chaos")
	wrongMemory.properties={{name="Memory Strands",values={{"12",0}}}}
	wrongLegacy.craftedMods={"+18% to Lightning Resistance"}
	local div=row(8,"~price 1.5 divine")
	local duplicate=row(9,"~price 1 chaos")
	local page={next_change_id="cursor",stashes={
		stash(1,"One#0001",{low,early,wrongRoll,wrongLevel,wrongState,wrongChannel,wrongIntangibility,wrongMemory,wrongLegacy}),
		stash(2,"Two#0002",{high,div,duplicate}),
		stash(3,"Three#0003",{row(10),row(9,"~price 60 chaos")},"~b/o 50 chaos"),
		stash(4,"Four#0004",{row(12,"~price 1/5 chaos"),row(13,"unpriced")},"~b/o 4 chaos"),
		other,stash(8,"Retired#0000",{row(14,"~price 1 chaos")}),{id=string.format("%064x",8),public=false},
	}}
	local json=require("dkjson")
	local encoded=assert(json.encode(page))
	local sample=listings.compare(encoded,target,"Covens")
	assert(sample.inspected==15 and sample.matched==7 and sample.priced==5 and sample.ambiguous==1)
	assert(sample.results[1].sellers==3 and sample.results[1].low==10 and sample.results[1].median==30 and sample.results[1].high==50)
	assert(sample.results[2].sellers==1 and sample.results[2].low==1.5 and not sample.results[2].median)
	assert(listings.compare(encoded,target,"Hardcore").matched==0)
	local specialCaptureRow=row(26,"~price 1 chaos");specialCaptureRow.crucible={nodes={}}
	local capture = {format="pob-public-stash-capture-v1",realm="pc",league="Covens",capturedAt=1700000000,pages={
		{requestCursor="start",response={next_change_id="next",stashes={
			stash(21,"Removed#0021",{row(21,"~price 1 chaos")}),
			stash(22,"Updated#0022",{row(22,"~price 15 chaos")}),
			stash(23,"Emptied#0023",{row(23,"~price 30 chaos")}),
		}}},
		{requestCursor="next",response={next_change_id="later",stashes={
			{id=string.format("%064x",21),public=false},
			stash(22,"Updated#0022",{row(22,"~price 25 chaos")}),
			stash(24,"Added#0024",{row(24,"~price 45 chaos")}),
		}}},
		{requestCursor="later",response={next_change_id="end",stashes={
			stash(23,"Emptied#0023",assert(json.decode("[]"))),
			stash(25,"Added#0025",{row(25,"~price 55 chaos")}),
			stash(26,"Special#0026",{specialCaptureRow}),
		}}},
		{requestCursor="end",response={next_change_id="end",stashes=assert(json.decode("[]"))}},
	}}
	local bundled=assert(json.encode(capture))
	local combined=listings.compare(bundled,target,"Covens")
	assert(combined.matched==3 and combined.results[1].low==25 and combined.results[1].median==45 and combined.results[1].high==55)
	assert(combined.capture.pages==4 and combined.capture.updated==2 and combined.capture.withdrawn==1)
	assert(not pcall(listings.compare,bundled,target,"Standard"))
	capture.realm="xbox"
	assert(not pcall(listings.compare,json.encode(capture),target,"Covens"))
	capture.realm="pc"
	capture.pages[2].requestCursor="missing"
	assert(not pcall(listings.compare,json.encode(capture),target,"Covens"))
	capture.pages[2].requestCursor="next"
	capture.pages[2].response.next_change_id="start"
	assert(not pcall(listings.compare,json.encode(capture),target,"Covens"))
	capture.pages[2].response.next_change_id="later"
	capture.pages[3].response.stashes[1].items={bad="shape"}
	assert(not pcall(listings.compare,json.encode(capture),target,"Covens"))
	capture.capturedAt=os.time()+86400
	assert(not pcall(listings.compare,json.encode(capture),target,"Covens"))
	assert(not pcall(listings.compare,'{"stashes":{},"next_change_id":"x"}',target,"Covens"))
	assert(not pcall(listings.compare,string.rep(" ",4*1024*1024+1),target,"Covens"))
	do
		local advanced=new("Item"):Item(raw:gsub("Item Level: 86","Item Level: 86\nIntangibility: 20%%"))
		assert(advanced.intangibility==20 and not listings.target(advanced))
		local amuletRaw=raw:gsub("Amethyst Ring","Agate Amulet"):gsub("+23%% to Chaos Resistance","+20 to Strength and Intelligence")
		amuletRaw=amuletRaw:gsub("%-%-%-%-%-%-%-%-\n%+20 to Strength","--------\nAllocates Charisma (enchant)\n--------\n+20 to Strength")
		local amulet=new("Item"):Item(amuletRaw)
		assert(amulet.enchantModLines[1] and amulet.enchantModLines[1].crafted)
		local listed=row(17,"~price 50 chaos")
		listed.baseType="Agate Amulet"
		listed.enchantMods={"Allocates Charisma"}
		listed.implicitMods={{description="+20 to Strength and Intelligence"}}
		local samplePage={next_change_id="cursor",stashes={stash(18,"Seller#0018",{listed})}}
		assert(listings.compare(json.encode(samplePage),assert(listings.target(amulet)),"Covens").matched==1)
		local variantRaw=raw:gsub("Amethyst Ring","Two-Stone Ring (Fire/Cold)")
			:gsub("+23%% to Chaos Resistance","+15%% to Fire and Cold Resistances")
		local variant=new("Item"):Item(variantRaw)
		local buildTargets=require("Modules.LootFilterMarketBrowse").buildTargets({itemsTab={orderedSlots={{slotName="Ring 1"}},
			items={variant},activeItemSet={["Ring 1"]={selItemId=1}}}})
		local variantTarget=assert(buildTargets[1] and buildTargets[1].listingItem)
		assert(variantTarget.base=="Two-Stone Ring")
		listed.baseType="Two-Stone Ring"
		listed.enchantMods=nil
		listed.implicitMods={{description="+15% to Fire and Cold Resistances"}}
		assert(listings.compare(json.encode(samplePage),variantTarget,"Covens").matched==1)
		listed.implicitMods[1].description="+15% to Cold and Lightning Resistances"
		assert(listings.compare(json.encode(samplePage),variantTarget,"Covens").matched==0)
	end
	local path=os.tmpname()..".json"
	local file=assert(io.open(path,"wb"))
	assert(file:write(encoded));assert(file:close())
	local originalPicker=require("Classes.LootFilterFileBrowser").Open
	require("Classes.LootFilterFileBrowser").Open=function(_,selected,options)
		assert(options.accept("listings.JSON") and not options.accept("filter.txt"))
		selected(path)
	end
	local oldDownload = launch.DownloadPage
	launch.DownloadPage=function() error("A file comparison must not request market data") end
	local variant=new("Item"):Item(raw:gsub("79 to maximum Life","78 to maximum Life"))
	local collection={itemsTab={orderedSlots={{slotName="Ring 1"},{slotName="Ring 2"}},items={item,variant},
		activeItemSet={["Ring 1"]={selItemId=1},["Ring 2"]={selItemId=2}}}}
	assert(#require("Modules.LootFilterMarketBrowse").buildTargets(collection)==2)
	local gearUI=headless.install({width=720,height=600})
	gearUI:bind(build)
	main.popups={}
	require("Classes.LootFilterMarketBrowseControl").Open(collection)
	gearUI:text("league","Covens")
	gearUI:click("buildTarget")
	gearUI:text("search","Ring 1")
	gearUI:click("choose")
	gearUI:click("listingSample")
	assert(main.popups[1].title=="Comparable asking prices")
	local rows={}
	for _, line in ipairs(main.popups[1].controls.details.list) do rows[#rows+1]=StripEscapes(line[1] or "") end
	local details=table.concat(rows," ")
	assert(details:find("7 matching rolls",1,true) and details:find("Median 30",1,true),details)
	assert(details:find("Range 10 to 50",1,true) and details:find("Ask 1.5 | 1 seller",1,true),details)
	assert(details:find("Realm, age and completed sales are unverified.",1,true),details)
	assert(not details:find("One#0001",1,true))
	if output then gearUI:frame():write(output.."/gear-listing-snapshot.json") end
	gearUI:click("close")
	file=assert(io.open(path,"wb"))
	assert(file:write(bundled));assert(file:close())
	gearUI:click("listingSample")
	local captureDetails={}
	for _, line in ipairs(main.popups[1].controls.details.list) do captureDetails[#captureDetails+1]=StripEscapes(line[1] or "") end
	local summary=table.concat(captureDetails," ")
	assert(summary:find("Declared PC capture",1,true) and summary:find("Median 45",1,true),summary)
	assert(summary:find("Pages: 4 | Stash updates: 2 | Withdrawals: 1",1,true),summary)
	assert(summary:find("partial stream",1,true),summary)
	if output then gearUI:frame():write(output.."/gear-listing-capture.json") end
	print("Native gear listing snapshot compares exact rolls and distinct sellers with no market request")

	local function equipmentRow(id, name, sockets, props, mods)
		local value=row(id,"~price 50 chaos")
		value.baseType=name
		value.sockets=sockets
		value.properties=props
		value.implicitMods=nil
		value.explicitMods=mods
		return value
	end
	local function sockets(colors, broken)
		colors=colors:gsub("%-","")
		local values={}
		for index=1,#colors do
			values[index]={sColour=colors:sub(index,index),group=broken and index==#colors and 1 or 0}
		end
		return values
	end
	local function property(name,value) return {name=name,values={{value,0}}} end
	do
		local rawQuiver="Rarity: RARE\nFixture Quiver\nBroadhead Arrow Quiver\nItem Level: 86\nImplicits: 1\n9% increased Attack Speed\n+79 to maximum Life"
		local quiver=new("Item"):Item(rawQuiver)
		local target=assert(listings.target(quiver))
		assert(target.equipment.class=="Quiver" and target.base=="Broadhead Arrow Quiver")
		for _, ambiguous in ipairs({
			rawQuiver:gsub("9%% increased Attack Speed","6 to 12 Added Physical Damage with Bow Attacks"),
			"Rarity: RARE\nFixture Quiver\nPenetrating Arrow Quiver\nItem Level: 86\nImplicits: 1\nArrows Pierce an additional Target\n+79 to maximum Life",
			rawQuiver.."\nCorrupted",
		}) do
			assert(not listings.target(new("Item"):Item(ambiguous)))
		end
		local mods={{description="+79 to maximum Life"}}
		local exact=equipmentRow(71,"Broadhead Arrow Quiver",nil,nil,mods)
		exact.implicitMods={{description="9% increased Attack Speed"}}
		local function changed(id,mutate)
			local listing=copyTable(exact)
			listing.id=string.format("%064x",id)
			mutate(listing)
			return listing
		end
		local header=changed(72,function(row) row.properties=assert(json.decode('[{"name":"Quiver","values":[]}]')) end)
		local rivals={exact,header,
			changed(73,function(row) row.explicitMods={{description="+78 to maximum Life"}} end),
			changed(74,function(row) row.implicitMods={{description="6 to 12 Added Physical Damage with Bow Attacks"}} end),
			changed(75,function(row) row.properties={property("Quality","+10%")} end),
			changed(76,function(row) row.sockets="invalid" end),
			changed(77,function(row) row.ilvl=85 end),
			changed(78,function(row) row.corrupted=true end),
			changed(79,function(row) row.sockets=sockets("R") end),
		}
		local encodedQuivers=json.encode({next_change_id="cursor",stashes={stash(71,"Quiver#0071",rivals)}})
		assert(listings.compare(encodedQuivers,target,"Covens").matched==2)
		local ornateRaw="Rarity: RARE\nFixture Quiver\nOrnate Quiver\nSockets: R\nItem Level: 86\nImplicits: 1\nHas 1 Socket\n+79 to maximum Life"
		local ornate=assert(listings.target(new("Item"):Item(ornateRaw)))
		assert(ornate.equipment.sockets=="R")
		local ornateAsk=equipmentRow(81,"Ornate Quiver",sockets("R"),nil,mods)
		ornateAsk.implicitMods={{description="Has 1 Socket"}}
		local incorrect=equipmentRow(82,"Ornate Quiver",sockets("G"),nil,mods)
		incorrect.implicitMods=ornateAsk.implicitMods
		local filled=copyTable(ornateAsk)
		filled.id=string.format("%064x",83)
		filled.socketedItems={{baseType="Empower Support"}}
		local ornatePage={next_change_id="cursor",stashes={stash(81,"Quiver#0081",{ornateAsk,incorrect,filled})}}
		assert(listings.compare(json.encode(ornatePage),ornate,"Covens").matched==1)
		file=assert(io.open(path,"wb"));assert(file:write(encodedQuivers));assert(file:close())
		gearUI:bind(build);main.popups={}
		require("Classes.LootFilterMarketBrowseControl").Open({itemsTab={orderedSlots={{slotName="Weapon 2"}},
			items={quiver},activeItemSet={["Weapon 2"]={selItemId=1}}}})
		gearUI:text("league","Covens");gearUI:click("buildTarget");gearUI:text("search","Weapon 2");gearUI:click("choose")
		gearUI:click("listingSample")
		assert(main.popups[1].title=="Comparable asking prices")
		local rows={}
		for _, line in ipairs(main.popups[1].controls.details.list) do rows[#rows+1]=StripEscapes(line[1] or "") end
		assert(table.concat(rows," "):find("2 matching rolls",1,true))
		if output then gearUI:frame():write(output.."/quiver-listing-snapshot.json") end
		local previousPaste=Paste
		Paste=function() return rawQuiver end
		main.popups={}
		require("Classes.LootFilterMarketBrowseControl").Open({})
		gearUI:text("league","Covens");gearUI:click("pasteItem");gearUI:click("listingSample")
		Paste=previousPaste
		assert(main.popups[1].title=="Comparable asking prices")
		print("Quiver pricing verifies copied and equipped rolls and excludes ambiguous legacy bases")
	end
	local armour = new("Item"):Item([[Rarity: RARE
Fixture Armour
Vaal Regalia
--------
Quality: +20%
Energy Shield: 190
--------
Sockets: B-B-B-B-R-G
--------
Item Level: 86
--------
+70 to maximum Life
]])
	local armourTarget=assert(listings.target(armour))
	assert(armourTarget.equipment.sockets=="B-B-B-B-R-G")
	assert(armourTarget.equipment.properties["Energy Shield"]==190 and armourTarget.equipment.quality==20)
	assert(not listings.target(new("Item"):Item(armour.raw:gsub("Sockets: B%-B%-B%-B%-R%-G\n",""))))
	assert(not listings.target(new("Item"):Item(armour.raw:gsub("Energy Shield: 190\n",""))))
	local defence={property("Quality","+20%"),property("Energy Shield","190")}
	local armourMods={{description="+70 to maximum Life"}}
	local candidate=equipmentRow(30,"Vaal Regalia",sockets("B-B-B-B-R-G"),defence,armourMods)
	local fewerLinks=equipmentRow(31,"Vaal Regalia",sockets("B-B-B-B-R-G",true),defence,armourMods)
	local differentColours=equipmentRow(32,"Vaal Regalia",sockets("B-B-B-B-G-G"),defence,armourMods)
	local differentDefence=equipmentRow(33,"Vaal Regalia",sockets("B-B-B-B-R-G"),
		{property("Quality","+20%"),property("Energy Shield","189")},armourMods)
	local differentQuality=equipmentRow(34,"Vaal Regalia",sockets("B-B-B-B-R-G"),
		{property("Quality","+19%"),property("Energy Shield","190")},armourMods)
	local layout={next_change_id="cursor",stashes={stash(31,"Armour#0031",
		{candidate,fewerLinks,differentColours,differentDefence,differentQuality})}}
	assert(listings.compare(json.encode(layout),armourTarget,"Covens").matched==1)

	local weapon = new("Item"):Item([[Rarity: RARE
Fixture Axe
Siege Axe
--------
Quality: +20%
--------
Sockets: R-R-G
--------
Item Level: 86
--------
70% increased Physical Damage
]])
	local weaponTarget=assert(listings.target(weapon))
	local visible=weaponTarget.equipment.properties
	assert(visible["Physical Damage"] and visible["Critical Strike Chance"] and visible["Attacks per Second"])
	local weaponProps={property("Quality","+20%"),property("Physical Damage",visible["Physical Damage"]),
		property("Critical Strike Chance",string.format("%.2f%%",visible["Critical Strike Chance"])),
		property("Attacks per Second",string.format("%.2f",visible["Attacks per Second"]))}
	local axeMods={{description="70% increased Physical Damage"}}
	local goodAxe=equipmentRow(40,"Siege Axe",sockets("RRG"),weaponProps,axeMods)
	local wrongAxe=equipmentRow(41,"Siege Axe",sockets("RRG"),copyTable(weaponProps),axeMods)
	wrongAxe.properties[2]=property("Physical Damage","1-2")
	local noAxeProps=equipmentRow(42,"Siege Axe",sockets("RRG"),{property("Quality","+20%")},axeMods)
	layout.stashes[2]=stash(41,"Weapon#0041",{goodAxe,wrongAxe,noAxeProps})
	assert(listings.compare(json.encode(layout),weaponTarget,"Covens").matched==1)
	for _, variant in ipairs({{"Carving Knife","Rune Dagger"},{"Iron Staff","Warstaff"},{"Jewelled Foil","One Handed Sword"}}) do
		local native = new("Item"):Item(weapon.raw:gsub("Siege Axe",variant[1]))
		local known = assert(listings.target(native))
		assert(known.equipment.class==variant[2],variant[1].." displayed as "..tostring(known.equipment.class))
		local combat = {property("Quality","+20%"),{name=variant[2],values=assert(json.decode("[]"))}}
		for name, value in pairs(known.equipment.properties) do combat[#combat+1]=property(name,tostring(value)) end
		local listing=equipmentRow(50,variant[1],sockets("R-R-G"),combat,axeMods)
		local variantPage={next_change_id="cursor",stashes={stash(50,"Subtype#0050",{listing})}}
		assert(listings.compare(json.encode(variantPage),known,"Covens").matched==1)
	end
	local stocked=assert(json.encode(layout))
	file=assert(io.open(path,"wb"));assert(file:write(stocked));assert(file:close())
	local chosenBuild={itemsTab={orderedSlots={{slotName="Body Armour"},{slotName="Weapon 1"}},items={armour,weapon},
		activeItemSet={["Body Armour"]={selItemId=1},["Weapon 1"]={selItemId=2}}}}
	main.popups={}
	require("Classes.LootFilterMarketBrowseControl").Open(chosenBuild)
	gearUI:text("league","Covens");gearUI:click("buildTarget");gearUI:text("search","Vaal Regalia");gearUI:click("choose")
	require("Classes.LootFilterFileBrowser").Open=function(_,selected) selected(path) end
	gearUI:click("listingSample")
	assert(main.popups[1].title=="Comparable asking prices")
	local text={}
	for _, line in ipairs(main.popups[1].controls.details.list) do text[#text+1]=StripEscapes(line[1] or "") end
	local summary=table.concat(text," ")
	assert(summary:find("Matched sockets: B-B-B-B-R-G | Quality: 20%",1,true))
	assert(summary:find("Matched properties: Energy Shield 190",1,true))
	if output then gearUI:frame():write(output.."/armour-listing-snapshot.json") end
	do
		local rawJewel="Rarity: RARE\nFixture Jewel\nCobalt Jewel\nItem Level: 86\n7% increased maximum Life"
		local jewel=new("Item"):Item(rawJewel)
		local abyss=new("Item"):Item(rawJewel:gsub("Cobalt Jewel","Ghastly Eye Jewel")
			:gsub("7%% increased maximum Life","+36 to maximum Life"))
		local abyssMods={{description="+36 to maximum Life"}}
		local exact=equipmentRow(51,"Ghastly Eye Jewel",nil,nil,abyssMods)
		exact.abyssJewel=true
		local lowerRoll=equipmentRow(52,"Ghastly Eye Jewel",nil,nil,{{description="+35 to maximum Life"}})
		local wrongChannel=equipmentRow(53,"Ghastly Eye Jewel",nil,nil,nil)
		wrongChannel.implicitMods=abyssMods
		local corrupt=equipmentRow(54,"Ghastly Eye Jewel",nil,nil,abyssMods);corrupt.corrupted=true
		local unknown=equipmentRow(55,"Ghastly Eye Jewel",nil,{property("Unverified","1")},abyssMods)
		local wrongLevel=equipmentRow(56,"Ghastly Eye Jewel",nil,nil,abyssMods);wrongLevel.ilvl=85
		local ordinary=equipmentRow(57,"Cobalt Jewel",nil,nil,{{description="7% increased maximum Life"}})
		local wrongSubtype=equipmentRow(58,"Cobalt Jewel",nil,nil,ordinary.explicitMods);wrongSubtype.abyssJewel=true
		local badFlag=equipmentRow(59,"Ghastly Eye Jewel",nil,nil,abyssMods);badFlag.fractured="unknown"
		local badInfluence=equipmentRow(60,"Ghastly Eye Jewel",nil,nil,abyssMods);badInfluence.shaper="unknown"
		local jewelPage=json.encode({next_change_id="cursor",stashes={
			stash(51,"Jewels#0051",{exact,lowerRoll,wrongChannel,corrupt,unknown,wrongLevel,ordinary,wrongSubtype,badFlag,badInfluence}),
		}})
		assert(listings.compare(jewelPage,assert(listings.target(abyss)),"Covens").matched==1)
		assert(listings.compare(jewelPage,assert(listings.target(jewel)),"Covens").matched==1)
		assert(not listings.target(new("Item"):Item(rawJewel:gsub("Cobalt Jewel","Large Cluster Jewel"))))
		local jewelBuild={itemsTab={orderedSlots={
			{slotName="Jewel 123",label="Socket",nodeId=123},{slotName="Jewel 124",label="Socket",nodeId=124},
			{slotName="Jewel 125",label="Socket",nodeId=125},{slotName="Belt Abyssal Socket",inactive=true},
		},items={abyss,jewel},activeItemSet={["Belt Abyssal Socket"]={selItemId=1}}},
			spec={allocNodes={[123]=true,[124]=true},jewels={[123]=1,[124]=1,[125]=1}}}
		local targets=require("Modules.LootFilterMarketBrowse").buildTargets(jewelBuild)
		assert(#targets==2 and targets[1].listingSocket and targets[2].listingSocket)
		assert(targets[1].label~=targets[2].label)
		file=assert(io.open(path,"wb"));assert(file:write(jewelPage));assert(file:close())
		main.popups={}
		require("Classes.LootFilterMarketBrowseControl").Open(jewelBuild)
		gearUI:text("league","Covens");gearUI:click("buildTarget");gearUI:text("search","Jewel 123");gearUI:click("choose")
		gearUI:click("listingSample")
		assert(main.popups[1].title=="Comparable asking prices")
		local details={}
		for _,line in ipairs(main.popups[1].controls.details.list) do details[#details+1]=StripEscapes(line[1] or "") end
		local summary=table.concat(details," ")
		assert(summary:find("1 matching rolls",1,true) and summary:find("Ask 50 | 1 seller",1,true),summary)
		if output then gearUI:frame():write(output.."/jewel-listing-snapshot.json") end
		print("Ordinary and Abyss jewel listing comparisons preserve roll, item state and allocated socket identity")
		local compact=headless.install({width=640,height=480})
		compact:bind(build)
		local previousPaste, clipboard = Paste, rawJewel
		Paste=function() return clipboard end
		main.popups={}
		require("Classes.LootFilterMarketBrowseControl").Open({itemsTab={}})
		local controls=main.popups[1].controls
		assert(not controls.buildTarget and not controls.listingSample:IsEnabled())
		compact:click("pasteItem")
		assert(controls.query.buf=="=Cobalt Jewel" and controls.listingSample:IsEnabled())
		if output then compact:frame():write(output.."/market-paste-target.json") end
		compact:click("listingSample")
		assert(controls.status.label:find("trade league ID",1,true))
		compact:text("league","Covens")
		compact:click("listingSample")
		assert(main.popups[1].title=="Comparable asking prices")
		local copiedDetails={}
		for _,line in ipairs(main.popups[1].controls.details.list) do copiedDetails[#copiedDetails+1]=StripEscapes(line[1] or "") end
		local copiedSummary=table.concat(copiedDetails," ")
		assert(copiedSummary:find("Copied item | Cobalt Jewel | Item level 86",1,true)
			and copiedSummary:find("Ask 50 | 1 seller",1,true),copiedSummary)
		if output then compact:frame():write(output.."/market-paste-result.json") end
		compact:click("close")
		for _, invalid in ipairs({rawJewel:gsub("RARE","MAGIC"),rawJewel:gsub("Item Level: 86\n",""),string.rep("x",24001),""}) do
			clipboard=rawJewel;compact:click("pasteItem");assert(controls.listingSample:IsEnabled())
			clipboard=invalid;compact:click("pasteItem");assert(not controls.listingSample:IsEnabled())
		end
		clipboard=rawJewel;compact:click("pasteItem")
		compact:text("query","Another item")
		assert(not controls.listingSample:IsEnabled())
		Paste=previousPaste
		compact:restore()
		print("Copied rares use the native file comparison without equipping the item or requesting market data")
	end
	do
		-- The Large layout and mod-channel shape follow the documented item fields
		-- and the Cluster Jewel in spec/System/SampleCharacter.json.
		local effect="Added Small Passive Skills grant: 12% increased Attack Damage while holding a Shield"
		local rolls={{description="Added Small Passive Skills also grant: +2% to Fire Resistance"},
			{description="1 Added Passive Skill is Heavy Hitter"}}
		local granted={"Adds 8 Passive Skills","2 Added Passive Skills are Jewel Sockets",effect}
		local rawCluster="Item Class: Jewels\nRarity: Rare\nFixture Cluster\nLarge Cluster Jewel\n--------\nItem Level: 84\n--------\n"
			..table.concat(granted," (enchant)\n").." (enchant)\n--------\n"..rolls[1].description.."\n"..rolls[2].description
			.."\n1 Added Passive Skill is Storm Drinker (fractured)\n--------\nFractured Item"
		local cluster=new("Item"):Item(rawCluster)
		local clusterTarget=assert(listings.target(cluster))
		assert(clusterTarget.cluster.passives==8 and clusterTarget.cluster.sockets==2)
		for _, invalid in ipairs({
			rawCluster:gsub("Adds 8 Passive Skills %(enchant%)\n",""),
			rawCluster:gsub("Adds 8 Passive Skills","Adds 13 Passive Skills"),
			rawCluster:gsub("2 Added Passive Skills are Jewel Sockets","1 Added Passive Skill is a Jewel Socket"),
			(rawCluster:gsub("Item Level: 84","Cluster Jewel Node Count: 9\nItem Level: 84")),
		}) do
			assert(not listings.target(new("Item"):Item(invalid)),"Incomplete or contradictory Cluster layout")
		end
		local smallBonus="Added Small Passive Skills grant: 4% increased maximum Life"
		local mediumBonus="Added Small Passive Skills grant: 10% increased Damage while affected by a Herald"
		local small="Rarity: RARE\nFixture Small Cluster\nSmall Cluster Jewel\nItem Level: 84\n"
			.."Adds 2 Passive Skills (enchant)\n"..smallBonus.." (enchant)\n"..rolls[1].description
		local medium="Rarity: RARE\nFixture Medium Cluster\nMedium Cluster Jewel\nItem Level: 84\n"
			.."Adds 4 Passive Skills (enchant)\n1 Added Passive Skill is a Jewel Socket (enchant)\n"..mediumBonus.." (enchant)\n"..rolls[1].description
		assert(assert(listings.target(new("Item"):Item(small))).cluster.sockets==0)
		assert(assert(listings.target(new("Item"):Item(medium))).cluster.sockets==1)
		local function clusterRow(id, enchants, explicit)
			local listing=equipmentRow(id,"Large Cluster Jewel",nil,nil,explicit or rolls)
			listing.ilvl=84;listing.fractured=true
			listing.enchantMods=enchants
			listing.fracturedMods={"1 Added Passive Skill is Storm Drinker"}
			return listing
		end
		local exact=clusterRow(61,granted)
		local differentCount=clusterRow(62,{"Adds 9 Passive Skills",granted[2],effect})
		local differentSocket=clusterRow(63,{granted[1],"1 Added Passive Skill is a Jewel Socket",effect})
		local differentEffect=clusterRow(64,{granted[1],granted[2],mediumBonus})
		local differentNotable=clusterRow(65,granted,{rolls[1],{description="1 Added Passive Skill is Prodigious Defence"}})
		local incomplete=clusterRow(66,{granted[1],granted[2]})
		local wrongLevel=clusterRow(67,granted);wrongLevel.ilvl=83
		local missingFracture=clusterRow(68,granted);missingFracture.fractured=nil
		local snapshot=json.encode({next_change_id="cursor",stashes={stash(62,"Clusters#0062",
			{exact,differentCount,differentSocket,differentEffect,differentNotable,incomplete,wrongLevel,missingFracture})}})
		assert(listings.compare(snapshot,clusterTarget,"Covens").matched==1)
		file=assert(io.open(path,"wb"));assert(file:write(snapshot));assert(file:close())
		local clusterBuild={itemsTab={orderedSlots={{slotName="Jewel 321",nodeId=321}},items={cluster}},
			spec={allocNodes={[321]=true},jewels={[321]=1}}}
		main.popups={}
		require("Classes.LootFilterMarketBrowseControl").Open(clusterBuild)
		gearUI:text("league","Covens");gearUI:click("buildTarget");gearUI:text("search","Jewel 321");gearUI:click("choose")
		gearUI:click("listingSample")
		assert(main.popups[1].title=="Comparable asking prices")
		local details={}
		for _,line in ipairs(main.popups[1].controls.details.list) do details[#details+1]=StripEscapes(line[1] or "") end
		local summary=table.concat(details," ")
		assert(summary:find("Passive layout: 8 passives | 2 jewel sockets",1,true) and summary:find("1 matching rolls",1,true),summary)
		if output then gearUI:frame():write(output.."/cluster-listing-snapshot.json") end
		print("Rolled Cluster Jewel listings distinguish passive layouts, notable rolls, and state")
	end
	require("Classes.LootFilterFileBrowser").Open=originalPicker
	os.remove(path)
	launch.DownloadPage=oldDownload
	print("Rolled equipment excludes mismatched links, quality, displayed defences and weapon stats")
end


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
	local waitingPopup=main.popups[1]
	harness:resize(640,480);harness:frame()
	assert(main.popups[1]==waitingPopup,"Resize must not discard a pending league request")
	market.endpoint=endpoint.."changed/"
	pending(reply)
	assert(main.popups[1].title=="Choose league" and saved=="Retired League")
	market.endpoint=endpoint
	harness:click("close")
	harness:resize(960,640);harness:frame()
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
	testPreviewStack(harness)
	assert(saved=="Retired League" and saves==0)
	harness:click("reviewAction")
	assert(main.popups[1].title=="Daily filter sync" and saved=="New League" and saves==1)
	sync.configuration,sync.preview,sync.configure,launch.DownloadPage=oldConfig,oldPreview,oldConfigure,oldDownload
end

checkReviewedRolloverControls()
print("Native league selection and preview keep the current profile until explicit review approval")

do
	newBuild();main.popups={};reviewFixture=nil
	local compact=headless.install({width=640,height=480});compact:bind(build)
	require("Classes.LootFilterDailySyncControl").Open()
	local controls=main.popups[1].controls
	local function visibleControlsFit()
		for key,control in pairs(controls) do if control:IsShown() then
			local x,y=control:GetPos();local w,h=control:GetSize()
			assert(x>=0 and y>=0 and x+w<=640 and y+h<=480,key.." leaves the compact window")
		end end
	end
	assert(controls.target:IsShown() and not controls.observedStack:IsShown())
	compact:text("target","C:/PoE/compact.filter")
	visibleControlsFit()
	if output then compact:frame():write(output.."/640-filter-sync-setup.json") end
	compact:click("actionsPage")
	assert(not controls.target:IsShown() and controls.observedStack:IsShown())
	visibleControlsFit()
	local _,bottom=controls.observedStack:GetPos();local _,buttonHeight=controls.observedStack:GetSize()
	local _,helpTop=controls.backgroundHelp:GetPos()
	assert(helpTop>=bottom+buttonHeight,"Background help overlaps the action buttons")
	assert(StripEscapes(controls.backgroundHelp.list[1][1]):find("Windows.",1,true),"Background help must fit on the page")
	if output then compact:frame():write(output.."/640-filter-sync-actions.json") end
	compact:click("pickupPolicy")
	assert(main.popups[1].title=="Pickup policy")
	compact:click("cancel")
	compact:click("setupPage")
	assert(controls.target.buf=="C:/PoE/compact.filter","Page navigation lost the draft")
	compact:click("close")
	compact:restore()
end

do
	newBuild();main.popups={};reviewFixture=nil
	local resized=headless.install({width=960,height=640});resized:bind(build)
	require("Classes.LootFilterDailySyncControl").Open()
	resized:text("target","C:/PoE/resize-draft.filter")
	local draft=main.popups[1].controls.target
	main.popups[1]:SelectControl(main.popups[1].controls.target)
	draft.buf="C:/PoE/resize-edited.filter";draft.caret=8;draft.sel=4;draft:AddUndoState()
	local waitingPopup=main.popups[1]
	sync.busy={};resized:resize(640,480);resized:frame()
	assert(main.popups[1]==waitingPopup,"Resize must not discard a pending sync preview")
	sync.busy=nil;resized:frame();resized:frame()
	local controls=main.popups[1].controls
	assert(#main.popups==1 and controls.actionsPage and controls.target.buf=="C:/PoE/resize-edited.filter")
	assert(main.popups[1].selControl==controls.target,"Resize lost the focused draft field")
	assert(controls.target.caret==8 and controls.target.sel==4,"Resize lost the selection")
	controls.target:Undo();assert(controls.target.buf=="C:/PoE/resize-draft.filter","Resize lost undo history")
	controls.target:Redo();assert(controls.target.buf=="C:/PoE/resize-edited.filter","Resize lost redo history")
	resized:click("actionsPage")
	resized:click("pickupPolicy");resized:text("campaign","1.5");resized:click("apply")
	local x,y=controls.observedStack:GetPos();local w,h=controls.observedStack:GetSize()
	assert(x>=0 and y>=0 and x+w<=640 and y+h<=480,"Resized action left the window")
	resized:resize(960,640);resized:frame();resized:frame()
	controls=main.popups[1].controls
	assert(#main.popups==1 and not controls.actionsPage and controls.target.buf=="C:/PoE/resize-edited.filter")
	resized:resize(640,480);resized:frame();resized:frame()
	controls=main.popups[1].controls
	assert(controls.observedStack:IsShown() and controls.target.buf=="C:/PoE/resize-edited.filter","Resize lost the selected page or draft")
	resized:click("pickupPolicy")
	assert(main.popups[1].controls.campaign.buf=="1.5","Resize lost the draft pickup policy")
	resized:click("cancel")
	resized:click("close");resized:restore()
end

do
	newBuild();main.popups={}
	local profile = require("Modules.LootFilters").profile("rare-policy","Rare policy")
	profile.template = [[# CUSTOM: Highlight item tier 5 rare equipment on rank A and B bases
Show
    Rarity Rare
    Identified False
    UnidentifiedItemTier 5
    Class == "Body Armours"
    BaseType == "Royal Plate"
Show # Named exception
    BaseType == "Plate Vest"
Hide
]]
	local saved = build.savers.LootFilters
	saved:Replace({schemaVersion=1,activeId=profile.id,profiles={profile}})
	local fingerprint = require("Modules.PlanningData").hash(saved.data)
	local auditUI = headless.install({width=720,height=600})
	auditUI:bind(build)
	build.planningWorkspace = require("Modules.PlanningWorkspace").new(build)
	build.viewMode = "PLANNER"
	build.planningWorkspace:Show("filters")
	local function openAudit()
		auditUI:click("manage")
		auditUI:text("search","Tier 5 rare exceptions")
		auditUI:click("choose")
		assert(main.popups[1].controls.status)
	end
	local function finishAudit()
		for _=1,600 do
			auditUI:frame()
			if main.popups[1] and main.popups[1].controls.results then break end
		end
		assert(main.popups[1].controls.results,"Audit did not finish")
	end
	openAudit()
	auditUI:click("close")
	auditUI:frame(build)
	assert(not main.popups[1],"Cancellation still opened audit results")
	openAudit()
	finishAudit()
	auditUI:text("search","Plate Vest")
	local dialog = main.popups[1].controls
	local details = {}
	for _, row in ipairs(dialog.details.list) do details[#details+1]=StripEscapes(row[1] or "") end
	local description = table.concat(details," ")
	assert(description:find("Show at compiled filter line",1,true) and description:find("Named exception",1,true),description)
	if output then auditUI:frame():write(output.."/720-rare-tier-exceptions.json") end
	auditUI:click("choose")
	local snapshot = build.planningWorkspace.cache.filters.layout.snapshot()
	assert(snapshot.page=="Simulate" and snapshot.sample.BaseType=="Plate Vest" and snapshot.sample.UnidentifiedItemTier==5)
	assert(require("Modules.PlanningData").hash(saved.data)==fingerprint)

	local getSources = sync.verifiedFilterPair
	sync.verifiedFilterPair = function(id)
		assert(id==namedId)
		return profile.template,profile.template:gsub("Named exception","Verified exception")
	end
	reviewFixture={hour=9,target=selected,league="Covens",enabled=true,lastSuccess=os.time()}
	auditUI:resize(640,480)
	require("Classes.LootFilterDailySyncControl").Open(namedId,"Covens test")
	auditUI:click("actionsPage")
	if output then auditUI:frame():write(output.."/640-daily-rare-action.json") end
	for _, source in ipairs({{"Verified filter","verified filter","Verified exception"},{"Fixed baseline","fixed baseline","Named exception"}}) do
		auditUI:click("rareExceptions")
		auditUI:text("search",source[1])
		auditUI:click("choose")
		finishAudit()
		auditUI:text("search","Plate Vest")
		local controls=main.popups[1].controls
		local rows={}
		for _,row in ipairs(controls.details.list) do rows[#rows+1]=StripEscapes(row[1] or "") end
		local report=table.concat(rows," ")
		assert(report:find(source[1],1,true) and report:find("Show at "..source[2].." line",1,true) and report:find(source[3],1,true),report)
		assert(not controls.choose:IsShown(),"A local-file audit must stay in the sync dialog")
		if output and source[1]=="Verified filter" then auditUI:frame():write(output.."/640-daily-rare-audit.json") end
		auditUI:click("close")
	end
	sync.verifiedFilterPair=getSources
	reviewFixture=nil
	auditUI:click("close")
	auditUI:restore()
	print("Tier 5 rare exceptions inspect the compiled profile, fixed baseline and verified filter with source-specific rule lines.")
end
