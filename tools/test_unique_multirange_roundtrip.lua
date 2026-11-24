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
print('UNIQUE_MULTIRANGE_ROUNDTRIP_OK')
