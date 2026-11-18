describe("Map clipboard import",function()
 local parser=require("Modules.MapClipboard")
 local header="Item Class: Maps\nRarity: Rare\nDreary Strand\nStrand Map\n--------\nMap Tier: 5\nItem Level: 68\n--------\nMonster Level: 72\n--------\n"
 local trailer="\n--------\nTravel to this Map by using it in a personal Map Device. Maps can only be used once."
 it("resolves a complete copied ordinary map and verifies exact roll values",function()
  local raw=header.."Monsters have 45% increased Area of Effect\nMonsters deal 55% extra Physical Damage as Fire"..trailer
  local result=parser.parse(raw);assert.equal("Metadata/Items/Maps/MapWorldsStrand",result.state.baseId)
  assert.same({"MapMonsterAreaOfEffectMapWorlds","MapMonsterFireDamageMapWorlds"},result.state.selected)
  assert.equal(2,#result.state.rolls);assert.same({16,9,6,55},result.state.rolls[2].values);assert.matches("other values remain ranges",result.notes[1])
 end)
 it("treats a multi-line modifier as one affix",function()
  local raw=header.."Unique Boss deals 15% increased Damage\nUnique Boss has 20% increased Attack and Cast Speed"..trailer
  local result=parser.parse(raw);assert.same({"MapDangerousBoss1MapWorlds"},result.state.selected)
 end)
 it("verifies multiple independently rendered values in a hybrid modifier",function()
  local raw=header.."Monsters have 180% increased Critical Strike Chance\n+33% to Monster Critical Strike Multiplier"..trailer
  local result=parser.parse(raw);assert.same({"MapMonsterCriticalStrikesAndDamageMapWorlds"},result.state.selected)
  assert.same({16,9,6,180,33},result.state.rolls[1].values)
 end)
 it("records an unambiguous corruption implicit and its value",function()
  local raw=header.."+15% Item Rarity (implicit)\n--------\nMonsters have 45% increased Area of Effect"..trailer.."\n--------\nCorrupted"
  local result=parser.parse(raw);assert.is_true(result.state.corrupted);assert.same({id="MapCorruptionItemRarity",value=15},result.state.implicit)
 end)
 it("rejects modifier text that matches multiple identities",function()
  local source=require("Modules.MapCraftingData").source();local alias="MapClipboardTestAlias"
  source.mods[alias]=copyTable(source.mods.MapMonsterAreaOfEffectMapWorlds)
  local ok,reason=pcall(parser.parse,header.."Monsters have 45% increased Area of Effect"..trailer)
  source.mods[alias]=nil
  assert.is_false(ok);assert.matches("multiple identities",reason)
 end)
 it("rejects missing, unmatched, unsupported and out-of-range information",function()
  assert.has_error(function() parser.parse(header.."Monsters have 999% increased Area of Effect"..trailer) end)
  assert.has_error(function() parser.parse(header.."Unknown modifier text"..trailer) end)
  assert.has_error(function() parser.parse(header.."Players are Delirious (enchant)"..trailer) end)
  assert.has_error(function() parser.parse(header:gsub("Item Level: 68\n","")..trailer) end)
 end)
end)
