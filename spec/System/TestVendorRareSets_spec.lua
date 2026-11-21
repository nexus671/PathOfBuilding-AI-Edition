describe("Rare vendor set review",function()
 local vendor=require("Modules.VendorRarePairs")
 local function item(class,level,identified)
  return "Item Class: "..class.."\nRarity: Rare\n"..(identified and "Gloom Bite\n" or "").."Example Base\n--------\nItem Level: "..level.."\n--------\n"..(identified and "" or "Unidentified")
 end
 local function kit(level,weapon)
  local list={};for _,class in ipairs({"Helmets","Body Armours","Gloves","Boots","Amulets","Belts","Rings","Rings",weapon or "Bows"}) do list[#list+1]=item(class,level) end;return list
 end
 it("groups full sets and determines the lowest level band",function()
  for _,pair in ipairs({{59,"Orb of Alchemy"},{60,"Chaos Orb"},{74,"Chaos Orb"},{75,"Regal Orb"}}) do
   local input=kit(86);input[2]=item("Body Armours",pair[1]);local result=vendor.reviewSets(input)
   assert.equal(1,#result.groups);assert.equal(pair[2],result.groups[1].reward);assert.equal(9,#result.groups[1].items);assert.equal(0,#result.remaining);assert.is_true(result.groups[1].unidentified)
  end
 end)
 it("requires all equipment slots and two one-hand slots",function()
  local input=kit(70,"One Hand Swords");assert.equal(0,#vendor.reviewSets(input).groups)
  input[#input+1]=item("Shields",80,true);local result=vendor.reviewSets(input);assert.equal(1,#result.groups);assert.equal(10,#result.groups[1].items);assert.is_false(result.groups[1].unidentified)
  local used={};for _,entry in ipairs(result.groups[1].items) do assert.is_nil(used[entry.index]);used[entry.index]=true end
 end)
 it("prefers higher-level items and leaves lower-level alternatives",function()
  local input=kit(80);input[#input+1]=item("Helmets",40);local result=vendor.reviewSets(input)
  assert.equal("Regal Orb",result.groups[1].reward);assert.equal(40,result.remaining[1].level)
 end)
 it("rejects unsupported, missing-level and non-rare input",function()
  assert.has_error(function() vendor.parseSet(item("Quivers",80)) end)
  assert.has_error(function() vendor.parseSet(item("Helmets",80):gsub("Item Level: 80","Item Level: unknown")) end)
  assert.has_error(function() vendor.parseSet(item("Helmets",80):gsub("Rarity: Rare","Rarity: Magic")) end)
 end)
end)
