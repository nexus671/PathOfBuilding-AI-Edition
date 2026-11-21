return function(build,ui,frame)
 local raw="Rarity: MAGIC\nHale Iron Hat\nItem Level: 86\nImplicits: 0\n+6 to maximum Life"
 local c=require("Classes.CraftingSimulatorControl").Open(build,{id="magic-name-ui",title="Named magic",slot="Helmet",startingItem=raw,goals={},steps={}})
 local found=false;for _,row in ipairs(c.actionHint.list) do if row[1]:find("verify the original name",1,true) then found=true end end
 assert(found,"The workbench did not explain its magic-name assumption");frame("crafting-magic-name-warning");ui:click("close")
end
