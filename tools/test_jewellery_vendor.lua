local output=arg[1];arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true
local vendor=require('Modules.VendorQualitySets')
local function item(class,base,qualityType,value,rarity)
 return 'Item Class: '..class..'\nRarity: '..(rarity or 'Rare')..'\n'..((rarity=='Normal') and '' or 'Example Name\n')..base..'\n--------\nQuality'..(qualityType and ' ('..qualityType..' Modifiers)' or '')..': +'..value..'% (augmented)\n--------\nItem Level: 80'
end
local inputs={item('Rings','Gold Ring','Attribute',20),item('Amulets','Jade Amulet','Attribute',20),item('Belts','Leather Belt','Resistance',20),item('Rings','Iron Ring','Resistance',20),item('Rings','Iron Ring',nil,20)}
local review=vendor.review(inputs);assert(#review.categories==7,'Unexpected number of quality categories')
local byName={};for _,category in ipairs(review.categories) do byName[category.name]=category end
local attributes=assert(byName['Jewellery: Attribute']);local resist=assert(byName['Jewellery: Resistance']);local unknown=assert(byName['Jewellery: unknown quality type'])
assert(#attributes.groups==1 and attributes.groups[1].quality==40 and attributes.reward=='Random Catalyst' and attributes.items[1].category==attributes.name)
assert(#resist.groups==1 and resist.groups[1].quality==40 and resist.groups[1].items[1].qualityType=='Resistance')
assert(#unknown.groups==0 and #unknown.leftover==1 and not unknown.optimal,'Unknown jewellery type was grouped')
local mixed=vendor.review({inputs[1],inputs[3]});assert(#mixed.categories[5].groups==0 and #mixed.categories[6].groups==0,'Different quality types were combined')
local normal=vendor.review({item('Rings','Iron Ring','Attack',20,'Normal')});local category=normal.categories[5];assert(not category.optimal and #category.groups==0,'Unverified single jewellery offer was treated as proven')
local unknownName=vendor.review({item('Rings','Iron Ring','Unknown',20),item('Rings','Iron Ring','Unknown',20)});assert(#unknownName.categories[5].groups==0,'Unrecognized quality types were grouped')
for _,size in ipairs({{960,640},{1024,768},{1280,720}}) do
 newBuild();main.popups={};local ui=require('Modules.HeadlessUI').install({width=size[1],height=size[2]});ui:bind(build);build.planningVendorQualityItems=inputs
 local c=require('Classes.VendorQualitySetsControl').Open(build);local lines={};for _,row in ipairs(c.details.list) do lines[#lines+1]=row[1] or '' end;local text=table.concat(lines,' ')
 assert(text:find('Jewellery: Attribute',1,true) and text:find('Random Catalyst',1,true) and text:find('Unknown catalyst quality type',1,true),'Jewellery groups not displayed')
 if output then ui:frame():write(output..'/'..size[1]..'-jewellery-vendor.json') end
 main.popups={};local saved;local panel=require('Classes.LootFilterCampaignControl').Open(build,nil,function(value) saved=value end,'Normal')
 if panel.page then ui:click('pageRecipes') end;ui:click('recipe11');if output then ui:frame():write(output..'/'..size[1]..'-jewellery-filter-policy.json') end;ui:click('keep')
 assert(saved and saved.recipes[1]=='Quality jewellery','Quality jewellery pickup was not saved')
 local filters=require('Modules.LootFilters');local p=filters.profile('jewel-quality','Jewellery','campaign');p.template='Hide';p.campaign=saved
 local sample={Class='Rings',BaseType='Gold Ring',Rarity='Rare',Quality=20,AreaLevel=40}
 local shown=filters.simulate(p,sample);assert(shown.action=='Show' and shown.ruleTitle:find('Quality jewellery',1,true),'Quality jewellery did not match its filter policy')
 sample.Quality=0;assert(filters.simulate(p,sample).action=='Hide','Zero-quality jewellery was highlighted')
 ui:restore();main.popups={}
end
print('JEWELLERY_VENDOR_OK')
