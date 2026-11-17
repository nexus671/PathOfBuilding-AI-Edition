-- cspell:ignore Siveran
-- Current colour model follows Siveran's CC0 calculator (3.29).
local S={}
local colours={"R","G","B"}
function S.extend(M,A,api)
	local methods={vorici_socket_count="Vorici: best of 100 socket counts",vorici_socket_colours="Vorici: best of 25 socket colours",beast_max_links="Bestiary: maximum links",jeweller="Jeweller's Orb (experimental)",fusing="Orb of Fusing (experimental)",omen_jeweller="Jeweller's Orb + Omen of the Jeweller",omen_trichromatism="Omen of Trichromatism (RGB)",omen_connections="Orb of Fusing + Omen of Connections",chromatic="Chromatic Orb",socket_colour_bench="Bench: non-white sockets",socket_white_bench="Bench: white sockets (3.30)",tainted_chromatic="Tainted Chromatic Orb",tainted_jeweller="Tainted Jeweller's Orb",tainted_fusing="Tainted Orb of Fusing"}
	for method,label in pairs(methods) do M.methods[#M.methods+1]=method;M.labels[method]=label end;table.sort(M.methods)
	local originalAction,originalOptions,originalPrice,originalComponents=M.action,M.actionOptions,M.priceKey,M.components
	local function naturalLimit(model,state)
		local level=model.item.itemLevel
		return math.min(M.socketLimit(model,state),level >= 50 and 6 or level >= 35 and 5 or level >= 25 and 4 or level >= 2 and 3 or 2)
	end
	M.methodChecks.omen_jeweller=function(model,state)
		local sockets=state.sockets or {}
		if #sockets==0 then return "Add a socket before using a Jeweller's Orb." end
		for _,socket in ipairs(sockets) do if socket.color=="A" then return "Abyssal sockets need a separate socket model." end end
		if #sockets>=naturalLimit(model,state) then return "The item already has its maximum natural socket count." end
	end
	M.methodChecks.jeweller=M.methodChecks.omen_jeweller
	M.methodChecks.vorici_socket_count=M.methodChecks.omen_jeweller
	M.methodChecks.vorici_socket_colours=function(model,state)
		if #(state.sockets or {})==0 then return "Add sockets before using Vorici's bench." end
		for _,socket in ipairs(state.sockets) do if socket.color=="A" then return "Abyssal sockets need a separate socket model." end end
	end
	-- Historical community estimates for zero-quality weapons. Applying these
	-- weights to other bases, and the quality adjustment, are model assumptions.
	function S.jewellerProbabilities(model,state)
		local limit=naturalLimit(model,state);local current=#(state.sockets or {})
		local weights={100,90,80,30,5,1};local total=0
		for count=1,limit do if count~=current then total=total+weights[count] end end
		assert(total>0,"No different socket count is available")
		local maximum=weights[limit]/total
		local adjusted=math.min(1,maximum*(1+math.min(math.max(state.quality or 0,0),30)/100))
		local remainder=maximum<1 and (1-adjusted)/(1-maximum) or 0
		local probabilities={}
		for count=1,limit do
			probabilities[count]=count==current and 0 or count==limit and adjusted or weights[count]/total*remainder
		end
		return probabilities
	end
	M.methodChecks.omen_connections=function(model,state)
		local sockets=state.sockets or {}
		if #sockets<2 then return "Add at least two sockets before linking." end
		local linked=true
		for _,socket in ipairs(sockets) do
			if socket.color=="A" then return "Abyssal sockets need a separate socket model." end
			linked=linked and socket.group==sockets[1].group
		end
		if linked then return "The item is already fully linked." end
	end
	M.methodChecks.fusing=function(model,state)
		local sockets=state.sockets or {};if #sockets<2 then return "Link crafting needs at least two sockets." end
		local linked=true;for _,socket in ipairs(sockets) do
			if socket.color=="A" then return "Abyssal sockets need a separate socket model." end
			linked=linked and socket.group==sockets[1].group
		end
		if #sockets>=5 and linked then return "The item is already fully linked." end
	end
	-- Historical six-socket observations at 20% quality. The same group-size
	-- weights for shorter remainders and the quality adjustment are assumptions.
	function S.fusingOutcomes(state)
		local sockets=state.sockets or {};local n=#sockets;assert(n>=2 and n<=6,"Link crafting needs two to six sockets")
		local base={0.178184223,0.348177081,0.267663189,0.196718817,0.008256689,0.001}
		local current={};for i=2,n do current[i-1]=sockets[i].group==sockets[i-1].group end
		local candidates={};local groups={}
		local function visit(start,group,probability)
			if start>n then
				local same=true;for i=2,n do if (groups[i]==groups[i-1])~=current[i-1] then same=false;break end end
				if not same then candidates[#candidates+1]={groups=copyTable(groups),probability=probability} end
				return
			end
			local remaining=n-start+1;local total=0;for length=1,remaining do total=total+base[length] end
			local maximum=base[remaining]/total
			local adjusted=math.min(1,maximum*(1+math.min(math.max(state.quality or 0,0),30)/100)/1.2)
			local remainder=maximum<1 and (1-adjusted)/(1-maximum) or 0
			for length=1,remaining do
				local chance=remaining==1 and 1 or length==remaining and adjusted or base[length]/total*remainder
				for i=start,start+length-1 do groups[i]=group end
				visit(start+length,group+1,probability*chance)
			end
		end
		visit(1,0,1);local total=0;for _,entry in ipairs(candidates) do total=total+entry.probability end
		assert(total>0,"No different socket-link layout is available")
		for _,entry in ipairs(candidates) do entry.probability=entry.probability/total end
		return candidates
	end
	M.methodChecks.beast_max_links=M.methodChecks.omen_connections
	M.methodChecks.tainted_fusing=function(model,state)
		local sockets=state.sockets or {}
		if #sockets<2 then return "Link crafting needs at least two sockets." end
		local linked=true
		for _,socket in ipairs(sockets) do linked=linked and socket.group==sockets[1].group end
		if linked then return "The item is already fully linked." end
	end
	M.methodChecks.omen_trichromatism=function(model,state)
		if #(state.sockets or {})<3 then return "Add at least three sockets for the RGB guarantee." end
		for _,socket in ipairs(state.sockets) do if socket.color=="A" then return "Abyssal sockets need a separate socket model." end end
	end
	local function colourWeights(model,tainted)
		if tainted then return {1/3,1/3,1/3} end
		local values={model.item.requirements.str or 0,model.item.requirements.dex or 0,model.item.requirements.int or 0}
		local total,n=0,0;for _,value in ipairs(values) do total=total+value;if value > 0 then n=n+1 end end
		if n == 0 then return {1/3,1/3,1/3} end
		local result={}
		for i,value in ipairs(values) do
			if n == 1 then result[i]=value > 0 and 0.9*(value+10)/(total+20) or 0.05+4.5/(total+20)
			elseif n == 2 then result[i]=value > 0 and 0.9*value/total or 0.1
			else result[i]=value/total end
		end
		return result
	end
	local function colour(weights,random)
		local pick=random();for i,value in ipairs(weights) do pick=pick-value;if pick < 0 then return colours[i] end end;return "B"
	end
	local function recolour(model,state,method,craft,tainted,random)
		local sockets=state.sockets;local rgb=method == "omen_trichromatism"
		local forced=rgb and 3 or method == "socket_colour_bench" and api.integer(craft.count,2,4,"minimum non-white sockets") or 1
		local indices={};for i,socket in ipairs(sockets) do if socket.color~="A" then indices[#indices+1]=i end end
		assert(forced <= #indices,"Not enough ordinary sockets for this colour craft")
		for i=#indices,2,-1 do local j=math.floor(random()*i)+1;indices[i],indices[j]=indices[j],indices[i] end
		local weights=colourWeights(model,tainted)
		local chance=math.min(1,0.00375*math.max(model.item.itemLevel-14,1)*(1+math.min(state.quality or 0,30)/100))
		for i,index in ipairs(indices) do
			if rgb and i<=3 then sockets[index].color=colours[i]
			else sockets[index].color=(i <= forced or random() < chance) and colour(weights,random) or "W" end
		end
	end
	function M.action(model,input,craft,random)
		local method=craft.method
		if not methods[method] then return originalAction(model,input,craft,random) end
		if method=="vorici_socket_count" then
			assert(not input.destroyed and not input.mirrored and not input.veil and not input.corrupted,"Vorici requires an uncorrupted, craftable item")
			local reason=M.methodChecks.vorici_socket_count(model,input);assert(not reason,reason)
			return M.bestJeweller(model,input,100,random)
		end
		if method=="vorici_socket_colours" then
			assert(not input.destroyed,"Cannot craft a destroyed item")
			local reason=M.methodChecks.vorici_socket_colours(model,input);assert(not reason,reason)
			return M.bestChromatic(model,input,25,random)
		end
		assert(not input.mirrored and not input.veil,"Cannot modify a mirrored item or unfinished unveil")
		local tainted=method:find("tainted_",1,true) ~= nil
		assert(method == "socket_colour_bench" or method == "socket_white_bench" or (input.corrupted or false) == tainted,tainted and "Tainted socket currency requires corruption" or "Use tainted currency or the bench on corrupted items")
		local state=copyTable(input);local sockets=state.sockets or {};state.sockets=sockets
		assert(#sockets > 0,"This item has no sockets")
		for _,socket in ipairs(sockets) do assert(socket.color ~= "A" or method=="chromatic","Abyssal sockets need a separate socket model") end
		if method == "socket_white_bench" then
			for _,socket in ipairs(sockets) do socket.color="W" end
		elseif method == "jeweller" or method == "omen_jeweller" then
			local count=naturalLimit(model,state)
			if method=="jeweller" then
				local probabilities=S.jewellerProbabilities(model,state);local pick=random()
				for i,chance in ipairs(probabilities) do pick=pick-chance;if pick<0 then count=i;break end end
			end
			while #sockets>count do table.remove(sockets) end
			local free=0;for _,socket in ipairs(sockets) do free=math.max(free,socket.group+1) end
			while #sockets<count do sockets[#sockets+1]={color="W",group=free};free=free+1 end
		elseif method == "fusing" then
			local outcomes=S.fusingOutcomes(state);local pick=random();local chosen=outcomes[#outcomes]
			for _,entry in ipairs(outcomes) do pick=pick-entry.probability;if pick<0 then chosen=entry;break end end
			for i,socket in ipairs(sockets) do socket.group=chosen.groups[i] end
		elseif method == "omen_connections" or method == "beast_max_links" then
			for _,socket in ipairs(sockets) do socket.group=0 end
		elseif method == "tainted_jeweller" then
			local limit=naturalLimit(model,state)
			if random() < 0.5 then if #sockets < limit then
				local free=0;for _,socket in ipairs(sockets) do free=math.max(free,socket.group+1) end
				sockets[#sockets+1]={color="W",group=free}
			end
			elseif #sockets > 1 then table.remove(sockets) end
		elseif method == "tainted_fusing" then
			assert(#sockets >= 2,"Link crafting needs at least two sockets")
			local groups={};local biggest={}
			for i,socket in ipairs(sockets) do groups[socket.group]=groups[socket.group] or {};local group=groups[socket.group];group[#group+1]=i;if #group > #biggest then biggest=group end end
			assert(#biggest < #sockets,"The item is already fully linked")
			if random() < 0.5 then
				local neighbour=biggest[#biggest]+1;if neighbour > #sockets then neighbour=biggest[1]-1 end
				sockets[neighbour].group=sockets[biggest[1]].group
			elseif #biggest > 1 then
				local free=0;for _,socket in ipairs(sockets) do free=math.max(free,socket.group+1) end
				sockets[biggest[#biggest]].group=free
			end
		else
			recolour(model,state,method,craft,tainted,random)
		end
		local previous,group=nil,-1
		for _,socket in ipairs(sockets) do local old=socket.group;if old ~= previous then group=group+1;previous=old end;socket.group=group end
		return state
	end
	-- Reuse one socket buffer while preserving the normal action's validation,
	-- random draws, group normalization and first-on-tie selection.
	local socketAction=M.action
	function M.bestJeweller(model,input,rolls,random)
		local probabilities=S.jewellerProbabilities(model,input);local best=0
		for _=1,rolls do
			local pick=random();local count=naturalLimit(model,input)
			for i,chance in ipairs(probabilities) do pick=pick-chance;if pick<0 then count=i;break end end
			best=math.max(best,count)
		end
		local offset=0;for i=1,best-1 do offset=offset+probabilities[i] end
		local chosen=offset+probabilities[best]/2
		return socketAction(model,input,{method="jeweller"},function() return chosen end)
	end
	function M.bestChromatic(model,input,rolls,random)
		local best=socketAction(model,input,{method="chromatic"},random)
		local work={sockets=copyTable(best.sockets),quality=input.quality};local bestCount=-1
		local function count(sockets) local n=0;for _,socket in ipairs(sockets) do if socket.color~="A" and socket.color~="W" then n=n+1 end end;return n end
		bestCount=count(best.sockets)
		for _=2,rolls do
			recolour(model,work,"chromatic",{},false,random)
			local n=count(work.sockets)
			if n>bestCount then for i,socket in ipairs(work.sockets) do best.sockets[i].color=socket.color end;bestCount=n end
		end
		return best
	end
	function M.bestFusing(model,input,rolls,random)
		local reason=M.methodReason(model,input,"fusing");assert(not reason,reason)
		local best=socketAction(model,input,{method="fusing"},random)
		local function largest(sockets)
			local longest,current,previous=0,0,nil
			for _,socket in ipairs(sockets) do current=socket.group==previous and current+1 or 1;previous=socket.group;longest=math.max(longest,current) end
			return longest
		end
		local bestCount=largest(best.sockets)
		if rolls>1 then
			local outcomes=S.fusingOutcomes(input)
			for _=2,rolls do
				local pick=random();local selected=outcomes[#outcomes]
				for _,entry in ipairs(outcomes) do pick=pick-entry.probability;if pick<0 then selected=entry;break end end
				local longest,current,previous=0,0,nil
				for _,group in ipairs(selected.groups) do current=group==previous and current+1 or 1;previous=group;longest=math.max(longest,current) end
				if longest>bestCount then for i,group in ipairs(selected.groups) do best.sockets[i].group=group end;bestCount=longest end
			end
		end
		return best
	end
	function M.actionOptions(model,state,method)
		if method ~= "socket_colour_bench" then return originalOptions(model,state,method) end
		local result={};for count=2,math.min(4,#(state.sockets or {})) do result[#result+1]={label="At least "..count.." non-white sockets",action={method=method,count=count}} end;return result
	end
	function M.priceKey(action) if action.method == "socket_colour_bench" then return action.method..":"..tostring(action.count) end;return originalPrice(action) end
	function M.components(action,state,model)
		if action.method == "beast_max_links" then return {beast_black_morrigan=1,beast_craicic_sand_spitter=1} end
		if action.method == "socket_white_bench" then
			local result={["Metadata/Items/Currency/CurrencyConvertToNormal"]=1};if state and state.corrupted then result["Metadata/Items/Currency/CurrencyCorrupt"]=1 end;return result
		end
		if action.method == "omen_connections" then return {["Metadata/Items/Currency/AncestralOmenOnFusingMakeFullLinks"]=1,["Metadata/Items/Currency/CurrencyRerollSocketLinks"]=1} end
		if action.method == "omen_jeweller" then return {["Metadata/Items/Currency/AncestralOmenOnJewellersMakeFullSockets"]=1,["Metadata/Items/Currency/CurrencyRerollSocketNumbers"]=1} end
		if action.method == "omen_trichromatism" then return {["Metadata/Items/Currency/AncestralOmenOnChromaticAddWhiteSockets"]=1,["Metadata/Items/Currency/CurrencyRerollSocketColours"]=1} end
		if action.method == "socket_colour_bench" then
			local amount=({[2]=5,[3]=20,[4]=75})[action.count]
			local result={chromatic=amount};if state and state.corrupted then result["Metadata/Items/Currency/CurrencyCorrupt"]=amount end;return result
		end
		return originalComponents(action,state,model)
	end
	local catalog=M.catalog
	function M.catalog(raw,query,limit,initialState)
		local result=catalog(raw,query,limit,initialState);local model=M.model(raw)
		local state=initialState and M.validateState(model,initialState) or model.initial
		model=M.context(model,state);query=(query or ""):lower();result.socketCrafts={}
		local available=require("Modules.CraftingAvailability").check
		for _,method in ipairs({"socket_bench","socket_white_bench","socket_colour_bench","chromatic","vorici_socket_colours","vorici_socket_count","beast_max_links","jeweller","fusing","omen_jeweller","omen_connections","omen_trichromatism","tainted_chromatic","tainted_jeweller","tainted_fusing"}) do
			local choices=(method=="socket_bench" or method=="socket_colour_bench") and M.actionOptions(model,state,method) or {{label=M.labels[method],action={method=method}}}
			local allowed,reason=available(method,state,model)
			for _,choice in ipairs(choices) do
				if #result.socketCrafts<(limit or 50) and (method.." "..choice.label):lower():find(query,1,true) then
					result.socketCrafts[#result.socketCrafts+1]={method=method,label=choice.label,action=copyTable(choice.action),priceKey=M.priceKey(choice.action),
						available=allowed,unavailableReason=not allowed and reason or nil,deterministic=method=="socket_bench" or method=="socket_white_bench" or method=="beast_max_links" or method=="omen_jeweller" or method=="omen_connections",guaranteedColours=method=="omen_trichromatism" and "RGB" or nil,components=M.components(choice.action,state)}
				end
			end
		end
		return result
	end
	M.limits[#M.limits+1]="Omen of Trichromatism guarantees one red, green and blue socket using one Omen and one Chromatic Orb. Forced positions are sampled uniformly; remaining sockets use the existing colour model. Placement and extra-colour probabilities are model assumptions."
	M.limits[#M.limits+1]="The white socket bench action uses the announced 3.30 rule. Other crafting rules and modifier pools have separate data sources and limitations."

	M.limits[#M.limits+1]="Socket colours use Siveran's empirical 3.29 model, with attribute bias for ordinary Chromatics and uniform RGB for tainted Chromatics. Tainted socket/link currencies assume 50/50 addition/removal; added sockets are white. Tainted Fusing grows the largest group by one socket, so a 4-link and 2-link become a 5-link and one unlinked socket, not a 6-link. It selects the first largest group and extends it to the right when possible; tie and direction rules are model assumptions."
end
return S
