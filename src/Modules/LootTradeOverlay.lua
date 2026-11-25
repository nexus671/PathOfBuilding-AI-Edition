local M = {}
local capture = require("Modules.LootTradeOverlayCapture")
local title = "PoB AI Edition trade overlay"
local openingTitle = "Starting PoB trade overlay"

local listener = [=[
local ok, successful, problem = pcall(function(event,path,key)
	return require("Modules.LootTradeOverlayCapture").watch(
		require("Modules.LootTradeOverlayWindows").listener(event),path,key,LootTradeOverlayStatus,LootTradeOverlayItem)
end,...)
return ok and successful, tostring(ok and problem or successful or "")
]=]

local function setup(state)
	local ui=require("Modules.PlanningUI")
	local width=math.min(600,main.screenW-40)
	local controls={}
	ui.description(controls,"instructions",16,18,width-32,60,{
		"Select the running Path of Exile 1 client's executable, then arm the overlay.",
		"One shortcut press copies the hovered item once and opens PoB market tools.",
		"Supported gems, currencies and uniques request a market overview.",
	},14)
	ui.label(controls,"pathLabel",16,98,"Path of Exile 1 executable",14)
	controls.path=new("EditControl"):EditControl(ui.anchor,{16,119,width-144,28},state.path or "",
		"Full path to the game executable",nil,4096)
	controls.browse=new("ButtonControl"):ButtonControl(ui.anchor,{width-118,119,102,28},"Browse",function()
		require("Classes.LootFilterFileBrowser").Open(controls.path.buf~="" and controls.path.buf or nil,
			function(path) controls.path:SetText(path) end,{title="Choose the PoE 1 executable",itemLabel="Client",
				category="Game clients",accept=function(name) return capture.gamePath("C:/"..name)~=nil end})
	end)
	ui.label(controls,"keyLabel",16,164,"Price check shortcut",14)
	local keys={}
	for _, key in ipairs(capture.hotkeys) do keys[#keys+1]=key.label end
	controls.key=new("DropDownControl"):DropDownControl(ui.anchor,{16,185,176,28},keys)
	controls.key:SetSel(state.key or 1)
	ui.label(controls,"leagueLabel",220,164,"PC trade league",14)
	controls.league=new("EditControl"):EditControl(ui.anchor,{220,185,width-236,28},state.league or "",
		"Current trade league",nil,80)
	ui.label(controls,"status",16,232,ui.fit(state.message or "",width-32,14),14)
	local function status(message)
		state.message=message
		controls.status.label=ui.fit(message,width-32,14)
	end
	controls.start=new("ButtonControl"):ButtonControl(ui.anchor,{16,270,150,28},"Arm overlay",function()
		local path=capture.gamePath(controls.path.buf)
		local league=controls.league.buf:match("^%s*(.-)%s*$")
		if not path then status("Select a local Path of Exile 1 game executable."); return end
		if league~="" and not league:match("^[%w _-]+$") then status("Enter a valid PC trade league ID."); return end
		local file=io.open(controls.path.buf,"rb")
		if not file then status("The selected executable could not be opened."); return end
		file:close()
		state.path,state.league,state.key=controls.path.buf,league,controls.key.selIndex or 1
		state.event=state.win.stopEvent()
		if not state.event then status("Windows could not start the shortcut listener."); return end
		state.job=LaunchSubScript(listener,"","LootTradeOverlayStatus,LootTradeOverlayItem",
			state.event,path,capture.hotkeys[state.key].code)
		if not state.job then
			state.win.close(state.event)
			state.event=nil
			status("Windows could not start the shortcut listener.")
			return
		end
		state.app:RegisterSubScript(state.job,function(ok,message)
			state.job=nil
			state.win.close(state.event)
			state.event=nil
			if not ok then status("The shortcut listener stopped: "..tostring(message)) end
		end)
		status("Armed. Switch to Path of Exile 1 and use "..capture.hotkeys[state.key].label..".")
		state.win.minimize(state.window)
	end)
	controls.start.enabled=function() return state.job==nil end
	controls.reconfigure=new("ButtonControl"):ButtonControl(ui.anchor,{174,270,158,28},"Disarm overlay",function()
		state.win.signal(state.event)
		status("Disarmed. Update settings and arm again when ready.")
	end)
	controls.reconfigure.enabled=function() return state.job~=nil end
	controls.close=new("ButtonControl"):ButtonControl(ui.anchor,{width-112,270,96,28},"Exit",function() Exit() end)
	ui.style(controls,{start=true})
	main:OpenPopup(width,322,"PoB trade overlay setup",controls,nil,nil,"close")
end

local function dismiss(state)
	state.active,state.captured=nil,nil
	wipeTable(main.popups)
	wipeTable(main.inputEvents)
	setup(state)
	state.win.minimize(state.window)
end

function M.start(app)
	local win=require("Modules.LootTradeOverlayWindows")
	local instance=assert(win.singleInstance(),"The PoB trade overlay is already running")
	local model=LoadModule("Modules/Main")
	model.popups,model.inputEvents={},{}
	if GetScriptPath()==GetRuntimePath() and not app.installedMode then
		model.userPath=GetScriptPath().."/"
	else
		model.userPath=(assert(GetUserPath(),"PoB's Windows Documents folder is unavailable")).."/Path of Building/"
	end
	local config=require("xml").LoadXMLFile(model.userPath.."Settings.xml")
	for _, element in ipairs(config and config[1] or {}) do
		if type(element)=="table" and element.elem=="Misc" then
			app.connectionProtocol=tonumber(element.attrib.connectionProtocol)
			app.proxyURL=element.attrib.proxyURL
			break
		end
	end
	local state={app=app,win=win,instance=instance}
	LootTradeOverlayStatus=function(message,game)
		state.message=message
		if game then state.captured={game=game,message=message} end
	end
	LootTradeOverlayItem=function(game,raw) state.captured={game=game,raw=raw} end
	SetWindowTitle(openingTitle)
	RenderInit("DPI_AWARE")
	return state
end

function M.frame(state)
	main.screenW,main.screenH=GetVirtualScreenSize()
	local view={x=0,y=0,width=main.screenW,height=main.screenH}
	main.viewPort=view
	if not state.window then
		state.window=state.win.findWindow(openingTitle)
		if not state.window then return end
		setup(state)
		SetWindowTitle(title)
	end
	if state.captured then
		local captured=state.captured
		state.captured=nil
		if state.win.present(state.window,captured.game) then
			state.active=true
			state.opened=GetTime()
			wipeTable(main.popups)
			wipeTable(main.inputEvents)
			main.screenW,main.screenH=GetVirtualScreenSize()
			if captured.message then
				main:OpenMessagePopup("Trade price check",captured.message)
			else
				require("Classes.LootFilterMarketBrowseControl").OpenForOverlay(captured.raw,state.league)
			end
			return
		end
	end
	if state.active then
		local foreground=state.win.foreground()
		if state.win.minimized(state.window) or (GetTime()-state.opened>650 and foreground~=state.window) then
			dismiss(state)
			return
		end
	elseif state.message and #main.popups==1 and main.popups[1].controls.status then
		local ui=require("Modules.PlanningUI")
		main.popups[1].controls.status.label=ui.fit(state.message,math.min(600,main.screenW-40)-32,14)
	end
	local popup=main.popups[1]
	if popup then popup:ProcessInput(main.inputEvents,view) end
	wipeTable(main.inputEvents)
	popup=main.popups[1]
	if not popup then
		if state.active then dismiss(state) else setup(state) end
		return
	end
	SetDrawColor(0.09,0.11,0.14)
	DrawImage(nil,0,0,main.screenW,main.screenH)
	popup:Draw(view)
end

function M.key(state,kind,key,doubleClick)
	if state.active and kind=="KeyDown" and key=="ESCAPE" then
		dismiss(state)
		return
	end
	main.inputEvents[#main.inputEvents+1]={type=kind,key=key,doubleClick=doubleClick}
end

function M.close(state)
	state.win.signal(state.event)
	state.win.close(state.instance)
end

return M
