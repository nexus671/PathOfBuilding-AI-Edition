local capture=require("Modules.LootTradeOverlayCapture")
local game=assert(capture.gamePath("F:/SteamLibrary/steamapps/common/Path of Exile/PathOfExileSteam.exe"))
assert(not capture.gamePath("F:/SteamLibrary/steamapps/common/Path of Exile 2/PathOfExileSteam.exe"))
assert(not capture.gamePath("F:/Games/../PathOfExile.exe"))
assert(not capture.gamePath("F:/Games/notepad.exe"))
assert(not capture.gamePath("PathOfExile.exe"))

local function fixture(options)
	options=options or {}
	local state={now=0,sequence=10,copies=0,reads=0,window=1,pid=500}
	local osApi={
		time=function() return state.now end,
		foreground=function() return state.window end,
		pid=function() return state.pid end,
		sequence=function() return state.sequence end,
		wait=function(duration)
			state.now=state.now+duration
			if options.switchFocus then state.window=2 end
			return options.stop
		end,
		chordDown=function() return options.keepHeld or options.switchFocus end,
		copy=function()
			state.copies=state.copies+1
			if not options.unchanged then state.sequence=state.sequence+1 end
			if options.wrongPID then state.pid=501 end
			return not options.failCopy
		end,
		read=function(pid)
			assert(pid==500)
			state.reads=state.reads+1
			if not options.invalidOwner then return "fixture item" end
		end,
	}
	return osApi,state
end
local osApi,state=fixture()
assert(capture.capture(osApi,1,500,0x44)=="fixture item" and state.copies==1 and state.reads==1)
for _, options in ipairs({{keepHeld=true},{switchFocus=true},{stop=true,keepHeld=true},
	{unchanged=true},{wrongPID=true},{failCopy=true},{invalidOwner=true}}) do
	local osApi,state=fixture(options)
	assert(not capture.capture(osApi,1,500,0x44))
	local expectedCopies=(options.keepHeld or options.switchFocus) and 0 or 1
	assert(state.copies==expectedCopies)
	assert(state.reads==(options.invalidOwner and 1 or 0))
end

do
	local osApi,state=fixture()
	local cycle,registered,unregistered,delivered=0,0,0,0
	osApi.wait=function()
		cycle=cycle+1
		state.window=cycle==1 and 2 or cycle<=3 and 1 or 2
		return cycle>=5
	end
	osApi.executable=function(window) return window==1 and game or [[F:\Other\PathOfExileSteam.exe]] end
	osApi.register=function(key) assert(key==0x44 and state.window==1); registered=registered+1; return true end
	osApi.unregister=function() unregistered=unregistered+1 end
	osApi.nextHotkey=function() return cycle==3 end
	local ok,reason=capture.watch(osApi,game,0x44,function(message) error(message) end,function(window,value)
		assert(window==1 and value=="fixture item")
		delivered=delivered+1
	end)
	assert(ok,reason)
	assert(registered==1 and unregistered==1 and delivered==1 and state.copies==1 and state.reads==1)
end

print("Trade overlay copy and read are single-use and scoped to the armed foreground process")
