-- cspell:ignore RGBW RGBWW
describe("Crafting goal conflicts",function()
 local sim=require("Modules.CraftingSimulator")
 before_each(function() newBuild();main.popups={} end)
 after_each(function() main.popups={} end)
 local function recipe(requirements) return {steps={{method="chaos"}},targets={},requirements=requirements} end
 it("keeps legacy recipes structurally valid but explains impossible goals before calculation",function()
  local cases={
   {{exactSockets=4,links=5},"linked sockets"},
   {{exactSockets=4,links=3,minAbyssSockets=2},"Abyss sockets"},
   {{exactSockets=4,socketColours="RGB",minAbyssSockets=2},"socket colours"},
   {{exactSockets=1,minAbyssSockets=2},"Abyss sockets"},
   {{links=5,minAbyssSockets=2},"six-socket limit"},
   {{socketColours="RGBWW",minAbyssSockets=2},"six-socket limit"},
   {{minFractured=3,maxAffixes=2},"Minimum fractured modifiers"},
  }
  for _,entry in ipairs(cases) do
   local saved=sim.validateRecipe(recipe(entry[1]));assert.same(entry[1],saved.requirements)
   local ok,message=pcall(sim.simulate,"",saved,{trials=1});assert.is_false(ok);assert.matches(entry[2],message,1,true)
   ok,message=pcall(sim.simulate,"Rarity: UNIQUE\n",saved,{trials=1});assert.is_false(ok);assert.matches(entry[2],message,1,true)
   ok,message=pcall(sim.calculate,"",{method="chaos"},{},nil,{requirements=entry[1]});assert.is_false(ok);assert.matches(entry[2],message,1,true)
  end
  assert.is_nil(sim.requirementsConflict({exactSockets=5,links=3,minAbyssSockets=2,socketColours="RGB"}))
  assert.is_nil(sim.requirementsConflict({sockets=4,links=5}))
  assert.is_nil(sim.requirementsConflict({links=4,minAbyssSockets=2,socketColours="RGBW"}))
  assert.is_nil(sim.requirementsConflict({minFractured=2,maxAffixes=2}))
 end)
 it("preserves step failure routes when a step condition is unreachable",function()
  local r=recipe({minQuality=1});r.steps[1].untilRequirements={exactSockets=2,socketColours="RGB"};r=sim.validateRecipe(r)
  assert.is_nil(sim.recipeConflict(r))
 end)
 it("keeps the editor open so a conflicting goal can be fixed",function()
  local saved;local c=require("Classes.CraftingTargetControl").Open({},{exactSockets=4,links=5},nil,function(_,value) saved=value end)
  assert.equal("Exactly",c.socketMode:GetSelValue());c.keep:Click()
  assert.is_nil(saved);assert.equal("4",c.sockets.buf);assert.equal("5",c.links.buf)
  main:ClosePopup();c.links:SetText("4",true);c.keep:Click();assert.equal(4,saved.exactSockets);assert.equal(4,saved.links)
 end)
end)
