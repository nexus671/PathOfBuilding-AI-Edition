-- cspell:ignore jsontype
local json = require("dkjson")
local M = {}
local null = {}
local objectMeta, arrayMeta = {__jsontype="object"}, {__jsontype="array"}

local function isObject(value)
	return type(value)=="table" and getmetatable(value)==objectMeta
end

local function objectRows(value)
	if type(value)~="table" or getmetatable(value)~=arrayMeta then return false end
	-- Explicit null decoding keeps every slot, including a null suffix. Validate
	-- the complete collection before any consumer can use ipairs on its rows.
	for _, row in ipairs(value) do
		if not isObject(row) then return false end
	end
	return true
end

local function optionalNulls(value)
	if type(value)~="table" or value==null then return end
	local object = getmetatable(value)==objectMeta
	for key, child in pairs(value) do
		if child==null then
			if object then value[key]=nil end
		else
			optionalNulls(child)
		end
	end
end

-- Return nil for malformed JSON or a wrong documented collection shape.
-- Optional object fields retain the historical null-as-absent semantics.
function M.decode(body, collections, rootRows)
	local data, position, problem = json.decode(body,1,null,objectMeta,arrayMeta)
	if problem or not position or body:sub(position):find("%S") then return nil end
	if rootRows then
		if not objectRows(data) then return nil end
	else
		if not isObject(data) then return nil end
		for _, field in ipairs(collections or {}) do
			if not objectRows(data[field]) then return nil end
		end
	end
	optionalNulls(data)
	return data, position
end

return M
