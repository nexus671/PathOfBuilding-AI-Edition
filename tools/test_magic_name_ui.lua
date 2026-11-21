return function(build,ui,frame)
 local raw="Rarity: MAGIC\nHale Iron Hat\nItem Level: 86\nImplicits: 0\n+6 to maximum Life"
 local c=require("Classes.CraftingSimulatorControl").Open(build,{id="magic-name-ui",title="Named magic",slot="Helmet",startingItem=raw,goals={},steps={}})
 local found=false;for _,row in ipairs(c.actionHint.list) do if row[1]:find("verify the original name",1,true) then found=true end end
 assert(found,"The workbench did not explain its magic-name assumption");frame("crafting-magic-name-warning");ui:click("close")
 local tincture="Item Class: Tinctures\nRarity: MAGIC\nPersevering Prismatic Tincture of Mastery\nPrismatic Tincture\nItem Level: 85\nQuality: 18\nImplicits: 1\n100% increased Elemental Damage with Melee Weapons\n30% reduced Mana Burn rate\n30% increased Melee Weapon Attack Speed"
 c=require("Classes.CraftingSimulatorControl").Open(build,{id="magic-warning-ui",title="Named tincture",slot="Weapon 1",startingItem=tincture,goals={},steps={}})
 local summary=false;for _,row in ipairs(c.actionHint.list) do if row[1]:find("3 item warnings",1,true) then summary=true end end
 assert(summary and c.warningDetails:IsShown(),"Multiple item warnings must remain accessible");frame("crafting-multiple-warnings")
 ui:click("warningDetails");assert(main.popups[1].title=="Crafting item warnings","Warning browser did not open");local labels={};for _,row in ipairs(main.popups[1].controls.results.list) do if row.entry then labels[row.entry.label]=true end end;assert(labels["Magic item name"] and labels["Tincture scaling"] and labels["Outside-tier roll"],"Warning browser omitted an item warning");frame("crafting-warning-details");ui:click("close");ui:click("close")
end
