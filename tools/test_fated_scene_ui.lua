local out=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 for _,property in ipairs({"Fated","Foulborn"}) do
  newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});build.viewMode="CONFIG";ui:bind(build);ui:click("aiBuild");ui:click("nav_filters");ui:click("create2");ui:click("viewSimulate");ui:choose("sceneKind",property.." gear")
  local state=build.planningWorkspace.cache.filters.layout.snapshot();assert(state.sample[property]==true and not build.planningWorkspace.controls.regenerate:IsEnabled())
  if out then ui:frame():write(out.."/"..size[1].."-"..property:lower().."-scene.json") end
  ui:click("sceneStats");local labels={};for _,row in ipairs(main.popups[1].controls.results.list) do labels[#labels+1]=StripEscapes(row[1] or "") end;local text=table.concat(labels," ");assert(text:find("("..property..")",1,true) and text:find("(other)",1,true));ui:click("close");ui:restore()
 end
end
print("FATED_SCENE_UI_OK")
