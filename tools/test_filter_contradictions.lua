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
assert(#diagnostics.contradictions(parser.parse("Show\n Rarity = Rare\n Rarity >= Unique"))==1,"Disjoint rarity conditions were missed")
assert(#diagnostics.contradictions(parser.parse("Show\n Rarity >= Rare\n Rarity != Unique"))==0,"A valid rarity intersection was flagged")
assert(#diagnostics.contradictions(parser.parse("Show\n Rarity > Unique"))==1,"An empty rarity range was missed")
assert(#diagnostics.contradictions(parser.parse("Show\n ItemLevel > 80\n ItemLevel < 81"))==1,"An empty integer level range was missed")
assert(#diagnostics.contradictions(parser.parse("Show\n AreaLevel > 80\n AreaLevel <= 81"))==0,"A valid integer level range was flagged")
assert(#diagnostics.contradictions(parser.parse("Show\n Sockets >= 6\n Sockets < 3"))==0,"Special socket semantics were guessed")
local p=filters.profile("contradictory","Conflicting filter");p.template="Show\n ItemLevel >= 80\n ItemLevel < 70"
local raw,report=filters.compile(p);assert(raw and not report.error,"A warning blocked filter compilation")
local view=structure.outline(p);local warnings=structure.filter(view,"",nil,nil,"Warnings / errors")
assert(#warnings==1 and structure.diagnostics(view,warnings[1])[1].code=="contradictoryConditions","Compiled structure omitted the contradiction")
local UI=require("Modules.HeadlessUI")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
 require("Classes.LootFilterStructureControl").Open(p)
 ui:choose("mode","Warnings / errors");local rows={};for _,row in ipairs(main.popups[1].controls.details.list) do rows[#rows+1]=StripEscapes(row[1] or "") end
 assert(table.concat(rows," "):gsub("%s+"," "):find("ItemLevel conditions conflict",1,true),"The structure browser did not explain the contradiction")
 if output then ui:frame():write(output.."/"..size[1].."-filter-contradiction.json") end
 ui:restore();main.popups={}
end
print("FILTER_CONTRADICTIONS_OK")
