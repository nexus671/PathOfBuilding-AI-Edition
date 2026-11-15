describe("PassiveTreeView jewel comparison", function()
	local viewer

	local function newJewel(name, raw)
		return {
			name = name,
			BuildRaw = function()
				return raw
			end,
		}
	end

	local function setCompareJewel(jewel, allocated)
		local itemsTab = {
			items = { [2] = jewel },
			sockets = { [100] = { selItemId = jewel and 2 or 0 } },
		}
		viewer.compareSpec = {
			allocNodes = { [100] = allocated },
			build = { itemsTab = itemsTab },
		}
		return itemsTab
	end

	before_each(function()
		newBuild()
		viewer = build.treeTab.viewer
	end)

	it("culls only connector quads entirely beyond a screen edge", function()
		local outside = {
			{ -10, 1, -1, 1, -1, 9, -10, 9 },
			{ 101, 1, 110, 1, 110, 9, 101, 9 },
			{ 1, -10, 9, -10, 9, -1, 1, -1 },
			{ 1, 101, 9, 101, 9, 110, 1, 110 },
		}
		for _, quad in ipairs(outside) do assert.is_true(viewer:IsQuadOffscreen(quad, 100, 100)) end
		-- Long and rotated connectors can cross the screen with every corner outside.
		assert.is_false(viewer:IsQuadOffscreen({ -10, 40, 110, 40, 110, 60, -10, 60 }, 100, 100))
		assert.is_false(viewer:IsQuadOffscreen({ -10, 50, 50, -10, 110, 50, 50, 110 }, 100, 100))
		assert.is_false(viewer:IsQuadOffscreen({ -10, 1, 0, 1, 0, 9, -10, 9 }, 100, 100))
	end)

	it("matches jewels by their complete raw representation", function()
		local primaryJewel = newJewel("Controller Metamorphosis", "Radius: Small")
		local compareJewel = newJewel("Controller Metamorphosis", "Radius: Small")
		setCompareJewel(compareJewel, true)

		local color = viewer:GetCompareNodeColor(
			{ id = 100, type = "Socket", alloc = true },
			{ alloc = true },
			{ jewels = { [100] = 1 } },
			{ itemsTab = { items = { [1] = primaryJewel } } },
			"^xFFFFFF"
		)

		assert.are.equals("^xFFFFFF", color)
	end)

	it("marks same-name jewels with different variants as changed", function()
		local primaryJewel = newJewel("Controller Metamorphosis", "Radius: Small")
		local compareJewel = newJewel("Controller Metamorphosis", "Radius: Large")
		setCompareJewel(compareJewel, true)

		local red, green, blue = viewer:GetCompareNodeColor(
			{ id = 100, type = "Socket", alloc = true },
			{ alloc = true },
			{ jewels = { [100] = 1 } },
			{ itemsTab = { items = { [1] = primaryJewel } } },
			"^xFFFFFF"
		)

		assert.are.same({ 0, 0, 1 }, { red, green, blue })
	end)

	it("shows both full jewel tooltips when allocated socket jewels differ", function()
		local primaryJewel = newJewel("Controller Metamorphosis", "Radius: Small")
		local compareJewel = newJewel("Controller Metamorphosis", "Radius: Large")
		local compareItemsTab = setCompareJewel(compareJewel, true)
		local primaryTooltipItems = { }
		local compareTooltipItems = { }
		local socket = { IsEnabled = function() return false end }
		local tooltip = {
			AddLine = function() end,
			AddSeparator = function() end,
		}
		local primaryBuild = {
			itemsTab = {
				GetSocketAndJewelForNodeID = function()
					return socket, primaryJewel
				end,
				AddItemTooltip = function(_, _, item)
					table.insert(primaryTooltipItems, item)
				end,
			},
		}
		compareItemsTab.AddItemTooltip = function(_, _, item)
			table.insert(compareTooltipItems, item)
		end

		viewer:AddNodeTooltip(tooltip, { id = 100, type = "Socket", alloc = true }, primaryBuild)

		assert.are.same({ primaryJewel }, primaryTooltipItems)
		assert.are.same({ compareJewel }, compareTooltipItems)
	end)

	it("shows the compared jewel tooltip when only the compared socket is allocated", function()
		local compareJewel = newJewel("Controller Metamorphosis", "Radius: Large")
		local compareItemsTab = setCompareJewel(compareJewel, true)
		local compareTooltipItems = { }
		local tooltip = {
			AddLine = function() end,
			AddSeparator = function() end,
		}
		local primaryBuild = {
			itemsTab = {
				GetSocketAndJewelForNodeID = function()
					return { }, nil
				end,
			},
		}
		compareItemsTab.AddItemTooltip = function(_, _, item)
			table.insert(compareTooltipItems, item)
		end

		viewer:AddNodeTooltip(tooltip, { id = 100, type = "Socket", alloc = false }, primaryBuild)

		assert.are.same({ compareJewel }, compareTooltipItems)
	end)
end)
