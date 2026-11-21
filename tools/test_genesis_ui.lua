-- Exercise the Genesis planner through native controls without opening a window.
local directory=assert(arg[1],"Supply an output directory")
arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
	newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
	local plan={id="genesis-ui",title="Genesis UI",version="3.30.0c",budget=10,nodes={},notes=""}
	require("Classes.AtlasPlannerControl").Open(build,plan)
	ui:click("tools");ui:text("search","Genesis");ui:click("choose")
	assert(main.popups[1].title=="Genesis tree","Genesis planner did not open")
	local c=main.popups[1].controls
	ui:frame():write(directory.."/"..size[1].."-genesis-overview.json")
	local function assertBackground()
		local background
		for _,command in ipairs(ui.commands) do if command.asset=="Assets/Genesis/Background.png" then background=command;break end end
		assert(background,"Genesis background was not drawn")
		local cx,cy=c.canvas:GetPos()
		assert(math.abs(background.x-(cx+c.canvas.width/2+(-7576/2-c.canvas.centerX)*c.canvas.scale))<0.1,"Genesis background moved out of world alignment")
		assert(math.abs(background.y-(cy+c.canvas.height/2+(-6640/2-c.canvas.centerY)*c.canvas.scale))<0.1,"Genesis background moved out of world alignment")
		assert(math.abs(background.width-7576*c.canvas.scale)<0.1 and math.abs(background.height-6640*c.canvas.scale)<0.1,"Genesis background scale is incorrect")
	end
	assertBackground()
	local assets={};for _,command in ipairs(ui.commands) do if command.asset then assets[command.asset]=true end end
	assert(assets["Assets/Genesis/FrameSmall.png"] and assets["Assets/Genesis/FrameNotable.png"] and assets["Assets/Genesis/Womb.png"],"Genesis frames or womb artwork were not drawn")
	ui:text("search","Mutation Cultivation");local x,y=c.results:GetPos();ui:clickAt(x+20,y+12)
	assert(c.canvas.focus==40721,"Search did not focus the current currency passive")
	ui:frame():write(directory.."/"..size[1].."-genesis-search.json")
	assertBackground()
	ui:click("toggle");assert(main.popups[1].title=="Connect Genesis path","A multi-node path must be confirmed")
	ui:click("confirm");ui:frame():write(directory.."/"..size[1].."-genesis-allocated.json")
	assets={};for _,command in ipairs(ui.commands) do if command.asset then assets[command.asset]=true end end
	assert(assets["Assets/Genesis/FrameSmallActive.png"] and assets["Assets/Genesis/FrameNotableActive.png"],"Allocated Genesis frame artwork was not drawn")
	local nx,ny=c.canvas:Position(c.canvas.tree.nodes[40721]);local cx,cy=c.canvas:GetPos()
	ui:clickAt(cx+nx+15,cy+ny);assert(c.canvas.focus==40721,"The notable frame edge did not select its node")
	ui:text("search","Parthenogenesis");ui:frame():write(directory.."/"..size[1].."-genesis-all-trees.json")
	local sx,sy=c.results:GetPos();ui:clickAt(sx+20,sy+12);assert(c.canvas.root==42956,"Search must switch to the result's tree")
	ui:choose("branch",22476,"val")
	local function find(name) ui:text("search",name);local sx,sy=c.results:GetPos();ui:clickAt(sx+20,sy+12) end
	find("Devoted Technique");assert(c.canvas.focus==20212,"Search must focus the choice node")
	local details={};for _,row in ipairs(c.details.list) do details[#details+1]=StripEscapes(row[1]) end;assert(table.concat(details," "):find("Equipment maximum 16",1,true),"Published point reference is missing")
	ui:frame():write(directory.."/"..size[1].."-genesis-choice-art.json")
	local art=false;for _,command in ipairs(ui.commands) do if command.asset=="Assets/Genesis/KeepersSelectionNotable.png" then art=true end end
	assert(art,"Choice node art was not drawn")
	find("Increased Attack Modifier Chance");ui:click("toggle");ui:click("confirm")
	find("Increased Caster Modifier Chance");ui:click("toggle")
	assert(main.popups[1].title=="Replace Genesis choice","Replacing a choice must be confirmed")
	ui:frame():write(directory.."/"..size[1].."-genesis-replace-choice.json");ui:click("confirm")
	ui:click("keep");ui:click("keep")
	local saved=assert(build.savers.AtlasPlans.plans[1].genesis,"Genesis draft was not saved")
	local found=false;for _,id in ipairs(saved.nodes) do if id==40721 then found=true end end;assert(found,"The selected passive was not saved")
	ui:restore();main.popups={}
end
print("GENESIS_UI_OK",18)
