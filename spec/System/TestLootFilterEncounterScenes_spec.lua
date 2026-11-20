describe("Filter encounter scenes", function()
	it("opens Breach and Legion examples through the planning workspace", function()
		newBuild();main.popups={}
		local ui=require("Modules.HeadlessUI").install({width=960,height=640})
		local ok,err=pcall(function()
			build.viewMode="CONFIG";ui:bind(build);ui:click("aiBuild");ui:click("nav_filters")
			ui:click("create2");ui:text("title","Encounter examples");ui:click("viewSimulate")
			for _,name in ipairs({"Breach","Legion"}) do
				ui:choose("sceneKind",name)
				local scene=build.planningWorkspace.cache.filters.layout.snapshot()
				assert.equal(name,scene.sceneKind)
				assert.equal(require("Modules.LootFilterLibrary").scene(nil,nil,name,scene.seed)[1].BaseType,scene.sample.BaseType)
			end
		end)
		ui:restore();main.popups={}
		assert.is_true(ok,err)
	end)
end)
