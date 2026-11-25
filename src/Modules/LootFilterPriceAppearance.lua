local json = require("dkjson")
local parser = require("Modules.LootFilterParser")
local areas = require("Modules.LootFilterPickupAreas")
local M = {}
local begin = "# PoB price highlight begin "
local stop = "# PoB price highlight end"
local bom = "\239\187\191"
M.presets = {
	{val="yellow-circle",label="Yellow circle",icon="1 Yellow Circle",effect="Yellow"},
	{val="orange-star",label="Orange star",icon="0 Orange Star",effect="Orange"},
	{val="cyan-diamond",label="Cyan diamond",icon="0 Cyan Diamond",effect="Cyan"},
	{val="purple-star",label="Purple star",icon="0 Purple Star",effect="Purple"},
	{val="red-diamond",label="Red diamond",icon="0 Red Diamond",effect="Red"},
	{val="green-hexagon",label="Green hexagon",icon="1 Green Hexagon",effect="Green"},
}
local defaults = {M.presets[1],M.presets[2]}
local styles = {}
for _, style in ipairs(M.presets) do styles[style.val] = style end

local function styleFor(tier, palette)
	if not defaults[tier] then return nil end
	if palette==nil then return defaults[tier] end
	return styles[palette]
end

function M.validPalette(palette)
	return type(palette)=="string" and styles[palette]~=nil
end

function M.icon(tier, palette)
	return assert(styleFor(tier,palette),"Invalid price highlight style").icon
end

local function whole(value, minimum, maximum)
	return type(value)=="number" and value>=minimum and value<=maximum and value==math.floor(value)
end

function M.settings(settings)
	if settings==nil then return nil end
	assert(type(settings)=="table","Invalid price highlight actions")
	local count = 0
	for key in pairs(settings) do
		assert(key=="sound" or key=="volume" or key=="fontSize","Unsupported price highlight action")
		count=count+1
	end
	assert(settings.sound==nil or whole(settings.sound,1,16),"Choose a built-in sound from 1 to 16")
	assert(settings.volume==nil or settings.sound and whole(settings.volume,0,300),"Choose a sound before setting its volume from 0 to 300")
	assert(settings.fontSize==nil or whole(settings.fontSize,1,45),"Enter a label size from 1 to 45")
	if count>0 then return {sound=settings.sound,volume=settings.volume,fontSize=settings.fontSize} end
end

local alertSounds = {PlayAlertSound=true,PlayAlertSoundPositional=true,CustomAlertSound=true,CustomAlertSoundOptional=true}
local function replaced(keyword, settings)
	return keyword=="MinimapIcon" or keyword=="PlayEffect"
		or settings and (settings.sound and alertSounds[keyword] or settings.fontSize and keyword=="SetFontSize")
end

