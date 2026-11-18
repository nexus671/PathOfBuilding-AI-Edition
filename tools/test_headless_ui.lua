-- cspell:ignore Ukatoa Katakohi
-- Run from src: luajit ../tools/test_headless_ui.lua <existing-output-directory>
local directory=assert(arg[1],"Supply an output directory")
arg={}
dofile("HeadlessWrapper.lua")
main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI")
local sim=require("Modules.CraftingSimulator")
local frames=0
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
	newBuild();main.popups={}
	local ui=UI.install({width=size[1],height=size[2]})
	local function frame(name,hover)
		ui.cursorX,ui.cursorY=-100,-100
		if hover then local control=main.popups[1] and main.popups[1].controls[hover] or build.planningWorkspace.controls[hover];local x,y=control:GetPos();ui.cursorX,ui.cursorY=x+10,y+10 end
		ui:frame():write(directory.."/"..size[1].."-"..name..".json");frames=frames+1
		assert(not __mainObject__.promptMsg,__mainObject__.promptMsg)
	end
	-- Exercise the actual build-tab event loop, not direct panel callbacks.
	local bridge=require("Modules.DesktopBuildBridge")
	local json=require("dkjson")
	local originalOpen,originalRemove=io.open,os.remove
	local files={}
	io.open=function(path,mode)
		local name=path:match("AI%-build%-(%w+)%.json$")
		if not name then return originalOpen(path,mode) end
		if mode=="rb" and not files[name] then return nil end
		return {read=function(_,limit) return files[name]:sub(1,type(limit)=="number" and limit or -1) end,
			write=function(_,value) files[name]=value;return true end,close=function() return true end}
	end
	os.remove=function(path) local name=path:match("AI%-build%-(%w+)%.json$");if name then files[name]=nil;return true end;return originalRemove(path) end
	bridge.enabled=false;bridge.prepared=nil;bridge.plan={goal="balanced"};bridge.history={};bridge.undo={};bridge.owner=nil;bridge.previous=nil;bridge.comparison=nil
	build.viewMode="CONFIG";ui:bind(build);ui:click("aiBuild")
	assert(build.viewMode=="PLANNER" and #main.popups==0,"AI planner did not open as a native build tab")
	frame("ai-overview");ui:click("goals");frame("ai-goals")
	ui:text("budget","100");ui:text("minimumLife","3000");ui:click("save")
	ui:key("TAB");assert(build.planningWorkspace.body.selControl and build.planningWorkspace.body.selControl.hasFocus,"Tab did not retain visible keyboard focus");frame("planning-keyboard-focus");ui:key("ESCAPE")
	ui.keys.ALT=true;ui:key("2");assert(build.viewMode=="PLANNER" and build.planningWorkspace.page=="atlas","Alt+2 did not switch planning tools");ui:key("1");ui.keys.ALT=nil
	assert(bridge.plan.budget==100 and bridge.plan.minimums and bridge.plan.minimums.LifeUnreserved==3000,json.encode(bridge.plan).." popup="..tostring(main.popups[1] and main.popups[1].title))
	ui:click("candidates");frame("ai-empty-candidates");ui:click("close")
	ui:click("analysis");frame("ai-analysis");ui:click("close")
	ui:choose("page","Connection");frame("ai-connection");ui:click("setup")
	assert(ui.clipboard:find("McpServer.cjs",1,true))
	ui:click("enable");assert(bridge.enabled and files.context and files.state)
	ui:click("testConnection")
	files.client=json.encode({schemaVersion=1,session=bridge.session,name="Headless MCP client",seenAt=os.time(),contextRevision=bridge.contextRevision,testNonce=bridge.connectionTest.nonce})
	bridge.poll(build,true);assert(bridge.connectionTest.passed and bridge.client.name=="Headless MCP client","Client round-trip receipt was not recognized")
	frame("ai-client-confirmed")
	ui:click("diagnostics");frame("ai-diagnostics");ui:click("close")
	ui:choose("page","Plan & review")
	local original=main.modes.BUILD
	local prepared=bridge.prepare(original,{mode="edit",title="Headless life upgrade",baseRevision=bridge.revision(original),operations={{type="equip_item",slot="Helmet",text="Rarity: RARE\nTrial Hat\nIron Hat\nItem Level: 86\n+100 to maximum Life"}}})
	prepared.id="headless-review"
	prepared.audit.assumptions[#prepared.audit.assumptions+1]={text="Enabled condition: conditionFullEnergyShield. Check its source and uptime."}
	for i=1,60 do prepared.audit.assumptions[#prepared.audit.assumptions+1]={text="Review checklist entry "..i..": verify conditions and uptime before applying the candidate."} end
	bridge.remember(prepared);bridge.prepared=prepared
	ui:click("review");frame("ai-review-summary")
	ui:click("toggleMetrics");frame("ai-review-all-metrics");ui:click("toggleMetrics")
	ui:choose("page","Changes");frame("ai-review-changes")
	ui:choose("page","Checks");frame("ai-review-checks")
	ui:choose("page","Explain");frame("ai-review-explanation");assert(main.popups[1].controls.details.list[1][1]:find("Measured",1,true))
	ui:click("close");ui:click("candidates");frame("ai-candidates");ui:click("review")
	ui:click("apply");assert(main.modes.BUILD~=original,"Apply did not open the calculated candidate")
	ui:frame();ui:click("nav_ai");frame("ai-applied");ui:click("restore")
	assert(main.modes.BUILD==original,"Undo did not restore the original scratch build")
	ui:click("nav_atlas");frame("atlas-new-default");assert(build.planningWorkspace.controls.canvas.tree.version=="3.30.0-preview","New Atlas plan did not default to 3.30")
	assert(build.planningWorkspace.controls.version:GetSelValueByKey("label")=="3.30.0","Released Atlas version was not displayed")
	ui:click("tools");ui:text("search","Shaped Regions");ui:click("choose")
	ui:text("map","Beach Map");ui:text("count","2");ui:click("upsert");frame("atlas-shaped-regions")
	ui:choose("region","Blight");ui:text("count","3");ui:click("upsert");ui:text("map","Strand Map");ui:text("count","5");ui:click("upsert")
	ui:click("overview");ui:text("search","Beach Map");frame("atlas-shaped-map-overview")
	do local lines={};for _,row in ipairs(main.popups[1].controls.details.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;local detail=table.concat(lines," ");assert(detail:find("Abyss: 2",1,true) and detail:find("Blight: 3",1,true),"Overlapping region counts were not shown") end
	ui:click("choose");assert(main.popups[1].controls.objective1 and main.popups[1].controls.objective2,"Overlapping region objectives were not offered");frame("atlas-shaped-region-run");ui:click("objective1");ui:click("apply");ui:click("keep")

	ui:choose("version","3.28.0j","val");ui:click("confirm");assert(build.planningWorkspace.controls.canvas.tree.version=="3.28.0j","Mirage Atlas did not load");frame("atlas-mirage-tree")
	ui:choose("version","3.28.0j-ruthless","val");ui:click("confirm");assert(build.planningWorkspace.controls.canvas.tree.mode=="ruthless","Ruthless Mirage Atlas did not load");frame("atlas-mirage-ruthless-tree")
	ui:choose("version","3.29.3-ruthless","val");ui:click("confirm")
	assert(build.planningWorkspace.controls.canvas.tree.nodes[27].stats[1]:find("5%% increased Merging Radius"),"Historical Ruthless Atlas displayed a Standard modifier")
	frame("atlas-historic-ruthless-tree")
	ui:choose("version","3.30.0-preview-ruthless","val");ui:click("confirm")
	assert(build.planningWorkspace.controls.canvas.tree.mode=="ruthless","Ruthless Atlas did not load")
	assert(build.planningWorkspace.controls.canvas.tree.nodes[57123].stats[1]:find("3%% chance"),"Ruthless Atlas displayed a Standard modifier")
	frame("atlas-ruthless-tree");ui:choose("page","Notes & sharing");assert(build.planningWorkspace.controls.url:IsEnabled(),"Ruthless official links are unavailable")
	ui:click("copy");assert(json.decode(ui.clipboard).atlasPlan.version=="3.30.0-preview-ruthless","Ruthless plan export lost its mode")
	frame("atlas-ruthless-sharing");ui:choose("page","Tree")
	ui:choose("version","3.29.3","val");ui:click("confirm");frame("atlas-start");assert(not build.controls.statBox:IsShown(),"Build sidebar should be hidden while planning")
	ui:click("tools");ui:text("search","Thread restrictions");ui:click("choose");ui:text("level","73");ui:text("threads","2");frame("atlas-thread-restrictions")
	do local lines={};for _,row in ipairs(main.popups[1].controls.results.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;local text=table.concat(lines," ");assert(text:find("Conditions met",1,true) and text:find("Restricted",1,true),"Thread thresholds were not displayed") end
	ui:click("close")
	ui:click("tools");ui:text("search","Map modifier explorer");ui:click("choose");frame("map-modifier-explorer")
	do
		ui.clipboard="Item Class: Maps\nRarity: Rare\nVortex Artifice\nMap (Tier 5)\n--------\nQuality (Pack Size): +20% (augmented)\n--------\nItem Level: 68\n--------\nMonster Level: 72\n--------\nArea is Influenced by the Originator's Memories (implicit)\nPlayers are Delirious (enchant)\n--------\nMonsters have 45% increased Area of Effect\nMonsters deal 55% extra Physical Damage as Fire\n--------\nTravel to this Map by using it in a personal Map Device. Maps can only be used once."
		ui:click("pasteMap");frame("map-clipboard-review");ui:click("close")
		assert(main.popups[1].controls.tier:GetSelValueByKey("val")==16 and not main.popups[1].controls.remove:IsEnabled(),"Cancelling map review changed the draft")
		ui:click("pasteMap");ui:click("keep")
		assert(main.popups[1].controls.tier:GetSelValueByKey("val")==5 and main.popups[1].controls.remove:IsEnabled(),"Copied map was not applied")
		local lines={};for _,row in ipairs(main.popups[1].controls.affixes.list) do lines[#lines+1]=StripEscapes(row[1] or "") end
		assert(table.concat(lines," "):find("55%% extra Physical Damage"),"Verified copied map roll was not displayed")
		assert(table.concat(lines," "):find("Quality %(Pack Size%): %+20%%"),"Copied map quality was not shown")
		assert(table.concat(lines," "):find("Observed effects are not modeled",1,true) and table.concat(lines," "):find("Players are Delirious",1,true),"Observed map effects were not shown")
		frame("map-clipboard-imported");ui:click("quality");frame("map-quality-editor");ui:click("keep")
		local savedCopy=ui.clipboard;ui.clipboard="Item Class: Maps\nRarity: Rare\nMap (Tier 5)\n--------\nItem Level: 68\n--------\nUnidentified\n--------\nTravel to this Map by using it in a personal Map Device. Maps can only be used once."
		ui:click("pasteMap");frame("map-unidentified-review");ui:click("keep")
		do local c=main.popups[1].controls;assert(c.status.label:find("unknown",1,true) and not c.currency:IsEnabled() and not c.estimate:IsEnabled(),"Unidentified copied maps must keep modifiers unknown") end;frame("map-unidentified-imported")
		ui:text("draftName","Unknown map");ui:click("keep");ui:click("close");ui:click("tools");ui:text("search","Saved map drafts");ui:click("choose")
		do local details={};for _,row in ipairs(main.popups[1].controls.details.list) do details[#details+1]=StripEscapes(row[1] or "") end;assert(table.concat(details," "):find("modifiers and totals unknown",1,true),"Saved unidentified map should not claim zero modifiers") end;frame("saved-unidentified-map")
		ui:click("secondary");ui:click("close");ui:click("tools");ui:text("search","Map modifier explorer");ui:click("choose")
		ui.clipboard=savedCopy;ui:click("pasteMap");ui:click("keep")
		local ordinaryCopy=ui.clipboard;ui.clipboard=ordinaryCopy.."\n--------\nMirrored";ui:click("pasteMap");ui:click("keep")
		do local c=main.popups[1].controls;assert(not c.currency:IsEnabled() and not c.estimate:IsEnabled(),"Mirrored copied maps must block currency and estimates") end;frame("map-mirrored-imported")
		ui.clipboard=ordinaryCopy;ui:click("pasteMap");ui:click("keep");assert(main.popups[1].controls.currency:IsEnabled(),"Pasting an ordinary map should clear the mirrored marker")
		ui.clipboard=ui.clipboard:gsub("Monsters have 45%% increased Area of Effect","Players in Area are 35%% Delirious\nDelirium Reward Type: Currency\nMonsters have 45%% increased Area of Effect")
		ui:click("pasteMap");ui:click("keep")
		local c=main.popups[1].controls;assert(not c.currency:IsEnabled() and not c.estimate:IsEnabled(),"Unsupported explicit modifiers should block map rerolls")
		frame("map-delirium-imported");ui:choose("tier",16,"val")
	end
	ui:choose("tier",17,"val");ui:text("search","MapUberModCurses")
	do local c=main.popups[1].controls;assert(c.currency:IsEnabled() and c.estimate:IsEnabled(),"Nightmare Chaos estimates should be available");assert(c.list.list[1].entry,"Nightmare modifier was not offered");c.list.onClick({line=c.list.list[1]}) end
	ui:click("add");frame("map-nightmare-inspection");ui:click("currency");ui:text("search","Chaos Orb");ui:click("choose");frame("map-nightmare-rolled")
	do local c=main.popups[1].controls;local row;for _,entry in ipairs(c.affixes.list) do if entry.modifierId then row=entry;break end end
		assert(row,"Expected a selectable map modifier");c.affixes.onClick({line=row});assert(c.remove.label=="Remove selected");frame("map-modifier-selected");ui:click("remove") end
	ui:choose("tier",16,"val");ui:text("search","")
	do
		local initial=main.popups[1].controls;initial.list.onClick({line=initial.list.list[1]});ui:click("add")
		ui:choose("rarity","corrupted_rare","val");assert(main.popups[1].controls.remove:IsEnabled(),"Marking a map corrupted cleared its modifiers");ui:click("remove")
		for _=1,9 do local c=main.popups[1].controls;assert(c.list.list[1].entry,"Expected a compatible map modifier");c.list.onClick({line=c.list.list[1]});ui:click("add") end
		local c=main.popups[1].controls;assert(not c.currency:IsEnabled() and not c.estimate:IsEnabled(),"Corrupted maps should not be rerolled");frame("map-corrupted-nine-modifiers")
		ui:click("implicit");ui:choose("choice","MapCorruptionItemRarity","val");ui:text("value","15");frame("map-corruption-implicit-editor");ui:click("keep")
		local text={};for _,row in ipairs(main.popups[1].controls.affixes.list) do text[#text+1]=StripEscapes(row[1] or "") end
		assert(table.concat(text," "):find("+15%% Item Rarity"),"Recorded implicit not shown on the map")
		assert(table.concat(text," "):find("Estimated bonuses",1,true),"Combined implicit estimate was not shown");frame("map-corruption-implicit-estimate")
	end
	ui:choose("rarity","magic","val");ui:text("search","")
	do local c=main.popups[1].controls;assert(c.list.list[1].entry,"Magic map modifiers should be offered");c.list.onClick({line=c.list.list[1]});ui:click("add") end
	ui:choose("rarity","corrupted_magic","val");assert(main.popups[1].controls.remove:IsEnabled() and not main.popups[1].controls.currency:IsEnabled(),"Corrupted magic should keep modifiers and block currency");frame("map-corrupted-magic")
	ui:choose("rarity","magic","val");ui:text("search","MapContainsMirageWorlds");assert(main.popups[1].controls.status.label:find("0 candidates",1,true),"Rare-only suffix appeared on a magic map")
	ui:choose("rarity","rare","val");assert(main.popups[1].controls.status.label:find("1 candidates",1,true),"Rare map did not offer its encounter suffix")
	do local c=main.popups[1].controls;c.list.onClick({line=c.list.list[1]});ui:click("add");ui:text("level","1")
		assert(c.remove:IsEnabled() and not c.currency:IsEnabled() and c.status.label:find("requires item level 68",1,true),"Item level edit discarded or failed to flag the modifier");frame("map-level-conflict");ui:text("level","83");ui:click("remove") end
	ui:choose("tier",5,"val");ui:text("level","68");assert(main.popups[1].controls.level.buf=="68","Map item level did not accept numeric input");ui:text("search","Giants")
	do local mapList=main.popups[1].controls.list;local lx,ly=mapList:GetPos();ui:clickAt(lx+12,ly+10) end
	assert(main.popups[1].controls.add:IsEnabled(),"Map modifier selection did not enable Add")
	ui:click("add");assert(main.popups[1].controls.remove:IsEnabled(),"Map modifier was not staged");frame("map-modifier-staged")
	ui:click("estimate");frame("map-reroll-estimate");ui:click("addAlternative");ui:text("search","MapMonsterFireDamageMapWorlds");frame("map-reroll-alternative");ui:click("choose")
	ui:click("addAvoid");ui:text("search","MapMonsterColdDamageMapWorlds");frame("map-reroll-avoid");ui:click("choose")
	ui:click("price");frame("map-orb-price");ui:text("amount","0.5");ui:text("currency","chaos");ui:click("keep")
	ui:text("trials","1");ui:text("attempts","1");assert(main.popups[1].controls.trials.buf=="1" and main.popups[1].controls.attempts.buf=="1","Map estimate fields did not accept numeric input");ui:click("run")
	do local tasks=require("Modules.CraftingTasks");for _=1,10000 do if not tasks.job then break end;tasks.tick(build) end;assert(not tasks.job,"Map reroll estimate did not finish") end
	assert((main.popups[1].controls.report.list[1][1] or ""):find("succeeded",1,true),"Map reroll estimate did not report results");frame("map-reroll-result");ui:click("keepSettings");ui:click("close")
	ui:text("draftName","Targets");ui:click("keep");ui:click("close");ui:click("tools");ui:text("search","Saved map drafts");ui:click("choose");ui:click("choose");ui:click("estimate")
	do local c=main.popups[1].controls;local t="";for _,row in ipairs(c.wanted.list) do t=t..StripEscapes(row[1] or "") end;local a="";for _,row in ipairs(c.avoid.list) do a=a..StripEscapes(row[1] or "") end;assert(t:find("Burning",1,true) and a:find("Freezing",1,true) and c.trials.buf=="1","Map estimate settings did not reopen") end
	frame("map-estimate-restored");ui:click("price");assert(main.popups[1].controls.amount.buf=="0.5","Map orb price did not reopen");ui:click("close");ui:click("removeAvoid");frame("map-remove-avoided");ui:click("close");ui:click("removeAlternative");frame("map-remove-option");ui:click("close");ui:click("close")
	ui:click("remove");ui:choose("rarity","normal","val");ui:click("currency");ui:text("search","Chaos Orb")
	do local c=main.popups[1].controls;local detail={};for _,row in ipairs(c.details.list) do detail[#detail+1]=StripEscapes(row[1] or "") end;assert(not c.choose:IsEnabled() and table.concat(detail," "):find("Requires a rare map",1,true),"Incompatible currency did not explain why it is unavailable") end
	frame("map-currency-unavailable");ui:text("search","Orb of Alchemy");frame("map-currency-picker");ui:click("choose")
	assert(main.popups[1].controls.rarity:GetSelValueByKey("val")=="rare","Map Alchemy did not produce a rare map");assert(main.popups[1].controls.remove:IsEnabled(),"Map Alchemy did not add modifiers");frame("map-currency-result")
	ui:text("draftName","My map draft");ui:click("keep");ui:click("close");ui:click("tools");ui:text("search","Saved map drafts");ui:click("choose");frame("saved-map-drafts");ui:click("choose")
	assert(main.popups[1].controls.draftName.buf=="My map draft" and main.popups[1].controls.remove:IsEnabled(),"Saved map draft did not reopen");frame("reopened-map-draft");ui:click("close")
	do
		local state={baseId="Metadata/Items/Maps/MapWorldsStrand",tier=5,itemLevel=68,rarity="rare",selected={}}
		local settings={wantedGroups={{"MapMonsterFireDamageMapWorlds"},{"MapMonsterColdDamageMapWorlds"}},avoid={},trials=1000,maxAttempts=20}
		local c=require("Classes.MapCraftEstimateControl").Open(build,{state=state,settings=settings,apply=function() error("unexpected map result") end})
		ui:click("run");local tasks=require("Modules.CraftingTasks");for _=1,10000 do if not tasks.job then break end;tasks.tick(build) end
		assert(not tasks.job,"Conflicting map targets did not finish");local message="";for _,row in ipairs(c.report.list) do message=message..StripEscapes(row[1] or "").." " end
		assert(message:find("Wanted groups 1 and 2 cannot coexist",1,true),"Conflicting map targets were not explained");frame("map-impossible-targets");ui:click("close")
		settings.wantedGroups={{"MapBossPossessedMapWorlds"},{"MapDangerousBoss1MapWorlds"},{"MapMonsterCannotBeStunnedMapWorlds_"},{"MapMonsterChainMapWorlds"}}
		c=require("Classes.MapCraftEstimateControl").Open(build,{state=state,settings=settings,apply=function() error("unexpected map result") end})
		ui:click("run");for _=1,10000 do if not tasks.job then break end;tasks.tick(build) end
		assert(not tasks.job,"Collectively incompatible targets did not finish");message="";for _,row in ipairs(c.report.list) do message=message..StripEscapes(row[1] or "").." " end
		assert(message:find("Wanted targets cannot all coexist",1,true),"Collectively incompatible targets were not explained");frame("map-multi-target-conflict");ui:click("close")
	end
	local workspace=build.planningWorkspace
	build.buildFlag=true;ui:frame();ui:click("nav_tools");frame("planning-tools");ui:click("choose");frame("performance-diagnostics");ui:click("copy");assert(ui.clipboard:find("ms",1,true));ui:click("refresh");ui:click("close")
	local canvas=workspace.controls.canvas
	ui:choose("mechanic","Essence");assert(next(canvas.matches),"Inline mechanic filter did not highlight its nodes");frame("atlas-mechanic-filter");ui:choose("mechanic","All mechanics")
	ui:choose("mechanic","Mercenaries");assert(canvas.matches[50374],"Mercenary notable was not highlighted")
	local blockFound=false;for _,row in ipairs(workspace.controls.results.list) do if row.val==24930 then blockFound=row.subtitle:find("Blocks natural spawns",1,true)~=nil end end
	assert(blockFound,"Encounter-blocking nodes were not identified in results");frame("atlas-mercenary-filter")
	ui:choose("mechanic","Ore Deposits");assert(canvas.matches[65008],"Ore Deposit notable was not highlighted");frame("atlas-ore-filter");ui:choose("mechanic","All mechanics")
	ui:text("budget","120");assert(workspace.controls.status.label:find("120 points",1,true),"Point budget feedback is stale");ui:text("budget","138")
	ui:text("search","Unwavering Vision");ui:click("find");frame("atlas-search")
	assert(canvas.focus==65225 and workspace.controls.allocate.label:find("+",1,true),"The selected route should preview its point cost")
	local function atlasDetails() local text="";for _,row in ipairs(workspace.controls.details.list) do text=text..tostring(row[1] or "") end;return text end
	ui:text("title","");assert(atlasDetails():find("plan name",1,true) and not workspace.controls.allocate:IsEnabled(),"A missing plan name should explain why the route is unavailable")
	ui:text("title","Atlas strategy");assert(workspace.controls.allocate:IsEnabled(),"Restoring the name should restore the route preview")
	ui:text("budget","");assert(atlasDetails():find("valid point budget",1,true) and not workspace.controls.allocate:IsEnabled(),"An invalid budget should explain why the route is unavailable")
	ui:text("budget","138");assert(workspace.controls.allocate:IsEnabled(),"Restoring the budget should restore the route preview")
	local x,y=canvas:GetPos();ui:clickAt(x+canvas.width/2,y+canvas.height/2,true)
	frame("atlas-connected");assert(workspace.controls.status.label:find("20 granted",1,true))
	do
		local atlas=require("Modules.AtlasPlanner");local tree=atlas.tree("3.29.3")
		local route=atlas.connect({id="test",title="Test",version="3.29.3",budget=138,nodes={}},{65225});local set={};for _,id in ipairs(route.nodes) do set[id]=true end
		ui:text("budget",tostring(#route.nodes-1));assert(workspace.controls.status.label:find("points before grant",1,true),"Atlas budget did not explain that the grant is unreachable");frame("atlas-unreachable-grant");ui:text("budget","138")
		for _,id in ipairs(tree.nodes[tree.start].links) do if set[id] then canvas.focus=id;break end end
		ui:click("remove");assert(main.popups[1].controls.confirm,"Branch removal did not ask for review");frame("atlas-remove-branch-confirm")
		main:ClosePopup();assert(workspace.controls.status.label:find("20 granted",1,true),"Cancelling branch removal changed the plan");canvas.focus=65225
	end
	ui:click("remove");frame("atlas-removed");ui:click("avoid");assert(atlasDetails():find("node is avoided",1,true),"An avoided target should explain why it cannot be connected");frame("atlas-avoided");ui:click("clearAvoid");ui:click("undo")
	ui:click("undo");assert(workspace.controls.avoid.label=="Avoid selected","Undo did not restore exclusions");ui:click("redo");ui:click("undo")
	ui:click("undo");ui:click("undo");assert(workspace.controls.status.label:find("0 /",1,true),workspace.controls.status.label);ui:click("allocate")
	ui:click("stats");frame("atlas-stats");ui:click("close")
	ui:click("browse");ui:choose("category","Essence");ui:text("search","Essence");frame("atlas-node-browser");ui:click("choose")
	assert(next(workspace.controls.canvas.matches),"Mechanic selection did not highlight nodes")
	local map=workspace.controls.canvas;local mx,my=map:GetPos();local oldY=map.centerY
	ui:clickAt(mx+map.width-70,my+map.height-60);assert(map.centerY~=oldY,"Minimap did not navigate");frame("atlas-minimap")
	ui:click("routes");local routeText="";for _,line in ipairs(main.popups[1].controls.details.list) do routeText=routeText..tostring(line[1] or "") end;assert(routeText:find("New allocations:",1,true) and routeText:find("[",1,true),"Route comparison omitted allocated nodes");frame("atlas-route-options");ui:click("close")
	ui:click("tools");ui:text("search","Strategy");ui:click("choose");frame("atlas-presets");ui:click("close")
	local divider=workspace.controls.splitter;local dx,dy=divider:GetPos();local priorWidth=workspace.controls.canvas.width
	ui.cursorX,ui.cursorY=dx+5,dy+50;ui:dispatch(build,{{type="KeyDown",key="LEFTBUTTON"}});ui.cursorX=ui.cursorX-24;ui:dispatch(build,{{type="KeyUp",key="LEFTBUTTON"}})
	assert(workspace.controls.canvas.width<priorWidth,"Atlas divider did not resize the inspector");frame("atlas-split")
	ui:text("title",string.rep("Long Atlas strategy ",5));frame("atlas-long-title")
	ui:choose("page","Notes & sharing");ui:text("notes","Essence and map sustain. Save this strategy.");frame("atlas-notes")
	ui:click("copy");local exported=ui.clipboard;assert(json.decode(exported).atlasPlan.notes:find("Essence",1,true))
	ui:click("import");ui:click("url");assert(ui.clipboard:find("fullscreen-atlas-skill-tree",1,true));ui:click("close")
	ui.clipboard=exported
	ui:click("nav_ai")
	local alternate=size[1]==1280 and {1024,768} or {1280,720}
	ui:resize(alternate[1],alternate[2]);frame("workspace-resized");ui:click("nav_atlas")
	assert(workspace.controls.notes.buf:find("Essence",1,true),"Resizing on another page lost the Atlas draft")
	frame("atlas-resized");ui:resize(size[1],size[2]);ui:frame()
	local savedTitle=workspace.controls.title.buf;ui:text("title","");ui:text("budget","-1");ui:resize(alternate[1],alternate[2]);ui:frame()
	assert(workspace.controls.title.buf=="" and workspace.controls.budget.buf=="-1","Unfinished Atlas edits were lost on resize")
	ui:resize(size[1],size[2]);ui:frame();ui:text("title",savedTitle);ui:text("budget","138")
	ui:click("nav_build");ui:click("modeItems")
	local visceraDB=build.itemsTab.controls.visceraDB;build.itemsTab.controls.selectDB:SelByValue("Viscera")
	ui:frame();assert(visceraDB:IsShown(),"Viscera database did not open")
	visceraDB.controls.slot:SelByValue("Arm");visceraDB.listBuildFlag=true;ui:frame()
	assert(#visceraDB.list>0,"Viscera arm filter returned no items")
	for _,item in ipairs(visceraDB.list) do assert(item:GetPrimarySlot()=="Wickerman Upper Limb","Viscera arm filter returned another slot") end
	frame("wickerman-viscera-database");build.itemsTab.controls.selectDB:SelByValue("Uniques")
	ui:click("modeSkills");ui:click("atlas");assert(workspace.controls.notes.buf:find("Essence",1,true),"Switching tools lost the Atlas draft")
	ui:click("keep");assert(#build.savers.AtlasPlans.plans==1)
	do
		local atlas=require("Modules.AtlasPlanner");local start={id="temp-start",title="Temporary start",version="3.29.3",budget=138,nodes={}}
		local shortest=atlas.connect(start,{65225});local goal=atlas.connect(start,{65225},{17321});goal.avoided=nil;goal.id="temp-goal";goal.title="Temporary goal"
		start.budget=#shortest.nodes;goal.budget=start.budget;build.savers.AtlasPlans:Upsert(start)
		local grantPanel=require("Classes.AtlasPlannerControl").Open(build,goal);assert(grantPanel.status.label:find("Temporary grant route",1,true),"Constructed grant route was not shown")
		ui:click("stats");ui:text("search","Temporary grant route");local grantBrowser=main.popups[1].controls;local grantRows={};for _,row in ipairs(grantBrowser.details.list) do grantRows[#grantRows+1]=StripEscapes(row[1]) end
		assert(table.concat(grantRows," "):find("refund",1,true),"Grant route details did not explain refunds");frame("atlas-grant-proof")
		ui:click("choose");frame("atlas-grant-steps");ui:click("choose");assert(grantPanel.canvas.focus==atlas.report(goal).grantRoute[1].id,"Route step did not focus its Atlas node");assert(next(grantPanel.canvas.preview)==nil,"Route inspection showed a misleading connection preview")
		frame("atlas-grant-on-tree");ui:click("grantNext");assert(grantPanel.canvas.focus==atlas.report(goal).grantRoute[2].id,"Next did not advance the route")
		ui:click("grantPrevious");assert(grantPanel.canvas.focus==atlas.report(goal).grantRoute[1].id,"Previous did not return to the route step");ui:click("grantExit");assert(grantPanel.undo:IsShown(),"Exiting the route did not restore tree controls");ui:click("close")
		require("Classes.AtlasPlanningControl").Open(build,goal,function() end);ui:choose("previous","temp-start","val")
		local lines={};for _,row in ipairs(main.popups[1].controls.transition.list) do lines[#lines+1]=StripEscapes(row[1]) end
		assert(table.concat(lines," "):find("Temporary grant path",1,true),"Atlas stages did not show the temporary grant route");frame("atlas-temporary-grant-route");ui:click("close");build.savers.AtlasPlans:Remove("temp-start")
		local impossible=copyTable(shortest);impossible.id="legacy-start";impossible.title="Legacy start";impossible.budget=#shortest.nodes-1
		build.savers.AtlasPlans.plans[#build.savers.AtlasPlans.plans+1]=impossible
		local later=copyTable(impossible);later.id="legacy-later";later.title="Later stage";later.progression={stage="final",previousId=impossible.id}
		require("Classes.AtlasPlanningControl").Open(build,later,function() end)
		local warning={};for _,row in ipairs(main.popups[1].controls.transition.list) do warning[#warning+1]=StripEscapes(row[1]) end
		assert(table.concat(warning," "):find("Starting plan cannot be reached",1,true),"Impossible Atlas start was presented as a valid route")
		frame("atlas-impossible-start");ui:click("copyRoute");assert(ui.clipboard:find("Starting plan cannot be reached",1,true));ui:click("close")
		table.remove(build.savers.AtlasPlans.plans)
		local choiceNode=atlas.tree("3.30.0-preview").nodes[45404]
		local choiceStart=atlas.connect({id="choice-start",title="Choice start",version="3.30.0-preview",budget=150,nodes={}},{choiceNode.id})
		choiceStart=atlas.chooseEffect(choiceStart,choiceNode.id,choiceNode.variantEffects[1].effect);build.savers.AtlasPlans:Upsert(choiceStart)
		local choiceGoal=atlas.chooseEffect(choiceStart,choiceNode.id,choiceNode.variantEffects[2].effect);choiceGoal.id="choice-goal";choiceGoal.title="Choice goal";choiceGoal.progression={stage="final",previousId="choice-start"}
		require("Classes.AtlasPlanningControl").Open(build,choiceGoal,function() end)
		local choiceWarning={};for _,row in ipairs(main.popups[1].controls.transition.list) do choiceWarning[#choiceWarning+1]=StripEscapes(row[1]) end
		assert(table.concat(choiceWarning," "):find("additional refund",1,true),"Choice cost uncertainty was not shown")
		frame("atlas-choice-reselection");ui:click("copyRoute");assert(ui.clipboard:find("additional refund",1,true));ui:click("close");build.savers.AtlasPlans:Remove("choice-start")
	end
	local starter=copyTable(build.savers.AtlasPlans.plans[1]);starter.id="starter-atlas";starter.title="Starter maps";starter.nodes={};starter.progression={stage="starter"};build.savers.AtlasPlans:Upsert(starter)
	ui:click("progression");assert(not main.popups[1].controls.copyRoute:IsEnabled(),"Route copy should require a previous stage");ui:choose("stage","final","val");ui:choose("previous","starter-atlas","val");frame("atlas-progression");ui:click("copyRoute");assert(ui.clipboard:find("Starter maps",1,true) and ui.clipboard:find("Allocate:",1,true) and ui.clipboard:find("base points",1,true),"Copied Atlas route omitted steps or budget assumptions")
	ui:click("strategyTab");ui:text("maps","T16 maps; avoid reflect");ui:text("scarabs","Record map supplies here");ui:text("requirements","Complete map unlocks");ui:text("avoid","Reflect");ui:text("amount","many");ui:text("source","Manual test quote");ui:click("keep")
	assert(main.popups[1].title=="Atlas strategy" and main.popups[1].controls[1].label=="Enter a numeric setup cost","Invalid Atlas cost was not explained")
	frame("atlas-strategy-invalid-cost");ui:click("close");assert(main.popups[1].controls.amount.buf=="many","Invalid Atlas input was lost")
	ui:text("amount","25");frame("atlas-strategy-requirements");ui:click("keep");ui:click("keep")
	assert(build.savers.AtlasPlans.plans[1].strategy.setupCost.amount==25 and build.savers.AtlasPlans.plans[1].progression.previousId=="starter-atlas","Atlas strategy was not kept")
	ui:choose("page","Tree");ui:click("tools");ui:text("search","Compare");ui:click("choose");frame("atlas-compare");ui:text("search","Starter maps");ui:click("choose");frame("atlas-comparison-overlay");assert(workspace.controls.canvas.comparison,"Saved-plan comparison did not reach the canvas")
	ui:click("tools");ui:text("search","history");ui:click("choose");frame("atlas-history");ui:click("close")
	ui:click("library");frame("atlas-library")
	ui:choose("plans","starter-atlas","val");ui:click("delete")
	assert(main.popups[1].title=="Saved Atlas plans" and main.popups[1].controls[1].label:find("follows this plan",1,true),"Atlas dependency was not explained")
	assert(#build.savers.AtlasPlans.plans==2,"A referenced Atlas stage was deleted");frame("atlas-delete-dependency");ui:click("close")
	ui:choose("plans",build.savers.AtlasPlans.plans[1].id,"val");ui:click("open")
	ui:choose("page","Tree");ui:click("fit");frame("atlas-fit")
	canvas=workspace.controls.canvas;x,y=canvas:GetPos();ui.cursorX,ui.cursorY=x+canvas.width/2,y+canvas.height/2
	local scale=canvas.scale;ui:key("WHEELUP");assert(canvas.scale>scale,"Wheel did not zoom the Atlas canvas")
	local oldCenter=canvas.centerX;ui:dragAt(x+canvas.width/2,y+canvas.height/2,45,20)
	assert(canvas.centerX~=oldCenter,"Dragging did not pan the Atlas canvas");frame("atlas-panned")
	ui:choose("version","3.27.0","val");frame("atlas-version-confirm");ui:click("confirm")
	assert(workspace.controls.canvas.tree.version=="3.27.0")
	frame("atlas-legacy")
	ui:click("nav_crafting");frame("crafting-empty-workspace")
	ui:click("startProject");frame("crafting-project-editor")
	ui:text("title","Life helmet");ui:text("starting","Rarity: NORMAL\nIron Hat\nItem Level: 86\nSockets: R-G-B")
	ui:click("next");frame("crafting-wizard-target");ui:text("goals","Life\nResistances");ui:click("next");frame("crafting-wizard-plan");ui:text("steps","Roll life\nCheck resistances");ui:click("next");frame("crafting-wizard-review");ui:click("save")
	assert(#build.savers.CraftingProjects.projects==1 and #build.savers.CraftingProjects.projects[1].goals==2,"Project editor lost pasted line breaks")
	frame("crafting-workspace")
	ui:click("native");frame("crafting-workspace-item")
	assert(build.planningWorkspace.controls.keepItem.label=="Keep item snapshot" and build.planningWorkspace.controls.keepItem.tooltipText:find("Item inventory",1,true),"Snapshot action is not clearly labelled")
	assert(build.planningWorkspace.controls.keepWorking.tooltipText:find("history and settings",1,true),"Working craft action does not explain what it keeps")
	assert(not main.popups[1],"Workbench should be embedded in the planning workspace")
	ui:click("currency_alchemy");ui:click("item");frame("workspace-crafted")
	assert(require("Modules.PlanningUI").saveStatus(build):find("Working draft",1,true),"Working item was incorrectly presented as saved")
	assert(not workspace.controls.apply:IsEnabled() and workspace.controls.currency_chaos:IsEnabled(),"Currency eligibility did not follow the crafted rarity")
	ui:click("history");frame("crafting-history");ui:choose("state",1,"val");frame("crafting-history-before");ui:click("restore")
	assert(not workspace.controls.undo:IsEnabled(),"History restore did not undo subsequent actions");ui:click("currency_alchemy");ui:click("item")
	ui:click("settings");assert(not main.popups[1],"Currency search should stay beside the item");assert(workspace.body.selControl==workspace.controls.paletteSearch,"Currency search should take keyboard focus")
	ui:text("paletteSearch","Divine");ui:click("paletteFavorite");frame("crafting-palette");ui:choose("paletteCategory","Favorites");frame("crafting-favorites")
	ui:resize(alternate[1],alternate[2]);ui:frame();assert(workspace.controls.paletteSearch:IsShown() and workspace.controls.paletteSearch.buf=="Divine","Resizing lost inline currency search");assert(not workspace.controls.item:IsEnabled(),"Browsing currencies should not apply one by clicking the item")
	ui:resize(size[1],size[2]);ui:frame();ui:click("paletteUse")
	assert(workspace.controls.selectedAction:GetProperty("label"):find("Divine",1,true))
	local mods=workspace.controls.itemMods;local ax,ay=mods:GetPos();local top=2-mods.controls.scrollBar.offset;local targetY
	for _,row in ipairs(mods.list) do if row.affixId then targetY=ay+top+row.height/2;break end;top=top+row.height end
	assert(targetY,"Crafted item has no selectable modifiers");ui:clickAt(ax+mods.width/2,targetY)
	assert(not main.popups[1] and workspace.controls.affixFacts:IsShown(),"Modifier inspection should stay beside the item");frame("crafting-inline-inspector")
	ui:resize(alternate[1],alternate[2]);ui:frame();assert(workspace.controls.affixFacts:IsShown(),"Resizing lost the inspected modifier");ui:resize(size[1],size[2]);ui:frame()
	ui:click("affixTarget");assert(workspace.controls.targetSummary:IsShown(),"Inline inspector did not add the target");frame("crafting-inline-target");ui:choose("page","Emulate item")
	local split=workspace.controls.splitter;local sx,sy=split:GetPos();local oldItemX=select(1,workspace.controls.item:GetPos())
	ui.cursorX,ui.cursorY=sx+5,sy+80;ui:dispatch(build,{{type="KeyDown",key="LEFTBUTTON"}});ui.cursorX=ui.cursorX+32;ui:dispatch(build,{{type="KeyUp",key="LEFTBUTTON"}})
	assert(select(1,workspace.controls.item:GetPos())>oldItemX,"Crafting divider did not resize panels");frame("crafting-split")
	ui:click("nav_atlas");ui:click("nav_crafting")
	assert(workspace.controls.undo:IsEnabled(),"Switching tools lost crafting history")
	ui:resize(alternate[1],alternate[2]);frame("workbench-resized")
	assert(workspace.controls.undo:IsEnabled() and #workspace.controls.itemMods.list>=4,"Resizing lost the crafted item")
	ui:resize(size[1],size[2]);ui:frame();ui:click("close");ui:click("native")
	assert(workspace.controls.undo:IsEnabled(),"Returning to a project lost the working item")
	ui:click("settings");ui:choose("paletteCategory","Favorites");frame("crafting-restored-favorites");assert(workspace.controls.paletteUse:IsEnabled(),"Favorites were lost when resizing or reopening the project");ui:key("ESCAPE");assert(not workspace.controls.paletteSearch:IsShown(),"Escape did not return to the currency tray")
	ui:click("undo");ui:click("close")
	ui:choose("libraryPage","Plan");frame("crafting-plan");ui:click("done");ui:click("undoStep")
	ui:choose("libraryPage","Sharing");frame("crafting-sharing");ui:click("copy")
	assert(json.decode(ui.clipboard).title=="Life helmet")
	ui:choose("libraryPage","Item")
	bridge.disable(build);io.open,os.remove=originalOpen,originalRemove
	ui:bind(nil)
	local legacyLight="Rarity: MAGIC\nIron Hat\nItem Level: 86\n18% increased Global Accuracy Rating\n15% increased Light Radius"
	require("Classes.CraftingSimulatorControl").Open(build,{id="light-radius-ui",title="Legacy light radius",slot="Helmet",startingItem=legacyLight,goals={},steps={}})
	frame("crafting-light-radius-legacy");ui:click("currency_divine");ui:click("item")
	assert(main.popups[1].controls.intro.label:find("Applied Divine",1,true),"Divine Orb was not applied to the legacy item")
	frame("crafting-light-radius-current");ui:click("close")
	local assembled="Rarity: NORMAL\nAssembled Eye Jewel\nItem Level: 86"
	local assembledControls=require("Classes.CraftingSimulatorControl").Open(build,{id="abyss-330-ui",title="Assembled Eye craft",slot="Jewel",startingItem=assembled,goals={},steps={},nativeRecipe={steps={},targets={},requirements={minAffixes=1}}})
	frame("crafting-assembled-eye-base");ui:click("currency_transmute");ui:click("item")
	assert(main.popups[1].controls.intro.label:find("Applied",1,true),"Assembled Eye craft did not apply")
	assert(not main.popups[1].controls.itemMods.list[1][1]:find("No explicit modifiers",1,true),"Assembled Eye craft has no modifiers")
	ui:click("tab_simulate")
	assert(assembledControls.simulate:IsEnabled(),"An already satisfied goal must still permit simulation")
	assert(assembledControls.simulate.tooltipText():find("Requires a normal item",1,true) and assembledControls.simulate.tooltipText():find("already meets the goal",1,true),"Simulation did not explain the unavailable action and zero-action result")
	ui:click("simulate");local jobs=require("Modules.CraftingTasks");for i=1,1000 do if not jobs.job then break end;jobs.tick(build) end
	local result=build.craftingAnalyses["abyss-330-ui"].results.simulation.result
	assert(not jobs.job and result.successChance==100 and result.meanActions==0,"An already satisfied goal should succeed without an action")
	ui:click("tab_craft")
	frame("crafting-assembled-eye-crafted");ui:click("close")
	local oldAbyss="Rarity: MAGIC\nSearching Eye Jewel of Escape\nCrafted: true\nPrefix: None\nSuffix: {range:0.5}AbyssAvoidElementalAilmentsWhileElusiveJewel1\nItem Level: 86\nImplicits: 0\n{suffix}15% chance to Avoid Elemental Ailments while you have Elusive"
	require("Classes.CraftingSimulatorControl").Open(build,{id="abyss-legacy-ui",title="Legacy Abyss jewel",slot="Jewel",startingItem=oldAbyss,goals={},steps={}})
	frame("crafting-abyss-legacy");ui:click("close")
	local jewel="Rarity: NORMAL\nCobalt Jewel\nItem Level: 86"
	do
		local jewelSlot;local jewelItem=new("Item"):Item(jewel)
		for name in pairs(build.itemsTab.slots) do if name:match("^Jewel ") and build.itemsTab:IsItemValidForSlot(jewelItem,name) then jewelSlot=name;break end end
		assert(jewelSlot,"A jewel slot is required for checkpoint testing")
		local jewelControls=require("Classes.CraftingSimulatorControl").Open(build,{id="unique-jewel-ui",title="Jewel corruption",slot=jewelSlot,startingItem=jewel,goals={},steps={}})
		local uniqueSeed;for seed=1,100 do local derived=require("Modules.CalcEncounter").seed(seed,1,31);if (derived*16807%2147483647)/2147483647>=0.75 then uniqueSeed=seed;break end end
		assert(uniqueSeed,"Could not choose a deterministic unique outcome");jewelControls.seed:SetText(tostring(uniqueSeed),true)
		ui:click("currency_vaal");ui:click("item");assert(not jewelControls.apply:IsEnabled(),"Transformed unique should not accept ordinary crafting");frame("crafting-corrupted-unique-jewel")
		ui:click("keepWorking");local project;for _,entry in ipairs(build.savers.CraftingProjects.projects) do if entry.id=="unique-jewel-ui" then project=entry end end
		if not (project and project.run and project.run.state.uniqueTitle) then frame("unique-keep-error");error("Unique jewel checkpoint was not kept") end;ui:click("close")
		local reopened=require("Classes.CraftingSimulatorControl").Open(build,project);assert(not reopened.apply:IsEnabled(),"Reopened unique accepted ordinary crafting");frame("crafting-corrupted-unique-reopened")
		ui:click("tab_targets");ui:click("targetConditions");ui:click("chooseUnique");ui:text("search","Powerlessness");frame("crafting-unique-target-picker");ui:click("choose")
		assert(main.popups[1].controls.uniqueName.buf=="Powerlessness","Unique target selection was lost");frame("crafting-unique-target-selected");ui:click("keep");ui:click("close")
	end
	do
		local recipe={steps={{method="vaal"}},targets={},requirements={corrupted=true}}
		local distControls=require("Classes.CraftingSimulatorControl").Open(build,{id="unique-dist-ui",title="Jewel outcomes",slot="Jewel",startingItem=jewel,goals={},steps={},nativeRecipe=recipe})
		distControls.seed:SetText("123",true);ui:click("tab_simulate");ui:text("trials","32");ui:text("budget","1");ui:click("runRecipe")
		local jobs=require("Modules.CraftingTasks");for _=1,10000 do if not jobs.job then break end;jobs.tick(build) end
		local result=build.craftingAnalyses["unique-dist-ui"].results.simulation.result;assert(not jobs.job and #result.uniqueDistribution>0,"Unique outcome distribution is missing")
		ui:click("distribution");local list=main.popups[1].controls.results
		assert((list.list[1][1] or ""):find("Trials ending with unique jewels",1,true),"Unique outcome distribution was not displayed first")
		frame("crafting-unique-distribution");ui:click("close");ui:click("close")
	end
	require("Classes.CraftingSimulatorControl").Open(build,{id="unveiled-jewel-ui",title="Unveiled jewel",slot="Jewel",startingItem=jewel,goals={},steps={}})
	ui:click("tab_settings");ui:click("manual");ui:choose("modifier","JunMasterVeiledJewelElusiveEffect","val");ui:text("roll","50");ui:choose("rarity","MAGIC");ui:click("properties");frame("crafting-unveiled-jewel-editor")
	ui:click("offers");frame("crafting-jewel-unveil-choices");ui:choose("choice1","JunMasterVeiledJewelElusiveEffect","val");ui:choose("fractured","Fractured veil");ui:click("use");ui:click("offers");ui:click("clear")
	ui:click("add");frame("crafting-unveiled-jewel-selected");ui:click("keep");ui:click("tab_craft");frame("crafting-unveiled-jewel-item");ui:click("close")
	local corruptedJewel="Rarity: MAGIC\nCobalt Jewel\nItem Level: 86\nImplicits: 1\nCorrupted Blood cannot be inflicted on you\nCorrupted"
	local corruptedControls=require("Classes.CraftingSimulatorControl").Open(build,{id="corrupted-jewel-ui",title="Corrupted jewel",slot="Jewel",startingItem=corruptedJewel,goals={},steps={}})
	local implicitRows={};for _,row in ipairs(corruptedControls.itemMods.list) do implicitRows[#implicitRows+1]=StripEscapes(row[1] or "") end
	assert(table.concat(implicitRows," "):gsub("%s+"," "):find("Corrupted Blood cannot be inflicted",1,true),"Jewel corruption implicit did not appear")
	frame("crafting-corrupted-jewel");ui:click("close")
	local jewelModel=require("Modules.CraftingSimulator").model(jewel);local jewelStart=copyTable(jewelModel.initial);jewelStart.rarity="MAGIC"
	local jewelPending=require("Modules.CraftingSimulator").recordJewelOffers(jewelModel,jewelStart,{"JunMasterVeiledJewelElusiveEffect","JunMasterVeiledJewelLifeOnBlock"},true)
	local resumedJewel={id="jewel-resume-ui",title="Saved jewel choices",slot="Jewel",startingItem=jewel,goals={},steps={},run=require("Modules.CraftingInventory").run(jewelPending)}
	local jewelControls=require("Classes.CraftingSimulatorControl").Open(build,resumedJewel)
	assert(jewelControls.method:GetSelValueByKey("val")=="unveil","Resumed unveil did not select the choice action")
	local fracturedVisible=false;for _,row in ipairs(jewelControls.itemMods.list) do if tostring(row[1]):find("Fractured veiled modifier",1,true) then fracturedVisible=true end end
	assert(fracturedVisible,"Fractured veil is not shown on the working item");frame("crafting-jewel-unveil-resumed");ui:click("close")
	local protectedJewel=sim.perform(jewel,{method="unveil",modId="JunMasterVeiledJewelElusiveEffect"},7,jewelPending).state
	local protectedProject={id="protected-jewel-ui",title="Protected jewel",slot="Jewel",startingItem=jewel,goals={},steps={},run=require("Modules.CraftingInventory").run(protectedJewel)}
	local protectedControls=require("Classes.CraftingSimulatorControl").Open(build,protectedProject)
	assert(not protectedControls.currency_annul:IsEnabled(),"Annulment should be unavailable when its only modifier is fractured")
	assert(protectedControls.currency_annul.tooltipText():find("fractures or locks",1,true),"Annulment tooltip did not explain the restriction")
	frame("crafting-protected-annul-tooltip","currency_annul");ui:click("close")
	local flaskProject={id="flask-vaal-ui",title="Flask quality",slot="Flask 1",startingItem="Rarity: NORMAL\nSmall Life Flask\nItem Level: 86\nQuality: 30",goals={},steps={}}
	local flaskControls=require("Classes.CraftingSimulatorControl").Open(build,flaskProject)
	assert(flaskControls.currency_vaal:IsEnabled(),"Vaal Orb should be available for a flask");ui:click("currency_vaal")
	local flaskHints={};for _,row in ipairs(flaskControls.actionHint.list) do flaskHints[#flaskHints+1]=StripEscapes(row[1] or "") end
	assert(table.concat(flaskHints," "):find("assumed",1,true),"Flask Vaal assumption was not shown");frame("crafting-flask-vaal-ready")
	ui:click("item");assert(flaskControls.intro.label:find("Applied Vaal",1,true),"Flask Vaal was not applied");frame("crafting-flask-vaal-applied")
	local priorProjects=copyTable(build.savers.CraftingProjects.projects);ui:click("keepItem");ui:click("inventory");frame("crafting-flask-inventory");ui:click("close");ui:click("close")
	build.savers.CraftingProjects.projects=priorProjects
	do
		local controls={};local show=require("Classes.JourneyItemControl").new(controls,"card",16,30,440,220,"TARGET")
		show(require("Modules.CraftingProjects").item(flaskProject.startingItem));main:OpenPopup(472,270,"Flask comparison",controls)
		frame("journey-flask-card");main:ClosePopup()
	end
	local enchantedProject={id="harvest-ui",title="Body armour quality enchant",slot="Body Armour",startingItem="Rarity: NORMAL\nPlate Vest\nItem Level: 86\nQuality: 20",goals={},steps={}}
	require("Classes.CraftingSimulatorControl").Open(build,enchantedProject)
	ui:click("settings");ui:text("paletteSearch","replace quality");frame("crafting-harvest-service");ui:click("paletteUse")
	ui:choose("option",require("Modules.CraftingEnchants").label("LifeBodyEnchant"),"label");ui:click("apply");frame("crafting-harvest-enchanted")
	assert(main.popups[1].controls.intro.label:find("Applied Harvest",1,true),"Harvest enchantment was not applied")
	ui:choose("page","Target conditions");ui:click("targetConditions");ui:choose("harvestEnchant","LifeBodyEnchant","val");frame("crafting-harvest-goal");ui:choose("influence","shaper","val");frame("crafting-influence-goal");ui:click("keep")
	ui:choose("page","Emulate item");ui:click("undo");frame("crafting-harvest-undone");ui:click("close")
	local swordRaw="Rarity: NORMAL\nRusted Sword\nItem Level: 86\nQuality: 20\nSockets: R-G-B"
	local swordProject={id="weapon-ui",title="Local weapon properties",slot="Weapon 1",startingItem=swordRaw,goals={},steps={}}
	require("Classes.CraftingSimulatorControl").Open(build,swordProject)
	local baseWeapon=main.popups[1].controls.item.weaponStats;assert(baseWeapon and baseWeapon.PhysicalDPS>0 and baseWeapon.CritChance>0,"Weapon properties are missing")
	frame("crafting-weapon-properties")
	ui:click("settings");ui:text("paletteSearch","replace quality");ui:click("paletteUse");ui:choose("option",require("Modules.CraftingEnchants").label("WeaponCriticalEnchant"),"label");ui:click("apply")
	local enchantedWeapon=main.popups[1].controls.item.weaponStats
	assert(enchantedWeapon.CritChance>baseWeapon.CritChance and enchantedWeapon.PhysicalDPS<baseWeapon.PhysicalDPS,"The weapon preview missed the quality enchantment tradeoff")
	frame("crafting-weapon-enchanted")
	local swordModel=sim.model(swordRaw);local swordState=sim.perform(swordRaw,{method="harvest_enchant",enchantId="WeaponCriticalEnchant"},1).state
	require("Classes.CraftingItemComparisonControl").Open({title="Before enchantment",baseItem=swordRaw,state=swordModel.initial,slot="Weapon 1"},{title="After enchantment",baseItem=swordRaw,state=swordState,slot="Weapon 1"})
	frame("crafting-weapon-comparison");ui:click("close")
	ui:click("settings");ui:text("paletteSearch","remove enchantments");assert(main.popups[1].controls.paletteUse:IsEnabled(),"Enchantment removal is unavailable on an enchanted weapon")
	frame("crafting-remove-enchant-selection");ui:click("paletteUse")
	local removeHints={};for _,row in ipairs(main.popups[1].controls.actionHint.list) do removeHints[#removeHints+1]=StripEscapes(row[1]) end
	assert(table.concat(removeHints," "):find("three Orbs of Scouring",1,true),"Enchantment removal did not explain its cost")
	frame("crafting-remove-enchant-details");ui:click("apply")
	assert(main.popups[1].controls.intro.label:find("Applied Bench: remove enchantments",1,true),"Enchantment removal did not apply")
	frame("crafting-remove-enchant-applied");ui:click("undo");ui:click("close")
	require("Classes.CraftingSimulatorControl").Open(build,{id="ward-ui",title="Ward properties",slot="Helmet",startingItem="Rarity: NORMAL\nRunic Helm\nItem Level: 86",goals={},steps={}})
	assert(main.popups[1].controls.item.defences:find("Ward:",1,true),"Ward is missing from the item card")
	frame("crafting-ward-properties");ui:click("close")
	for count=1,2 do
		local sockets=count==1 and "W" or "W-W"
		require("Classes.CraftingSimulatorControl").Open(build,{id="socket-options-ui",title="Socket bench availability",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86\nSockets: "..sockets,goals={},steps={}})
		ui:click("settings");ui:text("paletteSearch","non-white");local panel=main.popups[1]
		if count==1 then
			assert(not panel.controls.paletteUse:IsEnabled(),"A bench with no valid socket option is selectable")
			ui:key("RETURN");assert(main.popups[1]==panel and panel.controls.paletteSearch:IsShown(),"Enter bypassed an unavailable action")
			frame("crafting-socket-bench-unavailable");ui:click("paletteBack")
		else
			assert(panel.controls.paletteUse:IsEnabled(),"A valid two-socket bench is unavailable")
			ui:key("RETURN");ui:click("apply");assert(main.popups[1].controls.intro.label:find("Applied Bench:",1,true),"The valid bench did not apply")
			frame("crafting-socket-bench-applied")
		end
		ui:click("close")
	end
	do
		local menuRaw="Rarity: NORMAL\nIron Hat\nItem Level: 86"
		require("Classes.CraftingSimulatorControl").Open(build,{id="harvest-menu-ui",title="Harvest input requirements",slot="Helmet",startingItem=menuRaw,goals={},steps={}})
		ui:click("settings");ui:text("paletteSearch",sim.labels.harvest_reforge);local panel=main.popups[1]
		assert(not panel.controls.paletteUse:IsEnabled(),"Harvest reforge accepts a normal item")
		ui:key("RETURN");assert(main.popups[1]==panel and panel.controls.paletteSearch:IsShown(),"Enter bypassed the Harvest rarity requirement")
		frame("crafting-harvest-rarity-unavailable");ui:click("paletteBack");ui:click("currency_alchemy");ui:click("item")
		ui:click("settings");ui:text("paletteSearch",sim.labels.harvest_reforge);assert(main.popups[1].controls.paletteUse:IsEnabled());ui:click("paletteUse")
		assert(#main.popups[1].controls.option.list>0,"The rare item has no Harvest choices");ui:choose("option","life","label");ui:click("apply")
		assert(main.popups[1].controls.intro.label:find("Applied Harvest",1,true),"A valid Harvest reforge did not apply")
		frame("crafting-harvest-options-applied");ui:click("close")
		local damageRaw="Rarity: MAGIC\nRusted Sword\nItem Level: 86\nAdds 1 to 3 Fire Damage"
		require("Classes.CraftingSimulatorControl").Open(build,{id="harvest-damage-ui",title="Harvest damage conversion",slot="Weapon 1",startingItem=damageRaw,goals={},steps={}})
		ui:click("settings");ui:text("paletteSearch",sim.labels.harvest_damage);ui:click("paletteUse");ui:choose("option","fire to cold","label")
		local damageHint={};for _,row in ipairs(main.popups[1].controls.actionHint.list) do damageHint[#damageHint+1]=row[1] end
		assert(table.concat(damageHint," "):find("Experimental",1,true),"Damage conversion assumptions are not visible")
		assert(#damageHint<=2 and table.concat(damageHint," "):find("Rancour",1,true),"Damage conversion ingredient hint does not fit")
		frame("crafting-harvest-damage-selected");ui:click("apply")
		local damageFound;for _,row in ipairs(main.popups[1].controls.itemMods.list) do if row.affixId=="LocalAddedColdDamage1" then damageFound=true end end
		assert(damageFound,"Harvest did not convert the weapon damage");frame("crafting-harvest-damage-applied");ui:click("close")
		local damageRing="Rarity: RARE\nConversion Ring\nGold Ring\nItem Level: 86\nAdds 1 to 2 Fire Damage to Attacks\n10% increased Fire Damage"
		local damageAction={method="harvest_damage",from="fire",to="cold"}
		require("Classes.CraftingSimulatorControl").Open(build,{id="harvest-damage-odds",title="Damage conversion outcomes",slot="Ring 1",startingItem=damageRing,goals={},steps={},nativeRecipe={steps={damageAction},targets={{anyOf={"AddedColdDamage1"}}}}})
		ui:click("settings");ui:text("paletteSearch",sim.labels.harvest_damage);ui:click("paletteUse");ui:choose("option","fire to cold","label");ui:click("tab_settings");ui:click("exact")
		local damageJobs=require("Modules.CraftingTasks");for i=1,1000 do if not damageJobs.job then break end;damageJobs.tick(build) end;assert(not damageJobs.job,"Damage conversion odds did not finish")
		local damageOdds={};for _,row in ipairs(main.popups[1].controls.resultSummary.list) do damageOdds[#damageOdds+1]=row[1] end
		local damageText=table.concat(damageOdds," ");assert(damageText:find("50.000000%%") and damageText:find("uniform selection",1,true),"Modeled damage outcomes are missing")
		ui:click("tab_simulate");frame("crafting-harvest-damage-odds");ui:click("close")
		local magic=sim.perform(menuRaw,{method="transmute"},7)
		require("Classes.CraftingSimulatorControl").Open(build,{id="essence-menu-ui",title="Essence input requirements",slot="Helmet",startingItem=magic.itemText,goals={},steps={}})
		ui:click("settings");ui:text("paletteSearch",sim.labels.essence);panel=main.popups[1]
		assert(not panel.controls.paletteUse:IsEnabled(),"An Essence accepts a magic item")
		ui:key("RETURN");assert(main.popups[1]==panel and panel.controls.paletteSearch:IsShown(),"Enter bypassed the Essence rarity requirement")
		frame("crafting-essence-rarity-unavailable");ui:text("paletteSearch",sim.labels.scour);ui:click("paletteUse");ui:click("apply")
		ui:click("settings");ui:text("paletteSearch",sim.labels.essence);assert(main.popups[1].controls.paletteUse:IsEnabled());ui:click("paletteUse");ui:click("apply")
		assert(main.popups[1].controls.intro.label:find("Applied Essence",1,true),"An Essence did not apply after scouring the item")
		frame("crafting-essence-options-applied");ui:click("close")
		require("Classes.CraftingSimulatorControl").Open(build,{id="trickery-menu-ui",title="Essence of Trickery",slot="Belt",startingItem="Rarity: NORMAL\nLeather Belt\nItem Level: 86",goals={},steps={}})
		ui:click("settings");ui:text("paletteSearch",sim.labels.essence);ui:click("paletteUse")
		ui:choose("option","Essence of Trickery","label")
		local hint={};for _,row in ipairs(main.popups[1].controls.actionHint.list) do hint[#hint+1]=row[1] end
		assert(table.concat(hint," "):find("not modeled",1,true),"Trickery's calculation limitation is not visible")
		frame("crafting-trickery-selected");ui:click("apply")
		assert(main.popups[1].controls.intro.label:find("Essence of Trickery",1,true),"Trickery did not apply to the belt")
		local found;for _,row in ipairs(main.popups[1].controls.itemMods.list) do if row.affixId=="PlayerIsDeliriousEssence1" then found=true end end
		assert(found,"The belt card did not display Trickery's modifier")
		frame("crafting-trickery-applied");ui:click("close")
		require("Classes.CraftingSimulatorControl").Open(build,{id="desolation-menu-ui",title="Essence of Desolation",slot="Belt",startingItem="Rarity: NORMAL\nLeather Belt\nItem Level: 86",goals={},steps={}})
		ui:click("settings");ui:text("paletteSearch",sim.labels.essence);ui:click("paletteUse");ui:choose("option","Essence of Desolation","label")
		local capHint={};for _,row in ipairs(main.popups[1].controls.actionHint.list) do capHint[#capHint+1]=row[1] end
		assert(table.concat(capHint," "):find("level 15",1,true),"Desolation's random-modifier cap is not visible")
		frame("crafting-desolation-selected");ui:click("apply")
		local desolationFound;for _,row in ipairs(main.popups[1].controls.itemMods.list) do if row.affixId=="MagicFlaskEffectNoAdjacentFlasksEssence1" then desolationFound=true end end
		assert(desolationFound,"The belt card did not display Desolation's modifier")
		frame("crafting-desolation-applied");ui:click("close")
		require("Classes.CraftingSimulatorControl").Open(build,{id="desolation-gloves-ui",title="Desolation gloves",slot="Gloves",startingItem="Rarity: NORMAL\nIron Gauntlets\nItem Level: 86",goals={},steps={}})
		ui:click("settings");ui:text("paletteSearch",sim.labels.essence);ui:click("paletteUse");ui:choose("option","Essence of Desolation","label");ui:click("apply")
		local texts={};for _,row in ipairs(main.popups[1].controls.itemMods.list) do if row.affixId=="AttackCastSpeedPerNearbyEnemyEssence1" then texts[#texts+1]=StripEscapes(row[1]) end end
		assert(table.concat(texts," "):gsub("%s+"," "):find("within 6 metres",1,true),"The item card did not use the 3.30 modifier wording")
		frame("crafting-desolation-gloves");ui:click("close")
	end

	do
		local beltRaw="Rarity: NORMAL\nLeather Belt\nItem Level: 86"
		require("Classes.CraftingSimulatorControl").Open(build,{id="ducat-menu-ui",title="Rotmother input requirements",slot="Belt",startingItem=beltRaw,goals={},steps={}})
		ui:click("settings");ui:text("paletteSearch",sim.labels.ducat_rotmother);local panel=main.popups[1]
		assert(not panel.controls.paletteUse:IsEnabled(),"Rotmother accepts a normal belt")
		ui:key("RETURN");assert(main.popups[1]==panel and panel.controls.paletteSearch:IsShown(),"Enter bypassed Rotmother requirements")
		frame("crafting-ducat-rarity-unavailable");ui:click("paletteBack");ui:click("currency_alchemy");ui:click("item")
		ui:click("settings");ui:text("paletteSearch",sim.labels.ducat_rotmother);assert(main.popups[1].controls.paletteUse:IsEnabled());ui:click("paletteUse");ui:click("apply")
		assert(main.popups[1].controls.intro.label:find("Applied Rotmother",1,true),"Rotmother did not apply to the rare belt")
		frame("crafting-ducat-rarity-applied");ui:click("close")
	end

	do
		local raw="Rarity: NORMAL\nGold Amulet\nItem Level: 86"
		require("Classes.CraftingSimulatorControl").Open(build,{id="ukatoa-ui",title="Eldritch amulet",slot="Amulet",startingItem=raw,goals={},steps={}})
		ui:click("settings");ui:text("paletteSearch",sim.labels.ducat_ukatoa);assert(main.popups[1].controls.paletteUse:IsEnabled());ui:click("paletteUse")
		frame("crafting-ukatoa-ready");ui:click("apply")
		assert(main.popups[1].controls.intro.label:find("Applied Ukatoa",1,true),"Ukatoa did not apply to an amulet")
		frame("crafting-ukatoa-applied");ui:click("close")
	end

	do
		require("Classes.CraftingSimulatorControl").Open(build,{id="corruption-ranges-ui",title="Independent corruption rolls",slot="Weapon 1",startingItem="Rarity: NORMAL\nRusted Sword\nItem Level: 86",goals={},steps={}})
		ui:click("tab_settings");ui:text("seed","8");ui:click("tab_craft");ui:click("currency_vaal");ui:click("item")
		assert(main.popups[1].controls.intro.label:find("Applied Vaal",1,true),"A multi-range corruption did not apply")
		frame("crafting-corruption-independent-ranges");ui:click("close")
	end
	do
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86\nSockets: W W W\nCorrupted"
		require("Classes.CraftingSimulatorControl").Open(build,{id="locus-second-ui",title="Second corruption",slot="Helmet",startingItem=raw,goals={},steps={},preferredMethod="locus"})
		assert(main.popups[1].controls.apply:IsEnabled(),"A once-corrupted item cannot use the altar")
		frame("crafting-locus-second-ready");ui:click("apply")
		assert(main.popups[1].controls.intro.label:find("Applied Locus",1,true),"Second corruption did not apply")
		frame("crafting-locus-second-applied");ui:click("close")
	end

	do
		local rgbRaw="Rarity: NORMAL\nPlate Vest\nItem Level: 86\nSockets: W-W-W"
		local p={id="omen-rgb-ui",title="Guaranteed RGB colours",slot="Body Armour",startingItem=rgbRaw,goals={},steps={},nativeRecipe={steps={{method="omen_trichromatism"}},targets={},requirements={socketColours="RGB",linkedColours=true}},priceBook={currency="chaos",source="Omen quotes",quotedAt=1700000000,values={["Metadata/Items/Currency/AncestralOmenOnChromaticAddWhiteSockets"]=2,["Metadata/Items/Currency/CurrencyRerollSocketColours"]=0.25}}}
		require("Classes.CraftingSimulatorControl").Open(build,p);ui:click("settings");ui:text("paletteSearch","Trichromatism");assert(main.popups[1].controls.paletteUse:IsEnabled());frame("crafting-omen-rgb-selection")
		ui:click("paletteUse");ui:click("item");frame("crafting-omen-rgb-applied");ui:click("undo");frame("crafting-omen-rgb-undone")
		ui:click("tab_settings");ui:click("exact");local exactJobs=require("Modules.CraftingTasks");for i=1,1000 do if not exactJobs.job then break end;exactJobs.tick(build) end
		assert(not exactJobs.job);local exactLines={};for _,row in ipairs(main.popups[1].controls.resultSummary.list) do exactLines[#exactLines+1]=row[1] end;assert(table.concat(exactLines," "):find("Six socket placements",1,true));ui:click("tab_simulate");frame("crafting-omen-rgb-enumeration")
		ui:click("tab_simulate");ui:text("trials","2");ui:text("budget","1");ui:click("runRecipe")
		local jobs=require("Modules.CraftingTasks");for i=1,1000 do if not jobs.job then break end;jobs.tick(build) end
		assert(not jobs.job);local lines={};for _,row in ipairs(main.popups[1].controls.resultSummary.list) do lines[#lines+1]=row[1] end;assert(table.concat(lines," "):find("Mean spent: 2.25 chaos",1,true));frame("crafting-omen-rgb-simulation")
		ui:click("distribution");ui:click("resources");assert(#main.popups[1].controls.results.list>=2);frame("crafting-omen-rgb-ingredients");ui:click("close");ui:click("close");ui:click("close")
		require("Classes.CraftingSimulatorControl").Open(build,{id="omen-rgb-short",title="Add a third socket first",slot="Body Armour",startingItem=rgbRaw:gsub("W%-W%-W","W-W"),goals={},steps={},preferredMethod="omen_trichromatism"})
		assert(not main.popups[1].controls.apply:IsEnabled());frame("crafting-omen-rgb-unavailable");ui:click("tab_settings");assert(not main.popups[1].controls.allflame:IsEnabled());frame("crafting-omen-rgb-unsupported-profile");ui:click("close")
	end

	do
		local socketRaw="Rarity: NORMAL\nPlate Vest\nItem Level: 86\nSockets: R-G B"
		require("Classes.CraftingSimulatorControl").Open(build,{id="omen-sockets-ui",title="Maximum sockets",slot="Body Armour",startingItem=socketRaw,goals={},steps={},preferredMethod="omen_jeweller"})
		ui:click("settings");ui:text("paletteSearch","Omen of the Jeweller");assert(main.popups[1].controls.paletteUse:IsEnabled());frame("crafting-omen-sockets-selection")
		ui:click("paletteUse");ui:click("item");assert(not main.popups[1].controls.apply:IsEnabled());frame("crafting-omen-sockets-applied");ui:click("close")
	end
	do
		local socketRaw="Rarity: NORMAL\nPlate Vest\nItem Level: 86\nSockets: R-G B W-W R"
		require("Classes.CraftingSimulatorControl").Open(build,{id="omen-links-ui",title="Guaranteed socket links",slot="Body Armour",startingItem=socketRaw,goals={},steps={},nativeRecipe={steps={{method="omen_connections"}},targets={},requirements={links=6}}})
		ui:click("settings");ui:text("paletteSearch","Omen of Connections");assert(main.popups[1].controls.paletteUse:IsEnabled())
		frame("crafting-omen-link-selection");ui:click("paletteUse");ui:click("item")
		assert(main.popups[1].controls.intro.label:find("Applied Orb of Fusing",1,true),"Omen-assisted linking did not apply")
		assert(not main.popups[1].controls.apply:IsEnabled(),"A fully linked item accepts another linking Omen")
		frame("crafting-omen-linked");ui:click("undo");assert(main.popups[1].controls.apply:IsEnabled())
		frame("crafting-omen-link-undone");ui:click("tab_settings");ui:click("exact")
		local jobs=require("Modules.CraftingTasks");for i=1,100 do if not jobs.job then break end;jobs.tick(build) end
		assert(not jobs.job,"Guaranteed link calculation did not finish")
		local lines={};for _,row in ipairs(main.popups[1].controls.resultSummary.list) do lines[#lines+1]=row[1] end
		assert(table.concat(lines," "):find("deterministic socket craft",1,true),"Guaranteed linking was shown as a sampled estimate")
		ui:click("tab_simulate");frame("crafting-omen-exact-links");ui:click("close")
	end

	do
		local raw="Rarity: NORMAL\nAmethyst Ring\nItem Level: 1"
		require("Classes.CraftingSimulatorControl").Open(build,{id="catalyst-base-ui",title="Catalyst ring",slot="Ring 1",startingItem=raw,goals={},steps={}})
		ui:click("settings");ui:text("paletteSearch","Catalyst");ui:click("paletteUse");ui:choose("option","Prismatic Catalyst","label");ui:click("item")
		assert(main.popups[1].controls.intro.label:find("Applied Catalyst",1,true),"Catalyst could not be applied to the ring");ui:click("close")
	end

	do
		local raw="Rarity: NORMAL\nPlate Vest\nItem Level: 86\nSockets: R-G B W-W R"
		require("Classes.CraftingSimulatorControl").Open(build,{id="beast-links-ui",title="Bestiary links",slot="Body Armour",startingItem=raw,goals={},steps={},nativeRecipe={steps={{method="beast_max_links"}},targets={},requirements={links=6}}})
		ui:click("settings");ui:text("paletteSearch","Bestiary: maximum links");assert(main.popups[1].controls.paletteUse:IsEnabled());frame("crafting-beast-link-selection")
		ui:click("paletteUse");ui:click("item");assert(main.popups[1].controls.intro.label:find("Applied Bestiary: maximum links",1,true));frame("crafting-beast-linked");ui:click("close")
	end
	do
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 20";local sim=require("Modules.CraftingSimulator");local model=sim.model(raw);local rare=copyTable(model.initial);rare.rarity="RARE"
		for _,entry in ipairs(model.mods) do if entry.mod.type=="Prefix" and entry.mod.level<=1 then rare.affixes={{id=entry.id,range=0.5}};break end end
		local controls=require("Classes.CraftingSimulatorControl").Open(build,{id="beast-level-ui",title="Beast level",slot="Helmet",startingItem=raw,goals={},steps={},preferredMethod="beast_prefix_suffix",run=require("Modules.CraftingInventory").run(rare)})
		ui:choose("page","Craft settings");ui:choose("method","beast_prefix_suffix","val");assert(controls.configure:IsEnabled());ui:click("configure");frame("crafting-beast-level-settings")
		ui:text("beastLevel","86");ui:click("use");ui:choose("page","Target conditions")
		local high;for _,entry in ipairs(controls.target.list) do if entry.label:find("beast level 86",1,true) then assert(entry.label:find("Suffix",1,true)==1,"Wrong side offered by Bestiary target list");high=entry.val end end
		assert(high,"Beast-level targets were not offered");ui:choose("target",high,"val");ui:click("addTarget");frame("crafting-beast-level-target")
		ui:choose("page","Emulate item");assert(controls.selectedAction:GetProperty("label"):find("beast level 86",1,true),"Beast level was lost from the selected action");ui:click("item")
		assert(main.popups[1].controls.intro.label:find("Applied",1,true),"Configured Bestiary craft did not apply");frame("crafting-beast-level-applied")
		ui:choose("page","Craft settings");ui:click("configure");ui:click("clearBeast");ui:choose("page","Emulate item")
		assert(not controls.selectedAction:GetProperty("label"):find("beast level",1,true),"Item-level fallback did not clear the configured beast level");ui:click("close")
	end
	do
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 68";local sim=require("Modules.CraftingSimulator");local model=sim.model(raw);local rare=copyTable(model.initial);rare.rarity="RARE"
		for _,entry in ipairs(model.mods) do if entry.mod.type=="Prefix" and entry.mod.level<=1 then rare.affixes={{id=entry.id,range=0.5}};break end end
		local influenced=sim.action(model,rare,{method="influence_exalt",influence="shaper"},function() return 0.5 end)
		local controls=require("Classes.CraftingSimulatorControl").Open(build,{id="beast-influence-ui",title="Influenced beast craft",slot="Helmet",startingItem=raw,goals={},steps={},run=require("Modules.CraftingInventory").run(influenced)})
		ui:choose("page","Craft settings");ui:choose("method","beast_prefix_suffix","val");ui:click("configure");ui:text("beastLevel","86");ui:click("use");ui:choose("page","Target conditions")
		local allowed={};for _,entry in ipairs(sim.beastTargetSource(model,influenced,86)) do allowed[entry.id]=true end
		local shown=0;for _,entry in ipairs(controls.target.list) do if entry.label:find("beast level 86",1,true) then assert(allowed[entry.val],"Target from a different influence was displayed");shown=shown+1 end end
		assert(shown>0,"No high-level influenced targets were offered")
		local crafted=sim.perform(raw,{method="beast_prefix_suffix",beastLevel=86},104729,influenced).state
		ui:choose("page","Emulate item");ui:click("item");assert(main.popups[1].controls.intro.label:find("Applied",1,true));ui:choose("page","Target conditions")
		local after={};for _,entry in ipairs(sim.beastTargetSource(model,crafted,86)) do after[entry.id]=true end
		for _,entry in ipairs(controls.target.list) do if entry.label:find("beast level 86",1,true) then assert(after[entry.val],"Targets were not refreshed after crafting") end end
		ui:click("close")
	end
	do
		local raw="Rarity: NORMAL\nGlorious Plate\nItem Level: 86";local sim=require("Modules.CraftingSimulator");local model=sim.model(raw);local rare=copyTable(model.initial);rare.rarity="RARE"
		local target=sim.perform(raw,{method="influence_exalt",influence="shaper"},43,rare).state
		local donor=sim.perform(raw,{method="influence_exalt",influence="elder"},44,rare).itemText
		require("Classes.CraftingSimulatorControl").Open(build,{id="awakener-donor-ui",title="Influenced armour",slot="Body Armour",startingItem=raw,goals={},steps={},run=require("Modules.CraftingInventory").run(target)})
		ui:click("settings");ui:text("paletteSearch","Awakener");ui:click("paletteUse");assert(not main.popups[1].controls.apply:IsEnabled(),"Awakener allowed without a donor")
		assert(main.popups[1].controls.apply:GetProperty("tooltipText"):find("donor",1,true),"Missing donor lacks an explanation");frame("crafting-awakener-donor-required")
		ui:click("tab_settings");ui:click("configure");ui:text("donor",donor);ui:click("use");assert(main.popups[1].controls.apply:IsEnabled(),"Compatible donor did not enable Awakener");ui:click("close")
	end
	do
		local raw="Rarity: NORMAL\nPrismatic Tincture\nItem Level: 86";local sim=require("Modules.CraftingSimulator")
		local state=sim.perform(raw,{method="transmute"},1).state
		require("Classes.CraftingSimulatorControl").Open(build,{id="kishara-profile-ui",title="Tincture",slot="Tincture 1",startingItem=raw,goals={},steps={},run=require("Modules.CraftingInventory").run(state)})
		ui:click("settings");ui:text("paletteSearch","Kishara");ui:click("paletteUse")
		assert(not main.popups[1].controls.apply:IsEnabled(),"Kishara allowed without its missing profile")
		assert(main.popups[1].controls.apply:GetProperty("tooltipText"):find("observed override",1,true),"Missing profile lacks an explanation");frame("crafting-kishara-profile-required")
		ui:click("tab_settings");ui:click("allflame");ui:choose("mode","Observed override");ui:text("outcomes","1");ui:text("gainMin","0");ui:text("gainMax","0");ui:text("sulphur","0");ui:click("use")
		assert(main.popups[1].controls.apply:IsEnabled(),"Observed profile did not enable Kishara");ui:click("close")
	end
	do
		local raw="Rarity: RARE\nExample\nGold Amulet\nItem Level: 86\nImplicits: 2\n{range:0}(8-10)% increased maximum Life\n+20 to Dexterity\nSynthesised Item"
		require("Classes.CraftingSimulatorControl").Open(build,{id="gwennen-synthesis-ui",title="Synthesised reroll",slot="Amulet",startingItem=raw,goals={},steps={}})
		ui:click("tab_settings");ui:click("gwennen");ui:choose("first",1032,"val");ui:choose("second",1032,"val");ui:click("simulate");ui:click("item")
		assert(main.popups[1].controls.intro.label:find("Gwennen modeled outcome",1,true),"Synthesised reroll did not apply")
		assert(not main.popups[1].controls.apply:IsEnabled() and main.popups[1].controls.apply.tooltipText():find("below its maximum",1,true),"A maximum implicit should explain why another application is unavailable")
		frame("crafting-gwennen-max-implicit")
		assert(not main.popups[1].controls.item:IsEnabled(),"The item should not accept an unavailable currency")
		ui:click("undo");assert(main.popups[1].controls.apply:IsEnabled(),"Undo should restore implicit reroll availability");ui:click("item")
		frame("crafting-gwennen-synthesis");ui:click("keepWorking")
		local saved;for _,project in ipairs(build.savers.CraftingProjects.projects) do if project.id=="gwennen-synthesis-ui" then saved=project end end
		assert(saved and saved.run.state.synthRolls and #saved.run.state.synthRolls==2,"Synthesised implicit rolls were not kept in the build")
	end
	do
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local sim=require("Modules.CraftingSimulator")
		local state=sim.perform(raw,{method="alchemy"},12).state
		require("Classes.CraftingSimulatorControl").Open(build,{id="veiled-chaos-ui",title="Veiled reforge",slot="Helmet",startingItem=raw,goals={},steps={},run=require("Modules.CraftingInventory").run(state)})
		ui:click("settings");ui:text("paletteSearch","Veiled Chaos");ui:click("paletteUse")
		assert(main.popups[1].controls.apply:IsEnabled(),"Veiled Chaos action was not available");ui:click("item")
		assert(main.popups[1].controls.intro.label:find("Applied",1,true),"Veiled Chaos did not apply");frame("crafting-veiled-chaos")
		ui:click("keepWorking");local saved;for _,project in ipairs(build.savers.CraftingProjects.projects) do if project.id=="veiled-chaos-ui" then saved=project end end
		assert(saved and saved.run.state.veil,"Pending Veiled Chaos result was not saved")
	end
	do
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local sim=require("Modules.CraftingSimulator")
		local rare=sim.perform(raw,{method="alchemy"},12).state;local pending=sim.perform(raw,{method="veiled_chaos"},19,rare).state;pending.affixes={}
		require("Classes.CraftingSimulatorControl").Open(build,{id="veiled-bench-ui",title="Block an unveil",slot="Helmet",startingItem=raw,goals={},steps={},run=require("Modules.CraftingInventory").run(pending)})
		ui:click("settings");ui:text("paletteSearch","Crafting bench");ui:click("paletteUse")
		assert(main.popups[1].controls.apply:IsEnabled(),"Bench was not available before unveiling")
		local hint={};for _,row in ipairs(main.popups[1].controls.actionHint.list) do hint[#hint+1]=StripEscapes(row[1] or "") end
		assert(table.concat(hint," "):find("modeled assumptions",1,true),"The unveil offer assumption was not shown");ui:click("item")
		assert(main.popups[1].controls.intro.label:find("Applied Crafting bench",1,true),"The selected bench craft was not applied")
		frame("crafting-veiled-bench");ui:click("close")
	end
	do
		local raw="Rarity: RARE\nExample\nIron Hat\nItem Level: 86"
		require("Classes.CraftingSimulatorControl").Open(build,{id="gwennen-ui",title="Gwennen pair",slot="Helmet",startingItem=raw,goals={},steps={}})
		ui:click("settings");ui:text("paletteSearch","Gwennen");ui:click("paletteUse");assert(not main.popups[1].controls.apply:IsEnabled(),"An unconfigured Gwennen pair could be applied")
		ui:click("tab_settings");ui:click("gwennen");assert(not main.popups[1].controls.keep:IsEnabled());frame("crafting-gwennen-empty")
		ui:choose("first",1030,"val");local warning={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do warning[#warning+1]=StripEscapes(row[1]) end
		assert(table.concat(warning," "):find("conflict",1,true),"Disputed outcome did not show its warning");frame("crafting-gwennen-conflict")
		ui:choose("second",1000,"val");assert(not main.popups[1].controls.simulate:IsEnabled(),"Disputed offer needs an explicit scenario")
		ui:choose("rerolls",50,"val");assert(main.popups[1].controls.simulate:IsEnabled(),"Selected socket scenario did not enable modeling");frame("crafting-gwennen-socket-scenario")
		ui:choose("first",1005,"val");ui:choose("second",1022,"val");ui:text("cost","20 Grand Broken Circle Artifacts")
		assert(main.popups[1].controls.keep:IsEnabled());frame("crafting-gwennen-pair");ui:click("keep");ui:click("keepWorking")
		local saved;for _,project in ipairs(build.savers.CraftingProjects.projects) do if project.id=="gwennen-ui" then saved=project end end
		assert(saved and #saved.steps==1 and saved.steps[1].action=="Gwennen observed pair: Add a random Modifier OR Destroy. Artifact price: 20 Grand Broken Circle Artifacts.","Observed pair was not saved in the guide")
		assert(saved.steps[1].stopWhen:find("keeps the item",1,true),"Gwennen commitment was not saved in the guide")
		assert(build:SaveDB("Gwennen test"):find("20 Grand Broken Circle Artifacts",1,true),"Observed pair was not serialized in the build")
		assert(not saved.nativeRecipe,"Observed pair was incorrectly added to simulated actions")
		ui:click("gwennen");ui:choose("first",1018,"val");ui:choose("second",1019,"val")
		local notes={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do notes[#notes+1]=StripEscapes(row[1]) end
		assert(main.popups[1].controls.simulate:IsEnabled() and table.concat(notes," "):find("unverified",1,true),"Side rerolls or their assumption were not shown");frame("crafting-gwennen-side-rerolls")
		do ui:choose("first",1033,"val");ui:choose("second",1038,"val");local bestNotes={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do bestNotes[#bestNotes+1]=StripEscapes(row[1]) end
			assert(main.popups[1].controls.simulate:IsEnabled() and table.concat(bestNotes," "):find("unverified",1,true),"Best-of outcomes or their assumptions were not shown");frame("crafting-gwennen-best-of") end
		ui:choose("first",1020,"val");ui:choose("second",1021,"val");local tierNotes={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do tierNotes[#tierNotes+1]=StripEscapes(row[1]) end
		assert(main.popups[1].controls.simulate:IsEnabled() and table.concat(tierNotes," "):find("unverified",1,true),"Tier outcomes or their assumptions were not shown");frame("crafting-gwennen-tier")
		ui:choose("first",1043,"val");ui:choose("second",1044,"val");local multiTierNotes={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do multiTierNotes[#multiTierNotes+1]=StripEscapes(row[1]) end
		assert(main.popups[1].controls.simulate:IsEnabled() and table.concat(multiTierNotes," "):find("unverified",1,true),"Multi-tier outcomes or their assumptions were not shown");frame("crafting-gwennen-multi-tier")
		ui:choose("first",1031,"val");ui:choose("second",1031,"val");assert(main.popups[1].controls.simulate:IsEnabled(),"Influence outcome is not available");frame("crafting-gwennen-influence")
		do ui:choose("first",1032,"val");local notes={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do notes[#notes+1]=StripEscapes(row[1]) end;assert(main.popups[1].controls.simulate:IsEnabled() and table.concat(notes," "):find("unverified",1,true),"Implicit reroll or its assumptions were not shown");frame("crafting-gwennen-implicit") end
		ui:choose("first",1013,"val");local aspectNotes={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do aspectNotes[#aspectNotes+1]=StripEscapes(row[1]) end
		assert(main.popups[1].controls.simulate:IsEnabled() and table.concat(aspectNotes," "):find("unverified",1,true),"Pantheon outcome or its assumptions were not shown")
		ui:choose("first",1027,"val");local keepNotes={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do keepNotes[#keepNotes+1]=StripEscapes(row[1]) end
		assert(main.popups[1].controls.simulate:IsEnabled() and table.concat(keepNotes," "):find("unverified",1,true),"Keep-one reroll or its assumptions were not shown")
		ui:choose("first",1010,"val");ui:choose("second",1011,"val");local colourNotes={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do colourNotes[#colourNotes+1]=StripEscapes(row[1]) end
		assert(main.popups[1].controls.simulate:IsEnabled() and table.concat(colourNotes," "):find("unverified",1,true),"Socket-colour outcomes or their assumptions were not shown")
		ui:choose("first",1016,"val");ui:choose("second",1017,"val");local linkNotes={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do linkNotes[#linkNotes+1]=StripEscapes(row[1]) end
		assert(main.popups[1].controls.simulate:IsEnabled() and table.concat(linkNotes," "):find("unverified",1,true),"Link outcomes or their assumptions were not shown")
		ui:choose("first",1028,"val");local countNotes={};for _,row in ipairs(main.popups[1].controls.firstNote.list) do countNotes[#countNotes+1]=StripEscapes(row[1]) end
		assert(main.popups[1].controls.simulate:IsEnabled() and table.concat(countNotes," "):find("unverified",1,true),"Socket-count outcome or its assumptions were not shown")
		local readiness={};for _,row in ipairs(main.popups[1].controls.limits.list) do readiness[#readiness+1]=StripEscapes(row[1]) end
		local readinessText=table.concat(readiness," ");assert(readinessText:find("Add a socket",1,true) and readinessText:find("later step",1,true) and not readinessText:find(".lua",1,true),"Current-item restriction should be readable and preserve future-step planning");frame("crafting-gwennen-readiness")
		ui:choose("first",1041,"val");ui:choose("second",1022,"val");assert(main.popups[1].controls.simulate:IsEnabled(),"Lowest-level removal is not available");ui:choose("first",1003,"val");ui:choose("second",1012,"val");assert(main.popups[1].controls.simulate:IsEnabled(),"Fracture and corruption are not available");ui:choose("first",1009,"val");ui:choose("second",1022,"val");ui:text("cost","20 Grand Broken Circle Artifacts");assert(main.popups[1].controls.simulate:IsEnabled());ui:click("simulate")
		ui:click("tab_settings");ui:click("configure");assert(main.popups[1].controls.first:GetSelValueByKey("val")==1009 and main.popups[1].controls.second:GetSelValueByKey("val")==1022 and main.popups[1].controls.cost.buf=="20 Grand Broken Circle Artifacts","Gwennen configuration was not restored");ui:click("simulate")
		ui:click("item");assert(main.popups[1].controls.intro.label:find("Gwennen modeled outcome",1,true),"Modeled outcome was not identified");frame("crafting-gwennen-modeled");ui:click("undo");ui:click("close")
	end
	do
		local raw="Rarity: RARE\nExample\nIron Hat\nItem Level: 86"
		local recipe={steps={{method="gwennen",firstOutcome=1029,secondOutcome=1022}},targets={},requirements={minQuality=20}}
		require("Classes.CraftingSimulatorControl").Open(build,{id="gwennen-exact-ui",title="Gwennen odds",slot="Helmet",startingItem=raw,goals={},steps={},nativeRecipe=recipe})
		ui:click("tab_settings");ui:click("gwennen");ui:choose("first",1029,"val");ui:choose("second",1022,"val");ui:click("simulate");ui:click("tab_settings");ui:click("exact")
		local jobs=require("Modules.CraftingTasks");for i=1,1000 do if not jobs.job then break end;jobs.tick(build) end
		local odds=build.craftingAnalyses["gwennen-exact-ui"].results.odds.result
		assert(not jobs.job and not odds.sampled and odds.successChance==50,"Gwennen deterministic branches were not enumerated")
		local lines={};for _,row in ipairs(main.popups[1].controls.resultSummary.list) do lines[#lines+1]=StripEscapes(row[1]) end
		local summary=table.concat(lines," ");assert(summary:find("Destroy",1,true) and summary:find("Set quality to 20%",1,true),"Both Gwennen outcomes were not shown")
		assert(summary:find("Model note",1,true)<summary:find("Destroy",1,true) and summary:find("assumed fair coin",1,true)<summary:find("Destroy",1,true),"Model assumptions should precede the branch breakdown")
		ui:click("tab_simulate");frame("crafting-gwennen-exact");ui:click("close")
	end
	do
		local raw="Rarity: RARE\nExample\nPlate Vest\nItem Level: 86\nSockets: W W W W W W"
		local recipe={steps={{method="gwennen",firstOutcome=1016,secondOutcome=1017}},targets={},requirements={links=6}}
		require("Classes.CraftingSimulatorControl").Open(build,{id="gwennen-links-ui",title="Link odds",slot="Body Armour",startingItem=raw,goals={},steps={},nativeRecipe=recipe})
		ui:click("tab_settings");ui:click("gwennen");ui:choose("first",1016,"val");ui:choose("second",1017,"val");ui:click("simulate");ui:click("tab_settings");ui:click("exact")
		local jobs=require("Modules.CraftingTasks");for i=1,1000 do if not jobs.job then break end;jobs.tick(build) end
		local odds=build.craftingAnalyses["gwennen-links-ui"].results.odds.result
		assert(not jobs.job and not odds.sampled and #odds.outcomes>2,"Gwennen link layouts were not enumerated")
		local lines={};for _,row in ipairs(main.popups[1].controls.resultSummary.list) do lines[#lines+1]=StripEscapes(row[1]) end
		local summary=table.concat(lines," ");assert(summary:find("Experimental: Gwennen odds and rules are unverified.",1,true)<summary:find("All modeled outcomes",1,true),"Link assumptions should precede the outcome list")
		ui:click("tab_simulate");frame("crafting-gwennen-link-odds");ui:click("close")
	end
	do
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86\nSockets: W-W-W-W";local model=sim.model(raw)
		local unknown=sim.action(model,model.initial,{method="vaal"},function() return 0.6 end)
		require("Classes.CraftingSimulatorControl").Open(build,{id="unknown-sockets-ui",title="Corrupted helmet",slot="Helmet",startingItem=raw,goals={},steps={},run=require("Modules.CraftingInventory").run(unknown)})
		assert(not main.popups[1].controls.preview:IsEnabled(),"Unknown sockets must block build preview");assert(main.popups[1].controls.resolveSockets:IsShown(),"Unknown sockets need a direct correction action");frame("crafting-unknown-sockets")
		ui:click("resolveSockets");frame("crafting-confirm-sockets");ui:click("use");ui:click("keep")
		assert(main.popups[1].controls.preview:IsEnabled(),"Confirming a socket layout should restore preview");ui:click("close")
	end
	do
		local raw="Rarity: NORMAL\nCoral Ring\nItem Level: 86\nImplicits: 1\n+25 to maximum Life"
		require("Classes.CraftingSimulatorControl").Open(build,{id="blessed-copy-ui",title="Copied ring",slot="Ring",startingItem=raw,goals={},steps={}})
		ui:click("settings");ui:text("paletteSearch","Blessed Orb");ui:click("paletteUse");ui:click("tab_settings");ui:text("seed","1");ui:click("tab_craft");ui:click("item")
		local lines={};for _,row in ipairs(main.popups[1].controls.itemMods.list) do lines[#lines+1]=StripEscapes(row[1]) end
		assert(table.concat(lines," "):find("+20 to maximum Life",1,true),"Blessed Orb did not reroll the copied implicit");frame("crafting-blessed-copied");ui:click("close")
	end
	do
		local raw="Item Class: Rings\nRarity: Normal\nCoral Ring\n--------\nQuality (Life and Mana Modifiers): +20% (augmented)\n--------\nItem Level: 86\n--------\n{ Implicit Modifier — Life }\n+36(24-36) to maximum Life"
		require("Classes.CraftingSimulatorControl").Open(build,{id="blessed-quality-ui",title="Quality ring",slot="Ring",startingItem=raw,goals={},steps={}})
		ui:click("settings");ui:text("paletteSearch","Blessed Orb");ui:click("paletteUse");ui:click("tab_settings");ui:text("seed","1");ui:click("tab_craft");ui:click("item")
		local lines={};for _,row in ipairs(main.popups[1].controls.itemMods.list) do lines[#lines+1]=StripEscapes(row[1]) end
		assert(table.concat(lines," "):find("+24 to maximum Life",1,true),"Catalyst quality was lost after the Blessed Orb");frame("crafting-blessed-quality");ui:click("close")
	end
	do
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 1";local model=sim.model(raw)
		require("Classes.CraftingSimulatorControl").Open(build,{id="binding-legacy-ui",title="Legacy Binding",slot="Helmet",startingItem=raw,goals={},steps={}})
		ui:click("settings");ui:text("paletteSearch","Orb of Binding")
		local hints={};for _,row in ipairs(main.popups[1].controls.paletteHint.list) do hints[#hints+1]=StripEscapes(row[1]) end
		assert(table.concat(hints," "):find("No longer generated",1,true),"Binding availability was not disclosed");frame("crafting-binding-legacy")
		ui:click("paletteUse");ui:click("item");assert(main.popups[1].controls.intro.label:find("Applied Orb of Binding",1,true),"Binding failed on low-level equipment");ui:click("close")
		local saved;require("Classes.CraftingRecipeControl").Open({steps={{method="alchemy"}},targets={},requirements={maxAffixes=0}},{method="alchemy"},function(value) saved=value end,model)
		ui:click("addCurrency");ui:text("search","Orb of Binding");local details={};for _,row in ipairs(main.popups[1].controls.details.list) do details[#details+1]=StripEscapes(row[1]) end
		assert(table.concat(details," "):find("No longer generated",1,true),"Binding recipe step omitted its availability");frame("crafting-binding-recipe");ui:click("choose");ui:click("keep")
		assert(saved and saved.steps[2].method=="binding" and sim.recipeWarnings(saved)[1].code=="binding_legacy","Binding recipe step was not retained")
	end

	do
		local raw="Rarity: NORMAL\nIron Gauntlets\nItem Level: 86\nSockets: W-W-W\nImplicits: 2\n{enchant}-1 to maximum Sockets\n{enchant}20% increased Fire Damage"
		require("Classes.CraftingSimulatorControl").Open(build,{id="etched-gloves-ui",title="Etched gloves",slot="Gloves",startingItem=raw,goals={},steps={}})
		ui:click("settings");ui:text("paletteSearch",sim.labels.socket_bench);assert(main.popups[1].controls.paletteUse:IsEnabled());ui:click("paletteUse")
		local choices={};for _,option in ipairs(main.popups[1].controls.option.list) do choices[#choices+1]=option.label end
		local joined=table.concat(choices," | ");assert(joined:find("3 sockets",1,true) and not joined:find("4 sockets",1,true),"Etched socket limit was not reflected in bench options")
		frame("crafting-etched-socket-options");ui:click("tab_settings");ui:click("manual");ui:click("katakohi")
		assert(#main.popups[1].controls.choice1.list==25,"The socket enchantment catalogue is incomplete")
		assert(main.popups[1].controls.choice1:GetSelValueByKey("val")=="DeepwaterTattooEnchantStrGlobalFireDamage","Imported socket enchantment was not selected")
		ui:choose("choice1","DeepwaterTattooEnchantDexMovementSpeed","val");frame("crafting-katakohi-catalogue");ui:click("use");ui:click("keep");ui:click("tab_craft");frame("crafting-katakohi-hypothetical")
		ui:click("tab_targets");ui:click("targetPicker");ui:choose("kind","Enchant");ui:text("search","Movement Speed");frame("crafting-enchantment-target-picker");ui:click("choose")
		ui:click("targetGroups");ui:click("groupConditions");assert(main.popups[1].controls.scope:GetSelValue()=="Enchantments","Socket enchantment target scope was not retained");ui:click("keep");ui:click("keepGroups");ui:click("close")
	end
	do
		local raw="Rarity: NORMAL\nIron Gauntlets\nItem Level: 86\nSockets: R-R-R-R"
		local model=sim.model(raw);require("Classes.CraftingSimulatorControl").Open(build,{id="katakohi-roll-ui",title="Socket enchantment roll",slot="Gloves",startingItem=raw,goals={},steps={}})
		ui:click("settings");ui:text("paletteSearch",sim.labels.ducat_katakohi);assert(main.popups[1].controls.paletteUse:IsEnabled());ui:click("paletteUse")
		local hints={};for _,row in ipairs(main.popups[1].controls.actionHint.list) do hints[#hints+1]=StripEscapes(row[1]) end
		assert(table.concat(hints," "):find("experimental",1,true),"The Ducat assumptions were not shown");frame("crafting-katakohi-roll")
		ui:click("apply");assert(main.popups[1].title=="Allflame outcomes" and #main.popups[1].controls.choice.list==4,"The Ducat did not show its historical ghost outcomes")
		frame("crafting-katakohi-ghosts");ui:click("keep");ui:click("close")
		local saved;require("Classes.CraftingRecipeControl").Open({steps={{method="alchemy"}},targets={},requirements={minAffixes=1}},{method="alchemy"},function(value) saved=value end,model)
		ui:click("addCurrency");ui:text("search","Katakohi");frame("crafting-katakohi-recipe");ui:click("choose");ui:click("keep")
		assert(saved and saved.steps[2].method=="ducat_katakohi","The Ducat recipe step was not retained")
	end
	do
		local raw="Rarity: NORMAL\nPlate Vest\nItem Level: 86\nQuality: 20\nSockets: R-G W-W"
		require("Classes.CraftingSimulatorControl").Open(build,{id="jeweller-ui",title="Experimental Jeweller",slot="Body Armour",startingItem=raw,goals={},steps={},nativeRecipe={steps={{method="jeweller"}},targets={},requirements={sockets=6}}})
		ui:click("settings");ui:text("paletteSearch",sim.labels.jeweller);assert(main.popups[1].controls.paletteUse:IsEnabled());ui:click("paletteUse")
		local hints={};for _,row in ipairs(main.popups[1].controls.actionHint.list) do hints[#hints+1]=StripEscapes(row[1]) end
		assert(table.concat(hints," "):find("Experimental",1,true),"Jeweller assumptions were not shown");frame("crafting-jeweller-experimental")
		ui:click("tab_settings");ui:click("exact");local jobs=require("Modules.CraftingTasks");for i=1,1000 do if not jobs.job then break end;jobs.tick(build) end
		local odds=build.craftingAnalyses["jeweller-ui"].results.odds.result
		assert(not jobs.job and not odds.sampled and odds.warnings[1].code=="jeweller_estimate","Jeweller exact model warning was not shown")
		local lines={};for _,row in ipairs(main.popups[1].controls.resultSummary.list) do lines[#lines+1]=StripEscapes(row[1] or "") end
		assert(table.concat(lines," "):find("1 socket",1,true) and table.concat(lines," "):find("6 sockets | Target",1,true),"Jeweller outcome breakdown omitted a modeled count")
		ui:click("tab_simulate");frame("crafting-jeweller-odds");ui:click("tab_craft");ui:click("item");assert(main.popups[1].controls.intro.label:find("Applied Jeweller",1,true),"Jeweller action failed");ui:click("close")
	end
	do
		local raw="Rarity: NORMAL\nPlate Vest\nItem Level: 86\nQuality: 20\nSockets: R G B W W W"
		require("Classes.CraftingSimulatorControl").Open(build,{id="fusing-ui",title="Experimental Fusing",slot="Body Armour",startingItem=raw,goals={},steps={}})
		ui:click("settings");ui:text("paletteSearch",sim.labels.fusing);assert(main.popups[1].controls.paletteUse:IsEnabled());ui:click("paletteUse")
		local hints={};for _,row in ipairs(main.popups[1].controls.actionHint.list) do hints[#hints+1]=StripEscapes(row[1]) end
		assert(table.concat(hints," "):find("Experimental",1,true),"Fusing assumptions were not shown");frame("crafting-fusing-experimental")
		ui:click("item");assert(main.popups[1].controls.intro.label:find("Applied Orb of Fusing",1,true),"Fusing action failed");ui:click("close")
	end

	do
		local raw="Rarity: NORMAL\nPlate Vest\nItem Level: 86"
		local oldProjects=copyTable(build.savers.CraftingProjects.projects);local oldJourney=copyTable(build.savers.BuildJourney.data)
		local project={id="bench-unlock-ui",title="Bench unlock",slot="Body Armour",startingItem=raw,goals={},steps={}}
		build.savers.CraftingProjects:Upsert(project);require("Classes.CraftingSimulatorControl").Open(build,project)
		ui:click("settings");ui:text("paletteSearch","Crafting bench");ui:click("paletteUse");ui:choose("option","1 Prefix Modifier cannot be changed","label")
		local hints={};for _,row in ipairs(main.popups[1].controls.actionHint.list) do hints[#hints+1]=StripEscapes(row[1]) end
		local description=table.concat(hints," ");assert(description:find("Sanctuary Map",1,true),"Bench recipe location was not shown")
		assert(description:find("equal odds assumed",1,true),"Partial-lock assumption was not shown with the recipe location")
		frame("crafting-bench-unlock");ui:click("tab_simulate");ui:click("editRecipe");ui:click("add")
		assert(main.popups[1].controls.graph.list[1].detail:find("Sanctuary Map",1,true),"Recipe card omitted the bench location")
		frame("crafting-bench-unlock-recipe");ui:click("reviewUnlocks");frame("crafting-unlock-checklist")
		assert(main.popups[1].controls.choose:IsEnabled(),"Untracked recipe unlock was not offered");ui:click("choose")
		assert(not main.popups[1].controls.choose:IsEnabled(),"Tracked unlock was offered twice");frame("crafting-unlock-checklist-tracked");ui:click("close");ui:click("trackUnlock")
		assert(main.popups[1].title=="Recipe unlock" and #build.savers.BuildJourney.data.milestones==#oldJourney.milestones+1,"Tracking did not add a linked Roadmap task")
		frame("crafting-unlock-roadmap-confirm");ui:click("close");ui:click("close");ui:click("close")
		build.savers.CraftingProjects.projects=oldProjects;build.savers.BuildJourney.data=oldJourney
	end
	do
		local raw="Rarity: NORMAL\nPlate Vest\nItem Level: 86\nSockets: R-G B W-W R"
		require("Classes.CraftingSimulatorControl").Open(build,{id="white-socket-bench-ui",title="White sockets",slot="Body Armour",startingItem=raw,goals={},steps={}})
		ui:click("settings");ui:text("paletteSearch","white sockets (3.30)");assert(main.popups[1].controls.paletteUse:IsEnabled());frame("crafting-white-socket-bench-selection")
		ui:click("paletteUse");ui:click("item");assert(main.popups[1].controls.intro.label:find("Applied Bench: white sockets",1,true),"White socket bench craft was not applied")
		frame("crafting-white-socket-bench-applied");ui:click("undo");ui:click("close")
	end

	do
		local raw="Rarity: NORMAL\nDriftwood Wand\nItem Level: 86";local model=sim.model(raw)
		local state=sim.validateState(model,{rarity="RARE",affixes={{id="LocalAddedChaosDamage1",range=0.5},{id="bench:731",range=0.5,crafted=true}}})
		require("Classes.CraftingSimulatorControl").Open(build,{id="annul-330-ui",title="Annul with attack blocker",slot="Weapon 1",startingItem=sim.toItem(model,state).raw,goals={},steps={},nativeRecipe={steps={},targets={{anyOf={"LocalAddedChaosDamage1"}}}}})
		ui:click("currency_annul");local hints={};for _,row in ipairs(main.popups[1].controls.actionHint.list) do hints[#hints+1]=row[1] end;assert(table.concat(hints," "):find("3.30",1,true),"Annulment did not explain the 3.30 rule")
		ui:choose("page","Craft settings");ui:click("exact");local jobs=require("Modules.CraftingTasks")
		for i=1,100 do if not jobs.job then break end;jobs.tick(build) end
		local odds=build.craftingAnalyses["annul-330-ui"].results.odds.result
		assert(not jobs.job and odds.sampled==false and odds.successChance==50,"Annulment odds did not enumerate the two outcomes")
		ui:choose("page","Simulate recipe");frame("crafting-annul-exact-odds");ui:choose("page","Emulate item")
		frame("crafting-annul-330-rule");ui:click("item");assert(main.popups[1].controls.intro.label:find("Applied Orb of Annulment",1,true));frame("crafting-annul-330-applied");ui:click("close")
	end
	do
		local raw="Rarity: NORMAL\nDriftwood Wand\nItem Level: 86\nSockets: R G B";local model=sim.model(raw)
		local state=sim.validateState(model,{rarity="RARE",affixes={{id="LocalAddedChaosDamage1",range=0.5}}})
		require("Classes.CraftingSimulatorControl").Open(build,{id="partial-lock-ui",title="Partial prefix lock",slot="Weapon 1",startingItem=sim.toItem(model,state).raw,goals={},steps={},nativeRecipe={steps={},targets={{anyOf={"LocalAddedChaosDamage1"}}}}})
		ui:click("settings");ui:text("paletteSearch","Crafting bench");assert(main.popups[1].controls.paletteUse:IsEnabled(),"Crafting bench not offered")
		ui:click("paletteUse");ui:choose("option","1 Prefix Modifier cannot be changed","label")
		local hints={};for _,row in ipairs(main.popups[1].controls.actionHint.list) do hints[#hints+1]=row[1] end;assert(table.concat(hints," "):find("Experimental partial lock",1,true),"Partial lock assumption was not explained before application")
		frame("crafting-partial-lock-select")
		ui:click("apply");assert(main.popups[1].controls.intro.label:find("Applied Crafting bench",1,true),"Partial lock was not applied")
		ui:click("settings");ui:text("paletteSearch","white sockets (3.30)");assert(main.popups[1].controls.paletteUse:IsEnabled(),"Socket craft was blocked by a partial lock")
		ui:click("paletteUse");ui:click("item");assert(main.popups[1].controls.intro.label:find("Applied Bench: white sockets",1,true),"Socket craft did not apply")
		frame("crafting-partial-lock-sockets")
		ui:click("currency_annul");ui:choose("page","Craft settings");ui:click("exact");local jobs=require("Modules.CraftingTasks")
		for i=1,100 do if not jobs.job then break end;jobs.tick(build) end
		local odds=build.craftingAnalyses["partial-lock-ui"].results.odds.result
		assert(not jobs.job and odds.sampled==false and odds.successChance==100 and odds.warnings[1].code=="partial_lock_model","Partial lock odds were not disclosed")
		ui:choose("page","Simulate recipe");frame("crafting-partial-lock-odds")
		ui:choose("page","Emulate item");ui:click("settings");ui:text("paletteSearch",sim.labels.harvest_reforge);assert(main.popups[1].controls.paletteUse:IsEnabled(),"Harvest reforge was blocked by a partial lock")
		ui:click("paletteUse");ui:choose("option","fire","label");ui:click("apply")
		assert(main.popups[1].controls.intro.label:find("Applied Harvest",1,true),"Harvest reforge did not apply")
		frame("crafting-partial-lock-harvest");ui:click("close")
	end
	do
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local model=sim.model(raw)
		local state=sim.validateState(model,{rarity="RARE",affixes={{id="FireResist1",range=0.5},{id="ChaosResist1",range=0.5}}})
		state=sim.perform(raw,{method="bench",modId="bench:partial-suffix-1"},1,state).state
		require("Classes.CraftingSimulatorControl").Open(build,{id="partial-conversion-ui",title="Partial lock conversion",slot="Helmet",startingItem=raw,goals={},steps={},nativeRecipe={initialState=state,steps={},targets={}}})
		ui:click("settings");ui:text("paletteSearch",sim.labels.harvest_resistance)
		assert(main.popups[1].controls.paletteUse:IsEnabled(),"Partial-lock conversion was not offered")
		ui:click("paletteUse");ui:choose("option","fire to cold","label")
		local hints={};for _,row in ipairs(main.popups[1].controls.actionHint.list) do hints[#hints+1]=StripEscapes(row[1]) end
		assert(table.concat(hints," "):gsub("%s+"," "):find("no legal Harvest outcome",1,true),"Conversion selection risk was not explained")
		frame("crafting-partial-conversion");ui:click("close")
	end
	do
		local raw="Rarity: NORMAL\nDriftwood Wand\nItem Level: 86";local model=sim.model(raw)
		local state=sim.validateState(model,{rarity="RARE",affixes={{id="LocalAddedChaosDamage1",range=0.5}}})
		state=sim.perform(raw,{method="bench",modId="bench:partial-prefix-1"},1,state).state
		require("Classes.CraftingSimulatorControl").Open(build,{id="partial-bench-ui",title="Partial lock bench reroll",slot="Weapon 1",startingItem=raw,goals={},steps={},nativeRecipe={initialState=state,steps={},targets={}}})
		ui:click("settings");ui:text("paletteSearch",sim.labels.bench_reroll);assert(main.popups[1].controls.paletteUse:IsEnabled(),"Bench reroll was blocked by a partial lock")
		ui:click("paletteUse");ui:choose("option","Reroll one random modifier","label")
		assert(#main.popups[1].controls.option.list==1,"Impossible three-mod reroll was offered")
		local hints={};for _,row in ipairs(main.popups[1].controls.actionHint.list) do hints[#hints+1]=row[1] end;assert(table.concat(hints," "):find("too few removable",1,true),"Conditional bench reroll was not explained")
		frame("crafting-partial-bench-reroll");ui:click("apply")
		assert(main.popups[1].controls.intro.label:find("Applied",1,true),"Partial-lock bench reroll did not apply");ui:click("close")
	end
	do
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local model=sim.model(raw)
		local state=sim.validateState(model,{rarity="RARE",affixes={{id="AttackerTakesDamage1",range=0.5}}})
		state=sim.perform(raw,{method="bench",modId="bench:partial-prefix-1"},1,state).state
		require("Classes.CraftingSimulatorControl").Open(build,{id="partial-harvest-choices-ui",title="Partial lock Harvest choices",slot="Helmet",startingItem=raw,goals={},steps={},nativeRecipe={initialState=state,steps={},targets={}}})
		ui:click("settings");ui:text("paletteSearch",sim.labels.harvest_reforge);assert(main.popups[1].controls.paletteUse:IsEnabled());ui:click("paletteUse")
		local found={};for _,option in ipairs(main.popups[1].controls.option.list) do found[option.label]=true end
		assert(not found.physical and found.life,"Harvest reforge options ignored protected modifier groups")
		local explanation={};for _,row in ipairs(main.popups[1].controls.actionHint.list) do explanation[#explanation+1]=StripEscapes(row[1]) end;assert(table.concat(explanation," "):gsub("%s+"," "):find("no legal Harvest outcome",1,true),"Conditional Harvest availability was not explained")
		frame("crafting-partial-harvest-choices");ui:click("close")
		local multi;for _,entry in ipairs(model.bench) do if entry.mod[1]=="Can have up to 3 Crafted Modifiers" then multi=entry.id;break end end
		local protected={rarity="RARE",affixes={{id="bench:partial-suffix-2",crafted=true,range=0.5},{id="bench:partial-prefix-1",crafted=true,range=0.5},{id=assert(multi),crafted=true,range=0.5}}}
		require("Classes.CraftingSimulatorControl").Open(build,{id="partial-harvest-blocked-ui",title="Protected Harvest item",slot="Helmet",startingItem=raw,goals={},steps={},nativeRecipe={initialState=protected,steps={},targets={}}})
		ui:click("settings");ui:text("paletteSearch",sim.labels.harvest_augment);assert(not main.popups[1].controls.paletteUse:IsEnabled(),"Fully protected Harvest augment was offered")
		local hints={};for _,row in ipairs(main.popups[1].controls.paletteHint.list) do hints[#hints+1]=StripEscapes(row[1]) end;assert(table.concat(hints," "):gsub("%s+"," "):find("modifier that can be removed",1,true),"Protected-item reason was not explained")
		frame("crafting-partial-harvest-unavailable")
		ui:text("paletteSearch",sim.labels.bench_reroll);assert(not main.popups[1].controls.paletteUse:IsEnabled(),"Fully protected bench reroll was offered")
		hints={};for _,row in ipairs(main.popups[1].controls.paletteHint.list) do hints[#hints+1]=StripEscapes(row[1]) end;assert(table.concat(hints," "):gsub("%s+"," "):find("removable modifier",1,true),"Bench reroll unavailability was not explained")
		frame("crafting-partial-bench-unavailable");ui:click("close")
	end

	do
		local raw="Rarity: NORMAL\nPlate Vest\nItem Level: 86";local model=sim.model(raw)
		local state=sim.validateState(model,{rarity="RARE",affixes={{id="AttackerTakesDamage1",range=0.5}}})
		local divine="Metadata/Items/Currency/CurrencyModValues";local blessed="Metadata/Items/Currency/CurrencyRerollImplicit"
		local p={id="meta-cost-ui",title="Prefix lock budget",slot="Body Armour",startingItem=sim.toItem(model,state).raw,goals={},steps={},nativeRecipe={steps={{method="bench",modId="bench:728"}},targets={},requirements={minAffixes=2}},priceBook={currency="chaos",source="Test quotes",quotedAt=1700000000,values={[divine]=10,[blessed]=2}}}
		require("Classes.CraftingSimulatorControl").Open(build,p);ui:click("tab_simulate");ui:click("resourcePrices");ui:choose("mode","Recipe resources");frame("crafting-meta-330-resources");ui:click("close")
		ui:text("trials","2");ui:text("budget","1");ui:click("runRecipe");local jobs=require("Modules.CraftingTasks");for i=1,200 do if not jobs.job then break end;jobs.tick(build) end;assert(not jobs.job)
		local lines={};for _,row in ipairs(main.popups[1].controls.resultSummary.list) do lines[#lines+1]=row[1] end;assert(table.concat(lines," "):find("Mean spent: 48.00 chaos",1,true),"3.30 lock ingredient costs were not included")
		local provenance=build.craftingAnalyses[p.id].results.simulation.result;assert(provenance.treeVersion==build.spec.treeVersion and provenance.treeVersionScope=="build_context_only","Crafting result lost the selected tree context")
		assert(table.concat(lines," "):find("context only",1,true),"Crafting result did not explain tree provenance")
		frame("crafting-meta-330-budget");ui:click("close")
	end

	do
		local left=sim.model("Rarity: NORMAL\nZodiac Leather\nItem Level: 70");local right=sim.model("Rarity: NORMAL\nPlate Vest\nItem Level: 86")
		local leftState=sim.validateState(left,{rarity="MAGIC",affixes={{id="IncreasedLife0",range=0.5}}})
		local rightState=sim.validateState(right,{rarity="MAGIC",affixes={{id="LocalIncreasedPhysicalDamageReductionRating1",range=0.5}}})
		local donor=sim.toItem(right,rightState).raw
		require("Classes.CraftingSimulatorControl").Open(build,{id="recombine-330-ui",title="Armour and evasion bases",slot="Body Armour",startingItem=sim.toItem(left,leftState).raw,goals={},steps={},nativeRecipe={steps={{method="recombine",donorItem=donor}},targets={},requirements={minAffixes=2}}})
		ui:click("settings");ui:text("paletteSearch","Unpredictable recombination");ui:click("paletteUse");ui:click("tab_settings");ui:click("configure")
		local invalidText="Rarity: NORMAL\nGold Ring\nItem Level: 86";ui:text("donor",invalidText);assert(main.popups[1].controls.donor.buf==invalidText,"Donor entry changed while typing");ui:click("use")
		local warning=StripEscapes(main.popups[1].controls[1].label);assert(warning:find("same item class",1,true),"Donor setup did not explain the incompatible base")
		frame("crafting-recombine-donor-invalid")
		ui:click("close");assert(main.popups[1].controls.donor.buf==invalidText,"Donor text was lost after validation")
		local locked=sim.validateState(right,{rarity="RARE",affixes={{id="LocalIncreasedPhysicalDamageReductionRating1",range=0.5},{id="bench:partial-prefix-1",range=0.5,crafted=true}}})
		ui:text("donor",sim.toItem(right,locked).raw);ui:click("use");assert(main.popups[1].controls.configure,"A partial-lock donor was not accepted for unpredictable recombination");ui:click("configure")
		ui:text("donor",donor);frame("crafting-recombine-330-donor");ui:click("use");ui:text("seed","1");ui:click("tab_craft")
		local hints={};for _,row in ipairs(main.popups[1].controls.actionHint.list) do hints[#hints+1]=row[1] end;assert(table.concat(hints," "):find("preliminary 3.30",1,true),"Recombination did not flag preliminary count odds")
		frame("crafting-recombine-330-warning");ui:click("item");assert(main.popups[1].controls.intro.label:find("Applied Unpredictable",1,true),"Cross-defence recombination failed");frame("crafting-recombine-330-result")
		ui:click("tab_simulate");ui:text("trials","2");ui:text("budget","1");ui:click("runRecipe");local jobs=require("Modules.CraftingTasks");for i=1,1000 do if not jobs.job then break end;jobs.tick(build) end;assert(not jobs.job)
		local lines={};for _,row in ipairs(main.popups[1].controls.resultSummary.list) do lines[#lines+1]=row[1] end;assert(table.concat(lines," "):find("preliminary 3.30",1,true) and table.concat(lines," "):find("weights",1,true),"Saved recipe result lost its model note");frame("crafting-recombine-model-note")
		ui:click("compareRecipes");ui:click("run");for i=1,1000 do if not jobs.job then break end;jobs.tick(build) end;assert(not jobs.job)
		lines={};for _,row in ipairs(main.popups[1].controls.results.list) do lines[#lines+1]=row[1] end;assert(table.concat(lines," "):find("preliminary 3.30",1,true) and table.concat(lines," "):find("weights",1,true),"Recipe comparison lost its model note");frame("crafting-recombine-comparison-note");ui:click("close")
		ui:click("distribution");frame("crafting-recombine-distribution-note");ui:click("charts");assert(main.popups[1].controls.notes:IsEnabled());frame("crafting-recombine-chart-note");ui:click("notes");frame("crafting-recombine-chart-notes-open");ui:click("close");ui:click("close");ui:click("close");ui:click("close")
	end

	do
		local hybridRaw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local m=sim.model(hybridRaw);local state=copyTable(m.initial)
		state.rarity="RARE";state.affixes={{id="LocalBaseArmourAndLife1",range={0,1}}}
		require("Classes.CraftingSimulatorControl").Open(build,{id="independent-affix-ui",title="Independent modifier rolls",slot="Helmet",startingItem=sim.toItem(m,state).raw,goals={},steps={}})
		local found=false;for _,row in ipairs(main.popups[1].controls.itemMods.list) do if row[1]:find("23 to maximum Life",1,true) then found=true end end
		assert(found,"The item card reused the Armour roll for maximum Life")
		frame("crafting-independent-affix-lines");ui:click("close")
	end

	do
		local priceRaw="Rarity: NORMAL\nPlate Vest\nItem Level: 86\nQuality: 20\nSockets: W W W W W W"
		local priced={id="priced-ui",title="Enchanted six-link budget",slot="Body Armour",startingItem=priceRaw,goals={},steps={},preferredMethod="omen_connections",nativeRecipe={steps={{method="harvest_enchant",enchantId="LifeBodyEnchant"},{method="omen_connections"}},targets={},requirements={links=6,harvestEnchant="LifeBodyEnchant"}}}
		require("Classes.CraftingSimulatorControl").Open(build,priced)
		ui:click("tab_simulate");ui:click("resourcePrices");frame("crafting-resource-prices")
		ui:text("search","Omen of Connections");ui:text("price","2");assert(not main.popups[1].controls.currency:IsEnabled())
		ui:text("search","Orb of Fusing");ui:text("price","0.25")
		ui:text("search","Wild Crystallised Lifeforce");ui:text("price","0.1");ui:text("source","Local reference quotes")
		frame("crafting-resource-quote");ui:choose("mode","Quoted resources");ui:text("search","");frame("crafting-resource-priced-list")
		ui:click("keep");assert(main.popups[1].title=="Crafting workbench","Keeping prices left the resource editor open")
		ui:text("trials","6");ui:text("budget","2");ui:click("runRecipe")
		local jobs=require("Modules.CraftingTasks");for i=1,100 do if not jobs.job then break end;jobs.tick(build) end;assert(not jobs.job)
		local lines={};for _,row in ipairs(main.popups[1].controls.resultSummary.list) do lines[#lines+1]=row[1] end
		assert(table.concat(lines," "):find("Mean spent: 327.25 chaos",1,true),"The saved resource quotes were not used")
		frame("crafting-resource-price-simulation")
		ui:click("resourcePrices");ui:click("reset");assert(main.popups[1].controls.currency:IsEnabled());ui:text("currency","divine")
		frame("crafting-resource-unit-reset");ui:click("close")
		assert(main.popups[1].controls.currency.buf=="chaos","Cancelling the price edit changed saved units")
		ui:click("compareRecipes");for i=1,3 do ui:choose("route"..i,2,"val") end;assert(not main.popups[1].controls.price1:IsEnabled())
		ui:click("run");for i=1,200 do if not jobs.job then break end;jobs.tick(build) end;assert(not jobs.job)
		lines={};for _,row in ipairs(main.popups[1].controls.results.list) do lines[#lines+1]=row[1] end
		assert(table.concat(lines," "):find("327.25 chaos",1,true),"Recipe comparison ignored saved quotes")
		frame("crafting-resource-price-comparison");ui:click("close");ui:click("close")
		require("Classes.CraftingSimulatorControl").Open(build,{id="price-copy-ui",title="Helmet quote reuse",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={}})
		ui:click("tab_simulate");ui:click("resourcePrices");assert(main.popups[1].controls.copy:IsEnabled());ui:click("copy");ui:click("keep")
		assert(main.popups[1].controls.source.buf=="Local reference quotes","Copying quotes lost their source")
		ui:text("search","Orb of Alchemy");ui:text("price","1.5");frame("crafting-resource-copy-quote");ui:click("keep");ui:click("close")
	end

	do
		local model=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86")
		local quote={currency="chaos",source="Manual quotes",quotedAt=1700000000,values={beast_prefix_suffix=2}}
		require("Classes.CraftingPricesControl").Open(model,model.initial,{{method="beast_prefix_suffix",beastLevel=86}},quote,"chaos",function() end)
		ui:text("search","beast level 86")
		assert(StripEscapes(main.popups[1].controls.resources.list[2][1]):find("Generic quote: 2 chaos",1,true),"Missing generic Bestiary price")
		frame("crafting-beast-generic-price");ui:text("price","7")
		assert(StripEscapes(main.popups[1].controls.resources.list[2][1]):find("7 chaos",1,true),"Specific Bestiary price not shown")
		ui:click("close")
	end

	do
		local model=sim.model("Rarity: NORMAL\nPlate Vest\nItem Level: 86\nSockets: W W W W W W")
		require("Classes.CraftingPricesControl").Open(model,model.initial,{{method="gwennen",firstOutcome=1000,secondOutcome=1012},{method="socket_colour_bench",count=3}},nil,"chaos",function() end)
		ui:text("search","Vaal Orb");assert(StripEscapes(main.popups[1].controls.resources.list[1][1]):find("Vaal Orb",1,true),"Possible Gwennen corruption surcharge was omitted")
		frame("crafting-gwennen-price");ui:click("close")
	end

	do
		local raw="Rarity: NORMAL\nPlate Vest\nItem Level: 86"
		local benchProject={id="bench-price-ui",title="Bench ingredient budget",slot="Body Armour",startingItem=raw,goals={},steps={},preferredMethod="bench",nativeRecipe={steps={{method="bench",modId="bench:1"}},targets={},requirements={minAffixes=1}}}
		require("Classes.CraftingSimulatorControl").Open(build,benchProject)
		ui:click("tab_simulate");ui:click("resourcePrices");ui:text("search","Orb of Alteration")
		local resources=main.popups[1].controls.resources.list
		assert(resources[1][1]:find("Orb of Alteration",1,true),"Bench ingredients were not discovered")
		frame("crafting-bench-ingredients");ui:text("price","1.5");ui:click("keep");ui:text("trials","4");ui:text("budget","1");ui:click("runRecipe")
		local jobs=require("Modules.CraftingTasks");for i=1,200 do if not jobs.job then break end;jobs.tick(build) end;assert(not jobs.job)
		local lines={};for _,row in ipairs(main.popups[1].controls.resultSummary.list) do lines[#lines+1]=row[1] end
		assert(table.concat(lines," "):find("Mean spent: 1.50 chaos",1,true));frame("crafting-bench-cost");ui:click("close")
		local life,cold="Metadata/Items/Currency/CurrencyDelveCraftingLife","Metadata/Items/Currency/CurrencyDelveCraftingCold"
		local p={id="fossil-budget-ui",title="Fossil comparison budget",slot="Body Armour",startingItem=raw,goals={},steps={},preferredMethod="fossil",nativeRecipe={steps={{method="fossil",fossils={life,cold}}},targets={},requirements={minAffixes=1}},priceBook={currency="chaos",source="Local fossil quotes",quotedAt=1700000000,values={[life]=1,["Metadata/Items/Delve/DelveStackableSocketableCurrencyReroll1"]=2}}}
		require("Classes.CraftingSimulatorControl").Open(build,p)
		ui:click("tab_settings");ui:click("configure");ui:choose("fossil1",life,"id");ui:choose("fossil2",cold,"id")
		assert(main.popups[1].controls.tangled:GetSelValueByKey("id")==nil,"An unrevealed Tangled outcome was assumed")
		frame("crafting-fossil-configured");ui:choose("fossil2",life,"id");ui:click("use")
		assert(main.popups[1].title=="Native crafting");frame("crafting-fossil-duplicate-error");ui:click("close")
		assert(main.popups[1].controls.fossil1:GetSelValueByKey("id")==life,"Invalid fossil configuration lost the input")
		ui:choose("fossil2",cold,"id");ui:click("use");ui:click("configure")
		assert(main.popups[1].controls.fossil1:GetSelValueByKey("id")==life and main.popups[1].controls.fossil2:GetSelValueByKey("id")==cold,"Reopening configuration lost its selection")
		frame("crafting-fossil-reopened");ui:click("close");ui:click("tab_simulate");ui:text("trials","4");ui:click("optimize")
		for i=1,400 do if not jobs.job then break end;jobs.tick(build) end;assert(not jobs.job)
		assert(main.popups[1].title=="Fossil comparison");frame("crafting-fossil-comparison")
		local list=main.popups[1].controls.results;local x,y=list:GetPos();ui:clickAt(x+180,y+12);ui:key("DOWN")
		lines={};for _,row in ipairs(main.popups[1].controls.stats.list) do lines[#lines+1]=row[1] end
		assert(table.concat(lines," "):find("Cost unknown",1,true));frame("crafting-fossil-unknown-cost")
		ui:choose("sort","successChance","val");frame("crafting-fossil-sorted");ui:click("copy")
		assert(ui.clipboard:find('"Quote source"',1,true) and ui.clipboard:find('"Local fossil quotes"',1,true))
		ui:click("choose");assert(main.popups[1].title=="Crafting workbench")
		frame("crafting-fossil-selected","optimize");ui:click("fossilResults");assert(main.popups[1].title=="Fossil comparison");ui:click("close")
		ui:click("keepWorking");local saved
		for _,entry in ipairs(build.savers.CraftingProjects.projects) do if entry.id==p.id then saved=entry end end
		assert(saved and #saved.run.state.affixes==0 and #saved.run.history==0,"Selecting fossils spent currency or changed the item")
		ui:click("close")
	end

	do
		local raw="Rarity: NORMAL\nPlate Vest\nItem Level: 86";local model=sim.model(raw);local alchemy="Metadata/Items/Currency/CurrencyUpgradeToRare";local action
		for _,entry in ipairs(model.bench) do local cost=require("Modules.CraftingBenchCosts").cost(model,entry.id);if cost and cost[alchemy]==1 then action={method="bench",modId=entry.id};break end end
		assert(action)
		local p={id="action-price-ui",title="Separate action and currency quotes",slot="Body Armour",startingItem=raw,goals={},steps={},preferredMethod="alchemy",nativeRecipe={steps={action},targets={},requirements={minAffixes=1}},priceBook={currency="chaos",source="Action scope quotes",quotedAt=1700000000,values={[alchemy]=1}}}
		require("Classes.CraftingSimulatorControl").Open(build,p);ui:click("tab_simulate");ui:text("trials","2");ui:text("budget","1");ui:text("price","7");ui:click("runRecipe")
		local function finish() local jobs=require("Modules.CraftingTasks");for i=1,1000 do if not jobs.job then return end;jobs.tick(build) end;error("Action price job did not complete") end
		local function summary(key) local lines={};for _,row in ipairs(main.popups[1].controls[key].list) do lines[#lines+1]=row[1] end;return table.concat(lines," ") end
		finish();assert(summary("resultSummary"):find("Mean spent: 1.00 chaos",1,true));assert(summary("resultSummary"):find("override was not used",1,true));frame("crafting-action-override-unused")
		ui:text("price","99");ui:text("budget","5");ui:click("distribution");frame("crafting-saved-recipe-results")
		local equipped=build.itemsTab.slots["Body Armour"].selItemId
		ui:click("keepTarget");local keptProject;for _,entry in ipairs(build.savers.CraftingProjects.projects) do if entry.id==p.id then keptProject=entry end end
		assert(summary("precision"):find("Save the build",1,true),"Keeping a target should explain how to persist it")
		assert(keptProject and keptProject.targetItem and keptProject.targetItem:find("Plate Vest",1,true),"Retained result was not kept in the crafting guide")
		assert(keptProject.nativeRecipe and keptProject.priceBook and build.itemsTab.slots["Body Armour"].selItemId==equipped,"Keeping the target changed the recipe, prices or equipped item")
		local saved={};build.savers.CraftingProjects:Save(saved);local reopened=require("Modules.CraftingProjects").new(build);reopened:Load(saved)
		local found;for _,entry in ipairs(reopened.projects) do if entry.id==p.id then found=entry end end;assert(found and found.targetItem==keptProject.targetItem,"Kept target did not survive serialization")
		frame("crafting-result-target-kept");ui:click("moreTrials");finish()
		assert(summary("resultSummary"):find("Mean spent: 1.00 chaos",1,true));assert(summary("resultSummary"):find("Saved recipe",1,true));assert(main.popups[1].controls.trials.buf=="32");frame("crafting-saved-recipe-refined")
		ui:text("price","7");ui:text("budget","1");ui:text("trials","2000");ui:click("simulate")
		assert(not main.popups[1].controls.simulate:IsEnabled() and not main.popups[1].controls.runRecipe:IsEnabled());frame("crafting-simulation-running")
		finish();assert(summary("resultSummary"):find("Mean spent: 7.00 chaos",1,true));frame("crafting-action-override-applied")
		assert(summary("resultSummary"):find("Orb of Alchemy: 2000 total",1,true));main.popups[1].controls.resultSummary.controls.scrollBar:SetOffset(10000);frame("crafting-resource-usage");main.popups[1].controls.resultSummary.controls.scrollBar:SetOffset(0)
		ui:click("distribution");frame("crafting-resource-results");ui:click("resources");assert(main.popups[1].title=="Crafting resources used");frame("crafting-resource-browser");ui:text("search","alchemy");frame("crafting-resource-search");ui:click("close");ui:click("close")
		ui:click("compareRecipes");ui:text("price1","many");ui:click("run");assert(main.popups[1].title=="Compare recipes");frame("crafting-comparison-invalid-price");ui:click("close")
		assert(main.popups[1].controls.price1.buf=="many");ui:text("price1","7");ui:click("run");finish()
		assert(summary("results"):find("Mean spent: 7.00 chaos",1,true) and summary("results"):find("Mean spent: 1.00 chaos",1,true));frame("crafting-property-action-comparison")
		ui:click("close");ui:click("close")
		local replacement=copyTable(p);replacement.id="replacement-target-ui";replacement.targetItem=raw;build.savers.CraftingProjects:Upsert(replacement)
		require("Classes.CraftingSimulatorControl").Open(build,replacement);ui:click("tab_simulate");ui:text("trials","2");ui:text("budget","1");ui:click("runRecipe");finish();ui:click("distribution");ui:click("keepTarget")
		assert(main.popups[1].title=="Replace crafting target","Replacing a target must ask for confirmation")
		local cancel;for key,control in pairs(main.popups[1].controls) do if control.label=="Cancel" then cancel=key end end;ui:click(assert(cancel))
		local function replacementTarget() for _,entry in ipairs(build.savers.CraftingProjects.projects) do if entry.id==replacement.id then return entry.targetItem end end end
		assert(replacementTarget()==raw,"Cancelling target replacement changed the guide")
		ui:click("keepTarget");ui:click("confirm");assert(replacementTarget()~=raw,"Confirmed target replacement did not update the guide");frame("crafting-result-target-replaced");ui:click("close");ui:click("close")
		local life="Metadata/Items/Currency/CurrencyDelveCraftingLife";local key=sim.priceKey({method="fossil",fossils={life}})
		local fossilResult=sim.optimizeFossils(raw,{}, {fossils={life},maxSockets=1,trials=2,requirements={minAffixes=1},priceBook={currency="chaos",source="Fossil action quotes",quotedAt=1700000000,values={[life]=1,["Metadata/Items/Delve/DelveStackableSocketableCurrencyReroll1"]=2}},prices={["resonator:1"]=4},actionPrices={[key]=9}})
		require("Classes.CraftingFossilCompareControl").Open(fossilResult);assert(summary("stats"):find("Mean / trial: 9 chaos",1,true))
		assert(summary("names"):find("Resource + action overrides supplied",1,true));frame("crafting-fossil-action-quote");ui:click("copy")
		assert(ui.clipboard:find('"Action override uses"',1,true));ui:click("close")
		local state=sim.perform(raw,{method="alchemy"},1).state;local craft
		for _,entry in ipairs(model.bench) do if not sim.benchReason(model,state,entry.id) then craft={method="bench",modId=entry.id};break end end;assert(craft)
		state=sim.perform(raw,craft,1,state).state
		local services={id="service-prices-ui",title="Bench service ingredients",slot="Body Armour",startingItem=raw,goals={},steps={},preferredMethod="bench_reroll",nativeRecipe={initialState=state,steps={{method="remove_crafted"}},targets={},requirements={maxAffixes=#state.affixes-1}},priceBook={currency="chaos",source="Bench service quotes",quotedAt=1700000000,values={["Metadata/Items/Currency/CurrencyRerollRare"]=1,["Metadata/Items/Currency/CurrencyConvertToNormal"]=2}}}
		require("Classes.CraftingSimulatorControl").Open(build,services);ui:click("tab_simulate");ui:click("resourcePrices")
		local list=main.popups[1].controls.resources.list;local names={};for _,row in ipairs(list) do names[#names+1]=row[1] end;names=table.concat(names," ")
		assert(names:find("Chaos Orb",1,true) and names:find("Orb of Scouring",1,true));frame("crafting-bench-service-quotes");ui:click("close")
		ui:text("trials","2");ui:text("budget","1");ui:click("runRecipe");finish();assert(summary("resultSummary"):find("Mean spent: 2.00 chaos",1,true));frame("crafting-bench-service-cost");ui:click("close")
	end

	do
		local p={id="tainted-quality-ui",title="Corrupted helmet quality",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86\nQuality: 29\nCorrupted",goals={},steps={},preferredMethod="tainted_quality"}
		require("Classes.CraftingSimulatorControl").Open(build,p);local c=main.popups[1].controls
		assert(c.apply:IsEnabled() and c.apply.tooltipText():find("Maximum 20%",1,true),"Tainted quality cap was not disclosed")
		frame("crafting-tainted-quality-cap","apply");ui:click("apply");ui:click("keepWorking")
		local kept;for _,entry in ipairs(build.savers.CraftingProjects.projects) do if entry.id==p.id then kept=entry end end
		assert(kept and kept.run.state.quality>=1 and kept.run.state.quality<=20 and kept.run.initial.quality==29,"Tainted quality or its original item was not saved correctly")
		ui:click("close")
	end
	do
		local p={id="vaal-sockets-ui",title="Corrupt helmet",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86\nSockets: W-W-W-W",goals={},steps={},preferredMethod="vaal"}
		require("Classes.CraftingSimulatorControl").Open(build,p);local c=main.popups[1].controls
		assert(c.apply:IsEnabled() and c.apply.tooltipText():find("reroll sockets and links",1,true),"Vaal socket limitation was not disclosed")
		frame("crafting-vaal-socket-warning","apply");ui:click("close")
	end
	do
		local p={id="abyss-vaal-ui",title="Abyss jewel corruption",slot="Jewel 1",startingItem="Rarity: NORMAL\nSearching Eye Jewel\nItem Level: 86",goals={},steps={},preferredMethod="vaal"}
		require("Classes.CraftingSimulatorControl").Open(build,p);local c=main.popups[1].controls
		assert(c.apply:IsEnabled() and c.apply.tooltipText():find("Unique outcome treated as no change",1,true),"Abyss Vaal unique outcome assumption was not disclosed")
		frame("crafting-abyss-vaal","apply");ui:click("apply");assert(c.intro.label:find("Applied Vaal Orb",1,true),"Abyss jewel Vaal action failed");ui:click("close")
	end
	do
		local p={id="cluster-vaal-ui",title="Cluster jewel corruption",slot="Jewel 1",startingItem="Rarity: NORMAL\nLarge Cluster Jewel\nItem Level: 86\nCluster Jewel Skill: affliction_axe_and_sword_damage\nCluster Jewel Node Count: 8\nImplicits: 2\n{crafted}Adds 8 Passive Skills\n{crafted}Added Small Passive Skills grant: 12% increased Axe and Sword Damage",goals={},steps={},preferredMethod="vaal"}
		require("Classes.CraftingSimulatorControl").Open(build,p);local c=main.popups[1].controls
		assert(c.apply:IsEnabled() and c.apply.tooltipText():find("Unique outcome treated as no change",1,true),"Cluster Vaal unique outcome assumption was not disclosed")
		frame("crafting-cluster-vaal","apply");ui:click("apply");assert(c.intro.label:find("Applied Vaal Orb",1,true),"Cluster jewel Vaal action failed");ui:click("close")
	end
	do
		local p={id="jewel-locus-ui",title="Jewel second corruption",slot="Jewel 1",startingItem="Rarity: NORMAL\nSearching Eye Jewel\nItem Level: 86\nImplicits: 1\nCorrupted Blood cannot be inflicted on you\nCorrupted",goals={},steps={},preferredMethod="locus"}
		require("Classes.CraftingSimulatorControl").Open(build,p);local c=main.popups[1].controls
		assert(c.apply:IsEnabled() and c.apply.tooltipText():find("unverified",1,true),"Jewel Locus assumptions were not disclosed")
		frame("crafting-jewel-locus","apply");ui:click("apply");assert(c.intro.label:find("Applied Locus of Corruption",1,true),"Jewel Locus action failed");ui:click("close")
	end
	local project={id="headless-ui",title="Headless crafting check",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86\nSockets: R-G-B",
		goals={"Life and resistances"},steps={{action="Inspect native crafting"}}}
	build.savers.CraftingProjects:Upsert(project)
	require("Classes.CraftingProjectControl").Open(build)
	frame("projects");ui:choose("projects","Headless crafting check","label");ui:click("native")
	frame("emulator");frame("currency-tooltip","currency_alchemy")
	ui:click("tab_simulate");assert(main.popups[1].controls.simulate.tooltipText():find("Choose a target",1,true));frame("crafting-missing-target-tooltip","simulate");ui:click("tab_craft")
	ui:click("currency_alchemy");ui:click("item")
	frame("crafted")
	assert(#main.popups[1].controls.itemMods.list>=4,"Clicking the item did not apply Alchemy")
	assert(main.popups[1].controls.intro.label:find("Applied Orb of Alchemy",1,true))
	ui:click("undo");frame("undone")
	assert(main.popups[1].controls.itemMods.list[1][1]:find("No explicit modifiers",1,true),"Undo did not restore the item")
	ui:click("keepItem");ui:click("inventory");frame("crafting-inventory");ui:text("itemTitle","Reusable helmet base");ui:click("rename");frame("crafting-inventory-renamed");ui:click("compare");frame("crafting-inventory-comparison");ui:click("close");ui:click("remove");frame("crafting-inventory-empty");ui:click("undoRemove");frame("crafting-inventory-restored");ui:click("close")
	ui:click("currency_transmute");ui:click("item");frame("magic")
	assert(main.popups[1].controls.itemMods.list[1][1]:find("No explicit modifiers",1,true)==nil)
	ui:click("undo");ui:click("currency_chromatic");ui:click("item");frame("sockets")
	assert(main.popups[1].controls.intro.label:find("Applied Chromatic Orb",1,true))
	ui:click("undo");ui:click("currency_alchemy");ui:choose("page","Craft settings");ui:click("allflame")
	assert(main.popups[1].controls.mode:GetSelValue()=="3.29 client data","Historical data was labelled current")
	local historical={};for _,row in ipairs(main.popups[1].controls.historical.list) do historical[#historical+1]=row[1] end;assert(table.concat(historical," "):find("not core in 3.30",1,true))
	frame("allflame");ui:choose("mode","Observed override");frame("allflame-observed-historical");ui:choose("mode","3.29 client data");ui:click("use");ui:choose("page","Emulate item");ui:click("apply")
	assert(main.popups[1].title=="Allflame outcomes")
	assert(#main.popups[1].controls.choice.list==4)
	frame("ghosts");ui:choose("choice",3,"val");ui:click("keep")
	frame("kept");ui:choose("page","Craft settings");ui:click("manual")
	frame("editor");ui:click("editSockets");ui:choose("count",4,"val");ui:choose("color1","R","val");ui:click("link1");frame("crafting-manual-sockets");ui:click("use");ui:click("close")
	ui:choose("page","Target conditions")
	ui:click("targetPicker");ui:text("search","maximum Life");frame("crafting-target-picker");ui:click("choose")
	assert(#main.popups[1].controls.targetSummary.list>2,"Target picker did not add a target")
	ui:click("targetGroups");frame("crafting-target-groups");ui:click("newAlternative");ui:text("search","Fire Resistance");frame("crafting-alternative-table");ui:click("choose");frame("crafting-target-alternatives");ui:click("keepGroups")
	ui:click("addTarget");ui:click("targetGroups");ui:click("groupConditions");ui:choose("fractured","Fractured only");frame("crafting-group-conditions");ui:click("keep");ui:click("keepGroups");ui:click("targetConditions")
	ui:choose("corrupted","Must be twice corrupted");frame("crafting-twice-corrupted-goal");ui:click("keep")
	local summary={};for _,row in ipairs(main.popups[1].controls.targetSummary.list) do summary[#summary+1]=row[1] end;assert(StripEscapes(table.concat(summary," ")):find("Must be twice corrupted",1,true),"Twice-corrupted target was not shown")
	ui:click("targetConditions");assert(main.popups[1].controls.corrupted:GetSelValue()=="Must be twice corrupted","Twice-corrupted target was not retained");ui:choose("corrupted","Any corruption state");ui:text("minAbyssSockets","1");ui:click("keep")
	ui:click("targetConditions");assert(main.popups[1].controls.minAbyssSockets.buf=="1","Abyss socket target was not retained");ui:text("minAbyssSockets","")
	ui:text("socketColours","RGB");ui:choose("linkedColours","In one linked group");ui:text("minQuality","many");ui:click("keep")
	assert(main.popups[1].title=="Crafting targets" and main.popups[1].controls[1].label=="Enter a number for minimum quality","Invalid crafting property was not explained")
	frame("crafting-target-invalid-quality");ui:click("close");assert(main.popups[1].controls.minQuality.buf=="many","Invalid crafting input was lost")
	ui:text("minQuality","");ui:click("itemStats");ui:text("Armour","5");frame("crafting-native-stat-goals");ui:text("Armour","many");ui:click("keep");frame("crafting-native-stat-error");ui:click("close");ui:text("Armour","5");ui:click("keep");frame("targets");ui:click("keep")
	ui:choose("page","Simulate recipe")
	ui:choose("page","Craft settings");frame("settings");ui:click("inspectItem");frame("crafting-affix-inspector");ui:click("close")
	ui:click("compareItem");frame("crafting-item-diff");ui:click("close");ui:click("coverage");frame("crafting-coverage")
	local coverageText={};for _,line in ipairs(main.popups[1].controls.details.list) do coverageText[#coverageText+1]=line[1] end
	assert(StripEscapes(table.concat(coverageText," ")):find("Modifier data: 3.30.0.2",1,true),"Crafting coverage did not disclose the modifier version")
	ui:click("close");ui:choose("page","Simulate recipe")
	frame("simulation");ui:text("trials","12")
	ui:choose("page","Target conditions")
	ui:choose("page","Emulate item");ui:click("currency_chaos")
	ui:choose("page","Craft settings");ui:click("exact")
	local jobs=require("Modules.CraftingTasks")
	for i=1,100 do if not jobs.job then break end;jobs.tick(build) end
	assert(not jobs.job,"Action odds did not finish")
	ui:choose("page","Simulate recipe");ui:text("budget","2");ui:text("price","5");ui:text("baseCost","10");ui:click("simulate")
	for i=1,100 do if not jobs.job then break end;jobs.tick(build) end
	assert(not jobs.job,"Crafting simulation did not finish")
	frame("simulation-result");assert(#main.popups[1].controls.resultSummary.list>=4,"Detailed simulation results are missing")
	do
		local model=sim.model("Rarity: NORMAL\nSomatic Wand\nItem Level: 86");local row
		for _,entry in ipairs(require("Modules.CraftingModifiers").inspect(model,model.initial).rows) do if table.concat(entry.reasons," "):find("Cannot roll caster",1,true) then row=entry;break end end
		assert(row,"The wand's caster restriction was not explained");require("Classes.CraftingModifierControl").Open(model,model.initial,{choose=function() end});ui:text("search",row.id)
		local lines={};for _,line in ipairs(main.popups[1].controls.details.list) do lines[#lines+1]=line[1] end;assert(table.concat(lines," "):find("Cannot roll caster",1,true),"Modifier browser did not show the implicit restriction")
		frame("crafting-wand-implicit-block");ui:click("close")
	end
	ui:click("editRecipe");frame("crafting-recipe-cards");ui:click("flowGraph");frame("crafting-route-graph");ui:click("graphAll");frame("crafting-route-graph-all");ui:click("close");ui:click("recovery");ui:choose("action","stop","val");ui:text("notes","Inspect unwanted rolls before spending more");frame("crafting-failure-recovery");ui:click("keep")
	assert(main.popups[1].controls.failure:GetSelValueByKey("val")=="stop","Recovery policy was not shown as the failure behavior")
	ui:click("update");assert(main.popups[1].controls.failure:GetSelValueByKey("val")=="stop","Updating a step lost its recovery policy")
	ui:choose("failure","Step 1","label");ui:click("update");assert(main.popups[1].controls.graph.list[1].subtitle:find("Failure -> Step 1",1,true),"Choosing a failure route did not replace recovery")
	ui:choose("failure","restart","val");ui:click("update");assert(main.popups[1].controls.graph.list[1].subtitle:find("Restart",1,true),"Choosing restart did not update the recipe")
	ui:choose("failure","stop","val");ui:click("update");frame("crafting-recovery-route");ui:click("keep")
	do
		local model=sim.model("Rarity: NORMAL\nRusted Sword\nItem Level: 86");local saved
		require("Classes.CraftingRecipeControl").Open({steps={{method="alchemy"}},targets={},requirements={minAffixes=1}},{method="alchemy"},function(value) saved=value end,model)
		ui:click("addCurrency");ui:text("search","remove enchantments");frame("crafting-recipe-remove-enchant");ui:click("choose");ui:click("keep")
		assert(saved and saved.steps[2].method=="bench_remove_enchant","The recipe did not retain enchantment removal")
	end
	do
		local raw="Rarity: NORMAL\nPlate Vest\nItem Level: 86";local routeModel=sim.model(raw);local benchId=routeModel.bench[1].id
		local saved;require("Classes.CraftingRecipeControl").Open({steps={{method="alchemy"}},targets={},requirements={maxAffixes=0}},{method="alchemy"},function(value) saved=value end,routeModel)
		ui:click("addCurrency");ui:text("search","Orb of Fusing (experimental)");frame("crafting-recipe-socket-currency");local socketDetails={};for _,row in ipairs(main.popups[1].controls.details.list) do socketDetails[#socketDetails+1]=StripEscapes(row[1]) end;assert(table.concat(socketDetails," "):find("unverified",1,true),"Socket currency assumptions are missing");ui:click("close")
		ui:click("addCurrency");ui:text("search","Tainted Exalted Orb");do local details={};for _,row in ipairs(main.popups[1].controls.details.list) do details[#details+1]=StripEscapes(row[1] or "") end;assert(table.concat(details," "):find("unverified",1,true),"Tainted recipe warning should be visible") end;frame("crafting-recipe-tainted-currency");ui:click("close")
		ui:click("addCurrency");ui:text("search","Omen of Connections");do local details={};for _,row in ipairs(main.popups[1].controls.details.list) do details[#details+1]=StripEscapes(row[1] or "") end;local text=table.concat(details," ");assert(text:find("Omen of Connections",1,true) and text:find("Orb of Fusing",1,true),"Omen recipe should identify both resources") end;frame("crafting-recipe-socket-omen");ui:click("close")
		ui:click("addCurrency");ui:text("search","Chaos Orb");frame("crafting-recipe-currency-picker");ui:click("choose")
		ui:click("addCurrency");ui:text("search","Bench: reroll 3");ui:click("choose");assert(main.popups[1].controls.graph.list[3][1]:find("reroll 3 modifiers",1,true),"Bench reroll card lost its chosen count");frame("crafting-recipe-added-currencies")
		ui:click("flowGraph");assert(main.popups[1].controls.graphStep.list[3].label:find("reroll 3 modifiers",1,true),"Flow graph lost the bench reroll count");frame("crafting-recipe-currency-flow");ui:click("close")
		ui:click("addCurrency");ui:text("search","Deafening Essence of Greed")
		local details={};for _,row in ipairs(main.popups[1].controls.details.list) do details[#details+1]=row[1] end;assert(table.concat(details," "):find("Guaranteed on this base",1,true),"Essence picker omitted its guaranteed modifier")
		frame("crafting-recipe-essence-picker");ui:click("choose")
		ui:click("addCurrency");ui:text("search",benchId);ui:click("choose")
		ui:click("addCurrency");ui:text("search","reforge with a tagged modifier (minion)");do local c=main.popups[1].controls;local details={};for _,row in ipairs(c.details.list) do details[#details+1]=StripEscapes(row[1] or "") end;local text=table.concat(details," ");assert(c.choose:IsEnabled() and c.results.list[1].icon and text:find("200 Primal Crystallised Lifeforce",1,true) and text:find("3 Crystallised Rancour",1,true),"Minion reforge should show its ingredients and artwork") end;frame("crafting-recipe-harvest-minion");ui:click("close")
		ui:click("addCurrency");ui:text("search","Bestiary: prefix to suffix");ui:click("choose");ui:text("level","78");frame("crafting-recipe-beast-level");ui:click("cancel")
		ui:click("addCurrency");ui:text("search","Harvest: fire to cold resistance");do local c=main.popups[1].controls;local details={};for _,row in ipairs(c.details.list) do details[#details+1]=StripEscapes(row[1] or "") end;local text=table.concat(details," ");assert(c.choose:IsEnabled() and c.results.list[1].icon and text:find("300 Wild Crystallised Lifeforce",1,true) and text:find("300 Primal Crystallised Lifeforce",1,true),"Resistance conversion should show both ingredients") end;frame("crafting-recipe-harvest-resistance");ui:click("close")
		ui:click("addCurrency");ui:text("search","reforge with a tagged modifier (life)");ui:click("choose")
		local cards=main.popups[1].controls.graph;local cardTop=5*92;assert(cards.controls.scrollBar.offset<=cardTop and cards.controls.scrollBar.offset+cards.height>=cardTop+92,"New recipe step was not scrolled into view")
		frame("crafting-recipe-configured-actions")
		ui:click("addCurrency");ui:text("search","Fossil combination");ui:click("choose")
		local life,cold="Metadata/Items/Currency/CurrencyDelveCraftingLife","Metadata/Items/Currency/CurrencyDelveCraftingCold"
		ui:choose("fossil1",life,"id");ui:choose("fossil2",cold,"id");frame("crafting-recipe-fossil-configuration");ui:click("use")
		assert(main.popups[1].controls.graph.list[7][1]:find("Fossils:",1,true),"Recipe fossil combination was not labeled");frame("crafting-recipe-fossil-added")
		ui:text("attempts","2");ui:choose("condition","Until final targets and properties match");ui:choose("success","Step 2","label");ui:choose("failure","End recipe","label");ui:click("update")
		ui:text("attempts","0");ui:choose("success","Step 1","label");ui:click("update");ui:click("close")
		ui:choose("step",1,"val");ui:choose("step",7,"val")
		assert(main.popups[1].controls.attempts.buf=="2" and main.popups[1].controls.success:GetSelValueByKey("val")==2,"A rejected route update changed the saved step")
		ui:click("editFossils");assert(main.popups[1].controls.fossil1:GetSelValueByKey("id")==life and main.popups[1].controls.fossil2:GetSelValueByKey("id")==cold,"Fossil edit lost existing choices")
		local metallic="Metadata/Items/Currency/CurrencyDelveCraftingLightning";ui:choose("fossil2",metallic,"id");frame("crafting-recipe-fossil-edit");ui:click("use");frame("crafting-recipe-fossil-edited");ui:click("keep")
		assert(saved.steps[2].method=="chaos" and saved.steps[3].method=="bench_reroll" and saved.steps[3].count==3,"Direct recipe actions were not retained")
		assert(saved.steps[4].method=="essence" and saved.steps[5].modId==benchId and saved.steps[6].tag=="life","Configured recipe actions were not retained")
		assert(saved.steps[7].method=="fossil" and saved.steps[7].fossils[1]==life and saved.steps[7].fossils[2]==metallic,"Edited fossil combination was not retained")
		assert(saved.steps[7].maxAttempts==2 and saved.steps[7].onSuccess==2 and saved.steps[7].onFailure==8 and saved.steps[7].untilRequirements.maxAffixes==0,"Editing fossils lost routes or conditions")
		local result=sim.simulate(raw,saved,{trials=1,maxActions=3,forceFirstAction=true})
		assert(not next(result.transitionErrors) and result.meanActions==3,"The directly assembled recipe did not run all three actions")
		local essence=sim.perform(raw,saved.steps[4],1);assert(essence.state.rarity=="RARE","Direct Essence step did not execute")
		assert(sim.perform(raw,saved.steps[5],1).state.rarity=="MAGIC","Direct bench step did not execute")
		assert(sim.perform(raw,saved.steps[6],1,essence.state).state.rarity=="RARE","Direct Harvest step did not execute")
		assert(sim.perform(raw,saved.steps[7],1).state.rarity=="RARE","Direct fossil step did not execute")
		local socketRaw="Rarity: NORMAL\nPlate Vest\nItem Level: 86\nSockets: R-G B W-W R"
		local socketRecipe;require("Classes.CraftingRecipeControl").Open({steps={{method="alchemy"}},targets={},requirements={links=6}},{method="alchemy"},function(value) socketRecipe=value end,sim.model(socketRaw))
		ui:click("addCurrency");ui:text("search","Bestiary: maximum links");frame("crafting-recipe-beast-picker");ui:click("choose");ui:click("keep")
		assert(socketRecipe.steps[2].method=="beast_max_links","Bestiary recipe step was not retained")
		local socketRun=sim.simulate(socketRaw,socketRecipe,{trials=1,maxActions=2,forceFirstAction=true})
		assert(socketRun.successes==1 and not next(socketRun.transitionErrors),"The saved Bestiary recipe did not link the item")
		local voriciRecipe;require("Classes.CraftingRecipeControl").Open({steps={{method="alchemy"}},targets={},requirements={minQuality=30}},{method="alchemy"},function(value) voriciRecipe=value end,sim.model(socketRaw))
		ui:click("addCurrency");ui:text("search","Vorici: best of 25");frame("crafting-recipe-vorici-picker");ui:click("choose");ui:click("keep")
		assert(voriciRecipe.steps[2].method=="vorici_socket_colours","Vorici service was not retained")
		local voriciRun=sim.simulate(socketRaw,voriciRecipe,{trials=1,maxActions=2,forceFirstAction=true})
		assert(not next(voriciRun.transitionErrors) and voriciRun.meanActions==2,"The saved Vorici recipe did not execute")
		local countRecipe;require("Classes.CraftingRecipeControl").Open({steps={{method="alchemy"}},targets={},requirements={sockets=6}},{method="alchemy"},function(value) countRecipe=value end,sim.model(socketRaw))
		ui:click("addCurrency");ui:text("search","Vorici: best of 100");frame("crafting-recipe-vorici-count");ui:click("choose");ui:click("keep")
		assert(countRecipe.steps[2].method=="vorici_socket_count","Vorici socket service was not retained")


		local talismanRaw="Rarity: NORMAL\nChieftain Talisman\nItem Level: 86";local talismanRecipe
		require("Classes.CraftingRecipeControl").Open({steps={{method="alchemy"}},targets={},requirements={minAffixes=4}},{method="alchemy"},function(value) talismanRecipe=value end,sim.model(talismanRaw))
		ui:click("addCurrency");ui:text("search","imprint rare Talisman");frame("crafting-recipe-talisman-imprint");ui:click("choose");ui:click("keep")
		assert(talismanRecipe.steps[2].method=="beast_talisman_imprint","Rare Talisman imprint was not kept in the recipe")
		local beastRecipe;require("Classes.CraftingRecipeControl").Open({steps={{method="alchemy"}},targets={},requirements={minAffixes=4}},{method="alchemy"},function(value) beastRecipe=value end,routeModel)
		ui:click("addCurrency");ui:text("search","Bestiary: prefix to suffix");ui:click("choose");ui:text("level","78");ui:click("use")
		assert(main.popups[1].controls.editBeast:IsShown(),"Added Bestiary swap should offer level editing");ui:click("editBeast");ui:text("level","76");ui:click("use");frame("crafting-recipe-beast-edited");ui:click("keep")
		assert(beastRecipe.steps[2].method=="beast_prefix_suffix" and beastRecipe.steps[2].beastLevel==76,"Edited beast level should be retained")
		local replaced;require("Classes.CraftingRecipeControl").Open({steps={{method="alchemy",maxAttempts=2,onSuccess=1,onFailure=2,onFailureAction="stop",recoveryNotes="Keep this note",untilRequirements={minAffixes=5}}},targets={},requirements={minAffixes=6}},{method="chaos"},function(value) replaced=value end,routeModel)
		ui:click("replace");ui:click("keep");local step=replaced.steps[1]
		assert(step.method=="chaos" and step.maxAttempts==2 and step.onSuccess==1 and step.onFailure==2 and step.onFailureAction=="stop" and step.recoveryNotes=="Keep this note" and step.untilRequirements.minAffixes==5,"Replacing action lost routes or conditions")
		local finished;local input={steps={{method="alchemy",onSuccess=3,onFailure=3},{method="chaos",onSuccess=1}},targets={},requirements={maxAffixes=0}}
		require("Classes.CraftingRecipeControl").Open(input,{method="transmute"},function(value) finished=value end,routeModel)
		ui:click("add");ui:click("addCurrency");ui:text("search","Chaos Orb");ui:click("choose")
		ui:click("addCurrency");ui:text("search","Fossil combination");ui:click("choose");ui:choose("fossil1",life,"id");ui:click("use")
		frame("crafting-recipe-append-finish");ui:click("keep")
		assert(finished.steps[1].onSuccess==6 and finished.steps[1].onFailure==6 and finished.steps[2].onSuccess==1 and finished.steps[2].onFailure==nil,"Appending changed existing route destinations")
		local stopped=sim.simulate(raw,finished,{trials=1,maxActions=5,forceFirstAction=true});assert(stopped.meanActions==1 and not next(stopped.transitionErrors),"An explicit finish route executed an appended step")
	end
	ui:click("distribution");frame("simulation-distribution");assert(main.popups[1].controls.successCard and main.popups[1].controls.medianSpend and main.popups[1].controls.veryUnluckySpend and main.popups[1].controls.moreTrials,"Simulation result cards are missing");ui:click("charts");frame("crafting-success-chart");ui:choose("mode","Executed actions per trial");frame("crafting-executed-chart");ui:choose("mode","Spending per trial");frame("crafting-spending-chart");ui:click("copy");assert(ui.clipboard:find("route,value,percent,count,trials",1,true));ui:click("close");ui:click("sample");frame("crafting-sampled-outcome");ui:click("close");ui:click("moreTrials")
	for i=1,100 do if not jobs.job then break end;jobs.tick(build) end
	assert(not jobs.job and main.popups[1].controls.trials.buf=="48","More trials did not rerun the captured setup")
	frame("simulation-refined")
	ui:click("simulate");ui:click("cancelJob");assert(not jobs.job);frame("simulation-cancelled")
	ui:click("compareRecipes");frame("crafting-recipe-comparison");ui:click("run")
	-- The cooperative job yields on a CPU-time deadline, so a fixed 200 slices
	-- can be too short on slower hosts even when comparison is still advancing.
	for i=1,2000 do if not jobs.job then break end;jobs.tick(build) end
	assert(not jobs.job,"Recipe comparison did not finish");frame("crafting-comparison-result");ui:click("charts");frame("crafting-comparison-chart");ui:click("close");ui:click("close")
	assert(main.popups[1].controls.trials.buf=="48","Native character events did not reach the edit control")
	ui:click("close");main.popups={}
	ui:bind(build);ui:click("nav_crafting");ui:click("native");ui:choose("page","Emulate item");ui:click(workspace.controls.currency_chaos:IsEnabled() and "currency_chaos" or "currency_alchemy");ui:click("item");ui:click("keepWorking")
	assert(build.savers.CraftingProjects.projects[1].run,"Working craft was not kept: "..tostring(main.popups[1] and main.popups[1].controls[1] and main.popups[1].controls[1].label))
	frame("crafting-checkpoint")
	workspace.craftDrafts={};workspace.cache.crafting=nil;workspace.drafts.crafting=nil;workspace:Show("crafting");ui:click("native")
	assert(workspace.controls.undo:IsEnabled(),"Saved working craft did not restore undo")
	frame("crafting-resumed")
	ui:click("nav_journey");frame("journey-empty")
	ui:click("nav_ai")
	bridge.calculateBatch(build,{id="guide-test",kind="leveling",baseRevision=bridge.revision(build),stages={{title="Early links",level=12,operations={}},{title="Later links",level=24,operations={}}}})
	ui:click("candidates");frame("journey-calculated-stages");ui:click("keepLeveling")
	assert(#build.savers.BuildJourney.data.stages==2,"Calculated leveling stages were not kept")
	frame("journey-captured-guide")
	ui:click("page4");ui:click("add");frame("journey-resource-editor")
	ui:text("title","Chaos Orbs");ui:text("unit","orbs");ui:click("keep")
	local resource=build.savers.BuildJourney.data.resources[1].id
	ui:click("record");ui:text("amount","100");ui:text("note","Starting stash");frame("journey-ledger-editor");ui:click("keep")
	assert(require("Modules.BuildJourney").budget(build.savers.BuildJourney.data)[resource].owned==100)
	frame("journey-budget")
	ui:click("page3");ui:click("add");ui:text("title","Final life helmet");ui:choose("slot","Helmet");ui:choose("route","craft")
	ui:choose("resourceId",resource,"val");ui:text("estimate","60");ui:choose("reserve","yes");ui:choose("projectId",build.savers.CraftingProjects.projects[1].id,"val")
	frame("journey-gear-editor");ui:click("keep");frame("journey-gear")
	ui:click("pasteTarget");ui:text("text","Rarity: RARE\nWishlist Hat\nIron Hat\nItem Level: 86\n+100 to maximum Life");frame("journey-paste-target");ui:click("keep")
	ui:click("expandDetails");frame("journey-expanded-details");ui:click("expandDetails")
	local splitter=workspace.controls.detailSplitter;local sx,sy=splitter:GetPos();local oldHeight=select(2,workspace.controls.details:GetSize())
	ui.cursorX,ui.cursorY=sx+40,sy+4;ui:dispatch(build,{{type="KeyDown",key="LEFTBUTTON"}});ui.cursorY=ui.cursorY-16;ui:dispatch(build,{{type="KeyUp",key="LEFTBUTTON"}})
	assert(select(2,workspace.controls.details:GetSize())>oldHeight,"Journey detail splitter did not resize the panel");frame("journey-resized-details")
	local gearId=build.savers.BuildJourney.data.wishlist[1].id
	local project=copyTable(build.savers.CraftingProjects.projects[1]);project.targetItem="Rarity: RARE\nJourney Hat\nIron Hat\nItem Level: 86\n+100 to maximum Life";build.savers.CraftingProjects:Upsert(project)
	ui:click("measure")
	for i=1,2000 do ui:frame();if not require("Modules.JourneyUpgrades").job then break end end
	assert(require("Modules.JourneyUpgrades").current(build).entries[gearId].status=="calculated","Native upgrade measurement did not finish")
	ui:choose("sort","LifeUnreserved","val");ui:click("perCost");frame("journey-upgrade-ranking")
	ui:click("compareAll");frame("journey-comparison-table");ui:click("choose")
	ui:click("reviewIssues");frame("journey-requirement-reasons");ui:click("close")
	ui:click("edit");ui:click("notesExpand");ui:text("text","Record exact target and price source");ui:click("keep");ui:click("keep");frame("journey-stale-ranking")
	local background=copyTable(build.savers.BuildJourney.data)
	for index=2,4 do local extra=copyTable(background.wishlist[1]);extra.id="background-"..index;extra.title="Background candidate "..index;background.wishlist[#background.wishlist+1]=extra end
	build.savers.BuildJourney:Replace(background);workspace:Show("journey",{page="Gear"});ui:click("measure");ui:click("nav_atlas")
	for i=1,2000 do ui:frame();if not require("Modules.JourneyUpgrades").job then break end end
	assert(workspace.page=="atlas","Finishing background upgrade measurements stole navigation")
	frame("journey-background-navigation")
	background.wishlist={background.wishlist[1]};build.savers.BuildJourney:Replace(background);ui:click("nav_journey");ui:click("page3")
	ui:click("page5");ui:click("add");ui:text("title","Campaign links");ui:text("level","12");ui:text("gems","Fireball + Combustion")
	ui:text("passives","Take nearby life");ui:text("quests","Finish Act 1");ui:text("transition","After finding a linked item");frame("journey-stage-editor")
	ui:click("gemsExpand");ui:text("text","Fireball + Combustion\nKeep an extra gem leveling");frame("journey-guide-text");ui:click("keep");ui:click("keep");frame("journey-leveling")
	ui:click("openLink");local quests=main.popups[1].controls.quests;local qx,qy=quests:GetPos();ui:clickAt(qx+30,qy+10);frame("journey-quest-guide");ui:click("close")
	assert(build.savers.BuildJourney.data.stages[3].questChecks[1]=="Finish Act 1","Quest completion was not kept")
	ui:click("page2");ui:click("add");ui:text("title","Craft the helmet");ui:choose("wishlistId",gearId,"val");ui:choose("projectId",build.savers.CraftingProjects.projects[1].id,"val")
	frame("journey-milestone-editor");ui:click("keep");frame("journey-roadmap")
	ui:click("complete");assert(build.savers.BuildJourney.data.milestones[1].done);ui:click("complete")
	ui:click("add");ui:text("title","Try the finished build");ui:click("dependencies");ui:text("search","Craft the helmet");frame("journey-prerequisite-picker")
	local picker=main.popups[1].controls.entries;local px,py=picker:GetPos();ui:clickAt(px+40,py+12);ui:click("keep");ui:click("keep")
	assert(build.savers.BuildJourney.data.milestones[2].dependencies[1]==build.savers.BuildJourney.data.milestones[1].id,"Prerequisite picker lost its selection")
	frame("journey-linked-progress")
	local milestones=workspace.controls.entries;local lx,ly=milestones:GetPos();ui:clickAt(lx+30,ly+10);ui:click("complete")
	assert(build.savers.BuildJourney.data.milestones[1].done and not build.savers.BuildJourney.data.milestones[2].done,"Clicking a different Journey entry did not select it")
	frame("journey-completed-progress");ui:click("complete")
	local entryX,entryY=workspace.controls.entries:GetPos();ui:clickAt(entryX+30,entryY+10)
	ui:key("DOWN");assert(workspace.controls.entries.selectedKey==2,"Keyboard navigation did not select the next milestone");frame("journey-keyboard-selection");ui:key("UP")
	ui:click("page1");frame("journey-overview");ui:click("openLink")
	assert(workspace.page=="crafting" and workspace.controls.keepWorking,"Journey link did not open the working craft")
	ui:click("nav_journey");ui.keys.ALT=true;ui:key("1");ui:key("4");ui.keys.ALT=nil
	assert(workspace.page=="journey","Alt+4 did not open Journey")
	ui:click("nav_text");frame("planning-large-text");ui:click("nav_text")
	ui:click("nav_tools");ui:text("search","bundle");ui:click("choose");frame("planning-bundle");ui:click("export");local bundle=ui.clipboard;assert(require("Modules.PlanningBundle").import(bundle).contents.checkpoints>=1,"Bundle omitted kept craft")
	ui:click("paste");frame("planning-bundle-inspected");bridge.prepared=nil;ui:click("review");frame("planning-bundle-review");ui:click("close");assert(main.modes.BUILD==build,"Bundle review changed the active build before Apply");bridge.prepared=nil

	ui:click("page5");ui:click("remove");ui:click("confirm");assert(#build.savers.BuildJourney.data.stages==2,"Guide stage removal failed")
	ui:click("nav_build")
	newBuild()
	local input=build.configTab.input
	input.simulateRecovery=true;input.recoverySimulationTrials=2;input.recoverySimulationWindow=3
	input.enemyDamageType="Untyped";input.enemyIsBoss="None";input.enemySpeed=1000;input.enemyCritChance=0
	input.enemyColdDamage="20";input.customMods="+3000 to maximum Life\n+60% to Cold Resistance"
	build.configTab:BuildModList();runCallback("OnFrame")
	local actor=build.calcsTab.calcsEnv.player
	assert(actor.recoverySimulationTrace and #actor.recoverySimulationTrace.points>1)
	build.calcsTab:OpenEncounterWorkspace();frame("encounter-workspace");ui:choose("preset",7,"val");ui:click("usePreset");frame("survival-scenario-assumptions");ui:click("create");assert(build.configTab.input.recoverySimulationColdDot==4,"Continuous damage preset did not preserve its stated scale");ui:click("chartUnits");frame("encounter-actual-values");ui:click("series_Life");ui:click("series_Mana");frame("encounter-series-hidden");ui:click("emptyLanes");frame("encounter-empty-lanes");ui:click("close")
	ui.cursorX,ui.cursorY=300,120
	ui:frame(function() build.calcsTab.controls.breakdown:DrawEncounterTimeline(16,16,{width=size[1]-32,timeline=actor.recoverySimulationTrace}) end)
	ui.regions={{0,0,size[1],size[2]}};ui:write(directory.."/"..size[1].."-recovery-hover.json");frames=frames+1
	ui.cursorX,ui.cursorY=-100,-100
	ui:frame(function() build.calcsTab.controls.breakdown:DrawEncounterTimeline(16,16,{width=size[1]-32,timeline=actor.recoverySimulationTrace}) end)
	ui.regions={{0,0,size[1],size[2]}}
	ui:write(directory.."/"..size[1].."-recovery-timeline.json");frames=frames+1
	newBuild();ui:bind(build)
	assert(not main.popups[1],"Preview setup: "..tostring(main.popups[1] and main.popups[1].title).." | "..tostring(main.popups[1] and main.popups[1].controls[1] and main.popups[1].controls[1].label))
	assert(build.spec.treeVersion=="3_30","New builds should default to 3.30")
	ui:choose("versionSelect","3_29","value");ui:click("convert")
	ui:choose("versionSelect","3_30_preview","value");frame("covens-convert-preview");ui:click("convert")
	assert(build.spec.treeVersion=="3_30_preview","Native tree conversion did not select the preview")
	frame("covens-passive-tree");assert(table.concat(build.controls.warnings.lines," "):find("preview",1,true),"Preview warning missing")
	ui:click("atlas");ui:text("search","Massing Forces");ui:click("find");ui:click("allocate");frame("covens-atlas-tree")
	assert(build.planningWorkspace.controls.canvas.tree.maxPoints==150,"Atlas preview lost its 150 point budget")
	ui:text("search","Secrets Unveiled");ui:click("find");ui:click("allocate");assert(build.planningWorkspace.controls.allocate:IsEnabled() and build.planningWorkspace.controls.allocate.label=="Choose effect","Allocated choice node cannot select an effect")
	ui:click("allocate");frame("atlas-effect-picker");ui:click("choose");frame("atlas-effect-selected")
	local selectedAtlas=build.planningWorkspace.cache.atlas.layout.snapshot();assert(#selectedAtlas.choices==1 and selectedAtlas.choices[1].node==45404,"Selected Atlas effect was not retained")
	ui:click("undo");assert(#(build.planningWorkspace.cache.atlas.layout.snapshot().choices or {})==0,"Undo did not restore the unselected node");ui:click("redo")
	ui:text("search","Threadbare");ui:click("find");ui:click("allocate");ui:click("allocate")
	local picker={};for _,row in ipairs(main.popups[1].controls.results.list) do picker[#picker+1]=StripEscapes(row[1] or "") end
	assert(table.concat(picker," "):find("Option 1 | Breach",1,true) and not table.concat(picker," "):find("BreachThread",1,true),"Atlas effect labels expose internal markup")
	local choiceDetail={};for _,row in ipairs(main.popups[1].controls.details.list) do choiceDetail[#choiceDetail+1]=StripEscapes(row[1] or "") end
	assert(table.concat(choiceDetail," "):find("Threads found in your Maps cannot be of type",1,true),"Atlas effect picker omitted the node's restriction")
	frame("atlas-thread-choice");ui:click("choose");frame("atlas-thread-selected")
	local detail={};for _,row in ipairs(build.planningWorkspace.controls.details.list) do detail[#detail+1]=StripEscapes(row[1] or "") end
	assert(table.concat(detail," "):find("Threads found in your Maps cannot",1,true),"Atlas node text was not rendered readably")
	ui:text("search","Dextral Threads");ui:click("find");ui:click("allocate");ui:click("allocate");ui:click("choose");ui:click("targets")
	local conflict={};for _,row in ipairs(main.popups[1].controls.details.list) do conflict[#conflict+1]=StripEscapes(row[1] or "") end
	assert(table.concat(conflict," "):gsub("%s+"," "):find("conflicting with Dextral Threads",1,true),"Conflicting Atlas Thread effects were not explained")
	frame("atlas-thread-conflict");ui:click("close")
	ui:click("progression");ui:click("strategyTab");ui:text("maps","Run Strand Maps");ui:click("mapTier");ui:text("search","Map (Tier 16)");frame("atlas-map-tier-picker");ui:click("choose");assert(main.popups[1].controls.maps.buf:find("Map (Tier 16)",1,true),"Map tier picker did not update strategy");frame("atlas-map-tier-selected");ui:text("avoid","Beach Map");ui:click("keep")
	ui:click("keep");assert(build.savers.AtlasPlans.plans[1].version=="3.30.0-preview" and #build.savers.AtlasPlans.plans[1].choices==3,"Atlas preview version or effects not retained")
	ui:click("nav_journey");ui:click("page4");ui:click("add");ui:text("title","Pristine Fossils");ui:click("keep")
	local function filterTool(query)
		ui:click("manage");ui:text("search",query);ui:click("choose")
	end
	ui:click("nav_filters");frame("filter-empty")
	ui:click("manage");frame("filter-empty-profile-tools");local emptyToolIds={};for _,row in ipairs(main.popups[1].controls.results.list) do if row.entry then emptyToolIds[row.entry.id]=true end end;local emptyToolCount=0;for _ in pairs(emptyToolIds) do emptyToolCount=emptyToolCount+1 end;assert(emptyToolCount==2 and emptyToolIds.new and emptyToolIds.import,"Empty filter tools offered actions without a profile");ui:click("close")
	ui:click("create2");ui:text("title","Covens pickup plan");frame("filter-profile")
	do
		local profile=build.planningWorkspace.cache.filters.layout.snapshot().data.profiles[1]
		profile.rules={{id="order-a",title="Match A",text='Show\n BaseType == "Iron Hat"',enabled=true},
			{id="order-hidden",title="Other rule",text='Show\n BaseType == "Leather Belt"',enabled=true},
			{id="order-c",title="Match C",text='Show\n BaseType == "Iron Hat"',enabled=true}}
		ui:click("viewCustomize");ui:choose("source","My rules");ui:text("search","Match");local list=build.planningWorkspace.controls.rules
		assert(#list.list==2,"Filtered rule fixture did not show two rules")
		local function ids() local result={};for _,rule in ipairs(profile.rules) do result[#result+1]=rule.id end;return table.concat(result,",") end
		assert(list.selectedKey=="order-a","Initial visible selection was not available to keyboard navigation")
		build.planningWorkspace.body:SelectControl(list);ui:key("DOWN")
		assert(build.planningWorkspace.cache.filters.layout.snapshot().rule=="order-c","Down did not select the next visible rule")
		ui.keys.ALT=true;ui:key("UP");ui.keys.ALT=nil
		assert(ids()=="order-c,order-a,order-hidden","Alt+Up did not move before the visible target: "..ids())
		list=build.planningWorkspace.controls.rules;assert(list.selectedKey=="order-c","Reordering lost keyboard selection")
		assert(build.planningWorkspace.body.selControl==list,"Reordering lost keyboard focus")
		ui.keys.ALT=true;ui:key("DOWN");ui.keys.ALT=nil
		assert(ids()=="order-a,order-c,order-hidden","Alt+Down did not move after the visible target: "..ids())
		list=build.planningWorkspace.controls.rules
		local x,y=list:GetPos();ui:clickAt(x+30,y+20)
		assert(#main.popups==0 and build.planningWorkspace.cache.filters.layout.snapshot().rule=="order-a","Single click did not select the rule without opening its editor")
		ui:clickAt(x+30,y+20,true);assert(#main.popups==1,"Double click did not open the rule editor");ui:click("cancel")
		ui:dragAt(x+30,y+2+76+20,0,-76,"LEFTBUTTON")
		assert(ids()=="order-c,order-a,order-hidden","Dragging did not move the rule before the visible target: "..ids())
		frame("filter-rule-dragged");assert(build.planningWorkspace.controls.down:IsEnabled(),"The selected rule cannot move down")
		ui:click("down");assert(ids()=="order-a,order-c,order-hidden","Arrow did not move after the next visible rule: "..ids())
		assert(not build.planningWorkspace.controls.down:IsEnabled(),"The last visible rule can move down")
		frame("filter-rule-filtered-order");profile.rules={};ui:click("viewOverview")
	end
	do
		local rule={id="rare-example",title="Rare modifiers",text='Show\n Rarity Rare\n HasExplicitMod >=2 "Haast" "Ephij"'}
		local example=require("Modules.LootFilterLibrary").sample(rule);assert(example.BaseType=="Iron Hat" and example.Identified and #example.HasExplicitMod==2,"Generic rare example did not use equipment and matching modifiers")
		require("Classes.LootFilterControl").EditRule(rule,function() end);assert(main.popups[1].controls.textHex.buf=="FFFF77FF","Rare example did not show its default text colour");frame("filter-rare-example");ui:click("cancel")
	end
	do
		local saved;require("Classes.LootFilterControl").Conditions({id="count",title="Modifier count",text='Hide\n HasExplicitMod >=2 "Haast" "Ephij"'},function(rule) saved=rule end)
		frame("filter-modifier-count-editor");ui:click("keepRule")
		assert(saved.text:find('HasExplicitMod >=2 "Haast" "Ephij"',1,true),"Rule editor separated the modifier count operator")
	end
	do
		local saved;local raw='Hide\n HasExplicitMod >=2 == "Polar" "Shocking"'
		require("Classes.LootFilterControl").Conditions({id="exact-count",title="Exact modifier count",text=raw},function(rule) saved=rule end)
		frame("filter-exact-modifier-count-editor");ui:click("keepRule")
		assert(saved.text:find('HasExplicitMod >=2 == "Polar" "Shocking"',1,true),"Rule editor changed the exact marker")
		local parser=require("Modules.LootFilterParser");local result=parser.simulate(parser.parse(saved.text.."\nShow"),{Identified=true,HasExplicitMod={"of the Polar Bear","Shocking"}})
		assert(result.status=="unknown" and result.reasons[1]:find("exact%-match operator"),"Exact modifier count preview must be uncertain")
	end
	do
		local control=require("Classes.LootFilterControl");local original={id="silent",title="Silent",text='Show\n HasExplicitMod >=2 "Haast" "Ephij"'}
		local function check(rule) assert(rule.text:find('HasExplicitMod >=2 "Haast" "Ephij"',1,true) and rule.text:find('PlayAlertSound None',1,true) and rule.text:find('CustomAlertSound "None"',1,true),"Silent rule lost its conditions or disable actions") end
		local saved;control.EditRule(original,function(rule) saved=rule end);ui:choose("sound","Silent");ui:click("keepRule");check(saved)
		saved=nil;control.EditRule(original,function(rule) saved=rule end);ui:click("effects");ui:choose("soundKind","Silent");ui:click("keep");ui:click("keepRule");check(saved)
		saved=nil;control.Conditions(original,function(rule) saved=rule end);ui:choose("sound","Silent");ui:click("keepRule");check(saved)
	end
	do
		local effects=require("Classes.LootFilterEffectsControl")
		local sample={BaseType="Iron Hat"}
		for _,case in ipairs({{styles={PlayAlertSound={"4"}},volume=50},{styles={CustomAlertSound={"test.wav"}},volume=100},{styles={PlayAlertSoundPositional={"5","80"}},volume=80},{styles={PlayAlertSound={"4","30"},CustomAlertSoundOptional={"test.wav","120"}},volume=120}}) do
			local saved;local controls=effects.Open(case.styles,sample,function(value) saved=value end)
			assert(controls.volumeLabel.label()=="^7Alert volume: "..case.volume,"Sound editor displayed an incorrect default volume")
			if case.styles.PlayAlertSound and case.styles.CustomAlertSoundOptional then assert(controls.alertId:GetSelValueByKey("val")==4,"Sound editor lost the numbered fallback identity") end
			ui:click("keep");for key,original in pairs(case.styles) do assert(saved[key] and #saved[key]==#original and saved[key][1]==original[1] and saved[key][2]==original[2],"Opening sound effects changed an untouched alert") end
		end
		local selected;effects.Open({PlayAlertSound={"4","30"},CustomAlertSoundOptional={"test.wav","120"}},sample,function(value) selected=value end)
		ui:choose("soundKind","Numbered alert");ui:click("keep");assert(selected.PlayAlertSound[1]=="4","Switching to a numbered alert changed the fallback identity")
		local saved;local controls=effects.Open({PlayAlertSound={"None"},CustomAlertSound={"None"}},sample,function(value) saved=value end)
		controls.volume:SetVal(0);ui:click("keep")
		assert(#saved.PlayAlertSound==1 and #saved.CustomAlertSound==1,"Changing volume modified disabled alerts")
	end
	ui:click("manage");ui:text("search","Included filter files");ui:click("choose")
	ui:text("name","rules.filter");ui:text("text",'Hide\n BaseType "Iron Hat"');frame("filter-included-files");ui:click("keep")
	assert(build.planningWorkspace.cache.filters.layout.snapshot().data.profiles[1].importFiles[1].name=="rules.filter","Included filter file was not kept in the draft")
	do
		local path=os.tmpname()..".filter";local file=assert(io.open(path,"wb"));file:write('Show\n BaseType "Iron Hat"');file:close()
		local name=path:match("([^/\\]+)$");local original=NewFileSearch
		_G.NewFileSearch=function(_,folders) if folders then return nil end;return {GetFileName=function() return name end,NextFile=function() return false end,Close=function() end} end
		local saved;require("Classes.LootFilterImportControl").Open(require("Modules.LootFilters").profile("browse-ui","Browse UI"),function(files) saved=files end)
		ui:text("path",path);ui:click("browseFile");ui:text("search",name);frame("filter-browse-local");ui:click("choose");ui:click("keep")
		_G.NewFileSearch=original;os.remove(path);assert(saved and saved[1].name==name and saved[1].text:find("Iron Hat",1,true),"Selected local filter was not loaded")
	end
	do
		local profile=require("Modules.LootFilters").profile("import-picker-ui","Import picker")
		profile.template='Import "outer.filter"\nShow';profile.importFiles={{name="outer.filter",text='Import "inner.filter"\nImport "outer.filter"\nHide'}}
		local saved;require("Classes.LootFilterImportControl").Open(profile,function(files) saved=files end)
		ui:click("findImports");frame("filter-unresolved-imports");ui:text("search","inner.filter");ui:click("choose")
		assert(main.popups[1].controls.name.buf=="inner.filter","Missing import did not populate its exact filename");frame("filter-unresolved-selected");ui:click("keep")
		assert(saved and #saved==1,"Selecting a missing name silently created an empty file")
		require("Classes.LootFilterImportControl").Open(profile,function(files) saved=files end);ui:click("findImports");ui:text("search","outer.filter");ui:click("choose")
		assert(main.popups[1].controls.name.buf=="outer.filter" and main.popups[1].controls.text.buf:find('Import "outer.filter"',1,true),"Circular import did not open its existing file")
		frame("filter-circular-import-selected");ui:click("cancel")
	end
	ui:choose("mode","Ruthless");frame("filter-ruthless");ui:click("viewStyle");ui:click("globalStyle");ui:click("textColorPick");ui:text("a","0");assert(not main.popups[1].controls.keep:IsEnabled(),"Ruthless picker allowed invisible text");ui:text("a","80");frame("filter-colour-ruthless");ui:click("cancel");ui:click("close");ui:click("viewOverview");ui:choose("mode","Normal")
	ui:click("generate");frame("filter-build-targets")
	local foundBudget=false
	for i=1,2000 do
		ui:frame();local profile=build.planningWorkspace.cache.filters.layout.snapshot().data.profiles[1]
		for _,rule in ipairs(profile.rules) do if rule.title=="Pristine Fossil" and rule.origin and rule.origin:find("budget:",1,true) then foundBudget=true end end
		if foundBudget then break end
	end
	assert(foundBudget,"Saved fossil budget did not generate a linked filter pickup")
	assert(main.popups[1] and main.popups[1].title=="Review build pickups","Layout warning was not shown after generation")
	frame("filter-map-layout-warning");ui:click("close")
	local profile=build.planningWorkspace.cache.filters.layout.snapshot().data.profiles[1];for _,rule in ipairs(profile.rules) do assert(rule.title~="Beach Map","Avoided Atlas map became a pickup") end
	frame("filter-budget-fossil-pickup")
	ui:click("viewCustomize");ui:choose("source","My rules");ui:text("search","Map (Tier 16)")
	local mapFound=false;for _,row in ipairs(build.planningWorkspace.controls.rules.list) do if row.entry and row.entry.rule.title=="Map (Tier 16)" then mapFound=true end end
	assert(mapFound,"Explicit Atlas map tier did not produce a visible filter pickup")
	local detail={};for _,row in ipairs(build.planningWorkspace.controls.detail.list) do detail[#detail+1]=row[1] or "" end
	assert(table.concat(detail," "):find("Linked to Atlas: "..build.savers.AtlasPlans.plans[1].title,1,true),"Atlas source title was not shown")
	frame("filter-atlas-map-pickup")
	local removedPlan=copyTable(build.savers.AtlasPlans.plans[1]);build.savers.AtlasPlans:Remove(removedPlan.id)
	ui:click("openSource");assert(main.popups[1] and main.popups[1].title=="Linked source" and main.popups[1].controls[1].label:find("Refresh build pickups",1,true),"Missing source did not explain how to recover")
	frame("filter-missing-source");ui:click("close");assert(build.planningWorkspace.page=="filters","Missing source lost the filter draft")
	build.savers.AtlasPlans:Upsert(removedPlan);ui:text("search","")
	ui:click("viewCustomize");ui:choose("source","Base filter");frame("filter-base-catalog")
	ui:text("search","Gold");local goldFound=false
	for _,row in ipairs(build.planningWorkspace.controls.rules.list) do if row.entry and row.entry.rule.title=="Gold" then
		assert(row.entry.category=="Currency" and row.entry.sample.Class=="Gold","Gold catalogue entry has the wrong category or sample class");goldFound=true
	end end
	assert(goldFound,"Gold was not found in the base filter catalogue")
	ui:text("search","Expedition Logbook");local logbookFound=false
	for _,row in ipairs(build.planningWorkspace.controls.rules.list) do if row.entry and row.entry.rule.title=="Expedition Logbook" then
		assert(row.entry.category=="League items" and row.entry.sample.Class=="Expedition Logbooks","Logbook catalogue entry has the wrong category or sample class");logbookFound=true
	end end
	assert(logbookFound,"Expedition Logbook was not found in the base filter catalogue")
	ui:text("search","Chaos Orb");frame("filter-search")
	ui:click("edit");frame("filter-appearance");ui:click("textHexPick");frame("filter-colour-wheel");frame("filter-colour-preset-hover","preset7")
	local colourWheel=main.popups[1].controls.wheel;local wx,wy=colourWheel:GetPos();ui:dragAt(wx+192,wy+128,-64,64,"LEFTBUTTON");frame("filter-colour-dragged");ui:text("hex","FFE0A0FF");ui:click("keep");assert(main.popups[1].controls.textHex.buf=="FFE0A0FF","Rule picker did not return the selected colour")
	ui:text("backgroundHex","101820FF");ui:choose("sound","Alert 6");ui:choose("icon","Diamond");ui:click("effects");ui:choose("iconShape","Moon");ui:choose("iconColor","Purple");ui:choose("iconSize","Large","label");ui:choose("beam","Purple");ui:choose("beamDuration","Temporary");frame("filter-sound-and-effects");ui:click("keep");ui:click("keepRule");frame("filter-base-override")
	do
		local saved;local rule={id="implicit-alpha",title="Imported background",text='Show\n BaseType == "Chaos Orb"\n SetBackgroundColor 10 20 30'}
		require("Classes.LootFilterAppearance").Open(rule,function(value) saved=value end,function() end)
		assert(main.popups[1].controls.backgroundHex.buf=="0A141EF0");frame("filter-background-default-alpha")
		ui:click("backgroundHexPick");assert(main.popups[1].controls.hex.buf=="0A141EF0");frame("filter-background-default-picker");ui:click("keep");ui:click("keepRule")
		assert(saved and saved.text:find("SetBackgroundColor 10 20 30 240",1,true))
	end
	ui:click("add");ui:text("title","Keep crafting helmets");ui:click("textHexColor1");ui:click("borderHexColor2");ui:click("conditions");frame("filter-rule-editor")
	ui:click("addCondition");ui:choose("c2key","ItemLevel");ui:choose("c2op",">=");ui:text("c2values","83");ui:click("addCondition");ui:choose("c3key","SocketGroup");ui:choose("c3op",">=");ui:text("c3values","5GGG");ui:click("keepRule");frame("filter-custom-rule")
	ui:click("toggle");frame("filter-disabled-rule");ui:click("toggle")
	ui:click("sampleEdit");frame("filter-drop-properties")
	ui:text("BaseType","Iron Hat");ui:text("Class","Helmets");ui:text("Rarity","Rare");ui:text("ItemLevel","86");ui:text("DropLevel","1");ui:text("Width","2");ui:text("Height","2");ui:choose("Identified","Yes");ui:choose("TwiceCorrupted","Yes");ui:choose("Fated","No");ui:text("HasExplicitMod",'"of Haast" "of Ephij"');ui:text("SocketGroup","G-G-G-R-R-W?");ui:click("useSample");frame("filter-invalid-socket-sample")
	assert(build.planningWorkspace.cache.filters.layout.snapshot().sample.TwiceCorrupted==true,"Twice-corrupted sample was not retained")
	local dimensions=build.planningWorkspace.cache.filters.layout.snapshot().sample;assert(dimensions.DropLevel==1 and dimensions.Width==2 and dimensions.Height==2,"Base properties were not retained")
	assert(build.planningWorkspace.cache.filters.layout.snapshot().sample.HasExplicitMod[2]=="of Ephij","Explicit modifier names were not retained")
	local detail={};for _,row in ipairs(build.planningWorkspace.controls.detail.list) do detail[#detail+1]=row[1] or "" end;assert(table.concat(detail," "):find("Invalid socket colours",1,true),"Invalid sample explanation was not refreshed")
	ui:click("sampleEdit");assert(main.popups[1].controls.TwiceCorrupted:GetSelValue()=="Yes" and main.popups[1].controls.Fated:GetSelValue()=="No","Boolean sample choices were not restored");assert(main.popups[1].controls.HasExplicitMod.buf=='"of Haast" "of Ephij"',"Explicit modifier names were not restored");ui:choose("TwiceCorrupted","Unknown");ui:text("HasExplicitMod","");ui:text("SocketGroup","G-G-G-R-R-W");ui:click("useSample");frame("filter-matched-drop")
	assert(build.planningWorkspace.cache.filters.layout.snapshot().sample.TwiceCorrupted==nil,"Unknown sample property was not cleared")
	assert(build.planningWorkspace.cache.filters.layout.snapshot().sample.HasExplicitMod==nil,"Unknown modifier names were not cleared")
	ui:click("sampleEdit");ui:text("HasExplicitMod","[]");ui:click("useSample")
	local emptyMods=build.planningWorkspace.cache.filters.layout.snapshot().sample.HasExplicitMod;assert(type(emptyMods)=="table" and #emptyMods==0,"Known empty modifier list was not retained")
	local influenceRule=require("Modules.LootFilterParser").parse("Hide\n HasInfluence == Shaper Elder\nShow")
	ui:click("sampleEdit");ui:text("HasInfluence","Shaper");ui:click("useSample")
	assert(require("Modules.LootFilterParser").simulate(influenceRule,build.planningWorkspace.cache.filters.layout.snapshot().sample).action=="Show","Single influence matched a dual-influence rule")
	ui:click("sampleEdit");ui:text("HasInfluence","Shaper Elder");ui:click("useSample")
	assert(require("Modules.LootFilterParser").simulate(influenceRule,build.planningWorkspace.cache.filters.layout.snapshot().sample).action=="Hide","Dual influence did not match the exact influence rule")
	ui:click("sampleEdit");ui:text("HasInfluence","");ui:text("SocketGroup","0");ui:text("Sockets","0");ui:click("useSample")
	local noSockets=build.planningWorkspace.cache.filters.layout.snapshot().sample
	assert(noSockets.HasInfluence==nil and require("Modules.LootFilterParser").simulate(influenceRule,noSockets).status=="unknown","Blank influence must remain unknown")
	assert(noSockets.SocketGroup=="0" and noSockets.Sockets==0,"Zero sockets were not retained in the sample")
	assert(require("Modules.LootFilterParser").simulate(require("Modules.LootFilterParser").parse("Show\n SocketGroup 0\nHide"),noSockets).action=="Show","Zero-socket sample did not match")
	detail={};for _,row in ipairs(build.planningWorkspace.controls.detail.list) do detail[#detail+1]=row[1] or "" end;assert(not table.concat(detail," "):find("Invalid socket colours",1,true),"Corrected sample left a stale explanation")
	ui:click("viewSimulate");frame("filter-loot-pile");ui:click("drop2");frame("filter-selected-drop");ui:click("regenerate");ui:click("hidden");frame("filter-hidden-drops")
	ui:click("viewStyle");ui:click("style2");ui:click("applyStyle");frame("filter-themes");ui:click("globalStyle");ui:choose("minimumFontSize","Minimum size 40","label");ui:choose("alertVolume","Mute filter alerts","label");ui:choose("disableEffects","Disable beams","label");ui:choose("alertId","Use alert 6","label");ui:text("textColor","FFE0A0FF");ui:text("borderColor","C0A060FF");ui:text("backgroundColor","101820FF");ui:click("borderColorPick");frame("filter-global-colour-wheel");ui:text("hex","C0A060FF");ui:click("keep");assert(main.popups[1].controls.borderColor.buf=="C0A060FF","Global picker did not return the selected colour");frame("filter-global-style");ui:click("keep")
	ui:click("categoryStyles");frame("filter-category-browser");ui:text("search","Currency");ui:click("choose");ui:text("textColor","00FF00FF");frame("filter-category-preview");ui:click("keep");frame("filter-category-applied")
	assert(build.planningWorkspace.cache.filters.layout.snapshot().data.profiles[1].categoryStyles[1].category=="Currency","Category style was not kept in the draft");ui:click("viewOverview")
	filterTool("Account filters");frame("filter-account");ui:click("createAccount");frame("filter-account-review");ui:click("cancel");ui:click("close")
	filterTool("Campaign and base-family");frame("filter-campaign-empty");ui:click("weapons1");ui:click("defences3");ui:click("recipe1");ui:click("recipe5");ui:click("rareSetSlots");ui:click("slot2");ui:click("slot3");frame("filter-rare-set-slots");ui:click("keep");ui:text("minAreaLevel","80");ui:text("maxAreaLevel","60");ui:click("keep");frame("filter-campaign-invalid");ui:click("close");ui:text("minAreaLevel","10");ui:text("minDropLevel","10");ui:text("minLinks","2");ui:text("upgradeWindow","20");frame("filter-campaign-selected");ui:click("keep")
	local campaignDraft=build.planningWorkspace.cache.filters.layout.snapshot().data.profiles[1].campaign
	assert(campaignDraft.weapons[1]=="Bow" and #campaignDraft.defences==1 and #campaignDraft.recipes==2 and campaignDraft.recipes[2]=="Unidentified rare set pieces","Campaign pickup choices were not kept in the draft")
	assert(#campaignDraft.rareSetSlots==1 and campaignDraft.rareSetSlots[1]=="Jewellery","Rare-set slot groups were not kept in the draft")
	assert(campaignDraft.minAreaLevel==10 and campaignDraft.maxAreaLevel==60 and campaignDraft.minDropLevel==10 and campaignDraft.minLinks==2 and campaignDraft.upgradeWindow==20,"Campaign numeric edits were ignored")
	filterTool("Filter structure and priority");frame("filter-structure-all");ui:choose("mode","Priority conflicts");frame("filter-structure-conflicts");ui:click("close")
	do
		local example=require("Modules.LootFilters").profile("threshold-example","Threshold example")
		example.template='Show\n ItemLevel >= 70\nHide\n ItemLevel >= 80'
		local structureControls=require("Classes.LootFilterStructureControl").Open(example)
		ui:choose("mode","Priority conflicts");local details={};for _,row in ipairs(structureControls.details.list) do details[#details+1]=StripEscapes(row[1] or "") end
		assert(table.concat(details," "):gsub("%s+"," "):find("matches every item matched",1,true),"Threshold priority conflict was not explained")
		frame("filter-threshold-conflict");ui:click("close")
	end
	do
		local example=require("Modules.LootFilters").profile("subset-example","Subset example")
		example.template='Show\n Class == "Currency"\nHide\n Class == "Currency"\n BaseType == "Chaos Orb"\n ItemLevel >= 50'
		local structureControls=require("Classes.LootFilterStructureControl").Open(example)
		ui:choose("mode","Priority conflicts");local details={};for _,row in ipairs(structureControls.details.list) do details[#details+1]=StripEscapes(row[1] or "") end
		assert(table.concat(details," "):gsub("%s+"," "):find("matches every item matched",1,true),"Broader rule conflict was not explained")
		ui:click("close")
	end
	ui:click("export");frame("filter-export")
	ui:text("directory",directory);ui:text("filename","ui-"..size[1]..".filter");ui:click("write");ui:click("close")
	local exportedPath=directory.."/ui-"..size[1]..".filter";local exportedFile=assert(io.open(exportedPath,"rb"));local exportedText=exportedFile:read("*a");exportedFile:close();assert(exportedText:find("Covens pickup plan",1,true),"Exported filter lost its title")
	local sentinel=assert(io.open(exportedPath,"wb"));sentinel:write("Preserve existing filter");sentinel:close();ui:click("write");ui:click("close")
	exportedFile=assert(io.open(exportedPath,"rb"));assert(exportedFile:read("*a")=="Preserve existing filter","Export overwrote an existing file");exportedFile:close();os.remove(exportedPath)
	local collision=exportedPath:gsub("%.filter$","-3.filter");local file=assert(io.open(collision,"wb"));file:write("Keep existing batch file");file:close()
	ui:click("writeAll");ui:click("close");assert(not io.open(exportedPath:gsub("%.filter$","-0.filter"),"rb"),"Batch wrote files before detecting a collision")
	file=assert(io.open(collision,"rb"));assert(file:read("*a")=="Keep existing batch file");file:close();os.remove(collision)
	ui:click("writeAll");ui:click("close")
	local zipPath=exportedPath:gsub("%.filter$","-strictnesses.zip");local zipSentinel=assert(io.open(zipPath,"wb"));zipSentinel:write("Keep archive");zipSentinel:close()
	ui:click("writeZip");ui:click("close");zipSentinel=assert(io.open(zipPath,"rb"));assert(zipSentinel:read("*a")=="Keep archive","ZIP export overwrote an existing archive");zipSentinel:close();os.remove(zipPath)
	ui:click("writeZip");ui:click("close");local zipFile=assert(io.open(zipPath,"rb"));local zip=zipFile:read("*a");zipFile:close()
	for strictness=0,6 do local target=exportedPath:gsub("%.filter$","-"..strictness..".filter");local file=assert(io.open(target,"rb"));local text=file:read("*a");assert(text:find("Covens pickup plan",1,true) and zip:find(text,1,true),"ZIP did not contain the compiled variant");file:close();os.remove(target) end
	ui:click("close")
	do
		local filters=require("Modules.LootFilters");local ruthless=filters.profile("ruthless-"..size[1],"Ruthless export");ruthless.mode="Ruthless"
		local raw=filters.compile(ruthless);require("Classes.LootFilterControl").Export(ruthless,raw)
		local controls=main.popups[1].controls;assert(controls.filename.buf==ruthless.id..".ruthlessfilter","Ruthless filename uses the wrong extension")
		ui:text("directory",directory);ui:click("write");ui:click("close")
		local path=directory.."/"..ruthless.id..".ruthlessfilter";local saved=assert(io.open(path,"rb"));assert(raw==saved:read("*a"),"Ruthless export changed the filter");saved:close();os.remove(path)
		ui:click("writeAll");ui:click("close");ui:click("writeZip");ui:click("close")
		local archivePath=directory.."/"..ruthless.id.."-strictnesses.zip";local archive=assert(io.open(archivePath,"rb"));local bytes=archive:read("*a");archive:close()
		for strictness=0,6 do local name=ruthless.id.."-"..strictness..".ruthlessfilter";local f=assert(io.open(directory.."/"..name,"rb"));local content=f:read("*a");f:close();assert(bytes:find(name,1,true) and bytes:find(content,1,true),"Ruthless ZIP omitted its variant");os.remove(directory.."/"..name) end
		ui:text("filename",ruthless.id..".filter");ui:click("write");ui:click("close");assert(not io.open(directory.."/"..ruthless.id..".filter","rb"),"Ruthless export accepted a normal extension")
		ui:click("close")
	end
	do
		local filters=require("Modules.LootFilters");local imported=filters.profile("unresolved","Unresolved imports")
		imported.template='Import "outer.filter"\nImport "optional.filter" Optional\nShow';imported.importFiles={{name="outer.filter",text='Import "missing.filter"\nImport "outer.filter"'}}
		local raw,report=filters.compile(imported);assert(#report.unresolvedImports==3,"Expected missing and circular imports")
		local export=require("Classes.LootFilterControl");export.Export(imported,raw,report)
		local panel=main.popups[1].controls;assert(panel.reviewImports:IsEnabled() and panel.importsStatus.list[1][1]:find("3 linked",1,true),"Export did not show unresolved imports")
		frame("filter-export-unresolved");ui:click("reviewImports")
		local browser=main.popups[1].controls;local statuses={};for _,row in ipairs(browser.results.list) do if row.entry then statuses[row.entry.label]=row.entry.details[1] end end
		assert(statuses["missing.filter"]=="Required file missing" and statuses["optional.filter"]=="Optional file missing" and statuses["outer.filter"]=="Circular reference","Import statuses were not distinguished")
		frame("filter-export-imports-review");ui:click("close");ui:click("close")
	end
	filterTool("Audit and update");frame("filter-audit");ui:click("close")
	ui:click("keep");assert(#build.savers.LootFilters.data.profiles==1,"Loot filter was not kept");assert(build.savers.LootFilters.data.profiles[1].appearance.alertVolume==0,"Global appearance was not kept")
	ui:click("nav_journey");ui:click("nav_filters");frame("filter-kept-navigation")
	filterTool("Import filter");frame("filter-import")
	local linkedPath=os.tmpname()..".filter";local linkedName=linkedPath:match("([^/\\]+)$");local linkedFile=assert(io.open(linkedPath,"wb"));linkedFile:write('Hide\n BaseType "Iron Hat"');linkedFile:close()
	local mainFilterPath=os.tmpname()..".filter";local mainFilterFile=assert(io.open(mainFilterPath,"wb"));mainFilterFile:write('Hide\n    BaseType == "Orb of Binding"\nShow\n    BaseType == "Chaos Orb"\nImport "'..linkedName..'"');mainFilterFile:close()
	ui:text("path",mainFilterPath);ui:click("loadFile");frame("filter-main-file-loaded");ui:click("loadLinked");frame("filter-linked-file-report");ui:click("close");os.remove(mainFilterPath);os.remove(linkedPath);ui:click("import");ui:click("keep")
	assert(build.savers.LootFilters.data.profiles[1].template:find("Orb of Binding",1,true),"Original imported filter text was not preserved")
	local attached=build.savers.LootFilters.data.profiles[1].importFiles;local found,previous=false,false;for _,file in ipairs(attached) do if file.name==linkedName then found=file.text:find("Iron Hat",1,true)~=nil elseif file.name=="rules.filter" then previous=true end end
	assert(found and previous,"Linked filter was not saved alongside existing attachments")
	local compiled=require("Modules.LootFilters").compile(build.savers.LootFilters.data.profiles[1]);assert(compiled:find("# Included filter: "..linkedName,1,true),"Saved linked filter was not expanded")
	filterTool("Import filter");ui:text("text",'Show\n SetFontSize 99');ui:click("import")
	local importError=StripEscapes(main.popups[1].controls.message.list[1][1]);assert(importError:find("Invalid SetFontSize",1,true) and not importError:find(".lua:",1,true),"Import error exposed a source path")
	ui:click("close");assert(main.popups[1].controls.text.buf:find("99",1,true),"Invalid import text was lost");ui:click("close")
	local draft=build.planningWorkspace.cache.filters.layout.snapshot().data.profiles[1];local priorTemplate,priorCommit=draft.template,draft.baseCommit
	draft.template=nil;draft.baseCommit="outdated";ui:click("viewOverview");ui:frame()
	assert(not build.planningWorkspace.controls.export:IsEnabled(),"An outdated base left export enabled")
	assert(build.planningWorkspace.controls.export.tooltipText():find("bundled base changed",1,true),"Export did not explain the compilation error")
	frame("filter-invalid-export","export")
	draft=build.planningWorkspace.cache.filters.layout.snapshot().data.profiles[1];draft.template=priorTemplate;draft.baseCommit=priorCommit;ui:click("viewOverview");ui:frame()
	assert(build.planningWorkspace.controls.export:IsEnabled(),"Correcting the filter did not restore export")
	draft=build.planningWorkspace.cache.filters.layout.snapshot().data.profiles[1];draft.rules[#draft.rules+1]={id="poe2-condition",title="Unsupported condition",text="Show\n AlwaysShow True",enabled=true}
	ui:click("viewSimulate");ui:frame();local invalidDrop=build.planningWorkspace.controls.drop1
	assert(invalidDrop and invalidDrop.tooltipText:find("Path of Exile 2%-only"),"Invalid filter was shown as a valid scene result");frame("filter-poe2-condition")
	ui:click("viewOverview");ui:frame();assert(not build.planningWorkspace.controls.export:IsEnabled());assert(build.planningWorkspace.controls.export.tooltipText():find("AlwaysShow",1,true))
	draft=build.planningWorkspace.cache.filters.layout.snapshot().data.profiles[1];for i=#draft.rules,1,-1 do if draft.rules[i].id=="poe2-condition" then table.remove(draft.rules,i) end end;ui:click("viewOverview");ui:frame();assert(build.planningWorkspace.controls.export:IsEnabled())
	filterTool("Import filter");ui:text("text",'Hide\n    BaseType == "Orb of Binding"\nShow\n    BaseType == "Chaos Orb"\n    SetFontSize 44');ui:click("import");ui:frame()
	filterTool("Full file changes");frame("filter-file-changes-compiled");ui:choose("content","Original base text");frame("filter-file-changes-source");ui:text("search","SetFontSize");frame("filter-file-changes-search")
	ui:click("copyBefore");assert(not ui.clipboard:find("SetFontSize 44",1,true),"Before source used the working draft");ui:click("copyAfter");assert(ui.clipboard:find("SetFontSize 44",1,true),"After source omitted the working change");ui:click("close");ui:click("keep")
	ui:click("viewTiers");ui:click("tierNew");assert(not build.planningWorkspace.controls.tierStack:IsEnabled());assert(build.planningWorkspace.controls.tierStack.tooltipText():find("Create another custom tier",1,true));ui:text("tierName","Chaos Orb");ui:click("tierAddItem");frame("filter-tiers")
	ui:choose("tierScope","Preset tiers");frame("filter-tier-preset");ui:click("tierCopy")
	local tierControls=build.planningWorkspace.controls;local ix,iy=tierControls.tierItems:GetPos();local tx,ty=tierControls.tiers:GetPos()
	ui.cursorX,ui.cursorY=ix+40,iy+22;ui:frame();ui:dispatch(build,{{type="KeyDown",key="LEFTBUTTON"}})
	ui.cursorX,ui.cursorY=tx+40,ty+22;ui:frame();ui:dispatch(build,{{type="KeyUp",key="LEFTBUTTON"}});frame("filter-tier-move")
	local tierDraft=build.planningWorkspace.cache.filters.layout.snapshot().data.profiles[1]
	assert(#tierDraft.tiers[1].items==1 and #tierDraft.tiers[2].items==0,"Dragging did not move the item between custom tiers")
	ui:click("tierNew");tierDraft=build.planningWorkspace.cache.filters.layout.snapshot().data.profiles[1]
	ui:click("tierStack");frame("filter-stack-styles");ui:choose("stackStyle",tierDraft.tiers[1].id,"val");ui:text("stackSize","5");ui:click("stackAdd");frame("filter-stack-added");ui:click("stackKeep")
	tierDraft=build.planningWorkspace.cache.filters.layout.snapshot().data.profiles[1];assert(tierDraft.tiers[3].stackRules[1].minimum==5,"Stack style was not saved")
	do
		local filters=require("Modules.LootFilters");local editing=require("Modules.LootFilterEditing");local profile=filters.profile("continue-stacks","Continue stacks")
		local source=editing.newTier("source","Source",'Show\n BaseType == "Chaos Orb"\n SetFontSize 20\n Continue');source.items={"Chaos Orb"}
		local style=editing.newTier("style","Style",'Show\n BaseType == "Divine Orb"\n SetFontSize 40\n Continue');style.items={"Divine Orb"};profile.tiers={source,style}
		local kept;require("Classes.LootFilterStackControl").Open(profile,"source",function(value) kept=value end)
		ui:choose("stackStyle","style","val");ui:text("stackSize","5");ui:click("stackAdd");frame("filter-continuing-stack-style");ui:click("stackKeep")
		assert(kept and kept.tiers[1].stackRules[1].minimum==5,"Continuing tier did not keep its stack style")
		local rules=editing.tierRules(kept.tiers);assert(require("Modules.LootFilterParser").parse(rules[1].text).rules[1].continue,"Stack style lost Continue")
	end
	ui:click("undo");ui:click("redo");ui:click("viewModules");ui:click("moduleCreate");frame("filter-modules")
	ui.clipboard="not a pickup module";ui:click("modulePaste");assert(#main.popups>0,"Invalid module did not show an explanation");assert(#build.planningWorkspace.cache.filters.layout.snapshot().data.profiles[1].modules==1,"Invalid module changed the profile");main.popups={}
	ui:click("moduleCopy");ui:click("modulePaste")
	filterTool("Review changes");frame("filter-change-review");ui:click("close");ui:click("keep")
	assert(#build.savers.LootFilters.data.profiles[1].modules==1,"Rule modules were not kept")
	ui:click("viewSimulate");ui:choose("sceneKind","Covens & Threads");assert(build.planningWorkspace.cache.filters.layout.snapshot().sceneKind=="Covens & Threads","League example scene was not selected");assert(build.planningWorkspace.controls.regenerate:IsEnabled(),"League examples should be reorderable");frame("filter-covens-examples")
	ui:choose("sceneKind","Preset highlights");assert(build.planningWorkspace.cache.filters.layout.snapshot().sceneKind=="Preset highlights");assert(build.planningWorkspace.controls.sceneKind.tooltipText:find("not live prices",1,true));frame("filter-preset-highlights")
	ui:choose("sceneKind","Maps & threads");local mapScene=build.planningWorkspace.cache.filters.layout.snapshot();assert(mapScene.sceneKind=="Maps & threads" and mapScene.sample.Class=="Maps","Mapping examples did not select their first item");frame("filter-mapping-examples")
	ui:click("sceneStats");assert(main.popups[#main.popups].controls.count.label:find("12 results |",1,true),"The selected mapping example appeared twice");ui:click("choose")
	do ui:choose("sceneKind","Map tiers");local tiers=build.planningWorkspace.cache.filters.layout.snapshot();assert(tiers.sample.MapTier==1 and not build.planningWorkspace.controls.regenerate:IsEnabled(),"Map tier comparison did not select its first map");frame("filter-map-tier-examples") end
	ui:choose("sceneKind","Flasks & tinctures");local flaskScene=build.planningWorkspace.cache.filters.layout.snapshot();assert(flaskScene.sceneKind=="Flasks & tinctures" and flaskScene.sample.Class=="Life Flasks","Flask examples did not select their first item");frame("filter-flask-examples")
	ui:click("sceneStats");assert(main.popups[#main.popups].controls.count.label:find("12 results |",1,true),"The selected flask example appeared twice");ui:click("choose")
	ui:choose("sceneKind","Divination cards");local cardScene=build.planningWorkspace.cache.filters.layout.snapshot();assert(cardScene.sceneKind=="Divination cards" and cardScene.sample.Class=="Divination Cards");frame("filter-card-examples")
	ui:choose("sceneKind","Essences");local essenceScene=build.planningWorkspace.cache.filters.layout.snapshot();assert(essenceScene.sceneKind=="Essences" and essenceScene.sample.BaseType:find("Essence",1,true))
	for _,row in ipairs(build.planningWorkspace.controls.selection.list) do assert(not row[1]:find("Unidentified item tier",1,true),"Currency incorrectly shows an equipment tier") end;frame("filter-essence-examples")
	ui:choose("sceneKind","Crafting materials");local craftScene=build.planningWorkspace.cache.filters.layout.snapshot();assert(craftScene.sample.BaseType==require("Modules.LootFilterLibrary").scene(nil,nil,"Crafting materials",craftScene.seed)[1].BaseType);frame("filter-crafting-examples")
	ui:choose("sceneKind","Heist & Expedition");local heistScene=build.planningWorkspace.cache.filters.layout.snapshot();assert(heistScene.sample.BaseType==require("Modules.LootFilterLibrary").scene(nil,nil,"Heist & Expedition",heistScene.seed)[1].BaseType);frame("filter-heist-expedition-examples")
	ui:choose("sceneKind","Tiered gear");assert(not build.planningWorkspace.controls.regenerate:IsEnabled(),"Tier comparison should not offer no-op regeneration");assert(build.planningWorkspace.cache.filters.layout.snapshot().sample.BaseType=="Iron Hat","Tier comparison did not select its own example");frame("filter-tiered-gear");ui:choose("sceneKind","Mixed drops");ui.clipboard="Item Class: Helmets\nRarity: Rare\nFoe Visage\nIron Hat\n--------\nItem Level: 86\nMemory Strands: 75\nUnidentified\nShaper Item\nElder Item";ui:click("pasteDrop")
	local tierDetails={};for _,row in ipairs(build.planningWorkspace.controls.selection.list) do tierDetails[#tierDetails+1]=row[1] end
	assert(table.concat(tierDetails," "):find("Unidentified item tier: unknown",1,true),"Unknown tier was not explained");frame("filter-tier-unknown")
	ui:click("sceneStats");assert(main.popups[#main.popups].controls.category,"Drop review did not open its result browser");frame("filter-drop-review");ui:click("choose")
	local pasted=build.planningWorkspace.cache.filters.layout.snapshot().sample;assert(pasted.ShaperItem and pasted.ElderItem and #pasted.HasInfluence==2 and pasted.MemoryStrands==75,"Pasted influences or memory strands were not retained")
	assert(pasted.Sockets==nil and pasted.LinkedSockets==nil and pasted.SocketGroup==nil,"Missing pasted sockets were treated as known")
	assert(pasted.DropLevel==1 and pasted.Width==2 and pasted.Height==2,"Pasted base properties were not populated")
	ui:click("sampleEdit");local missing=main.popups[1].controls;assert(missing.Sockets.buf=="" and missing.LinkedSockets.buf=="" and missing.SocketGroup.buf=="","Unknown sockets were not shown as blank");frame("filter-pasted-sockets-unknown");ui:text("HasInfluence","Elder");ui:click("useSample")
	do local changed=build.planningWorkspace.cache.filters.layout.snapshot().sample;local filterParser=require("Modules.LootFilterParser")
	assert(changed.ShaperItem==nil and changed.ElderItem==nil and filterParser.simulate(filterParser.parse("Hide\n ShaperItem True\nShow"),changed).action=="Show" and filterParser.simulate(filterParser.parse("Hide\n ElderItem True\nShow"),changed).action=="Hide","Editing influence retained stale flags") end
	ui.clipboard="Item Class: Helmets\nRarity: Rare\nFoe Visage\nIron Hat\n--------\nItem Level: 86\nUnidentified\nFractured Item";ui:click("pasteDrop");assert(build.planningWorkspace.cache.filters.layout.snapshot().sample.FracturedItem,"Pasted fracture marker was not retained")
	ui.clipboard="Item Class: Helmets\nRarity: Rare\nFoe Visage\nIron Hat\n--------\nItem Level: 86\nSynthesised Item";ui:click("pasteDrop");assert(build.planningWorkspace.cache.filters.layout.snapshot().sample.SynthesisedItem,"Pasted synthesis marker was not retained")
	ui.clipboard="Item Class: Active Skill Gems\nRarity: Gem\nFireball of Radiation\n--------\nLevel: 20";ui:click("pasteDrop");assert(build.planningWorkspace.cache.filters.layout.snapshot().sample.TransfiguredGem=="Fireball","Pasted transfigured gem lost its base skill")
	ui.clipboard="Item Class: Maps\nRarity: Rare\nVortex Artifice\nMap (Tier 5)\n--------\nQuality (Pack Size): +20% (augmented)\n--------\nItem Level: 68";ui:click("pasteDrop")
	do local sample=build.planningWorkspace.cache.filters.layout.snapshot().sample;assert(sample.MapTier==5 and sample.Quality==20,"Pasted map tier and quality were not retained") end
	frame("filter-copied-current-map")
	ui.clipboard="Rarity: Unique\nAn Unknown Name\n--------";ui:click("pasteDrop");assert(build.planningWorkspace.cache.filters.layout.snapshot().sample.BaseType==nil,"Incomplete copied item invented a base");assert(require("Modules.LootFilterVisuals").sampleName(build.planningWorkspace.cache.filters.layout.snapshot().sample)=="Unknown item","Incomplete copied item should be labelled unknown")
	ui.clipboard="not an item";ui:click("pasteDrop");assert(#main.popups>0,"Invalid clipboard did not show an explanation");assert(build.planningWorkspace.cache.filters.layout.snapshot().sample.BaseType==nil,"Invalid paste changed the current item");main.popups={}
	ui.clipboard="Item Class: Rings\nRarity: Normal\nIron Ring\n--------\nAdds 1 to 4 Physical Damage to Attacks (implicit)";ui:click("pasteDrop");assert(build.planningWorkspace.cache.filters.layout.snapshot().sample.HasImplicitMod==true,"Pasted implicit was not retained in the workspace")
	ui.clipboard='Item Class: Belts\nRarity: Rare\nTest Belt\nCord Belt\n--------\n{ Prefix Modifier "Hale" }\n+100 to maximum Life';ui:click("pasteDrop")
	local copiedMods=build.planningWorkspace.cache.filters.layout.snapshot().sample;assert(copiedMods.KnownExplicitMods[1]=="Hale" and copiedMods.HasExplicitMod==nil,"Partial modifier evidence was not retained")
	local copiedDetails={};for _,row in ipairs(build.planningWorkspace.controls.selection.list) do copiedDetails[#copiedDetails+1]=row[1] end
	assert(table.concat(copiedDetails," "):find("Hale",1,true),"Copied modifier name was not shown in the item details");frame("filter-copied-modifiers")
	ui:click("sampleEdit");ui:text("HasExplicitMod",'"Other"');ui:click("useSample");local editedMods=build.planningWorkspace.cache.filters.layout.snapshot().sample;assert(editedMods.KnownExplicitMods==nil and editedMods.HasExplicitMod[1]=="Other","Editing modifier names retained partial copied evidence")
	ui.clipboard='Item Class: Belts\nRarity: Rare\nTest Belt\nCord Belt\n--------\n{ Prefix Modifier "Hale" }\n+100 to maximum Life';ui:click("pasteDrop")
	ui:click("sampleEdit");ui:text("BaseType","Iron Hat");ui:click("useSample");assert(build.planningWorkspace.cache.filters.layout.snapshot().sample.KnownExplicitMods==nil,"Changing base retained copied modifier names")
	ui.clipboard="Item Class: Stackable Currency\nRarity: Currency\nChaos Orb\n--------\nStack Size: 7/20";ui:click("pasteDrop");frame("filter-copied-item")
	local currency=build.planningWorkspace.cache.filters.layout.snapshot().sample;assert(currency.DropLevel==12 and currency.Width==1 and currency.Height==1 and currency.BaseDefencePercentile==0,"Pasted currency base properties were not populated")
	ui:click("sampleEdit");assert(main.popups[1].controls.DropLevel.buf=="12" and main.popups[1].controls.Width.buf=="1" and main.popups[1].controls.BaseDefencePercentile.buf=="0", "Pasted base properties were not editable");ui:text("MemoryStrands","0");assert(main.popups[1].controls.AlwaysShow==nil,"PoE 2-only sample field was offered");frame("filter-copied-base-properties")
	ui:click("moreSample");ui:text("extra_BaseArmour","0");frame("filter-more-sample-properties");ui:click("keepExtra");ui:click("useSample")
	local configured=build.planningWorkspace.cache.filters.layout.snapshot().sample
	assert(configured.BaseDefencePercentile==0 and configured.MemoryStrands==0 and configured.AlwaysShow==nil and configured.BaseArmour==0,"Configured properties were not retained in the test item")
	ui:click("sceneSettings");ui:text("areaLevel","72");ui:text("itemLevel","75");ui:choose("background","Dark");frame("filter-scene-settings");ui:click("keepScene")
	ui:choose("sceneKind","Build targets")
	local targetsReady=false
	for i=1,2000 do ui:frame();local state=build.planningWorkspace.transient.filterSceneTargets
		if state and state.rules then targetsReady=true;break end
	end
	assert(targetsReady,"Build-target scene did not finish generating")
	frame("filter-build-target-scene");ui:choose("sceneKind","Mixed drops")
	ui:click("sampleHistory");frame("filter-sample-history");ui:click("choose");ui:click("inspectMatch");frame("filter-matched-rules");ui:click("close")
	local savedArea=build.planningWorkspace.cache.filters.layout.snapshot().sample.AreaLevel
	ui:click("savedSamples");frame("filter-saved-examples-empty");ui:text("name","Mapping examples");ui:click("saveNew");frame("filter-saved-examples");ui:click("keep")
	ui:choose("sceneKind","Maps & threads");ui:click("savedSamples");ui:choose("source",3,"val");ui:text("name","Generated comparison set");ui:click("saveNew");ui:click("use");frame("filter-saved-scene")
	local savedDraft=build.planningWorkspace.cache.filters.layout.snapshot();assert(savedDraft.sceneKind=="Saved examples" and savedDraft.data.profiles[1].sampleSets[1].samples[1].AreaLevel==savedArea,"Saved examples changed their original properties")
	local savedScene=savedDraft.data.profiles[1].sampleSets[2].samples;assert(#savedScene==12 and savedScene[1].Class=="Maps","Saved examples did not capture the selected mapping scene")
	assert(not build.planningWorkspace.controls.regenerate:IsEnabled(),"Saved sets should not offer a no-op regeneration action")
	ui.clipboard="Item Class: Stackable Currency\nRarity: Currency\nDivine Orb\n--------\nStack Size: 3/20";ui:click("pasteDrop");frame("filter-saved-extra-test")
	local hoveredSample=build.planningWorkspace.controls.drop1;local hx,hy=hoveredSample:GetPos();ui.cursorX,ui.cursorY=hx+10,hy+10;ui:frame():write(directory.."/"..size[1].."-filter-sample-tooltip.json");frames=frames+1
	assert(hoveredSample.tooltip.lines[1] and hoveredSample.tooltip.lines[1].text=="Divine Orb","Sample hover did not show the selected item's tooltip")
	local extraDraft=build.planningWorkspace.cache.filters.layout.snapshot();assert(extraDraft.data.profiles[1].sampleSets[1].samples[1].BaseType=="Chaos Orb" and extraDraft.sample.BaseType=="Divine Orb","An extra test overwrote the saved set")
	local hasNext=build.planningWorkspace.controls.sceneNext:IsEnabled();if hasNext then ui:click("sceneNext");assert(build.planningWorkspace.cache.filters.layout.snapshot().scenePage==2,"Scene paging did not advance") end;frame("filter-scene-paging");if hasNext then ui:click("scenePrevious") end
	ui:click("viewStyle");ui:click("savedPalettes");ui:text("name","Gold highlights");ui:click("saveNew");frame("filter-saved-palette");ui:click("use");ui:click("keep")
	assert(#build.savers.LootFilters.data.profiles[1].palettes==1 and #build.savers.LootFilters.data.profiles[1].sampleSets==2,"Filter libraries were not kept")
	assert(build.savers.LootFilters.data.profiles[1].palettes[1].categoryStyles[1].category=="Currency","Palette omitted category settings")
	ui:click("viewSimulate");ui:choose("sceneKind","Mixed drops")
	filterTool("Linked build targets");frame("filter-linked-targets");ui:click("choose");assert(build.planningWorkspace.page~="filters","Linked filter target did not open its source plan");frame("filter-linked-plan");ui:click("nav_filters");frame("filter-returned-draft");assert(build.planningWorkspace.cache.filters.layout.snapshot().page=="Simulate","Following a linked plan lost the filter draft")
	ui:click("nav_atlas");ui:text("search","");ui:choose("mechanic","Mirage");frame("atlas-mirage-filter");ui:choose("mechanic","Essence");ui:click("targets");ui:click("targetAdd")
	ui:click("targetCalculate");for i=1,500 do ui:frame();if not require("Modules.AtlasTargets").jobs[build].thread then break end end
	local exactRoute=require("Modules.AtlasTargets").jobs[build].result;assert(exactRoute and not exactRoute.routing.heuristic,"Exact Atlas route did not complete");ui:frame();frame("atlas-exact-target-preview")
	ui:choose("targetMechanic","Harvest");ui:click("targetMechanicAdd");frame("atlas-desired-targets")
	ui:click("targetCalculate");for i=1,500 do ui:frame();if not require("Modules.AtlasTargets").jobs[build].thread then break end end
	assert(require("Modules.AtlasTargets").jobs[build].result,require("Modules.AtlasTargets").jobs[build].error)
	frame("atlas-desired-preview");local routeDetails={};for _,row in ipairs(main.popups[1].controls.details.list) do routeDetails[#routeDetails+1]=row[1] or "" end
	assert(StripEscapes(table.concat(routeDetails," ")):find("Heuristic route:",1,true),"Larger Atlas route did not disclose its heuristic")
	local beforeRoute=build.planningWorkspace.cache.atlas.layout.snapshot()
	ui:click("targetShowTree");ui:frame();local overlay=build.planningWorkspace.controls.canvas.routeOverlay
	assert(overlay and next(overlay.added),"Route preview did not show added nodes")
	assert(build.planningWorkspace.controls.keep.label()=="Keep current plan" and build.planningWorkspace.controls.keep.tooltipText():find("not the route preview",1,true),"Preview did not distinguish keeping the current plan")
	assert(build.planningWorkspace.controls.help.label:find("Preview +",1,true),"Route preview point changes are not visible")
	assert(tableDeepEquals(beforeRoute,build.planningWorkspace.cache.atlas.layout.snapshot()),"Showing a route changed the draft")
	frame("atlas-route-tree-preview");local previousTitle=build.planningWorkspace.controls.title.buf
	ui:text("title","Temporary route title");assert(not build.planningWorkspace.controls.canvas.routeOverlay,"Editing the plan retained a stale route overlay")
	ui:text("title",previousTitle);ui:click("targets");ui:frame()
	do (function()
	ui:choose("routeMode","Rebuild from start");ui:click("targetCalculate")
	for i=1,500 do ui:frame();if not require("Modules.AtlasTargets").jobs[build].thread then break end end
	local rebuilt=require("Modules.AtlasTargets").jobs[build].result;assert(rebuilt,"Rebuilt Atlas route did not complete");ui:frame()
	local after={};for _,id in ipairs(rebuilt.plan.nodes) do after[id]=true end
	local expectedRefunds={};for _,id in ipairs(beforeRoute.nodes) do if not after[id] then expectedRefunds[id]=true end end
	assert(next(expectedRefunds),"Refund preview fixture did not refund any nodes")
	ui:click("targetShowTree");ui:frame();local refundOverlay=build.planningWorkspace.controls.canvas.routeOverlay
	assert(refundOverlay and tableDeepEquals(expectedRefunds,refundOverlay.removed),"Refund overlay did not match the rebuilt route")
	assert(tableDeepEquals(beforeRoute,build.planningWorkspace.cache.atlas.layout.snapshot()),"Showing refunds changed the draft")
	frame("atlas-route-refund-preview");ui:click("targets");ui:frame()
	end)() end
	ui:click("targetApply");ui:click("keep");frame("atlas-desired-kept")
	do
		local p={id="analysis-lifecycle",title="Resumable calculation",slot="Body Armour",startingItem="Rarity: NORMAL\nPlate Vest\nItem Level: 86",goals={},steps={},preferredMethod="alchemy",nativeRecipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1}},priceBook={currency="chaos",source="Lifecycle quotes",quotedAt=1700000000,values={["Metadata/Items/Currency/CurrencyUpgradeToRare"]=3}}}
		build.savers.CraftingProjects:Upsert(p)
		local w=build.planningWorkspace;w:Show("crafting",{kind="workbench",project=p});ui:frame()
		ui:click("tab_simulate");ui:text("trials","2");ui:text("budget","1")
		local function hold(key)
			local original=jobs.start;local thread
			jobs.start=function(...)
				local job=original(...);thread=job.thread;job.thread=coroutine.create(function() while true do coroutine.yield() end end);return job
			end
			local ok,message=pcall(ui.click,ui,key);jobs.start=original;assert(ok,message)
			local job=assert(jobs.job);return job,function() job.thread=thread end
		end
		local function finish() for i=1,3000 do if not jobs.job then return end;jobs.tick(build) end;error("Lifecycle calculation did not finish") end
		local function resize()
			ui:resize(size[1]==960 and 1024 or 960,640);ui:frame();ui:resize(size[1],size[2]);ui:frame()
		end
		local job,release=hold("simulate");resize();assert(job.owner==w.body.controls);frame("crafting-job-remounted")
		ui:click("nav_atlas");resize();release();finish();assert(#main.popups==0);ui:click("nav_crafting")
		assert(w.cache.crafting.layout.snapshot().lastSimulation.meanCost==3);frame("crafting-job-returned")
		job=hold("simulate");resize();ui:click("close");assert(not jobs.job);frame("crafting-job-cancelled-remount")
		w:Show("crafting",{kind="workbench",project=p});ui:frame();ui:click("tab_simulate")
		local analysis=require("Modules.CraftingAnalysis").get(build,p)
		analysis:start("odds",nil,function() error("C:/fixture/Recipe.lua:42: Invalid recipe fixture") end);finish();frame("crafting-async-error")
		w.controls.method:SelByValue("fossil","val");w.controls.method.selFunc();job,release=hold("optimize")
		ui:click("nav_atlas");resize();release();finish();assert(#main.popups==0);ui:click("nav_crafting")
		assert(w.controls.fossilResults:IsEnabled());frame("crafting-fossil-background-return")
		ui:click("tab_settings");job,release=hold("exact");resize();release();finish();ui:click("tab_simulate");frame("crafting-odds-remounted")
	end
	do
		newBuild();ui:bind(build);build.viewMode="CONFIG";ui:click("aiBuild")
		assert(require("Modules.PlanningUI").saveStatus(build)=="No pending build changes");frame("planning-fresh-build-status")
		local p={id="remove-restore",title=string.rep("Saved crafting guide ",5),slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={},priceBook={currency="chaos",source="Removal quotes",quotedAt=1700000000,values={}}}
		local state=sim.model(p.startingItem).initial;p.run=require("Modules.CraftingInventory").run(state)
		p.inventory={require("Modules.CraftingInventory").capture(p,state,"Kept base")};build.savers.CraftingProjects:Upsert(p)
		local w=build.planningWorkspace;w:Show("crafting",{kind="workbench",project=p});ui:frame();ui:click("currency_alchemy");ui:click("item")
		local working=w:CraftingDraft(p.id).state;ui:click("close");frame("crafting-project-remove-ready")
		ui:click("remove");assert(#build.savers.CraftingProjects.projects==0 and w.controls.undoRemove:IsEnabled());frame("crafting-project-removed-empty")
		ui:click("nav_text");frame("crafting-project-removal-large-text");ui:click("nav_text")
		ui:click("undoRemove");assert(#build.savers.CraftingProjects.projects[1].inventory==1);frame("crafting-project-restored")
		ui:click("inventory");frame("crafting-project-restored-inventory");ui:click("close");ui:click("native")
		assert(tableDeepEquals(working,w.cache.crafting.layout.snapshot().state));frame("crafting-project-restored-working")
		ui:click("keepWorking");assert(not require("Modules.PlanningUI").hasDraft(build,"workingCraft",p.id));frame("crafting-project-restored-kept")
		ui:click("tab_simulate");w.controls.trials:SetText("37",true)
		assert(require("Modules.PlanningUI").hasDraft(build,"workingCraft",p.id));frame("crafting-settings-working-draft")
		ui:click("keepWorking");assert(not require("Modules.PlanningUI").hasDraft(build,"workingCraft",p.id));frame("crafting-settings-kept")
		ui:click("close");ui:click("native");assert(w.controls.trials.buf=="37" and not require("Modules.PlanningUI").hasDraft(build,"workingCraft",p.id));frame("crafting-settings-reopened-clean")
	end

	do
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86\nSockets: W-W-W\nTwice Corrupted"
		local p={id="twice-corruption",title="Twice Corrupted helmet",slot="Helmet",startingItem=raw,goals={},steps={},preferredMethod="tainted_chromatic"}
		build.savers.CraftingProjects:Upsert(p)
		local w=build.planningWorkspace;w:Show("crafting",{kind="workbench",project=p});ui:frame();frame("crafting-twice-imported")
		ui:click("apply");assert(w.cache.crafting.layout.snapshot().state.twiceCorrupted);frame("crafting-twice-tainted")
		ui:click("tab_settings");ui:click("manual");frame("crafting-twice-editor")
		ui:choose("corrupted","Corrupted");ui:click("keep");assert(w.cache.crafting.layout.snapshot().state.twiceCorrupted==false);frame("crafting-twice-downgraded")
		ui:click("manual");ui:choose("corrupted","Uncorrupted");ui:click("keep");frame("crafting-twice-uncorrupted")
		ui:click("keepWorking");local xml=build:SaveDB("Twice corruption UI");loadBuildFromXML(xml,"Twice corruption UI");ui:bind(build)
		local saved;for _,entry in ipairs(build.savers.CraftingProjects.projects) do if entry.id==p.id then saved=entry end end
		assert(saved.run.state.twiceCorrupted==false and saved.run.state.corrupted==false)
		build.viewMode="PLANNER";build.planningWorkspace:Show("crafting",{kind="workbench",project=saved});frame("crafting-twice-reopened")
	end
	do
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86\nSockets: W W W\nImplicits: 2\n0.5% of Cold Damage Leeched as Life\n+10% to Damage over Time Multiplier\nTwice Corrupted"
		local target={anyOf={"V2ColdDamageLifeLeechPermyriadCorrupted_"},scope="implicit"}
		local p={id="implicit-import",title="Imported corruption target",slot="Helmet",startingItem=raw,goals={},steps={},preferredMethod="tainted_chromatic",nativeRecipe={steps={{method="tainted_chromatic"}},targets={target},requirements={minAffixes=0}}}
		build.savers.CraftingProjects:Upsert(p)
		local w=build.planningWorkspace;w:Show("crafting",{kind="workbench",project=p});ui:frame()
		assert(#w.cache.crafting.layout.snapshot().state.corruptedImplicits==2);frame("crafting-implicit-import-card")
		ui:click("tab_simulate");ui:text("trials","2");ui:text("budget","1");ui:click("simulate")
		for i=1,3000 do if not jobs.job then break end;jobs.tick(build) end
		assert(w.cache.crafting.layout.snapshot().lastSimulation.successes==2);frame("crafting-implicit-import-results")
		ui:click("keepWorking");local xml=build:SaveDB("Imported corruption UI");loadBuildFromXML(xml,"Imported corruption UI");ui:bind(build)
		local saved;for _,entry in ipairs(build.savers.CraftingProjects.projects) do if entry.id==p.id then saved=entry end end
		assert(#saved.run.state.corruptedImplicits==2);assert(saved.nativeRecipe.targets[1].anyOf[1]==target.anyOf[1])
		build.viewMode="PLANNER";build.planningWorkspace:Show("crafting",{kind="workbench",project=saved});frame("crafting-implicit-import-reopened")
	end
	do
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86\nSockets: W W W\nImplicits: 1\n{exarch}31% increased Movement Speed"
		local target={anyOf={"AreaOfEffectEldritchImplicit1"},scope="implicit"}
		local p={id="unknown-implicit-warning",title="Unidentified implicit",slot="Helmet",startingItem=raw,goals={},steps={},preferredMethod="alchemy",nativeRecipe={steps={{method="alchemy"}},targets={target}}}
		build.savers.CraftingProjects:Upsert(p);local w=build.planningWorkspace;w:Show("crafting",{kind="workbench",project=p});ui:frame();ui:click("tab_simulate");ui:key("TAB")
		assert(not w.controls.simulate:IsEnabled() and w.controls.intro.label:find("details below",1,true))
		local text={};for _,row in ipairs(w.controls.resultSummary.list) do text[#text+1]=StripEscapes(row[1]) end
		assert(table.concat(text," "):find("could not be identified uniquely",1,true));frame("crafting-unknown-implicit-inline-warning")
	end
	do
		local raw="Rarity: NORMAL\nStygian Vise\nItem Level: 86\nSockets: A\nImplicits: 1\nHas 1 Abyssal Socket"
		local p={id="stygian-ui",title="Stygian craft",slot="Belt",startingItem=raw,goals={},steps={},preferredMethod="alchemy"}
		build.savers.CraftingProjects:Upsert(p);local w=build.planningWorkspace;w:Show("crafting",{kind="workbench",project=p});ui:frame()
		ui:click("currency_alchemy");ui:click("item");ui:click("keepItem");ui:click("keepWorking")
		local xml=build:SaveDB("Stygian UI");loadBuildFromXML(xml,"Stygian UI");ui:bind(build)
		local saved;for _,entry in ipairs(build.savers.CraftingProjects.projects) do if entry.id==p.id then saved=entry end end
		assert(saved.run.state.sockets[1].color=="A" and saved.inventory[1].state.sockets[1].color=="A")
		build.viewMode="PLANNER";build.planningWorkspace:Show("crafting",{kind="workbench",project=saved});frame("crafting-stygian-abyss-socket")
	end
	ui:restore()
end
-- These checks exercise the audit itself: raw uncoloured list text inherits the
-- background colour, and an oversized line must be detected as clipped.
local ui=UI.install({width=1024,height=768})
local hint=new("ButtonControl"):ButtonControl({"TOPLEFT",nil,"TOPLEFT"},{16,28,100,24},"Hover",function() end)
hint.tooltipText="Alt+3 | Tab: move focus | Enter: activate";hint.layoutAudit="overlay-fixture"
local neighbour=new("ButtonControl"):ButtonControl({"TOPLEFT",nil,"TOPLEFT"},{184,28,100,24},"Neighbour",function() end);neighbour.layoutAudit="overlay-fixture"
main:OpenPopup(600,200,"Audit tooltip",{hint=hint,neighbour=neighbour})
ui:frame();local hx,hy=hint:GetPos();ui.cursorX=hx+30;ui.cursorY=hy+10
ui:frame():write(directory.."/../expected-audit-tooltip.json")
main.popups={};ui.cursorX=-100;ui.cursorY=-100
main:OpenPopup(600,200,"Audit controls",{details=new("TextListControl"):TextListControl({"TOPLEFT",nil,"TOPLEFT"},{16,28,560,120},nil,
	{{height=18,"Unreadable regression fixture"},{height=18,colorCodes.NORMAL..string.rep("Oversized ",20)}})})
for i=1,2 do
	local control=new("ButtonControl"):ButtonControl({"TOPLEFT",nil,"TOPLEFT"},{16+(i-1)*90,156,140,24},"Overlap fixture",function() end)
	control.layoutAudit="negative-fixture";control.anchor.other=main.popups[1];main.popups[1].controls["overlap"..i]=control
end
local overflow=new("ButtonControl"):ButtonControl({"TOPLEFT",nil,"TOPLEFT"},{16,120,80,24},"A button label extending outside its control",function() end)
overflow.layoutAudit="negative-fixture";overflow.anchor.other=main.popups[1];main.popups[1].controls.overflow=overflow
local overlay=new("Control"):Control(nil,{0,0,0,0})
function overlay:Draw()
	SetDrawLayer(nil,100);SetDrawColor(1,1,1);DrawString(1010,250,"LEFT",14,"VAR","Overlay outside the viewport");SetDrawLayer(nil,0)
end
main.popups[1].controls.overlay=overlay
ui:frame():write(directory.."/../expected-audit-failures.json")
ui:restore();main.popups={}
print("HEADLESS_UI_OK",frames)

