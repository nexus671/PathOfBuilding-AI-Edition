describe("TreeTab", function()
	local originalClusterNodeMap
	local originalMasteryEffects

	local function findMasteryNode()
		for _, node in pairs(build.spec.nodes) do
			if node.type == "Mastery" and node.masteryEffects and #node.masteryEffects > 0 then
				return node
			end
		end
	end

	before_each(function()
		newBuild()
		originalClusterNodeMap = build.spec.tree.clusterNodeMap
		originalMasteryEffects = build.spec.tree.masteryEffects
	end)

	after_each(function()
		build.spec.tree.clusterNodeMap = originalClusterNodeMap
		build.spec.tree.masteryEffects = originalMasteryEffects
	end)
	it("reports a failed node-power calculation without publishing partial results and can retry",function()
		local tab,tree=build.calcsTab,build.treeTab;local node=select(2,next(build.spec.nodes));local dev=launch.devMode;launch.devMode=false
		local original=tab.PowerBuilder;local originalReport=tree.BuildPowerReportList;local reports=0
		tree.BuildPowerReportList=function() reports=reports+1;return {} end
		tab.PowerBuilder=function() node.power.singleStat=123;error("synthetic power failure") end
		tab.powerBuildFlag=true;tree.viewer.showHeatMap=true;tab:BuildPower()
		assert.is_nil(tab.powerBuilder);assert.is_nil(tab.powerMax);assert.is_nil(node.power.singleStat);assert.is_false(tree.viewer.showHeatMap)
		assert.is_falsy(tree.controls.powerReportList.reportReady);assert.matches("Power failed",tree.controls.powerReportList.label,1,true);assert.equal(0,reports)
		tab.PowerBuilder=function() end;tree:SetPowerCalc({stat="Life",label="Life"});tab:BuildPower();assert.equal(1,reports);assert.is_true(tree.viewer.showHeatMap)
		tab.PowerBuilder=original;tree.BuildPowerReportList=originalReport;launch.devMode=dev
	end)
	it("retries a failed node-power calculation when its checkbox is re-enabled",function()
		local oldDev=launch.devMode;launch.devMode=false;build.viewMode="TREE";main.popups={}
		local ui=require("Modules.HeadlessUI").install({width=1280,height=720});ui:bind(build);ui:frame()
		local tab,tree=build.calcsTab,build.treeTab;local reports=0
		tree.BuildPowerReportList=function() reports=reports+1;return {} end
		tab.PowerBuilder=function() error("synthetic power failure") end;tree:SetPowerCalc({stat="Life",label="Life"});tab:BuildPower();ui:frame()
		assert.is_true(tree.powerCalculationFailed);assert.is_false(tree.controls.treeHeatMap.state)
		tab.PowerBuilder=function(self) self.powerMax={singleStat=0,offence=0,defence=0,offencePerPoint=0,defencePerPoint=0} end
		ui:click("treeHeatMap");for _=1,5 do ui:frame();if reports>0 then break end end
		assert.is_true(reports>0);assert.is_true(tree.viewer.showHeatMap);assert.is_false(tree.powerCalculationFailed)
		ui:restore();launch.devMode=oldDev
	end)

	it("restores a Runegraft after rebuilding mastery options", function()
		local node = assert(findMasteryNode())
		local override
		for _, tattooNode in pairs(build.spec.tree.tattoo.nodes) do
			if tattooNode.overrideType == "AlternateMastery" then
				override = copyTable(tattooNode, true)
				break
			end
		end
		assert(override)
		override.id = node.id
		build.spec.hashOverrides[node.id] = override
		build.spec:ReplaceNode(node, override)

		build.spec:DeallocSingleNode(node)
		build.spec:BuildAllDependsAndPaths()

		assert.is_false(node.allMasteryOptions)
		assert.are.equal("AlternateMastery", node.overrideType)
	end)

	it("clears the selected mastery reminder after deallocation", function()
		local node = assert(findMasteryNode())
		node.reminderText = { "Tip: Right click to select a different effect" }

		build.spec:DeallocSingleNode(node)
		build.spec:BuildAllDependsAndPaths()

		assert.is_nil(node.reminderText)
	end)

	it("adds separate power report entries for mastery effects", function()
		local treeTab = build.treeTab
		local parentNode = { id = 2 }
		local masteryNode = {
			id = 1,
			type = "Mastery",
			dn = "Two Hand Mastery",
			power = {
				masteryEffects = {
					[101] = { singleStat = 10, pathPower = 10 },
					[102] = { singleStat = 20, pathPower = 20 },
				},
			},
			masteryEffects = {
				{ effect = 101 },
				{ effect = 102 },
			},
			path = { parentNode, false },
			x = 10,
			y = 20,
		}
		masteryNode.path[2] = masteryNode

		treeTab.build.displayStats = {
			{ stat = "Damage", label = "Damage", fmt = ".1f" },
		}
		treeTab.build.spec.nodes = {
			[masteryNode.id] = masteryNode,
		}
		treeTab.build.spec.masterySelections = { }
		treeTab.build.spec.tree.clusterNodeMap = { }
		treeTab.build.spec.tree.masteryEffects = {
			[101] = { id = 101, sd = { "Gain 10 Damage" }, stats = { "Gain 10 Damage" } },
			[102] = { id = 102, sd = { "Gain 20 Damage" }, stats = { "Gain 20 Damage" } },
		}
		treeTab.build.calcsTab.mainEnv = { grantedPassives = { } }

		local report = treeTab:BuildPowerReportList({ stat = "Damage", label = "Damage" })

		assert.are.same(2, #report)
		assert.are.same("Mastery", report[1].type)
		assert.are.same("Two Hand Mastery: Gain 20 Damage", report[1].name)
		assert.are.same(20, report[1].power)
		assert.are.same(2, report[1].pathDist)
		assert.are.same(10, report[2].power)
		assert.are.same("Two Hand Mastery: Gain 10 Damage", report[2].name)
	end)
end)
