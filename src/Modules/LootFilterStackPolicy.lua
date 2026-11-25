local M = {}
local scopes = {all=true,campaign=true,maps=true,earlyMaps=true,endgame=true}
local fields = {BaseType=true,Class=true,StackSize=true,AreaLevel=true,StackMaximum=true,ItemLevel=true}

local function whole(value, upper)
	return type(value)=="number" and value>=1 and value<=upper and value==math.floor(value)
end

function M.normalize(rows, stackClass)
	assert(rows==nil or type(rows)=="table" and #rows<=250,"Use up to 250 recorded stacks")
	if not rows or not next(rows) then return nil end
	local checked, count = {}, 0
	for key, row in pairs(rows) do
		assert(whole(key,#rows) and type(row)=="table","Expected a list of recorded stacks")
		assert(type(row.BaseType)=="string" and #row.BaseType<=200 and row.BaseType:match("%S")
			and not row.BaseType:find('[%c%^"\\]') and stackClass(row.Class),
			"Choose an exact stackable item and class")
		assert(whole(row.StackSize,10000) and whole(row.AreaLevel,100)
			and (row.StackMaximum==nil or whole(row.StackMaximum,1000000000))
			and (row.ItemLevel==nil or whole(row.ItemLevel,100)), "Use valid whole stack sizes and levels")
		local copy = {}
		for field, value in pairs(row) do
			assert(fields[field],"Unsupported stack observation field")
			copy[field] = value
		end
		checked[key] = copy
		count=count+1
	end
	assert(count==#rows,"Recorded stacks must be a complete list")
	return checked
end

local function key(class, name, scope)
	return class.."\0"..name.."\0"..scope
end

function M.index(rows)
	local groups = {}
	local function add(row, scope)
		local id = key(row.Class,row.BaseType,scope)
		local group = groups[id]
		if not group then
			group = {sizes={},item=row.BaseType,class=row.Class,scope=scope}
			groups[id] = group
		end
		group.sizes[#group.sizes+1] = row.StackSize
		if row.StackMaximum then
			if group.inventoryMaximum==nil then group.inventoryMaximum=row.StackMaximum
			elseif group.inventoryMaximum~=row.StackMaximum then group.inventoryMaximum=false end
		end
	end
	for _, row in ipairs(rows or {}) do
		add(row,"all")
		if row.AreaLevel<68 then
			add(row,"campaign")
		else
			add(row,"maps")
			add(row,row.AreaLevel<78 and "earlyMaps" or "endgame")
		end
	end
	for _, group in pairs(groups) do
		table.sort(group.sizes)
		group.count = #group.sizes
		group.median = group.sizes[math.ceil(group.count/2)]
		group.largest = group.sizes[group.count]
		group.sizes = nil
	end
	return groups
end

function M.firstVisible(group)
	if not group then return end
	if group.count>=5 then return group.median end
	if group.inventoryMaximum and group.largest<=group.inventoryMaximum then return group.inventoryMaximum end
end

function M.forRule(groups, classes, name, scope)
	if not scopes[scope] then return end
	local representative
	for _, class in ipairs(classes) do
		local group = groups[key(class,name,scope)]
		if group and (not representative or (M.firstVisible(group) or math.huge)<(M.firstVisible(representative) or math.huge)) then
			representative = group
		end
	end
	return representative
end

function M.lines(stats)
	local lines = {string.format("%d recorded drops | median %d | largest %d",stats.count,stats.median,stats.largest)}
	if stats.inventoryMaximum then
		lines[#lines+1] = string.format("Inventory stack maximum from clipboard: %d",stats.inventoryMaximum)
	elseif stats.inventoryMaximum==false then
		lines[#lines+1] = "Recorded inventory stack limits disagree."
	end
	local firstVisible = M.firstVisible(stats)
	if firstVisible then
		lines[#lines+1] = string.format("A new hide cutoff must stay below %d.",firstVisible)
	else
		lines[#lines+1] = "Record five drops in this area group for a median-based limit."
	end
	return lines
end

return M
