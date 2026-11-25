local dir=assert(arg[1]);arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true
local uiLib=require('Modules.HeadlessUI');local sim=require('Modules.CraftingSimulator');local rog=require('Modules.CraftingRog')
local jewel=sim.model('Rarity: NORMAL\nCobalt Jewel\nItem Level: 86');local helmet=sim.model('Rarity: NORMAL\nIron Hat\nItem Level: 86')
local offer={method='rog_reroll',rogOperation='remove_lowest'}
assert(rog.jewelOfferWarning(jewel,offer) and not rog.jewelOfferWarning(helmet,offer))
for _,op in ipairs({'reroll','add','values_side'}) do assert(not rog.jewelOfferWarning(jewel,{rogOperation=op})) end
local found=false;for _,w in ipairs(sim.actionWarnings(offer,jewel)) do if w.code=='rog_jewel_offer_history' then found=true;assert(w.message:find('unverified',1,true)) end end;assert(found)
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=uiLib.install({width=size[1],height=size[2]});ui:bind(build)
 local saved;local c=require('Classes.CraftingRogControl').Open(offer,function(v) saved=v end,jewel)
 assert(c.jewelHint:IsShown() and not c.limits:IsShown() and not c.jewelValueHint:IsShown());c.operation:SelByValue('values_one','val');assert(c.jewelValueHint:IsShown() and not c.jewelHint:IsShown());c.operation:SelByValue('remove_lowest','val');ui:frame():write(dir..'/'..size[1]..'-rog-jewel-warning.json')
 ui:click('keep');assert(saved.rogOperation=='remove_lowest')
 c=require('Classes.CraftingRogControl').Open(nil,function() end,jewel);assert(not c.jewelHint:IsShown());ui:click('close')
 c=require('Classes.CraftingRogControl').Open(offer,function() end,helmet);assert(not c.jewelHint:IsShown());ui:click('close')
end
print('Rog jewel guidance passed')
