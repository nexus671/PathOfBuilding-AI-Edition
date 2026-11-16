-- Identify modifier boundaries without guessing between different partitions.
local M={}
function M.resolve(lines,modifiers)
	if #lines==0 or #lines>12 then return nil end
	local infer=require("Modules.CraftingImport").inferRange
	local lengths={}
	for start=1,#lines do lengths[start]={} end
	for _,mod in pairs(modifiers) do
		if #mod>0 and #mod<=#lines then
			for start=1,#lines-#mod+1 do
				local valid=true
				for offset,template in ipairs(mod) do
					local line=lines[start+offset-1]
					if not infer(template,itemLib.applyRange(line.line,line.range or 0.5)) then valid=false;break end
				end
				if valid then lengths[start][#mod]=true end
			end
		end
	end
	local solutions,chosen={},{}
	local function search(start)
		if #solutions>1 then return end
		if start>#lines then solutions[#solutions+1]=copyTable(chosen);return end
		if #chosen>=3 then return end
		for length in pairs(lengths[start]) do
			local group=lines[start].modGroup
			local valid=true
			for i=start,start+length-1 do
				local current=lines[i].modGroup
				if (group or current) and group~=current then valid=false;break end
			end
			if valid and group and start+length<=#lines and lines[start+length].modGroup==group then valid=false end
			if valid then chosen[#chosen+1]=length;search(start+length);chosen[#chosen]=nil end
		end
	end
	search(1)
	if #solutions~=1 then return nil end
	local result,start={},1
	for _,length in ipairs(solutions[1]) do
		local group={};for index=start,start+length-1 do group[#group+1]=copyTable(lines[index]) end
		result[#result+1]=group;start=start+length
	end
	return result
end
return M
