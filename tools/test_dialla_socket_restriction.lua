arg={};dofile('HeadlessWrapper.lua');newBuild()
local q=require('Modules.CraftingUniqueQuality');local sim=require('Modules.CraftingSimulator')
local raw="Rarity: UNIQUE\nDialla's Malefaction\nSage's Robe\nItem Level: 86\nSockets: R-G-B"
local function blocked(reason) assert(reason and reason:find('no%-white%-socket'),reason) end
blocked(q.whiteReason(raw));blocked(q.socketCountReason(raw,4));blocked(q.omenReason(raw));blocked(q.randomSocketReason(raw,'jeweller'));blocked(q.colourReason(raw,'chromatic'))
assert(not q.socketCountReason(raw,2));assert(not q.colourReason(raw,'omen_trichromatism'));assert(q.socketCount(raw,2).itemText:find('Sockets: R%-G'));assert(not sim.perform(raw,{method='omen_trichromatism'},1).itemText:match('Sockets: [^\n]*W'))
local corrupted=raw..'\nCorrupted';blocked(q.randomSocketReason(corrupted,'tainted_jeweller'));blocked(q.colourReason(corrupted,'tainted_chromatic'));blocked(q.whiteReason(corrupted))
assert(not pcall(sim.perform,raw,{method='socket_white_bench'},1));assert(not pcall(sim.perform,raw,{method='omen_jeweller'},1));assert(not pcall(sim.perform,raw,{method='chromatic'},1))
local legacy=raw:gsub('R%-G%-B','R-G-W');assert(not q.whiteReason(legacy));assert(not q.socketCountReason(legacy,4));assert(not q.colourReason(legacy,'chromatic'));assert(not q.randomSocketReason(legacy,'jeweller'))
local other=raw:gsub("Dialla's Malefaction",'Other Armour');assert(not q.whiteReason(other));assert(not q.socketCountReason(other,4))
print('DIALLA_SOCKET_RESTRICTION_OK')
