-- cspell:ignore Kalguuran Trarthan
-- Presentation queries over the pinned graph; no character or map-odds simulation.
local atlas=require("Modules.AtlasPlanner")
local M={mechanics={"Maps","Essence","Harvest","Expedition","Breach","Legion","Blight","Delirium","Ritual","Beyond","Abyss","Strongboxes","Shrines","Heist","Delve","Bestiary","Incursion","Betrayal","Ultimatum","Bosses","Mirage","Wildwood","Sentinels","Torment","Rogue Exiles","Mercenaries","Ore Deposits","Threads"}}
local threadRestrictions={
	{mechanic="Blight",effect="Sleeping Pantheon god replaces the pump",areaLevel=73},
	{mechanic="Abyss",effect="Rare monsters have an additional Abyssal modifier",areaLevel=80},
	{mechanic="Ultimatum",effect="Double Down encounters",areaLevel=73},
	{mechanic="Bestiary",effect="Monsters empowered with wisps",areaLevel=80},
	{mechanic="Betrayal",effect="Catarina accompanies encounters",areaLevel=80},
	{mechanic="Betrayal",effect="Syndicate members gain Rare Monster modifiers",areaLevel=80},
	{mechanic="Breach",effect="Rare monsters gain an additional Breach modifier",areaLevel=73},
}
local threadMilestones={
	{mechanic="Abyss",values={"1 additional pit","2 additional pits","3 additional pits"}},
	{mechanic="Breach",values={"20% increased Magic Breach monsters","40% increased Magic Breach monsters","60% increased Magic Breach monsters"}},
	{mechanic="Blight",values={"+40% surpassing chance for a lane to be at least Magic","+80% surpassing chance for a lane to be at least Magic","+120% surpassing chance for a lane to be at least Magic"}},
	{mechanic="Legion",values={"1 additional encounter","2 additional encounters","3 additional encounters"}},
	{mechanic="Expedition",values={"15% surpassing chance for an additional Remnant suffix","30% surpassing chance for an additional Remnant suffix","50% surpassing chance for an additional Remnant suffix"}},
	{mechanic="Ultimatum",values={"15% increased Rare monsters","15% increased Rare monsters; rewards as one additional round","30% increased Rare monsters; rewards as one additional round"}},
	{mechanic="Ritual",values={"20% increased Favours","40% increased Favours","60% increased Favours"}},
	{mechanic="Bestiary",values={"2 additional Red Beasts","3 additional Red Beasts","4 additional Red Beasts"}},
	{mechanic="Betrayal",values={"30% increased reinforcement chance","60% increased reinforcement chance","90% increased reinforcement chance"}},
	{mechanic="Incursion",values={"20% increased pack size","30% increased pack size","40% increased pack size"}},
}
-- The patch describes necessary conditions, not an exhaustive offer pool or odds.
function M.threadRestrictionReference()
	local rows=copyTable(threadRestrictions);for _,row in ipairs(rows) do row.singleSpendRestricted=true end
	return {modifiers=rows,patch="3.30.0b Hotfix 3",source="https://www.pathofexile.com/forum/view-thread/4015683",note="The seven modifiers are restricted by area level and cannot occur when only one Thread is spent. This check assumes the relevant type's spend is what matters; interactions with other Thread types are unverified. Applied Threads may include free or bonus Threads. Other requirements, offer availability and probabilities are not modeled."}
