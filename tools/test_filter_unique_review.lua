arg={};dofile('HeadlessWrapper.lua');newBuild()
local filters=require('Modules.LootFilters');local lib=require('Modules.LootFilterLibrary')
local function warning(report) for _,d in ipairs(report.diagnostics) do if d.warning and d.warning:find('Bottled Faith',1,true) then return d end end end
local p=filters.profile('review','Review');p.strictness=6;p.rules={{id='unique-sulphur',title='Old disabled rule',text='Hide',enabled=false}}
local raw,report=filters.compile(p);local w=assert(warning(report));assert(w.line and w.warning:find('sample',1,true))
local found=false;for _,item in ipairs(lib.scene(p,build,'Flasks & tinctures',1,83,86)) do if item.BaseType=='Sulphur Flask' and item.Rarity=='Unique' then found=true;local result=filters.simulate(p,item);assert(result.action=='Hide' and result.status=='matched') end end;assert(found)
main.popups={};local ui=require('Modules.HeadlessUI').install({width=1024,height=768});ui:bind(build)
local saved;require('Classes.LootFilterControl').Audit(p,report,function(value) saved=value end);ui:text('search','Bottled Faith');local controls=main.popups[1].controls
assert(controls.results.list[1] and (controls.results.list[1][1] or ''):find('Sulphur Flask',1,true),'Audit could not find the hidden unique sample')
controls.results.onClick({line=controls.results.list[1]});assert(controls.choose:IsEnabled());ui:click('choose')
assert(saved and saved.rules[1].id=='unique-sulphur-2' and saved.rules[2].enabled==false);assert(not warning(select(2,filters.compile(saved))))
local sample=lib.sample();sample.BaseType='Sulphur Flask';sample.Class='Utility Flasks';sample.Rarity='Unique';assert(filters.simulate(saved,sample).action=='Show')
build.savers.LootFilters:Upsert(saved);local xml=build:SaveDB('Unique flask review');loadBuildFromXML(xml,'Unique flask review');ui:bind(build)
local restored=filters.find(build.savers.LootFilters.data,'review');assert(restored and restored.rules[1].id=='unique-sulphur-2' and not warning(select(2,filters.compile(restored))))
ui:restore();main.popups={}
p.strictness=5;assert(not warning(select(2,filters.compile(p))))
p.strictness=6;p.rules={filters.rule('faith','Show unique Sulphur',{'Rarity == Unique','BaseType == "Sulphur Flask"'})}
local revised,ok=filters.compile(p);assert(not warning(ok));assert(raw~=revised)
p.rules={filters.rule('uncertain','Unknown before target',{'FutureKeyword True'})};assert(not warning(select(2,filters.compile(p))))
print('FILTER_UNIQUE_REVIEW_OK')
