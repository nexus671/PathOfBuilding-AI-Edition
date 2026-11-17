describe("Loot filter module controls",function()
	before_each(function() newBuild() end)
	it("explains invalid clipboard content without changing the profile",function()
		local filters=require("Modules.LootFilters")
		local profile=filters.profile("test","Test")
		local controls={};local changed=false
		require("Classes.LootFilterModuleControl").Mount(controls,{profiles={profile}},profile,960,640,{id=function() return "id" end,change=function() changed=true end,edit=function() end})
		local previousPaste=Paste;Paste=function() return "not a pickup module" end
		local ok,err=pcall(function() controls.modulePaste:Click() end);Paste=previousPaste
		assert.is_true(ok,tostring(err));assert.is_false(changed);assert.equal(0,#(profile.modules or {}));assert.is_true(#main.popups>0)
		main.popups={}
	end)
end)
