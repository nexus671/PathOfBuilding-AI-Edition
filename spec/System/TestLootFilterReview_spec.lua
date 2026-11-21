describe("Loot filter change review",function()
	local filters=require("Modules.LootFilters")
	local editing=require("Modules.LootFilterEditing")
	before_each(function() newBuild();main.popups={} end)
	after_each(function() main.popups={} end)
	it("shows a changed active profile even when the profiles themselves are unchanged",function()
		local a=filters.profile("a","First");local b=filters.profile("b","Second")
		local before={schemaVersion=1,activeId="a",profiles={a,b}};local after=copyTable(before);after.activeId="b"
		local review=editing.review(before,after);assert.equal(1,#review);assert.equal("Active profile changed",review[1].label)
		assert.same({"Before: First [a]","After: Second [b]"},review[1].details)
	end)
	it("shows the changed notice setting without unchanged fields",function()
		local profile=filters.profile("a","First");profile.trackBuildPickups=true
		local before={schemaVersion=1,activeId="a",profiles={profile}};local after=copyTable(before);after.profiles[1].trackBuildPickups=false
		local review=editing.review(before,after);assert.same({"Build pickup notices: Enabled -> Disabled"},review[1].details)
	end)
	it("explains changed settings, included files and rule status",function()
		local profile=filters.profile("a","First");profile.importFiles={{name="same.filter",text="old"},{name="removed.filter",text="old"}}
		profile.rules={filters.rule("personal","Hat",{'BaseType == "Iron Hat"'})}
		local before={schemaVersion=1,activeId="a",profiles={profile}};local after=copyTable(before);local changed=after.profiles[1]
		changed.preset="campaign";changed.theme="contrast";changed.trackBuildPickups=false
		changed.importFiles={{name="same.filter",text="new contents"},{name="added.filter",text="new"}}
		changed.rules[1].enabled=false;changed.rules[1].origin="craft:helmet"
		local review=editing.review(before,after);assert.equal(1,#review);local text=table.concat(review[1].details,"\n")
		for _,expected in ipairs({"Preset: early_maps -> campaign","Theme: default -> contrast","Build pickup notices: Automatic (legacy) -> Disabled","Included file changed: same.filter","Included file added: added.filter","Included file removed: removed.filter","Rule enabled: true -> false","Linked source: Manual -> craft:helmet"}) do
			assert.is_truthy(text:find(expected,1,true),expected)
		end
	end)
end)
