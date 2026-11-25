describe("Crafting method availability across bases",function()
 local sim=require("Modules.CraftingSimulator")
 it("inspects representative bases without guessing prerequisites",function()
  for _,base in ipairs({"Iron Hat","Cobalt Jewel","Searching Eye Jewel","Small Life Flask","Prismatic Tincture","Chieftain Talisman","Plate Vest","Iron Ring"}) do
   local raw="Rarity: NORMAL\n"..base.."\nItem Level: 86";local catalog=sim.catalog(raw,"",5)
   assert.equal(#sim.methods,#catalog.methodAvailability,base)
   for _,row in ipairs(catalog.methodAvailability) do assert.is_boolean(row.available,base.." "..row.method);if not row.available then assert.is_string(row.unavailableReason,base.." "..row.method) end end
  end
 end)
end)
