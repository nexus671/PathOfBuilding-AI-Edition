local ui = require("Modules.PlanningUI")
local M = {}
local title = "Tier 5 rare exceptions"

local function showResults(result, options)
	local lines = {
		options.sourceLabel,
		string.format("%d shown, %d hidden, %d unresolved outside the Rank A/B list.",result.shown,result.hidden,result.unknown),
		"Samples are unidentified, uncorrupted Tier 5 rares at item level 86 in area level 83, with no sockets or special flags.",
		"Counts describe eligible bases in PoB's item catalogue.",
	}
	if result.missing>0 then lines[#lines+1]=result.missing.." bases lack the metadata needed for a sample." end
	local entries = {{label="Audit summary",category="Summary",details=lines}}
	for _, row in ipairs(result.rows) do
		local item, decision, rule = row.item, row.decision, row.rule
		entries[#entries+1] = {
			label=item.BaseType, category=decision.action=="Show" and "Shown outside rank list" or "Unresolved",
			search=item.Class.." "..(decision.line and "line "..decision.line or ""), sample=item,
			details=function()
				local location = decision.line and " at "..(options.lineLabel or "compiled filter").." line "..decision.line
					or " from the default filter behavior"
				local details = {options.sourceLabel,item.Class,decision.action..location}
				if #decision.matches>1 then details[#details+1]="Matched lines in order: "..table.concat(decision.matches,", ") end
				for _, reason in ipairs(decision.reasons) do details[#details+1]=reason end
				if rule then details[#details+1]=StripEscapes(table.concat(rule.rawLines,"\n")) end
				return details
			end,
		}
	end
	local browse = {action="Inspect sample",canChoose=function(entry) return entry.sample~=nil end,closeOnChoose=false}
	if options.inspect then
		browse.choose=function(entry) main:ClosePopup();options.inspect(entry.sample) end
	end
	require("Classes.PlanningBrowserControl").Open(title,entries,browse)
end

function M.Open(loadSource, options)
	local width = math.min(420,main.screenW-40)
	local controls = {}
	ui.label(controls,"status",16,28,"Checking rare base rules...",16)
	controls.close = new("ButtonControl"):ButtonControl(ui.anchor,{width-132,74,116,28},"Cancel",function() main:ClosePopup() end)
	ui.style(controls)
	local popup, deadline
	local worker = coroutine.create(function()
		local raw, parsed = loadSource()
		return require("Modules.LootFilterProtectedDrops").rareTierExceptions(raw,parsed,function()
			if os.clock()>=deadline then coroutine.yield() end
		end)
	end)
	popup = main:OpenPopup(width,122,title,controls,nil,nil,"close",nil,function()
		if main.popups[1]~=popup then return end
		deadline = os.clock()+0.005
		local ok, result = coroutine.resume(worker)
		if ok and coroutine.status(worker)~="dead" then return end
		main:ClosePopup()
		if ok then showResults(result,options) else ui.errorPopup(title,result) end
	end)
end

function M.ChooseVerifiedSource(profileId)
	local entries = {
		{label="Verified filter",lineLabel="verified filter",details={"Audit the most recent verified local output."}},
		{label="Fixed baseline",lineLabel="fixed baseline",details={"Audit the pinned source used for the daily refresh."},baseline=true},
	}
	require("Classes.PlanningBrowserControl").Open(title,entries,{
		action="Review source",closeOnChoose=false,
		choose=function(entry)
			main:ClosePopup()
			M.Open(function()
				local baseline, verified = require("Modules.LootFilterDailySync").verifiedFilterPair(profileId)
				local raw = entry.baseline and baseline or verified
				return raw,require("Modules.LootFilterParser").parse(raw)
			end,{sourceLabel=entry.label,lineLabel=entry.lineLabel})
		end,
	})
end

return M
