-- Bounded lookup of native catalyst display values for one precision-aware roll.
-- This models PoB's display rules; game distributions remain unverified.
local M={}
local cacheOwner,cache
local function tokens(text)
	local values={}
	local skeleton=text:gsub("%-?%d+%.?%d*",function(number) values[#values+1]=tonumber(number);return "#" end)
	return skeleton,values
end
function M.profile(line,low,high,scalar,precision)
	precision=precision or 1
	if not cache or cacheOwner~=data.modScalability then cacheOwner=data.modScalability;cache={} end
	local key=line.."\0"..low..":"..high..":"..scalar..":"..precision
	if cache[key]~=nil then return cache[key] or nil end
	local function remember(result)
		if not cache.order then cache.order={} end
		if #cache.order>=256 then cache[table.remove(cache.order,1)]=nil end
		cache.order[#cache.order+1]=key;cache[key]=result or false
		return result
	end
	local lo=math.floor(low*precision+0.5);local hi=math.floor(high*precision+0.5)
	if precision<1 or hi<=lo or hi-lo>500 or math.abs(low*precision-lo)>1e-7 or math.abs(high*precision-hi)>1e-7 then return remember(nil) end
	local samples,difference={},nil
	local firstSkeleton,firstValues
	for tick=lo,hi do
		local value=tick/precision;local rendered=itemLib.applyRange(line,(value-low)/(high-low),scalar)
		local current,values=tokens(rendered)
		if not firstSkeleton then firstSkeleton=current;firstValues=values
		elseif current~=firstSkeleton or #values~=#firstValues then return remember(nil) end
		for i,number in ipairs(values) do
			local ticks=number*precision
			if math.abs(ticks-math.floor(ticks+0.5))>1e-7 then return remember(nil) end
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
-- Verify that each component independently changes one displayed integer.
-- Full enumeration prevents assuming independence for an unfamiliar format.
local multiOwner,multiCache,multiOrder
function M.multiProfile(line,ranges,scalar)
	if not multiCache or multiOwner~=data.modScalability then multiOwner=data.modScalability;multiCache={};multiOrder={} end
	local parts={line,tostring(scalar)};local combinations=1
	for _,range in ipairs(ranges) do
		parts[#parts+1]=range.low..":"..range.high;combinations=combinations*(range.high-range.low+1)
	end
	local key=table.concat(parts,"\0");if multiCache[key]~=nil then return multiCache[key] or nil end
	local function remember(value)
		if #multiOrder>=32 then multiCache[table.remove(multiOrder,1)]=nil end
		multiOrder[#multiOrder+1]=key;multiCache[key]=value or false;return value
	end
	if #ranges<2 or #ranges>6 or combinations>4096 then return remember(nil) end
	for _,range in ipairs(ranges) do if range.high<=range.low or range.high-range.low>500 then return remember(nil) end end
	local vector={};for i=1,#ranges do vector[i]=0 end
	local baseline=itemLib.applyRange(line,vector,scalar);local skeleton,initial=tokens(baseline)
	local axes,indices,used={},{},{}
	for i,range in ipairs(ranges) do
		local axis,index={},nil
		for value=range.low,range.high do
			vector[i]=(value-range.low)/(range.high-range.low)
			local shape,values=tokens(itemLib.applyRange(line,vector,scalar))
			if shape~=skeleton or #values~=#initial then return remember(nil) end
			for j,number in ipairs(values) do
				if number~=math.floor(number) then return remember(nil) end
				if number~=initial[j] then if index and index~=j then return remember(nil) end;index=j end
			end
			axis[value]=values
		end
		vector[i]=0
		if not index or used[index] then return remember(nil) end
		used[index]=true;indices[i]=index;axes[i]=axis
	end
	local result={lookup={},minima={},maxima={},components=#ranges}
	for i=1,#ranges do result.minima[i]=math.huge;result.maxima[i]=-math.huge end
	local selected={}
	local function enumerate(index)
		if index>#ranges then
			local rendered=itemLib.applyRange(line,vector,scalar);local shape,values=tokens(rendered)
			if shape~=skeleton or #values~=#initial then return false end
			for j,value in ipairs(values) do
				local component
				for i,position in ipairs(indices) do if position==j then component=i;break end end
				if component then if value~=axes[component][selected[component]][j] then return false end
				elseif value~=initial[j] then return false end
			end
			local display={};for i,position in ipairs(indices) do
				display[i]=values[position];result.minima[i]=math.min(result.minima[i],display[i]);result.maxima[i]=math.max(result.maxima[i],display[i])
			end
			result.lookup[rendered]=display;return true
		end
		local range=ranges[index]
		for value=range.low,range.high do
			selected[index]=value;vector[index]=(value-range.low)/(range.high-range.low)
			if not enumerate(index+1) then return false end
		end
		vector[index]=0;return true
	end
	if not enumerate(1) then return remember(nil) end
	return remember(result)
end

return M
