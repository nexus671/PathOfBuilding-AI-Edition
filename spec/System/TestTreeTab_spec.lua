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
	it("calculates every available node-power category for a real passive change",function()
		build.calcsTab:BuildOutput(false)
		local node;for _,candidate in pairs(build.spec.nodes) do if not candidate.alloc and candidate.path and #candidate.path==1 and candidate.modKey~="" then node=candidate;break end end;assert.is_not_nil(node)
		local calc,base=build.calcsTab:GetMiscCalculator();local normal=calc({addNodes={[node]=true}},false);local full=calc({addNodes={[node]=true}},true)
		local checked=0;for _,selection in ipairs(data.powerStatList) do if selection.stat and not selection.ignoreForNodes then
			local value=build.calcsTab:CalculatePowerStat(selection,selection.stat=="FullDPS" and full or normal,base)
			assert.is_true(type(value)=="number" and value==value,selection.label);checked=checked+1
		end end;assert.is_true(checked>0)
	end)
	it("completes limited-depth node-power reports for niche defensive categories",function()
		build.calcsTab:BuildOutput(false);local tab=build.calcsTab;tab.nodePowerMaxDepth=1
		-- This check covers the ordinary tree; cluster calculations have their own tests.
		build.spec.tree.clusterNodeMap={}
		for _,key in ipairs({"MeleeAvoidChance","SpellAvoidChance","ProjectileAvoidChance","EnergyShieldRecoveryCap","LifeLeechRate","ManaRegen"}) do
			local selection;for _,entry in ipairs(data.powerStatList) do if entry.stat==key then selection=entry;break end end;assert.is_not_nil(selection)
			tab.powerStat=selection;tab.powerBuildFlag=true;tab.powerBuilderInitialized=false
			for _=1,10000 do tab:BuildPower();if not tab.powerBuilder and not tab.powerBuildFlag then break end end
			assert.is_true(tab.powerBuilderInitialized,key);assert.is_falsy(build.treeTab.powerCalculationFailed,key)
		end
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
		treeTab.build.spec.masterySelections = {}
		treeTab.build.spec.tree.clusterNodeMap = {}
		treeTab.build.spec.tree.masteryEffects = {
			[101] = { id = 101, sd = { "Gain 10 Damage" }, stats = { "Gain 10 Damage" } },
			[102] = { id = 102, sd = { "Gain 20 Damage" }, stats = { "Gain 20 Damage" } },
		}
		treeTab.build.calcsTab.mainEnv = { grantedPassives = {} }

		local report = treeTab:BuildPowerReportList({ stat = "Damage", label = "Damage" })

		assert.are.same(2, #report)
		assert.are.same("Mastery", report[1].type)
		assert.are.same("Two Hand Mastery: Gain 20 Damage", report[1].name)
		assert.are.same(20, report[1].power)
		assert.are.same(2, report[1].pathDist)
		assert.are.same(10, report[2].power)
		assert.are.same("Two Hand Mastery: Gain 10 Damage", report[2].name)
	end)

	describe("CopyTree", function()
		it("Copies a tree spec with a new name", function()
			local newTitle = "Copied Tree"
			local newSpec = build.treeTab:CopyTree(1, newTitle)

			assert.is_not.same(build.treeTab.specList[1], newSpec)
			assert.are.equals(newTitle, newSpec.title)
		end)

		it("Copies tree version from source spec", function()
			local newSpec = build.treeTab:CopyTree(1, "Copy Test")

			assert.are.equals(build.treeTab.specList[1].treeVersion, newSpec.treeVersion)
		end)

		it("Copies jewels from source spec", function()
			local newSpec = build.treeTab:CopyTree(1, "Copy Test")

			assert.are.same(build.treeTab.specList[1].jewels, newSpec.jewels)
		end)

		it("Deep copies jewel allocations", function()
			local newSpec = build.treeTab:CopyTree(1, "Copy Test")

			-- Modify source jewels
			build.treeTab.specList[1].jewels["test_node"] = "test_item"

			-- Copy should have been independent
			assert.is_nil(newSpec.jewels["test_node"])
		end)

		it("Returns new spec with next ID", function()
			local newSpec = build.treeTab:CopyTree(1, "Copy Test")

			assert.are.equals(2, newSpec.id)
		end)

		it("Adds copied spec to specList", function()
			build.treeTab:CopyTree(1, "Copy Test")

			assert.are.equals(2, #build.treeTab.specList)
			assert.is_not_nil(build.treeTab.specList[2])
		end)

		it("Copies the default spec with a suffix", function()
			local newSpec = build.treeTab:CopyTree(1)

			assert.are.equals("Default (Copy)", newSpec.title)
		end)

		it("Appends suffix to source title when no name provided", function()
			build.treeTab.specList[1].title = "My Tree"
			local newSpec = build.treeTab:CopyTree(1)

			assert.are.equals("My Tree (Copy)", newSpec.title)
		end)

		it("Copies allocNodes from source spec via undo state", function()
			-- Allocate a node in the source spec
			build.treeTab.specList[1].allocNodes = { [1] = true }

			local newSpec = build.treeTab:CopyTree(1, "Copy Test")

			-- allocNodes should be copied via RestoreUndoState
			assert.is_not_nil(newSpec.allocNodes)
		end)

		it("Handles copying when source has no jewels", function()
			build.treeTab.specList[1].jewels = {}
			local newSpec = build.treeTab:CopyTree(1, "Copy Test")

			assert.are.same({}, newSpec.jewels)
		end)

		it("Handles copying when source has no allocNodes", function()
			local oldAlloc = build.treeTab.specList[1].allocNodes
			build.treeTab.specList[1].allocNodes = nil
			-- CreateUndoState needs allocNodes to exist, so we set it to empty table
			-- but the original spec may have had no allocations
			build.treeTab.specList[1].allocNodes = {}
			local newSpec = build.treeTab:CopyTree(1, "Copy Test")
			build.treeTab.specList[1].allocNodes = oldAlloc

			assert.is_not_nil(newSpec)
		end)
	end)

	describe("CopyTree integration", function()
		it("Copies multiple times with unique IDs", function()
			local copy1 = build.treeTab:CopyTree(1, "Copy 1")
			local copy2 = build.treeTab:CopyTree(1, "Copy 2")

			assert.are.equals(2, copy1.id)
			assert.are.equals(3, copy2.id)
			assert.are.not_same(copy1, copy2)
		end)

		it("Copies from copied spec", function()
			local copy1 = build.treeTab:CopyTree(1, "Copy 1")
			local copy2 = build.treeTab:CopyTree(2, "Copy 2")

			assert.are.equals(copy1.treeVersion, copy2.treeVersion)
			assert.are.equals("Copy 2", copy2.title)
		end)
	end)


	describe("SpecStateManagement", function()
		it("Preserves tree allocations across spec switches", function()
			build.treeTab:CopyTree(1, "Copy 1")

			-- Allocate a node in original
			build.treeTab.specList[1].allocNodes = { [1] = true }

			build.treeTab:SetActiveSpec(1)
			assert.is_not_nil(build.treeTab.specList[1].allocNodes[1])

			build.treeTab:SetActiveSpec(2)
			build.treeTab.specList[2].allocNodes = { [2] = true }

			build.treeTab:SetActiveSpec(1)
			assert.is_not_nil(build.treeTab.specList[1].allocNodes[1])
			assert.is_nil(build.treeTab.specList[1].allocNodes[2])
		end)
	end)
end)
