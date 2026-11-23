local parser=require('Modules.LootFilterParser');local protected=require('Modules.LootFilterProtectedDrops');local refresh=require('Modules.LootFilterBaseRefresh');local validate=require('Modules.LootFilterSyncValidation')
local raw=[[Show
 BaseType == "Cord Belt" "Agate Amulet"
 MinimapIcon 0 Purple Star
Show
 BaseType == "Royal Plate"
 MinimapIcon 0 Red Diamond
Show
 BaseType == "Iron Ring"
 MinimapIcon 0 Yellow Diamond
# PoB economy: begin
Hide
 Class == "Stackable Currency"
 BaseType == "Orb of Alteration"
 StackSize <= 6
# PoB economy: end
Show
]]
assert(validate(raw,{},true,1))
local candidate='Hide\n BaseType == "Cord Belt"\n Width >= 2\n'..raw;local ok,why=pcall(validate,candidate,{},true,1);assert(not ok and why:find('Protected drop failed',1,true),tostring(why))
local uncertain='Hide\n Rarity == Unique\n DropLevel >= 1\n'..raw;local certain,reason=pcall(validate,uncertain,{},true,1);assert(not certain and reason:find('Missing DropLevel',1,true),tostring(reason))
local uncertainDefence='Hide\n Rarity == Unique\n BaseDefencePercentile >= 50\n'..raw;local certainDefence,defenceReason=pcall(validate,uncertainDefence,{},true,1);assert(not certainDefence and defenceReason:find('Missing BaseDefencePercentile',1,true),tostring(defenceReason))
local report=refresh.evaluate(parser.parse(raw),parser.parse(candidate),{});assert(#report.blocks>0,'base refresh missed protected width change')
local unknown='Hide\n DropLevel >= 80\n'..raw;local report2=refresh.evaluate(parser.parse(unknown),parser.parse(raw),{});assert(#report2.warnings>0,'unknown baseline not reported')
local seen={};for _,entry in ipairs(protected.samples()) do local item=entry.item;if item.BaseType=='Cord Belt' then assert(item.Width==2 and item.Height==1);if item.Rarity=='Unique' then assert(item.DropLevel==nil and item.BaseDefencePercentile==nil) else assert(item.DropLevel==75 and item.BaseDefencePercentile==100) end end;if item.BaseType=='Royal Plate' then assert(item.Width==2 and item.Height==3 and item.ItemLevel==85);if item.Rarity~='Unique' then assert(item.DropLevel==84 and item.BaseDefencePercentile==0) end end;seen[item.BaseType]=true end;assert(seen['Cord Belt'] and seen['Royal Plate']);print('PROTECTED_SAMPLE_REGRESSION_OK')
local impact=[[Show
 BaseType == "Cord Belt"
# PoB economy: begin
Hide
 Class == "Stackable Currency"
 BaseType == "Orb of Alteration"
 StackSize <= 6
# PoB economy: end
Show
 BaseType == "Orb of Alteration"
 DropLevel == 2
Hide
]]
local body='{"core":{"primary":"chaos"},"items":[{"id":"alt","name":"Orb of Alteration"}],"lines":[{"id":"alt","primaryValue":0.21,"volumePrimaryValue":1000}]}'
local bodies={};for index in ipairs(require('Modules.LootFilterEconomy').categories) do bodies[index]=body end
local _,count,changes=validate(impact,bodies,false,1,{{BaseType='Cord Belt',Rarity='Magic'}});assert(count==1 and changes[1].sample.before=='Hide' and changes[1].sample.action=='Show','Economy impact did not use the base drop level')
local levelImpact=impact:gsub('DropLevel == 2','ItemLevel >= 84');local _,levelCount,levelChanges=validate(levelImpact,bodies,false,1,{{BaseType='Cord Belt',Rarity='Magic'}});assert(levelCount==1 and levelChanges[1].sample.action=='Unknown' and levelChanges[1].sample.afterMissing[1]=='ItemLevel','An unknown item level was not explained')
local early='Show\n BaseType == "Orb of Alteration"\n ItemLevel >= 84\n'..levelImpact;local _,_,earlyChanges=validate(early,bodies,false,1,{{BaseType='Cord Belt',Rarity='Magic'}});assert(earlyChanges[1].sample.before=='Unknown' and earlyChanges[1].sample.beforeMissing[1]=='ItemLevel','Previous uncertainty was not retained')
local missing=parser.safeMissingProperties({'ItemLevel','ItemLevel','C:/private/filter','DropLevel','UnknownPrivateName'});assert(#missing==2 and missing[1]=='ItemLevel' and missing[2]=='DropLevel','Missing-property sanitization failed')
print('ECONOMY_IMPACT_METADATA_OK')
