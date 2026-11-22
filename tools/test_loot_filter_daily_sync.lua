-- Windows integration check. Runs the actual native file operations using
-- synthetic exchange responses and an isolated destination.
local dir = assert(arg[1], "Supply an existing temporary directory")
local function write(path, value)
	local file = assert(io.open(path, "wb"))
	assert(file:write(value))
	assert(file:close())
end
local function read(path)
	local file = assert(io.open(path,"rb"))
	local value = file:read("*a")
	file:close()
	return value
end
local original = [[Show
    BaseType == "Cord Belt"

# PoB economy: begin
Hide
    Class == "Stackable Currency"
    BaseType == "Orb of Alteration"
    StackSize <= 6

# PoB economy: end
Show
    Class == "Stackable Currency"
]]
local target, baseline, protections = dir.."/target.filter", dir.."/baseline.filter", dir.."/protect.json"
write(target,original)
write(baseline,original)
write(protections,'[{"BaseType":"Cord Belt","Rarity":"Magic"}]')
main = {userPath=dir.."/"}
function urlEncode(value) return value end
local sync = require("Modules.LootFilterDailySync")
local now = os.time()
local header = "HTTP/1.1 200 OK\r\nDate: "..os.date("!%a, %d %b %Y %H:%M:%S GMT",now).."\r\nAge: 5\r\n\r\n"
local calls, stale = 0, true
launch = {DownloadPage=function(_, _, callback, params)
	calls = calls + 1
	assert(params.timeout == 20)
	callback({
		header=stale and header:gsub("Age: 5","Age: 4001") or header,
		body='{"core":{"primary":"chaos"},"items":[{"id":"alt","name":"Orb of Alteration"}],"lines":[{"id":"alt","primaryValue":0.21,"volumePrimaryValue":1000}]}',
	})
end}
sync.configure(target,baseline,"Covens",{hour=0,targetValue=1,protectionFile=protections})
sync.tick(now,true)
assert(sync.status:find("stale",1,true) and read(target)==original,sync.status)
stale=false
sync.tick(now,true)
assert(sync.status:find("Protected drops verified",1,true) and read(target):find("StackSize <= 4",1,true),sync.status)
assert(calls==9)
sync.tick(now+60)
assert(calls==9)
sync.tick(now+60,true)
assert(calls==17)
sync.rollback()
assert(read(target)==original and sync.configuration().paused)
sync.tick(now+86400,true)
assert(calls==17)
sync.pause(false)
launch.noSSL=true
sync.tick(now+86400,true)
assert(calls==17 and sync.status:find("HTTPS",1,true))
launch.noSSL=false
sync.disable()
sync.tick(now+86400,true)
assert(calls==17 and not sync.configuration().enabled)
print("Native daily sync: fresh/stale data, manual rerun, rollback, pause, TLS and disable passed")
