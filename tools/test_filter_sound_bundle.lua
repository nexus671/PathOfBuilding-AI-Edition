local dir=assert(arg[1]);arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true
local zip=require('Modules.LootFilterZip');local filters=require('Modules.LootFilters');local UI=require('Modules.HeadlessUI')
local source=dir..'/bundle-test.wav';local f=assert(io.open(source,'wb'));f:write('RIFF-test-sound');f:close()
local source2=dir..'/bundle-test.ogg';f=assert(io.open(source2,'wb'));f:write('OggS-test-sound');f:close()
local profile=filters.profile('audio-bundle','Audio bundle');local raw='Show\n CustomAlertSound "bundle-test.wav;bundle-test.ogg" 200 # note\nShow\n CustomAlertSoundOptional "bundle-test.wav"\nShow\n CustomAlertSound "None"\n'
profile.rules={{id='sound-rule',title='Sounds',text='Show\n Class == "Currency"\n CustomAlertSound "bundle-test.wav;bundle-test.ogg" 200',enabled=true}}
local variantBytes,variantCount=zip.soundBundleVariants(profile,'audio.filter',dir);assert(variantCount==2)
f=assert(io.open(dir..'/sound-variants-check.zip','wb'));f:write(variantBytes);f:close()
local bytes,count=zip.soundBundle(profile,'audio.filter',raw,dir);assert(count==2 and bytes:sub(1,4)=='PK\3\4')
f=assert(io.open(dir..'/sound-bundle-check.zip','wb'));f:write(bytes);f:close()
assert(not pcall(zip.soundBundle,profile,'audio.filter','Show\n CustomAlertSound "missing.wav"',dir))
assert(not pcall(zip.soundBundle,profile,'audio.filter','Show\n CustomAlertSoundOptional "missing.wav"',dir))
local _,absoluteCount=zip.soundBundle(profile,'audio.filter','Show\n CustomAlertSound "'..source..'"',dir);assert(absoluteCount==1)
assert(not pcall(zip.soundBundle,profile,'audio.filter','Show\n CustomAlertSound "../secret.wav"',dir))
assert(not pcall(zip.soundBundle,profile,'audio.filter','Import "more.filter" Optional\n',dir))
assert(not pcall(zip.soundBundle,profile,'audio.filter','Show\n CustomAlertSound unquoted.wav',dir))
local collisionPath=dir..'/sound-as-filter.filter';f=assert(io.open(collisionPath,'wb'));f:write('sound');f:close();local collisionName='pob-sound-'..require('sha1')(collisionPath):sub(1,20)..'.filter'
assert(not pcall(zip.soundBundle,profile,collisionName,'Show\n CustomAlertSound "'..collisionPath..'"',dir))
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
 os.remove(dir..'/audio-'..size[1]..'-sounds.zip')
 local c=require('Classes.LootFilterControl').Export(profile,raw);ui:text('directory',dir);ui:text('filename','audio-'..size[1]..'.filter')
 ui:frame():write(dir..'/'..size[1]..'-filter-sound-export.json');ui:click('soundZip');local sourceControl=main.popups[1].controls.source;local long=dir..'/'..string.rep('long-directory-',12);sourceControl:SetText(long);assert(sourceControl.inactiveText(long):find('click to view',1,true));ui:frame():write(dir..'/'..size[1]..'-filter-sound-bundle.json');assert(sourceControl.buf==long);sourceControl:SetText(dir)
 ui:click('save');assert(main.popups[1] and main.popups[1].title=='Filter and sounds exported');local out=assert(io.open(dir..'/audio-'..size[1]..'-sounds.zip','rb'));assert(out:read(4)=='PK\3\4');out:close()
 if size[1]==960 then
  os.remove(dir..'/audio-all-strictnesses-sounds.zip');main.popups={};require('Classes.LootFilterControl').Export(profile,raw);ui:text('directory',dir);ui:text('filename','audio-all.filter');ui:click('soundZip');ui:click('saveAllSounds');assert(main.popups[1] and main.popups[1].title=='Filter and sounds exported')
 end
end
print('FILTER_SOUND_BUNDLE_OK')
