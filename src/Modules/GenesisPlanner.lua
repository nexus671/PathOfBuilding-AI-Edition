-- Genesis allocations are separate from character and Atlas passive points.
-- cspell:ignore jsontype
local json=require("dkjson")
local M={version="3.30.0d"}
local cache,pointReference
local roots={
	[42956]="Mysterious",[19625]="Currency",[22476]="Equipment",[47967]="Unique",
}
local wombs={[7411]=true,[41240]=true,[33919]=true,[28988]=true}
M.roots=roots
M.wombs=wombs
function M.pointReference()
	if not pointReference then
		local file=assert(io.open("Data/Genesis/point-reference.json","rb"));local raw=file:read("*a");file:close()
		pointReference=assert(json.decode(raw));assert(pointReference.version==M.version,"Unsupported Genesis point reference")
	end
	return copyTable(pointReference)
end
function M.tree()
	if not cache then
		local file=assert(io.open("Data/Genesis/3.30.0d.json","rb"));local raw=file:read("*a");file:close()
		local decoded,_,err=json.decode(raw);assert(decoded,err)
		assert(decoded.version==M.version,"Unsupported Genesis data")
		local nodes={};for key,node in pairs(decoded.nodes) do nodes[tonumber(key)]=node end
		decoded.nodes=nodes;cache=decoded
	end
	return cache
end
local function selectedSet(plan)
	local result={};for _,id in ipairs(plan.nodes) do result[id]=true end;return result
