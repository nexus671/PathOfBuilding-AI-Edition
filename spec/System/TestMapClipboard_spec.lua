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
 it("imports corrupted normal and magic maps without changing rarity",function()
  local normal="Item Class: Maps\nRarity: Normal\nMap (Tier 1)\n--------\nItem Level: 68\n--------\n"..trailer.."\n--------\nCorrupted"
  local magic="Item Class: Maps\nRarity: Magic\nEnlarged Map (Tier 5)\n--------\nItem Level: 68\n--------\nMonsters have 45% increased Area of Effect"..trailer.."\n--------\nCorrupted"
  local a,b=parser.parse(normal).state,parser.parse(magic).state
  assert.equal("normal",a.rarity);assert.is_true(a.corrupted);assert.equal(0,#a.selected)
  assert.equal("magic",b.rarity);assert.is_true(b.corrupted);assert.same({"MapMonsterAreaOfEffectMapWorlds"},b.selected)
  local withImplicit=normal:gsub("Item Level: 68\n--------\n","Item Level: 68\n--------\n+15%% Item Rarity (implicit)\nArea is Influenced by the Originator's Memories (implicit)\n--------\n")
  local parsed=parser.parse(withImplicit).state;assert.same({id="MapCorruptionItemRarity",value=15},parsed.implicit)
  assert.same({{kind="implicit",text="Area is Influenced by the Originator's Memories"}},parsed.observedEffects)
  local draft={id="normal-corrupt",title="Copied map",patch=require("Modules.MapCraftingData").source().patch,baseId=parsed.baseId,tier=parsed.tier,itemLevel=parsed.itemLevel,rarity=parsed.rarity,selected=parsed.selected,corrupted=parsed.corrupted,implicit=parsed.implicit,observedEffects=parsed.observedEffects}
  assert.same(draft,require("Modules.AtlasPlanner").validateMapDraft(draft))
 end)
 it("imports unidentified maps without inventing their hidden modifiers",function()
  local raw="Item Class: Maps\nRarity: Rare\nMap (Tier 5)\n--------\nItem Level: 68\n--------\nUnidentified"..trailer
  local result=parser.parse(raw);local state=result.state;assert.is_true(state.unidentified);assert.equal(0,#state.selected);assert.matches("unknown",result.notes[1],1,true);assert.equal(30,result.unidentifiedOpeningBonus.atlasDrops)
  assert.has_error(function() require("Modules.MapCurrency").perform(state,"chaos",1) end)
  assert.has_error(function() require("Modules.MapCraftEstimate").run(state,{wanted={},avoid={},trials=1,maxAttempts=1,seed=1}) end)
 end)
 it("imports mirrored maps and preserves their marker",function()
  local raw=header.."Monsters have 45% increased Area of Effect"..trailer.."\n--------\nMirrored"
  local state=parser.parse(raw).state;assert.is_true(state.mirrored);assert.equal("rare",state.rarity)
  assert.same({"MapMonsterAreaOfEffectMapWorlds"},state.selected)
  assert.has_error(function() require("Modules.MapCurrency").perform(state,"chaos",1) end)
  assert.has_error(function() require("Modules.MapCraftEstimate").run(state,{wanted={},avoid={},trials=1,maxAttempts=1,seed=1}) end)
 end)
 it("recognizes the Blighted implicit on copied tier-based maps",function()
  local raw="Item Class: Maps\nRarity: Rare\nBlighted Example\nBlighted Map (Tier 5)\n--------\nItem Level: 68\n--------\nArea is infested with Fungal Growths (implicit)\n--------\nMonsters have 45% increased Area of Effect"..trailer
  local result=parser.parse(raw)
  assert.equal("Metadata/Items/Maps/MapKeyTier5",result.state.baseId)
  assert.is_true(require("Modules.MapObservedEffects").isBlighted(result.state.observedEffects))
  assert.matches("Blighted rare%-only",result.notes[3]);assert.matches("not modeled",result.notes[3])
  assert.has_error(function() parser.parse(raw:gsub("Area is infested with Fungal Growths %(implicit%)\n--------\n","")) end)
  local magic="Item Class: Maps\nRarity: Magic\nEnlarged Blighted Map (Tier 5)\n--------\nItem Level: 68\n--------\nMonsters have 45% increased Area of Effect"..trailer
  assert.has_error(function() parser.parse(magic) end)
  local legacy="Item Class: Maps\nRarity: Rare\nAncient Example\nBlighted Map (Tier 16)\n--------\nItem Level: 83\n--------\nArea is infested with Fungal Growths (implicit)\n--------\nArea contains a Mirage"..trailer
  local imported=parser.parse(legacy);local existing=imported.state;assert.same({"MapContainsMirageWorlds"},existing.selected);assert.matches("pre%-hotfix",imported.notes[3])
  assert.is_true(require("Modules.MapCurrency").options(existing)[4].available)
 end)
 it("imports a named Nightmare map with its complete visible modifier",function()
  local raw="Item Class: Maps\nRarity: Rare\nDread Tower\nAbomination Map\n--------\nMap Tier: 17\nItem Level: 84\n--------\nPlayers are Cursed with Vulnerability\nPlayers are Cursed with Temporal Chains\nPlayers are Cursed with Elemental Weakness\n35% more Threads found in Area"..trailer
  local result=parser.parse(raw)
  assert.equal("Metadata/Items/Maps/MapWorldsAbomination",result.state.baseId);assert.equal(17,result.state.tier)
  assert.same({"MapUberModCurses"},result.state.selected);assert.matches("experimental",result.notes[3])
  assert.has_error(function() parser.parse(raw:gsub("Map Tier: 17","Map Tier: 16")) end)
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
 it("retains multiple map implicits and enchantments without modeling them",function()
  local raw=header.."Map contains Baran's Citadel (implicit)\nArea is Influenced by the Originator's Memories (implicit)\nPlayers are Delirious (enchant)\n--------\nMonsters have 45% increased Area of Effect"..trailer
  local result=parser.parse(raw)
  assert.same({{kind="implicit",text="Map contains Baran's Citadel"},{kind="implicit",text="Area is Influenced by the Originator's Memories"},{kind="enchant",text="Players are Delirious"}},result.state.observedEffects)
  assert.matches("not modeled",result.notes[3])
  local corrupt=parser.parse(raw.."\n--------\nCorrupted")
  assert.same(result.state.observedEffects,corrupt.state.observedEffects)
 end)
 it("preserves current Delirium explicit lines while retaining ordinary modifiers",function()
  local raw=header.."Players in Area are 35% Delirious\nDelirium Reward Type: Currency\nMonsters have 45% increased Area of Effect"..trailer
  local result=parser.parse(raw)
  assert.same({{kind="explicit",text="Players in Area are 35% Delirious"},{kind="explicit",text="Delirium Reward Type: Currency"}},result.state.observedEffects)
  assert.same({"MapMonsterAreaOfEffectMapWorlds"},result.state.selected)
  assert.matches("not modeled",result.notes[3])
  assert.has_error(function() parser.parse(raw:gsub("Delirium Reward Type: Currency\n","")) end)
  assert.has_error(function() parser.parse(raw:gsub("35%% Delirious","101%% Delirious")) end)
  assert.has_error(function() parser.parse(raw:gsub("Delirium Reward Type: Currency\n","Delirium Reward Type: Currency\nDelirium Reward Type: Maps\n")) end)
 end)
 it("retains an observed implicit alongside one modeled corruption implicit",function()
  local raw=header.."+15% Item Rarity (implicit)\nArea is Influenced by the Originator's Memories (implicit)\n--------\nMonsters have 45% increased Area of Effect"..trailer.."\n--------\nCorrupted"
  local result=parser.parse(raw)
  assert.same({id="MapCorruptionItemRarity",value=15},result.state.implicit)
  assert.same({{kind="implicit",text="Area is Influenced by the Originator's Memories"}},result.state.observedEffects)
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
  assert.has_error(function() parser.parse(header.."^1Bad data (enchant)\nMonsters have 45% increased Area of Effect"..trailer) end)
  assert.has_error(function() parser.parse(header:gsub("Item Level: 68\n","")..trailer) end)
 end)
end)
