-- Constructive, conservative proof for a single Atlas point grant. A failure
-- to find a route is not proof that no valid allocation sequence exists.
local M={}
function M.find(tree,final,blocked,budget,grant)
	if not final[grant] or not tree.nodes[grant] or (tree.nodes[grant].grantedPoints or 0)<=0 then return nil end
	local incoming={};for id,node in pairs(tree.nodes) do for _,other in ipairs(node.links) do
		incoming[other]=incoming[other] or {};incoming[other][#incoming[other]+1]=id
	end end
	local start=tree.start;local parent={[start]=false};local queue={start};local index=1
	while index<=#queue and parent[grant]==nil do
		local id=queue[index];index=index+1
		for _,other in ipairs(tree.nodes[id].links) do
			if not blocked[other] and parent[other]==nil and other~=start then parent[other]=id;queue[#queue+1]=other end
		end
	end
	if parent[grant]==nil then return nil end
	local reverse={};local cursor=grant
	while cursor~=start do reverse[#reverse+1]=cursor;cursor=parent[cursor] end
	if #reverse>budget then return nil end
	local allocated={[start]=true};local steps={};local used=0
	for i=#reverse,1,-1 do
		local id=reverse[i];allocated[id]=true;used=used+1;steps[#steps+1]={action="Allocate",id=id}
	end
	local capacity=budget+(tree.nodes[grant].grantedPoints or 0)
	local ids={};for id in pairs(final) do if id~=start then ids[#ids+1]=id end end;table.sort(ids)
	local function removable(id)
		allocated[id]=nil
		local seen={[start]=true};local search={start};local head=1
		while head<=#search do local node=search[head];head=head+1;for _,other in ipairs(tree.nodes[node].links) do
			if allocated[other] and not seen[other] then seen[other]=true;search[#search+1]=other end
		end end
		local connected=true;for node in pairs(allocated) do if not seen[node] then connected=false;break end end
		allocated[id]=true;return connected
	end
	while true do
		local removed=true
		while removed do
			removed=false;local candidates={};for id in pairs(allocated) do if id~=start and not final[id] then candidates[#candidates+1]=id end end;table.sort(candidates)
			for _,id in ipairs(candidates) do if removable(id) then allocated[id]=nil;used=used-1;steps[#steps+1]={action="Refund",id=id};removed=true;break end end
		end
		local done=true;for _,id in ipairs(ids) do if not allocated[id] then done=false;break end end
		if done then return steps end
		if used>=capacity then return nil end
		local added
		for _,id in ipairs(ids) do if not allocated[id] then
			for _,other in ipairs(incoming[id] or {}) do if allocated[other] then added=id;break end end
			if added then break end
		end end
		if not added then return nil end
		allocated[added]=true;used=used+1;steps[#steps+1]={action="Allocate",id=added}
	end
end
return M
