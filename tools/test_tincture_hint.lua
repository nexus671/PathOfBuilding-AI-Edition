return function(build,ui,frame)
	local raw="Item Class: Tinctures\nRarity: MAGIC\nPrismatic Tincture\nItem Level: 85\nQuality: 18\nImplicits: 1\n100% increased Elemental Damage with Melee Weapons\n26% reduced Mana Burn rate\n29% increased Melee Weapon Attack Speed"
	local controls=require("Classes.CraftingSimulatorControl").Open(build,{id="tincture-hint-ui",title="Tincture",slot="Flask 1",startingItem=raw,goals={},steps={}})
	controls.method:SelByValue("chaos","val");controls.method.selFunc()
	local _,height=controls.actionHint:GetSize();local used=0
	for _,row in ipairs(controls.actionHint.list) do used=used+row.height end
	assert(used<=height,"Crafting blocker or tincture warning is clipped")
	assert(controls.apply.tooltipText():find("locally scaled",1,true),"Full tincture warning missing from action tooltip")
	frame("crafting-tincture-blocker");frame("crafting-tincture-blocker-tooltip","apply");ui:click("close")
	local scaled="Item Class: Tinctures\nRarity: MAGIC\nPersevering Prismatic Tincture of Mastery\nPrismatic Tincture\nItem Level: 85\nQuality: 18\nImplicits: 1\n100% increased Elemental Damage with Melee Weapons\n30% reduced Mana Burn rate\n30% increased Melee Weapon Attack Speed"
	local named=require("Classes.CraftingSimulatorControl").Open(build,{id="scaled-tincture-ui",title="Scaled tincture",slot="Flask 1",startingItem=scaled,goals={},steps={}})
	local text="";for _,row in ipairs(named.itemMods.list) do text=text..StripEscapes(row[1] or "").." " end
	assert(text:find("30% increased Melee Weapon Attack Speed",1,true) and text:find("30% reduced Mana Burn rate",1,true),"Scaled tincture display was not retained")
	assert(named.apply.tooltipText():find("locally scaled",1,true),"Scaled tincture warning missing");frame("crafting-tincture-scaled");ui:click("close")
	dofile("../tools/test_combined_fossil_ui.lua")(build,ui,frame)
end