end
function M.threadRestrictions(areaLevel,threads,spentAbyssThreads,spentThreads)
	assert(type(areaLevel)=="number" and areaLevel==math.floor(areaLevel) and areaLevel>=1 and areaLevel<=100,"Use an area level from 1 to 100")
	assert(type(threads)=="number" and threads==math.floor(threads) and threads>=0 and threads<=100,"Use a non-negative whole Thread count up to 100")
	assert(spentAbyssThreads==nil or type(spentAbyssThreads)=="number" and spentAbyssThreads==math.floor(spentAbyssThreads) and spentAbyssThreads>=0 and spentAbyssThreads<=100,"Use a non-negative whole Abyss Thread spend up to 100")
	assert(spentThreads==nil or type(spentThreads)=="number" and spentThreads==math.floor(spentThreads) and spentThreads>=0 and spentThreads<=100,"Use a non-negative whole Thread spend up to 100")
	assert(spentThreads==nil or spentThreads<=threads,"Threads spent cannot exceed Threads applied for the same type")
	local result=M.threadRestrictionReference();result.areaLevel=areaLevel;result.threads=threads;result.spentThreads=spentThreads
	for _,row in ipairs(result.modifiers) do
		if areaLevel<row.areaLevel or spentThreads==1 then row.restrictionsMet=false;row.conditionStatus="restricted"
		elseif spentThreads and spentThreads>=2 then row.restrictionsMet=true;row.conditionStatus="conditions_met"
		else row.conditionStatus="spend_unresolved" end
	end
	local tier=threads>=8 and 3 or threads>=6 and 2 or threads>=3 and 1 or 0
	result.guaranteedWhenSpending=threads==0 and 0 or threads>=8 and 3 or threads>=4 and 2 or 1
	result.guaranteeStatus=threads==0 and "no_threads" or spentThreads==nil and "spend_unresolved" or spentThreads==0 and "free_only_unverified" or "confirmed_spend"
	if threads==0 or spentThreads and spentThreads>0 then result.guaranteedModifiers=result.guaranteedWhenSpending end
	result.guaranteeRequiresSpend=true
	result.guaranteeNote="The published modifier guarantee applies when spending Threads; the applied count sets its tier. Free-only cases are not established. guaranteedWhenSpending is conditional; guaranteedModifiers is omitted when the spend is zero or unknown."
	result.milestones={patch="3.30.0c",source="https://www.pathofexile.com/forum/view-thread/4017172",thresholds={3,6,8},threshold=tier>0 and ({3,6,8})[tier] or nil,mechanics={},note="Use the applied count for one Thread type, including free or bonus Threads. Published values are shown at the reached threshold; stacking between thresholds is not assumed."}
	for _,entry in ipairs(threadMilestones) do result.milestones.mechanics[#result.milestones.mechanics+1]={mechanic=entry.mechanic,values=copyTable(entry.values),current=tier>0 and entry.values[tier] or nil} end
	result.abyssalConsort={spentThreads=spentAbyssThreads,restricted=spentAbyssThreads==1 and true or nil,patch="3.30.0c",source="https://www.pathofexile.com/forum/view-thread/4017172",note="Abyssal Consorts cannot appear when only one Abyss Thread is spent. This is the spent count, separate from free or bonus Threads. Other counts and conditions are not evaluated."}
	return result
end
local aliases={Maps={"map","kirac"},Bosses={"boss","shaper","elder","maven","eater","exarch"},Strongboxes={"strongbox"},Shrines={"shrine"},Heist={"heist","smuggler","blueprint"},Bestiary={"beast","einhar"},Incursion={"incursion","alva"},Betrayal={"syndicate","jun","veiled item"},Delve={"sulphite","niko"},Harvest={"harvest","sacred grove","sacred flora","sacred fauna","sacred specimen","lifeforce"},Wildwood={"viridian wildwood","wildwood chance"},Sentinels={"sentinel"},Torment={"tormented spirit","tormented procurator"},["Rogue Exiles"]={"rogue exile"},Mercenaries={"mercenary","mercenaries","trarthan"},["Ore Deposits"]={"ore deposit","smelted bar","marking ore","kalguuran scarab"},Threads={"thread"}}
local wholeWord={alva=true,jun=true,niko=true,kirac=true,einhar=true,shaper=true,elder=true,maven=true,eater=true,exarch=true}
local searchTextCache=setmetatable({},{__mode="k"})
local function searchText(node)
	local parts={node.name,table.concat(node.stats," ")}
	local base=table.concat(parts," ")
	for _,effect in ipairs(node.variantEffects or {}) do for _,stat in ipairs(effect.stats) do parts[#parts+1]=stat end end
	local raw=table.concat(parts," ");local cached=searchTextCache[node]
	if not cached or cached.raw~=raw or cached.base~=base then
		local kind
		for _,stat in ipairs(node.stats) do
			local line=atlas.displayStat(stat):lower()
			if line:find("threads found in your maps cannot be of type",1,true) then kind="exclude";break end
			if line:find("increased chance for threads in your maps to be of type",1,true) then kind="increase";break end
		end
		local lower=atlas.displayStat(raw):lower()
		cached={raw=raw,base=base,lower=lower,classification=kind and atlas.displayStat(base):lower() or lower,threadKind=kind};searchTextCache[node]=cached
	end
	return cached.lower,cached.classification,cached.threadKind
end
local function letter(byte) return byte and byte>=97 and byte<=122 end
local function matches(text,name)
	for _,word in ipairs(aliases[name] or {name:lower()}) do
		local position=1
		while true do
			local first,last=text:find(word,position,true);if not first then break end
			if not letter(text:byte(first-1)) and (not wholeWord[word] or not letter(text:byte(last+1))) then return true end
			position=first+1
		end
	end
	return false
end
local function primaryMechanic(text)
	-- Generic map text is common to every mechanic: classify it last.
	for i=2,#M.mechanics do local name=M.mechanics[i];if matches(text,name) then return name end end
	if matches(text,"Maps") then return "Maps" end
	return "Other"
end
-- These choices name Thread types, not the associated encounter mechanics.
-- Keep all variant text searchable, but exclude it when classifying the node.
local function threadKind(node)
	local _,_,kind=searchText(node);return kind
end
local function mechanicText(node)
	local _,classification=searchText(node);return classification
end
function M.mechanic(node)
	return primaryMechanic(mechanicText(node))
end
function M.hasMechanic(node,name)
	-- Keep generic map bonuses separate from mechanic-specific nodes.
	if name=="Maps" then return M.mechanic(node)=="Maps" end
	return matches(mechanicText(node),name)
end
function M.allMechanics(node)
	local text=mechanicText(node);local result={}
	for i=2,#M.mechanics do local name=M.mechanics[i];if matches(text,name) then result[#result+1]=name end end
	if #result==0 and matches(text,"Maps") then result[1]="Maps" end
	return result
end
-- The preview contains one selected Thread type on each of these node forms.
-- A Thread exclusion is not a restriction on the corresponding encounter.
function M.threadRule(plan,node)
	local kind=threadKind(node)
	if not kind then return nil end
	for _,choice in ipairs(plan.choices or {}) do if choice.node==node.id then
		for _,effect in ipairs(node.variantEffects or {}) do if effect.effect==choice.effect and #effect.stats==1 then
			local mechanic=atlas.displayStat(effect.stats[1]);if isValueInArray(M.mechanics,mechanic) then return {kind=kind,mechanic=mechanic,id=node.id,name=node.name} end
		end end
	end end
end
function M.selectedNode(plan,node)
	local rule=M.threadRule(plan,node)
	-- The selected type changes Thread drops, not encounter spawn or rewards.
	-- Keep it in threadRule rather than classifying it as encounter investment.
	return {name=node.name,stats=rule and node.stats or atlas.nodeStats(plan,node)}
end
function M.blocking(node)
	local lines={};for _,stat in ipairs(node.stats or {}) do local text=stat:lower();if text:find("no chance to contain",1,true) or text:find("cannot contain",1,true) then lines[#lines+1]=stat end end
	return lines
end
function M.costs(plan,avoid)
	local tree=atlas.tree(plan.version);local blocked={};for _,id in ipairs(atlas.exclusions(plan,avoid)) do blocked[id]=true end
	local costs={[tree.start]=0};local queue={tree.start}
	for _,id in ipairs(plan.nodes) do costs[id]=0;queue[#queue+1]=id end
	local index=1
	while index<=#queue do
		local id=queue[index];index=index+1
		for _,nextId in ipairs(tree.nodes[id].links) do if costs[nextId]==nil and not blocked[nextId] then costs[nextId]=costs[id]+1;queue[#queue+1]=nextId end end
	end
	return costs
end
function M.results(plan,query,mechanic,avoid)
	local costs=M.costs(plan,avoid);local tree=atlas.tree(plan.version);local entries={}
	query=(query or ""):lower()
	for id,node in pairs(tree.nodes) do if id~=tree.start then
		local text,classification=searchText(node)
		if (mechanic==nil or mechanic=="All" or mechanic=="Maps" and primaryMechanic(classification)=="Maps" or mechanic~="Maps" and matches(classification,mechanic)) and text:find(query,1,true) then
			entries[#entries+1]={id=id,node=node,cost=costs[id]}
		end
	end end
	table.sort(entries,function(a,b) if a.cost~=b.cost then return (a.cost or math.huge)<(b.cost or math.huge) elseif a.node.name~=b.node.name then return a.node.name<b.node.name else return a.id<b.id end end)
	return entries
end
function M.compare(before,after)
	assert(before.version==after.version,"Choose plans from the same Atlas version to compare")
	local old,new={},{};for _,id in ipairs(before.nodes) do old[id]=true end;for _,id in ipairs(after.nodes) do new[id]=true end
	local result={added={},removed={},stats={},modifierChanges={},choiceChanges={}};local tree=atlas.tree(after.version)
	local priorChoices,nextChoices={},{}
	for _,choice in ipairs(before.choices or {}) do priorChoices[choice.node]=choice.effect end
	for _,choice in ipairs(after.choices or {}) do nextChoices[choice.node]=choice.effect end
	for _,id in ipairs(after.nodes) do if tree.nodes[id].variantEffects and (not old[id] or priorChoices[id]~=nextChoices[id]) then
		result.choiceChanges[#result.choiceChanges+1]={id=id,name=tree.nodes[id].name,previousEffect=priorChoices[id],effect=nextChoices[id],stats=atlas.nodeStats(after,tree.nodes[id])}
	end end
	for id in pairs(new) do if not old[id] then result.added[#result.added+1]=tree.nodes[id] end end
	for id in pairs(old) do if not new[id] then result.removed[#result.removed+1]=tree.nodes[id] end end
	for _,list in ipairs({result.added,result.removed}) do table.sort(list,function(a,b) return a.id<b.id end) end
	local counts={};local beforeReport,afterReport=atlas.report(before),atlas.report(after)
	for _,entry in ipairs(beforeReport.stats) do counts[entry.text]=-entry.count end
	for _,entry in ipairs(afterReport.stats) do counts[entry.text]=(counts[entry.text] or 0)+entry.count end
	for text,count in pairs(counts) do if count~=0 then result.stats[#result.stats+1]=string.format("%+dx %s",count,text) end end
	table.sort(result.stats)
	local changes={}
	for _,entry in ipairs(beforeReport.additiveTotals) do local key=entry.prefix.."\0"..entry.suffix;changes[key]={text=entry.prefix.."increased "..entry.suffix,delta=-entry.value} end
	for _,entry in ipairs(afterReport.additiveTotals) do local key=entry.prefix.."\0"..entry.suffix;local change=changes[key] or {text=entry.prefix.."increased "..entry.suffix,delta=0};change.delta=change.delta+entry.value;changes[key]=change end
	for _,change in pairs(changes) do if change.delta~=0 then result.modifierChanges[#result.modifierChanges+1]=change end end
	table.sort(result.modifierChanges,function(a,b) return a.text<b.text end)
	return result
end
-- A previous stage cannot already depend on this draft. Check the complete
-- saved chain, including missing or incompatible ancestors, before offering it.
function M.previousCandidates(plan,plans)
	local byId={};for _,entry in ipairs(plans) do byId[entry.id]=entry end
	local result={};local resolved={[plan.id]=false}
	for _,entry in ipairs(plans) do if entry.id~=plan.id and entry.version==plan.version then
		local seen,path={},{};local current=entry;local valid
		while current do
			if resolved[current.id]~=nil then valid=resolved[current.id];break end
			if seen[current.id] or current.version~=plan.version then valid=false;break end
			seen[current.id]=true;path[#path+1]=current.id
			local previous=current.progression and current.progression.previousId
			if not previous or previous=="" then valid=true;break end
			current=byId[previous];if not current then valid=false;break end
		end
		for _,id in ipairs(path) do resolved[id]=valid end
		if valid then result[#result+1]=entry end
	end end
	return result
end
function M.routes(plan,target,avoid,preferred)
	local routes={};local seen={}
	local function add(label,targets,blocked)
		local ok,nextPlan,added=pcall(atlas.connect,plan,targets,blocked)
		if ok then local signature=table.concat(nextPlan.nodes,",");if not seen[signature] then seen[signature]=true;routes[#routes+1]={label=label,plan=nextPlan,added=added,cost=#added} end end
	end
	add("Shortest connection",{target},avoid)
	if preferred and preferred~=target then add("Via preferred node",{preferred,target},avoid) end
	if routes[1] then
		local first=routes[1].added
		-- Additions are returned from target back towards the existing tree.
		-- The last addition is a valid intermediate node too, including for a
		-- two-node route; only the target itself must remain unblocked.
		for i=2,math.min(#first,9) do local blocked=copyTable(avoid or {});blocked[#blocked+1]=first[i];add("Alternative connection",{target},blocked);if #routes>=4 then break end end
	end
	table.sort(routes,function(a,b) if a.cost~=b.cost then return a.cost<b.cost else return a.label<b.label end end)
	return routes
end
function M.presets(plan)
	plan=atlas.validate(plan)
	local tree=atlas.tree(plan.version);local allocated={[tree.start]=true};for _,id in ipairs(plan.nodes) do allocated[id]=true end
	local blocked={};for id,node in pairs(tree.nodes) do if not allocated[id] and #M.blocking(node)>0 then blocked[#blocked+1]=id end end;table.sort(blocked)
	-- These exclusions apply only while calculating the suggestion. Preserve
	-- the user's desired and avoided preferences in the resulting plan.
	local working=copyTable(plan);working.desired=nil
	local function restore(candidate)
		candidate.desired=plan.desired and copyTable(plan.desired) or nil
		candidate.avoided=plan.avoided and copyTable(plan.avoided) or nil
		return atlas.validate(candidate)
	end
	local result={};local costs=M.costs(plan,blocked);local candidates={}
	for _,mechanic in ipairs(M.mechanics) do candidates[mechanic]={} end
	for id,node in pairs(tree.nodes) do if costs[id] and not allocated[id] and node.kind=="notable" and #M.blocking(node)==0 then
		local text=mechanicText(node)
		for _,mechanic in ipairs(M.mechanics) do
			local matched=mechanic=="Maps" and M.mechanic(node)=="Maps" or mechanic~="Maps" and matches(text,mechanic)
			if matched then local bucket=candidates[mechanic];bucket[#bucket+1]={id=id,node=node,cost=costs[id]} end
		end
	end end
	for _,mechanic in ipairs(M.mechanics) do
		local targets={};local entries=candidates[mechanic]
		table.sort(entries,function(a,b) if a.cost~=b.cost then return a.cost<b.cost elseif a.node.name~=b.node.name then return a.node.name<b.node.name else return a.id<b.id end end)
		for i=1,math.min(3,#entries) do targets[i]=entries[i].id end
		if #targets>0 then
			local nextPlan=copyTable(working);local kept={}
			for _,target in ipairs(targets) do local ok,value=pcall(atlas.connect,nextPlan,{target},blocked);if ok then nextPlan=value;kept[#kept+1]=target end end
			-- Try the whole target set before dropping a notable for the budget.
			local ok,optimized,_,routing=pcall(atlas.connectOptimized,working,targets,blocked,{exact=false})
			if ok then nextPlan=optimized;kept=targets else
				ok,optimized,_,routing=pcall(atlas.connectOptimized,working,kept,blocked,{exact=false});if ok then nextPlan=optimized end
			end
			if #kept>0 then result[#result+1]={label=mechanic.." starting route",plan=restore(nextPlan),targets=kept,mechanic=mechanic,routing=ok and routing or nil} end
		end
	end
	return result
end
function M.transition(before,after)
	local diff=M.compare(before,after);local tree=atlas.tree(after.version);local goal={};for _,id in ipairs(after.nodes) do goal[id]=true end
	local budget=math.max(before.budget,after.budget)
	-- Saved legacy plans can be structurally valid while relying on a grant
	-- that they cannot reach with their earned points. Preferences do not
	-- restrict temporary respec paths, so check reachability without them.
	local starting=copyTable(before);starting.budget=budget;starting.desired=nil;starting.avoided=nil
	local startingReachable,startingWarning=atlas.budgetReachability(starting)
	local function freePoints(state)
		local granted=tree.nodes[tree.start].grantedPoints or 0
		for _,id in ipairs(state.nodes) do granted=granted+(tree.nodes[id].grantedPoints or 0) end
		return state.budget+granted-#state.nodes
	end
	local function route(rebuild,initial)
		local state=copyTable(initial or before);state.budget=budget
		-- Saved routing preferences can change between stages. They do not
		-- prevent allocating or refunding the nodes in a respec sequence.
		state.desired=nil;state.avoided=nil
		local steps={};local clearing=rebuild
		for _=1,#state.nodes+#after.nodes+1 do
			if table.concat(state.nodes,",")==table.concat(after.nodes,",") then return steps end
			if #state.nodes==0 then clearing=false end
			local nextState,step
			for index,id in ipairs(state.nodes) do if clearing or not goal[id] then
				local candidate=copyTable(state);table.remove(candidate.nodes,index)
				if candidate.choices then for i=#candidate.choices,1,-1 do if candidate.choices[i].node==id then table.remove(candidate.choices,i) end end end
				local ok,validated=pcall(atlas.validate,candidate)
				if ok then nextState=validated;step={action="Refund",id=id};break end
			end end
			if not nextState and not clearing and freePoints(state)>0 then
				local allocated={[tree.start]=true};for _,id in ipairs(state.nodes) do allocated[id]=true end
				for _,id in ipairs(after.nodes) do if not allocated[id] then
					local adjacent=false;for _,other in ipairs(tree.nodes[id].links) do if allocated[other] then adjacent=true;break end end
					if adjacent then local candidate=copyTable(state);candidate.nodes[#candidate.nodes+1]=id;local ok,validated=pcall(atlas.validate,candidate);if ok then nextState=validated;step={action="Allocate",id=id};break end end
				end end
			end
			if not nextState then return end
			steps[#steps+1]=step;state=nextState
		end
	end
	local steps,rebuilt
	if startingReachable~=false then steps=route(false);rebuilt=false;if not steps then steps=route(true);rebuilt=steps~=nil end end
	local temporary=false
	if startingReachable~=false and not steps then
		local allocated={[tree.start]=true};for _,id in ipairs(before.nodes) do allocated[id]=true end
		local grants={};for _,id in ipairs(after.nodes) do if not allocated[id] and (tree.nodes[id].grantedPoints or 0)>0 then grants[#grants+1]=id end end
		if #grants==1 then
			local avoid={};for _,id in ipairs(after.avoided or {}) do if not allocated[id] then avoid[#avoid+1]=id end end
			local start=copyTable(before);start.budget=budget;start.desired=nil;start.avoided=nil
			local ok,via,added=pcall(atlas.connect,start,{grants[1]},avoid)
			if ok then
				local prefix={};local state=copyTable(start)
				for i=#added,1,-1 do if freePoints(state)<1 then prefix=nil;break end;local candidate=copyTable(state);candidate.nodes[#candidate.nodes+1]=added[i];local valid,nextState=pcall(atlas.validate,candidate);if not valid then prefix=nil;break end;state=nextState;prefix[#prefix+1]={action="Allocate",id=added[i]} end
				if prefix then local suffix=route(false,via);if suffix then steps=prefix;for _,step in ipairs(suffix) do steps[#steps+1]=step end;temporary=true end end
			end
		end
	end
	local noted={};for _,change in ipairs(diff.choiceChanges) do noted[change.id]=true end
	if steps then for _,step in ipairs(steps) do if step.action=="Refund" and goal[step.id] and not noted[step.id] then
		for _,choice in ipairs(after.choices or {}) do if choice.node==step.id then
			diff.choiceChanges[#diff.choiceChanges+1]={id=step.id,name=tree.nodes[step.id].name,effect=choice.effect,stats=atlas.nodeStats(after,tree.nodes[step.id])};noted[step.id]=true;break
		end end
	end end end
	local refunded={};for _,step in ipairs(steps or {}) do if step.action=="Refund" then refunded[step.id]=true end end
	local choiceReselectionCostUnknown=false
	for _,change in ipairs(diff.choiceChanges) do
		if change.previousEffect and change.effect and change.previousEffect~=change.effect and not refunded[change.id] then
			change.reselectionCostUnknown=true;choiceReselectionCostUnknown=true
		end
	end
	local result={added=diff.added,removed=diff.removed,stats=diff.stats,choiceChanges=diff.choiceChanges,choiceReselectionCostUnknown=choiceReselectionCostUnknown,steps=steps,rebuild=rebuilt,temporary=temporary,startingReachable=startingReachable,startingStatus=startingReachable==nil and "unknown" or startingReachable and "reachable" or "unreachable",startingWarning=startingWarning,lines={before.title.." -> "..after.title,#diff.removed.." changed nodes to refund; "..#diff.added.." changed nodes to allocate.","Route assumes "..budget.." base points are available. Each step preserves connectivity and the supplied budget plus granted points. Refund currency prices are not assumed."}}
	if startingReachable==false then result.lines[#result.lines+1]="Starting plan cannot be reached with this budget. "..startingWarning
	elseif startingReachable==nil then result.lines[#result.lines+1]="Starting plan reachability is unverified; this route assumes it is already allocated. "..startingWarning end
	if steps then
		local refunds=0;for _,step in ipairs(steps) do if step.action=="Refund" then refunds=refunds+1 end end
		result.lines[#result.lines+1]=(temporary and "Temporary grant path; includes extra refunds. " or rebuilt and "Rebuild route; may require extra refunds. " or "Direct route. ")..refunds.." node refunds, "..(#steps-refunds).." allocations. This is a valid allocation route, not a minimum-refund optimizer."
		for i,step in ipairs(steps) do result.lines[#result.lines+1]=i..". "..step.action..": "..tree.nodes[step.id].name.." ["..step.id.."]" end
	elseif startingReachable~=false then result.lines[#result.lines+1]="No sequential route found within this budget. Earn more points or plan a temporary route before applying these allocations." end
	if choiceReselectionCostUnknown then result.lines[#result.lines+1]="Changing an already selected effect may require an additional refund; its in-game cost and procedure are unverified and excluded from the node-refund count." end
	for _,change in ipairs(diff.choiceChanges) do
		result.lines[#result.lines+1]=change.effect and ("Choose effect for "..change.name.." ["..change.id.."]: "..table.concat(change.stats," ")) or ("Choose an effect for "..change.name.." ["..change.id.."]; the destination has none selected.")
	end
	return result
end
return M
