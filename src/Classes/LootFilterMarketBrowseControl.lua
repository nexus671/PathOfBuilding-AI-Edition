local market = require("Modules.LootFilterEconomy")
local browse = require("Modules.LootFilterMarketBrowse")
local ui = require("Modules.PlanningUI")
local json = require("dkjson")
local M = {}

function M.Open()
	local width = math.min(680,main.screenW-40)
	local controls = {}
	local busy, popup
	ui.label(controls,"leagueLabel",16,24,"PC trade league ID",14)
	controls.league=new("EditControl"):EditControl(ui.anchor,{16,50,width-32,26},"","Current trade league",nil,80)
	local options={}
	for i, category in ipairs(browse.categories) do options[i]=category.label end
	controls.category=new("DropDownControl"):DropDownControl(ui.anchor,{16,98,width-32,28},options)
	ui.label(controls,"queryLabel",16,138,"Item name, base or variant",14)
	controls.query=new("EditControl"):EditControl(ui.anchor,{16,160,width-32,26},"","Search prices",nil,100)
	ui.description(controls,"help",16,196,width-32,44,{"Compare price estimates and variant details. The browser reads one category at a time."},14)
	ui.label(controls,"status",16,250,"",14)
	local function status(label) controls.status.label=ui.fit(label,width-32,14) end
	controls.get=new("ButtonControl"):ButtonControl(ui.anchor,{16,282,138,28},"Show prices",function()
		if busy then return end
		if launch.noSSL then status("Enable HTTPS certificate verification first."); return end
		local league=controls.league.buf:match("^%s*(.-)%s*$")
		if league~="" and not league:match("^[%w%s_-]+$") then status("Enter a valid league ID."); return end
		local category=browse.categories[controls.category.selIndex or 1]
		local query=controls.query.buf:match("^%s*(.-)%s*$")
		if (category.id=="BaseType" or category.id=="SkillGem") and #query<2 then
			status("Enter at least two characters to search this category.")
			return
		end
		busy=true
		local function finish(message)
			busy=false
			status(message)
		end
		local function request(path,callback)
			launch:DownloadPage(market.endpoint..path,function(response,err)
				if main.popups[1]~=popup then busy=false;return end
				if err or not response then finish("Market request failed. Try again later."); return end
				callback(response)
			end,{timeout=20,maxBytes=browse.maxBytes,header="Accept: application/json"})
		end
		local function prices()
			status("Fetching "..category.label:lower().." for "..league.."...")
			local route=category.feed=="exchange" and "exchange/current/overview" or "stash/current/item/overview"
			request(route.."?league="..urlEncode(league).."&type="..category.id,function(response)
				local ok,body,age=pcall(require("Modules.LootFilterDailySync").fresh,response,os.time())
				if not ok then finish("Exchange response is unavailable or stale.");return end
				local valid,rows=pcall(browse.rows,body,category,query)
				if not valid then finish(ui.errorText(rows));return end
				local entries={}
				for i,row in ipairs(rows) do
					if i>1000 then break end
					local details={
						row.ambiguous and "Ambiguous exchange name" or string.format("%.4g chaos estimated",row.price),
						"Response age: "..math.ceil(age/60).." minutes",
					}
					local function show(label,value)
						if value then details[#details+1]=label..tostring(value) end
					end
					show("Base: ",row.base);show("Variant: ",row.variant)
					if row.corrupted~=nil then details[#details+1]=row.corrupted and "Corrupted" or "Uncorrupted" end
					local evidence = row.baseEvidence
					if evidence and evidence.variants>1 then
						details[#details+1]=string.format("Shared base: %d unique names across %d listed variants",evidence.names,evidence.variants)
						details[#details+1]=string.format("Listing-backed estimates: %d of %d variants",evidence.priced,evidence.variants)
						if evidence.priced>0 then
							details[#details+1]=string.format("Supported price range: %.4g to %.4g chaos",evidence.minimum,evidence.maximum)
						end
						details[#details+1]="An unidentified drop on this base can belong to different variants."
					end
					show("Links: ",row.links);show("Gem level: ",row.gemLevel)
					show("Gem quality: ",row.gemQuality);show("Map tier: ",row.mapTier)
					show("Observations: ",row.count);show("Listings: ",row.listings);show("Chaos quoted volume: ",row.volume)
					entries[#entries+1]={id=tostring(i), label=row.name, details=details, search=table.concat(details," ")}
				end
				finish("Showing "..#entries.." of "..#rows.." matches.")
				require("Classes.PlanningBrowserControl").Open(category.label.." market prices",entries)
			end)
		end
		if league~="" then prices();return end
		status("Checking the current PC trade league...")
		request("leagues",function(response)
			local list = type(response.body)=="string" and #response.body<=65536 and json.decode(response.body)
			local first=type(list)=="table" and list[1]
			if type(first)~="table" or type(first.id)~="string" or not first.id:match("^[%w%s_-]+$") then finish("Could not find a current league.");return end
			league=first.id
			prices()
		end)
	end)
	controls.get.enabled=function() return not busy end
	controls.close=new("ButtonControl"):ButtonControl(ui.anchor,{width-154,282,138,28},"Close",function() main:ClosePopup() end)
	ui.style(controls)
	popup=main:OpenPopup(width,330,"Browse loot market prices",controls,nil,nil,"close")
end

return M
