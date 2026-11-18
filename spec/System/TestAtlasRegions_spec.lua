describe("Manually tracked Shaped Regions",function()
	local regions=require("Modules.AtlasRegions")
	local atlas=require("Modules.AtlasPlanner")
	local function fixture() return {
		{mechanic="Blight",maps={{name="Beach Map",freeThreads=2},{name="Strand Map",freeThreads=3}}},
		{mechanic="Breach",maps={{name="beach map",freeThreads=4},{name="Dunes Map",freeThreads=1}}},
		{mechanic="Abyss",maps={{name="Strand Map",freeThreads=6}}},
	} end
	it("removes a run map from every overlapping region and advances only completed objectives",function()
		local input=fixture();local before=copyTable(input)
		local result=regions.complete(input," Beach Map ",{"Blight"})
		assert.same(before,input);assert.same({{name="Strand Map",freeThreads=4}},result[1].maps)
		assert.same({{name="Dunes Map",freeThreads=1}},result[2].maps);assert.same(input[3],result[3])
		local both=regions.complete(input,"Beach Map",{"Blight","Breach"});assert.equal(2,both[2].maps[1].freeThreads)
		local skipped=regions.complete(input,"Beach Map",{});assert.equal(3,skipped[1].maps[1].freeThreads)
		assert.has_error(function() regions.complete(input,"Beach Map",{"Abyss"}) end)
		assert.has_error(function() regions.complete(input,"Unknown",{}) end)
	end)
	it("validates observations without silently dropping duplicates or invalid counts",function()
		local bad=fixture();bad[1].maps[2].name="beach MAP";assert.has_error(function() regions.validate(bad) end)
		bad=fixture();bad[2].mechanic="Blight";assert.has_error(function() regions.validate(bad) end)
		bad=fixture();bad[1].maps[1].freeThreads=-1;assert.has_error(function() regions.validate(bad) end)
		bad=fixture();bad[1].maps[1].freeThreads=1.5;assert.has_error(function() regions.validate(bad) end)
		bad=fixture();bad[1].maps[2].freeThreads=1000;assert.has_error(function() regions.complete(bad,"Beach Map",{"Blight"}) end)
	end)
	it("keeps regions through Atlas export and build save/reopen",function()
		newBuild();local plan={id="regions",title="Regions",version="3.30.0-preview",budget=150,nodes={},shapedRegions=fixture()}
		local validated=atlas.validate(plan);assert.same(fixture(),validated.shapedRegions)
		assert.same(validated,atlas.import(atlas.export(validated)))
		build.savers.AtlasPlans:Upsert(validated);local xml=build:SaveDB("Region test");loadBuildFromXML(xml,"Region test")
		assert.same(fixture(),build.savers.AtlasPlans.plans[1].shapedRegions)
		plan.version="3.29.3";plan.budget=120;assert.has_error(function() atlas.validate(plan) end)
	end)
end)
