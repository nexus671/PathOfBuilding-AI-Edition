local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local shared=require("Modules.LootFilterSharedStyles")
local raw=[[# untouched
Show
 SetTextColor 255 0 0 # red
 SetBackgroundColor 0 0 0
 PlayAlertSound 2 200 # alert
 CustomAlertSound "C:\sounds\a#1.wav" 100
Hide
 SetTextColor 0 255 0 255
Import "other.filter"
 SetTextColor 255 0 0
]]
local entries={
	{key="SetTextColor",from="FF0000FF",to="00FF00FF"},
	{key="SetTextColor",from="00FF00FF",to="0000FFFF"},
	{key="SetBackgroundColor",from="000000F0",to="11223344"},
	{key="PlayAlertSound",from="2",to="6"},
	{key="CustomAlertSound",from="C:\\sounds\\a#1.wav",to="C:\\sounds\\b.wav"},
}
local before=shared.list(raw);assert(#before==10,"Unexpected shared style inventory")
local result=shared.apply(raw,entries)
assert(result:find("SetTextColor 0 255 0 255 # red",1,true),"Replacement lost the comment or chained into another mapping")
assert(result:find("SetTextColor 0 0 255 255",1,true),"Second source was not replaced")
assert(result:find("SetBackgroundColor 17 34 51 68",1,true),"Background default alpha was not matched")
assert(result:find("PlayAlertSound 6 200 # alert",1,true),"Alert volume or comment was lost")
assert(result:find('CustomAlertSound "C:\\sounds\\b.wav" 100',1,true),"Quoted custom sound was not preserved")
assert(result:find('Import "other.filter"\n SetTextColor 255 0 0',1,true),"An import's contents were changed without loading it")
local silent=shared.apply(raw,{{key="PlayAlertSound",from="2",to="None"},{key="CustomAlertSound",from="C:\\sounds\\a#1.wav",to="None"}})
assert(silent:find("PlayAlertSound None # alert",1,true) and silent:find('CustomAlertSound "None"',1,true),"Muting shared sounds must remove their volume, quote custom None and preserve comments")
local muted='Show\n PlayAlertSound None # muted\n PlayAlertSoundPositional None\n CustomAlertSound "None"'
local mutedRows=shared.list(muted);local foundMuted=false
for _,row in ipairs(mutedRows) do if row.key=="AlertSound" and row.value=="None" and row.count==2 then foundMuted=true end end
assert(foundMuted,"Silenced sounds must appear in the shared-style browser")
local enabled=shared.apply(muted,{{key="AlertSound",from="None",to="3"},{key="PlayAlertSoundPositional",from="None",to="4"},{key="CustomSound",from="None",to="new.wav"}})
assert(enabled:find("PlayAlertSound 3 # muted",1,true) and enabled:find("PlayAlertSoundPositional 4",1,true) and enabled:find('CustomAlertSound "new.wav"',1,true),"Re-enabling muted sounds must preserve comments, specificity and default volumes")
assert(shared.apply(raw,{})==raw,"Empty mappings changed the filter")
local grouped='Show\n SetTextColor 255 0 0\n SetBorderColor 255 0 0\n SetBackgroundColor 255 0 0 255\n PlayAlertSound 2 100\n PlayAlertSoundPositional 2 200'
local groupedResult=shared.apply(grouped,{{key="Colour",from="FF0000FF",to="00FF00FF"},{key="SetBorderColor",from="FF0000FF",to="0000FFFF"},{key="AlertSound",from="2",to="6"}})
assert(groupedResult:find("SetTextColor 0 255 0 255",1,true) and groupedResult:find("SetBackgroundColor 0 255 0 255",1,true),"Shared colour did not reach all matching uses")
assert(groupedResult:find("SetBorderColor 0 0 255 255",1,true),"Specific replacement must take precedence over the shared group")
assert(groupedResult:find("PlayAlertSound 6 100",1,true) and groupedResult:find("PlayAlertSoundPositional 6 200",1,true),"Shared alert did not preserve positional mode and volume")
local preview=require("Classes.LootFilterSharedStylesControl").previewStyles
local reenabledPreview=preview({},{key="PlayAlertSound",value="None"},"3")
assert(reenabledPreview.PlayAlertSound and reenabledPreview.PlayAlertSound[1]=="3" and #reenabledPreview.PlayAlertSound==1,"Re-enabled preview must retain the default sound volume")
local borderOnly=shared.list('Show\n SetBorderColor 255 0 0');local groupRow;for _,row in ipairs(borderOnly) do if row.key=="Colour" then groupRow=row end end
assert(groupRow and groupRow.types.SetBorderColor and not groupRow.types.SetTextColor,"Shared inventory lost actual colour uses")
local borderPreview=preview({},groupRow,"00FF00FF");assert(table.concat(borderPreview.SetBorderColor,",")=="0,255,0,255" and table.concat(borderPreview.SetTextColor,",")=="255,235,175,255","Grouped preview did not retain the actual border-only use")
local positionalOnly=shared.list('Show\n PlayAlertSoundPositional 2 100');local alertRow;for _,row in ipairs(positionalOnly) do if row.key=="AlertSound" then alertRow=row end end
local positionalPreview=preview({},alertRow,"6");assert(positionalPreview.PlayAlertSoundPositional and not positionalPreview.PlayAlertSound,"Grouped preview lost positional sound mode")
local previewProfile={sharedStyles={{key="SetTextColor",from="FF0000FF",to="0000FFFF"}}}
local shown=preview(previewProfile,{key="Colour",value="FF0000FF"},"00FF00FF");assert(table.concat(shown.SetTextColor,",")=="0,0,255,255","Preview ignored a more specific replacement")
previewProfile.appearance={textColor={255,255,255,255},alertId=8,alertVolume=50}
shown=preview(previewProfile,{key="Colour",value="FF0000FF"},"00FF00FF");assert(table.concat(shown.SetTextColor,",")=="255,255,255,255","Preview ignored the whole-filter colour")
shown=preview(previewProfile,{key="AlertSound",value="2"},"6");assert(table.concat(shown.PlayAlertSound,",")=="8,50","Sound preview ignored whole-filter settings")
assert(not pcall(shared.validate,{{key="SetTextColor",from="FF0000FF",to="00FF00FF"},{key="SetTextColor",from="FF0000FF",to="FFFFFFFF"}}),"Duplicate sources were accepted")
newBuild();local filters=require("Modules.LootFilters");local profile=filters.profile("shared","Shared styles")
profile.template="Show\n SetTextColor 255 0 0\n PlayAlertSound 2 200";profile.sharedStyles={entries[1],entries[4]}
local compiled=filters.compile(profile);assert(compiled:find("SetTextColor 0 255 0 255",1,true) and compiled:find("PlayAlertSound 6 200",1,true),"Compiled filter did not use shared styles")
profile.appearance={textColor={255,255,255,255}};compiled=filters.compile(profile);assert(compiled:find("SetTextColor 255 255 255 255",1,true),"Whole-filter appearance must take precedence")
local imported=copyTable(profile);imported.appearance=nil;imported.template='Import "linked.filter"\nShow';imported.importFiles={{name="linked.filter",text="Show\n SetTextColor 255 0 0"}}
compiled=filters.compile(imported);assert(compiled:find("SetTextColor 0 255 0 255",1,true),"Loaded imports did not receive the shared replacement")
imported.importFiles=nil;local report;compiled,report=filters.compile(imported);local warning=false;for _,diagnostic in ipairs(report.diagnostics) do if diagnostic.warning and diagnostic.warning:find("unresolved imported files",1,true) then warning=diagnostic.line~=nil end end;assert(warning,"Unresolved imports must report that replacements cannot change them")
local ruthless=copyTable(profile);ruthless.mode="Ruthless";ruthless.sharedStyles={{key="SetTextColor",from="FF0000FF",to="00000000"}};assert(not pcall(filters.compile,ruthless),"Ruthless text opacity restriction was bypassed")
build.savers.LootFilters:Upsert(profile);local xml={};build.savers.LootFilters:Save(xml)
local restored=filters.new(build);restored:Load(xml);assert(restored.data.profiles[1].sharedStyles[1].from=="FF0000FF","Saved profile lost its shared styles")
local collections=require("Modules.LootFilterCollections");profile.palettes={{id="p",title="Palette",theme="default",appearance={},sharedStyles=profile.sharedStyles}}
local restoredPalette=collections.palette(profile,"p");assert(#restoredPalette.sharedStyles==2,"Palette lost its shared styles")
local ui=require("Modules.HeadlessUI").install({width=640,height=480});ui:bind(build);local kept
profile.sharedStyles=nil;profile.appearance=nil
for _,size in ipairs({{640,480},{960,640},{1280,720}}) do
	ui:resize(size[1],size[2]);require("Classes.LootFilterSharedStylesControl").Open(profile,function(value) kept=value end)
	ui:text("search","FF0000FF");if output then ui:frame():write(output.."/"..size[1].."-shared-style-browser.json") end
	ui:click("choose");local editor=require("Classes.LootFilterSharedStylesControl");local original=editor.previewStyles;local calls=0
	editor.previewStyles=function(...) calls=calls+1;return original(...) end
	ui:text("target","11223344");ui:frame();ui:frame();assert(calls==1,"An unchanged preview was recomputed")
	ui:text("target","55667788");ui:frame();assert(calls==2,"Editing the replacement did not refresh the preview")
	editor.previewStyles=original;ui:text("target","11223344");if output then ui:frame():write(output.."/"..size[1].."-shared-style-edit.json") end;ui:click("keep")
	assert(kept and kept.sharedStyles[1].from=="FF0000FF" and kept.sharedStyles[1].to=="11223344","Shared style editor did not keep the chosen replacement")
	require("Classes.LootFilterSharedStylesControl").Open(kept,function(value) kept=value end)
	ui:text("search","FF0000FF");ui:click("choose");ui:click("remove");assert(#kept.sharedStyles==0,"Shared style editor did not remove the replacement")
end
ui:restore()
for _,size in ipairs({{640,480},{960,640},{1280,720}}) do
	newBuild();ui=require("Modules.HeadlessUI").install({width=size[1],height=size[2]});ui:bind(build)
	profile=filters.profile("workspace","Shared");profile.template="Show\n SetTextColor 255 0 0";build.savers.LootFilters:Upsert(profile)
	build.planningWorkspace=require("Modules.PlanningWorkspace").new(build);build.viewMode="PLANNER";build.planningWorkspace:Show("filters")
	ui:click("viewStyle");if output then ui:frame():write(output.."/"..size[1].."-shared-style-workspace.json") end
	ui:click("sharedStyles");ui:text("search","FF0000FF");ui:click("choose");ui:text("target","00FF00FF");ui:click("keep")
	local function current() return build.planningWorkspace.cache.filters.layout.snapshot().data.profiles[1] end
	assert(current().sharedStyles[1].to=="00FF00FF");ui:click("undo");assert(not current().sharedStyles);ui:click("redo");assert(current().sharedStyles[1].to=="00FF00FF","Workspace undo/redo lost the replacement")
	ui:restore()
end
local bulk={};for i=1,600 do bulk[#bulk+1]={key="Colour",from=string.format("%08X",i),to="FFFFFFFF"} end
local large=filters.profile("many","Many replacements");large.template="Show\n SetTextColor 255 0 0";large.sharedStyles=bulk
local checked=filters.validate({schemaVersion=1,activeId=large.id,profiles={large}}).profiles[1];assert(#checked.sharedStyles==600,"Shared replacements were capped below the metadata guard")
newBuild();ui=require("Modules.HeadlessUI").install({width=960,height=640});ui:bind(build);local keptLarge
require("Classes.LootFilterSharedStylesControl").Open(checked,function(value) keptLarge=value end);ui:text("search","00000258");ui:click("choose")
assert(main.popups[1].controls.target.buf=="FFFFFFFF","A later saved replacement was not reachable");ui:click("remove");assert(#keptLarge.sharedStyles==599,"Removing a later replacement lost other entries");ui:restore()
large.palettes={{id="large",title="Large palette",theme="default",appearance={},sharedStyles=large.sharedStyles}}
build.savers.LootFilters:Upsert(large);local largeXml={};build.savers.LootFilters:Save(largeXml)
local reopened=filters.new(build);reopened:Load(largeXml);local savedLarge=reopened.data.profiles[1]
assert(#savedLarge.sharedStyles==600 and #savedLarge.palettes[1].sharedStyles==600,"Large shared styles did not survive save and reopen")
savedLarge.sharedStyles={};local restoredLarge=collections.palette(savedLarge,"large");assert(#restoredLarge.sharedStyles==600 and restoredLarge.sharedStyles[600].from=="00000258","Large palette did not restore its replacements")
print("FILTER_SHARED_STYLES_OK")
