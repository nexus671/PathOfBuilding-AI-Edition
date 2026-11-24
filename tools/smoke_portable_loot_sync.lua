local action, directory, league = arg[1], arg[2], arg[3]
local root = directory:gsub("\\", "/") .. "/"
main = {userPath=root}
local sync = require("Modules.LootFilterDailySync")
if action == "prepare" then
	sync.configure(root .. "smoke-output.filter", root .. "smoke-baseline.filter", league, {hour=0, targetValue=1})
	sync.setBackground(true, assert(sync.configuration()).revision)
	assert(#sync.dueProfiles(os.time(), true) == 1, "Expected one due portable profile")
elseif action == "report" then
	local now = os.time()
	local report = sync.diagnosticReport(now)
	local status = sync.publicStatus(now)
	if status.state == "enabled" and status.lastSuccess then
		sync.verifiedOutput()
		assert(#sync.dueProfiles(now, true) == 0, "The successful profile is still due")
	end
	print(report)
else
	error("Expected prepare or report")
end
