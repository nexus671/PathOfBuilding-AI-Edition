describe("ItemDBControl", function()
	local originalGetCursorPos

	before_each(function()
		originalGetCursorPos = GetCursorPos
	end)

	after_each(function()
		GetCursorPos = originalGetCursorPos
	end)

	it("sorts lower-is-better stats below zero", function()
		local function makeItem(name)
			return {
				name = name,
				base = {},
				enchantModLines = {},
				implicitModLines = {},
				explicitModLines = {},
				baseModList = {},
			}
		end
		local betterItem = makeItem("Better Item")
		local worseItem = makeItem("Worse Item")
		local invalidItem = makeItem("Invalid Item")
		local takenDamage = {
			[betterItem] = 80,
			[worseItem] = 120,
		}
		local itemsTab = {
			activeItemSet = { useSecondWeaponSet = false },
			slots = { ["Body Armour"] = { shown = function() return true end } },
			build = {
				calcsTab = {
					GetMiscCalculator = function()
						return function(args)
							return { PhysicalTakenHit = takenDamage[args.repItem] }
						end
					end,
				},
			},
			IsItemValidForSlot = function(_, item)
				return item ~= invalidItem
			end,
		}
		local control = new("ItemDBControl"):ItemDBControl(nil, { 0, 0, 100, 100 }, itemsTab, {
			list = { invalidItem, betterItem, worseItem },
		}, "RARE")
		control.sortDetail = {
			stat = "PhysicalTakenHit",
			transform = function(value) return -value end,
		}
		control.sortOrder = { control.sortControl.STAT, control.sortControl.NAME }

		control:ListBuilder()

		assert.are.equal(betterItem, control.list[1])
		assert.are.equal(worseItem, control.list[2])
		assert.are.equal(invalidItem, control.list[3])
		assert.are.equal(-80, betterItem.measuredPower)
		assert.are.equal(-120, worseItem.measuredPower)
		assert.are.equal(-math.huge, invalidItem.measuredPower)
	end)

	it("searches Foulborn modifier text without case sensitivity", function()
		local item = new("Item"):Item([[
			Rarity: Unique
			Kitava's Thirst
			Zealot Helmet
			Variant: Pre 3.11.0
			Variant: Current
			Selected Variant: 2
			50% chance to Trigger Socketed Spells when you Spend at least 100 Mana on an
			Upfront Cost to Use or Trigger a Skill, with a 0.1 second Cooldown
		]])
		local control = new("ItemDBControl"):ItemDBControl(nil, { 0, 0, 100, 100 }, {
			build = {
				characterLevel = 100,
			},
		}, {
			list = { item },
		}, "UNIQUE")
		control.controls.search.buf = "life on an upfront cost"
		control.controls.searchMode.selIndex = 3

		assert.is_true(control:DoesItemMatchFilters(item))
	end)

	it("releases focus after opening an item with a double click", function()
		local item = {
			raw = "Rarity: Unique\nTest Item\nLeather Belt",
		}
		local itemsTab
		itemsTab = {
			CreateDisplayItemFromRaw = function(_, raw, isUnique)
				itemsTab.displayRaw = raw
				itemsTab.displayIsUnique = isUnique
			end,
		}
		local control = new("ItemDBControl"):ItemDBControl(nil, { 0, 0, 100, 100 }, itemsTab, {
			list = { item },
		}, "UNIQUE")
		control.list = { item }
		GetCursorPos = function()
			return 3, 3
		end
		control.GetRowRegion = function()
			return { x = 0, y = 0, width = 100, height = 100 }
		end

		local selectedControl = control:OnKeyDown("LEFTBUTTON", true)

		assert.is_nil(selectedControl)
		assert.are.equal(item.raw, itemsTab.displayRaw)
		assert.is_true(itemsTab.displayIsUnique)
	end)

	it("appends typed Wickerman filters after Grafts", function()
		local item = new("Item"):Item("")
		item.base = { }
		for _, dbType in ipairs({ "RARE", "UNIQUE" }) do
			local control = new("ItemDBControl"):ItemDBControl(nil, { 0, 0, 100, 100 }, { }, { list = { } }, dbType)
			item.type = "Graft"
			control.controls.slot:SelByValue("Graft 1")
			assert.are.equal("Graft 1", control.slotList[control.controls.slot.selIndex])
			assert.is_true(control:DoesItemMatchFilters(item))
			control.controls.slot:SelByValue("Graft 2")
			assert.are.equal("Graft 2", control.slotList[control.controls.slot.selIndex])
			local lastIndex = control.controls.slot.selIndex
			for _, slotName in ipairs({ "Head", "Body", "Arm", "Leg" }) do
				control.controls.slot:SelByValue(slotName)
				assert.are.equal(lastIndex + 1, control.controls.slot.selIndex)
				assert.is_false(control:DoesItemMatchFilters(item))
				item.type = slotName
				assert.is_true(control:DoesItemMatchFilters(item))
				lastIndex = control.controls.slot.selIndex
			end
		end
	end)
	it("sorts Viscera by the calculated stat while keeping name sorting as default", function()
		newBuild()
		local control=build.itemsTab.controls.visceraDB
		assert.is_truthy(control.controls.sort);assert.equal("NAME",control.sortMode);assert.is_nil(control.sortDetail.stat)
		local selected={}
		for _,item in pairs(control.db.list) do
			if item.name:find("Lesser Warden's Arm",1,true) or item.name:find("Crustacean's Claw",1,true) then selected[#selected+1]=item end
		end
		assert.is_true(#selected>=2);control.db={list=selected};control.controls.slot:SelByValue("Arm");control:SetSortMode("Life")
		local task=coroutine.create(function() control:ListBuilder() end)
		repeat local ok,err=coroutine.resume(task);assert.is_true(ok,err) until coroutine.status(task)=="dead"
		assert.is_truthy(control.list[1].name:find("Lesser Warden's Arm",1,true));assert.is_true(control.list[1].measuredPower>control.list[#control.list].measuredPower)
	end)
	it("filters upstream Viscera using the fork's compatible Wickerman slots", function()
		local item = new("Item"):Item("Rarity: NORMAL\nScorched Arm")
		assert.are.equal("Viscera", item.type)
		assert.are.equal("Wickerman Upper Limb", item:GetPrimarySlot())
		local control = new("ItemDBControl"):ItemDBControl(nil, { 0, 0, 100, 100 }, { }, { list = { item } }, "RARE")
		control.controls.slot:SelByValue("Arm");assert.is_true(control:DoesItemMatchFilters(item))
		control.controls.slot:SelByValue("Head");assert.is_false(control:DoesItemMatchFilters(item))
	end)

end)
