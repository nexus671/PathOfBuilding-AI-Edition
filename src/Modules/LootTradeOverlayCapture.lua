local M = {}

M.hotkeys = {
	{label="Ctrl+Alt+D", code=0x44},
	{label="Ctrl+Alt+Q", code=0x51},
	{label="Ctrl+Alt+W", code=0x57},
}

function M.gamePath(path)
	if type(path)~="string" or #path>4096 or path:find("[%c\"]") or not path:match("^%a:[/\\]") then return end
	local normalized=path:gsub("/", "\\"):lower()
	if normalized:find("\\%.%.?\\") or normalized:find("\\\\",1,true)
		or normalized:find("\\path of exile 2\\",1,true) then return end
	local name=normalized:match("([^\\]+)$")
	local executables={["pathofexile.exe"]=true,["pathofexile_x64.exe"]=true,["pathofexilesteam.exe"]=true,
		["pathofexile_x64steam.exe"]=true,["pathofexileegs.exe"]=true,["pathofexile_x64egs.exe"]=true}
	return executables[name] and normalized or nil
end

-- One explicit hotkey message starts at most one native copy and one data read.
-- Polling the clipboard sequence number only checks whether the copy arrived.
function M.capture(osApi, window, pid, key)
	local release=osApi.time()+900
	while osApi.chordDown(key) do
		if osApi.time()>=release or osApi.foreground()~=window or osApi.wait(20) then return end
	end
	if osApi.foreground()~=window or osApi.pid(window)~=pid then return end
	local sequence=osApi.sequence()
	if not osApi.copy() then return nil,"Could not send the item copy to Path of Exile." end
	local deadline=osApi.time()+850
	while osApi.foreground()==window and osApi.pid(window)==pid do
		if osApi.sequence()~=sequence then
			local item=osApi.read(pid)
			if item then return item end
			break
		end
		if osApi.time()>=deadline or osApi.wait(20) then break end
	end
	return nil,"No new item text was copied. Hover an item and press the overlay hotkey again."
end

function M.watch(osApi, path, code, report, deliver)
	local lastWindow, gamePID, registered
	local ok, problem=pcall(function()
		while not osApi.wait(35) do
			local window=osApi.foreground()
			if window~=lastWindow then
				if registered then osApi.unregister() end
				osApi.nextHotkey()
				lastWindow,gamePID,registered=window,nil,false
				if window and M.gamePath(osApi.executable(window))==path then
					gamePID=osApi.pid(window)
					if gamePID and gamePID>0 then
						registered=osApi.register(code)
						if not registered then report("The hotkey is in use. Choose another shortcut and arm the overlay again.") end
					end
				end
			end
			if registered and osApi.nextHotkey() and osApi.pid(window)==gamePID
				and M.gamePath(osApi.executable(window))==path then
				local item, message=M.capture(osApi,window,gamePID,code)
				if item and osApi.foreground()==window then deliver(window,item)
				elseif message then report(message,osApi.foreground()==window and window or nil) end
			end
		end
	end)
	if registered then osApi.unregister() end
	return ok,problem
end

return M
