describe("3.28 Atlas",function()
	local atlas=require("Modules.AtlasPlanner")
	it("loads both official 3.28.0j modes and defaults matching character trees",function()
		for _,case in ipairs({
			{"3.28.0j","3_28", "standard", "11f7e227a4d49463f31e4b63c788acbd158cf058c1fba563554e41fcd2fad0f2",{"Standard","Mirage"}},
			{"3.28.0j-ruthless","3_28_ruthless", "ruthless", "1fcb6379c5bb0c1ebdb5d473f8f4ab28f69cc6d86c711832fc3b492284fa594d",{"Ruthless Standard","Ruthless Mirage"}},
		}) do
			local tree=atlas.tree(case[1]);assert.equal(case[1],atlas.defaultVersion(case[2]))
			assert.equal(case[3],tree.mode);assert.equal(case[4],tree.sha256);assert.same(case[5],tree.compatibleModes)
			assert.equal(138,tree.maxPoints);assert.is_truthy(tree.leagueSha256);assert.is_truthy(require("Modules.AtlasArt").load(case[1]))
			local matches=atlas.search(case[1],"Essence",10).matches;assert.is_true(#matches>0)
			local plan=atlas.connect({id="mirage",title="Mirage",version=case[1],budget=138,nodes={}}, {matches[1].id})
			local restored=atlas.import(atlas.export(plan),case[1]);assert.equal(case[1],restored.version);assert.same(plan.nodes,restored.nodes)
		end
		assert.equal("3.28.0j",atlas.defaultVersion("3_28_alternate"))
		assert.equal("3.28.0j-ruthless",atlas.defaultVersion("3_28_ruthless_alternate"))
	end)
end)
