-- cspell:ignore Katakohi

describe("Socket-reducing glove enchantments",function()
 local sim=require("Modules.CraftingSimulator")
 local function raw(count)
  local lines={"Rarity: NORMAL","Iron Gauntlets","Item Level: 86","Sockets: "..table.concat((count==1 and {"W","W","W"} or {"W","W"}),"-"),"Implicits: "..(count*2)}
  for i=1,count do lines[#lines+1]="{enchant}-1 to maximum Sockets";lines[#lines+1]="{enchant}"..(i==1 and "20% increased Fire Damage" or "20% increased Cold Damage") end
  return table.concat(lines,"\n")
 end
 it("uses the reduced capacity for validation, bench choices and guaranteed sockets",function()
  for count=1,2 do
   local text=raw(count);local model=sim.model(text);local limit=4-count
   assert.equal(limit,sim.socketLimit(model));assert.equal(limit,#model.initial.sockets)
   assert.equal(limit,model.item.selectableSocketCount)
   assert.is_nil((itemLib.formatModLine(model.item.enchantModLines[1],false) or ""):find("Not supported",1,true))
   local options=sim.actionOptions(model,model.initial,"socket_bench")
   for _,choice in ipairs(options) do assert.is_true(choice.action.count<=limit) end
   local invalid=copyTable(model.initial);invalid.sockets[#invalid.sockets+1]={color="W",group=9}
   assert.is_false(pcall(sim.validateState,model,invalid))
   assert.is_false(pcall(sim.perform,text,{method="socket_bench",count=limit+1},1))
   assert.is_false(require("Modules.CraftingAvailability").check("omen_jeweller",model.initial,model))
   local bound=sim.perform(text,{method="binding"},1);assert.equal(limit,#bound.state.sockets)
   local output=sim.toItem(model,bound.state).raw;assert.equal(count,select(2,output:gsub("%-1 to maximum Sockets","")))
   assert.equal(limit,sim.socketLimit(sim.model(output)))
  end
 end)
 it("handles a single enchantment that removes three maximum sockets",function()
  local text="Rarity: NORMAL\nIron Gauntlets\nItem Level: 86\nSockets: W\nImplicits: 1\n{enchant}-3 to maximum Sockets"
  local model=sim.model(text);assert.equal(1,sim.socketLimit(model));assert.equal(1,model.item.selectableSocketCount)
  assert.is_false(require("Modules.CraftingAvailability").check("socket_bench",model.initial,model))
 end)
 it("does not treat an explicit stat or a non-glove enchant as an etched socket",function()
  local model=sim.model("Rarity: NORMAL\nPlate Vest\nItem Level: 86\nSockets: W W W W W W\nImplicits: 1\n{enchant}-1 to maximum Sockets")
  assert.equal(6,sim.socketLimit(model))
 end)
end)
