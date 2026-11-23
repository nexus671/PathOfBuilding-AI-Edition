-- Item-only goals use PoB's parsed unconditional modifiers, not build totals.
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local stats=require("Modules.CraftingItemStats");local sim=require("Modules.CraftingSimulator")
local function item(raw) local value=new("Item"):Item(raw);value:BuildAndParseRaw();return value end
local ring=item('Rarity: RARE\nTest\nGold Ring\nItem Level: 86\nImplicits: 0\n+20% to all Elemental Resistances\n+30% to Fire and Cold Resistances\n+30 to all Attributes\n-10% to Chaos Resistance')
local values=stats.itemValues(ring)
assert(values.ItemFireResist==50 and values.ItemColdResist==50 and values.ItemLightningResist==20 and values.ItemChaosResist==-10)
assert(values.ItemStrength==30 and values.ItemDexterity==30 and values.ItemIntelligence==30)
local hat=item('Rarity: RARE\nTest\nIron Hat\nItem Level: 86\n+60 to maximum Life\n+30% to Fire Resistance while on Low Life\n+15 to Dexterity')
values=stats.itemValues(hat);assert(values.ItemLife==60 and values.ItemFireResist==0 and values.ItemDexterity==15)
assert(stats.matchesValues(values,{ItemLife=60,ItemDexterity=15}));assert(not stats.matchesValues(values,{ItemLife=61}))
local defensive=item('Rarity: RARE\nTest\nIron Hat\nItem Level: 86\nImplicits: 0\n15% chance to Suppress Spell Damage\n20% chance to Avoid Elemental Ailments\n12% chance to Avoid being Shocked\n10% chance to Block Attack Damage\n11% chance to Block Spell Damage')
local dv=stats.itemValues(defensive);assert(dv.ItemSpellSuppression==15 and dv.ItemAttackBlock==10 and dv.ItemSpellBlock==11)
assert(dv.ItemAvoidElementalAilments==20 and dv.ItemAvoidShock==32 and dv.ItemAvoidFreeze==20 and dv.ItemAvoidBleed==0)
assert(stats.matchesValues(dv,{ItemSpellSuppression=15,ItemAvoidShock=32}));assert(not stats.matchesValues(dv,{ItemAvoidShock=33}))
local all=stats.itemValues({modList={{name="AvoidAilments",type="BASE",value=7}}});assert(all.ItemAvoidElementalAilments==7 and all.ItemAvoidShock==7 and all.ItemAvoidBleed==7 and all.ItemAvoidPoison==7)
local conditional=stats.itemValues({modList={{name="SpellSuppressionChance",type="BASE",value=50,{type="Condition",var="FullLife"}}}});assert(conditional.ItemSpellSuppression==0)
local slots=stats.itemValues({slotModList={{{name="AvoidShock",type="BASE",value=10}},{{name="AvoidShock",type="BASE",value=20}}}});assert(slots.ItemAvoidShock==nil);assert(not pcall(stats.matchesValues,slots,{ItemAvoidShock=10}))


local malformed=item('Rarity: RARE\nTest\nIron Hat\nItem Level: 86\n+60 to maximum Life\nUnknown modifier text')
assert(stats.itemValues(malformed).ItemLife==nil);assert(not pcall(stats.matchesValues,stats.itemValues(malformed),{ItemLife=1}))
local unresolved={modList={{name="Life",type="BASE",value=function() end},{name="Life",type="BASE",value=10}}}
assert(stats.itemValues(unresolved).ItemLife==nil);assert(not pcall(stats.matchesValues,stats.itemValues(unresolved),{ItemLife=1}))
local slotSpecific={slotModList={{{name="Life",type="BASE",value=10}},{{name="Life",type="BASE",value=20}}}}
assert(stats.itemValues(slotSpecific).ItemLife==nil and stats.itemValues(slotSpecific).ItemFireResist==0)
local uniqueRaw='Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nImplicits: 0\n+37% to all Elemental Resistances'
local unique=require("Modules.CraftingUniqueQuality");assert(unique.matches(uniqueRaw,{nativeStats={ItemFireResist=37,ItemColdResist=37}}));assert(not unique.matches(uniqueRaw,{nativeStats={ItemLightningResist=38}}))
local raw='Rarity: NORMAL\nIron Hat\nItem Level: 86';local model=sim.model(raw);local state=sim.perform(raw,{method="alchemy"},104729).state
values=stats.values(sim,model,state);assert(type(values.ItemLife)=="number" and type(values.ItemFireResist)=="number")
local goal={ItemLife=math.max(0,values.ItemLife)};assert(stats.matches(sim,model,state,goal))
local calculated=sim.calculate(raw,{method="alchemy"},{},nil,{requirements={nativeStats={ItemLife=40}},trials=20,seed=5})
assert(calculated.sampled and calculated.trials==20 and calculated.successChance>=0 and calculated.successChance<=100,"Flat-life goal did not run through the crafting simulator")
local recipe={steps={{method="alchemy"}},targets={},requirements={nativeStats={ItemLife=40,ItemFireResist=10}}}
local simulated=sim.simulate(raw,recipe,{trials=20,maxActions=1,seed=5});assert(simulated.trials==20 and simulated.successes>=0,"Flat-stat recipe did not simulate")
local UI=require("Modules.HeadlessUI")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
	newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build);local saved
	require("Classes.CraftingItemStatsControl").Open(nil,function(result) saved=result end)
	ui:text("Armour","100");ui:choose("page","Life / resists / attributes");ui:text("ItemLife","70");ui:text("ItemFireResist","35");ui:choose("page","Suppression / avoidance");ui:text("ItemSpellSuppression","15");ui:text("ItemAvoidShock","32")
	if output then ui:frame():write(output.."/"..size[1].."-crafting-flat-stat-goals.json") end
	ui:click("keep");assert(saved.Armour==100 and saved.ItemLife==70 and saved.ItemFireResist==35 and saved.ItemSpellSuppression==15 and saved.ItemAvoidShock==32)
	local reopened=require("Classes.CraftingItemStatsControl").Open({ItemLife=70},function() end);assert(reopened.page:GetSelValue()=="Life / resists / attributes");ui:click("close")
	local defensivePage=require("Classes.CraftingItemStatsControl").Open({ItemSpellSuppression=15},function() end);assert(defensivePage.page:GetSelValue()=="Suppression / avoidance");ui:click("close")
end
print("CRAFTING_FLAT_STATS_OK")
