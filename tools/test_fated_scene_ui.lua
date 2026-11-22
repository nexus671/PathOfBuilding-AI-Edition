local out=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});build.viewMode="CONFIG";ui:bind(build);ui:click("aiBuild");ui:click("nav_filters");ui:click("create2");ui:click("viewSimulate");ui:choose("sceneKind","Fated gear")
 local state=build.planningWorkspace.cache.filters.layout.snapshot();assert(state.sample.Fated==true and not build.planningWorkspace.controls.regenerate:IsEnabled())
 if out then ui:frame():write(out.."/"..size[1].."-fated-scene.json") end
 ui:click("sceneStats");local labels={};for _,row in ipairs(main.popups[1].controls.results.list) do labels[#labels+1]=StripEscapes(row[1] or "") end;local text=table.concat(labels," ");assert(text:find("(Fated)",1,true) and text:find("(other)",1,true));ui:click("close");ui:restore()
end
print("FATED_SCENE_UI_OK")
