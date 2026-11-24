-- Exact, simultaneous substitutions for declared filter styles.
-- cspell:ignore jsontype
local parser=require("Modules.LootFilterParser")
local appearance=require("Modules.LootFilterAppearanceSettings")
local M={}
local colours={SetTextColor=true,SetBorderColor=true,SetBackgroundColor=true}
local sounds={PlayAlertSound=true,PlayAlertSoundPositional=true,CustomAlertSound=true,CustomAlertSoundOptional=true}
local groups={Colour=true,AlertSound=true,CustomSound=true}
local function group(key)
	if colours[key] then return "Colour" end
	if key=="PlayAlertSound" or key=="PlayAlertSoundPositional" then return "AlertSound" end
	if sounds[key] then return "CustomSound" end
end
local function canonical(key,values)
	if colours[key] or key=="Colour" then
		if #values~=3 and #values~=4 then return end
		local rgba=appearance.rgba(key,values)
		for i=1,#values do local n=tonumber(values[i]);if not n or n~=math.floor(n) or n<0 or n>255 then return end end
		return appearance.hex(rgba)
	elseif sounds[key] then
		local value=values[1];if not value or value=="None" then return end
		if key=="PlayAlertSound" or key=="PlayAlertSoundPositional" then
			local number=tonumber(value);if not number or number~=math.floor(number) or number<1 or number>16 then return end
			return tostring(number)
		end
		return value
	end
end
local function normalized(key,value,allowNone)
	assert(type(value)=="string" and #value>0 and #value<=1000 and not value:find('["\r\n%z]'),"Invalid shared style value")
	if colours[key] or key=="Colour" then
		local rgba=appearance.fromHex(value);assert(rgba and #value==8,"Use an eight-digit RGBA colour")
		return appearance.hex(rgba)
	end
	assert(sounds[key] or groups[key],"Unknown shared style")
	if allowNone and value=="None" then return value end
	if key=="PlayAlertSound" or key=="PlayAlertSoundPositional" or key=="AlertSound" then
		local n=tonumber(value);assert(n and n==math.floor(n) and n>=1 and n<=16,"Choose an alert from 1 to 16");return tostring(n)
	end
	assert(not value:find('[%c]') and value~="None","Invalid custom sound")
	return value
end
function M.validate(entries)
	assert(type(entries)=="table" and entries~=require("dkjson").null,"Invalid shared styles")
	assert(not getmetatable(entries) or getmetatable(entries).__jsontype~="object","Expected a shared-style list")
	local result,seen={},{}
	for key in pairs(entries) do assert(type(key)=="number" and key==math.floor(key) and key>=1 and key<=#entries,"Expected a dense shared-style list") end
	for _,entry in ipairs(entries) do
		assert(type(entry)=="table","Invalid shared style")
		local key=entry.key;assert(colours[key] or sounds[key] or groups[key],"Unknown shared style")
		local from,to=normalized(key,entry.from),normalized(key,entry.to,true);local id=key.."\0"..from
		assert(not seen[id],"Duplicate shared style source");seen[id]=true
		result[#result+1]={key=key,from=from,to=to}
	end
	return result
end
-- Preserve comments and quoted sound paths while identifying declared values.
local function comment(line)
	local quoted=false
	for i=1,#line do local char=line:sub(i,i);if char=='"' then quoted=not quoted elseif char=="#" and not quoted then return line:sub(i) end end
end
local function visit(raw,callback)
	local output,block={},false
	for line in (raw.."\n"):gmatch("([^\n]*)\n") do
		local ok,tokens,quoted=pcall(parser.tokens,line);local key=ok and tokens[1]
		if key=="Show" or key=="Hide" or key=="Minimal" or key=="Import" then block=key~="Import"
		elseif block and (colours[key] or sounds[key]) then
			local values={};for i=2,#tokens do values[#values+1]=tokens[i] end
			local value=canonical(key,values)
			if value then line=callback(key,value,line,tokens,quoted) or line end
		end
		output[#output+1]=line
	end
	return table.concat(output,"\n")
end
function M.list(raw)
	local counts={};visit(raw,function(key,value)
		for _,kind in ipairs({key,group(key)}) do local id=kind.."\0"..value;local row=counts[id];if row then row.count=row.count+1 else row={key=kind,value=value,count=1,types={}};counts[id]=row end;row.types[key]=true end
	end)
	local rows={};for _,row in pairs(counts) do rows[#rows+1]=row end
	table.sort(rows,function(a,b) return a.key==b.key and a.value<b.value or a.key<b.key end);return rows
end
function M.apply(raw,entries)
	local lookup={};for _,entry in ipairs(M.validate(entries or {})) do lookup[entry.key.."\0"..entry.from]=entry.to end
	if not next(lookup) then return raw end
	return visit(raw,function(key,value,line,tokens,quoted)
		local target=lookup[key.."\0"..value] or lookup[group(key).."\0"..value];if not target then return end
		local prefix=line:match("^%s*") or "";local values={}
		if colours[key] then for i=1,8,2 do values[#values+1]=tostring(tonumber(target:sub(i,i+1),16)) end
		else values[1]=(key=="CustomAlertSound" or key=="CustomAlertSoundOptional") and ('"'..target..'"') or target;if target~="None" then for i=3,#tokens do values[#values+1]=quoted[i] and ('"'..tokens[i]..'"') or tokens[i] end end end
		local suffix=comment(line);return prefix..key.." "..table.concat(values," ")..(suffix and " "..suffix or "")
	end)
end
return M
