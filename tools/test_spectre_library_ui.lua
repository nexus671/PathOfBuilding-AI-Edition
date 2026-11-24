-- Editing the gem level must remain safe while its field is temporarily empty.
arg={}
dofile('HeadlessWrapper.lua')
local UI=require('Modules.HeadlessUI')
for _,size in ipairs({{960,640},{1024,768},{1280,720}}) do
	newBuild()
	local ui=UI.install({width=size[1],height=size[2]})
	ui:bind(build)
	build:OpenSpectreLibrary()
	local controls=main.popups[1].controls
	controls.source.selValue=assert(controls.source.unfilteredList[1], 'No recommended spectres')
	controls.source.OnSelect()
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
	ui:restore()
end
print('SPECTRE_LIBRARY_LEVEL_OK')
