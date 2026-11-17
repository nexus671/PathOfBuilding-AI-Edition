describe("Prefix and suffix catalyst scaling",function()
	it("scales identified affix sides even when the modifier has no tags",function()
		local item=new("Item"):Item("Rarity: RARE\nTest Ring\nSapphire Ring\nImplicits: 0")
		item.catalystQuality=20
		item.catalyst=9 -- Sinistral
		assert.equal(1.2,item:GetModLineValueScalar({prefix=true},"explicit"))
		assert.equal(1.2,item:GetModLineValueScalar({prefix=true,modTags={}},"explicit"))
		assert.equal(1,item:GetModLineValueScalar({suffix=true},"explicit"))
		assert.equal(1,item:GetModLineValueScalar({prefix=true,unscalable=true},"explicit"))
		item.catalyst=3 -- Dextral
		assert.equal(1.2,item:GetModLineValueScalar({suffix=true},"explicit"))
		assert.equal(1,item:GetModLineValueScalar({prefix=true},"explicit"))
		item.catalyst=6 -- Intrinsic still requires an attribute tag
		assert.equal(1,item:GetModLineValueScalar({prefix=true},"explicit"))
		assert.equal(1.2,item:GetModLineValueScalar({prefix=true,modTags={"attribute"}},"explicit"))
	end)
	it("applies to a parsed affix without an explicit tag list",function()
		local item=new("Item"):Item("Rarity: RARE\nTest Ring\nSapphire Ring\nCatalyst: Sinistral\nCatalystQuality: 20\nImplicits: 0\n{prefix}+100 to maximum Life")
		local line=item.explicitModLines[1]
		assert.is_true(line.prefix);assert.same({},line.modTags)
		assert.equal(1.2,item:GetModLineValueScalar(line,"explicit"))
		item:BuildModList()
		local life;for _,mod in ipairs(item.slotModList[1]) do if mod.name=="Life" then life=mod.value end end
		assert.equal(120,life)
	end)
end)
