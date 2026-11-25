return function(ui,frame,id)
	ui:click("nextPage")
	assert(main.popups[1].controls.count.label:find("Page 2 /",1,true),"Modifier browser did not advance")
	frame("crafting-modifier-browser-page-two")
	ui:text("search",id)
	assert(main.popups[1].controls.count.label:find("Page 1 /",1,true),"Modifier search did not reset its page")
end
