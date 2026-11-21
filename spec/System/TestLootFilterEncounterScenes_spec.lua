describe("Filter encounter scenes", function()
	it("opens encounter examples and navigates pages when needed", function()
		newBuild();main.popups={}
		local ui=require("Modules.HeadlessUI").install({width=960,height=640})
		local ok,err=pcall(function()
			build.viewMode="CONFIG";ui:bind(build);ui:click("aiBuild");ui:click("nav_filters")
			ui:click("create2");ui:text("title","Encounter examples");ui:click("viewSimulate")
			for _,case in ipairs({{"Breach",false},{"Beyond",false},{"Incursion",false},{"Legion",true},{"Sanctum",true},{"Pinnacle bosses",true}}) do
				local name,hasNext=case[1],case[2]
				ui:choose("sceneKind",name)
				local scene=build.planningWorkspace.cache.filters.layout.snapshot()
				assert.equal(name,scene.sceneKind)
				assert.equal(require("Modules.LootFilterLibrary").scene(nil,nil,name,scene.seed)[1].BaseType,scene.sample.BaseType)
				assert.is_true(build.planningWorkspace.controls.drop1.width >= 200, "Encounter labels need room at 960px")
				assert.is_false(build.planningWorkspace.controls.scenePrevious:IsEnabled())
				assert.equal(hasNext,build.planningWorkspace.controls.sceneNext:IsEnabled(),name)
				if hasNext then
					ui:click("sceneNext");assert.equal(2,build.planningWorkspace.cache.filters.layout.snapshot().scenePage)
					ui:click("scenePrevious");assert.equal(1,build.planningWorkspace.cache.filters.layout.snapshot().scenePage)
				end
			end
			ui:choose("sceneKind","Mixed drops")
			assert.equal("Mixed drops",build.planningWorkspace.cache.filters.layout.snapshot().sceneKind)
		end)
		ui:restore();main.popups={}
		assert.is_true(ok,err)
	end)
end)
