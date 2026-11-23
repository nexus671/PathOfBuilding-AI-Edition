local output=arg[1];arg={};dofile('HeadlessWrapper.lua');local UI=require('Modules.HeadlessUI')
for _,size in ipairs({{960,640},{1024,768},{1280,720}}) do
 newBuild();local ui=UI.install({width=size[1],height=size[2]});build.viewMode='ITEMS';ui:bind(build)
 local db=build.itemsTab.controls.visceraDB;build.itemsTab.controls.selectDB:SelByValue('Viscera');ui:frame();assert(db:IsShown() and db.controls.sort and db.sortMode=='NAME')
 db.controls.slot:SelByValue('Arm');db.listBuildFlag=true;ui:frame();if output then ui:frame():write(output..'/'..size[1]..'-viscera-sort.json') end
 local selected={};for _,item in pairs(db.db.list) do if item.name:find("Lesser Warden's Arm",1,true) or item.name:find("Crustacean's Claw",1,true) then selected[#selected+1]=item end end
 assert(#selected>=2);db.db={list=selected};db:SetSortMode('Life');local task=coroutine.create(function() db:ListBuilder() end)
 repeat local ok,err=coroutine.resume(task);assert(ok,err) until coroutine.status(task)=='dead'
 assert(db.list[1].name:find("Lesser Warden's Arm",1,true));assert(db.list[1].measuredPower>db.list[#db.list].measuredPower)
 ui:restore()
end
print('VISCERA_SORT_UI_OK')
