-- Create a new export without replacing a file that appeared after preflight.
local M={}
function M.writeNew(path,contents)
	assert(type(path)=="string" and path~="" and type(contents)=="string","Invalid export destination or contents")
	local file,reason=io.open(path,"wbx")
	assert(file,"Could not create a new file: "..tostring(reason))
	local written,writeError=file:write(contents);local closed,closeError=file:close()
	assert(written and closed,"Could not finish the new file; it may be incomplete: "..tostring(writeError or closeError))
end
return M
