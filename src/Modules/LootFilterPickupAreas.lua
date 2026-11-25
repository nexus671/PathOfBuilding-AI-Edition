local M = {}

M.bands = {
	campaign = {id=1,conditions={"    AreaLevel < 68"},samples={60,67},label="campaign areas"},
	earlyMaps = {id=2,conditions={"    AreaLevel >= 68","    AreaLevel < 78"},samples={68,77},label="early maps"},
	endgame = {id=3,conditions={"    AreaLevel >= 78"},samples={78,83},label="endgame areas"},
}

local guards = {
	maps = {"    AreaLevel >= 68"},
	campaign = M.bands.campaign.conditions,
	earlyMaps = M.bands.earlyMaps.conditions,
	endgame = M.bands.endgame.conditions,
}

function M.read(conditions)
	local found = {}
	for _, condition in ipairs(conditions) do
		if condition.keyword=="AreaLevel" then
			if #condition.values~=1 then return nil end
			found[#found+1] = "    AreaLevel "..condition.operator.." "..condition.values[1]
		end
	end
	if #found==0 then return "all" end
	for scope, expected in pairs(guards) do
		if #found==#expected and (found[1]==expected[1] and found[2]==expected[2]
			or #found==2 and found[1]==expected[2] and found[2]==expected[1]) then return scope end
	end
end

function M.conditions(scope)
	return guards[scope] or {}
end

function M.mapScope(scope)
	return scope=="maps" or scope=="earlyMaps" or scope=="endgame"
end

function M.split(scope)
	if scope=="maps" then return {"earlyMaps","endgame"} end
	return {"campaign","earlyMaps","endgame"}
end

function M.target(policy, scope, band)
	local stage = band or scope
	if M.mapScope(stage) then return policy[stage] or policy.maps or policy.target end
	return policy[stage] or policy[scope] or policy.target
end

function M.samples(scope, tier)
	if M.bands[scope] then return M.bands[scope].samples end
	if scope=="maps" then return tier and {83} or {83,68} end
	return {83,60}
end

return M
