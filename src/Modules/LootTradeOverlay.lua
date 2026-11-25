local M = {}
local capture = require("Modules.LootTradeOverlayCapture")
local json = require("dkjson")
local title = "PoB AI Edition trade overlay"
local openingTitle = "Starting PoB trade overlay"
local maxSettingsBytes=20000

local listener = [=[
local ok, successful, problem = pcall(function(event,path,key)
	return require("Modules.LootTradeOverlayCapture").watch(
		require("Modules.LootTradeOverlayWindows").listener(event),path,key,LootTradeOverlayStatus,LootTradeOverlayItem)
end,...)
return ok and successful, tostring(ok and problem or successful or "")
]=]

local function snapshotPath(path)
	return type(path)=="string" and #path<=4096 and not path:find("[%c\"]")
		and path:match("^%a:[/\\]") and path:lower():match("%.json$") and path or nil
end

local function validLeague(league)
	return type(league)=="string" and #league<=80 and (league=="" or league:match("^[%w _-]+$"))
end

local function readSettings(path)
	local file=io.open(path,"rb")
	if not file then return {} end
	local raw=file:read(maxSettingsBytes+1)
	file:close()
	if raw and #raw<=maxSettingsBytes then
		local saved, position=json.decode(raw)
		if type(saved)=="table" and saved.version==1 and position and not raw:sub(position):find("%S")
			and capture.gamePath(saved.path) and validLeague(saved.league)
			and type(saved.key)=="number" and capture.hotkeys[saved.key]
			and (saved.snapshot==nil or snapshotPath(saved.snapshot) and saved.league~="") then return saved end
	end
	return {},"Saved overlay settings could not be read. Review the setup and arm again."
end

local function saveSettings(state)
	local path=state.settingsPath
	if not path then return true end
	local data=json.encode({version=1,path=state.path,key=state.key,league=state.league,snapshot=state.snapshot})
	local temporary=path..".tmp"
	local file=io.open(temporary,"wb")
	if not file then
		pcall(MakeDir,main.userPath)
		file=io.open(temporary,"wb")
	end
	if not file then return false end
	local written=file:write(data)
	local closed=file:close()
	local saved=written and closed and pcall(state.win.replaceFile,temporary,path)
	if not saved then os.remove(temporary) end
	return saved
end

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
	ui.label(controls,"snapshotLabel",16,230,"Saved listing capture (optional)",14)
	controls.snapshot=new("EditControl"):EditControl(ui.anchor,{16,251,width-144,28},state.snapshot or "",
		"Path to a PoB Public Stashes capture",nil,4096)
	controls.snapshotBrowse=new("ButtonControl"):ButtonControl(ui.anchor,{width-118,251,102,28},"Browse",function()
		require("Classes.LootFilterFileBrowser").Open(controls.snapshot.buf~="" and controls.snapshot.buf or nil,
			function(path) controls.snapshot:SetText(path) end,{title="Choose a saved listing capture",itemLabel="Capture",
				category="Captures",accept=function(name) return name:lower():match("%.json$")~=nil end})
	end)
	ui.label(controls,"status",16,297,ui.fit(state.message or "",width-32,14),14)
	local function status(message)
		state.message=message
		controls.status.label=ui.fit(message,width-32,14)
	end
	controls.start=new("ButtonControl"):ButtonControl(ui.anchor,{16,332,150,28},"Arm overlay",function()
		local path=capture.gamePath(controls.path.buf)
		local league=controls.league.buf:match("^%s*(.-)%s*$")
		if not path then status("Select a local Path of Exile 1 game executable."); return end
		if not validLeague(league) then status("Enter a valid PC trade league ID."); return end
		local snapshot=controls.snapshot.buf
		if snapshot~="" and (not snapshotPath(snapshot) or league=="") then
			status("Choose a local JSON capture and enter its PC trade league."); return
		end
		local file=io.open(controls.path.buf,"rb")
		if not file then status("The selected executable could not be opened."); return end
		file:close()
		state.path,state.league,state.key=controls.path.buf,league,controls.key.selIndex or 1
		state.snapshot=snapshot~="" and snapshot or nil
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
		if saveSettings(state) then
			status("Armed. Switch to Path of Exile 1 and use "..capture.hotkeys[state.key].label..".")
		else
			status("Armed for this session. PoB could not save the overlay settings.")
		end
		state.win.minimize(state.window)
	end)
	controls.start.enabled=function() return state.job==nil end
	controls.reconfigure=new("ButtonControl"):ButtonControl(ui.anchor,{174,332,158,28},"Disarm overlay",function()
		state.win.signal(state.event)
		status("Disarmed. Update settings and arm again when ready.")
	end)
	controls.reconfigure.enabled=function() return state.job~=nil end
	controls.close=new("ButtonControl"):ButtonControl(ui.anchor,{width-112,332,96,28},"Exit",function() Exit() end)
	for _,key in ipairs({"path","browse","key","league","snapshot","snapshotBrowse"}) do
		controls[key].enabled=function() return state.job==nil end
	end
	ui.style(controls,{start=true})
	main:OpenPopup(width,384,"PoB trade overlay setup",controls,nil,nil,"close")
end

local function dismiss(state)
	state.active,state.captured,state.game,state.hadFocus=nil,nil,nil,nil
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
	local path=model.userPath.."LootTradeOverlay.json"
	local state,message=readSettings(path)
	state.app,state.win,state.instance,state.settingsPath,state.message=app,win,instance,path,message
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
			state.game=captured.game
			state.hadFocus=state.win.foreground()==state.window
			state.opened=GetTime()
			wipeTable(main.popups)
			wipeTable(main.inputEvents)
			main.screenW,main.screenH=GetVirtualScreenSize()
			if captured.message then
				main:OpenMessagePopup("Trade price check",captured.message)
			else
				require("Classes.LootFilterMarketBrowseControl").OpenForOverlay(captured.raw,state.league,state.snapshot)
			end
			return
		end
	end
	if state.active then
		local foreground=state.win.foreground()
		if foreground==state.window then state.hadFocus=true end
		-- Windows can leave the game focused when the companion first appears.
		-- Keep the review visible until clicked, dismissed, or the user leaves the game.
		local leftReview=foreground~=state.window and
			(state.hadFocus or foreground~=state.game or state.win.pointerDown())
		if state.win.minimized(state.window) or GetTime()-state.opened>300 and leftReview then
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
