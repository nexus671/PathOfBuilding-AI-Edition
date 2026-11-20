-- Construct stack-sensitive rules without changing their original item conditions.
local parser=require("Modules.LootFilterParser")
local M={}
local function block(text)
	local parsed=parser.parse(text)
	assert(#parsed.rules==1 and #parsed.imports==0,"Choose one filter block")
	for _,entry in ipairs(parsed.diagnostics) do assert(not entry.error,entry.error) end
	return parsed.rules[1]
end
function M.rule(sourceText,styleText,minimum,upper)
	assert(type(minimum)=="number" and minimum==math.floor(minimum) and minimum>=2 and minimum<=1000000000,"Enter a stack size from 2 to 1000000000")
	assert(upper==nil or type(upper)=="number" and upper==math.floor(upper) and upper>minimum and upper<=1000000000,"Invalid upper stack size")
	local source,style=block(sourceText),block(styleText)
	for _,condition in ipairs(source.conditions) do if condition.keyword=="StackSize" and (condition.operator=="<" or condition.operator=="<=" or condition.operator=="=" or condition.operator=="==" or condition.operator==">" or condition.operator==">=") then
		local possible=false;for _,value in ipairs(condition.values) do local n=tonumber(value);local op=condition.operator
			if n and (op=="<" and minimum<n or op=="<=" and minimum<=n or (op=="=" or op=="==") and minimum<=n and (not upper or n<upper) or op==">" and (not upper or upper-1>n) or op==">=" and (not upper or upper-1>=n)) then possible=true end
		end
		assert(possible,"The tier's existing stack-size condition cannot match this threshold")
	end end
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
