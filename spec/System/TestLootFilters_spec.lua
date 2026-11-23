-- cspell:ignore RRAG RRRG GGGRRW GGGGR GGGRR GGRRRW winmm
describe("Build-owned loot filters",function()
	local filters=require("Modules.LootFilters")
	local parser=require("Modules.LootFilterParser")
	it("keeps Ruthless Minimal results separate from unknown drop outcomes",function()
		local outcome=require("Classes.LootFilterWorkspace").dropOutcome
		for _,action in ipairs({"Show","Hide","Minimal"}) do
			assert.equal(action,outcome(parser.simulate(parser.parse(action),{})))
		end
		assert.equal("Unknown",outcome(parser.simulate(parser.parse("Show\n ItemLevel >= 80"),{})))
		assert.equal("Unknown",outcome(parser.simulate(parser.parse("Show\n ItemLevel >= nope"),{})))
	end)
	before_each(function() newBuild();main.popups={} end)
	after_each(function() main.popups={} end)
	it("warns when unfinished written crafting steps cannot supply currency pickups",function()
		local project={id="manual-guide",title="Manual guide",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={{action="Use a rare currency"}}}
		build.savers.CraftingProjects:Upsert(project);local profile=filters.profile("manual","Manual");local _,warnings=filters.generate(build,profile)
		local found=false;for _,entry in ipairs(warnings) do if entry.origin=="craft:manual-guide" and entry.message:find("Written guide steps",1,true) then found=true end end;assert.is_true(found)
		local report=require("Modules.LootFilterDependencies").report(build,profile);local linked;for _,entry in ipairs(report.entries) do if entry.origin=="craft:manual-guide" then linked=entry end end;assert.is_true(linked.openGuide)
		project.steps[1].done=true;build.savers.CraftingProjects:Upsert(project);_,warnings=filters.generate(build,profile)
		for _,entry in ipairs(warnings) do assert.is_false(entry.origin=="craft:manual-guide" and entry.message:find("Written guide steps",1,true)~=nil) end
	end)
	it("remembers a reviewed written guide and asks again when the guide or budget changes",function()
		local project={id="reviewed-guide",title="Guide",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={{action="Use a rare currency"}}}
		build.savers.CraftingProjects:Upsert(project);local profile=filters.profile("reviewed","Reviewed");local _,warnings=filters.generate(build,profile)
		local signature=warnings[1].manualGuideSignature;assert.is_not_nil(signature);local dependencies=require("Modules.LootFilterDependencies");assert.is_true(dependencies.report(build,profile).needsReview)
		profile.manualGuideReviews={{projectId=project.id,signature=signature}};assert.is_false(dependencies.report(build,profile).needsReview)
		build.savers.LootFilters:Upsert(profile);local xml=build:SaveDB("Reviewed guide");loadBuildFromXML(xml,"Reviewed guide");profile=build.savers.LootFilters.data.profiles[1]
		_,warnings=filters.generate(build,profile);assert.equal(0,#warnings)
		build.savers.AtlasPlans:Upsert({id="other-warning",title="Atlas",version="3.30.0c",budget=150,nodes={},strategy={maps="Strand Map"}})
		_,warnings=filters.generate(build,profile);assert.equal(1,#warnings);assert.equal("atlas:other-warning",warnings[1].origin);build.savers.AtlasPlans:Remove("other-warning")
		local journey=require("Modules.BuildJourney").empty();journey.resources={{id="currency",title="Chaos Orb"}};build.savers.BuildJourney:Replace(journey)
		_,warnings=filters.generate(build,profile);assert.equal(1,#warnings);assert.is_not.equal(signature,warnings[1].manualGuideSignature)
		profile.manualGuideReviews[1].signature=warnings[1].manualGuideSignature;project.steps[1].action="Use a different currency";build.savers.CraftingProjects:Upsert(project)
		_,warnings=filters.generate(build,profile);assert.equal(1,#warnings);assert.is_not.equal(profile.manualGuideReviews[1].signature,warnings[1].manualGuideSignature)
		profile.manualGuideReviews[1].signature=warnings[1].manualGuideSignature;project.notes="A different crafting material";build.savers.CraftingProjects:Upsert(project)
		_,warnings=filters.generate(build,profile);assert.equal(1,#warnings);assert.is_not.equal(profile.manualGuideReviews[1].signature,warnings[1].manualGuideSignature)
		local before=filters.empty();local without=copyTable(profile);without.manualGuideReviews=nil;before.profiles={without};local after=filters.empty();after.profiles={profile}
		local review=require("Modules.LootFilterEditing").review(before,after);assert.matches("Reviewed crafting guide: reviewed%-guide",table.concat(review[1].details," "))
	end)
	it("explains invalid filter previews with their compiled line in single and batch tests",function()
		local direct=parser.simulate(parser.parse('Show\n SetFontSize 99'),{})
		assert.equal("invalid",direct.status);assert.equal(2,direct.line);assert.matches("line 2: Invalid SetFontSize",direct.reasons[1])
		local profile=filters.profile("invalid-preview","Invalid preview");profile.template='Show\n SetFontSize 99'
		profile.sampleSets={{id="drops",title="Drops",samples={{BaseType="Iron Hat"},{BaseType="Iron Ring"}}}}
		local _,report=filters.compile(profile);local expected
		for _,entry in ipairs(report.diagnostics) do if entry.error then expected=entry;break end end
		assert.is_truthy(expected)
		local single=filters.simulate(profile,{});local page=filters.simulateExamples(profile,"drops",0,2)
		for _,result in ipairs({single,page.results[1].result,page.results[2].result}) do
			assert.equal("invalid",result.status);assert.equal(expected.line,result.line)
			assert.equal("Filter line "..expected.line..": "..expected.error,result.reasons[1])
		end
	end)
	it("keeps undocumented Continue arguments uncertain without changing the text",function()
		local raw='Show\n BaseType "Iron"\n Continue unexpected\nHide'
		local parsed=parser.parse(raw);assert.equal(1,#parsed.diagnostics);assert.equal(3,parsed.diagnostics[1].line);assert.is_true(parsed.diagnostics[1].unverifiedContinue)
		for _,item in ipairs({{BaseType="Iron Hat"},{BaseType="Wooden Shield"}}) do local outcome=parser.simulate(parsed,item);assert.equal("unknown",outcome.status);assert.equal(3,outcome.line);assert.matches("Continue arguments",outcome.reasons[1]) end
		assert.equal("Hide",parser.simulate(parser.parse('Show\n Continue # comment\nHide'),{}).action)
		local profile=filters.profile("continue-warning","Continue warning");profile.template=raw;local text,report=filters.compile(profile);assert.is_truthy(text:find("Continue unexpected",1,true));local found=false;for _,d in ipairs(report.diagnostics) do if d.unverifiedContinue then found=true end end;assert.is_true(found)
	end)
	it("keeps undocumented drop-sound arguments uncertain without changing the filter",function()
		for _,name in ipairs({"DisableDropSound","EnableDropSound","DisableDropSoundIfAlertSound","EnableDropSoundIfAlertSound"}) do
			local raw='Show\n '..name..' unexpected\nHide';local parsed=parser.parse(raw)
			assert.equal(name,parsed.diagnostics[1].unverifiedAction);assert.equal(2,parsed.diagnostics[1].line)
			local outcome=parser.simulate(parsed,{});assert.equal("unknown",outcome.status);assert.equal(2,outcome.line);assert.matches(name.." arguments",outcome.reasons[1])
			local profile=filters.profile("sound-warning","Sound warning");profile.template=raw;local text,report=filters.compile(profile);assert.is_truthy(text:find(name..' unexpected',1,true));assert.is_truthy(report.diagnostics[1])
			assert.equal("Show",parser.simulate(parser.parse('Show\n '..name..' # comment'),{}).action)
		end
		assert.equal("Show",parser.simulate(parser.parse('Show\n DisableDropSound True'),{}).action)
	end)
	it("accepts the bundled drop-sound compatibility form",function()
		local parsed=parser.parse("Show\n DisableDropSound True")
		assert.equal(0,#parsed.diagnostics);assert.equal("matched",parser.simulate(parsed,{}).status)
	end)
	it("parses every bundled filter preset without errors",function()
		for index=0,6 do
			local path="Data/LootFilters/"..index..".filter";local file=assert(io.open(path,"rb"));local raw=file:read("*a");file:close()
			local parsed=parser.parse(raw);assert.is_true(#parsed.rules>0,path)
			for _,diagnostic in ipairs(parsed.diagnostics) do assert.is_nil(diagnostic.error,path..":"..diagnostic.line.." "..tostring(diagnostic.error)) end
		end
	end)
	it("rejects malformed imports even when other imports are unresolved",function()
		for _,line in ipairs({"Import",'Import ""','Import "file.filter" Invalid','Import "file.filter" Optional extra'}) do
			local parsed=parser.parse('Import "valid.filter" Optional\n'..line..'\nShow')
			assert.equal("invalid",parser.simulate(parsed,{}).status);assert.equal(2,parsed.diagnostics[1].line)
		end
		local parsed=parser.parse('Import "required.filter"\nImport "optional.filter" Optional\nShow')
		assert.equal(0,#parsed.diagnostics);assert.equal(2,#parsed.imports);assert.is_true(parsed.imports[2].optional);assert.equal("unknown",parser.simulate(parsed,{}).status)
		local profile=filters.profile("bad-import","Bad import");profile.template='Import "file.filter" Invalid\nShow'
		local _,report=filters.compile(profile);local found=false;for _,entry in ipairs(report.diagnostics) do if entry.error and entry.error:find("Invalid Import",1,true) then found=true end end;assert.is_true(found)
	end)
	it("respects unresolved imports in rule order",function()
		local raw='Hide\n BaseType "Iron Hat"\nImport "missing.filter"\nShow'
		local before=parser.simulate(parser.parse(raw),{BaseType="Iron Hat"})
		assert.equal("matched",before.status);assert.equal("Hide",before.action);assert.equal(1,before.line)
		assert.matches("Later included files",before.reasons[1])
		local after=parser.simulate(parser.parse(raw),{BaseType="Iron Ring"})
		assert.equal("unknown",after.status);assert.equal(3,after.line);assert.matches("missing.filter",after.reasons[1])
		local continuing=parser.simulate(parser.parse('Hide\n Continue\nImport "missing.filter"\nShow'),{})
		assert.equal("unknown",continuing.status);assert.equal("Unknown",continuing.action);assert.same({1},continuing.matches)
		assert.equal("unknown",parser.simulate(parser.parse('Show\n BaseType "Iron Hat"\nImport "missing.filter"'),{}).status)
		assert.equal("invalid",parser.simulate(parser.parse('Show\nImport "bad.filter" Invalid'),{}).status)
		local profile=filters.profile("ordered-import","Ordered import");profile.template=raw
		assert.equal("Hide",filters.simulate(profile,{BaseType="Iron Hat"}).action)
		assert.equal("unknown",filters.simulate(profile,{BaseType="Iron Ring"}).status)
		profile.importFiles={{name="missing.filter",text='Hide\n BaseType "Iron Ring"'}}
		assert.equal("Hide",filters.simulate(profile,{BaseType="Iron Ring"}).action)
	end)
	it("evaluates saved example sets in stable pages without changing the profile",function()
		local profile=filters.profile("examples","Examples")
		profile.template='Hide\n BaseType "Iron Hat"\nShow\n ItemLevel >= 80\nHide'
		profile.sampleSets={{id="drops",title="Drops",samples={{BaseType="Iron Hat"},{BaseType="Iron Ring",ItemLevel=86},{BaseType="Iron Ring"}}}}
		local before=copyTable(profile);local progress={}
		local page=filters.simulateExamples(profile,"drops",0,2,function(value) progress[#progress+1]=value.completed end)
		assert.equal(3,page.total);assert.equal(2,page.nextOffset);assert.same({1,2},progress)
		assert.equal(0,page.results[1].index);assert.equal("Hide",page.results[1].result.action)
		assert.equal(1,page.results[2].index);assert.equal("Show",page.results[2].result.action)
		local last=filters.simulateExamples(profile,"drops",page.nextOffset,2);assert.is_nil(last.nextOffset)
		assert.equal(2,last.results[1].index);assert.equal("unknown",last.results[1].result.status)
		assert.same(before,profile);assert.is_false(pcall(filters.simulateExamples,profile,"missing",0,1))
		assert.is_false(pcall(filters.simulateExamples,profile,"drops",4,1));assert.is_false(pcall(filters.simulateExamples,profile,"drops",0,51))
		local long=copyTable(profile);long.template=string.rep("Show\n Continue\n",35).."Hide";long.sampleSets[1].samples={{BaseType=string.rep("x",300)}}
		local compact=filters.simulateExamples(long,"drops",0,1).results[1]
		assert.is_true(compact.baseTypeTruncated);assert.equal(240,#compact.baseType)
		assert.is_true(compact.result.matchesTruncated);assert.equal(30,#compact.result.matches);assert.equal("Hide",compact.result.action)
	end)
	it("preserves quoted conditions and modifier counts when restyling",function()
		local library=require("Modules.LootFilterLibrary")
		for _,condition in ipairs({'HasExplicitMod >=2 "Haast" "Ephij"','HasExplicitMod "1"','BaseType "123"'}) do
			local rule={id="quoted",title="Quoted",text="Show\n "..condition}
			local edited=library.appearance(rule,{SetFontSize={"42"}});local parsed=parser.parse(edited.text)
			assert.equal(0,#parsed.diagnostics)
			local before=parser.parse(rule.text).rules[1].conditions[1];local after=parsed.rules[1].conditions[1]
			assert.equal(before.operator,after.operator);assert.same(before.values,after.values);assert.same(before.quoted,after.quoted)
		end
	end)
	it("does not claim matches for impossible numeric drop samples",function()
		local function test(condition,item) return parser.simulate(parser.parse("Show\n "..condition.."\nHide"),item) end
		for _,value in ipairs({-1,2.5,7,math.huge,-math.huge,0/0}) do
			for _,condition in ipairs({"Sockets >= 1","SocketGroup R","LinkedSockets >= 1"}) do
				local result=test(condition,{Sockets=value,SocketGroup="R"});assert.equal("unknown",result.status);assert.matches("Invalid Sockets",result.reasons[1],1,true)
			end
		end
		for _,value in ipairs({math.huge,-math.huge,0/0}) do
			local result=test("ItemLevel >= 80",{ItemLevel=value});assert.equal("unknown",result.status);assert.matches("Invalid ItemLevel",result.reasons[1],1,true)
		end
		for _,value in ipairs({-1,5.5,6}) do assert.equal("unknown",test("UnidentifiedItemTier >= 4",{UnidentifiedItemTier=value}).status) end
		for _,value in ipairs({-1,101}) do assert.equal("unknown",test("BaseDefencePercentile >= 90",{BaseDefencePercentile=value}).status) end
		assert.equal("Show",test("UnidentifiedItemTier >= 4",{UnidentifiedItemTier=4}).action)
		assert.equal("Show",test("BaseDefencePercentile >= 90",{BaseDefencePercentile=100}).action)
	end)
	it("distinguishes known zero sockets from an unknown socket group",function()
		local function test(condition,item) return parser.simulate(parser.parse("Show\n "..condition.."\nHide"),item) end
		for _,item in ipairs({{Sockets=0},{SocketGroup="0"},{SocketGroup=""}}) do
			assert.equal("Show",test("SocketGroup 0",item).action)
			assert.equal("Show",test("SocketGroup < 1",item).action)
			assert.equal("Hide",test("SocketGroup >= 1",item).action)
		end
		assert.equal("Hide",test("SocketGroup 0",{SocketGroup="W"}).action)
		assert.equal("unknown",test("SocketGroup 0",{}).status)
		assert.equal("Hide",test("Sockets R",{Sockets=0}).action)
	end)
	it("rejects zero linked sockets when the sample has sockets",function()
		local function test(condition,item) return parser.simulate(parser.parse("Show\n "..condition.."\nHide"),item) end
		for _,item in ipairs({{Sockets=2,LinkedSockets=0},{SocketColours="R-G",LinkedSockets=0},{SocketGroup="R-G",LinkedSockets=0}}) do
			for _,condition in ipairs({"Sockets >= 1","SocketGroup RG","LinkedSockets = 0"}) do
				local result=test(condition,item);assert.equal("unknown",result.status);assert.matches("Zero linked sockets",result.reasons[1],1,true)
			end
		end
		assert.equal("Show",test("LinkedSockets = 0",{Sockets=0,LinkedSockets=0}).action)
		assert.equal("Show",test("LinkedSockets = 0",{LinkedSockets=0}).action)
	end)
	it("uses complete socket colours when the separate count is omitted",function()
		local function test(condition,item) return parser.simulate(parser.parse("Show\n "..condition.."\nHide"),item) end
		local item={SocketColours="R-G B A"}
		assert.equal("Show",test("Sockets >= 4",item).action)
		assert.equal("Hide",test("Sockets >= 5",item).action)
		assert.equal("Show",test("Sockets RGA",item).action)
		assert.equal("unknown",test("Sockets R",{}).status)
		assert.equal("unknown",test("Sockets >= 1",{SocketColours="R-X"}).status)
		assert.equal("unknown",test("Sockets >= 1",{SocketColours="-------"}).status)
		assert.equal("unknown",test("Sockets >= 1",{SocketColours="RRRRRRR"}).status)
		assert.equal("unknown",test("SocketGroup RG",item).status)
	end)
	it("derives links only when the group layout accounts for all sockets",function()
		local function test(condition,item) return parser.simulate(parser.parse("Show\n "..condition.."\nHide"),item) end
		local full={Sockets=4,SocketGroup="R-G B A"}
		assert.equal("Show",test("LinkedSockets = 2",full).action)
		assert.equal("Hide",test("LinkedSockets >= 3",full).action)
		assert.equal("Show",test("LinkedSockets = 1",{Sockets=3,SocketGroup="R-A-G"}).action)
		assert.equal("Show",test("LinkedSockets = 0",{Sockets=0}).action)
		assert.equal("Show",test("LinkedSockets = 0",{SocketGroup="0"}).action)
		assert.equal("unknown",test("LinkedSockets >= 2",{Sockets=4,SocketGroup="RG"}).status)
		assert.equal("unknown",test("LinkedSockets >= 2",{SocketGroup="RG"}).status)
		assert.equal("unknown",test("LinkedSockets >= 2",{Sockets=2,SocketGroup="RX"}).status)
	end)
	it("keeps whitespace-separated groups and link counts consistent",function()
		local function test(condition,item) return parser.simulate(parser.parse("Show\n "..condition.."\nHide"),item) end
		local separated={Sockets=2,SocketGroup="R\tG"}
		assert.equal("Hide",test("SocketGroup RG",separated).action)
		assert.equal("Show",test("LinkedSockets = 1",separated).action)
		local contradiction={Sockets=4,SocketGroup="R-G B A",LinkedSockets=4}
		local result=test("LinkedSockets >= 4",contradiction)
		assert.equal("unknown",result.status);assert.is_truthy(result.reasons[1])
		assert.equal("unknown",test("SocketGroup RG",contradiction).status)
		assert.equal("unknown",test("LinkedSockets >= 4",{Sockets=2,LinkedSockets=4}).status)
		assert.equal("unknown",test("LinkedSockets >= 4",{LinkedSockets=7}).status)
		assert.equal("Show",test("LinkedSockets = 2",{Sockets=4,SocketGroup="R-G B A",LinkedSockets=2}).action)
	end)
	it("uses complete colours to verify a group layout without a separate socket count",function()
		local function test(condition,item) return parser.simulate(parser.parse("Show\n "..condition.."\nHide"),item) end
		local complete={SocketColours="BRG",SocketGroup="R-G B"}
		assert.equal("Show",test("LinkedSockets = 2",complete).action);assert.equal("Hide",test("LinkedSockets >= 3",complete).action)
		assert.equal("Show",test("SocketGroup RG",complete).action)
		local contradictory={SocketColours="BRG",SocketGroup="R-G B",LinkedSockets=3}
		assert.equal("unknown",test("LinkedSockets = 3",contradictory).status);assert.equal("unknown",test("SocketGroup RG",contradictory).status)
		assert.equal("unknown",test("LinkedSockets >= 2",{SocketGroup="R-G"}).status)
	end)

	it("rejects inconsistent socket colours across sample fields",function()
		local function test(condition,item) return parser.simulate(parser.parse("Show\n "..condition.."\nHide"),item) end
		local cases={
			{Sockets=2,SocketColours="RR",SocketGroup="R-G",LinkedSockets=2},
			{Sockets=3,SocketColours="RG",SocketGroup="R-G B",LinkedSockets=2},
			{Sockets=3,SocketColours="RGB",SocketGroup="R-G",LinkedSockets=2},
		}
		for _,item in ipairs(cases) do for _,condition in ipairs({"Sockets >= 2","Sockets R","SocketGroup RG","LinkedSockets >= 1"}) do
			local result=test(condition,item);assert.equal("unknown",result.status,condition);assert.is_truthy(result.reasons[1])
		end end
		local consistent={Sockets=3,SocketColours="BRG",SocketGroup="R-G B",LinkedSockets=2}
		assert.equal("Show",test("Sockets >= 3",consistent).action)
		assert.equal("Show",test("SocketGroup RG",consistent).action)
		assert.equal("Show",test("LinkedSockets = 2",consistent).action)
		assert.equal("Show",test("Sockets >= 2",{Sockets=2}).action)
	end)

	it("does not decide linked group matches from an incomplete socket layout",function()
		local function test(item) return parser.simulate(parser.parse("Show\n SocketGroup RGB\nHide"),item) end
		for _,item in ipairs({{Sockets=6,SocketGroup="RG"},{Sockets=4,SocketGroup="RGB"},{Sockets=3,SocketGroup="0"},{Sockets=1,SocketGroup=""},{SocketGroup="RRRRRRR"},{SocketGroup="---"}}) do
			local result=test(item);assert.equal("unknown",result.status);assert.equal("Unknown",result.action);assert.is_truthy(result.reasons[1])
		end
		assert.equal("Hide",test({Sockets=2,SocketGroup="RG"}).action)
		assert.equal("Show",test({Sockets=3,SocketGroup="RGB"}).action)
		assert.equal("Show",test({SocketGroup="RGB"}).action)
	end)
	it("never treats Abyss or Delve sockets as links in simulated drops",function()
		local function action(condition,item)
			return parser.simulate(parser.parse("Show\n "..condition.."\nHide"),item).action
		end
		assert.equal("Hide",action("SocketGroup RG",{SocketGroup="RAG"}))
		assert.equal("Hide",action("SocketGroup >= 2",{SocketGroup="AA"}))
		assert.equal("Hide",action("SocketGroup DD",{SocketGroup="DD"}))
		assert.equal("Show",action("SocketGroup A",{SocketGroup="RAG"}))
		assert.equal("Show",action("SocketGroup 2RR",{SocketGroup="RRAG"}))
		assert.equal("Show",action("Sockets RAG",{Sockets=3,SocketColours="RAG"}))
	end)
	it("compares socket counts separately from minimum colours",function()
		local function action(condition,item)
			return parser.simulate(parser.parse("Show\n "..condition.."\nHide"),item).action
		end
		assert.equal("Show",action("SocketGroup > 5GGG",{SocketGroup="GGGRRW"}))
		assert.equal("Show",action("SocketGroup <= 5GGG",{SocketGroup="GGGGR"}))
		assert.equal("Hide",action("SocketGroup == 5GGG",{SocketGroup="GGGGR"}))
		assert.equal("Show",action("SocketGroup == 5GGG",{SocketGroup="GGGRR"}))
		assert.equal("Show",action("SocketGroup == RRR GGG BBB",{SocketGroup="RRR"}))
		assert.equal("Hide",action("SocketGroup == RRR GGG BBB",{SocketGroup="RRRG"}))
		assert.equal("Show",action("SocketGroup RRR",{SocketGroup="RRRG"}))
		assert.equal("Hide",action("Sockets == RRR",{Sockets=4,SocketColours="RRRG"}))
		assert.equal("Show",action("Sockets == RRR",{Sockets=3,SocketColours="RRR"}))
		assert.equal("Show",action("Sockets < 6GGG",{Sockets=5,SocketColours="GGGGR"}))
		assert.equal("Show",action("Sockets > 5GGG",{Sockets=6,SocketColours="GGRRRW"}))
		assert.equal("Show",action("SocketGroup < 4RG",{SocketGroup="BBBB"}))
		assert.equal("Show",action("SocketGroup > 4RG",{SocketGroup="RR"}))
		assert.equal("Hide",action("SocketGroup > 4RG",{SocketGroup="RG"}))
		assert.equal("Show",action("Sockets < 4RG",{Sockets=4,SocketColours="BBBB"}))
		assert.equal("Show",action("Sockets > 4RG",{Sockets=2,SocketColours="RR"}))
		assert.equal("Hide",action("Sockets > 4RG",{Sockets=2,SocketColours="RG"}))
	end)
	it("rejects malformed socket patterns and explains invalid sample colours",function()
		for _,condition in ipairs({"SocketGroup XYZ","SocketGroup 3RGBx","Sockets 5GR?",'SocketGroup ""'}) do
			local parsed=parser.parse("Hide\n "..condition.."\nShow")
			assert.equal("invalid",parser.simulate(parsed,{SocketGroup="RGB",Sockets=3,SocketColours="RGB"}).status)
		end
		local result=parser.simulate(parser.parse("Hide\n SocketGroup RGB\nShow"),{SocketGroup="RGB?"})
		assert.equal("unknown",result.status);assert.equal("Unknown",result.action);assert.matches("Invalid socket colours",result.reasons[1])
		result=parser.simulate(parser.parse("Hide\n Sockets RGB\nShow"),{Sockets=3,SocketColours="RGB?"})
		assert.equal("unknown",result.status);assert.equal("Unknown",result.action)
		assert.equal("Hide",parser.simulate(parser.parse("Hide\n SocketGroup RGB\nShow"),{SocketGroup="R-G-B"}).action)
	end)
	it("tests mixed socket-count and colour alternatives without guessing missing colours",function()
		local function result(condition,item) return parser.simulate(parser.parse("Hide\n "..condition.."\nShow"),item) end
		local rgb={Sockets=3,SocketColours="RGB"}
		assert.equal("Hide",result("Sockets 6 RGB",rgb).action)
		assert.equal("Hide",result("Sockets RGB 3",rgb).action)
		assert.equal("Hide",result("Sockets RGB",{Sockets="RGB"}).action)
		assert.equal("Show",result("Sockets 6 RRR",rgb).action)
		assert.equal("Hide",result("Sockets 3 RGB",{Sockets=3}).action)
		assert.equal("Hide",result("Sockets RGB 3",{Sockets=3}).action)
		assert.equal("unknown",result("Sockets 6 RGB",{Sockets=3}).status)
		assert.equal("unknown",result("Sockets RGB 6",{Sockets=3,SocketColours="RGB?"}).status)
		local inconsistent={Sockets=4,SocketColours="RGB"}
		assert.equal("unknown",result("Sockets RGB",inconsistent).status)
		assert.matches("Socket count does not match",result("Sockets RGB",inconsistent).reasons[1])
		assert.equal("unknown",result("Sockets 4 RGB",inconsistent).status)
		assert.equal("unknown",result("Sockets 6 RGB",inconsistent).status)
		assert.equal("unknown",result("Sockets RGB",{Sockets=0,SocketColours="RGB"}).status)
		assert.equal("Show",result("Sockets != 3 6",{Sockets=3}).action)
		assert.equal("unknown",result("Sockets != 3R",{Sockets=3,SocketColours="BBB"}).status)
		assert.equal("unknown",result("Sockets != R",{Sockets=3,SocketColours="RGB"}).status)
		assert.equal("Show",result("Sockets != 3R 3",{Sockets=3,SocketColours="BBB"}).action)
		assert.equal("unknown",result("SocketGroup != 3R",{SocketGroup="BBB"}).status)
		assert.equal("unknown",result("SocketGroup ! 3",{SocketGroup="RGB"}).status)
	end)
	it("updates numbered alerts across continuing blocks",function()
		local audio=require("Modules.LootFilterAudio")
		local function result(raw) return parser.simulate(parser.parse(raw),{}) end
		local muted=result('Show\n PlayAlertSound 4\n Continue\nShow\n PlayAlertSoundPositional None')
		assert.is_nil(muted.styles.PlayAlertSound);assert.same({"None"},muted.styles.PlayAlertSoundPositional)
		local id,reason=audio.alert(muted.styles);assert.is_nil(id);assert.matches("disabled",reason)
		local replaced=result('Show\n PlayAlertSoundPositional 4\n Continue\nShow\n PlayAlertSound 6')
		assert.is_nil(replaced.styles.PlayAlertSoundPositional);assert.equal(6,audio.alert(replaced.styles))
		local ambiguous=result('Show\n PlayAlertSound 4\n PlayAlertSoundPositional 6')
		id,reason=audio.alert(ambiguous.styles);assert.is_nil(id);assert.matches("not verified",reason)
		local custom=result('Show\n CustomAlertSound "custom.wav"\n PlayAlertSound 4\n Continue\nShow\n PlayAlertSoundPositional 6')
		id,reason=audio.alert(custom.styles);assert.is_nil(id);assert.matches("overrides",reason)
	end)
	it("tracks independent drop sound settings across continuing blocks",function()
		local audio=require("Modules.LootFilterAudio")
		local function result(raw) return parser.simulate(parser.parse(raw),{}) end
		local changed=result("Show\n DisableDropSound\n DisableDropSoundIfAlertSound\n Continue\nShow\n EnableDropSound")
		assert.is_nil(changed.styles.DisableDropSound);assert.is_not_nil(changed.styles.EnableDropSound)
		assert.is_not_nil(changed.styles.DisableDropSoundIfAlertSound)
		assert.matches("disabled when an alert",audio.dropSound(changed.styles))
		local enabled=result("Show\n DisableDropSoundIfAlertSound\n Continue\nShow\n EnableDropSoundIfAlertSound")
		assert.is_nil(enabled.styles.DisableDropSoundIfAlertSound);assert.equal("Drop sound: enabled.",audio.dropSound(enabled.styles))
		local disabled=result("Show\n DisableDropSound\n EnableDropSoundIfAlertSound")
		assert.equal("Drop sound: disabled.",audio.dropSound(disabled.styles))
		local ambiguous=result("Show\n DisableDropSound\n EnableDropSound")
		assert.matches("conflicting",audio.dropSound(ambiguous.styles))
		local args=result("Show\n DisableDropSound True")
		assert.matches("verification",audio.dropSound(args.styles));assert.is_nil(audio.dropSound({}))
	end)
	it("applies first-match ordering, Continue styles and exact/partial names",function()
		local raw='Show\n BaseType "Iron"\n SetTextColor 255 0 0\n Continue\nHide\n BaseType == "Iron Hat"\n SetFontSize 25\nShow'
		local result=parser.simulate(parser.parse(raw),{BaseType="Iron Hat"})
		assert.equal("Hide",result.action);assert.equal(2,#result.matches);assert.same({"255","0","0"},result.styles.SetTextColor)
		assert.equal("Show",parser.simulate(parser.parse(raw),{BaseType="Iron Ring"}).action)
	end)
	it("validates documented alert sound IDs and volumes",function()
		for _,line in ipairs({"PlayAlertSound 0","PlayAlertSound 17","PlayAlertSound 1 301","PlayAlertSoundPositional 2 -1",'CustomAlertSound "file.wav" 301',"CustomAlertSoundOptional",'CustomAlertSound ""'}) do
			local result=parser.simulate(parser.parse("Show\n "..line.."\nHide"),{})
			assert.equal("invalid",result.status,line)
		end
		for _,line in ipairs({"PlayAlertSound None","PlayAlertSound 1 0","PlayAlertSoundPositional 16 300",'CustomAlertSound "file one.wav;file two.wav" 100',"DisableDropSound True"}) do
			assert.equal("matched",parser.simulate(parser.parse("Show\n "..line),{}).status,line)
		end
	end)
	it("scales reference audio by the selected volume without changing system settings",function()
		local audio=require("Modules.LootFilterAudio")
		local file=assert(io.open("Assets/LootFilters/alert-1.wav","rb"));local raw=file:read("*a");file:close()
		local quiet=audio.scaleReferenceWave(raw,50);local loud=audio.scaleReferenceWave(raw,300)
		assert.equal(#raw,#quiet);assert.equal(#raw,#loud);assert.equal(raw:sub(1,44),quiet:sub(1,44));assert.equal(raw,audio.scaleReferenceWave(raw,100))
		local function sample(wave,i) local a,b=wave:byte(i,i+1);local value=a+b*256;return value>=32768 and value-65536 or value end
		local found=false
		for i=45,#raw-1,2 do
			local original=sample(raw,i)
			if original>0 and original<10000 then assert.equal(math.floor(original/2),sample(quiet,i));assert.equal(original*3,sample(loud,i));found=true;break end
		end
		assert.is_true(found)
		local clipped=false;for i=45,#raw-1,2 do if sample(raw,i)>10923 then assert.equal(32767,sample(loud,i));clipped=true;break end end
		assert.is_true(clipped);assert.has_error(function() audio.scaleReferenceWave("invalid",50) end);assert.has_error(function() audio.scaleReferenceWave(raw,301) end)
		for id=2,16 do local source=assert(io.open("Assets/LootFilters/alert-"..id..".wav","rb"));local bytes=source:read("*a");source:close();assert.equal(#bytes,#audio.scaleReferenceWave(bytes,50)) end
		local ffi=require("ffi")
		if ffi.os=="Windows" then
			local load=ffi.load;local played
			ffi.load=function(name) if name=="winmm" then return {PlaySoundA=function(buffer,_,flags) played={wave=ffi.string(buffer,#raw),flags=flags};return 1 end} end;return load(name) end
			local ok,success,message=pcall(audio.play,{PlayAlertSound={"1","50"}});ffi.load=load
			assert.is_true(ok);assert.is_true(success);assert.matches("volume%-adjusted",message);assert.same(quiet,played.wave);assert.equal(7,played.flags);assert.is_not_nil(audio.buffer)
		end
	end)
	it("treats numeric text as a name outside modifier-count conditions",function()
		local function action(condition,item) return parser.simulate(parser.parse("Hide\n "..condition.."\nShow"),item).action end
		assert.equal("Hide",action('BaseType "1"',{BaseType="Level 1 Relic"}))
		assert.equal("Show",action('BaseType == "1"',{BaseType="Level 1 Relic"}))
		assert.equal("Hide",action('Class "2"',{Class="Tier 2 Items"}))
		assert.equal("Show",action('BaseType != "1"',{BaseType="Level 1 Relic"}))
		assert.equal("Hide",action('HasExplicitMod >=2 "Haast" "Ephij"',{Identified=true,HasExplicitMod={"of Haast","of Ephij"}}))
		assert.equal("Show",action('HasExplicitMod >=2 "Haast" "Ephij"',{Identified=true,HasExplicitMod={"of Haast"}}))
	end)
	it("preserves quoted names that resemble numbers or operators",function()
		local function action(condition,item) return parser.simulate(parser.parse("Hide\n "..condition.."\nShow"),item).action end
		assert.equal("Hide",action('HasExplicitMod "1"',{Identified=true,HasExplicitMod={"Tier 1"}}))
		assert.equal("Hide",action('HasEnchantment "1"',{HasEnchantment={"Enchantment 1"}}))
		assert.equal("Hide",action('BaseType ">=1"',{BaseType=">=1 Token"}))
		assert.equal("Hide",action('HasExplicitMod >=2 "Haast" "Ephij"',{Identified=true,HasExplicitMod={"of Haast","of Ephij"}}))
		local saved;require("Classes.LootFilterControl").Conditions({id="quoted",title="Quoted",text='Hide\n HasExplicitMod "1"\n BaseType ">=1"'},function(value) saved=value end)
		main.popups[1].controls.keepRule:Click();assert.is_truthy(saved.text:find('HasExplicitMod = "1"',1,true));assert.is_truthy(saved.text:find('BaseType = ">=1"',1,true))
		assert.equal("Hide",parser.simulate(parser.parse(saved.text.."\nShow"),{Identified=true,HasExplicitMod={"Tier 1"},BaseType=">=1 Token"}).action)
	end)
	it("keeps modifier count operators joined to their number",function()
		for _,key in ipairs({"HasExplicitMod","HasEnchantment"}) do
			local raw='Hide\n '..key..' >=2 "Haast" "Ephij"';local saved
			require("Classes.LootFilterControl").Conditions({id="count",title="Count",text=raw},function(value) saved=value end)
			main.popups[1].controls.keepRule:Click();assert.is_truthy(saved.text:find(key..' >=2 "Haast" "Ephij"',1,true))
			local item={Identified=true,[key]={"of Haast","of Ephij"}};assert.equal("Hide",parser.simulate(parser.parse(saved.text.."\nShow"),item).action)
			assert.equal("invalid",parser.simulate(parser.parse('Hide\n '..key..' >= 2 "Haast"\nShow'),item).status)
		end
	end)
	it("preserves appearance command order and continue arguments when editing conditions",function()
		local raw='Show\n BaseType "Iron Hat"\n DisableDropSound\n EnableDropSound\n DisableDropSound\n SetTextColor 1 2 3\n Continue unexpected'
		local saved;local editor=require("Classes.LootFilterControl")
		editor.Conditions({id="order",title="Order",text=raw},function(value) saved=value end)
		main.popups[1].controls.keepRule:Click()
		assert.is_truthy(saved.text:find('DisableDropSound\n EnableDropSound\n DisableDropSound\n SetTextColor 1 2 3\n Continue unexpected',1,true))
		local parsed=parser.parse(saved.text);assert.is_true(parsed.diagnostics[1].unverifiedContinue)
		editor.Conditions({id="order",title="Order",text=raw},function(value) saved=value end)
		main.popups[1].controls.theme:SelByValue("High contrast");main.popups[1].controls.keepRule:Click()
		assert.is_truthy(saved.text:find('DisableDropSound\n EnableDropSound\n DisableDropSound',1,true))
		assert.is_nil(saved.text:find('SetTextColor 1 2 3',1,true));assert.is_truthy(saved.text:find('Continue unexpected',1,true))
		local styled=require("Modules.LootFilterLibrary").appearance({id="order",text=raw},{SetFontSize={"40"}})
		assert.is_truthy(styled.text:find('DisableDropSound\n EnableDropSound\n DisableDropSound\n SetTextColor 1 2 3',1,true))
		assert.is_truthy(styled.text:find('Continue unexpected',1,true));assert.is_truthy(styled.text:find('SetFontSize 40',1,true))
		local sounds='Show\n PlayAlertSound 1\n PlayAlertSoundPositional 2\n SetFontSize 42'
		editor.Conditions({id="sound",title="Sound",text=sounds},function(value) saved=value end)
		main.popups[1].controls.sound:SelByValue("Alert 6");main.popups[1].controls.keepRule:Click()
		assert.is_truthy(saved.text:find('PlayAlertSound 6 200',1,true));assert.is_nil(saved.text:find('PlayAlertSoundPositional',1,true));assert.is_truthy(saved.text:find('SetFontSize 42',1,true))
	end)
	it("preserves a separate exact marker and reports its preview as uncertain",function()
		for _,key in ipairs({"HasExplicitMod","HasEnchantment"}) do
			local raw='Hide\n '..key..' >=2 == "Polar" "Shocking"';local item={Identified=true,[key]={"of the Polar Bear","Shocking"}}
			local parsed=parser.parse(raw.."\nShow");local warned=false
			for _,diagnostic in ipairs(parsed.diagnostics) do if diagnostic.line==2 and diagnostic.warning and diagnostic.warning:find("separate exact-match operator",1,true) then warned=true end end;assert.is_true(warned)
			local result=parser.simulate(parsed,item)
			assert.equal("unknown",result.status);assert.matches("exact%-match operator",result.reasons[1])
			local profile=filters.profile("exact-warning","Exact warning");profile.template=raw.."\nShow"
			local compiled,report=filters.compile(profile);local reportWarning=false
			for _,diagnostic in ipairs(report.diagnostics) do assert.is_nil(diagnostic.error);if diagnostic.warning and diagnostic.warning:find("separate exact-match operator",1,true) then reportWarning=true end end
			assert.is_true(reportWarning);assert.is_truthy(compiled:find(key..' >=2 == "Polar" "Shocking"',1,true))
			local saved;require("Classes.LootFilterControl").Conditions({id="exact",title="Exact",text=raw},function(value) saved=value end)
			main.popups[1].controls.keepRule:Click();assert.is_truthy(saved.text:find(key..' >=2 == "Polar" "Shocking"',1,true))
			local styled=require("Modules.LootFilterLibrary").appearance({id="exact",text=raw},{SetFontSize={"40"}})
			assert.is_truthy(styled.text:find(key..' >=2 == "Polar" "Shocking"',1,true))
		end
		local literal=parser.parse('Hide\n HasExplicitMod >=2 "==" "Polar"\nShow');assert.equal(0,#literal.diagnostics)
		local ordinary=parser.simulate(literal,{Identified=true,HasExplicitMod={"==","Polar"}})
		assert.equal("Hide",ordinary.action)
	end)
	it("never treats incomplete or unsupported samples as a certain hide",function()
		for _,raw in ipairs({'Hide\n Fated True','Hide\n TwiceCorrupted True','Hide\n UnidentifiedItemTier >= 3','Hide\n FutureKeyword True'}) do
			assert.equal("unknown",parser.simulate(parser.parse(raw),{}).status)
		end
		assert.equal("Show",parser.simulate(parser.parse('Hide\n Fated True\n Class == "Viscera"\nShow'),{Class="Currency"}).action)
		assert.equal("unknown",parser.simulate(parser.parse('Import "other.filter"\nHide'),{}).status)
		assert.equal("invalid",parser.simulate(parser.parse('Hide\n BaseType "broken'),{}).status)
		assert.equal("invalid",parser.simulate(parser.parse('Hide\n ItemLevel'),{}).status)
		assert.equal("invalid",parser.simulate(parser.parse('Hide\n TransfiguredGem >= True'),{TransfiguredGem=true}).status)
	end)
	it("matches either influence normally and both influences with the exact operator",function()
		local either=parser.parse('Show\n HasInfluence Shaper Elder\nHide')
		local both=parser.parse('Show\n HasInfluence == Shaper Elder\nHide')
		for _,sample in ipairs({{HasInfluence={"Shaper"}},{HasInfluence={"Elder"}}}) do
			assert.equal("Show",parser.simulate(either,sample).action)
			assert.equal("Hide",parser.simulate(both,sample).action)
		end
		local dual={HasInfluence={"Elder","Shaper"}}
		assert.equal("Show",parser.simulate(either,dual).action)
		assert.equal("Show",parser.simulate(both,dual).action)
		assert.equal("Hide",parser.simulate(either,{HasInfluence={}}).action)
		assert.equal("Show",parser.simulate(parser.parse('Show\n HasInfluence None\nHide'),{HasInfluence={}}).action)
		assert.equal("unknown",parser.simulate(parser.parse('Show\n HasInfluence == Shaper\nHide'),dual).status)
		assert.equal("unknown",parser.simulate(either,{HasInfluence={"None","Shaper"}}).status)
		assert.equal("unknown",parser.simulate(either,{HasInfluence={"Unknown"}}).status)
		assert.equal("unknown",parser.simulate(either,{HasInfluence={[1]="Shaper",[3]="Elder"}}).status)
		local imported=filters.profile("dual-influence","Dual influence");imported.template='Hide\n HasInfluence == Shaper Elder\nShow'
		assert.equal("Show",filters.simulate(imported,{BaseType="Iron Hat",HasInfluence={"Shaper"}}).action)
		assert.equal("Hide",filters.simulate(imported,{BaseType="Iron Hat",HasInfluence={"Shaper","Elder"}}).action)
	end)
	it("derives Shaper and Elder flags from a known influence list and reports conflicts",function()
		local shaper=parser.parse('Hide\n ShaperItem True\nShow');local elder=parser.parse('Hide\n ElderItem True\nShow')
		local influence=parser.parse('Hide\n HasInfluence Shaper\nShow')
		assert.equal("Hide",parser.simulate(shaper,{HasInfluence={"Shaper"}}).action)
		assert.equal("Show",parser.simulate(elder,{HasInfluence={"Shaper"}}).action)
		assert.equal("Show",parser.simulate(shaper,{HasInfluence={"None"}}).action)
		assert.equal("unknown",parser.simulate(shaper,{}).status)
		local contradictory={HasInfluence={"Shaper"},ShaperItem=false}
		for _,rule in ipairs({shaper,elder,influence}) do local result=parser.simulate(rule,contradictory);assert.equal("unknown",result.status);assert.matches("conflicts",result.reasons[1]) end
		assert.equal("unknown",parser.simulate(shaper,{HasInfluence={"None","Shaper"}}).status)
		assert.equal("Hide",parser.simulate(shaper,{ShaperItem=true}).action)
	end)
	it("identifies missing properties only on a possibly matching rule",function()
		local rule=parser.parse('Hide\n BaseType "Iron Hat"\n BaseArmour >= 10\n Mirrored True\nShow')
		local missing=parser.simulate(rule,{BaseType="Iron Hat"});assert.equal("unknown",missing.status);assert.same({"BaseArmour","Mirrored"},missing.missingProperties)
		local other=parser.simulate(rule,{BaseType="Iron Ring"});assert.equal("Show",other.action);assert.is_nil(other.missingProperties)
		local imported=parser.simulate(parser.parse('Import "other.filter"\nShow'),{});assert.equal("unknown",imported.status);assert.is_nil(imported.missingProperties)
	end)
	it("expands supplied filter files in order and leaves missing or cyclic imports unresolved",function()
		local bom=string.char(239,187,191);local profile=filters.profile("included","Included");profile.template=bom..'Import "outer.filter"\nShow'
		profile.importFiles={{name="outer.filter",text=bom..'Import "inner.filter"\nShow\n BaseType "Iron"'},{name="inner.filter",text=bom..'Hide\n BaseType "Iron Hat"'}}
		local raw,report=filters.compile(profile);assert.equal(0,#report.imports);assert.is_truthy(raw:find("# Included filter: inner.filter",1,true))
		assert.is_falsy(raw:find(bom,1,true));for _,diagnostic in ipairs(report.diagnostics) do assert.is_nil(diagnostic.error) end
		assert.equal("Hide",filters.simulate(profile,{BaseType="Iron Hat"}).action)
		assert.equal("Show",filters.simulate(profile,{BaseType="Iron Ring"}).action)
		local checked=filters.validate({schemaVersion=1,activeId=profile.id,profiles={profile}});assert.same(profile.importFiles,checked.profiles[1].importFiles)
		assert.is_truthy(require("Modules.LootFilterStructure").outline(profile).entries[1])
		local store=filters.new(build);store.data=checked;local xml={};store:Save(xml);local restored=filters.new(build);restored:Load(xml);assert.same(profile.importFiles,restored.data.profiles[1].importFiles)
		profile.importFiles[2].text='Import "outer.filter"';local _,cyclic=filters.compile(profile);assert.equal(1,#cyclic.imports);assert.equal("unknown",filters.simulate(profile,{BaseType="Iron Hat"}).status)
		profile.importFiles={};local _,missing=filters.compile(profile);assert.equal(1,#missing.imports);assert.equal("unknown",filters.simulate(profile,{BaseType="Iron Hat"}).status)
		profile.template='Import "outer.filter"';assert.is_truthy(filters.validate({schemaVersion=1,activeId=profile.id,profiles={profile}}))
		profile.template='Hide\n BaseType "Orb of Binding"\nImport "missing.filter"\nShow';local _,migrated=filters.compile(profile);assert.equal(1,#migrated.imports)
	end)
	it("edits and validates included files without touching the original profile",function()
		local profile=filters.profile("included","Included");local saved
		require("Classes.LootFilterImportControl").Open(profile,function(files) saved=files end)
		local c=main.popups[1].controls;c.name:SetText("rules.filter");c.text:SetText('Hide\n BaseType "Iron Hat"');c.keep:Click()
		assert.is_nil(profile.importFiles);assert.equal("rules.filter",saved[1].name);assert.is_truthy(saved[1].text:find("Iron Hat",1,true))
	end)
	it("opens the main filter from an explicit path or the local browser",function()
		local path=os.tmpname()..".filter";local file=assert(io.open(path,"wb"));local raw='\239\187\191Hide\r\n BaseType "Iron Hat"\r\nShow';file:write(raw);file:close()
		local original=NewFileSearch;local name=path:match("([^/\\]+)$")
		_G.NewFileSearch=function(_,folders) if folders then return nil end;return {GetFileName=function() return name end,NextFile=function() return false end,Close=function() end} end
		local ok,err=pcall(function()
			local saved;require("Classes.LootFilterControl").Import(function(text) saved=text end);local c=main.popups[1].controls
			c.path:SetText(path);c.loadFile:Click();assert.equal(raw,c.text.buf);c.text:SetText("")
			c.browseFile:Click();local browser=main.popups[1].controls;browser.search:SetText(name,true);browser.choose:Click();assert.equal(raw,c.text.buf)
			c.path:SetText(path.."-missing");c.loadFile:Click();assert.equal("Loot filter",main.popups[1].title);main:ClosePopup();assert.equal(raw,c.text.buf)
			os.remove(path);c.import:Click();assert.equal(raw,saved)
		end)
		_G.NewFileSearch=original;os.remove(path);assert(ok,err)
	end)
	it("loads nested sibling filters explicitly and reports missing, unsafe and circular references",function()
		local first=os.tmpname()..".filter";local second=os.tmpname()..".filter";local mainPath=os.tmpname()..".filter"
		local a=first:match("([^/\\]+)$");local b=second:match("([^/\\]+)$");local missing=a.."-missing.filter"
		local f=assert(io.open(first,"wb"));f:write('Import "'..b..'"\nShow');f:close();f=assert(io.open(second,"wb"));f:write('Import "'..a..'"\nHide');f:close()
		local raw='Import "'..a..'"\nImport "'..missing..'" Optional\nImport "'..missing..'"\nImport "../outside.filter"\nImport "CON.filter"\nImport "NUL .filter"\nImport "'..string.rep("x",235)..'.filter"'
		local ok,err=pcall(function()
			local imports=require("Modules.LootFilterImports");local result=imports.collectLocal(raw,mainPath)
			assert.equal(2,#result.files);assert.equal(5,#result.issues);assert.is_false(result.issues[1].optional)
			assert.matches("sibling",result.issues[2].reason);assert.matches("sibling",result.issues[3].reason)
			local unresolved=imports.unresolved(raw,result.files);local cycle;for _,row in ipairs(unresolved) do if row.name==a then cycle=row.cycle end end;assert.is_true(cycle)
			local saved,linked;require("Classes.LootFilterControl").Import(function(text,files) saved=text;linked=files end,{{name=a,text="old copy"}});local c=main.popups[1].controls
			c.text:SetText(raw);c.path:SetText(mainPath);c.loadLinked:Click();assert.equal("Linked filter files",main.popups[1].title)
			local lines={};for _,row in ipairs(main.popups[1].controls.details.list) do lines[#lines+1]=row[1] end;assert.matches("replaces the existing",StripEscapes(table.concat(lines," ")));main:ClosePopup()
			c.text:SetText(raw.."\nShow");c.import:Click();assert.equal("Loot filter",main.popups[1].title);main:ClosePopup();assert.is_nil(saved)
			c.text:SetText(raw);c.import:Click();assert.equal(raw,saved);assert.same(result.files,linked)
		end)
		os.remove(first);os.remove(second);os.remove(mainPath);assert(ok,err)
	end)
	it("replaces matching attached copies and retains unrelated files",function()
		local imports=require("Modules.LootFilterImports");local original={{name="one.filter",text="old"},{name="other.filter",text="keep"}}
		local loaded={{name="one.filter",text="new"},{name="three.filter",text="added"}};local merged=imports.merge(original,loaded)
		assert.same({{name="one.filter",text="new"},{name="other.filter",text="keep"},{name="three.filter",text="added"}},merged)
		assert.equal("old",original[1].text);loaded[1].text="changed";assert.equal("new",merged[1].text)
	end)
	it("discovers nested missing imports and circular references without reading disk",function()
		local imports=require("Modules.LootFilterImports")
		local raw='Import "outer.filter"\nImport "z.filter" Optional\nImport "z.filter"\nShow'
		local files={{name="outer.filter",text='Import "inner.filter" Optional\nImport "outer.filter"'}}
		local rows=imports.unresolved(raw,files)
		assert.same({{name="inner.filter",optional=true,cycle=false,count=1},{name="outer.filter",optional=false,cycle=true,count=1},{name="z.filter",optional=false,cycle=false,count=2}},rows)
		local profile=filters.profile("imports-report","Import report");profile.template=raw;profile.importFiles=files
		local _,report=filters.compile(profile);assert.same(rows,report.unresolvedImports)
		assert.same({},imports.unresolved('Import "empty.filter" Optional\nShow',{{name="empty.filter",text=""}}))
	end)
	it("helps attach nested references without silently creating empty files",function()
		local profile=filters.profile("included-help","Included help");profile.template='Import "outer.filter"\nShow'
		profile.importFiles={{name="outer.filter",text='Import "inner.filter"\nHide'}};local saved
		require("Classes.LootFilterImportControl").Open(profile,function(files) saved=files end);local editor=main.popups[1].controls
		editor.findImports:Click();local browser=main.popups[1].controls
		assert.equal("inner.filter",browser.results.list[1].entry.id);browser.choose:Click()
		assert.equal("inner.filter",editor.name.buf);editor.keep:Click()
		assert.equal(1,#saved);assert.equal("outer.filter",saved[1].name)
		require("Classes.LootFilterImportControl").Open(profile,function(files) saved=files end);editor=main.popups[1].controls
		editor.findImports:Click();main.popups[1].controls.choose:Click();editor.text:SetText('Show\n BaseType "Iron Hat"');editor.keep:Click()
		assert.equal(2,#saved);assert.equal("inner.filter",saved[2].name)
		profile.importFiles=saved;assert.equal("matched",filters.simulate(profile,{BaseType="Iron Hat"}).status)
	end)
	it("loads an explicitly selected local import and keeps a portable copy",function()
		local path=os.tmpname();local file=assert(io.open(path,"wb"));file:write('Show\n BaseType "Iron Hat"');file:close()
		local profile=filters.profile("local-import","Local import");profile.template='Import "nested.filter"\nHide';local saved
		require("Classes.LootFilterImportControl").Open(profile,function(files) saved=files end);local c=main.popups[1].controls
		c.name:SetText("nested.filter");c.path:SetText(path);c.loadFile:Click();os.remove(path);c.keep:Click()
		assert.equal("nested.filter",saved[1].name);profile.importFiles=saved
		assert.equal("Show",filters.simulate(profile,{BaseType="Iron Hat"}).action)
		local read=require("Modules.LootFilterImports").readFile
		assert.has_error(function() read(path,10) end)
		path=os.tmpname();file=assert(io.open(path,"wb"));file:write("12345");file:close()
		assert.has_error(function() read(path,4) end);os.remove(path)
	end)
	it("browses to a local filter and loads the selected file",function()
		local path=os.tmpname()..".filter";local file=assert(io.open(path,"wb"));file:write('Show\n BaseType "Iron Hat"');file:close()
		local original=NewFileSearch;local name=path:match("([^/\\]+)$");local closed=0
		_G.NewFileSearch=function(_,folders)
			if folders then return nil end
			return {GetFileName=function() return name end,NextFile=function() return false end,Close=function() closed=closed+1 end}
		end
		local ok,err=pcall(function()
			local profile=filters.profile("browse-local","Browse local");local saved
			require("Classes.LootFilterImportControl").Open(profile,function(files) saved=files end);local c=main.popups[1].controls
			c.path:SetText(path);c.browseFile:Click();local browser=main.popups[1].controls
			browser.search:SetText(name,true);browser.choose:Click();assert.equal(path,c.path.buf);assert.is_truthy(c.text.buf:find("Iron Hat",1,true))
			c.keep:Click();assert.equal(name,saved[1].name);assert.equal(1,closed)
		end)
		_G.NewFileSearch=original;os.remove(path);assert(ok,err)
	end)
	it("lists folders and filter files with a parent navigation entry",function()
		local original=NewFileSearch;local closed=0
		_G.NewFileSearch=function(_,folders)
			local names=folders and {"child"} or {"rules.filter","other.txt","EXTRA.FILTER","ruthless.RUTHLESSFILTER"};local index=1
			return {GetFileName=function() return names[index] end,NextFile=function() index=index+1;return names[index]~=nil end,Close=function() closed=closed+1 end}
		end
		local ok,err=pcall(function()
			local rows=require("Classes.LootFilterFileBrowser").entries("C:/Users/test/")
			assert.equal(5,#rows);assert.equal("C:/Users/",rows[1].id);assert.equal("C:/Users/test/child/",rows[2].id)
			assert.equal("C:/Users/test/EXTRA.FILTER",rows[3].id);assert.equal("C:/Users/test/rules.filter",rows[4].id);assert.equal("C:/Users/test/ruthless.RUTHLESSFILTER",rows[5].id);assert.equal(2,closed)
		end)
		_G.NewFileSearch=original;assert(ok,err)
	end)
	it("retains attachment edits across selection and rejected saves",function()
		local profile=filters.profile("included","Included");profile.importFiles={{name="one.filter",text="Show"},{name="two.filter",text="Hide"}};local saved
		require("Classes.LootFilterImportControl").Open(profile,function(files) saved=files end);local c=main.popups[1].controls
		c.files.selFunc(2,c.files.list[2]);c.text:SetText('Hide\n BaseType "Iron Hat"');c.files.selFunc(3,c.files.list[3]);c.files.selFunc(2,c.files.list[2])
		assert.is_truthy(c.text.buf:find("Iron Hat",1,true));c.name:SetText("");c.keep:Click();assert.is_truthy(main.popups[1].controls);assert.equal("",c.name.buf);assert.is_nil(saved)
		main:ClosePopup();c.name:SetText("one.filter");c.keep:Click();assert.is_truthy(saved[1].text:find("Iron Hat",1,true));assert.equal("Hide",saved[2].text)
	end)
	it("evaluates the twice-corrupted filter condition",function()
		local parsed=parser.parse("Hide\n TwiceCorrupted True\nShow")
		assert.equal("Hide",parser.simulate(parsed,{TwiceCorrupted=true}).action)
		assert.equal("Show",parser.simulate(parsed,{TwiceCorrupted=false}).action)
		assert.equal("unknown",parser.simulate(parsed,{}).status)
		assert.equal("invalid",parser.simulate(parser.parse("Hide\n TwiceCorrupted Maybe"),{TwiceCorrupted=true}).status)
	end)
	it("does not use hidden explicit modifier names on unidentified samples",function()
		local parsed=parser.parse('Hide\n HasExplicitMod >=2 "of Haast" "of Ephij"\nShow')
		local names={"of Haast","of Ephij"}
		assert.equal("Hide",parser.simulate(parsed,{Identified=true,HasExplicitMod=names}).action)
		local hidden=parser.simulate(parsed,{Identified=false,HasExplicitMod=names})
		assert.equal("unknown",hidden.status);assert.is_truthy(hidden.reasons[1]:find("hidden",1,true))
		assert.equal("unknown",parser.simulate(parsed,{HasExplicitMod=names}).status)
		assert.equal("unknown",parser.simulate(parsed,{Identified=true}).status)
	end)
	it("supports 3.30 tier/fated, numeric alternatives, booleans, sockets and influences",function()
		local parsed=parser.parse('Show\n UnidentifiedItemTier >= 3\n Fated True\n SocketGroup RGB\n HasInfluence Shaper\nHide')
		assert.equal("Show",parser.simulate(parsed,{UnidentifiedItemTier=4,Fated=true,SocketGroup="RGB BB",HasInfluence={"Shaper"}}).action)
		assert.equal("Hide",parser.simulate(parsed,{UnidentifiedItemTier=2,Fated=true,SocketGroup="RGB BB",HasInfluence={"Shaper"}}).action)
		for _,keyword in ipairs({"Imbued","Vestigial","ZanaMemory","MirageMap"}) do assert.equal("Show",parser.simulate(parser.parse("Show\n "..keyword.." True\nHide"),{[keyword]=true}).action) end
		assert.equal("Show",parser.simulate(parser.parse('Show\n TransfiguredGem "Leap Slam"\nHide'),{TransfiguredGem="Leap Slam"}).action)
		assert.equal("Show",parser.simulate(parser.parse('Show\n TransfiguredGem True\nHide'),{TransfiguredGem="Leap Slam"}).action)
		local anyGem=parser.parse('Show\n TransfiguredGem False\nHide')
		for _,value in ipairs({0,{},"", "  "}) do
			local preview=parser.simulate(anyGem,{TransfiguredGem=value})
			assert.equal("unknown",preview.status)
			assert.equal("Unknown",preview.action)
		end
		assert.equal("Show",parser.simulate(anyGem,{TransfiguredGem=false}).action)
		assert.equal("Hide",parser.simulate(anyGem,{TransfiguredGem=true}).action)
		assert.equal("Hide",parser.simulate(anyGem,{TransfiguredGem="Leap Slam"}).action)
	end)
	it("requests validated account writes without exposing tokens and distinguishes pending from success",function()
		local account=require("Modules.LootFilterAccount");local original=launch.DownloadPage;local called=false
		local api={authToken="test-only",ValidateAuth=function(_,callback) callback(true) end}
		local payload={filter_name="Test",realm="pc",filter="Show",public=false}
		local ok,message=pcall(function()
			launch.DownloadPage=function(_,url,callback,options)
				called=true;assert.equal("https://api.pathofexile.com/item-filter?validate=true",url)
				assert.is_truthy(options.header:find("Content-Type: application/json",1,true));assert.is_false(require("dkjson").decode(options.body).public)
				callback({header="HTTP/1.1 202 Accepted",body='{"filter":{"id":"test"}}'},"Response code: 202")
			end
			account.nextRequest=0;account.request(api,"POST",nil,payload,function(_,err) assert.is_truthy(err:find("processing",1,true)) end)
			assert.is_true(called);assert.is_false(account.busy)
			launch.DownloadPage=function(_,_,callback) callback({header="HTTP/1.1 200 Connection established\r\n\r\nHTTP/2 201 Created",body='{"filter":{"id":"test","validation":{"valid":true}}}'},"Response code: 201") end
			account.nextRequest=0;account.request(api,"POST",nil,payload,function(value,err) assert.is_nil(err);assert.equal("test",value.filter.id) end)
			launch.DownloadPage=function(_,_,callback) callback({header="HTTP/1.1 403 Forbidden",body="{}"}) end
			account.nextRequest=0;account.request(api,"GET",nil,nil,function(_,err) assert.is_truthy(err:find("account:item_filter",1,true)) end)
			assert.has_error(function() account.request(api,"POST","../other",payload,function() end) end)
		end)
		launch.DownloadPage=original;account.busy=false;account.nextRequest=0;assert.is_true(ok,message)
	end)
	it("migrates renamed items and drops empty removed-item blocks without widening Hide",function()
		local raw='Hide\n BaseType == "Orb of Binding"\nShow\n BaseType == "Maven\'s Chisel of Scarabs"\nShow\n BaseType == "Chaos Orb" "Orb of Binding"'
		local migrated,changes=filters.migrate(raw)
		assert.is_nil(migrated:find("Orb of Binding",1,true));assert.is_truthy(migrated:find("Maven's Chisel of Threads",1,true))
		assert.equal(2,#parser.parse(migrated).rules);assert.equal("removed",changes["Orb of Binding"])
		assert.equal("Show",parser.simulate(parser.parse(migrated),{BaseType="Iron Hat"}).action)
		local mixed='Hide\n BaseType "Orb of Binding" Chaos # "Orb of Binding" is a comment\nShow'
		local result=filters.migrate(mixed)
		assert.is_truthy(result:find('Chaos # "Orb of Binding" is a comment',1,true))
		assert.equal("Hide",parser.simulate(parser.parse(result),{BaseType="Chaos Orb"}).action)
		local commentOnly='Show\n BaseType Chaos # "Orb of Binding"\nHide'
		local preserved,notes=filters.migrate(commentOnly);assert.equal(commentOnly,preserved);assert.is_nil(next(notes))
	end)
	it("compiles all seven 3.30-native bases with provenance",function()
		for strictness=0,6 do
			local profile=filters.profile("test","Test");profile.strictness=strictness
			local raw,report=filters.compile(profile)
			assert.is_true(#raw>10000);assert.equal(filters.source().commit,report.baseCommit)
			assert.is_truthy(raw:find("# Copyright (c) 2026 NeverSink",1,true));assert.is_truthy(raw:find("# Permission is hereby granted",1,true))
			assert.is_truthy(raw:find('"Frayed Thread"',1,true))
			for _,diagnostic in ipairs(report.diagnostics) do assert.is_nil(diagnostic.error,diagnostic.error) end
		end
	end)
	it("preserves imported text, personal rules and unknown future metadata",function()
		local profile=filters.profile("test","Test");profile.template='Show\n BaseType == "Iron Hat" # original'
		profile.rules={filters.rule("mine","My rule",{'BaseType == "Chaos Orb"'})}
		local updated=filters.update(profile);assert.equal(profile.template,updated.template);assert.same(profile.rules,updated.rules)
		local saver=build.savers.LootFilters;saver:Upsert(profile)
		local xml={};saver:Save(xml);local restored=filters.new(build);restored:Load(xml);assert.same(saver.data,restored.data)
		restored:Load({'{"schemaVersion":99,"profiles":[]}'});local preserved={};restored:Save(preserved);assert.equal('{"schemaVersion":99,"profiles":[]}',preserved[1])
		assert.has_error(function() restored:Upsert(profile) end)
	end)
	it("requires an explicit base update and produces Ruthless Minimal blocks",function()
		local p=filters.profile("test","Test");p.baseCommit=string.rep("0",40)
		assert.has_error(function() filters.compile(p) end)
		p=filters.update(p);p.mode="Ruthless";local raw=filters.compile(p)
		for _,rule in ipairs(parser.parse(raw).rules) do assert.is_not.equal("Hide",rule.action) end
		assert.is_truthy(raw:find("Minimal",1,true))
		p.mode="Normal";p.template="Minimal\n BaseType Iron";assert.equal("invalid",filters.simulate(p,{BaseType="Iron"}).status)
	end)
	it("generates from saved craft and gear goals while preserving personal rules",function()
		local craft={id="hat",title="Craft helmet",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={}}
		build.savers.CraftingProjects:Upsert(craft)
		local journey=require("Modules.BuildJourney").empty();journey.wishlist={{id="ring",title="Ring",slot="Ring 1",route="farm",targetItem="Rarity: NORMAL\nIron Ring\nItem Level: 80"}};build.savers.BuildJourney:Replace(journey)
		local profile=filters.profile("test","Test");profile.rules={filters.rule("mine","My rule",{'BaseType == "Chaos Orb"'})}
		profile.rules=filters.generate(build,profile);assert.equal(3,#profile.rules);assert.equal("mine",profile.rules[1].id)
		assert.equal("Show",filters.simulate(profile,{BaseType="Iron Hat",Rarity="Rare",ItemLevel=86}).action)
		local count=#profile.rules;profile.rules=filters.generate(build,profile);assert.equal(count,#profile.rules)
	end)
	it("includes a distinct non-unique crafting target base without duplicating covered bases",function()
		local start="Rarity: NORMAL\nZodiac Leather\nItem Level: 70"
		local target="Rarity: RARE\nGoal Armour\nPlate Vest\nItem Level: 86"
		local project={id="armour-goal",title="Armour goal",slot="Body Armour",startingItem=start,targetItem=target,goals={},steps={}}
		build.savers.CraftingProjects:Upsert(project)
		local profile=filters.profile("test","Test");profile.template="Hide";profile.rules=filters.generate(build,profile)
		local function preview(base,level) return filters.simulate(profile,{BaseType=base,Rarity="Rare",ItemLevel=level}).action end
		assert.equal("Show",preview("Zodiac Leather",70));assert.equal("Show",preview("Plate Vest",86));assert.equal("Hide",preview("Plate Vest",70))
		project.targetItem="Rarity: RARE\nGoal Armour\nZodiac Leather\nItem Level: 86";build.savers.CraftingProjects:Upsert(project)
		local count=0;for _,rule in ipairs(filters.generate(build,profile)) do if rule.origin=="craft:armour-goal" then count=count+1 end end;assert.equal(1,count)
		project.targetItem="Rarity: RARE\nGoal Armour\nZodiac Leather\nItem Level: 60";build.savers.CraftingProjects:Upsert(project)
		profile.rules=filters.generate(build,profile);assert.equal("Show",preview("Zodiac Leather",60))
		project.targetItem="Rarity: RARE\nGoal Armour\nZodiac Leather";build.savers.CraftingProjects:Upsert(project)
		profile.rules=filters.generate(build,profile);assert.equal("Show",preview("Zodiac Leather",1))
	end)
	it("highlights a saved recipe's recombined starting base",function()
		local sim=require("Modules.CraftingSimulator")
		local start="Rarity: NORMAL\nZodiac Leather\nItem Level: 70";local derived="Rarity: NORMAL\nPlate Vest\nItem Level: 86"
		local model=sim.model(start);local initial=sim.validateState(model,{rarity="RARE",affixes={},baseItem=derived})
		local recipe={steps={{method="chaos"}},targets={},requirements={minAffixes=0},initialState=initial}
		build.savers.CraftingProjects:Upsert({id="recombined",title="Recombined armour",slot="Body Armour",startingItem=start,nativeRecipe=recipe,goals={},steps={}})
		local profile=filters.profile("test","Test");profile.template="Hide";profile.rules=filters.generate(build,profile)
		local function preview(base,level) return filters.simulate(profile,{BaseType=base,Rarity="Rare",ItemLevel=level}).action end
		assert.equal("Show",preview("Zodiac Leather",70));assert.equal("Show",preview("Plate Vest",86));assert.equal("Hide",preview("Plate Vest",70))
		local found=false;for _,rule in ipairs(profile.rules) do if rule.id=="craft-working-recombined" then found=true end end;assert.is_true(found)
		local thread=coroutine.create(function() return filters.generate(build,profile,function() coroutine.yield() end) end)
		local ok,result;repeat ok,result=coroutine.resume(thread);assert.is_true(ok,result) until coroutine.status(thread)=="dead"
		assert.same(profile.rules,result)
		local original=copyTable(build.savers.CraftingProjects.projects[1]);local revised=copyTable(original)
		revised.targetItem="Rarity: RARE\nGoal Armour\nPlate Vest\nItem Level: 90";build.savers.CraftingProjects:Upsert(revised)
		local higher=filters.generate(build,profile);for _,rule in ipairs(higher) do assert.is_not.equal("craft-target-recombined",rule.id) end
		revised.targetItem="Rarity: RARE\nGoal Armour\nPlate Vest\nItem Level: 80";build.savers.CraftingProjects:Upsert(revised)
		local lower=filters.generate(build,profile);local lowerFound=false;for _,rule in ipairs(lower) do if rule.id=="craft-target-recombined" then lowerFound=true end end;assert.is_true(lowerFound)
		revised.targetItem=nil;revised.nativeRecipe.initialState.baseItem=start;build.savers.CraftingProjects:Upsert(revised)
		assert.is_true(require("Modules.LootFilterDependencies").report(build,profile).stale)
		build.savers.CraftingProjects:Upsert(original)
		build.savers.CraftingProjects.projects[1].nativeRecipe.initialState.baseItem="Not an item"
		local updated,warnings=filters.generate(build,profile);local kept=false
		for _,rule in ipairs(updated) do if rule.id=="craft-working-recombined" then kept=true end end
		assert.is_true(kept);assert.is_true(#warnings>0)
	end)
	it("generates a unique target pickup alongside a non-unique crafting base",function()
		local start="Rarity: NORMAL\nEzomyte Tower Shield\nItem Level: 86"
		local target="Rarity: UNIQUE\nThe Surrender\nEzomyte Tower Shield\nItem Level: 86\n+100 to maximum Life"
		local project={id="unique-goal",title="Shield goal",slot="Weapon 2",startingItem=start,goals={},steps={}}
		build.savers.CraftingProjects:Upsert(project)
		local profile=filters.profile("test","Test");profile.template="Hide";profile.rules=filters.generate(build,profile)
		project.targetItem=target;build.savers.CraftingProjects:Upsert(project)
		assert.is_true(require("Modules.LootFilterDependencies").report(build,profile).stale)
		profile.rules=filters.generate(build,profile);assert.is_false(require("Modules.LootFilterDependencies").report(build,profile).stale)
		local function preview(rarity,level) return filters.simulate(profile,{BaseType="Ezomyte Tower Shield",Rarity=rarity,ItemLevel=level}).action end
		assert.equal("Show",preview("Unique",70));assert.equal("Show",preview("Rare",86));assert.equal("Hide",preview("Rare",70))
		local targetRule;for _,rule in ipairs(profile.rules) do if rule.id=="craft-target-unique-goal" then targetRule=rule end end
		assert.is_truthy(targetRule);assert.is_nil(targetRule.text:find("ItemLevel",1,true))
		local scene=filters.simulateScene(profile,"Build targets",0,70,70,0,50,nil,build);local uniqueSample
		for _,entry in ipairs(scene.results) do if entry.sample.BaseType=="Ezomyte Tower Shield" and entry.sample.Rarity=="Unique" then uniqueSample=entry end end
		assert.is_truthy(uniqueSample);assert.equal("Show",uniqueSample.result.action);assert.equal(70,uniqueSample.sample.ItemLevel)
		build.savers.CraftingProjects.projects[1].targetItem="Not an item"
		local updated,warnings=filters.generate(build,profile);local retained=false
		for _,rule in ipairs(updated) do if rule.id=="craft-target-unique-goal" then retained=true end end
		assert.is_true(retained);assert.is_truthy(warnings[1].message:find("crafting target",1,true))
	end)
	it("generates unique pickups for unique crafting starting items",function()
		local raw="Rarity: UNIQUE\nThe Surrender\nEzomyte Tower Shield\nItem Level: 86\n+100 to maximum Life"
		build.savers.CraftingProjects:Upsert({id="unique-project",title="Improve shield",slot="Weapon 2",startingItem=raw,goals={},steps={}})
		local profile=filters.profile("test","Test");profile.template="Hide";profile.rules=filters.generate(build,profile)
		local function preview(rarity,level) return filters.simulate(profile,{BaseType="Ezomyte Tower Shield",Rarity=rarity,ItemLevel=level}).action end
		assert.equal("Show",preview("Unique",70));assert.equal("Hide",preview("Rare",86))
		local generated;for _,rule in ipairs(profile.rules) do if rule.origin=="craft:unique-project" then generated=rule end end
		assert.is_truthy(generated);assert.is_truthy(generated.text:find("Rarity == Unique",1,true));assert.is_nil(generated.text:find("ItemLevel",1,true))
		local project=copyTable(build.savers.CraftingProjects.projects[1]);project.targetItem=raw;build.savers.CraftingProjects:Upsert(project)
		local count=0;for _,rule in ipairs(filters.generate(build,profile)) do if rule.origin=="craft:unique-project" then count=count+1 end end
		assert.equal(1,count)
	end)
	it("generates Betrayal Thread pickups for either Secrets Unveiled choice",function()
		local atlas=require("Modules.AtlasPlanner");local node=atlas.tree("3.30.0-preview").nodes[45404]
		local profile=filters.profile("test","Test")
		for _,effect in ipairs(node.variantEffects) do
			build.savers.AtlasPlans.plans={{id="choice",version="3.30.0-preview",nodes={node.id},choices={{node=node.id,effect=effect.effect}}}}
			local found=false;for _,rule in ipairs(filters.generate(build,profile)) do if rule.title=="Betrayal Thread" then found=true end end
			assert.is_true(found)
		end
	end)
	it("does not infer a Thread pickup from an encounter blocker",function()
		local profile=filters.profile("test","Test")
		local plan={id="blocked",version="3.29.3",nodes={39896}}
		build.savers.AtlasPlans.plans={plan}
		local function hasBreach() for _,rule in ipairs(filters.generate(build,profile)) do if rule.title=="Breach Thread" then return true end end return false end
		assert.is_false(hasBreach())
		plan.nodes={53006};assert.is_true(hasBreach())
		plan.nodes={39896};plan.strategy={scarabs="Breach Thread"};assert.is_true(hasBreach())
		plan.strategy.avoid="Breach Thread";assert.is_false(hasBreach())
	end)
	it("generates named current Atlas supplies and respects explicit exclusions",function()
		local profile=filters.profile("test","Test")
		build.savers.AtlasPlans.plans={{id="supplies",version="3.30.0-preview",nodes={},strategy={scarabs="Allflame Ember of Kulemak, Divine Vessels, Feral Astrolabe, Maven's Chisel of Divination, Threaded Delirium Orb, Fruiting Astrolabe, Memory of Trauma, Memory of Reverence",avoid="Feral Astrolabe, Memory of Reverence"}}}
		local titles={};for _,rule in ipairs(filters.generate(build,profile)) do titles[rule.title]=true end
		for _,name in ipairs({"Allflame Ember of Kulemak","Divine Vessel","Maven's Chisel of Divination","Threaded Delirium Orb","Memory of Trauma"}) do assert.is_true(titles[name],name) end
		assert.is_nil(titles["Feral Astrolabe"]);assert.is_nil(titles["Fruiting Astrolabe"]);assert.is_nil(titles["Memory of Reverence"])
	end)
	it("links saved map-plan supplies to Atlas pickups and respects avoid rules",function()
		local profile=filters.profile("test","Test")
		local target={currentPercent=35,currentType="Currency Items",nextType="Currency Items",gain=10,targetPercent=80}
		local draft={id="map",title="Map target",plannedDelirium=target,plannedAllflame="Metadata/Items/MapFragments/MeatSackAllflamePack",plannedDeified=true}
		local plan={id="planned",title="Mapping",version="3.30.0-preview",nodes={},mapDrafts={draft,copyTable(draft)},strategy={scarabs="Fine Delirium Orb"}}
		build.savers.AtlasPlans.plans={plan}
		local function generated() local found={};local rules,warnings=filters.generate(build,profile);for _,rule in ipairs(rules) do if rule.origin=="atlas:planned" then found[rule.title]=(found[rule.title] or 0)+1 end end;return found,warnings end
		local found=generated();assert.equal(1,found["Fine Delirium Orb"]);assert.equal(1,found["Allflame Ember of Flesh"]);assert.equal(1,found["Divine Vessel"])
		profile.template="Hide";profile.rules=filters.generate(build,profile);assert.equal("Show",filters.simulate(profile,{BaseType="Fine Delirium Orb"}).action);assert.equal("Hide",filters.simulate(profile,{BaseType="Cartographer's Delirium Orb"}).action)
		plan.strategy={avoid="Fine Delirium Orb, Allflame Ember of Flesh"};found=generated();assert.is_nil(found["Fine Delirium Orb"]);assert.is_nil(found["Allflame Ember of Flesh"]);assert.equal(1,found["Divine Vessel"])
		plan.strategy={};draft.plannedDelirium.currentPercent=80;plan.mapDrafts={draft};found=generated();assert.is_nil(found["Fine Delirium Orb"])
		draft.plannedDelirium.currentType="Map Items";found=generated();assert.equal(1,found["Fine Delirium Orb"])
		draft.plannedDelirium="invalid";local _,warnings=generated();assert.is_true(#warnings>0);assert.matches("could not be identified",warnings[#warnings].message)
	end)
	it("distinguishes a generic Delirium Orb from named variants in Atlas strategies",function()
		local profile=filters.profile("test","Test")
		local strategy={scarabs="Threaded Delirium Orb",avoid=""}
		build.savers.AtlasPlans.plans={{id="orbs",version="3.30.0-preview",nodes={},strategy=strategy}}
		local function titles() local result={};for _,rule in ipairs(filters.generate(build,profile)) do result[rule.title]=true end;return result end
		local found=titles();assert.is_true(found["Threaded Delirium Orb"]);assert.is_nil(found["Delirium Orb"])
		strategy.scarabs="Delirium Orbs, Threaded Delirium Orb";strategy.avoid="Threaded Delirium Orb"
		found=titles();assert.is_true(found["Delirium Orb"]);assert.is_nil(found["Threaded Delirium Orb"])
	end)
	it("migrates renamed supplies in saved Atlas strategies and exclusions",function()
		local profile=filters.profile("test","Test")
		local strategy={scarabs="Skittering Delirium Orb, Maven's Chisel of Scarabs",avoid="Maven's Chisel of Threads"}
		build.savers.AtlasPlans.plans={{id="renames",version="3.30.0-preview",nodes={},strategy=strategy}}
		local function titles() local result={};for _,rule in ipairs(filters.generate(build,profile)) do result[rule.title]=true end;return result end
		local found=titles();assert.is_true(found["Threaded Delirium Orb"]);assert.is_nil(found["Skittering Delirium Orb"]);assert.is_nil(found["Maven's Chisel of Threads"])
		strategy.scarabs="Threaded Delirium Orb, Maven's Chisel of Threads";strategy.avoid="Skittering Delirium Orb"
		found=titles();assert.is_nil(found["Threaded Delirium Orb"]);assert.is_true(found["Maven's Chisel of Threads"])
	end)
	it("uses explicit map tiers instead of treating Atlas layouts as dropped item bases",function()
		local profile=filters.profile("test","Test")
		local strategy={maps="Beach Map, Map (Tier 16), Abomination Map",avoid=""}
		local plan={id="mapping",title="Mapping",version="3.30.0-preview",nodes={},strategy=strategy,shapedRegions={{mechanic="Blight",maps={{name="Strand Map",freeThreads=3}}}}}
		build.savers.AtlasPlans.plans={plan}
		local rules,warnings=filters.generate(build,profile);local titles={};for _,rule in ipairs(rules) do titles[rule.title]=rule end
		assert.is_nil(titles["Beach Map"]);assert.is_nil(titles["Strand Map"])
		assert.is_truthy(titles["Map (Tier 16)"]);assert.is_truthy(titles["Nightmare Map"])
		assert.matches('BaseType == "Map %(Tier 16%)"',titles["Map (Tier 16)"].text)
		assert.equal(2,#warnings);local messages=warnings[1].message..warnings[2].message;assert.matches("do not identify ordinary map drops",messages,1,true);assert.matches("share the Nightmare Map item",messages,1,true)
		profile.rules=rules;local sample=filters.simulate(profile,{BaseType="Map (Tier 16)",Class="Maps",Rarity="Normal",MapTier=16})
		assert.equal("Show",sample.action);assert.equal("Map (Tier 16) [atlas:mapping]",sample.ruleTitle)
		local again=filters.generate(build,profile);assert.same(rules,again)
		strategy.avoid="Map (Tier 16)";local excluded=filters.generate(build,profile);for _,rule in ipairs(excluded) do assert.is_not.equal("Map (Tier 16)",rule.title) end
		plan.strategy={maps="Map (Tier 5)"};plan.shapedRegions=nil
		local explicit,notes=filters.generate(build,profile);assert.equal(0,#notes)
		local found=false;for _,rule in ipairs(explicit) do if rule.title=="Map (Tier 5)" then found=true end end;assert.is_true(found)
	end)
	it("does not treat budgeted Atlas layouts as current map item bases",function()
		local journey=require("Modules.BuildJourney").empty();journey.resources={{id="layout",title="Beach Maps"},{id="tier",title="Map (Tier 16)"}}
		build.savers.BuildJourney:Replace(journey);local profile=filters.profile("test","Test")
		local rules,warnings=filters.generate(build,profile);local found={};for _,rule in ipairs(rules) do found[rule.title]=rule end
		assert.is_nil(found["Beach Map"]);assert.is_truthy(found["Map (Tier 16)"]);assert.equal("budget:tier",found["Map (Tier 16)"].origin)
		assert.equal(1,#warnings);assert.equal("budget:layout",warnings[1].origin)
	end)
	it("explains Atlas strategy fields with no recognized pickup names",function()
		local profile=filters.profile("test","Test")
		local strategy={scarabs="Use the expensive ones",maps="Strand Map",avoid="dangerous things"}
		build.savers.AtlasPlans.plans={{id="notes",title="Mapping notes",version="3.30.0-preview",nodes={},strategy=strategy}}
		local _,warnings=filters.generate(build,profile);assert.equal(2,#warnings);assert.equal("atlas:notes",warnings[1].origin)
		assert.matches("supplies, avoid",warnings[1].message,1,true)
		strategy.scarabs="Skittering Delirium Orb";strategy.avoid="Threaded Delirium Orb"
		_,warnings=filters.generate(build,profile);assert.equal(1,#warnings);assert.matches("do not identify ordinary map drops",warnings[1].message,1,true)
	end)
	it("generates gem rules only for enabled groups in the active weapon set",function()
		local original=build.skillsTab.socketGroupList
		build.skillsTab.socketGroupList={
			{enabled=true,slot="Weapon 1",gemList={{nameSpec="Fireball",enabled=true,grantedEffect={color="R"}},{nameSpec="Added Fire Damage",enabled=true,grantedEffect={color="R"},gemData={tags={support=true}}}}},
			{enabled=false,gemList={{nameSpec="Ice Nova",enabled=true}}},
			{enabled=true,slot="Weapon 1 Swap",gemList={{nameSpec="Arc",enabled=true}}},
			{enabled=true,gemList={{nameSpec="Spark",enabled=false}}},
		}
		local profile=filters.profile("active-gems","Active gems","campaign")
		local rules=filters.generate(build,profile);local titles,link,support={};for _,rule in ipairs(rules) do titles[rule.title]=true;if rule.title=="Links for skill group 1" then link=rule elseif rule.title=="Added Fire Damage" then support=rule end end
		assert.is_true(titles.Fireball);assert.is_true(titles["Links for skill group 1"])
		assert.is_truthy(support.text:find('BaseType == "Added Fire Damage Support"',1,true))
		assert.equal("Show",parser.simulate(parser.parse(support.text.."\nHide"),{Class="Support Gems",BaseType="Added Fire Damage Support"}).action)
		assert.equal("Hide",parser.simulate(parser.parse(support.text.."\nHide"),{Class="Support Gems",BaseType="Added Fire Damage"}).action)
		assert.is_truthy(link.text:find("LinkedSockets >= 2",1,true));assert.is_nil(link.text:find("SocketGroup",1,true))
		local generated=parser.parse(link.text.."\nHide")
		assert.equal("Show",parser.simulate(generated,{Rarity="Normal",LinkedSockets=2,SocketGroup="WW"}).action)
		assert.equal("Show",parser.simulate(generated,{Rarity="Rare",LinkedSockets=3,SocketGroup="RGB"}).action)
		assert.equal("Hide",parser.simulate(generated,{Rarity="Normal",LinkedSockets=1,SocketGroup="W W"}).action)
		assert.equal("Hide",parser.simulate(generated,{Rarity="Unique",LinkedSockets=2,SocketGroup="WW"}).action)
		build.skillsTab.socketGroupList[1].gemList[#build.skillsTab.socketGroupList[1].gemList+1]={nameSpec="Barrage Support",enabled=true,grantedEffect={color="G"},gemData={tags={support=true}}}
		local barrage;for _,rule in ipairs(filters.generate(build,profile)) do if rule.title=="Barrage Support" then barrage=rule end end
		assert.is_truthy(barrage.text:find('BaseType == "Barrage Support"',1,true));assert.is_nil(barrage.text:find("Support Support",1,true))
		assert.is_nil(titles["Ice Nova"]);assert.is_nil(titles.Arc);assert.is_nil(titles.Spark)
		build.itemsTab.activeItemSet.useSecondWeaponSet=true
		rules=filters.generate(build,profile);titles={};for _,rule in ipairs(rules) do titles[rule.title]=true end
		assert.is_true(titles.Arc);assert.is_nil(titles.Fireball);assert.is_nil(titles["Links for skill group 1"])
		build.itemsTab.activeItemSet.useSecondWeaponSet=false;build.skillsTab.socketGroupList=original
	end)
	it("refreshes generated pickups when a gem resolves as a support",function()
		local dependencies=require("Modules.LootFilterDependencies");local original=build.skillsTab.socketGroupList
		local ok,err=pcall(function()
			build.skillsTab.socketGroupList={{enabled=true,gemList={{nameSpec="Added Fire Damage",enabled=true,grantedEffect={color="R"},gemData={tags={support=false}}}}}}
			local profile=filters.profile("support-refresh","Support refresh");profile.rules=filters.generate(build,profile)
			assert.is_false(dependencies.report(build,profile).stale)
			local job=dependencies.beginGenerate(build,profile)
			build.skillsTab.socketGroupList[1].gemList[1].gemData.tags.support=true
			assert.is_false(dependencies.current(job));assert.is_true(dependencies.report(build,profile).stale)
			local generated=filters.generate(build,profile);local found=false
			for _,rule in ipairs(generated) do if rule.origin=="gems" and rule.text:find('BaseType == "Added Fire Damage Support"',1,true) then found=true end end
			assert.is_true(found);profile.rules=generated;assert.is_false(dependencies.report(build,profile).stale)
		end)
		build.skillsTab.socketGroupList=original;assert.is_true(ok,tostring(err))
	end)
	it("rejects malformed metadata, title injection, duplicate IDs and executable imports",function()
		local p=filters.profile("test","Bad\nHide");assert.has_error(function() filters.validate({schemaVersion=1,profiles={p}}) end)
		p=filters.profile("test","Test");p.rules={{id="bad",title="Bad",text='Import "evil.filter"'}}
		assert.has_error(function() filters.validate({schemaVersion=1,profiles={p}}) end)
		p=filters.profile("test","Test");assert.has_error(function() filters.validate({schemaVersion=1,profiles={p,p}}) end)
	end)
	it("reviews removed profiles and changed pickup notices in an AI proposal",function()
		local first=filters.profile("first","First");local second=filters.profile("second","Second");second.trackBuildPickups=true
		build.savers.LootFilters:Replace({schemaVersion=1,activeId="first",profiles={first,second}})
		local changed=copyTable(second);changed.trackBuildPickups=false
		local bridge=require("Modules.DesktopBuildBridge");local prepared=bridge.prepare(build,{mode="edit",title="Revise filters",baseRevision=bridge.revision(build),operations={{type="set_loot_filters",filters={schemaVersion=1,activeId="second",profiles={changed}}}}})
		local summary=table.concat(prepared.changes,"\n")
		assert.is_truthy(summary:find("Active profile changed",1,true));assert.is_truthy(summary:find("Profile removed",1,true));assert.is_truthy(summary:find("Build pickup notices: Enabled -> Disabled",1,true))
		assert.equal(2,#build.savers.LootFilters.data.profiles);assert.is_true(build.savers.LootFilters.data.profiles[2].trackBuildPickups)
	end)
	it("carries filters through native proposal review and portable XML without exporting files",function()
		local p=filters.profile("test","Test");p.rules={filters.rule("mine","My rule",{'BaseType == "Chaos Orb"'})}
		local bridge=require("Modules.DesktopBuildBridge");local prepared=bridge.prepare(build,{mode="edit",title="Loot filter",baseRevision=bridge.revision(build),operations={{type="set_loot_filters",filters={schemaVersion=1,activeId="test",profiles={p}}}}})
		assert.equal(0,#build.savers.LootFilters.data.profiles);assert.equal(1,#prepared.candidate.savers.LootFilters.data.profiles)
		assert.is_truthy(table.concat(prepared.changes," "):find("Loot filters updated",1,true))
		local raw,contents=require("Modules.PlanningBundle").export(prepared.candidate);assert.equal(1,contents.filters);assert.equal(1,require("Modules.PlanningBundle").import(raw).contents.filters)
	end)
	it("keeps cached preset migrations isolated and still rejects unavailable revisions",function()
		local p=filters.profile("test","Test");local raw,changes=filters.migratedBase(p);changes["invented"]="poisoned report"
		local again,nextChanges=filters.migratedBase(p);assert.equal(raw,again);assert.is_nil(nextChanges.invented)
		p.baseCommit=string.rep("a",40);assert.has_error(function() filters.migratedBase(p) end)
		p.template='Show\n BaseType == "Iron Hat"';assert.is_truthy(filters.migratedBase(p):find("Iron Hat",1,true));p.template='Hide\n BaseType == "Iron Ring"';assert.is_truthy(filters.migratedBase(p):find("Iron Ring",1,true))
	end)
end)
