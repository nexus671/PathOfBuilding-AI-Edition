local market = require("Modules.LootFilterEconomy")
local browse = require("Modules.LootFilterMarketBrowse")
local ui = require("Modules.PlanningUI")
local sync = require("Modules.LootFilterDailySync")
local M = {}

local function showManagedQuote(entry)
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
	ui.style(controls,{close=true})
	main:OpenPopup(width,height,"Exact market quote",controls,nil,nil,"close")
end

local function open(build, managedTarget)
	local width = math.min(680,main.screenW-40)
	local controls = {}
	local busy, popup, target
	ui.label(controls,"leagueLabel",16,24,"PC trade league ID",14)
	controls.league=new("EditControl"):EditControl(ui.anchor,{16,50,width-32,26},"","Current trade league",nil,80)
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
	if #buildTargets>0 then
		controls.buildTarget = new("ButtonControl"):ButtonControl(ui.anchor,{162,282,152,28},"From build",function()
			require("Classes.PlanningBrowserControl").Open("Compare a build item",buildTargets,{
				action="Use item",
				choose=function(entry)
					for index, category in ipairs(browse.categories) do
						if category.id==entry.category then controls.category:SetSel(index); break end
					end
					controls.query:SetText("="..entry.name)
					target = entry
					status(entry.imbuedSupport and "Comparing gem and support; listed level or quality must agree."
						or entry.level and string.format("Matching level %g and %g%% quality.",entry.level,entry.quality)
						or entry.details[1])
				end,
			})
		end)
		controls.buildTarget.enabled = function() return not busy end
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
					showManagedQuote(entries[1])
				else
					require("Classes.PlanningBrowserControl").Open(category.label.." market prices",entries)
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
		for index,category in ipairs(browse.categories) do
			if category.id==managedTarget.category then controls.category:SetSel(index);break end
		end
		controls.query:SetText("="..managedTarget.name)
		target=managedTarget
		status("Exact managed target. Show prices to check its current quote.")
	end
	ui.style(controls)
	popup=main:OpenPopup(width,330,"Browse loot market prices",controls,nil,nil,"close")
end

function M.Open(build)
	return open(build)
end

function M.OpenForManagedRule(rule)
	local target=assert(browse.managedTarget(rule),"Choose an explicit exchange feed for this managed item first")
	return open(nil,target)
end

return M
