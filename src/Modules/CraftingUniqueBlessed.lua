-- Conditional model for a recognized, single-line ordinary unique base implicit.
local M={}
local function plan(raw)
	local ok,item,info=pcall(require("Modules.CraftingUniqueQuality").inspect,raw)
	if not ok then return nil,(tostring(item):gsub("^.-:%d+: ","")) end
	if item.corrupted then return nil,"Blessed Orbs cannot modify a corrupted item" end
	if item.synthesised or item.base.blessed330 or (item.catalyst and info.quality>0) or #(item.modMagnitudeMods or {})>0 then return nil,"This implicit needs a separate Blessed Orb model" end
	local lines=item.implicitModLines or {};local template=item.base.implicit
	if #lines~=1 or type(template)~="string" or template:find("[\r\n]") then return nil,"A single recognized ordinary base implicit is required" end
	local line=lines[1]
	if line.disabled or line.custom or line.corrupted or line.crafted or line.fractured or line.enchant or line.exarch or line.eater or line.unscalable or line.modTags and #line.modTags>0 then return nil,"Special implicit modifiers need a separate Blessed Orb model" end
	local low,high=template:match("%((%-?%d+)%-(%-?%d+)%)");low,high=tonumber(low),tonumber(high)
	local _,count=template:gsub("%(%-?%d+%.?%d*%-%-?%d+%.?%d*%)","")
	if not low or not high or count~=1 or high<=low or high-low>1000 or template:find("%-%(") then return nil,"This base implicit needs a separate roll model" end
	local shown=StripEscapes(itemLib.formatModLine(line,false) or "");local choices={};local current
	for value=low,high do
		local display=itemLib.applyRange(template,(value-low)/(high-low))
		if choices[display] then return nil,"Different base rolls produce the same displayed implicit" end
		choices[display]=value;if display==shown then current=value end
	end
	if current==nil then return nil,"The implicit does not match the current base range" end
	local source,suffix,occurrences=nil,nil,0
	for row in raw:gmatch("[^\r\n]+") do
		if row==shown or row==shown.." (implicit)" then source=row;suffix=row==shown and "" or " (implicit)";occurrences=occurrences+1 end
	end
	if occurrences~=1 then return nil,"The original implicit line could not be identified uniquely" end
	return {item=item,template=template,low=low,high=high,current=current,source=source,suffix=suffix}
end
function M.reason(raw) local _,reason=plan(raw);return reason end
function M.options(raw)
	local p,reason=plan(raw);if not p then return nil,reason end
	return {line=p.template,min=p.low,max=p.high,current=p.current}
end
function M.roll(raw,seed)
	local p,reason=plan(raw);assert(p,reason);assert(type(seed)=="number" and seed==math.floor(seed) and seed>=1 and seed<=2147483646,"Invalid seed")
	local random=require("Modules.CalcTime").random(seed);local value=p.low+math.floor(random()*(p.high-p.low+1))
	local display=itemLib.applyRange(p.template,(value-p.low)/(p.high-p.low));local replacements=0
	local output=raw:gsub("[^\r\n]+",function(line) if line==p.source then replacements=replacements+1;return display..p.suffix end;return line end)
	assert(replacements==1,"The implicit line could not be replaced safely")
	local after=require("Modules.CraftingUniqueQuality").inspect(output)
	assert(after.title==p.item.title and after.baseName==p.item.baseName and not after.corrupted and #after.implicitModLines==1 and StripEscapes(itemLib.formatModLine(after.implicitModLines[1],false) or "")==display,"The rerolled implicit did not round-trip")
	return {itemText=output,components={blessed=1}}
end
return M
