-- Local filter extensions depend on the game mode.
local M={}
function M.extension(profile)
	return profile.mode=="Ruthless" and ".ruthlessfilter" or ".filter"
end
-- ZIP names are marked as UTF-8, so reject malformed byte sequences too.
local function validUtf8(value)
	local i=1
	while i<=#value do
		local a=value:byte(i);local count,min,max
		if a<128 then count=1
		elseif a>=194 and a<=223 then count=2
		elseif a>=224 and a<=239 then count=3
		elseif a>=240 and a<=244 then count=4
		else return false end
		if i+count-1>#value then return false end
		for j=1,count-1 do
			local byte=value:byte(i+j);min,max=128,191
			if j==1 then
				if a==224 then min=160 elseif a==237 then max=159 elseif a==240 then min=144 elseif a==244 then max=143 end
			end
			if byte<min or byte>max then return false end
		end
		i=i+count
	end
	return true
end
function M.stem(profile,filename)
	local extension=M.extension(profile)
	assert(type(filename)=="string" and filename:sub(-#extension):lower()==extension,"Use a "..extension.." filename for this mode.")
	local stem=filename:sub(1,-#extension-1)
	assert(#filename<=240 and validUtf8(stem) and stem:match("%S") and not stem:find('[%c/\\:*?"<>|]') and not stem:match('[%. ]$'),"Use a valid filename of at most 240 bytes without path separators or trailing spaces or dots.")
	local device=(stem:match("^([^%.]+)") or ""):gsub("%s+$",""):upper()
	assert(device~="CON" and device~="PRN" and device~="AUX" and device~="NUL" and not device:match("^COM[1-9]$") and not device:match("^LPT[1-9]$"),"Choose a filename that is not a reserved Windows device name.")
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
