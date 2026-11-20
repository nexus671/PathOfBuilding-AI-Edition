-- Construct stack-sensitive rules without changing their original item conditions.
local parser=require("Modules.LootFilterParser")
local M={}
local function block(text)
	local parsed=parser.parse(text)
	assert(#parsed.rules==1 and #parsed.imports==0,"Choose one filter block")
	for _,entry in ipairs(parsed.diagnostics) do assert(not entry.error,entry.error) end
	return parsed.rules[1]
end
-- Each numeric line is an OR of its values; separate lines are ANDed.
-- Stack sizes are integers, so intersect their bounds and finite exclusions.
local function possibleStackRange(conditions,minimum,upper)
	local low,high=minimum,upper and upper-1 or math.huge
	local allowed,excluded=nil,{}
	for _,condition in ipairs(conditions) do if condition.keyword=="StackSize" then
		local op=condition.operator;local values={}
		for _,value in ipairs(condition.values) do values[#values+1]=assert(tonumber(value),"Invalid stack-size condition") end
		if op=="=" or op=="==" then
			local choices={};for _,n in ipairs(values) do if n==math.floor(n) and (not allowed or allowed[n]) then choices[n]=true end end;allowed=choices
		elseif op=="!" or op=="!=" then
			for _,n in ipairs(values) do if n==math.floor(n) then excluded[n]=true end end
		elseif op=="<" or op=="<=" then
			local largest=-math.huge;for _,n in ipairs(values) do largest=math.max(largest,n) end;high=math.min(high,op=="<" and math.ceil(largest)-1 or math.floor(largest))
		elseif op==">" or op==">=" then
			local smallest=math.huge;for _,n in ipairs(values) do smallest=math.min(smallest,n) end;low=math.max(low,op==">" and math.floor(smallest)+1 or math.ceil(smallest))
		end
	end end
	if low>high then return false end
	if allowed then for n in pairs(allowed) do if n>=low and n<=high and not excluded[n] then return true end end;return false end
	if high==math.huge then return true end
	local count=0;for n in pairs(excluded) do if n>=low and n<=high then count=count+1 end end
	return count<high-low+1
end
function M.rule(sourceText,styleText,minimum,upper)
	assert(type(minimum)=="number" and minimum==math.floor(minimum) and minimum>=2 and minimum<=1000000000,"Enter a stack size from 2 to 1000000000")
	assert(upper==nil or type(upper)=="number" and upper==math.floor(upper) and upper>minimum and upper<=1000000000,"Invalid upper stack size")
	local source,style=block(sourceText),block(styleText)
	assert(possibleStackRange(source.conditions,minimum,upper),"The tier's existing stack-size conditions cannot match this range")
	for _,condition in ipairs(style.conditions) do assert(condition.known,"Cannot copy an unrecognized tier directive") end
	local result={style.action}
	for i=2,#source.rawLines do local line=source.rawLines[i];local tokens=parser.tokens(line);if tokens[1] and not parser.actions[tokens[1]] and tokens[1]~="Continue" then result[#result+1]=line end end
	result[#result+1]="    StackSize >= "..minimum
	if upper then result[#result+1]="    StackSize < "..upper end
	for i=2,#style.rawLines do local line=style.rawLines[i];local tokens=parser.tokens(line);if parser.actions[tokens[1]] then result[#result+1]=line end end
	-- Keep unverified arguments intact; dropping them could turn an uncertain
	-- source filter into a falsely certain preview of the generated tier.
	for i=2,#source.rawLines do local line=source.rawLines[i];local tokens=parser.tokens(line);if tokens[1]=="Continue" then result[#result+1]=line end end
	return table.concat(result,"\n")
end
return M
