arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true
local UI=require('Modules.HeadlessUI')
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});build.viewMode='ITEMS';ui:bind(build)
 local tab=build.itemsTab;tab:SetDisplayItem(new('Item'):Item('Rarity: NORMAL\nAmber Amulet\nItem Level: 86'));tab:AnointDisplayItem()
 local popup=assert(main.popups[1]);local control=assert(popup.controls.notableDB);control.controls.search:SetText('Constitution')
 for _,stat in ipairs({'Life','FullDPS'}) do
  local sort=control.controls.sort;sort:SelByValue(stat,'sortMode');sort.selFunc(sort.selIndex,sort:GetSelValue())
  for _=1,200 do ui:frame();if not control.listBuildFlag and not control.listBuilder then break end end
  assert(not control.listBuilder and control.sortDetail.stat==stat and #control.list==1 and control.list[1].dn=='Constitution','Anoint sort did not finish for '..stat)
 end
 ui:click('close');ui:restore()
end
print('ANOINT_SORT_UI_OK')
