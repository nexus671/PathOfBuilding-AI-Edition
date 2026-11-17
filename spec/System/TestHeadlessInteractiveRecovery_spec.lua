describe("Headless interactive recovery",function()
	for _,interactive in ipairs({true,false}) do
	it("keeps automatic level and recovery consistent after a passive click (deferred: "..tostring(interactive)..")",function()
		newBuild();main.popups={}
		build.characterLevelAutoMode=true;build.characterLevel=1
		local input=build.configTab.input
		input.simulateRecovery=true;input.recoverySimulationTrials=4;input.recoverySimulationWindow=10
		input.enemyDamageType="Untyped";input.enemyIsBoss="None";input.enemySpeed=1000;input.enemyCritChance=0;input.enemyColdDamage="20"
		input.customMods="+3000 to maximum Life\n+60% to Cold Resistance";build.configTab:BuildModList();build.calcsTab:BuildOutput()
		local previous=launch.headlessInteractiveRecovery;local ui=require("Modules.HeadlessUI").install({width=1280,height=720,interactiveRecovery=interactive})
		local viewer=build.treeTab.viewer;local draw=viewer.Draw;local viewport;local output=build.calcsTab.BuildOutput;local deferred=false
		viewer.Draw=function(self,owner,view,events) viewport=copyTable(view);return draw(self,owner,view,events) end
		build.calcsTab.BuildOutput=function(self,defer) deferred=defer;return output(self,defer) end
		local ok,message=pcall(function()
			ui:bind(build);ui:frame();local selected
			for _,node in pairsSortByKey(build.spec.nodes) do if not node.alloc and node.type=="Normal" and node.path and #node.path==1 and node.rsq and node.group and not node.ascendancyName then selected=node;break end end
			assert.is_truthy(selected);viewer:Focus(selected.x,selected.y,viewport,build)
			local x,y=viewport.x+viewport.width/2,viewport.y+viewport.height/2
			ui:clickAt(x,y);assert.is_true(selected.alloc)
			ui:frame();assert.equal(interactive,deferred)
			local frames=0;while build.calcsTab.recoveryJob do ui:frame();frames=frames+1;assert.is_true(frames<1000) end
			assert.equal(build.characterLevel,build.calcsTab.calcsEnv.player.level)
			local expected=copyTable(build.calcsTab.calcsEnv.player.recoverySimulationResults);assert.is_truthy(expected)
			output(build.calcsTab,false);assert.are.same(expected,build.calcsTab.calcsEnv.player.recoverySimulationResults)
		end)
		viewer.Draw=draw;build.calcsTab.BuildOutput=output;ui:restore();assert.are.equal(previous,launch.headlessInteractiveRecovery)
		assert.is_true(ok,message)
	end)
	end
	it("recalculates automatic level when the new output changes extra points",function()
		newBuild();main.popups={};build.characterLevelAutoMode=true
		for _=1,40 do
			local selected;for _,node in pairsSortByKey(build.spec.nodes) do if not node.alloc and node.type=="Normal" and node.path and #node.path==1 and not node.ascendancyName then selected=node;break end end
			assert.is_truthy(selected);build.spec:AllocNode(selected)
		end
		build.configTab.input.customMods="";build.configTab:BuildModList();build.calcsTab:BuildOutput();build:RefreshStatList()
		local previousExtra=build.calcsTab.mainOutput.ExtraPoints;local previousLevel=build.characterLevel
		local ui=require("Modules.HeadlessUI").install({width=1280,height=720,interactiveRecovery=false});local calls=0;local output=build.calcsTab.BuildOutput
		build.calcsTab.BuildOutput=function(self,...) calls=calls+1;return output(self,...) end
		local ok,message=pcall(function()
			build.configTab.input.customMods="Grants 10 Passive Skill Points";build.configTab:BuildModList();build.buildFlag=true;ui:bind(build);ui:frame()
			assert.equal(previousExtra+10,build.calcsTab.mainOutput.ExtraPoints);assert.is_true(build.characterLevel<previousLevel)
			assert.equal(build.characterLevel,build.calcsTab.mainEnv.player.level);assert.equal(build.characterLevel,build.calcsTab.calcsEnv.player.level);assert.is_true(calls>=2)
		end)
		build.calcsTab.BuildOutput=output;ui:restore();assert.is_true(ok,message)
	end)
end)
