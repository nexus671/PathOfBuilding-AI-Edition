-- cspell:ignore exoticveiled
describe("3.30 native filter update",function()
	local filters=require("Modules.LootFilters")
	local parser=require("Modules.LootFilterParser")
	local library=require("Modules.LootFilterLibrary")
	before_each(function() newBuild();main.popups={} end)
	after_each(function() main.popups={} end)
	it("keeps the reviewed base's own decisions across all strictness levels",function()
		for strictness=0,6 do
			local profile=filters.profile("native","Native");profile.strictness=strictness
			local base,changes=filters.migratedBase(profile);assert.same({},changes)
			local output,report,compiled=filters.compile(profile,true)
			assert.is_nil(output:find("# 3.30 new-item safety:",1,true))
			for _,diagnostic in ipairs(report.diagnostics) do assert.is_nil(diagnostic.error,diagnostic.error) end
			local original=parser.parse(base)
			for _,sample in ipairs(library.scene(profile,build,"Covens & Threads",0,83,86)) do
				local before=parser.simulate(original,sample);local after=parser.simulate(compiled,sample)
				assert.equal(before.action,after.action,sample.BaseType);assert.same(before.styles,after.styles)
			end
		end
	end)
	it("shows the 3.30.0d Exalted Orbs in every native strictness",function()
		for strictness=0,6 do
			local profile=filters.profile("new-currency","New currency");profile.strictness=strictness
			for _,name in ipairs({"Originator's Exalted Orb","Primordial Exalted Orb"}) do
				local item=library.sample();item.BaseType=name;item.MemoryStrands=0
				local result=filters.simulate(profile,item)
				assert.equal("Show",result.action,name.." strictness "..strictness)
			end
		end
	end)
	it("requires review of old profiles and keeps personal rules ahead of the new base",function()
		local old=filters.profile("old","Old");old.baseCommit="3ab00dd016b00c6be7acfa989baf498842973d54"
		old.rules={{id="personal",title="Hide thread",text='Hide\n BaseType == "Frayed Thread"',enabled=true}}
		old.tiers={{id="tier",title="Currency tier",items={"Divine Orb"},text='Show\n BaseType == "Divine Orb"'}}
		old.appearance={textColor={255,220,100,255}}
		assert.has_error(function() filters.compile(old) end)
		local updated=filters.update(old);assert.same(old.rules,updated.rules);assert.same(old.tiers,updated.tiers);assert.same(old.appearance,updated.appearance);assert.equal(filters.source().commit,updated.baseCommit)
		local sample=library.sample();sample.BaseType="Frayed Thread";sample.Class="Stackable Currency"
		assert.equal("Hide",filters.simulate(updated,sample).action)
	end)
	it("includes the newer veiled jewel rule at every strictness",function()
		for strictness=0,6 do
			local profile=filters.profile("jewel","Jewel");profile.strictness=strictness
			local base=filters.migratedBase(profile)
			local block=assert(base:match('(Show #[^\n]*%$tier%->exoticveiled[^\n]*\n.-)\n%s*\n'))
			local result=parser.simulate(parser.parse(block.."\nHide"),{Class="Abyss Jewels",Rarity="Rare",Identified=true,HasExplicitMod={"Veil"}})
			assert.equal("Show",result.action,tostring(strictness))
		end
	end)
	it("retains the safety layer for imported filters",function()
		local profile=filters.profile("import","Imported");profile.template='Hide\n BaseType == "Chaos Orb"\nShow'
		local output=filters.compile(profile);assert.is_truthy(output:find("# 3.30 new-item safety:",1,true))
	end)
	it("requires selecting the base update before changing the filter",function()
		local profile=filters.profile("old","Old");profile.baseCommit="3ab00dd016b00c6be7acfa989baf498842973d54"
		profile.rules={{id="personal",title="Personal",text="Show",enabled=true}}
		local saved;require("Classes.LootFilterControl").Audit(profile,{diagnostics={{line=12,warning="Example warning"}}},function(value) saved=value end)
		local controls=main.popups[1].controls
		assert.equal("Update bundled NeverSink base",controls.results.list[1].entry.label)
		controls.search:OnKeyDown("RETURN");assert.is_nil(saved)
		controls.results.onClick({line=controls.results.list[3]})
		controls.search:OnKeyDown("RETURN");assert.is_nil(saved)
		assert.is_false(controls.choose:IsEnabled());controls.choose:Click();assert.is_nil(saved)
		controls.results.onClick({line=controls.results.list[1]});assert.is_true(controls.choose:IsEnabled())
		controls.choose:Click()
		assert.equal(filters.source().commit,saved.baseCommit);assert.same(profile.rules,saved.rules)
	end)
	it("shows a readable compilation error in the audit",function()
		local profile=filters.profile("broken","Broken")
		require("Classes.LootFilterControl").Audit(profile,{error="C:/work/Filters.lua:42: The filter is too large"},function() end)
		local controls=main.popups[1].controls;controls.search:SetText("Compilation error",true)
		local entry=controls.results.list[1].entry;assert.equal("Compilation error",entry.label);assert.equal("The filter is too large",entry.details[1])
		main:ClosePopup()
	end)
	it("opens the first error when the simulator requests error review",function()
		local profile=filters.profile("broken","Broken")
		require("Classes.LootFilterControl").Audit(profile,{diagnostics={{line=3,warning="Warning"},{line=9,error="Invalid font"}}},function() end,true)
		local controls=main.popups[1].controls;assert.equal("Line 9",controls.results.list[1].entry.label)
		assert.equal("Invalid font",controls.results.list[1].entry.details[1]);assert.is_false(controls.choose:IsEnabled());main:ClosePopup()
	end)
end)
