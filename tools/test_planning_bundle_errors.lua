local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI");local bundles=require("Modules.PlanningBundle");local bridge=require("Modules.DesktopBuildBridge")
for _,size in ipairs({{1280,720},{1024,768},{960,640},{720,600}}) do
	newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
	local valid=bundles.export(build);require("Classes.PlanningToolsControl").Bundle(build);local controls=main.popups[1].controls
	ui:frame()
	local lastRight=0
	for _,key in ipairs({"export","paste","review","close"}) do local x=controls[key]:GetPos();local width=controls[key]:GetSize();assert(x>=lastRight,"Overlapping bundle controls: "..key);lastRight=x+width end
	ui.clipboard=valid;ui:click("paste");assert(controls.review:IsEnabled(),"Valid bundle was not available for review")
	ui.clipboard=valid.." \r\n\t";ui:click("paste");assert(controls.review:IsEnabled(),"Trailing whitespace should be accepted")
	ui.clipboard=valid.."{}";ui:click("paste");assert(#main.popups==2 and not controls.review:IsEnabled(),"Extra data after a bundle must be rejected")
	main:ClosePopup();ui.clipboard=valid;ui:click("paste");assert(controls.review:IsEnabled(),"A valid bundle could not be pasted after extra data")
	ui.clipboard="{invalid bundle";ui:click("paste");assert(#main.popups==2 and not controls.review:IsEnabled(),"Invalid paste did not clear the previous review")
	assert(controls.text.buf=="{invalid bundle","Invalid input was not retained")
	local message="";for _,control in pairs(main.popups[1].controls) do if type(control.label)=="string" then message=message..control.label end end
	assert(message:find("This is not a valid planning bundle.",1,true),"The bundle error was not explained")
	if output then ui:frame():write(output.."/"..size[1].."-planning-bundle-error.json") end
	main:ClosePopup();ui.clipboard=valid;ui:click("paste");assert(controls.review:IsEnabled(),"A valid bundle could not be pasted after an error")
	ui:click("export");assert(not controls.review:IsEnabled(),"Export retained an unrelated earlier review");ui:click("paste");assert(controls.review:IsEnabled(),"The copied bundle could not be inspected")
	if size[1]==960 then
		local original=bridge.serialize;bridge.serialize=function() return string.rep("x",bundles.limit+1) end
		ui.clipboard="clipboard sentinel";ui:click("export");bridge.serialize=original
		assert(#main.popups==2 and ui.clipboard=="clipboard sentinel" and controls.review:IsEnabled(),"Oversized export lost the clipboard or previous review")
		main:ClosePopup()
	end
	ui:restore();main.popups={}
end
print("PLANNING_BUNDLE_ERRORS_OK")
