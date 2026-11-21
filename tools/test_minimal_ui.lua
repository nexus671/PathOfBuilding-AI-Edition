return function(ui,frame)
	local rule={id="minimal-preview",title="Minimal preview",text='Minimal\n BaseType == "Iron Hat"'}
	require("Classes.LootFilterAppearance").Open(rule,function() end,function() end)
	local c=main.popups[1].controls
	assert(c.backgroundHex.buf=="080C0E00" and c.sizeLabel.label():find("minimum",1,true),"Minimal defaults were not shown")
	frame("filter-minimal-default")
	ui:choose("action","Show");assert(c.backgroundHex.buf=="080C0EFF","Show defaults were not restored")
	frame("filter-minimal-show");ui:click("cancel")
end
