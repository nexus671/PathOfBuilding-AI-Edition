describe("Compiled filter structure",function()
	local filters=require("Modules.LootFilters")
	local structure=require("Modules.LootFilterStructure")
	local function profile()
		local p=filters.profile("test","Test");p.template='Show\n BaseType == "Chaos Orb"\nHide\n Class == "Helmets"'
		p.rules={filters.rule("personal","Personal Chaos",{'BaseType == "Chaos Orb"'})}
		p.tiers={{id="tier",title="Currency tier",items={"Divine Orb"},text='Show\n BaseType == "Divine Orb"'}}
		p.modules={{id="shared",title="Shared",rules={filters.rule("duplicate","Duplicate Chaos",{'BaseType == "Chaos Orb"'})}}}
		p.campaign=require("Modules.LootFilterCampaign").defaults();p.campaign.weapons={"Bow"};p.campaign.upgradeWindow=0;return p
	end
	before_each(function() newBuild() end)
	it("maps a native 3.30 preset without nonexistent safety blocks",function()
		local p=filters.profile("native","Native");local view=structure.outline(p)
		assert.equal(view.report.rules,#view.entries);assert.equal(0,#structure.filter(view,"","safety"));assert.is_true(#structure.filter(view,"","base")>500)
	end)
	it("does not flag different modifier counts as unreachable in the structure",function()
		local p=filters.profile("counts","Counts");p.template='Show\n HasExplicitMod >=2 "1"\nHide\n HasExplicitMod >=1 "2"'
		local view=structure.outline(p);local base=structure.filter(view,"","base")
		assert.equal(2,#base)
		for _,entry in ipairs(base) do for _,diagnostic in ipairs(structure.diagnostics(view,entry)) do assert.is_nil(diagnostic.shadowedBy) end end
	end)
	it("exposes proven threshold conflicts in the structure browser",function()
		local p=filters.profile("levels","Levels");p.template='Show\n ItemLevel >= 70\nHide\n ItemLevel >= 80'
		local view=structure.outline(p);local conflicts=structure.filter(view,"",nil,nil,"Priority conflicts")
		assert.equal(1,#conflicts);local reason=structure.diagnostics(view,conflicts[1])[1]
		assert.is_truthy(reason.shadowedBy);assert.matches("every item matched",reason.warning)
		local blocker=structure.blockingEntry(view,conflicts[1]);assert.is_not_nil(blocker);assert.equal(reason.shadowedBy,blocker.line);assert.matches("ItemLevel >= 70",blocker.text,1,true);assert.is_nil(structure.blockingEntry(view,blocker))
	end)
	it("opens a blocking rule and restores the prior filtered view",function()
		main.popups={};local p=filters.profile("navigation","Navigation");local lines={}
		for index=1,35 do lines[#lines+1]='Show\n BaseType == "Example '..index..'"' end
		lines[#lines+1]='Show\n ItemLevel >= 70';lines[#lines+1]='Hide\n ItemLevel >= 80';p.template=table.concat(lines,"\n")
		local c=require("Classes.LootFilterStructureControl").Open(p)
		local section;for _,row in ipairs(c.sections.list) do if row.id=="base" then section=row end end;assert.is_not_nil(section)
		c.sections.planningSelect(section,false);c.mode:SelByValue("Priority conflicts");c.mode.selFunc();c.search:SetText("ItemLevel >= 80",true)
		assert.is_true(c.blocking:IsEnabled());assert.is_false(c.backConflict:IsEnabled());c.blocking:Click()
		assert.equal("All blocks",c.mode:GetSelValue());assert.equal("",c.search.buf);assert.equal("all",c.sections.selectedKey);assert.is_true(c.blocks.controls.scrollBar.offset>0)
		local lines={};for _,row in ipairs(c.details.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;assert.matches("ItemLevel >= 70",table.concat(lines," "),1,true)
		c.backConflict:Click();assert.equal("Priority conflicts",c.mode:GetSelValue());assert.equal("ItemLevel >= 80",c.search.buf);assert.equal("base",c.sections.selectedKey)
		lines={};for _,row in ipairs(c.details.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;assert.matches("ItemLevel >= 80",table.concat(lines," "),1,true);assert.is_false(c.backConflict:IsEnabled())
		main:ClosePopup()
	end)
	it("exposes a covered base-type list in the structure browser",function()
		local p=filters.profile("base-list","Base list");p.template='Show\n BaseType == "Iron Hat" "Wool Shoes"\nHide\n BaseType == "Wool Shoes"'
		local view=structure.outline(p);local conflicts=structure.filter(view,"",nil,nil,"Priority conflicts")
		assert.equal(1,#conflicts);assert.matches("every item matched",structure.diagnostics(view,conflicts[1])[1].warning)
	end)
	it("finds exact numeric values covered by an earlier terminating range",function()
		local parser=require("Modules.LootFilterParser")
		local diagnostics=require("Modules.LootFilterDiagnostics")
		local cases={
			{">=",70,80,true},{">",80,80,false},{">=",80,80,true},
			{"<=",80,70,true},{"<",80,80,false},{"<=",80,80,true},
			{">=",80,70,false},{"<=",70,80,false},
		}
		for _,case in ipairs(cases) do
			local raw="Show\n Class == \"Helmets\"\n ItemLevel "..case[1].." "..case[2].."\nHide\n Class == \"Helmets\"\n ItemLevel == "..case[3]
			local conflicts=diagnostics.shadowing(parser.parse(raw))
			assert.are.equal(case[4],#conflicts==1,raw)
		end
		local unrelated='Show\n Class == "Boots"\n ItemLevel >= 70\nHide\n Class == "Helmets"\n ItemLevel == 80'
		assert.are.equal(0,#diagnostics.shadowing(parser.parse(unrelated)))
		local continuing='Show\n ItemLevel >= 70\n Continue\nHide\n ItemLevel == 80'
		assert.are.equal(0,#diagnostics.shadowing(parser.parse(continuing)))
	end)
	it("finds rules covered by a broader earlier condition set",function()
		local p=filters.profile("subset","Subset")
		p.template='Show\n Class == "Currency"\nHide\n Class == "Currency"\n BaseType == "Chaos Orb"\n ItemLevel >= 50\nShow\n Class == "Maps"\n BaseType == "Chaos Orb"'
		local view=structure.outline(p);local entries=structure.filter(view,"","base")
		assert.equal(3,#entries);assert.is_truthy(structure.diagnostics(view,entries[2])[1].shadowedBy)
		for _,diagnostic in ipairs(structure.diagnostics(view,entries[3])) do assert.is_nil(diagnostic.shadowedBy) end
		p.template='Show\n Class == "Currency"\n Continue\nHide\n Class == "Currency"\n BaseType == "Chaos Orb"'
		view=structure.outline(p);entries=structure.filter(view,"","base")
		for _,diagnostic in ipairs(structure.diagnostics(view,entries[2])) do assert.is_nil(diagnostic.shadowedBy) end
	end)
	it("maps every active block to its real source section and edit behavior",function()
		local view=structure.outline(profile());assert.equal(view.report.rules,#view.entries);local sections={};for _,group in ipairs(view.sections) do sections[group.id]=true end
		for _,id in ipairs({"personal","tiers","module-shared","campaign","safety","base"}) do assert.is_true(sections[id],id) end
		assert.equal("personal",view.entries[1].rule.id);assert.is_true(view.entries[1].editable)
		local tiers=structure.filter(view,"","tiers");assert.equal(1,#tiers);assert.is_truthy(tiers[1].rule.id:match("^override%-"));assert.is_nil(tiers[1].editable)
		local conflicts=structure.filter(view,"Chaos Orb",nil,nil,"Priority conflicts");assert.is_true(#conflicts>=2)
		for _,entry in ipairs(conflicts) do assert.is_truthy(structure.diagnostics(view,entry)[1].shadowedBy) end
	end)
	it("keeps disabled rules outside compiled structure and distinguishes Continue and unknown predicates",function()
		local p=profile();p.rules[1].enabled=false;p.modules={};p.template='Show\n BaseType == "Chaos Orb"\n Continue\nHide\n FutureProperty True'
		local view=structure.outline(p);assert.equal(0,#structure.filter(view,"","personal"));assert.equal(1,#structure.filter(view,"",nil,nil,"Continue blocks"))
		assert.equal(1,#structure.filter(view,"FutureProperty",nil,nil,"Warnings / errors"))
		assert.equal(0,#structure.filter(view,"[not a pattern]"))
	end)
	it("preserves unresolved imports as diagnostics rather than reading external files",function()
		local p=profile();p.template='Import "external.filter"\nShow\n BaseType == "Chaos Orb"';local view=structure.outline(p)
		assert.equal(1,#view.report.imports);assert.equal("external.filter",view.report.imports[1].file);assert.equal(1,#structure.filter(view,"","base"))
	end)
	it("uses one override identity across catalogue, structure, matched rules and appearance changes",function()
		local p=profile();local base=require("Modules.LootFilterLibrary").catalog(p)[1];local view=structure.outline(p);local source=structure.filter(view,"","base")[1]
		assert.equal(base.rule.id,source.rule.id)
		p.appearance={textColor={255,0,0,255}};local styled=structure.filter(structure.outline(p),"","base")[1];assert.equal(source.rule.id,styled.rule.id)
		local module=structure.filter(view,"","module-shared")[1];p.appearance.alertVolume=0;assert.equal(module.rule.id,structure.filter(structure.outline(p),"","module-shared")[1].rule.id)
	end)
end)
