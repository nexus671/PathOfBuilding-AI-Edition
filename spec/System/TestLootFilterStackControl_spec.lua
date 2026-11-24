describe("Stack style preview",function()
 local ui
 before_each(function() newBuild();main.popups={};ui=require("Modules.HeadlessUI").install({width=960,height=640}) end)
 after_each(function() main.popups={};ui:restore() end)
 it("shows the source item using the selected tier's colours",function()
  local filters=require("Modules.LootFilters");local editing=require("Modules.LootFilterEditing")
  local p=filters.profile("preview","Preview");local source=editing.newTier("low","Low");source.items={"Chaos Orb"}
  local red=editing.newTier("red","Red",'Show\n BaseType == "Divine Orb"\n SetTextColor 255 30 30')
  local blue=editing.newTier("blue","Blue",'Show\n BaseType == "Divine Orb"\n SetTextColor 30 30 255')
  p.tiers={source,red,blue};require("Classes.LootFilterStackControl").Open(p,"low",function() end)
  local function textColor()
   ui:frame();for _,command in ipairs(ui.commands) do if command.kind=="text" and command.text=="Chaos Orb" then return command.color end end
  end
  local first=assert(textColor(),"Preview item was not drawn");assert.is_true(first[1]>first[3])
  ui:choose("stackStyle","blue","val");local second=assert(textColor(),"Preview item was not drawn");assert.is_true(second[3]>second[1])
 end)
 it("applies a stack style to every other custom tier without changing the input",function()
  local filters=require("Modules.LootFilters");local editing=require("Modules.LootFilterEditing")
  local p=filters.profile("bulk","Bulk");p.tiers={editing.newTier("low","Low"),editing.newTier("mid","Mid"),editing.newTier("high","High")}
	  p.tiers[1].items={"Chaos Orb"};p.tiers[2].items={"Divine Orb"};p.tiers[3].text='Show\n BaseType == "Mirror of Kalandra"\n SetFontSize 45';p.tiers[3].items={"Mirror of Kalandra"}
  p.tiers[2].stackRules={{minimum=10,styleTierId="low"}};local before=copyTable(p);local kept
  require("Classes.LootFilterStackControl").Open(p,"low",function(value) kept=value end)
	  ui:choose("stackStyle","high","val");ui:text("stackSize","5");ui:click("stackAll");assert.matches("Applied to 2 tiers",main.popups[1].controls.note.label);ui:click("stackKeep")
  assert.same(before,p);assert.same({{minimum=5,styleTierId="high"}},kept.tiers[1].stackRules)
  assert.same({{minimum=10,styleTierId="low"},{minimum=5,styleTierId="high"}},kept.tiers[2].stackRules);assert.is_nil(kept.tiers[3].stackRules)
	  for _,name in ipairs({"Chaos Orb","Divine Orb"}) do
	   local result=filters.simulate(kept,{BaseType=name,Class="Stackable Currency",StackSize=5})
	   assert.same({"45"},result.styles.SetFontSize)
	  end
 end)
 it("includes profile-wide appearance settings in the preview",function()
  local filters=require("Modules.LootFilters");local editing=require("Modules.LootFilterEditing")
  local p=filters.profile("preview","Preview");local source=editing.newTier("low","Low");source.items={"Chaos Orb"}
  local red=editing.newTier("red","Red",'Show\n BaseType == "Divine Orb"\n SetTextColor 255 30 30')
  p.tiers={source,red};p.appearance={textColor={30,255,30,255}}
  require("Classes.LootFilterStackControl").Open(p,"low",function() end);ui:frame()
  local color;for _,command in ipairs(ui.commands) do if command.kind=="text" and command.text=="Chaos Orb" then color=command.color end end
  assert.is_truthy(color);assert.is_true(color[2]>color[1] and color[2]>color[3])
 end)

 it("includes source-category styling in the preview",function()
  local filters=require("Modules.LootFilters");local editing=require("Modules.LootFilterEditing")
  local p=filters.profile("preview","Preview");local source=editing.newTier("low","Low");source.items={"Chaos Orb"}
  local red=editing.newTier("red","Red",'Show\n BaseType == "Divine Orb"\n SetTextColor 255 30 30')
  p.tiers={source,red};p.categoryStyles={{category="Currency",appearance={textColor={30,255,30,255}}}}
  require("Classes.LootFilterStackControl").Open(p,"low",function() end);ui:frame()
  local color;for _,command in ipairs(ui.commands) do if command.kind=="text" and command.text=="Chaos Orb" then color=command.color end end
  assert.is_truthy(color);assert.is_true(color[2]>color[1] and color[2]>color[3])
 end)

 it("labels hidden results explicitly",function()
  local filters=require("Modules.LootFilters");local editing=require("Modules.LootFilterEditing")
  local p=filters.profile("preview","Preview");local source=editing.newTier("low","Low");source.items={"Chaos Orb"}
  local target=editing.newTier("hide","Hide tier",'Hide\n BaseType == "Divine Orb"');p.tiers={source,target}
  require("Classes.LootFilterStackControl").Open(p,"low",function() end);ui:frame()
  local found;for _,command in ipairs(ui.commands) do if command.kind=="text" and command.text=="Hidden" then found=true end end
  assert.is_true(found)
 end)

 it("marks an unsupported target as a style-only preview",function()
  local filters=require("Modules.LootFilters");local editing=require("Modules.LootFilterEditing")
  local p=filters.profile("preview","Preview");local source=editing.newTier("low","Low");source.items={"Chaos Orb"}
  local target=editing.newTier("other","Other",'Show\n BaseType == "Divine Orb"\n FutureDirective 1');p.tiers={source,target}
  require("Classes.LootFilterStackControl").Open(p,"low",function() end);ui:frame()
  local found;for _,command in ipairs(ui.commands) do if command.kind=="text" and command.text=="Style preview" then found=true end end
  assert.is_true(found)
 end)

 it("updates the preview when the entered threshold cannot match the source",function()
  local filters=require("Modules.LootFilters");local editing=require("Modules.LootFilterEditing")
  local p=filters.profile("preview","Preview")
  local source=editing.newTier("low","Low",'Show\n BaseType == "Chaos Orb"\n StackSize < 5');source.items={"Chaos Orb"}
  local target=editing.newTier("other","Other",'Show\n BaseType == "Divine Orb"');p.tiers={source,target}
  require("Classes.LootFilterStackControl").Open(p,"low",function() end)
  local function label()
   ui:frame();for _,command in ipairs(ui.commands) do
    if command.kind=="text" and (command.text=="Tier preview" or command.text=="Style preview") then return command.text end
   end
  end
  assert.equal("Style preview",label())
  local unavailable=false;for _,command in ipairs(ui.commands) do if command.kind=="text" and command.text=="Unavailable" then unavailable=true end end
  assert.is_true(unavailable)
  ui:text("stackSize","3");assert.equal("Tier preview",label())
  ui:text("stackSize","5");assert.equal("Style preview",label())
  ui:text("stackSize","");assert.equal("Style preview",label())
 end)

 it("shows a style-only preview when another continuing threshold excludes the new range",function()
  local filters=require("Modules.LootFilters");local editing=require("Modules.LootFilterEditing")
  local p=filters.profile("preview","Preview")
  local source=editing.newTier("low","Low",'Show\n BaseType == "Chaos Orb"\n StackSize >= 10\n Continue');source.items={"Chaos Orb"}
  local target=editing.newTier("other","Other",'Show\n BaseType == "Divine Orb"')
  source.stackRules={{minimum=10,styleTierId="other"}};p.tiers={source,target}
  require("Classes.LootFilterStackControl").Open(p,"low",function() end);ui:frame()
  local found;for _,command in ipairs(ui.commands) do if command.kind=="text" and command.text=="Style preview" then found=true end end
  assert.is_true(found)
 end)

 it("does not promise a tier preview if another tier is invalid",function()
  local filters=require("Modules.LootFilters");local editing=require("Modules.LootFilterEditing")
  local p=filters.profile("preview","Preview")
  local source=editing.newTier("low","Low");source.items={"Chaos Orb"}
  local target=editing.newTier("other","Other")
  local invalid=editing.newTier("invalid","Invalid");invalid.stackRules={{minimum=5,styleTierId="missing"}}
  p.tiers={source,target,invalid};require("Classes.LootFilterStackControl").Open(p,"low",function() end);ui:frame()
  local found;for _,command in ipairs(ui.commands) do if command.kind=="text" and command.text=="Style preview" then found=true end end
  assert.is_true(found)
 end)

 it("uses the full tier preview for a continuing target",function()
  local filters=require("Modules.LootFilters");local editing=require("Modules.LootFilterEditing")
  local p=filters.profile("preview","Preview");local source=editing.newTier("low","Low");source.items={"Chaos Orb"}
  local target=editing.newTier("other","Other",'Show\n BaseType == "Divine Orb"\n Continue');p.tiers={source,target}
  require("Classes.LootFilterStackControl").Open(p,"low",function() end);ui:frame()
  local found;for _,command in ipairs(ui.commands) do if command.kind=="text" and command.text=="Tier preview" then found=true end end
  assert.is_true(found)
 end)

end)
