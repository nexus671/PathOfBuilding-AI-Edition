return function(ui,frame)
	local rule={id="minimal-preview",title="Minimal preview",text='Minimal\n BaseType == "Iron Hat"'}
	require("Classes.LootFilterAppearance").Open(rule,function() end,function() end)
	local c=main.popups[1].controls
	assert(c.backgroundHex.buf=="080C0E00" and c.sizeLabel.label():find("minimum",1,true),"Minimal defaults were not shown")
	frame("filter-minimal-default")
	ui:choose("action","Show");assert(c.backgroundHex.buf=="080C0EFF","Show defaults were not restored")
	frame("filter-minimal-show");ui:click("cancel")
	local saved;require("Classes.LootFilterControl").EditRule(rule,function(value) saved=value end,"Normal")
	assert(not main.popups[1].controls.keepRule:IsEnabled(),"Incompatible Minimal action could be kept in Normal mode");frame("filter-mode-repair")
	ui:choose("action","Show");ui:click("conditions");assert(#main.popups[1].controls.action.list==2,"Advanced editor offered the wrong mode actions");frame("filter-mode-conditions")
	ui:click("keepRule");assert(saved and saved.text:match("^Show"),"Mode repair did not keep the selected action")
end
