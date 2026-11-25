-- Group copied equipment by native base and rarity; no stash access.
local M={maxBytes=4*1024*1024}
local kinds={Helmet=true,['Body Armour']=true,Gloves=true,Boots=true,Shield=true,Quiver=true,Amulet=true,Ring=true,Belt=true,Jewel=true,Flask=true,Tincture=true}
local rarities={'NORMAL','MAGIC','RARE','UNIQUE'}
function M.parse(raw)
 assert(type(raw)=='string' and #raw>0 and #raw<=24000 and not raw:find('%z'),'Paste one copied item up to 24 KiB')
 raw=raw:gsub('\r\n','\n'):gsub('\r','\n')
 local rarity=raw:match('^Rarity:%s*(%a+)') or raw:match('\nRarity:%s*(%a+)')
 rarity=rarity and rarity:upper();assert(rarity=='NORMAL' or rarity=='MAGIC' or rarity=='RARE' or rarity=='UNIQUE','Copy a normal, magic, rare or unique item')
 assert(raw:find('\n--------',1,true),'Copy the complete item including its separator')
 local ok,item=pcall(function() return new('Item'):Item(raw) end)
 assert(ok and item.base and item.baseName and item.rarity==rarity,'The copied item base could not be identified')
 assert(kinds[item.type] or data.weaponTypeInfo[item.type],'Only supported equipment and jewel bases can be reviewed')
 local header=raw:match('Rarity:%s*%a+\n(.-)\n%-%-%-%-%-%-%-%-') or ''
 local names={};for line in header:gmatch('[^\n]+') do names[#names+1]=line end
 assert(#names>0 and #names<=2,'The copied item header is incomplete or ambiguous')
 for _,name in ipairs(names) do assert(#name<=160 and not name:find('[%c%^]'),'Invalid copied item name') end
 if (rarity=='RARE' or rarity=='UNIQUE') and not raw:find('\nUnidentified',1,true) then assert(#names==2,'Copy the item name and base') end
 local displayBase=item.baseName:find('^Two%-Toned Boots %(') and 'Two-Toned Boots' or item.baseName
 local visible=names[#names];local first,last=visible:find(displayBase,1,true)
 assert(first and (first==1 or visible:sub(first-1,first-1)==' ') and (last==#visible or visible:sub(last+1,last+1)==' '),'The copied base is ambiguous')
 if rarity=='RARE' or rarity=='UNIQUE' then assert(visible==displayBase,'The copied base is ambiguous') end
 local class=raw:match('^Item Class:%s*([^\n]+)') or raw:match('\nItem Class:%s*([^\n]+)')
 local knownClass=require('Modules.LootFilterLibrary').baseClass(displayBase)
 assert(not class or not knownClass or class==knownClass,'The copied item class does not match its base')
 if item.baseName:find('Two%-Toned Boots') then
  local armour=raw:find('\nArmour:',1,true)~=nil;local evasion=raw:find('\nEvasion Rating:',1,true)~=nil;local energy=raw:find('\nEnergy Shield:',1,true)~=nil
  local variant=armour and evasion and not energy and 'Armour/Evasion' or armour and energy and not evasion and 'Armour/Energy Shield' or evasion and energy and not armour and 'Evasion/Energy Shield'
  assert(variant and item.baseName=='Two-Toned Boots ('..variant..')','Include both defence properties to distinguish the Two-Toned Boots base')
 end
 return {base=item.baseName,kind=item.type,rarity=rarity,name=names[1]}
end
function M.review(items)
 assert(type(items)=='table','Supply copied items');local groups,bytes={},0
 for index,raw in ipairs(items) do
  assert(type(raw)=='string','Item '..index..' must be copied item text');bytes=bytes+#raw;assert(bytes<=M.maxBytes,'Copied items exceed the 4 MiB review limit')
 end
 for index,raw in ipairs(items) do
  local ok,item=pcall(M.parse,raw);assert(ok,'Item '..index..': '..tostring(item))
  local key=item.kind..'\0'..item.base;local group=groups[key] or {base=item.base,kind=item.kind,counts={NORMAL=0,MAGIC=0,RARE=0,UNIQUE=0},items={}}
  group.counts[item.rarity]=group.counts[item.rarity]+1;group.items[#group.items+1]={index=index,rarity=item.rarity,name=item.name};groups[key]=group
 end
 local result={};for _,group in pairs(groups) do
  group.sets=math.min(group.counts.NORMAL,group.counts.MAGIC,group.counts.RARE,group.counts.UNIQUE);group.missing={};group.remaining={};local leftovers=0
  for _,rarity in ipairs(rarities) do group.remaining[rarity]=group.counts[rarity]-group.sets;leftovers=leftovers+group.remaining[rarity] end
  if leftovers>0 then for _,rarity in ipairs(rarities) do if group.remaining[rarity]==0 then group.missing[#group.missing+1]=rarity end end end
  result[#result+1]=group
 end
 table.sort(result,function(a,b) if a.sets~=b.sets then return a.sets>b.sets end;if a.base~=b.base then return a.base<b.base end;return a.kind<b.kind end)
 return {groups=result,totalItems=#items,note='Possible one Orb of Chance per set. Base identification and item eligibility need verification; each paste must be a different item. Other vendor reviews can use the same items. Check the actual vendor offer. No stash is read.'}
end
return M
