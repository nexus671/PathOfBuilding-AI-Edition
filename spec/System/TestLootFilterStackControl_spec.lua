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

 it("uses the full tier preview for a continuing target",function()
  local filters=require("Modules.LootFilters");local editing=require("Modules.LootFilterEditing")
  local p=filters.profile("preview","Preview");local source=editing.newTier("low","Low");source.items={"Chaos Orb"}
  local target=editing.newTier("other","Other",'Show\n BaseType == "Divine Orb"\n Continue');p.tiers={source,target}
  require("Classes.LootFilterStackControl").Open(p,"low",function() end);ui:frame()
  local found;for _,command in ipairs(ui.commands) do if command.kind=="text" and command.text=="Tier preview" then found=true end end
  assert.is_true(found)
 end)

end)
