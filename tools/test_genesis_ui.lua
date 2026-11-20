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
	ui:text("search","Mutation Cultivation");local x,y=c.results:GetPos();ui:clickAt(x+20,y+12)
	assert(c.canvas.focus==40721,"Search did not focus the current currency passive")
	ui:frame():write(directory.."/"..size[1].."-genesis-search.json")
	ui:click("toggle");assert(main.popups[1].title=="Connect Genesis path","A multi-node path must be confirmed")
	ui:click("confirm");ui:frame():write(directory.."/"..size[1].."-genesis-allocated.json")
	ui:text("search","Parthenogenesis");ui:frame():write(directory.."/"..size[1].."-genesis-all-trees.json")
	local sx,sy=c.results:GetPos();ui:clickAt(sx+20,sy+12);assert(c.canvas.root==42956,"Search must switch to the result's tree")
	ui:choose("branch",22476,"val")
	local function find(name) ui:text("search",name);local sx,sy=c.results:GetPos();ui:clickAt(sx+20,sy+12) end
	find("Increased Attack Modifier Chance");ui:click("toggle");ui:click("confirm")
	find("Increased Caster Modifier Chance");ui:click("toggle")
	assert(main.popups[1].title=="Replace Genesis choice","Replacing a choice must be confirmed")
	ui:frame():write(directory.."/"..size[1].."-genesis-replace-choice.json");ui:click("confirm")
	ui:click("keep");ui:click("keep")
	local saved=assert(build.savers.AtlasPlans.plans[1].genesis,"Genesis draft was not saved")
	local found=false;for _,id in ipairs(saved.nodes) do if id==40721 then found=true end end;assert(found,"The selected passive was not saved")
	ui:restore();main.popups={}
end
print("GENESIS_UI_OK",15)
