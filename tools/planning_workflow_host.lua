-- Isolated native desktop side of the stdio MCP integration test. No live app.
local directory=assert(arg[1]):gsub("\\","/").."/"
io.stdout:setvbuf("no")
io.stderr:write("Native workflow: loading headless wrapper\n")
arg={};dofile("HeadlessWrapper.lua")
io.stderr:write("Native workflow: installing UI recorder\n")
local json=require("dkjson")
local bridge=require("Modules.DesktopBuildBridge")
local ui=require("Modules.HeadlessUI").install({width=1024,height=768})
local function frame()
	-- Each native frame replaces the recorder's previous draw commands.
	-- Calling OnFrame directly retains every tree draw across the whole workflow.
	ui:frame(function() runCallback("OnFrame") end)
end
io.stdout:setvbuf("no")
main.userPath=directory;main.buildPath=directory;main.defaultBuildPath=directory;main.disableDevAutoSave=true
newBuild()
io.stderr:write("Native workflow: calculating fixture\n")
build.buildName="MCP workflow fixture";build.characterLevel=80;build.characterLevelAutoMode=false
build.buildFlag=true;frame();ui:bind(build)
bridge.enable(build)
io.stderr:write("Native workflow: bridge ready\n")
local function respond(value) io.stdout:write("WORKFLOW\t"..json.encode(value).."\n") end
local injected={}
respond({ready=true,revision=bridge.revision(build)})
for line in io.lines() do
	local command=assert(json.decode(line))
	local ok,result=xpcall(function()
		if command.kind=="tick" then
			for i=1,command.frames or 1 do
				frame();bridge.poll(build,true)
				local status=bridge.status
				if command.untilId and status and status.id==command.untilId and (status.status==command.untilStatus or status.status=="failed") then break end
			end
		elseif command.kind=="convert-tree" then
			build.treeTab:ConvertToVersion(assert(command.version),true,false,true);frame();bridge.refresh(build)
			return {treeVersion=build.spec.treeVersion,revision=bridge.revision(build)}
		elseif command.kind=="equip-fixture-jewel" then
			local gear,spec=build.itemsTab,build.spec
			for _,slot in ipairs(gear.orderedSlots) do
				local node=slot.nodeId and spec.nodes[slot.nodeId]
				if node and node.path and not node.expansionJewel then
					spec:AllocNode(node)
					assert(spec.allocNodes[node.id])
					local item=new("Item"):Item(assert(command.itemText))
					gear:AddItem(item,true)
					slot:SetSelItemId(item.id)
					build.buildFlag=true;frame();bridge.refresh(build)
					return {jewelSocketId=node.id}
				end
			end
			error("No connected ordinary jewel socket in fixture")
		elseif command.kind=="inject-crafting-error" or command.kind=="inject-planning-error" then
			local simulator=command.kind=="inject-crafting-error" and require("Modules.CraftingSimulator") or require(assert(command.module))
			local key=assert(command.method)
			assert(command.kind=="inject-crafting-error" and (key=="catalog" or key=="beastCatalog" or key=="allflameProfile") or command.kind=="inject-planning-error" and (command.module=="Modules.MapCurrency" and (key=="planningOptions" or key=="options") or command.module=="Modules.CraftingProjects" and key=="blankBase"))
			local identity=(command.module or "Modules.CraftingSimulator")..":"..key
			if command.restore then simulator[key]=assert(injected[identity]);injected[identity]=nil
			else assert(not injected[identity]);injected[identity]=simulator[key];simulator[key]=function() error("Modules/Example.lua:12: First problem\nC:/PoB/Other.lua:34: Second problem\nstack traceback:\n internal frame",0) end end
		elseif command.kind=="request-test" then bridge.connectionTest={nonce="workflow-connection-test",requestedAt=os.time()};bridge.publishState()
		elseif command.kind=="connection-proof" then return {client=bridge.client and bridge.client.name,tested=bridge.connectionTest and bridge.connectionTest.passed,synced=bridge.client and bridge.client.contextRevision==bridge.contextRevision}
		elseif command.kind=="apply" then
			assert(bridge.prepared,"Expected a pending native review")
			build.viewMode="CONFIG";ui:bind(build);ui:click("aiBuild");ui:click("review");ui:click("apply")
			assert(not main.popups[1],"Native apply did not finish")
			build=main.modes.BUILD;ui:bind(build);frame();bridge.refresh(build)
		elseif command.kind=="reject-proposal" then
			assert(bridge.prepared,"Expected a pending native review")
			build.viewMode="CONFIG";ui:bind(build);ui:click("aiBuild");ui:click("review");ui:click("reject")
			frame();bridge.refresh(build)
		elseif command.kind=="undo-applied" then
			build.viewMode="CONFIG";ui:bind(build);ui:click("aiBuild");ui:choose("page","Plan & review");ui:click("restore")
			build=main.modes.BUILD;ui:bind(build);frame();bridge.refresh(build)
		elseif command.kind=="keep-sampled-target" then
			local project=build.savers.CraftingProjects.projects[1]
			local result=require("Modules.CraftingSimulator").simulate(project.startingItem,
				{steps={{method="alchemy"}},targets={},requirements={minAffixes=4}},
				{trials=1,maxActions=1,retainSuccesses=1,seed=5})
			local target=assert(result.retainedSuccesses[1]).itemText
			local analysis=require("Modules.CraftingAnalysis").get(build,project)
			analysis.results.simulation={result=result}
			local equipped=build.itemsTab.slots[project.slot].selItemId
			build.viewMode="CONFIG";ui:bind(build);ui:click("aiBuild");ui:click("nav_crafting");ui:click("native")
			ui:click("tab_simulate");ui:click("distribution");ui:click("keepTarget")
			assert(main.popups[1].title=="Replace crafting target");ui:click("confirm")
			assert(build.savers.CraftingProjects.projects[1].targetItem==target,"UI did not keep the sampled target")
			assert(build.itemsTab.slots[project.slot].selItemId==equipped,"Keeping a target equipped the item")
			ui:click("close");ui:click("close");frame();bridge.poll(build,true)
			return {target=target,revision=bridge.revision(build)}
		elseif command.kind=="save-reopen" then
			build.viewMode="CONFIG";ui:bind(build);ui:click("aiBuild");ui:click("nav_crafting");ui:click("native")
			ui:click("tab_craft");ui:click("currency_alchemy");ui:click("item")
			ui:click("tab_simulate");ui:text("trials","2");ui:text("budget","1");ui:click("runRecipe")
			local tasks=require("Modules.CraftingTasks");for i=1,1000 do if not tasks.job then break end;tasks.tick(build) end
			assert(not tasks.job and build.craftingAnalyses[build.savers.CraftingProjects.projects[1].id].results.simulation,"Simulation did not finish")
			ui:click("keepWorking")
			assert(build.savers.CraftingProjects.projects[1].run,"Checkpoint was not kept")
			build.dbFileName=directory.."journey.xml";build:SaveDBFile()
			assert(require("Modules.PlanningUI").saveStatus(build)=="Build saved","Save status did not acknowledge the actual file save")
			local file=assert(io.open(directory.."journey.xml","rb"));local xml=file:read("*a");file:close()
			bridge.disable(build);loadBuildFromXML(xml,"MCP workflow fixture");build=main.modes.BUILD;ui:bind(build)
			assert(not main.popups[1],"Reload opened a popup: "..tostring(main.popups[1] and main.popups[1].title).." | "..tostring(main.popups[1] and main.popups[1].controls[1] and main.popups[1].controls[1].label))
			assert(#build.savers.BuildJourney.data.wishlist==3 and build.savers.BuildJourney.data.wishlist[3].id=="surrender" and #build.savers.CraftingProjects.projects==2,"Saved plans did not reload")
			build.viewMode="CONFIG";ui:click("aiBuild");ui:click("nav_crafting");ui:click("native")
			assert(build.planningWorkspace.controls.undo:IsEnabled(),"Saved checkpoint did not restore undo")
			bridge.enable(build)
		elseif command.kind=="bundle-roundtrip" then
			local profile=require("Modules.LootFilters").profile("bundle-filter","Bundle filter")
			profile.trackBuildPickups=true;profile.rules={{id="bundle-rule",title="Chaos highlight",text='Show\n BaseType == "Chaos Orb"\n SetTextColor 255 0 0'}}
			build.savers.LootFilters:Upsert(profile)
			build.viewMode="CONFIG";ui:bind(build);ui:click("aiBuild");ui:click("nav_tools");ui:text("search","bundle");ui:click("choose");ui:click("export");ui:click("paste");ui:click("review")
			assert(bridge.prepared and bridge.prepared.mode=="new","Bundle did not prepare a new build")
			ui:click("apply");build=main.modes.BUILD;ui:bind(build);frame()
			assert(not build.dbFileName and #build.savers.AtlasPlans.plans==2 and build.savers.CraftingProjects.projects[1].run,"Bundle import lost saved metadata or reused the source file")
			local body=build.savers.CraftingProjects.projects[2]
			assert(body and body.id=="body-enchant" and body.nativeRecipe.requirements.harvestEnchant=="LifeBodyEnchant" and body.inventory[1].state.harvestEnchant=="LifeBodyEnchant","Bundle import lost the second gear guide or its enchantment")
			local restored=require("Modules.LootFilters").find(build.savers.LootFilters.data,"bundle-filter")
			assert(restored and restored.trackBuildPickups and restored.rules[1] and restored.rules[1].text==profile.rules[1].text,"Bundle import lost saved filter rules or build pickups")
		elseif command.kind=="quit" then bridge.disable(build);return {quit=true}
		else error("Unknown host command") end
		return {revision=bridge.revision(build),status=bridge.status and bridge.status.status,life=build.calcsTab.calcsOutput.LifeUnreserved,drawCommands=#ui.commands}
	end,debug.traceback)
	respond({id=command.id,ok=ok,result=ok and result or nil,error=not ok and tostring(result) or nil})
	if command.kind=="quit" then break end
end
ui:restore()
