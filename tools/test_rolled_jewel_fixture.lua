local listings = require("Modules.LootFilterGearListings")

local function target(base, bonus, passiveCount, socketCount)
	local enchants = {"--Adds "..passiveCount.." Passive Skills", "--Added Small Passive Skills grant: "..bonus}
	if socketCount==1 then enchants[#enchants+1]="--1 Added Passive Skill is a Jewel Socket" end
	if socketCount==2 then enchants[#enchants+1]="--2 Added Passive Skills are Jewel Sockets" end
	table.sort(enchants)
	return {base=base,level=84,abyssJewel=false,corrupted=false,fractured=false,synthesised=false,split=false,
		shaper=false,elder=false,adjudicator=false,basilisk=false,crusader=false,eyrie=false,cleansing=false,tangle=false,
		enchantMods=table.concat(enchants,"\0"),implicitMods="",explicitMods="--+3 to maximum Life"}
end

local seed=target("Mycelium Core","",0,0)
seed.blightcore={"Atrophy","Corruption"}
seed.enchantMods="--1 Added Passive Skill is Atrophy\0--1 Added Passive Skill is Corruption"
seed.explicitMods="--Grows four random Passive Skills when Anointed\0--Passive Skills grown are influenced by Oils used when Anointing"
local targets = {
	target("Small Cluster Jewel","4% increased maximum Life",2,0),
	target("Medium Cluster Jewel","12% increased Burning Damage",4,1),
	target("Large Cluster Jewel","12% increased Axe and Sword Damage",8,2),
	seed,
}

for _, item in ipairs(targets) do
	local raw=listings.compareFile(arg[1],item,"Source",nil,true,false)
	local fixture=listings.compareFile(arg[2],item,"Fixture",nil,true,false)
	assert(fixture.matched==6 and fixture.priced==5 and fixture.ambiguous==1,item.base.." did not preserve exact matches")
	local chaos, divine = fixture.results[1], fixture.results[2]
	assert(chaos.sellers==3 and chaos.median==20 and chaos.low==12 and chaos.high==30,item.base.." changed chaos asks")
	assert(divine.sellers==1 and divine.median==nil and divine.low==1.5 and divine.high==1.5,item.base.." changed divine asks")
	for _, key in ipairs({"matched","priced","ambiguous","inspected"}) do assert(fixture[key]==raw[key],key) end
	for _, key in ipairs({"withdrawn","updated","conflicts"}) do assert(fixture.capture[key]==raw.capture[key],key) end
	local recent=listings.compareFile(arg[2],item,"Fixture",nil,true,true)
	assert(recent.results[1].sellers==0 and recent.expiredListings>0,item.base.." fixture was treated as recent")
end
