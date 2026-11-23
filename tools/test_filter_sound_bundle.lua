local dir=assert(arg[1]);arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true
local zip=require('Modules.LootFilterZip');local filters=require('Modules.LootFilters');local UI=require('Modules.HeadlessUI')
local source=dir..'/bundle-test.wav';local f=assert(io.open(source,'wb'));f:write('RIFF-test-sound');f:close()
local source2=dir..'/bundle-test.ogg';f=assert(io.open(source2,'wb'));f:write('OggS-test-sound');f:close()
local profile=filters.profile('audio-bundle','Audio bundle');local raw='Show\n CustomAlertSound "bundle-test.wav;bundle-test.ogg" 200 # note\nShow\n CustomAlertSoundOptional "bundle-test.wav"\nShow\n CustomAlertSound "None"\n'
local bytes,count=zip.soundBundle(profile,'audio.filter',raw,dir);assert(count==2 and bytes:sub(1,4)=='PK\3\4')
f=assert(io.open(dir..'/sound-bundle-check.zip','wb'));f:write(bytes);f:close()
assert(not pcall(zip.soundBundle,profile,'audio.filter','Show\n CustomAlertSound "missing.wav"',dir))
assert(not pcall(zip.soundBundle,profile,'audio.filter','Show\n CustomAlertSoundOptional "missing.wav"',dir))
local _,absoluteCount=zip.soundBundle(profile,'audio.filter','Show\n CustomAlertSound "'..source..'"',dir);assert(absoluteCount==1)
assert(not pcall(zip.soundBundle,profile,'audio.filter','Show\n CustomAlertSound "../secret.wav"',dir))
assert(not pcall(zip.soundBundle,profile,'audio.filter','Import "more.filter" Optional\n',dir))
assert(not pcall(zip.soundBundle,profile,'audio.filter','Show\n CustomAlertSound unquoted.wav',dir))
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
 os.remove(dir..'/audio-'..size[1]..'-sounds.zip')
 local c=require('Classes.LootFilterControl').Export(profile,raw);ui:text('directory',dir);ui:text('filename','audio-'..size[1]..'.filter')
 ui:frame():write(dir..'/'..size[1]..'-filter-sound-export.json');ui:click('soundZip');ui:frame():write(dir..'/'..size[1]..'-filter-sound-bundle.json')
 ui:click('save');assert(main.popups[1] and main.popups[1].title=='Filter and sounds exported');local out=assert(io.open(dir..'/audio-'..size[1]..'-sounds.zip','rb'));assert(out:read(4)=='PK\3\4');out:close()
end
print('FILTER_SOUND_BUNDLE_OK')
