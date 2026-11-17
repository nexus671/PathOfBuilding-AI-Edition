-- A graphical rule workbench. Raw filter text is confined to import/export.
local ui=require("Modules.PlanningUI")
local filters=require("Modules.LootFilters")
local parser=require("Modules.LootFilterParser")
local M={}
local sampleFields={"BaseType","Class","Rarity","ItemLevel","AreaLevel","DropLevel","Width","Height","UnidentifiedItemTier","SocketGroup","Sockets","SocketColours","LinkedSockets","StackSize","GemLevel","MapTier","Quality","BaseDefencePercentile","MemoryStrands","Fated","Identified","Corrupted","TwiceCorrupted","FracturedItem","HasInfluence","HasExplicitMod"}
local function additionalSampleFields()
	local seen=copyTable(parser.poe2Only);for _,key in ipairs(sampleFields) do seen[key]=true end
	local fields={};for _,group in ipairs({parser.numeric,parser.booleans,parser.strings}) do for key in pairs(group) do if not seen[key] then fields[#fields+1]=key;seen[key]=true end end end
	table.sort(fields);return fields
end
local function button(c,key,x,y,w,label,run) c[key]=new("ButtonControl"):ButtonControl(ui.anchor,{x,y,w,28},label,run);return c[key] end
local function notify(title,message)
	local c={};local w,h=math.min(760,main.screenW-40),math.min(360,main.screenH-60)
	ui.description(c,"message",16,28,w-32,h-100,{tostring(message)},16)
	button(c,"close",w-156,h-48,140,"Close",function() main:ClosePopup() end);ui.style(c);main:OpenPopup(w,h,title,c,"close",nil,"close")
end
local function attempt(callback) local ok,why=pcall(callback);if not ok then notify("Loot filter",ui.errorText(why)) end end
local function modal(title,raw,save,existing)
	local c={};local pending,pendingText,pendingPath;local w,h=math.min(860,main.screenW-40),math.min(570,main.screenH-60)
	local attached={};for _,file in ipairs(existing or {}) do attached[file.name]=true end
	ui.description(c,"help",16,28,w-32,44,{save and "Paste a filter or load a local filter file. Original text is preserved; personal rules stay separate." or "Copy the filter text, or export a file for your game mode. Copy does not change any game files."},14)
	c.text=new("EditControl"):EditControl(ui.anchor,{16,84,w-32,h-(save and 205 or 150)},raw,nil,"^%C\t\n",filters.limit,nil,14,true)
	if save then
		ui.label(c,"pathLabel",16,h-114,"Local file path",14)
		c.path=new("EditControl"):EditControl(ui.anchor,{16,h-96,w-284,26},"",nil,nil,1024)
		local function loadFile() attempt(function() local text=require("Modules.LootFilterImports").readFile(c.path.buf,filters.limit);c.text:SetText(text);pending=nil end) end
		button(c,"browseFile",w-256,h-96,100,"Browse",function() require("Classes.LootFilterFileBrowser").Open(c.path.buf,function(path) c.path:SetText(path);loadFile() end) end)
		button(c,"loadFile",w-148,h-96,132,"Load file",loadFile)
		button(c,"loadLinked",304,h-48,180,"Load linked files",function() attempt(function()
			local imports=require("Modules.LootFilterImports");pending=imports.collectLocal(c.text.buf,c.path.buf,filters.limit);pendingText=c.text.buf;pendingPath=c.path.buf
			local entries={};for _,file in ipairs(pending.files) do entries[#entries+1]={id=file.name,label=file.name,category="Loaded",details={"Loaded from the selected filter's folder.",attached[file.name] and "Using this import replaces the existing attached copy with this name." or "This copy will be kept with the imported filter."}} end
			for _,issue in ipairs(pending.issues) do local status=issue.optional and "Optional file not loaded" or "File not loaded";entries[#entries+1]={id=issue.name,label=issue.name,category=status,details={status,issue.reason}} end
			local ok,unresolved=pcall(imports.unresolved,c.text.buf,pending.files,filters.limit)
			if ok then for _,row in ipairs(unresolved) do if row.cycle then entries[#entries+1]={id=row.name,label=row.name,category="Circular reference",details={"A circular reference remains unresolved. Edit the included files to break the cycle."}} end end
			else entries[#entries+1]={id="preview",label="Expanded filter could not be checked",category="Review",details={tostring(unresolved)}} end
			if #entries==0 then notify("Linked filter files","No linked filter files were found.") else require("Classes.PlanningBrowserControl").Open("Linked filter files",entries) end
		end) end)
		c.loadLinked.label=function() return pending and ("Linked: "..#pending.files.." loaded") or "Load linked files" end
		c.loadLinked.tooltipText="Load referenced sibling filter files, including nested references. Other paths remain unresolved."
	end
	button(c,"copy",16,h-48,124,"Copy filter",function() Copy(c.text.buf) end)
	if save then button(c,"import",152,h-48,140,"Use import",function() attempt(function() assert(not pending or c.text.buf==pendingText and c.path.buf==pendingPath,"The filter text or path changed; load linked files again.");save(c.text.buf,pending and pending.files);main:ClosePopup() end) end) end
	button(c,"close",w-140,h-48,124,"Close",function() main:ClosePopup() end)
	ui.style(c);main:OpenPopup(w,h,title,c,nil,"text","close")
end
function M.Conditions(rule,save)
	local c={};local w,h=math.min(880,main.screenW-40),math.min(600,main.screenH-60);local parsed=parser.parse(rule.text);local block=parsed.rules[1]
	local conditions=copyTable(block.conditions);local keywords={"BaseType","Class","Rarity","ItemLevel","AreaLevel","Quality","BaseDefencePercentile","MemoryStrands","LinkedSockets","Sockets","SocketGroup","GemLevel","MapTier","StackSize","UnidentifiedItemTier","Fated","Identified","Corrupted","TwiceCorrupted","FracturedItem","HasInfluence"}
	local known=copyTable(parser.poe2Only);for _,key in ipairs(keywords) do known[key]=true end
	local additional={};for _,group in ipairs({parser.numeric,parser.booleans,parser.strings}) do for key in pairs(group) do if not known[key] then additional[#additional+1]=key;known[key]=true end end end
	table.sort(additional);for _,key in ipairs(additional) do keywords[#keywords+1]=key end
	for _,condition in ipairs(conditions) do local known=false;for _,k in ipairs(keywords) do if k==condition.keyword then known=true end end;if not known then keywords[#keywords+1]=condition.keyword end end
	ui.label(c,"nameLabel",16,28,"Rule name",14);c.title=new("EditControl"):EditControl(ui.anchor,{16,50,w-200,26},rule.title,nil,nil,160)
	c.action=new("DropDownControl"):DropDownControl(ui.anchor,{w-168,50,152,26},{"Show","Hide","Minimal"});c.action:SelByValue(block.action)
	ui.description(c,"hint",16,88,w-32,42,{"All conditions must match. Add values in quotes for names with spaces. A filter cannot inspect unidentified explicit modifiers."},14)
	local rows=math.max(1,math.floor((h-280)/40));local offset=1;local dialog
	local function drawConditions()
		for i=1,rows do
			local index=offset+i-1;local condition=conditions[index];local y=142+(i-1)*40
			for _,suffix in ipairs({"key","op","values","remove"}) do c["c"..i..suffix]=nil end
			if condition then
				c["c"..i.."key"]=new("DropDownControl"):DropDownControl(ui.anchor,{16,y,190,26},keywords,function(_,value) condition.keyword=value end);c["c"..i.."key"]:SelByValue(condition.keyword)
				c["c"..i.."op"]=new("DropDownControl"):DropDownControl(ui.anchor,{218,y,72,26},{"=","==",">=","<=",">","<","!="},function(_,value) condition.operator=value end);c["c"..i.."op"]:SelByValue(condition.operator)
				local values={};for j,v in ipairs(condition.values) do values[#values+1]=(condition.quoted and condition.quoted[j] or v:find(" ",1,true)) and filters.quote(v) or v end
				c["c"..i.."values"]=new("EditControl"):EditControl(ui.anchor,{302,y,w-366,26},table.concat(values," "),nil,nil,2000,function(value) local ok,result,quoted=pcall(parser.tokens,value);condition.invalid=not ok;if ok then condition.values=result;condition.quoted=quoted end end)
				button(c,"c"..i.."remove",w-52,y,36,"X",function() table.remove(conditions,index);drawConditions() end)
			end
		end
		if dialog then for _,control in pairs(c) do if not control.anchor.other then control.anchor.other=dialog end end;ui.style(c,{keepRule=true}) end
	end
	local styleY=h-124
	ui.label(c,"themeLabel",16,styleY-24,"Label style",14)
	c.theme=new("DropDownControl"):DropDownControl(ui.anchor,{16,styleY,160,26},{"Keep original","Gold / cyan","High contrast"})
	c.sound=new("DropDownControl"):DropDownControl(ui.anchor,{188,styleY,164,26},{"Keep sound","Silent","Alert 2","Alert 6"})
	button(c,"addCondition",364,styleY,140,"Add condition",function() conditions[#conditions+1]={keyword="BaseType",operator="==",values={"Iron Hat"}};offset=math.max(1,#conditions-rows+1);drawConditions() end)
	button(c,"previous",516,styleY,60,"<",function() offset=math.max(1,offset-rows);drawConditions() end)
	button(c,"next",588,styleY,60,">",function() offset=math.min(math.max(1,#conditions-rows+1),offset+rows);drawConditions() end)
	button(c,"keepRule",16,h-48,140,"Keep rule",function() attempt(function()
		local lines={c.action:GetSelValue()};for _,condition in ipairs(conditions) do
			assert(not condition.invalid,"Close every quoted condition value")
			local controlValues={};for i,value in ipairs(condition.values) do controlValues[#controlValues+1]=not parser.countExactMarker(condition,i) and ((condition.quoted and condition.quoted[i]) or (parser.strings[condition.keyword] and not tonumber(value)) or value:find("%s")) and filters.quote(value) or value end
			assert(#controlValues>0,"Every condition needs a value")
			local count=(condition.keyword=="HasExplicitMod" or condition.keyword=="HasEnchantment") and not (condition.quoted and condition.quoted[1]) and tonumber(condition.values[1])
			if count then lines[#lines+1]="    "..condition.keyword.." "..condition.operator..table.concat(controlValues," ")
			else lines[#lines+1]="    "..condition.keyword.." "..condition.operator.." "..table.concat(controlValues," ") end
		end
		local styles=copyTable(block.styles)
		if c.theme.selIndex>1 then local generated=filters.rule("style","Style",{},nil,c.theme.selIndex==3 and "contrast" or "default");local style=parser.parse(generated.text).rules[1].styles;for key,value in pairs(style) do styles[key]=value end end
		if c.sound.selIndex>1 then if c.sound.selIndex==2 then styles.PlayAlertSound={"None"};styles.CustomAlertSound={"None"} else styles.PlayAlertSound={c.sound.selIndex==3 and "2" or "6","200"};styles.CustomAlertSound=nil end;styles.CustomAlertSoundOptional=nil;styles.PlayAlertSoundPositional=nil end
		local keys={};for key in pairs(styles) do keys[#keys+1]=key end;table.sort(keys)
		for _,key in ipairs(keys) do local values=styles[key];local quoted=key:match("^CustomAlertSound") and (filters.quote(values[1])..(#values>1 and " "..table.concat(values," ",2) or "")) or table.concat(values," ");lines[#lines+1]="    "..key.." "..quoted end
		if block.continue then lines[#lines+1]="    Continue" end
		local nextRule=copyTable(rule);nextRule.title=c.title.buf;nextRule.text=table.concat(lines,"\n");nextRule.origin=nil
		local p=filters.profile("validate","Validate");p.rules={nextRule};filters.validate({schemaVersion=1,activeId=p.id,profiles={p}})
		save(nextRule);main:ClosePopup()
	end) end)
	button(c,"cancel",w-156,h-48,140,"Cancel",function() main:ClosePopup() end)
	drawConditions();ui.style(c,{keepRule=true});main:OpenPopup(w,h,"Loot filter rule",c,nil,"title","cancel");dialog=main.popups[1]
end
function M.EditRule(rule,save,mode)
 require("Classes.LootFilterAppearance").Open(rule,function(nextRule)
  local profile=filters.profile("validate","Validate");profile.rules={nextRule};filters.validate({schemaVersion=1,activeId=profile.id,profiles={profile}})
  save(nextRule)
 end,M.Conditions,{mode=mode})
end
function M.Import(save,existing)
 modal("Import loot filter","",function(raw,linked)
  local parsed=parser.parse(raw);assert(#parsed.rules>0 or #parsed.imports>0,"No filter rules or imports found")
  for _,d in ipairs(parsed.diagnostics) do assert(not d.error,d.error) end
  save(raw,linked)
 end,existing)
end
function M.Open(build,source,layout)
 return require("Classes.LootFilterWorkspace").Open(build,source,layout,M)
end
function M.Account(profile,import)
	local account=require("Modules.LootFilterAccount");local c={};local w,h=math.min(900,main.screenW-40),math.min(560,main.screenH-60);local entries={};local selected;local status="No account request made."
	ui.description(c,"help",16,28,w-32,70,{"Optional account sync needs account:item_filter permission from GGG. Log in requests that additional scope; it may require OAuth client approval. Local export works independently. Publishing is explicit and sends this profile's compiled filter."},14)
	c.realm=new("DropDownControl"):DropDownControl(ui.anchor,{16,112,160,26},{"pc","xbox","sony"})
	c.entries=new("TextListControl"):TextListControl(ui.anchor,{16,154,w-32,h-298},nil,{})
	ui.selectable(c.entries,function(row) return row.entry and row.entry.id end,function(row) selected=row.entry end)
	c.status=new("TextListControl"):TextListControl(ui.anchor,{16,h-132,w-32,60},nil,ui.rows({status},w-64,14))
	local function show(message) status=message;c.status.list=ui.rows({status},w-64,14) end
	local function request(method,target,payload,done)
		attempt(function() show("Request in progress...");account.request(main.api,method,target,payload,function(value,err)
			if err then show(err) else local ok=pcall(done,value);if not ok then show("The account response was incomplete. Check your account before retrying a write.") end end
		end) end)
	end
	local bw=math.floor((w-72)/6)
	local function action(key,i,label,run) button(c,key,16+i*(bw+8),h-48,bw,label,run);c[key].enabled=function() return not account.busy end end
	action("login",0,"Log in",function() show("Complete login in your browser. If item-filter scope is unavailable, use local export.");main.api:FetchAuthToken(function(err) show(err and "Login failed; item-filter permission may need approval. Use local export." or "Logged in. List filters to check access.") end,true) end)
	action("fetch",1,"List filters",function() request("GET",nil,nil,function(value)
		entries=value.filters or {};local rows={};selected=nil;for _,entry in ipairs(entries) do rows[#rows+1]={height=30,textSize=15,"^7"..ui.fit((entry.filter_name or entry.id).." ["..(entry.realm or "?").."]",w-64,15),entry=entry} end;c.entries.list=rows
	end) end)
	action("importAccount",2,"Import selected",function() if selected then request("GET",selected.id,nil,function(value) assert(value.filter and value.filter.filter,"No filter text returned");import(value.filter.filter);show("Imported as a working draft. Keep in build and Save to persist.") end) else show("Select a listed filter first.") end end)
	local function publish(target)
		local raw,report=filters.compile(profile);for _,d in ipairs(report.diagnostics) do assert(not d.error,d.error) end
		local payload={filter_name=profile.title,realm=c.realm:GetSelValue(),description="Created with Path of Building AI Edition",version="3.30",type=profile.mode or "Normal",filter=raw}
		if not target then payload.public=false end
		if target then assert(selected.realm==payload.realm,"Choose the selected filter's realm before updating") end
		local confirmation={};local cw,ch=math.min(760,main.screenW-40),320
		local lines={target and "Replace account filter: "..(selected.filter_name or target).." ["..target.."]" or "Create a new private account filter: "..profile.title,"Realm: "..payload.realm.." | "..report.rules.." rules | "..#raw.." bytes"}
		if #report.unresolvedImports>0 then lines[#lines+1]=#report.unresolvedImports.." linked filter names are unresolved. Review included files before publishing." end
		lines[#lines+1]="This publishes the current working profile, including personal rules and 3.30 migrations. Existing subscriptions are not changed. The server will validate against its current game version."
		ui.description(confirmation,"summary",16,28,cw-32,200,lines,16)
		button(confirmation,"publish",16,ch-48,160,target and "Replace filter" or "Create filter",function() main:ClosePopup();request("POST",target,payload,function(value) show("Server confirmed valid filter "..value.filter.id..". Select it in game.") end) end)
		button(confirmation,"cancel",cw-176,ch-48,160,"Cancel",function() main:ClosePopup() end);ui.style(confirmation,{publish=true});main:OpenPopup(cw,ch,"Review account publication",confirmation,nil,nil,"cancel")
	end
	action("createAccount",3,"Publish new",function() attempt(function() publish() end) end)
	action("updateAccount",4,"Update selected",function() if selected then attempt(function() publish(selected.id) end) else show("Select a listed filter first.") end end)
	action("close",5,"Close",function() main:ClosePopup() end)
	ui.style(c);main:OpenPopup(w,h,"Account loot filters",c,nil,nil,"close")
end
function M.EditAdditionalSample(item,save)
	local c={};local w,h=math.min(820,main.screenW-40),math.min(560,main.screenH-60)
	local draft=copyTable(item);local fields=additionalSampleFields();local columns=4;local rowHeight=46
	local rows=math.max(1,math.floor((h-120)/rowHeight));local perPage=columns*rows;local page=1;local pages=math.max(1,math.ceil(#fields/perPage));local visible={};local dialog
	ui.description(c,"hint",16,26,w-32,36,{"Optional filter properties. Leave fields blank or choose Unknown when the value is unavailable."},14)
	local function collect()
		for _,key in ipairs(visible) do
			local control=c["extra_"..key];local value=parser.booleans[key] and key~="TransfiguredGem" and control:GetSelValue() or control.buf
			if parser.numeric[key] then local n=value~="" and tonumber(value);assert(value=="" or n and n==n and math.abs(n)<1e9,"Enter a finite number for "..key);draft[key]=n or nil
			elseif key=="TransfiguredGem" then if value=="" then draft[key]=nil elseif value=="True" then draft[key]=true elseif value=="False" then draft[key]=false else draft[key]=value end
			elseif parser.booleans[key] then if value=="Unknown" then draft[key]=nil else draft[key]=value=="Yes" end
			elseif key=="HasEnchantment" or key=="ArchnemesisMod" or type(draft[key])=="table" then
				if value=="" then draft[key]=nil elseif value=="[]" then draft[key]={} else draft[key]=parser.tokens(value) end
			else draft[key]=value~="" and value or nil end
		end
	end
	local function draw()
		for _,key in ipairs(visible) do c["extra_"..key]=nil;c["extraLabel_"..key]=nil end;visible={}
		local width=w/columns
		for index=(page-1)*perPage+1,math.min(page*perPage,#fields) do
			local key=fields[index];local slot=index-(page-1)*perPage-1;local x=16+(slot%columns)*width;local y=70+math.floor(slot/columns)*rowHeight
			visible[#visible+1]=key;ui.label(c,"extraLabel_"..key,x,y,ui.fit(key:gsub("(%l)(%u)","%1 %2"),width-32,14),14)
			local value=draft[key]
			if parser.booleans[key] and key~="TransfiguredGem" then
				c["extra_"..key]=new("DropDownControl"):DropDownControl(ui.anchor,{x,y+18,width-32,24},{"Unknown","Yes","No"})
				c["extra_"..key]:SelByValue(value==nil and "Unknown" or value and "Yes" or "No")
			else
				if type(value)=="table" then local names={};for _,name in ipairs(value) do names[#names+1]=filters.quote(name) end;value=#names>0 and table.concat(names," ") or "[]"
				elseif type(value)=="boolean" then value=value and "True" or "False" end
				c["extra_"..key]=new("EditControl"):EditControl(ui.anchor,{x,y+18,width-32,24},tostring(value==nil and "" or value),nil,nil,1000)
			end
			c["extra_"..key].tooltipText=key=="TransfiguredGem" and "Enter True, False or the base gem name; leave blank if unknown." or (key=="HasEnchantment" or key=="ArchnemesisMod") and "Enter quoted names, [] for a known empty list, or leave blank if unknown." or key
		end
		if dialog then for _,control in pairs(c) do if not control.anchor.other then control.anchor.other=dialog end end;ui.style(c,{keepExtra=true}) end
	end
	button(c,"extraPrevious",16,h-48,76,"<",function() attempt(function() collect();page=math.max(1,page-1);draw() end) end)
	button(c,"extraNext",104,h-48,76,">",function() attempt(function() collect();page=math.min(pages,page+1);draw() end) end)
	c.extraPrevious.enabled=function() return page>1 end;c.extraNext.enabled=function() return page<pages end
	c.extraPage=ui.label(c,"extraPage",194,h-42,"",14);c.extraPage.label=function() return "^7Page "..page.." / "..pages end
	button(c,"keepExtra",w-318,h-48,150,"Use properties",function() attempt(function() collect();save(draft);main:ClosePopup() end) end)
	button(c,"cancelExtra",w-156,h-48,140,"Cancel",function() main:ClosePopup() end)
	draw();ui.style(c,{keepExtra=true});main:OpenPopup(w,h,"More sample properties",c,nil,nil,"cancelExtra");dialog=main.popups[1]
end
function M.EditSample(item,save)
	local c={};local w,h=math.min(820,main.screenW-40),math.min(560,main.screenH-60)
	local fields=sampleFields;local extra=copyTable(item)
	local columns=4;local fieldWidth=w/columns;local rowHeight=h<520 and 48 or 56
	for i,key in ipairs(fields) do local x=16+((i-1)%columns)*fieldWidth;local y=28+math.floor((i-1)/columns)*rowHeight;ui.label(c,key.."Label",x,y,key:gsub("(%l)(%u)","%1 %2"),14)
		local value=item[key];if type(value)=="table" then
			if key=="HasExplicitMod" then local names={};for _,name in ipairs(value) do names[#names+1]=filters.quote(name) end;value=#names>0 and table.concat(names," ") or "[]"
			else value=table.concat(value," ") end
		end
		if parser.booleans[key] then
			c[key]=new("DropDownControl"):DropDownControl(ui.anchor,{x,y+18,fieldWidth-32,24},{"Unknown","Yes","No"})
			c[key]:SelByValue(value==nil and "Unknown" or value and "Yes" or "No")
		else c[key]=new("EditControl"):EditControl(ui.anchor,{x,y+18,fieldWidth-32,24},tostring(value==nil and "" or value),nil,nil,240) end
		if key=="HasExplicitMod" then c[key].tooltipText='Enter quoted modifier names, or [] for a known empty list. Editing this field clears names inferred from pasted text.' end
		if key=="SocketGroup" then c[key].tooltipText='Enter linked groups, 0 for no sockets, or leave blank if unknown.' end
		if key=="DropLevel" or key=="Width" or key=="Height" or key=="BaseDefencePercentile" or key=="MemoryStrands" or key=="UnidentifiedItemTier" then c[key].tooltipText="Leave blank if this property is unknown." end
	end
	c.HasExplicitMod.changeFunc=function() extra.KnownExplicitMods=nil end
	local previousBase=c.BaseType.buf
	c.BaseType.tooltipText="Changing the base clears its class, dimensions, drop level, defence percentile, item tier, memory strands, map tier and sockets. Enter values for the new item."
	c.BaseType.changeFunc=function(value)
		if value~=previousBase then
			for _,key in ipairs({"Class","DropLevel","Width","Height","BaseDefencePercentile","UnidentifiedItemTier","MemoryStrands","MapTier","SocketGroup","Sockets","SocketColours","LinkedSockets"}) do c[key]:SetText("") end
			extra.AlwaysShow=nil
			extra.KnownExplicitMods=nil
			for _,key in ipairs(additionalSampleFields()) do extra[key]=nil end
			previousBase=value
		end
	end
	local previousRarity=c.Rarity.buf
	c.Rarity.changeFunc=function(value)
		if value:lower()~=previousRarity:lower() then extra.KnownExplicitMods=nil end
		if value:lower()~=previousRarity:lower() then c.UnidentifiedItemTier:SetText("") end
		if value:lower()=="unique" and previousRarity:lower()~="unique" then c.DropLevel:SetText("");c.BaseDefencePercentile:SetText("") end
		previousRarity=value
	end
	button(c,"useSample",16,h-48,140,"Test drop",function() attempt(function()
		local nextItem=copyTable(extra);for _,key in ipairs(fields) do local v=parser.booleans[key] and c[key]:GetSelValue() or c[key].buf
			if parser.numeric[key] then local n=v~="" and tonumber(v);assert(v=="" or n and n==n and math.abs(n)<1e9,"Enter a finite number for "..key);if key=="BaseDefencePercentile" and n then assert(n>=0 and n<=100,"Defence percentile must be between 0 and 100") elseif key=="MemoryStrands" and n then assert(n>=0 and n<=100 and n==math.floor(n),"Memory strands must be a whole number between 0 and 100") end;nextItem[key]=n or nil
			elseif parser.booleans[key] then if v=="Unknown" then nextItem[key]=nil else nextItem[key]=v=="Yes" end
			elseif key=="HasInfluence" then nextItem[key]=parser.tokens(v)
			elseif key=="HasExplicitMod" then if v=="" then nextItem[key]=nil elseif v=="[]" then nextItem[key]={} else nextItem[key]=parser.tokens(v) end
			else nextItem[key]=v~="" and v or nil end
		end;save(nextItem);main:ClosePopup()
	end) end)
	button(c,"moreSample",168,h-48,160,"More properties",function() M.EditAdditionalSample(extra,function(value) extra=value end) end)
	button(c,"cancel",w-156,h-48,140,"Cancel",function() main:ClosePopup() end);ui.style(c,{useSample=true});main:OpenPopup(w,h,"Test a drop",c,nil,"BaseType","cancel")
end
function M.Export(profile,raw,report)
	local c={};local w,h=math.min(800,main.screenW-40),342
	local names=require("Modules.LootFilterFileNames");local extension=names.extension(profile)
	local imports=report and report.unresolvedImports or require("Modules.LootFilterImports").summarize(parser.parse(raw),profile.importFiles)
	ui.description(c,"help",16,28,w-32,62,{"Save a "..extension.." file, then select it in Path of Exile's item-filter settings. Exporting does not equip items or change the character."},16)
	ui.label(c,"directoryLabel",16,106,"Destination directory",14)
	c.directory=new("EditControl"):EditControl(ui.anchor,{16,128,w-32,26},main.userPath.."LootFilters",nil,nil,1000)
	c.filename=new("EditControl"):EditControl(ui.anchor,{16,170,w-32,26},profile.id..extension,nil,nil,120)
	ui.description(c,"importsStatus",16,200,w-32,30,{#imports>0 and (#imports.." linked filter names unresolved. Review them before saving.") or "All included filter files are resolved."},14)
	button(c,"copy",16,236,140,"Copy text",function() Copy(raw) end)
	button(c,"write",168,236,140,"Save file",function() attempt(function()
		names.stem(profile,c.filename.buf)
		local directory=c.directory.buf;assert(directory~="" and not directory:find("[%c]"),"Choose a directory")
		local target=directory.."/"..c.filename.buf;local existing=io.open(target,"rb")
		if existing then existing:close();notify("File exists","Choose another filename to preserve the existing filter.");return end
		MakeDir(directory);local file=assert(io.open(target,"wb"),"Could not create filter file");assert(file:write(raw));assert(file:close());notify("Filter exported",target)
	end) end)
	button(c,"raw",320,236,140,"Inspect text",function() modal("Compiled filter",raw) end)
	button(c,"reviewImports",472,236,160,"Review imports",function()
		local entries={};for _,entry in ipairs(imports) do
			local status=entry.cycle and "Circular reference" or entry.optional and "Optional file missing" or "Required file missing"
			entries[#entries+1]={id=entry.name,label=entry.name,details={status,entry.count.." reference(s) in the compiled filter.",entry.cycle and "Resolve the cycle in Included filter files." or entry.optional and "The game may skip this optional file if it is absent." or "Attach the file in Included filter files, or supply it alongside the exported filter."}}
		end
		require("Classes.PlanningBrowserControl").Open("Unresolved filter imports",entries)
	end)
	c.reviewImports.enabled=#imports>0
	c.reviewImports.tooltipText="Review missing and circular references retained in the exported text."
	button(c,"writeAll",16,282,280,"Save all seven strictnesses",function() attempt(function()
		names.stem(profile,c.filename.buf)
		local directory=c.directory.buf;assert(directory~="" and not directory:find("[%c]"),"Choose a directory")
		local variants=filters.variants(profile);local targets={}
		for i,variant in ipairs(variants) do
			local target=directory.."/"..names.variant(profile,c.filename.buf,variant.strictness);local existing=io.open(target,"rb")
			if existing then existing:close();error("Batch cancelled: file already exists: "..target) end;targets[i]=target
		end
		MakeDir(directory);local written=0
		for i,variant in ipairs(variants) do
			local file=io.open(targets[i],"wb");assert(file,"Could not create "..targets[i]..". Files already written: "..written)
			local ok=file:write(variant.text);local closed=file:close();assert(ok and closed,"Could not finish "..targets[i]..". Files already completed: "..written);written=written+1
		end
		notify("Filters exported","Saved seven strictnesses to "..directory)
	end) end)
	c.writeAll.enabled=not profile.template;c.writeAll.tooltipText="Keeps personal rules and global appearance in every variant. Imported filters have no preset variants."
	button(c,"writeZip",308,282,196,"Save strictness ZIP",function() attempt(function()
		local stem=names.stem(profile,c.filename.buf)
		local directory=c.directory.buf;assert(directory~="" and not directory:find("[%c]"),"Choose a directory")
		local target=directory.."/"..stem.."-strictnesses.zip"
		local existing=io.open(target,"rb");if existing then existing:close();notify("File exists","Choose another filename to preserve the existing archive.");return end
		local archive=require("Modules.LootFilterZip").variants(profile,c.filename.buf)
		MakeDir(directory);local file=assert(io.open(target,"wb"),"Could not create archive");local ok=file:write(archive);local closed=file:close();assert(ok and closed,"Could not finish "..target)
		notify("Filters exported",target)
	end) end)
	c.writeZip.enabled=not profile.template;c.writeZip.tooltipText=c.writeAll.tooltipText
	button(c,"close",w-156,236,140,"Close",function() main:ClosePopup() end);ui.style(c,{write=true});main:OpenPopup(w,h,"Export loot filter",c,nil,"filename","close")
end
function M.Audit(profile,report,save)
	local entries={{id="update",label="Update bundled NeverSink base",details={"Saved revision: "..profile.baseCommit,"Bundled revision: "..filters.source().commit,"Personal rules and original imported text are preserved. Templates refresh with fork releases; no live economy feed is implied.","Imported filters use safety rules for new 3.30 items; bundled presets use their own tiering."}}};for name,value in pairs(report and report.changes or {}) do entries[#entries+1]={id=name,label=name,details={value=="removed" and "Removed in 3.30. An empty BaseType list removes its entire rule." or "Renamed to "..value}} end
	if report and report.error then entries[#entries+1]={id="compile-error",label="Compilation error",details={ui.errorText(report.error)}} end
	for i,d in ipairs(report and report.diagnostics or {}) do entries[#entries+1]={id="diagnostic-"..i,label="Line "..d.line,details={d.error or d.warning}} end
	require("Classes.PlanningBrowserControl").Open("Filter audit",entries,{action="Use current base",enterChooses=false,closeOnChoose=false,choose=function() save(filters.update(profile));main:ClosePopup() end})
end
return M
