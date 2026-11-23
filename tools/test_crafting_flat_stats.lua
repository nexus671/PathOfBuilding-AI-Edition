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
	ui:text("Armour","100");ui:choose("page","Life / resists / attributes");ui:text("ItemLife","70");ui:text("ItemFireResist","35")
	if output then ui:frame():write(output.."/"..size[1].."-crafting-flat-stat-goals.json") end
	ui:click("keep");assert(saved.Armour==100 and saved.ItemLife==70 and saved.ItemFireResist==35)
	local reopened=require("Classes.CraftingItemStatsControl").Open({ItemLife=70},function() end);assert(reopened.page:GetSelValue()=="Life / resists / attributes");ui:click("close")
end
print("CRAFTING_FLAT_STATS_OK")
