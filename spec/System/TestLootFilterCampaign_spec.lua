describe("Offline campaign pickup policies",function()
	local campaign=require("Modules.LootFilterCampaign")
	local filters=require("Modules.LootFilters")
	local function profile() local p=filters.profile("campaign","Campaign","campaign");p.template="Hide";p.campaign=campaign.defaults();return p end
	before_each(function() newBuild();main.popups={} end)
	it("separates weapon subtypes and all native defence combinations",function()
		assert.equal("Rune Dagger",campaign.weapon({type="Dagger",subType="Rune Dagger",weapon={}}));assert.equal("Dagger",campaign.weapon({type="Dagger",weapon={}}))
		assert.equal("Warstaff",campaign.weapon({type="Staff",subType="Warstaff",weapon={}}));assert.equal("Thrusting Sword",campaign.weapon({type="One Handed Sword",subType="Thrusting",weapon={}}))
		assert.equal("Armour / Energy shield",campaign.defence({type="Helmet",armour={ArmourBaseMin=1,EnergyShieldBaseMin=1}}));assert.equal("Ward",campaign.defence({type="Helmet",armour={WardBaseMin=1}}))
		assert.is_true(#campaign.families().weapons.Bow>0);assert.is_true(#campaign.families().defences.Ward>0)
	end)
	it("shows selected families in progressive area bands and retains personal priority",function()
		local p=profile();p.campaign.weapons={"Bow"};local name=campaign.families().weapons.Bow[1]
		local item={BaseType=name,AreaLevel=40,DropLevel=35,Rarity="Normal",LinkedSockets=0}
		assert.equal("Show",filters.simulate(p,item).action);item.DropLevel=1;assert.equal("Hide",filters.simulate(p,item).action)
		item.DropLevel=35;item.AreaLevel=71;assert.equal("Hide",filters.simulate(p,item).action)
		item.AreaLevel=40;p.rules={{id="mine",title="Personal exception",text='Hide\n BaseType == '..filters.quote(name)}};assert.equal("Hide",filters.simulate(p,item).action)
		p.rules={};p.campaign.enabled=false;assert.equal("Hide",filters.simulate(p,item).action)
	end)
	it("keeps recipe pickups independent of base-upgrade thresholds and validates policy bounds",function()
		local p=profile();p.campaign.recipes={"Three-colour linked equipment"};p.campaign.minDropLevel=90;p.campaign.minLinks=6
		assert.equal("Show",filters.simulate(p,{BaseType="Iron Hat",AreaLevel=40,Rarity="Normal",SocketGroup="RGB",DropLevel=1,LinkedSockets=3}).action)
		p.campaign.weapons={"Bow"};p.campaign.upgradeWindow=0;assert.equal(2,#campaign.rules(p.campaign))
		assert.has_error(function() campaign.validate({weapons={"Imaginary"}}) end);assert.has_error(function() campaign.validate({minAreaLevel=70,maxAreaLevel=1}) end)
		assert.has_error(function() campaign.validate({weapons={"Bow","Bow"}}) end)
	end)
	it("shows unidentified full-set candidates with distinct item-level bands in normal mode",function()
		local p=profile();p.campaign.recipes={"Unidentified rare set pieces"};p.campaign.maxAreaLevel=100
		local item={Class="Rings",BaseType="Iron Ring",AreaLevel=75,ItemLevel=60,Rarity="Rare",Identified=false}
		local result=filters.simulate(p,item);assert.equal("Show",result.action);assert.same({"245","190","65","255"},result.styles.SetBorderColor)
		item.ItemLevel=74;assert.same({"245","190","65","255"},filters.simulate(p,item).styles.SetBorderColor)
		item.ItemLevel=75;assert.same({"100","160","230","255"},filters.simulate(p,item).styles.SetBorderColor)
		item.ItemLevel=59;assert.equal("Hide",filters.simulate(p,item).action)
		item.ItemLevel=60;item.Identified=true;assert.equal("Hide",filters.simulate(p,item).action)
		item.Identified=false;item.Rarity="Magic";assert.equal("Hide",filters.simulate(p,item).action)
		item.Rarity="Rare";item.Class="Quivers";assert.equal("Hide",filters.simulate(p,item).action)
		item.Class="Rings";item.ItemLevel=nil;assert.equal("unknown",filters.simulate(p,item).status)
		p.mode="Ruthless";item.ItemLevel=60;assert.equal("Minimal",filters.simulate(p,item).action)
		assert.equal(0,#campaign.rules(p.campaign,nil,"Ruthless"));assert.equal(2,#campaign.rules(p.campaign,nil,"Normal"))
	end)
	it("filters rare-set pickups to the selected slot groups and restores old defaults",function()
		local old=campaign.validate({recipes={"Unidentified rare set pieces"}});assert.same(campaign.rareSetSlots,old.rareSetSlots)
		local p=profile();p.campaign.recipes={"Unidentified rare set pieces"};p.campaign.rareSetSlots={"Jewellery"};p.campaign.maxAreaLevel=100
		local item={Class="Rings",BaseType="Iron Ring",AreaLevel=75,ItemLevel=70,Rarity="Rare",Identified=false}
		assert.equal("Show",filters.simulate(p,item).action);item.Class="Helmets";item.BaseType="Iron Hat";assert.equal("Hide",filters.simulate(p,item).action)
		item.Class="One Hand Swords";item.BaseType="Rusted Sword";assert.equal("Hide",filters.simulate(p,item).action)
		p.campaign.rareSetSlots={"Weapons and shields"};assert.equal("Show",filters.simulate(p,item).action)
		item.Class="Rings";item.BaseType="Iron Ring";assert.equal("Hide",filters.simulate(p,item).action)
		assert.has_error(function() campaign.validate({rareSetSlots={}}) end)
		assert.has_error(function() campaign.validate({rareSetSlots={"Jewellery","Jewellery"}}) end)
	end)
	it("uses the active weapon set and skips inactive equipment",function()
		local fake={itemsTab={activeItemSet={useSecondWeaponSet=true},items={
			[1]={base={type="Bow",weapon={}}},[2]={base={type="Wand",weapon={}}},
			[3]={base={type="Shield",armour={ArmourBaseMin=1}}},[4]={base={type="Helmet",armour={EvasionBaseMin=1}}},
		},slots={
			first={selItemId=1,weaponSet=1},second={selItemId=2,weaponSet=2},
			shield={selItemId=3,weaponSet=2},inactive={selItemId=4,inactive=true},
		}}}
		local equipped=campaign.equipped(fake)
		assert.same({"Wand","Shield"},equipped.weapons);assert.same({"Armour"},equipped.defences)
		fake.itemsTab.activeItemSet.useSecondWeaponSet=false
		equipped=campaign.equipped(fake);assert.same({"Bow"},equipped.weapons);assert.same({},equipped.defences)
	end)
	it("keeps recipe selections when choosing equipped families",function()
		local policy=campaign.defaults();policy.recipes={"Quality gems"};local kept
		local controls=require("Classes.LootFilterCampaignControl").Open(build,policy,function(value) kept=value end)
		controls.equipped:Click();controls.keep:Click()
		assert.same({"Quality gems"},kept.recipes)
	end)
	it("preserves but disables a normal-mode rare-set choice in Ruthless",function()
		local policy=campaign.defaults();policy.recipes={"Unidentified rare set pieces"};local kept
		local controls=require("Classes.LootFilterCampaignControl").Open(build,policy,function(value) kept=value end,"Ruthless")
		assert.is_false(controls.recipe5:IsEnabled());assert.matches("not been verified",controls.recipe5.tooltipText)
		controls.keep:Click();assert.same(policy.recipes,kept.recipes);assert.equal(0,#campaign.rules(kept,nil,"Ruthless"))
	end)
	it("explains the rare-set color bands when selected",function()
		local controls=require("Classes.LootFilterCampaignControl").Open(build,nil,function() end,"Normal")
		controls.recipe5:Click();local summary="";for _,row in ipairs(controls.summary.list) do summary=summary..StripEscapes(row[1] or "").." " end
		assert.matches("60%-74",summary);assert.matches("gold",summary);controls.close:Click()
	end)
	it("keeps selected rare-set slot groups through the dialog",function()
		local kept;local controls=require("Classes.LootFilterCampaignControl").Open(build,nil,function(value) kept=value end,"Normal")
		controls.recipe5:Click();controls.rareSetSlots:Click();local popup=main.popups[1].controls
		popup.slot2:Click();popup.slot3:Click();popup.keep:Click();controls.keep:Click()
		assert.same({"Jewellery"},kept.rareSetSlots);assert.same({"Unidentified rare set pieces"},kept.recipes)
	end)
	it("keeps every selectable family within the export budget and round-trips policy metadata",function()
		local p=profile();p.campaign.weapons=copyTable(campaign.weapons);p.campaign.defences=copyTable(campaign.defences);p.campaign.recipes=copyTable(campaign.recipes)
		local raw,report=filters.compile(p);assert.is_true(#raw<filters.limit);for _,d in ipairs(report.diagnostics) do assert.is_nil(d.error,d.error) end
		build.savers.LootFilters:Upsert(p);local xml={};build.savers.LootFilters:Save(xml);local restored=filters.new(build);restored:Load(xml);assert.same(p.campaign,restored.data.profiles[1].campaign)
	end)
	it("accepts digits in every campaign level and link field through native input",function()
		local ui=require("Modules.HeadlessUI").install({width=1024,height=768});local kept
		local ok,err=pcall(function()
			require("Classes.LootFilterCampaignControl").Open(build,nil,function(value) kept=value end)
			for key,value in pairs({minAreaLevel=10,maxAreaLevel=60,minDropLevel=10,minLinks=2,upgradeWindow=20}) do ui:text(key,tostring(value)) end
			ui:click("keep");assert.equal(10,kept.minAreaLevel);assert.equal(60,kept.maxAreaLevel);assert.equal(10,kept.minDropLevel);assert.equal(2,kept.minLinks);assert.equal(20,kept.upgradeWindow)
		end)
		ui:restore();main.popups={};assert.is_true(ok,err)
	end)
end)
