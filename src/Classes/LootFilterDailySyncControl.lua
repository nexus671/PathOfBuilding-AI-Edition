local sync = require("Modules.LootFilterDailySync")
local ui = require("Modules.PlanningUI")
local M = {}

function M.Open()
	local ok, config = pcall(sync.configuration)
	if not ok then main:OpenMessagePopup("Daily filter sync", ui.errorText(config)); return end
	config = config or {}
	local width = math.min(720, main.screenW - 40)
	local c = {}
	local function button(key, x, label, action)
		c[key] = new("ButtonControl"):ButtonControl(ui.anchor,{x, 286, 138, 28},label,action)
	end
	local function field(key, y, label, value)
		ui.label(c, key.."Label", 16, y, label, 14)
		c[key] = new("EditControl"):EditControl(ui.anchor,{16, y+20, width-32, 26},value,nil,nil,1000)
	end
	local function attempt(action)
		local passed, err = pcall(action)
		if not passed then main:OpenMessagePopup("Daily filter sync", ui.errorText(err)); return end
		main:ClosePopup()
		M.Open()
	end
	field("target", 24, "Live Path of Exile .filter file", config.target or "")
	field("baseline", 82, "Fixed baseline .filter file", config.baseline or "")
	field("league", 140, "poe.ninja league ID", config.league or "Covens")
	ui.description(c,"help",16,198,width-32,38,{"Runs at or after 9:00 a.m. local time while PoB is open. The fixed baseline is stored in PoB."},14)
	c.status = new("LabelControl"):LabelControl(ui.anchor,{16,242,width-32,24},"",14)
	c.status.label = function() return ui.fit(sync.status, width-32, 14) end
	button("enable",16,"Enable / update",function() attempt(function() sync.configure(c.target.buf,c.baseline.buf,c.league.buf) end) end)
	button("run",164,"Sync now",function() sync.tick(os.time(),true) end)
	button("disable",312,"Disable",function() attempt(sync.disable) end)
	button("close",width-154,"Close",function() main:ClosePopup() end)
	c.enable.enabled = function() return not sync.busy end
	c.disable.enabled = function() return config.enabled and not sync.busy end
	c.run.enabled = function() return config.enabled and not sync.busy end
	ui.style(c)
	main:OpenPopup(width, 336, "Daily filter sync", c, nil, nil, "close")
end

return M
