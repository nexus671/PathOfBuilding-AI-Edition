-- cspell:ignore RGBWAD
-- Data-only PoE filter parsing. Unknown conditions produce an explained unknown,
-- never a falsely certain hidden/shown result. Imports are not read from disk.
local M={}
-- GGG's item-filter reference marks these conditions as PoE 2-only.
M.poe2Only={AlwaysShow=true,HasVaalUniqueMod=true,IsVaalUnique=true,WaystoneTier=true}
function M.actionReason(mode,action)
	if mode=="Normal" and action=="Minimal" then return "Minimal is available only in Ruthless. Choose Show or Hide." end
	if mode=="Ruthless" and action=="Hide" then return "Ruthless cannot hide drops. Choose Show or Minimal." end
end
function M.actionChoices(mode,current)
	local choices=mode=="Normal" and {"Show","Hide"} or mode=="Ruthless" and {"Show","Minimal"} or {"Show","Hide","Minimal"}
	-- Keep an existing incompatible choice visible so it can be repaired.
	if current and M.actionReason(mode,current) then choices[#choices+1]=current end
	return choices
end
local styleOptions=require("Modules.LootFilterAppearanceSettings");local colors,shapes={},{}
for _,value in ipairs(styleOptions.colors) do colors[value]=true end;for _,value in ipairs(styleOptions.shapes) do shapes[value]=true end
M.actions={SetTextColor=true,SetBorderColor=true,SetBackgroundColor=true,SetFontSize=true,PlayAlertSound=true,PlayAlertSoundPositional=true,
	CustomAlertSound=true,CustomAlertSoundOptional=true,DisableDropSound=true,EnableDropSound=true,DisableDropSoundIfAlertSound=true,EnableDropSoundIfAlertSound=true,MinimapIcon=true,PlayEffect=true}
M.numeric={AreaLevel=true,ItemLevel=true,DropLevel=true,Quality=true,LinkedSockets=true,Sockets=true,Width=true,Height=true,StackSize=true,GemLevel=true,MapTier=true,
	BaseArmour=true,BaseEvasion=true,BaseEnergyShield=true,BaseWard=true,BaseDefencePercentile=true,EnchantmentPassiveNum=true,CorruptedMods=true,
	HasEaterOfWorldsImplicit=true,HasSearingExarchImplicit=true,UnidentifiedItemTier=true,MemoryStrands=true}
M.booleans={AlwaysShow=true,Identified=true,Corrupted=true,TwiceCorrupted=true,Mirrored=true,FracturedItem=true,SynthesisedItem=true,ShaperItem=true,ElderItem=true,ShapedMap=true,ElderMap=true,
	BlightedMap=true,UberBlightedMap=true,Replica=true,Scourged=true,HasImplicitMod=true,AnyEnchantment=true,HasCruciblePassiveTree=true,Foulborn=true,Fated=true,Exceptional=true,TransfiguredGem=true,AlternateQuality=true,Imbued=true,Vestigial=true,ZanaMemory=true,MirageMap=true}
M.strings={Class=true,BaseType=true,HasInfluence=true,HasExplicitMod=true,HasEnchantment=true,EnchantmentPassiveNode=true,Prophecy=true,ArchnemesisMod=true,GemQualityType=true}
local rarity={Normal=0,Magic=1,Rare=2,Unique=3}
local influences={shaper=true,elder=true,crusader=true,hunter=true,redeemer=true,warlord=true,none=true}
local dropSoundPairs={{"DisableDropSound","EnableDropSound"},{"DisableDropSoundIfAlertSound","EnableDropSoundIfAlertSound"}}
-- Some filters put a second operator after a modifier count. Preserve it as
-- syntax, not a quoted modifier name; its combined semantics need verification.
function M.countExactMarker(condition,index)
	return (condition.keyword=="HasExplicitMod" or condition.keyword=="HasEnchantment")
		and index==2 and not (condition.quoted and (condition.quoted[1] or condition.quoted[2]))
		and tonumber(condition.values[1])~=nil and condition.values[2]=="=="
end
-- A boolean plus extra values may be rejected or interpreted differently by
-- the game. Named TransfiguredGem lists are a separate supported form.
function M.ambiguousBoolean(condition)
 if not M.booleans[condition.keyword] or #condition.values<=1 then return false end
 if condition.keyword~="TransfiguredGem" then return true end
 for _,value in ipairs(condition.values) do if value=="True" or value=="False" then return true end end
 return false
end
function M.tokens(line)
	local out,quoted={},{};local pos=1
	while pos<=#line do
		local char=line:sub(pos,pos)
		if char=="#" then break
		elseif char:match("%s") then pos=pos+1
		elseif char=='"' then
			local last=line:find('"',pos+1,true);assert(last,"Unclosed quoted value")
			out[#out+1]=line:sub(pos+1,last-1);quoted[#out]=true;pos=last+1
		else local last=line:find('[%s#]',pos) or #line+1;out[#out+1]=line:sub(pos,last-1);quoted[#out]=false;pos=last end
	end
	return out,quoted
end
function M.parse(raw)
	assert(type(raw)=="string" and #raw<=2*1024*1024,"Filter exceeds 2 MiB")
	local result={rules={},diagnostics={},imports={}};local current;local title
	for line in (raw:gsub("^\239\187\191","").."\n"):gmatch("([^\n]*)\n") do
		local ok,t,quoted=pcall(M.tokens,line);local lineNo=(result.lineCount or 0)+1;result.lineCount=lineNo
		title=line:match("^%s*# PoB rule: (.*)") or title
		if not ok then result.diagnostics[#result.diagnostics+1]={line=lineNo,error=t}
		elseif #t>0 then
			local key=table.remove(t,1);table.remove(quoted,1)
			if key=="Show" or key=="Hide" or key=="Minimal" then
				current={action=key,line=lineNo,title=title,conditions={},styles={},rawLines={line}};title=nil;result.rules[#result.rules+1]=current
				if #t>0 then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="Unexpected values after "..key} end
			elseif key=="Import" then
				if #t<1 or #t>2 or not t[1]:match("%S") or #t==2 and t[2]~="Optional" then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="Invalid Import; specify a file and optional Optional keyword"}
				else result.imports[#result.imports+1]={line=lineNo,file=t[1],optional=t[2]=="Optional"} end
				current=nil
			elseif not current then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="Expected Show, Hide or Minimal before "..key}
			else
				current.rawLines[#current.rawLines+1]=line
				if key=="Continue" then
					current.continue=true
					if #t>0 then result.diagnostics[#result.diagnostics+1]={line=lineNo,warning="Continue arguments need in-game verification; original text is preserved",unverifiedContinue=true} end
				elseif M.actions[key] then
					current.styles[key]=t
					local invalid
					if key=="SetTextColor" or key=="SetBorderColor" or key=="SetBackgroundColor" then
						invalid=#t<3 or #t>4;for _,v in ipairs(t) do local n=tonumber(v);if not n or n<0 or n>255 or n~=math.floor(n) then invalid=true end end
					elseif key=="SetFontSize" then local n=tonumber(t[1]);invalid=#t~=1 or not n or n<1 or n>45 or n~=math.floor(n)
					elseif key=="PlayAlertSound" or key=="PlayAlertSoundPositional" or key=="CustomAlertSound" or key=="CustomAlertSoundOptional" then
						local custom=key=="CustomAlertSound" or key=="CustomAlertSoundOptional";local id=tonumber(t[1]);local volume=tonumber(t[2])
						invalid=#t<1 or #t>2 or not t[1] or not t[1]:match("%S")
						if not custom and t[1]~="None" and (not id or id~=math.floor(id) or id<1 or id>16) then invalid=true end
						if t[2] and (not volume or volume~=math.floor(volume) or volume<0 or volume>300) then invalid=true end
					elseif key=="MinimapIcon" then local size=tonumber(t[1]);invalid=not (#t==1 and size==-1) and (#t~=3 or not size or size<0 or size>2 or size~=math.floor(size) or not colors[t[2]] or not shapes[t[3]])
					elseif key=="PlayEffect" then invalid=not (#t==1 and t[1]=="None") and (not colors[t[1]] or #t>2 or #t==2 and t[2]~="Temp") end
					if invalid then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="Invalid "..key} end
				else
					local op="=";local first=t[1] or "";local prefix=not quoted[1] and first:match("^[<>=!]+")
					local separated=prefix and #first==#prefix
					if prefix then op=prefix;t[1]=first:sub(#prefix+1);if t[1]=="" then table.remove(t,1);table.remove(quoted,1) end end
					local known=M.numeric[key] or M.booleans[key] or M.strings[key] or key=="Rarity" or key=="SocketGroup"
					local condition={keyword=key,operator=op,values=t,quoted=quoted,known=known,line=lineNo}
					current.conditions[#current.conditions+1]=condition
					if M.ambiguousBoolean(condition) then result.diagnostics[#result.diagnostics+1]={line=lineNo,warning="Preview cannot verify multiple boolean values; original text is preserved"} end
					if M.countExactMarker(condition,2) then result.diagnostics[#result.diagnostics+1]={line=lineNo,warning="Preview cannot verify modifier count with a separate exact-match operator; original text is preserved"} end
					if #t==0 then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="Condition requires a value: "..key}
					elseif not known then result.diagnostics[#result.diagnostics+1]={line=lineNo,warning="Simulator cannot resolve "..key.."; original text is preserved"} end
					if not ({["="]=true,["=="]=true,["!="]=true,["!"]=true,[">="]=true,["<="]=true,[">"]=true,["<"]=true})[op] then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="Invalid operator "..op} end
					if (key=="HasExplicitMod" or key=="HasEnchantment") and separated and not quoted[1] and tonumber(t[1]) then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="Join the operator and modifier count for "..key} end
					if M.booleans[key] and (key~="TransfiguredGem" and t[1]~="True" and t[1]~="False" or op~="=" and op~="==" and op~="!" and op~="!=") then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="Invalid boolean "..key} end
					if key=="UnidentifiedItemTier" then local n=tonumber(t[1]);if not n or n<0 or n>5 or n~=math.floor(n) then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="UnidentifiedItemTier must be 0 to 5"} end end
					if key=="SocketGroup" or key=="Sockets" then for _,value in ipairs(t) do
						if value=="" or not value:match("^%d*[RGBWAD]*$") and not (key=="Sockets" and tonumber(value)) then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="Invalid socket pattern for "..key};break end
					end end
					if M.numeric[key] and key~="Sockets" then for _,value in ipairs(t) do local n=tonumber(value);if not n or n~=n or math.abs(n)==math.huge then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="Invalid numeric value for "..key};break end end end
				end
			end
		end
	end
	return result
end
local function compare(a,b,op)
	if op=="=" or op=="==" then return a==b elseif op=="!" or op=="!=" then return a~=b elseif op==">=" then return a>=b elseif op=="<=" then return a<=b elseif op==">" then return a>b elseif op=="<" then return a<b end
end
local function socketMatch(value,pattern,op)
	local required={};local number=tonumber(pattern:match("^%d+"))
	for color in pattern:gmatch("[RGBWAD]") do required[color]=(required[color] or 0)+1 end
	local available={};local count=0;for color in value:gmatch("[RGBWAD]") do available[color]=(available[color] or 0)+1;count=count+1 end
	-- Without an explicit count, exact colour matching also excludes extra
	-- colours: == RRR describes a three-socket all-red group.
	if op=="==" and not number then number=0;for _,n in pairs(required) do number=number+n end end
	-- GGG defines strict comparisons as any specified count being greater or less.
	if op=="<" or op==">" then
		if number and compare(count,number,op) then return true end
		for color,n in pairs(required) do if compare(available[color] or 0,n,op) then return true end end
		return false
	end
	if number and not compare(count,number,op) then return false end
	local colorOp=op=="==" and "==" or (op=="!" or op=="!=") and op or ">="
	for color,n in pairs(required) do if not compare(available[color] or 0,n,colorOp) then return false end end
	return true
end
-- SocketColours and SocketGroup both describe the complete set when supplied.
-- Compare counts rather than order: link groups can list the colours differently.
local function socketConsistency(item)
	local function colours(value,group)
		if type(value)~="string" then return nil,nil,"Invalid socket colours" end
		if group and (value=="" or value=="0") then return {},0 end
		if not group and value=="" then return nil,nil end
		if value:find("[^RGBWAD%s%-]") then return nil,nil,"Invalid socket colours" end
		local counts,total={},0
		for colour in value:gmatch("[RGBWAD]") do counts[colour]=(counts[colour] or 0)+1;total=total+1 end
		if total==0 or total>6 then return nil,nil,"Invalid socket colours" end
		return counts,total
	end
	local a,na,err
	if item.SocketColours~=nil then a,na,err=colours(item.SocketColours,false);if err then return err end end
	local b,nb
	if item.SocketGroup~=nil then b,nb,err=colours(item.SocketGroup,true);if err then return err end end
	local count=tonumber(item.Sockets)
	if count and na and count~=na then return "Socket count does not match socket colours" end
	if count and nb and count~=nb then return "Socket group layout does not account for the stated socket count" end
	if a and b then
		for _,colour in ipairs({"R","G","B","W","A","D"}) do
			if (a[colour] or 0)~=(b[colour] or 0) then return "Socket colours conflict with socket group layout" end
		end
	end
	local linked=tonumber(item.LinkedSockets)
	if linked and na and linked>na then return "Linked socket count exceeds total socket colours" end
	if linked==0 and ((count and count>0) or (na and na>0) or (nb and nb>0)) then
		return "Zero linked sockets conflicts with sockets on the item"
	end
end
local function influenceState(item)
	local value=item.HasInfluence;if value==nil then return nil end
	local entries=type(value)=="table" and value or {value};local present={};local count=0;local keys=0
	for key in pairs(entries) do if type(key)~="number" or key<1 or key~=math.floor(key) then return nil,nil,"Invalid HasInfluence sample" end;keys=keys+1 end
	if keys~=#entries then return nil,nil,"Invalid HasInfluence sample" end
	for _,entry in ipairs(entries) do
		if type(entry)~="string" or not influences[entry:lower()] then return nil,nil,"Invalid HasInfluence sample" end
		local name=entry:lower();if not present[name] then present[name]=true;count=count+1 end
	end
	for i=1,keys do if entries[i]==nil then return nil,nil,"Invalid HasInfluence sample" end end
	if count==0 then present.none=true;count=1 end
	if present.none and count>1 then return nil,nil,"An uninfluenced sample cannot have other influences" end
	for _,name in ipairs({"Shaper","Elder"}) do
		local flag=item[name.."Item"]
		if flag~=nil and (type(flag)~="boolean" or flag~=(present[name:lower()]==true)) then return nil,nil,name.." item flag conflicts with influence list" end
	end
	return present,count
end
function M.condition(c,item)
	if c.keyword=="Sockets" or c.keyword=="SocketGroup" or c.keyword=="LinkedSockets" then
		local reason=socketConsistency(item);if reason then return nil,reason end
	end
	if not c.known then return nil,"Unsupported condition "..c.keyword end
	if M.countExactMarker(c,2) then return nil,"Modifier count with a separate exact-match operator is not yet verified" end
	if M.ambiguousBoolean(c) then return nil,"Multiple boolean values are not verified" end
	if c.keyword=="HasExplicitMod" and item.Identified~=true then
		return nil,item.Identified==false and "Explicit modifiers are hidden on unidentified items" or "Supply identification state for explicit modifiers"
	end
	local value=item[c.keyword];local present,influenceCount
	-- Memory Strands occur on equipment, not stackable currency. Positive
	-- thresholds therefore cannot match a currency example even if its strand
	-- count was not supplied. Keep other comparisons and equipment unknown.
	if c.keyword=="MemoryStrands" and value==nil and item.Class=="Stackable Currency" and #c.values==1 then
		local threshold=tonumber(c.values[1])
		if threshold and ((c.operator==">" and threshold>=0) or (c.operator==">=" and threshold>0)) then return false end
	end
	if (c.keyword=="HasInfluence" or c.keyword=="ShaperItem" or c.keyword=="ElderItem") and item.HasInfluence~=nil then
		local reason;present,influenceCount,reason=influenceState(item);if reason then return nil,reason end
		if c.keyword~="HasInfluence" and value==nil then value=present[c.keyword=="ShaperItem" and "shaper" or "elder"]==true end
	end
	local partialExplicit=c.keyword=="HasExplicitMod" and value==nil and type(item.KnownExplicitMods)=="table"
	if partialExplicit then value=item.KnownExplicitMods end
	if c.keyword=="SocketGroup" and value==nil and tonumber(item.Sockets)==0 then value="0" end
	if c.keyword=="LinkedSockets" then
		local count=tonumber(item.Sockets);local groups=item.SocketGroup;local derived
		-- A complete colour list establishes the total even when the separate
		-- socket-count field was left blank. socketConsistency checked its shape.
		if item.Sockets==nil and type(item.SocketColours)=="string" and item.SocketColours:match("%S") then count=select(2,item.SocketColours:gsub("[RGBWAD]","")) end
		local supplied=value~=nil and tonumber(value) or nil
		if value~=nil and (not supplied or supplied<0 or supplied>6 or supplied~=math.floor(supplied)) then return nil,"Invalid LinkedSockets" end
		if item.Sockets~=nil and (not count or count<0 or count>6 or count~=math.floor(count)) then return nil,"Invalid Sockets" end
		if supplied and count and supplied>count then return nil,"Linked socket count exceeds total sockets" end
		if type(groups)=="string" then
			if groups=="" or groups=="0" then
				if count==nil or count==0 then derived=0 elseif supplied then return nil,"Socket group layout does not account for the stated socket count" end
			elseif groups:find("[^RGBWAD%s%-]") then return nil,"Invalid socket colours for SocketGroup"
			else
				local total=select(2,groups:gsub("[RGBWAD]",""));local largest=0
				local separated=groups:gsub("([AD])"," %1 "):gsub("%-","")
				for group in separated:gmatch("%S+") do largest=math.max(largest,#group) end
				if count and count==total and total>0 and total<=6 then derived=largest
				elseif count and supplied then return nil,"Socket group layout does not account for the stated socket count" end
			end
		elseif count==0 then derived=0 end
		if supplied and derived and supplied~=derived then return nil,"Linked socket count conflicts with socket group layout" end
		if value==nil then value=derived end
	end
	if c.keyword=="Sockets" and value==nil and type(item.SocketColours)=="string" and item.SocketColours:match("%S") then
		if item.SocketColours:find("[^RGBWAD%s%-]") then return nil,"Invalid socket colours for Sockets" end
		local count=select(2,item.SocketColours:gsub("[RGBWAD]",""))
		if count<1 or count>6 then return nil,"Invalid socket colours for Sockets" end
		value=count
	end
	if value==nil then return nil,"Missing "..c.keyword end
	local op=c.operator;local values=c.values
	if c.keyword=="HasInfluence" then
		if op~="=" and op~="==" and op~="!" and op~="!=" then return nil,"Unsupported HasInfluence operator" end
		local wanted={};local wantedCount=0
		for _,entry in ipairs(values) do
			local name=entry:lower();if not influences[name] then return nil,"Unsupported influence name" end
			if not wanted[name] then wanted[name]=true;wantedCount=wantedCount+1 end
		end
		if op=="==" then
			for name in pairs(wanted) do if not present[name] then return false end end
			if wantedCount<influenceCount then return nil,"Exact matching with additional influences is not verified" end
			return true
		end
		local found=false;for name in pairs(wanted) do if present[name] then found=true;break end end
		if op=="!" or op=="!=" then return not found end
		return found
	elseif c.keyword=="Sockets" then
		local count=tonumber(value);local colours=item.SocketColours or (count==0 and "") or (not count and type(value)=="string" and value or nil);local unknown
		local negative=op=="!" or op=="!="
		for _,pattern in ipairs(values) do
			local number=tonumber(pattern);local pass
			if number then
				if count then pass=compare(count,number,op) else unknown="Invalid Sockets" end
			elseif negative then unknown="Negative socket-colour comparisons are not verified"
			elseif type(colours)~="string" then unknown="Supply socket colours for Sockets"
			elseif colours:find("[^RGBWAD%s%-]") then unknown="Invalid socket colours for Sockets"
			elseif count and select(2,colours:gsub("[RGBWAD]",""))~=count then unknown="Socket count does not match socket colours"
			else pass=socketMatch(colours,pattern,op) end
			if pass~=nil and (negative and not pass or not negative and pass) then return not negative end
		end
		if unknown then return nil,unknown end
		return negative
	end
	if c.keyword=="SocketGroup" then
		if item.LinkedSockets~=nil then
			local valid,reason=M.condition({keyword="LinkedSockets",known=true,operator="=",values={tostring(item.LinkedSockets)}},item)
			if valid==nil then return nil,reason end
		end
		if op=="!" or op=="!=" then return nil,"Negative linked-socket comparisons are not verified" end
		if type(value)~="string" then return nil,"Supply socket colours for "..c.keyword end
		local total=select(2,value:gsub("[RGBWAD]",""))
		local count=item.Sockets~=nil and tonumber(item.Sockets) or nil
		if item.Sockets~=nil and (not count or count~=total) then return nil,"Socket group layout does not account for the stated socket count" end
		if total>6 or total==0 and value~="" and value~="0" then return nil,"Invalid socket colours for SocketGroup" end
		if value=="0" or value=="" then
			for _,pattern in ipairs(values) do if socketMatch("",pattern,op) then return true end end
			return false
		end
		if value:find("[^RGBWAD%s%-]") then return nil,"Invalid socket colours for "..c.keyword end
		for _,pattern in ipairs(values) do
			-- Abyss and Delve sockets cannot link to other sockets, even when
			-- a manually entered sample places them inside a group.
			local separated=value:gsub("([AD])"," %1 ")
			for group in separated:gmatch("%S+") do if socketMatch(group,pattern,op) then return true end end
		end;return false
	elseif M.numeric[c.keyword] or c.keyword=="Rarity" then
		value=c.keyword=="Rarity" and rarity[value] or tonumber(value)
		if value==nil then return nil,"Invalid "..c.keyword end
		local negative=op=="!" or op=="!="
		for _,v in ipairs(values) do local n=c.keyword=="Rarity" and rarity[v] or tonumber(v);if not n then return nil,"Invalid numeric value for "..c.keyword end
			if negative and value==n then return false elseif not negative and compare(value,n,op) then return true end
		end
		return negative
	elseif M.booleans[c.keyword] then
		if c.keyword=="TransfiguredGem" then
			if type(value)~="boolean" and (type(value)~="string" or not value:match("%S")) then return nil,"Supply a transfigured gem state or base name" end
			if values[1]=="True" or values[1]=="False" then return compare(value==true or type(value)=="string",values[1]=="True",op) end
			if value==false then return op=="!" or op=="!=" end
			if type(value)~="string" then return nil,"Supply the base name for TransfiguredGem" end
			local found=false;for _,name in ipairs(values) do if value==name then found=true end end;return (op=="!" or op=="!=") and not found or op~="!" and op~="!=" and found
		end
		if type(value)~="boolean" or (values[1]~="True" and values[1]~="False") then return nil,"Invalid boolean "..c.keyword end
		return compare(value,values[1]=="True",op)
	else
		local negative=op=="!" or op=="!=";local entries=type(value)=="table" and value or {value}
		local count=0;local minimum=(c.keyword=="HasExplicitMod" or c.keyword=="HasEnchantment") and not (c.quoted and c.quoted[1]) and tonumber(values[1]) or nil;local start=minimum and 2 or 1
		for _,entry in ipairs(entries) do for i=start,#values do
			local found=op=="==" and tostring(entry)==values[i] or op~="==" and tostring(entry):lower():find(values[i]:lower(),1,true)~=nil
			if found then count=count+1;break end
		end end
		if partialExplicit then
			if minimum then
				local first=compare(count,minimum,op);local atThreshold=compare(math.max(count,minimum),minimum,op);local above=compare(math.max(count,minimum)+1,minimum,op)
				if first~=nil and first==atThreshold and first==above then return first end
			elseif count>0 then return not negative end
			return nil,"Copied modifier names may be incomplete"
		end
		if minimum then return compare(count,minimum,op) end
		return negative and count==0 or not negative and count>0
	end
end
function M.invalidResult(diagnostic)
	local reason=diagnostic.line and ("Filter line "..diagnostic.line..": "..diagnostic.error) or diagnostic.error
	return {status="invalid",action="Unknown",line=diagnostic.line,styles={},matches={},reasons={reason}}
end
function M.simulate(parsed,item)
	local result={action="Show",status="matched",styles={},matches={},reasons={}}
	for _,d in ipairs(parsed.diagnostics) do if d.error then return M.invalidResult(d) end end
	for _,d in ipairs(parsed.diagnostics) do if d.unverifiedContinue then
		return {status="unknown",action="Unknown",line=d.line,styles={},matches={},reasons={"Filter line "..d.line..": Continue arguments need in-game verification; the filter may not load as expected."}}
	end end
	local importIndex=1
	local function unresolvedImport()
		local entry=parsed.imports[importIndex]
		result.status="unknown";result.action="Unknown";result.line=entry.line
		result.reasons={"Included file '"..entry.file.."' is unresolved and could change this result. Attach it for an exact preview."}
		return result
	end
	for _,rule in ipairs(parsed.rules) do
		if parsed.imports[importIndex] and parsed.imports[importIndex].line<rule.line then return unresolvedImport() end
		local matched,unknown,missing=true,{},{}
		for _,condition in ipairs(rule.conditions) do local pass,why=M.condition(condition,item);if pass==false then matched=false;break elseif pass==nil then unknown[#unknown+1]=why;if why=="Missing "..condition.keyword then missing[#missing+1]=condition.keyword end end end
		if matched then
			if #unknown>0 then result.status="unknown";result.action="Unknown";result.reasons=unknown;result.missingProperties=missing;result.line=rule.line;return result end
			result.action=rule.action;result.line=rule.line;result.ruleTitle=rule.title;result.matches[#result.matches+1]=rule.line
			-- Both numbered alert commands address the alert sound. A later
			-- matching block replaces its earlier numbered alert, including None.
			if rule.styles.PlayAlertSound or rule.styles.PlayAlertSoundPositional then
				result.styles.PlayAlertSound=nil;result.styles.PlayAlertSoundPositional=nil
			end
			-- These pairs each control one independent drop-sound flag.
			-- Keep both commands when they occur in one block: their order is
			-- not represented in styles, so the preview must not guess.
			for _,pair in ipairs(dropSoundPairs) do
				if rule.styles[pair[1]] or rule.styles[pair[2]] then
					result.styles[pair[1]]=nil;result.styles[pair[2]]=nil
				end
			end
			for key,value in pairs(rule.styles) do result.styles[key]=value end
			if not rule.continue then
				if #parsed.imports>0 then result.reasons[#result.reasons+1]="Later included files are unresolved; this preview assumes they are valid and available when required." end
				return result
			end
		end
	end
	if parsed.imports[importIndex] then return unresolvedImport() end
	return result
end
return M
