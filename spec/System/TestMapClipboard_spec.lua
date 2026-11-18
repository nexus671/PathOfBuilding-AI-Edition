describe("Map clipboard import",function()
 local parser=require("Modules.MapClipboard")
 local header="Item Class: Maps\nRarity: Rare\nDreary Strand\nStrand Map\n--------\nMap Tier: 5\nItem Level: 68\n--------\nMonster Level: 72\n--------\n"
 local trailer="\n--------\nTravel to this Map by using it in a personal Map Device. Maps can only be used once."
 it("imports a current tier-based map without a separate Map Tier line",function()
  local raw="Item Class: Maps\nRarity: Rare\nVortex Artifice\nMap (Tier 5)\n--------\nQuality (Pack Size): +20% (augmented)\n--------\nItem Level: 68\n--------\nMonsters have 45% increased Area of Effect"..trailer
  local result=parser.parse(raw)
  assert.equal("Metadata/Items/Maps/MapKeyTier5",result.state.baseId)
  assert.equal(5,result.state.tier)
  assert.same({kind="Pack Size",value=20},result.state.quality)
  assert.same({"MapMonsterAreaOfEffectMapWorlds"},result.state.selected)
  assert.has_error(function() parser.parse(raw:gsub("Item Level: 68","Map Tier: 6\nItem Level: 68")) end)
  assert.has_error(function() parser.parse(raw:gsub("Quality %(Pack Size%): %+20%% %(augmented%)","Quality (Pack Size): unknown")) end)
 end)
 it("accepts normal and magic tier-based map item headers",function()
  local normal="Item Class: Maps\nRarity: Normal\nMap (Tier 1)\n--------\nItem Level: 68\n--------\n"
  assert.equal("Metadata/Items/Maps/MapKeyTier1",parser.parse(normal..trailer).state.baseId)
  local magic="Item Class: Maps\nRarity: Magic\nEnlarged Map (Tier 5)\n--------\nItem Level: 68\n--------\nMonsters have 45% increased Area of Effect"
  assert.equal("Metadata/Items/Maps/MapKeyTier5",parser.parse(magic..trailer).state.baseId)
 end)
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
