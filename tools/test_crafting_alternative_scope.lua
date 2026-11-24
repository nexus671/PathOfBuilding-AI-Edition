local output,width=arg[1],tonumber(arg[2]) or 960
arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true;newBuild()
local ui=require('Modules.HeadlessUI').install({width=width,height=width==640 and 480 or 640});ui:bind(build)
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
if output then ui:frame():write(output..'/'..width..'-crafting-alternative-scope.json') end
controls.target:SetSel(other)
assert(controls.alternative:IsEnabled(), 'A distinct modifier in the same scope should be available')
ui:click('alternative')
local targets=build.planningWorkspace.cache.crafting.layout.snapshot().targets
assert(#targets==1 and #targets[1].anyOf==2 and targets[1].scope=='explicit', 'Alternative was not kept in the expected group')
local simulator=require('Modules.CraftingSimulator')
local model=simulator.model(project.startingItem)
local implicitId=controls.target.list[implicit].val
assert(pcall(simulator.validateTargetAvailability,model,targets,{}), 'Valid target group was rejected')
local mixed={{scope='explicit',anyOf={targets[1].anyOf[1],implicitId}}}
local ok,reason=pcall(simulator.validateTargetAvailability,model,mixed,{})
assert(not ok and tostring(reason):find('scope',1,true), 'Mixed-scope API targets must be rejected')
ok,reason=pcall(simulator.validateTargetAvailability,model,{},{{untilTargets=mixed}})
assert(not ok and tostring(reason):find('scope',1,true), 'Mixed-scope step targets must be rejected')
local donor='Rarity: NORMAL\nIron Hat\nItem Level: 86'
local donorModel=simulator.model(donor);local available={};local donorOnly
for _,entry in ipairs(model.mods) do available[entry.id]=true end
for _,entry in ipairs(donorModel.mods) do if not available[entry.id] and (entry.mod.type=='Prefix' or entry.mod.type=='Suffix') then donorOnly=entry.id;break end end
assert(donorOnly, 'Expected a donor-only explicit modifier')
local steps={{method='recombine',donorItem=donor}}
assert(pcall(simulator.validateTargetAvailability,model,{{scope='explicit',anyOf={donorOnly}}},steps), 'Valid donor target was rejected')
ok,reason=pcall(simulator.validateTargetAvailability,model,{{scope='implicit',anyOf={donorOnly}}},steps)
assert(not ok and tostring(reason):find('scope',1,true), 'Donor scope mismatch must be rejected')
ui:click('targetPicker');ui:choose('kind','Exarch')
local picker=main.popups[1].controls
assert(not picker.alternative:IsEnabled() and picker.alternative.tooltipText():find('same',1,true), 'Modifier browser must explain incompatible alternatives')
main:ClosePopup()
ui:click('targetGroups');ui:click('newAlternative');ui:choose('kind','Exarch')
picker=main.popups[1].controls
assert(not picker.choose:IsEnabled() and picker.choose.tooltipText():find('same',1,true), 'Group editor must explain incompatible alternatives')
main:ClosePopup();main:ClosePopup()
ui:restore();print('CRAFTING_ALTERNATIVE_SCOPE_OK')
