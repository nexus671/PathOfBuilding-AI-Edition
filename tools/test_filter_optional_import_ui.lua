-- Verify the optional-import assumption through the native popup and persistence.
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI");local filters=require("Modules.LootFilters")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
	newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
	local profile=filters.profile("optional-ui","Optional import");profile.template='Import "missing.filter" Optional\nHide'
	local files,absent;require("Classes.LootFilterImportControl").Open(profile,function(a,b) files,absent=a,b end)
	ui:click("findImports");assert(main.popups[1].title=="Unresolved filter imports")
	if output then ui:frame():write(output.."/"..size[1].."-filter-optional-import.json") end
	ui:click("secondary");local browser=main.popups[1].controls
	assert(browser.results.list[1].entry.label:find("Preview assumes absent",1,true))
	ui:click("close");ui:click("keep");profile.importFiles=files;profile.absentOptionalImports=absent
	local result=filters.simulate(profile,{BaseType="Iron Hat"});assert(result.action=="Hide" and result.reasons[1]:find("assumes optional",1,true))
	local raw=filters.compile(profile);assert(raw:find('Import "missing.filter" Optional',1,true))
	local saver=filters.new(build);saver.data={schemaVersion=1,activeId=profile.id,profiles={profile}};local xml={};saver:Save(xml)
	local restored=filters.new(build);restored:Load(xml);assert(restored.data.profiles[1].absentOptionalImports[1]=="missing.filter")
end
do
	local profile=filters.profile("plain-include","Plain include");profile.template='Import "file.filter"\nShow';local files
	require("Classes.LootFilterImportControl").Open(profile,function(saved) files=saved end);local controls=main.popups[1].controls
	controls.name:SetText("file.filter");controls.text:SetText("Hide");controls.keep:Click()
	assert(files and files[1].name=="file.filter","Adding an included file without assumptions failed")
	main.popups={}
end
do
	local profile=filters.profile("nested-optional","Nested optional");profile.template='Import "outer.filter"\nShow'
	profile.importFiles={{name="outer.filter",text='Import "missing.filter" Optional\nHide\n BaseType "Iron Hat"'}}
	local before=copyTable(profile);assert(filters.simulate(before,{BaseType="Iron Hat"}).status=="unknown")
	profile.absentOptionalImports={"missing.filter"}
	local result=filters.simulate(profile,{BaseType="Iron Hat"});assert(result.action=="Hide" and result.reasons[1]:find("assumes optional",1,true))
	local changes=require("Modules.LootFilterEditing").review({activeId=before.id,profiles={before}},{activeId=profile.id,profiles={profile}})
	assert(table.concat(changes[1].details," "):find("Preview now assumes optional file absent",1,true))
	local impact=require("Modules.LootFilterImpact");local comparison=impact.page(impact.prepare(before,profile),{{BaseType="Iron Hat"}},0,1)
	assert(comparison.results[1].category=="Needs review" and comparison.results[1].after.reasons[1]:find("assumes optional",1,true))
	profile.template='Import "missing.filter"\nShow';assert(filters.simulate(profile,{BaseType="Iron Hat"}).status=="unknown")
	profile.template='Import "missing.filter" Optional\nShow';profile.importFiles={{name="missing.filter",text='Import "missing.filter" Optional'}}
	assert(filters.simulate(profile,{BaseType="Iron Hat"}).status=="unknown")
	profile.importFiles={{name="missing.filter",text="Show"}};assert(filters.simulate(profile,{BaseType="Iron Hat"}).action=="Show")
end
do
	newBuild();main.popups={};local ui=UI.install({width=960,height=640});ui:bind(build)
	local profile=filters.profile("attach-optional","Attach filters")
	profile.template='Import "outer.filter"\nHide'
	local files, absent
	require("Classes.LootFilterImportControl").Open(profile,function(a,b) files,absent=a,b end)
	ui:text("name","outer.filter");ui:text("text",'Import "inner.filter" Optional\nShow')
	ui:click("findImports");assert(main.popups[1].title=="Unresolved filter imports")
	ui:click("secondary");ui:click("secondary");ui:click("close");ui:click("keep")
	assert(files and files[1].name=="outer.filter" and absent==nil)
end
print("FILTER_OPTIONAL_IMPORT_UI_OK")
