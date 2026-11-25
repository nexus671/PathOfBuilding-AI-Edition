local directory=assert(arg[1]);arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI");local currency=require("Modules.MapCurrency");local map=require("Modules.MapCraftingData")
local normal={baseId="Metadata/Items/Maps/MapKeyTier16",tier=16,itemLevel=83,rarity="normal",selected={}}
local rare
for seed=100000,200000,1000 do local s=currency.perform(normal,"alchemy",seed).state;if #s.selected==6 then rare=s;break end end
assert(rare,"could not create a six modifier map")
local first=currency.perform(rare,"vaal_add",42).state
assert(#first.selected==8 and first.corrupted)
local before=copyTable(first);local out=currency.perform(first,"temple_add",42)
assert(tableDeepEquals(first,before),"preview mutated its input")
assert(#out.state.selected==9 and out.state.twiceCorrupted and out.state.vaalPreview and out.state.templePreview and out.note:find("unverified",1,true))
for i,id in ipairs(first.selected) do assert(out.state.selected[i]==id) end
for i,roll in ipairs(first.rolls) do assert(tableDeepEquals(out.state.rolls[i],roll)) end
assert(not pcall(currency.perform,out.state,"temple_add",42))
assert(not pcall(currency.perform,rare,"temple_add",42))
local special=copyTable(first);special.plannedDeified=true;assert(not pcall(currency.perform,special,"temple_add",42))
local implicit=currency.perform(rare,"vaal_implicit",42).state;local withImplicit=currency.perform(implicit,"temple_add",42).state
assert(tableDeepEquals(implicit.implicit,withImplicit.implicit),"implicit changed")
newBuild()
local atlas=require("Modules.AtlasPlanner");local draft=copyTable(out.state);draft.id="temple-map";draft.title="Temple map";draft.patch=map.source().patch
local plan={id="temple-plan",title="Temple plan",version="3.30.0-preview",budget=150,nodes={},notes="",mapDrafts={draft}}
local store=atlas.new(build);store:Upsert(plan);local xml={};store:Save(xml);local restored=atlas.new(build);restored:Load(xml)
assert(restored.plans[1].mapDrafts[1].templePreview,"Temple context lost after save and load")
assert(atlas.import(atlas.export(plan)).mapDrafts[1].templePreview,"Temple context lost after export and import")
local invalid=copyTable(draft);invalid.twiceCorrupted=nil;assert(not pcall(atlas.validateMapDraft,invalid),"Invalid Temple preview marker accepted")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
 local draft=copyTable(first);draft.id="second-corruption";draft.title="Map";draft.patch=map.source().patch
 local saved;local c=require("Classes.MapModifierControl").Open({initial=draft,keep=function(v) saved=require("Modules.AtlasPlanner").validateMapDraft(v);return v.id end})
 ui:click("currency");ui:text("search","Temple: +2 modifiers");ui:frame():write(directory.."/"..size[1].."-temple-second-picker.json");ui:click("choose")
 ui:frame():write(directory.."/"..size[1].."-temple-second-result.json");ui:click("keep");assert(saved.twiceCorrupted and saved.templePreview and #saved.selected==9);ui:click("close")
 c=require("Classes.MapModifierControl").Open({initial=saved});assert(c.status.label:find("Hypothetical Temple",1,true));ui:frame():write(directory.."/"..size[1].."-temple-second-reopened.json");ui:click("close")
end
print("Temple second-corruption preview: passed")
