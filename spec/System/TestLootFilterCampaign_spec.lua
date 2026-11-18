-- cspell:ignore RGBRRR
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
	it("shows socket vendor recipes for every rarity and prioritizes the highest socket recipe",function()
		local p=profile();p.campaign.recipes={"Three-colour linked equipment","Six-socket equipment","Six-link equipment"}
		for _,rarity in ipairs({"Normal","Magic","Rare","Unique"}) do
			local item={BaseType="Iron Hat",AreaLevel=40,Rarity=rarity,Sockets=6,LinkedSockets=6,SocketGroup="RGBRRR"}
			local result=filters.simulate(p,item);assert.equal("Show",result.action);assert.matches("Six%-link equipment",result.ruleTitle)
			item.LinkedSockets=3;item.SocketGroup="RGB R R R";result=filters.simulate(p,item);assert.matches("Six%-socket equipment",result.ruleTitle)
			item.Sockets=3;item.SocketGroup="RGB";result=filters.simulate(p,item);assert.matches("Three%-colour linked equipment",result.ruleTitle)
		end
		local rules=campaign.rules(p.campaign);assert.equal("campaign-recipe-3",rules[1].id);assert.equal("campaign-recipe-2",rules[2].id);assert.equal("campaign-recipe-1",rules[3].id)
	end)
	it("chooses a policy preview base that satisfies the displayed drop-level band",function()
		local p=profile();p.campaign.weapons={"Bow"};p.campaign.minAreaLevel=50;p.campaign.maxAreaLevel=54;p.campaign.upgradeWindow=15
		local entries=require("Modules.LootFilterLibrary").campaign(p);assert.equal(1,#entries)
		local entry=entries[1];assert.is_true(entry.sample.DropLevel>=35)
		local result=require("Modules.LootFilterParser").simulate(require("Modules.LootFilterParser").parse(entry.rule.text),entry.sample)
		assert.equal("matched",result.status);assert.equal("Show",result.action)
		local sample=require("Modules.LootFilterLibrary").sample({text='Show\n BaseType == "Crude Bow" "Assassin Bow"\n DropLevel >= 35'})
		assert.equal("Assassin Bow",sample.BaseType);assert.equal(62,sample.DropLevel)
	end)
	it("prioritizes recipe pickups over matching equipment families",function()
		local p=profile();p.campaign.weapons={"Bow"};p.campaign.recipes={"Six-link equipment"}
		local item={BaseType=campaign.families().weapons.Bow[1],AreaLevel=40,DropLevel=35,Rarity="Rare",Sockets=6,LinkedSockets=6}
		local result=filters.simulate(p,item);assert.equal("Show",result.action);assert.matches("Six%-link equipment",result.ruleTitle)
		item.LinkedSockets=5;result=filters.simulate(p,item);assert.matches("Bow / areas",result.ruleTitle,1,true)
		p.rules={{id="mine",title="Personal exception",text='Hide\n BaseType == '..filters.quote(item.BaseType)}}
		item.LinkedSockets=6;assert.equal("Hide",filters.simulate(p,item).action)
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
	it("offers optional low-level rare-set pickups without changing existing policies",function()
		local p=profile();p.campaign.recipes={"Low-level unidentified rare set pieces"};p.campaign.maxAreaLevel=100;p.campaign.rareSetSlots={"Jewellery"}
		local item={Class="Rings",BaseType="Iron Ring",AreaLevel=50,ItemLevel=59,Rarity="Rare",Identified=false}
		local result=filters.simulate(p,item);assert.equal("Show",result.action);assert.same({"180","130","245","255"},result.styles.SetBorderColor)
		item.ItemLevel=60;assert.equal("Hide",filters.simulate(p,item).action)
		item.ItemLevel=59;item.Identified=true;assert.equal("Hide",filters.simulate(p,item).action)
		item.Identified=false;item.Class="Helmets";assert.equal("Hide",filters.simulate(p,item).action)
		item.Class="Rings";p.mode="Ruthless";assert.equal("Minimal",filters.simulate(p,item).action)
		local kept;local c=require("Classes.LootFilterCampaignControl").Open(build,p.campaign,function(value) kept=value end,"Normal")
		assert.is_true(c.rareSetSlots:IsEnabled());c.keep:Click();assert.same({"Low-level unidentified rare set pieces"},kept.recipes)
		c=require("Classes.LootFilterCampaignControl").Open(build,p.campaign,function() end,"Ruthless");assert.is_false(c.recipe6:IsEnabled());assert.is_false(c.rareSetSlots:IsEnabled());c.close:Click()
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
		assert.matches("60%-74",summary);assert.matches("Gold",summary);controls.close:Click()
	end)
	it("keeps selected rare-set slot groups through the dialog",function()
		local kept;local controls=require("Classes.LootFilterCampaignControl").Open(build,nil,function(value) kept=value end,"Normal")
		controls.recipe5:Click();controls.rareSetSlots:Click();local popup=main.popups[1].controls
		popup.slot2:Click();popup.slot3:Click();popup.keep:Click();controls.keep:Click()
		assert.same({"Jewellery"},kept.rareSetSlots);assert.same({"Unidentified rare set pieces"},kept.recipes)
	end)
	it("explains invalid values and preserves edits until corrected",function()
		local kept,message;local original=main.OpenMessagePopup
		main.OpenMessagePopup=function(_,title,text) message={title,text} end
		local ok,err=pcall(function()
			local controls=require("Classes.LootFilterCampaignControl").Open(build,nil,function(value) kept=value end,"Normal")
			controls.recipe5:Click();controls.minAreaLevel:SetText("80");controls.maxAreaLevel:SetText("70");controls.keep:Click()
			assert.is_nil(kept);assert.same({"Check pickup policy","From area cannot exceed Through area."},message)
			controls.minLinks:SetText("7");controls.keep:Click();assert.matches("Minimum links must be between 0 and 6",message[2])
			controls.minLinks:SetText("2");controls.maxAreaLevel:SetText("100");controls.keep:Click()
			assert.equal(80,kept.minAreaLevel);assert.equal(100,kept.maxAreaLevel);assert.same({"Unidentified rare set pieces"},kept.recipes)
		end)
		main.OpenMessagePopup=original;assert.is_true(ok,err)
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
