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
	it("keeps larger difficult collections as explicitly marked suggestions",function()
		local copies={};for _,quality in ipairs({18,17,13,12,11,9,18,17,13,12,11,9,1,1,1}) do copies[#copies+1]=item("Wands","Magic","Driftwood Wand",quality) end
		local category=vendor.review(copies).categories[1];assert.is_false(category.optimal);assert.equal(3,#category.groups)
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
		local oldPaste=Paste;Paste=function() return raw end
		local control=require("Classes.VendorQualitySetsControl").Open(build);control.paste:Click();assert.equal(1,#build.planningVendorQualityItems)
		main.popups={};local reopened=require("Classes.VendorQualitySetsControl").Open(build);assert.equal(1,#build.planningVendorQualityItems);assert.matches("1 pasted item",reopened.status.label)
		Paste=oldPaste;main.popups={}
	end)
	it("clears the review when another build is opened",function()
		newBuild();build.planningVendorQualityItems={item("Wands","Normal","Driftwood Wand",20)};newBuild();assert.is_nil(build.planningVendorQualityItems)
	end)
end)
