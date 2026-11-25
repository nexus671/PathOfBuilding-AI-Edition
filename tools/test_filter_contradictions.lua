-- Exercise conservative filter conflict warnings and their native browser.
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local parser=require("Modules.LootFilterParser");local diagnostics=require("Modules.LootFilterDiagnostics")
local filters=require("Modules.LootFilters");local structure=require("Modules.LootFilterStructure")
for _,a in ipairs({">",">=","<","<=","="}) do for _,b in ipairs({">",">=","<","<=","="}) do
 for x=0,3 do for y=0,3 do
  local parsed=parser.parse("Show\n ItemLevel "..a.." "..x.."\n ItemLevel "..b.." "..y)
  local warnings=diagnostics.contradictions(parsed)
  if #warnings>0 then for level=-1,4 do assert(parser.simulate(parsed,{ItemLevel=level}).line~=1,"A reported contradiction matched an item") end end
 end end
end end
for lower=0,3 do for upper=lower,4 do for a=0,4 do for b=0,4 do
 local parsed=parser.parse("Show\n StackSize >= "..lower.."\n StackSize <= "..upper.."\n StackSize != "..a.."\n StackSize != "..b)
 if #diagnostics.contradictions(parsed)>0 then for count=0,5 do assert(parser.simulate(parsed,{StackSize=count}).line~=1,"A reported stack contradiction matched an item") end end
end end end end
assert(#diagnostics.contradictions(parser.parse("Show\n Rarity = Rare\n Rarity >= Unique"))==1,"Disjoint rarity conditions were missed")
assert(#diagnostics.contradictions(parser.parse("Show\n Rarity >= Rare\n Rarity != Unique"))==0,"A valid rarity intersection was flagged")
assert(#diagnostics.contradictions(parser.parse("Show\n Rarity > Unique"))==1,"An empty rarity range was missed")
assert(#diagnostics.contradictions(parser.parse("Show\n ItemLevel > 80\n ItemLevel < 81"))==1,"An empty integer level range was missed")
assert(#diagnostics.contradictions(parser.parse("Show\n StackSize > 5\n StackSize < 6"))==1,"An empty stack-count range was missed")
assert(#diagnostics.contradictions(parser.parse("Show\n StackSize >= 5\n StackSize <= 6\n StackSize != 5"))==0,"A valid stack-count range was flagged")
assert(#diagnostics.contradictions(parser.parse("Show\n StackSize >= 5\n StackSize <= 6\n StackSize != 5\n StackSize != 6"))==1,"Fully excluded stack counts were missed")
assert(#diagnostics.contradictions(parser.parse("Show\n StackSize >= 5\n StackSize <= 7\n StackSize != 5\n StackSize != 6"))==0,"A remaining stack count was missed")
assert(#diagnostics.contradictions(parser.parse("Show\n StackSize >= 5\n StackSize < 6\n StackSize != 5"))==1,"An excluded sole stack count was missed")
assert(#diagnostics.contradictions(parser.parse("Show\n Quality = 20\n Quality != 20"))==1,"An excluded exact value was missed")
assert(#diagnostics.contradictions(parser.parse("Show\n Quality = 20\n Quality != 19"))==0,"A compatible exclusion was flagged")
assert(#diagnostics.contradictions(parser.parse("Show\n AreaLevel > 80\n AreaLevel <= 81"))==0,"A valid integer level range was flagged")
for _,key in ipairs({"MapTier","GemLevel","LinkedSockets","Width","Height","Quality","DropLevel","BaseArmour","BaseEvasion","BaseEnergyShield","BaseWard","EnchantmentPassiveNum","CorruptedMods","HasEaterOfWorldsImplicit","HasSearingExarchImplicit","UnidentifiedItemTier","MemoryStrands"}) do
 assert(#diagnostics.contradictions(parser.parse("Show\n "..key.." > 2\n "..key.." < 3"))==1,key.." empty integer range was missed")
 assert(#diagnostics.contradictions(parser.parse("Show\n "..key.." >= 2\n "..key.." <= 3\n "..key.." != 2"))==0,key.." valid value was flagged")
 assert(#diagnostics.contradictions(parser.parse("Show\n "..key.." >= 2\n "..key.." <= 3\n "..key.." != 2\n "..key.." != 3"))==1,key.." excluded range was missed")
end
assert(#diagnostics.contradictions(parser.parse("Show\n BaseDefencePercentile > 2\n BaseDefencePercentile < 3"))==0,"Fractional percentile was incorrectly flagged")
assert(#diagnostics.contradictions(parser.parse("Show\n Sockets >= 6\n Sockets < 3"))==0,"Special socket semantics were guessed")
local p=filters.profile("contradictory","Conflicting filter");p.template="Show\n MapTier > 10\n MapTier < 11"
local raw,report=filters.compile(p);assert(raw and not report.error,"A warning blocked filter compilation")
local view=structure.outline(p);local warnings=structure.filter(view,"",nil,nil,"Warnings / errors")
assert(#warnings==1 and structure.diagnostics(view,warnings[1])[1].code=="contradictoryConditions","Compiled structure omitted the contradiction")
local UI=require("Modules.HeadlessUI")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
 require("Classes.LootFilterStructureControl").Open(p)
 ui:choose("mode","Warnings / errors");local rows={};for _,row in ipairs(main.popups[1].controls.details.list) do rows[#rows+1]=StripEscapes(row[1] or "") end
 assert(table.concat(rows," "):gsub("%s+"," "):find("MapTier conditions conflict",1,true),"The structure browser did not explain the contradiction")
 if output then ui:frame():write(output.."/"..size[1].."-filter-contradiction.json") end
 ui:restore();main.popups={}
end
print("FILTER_CONTRADICTIONS_OK")
