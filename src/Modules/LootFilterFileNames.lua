-- Local filter extensions depend on the game mode.
local M={}
function M.extension(profile)
	return profile.mode=="Ruthless" and ".ruthlessfilter" or ".filter"
end
function M.stem(profile,filename)
	local extension=M.extension(profile)
	assert(type(filename)=="string" and filename:sub(-#extension)==extension,"Use a "..extension.." filename for this mode.")
	local stem=filename:sub(1,-#extension-1)
	assert(stem:match("^[%w_-]+$"),"Use a filename with letters, numbers, hyphens or underscores.")
	return stem
end
function M.variant(profile,filename,strictness)
	return M.stem(profile,filename).."-"..strictness..M.extension(profile)
end
function M.isFilter(filename)
	local lower=filename:lower()
	return lower:match("^.+%.filter$")~=nil or lower:match("^.+%.ruthlessfilter$")~=nil
end
return M
