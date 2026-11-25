-- Supplemental metadata from the 3.30.0.1.4 client modifier export.
-- mods.json SHA-256: a6814fdd00755eca4208b2d5bae7877795e5c91a2d0935daa6748b49f26ec0ce
-- Upstream supplies the displayed modifier; the pinned 3.29 crafting export
-- cannot contain a modifier introduced after that export.
return {
	V2MinPowerChargesCorruptedNew = {
		groups = {"MinimumPowerCharges"},
		spawn_weights = {
			{tag = "amulet", weight = 1000},
			{tag = "shield", weight = 1000},
			{tag = "default", weight = 0},
		},
	},
}
