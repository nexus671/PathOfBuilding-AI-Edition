arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true
local function item(raw) build.itemsTab:CreateDisplayItemFromRaw(raw);build.itemsTab:AddDisplayItem() end
local function hasSupport(name,id)
 for _,skill in ipairs(build.calcsTab.mainEnv.player.activeSkillList) do
  if skill.activeEffect.grantedEffect.name==name then for _,effect in ipairs(skill.effectList) do if effect.grantedEffect.id==id then return true end end end
 end
 return false
end
newBuild();item('Granting Helmet\nEzomyte Burgonet\nGrants Level 20 Fireball');item('Plain Gloves\nSpiked Gloves')
build.skillsTab:PasteSocketGroup('Slot: Helmet\nHypothermia 20/0  1\n');build.skillsTab:PasteSocketGroup('Slot: Gloves\nFrostbolt 20/0  1\n');runCallback('OnFrame');assert(hasSupport('Fireball','SupportHypothermia'))
local calc=build.calcsTab:GetMiscCalculator();local gloves=new('Item'):Item('Rarity: RARE\nSupporting Gloves\nSpiked Gloves\nSocketed Gems are Supported by Level 20 Hypothermia');calc({repSlotName='Gloves',repItem=gloves});build.buildFlag=true;runCallback('OnFrame');assert(not data.skills.SupportHypothermia.fromItem and hasSupport('Fireball','SupportHypothermia'),'Item comparison polluted the global support gem')
newBuild();item('Test Subject\nImbued Wand\nSockets: B-B-B');build.skillsTab:PasteSocketGroup('Fireball 20/0  1\nAdded Fire Damage 20/0  1');local group=build.skillsTab.socketGroupList[1];group.slot='Weapon 1';group.imbuedSupport='Constriction';build.skillsTab:RebuildImbuedSupportBySlot();build.buildFlag=true;runCallback('OnFrame');local skill=build.calcsTab.mainEnv.player.mainSkill;assert(#skill.effectList==2 and skill.effectList[2].grantedEffect.id=='SupportConstriction','Imbued Constriction did not exclude other supports')
print('UPSTREAM_SKILL_FIXES_OK')
