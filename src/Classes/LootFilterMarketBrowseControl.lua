local market = require("Modules.LootFilterEconomy")
local browse = require("Modules.LootFilterMarketBrowse")
local ui = require("Modules.PlanningUI")
local sync = require("Modules.LootFilterDailySync")
local M = {}

local function openTradeSearch(league, query)
	local encoded = require("Classes.TradeHelpers").B64GzipEncode(assert(require("dkjson").encode(query)))
	OpenURL("https://www.pathofexile.com/trade/search/"..urlEncode(league).."/"..encoded)
end

local function openExactBase(target,league)
	local level = target.itemLevel
	local query = {type=target.name,status={option="available"},
		stats={{type="and",filters={}}},filters={misc_filters={filters={ilvl={min=level,max=level}}}}}
	if target.baseImplicit then query.stats[1].filters[1]={id=target.baseImplicit} end
	openTradeSearch(league,query)
end

local function reviewTradeRolls(target, league, compare, pinned)
	local rolls = browse.tradeRolls(target)
	local openReview
	local function edit(row)
		local width = math.min(490,main.screenW-40)
		local c = {}
		ui.description(c,"modifier",16,16,width-32,42,{row.line},14)
		ui.label(c,"minLabel",16,68,"Minimum",14)
		ui.label(c,"maxLabel",width/2,68,"Maximum",14)
		c.minimum = new("EditControl"):EditControl(ui.anchor,{16,90,width/2-28,28},tostring(row.minimum or ""),"Any",nil,16)
		c.maximum = new("EditControl"):EditControl(ui.anchor,{width/2,90,width/2-16,28},tostring(row.maximum or ""),"Any",nil,16)
		c.apply = new("ButtonControl"):ButtonControl(ui.anchor,{16,140,132,28},"Apply bounds",function()
			local minimum = c.minimum.buf=="" and nil or tonumber(c.minimum.buf)
			local maximum = c.maximum.buf=="" and nil or tonumber(c.maximum.buf)
			local function valid(text, value) return text=="" or value and math.abs(value)<=1000000 end
			if not valid(c.minimum.buf,minimum) or not valid(c.maximum.buf,maximum) or minimum and maximum and minimum>maximum then
				main:OpenMessagePopup("Trade roll bounds","Enter valid bounds in order, or leave either field blank.")
				return
			end
			row.minimum,row.maximum,row.enabled = minimum,maximum,true
			main:ClosePopup()
			main:ClosePopup()
			openReview()
		end)
		c.toggle = new("ButtonControl"):ButtonControl(ui.anchor,{158,140,132,28},row.enabled and "Exclude filter" or "Include filter",function()
			row.enabled = not row.enabled
			main:ClosePopup()
			main:ClosePopup()
			openReview()
		end)
		c.close = new("ButtonControl"):ButtonControl(ui.anchor,{width-126,140,110,28},"Cancel",function() main:ClosePopup() end)
		ui.style(c,{apply=true})
		main:OpenPopup(width,188,"Trade roll bounds",c,nil,"minimum","close")
	end
	openReview = function()
		local query = browse.rolledTradeQuery(target,rolls)
		local filters = query.stats[1].filters
		local matchesRolls = browse.listingRollMatcher(filters)
		local socketFilters = query.filters.socket_filters
		local info = {target.base,league.." | Identified rare | Item level "..target.level,
			target.corrupted and "Corrupted" or "Uncorrupted",
			string.format("%d of %d item modifiers included",#filters,#rolls),
		}
		if socketFilters then
			info[#info+1]=string.format("Sockets: %d | Largest link group: %d",
				socketFilters.filters.sockets.min,socketFilters.filters.links.min)
		end
		info[#info+1]="Check influences, socket colors, and other item details in the Trade results."
		info[#info+1]=matchesRolls and "Local comparisons also match item properties and base or layout identifiers."
			or "Include a supported modifier to compare a local listing file."
		local entries = {{id="summary",category="Search",label="Trade search for "..target.base,details=info}}
		for index, row in ipairs(rolls) do
			local filter = row.enabled and "Included" or row.id and "Excluded" or "Unavailable"
			local bounds = row.numeric and ("Minimum "..tostring(row.minimum or "any").." | Maximum "..tostring(row.maximum or "any"))
				or "Match modifier presence"
			entries[#entries+1] = {id=tostring(index),label=row.line,category=filter,roll=row,
				details={row.line,row.kind,filter,row.reason or bounds}}
		end
		require("Classes.PlanningBrowserControl").Open("Review Trade search",entries,{
			action="Edit or toggle",closeOnChoose=false,enterChooses=false,
			canChoose=function(entry) return entry.roll and entry.roll.id~=nil end,
			choose=function(entry)
				if entry.roll.numeric then edit(entry.roll); return end
				entry.roll.enabled = not entry.roll.enabled
				main:ClosePopup()
				openReview()
			end,
			secondary={label="Open official Trade",run=function() openTradeSearch(league,query) end},
			tertiary={label=pinned and "Compare saved capture" or "Compare listing file",canRun=function() return matchesRolls~=nil end,
				run=function() compare(filters) end},
		})
	end
	openReview()
end

local function showMarketDetails(entry, title, review)
	local width = math.min(500,main.screenW-40)
	local lines = {entry.label}
	for _, detail in ipairs(entry.details) do lines[#lines+1] = detail end
	local rows = ui.rows(lines,width-50,14)
	local contentHeight = 0
	for _, row in ipairs(rows) do contentHeight = contentHeight+row.height end
	local height = math.min(main.screenH-40,contentHeight+80)
	local controls = {
		details=new("TextListControl"):TextListControl(ui.anchor,{16,18,width-32,height-72},nil,rows),
		close=new("ButtonControl"):ButtonControl(ui.anchor,{width-136,height-42,120,28},"Close",function()
			main:ClosePopup()
		end),
	}
	if review then
		controls.review=new("ButtonControl"):ButtonControl(ui.anchor,{16,height-42,158,28},"Review roll filters",function()
			main:ClosePopup()
			review()
		end)
	end
	ui.style(controls,{close=true})
	main:OpenPopup(width,height,title,controls,nil,nil,"close")
end

local function showListingSample(target, league, sample, filterCount, review)
	local details = {
		league .. " | Local public stash listing sample",
		string.format("%d same-base listings checked | %d matching %s",sample.inspected,sample.matched,
			filterCount and "listings" or "rolls"),
		string.format("%d matching listings with a supported asking price",sample.priced),
	}
	if filterCount then
		details[#details+1]=string.format("Filtered comparison | %d selected modifier %s",filterCount,filterCount==1 and "filter" or "filters")
	end
	local equipment = target.listingItem.equipment
	local cluster = target.listingItem.cluster
	local seed = target.listingItem.blightcore
	if seed then
		details[#details+1] = "Granted passives in order"
		for index, name in ipairs(seed) do details[#details+1]=index..". "..name end
	end
	if cluster then
		details[#details+1] = string.format("Passive layout: %d passives | %d jewel socket%s",
			cluster.passives,cluster.sockets,cluster.sockets==1 and "" or "s")
	end
	if equipment then
		details[#details+1] = string.format("Matched sockets: %s | Quality: %d%%",
			equipment.sockets=="" and "None" or equipment.sockets,equipment.quality)
		local properties = {}
		for name, value in pairsSortByKey(equipment.properties) do properties[#properties+1]=name.." "..value end
		if #properties>0 then details[#details+1] = "Matched properties: "..table.concat(properties,", ") end
	end
	local capture = sample.capture
	if capture then
		details[#details+1] = "Declared PC capture | "..os.date("!%Y-%m-%d %H:%M UTC",capture.capturedAt)
		local minutes=math.max(0,math.floor((os.time()-capture.capturedAt)/60))
		details[#details+1] = string.format("Capture age: %d min%s",minutes,minutes>=60 and " | Over one hour old" or "")
		details[#details+1] = string.format("Pages: %d | Stash updates: %d | Withdrawals: %d",capture.pages,capture.updated,capture.withdrawn)
		if capture.conflicts>0 then details[#details+1]=string.format("%d conflicting stash changes excluded",capture.conflicts) end
	end
	if sample.ambiguous>0 then details[#details+1]=string.format("%d conflicting listing IDs excluded",sample.ambiguous) end
	for _, row in ipairs(sample.results) do
		if row.sellers>0 then
			local range = row.low==row.high and string.format("Ask %.4g",row.low)
				or string.format("Range %.4g to %.4g",row.low,row.high)
			local estimate = row.median and string.format(" | Median %.4g",row.median) or ""
			local sellers = row.sellers==1 and "1 seller" or (row.sellers.." sellers")
			local note = row.median and "" or " (three needed for a median)"
			details[#details+1] = row.currency..estimate.." | "..range.." | "..sellers..note
		end
	end
	details[#details+1] = capture and "Asking prices from a partial stream. Live availability and sales are unverified."
		or "Asking prices from this file. Realm, age and completed sales are unverified."
	showMarketDetails({label=target.label,details=details},"Comparable asking prices",review)
end

local function compareListingFile(target, league, filters)
	require("Classes.LootFilterFileBrowser").Open(nil,function(path)
		local matchesRolls=filters and browse.listingRollMatcher(filters)
		local ok,sample=pcall(require("Modules.LootFilterGearListings").compareFile,path,target.listingItem,league,matchesRolls)
		if ok then showListingSample(target,league,sample,filters and #filters)
		else ui.errorPopup("Comparable asking prices",sample) end
	end,{title="Choose a public stash JSON file",itemLabel="Snapshot",category="Snapshots",
		accept=function(name) return name:lower():match("%.json$")~=nil end})
end

local savedCaptureWorker = [=[
local ok, result=pcall(function(path,league,encoded)
	local json=require("dkjson")
	local request=assert(json.decode(encoded))
	local matchesRolls=request.filters and require("Modules.LootFilterMarketBrowse").listingRollMatcher(request.filters)
	local sample=require("Modules.LootFilterGearListings").compareFile(path,request.target,league,matchesRolls,true)
	return assert(json.encode(sample))
end,...)
return ok,tostring(result)
]=]

local function compareSavedCapture(path,target,league,filters,stillCurrent,review)
	local json=require("dkjson")
	local host=main.popups[1]
	if host.savedCaptureJob then return end
	local request=assert(json.encode({target=target.listingItem,filters=filters}))
	host.savedCaptureJob=LaunchSubScript(savedCaptureWorker,"","",path,league,request)
	if not host.savedCaptureJob then
		ui.errorPopup("Comparable asking prices","Could not start the saved capture comparison.")
		return
	end
	launch:RegisterSubScript(host.savedCaptureJob,function(ok,result)
		host.savedCaptureJob=nil
		if main.popups[1]~=host or stillCurrent and not stillCurrent() then return end
		if not ok then ui.errorPopup("Comparable asking prices",result);return end
		local sample=json.decode(result)
		if sample then showListingSample(target,league,sample,filters and #filters,review)
		else ui.errorPopup("Comparable asking prices","The saved capture returned no result.") end
	end)
end

local function openTradeHistory(savedLeague)
	local exchange = require("Modules.LootFilterExchangeCrossCheck")
	local realms = {{id="pc",name="PC"},{id="xbox",name="Xbox"},{id="sony",name="PlayStation"}}
	local width = math.min(540,main.screenW-40)
	local controls = {}
	local busy, popup
	ui.label(controls,"realmLabel",16,22,"Trade realm",14)
	controls.realm = new("DropDownControl"):DropDownControl(ui.anchor,{16,46,width-32,28},{"PC","Xbox","PlayStation"})
	ui.label(controls,"leagueLabel",16,86,"Trade league ID",14)
	controls.league = new("EditControl"):EditControl(ui.anchor,{16,110,width-32,26},savedLeague,"All leagues with trades",nil,80)
	ui.description(controls,"help",16,148,width-32,46,{
		"Browse completed direct-chaos trades from GGG. Leave the league blank to browse all leagues with trades in the selected realm.",
	},14)
	ui.label(controls,"status",16,201,"",14)
	local function status(message) controls.status.label=ui.fit(message,width-32,14) end
	controls.load = new("ButtonControl"):ButtonControl(ui.anchor,{16,230,172,28},"Load completed hour",function()
		local name = controls.league.buf:match("^%s*(.-)%s*$")
		if name~="" and not market.tradeLeague({id=name,name=name}) then status("Enter a valid trade league ID."); return end
		if launch.noSSL then status("Enable HTTPS certificate verification first."); return end
		local realm = realms[controls.realm.selIndex or 1]
		local hour = exchange.hour(os.time())
		busy=true
		status("Loading completed trades for "..realm.name.."...")
		exchange.fetch(hour,function(markets, err)
			busy=false
			if main.popups[1]~=popup then return end
			if not markets then status(ui.errorText(err)); return end
			local entries = {}
			local period = os.date("!%Y-%m-%d %H:%M UTC",hour)
			for _, quote in ipairs(exchange.review(markets,name~="" and name or nil)) do
				entries[#entries+1] = {
					id=tostring(#entries+1),category="League "..quote.league,search=quote.league,
					label=name=="" and (quote.name.." | "..quote.league) or quote.name,
					details={quote.name,realm.name.." | "..quote.league,"Completed hour beginning "..period,
						string.format("Average %.4g chaos per item",quote.price),
						string.format("%d items traded for %.0f chaos",quote.count,quote.chaosVolume)},
				}
			end
			if #entries==0 then status("No matching direct-chaos trades meet the liquidity thresholds."); return end
			status("Loaded "..#entries.." liquid completed trade pairs.")
			require("Classes.PlanningBrowserControl").Open(realm.name.." completed trades",entries)
		end,realm.id)
	end)
	controls.realm.enabled = function() return not busy end
	controls.league.enabled = function() return not busy end
	controls.load.enabled = function() return not busy end
	controls.close = new("ButtonControl"):ButtonControl(ui.anchor,{width-136,230,120,28},"Close",function() main:ClosePopup() end)
	ui.style(controls)
	popup = main:OpenPopup(width,276,"GGG trade history",controls,nil,nil,"close")
end

local function open(build, managedTarget, overlay)
	local width = math.min(680,main.screenW-40)
	local actionWidth = math.floor((width-48)/3)
	local controls = {}
	local busy, popup, target, quoteOnOpen
	ui.label(controls,"leagueLabel",16,24,"PC trade league ID",14)
	controls.league=new("EditControl"):EditControl(ui.anchor,{16,50,width-32,26},overlay and overlay.league or "",
		"Current trade league",nil,80)
	local options={}
	for i, category in ipairs(browse.categories) do options[i]=category.label end
	controls.category=new("DropDownControl"):DropDownControl(ui.anchor,{16,98,width-32,28},options)
	ui.label(controls,"queryLabel",16,138,"Item name, base or variant",14)
	controls.query=new("EditControl"):EditControl(ui.anchor,{16,160,width-32,26},"","Search prices",nil,201)
	ui.description(controls,"help",16,196,width-32,44,{"Start with = to match an exact name, base or price ID."},14)
	ui.label(controls,"status",16,250,"",14)
	local function status(label) controls.status.label=ui.fit(label,width-32,14) end
	local function clearTarget()
		if target then target=nil; status("") end
	end
	controls.category.selFunc = clearTarget
	controls.query.changeFunc = clearTarget
	local buildTargets = build and browse.buildTargets(build) or {}
	local canSearchBase
	for _, entry in ipairs(buildTargets) do
		canSearchBase = canSearchBase or entry.itemLevel~=nil
	end
	local function selectTarget(entry, message)
		for index, category in ipairs(browse.categories) do
			if category.id==entry.category then controls.category:SetSel(index); break end
		end
		controls.query:SetText("="..entry.name)
		target = entry
		status(message)
	end
	if #buildTargets>0 then
		controls.buildTarget = new("ButtonControl"):ButtonControl(ui.anchor,{162,282,152,28},"From build",function()
			require("Classes.PlanningBrowserControl").Open("Compare a build item",buildTargets,{
				action="Use item",
				choose=function(entry)
					selectTarget(entry,entry.imbuedSupport and "Comparing gem and support; listed level or quality must agree."
						or entry.level and string.format("Matching level %g and %g%% quality.",entry.level,entry.quality)
						or entry.listingItem and "Choose a league and a public stash JSON file to compare rolls."
						or entry.itemLevel and ("Build item level "..entry.itemLevel..". Enter a league to search exact listings.")
						or entry.details[1])
				end,
			})
		end)
		controls.buildTarget.enabled = function() return not busy end
	end
	if canSearchBase then
		controls.exactBase=new("ButtonControl"):ButtonControl(ui.anchor,{32+2*actionWidth,320,actionWidth,28},"Search exact base",function()
			local league=controls.league.buf:match("^%s*(.-)%s*$")
			if not league:match("^[%w _-]+$") then status("Enter a valid league ID to search official trade."); return end
			openExactBase(target,league)
		end)
		controls.exactBase.enabled=function() return not busy and target and target.itemLevel~=nil end
	end
	if not managedTarget then
		local tradeX, tradeY = 322, 282
		if width<576 then tradeX, tradeY=16,358 end
		controls.tradeHistory=new("ButtonControl"):ButtonControl(ui.anchor,{tradeX,tradeY,116,28},"GGG trades",function()
			openTradeHistory(controls.league.buf:match("^%s*(.-)%s*$"))
		end)
		controls.tradeHistory.enabled = function() return not busy end
		local function selectCopiedItem(raw)
			clearTarget()
			if type(raw)~="string" or #raw>24000 or not raw:find("%S") then
				status("Copy one identified rare item or an anointed Putrid Seed first.")
				return
			end
			local ok, comparison, base, reason = pcall(function()
				local item = new("Item"):Item(raw)
				local target, unavailable = browse.listingTargetForItem(item)
				return target,item.baseName,unavailable
			end)
			if not ok or not comparison then
				local entry=overlay and browse.overlayTarget(raw)
				if entry then
					selectTarget(entry,"Item copied. Checking the chosen market category.")
					quoteOnOpen=true
					return
				end
				status(reason or "The copied item lacks comparable rolls or supported equipment properties.")
				return
			end
			local seed = comparison.blightcore
			local name = seed and "Putrid Seed" or comparison.base
			selectTarget({name=name,category=seed and "UniqueJewel" or comparison.cluster and "ClusterJewel" or "BaseType",
				listingItem=comparison,label="Copied item | "..(seed and name or base).." | Item level "..comparison.level,
				details={seed and "A listing file compares this jewel's granted passives in order."
					or "Market estimates are for the base. Compare a listing file for matching item rolls."}},
				"Item copied. Choose a league and compare a public stash JSON file.")
		end
		if not overlay then
			controls.pasteItem=new("ButtonControl"):ButtonControl(ui.anchor,{16,320,actionWidth,28},"Paste item",function()
				selectCopiedItem(Paste())
			end)
			controls.pasteItem.enabled = function() return not busy end
			if require("ffi").os=="Windows" then
				controls.overlay=new("ButtonControl"):ButtonControl(ui.anchor,{32+actionWidth*2,358,actionWidth,28},"Trade overlay",function()
					SpawnProcess(GetRuntimePath().."/Path of Building.exe","--trade-overlay")
				end)
				controls.overlay.enabled = function() return not busy end
			end
		else
			selectCopiedItem(overlay.raw)
		end
		controls.listingSample=new("ButtonControl"):ButtonControl(ui.anchor,{24+actionWidth,320,actionWidth,28},"Compare listing file",function()
			local league=controls.league.buf:match("^%s*(.-)%s*$")
			if not league:match("^[%w _-]+$") then status("Enter the trade league ID for the listing file."); return end
			compareListingFile(target,league)
		end)
		controls.listingSample.enabled=function() return not busy and target and target.listingItem~=nil end
		controls.rolledTrade = new("ButtonControl"):ButtonControl(ui.anchor,{24+actionWidth,358,actionWidth,28},"Review Trade search",function()
			local league=controls.league.buf:match("^%s*(.-)%s*$")
			if not league:match("^[%w _-]+$") then status("Enter a valid league ID to search official trade."); return end
			local selected=target
			local pinned=overlay and overlay.snapshot
			reviewTradeRolls(selected.listingItem,league,function(filters)
				if pinned then compareSavedCapture(pinned,selected,league,filters)
				else compareListingFile(selected,league,filters) end
			end,pinned)
		end)
		controls.rolledTrade.enabled=function() return not busy and target and target.listingItem~=nil and not target.listingItem.blightcore end
	end
	controls.get=new("ButtonControl"):ButtonControl(ui.anchor,{16,282,138,28},"Show prices",function()
		if busy then return end
		if not market.endpoint then status(market.endpointError); return end
		if launch.noSSL then status("Enable HTTPS certificate verification first."); return end
		local league=controls.league.buf:match("^%s*(.-)%s*$")
		if league~="" and not league:match("^[%w%s_-]+$") then status("Enter a valid league ID."); return end
		local category=browse.categories[controls.category.selIndex or 1]
		local query=controls.query.buf:match("^%s*(.-)%s*$")
		local comparable = target
		local advisory=browse.advisory(category)
		if advisory and #query:gsub("^=%s*","")<2 then
			status("Enter at least two characters to search this category.")
			return
		end
		busy=true
		local function finish(message)
			busy=false
			status(message)
		end
		local function waitMessage(wait)
			return string.format("Market provider cooldown. Try again in %d minutes.",math.ceil(wait/60))
		end
		local function request(path,callback)
			local wait = sync.providerWait(os.time())
			if wait>0 then finish(waitMessage(wait)); return end
			launch:DownloadPage(market.endpoint..path,function(response,err)
				local code = err and tonumber(err:match("^Response code: (%d+)$"))
				local delay = sync.noteProviderLimit(response,code,os.time())
				if main.popups[1]~=popup then busy=false;return end
				if delay then finish(waitMessage(delay)); return end
				if code==401 or code==403 then finish("Market provider denied access to this feed."); return end
				if err or not response then finish("Market request failed. Try again later."); return end
				callback(response)
			end,{followRedirects=false,timeout=20,maxBytes=path=="leagues" and 65536
				or comparable and comparable.managed and market.maxFeedBytes(category.id) or browse.maxBytes,header="Accept: application/json"})
		end
		local function prices()
			status("Fetching "..category.label:lower().." for "..league.."...")
			local route=category.feed=="exchange" and "exchange/current/overview" or "stash/current/item/overview"
			request(route.."?league="..urlEncode(league).."&type="..category.id,function(response)
				local ok,body,age=pcall(sync.fresh,response,os.time())
				if not ok then finish("Market response is unavailable or stale.");return end
				local catalogue = main.uniqueDB and not main.uniqueDB.loading and main.uniqueDB.list
				local valid,rows
				local managedState
				if comparable and comparable.managed then
					local result
					valid,result=pcall(browse.managedQuote,body,comparable)
					if not valid then finish(ui.errorText(result));return end
					managedState=result.state
					local messages={empty="The selected feed has no current price rows.",missing="No quote matches this managed rule exactly.",
						ambiguous="The exact managed quote is ambiguous."}
					if messages[managedState] then finish(messages[managedState]);return end
					rows={result.row}
				else
					valid,rows=pcall(browse.rows,body,category,query,comparable,catalogue)
					if not valid then finish(ui.errorText(rows));return end
				end
				local entries={}
				for i,row in ipairs(rows) do
					if i>1000 then break end
				local price
				if row.conflicting then price=advisory and "Conflicting price or variant evidence" or "Conflicting quotes for this price ID"
				elseif row.ambiguous then price="Ambiguous exchange name"
				else price=string.format("%.4g chaos estimated",row.price) end
				local details={price,"Response age: "..math.ceil(age/60).." minutes"}
				if comparable and not row.conflicting and not row.partialGemMatch then
					details[#details+1] = comparable.details[#comparable.details]
				end
				if category.id=="BaseType" and not row.conflicting then
					if comparable and comparable.itemLevel then details[#details+1]="Build item level: "..comparable.itemLevel end
					details[#details+1]="The market feed does not verify the item's level."
				end
				if row.partialGemMatch and not row.conflicting then
					details[#details+1]="Advisory match: exact gem name and Imbued support. Any listed level or quality agrees with the build."
					local missing={}
					if row.gemLevel==nil then missing[#missing+1]="level" end
					if row.gemQuality==nil then missing[#missing+1]="quality" end
					if row.corrupted==nil then missing[#missing+1]="corruption" end
					details[#details+1]="Not provided by this quote: "..table.concat(missing,", ")..". Compare the actual item before valuing it."
				end
					local function show(label,value)
						if value then details[#details+1]=label..tostring(value) end
					end
				show("Price ID: ",row.identity)
				if category.feed=="exchange" and not row.ambiguous and not row.supported then
					details[#details+1]="Quoted chaos volume is below this category's liquidity threshold."
				end
				if not row.conflicting then show("Base: ",row.base);show("Variant: ",row.variant) end
				if advisory and not row.conflicting then
					if row.incomplete then details[#details+1]="The listing lacks verifiable price ID or variant details."
					end
					if not row.supported and (not row.incomplete or row.partialGemMatch) then details[#details+1]="The estimate needs at least 20 consistent listings and observations." end
				end
				if not row.conflicting and row.corrupted~=nil then details[#details+1]=row.corrupted and "Corrupted" or "Uncorrupted" end
					local evidence = row.baseEvidence
					if evidence then
						details[#details+1]=string.format("Market coverage: %d unique names across %d listed variants",evidence.names,evidence.variants)
						details[#details+1]=string.format("Listing-backed estimates: %d of %d variants",evidence.priced,evidence.variants)
						if evidence.priced>0 then
							details[#details+1]=string.format("Supported price range: %.4g to %.4g chaos",evidence.minimum,evidence.maximum)
						end
						if #evidence.unquoted>0 then
							details[#details+1]=string.format("PoB catalogue entries without a supported quote (%d)",#evidence.unquoted)
							for index=1,math.min(3,#evidence.unquoted) do
								details[#details+1]="Unpriced: "..evidence.unquoted[index]
							end
						end
						details[#details+1]="An unidentified drop can be a different unique or variant."
					end
				if not row.conflicting then
					if row.advisoryCategory then details[#details+1]="Compare the listed variant and modifiers with the item." end
					for _,line in ipairs(row.providerEvidence or {}) do details[#details+1]=line end
					show("Links: ",row.links);show("Gem level: ",row.gemLevel)
					show("Gem quality: ",row.gemQuality);show("Map tier: ",row.mapTier)
					show("Observations: ",row.count);show("Listings: ",row.listings)
					show(row.liquidityUnit=="listing samples" and "Listing samples: " or "Chaos quoted volume: ",row.volume)
				end
				entries[#entries+1]={id=tostring(i), label=row.conflicting and row.identity or row.name,
					details=details, search=table.concat(details," ")}
				end
				finish(managedState=="thin" and "The exact managed quote has insufficient market volume." or "Showing "..#entries.." of "..#rows.." matches.")
				if managedState then
					table.insert(entries[1].details,1,category.label.." in "..league)
					showMarketDetails(entries[1],"Exact market quote")
				else
					local options
					if comparable and comparable.itemLevel then
						options={secondary={label="Search exact base on trade",run=function() openExactBase(comparable,league) end}}
					end
					require("Classes.PlanningBrowserControl").Open(category.label.." market prices",entries,options)
				end
			end)
		end
		if league~="" then prices();return end
		status("Checking the current PC trade league...")
		request("leagues",function(response)
			local valid, list = pcall(function()
				return market.tradeLeagues(sync.fresh(response,os.time()))
			end)
			if not valid then finish("Could not verify the current PC trade league."); return end
			league=list[1].id
			prices()
		end)
	end)
	controls.get.enabled=function() return not busy end
	controls.close=new("ButtonControl"):ButtonControl(ui.anchor,{width-154,282,138,28},"Close",function() main:ClosePopup() end)
	if managedTarget then
		selectTarget(managedTarget,"Exact managed target. Show prices to check its current quote.")
	end
	ui.style(controls)
	local height = managedTarget and 330 or 404
	popup=main:OpenPopup(width,height,"Browse loot market prices",controls,nil,nil,"close")
	if quoteOnOpen then controls.get:Click()
	elseif overlay and overlay.snapshot and target and target.listingItem and overlay.league~="" then
		local selected,league=target,overlay.league
		local review=not selected.listingItem.blightcore and function() controls.rolledTrade:Click() end or nil
		status("Comparing the saved listing capture...")
		compareSavedCapture(overlay.snapshot,selected,league,nil,function()
			if target==selected and controls.league.buf==league then
				status("Saved listing capture selected.")
				return true
			end
		end,review)
	end
end

function M.Open(build)
	return open(build)
end

function M.OpenForOverlay(raw, league, snapshot)
	return open(nil,nil,{raw=raw,league=league,snapshot=snapshot})
end

function M.OpenForManagedRule(rule)
	local target=assert(browse.managedTarget(rule),"Choose an explicit exchange feed for this managed item first")
	return open(nil,target)
end

return M
