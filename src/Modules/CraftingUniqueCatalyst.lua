-- Bounded lookup of native catalyst display values for one integer roll.
-- This models PoB's display rules; game distributions remain unverified.
local M={}
local cacheOwner,cache
local function tokens(text)
	local values={}
	local skeleton=text:gsub("%-?%d+%.?%d*",function(number) values[#values+1]=tonumber(number);return "#" end)
	return skeleton,values
end
function M.profile(line,low,high,scalar)
	if not cache or cacheOwner~=data.modScalability then cacheOwner=data.modScalability;cache={} end
	local key=line.."\0"..low..":"..high..":"..scalar
	if cache[key]~=nil then return cache[key] or nil end
	local function remember(result)
		if not cache.order then cache.order={} end
		if #cache.order>=256 then cache[table.remove(cache.order,1)]=nil end
		cache.order[#cache.order+1]=key;cache[key]=result or false
		return result
	end
	if high-low>500 then return remember(nil) end
	local samples,difference={},nil
	local firstSkeleton,firstValues
	for value=low,high do
		local rendered=itemLib.applyRange(line,(value-low)/(high-low),scalar)
		local current,values=tokens(rendered)
		if not firstSkeleton then firstSkeleton=current;firstValues=values
		elseif current~=firstSkeleton or #values~=#firstValues then return remember(nil) end
		for i,number in ipairs(values) do
			if number~=math.floor(number) then return remember(nil) end
			if number~=firstValues[i] then
				if difference and difference~=i then return remember(nil) end
				difference=i
			end
		end
		samples[#samples+1]={text=rendered,values=values}
	end
	if not difference then return remember(nil) end
	local result={lookup={},min=math.huge,max=-math.huge}
	for _,sample in ipairs(samples) do
		local value=sample.values[difference];result.lookup[sample.text]=value
		result.min=math.min(result.min,value);result.max=math.max(result.max,value)
	end
	return remember(result)
end
return M
