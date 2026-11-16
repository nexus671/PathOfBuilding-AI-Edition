describe("Wickerman planning",function()
	local bridge=require("Modules.DesktopBuildBridge")
	local raw="Item Class: Viscera\nLesser Warden's Arm\n--------\nUpper Limb\n--------\nItem Level: 69\n--------\n{ Implicit Modifier }\n+43 to maximum Life\n--------\nTake this to the Wickerman in a town or hideout to attach it."
	before_each(function() newBuild();bridge.prepared=nil end)
	after_each(function() bridge.prepared=nil;bridge.history={};main.popups={} end)
	it("previews a Viscera proposal and preserves the original build",function()
		local revision=bridge.revision(build);local before=build.calcsTab.mainOutput.Life
		local proposal={mode="edit",title="Wickerman preview",baseRevision=revision,operations={{type="equip_item",slot="Wickerman Upper Limb",text=raw}}}
		local result=bridge.prepare(build,proposal);local candidate=result.candidate
		assert.equal(0,build.itemsTab.slots["Wickerman Upper Limb"].selItemId);assert.equal(revision,bridge.revision(build))
		local item=candidate.itemsTab.items[candidate.itemsTab.slots["Wickerman Upper Limb"].selItemId]
		assert.equal("Wickerman Upper Limb",assert(item).type);assert.is_true(result.after.LifeUnreserved>before)
	end)
	it("saves Viscera acquisition targets with the correct slot",function()
		local journey=require("Modules.BuildJourney").empty()
		journey.wishlist={{id="wickerman-arm",title="Warden's Arm",slot="Wickerman Upper Limb",route="farm",targetItem=raw}}
		build.savers.BuildJourney:Replace(journey)
		local copied=bridge.prepare(build,{mode="edit",title="Reopen guide",baseRevision=bridge.revision(build),operations={{type="set_character",level=80}}}).candidate
		local target=copied.savers.BuildJourney.data.wishlist[1]
		assert.equal("Wickerman Upper Limb",target.slot);assert.equal(raw,target.targetItem)
		local filters=require("Modules.LootFilters");local rules=filters.generate(copied,filters.profile("viscera","Viscera"));local found
		for _,rule in ipairs(rules) do if rule.origin=="gear:wickerman-arm" then found=rule end end
		assert.is_truthy(found);assert.is_truthy(found.text:find('Class == "Viscera"',1,true))
		assert.is_truthy(found.text:find('BaseType == "Warden\'s Arm"',1,true));assert.is_nil(found.text:find('Rarity',1,true))
	end)
end)
