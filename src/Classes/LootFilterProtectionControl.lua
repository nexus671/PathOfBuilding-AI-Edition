local ui = require("Modules.PlanningUI")
local library = require("Modules.LootFilterLibrary")
local protected = require("Modules.LootFilterProtectedDrops")
local M = {}
local levels = {
	{key="AreaLevel",label="Area level",min=1,max=100},
	{key="ItemLevel",label="Item level",min=1,max=100},
	{key="LinkedSockets",label="Links",min=0,max=6},
	{key="UnidentifiedItemTier",label="Unidentified tier",min=0,max=5},
}
local flags = {"Identified","Corrupted","FracturedItem","Fated"}
local flagLabels = {"Identified","Corrupted","Fractured","Fated"}

local function edit(width, item, save)
	local c = {}
	local source = item or {}
	local column = math.floor((width-56)/4)
	local function field(key,label,x,y,w,limit)
		ui.label(c,key.."Label",x,y,label,13)
		c[key]=new("EditControl"):EditControl(ui.anchor,{x,y+19,w,26},"",nil,nil,limit)
	end
	field("BaseType","Exact base type",16,16,width-32,200)
	field("Class","Item class (blank infers class)",16,70,width-190,100)
	ui.label(c,"rarityLabel",width-158,70,"Rarity",13)
	c.Rarity=new("DropDownControl"):DropDownControl(ui.anchor,{width-158,89,142,26},{"Normal","Magic","Rare","Unique"})
	for index, level in ipairs(levels) do
		field(level.key,level.label,16+(index-1)*(column+8),123,column,3)
	end
	for index, key in ipairs(flags) do
		local x=16+(index-1)*(column+8)
		ui.label(c,key.."Label",x,178,flagLabels[index],13)
		c[key]=new("DropDownControl"):DropDownControl(ui.anchor,{x,197,column,26},{"Unknown","Yes","No"})
	end
	ui.label(c,"actionLabel",16,235,"Expected result",13)
	c.ExpectedAction=new("DropDownControl"):DropDownControl(ui.anchor,{16,254,130,26},{"Show","Hide"})
	field("ExpectedMarker","Expected icon (optional, e.g. 0 Red Star)",158,235,width-174,40)
	local function fill(value)
		for _, key in ipairs({"BaseType","Class","ExpectedMarker"}) do c[key]:SetText(value[key] or "") end
		for _, level in ipairs(levels) do
			local n=value[level.key]
			c[level.key]:SetText(n and tostring(n) or "")
		end
		for _, key in ipairs(flags) do
			c[key]:SetSel(value[key]==true and 2 or value[key]==false and 3 or 1)
		end
		c.Rarity:SelByValue(value.Rarity or "Normal")
		c.ExpectedAction:SelByValue(value.ExpectedAction or "Show")
	end
	fill(source)
	local function draft()
		local base = c.BaseType.buf:match("^%s*(.-)%s*$")
		local rarity = c.Rarity:GetSelValue()
		local enteredClass = c.Class.buf:match("^%s*(.-)%s*$")
		local itemClass = enteredClass~="" and enteredClass or library.baseClass(base)
		local sameClass = itemClass==source.Class or source.Class==nil and enteredClass==""
		local value = base==source.BaseType and sameClass and rarity==source.Rarity and copyTable(source) or {}
		value.BaseType,value.Rarity,value.Class = base,rarity,itemClass
		for _, level in ipairs(levels) do
			local raw = c[level.key].buf:match("^%s*(.-)%s*$")
			local number = tonumber(raw)
			assert(raw=="" or number and number==math.floor(number) and number>=level.min and number<=level.max,
				string.format("%s must be a whole number from %d to %d.",level.label,level.min,level.max))
			value[level.key] = number
		end
		for _, key in ipairs(flags) do
			local selected = c[key].selIndex
			if selected==1 then value[key]=nil else value[key]=selected==2 end
		end
		value.ExpectedAction = c.ExpectedAction.selIndex==2 and "Hide" or nil
		local marker = c.ExpectedMarker.buf:match("^%s*(.-)%s*$")
		value.ExpectedMarker = marker~="" and marker or nil
		local baseInfo = library.baseProperties(base,rarity)
		for _, key in ipairs({"Width","Height","DropLevel"}) do
			if value[key]==nil then value[key]=baseInfo[key] end
		end
		return protected.validateSamples({value})[1]
	end
	ui.label(c,"guidance",16,292,"Leave unknown properties blank. Preview checks whether the rule can match this sample.",13)
	c.paste=new("ButtonControl"):ButtonControl(ui.anchor,{16,323,130,28},"Paste item",function()
		local ok, result=pcall(function() return require("Modules.LootFilterClipboard").parse(Paste()) end)
		if not ok then main:OpenMessagePopup("Paste protected sample",ui.errorText(result));return end
		result.ExpectedAction=c.ExpectedAction:GetSelValue()
		result.ExpectedMarker=c.ExpectedMarker.buf
		source=result
		fill(result)
	end)
	c.apply=new("ButtonControl"):ButtonControl(ui.anchor,{154,323,130,28},"Keep sample",function()
		local ok,result=pcall(draft)
		if not ok then main:OpenMessagePopup("Protected sample",ui.errorText(result));return end
		main:ClosePopup()
		save(result)
	end)
	c.close=new("ButtonControl"):ButtonControl(ui.anchor,{width-136,323,120,28},"Cancel",function() main:ClosePopup() end)
	ui.style(c,{apply=true})
	main:OpenPopup(width,369,"Protected sample",c,nil,"BaseType","close")
end

function M.Open(samples, save)
	local list = samples or {}
	local entries={{id="add",label="Add a protected sample",details={
		"Enter an example drop or paste copied item text.",
		"Review the revised filter before saving this profile.",
	}}}
	for index, item in ipairs(list) do
		local action = item.ExpectedAction or "Show"
		entries[#entries+1] = {id=tostring(index),index=index,label=item.BaseType,category=action,
			details={item.Rarity,item.Class or "Class is unspecified",item.ExpectedMarker and "Expected icon: "..item.ExpectedMarker or nil}}
	end
	local function update(next)
		save(#next>0 and next or nil)
		M.Open(next,save)
	end
	require("Classes.PlanningBrowserControl").Open("Protected samples",entries,{
		action="Edit sample",closeOnChoose=false,
		canChoose=function(entry) return entry.index~=nil or #list<500 end,
		choose=function(entry)
			local index=entry.index or (#list+1)
			edit(math.min(580,main.screenW-40),list[index],function(item)
				local next=copyTable(list)
				next[index]=item
				main:ClosePopup()
				update(next)
			end)
		end,
		secondary={label="Remove sample",canRun=function(entry) return entry.index~=nil end,run=function(entry)
			local next=copyTable(list)
			table.remove(next,entry.index)
			main:ClosePopup()
			update(next)
		end},
	})
end

return M
