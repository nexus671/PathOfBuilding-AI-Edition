arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true;newBuild()
local ui=require('Modules.HeadlessUI').install({width=960,height=640});ui:bind(build)
local project={id='scope-test',title='Scope test',slot='Body Armour',startingItem='Rarity: NORMAL\nPlate Vest\nItem Level: 86',goals={},steps={}}
build.savers.CraftingProjects:Upsert(project)
build.planningWorkspace=require('Modules.PlanningWorkspace').new(build);build.viewMode='PLANNER'
build.planningWorkspace:Show('crafting',{kind='workbench',project=project})
local controls=build.planningWorkspace.controls
ui:click('tab_targets')
assert(not controls.alternative:IsEnabled(), 'An alternative cannot be added without a group')
local explicit,other,implicit
for index,entry in ipairs(controls.target.list) do
	if entry.label:match('^Prefix |') or entry.label:match('^Suffix |') then
		if not explicit then explicit=index elseif not other and entry.val~=controls.target.list[explicit].val then other=index end
	elseif entry.label:match('^Exarch |') or entry.label:match('^Eater |') or entry.label:match('^Corrupted |') then implicit=implicit or index end
end
assert(explicit and other and implicit, 'Expected explicit and implicit target choices')
controls.target:SetSel(explicit);ui:click('addTarget')
assert(not controls.alternative:IsEnabled() and controls.alternative.tooltipText():find('already',1,true), 'Duplicate target should be explained')
controls.target:SetSel(implicit)
assert(not controls.alternative:IsEnabled() and controls.alternative.tooltipText():find('same',1,true), 'Mixed scope should be explained')
controls.target:SetSel(other)
assert(controls.alternative:IsEnabled(), 'A distinct modifier in the same scope should be available')
ui:click('alternative')
local targets=build.planningWorkspace.cache.crafting.layout.snapshot().targets
assert(#targets==1 and #targets[1].anyOf==2 and targets[1].scope=='explicit', 'Alternative was not kept in the expected group')
ui:restore();print('CRAFTING_ALTERNATIVE_SCOPE_OK')
