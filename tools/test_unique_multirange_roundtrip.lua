-- Repeated Divine previews must retain independently rolled weapon values.
arg={}
dofile('HeadlessWrapper.lua')
main.disableDevAutoSave=true
newBuild()
local unique=require('Modules.CraftingUniqueQuality')
local template
for _,group in pairs(data.uniques) do
	for _,entry in ipairs(group) do
		if entry:match('^%s*Dreadarc[\r\n]') then template=entry end
	end
end
assert(template, 'Dreadarc fixture is missing')
local raw='Rarity: UNIQUE\n'..template..'\nItem Level: 86'
local original=assert(unique.divineOptions(raw))
local multi
for _,option in ipairs(original) do if option.components>1 then multi=option.line;break end end
assert(multi, 'Fixture needs independent modifier ranges')
local outcomes={}
for seed=1,80 do
	local result=unique.divine(raw,require('Modules.CalcEncounter').seed(104729,seed,31))
	local options=assert(unique.divineOptions(result.itemText))
	local values={}
	for _,option in ipairs(options) do if option.line==multi then values[option.component]=option.current end end
	assert(values[1] and values[2], 'Independent rolls were lost after preview')
	outcomes[tostring(values[1])..':'..tostring(values[2])]=true
	raw=result.itemText
end
local count=0
for _ in pairs(outcomes) do count=count+1 end
assert(count>10, 'Independent rolls did not vary across repeated previews')
local before=assert(unique.divineOptions(raw))
local project={id='independent-rolls',title='Dreadarc rolls',slot='Weapon 1',startingItem=raw,goals={},steps={}}
build.savers.CraftingProjects:Upsert(project)
local xml=build:SaveDB('Independent rolls')
loadBuildFromXML(xml,'Independent rolls')
local reopened=assert(build.savers.CraftingProjects.projects[1]).startingItem
local after=assert(unique.divineOptions(reopened))
for index,option in ipairs(before) do
	assert(after[index] and after[index].line==option.line and after[index].component==option.component and after[index].current==option.current,
		'Saving and reopening changed a Divine modifier roll')
end
assert(unique.divineOptions(unique.divine(reopened,12345).itemText), 'Reopened item could not be crafted again')
local ui=require('Modules.HeadlessUI').install({width=960,height=640})
ui:bind(build)
require('Classes.CraftingUniqueQualityControl').Open(build,build.savers.CraftingProjects.projects[1])
ui:click('divine')
local controls=main.popups[1].controls
local selected={}
for index,option in ipairs(after) do
	if option.line==multi and option.component<=2 then selected[option.component]={index=index,option=option} end
end
assert(selected[1] and selected[2], 'Independent target choices are missing')
controls.stat:SelByValue('modifier:'..selected[1].index,'val')
ui:text('target',tostring(selected[1].option.max))
ui:click('addGoal')
controls.stat:SelByValue('modifier:'..selected[2].index,'val')
ui:text('target',tostring(selected[2].option.max))
ui:click('plan')
local goals=assert(build.savers.CraftingProjects.projects[1].nativeRecipe).requirements.uniqueModifiers
assert(goals and #goals==2 and goals[1].component==1 and goals[2].component==2, 'Independent target conditions were not saved')
local xmlWithGoals=build:SaveDB('Independent roll targets')
loadBuildFromXML(xmlWithGoals,'Independent roll targets')
local saved=build.savers.CraftingProjects.projects[1]
assert(saved.nativeRecipe.requirements.uniqueModifiers[2].component==2, 'Reopening lost the second roll target')
assert(type(unique.matches(saved.startingItem,saved.nativeRecipe.requirements))=='boolean', 'Saved roll targets could not be evaluated')
ui:restore()
print('UNIQUE_MULTIRANGE_ROUNDTRIP_OK')