local function appendActions(lines, style, settings)
	lines[#lines+1]="    MinimapIcon "..style.icon
	lines[#lines+1]="    PlayEffect "..style.effect
	if settings and settings.fontSize then lines[#lines+1]="    SetFontSize "..settings.fontSize end
	if settings and settings.sound then lines[#lines+1]="    PlayAlertSound "..settings.sound.." "..(settings.volume or 50) end
end

function M.styleUnique(rule, tier, palette, settings, newline)
	local lines = {}
	for _, raw in ipairs(rule.rawLines) do
		local line = raw:gsub("\r$","")
		if not replaced(parser.tokens(line)[1],settings) then lines[#lines+1]=line end
	end
	appendActions(lines,assert(styleFor(tier,palette),"Invalid price highlight style"),settings)
	return table.concat(lines,newline)..newline
end

function M.resultActions(result)
	if result.action~="Show" then return nil end
	local styles = result.styles
	local alert = not (styles.CustomAlertSound or styles.CustomAlertSoundOptional)
		and (styles.PlayAlertSoundPositional or styles.PlayAlertSound)
	local sound, volume
	if alert and whole(tonumber(alert[1]),1,16) then
		sound = tonumber(alert[1])
		volume = tonumber(alert[2]) or 50
	end
	local fontSize = styles.SetFontSize and tonumber(styles.SetFontSize[1])
	if fontSize or sound then return {fontSize=fontSize,sound=sound,volume=volume} end
end

local function linesOf(raw)
	local lines = {}
	for line in raw:gmatch("[^\n]*\n?") do
		if line~="" then lines[#lines+1] = line end
	end
	return lines
end

local function plain(line)
	return (line:gsub("\r?\n$",""))
end

local function contains(values,value)
	for _, candidate in ipairs(values) do if candidate==value then return true end end
	return false
end

local function validInteger(value)
	return type(value)=="number" and value>=1 and value<=10000 and value==math.floor(value)
end

local function exactShow(rule)
	if not rule or rule.action~="Show" or rule.continue then return nil end
	local class, base
	for _, condition in ipairs(rule.conditions) do
		if condition.keyword=="Class" then
			if class or condition.operator~="==" or #condition.values~=1 then return nil end
			class = condition.values[1]
		elseif condition.keyword=="BaseType" then
			if base or condition.operator~="==" then return nil end
			base = condition.values
		end
	end
	if class and base then return class,base end
end

local function duplicate(rule,spec,base)
	local style = type(spec)=="table" and styleFor(spec.tier,spec.style)
	assert(style and type(spec.name)=="string" and #spec.name<=200
		and not spec.name:find('[%c"\\]') and contains(base,spec.name)
		and validInteger(spec.firstStack) and (not spec.upper or validInteger(spec.upper) and spec.upper>spec.firstStack)
		and (spec.area==nil or spec.area=="<" or spec.area==">=")
		and (spec.band==nil or spec.area==nil and areas.bands[spec.band]),
		"Invalid generated price highlight")
	local settings = M.settings(spec.actions)
	local lines = {"Show"}
	for offset=2,#rule.rawLines do
		local line = rule.rawLines[offset]
		line = line:gsub("\r$","")
		local keyword = parser.tokens(line)[1]
		if keyword=="BaseType" then
			lines[#lines+1]='    BaseType == "'..spec.name..'"'
		elseif not replaced(keyword,settings) then
			lines[#lines+1]=line
		end
	end
	lines[#lines+1]="    StackSize >= "..spec.firstStack
	if spec.upper then lines[#lines+1]="    StackSize < "..spec.upper end
	if spec.area then lines[#lines+1]="    AreaLevel "..spec.area.." 68" end
	if spec.band then
		for _, condition in ipairs(areas.bands[spec.band].conditions) do lines[#lines+1]=condition end
	end
	appendActions(lines,style,settings)
	return lines
end

local function render(rule,specs,base,newline)
	-- cspell:ignore keyorder
	local lines={begin..assert(json.encode(specs,{keyorder={"name","firstStack","upper","tier","area","style","band","actions","sound","volume","fontSize"}}))}
	for _, spec in ipairs(specs) do
		for _, line in ipairs(duplicate(rule,spec,base)) do lines[#lines+1]=line end
	end
	lines[#lines+1]=stop
	return table.concat(lines,newline)..newline
end

function M.apply(raw,byClass)
	if not next(byClass) then return raw end
	local parsed = parser.parse(raw)
	if #parsed.imports>0 or #parsed.diagnostics>0 then return raw end
	local prefix = raw:sub(1,3)==bom and bom or ""
	local lines,insertions = linesOf(raw:sub(#prefix+1)),{}
	local newline=raw:find("\r\n",1,true) and "\r\n" or "\n"
	for _, rule in ipairs(parsed.rules) do
		local class,base=exactShow(rule)
		local applicable=class and byClass[class]
		if applicable then
			local specs = {}
			for _, name in ipairs(base) do
				if applicable[name] then
					for _, spec in ipairs(applicable[name]) do specs[#specs+1]=spec end
				end
			end
			if #specs>0 then insertions[rule.line]=render(rule,specs,base,newline) end
		end
	end
	local output={prefix}
	for index,line in ipairs(lines) do
		if insertions[index] then output[#output+1]=insertions[index] end
		output[#output+1]=line
	end
	return table.concat(output)
end

-- Only remove a marked overlay when it is an exact decoration of the
-- immediately following Show. The ordinary filter source stays verifiable.
function M.strip(raw)
	if not raw:find(begin,1,true) then return raw end
	local parsed=parser.parse(raw)
	local rules={}
	for _, rule in ipairs(parsed.rules) do rules[rule.line]=rule end
	local prefix = raw:sub(1,3)==bom and bom or ""
	local lines,output=linesOf(raw:sub(#prefix+1)),{prefix}
	local index=1
	while index<=#lines do
		local line=plain(lines[index])
		if line:sub(1,#begin)==begin then
			local last=index+1
			while lines[last] and plain(lines[last])~=stop do last=last+1 end
			local following=rules[last+1]
			local class,base=exactShow(following)
			local specs,offset=json.decode(line:sub(#begin+1))
			assert(lines[last] and class and type(specs)=="table" and #specs>0 and #specs<=10000
				and not line:sub(#begin+offset):find("%S"),"Invalid generated price highlight")
			local newline=lines[index]:sub(-2)=="\r\n" and "\r\n" or "\n"
			-- Compare the same canonical content, including every original
			-- condition and setting except the two owned visual directives.
			local actual=table.concat(lines,"",index,last)
			local expected=render(following,specs,base,newline)
			assert(actual==expected,"Generated price highlight differs from its source rule")
			index=last+1
		else
			output[#output+1]=lines[index]
			index=index+1
		end
	end
	return table.concat(output)
end

return M
