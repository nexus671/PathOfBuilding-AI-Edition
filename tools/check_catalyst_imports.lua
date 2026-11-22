-- Generated single-modifier catalyst imports; rejected ambiguous items remain unmodeled.
arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true
local sim=require('Modules.CraftingSimulator');local accepted,rejected,wrong,attempted=0,0,0,0
for _,entry in ipairs({{'Stygian Vise','Prismatic',8},{'Ruby Ring','Turbulent',11},{'Gold Amulet','Fertile',4}}) do
 local raw='Rarity: NORMAL\n'..entry[1]..'\nItem Level: 86\nCatalyst: '..entry[2]..'\nCatalystQuality: 20';local model=sim.model(raw)
 local candidates={};for _,v in ipairs(model.mods) do local mod=v.mod;if #mod==1 and mod.affix and mod.affix~='' and mod[1]:match('%(%-?%d+%-%-?%d+%)') and model.item:GetModLineValueScalar({line=mod[1],modTags=mod.modTags,prefix=mod.type=='Prefix',suffix=mod.type=='Suffix'},'explicit')>1 then candidates[#candidates+1]=v end end
 for j=1,math.min(20,#candidates) do local v=candidates[j];local state=copyTable(model.initial);state.rarity='MAGIC';state.affixes={{id=v.id,range=0.5}};local ok,item=pcall(sim.toItem,model,state)
  if ok and #item.explicitModLines==1 then local display=itemLib.formatModLine(item.explicitModLines[1],false);if display then
   local copy='Rarity: MAGIC\n'..item.name..'\nItem Level: 86\nCatalyst: '..entry[2]..'\nCatalystQuality: 20\n'..StripEscapes(display);attempted=attempted+1
   local resolved,result=pcall(sim.model,copy);if resolved then accepted=accepted+1;local out=sim.toItem(result,result.initial);local found=StripEscapes(itemLib.formatModLine(out.explicitModLines[1],false) or '');if found~=StripEscapes(display) or result.initial.affixes[1].id~=v.id or itemLib.applyRange(v.mod[1],result.initial.affixes[1].range)~=itemLib.applyRange(v.mod[1],0.5) then wrong=wrong+1;print('MISMATCH',v.id,result.initial.affixes[1].id) end else rejected=rejected+1 end
  end end
 end
end
print('CATALYST_SWEEP',attempted,accepted,rejected,wrong);assert(attempted>=40 and accepted>=20,'Catalyst sweep did not exercise enough supported items');assert(wrong==0,'Accepted a different modifier identity')