end
local function reachable(tree,set)
	local visited,queue={},{}
	for _,id in ipairs(tree.roots) do visited[id]=true;queue[#queue+1]=id end
	local cursor=1
	while cursor<=#queue do
		local id=queue[cursor];cursor=cursor+1
		for _,nextId in ipairs(tree.nodes[id].links) do if (set[nextId] or wombs[nextId]) and not visited[nextId] then visited[nextId]=true;queue[#queue+1]=nextId end end
	end
	return visited
end
function M.validate(plan)
	assert(type(plan)=="table" and plan.version==M.version,"Unsupported Genesis plan version")
	assert(type(plan.nodes)=="table" and plan.nodes~=json.null and #plan.nodes<=133,"Invalid Genesis allocations")
	local meta=getmetatable(plan.nodes);assert(not meta or meta.__jsontype~="object","Expected a Genesis allocation array")
	for key in pairs(plan.nodes) do assert(type(key)=="number" and key==math.floor(key) and key>=1 and key<=#plan.nodes,"Invalid Genesis allocations") end
	local tree=M.tree();local set={};local result={version=M.version,nodes={}}
	for _,id in ipairs(plan.nodes) do
		assert(type(id)=="number" and id==math.floor(id) and tree.nodes[id] and not roots[id] and not wombs[id] and not set[id],"Invalid or duplicate Genesis node")
		set[id]=true;result.nodes[#result.nodes+1]=id
	end
	local visited=reachable(tree,set);local choices={}
	for _,id in ipairs(result.nodes) do
		assert(visited[id],"Genesis allocations must connect to their tree's starting point")
		local node=tree.nodes[id]
		if node.choiceOption then
			local parent
			for _,neighbor in ipairs(node.links) do if tree.nodes[neighbor].choice then assert(not parent,"Ambiguous Genesis choice");parent=neighbor end end
			assert(parent and set[parent] and not choices[parent],"Select one option for each allocated choice node")
			choices[parent]=id
		end
	end
	table.sort(result.nodes);return result
end
function M.empty() return {version=M.version,nodes={}} end
function M.report(plan)
	plan=M.validate(plan);local tree=M.tree();local result={counts={},missingChoices={}}
	local set=selectedSet(plan)
	for _,root in ipairs(tree.roots) do result.counts[root]={allocated=0,options=0} end
	for _,entry in pairs(M.pointReference().branches) do
		local count=assert(result.counts[entry.root],"Unknown Genesis point-reference branch")
		count.publishedMaximum=entry.publishedMaximum;count.maximumSource=entry.source;count.maximumSourcePatch=entry.sourcePatch
	end
	for _,id in ipairs(plan.nodes) do
		local node=tree.nodes[id];local count=result.counts[node.root]
		if node.choiceOption then count.options=count.options+1 else count.allocated=count.allocated+1 end
		if node.choice then
			local chosen=false;for _,neighbor in ipairs(node.links) do if tree.nodes[neighbor].choiceOption and set[neighbor] then chosen=true end end
			if not chosen then result.missingChoices[#result.missingChoices+1]=id end
		end
	end
	for _,count in pairs(result.counts) do if count.publishedMaximum then count.selectedPassivesExceedReference=count.allocated>count.publishedMaximum end end
	result.pointAccountingVerified=false
	return result
end
function M.toggle(plan,id)
	plan=M.validate(plan);local tree=M.tree();local node=tree.nodes[id]
	assert(node and not roots[id] and not wombs[id],"Select a Genesis passive")
	local set=selectedSet(plan)
	if set[id] then
		set[id]=nil;local connected=reachable(tree,set);local removed={}
		for candidate in pairs(set) do if not connected[candidate] then set[candidate]=nil;removed[#removed+1]=candidate end end
		removed[#removed+1]=id;table.sort(removed)
		local nodes={};for candidate in pairs(set) do nodes[#nodes+1]=candidate end
		return M.validate({version=M.version,nodes=nodes}),removed
	end
	local parent,adjacent
	for _,neighbor in ipairs(node.links) do
		if roots[neighbor] or wombs[neighbor] or set[neighbor] then adjacent=true end
		if node.choiceOption and tree.nodes[neighbor].choice then parent=neighbor end
	end
	assert(adjacent,"Allocate a connected passive first")
	if node.choiceOption then
		assert(parent and set[parent],"Allocate the choice node first")
		for _,neighbor in ipairs(tree.nodes[parent].links) do if tree.nodes[neighbor].choiceOption then set[neighbor]=nil end end
	end
	set[id]=true;local nodes={};for candidate in pairs(set) do nodes[#nodes+1]=candidate end
	return M.validate({version=M.version,nodes=nodes}),{}
end
function M.connect(plan,id)
	plan=M.validate(plan);local tree=M.tree();local node=tree.nodes[id]
	assert(node and not roots[id] and not wombs[id],"Select a Genesis passive")
	local allocated=selectedSet(plan);assert(not allocated[id],"This Genesis passive is already allocated")
	local target=id
	if node.choiceOption then
		for _,neighbor in ipairs(node.links) do if tree.nodes[neighbor].choice then target=neighbor;break end end
		assert(target~=id,"Genesis choice has no parent")
	end
	local queue,previous={},{}
	for _,candidate in ipairs(plan.nodes) do if tree.nodes[candidate].root==node.root and not tree.nodes[candidate].choiceOption then queue[#queue+1]=candidate end end
	for womb in pairs(wombs) do if tree.nodes[womb].root==node.root then queue[#queue+1]=womb end end
	table.sort(queue);for _,candidate in ipairs(queue) do previous[candidate]=false end
	local index=1
	while index<=#queue and previous[target]==nil do
		local current=queue[index];index=index+1
		for _,neighbor in ipairs(tree.nodes[current].links) do
			if previous[neighbor]==nil and tree.nodes[neighbor].root==node.root and not tree.nodes[neighbor].choiceOption and not roots[neighbor] then
				previous[neighbor]=current;queue[#queue+1]=neighbor
			end
		end
	end
	assert(previous[target]~=nil,"No connected Genesis path is available")
	local path={};local current=target
	while current and previous[current]~=false do table.insert(path,1,current);current=previous[current] end
	if node.choiceOption then path[#path+1]=id end
	local result=plan
	for _,candidate in ipairs(path) do result=M.toggle(result,candidate) end
	return result,path
end
return M
