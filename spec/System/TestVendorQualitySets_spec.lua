describe("Quality vendor review",function()
	local vendor=require("Modules.VendorQualitySets")
	local function item(class,rarity,base,quality)
		return "Item Class: "..class.."\nRarity: "..rarity.."\n"..(rarity=="Normal" and base or "Example Item\n"..base).."\n--------\nQuality: +"..quality.."% (augmented)"
	end
	it("groups copied weapons and armour independently and retains leftovers",function()
		local source={item("Wands","Normal","Driftwood Wand",20),item("Wands","Magic","Driftwood Wand",18),item("Bows","Rare","Crude Bow",14),item("Wands","Normal","Driftwood Wand",9),item("Helmets","Normal","Iron Hat",12),item("Shields","Magic","Twig Spirit Shield",18),item("Boots","Rare","Wool Shoes",10),item("Helmets","Rare","Iron Hat",5)}
		local review=vendor.review(source);assert.equal(8,review.totalItems);assert.equal(2,#review.categories[1].groups);assert.equal(1,#review.categories[2].groups)
		assert.is_true(review.categories[1].groups[1].single);assert.equal(41,review.categories[1].groups[2].quality);assert.equal(40,review.categories[2].groups[1].quality)
		assert.equal(1,#review.categories[2].leftover);assert.equal(8,review.categories[2].leftover[1].index);assert.is_true(review.categories[1].optimal);assert.is_true(review.categories[2].optimal)
		assert.equal(8,#source)
	end)
	it("rejects unsupported or malformed copies instead of inventing quality",function()
		assert.has_error(function() vendor.parse(item("Rings","Normal","Iron Ring",20)) end)
		assert.has_error(function() vendor.parse(item("Wands","Normal","Driftwood Wand",0)) end)
		assert.has_error(function() vendor.parse(item("Wands","Normal","Driftwood Wand",10).."\nQuality: +15%") end)
		assert.has_error(function() vendor.review({[2]=item("Wands","Normal","Driftwood Wand",20)}) end)
		assert.has_error(function() vendor.parse("Item Class: Wands\nRarity: Gem\nDriftwood Wand\nQuality: +20%") end)
		assert.has_error(function() vendor.parse("Item Class: Skill Gems\nRarity: Normal\nArc\nQuality: +20%") end)
	end)
	it("separates flask and tincture groups from gems and handles 20% gems",function()
		local gem=function(name,q) return "Item Class: Skill Gems\nRarity: Gem\n"..name.."\n--------\nQuality: +"..q.."%" end
		local copies={item("Life Flasks","Normal","Small Life Flask",20),item("Life Flasks","Magic","Small Life Flask",18),item("Tinctures","Magic","Prismatic Tincture",12),item("Utility Flasks","Magic","Quicksilver Flask",10),gem("Arc",20),gem("Frostbolt",18),gem("Fireball",13),gem("Spark",9),gem("Ice Nova",21)}
		local review=vendor.review(copies);local flasks,gems=review.categories[3],review.categories[4]
		assert.equal(2,#flasks.groups);assert.equal("normal",flasks.groups[1].singleKind);assert.equal(40,flasks.groups[2].quality)
		assert.equal(2,#gems.groups);assert.equal("gem",gems.groups[1].singleKind);assert.equal(20,gems.groups[1].quality);assert.equal(1,#gems.leftover)
		assert.is_true(flasks.optimal);assert.is_false(gems.optimal);assert.is_true(gems.eligibilityUncertain)
	end)
	it("reviews Vaal Orb groups without inventing missing quality",function()
		local function gem(extra) return "Item Class: Active Skill Gems\nRarity: Gem\nVaal Arc\n--------\n"..(extra or "") end
		local items={gem(),gem(),gem(),gem(),gem("Quality: +20%"),gem("Quality: +0%")}
		local review=vendor.review(items);assert.equal(6,review.vaal.count);assert.equal(1,#review.vaal.groups);assert.equal(1,#review.vaal.remaining)
		assert.equal(5,review.vaal.groups[1].items[5].index);assert.equal(5,review.categories[4].groups[1].items[1].index)
		assert.equal(4,#review.categories[4].unknownQuality);assert.equal(1,#review.categories[4].zeroQuality);assert.is_false(review.categories[4].optimal)
		assert.matches("may use the same items",review.note);assert.matches("Ruthless eligibility is unverified",review.note)
		assert.has_error(function() vendor.parse("Item Class: Active Skill Gems\nRarity: Gem\nVaal Imaginary Spell\n--------") end)
		assert.has_error(function() vendor.parse("Item Class: Support Skill Gems\nRarity: Gem\nVaal Arc\n--------") end)
	end)
	it("accepts copied active and support gem class labels",function()
		local function gem(class,name,quality) return "Item Class: "..class.."\nRarity: Gem\n"..name.."\n--------\nQuality: +"..quality.."%" end
		local active=gem("Active Skill Gems","Arc",20);local support=gem("Support Skill Gems","Added Fire Damage Support",20)
		assert.equal("Skill Gems",vendor.parse(active).class);assert.equal("Support Gems",vendor.parse(support).class)
		local gems=vendor.review({active,support}).categories[4];assert.equal(2,#gems.groups);assert.is_true(gems.optimal)
	end)
	it("accepts one-line magic and unidentified item names",function()
		local function copy(class,rarity,name,quality,marker)
			return "Item Class: "..class.."\nRarity: "..rarity.."\n"..name.."\n--------\nQuality: +"..quality.."%\n--------\n"..(marker or "")
		end
		local flask=copy("Life Flasks","Magic","Saturated Divine Life Flask of Sealing",18)
		local tincture=copy("Tinctures","Magic","Persevering Prismatic Tincture of Mastery",12)
		local utility=copy("Utility Flasks","Magic","Alchemist's Granite Flask of the Armadillo",10)
		local review=vendor.review({flask,tincture,utility});local result=review.categories[3]
		assert.equal(1,#result.groups);assert.equal(40,result.groups[1].quality)
		assert.equal("Saturated Divine Life Flask of Sealing",vendor.parse(flask).base)
		assert.equal("Iron Hat",vendor.parse(copy("Helmets","Rare","Iron Hat",12,"Unidentified (Tier 3)")).base)
		assert.has_error(function() vendor.parse(copy("Helmets","Rare","Incomplete name",12)) end)
		assert.has_error(function() vendor.parse("Item Class: Helmets\nRarity: Rare\nIncomplete name\nQuality: +12%") end)
		assert.has_error(function() vendor.parse("Item Class: Helmets\nRarity: Rare\nIncomplete name\nItem Level: 80\nQuality: +12%") end)
		assert.equal("Saturated Divine Life Flask of Sealing",vendor.parse("Item Class: Life Flasks\nRarity: Magic\nSaturated Divine Life Flask of Sealing\nQuality: +18%").base)
	end)
	it("does not turn an 80% total into two offers without two valid groups",function()
		local copies={};for _,quality in ipairs({19,13,15,9,17,7}) do copies[#copies+1]=item("Wands","Magic","Driftwood Wand",quality) end
		local category=vendor.review(copies).categories[1];assert.equal(1,#category.groups);assert.is_true(category.optimal);assert.is_true(category.groups[1].quality>=40);assert.equal(80,category.groups[1].quality+category.leftoverQuality)
	end)
	it("finds two exact groups when a high-quality-first grouping misses one",function()
		local copies={};for _,quality in ipairs({18,17,13,12,11,9}) do copies[#copies+1]=item("Wands","Magic","Driftwood Wand",quality) end
		local category=vendor.review(copies).categories[1];assert.is_true(category.optimal);assert.equal(2,#category.groups);assert.equal(0,#category.leftover)
		for _,group in ipairs(category.groups) do assert.equal(40,group.quality) end
	end)
	it("proves the optimum for a difficult 15-item collection",function()
		local copies={};for _,quality in ipairs({18,17,13,12,11,9,18,17,13,12,11,9,1,1,1}) do copies[#copies+1]=item("Wands","Magic","Driftwood Wand",quality) end
		local category=vendor.review(copies).categories[1];assert.is_true(category.optimal);assert.equal(4,#category.groups)
	end)
	it("keeps larger difficult collections as explicitly marked suggestions",function()
		local copies={};for _,quality in ipairs({18,17,13,12,11,9,18,17,13,12,11,9,1,1,1,1,1,1,1}) do copies[#copies+1]=item("Wands","Magic","Driftwood Wand",quality) end
		local category=vendor.review(copies).categories[1];assert.is_false(category.optimal);assert.equal(3,#category.groups)
	end)
	it("finds more complete offers in larger mixed-quality collections",function()
		local copies={};for i=1,8 do copies[#copies+1]=item("Wands","Magic","Driftwood Wand",30) end
		for i=1,8 do copies[#copies+1]=item("Wands","Magic","Driftwood Wand",10) end
		local category=vendor.review(copies).categories[1];assert.equal(8,#category.groups);assert.equal(0,#category.leftover);assert.is_true(category.optimal)
		local used={};for _,group in ipairs(category.groups) do assert.equal(40,group.quality);assert.equal(2,#group.items);for _,entry in ipairs(group.items) do assert.is_nil(used[entry.index]);used[entry.index]=true end end
	end)
	it("never loses a group from the previous large-collection heuristic",function()
		for trial=1,40 do
			local values,copies={},{};for i=1,24 do local q=(trial*17+i*11+trial*i*3)%35+1;values[i]=q;copies[i]=item("Wands","Magic","Driftwood Wand",q) end
			table.sort(values,function(a,b) return a>b end);local oldCount,sum,count=0,0,0
			for _,q in ipairs(values) do sum=sum+q;count=count+1;if count>=2 and sum>=40 then oldCount=oldCount+1;sum=0;count=0 end end
			local result=vendor.review(copies).categories[1];assert.is_true(#result.groups>=oldCount)
			local seen={};for _,group in ipairs(result.groups) do local total=0;assert.is_true(#group.items>=2);for _,entry in ipairs(group.items) do assert.is_nil(seen[entry.index]);seen[entry.index]=true;total=total+entry.quality end;assert.equal(total,group.quality);assert.is_true(total>=40) end
			for _,entry in ipairs(result.leftover) do assert.is_nil(seen[entry.index]);seen[entry.index]=true end;for i=1,#copies do assert.is_true(seen[i]) end
		end
	end)
	it("matches an independent exhaustive search for small collections",function()
		local bit=require("bit");local band=bit.band
		for trial=1,60 do
			local values,copies={},{};for i=1,7 do local q=(trial*17+i*11+trial*i*3)%19+1;values[i]=q;copies[i]=item("Wands","Magic","Driftwood Wand",q) end
			local memo={[0]=0};local function brute(mask)
				if memo[mask]~=nil then return memo[mask] end
				local first=band(mask,-mask);local best=brute(mask-first);local subset=mask
				while subset>0 do
					if band(subset,first)~=0 then local sum,count=0,0;for i=1,#values do if band(subset,2^(i-1))~=0 then sum=sum+values[i];count=count+1 end end
						if count>=2 and sum>=40 then best=math.max(best,1+brute(mask-subset)) end
					end
					subset=band(subset-1,mask)
				end
				memo[mask]=best;return best
			end
			local category=vendor.review(copies).categories[1];assert.is_true(category.optimal);assert.equal(brute(2^#values-1),#category.groups)
		end
	end)
	it("keeps pasted items while the build remains open",function()
		newBuild();main.popups={};local raw=item("Wands","Normal","Driftwood Wand",20)
		build.planningVendorQualityItems={raw}
		local control=require("Classes.VendorQualitySetsControl").Open(build);assert.equal(1,#build.planningVendorQualityItems);assert.matches("1 pasted item",control.status.label)
		main.popups={};local reopened=require("Classes.VendorQualitySetsControl").Open(build);assert.equal(1,#build.planningVendorQualityItems);assert.matches("1 pasted item",reopened.status.label)
		main.popups={}
	end)
	it("clears the review when another build is opened",function()
		newBuild();build.planningVendorQualityItems={item("Wands","Normal","Driftwood Wand",20)};newBuild();assert.is_nil(build.planningVendorQualityItems)
	end)
end)
