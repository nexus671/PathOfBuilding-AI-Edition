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
 it("chooses the highest available weapon combination without losing later sets",function()
  local input=kit(80);input[9]=item("Bows",40);input[#input+1]=item("One Hand Swords",80);input[#input+1]=item("Shields",80)
  local result=vendor.reviewSets(input);assert.equal(1,#result.groups);assert.equal("Regal Orb",result.groups[1].reward);assert.equal(40,result.remaining[1].level)
  local second=kit(80);for _,entry in ipairs(second) do input[#input+1]=entry end
  result=vendor.reviewSets(input);assert.equal(2,#result.groups);assert.equal("Regal Orb",result.groups[1].reward);assert.equal("Regal Orb",result.groups[2].reward)
  local used={};for _,group in ipairs(result.groups) do for _,entry in ipairs(group.items) do assert.is_nil(used[entry.index]);used[entry.index]=true end end
 end)
 it("can suggest two shields and describes missing one-hand slots",function()
  local input=kit(80,"Shields");local partial=vendor.reviewSets(input);assert.equal(0,#partial.groups)
  local found;for _,entry in ipairs(partial.missing) do if entry.slot=="Weapon or shield" then found=entry end end;assert.is_not_nil(found)
  input[#input+1]=item("Shields",80);local result=vendor.reviewSets(input);assert.equal(1,#result.groups);assert.equal(10,#result.groups[1].items);assert.equal("Regal Orb",result.groups[1].reward)
 end)
 it("prioritizes Chaos sets and keeps lower-level items out of them",function()
  local input=kit(80);input[#input+1]=item("Helmets",68);input[#input+1]=item("Gloves",40)
  local result=vendor.reviewSets(input,"chaos");assert.equal("chaos",result.preference);assert.is_true(result.maximumProven);assert.equal(1,result.maxSetsUpperBound);assert.equal(1,#result.groups);assert.equal("Chaos Orb",result.groups[1].reward);assert.equal(68,result.groups[1].minLevel)
  assert.equal(2,#result.remaining);local seen={};for _,entry in ipairs(result.remaining) do seen[entry.level]=true end;assert.is_true(seen[40]);assert.is_true(seen[80])
  local noAnchor=vendor.reviewSets(kit(80),"chaos");assert.equal(0,#noAnchor.groups)
  local found;for _,entry in ipairs(noAnchor.missing) do if entry.slot=="Item level 60-74" then found=entry end end;assert.is_not_nil(found)
  assert.equal("Regal Orb",vendor.reviewSets(kit(80)).groups[1].reward)
  assert.has_error(function() vendor.reviewSets(input,"unknown") end)
 end)
 it("proves the modeled Chaos set count with competing weapon layouts",function()
  local input=kit(80);local second=kit(80);for _,raw in ipairs(second) do input[#input+1]=raw end
  input[9]=item("Bows",70);input[18]=item("Bows",80);input[#input+1]=item("One Hand Swords",68);input[#input+1]=item("Shields",80)
  local result=vendor.reviewSets(input,"chaos");assert.equal(2,#result.groups);assert.equal(2,result.maxSetsUpperBound);assert.is_true(result.maximumProven)
  local seen={};for _,group in ipairs(result.groups) do assert.equal("Chaos Orb",group.reward);for _,entry in ipairs(group.items) do assert.is_nil(seen[entry.index]);seen[entry.index]=true end end
  local noAnchor=vendor.reviewSets(kit(80),"chaos");assert.equal(0,noAnchor.maxSetsUpperBound);assert.is_true(noAnchor.maximumProven)
 end)
 it("does not count two low weapons in one set as two Chaos sets",function()
  local input=kit(80);for _,raw in ipairs(kit(80)) do input[#input+1]=raw end
  input[#input+1]=item("One Hand Swords",70);input[#input+1]=item("Shields",70);input[#input+1]=item("Shields",70)
  local result=vendor.reviewSets(input,"chaos");assert.equal(1,#result.groups);assert.equal(1,result.maxSetsUpperBound);assert.is_true(result.maximumProven)
 end)
 it("checks the bound against exhaustive modeled weapon layouts",function()
  local classes={"Helmets","Body Armours","Gloves","Boots","Amulets","Belts","Rings","Bows","One Hand Swords","Shields"}
  local seed=137;local function random(n) seed=(seed*48271)%2147483647;return seed%n end
  for trial=1,200 do
   local input,counts,lows={},{},{}
   for i,class in ipairs(classes) do
    counts[i]=random(i==7 and 7 or 5);lows[i]=0
    for j=1,counts[i] do local level=random(2)==0 and 70 or 80;if level==70 then lows[i]=lows[i]+1 end;input[#input+1]=item(class,level) end
   end
   local upper=0
   for k=1,4 do
    local possible=true;local low=0
    for i=1,7 do local need=k*(i==7 and 2 or 1);if counts[i]<need then possible=false end;low=low+math.min(lows[i],k) end
    for two=0,k do
     local paired=2*(k-two)
     if possible and two<=counts[8] and paired<=counts[9]+counts[10] and low+math.min(two,lows[8])+math.min(k-two,lows[9]+lows[10])>=k then upper=math.max(upper,k) end
    end
   end
   local result=vendor.reviewSets(input,"chaos");assert.equal(upper,result.maxSetsUpperBound);assert.equal(#result.groups==upper,result.maximumProven)
  end
 end)
 it("accepts both Chaos item-level boundaries and excludes lower pieces",function()
  for _,level in ipairs({60,74}) do local input=kit(80);input[#input+1]=item("Helmets",level);input[#input+1]=item("Helmets",59)
   local result=vendor.reviewSets(input,"chaos");assert.equal("Chaos Orb",result.groups[1].reward);assert.equal(level,result.groups[1].minLevel)
   local retained=false;for _,entry in ipairs(result.remaining) do if entry.level==59 then retained=true end end;assert.is_true(retained)
  end
 end)
 it("uses a level 60-74 weapon as the Chaos anchor",function()
  local input=kit(80);input[9]=item("Bows",70);local result=vendor.reviewSets(input,"chaos")
  assert.equal(1,#result.groups);assert.equal("Chaos Orb",result.groups[1].reward)
  input[9]=item("One Hand Swords",70);input[#input+1]=item("Shields",80);input[#input+1]=item("Bows",80)
  result=vendor.reviewSets(input,"chaos");assert.equal(1,#result.groups);assert.equal("Chaos Orb",result.groups[1].reward);assert.equal(10,#result.groups[1].items)
 end)
 it("does not ask for another Chaos-level item when its weapon partner is missing",function()
  local input=kit(80,"One Hand Swords");input[9]=item("One Hand Swords",70)
  local result=vendor.reviewSets(input,"chaos");assert.equal(0,#result.groups)
  local missing={};for _,entry in ipairs(result.missing) do missing[entry.slot]=entry end
  assert.is_not_nil(missing["Weapon or shield"]);assert.is_nil(missing["Item level 60-74"])
 end)
 it("explains an unusable one-hand Chaos anchor when a two-hand weapon is available",function()
  for _,class in ipairs({"One Hand Swords","Shields"}) do
   local input=kit(80);input[#input+1]=item(class,70)
   local result=vendor.reviewSets(input,"chaos");assert.equal(0,#result.groups)
   local missing={};for _,entry in ipairs(result.missing) do missing[entry.slot]=entry end
   assert.is_not_nil(missing["Chaos-level item or weapon partner"])
   assert.matches("pair the existing weapon or shield",missing["Chaos-level item or weapon partner"].detail,1,true)
   input[#input+1]=item("Shields",80);result=vendor.reviewSets(input,"chaos");assert.equal(1,#result.groups);assert.equal("Chaos Orb",result.groups[1].reward)
  end
 end)
 it("reports missing slots from unused items",function()
  local input={item("Helmets",70),item("Rings",70),item("One Hand Swords",70)};local result=vendor.reviewSets(input);local missing={}
  for _,entry in ipairs(result.missing) do missing[entry.slot]=entry end
  assert.is_nil(missing.Helmet);assert.equal(1,missing.Ring.count);assert.equal(1,missing["Weapon or shield"].count);assert.equal(1,missing.Belt.count)
  local completed=kit(70);completed[#completed+1]=item("Rings",70);result=vendor.reviewSets(completed);missing={};for _,entry in ipairs(result.missing) do missing[entry.slot]=entry end
  assert.equal(1,missing.Ring.count);assert.equal(1,missing.Helmet.count);assert.equal(1,missing.Weapon.count)
  assert.equal(1,#result.groups);assert.equal(1,#result.remaining)
 end)
 it("rejects unsupported, missing-level and non-rare input",function()
  assert.has_error(function() vendor.parseSet(item("Quivers",80)) end)
  assert.has_error(function() vendor.parseSet(item("Helmets",80):gsub("Item Level: 80","Item Level: unknown")) end)
  assert.has_error(function() vendor.parseSet(item("Helmets",80):gsub("Rarity: Rare","Rarity: Magic")) end)
 end)
end)
