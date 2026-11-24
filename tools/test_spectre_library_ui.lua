-- Editing the gem level must remain safe while its field is temporarily empty.
local output=arg[1]
arg={}
dofile('HeadlessWrapper.lua')
local UI=require('Modules.HeadlessUI')
for _,size in ipairs({{640,480},{960,640},{1024,768},{1280,720}}) do
	newBuild()
	local ui=UI.install({width=size[1],height=size[2]})
	ui:bind(build)
	build:OpenSpectreLibrary()
	local controls=main.popups[1].controls
	controls.source.selValue=assert(controls.source.unfilteredList[1], 'No recommended spectres')
	controls.source.OnSelect()
	if size[1]==1280 then
		ui:click('sortMonsterCheckboxShowAll')
		local sort=controls.source.controls.sortModeDropDown
		for index in ipairs(sort.list) do sort:SetSel(index) end
		sort:SetSel(5)
		local previous=0
		local unknown=false
		for _,id in ipairs(controls.source.list) do
			local time=build.data.minions[id].attackTime
			if not time or time<=0 then unknown=true
			else
				assert(not unknown and time>=previous, 'Attack-speed sort must rank known fastest attacks first')
				previous=time
			end
		end
		assert(unknown and previous>0, 'Expected both known and undefined attack times')
	end
	if controls.compactDetails then
		local function fits(control)
			local x,y=control:GetPos();local w,h=control:GetSize()
			return x>=0 and y>=0 and x+w<=size[1] and y+h<=size[2]
		end
		assert(controls.list:IsShown() and not controls.minionNameLabel:IsShown(), 'Compact library page is incorrect')
		assert(fits(controls.list) and fits(controls.source) and fits(controls.save), 'Compact library controls leave the screen')
		if output then ui:frame():write(output..'/'..size[1]..'-spectre-library-compact.json') end
		ui:click('compactDetails')
		assert(not controls.list:IsShown() and controls.minionNameLabel:IsShown(), 'Compact details page is incorrect')
		assert(fits(controls.source) and fits(controls.spawnLocations) and fits(controls.minionGemLevel), 'Compact details controls leave the screen')
		if output then ui:frame():write(output..'/'..size[1]..'-spectre-details-compact.json') end
		local x,y=controls.source:GetPos()
		ui:clickAt(x+12,y+8)
		local selected=assert(controls.source.selValue, 'Could not select a compact spectre')
		x,y=controls.source.controls.add:GetPos();ui:clickAt(x+8,y+8)
		assert(#controls.list.list==1 and controls.list.list[1]==selected, 'Could not add from compact details')
		ui:click('compactLibrary')
		x,y=controls.list:GetPos();ui:clickAt(x+12,y+8)
		x,y=controls.list.controls.delete:GetPos();ui:clickAt(x+8,y+8)
		assert(#controls.list.list==0, 'Could not remove from compact library')
		x,y=controls.source.controls.add:GetPos();ui:clickAt(x+8,y+8)
		assert(#controls.list.list==1, 'Could not add from compact library')
	end
	controls.minionGemLevel:SetText('1',true)
	local low=controls.lifeLabel.lifeValue
	controls.minionGemLevel:SetText('',true)
	assert(controls.lifeLabel.lifeValue==low, 'Empty level should use level 1')
	controls.minionGemLevel:SetText('0',true)
	assert(controls.lifeLabel.lifeValue==low, 'Level below 1 should be clamped')
	controls.minionGemLevel:SetText('40',true)
	local high=controls.lifeLabel.lifeValue
	assert(high>low, 'Changing level should update spectre stats')
	controls.minionGemLevel:SetText('999',true)
	assert(controls.lifeLabel.lifeValue==high, 'Level above 40 should be clamped')
	controls.minionGemLevel:SetText('20',true)
	assert(controls.lifeLabel.lifeValue>low and controls.lifeLabel.lifeValue<high, 'Editing should recover after clearing')
	if controls.compactLibrary then
		ui:click('save')
		assert(#build.spectreList==1, 'Compact save did not keep the selected spectre')
	end
	ui:restore()
end
print('SPECTRE_LIBRARY_LEVEL_OK')
