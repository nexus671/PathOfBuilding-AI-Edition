-- Check direct Atlas, crafting and filter error handlers with long messages.
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI")
local long=string.rep("Review the saved settings before continuing. ",160).."Final guidance."
for _,size in ipairs({{960,640},{1024,768},{1280,720}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
 local function check(title,name)
  local popup=assert(main.popups[1]);assert(popup.title==title,title);assert(popup.width<=size[1]-40 and popup.height<=size[2]-48)
  local list=assert(popup.controls.message);local text={};for _,row in ipairs(list.list) do text[#text+1]=StripEscapes(row[1] or "") end
  assert(table.concat(text," "):gsub("%s+"," "):find("Final guidance.",1,true),"missing final guidance");ui:frame();local bar=list.controls.scrollBar;assert(bar.offsetMax>0,"not scrollable: "..tostring(bar.offsetMax));bar:SetOffset(bar.offsetMax)
  if output then ui:frame():write(output.."/"..size[1].."-"..name.."-error.json") end
  ui:click("close")
 end
 local atlas=require("Modules.AtlasPlanner");local plan={id="bounded",title="Bounded",version="3.30.0c",budget=150,nodes={}}
 require("Classes.AtlasPlanningControl").Open(build,plan,function() end)
 local validate=atlas.validate;atlas.validate=function() error(long,0) end;ui:click("keep");atlas.validate=validate;check("Atlas strategy","atlas");assert(main.popups[1].title=="Atlas stages and strategy");ui:click("close")
 local store=build.savers.CraftingProjects;local project={id="bounded",title="Bounded",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={{action="First step"}}};store:Upsert(project)
 local guide=require("Classes.CraftingGuideStepsControl").Open(build,project.id);guide.results.planningSelect(guide.results.list[1]);local upsert=store.Upsert;store.Upsert=function() error(long,0) end;ui:click("toggle");store.Upsert=upsert;check("Crafting guide","crafting");assert(not store.projects[1].steps[1].done);ui:click("close")
 local files=require("Modules.LootFilterImports");local read=files.readFile;local kept=false;require("Classes.LootFilterImportControl").Open(require("Modules.LootFilters").profile("bounded","Bounded"),function() kept=true end)
 files.readFile=function() error(long,0) end;ui:click("loadFile");files.readFile=read;check("Included filter","filter");assert(not kept);ui:click("cancel")
 local bridge=require("Modules.DesktopBuildBridge");require("Classes.BuildProposalControl").Goals(build)
 local configure=bridge.configure;bridge.configure=function() error(long,0) end;ui:click("save");bridge.configure=configure;check("Build proposal","proposal");assert(main.popups[1].title=="Build goals and budget");ui:click("close");ui:restore()
end
print("BOUNDED_PLANNING_ERRORS_OK")
