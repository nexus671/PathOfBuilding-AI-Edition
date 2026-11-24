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
assert(silent:find("PlayAlertSound None # alert",1,true) and silent:find("CustomAlertSound None",1,true),"Muting shared sounds must remove their volume and preserve comments")
assert(shared.apply(raw,{})==raw,"Empty mappings changed the filter")
local grouped='Show\n SetTextColor 255 0 0\n SetBorderColor 255 0 0\n SetBackgroundColor 255 0 0 255\n PlayAlertSound 2 100\n PlayAlertSoundPositional 2 200'
local groupedResult=shared.apply(grouped,{{key="Colour",from="FF0000FF",to="00FF00FF"},{key="SetBorderColor",from="FF0000FF",to="0000FFFF"},{key="AlertSound",from="2",to="6"}})
assert(groupedResult:find("SetTextColor 0 255 0 255",1,true) and groupedResult:find("SetBackgroundColor 0 255 0 255",1,true),"Shared colour did not reach all matching uses")
assert(groupedResult:find("SetBorderColor 0 0 255 255",1,true),"Specific replacement must take precedence over the shared group")
assert(groupedResult:find("PlayAlertSound 6 100",1,true) and groupedResult:find("PlayAlertSoundPositional 6 200",1,true),"Shared alert did not preserve positional mode and volume")
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
	ui:click("choose");ui:text("target","11223344");if output then ui:frame():write(output.."/"..size[1].."-shared-style-edit.json") end;ui:click("keep")
	assert(kept and kept.sharedStyles[1].from=="FF0000FF" and kept.sharedStyles[1].to=="11223344","Shared style editor did not keep the chosen replacement")
	require("Classes.LootFilterSharedStylesControl").Open(kept,function(value) kept=value end)
	ui:text("search","FF0000FF");ui:click("choose");ui:click("remove");assert(#kept.sharedStyles==0,"Shared style editor did not remove the replacement")
end
ui:restore()
newBuild();ui=require("Modules.HeadlessUI").install({width=1280,height=720});ui:bind(build)
profile=filters.profile("workspace","Shared");profile.template="Show\n SetTextColor 255 0 0";build.savers.LootFilters:Upsert(profile)
build.planningWorkspace=require("Modules.PlanningWorkspace").new(build);build.viewMode="PLANNER";build.planningWorkspace:Show("filters")
ui:click("viewStyle");ui:click("sharedStyles");ui:text("search","FF0000FF");ui:click("choose");ui:text("target","00FF00FF");ui:click("keep")
local function current() return build.planningWorkspace.cache.filters.layout.snapshot().data.profiles[1] end
assert(current().sharedStyles[1].to=="00FF00FF");ui:click("undo");assert(not current().sharedStyles);ui:click("redo");assert(current().sharedStyles[1].to=="00FF00FF","Workspace undo/redo lost the replacement")
ui:restore()
print("FILTER_SHARED_STYLES_OK")
