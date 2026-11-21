// cspell:ignore RRBG
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createBridge, tools } = require('../../src/AI/BuildProtocol.cjs');
function fixture(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(),'pob-build-'));
  t.after(() => fs.rmSync(dir,{recursive:true,force:true}));
  const state = {schemaVersion:1,session:'session-one',enabled:true,heartbeat:Date.now()/1000,revision:'a'.repeat(40)};
  const captured = {schemaVersion:1,session:state.session,capturedAt:new Date().toISOString(),context:{revision:state.revision,name:'Desktop',level:80,xml:'not returned'},
    catalog:{gems:[{name:'Fireball'}],passives:[{id:123,name:'Life',pathLength:3}],config:[],classes:[]}};
  const write = (name,value) => fs.writeFileSync(path.join(dir,`AI-build-${name}.json`),JSON.stringify(value));
  write('state',state); write('context',captured);
  return {dir,state,captured,write,call:createBridge(path.join(dir,'AI-encounter.json')),proposal:{mode:'new',title:'Fireball candidate',baseRevision:state.revision,
    operations:[{type:'set_character',level:80,className:'Witch',ascendancy:'Elementalist'},{type:'set_skills',groups:[{gems:[{name:'Fireball'}]}]}]}};
}

test('queues same-name rare review with bounded copied items', t => {
  const f=fixture(t), raw='Rarity: Rare\nVortex Visage\nIron Hat\n--------\nItem Level: 80';
  f.call('review_same_name_rares',{baseRevision:f.state.revision,items:[raw,raw,raw]});
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(request.kind,'review_same_name_rares');assert.equal(request.items.length,3);
  for(const items of [[],[3],['x'.repeat(24001)]]) assert.throws(()=>f.call('review_same_name_rares',{baseRevision:f.state.revision,items}),/arguments/);
});

test('preserves and validates predictable recombination observations', t => {
  const f=fixture(t), donorItem='Rarity: MAGIC\nIron Hat', selectedMods={left:['Life1'],right:['FireResist1']};
  const observedInputs={donorItem,selectedMods,reportedSuccessChance:40};
  const action={method:'recombine_predictable',donorItem,selectedMods,reportedSuccessChance:40,observedInputs};
  const args={baseRevision:f.state.revision,itemText:donorItem,recipe:{steps:[action],targets:[{anyOf:['Life1']}]}};
  f.call('simulate_crafting',args);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).recipe.steps[0].observedInputs,observedInputs);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  for (const invalid of [{...observedInputs,reportedSuccessChance:101},{...observedInputs,extra:true},{...observedInputs,selectedMods:{left:[],right:['FireResist1']}}]) {
    assert.throws(()=>f.call('simulate_crafting',{...args,recipe:{...args.recipe,steps:[{...action,observedInputs:invalid}]}}),/arguments/);
  }
});

test('queues reviewed crafting removals with closed project-ID validation', t => {
  const f=fixture(t);const proposal={...f.proposal,mode:'edit',operations:[{type:'remove_crafting_project',projectId:'helmet-guide'}]};
  f.call('propose_build',proposal);
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.deepEqual(request.proposal.operations,proposal.operations);assert.equal(f.captured.context.craftingProjects,undefined);
  for(const operation of [{type:'remove_crafting_project',projectId:'../other'},{type:'remove_crafting_project',projectId:''},{type:'remove_crafting_project',projectId:'helmet',project:{}}]) {
    assert.throws(()=>f.call('propose_build',{...proposal,operations:[operation]}),/arguments/);
  }
});

test('accepts 3.30 crafting state markers without opening the schema', t => {
  const f=fixture(t), itemText='Rarity: NORMAL\nIron Hat\nItem Level: 86';
  const initialState={rarity:'RARE',affixes:[{id:'AttackCastSpeedPerNearbyEnemyEssence1',range:0.5,description330:true,legacySource:itemText}],corrupted:true,corruptedImplicits:[{id:'V2SupportedByLifeGainOnHitCorrupted',range:0.5,corruption330:true}],synthRetained:[1,2,3],gildedCorruptionReplaced:true,synthExhausted:true,synthRolls:[{id:'SynthesisImplicitPercentLife3',range:0.5}],socketLayoutUnknown:true};
  const args={baseRevision:f.state.revision,itemText,initialState,action:{method:'tainted_chromatic'}};
  f.call('apply_crafting_action',args);
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(request.initialState,initialState);
  for(const invalid of [
    {...initialState,affixes:[{...initialState.affixes[0],description330:'yes'}]},
    {...initialState,affixes:[{...initialState.affixes[0],legacySource:123}]},
    {...initialState,affixes:[{...initialState.affixes[0],legacySource:'x'.repeat(24001)}]},
    {...initialState,socketLayoutUnknown:'yes'},
    {...initialState,synthExhausted:false},
    {...initialState,synthRetained:[0]},
    {...initialState,synthRetained:[]},
    {...initialState,synthRetained:[1,2,3,1]},
    {...initialState,gildedCorruptionReplaced:false},
    {...initialState,synthRolls:[]},
    {...initialState,synthRolls:[{id:'SynthesisImplicitPercentLife3',range:1.5}]},
    {...initialState,corruptedImplicits:[{...initialState.corruptedImplicits[0],corruption330:false}]},
    {...initialState,corruptedImplicits:[{...initialState.corruptedImplicits[0],unexpected:true}]}
  ]) assert.throws(()=>f.call('apply_crafting_action',{...args,initialState:invalid}),/arguments/);
});

test('accepts transformed jewel states and exact unique targets', t => {
  const f=fixture(t);
  const initialState={rarity:'UNIQUE',affixes:[],origin:'a'.repeat(40),corrupted:true,uniqueTitle:'Powerlessness',uniqueSeed:123};
  const args={baseRevision:f.state.revision,itemText:'Rarity: NORMAL\nCobalt Jewel\nItem Level: 83',initialState,action:{method:'vaal'}};
  f.call('apply_crafting_action',args);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).initialState,initialState);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  const recipe={steps:[{method:'vaal'}],targets:[],rarity:'UNIQUE',requirements:{uniqueName:'Powerlessness'}};
  f.call('simulate_crafting',{baseRevision:f.state.revision,itemText:args.itemText,recipe});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).recipe,recipe);
  assert.throws(()=>f.call('apply_crafting_action',{...args,initialState:{...initialState,uniqueSeed:0}}),/arguments/);
});

test('accepts bounded unique modifier roll targets', t => {
  const f=fixture(t);const goal={uniqueModifier:{line:'+(30-40)% to all Elemental Resistances',component:2,minValue:40}};
  const recipe={rarity:'UNIQUE',steps:[{method:'divine',maxAttempts:20,untilRequirements:goal}],targets:[],requirements:goal};
  const args={baseRevision:f.state.revision,itemText:'Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86',recipe,options:{trials:5,maxActions:20}};
  f.call('simulate_crafting',args);assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).recipe.requirements,goal);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  const signed={uniqueModifier:{line:'+( -2-2 ) seconds',maxValue:-1}};f.call('simulate_crafting',{...args,recipe:{...recipe,requirements:signed}});fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('simulate_crafting',{...args,recipe:{...recipe,requirements:{uniqueModifier:{...goal.uniqueModifier,maxValue:40}}}}),/arguments/);
  assert.throws(()=>f.call('simulate_crafting',{...args,recipe:{...recipe,requirements:{uniqueModifier:{...goal.uniqueModifier,minValue:-100001}}}}),/arguments/);
  assert.throws(()=>f.call('simulate_crafting',{...args,recipe:{...recipe,requirements:{uniqueModifier:{...goal.uniqueModifier,component:7}}}}),/arguments/);
});

test('accepts bounded long crafting steps', t => {
  const f=fixture(t);const recipe={steps:[{method:'fusing',maxAttempts:2000,untilRequirements:{links:6}}],targets:[],requirements:{links:6}};
  const args={baseRevision:f.state.revision,itemText:'Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B W',recipe,options:{trials:10,maxActions:2000}};
  f.call('simulate_crafting',args);assert.equal(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).recipe.steps[0].maxAttempts,2000);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));assert.throws(()=>f.call('simulate_crafting',{...args,recipe:{...recipe,steps:[{...recipe.steps[0],maxAttempts:2001}]}}),/arguments/);
});

test('queues loot-filter generation, evaluation and reviewed profiles without writing exports', t => {
  const f=fixture(t);const profile={id:'maps',title:'Map pickups',preset:'early_maps',strictness:2,rules:[{id:'base',title:'Craft base',text:'Show\n BaseType == "Iron Hat"',enabled:true}]};
  const filters={schemaVersion:1,activeId:'maps',profiles:[profile]};f.captured.context.lootFilters=filters;f.write('context',f.captured);
  assert.deepEqual(f.call('get_loot_filters',{}).filters,filters);
  for(const name of ['generate_loot_filter','test_loot_filter','export_loot_filter']) {
    f.call(name,{baseRevision:f.state.revision,profile,...(name==='test_loot_filter'?{sample:{BaseType:'Iron Hat',Fated:false,UnidentifiedItemTier:3}}:{})});
    const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.equal(request.kind,name);
    assert.equal(request.profile.id,'maps');assert.equal(request.path,undefined);fs.rmSync(path.join(f.dir,'AI-build-request.json'));
  }
  f.call('propose_loot_filters',{title:'Pickups',baseRevision:f.state.revision,filters});
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.equal(request.proposal.operations[0].type,'set_loot_filters');
  assert.throws(()=>f.call('test_loot_filter',{baseRevision:f.state.revision,profile,sample:{},path:'arbitrary'}),/arguments/);
});
test('queues copied items for filter evaluation with bounded optional area level', t => {
  const f=fixture(t), args={baseRevision:f.state.revision,profileId:'maps',itemText:'Rarity: Normal\nIron Hat',areaLevel:12};
  f.call('test_loot_filter',args);
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(request.itemText,args.itemText);assert.equal(request.areaLevel,12);
  fs.rmSync(path.join(f.dir,'AI-build-request.json'));
  for(const invalid of [{baseRevision:f.state.revision,profileId:'maps'}, {...args,sample:{}}, {...args,itemText:''}, {...args,itemText:'',sample:{}}, {...args,areaLevel:101}, {baseRevision:f.state.revision,profileId:'maps',sample:{},areaLevel:12}]) assert.throws(()=>f.call('test_loot_filter',invalid));
});
test('queues bounded pages of saved filter examples', t => {
  const f=fixture(t);const args={baseRevision:f.state.revision,profileId:'maps',sampleSetId:'examples',offset:50,limit:20};
  f.call('test_loot_filter_examples',args);
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(request.kind,'test_loot_filter_examples');assert.equal(request.offset,50);assert.equal(request.sampleSetId,'examples');
  for(const invalid of [{...args,limit:51},{...args,offset:-1},{...args,sampleSetId:'../outside'},{...args,unknown:true}]) assert.throws(()=>f.call('test_loot_filter_examples',invalid),/arguments/);
});
test('queues bounded built-in filter scenes', t => {
  const f=fixture(t), args={baseRevision:f.state.revision,profileId:'maps',scene:'Preset highlights',seed:3,areaLevel:76,itemLevel:81,offset:2,limit:5};
  f.call('test_loot_filter_scene',args);
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(request.kind,'test_loot_filter_scene');assert.equal(request.scene,args.scene);assert.equal(request.seed,3);
  const targetFixture=fixture(t);
  targetFixture.call('test_loot_filter_scene',{...args,baseRevision:targetFixture.state.revision,scene:'Build targets'});
  assert.equal(JSON.parse(fs.readFileSync(path.join(targetFixture.dir,'AI-build-request.json'))).scene,'Build targets');
  const mapFixture=fixture(t);mapFixture.call('test_loot_filter_scene',{...args,baseRevision:mapFixture.state.revision,scene:'Map tiers'});
  assert.equal(JSON.parse(fs.readFileSync(path.join(mapFixture.dir,'AI-build-request.json'))).scene,'Map tiers');
  const blightFixture=fixture(t);blightFixture.call('test_loot_filter_scene',{...args,baseRevision:blightFixture.state.revision,scene:'Blight & oils'});
  assert.equal(JSON.parse(fs.readFileSync(path.join(blightFixture.dir,'AI-build-request.json'))).scene,'Blight & oils');
  for(const scene of ['Breach','Legion','Abyss','Ultimatum']) { const encounter=fixture(t); encounter.call('test_loot_filter_scene',{...args,baseRevision:encounter.state.revision,scene}); assert.equal(JSON.parse(fs.readFileSync(path.join(encounter.dir,'AI-build-request.json'))).scene,scene); }
  const vendorFixture=fixture(t);vendorFixture.call('test_loot_filter_scene',{...args,baseRevision:vendorFixture.state.revision,scene:'Vendor recipes'});
  assert.equal(JSON.parse(fs.readFileSync(path.join(vendorFixture.dir,'AI-build-request.json'))).scene,'Vendor recipes');
  for(const invalid of [{...args,scene:'Unknown'},{...args,seed:-1},{...args,areaLevel:101},{...args,limit:51},{...args,offset:-1},{...args,unknown:true}]) assert.throws(()=>f.call('test_loot_filter_scene',invalid),/arguments/);
});
test('explains unidentified saved map drafts without changing them', t => {
  const f=fixture(t), draft={id:'unknown',unidentified:true,selected:[]}, vaal={id:'vaal',corrupted:true,vaalPreview:true,selected:[]};
  f.captured.context.atlasPlans=[{id:'atlas',mapDrafts:[draft,vaal]}];f.write('context',f.captured);
  const response=f.call('get_atlas_plans',{});
  assert.deepEqual(response.plans[0].mapDrafts,[draft,vaal]);
  assert.ok(response.limitations.some(note=>note.includes('one conditional modeled outcome')));
  assert.ok(response.limitations.some(note=>note.includes('unknown explicit modifiers') && note.includes('+30% Atlas Drops')));
  f.captured.context.atlasPlans=[{id:'atlas',mapDrafts:[{id:'known',selected:[]}]}];f.write('context',f.captured);
  assert.ok(!f.call('get_atlas_plans',{}).limitations.some(note=>note.includes('Unidentified map drafts')));
});
test('queues map Allflame reference and conditional plans', t => {
  const f=fixture(t);f.call('list_map_allflame',{baseRevision:f.state.revision});
  let request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.equal(request.kind,'list_map_allflame');
  const state={baseId:'Metadata/Items/Maps/MapWorldsStrand',tier:16,itemLevel:83,rarity:'rare',selected:[]};
  const g=fixture(t);g.call('simulate_map_currency',{baseRevision:g.state.revision,state,action:'plan_allflame',allflameId:'Metadata/Items/MapFragments/AtlasAllflamePack',seed:1});
  request=JSON.parse(fs.readFileSync(path.join(g.dir,'AI-build-request.json')));assert.equal(request.action,'plan_allflame');assert.match(request.allflameId,/AtlasAllflamePack/);
});
test('queues a bounded Delirium projection', t => {
  const f=fixture(t), args={baseRevision:f.state.revision,currentPercent:35,currentType:'Currency',nextType:'Maps',gain:10};
  f.call('project_map_delirium',args);
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(request.kind,'project_map_delirium');assert.equal(request.gain,10);
  for(const invalid of [{...args,gain:4},{...args,gain:51},{...args,currentPercent:101},{...args,unknown:true}]) assert.throws(()=>f.call('project_map_delirium',invalid),/arguments/);
});
test('queues copied map inspection without changing the build', t => {
  const f=fixture(t);f.call('inspect_copied_map',{baseRevision:f.state.revision,itemText:'Item Class: Maps\nRarity: Normal\nStrand Map'});
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.equal(request.kind,'inspect_copied_map');assert.match(request.itemText,/Strand Map/);
});
test('queues bounded map modifier inspection', t => {
  const f=fixture(t), args={baseRevision:f.state.revision,baseId:'Metadata/Items/Maps/MapWorldsBeach',tier:5,itemLevel:68,rarity:'magic',selected:[],limit:5,quality:{kind:'Pack Size',value:20},observedEffects:[{kind:'enchant',text:'Players are Delirious'}]};
  f.call('inspect_map_modifiers',args);
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(request.kind,'inspect_map_modifiers');assert.equal(request.tier,5);assert.equal(request.rarity,'magic');
  assert.deepEqual(request.quality,args.quality);
  assert.deepEqual(request.observedEffects,args.observedEffects);
  const delirium=fixture(t), effects=[{kind:'explicit',text:'Players in Area are 35% Delirious'},{kind:'explicit',text:'Delirium Reward Type: Currency'}];
  delirium.call('inspect_map_modifiers',{...args,baseRevision:delirium.state.revision,rarity:'rare',observedEffects:effects});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(delirium.dir,'AI-build-request.json'))).observedEffects,effects);
  const normal=fixture(t);normal.call('inspect_map_modifiers',{...args,baseRevision:normal.state.revision,rarity:'magic',corrupted:true,mirrored:true,unidentified:true});
  assert.equal(JSON.parse(fs.readFileSync(path.join(normal.dir,'AI-build-request.json'))).unidentified,true);
  const nightmare=fixture(t);nightmare.call('inspect_map_modifiers',{...args,baseRevision:nightmare.state.revision,baseId:'Metadata/Items/Maps/MapWorldsAbomination',tier:17,itemLevel:84,rarity:'rare'});
  assert.equal(JSON.parse(fs.readFileSync(path.join(nightmare.dir,'AI-build-request.json'))).tier,17);
  for(const invalid of [{...args,tier:18},{...args,itemLevel:0},{...args,selected:Array(10).fill('x')},{...args,limit:101},{...args,unknown:true}]) assert.throws(()=>f.call('inspect_map_modifiers',invalid),/arguments/);
  const bases=fixture(t);bases.call('search_map_bases',{baseRevision:bases.state.revision,query:'Beach',limit:5});
  assert.equal(JSON.parse(fs.readFileSync(path.join(bases.dir,'AI-build-request.json'))).kind,'search_map_bases');
});
test('queues a seeded hypothetical map currency action', t => {
  const f=fixture(t), state={baseId:'Metadata/Items/Maps/MapWorldsStrand',tier:16,itemLevel:83,rarity:'normal',selected:[],quality:{kind:'Pack Size',value:20}};
  const args={baseRevision:f.state.revision,state,action:'alchemy',seed:42};
  f.call('simulate_map_currency',args);
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(request.kind,'simulate_map_currency');assert.deepEqual(request.state,state);assert.equal(request.seed,42);
  const vaal=fixture(t);vaal.call('simulate_map_currency',{baseRevision:vaal.state.revision,state:{...state,rarity:'rare'},action:'vaal_add',seed:42});
  assert.equal(JSON.parse(fs.readFileSync(path.join(vaal.dir,'AI-build-request.json'))).action,'vaal_add');
  const nightmare=fixture(t), nightmareState={baseId:'Metadata/Items/Maps/MapWorldsAbomination',tier:17,itemLevel:84,rarity:'rare',selected:[]};
  nightmare.call('simulate_map_currency',{baseRevision:nightmare.state.revision,state:nightmareState,action:'chaos',seed:42});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(nightmare.dir,'AI-build-request.json'))).state,nightmareState);
  for(const invalid of [{...args,seed:0},{...args,action:'vaal'},{...args,state:{...state,rarity:'unique'}},{...args,state:{...state,selected:Array(10).fill('x')}}]) assert.throws(()=>f.call('simulate_map_currency',invalid),/arguments/);
});
test('queues bounded map reroll estimates', t => {
  const f=fixture(t), state={baseId:'Metadata/Items/Maps/MapWorldsStrand',tier:16,itemLevel:83,rarity:'rare'}, options={wanted:[],wantedGroups:[['MapContainsMirageWorlds','MapContainsWildwoodWorlds']],avoid:['MapMonsterAreaOfEffectMapWorlds'],trials:10,maxAttempts:5,seed:42,price:{amount:0.5,currency:'chaos'}};
  f.call('estimate_map_rerolls',{baseRevision:f.state.revision,state,options});
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(request.kind,'estimate_map_rerolls');assert.deepEqual(request.options,options);
  assert.throws(()=>f.call('estimate_map_rerolls',{baseRevision:f.state.revision,state,options:{...options,trials:1001}}),/arguments/);
  assert.throws(()=>f.call('estimate_map_rerolls',{baseRevision:f.state.revision,state,options:{...options,price:{amount:-1,currency:'chaos'}}}),/arguments/);
  const grouped=fixture(t);grouped.call('estimate_map_rerolls',{baseRevision:grouped.state.revision,state,options:{wantedGroups:options.wantedGroups,trials:1,maxAttempts:1,seed:42}});
});
test('accepts typed Atlas stages, strategy inputs and explicit failure recovery branches', t => {
  const f=fixture(t);
  const plan={id:'final',title:'Final maps',version:'3.29.1',budget:138,nodes:[],progression:{stage:'final',previousId:'starter'},strategy:{maps:'T16 maps',scarabs:'Supplied scarabs',requirements:'Unlocks complete',avoid:'Reflect',setupCost:{amount:25,currency:'chaos',source:'Manual quote',quotedAt:1700000000}}};
  f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan});
  let request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(request.proposal.operations[0].plan,plan);
  assert.throws(()=>f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan:{...plan,progression:{stage:'invented'}}}),/arguments/);
  fs.rmSync(path.join(f.dir,'AI-build-request.json'));
  const recipe={steps:[{method:'alchemy',onFailureAction:'restart',recoveryNotes:'Restart within the action budget'}],targets:[]};
  f.call('simulate_crafting',{baseRevision:f.state.revision,itemText:'Rarity: NORMAL\nIron Hat',recipe});
  request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(request.recipe,recipe);
  assert.throws(()=>f.call('simulate_crafting',{baseRevision:f.state.revision,itemText:'Iron Hat',recipe:{...recipe,steps:[{method:'alchemy',onFailureAction:'sell-for-profit'}]}}),/arguments/);
});

test('queues portable tiers, local modules, whole-filter styles and saved Atlas intentions', t => {
  const f=fixture(t);const rule={id:'chaos',title:'Chaos',text:'Show\n BaseType == "Chaos Orb"'};
  const profile={id:'maps',title:'Maps',preset:'early_maps',strictness:2,rules:[],tiers:[{id:'tier',title:'High currency',text:rule.text,items:['Chaos Orb']}],modules:[{id:'module',title:'Shared rules',rules:[rule]}],appearance:{textColor:[255,220,120,255],alertId:6,alertVolume:0,effectColor:'Purple',disableIcons:true}};
  f.call('propose_loot_filters',{title:'Local filter tools',baseRevision:f.state.revision,filters:{schemaVersion:1,activeId:'maps',profiles:[profile]}});
  let request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(request.proposal.operations[0].filters.profiles[0],profile);fs.rmSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('test_loot_filter',{baseRevision:f.state.revision,profile:{...profile,appearance:{textColor:[255,0,0] }},sample:{}}),/arguments/);
  const plan={id:'atlas',title:'Saved intentions',version:'3.30.0-preview',budget:150,nodes:[],desired:[123],avoided:[456]};
  f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan});request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(request.proposal.operations[0].plan,plan);
});

test('queues full crafting inventory snapshots without imposing a count limit', t => {
  const f=fixture(t);const raw='Rarity: NORMAL\nIron Hat\nItem Level: 86';
  const inventory=Array.from({length:12},(_,i)=>({id:`item-${i}`,title:`Helmet ${i}`,slot:'Helmet',baseItem:raw,at:1700000000,state:{rarity:'NORMAL',affixes:[],quality:0,sockets:[{color:'R',group:0}]}}));
  const project={id:'helmet',title:'Helmet',slot:'Helmet',startingItem:raw,goals:[],steps:[],inventory};
  f.call('propose_crafting_plan',{baseRevision:f.state.revision,project});const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(request.proposal.operations[0].project.inventory,inventory);
  fs.rmSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('propose_crafting_plan',{baseRevision:f.state.revision,project:{...project,inventory:[{...inventory[0],state:{rarity:'INVENTED',affixes:[]}}]}}),/arguments/);
});

test('accepts typed campaign pickup policies and rejects invented families', t => {
  const f=fixture(t);const profile={id:'campaign',title:'Campaign',preset:'campaign',strictness:1,rules:[],campaign:{weapons:['Bow','Rune Dagger'],defences:['Energy shield'],recipes:['Three-colour linked equipment','Six-socket equipment','Six-link equipment','Quality gems','Unidentified rare set pieces','Low-level unidentified rare set pieces','Vaal skill gems','Quality flasks and tinctures','Quality weapons','Quality armour'],rareSetSlots:['Jewellery'],minAreaLevel:1,maxAreaLevel:70,minLinks:3,upgradeWindow:15}};
  f.call('export_loot_filter',{baseRevision:f.state.revision,profile});
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(request.profile.campaign,profile.campaign);
  for(const campaign of [{weapons:['Invented weapon']},{defences:['All armour']},{recipes:['Guaranteed profit']},{rareSetSlots:[]},{rareSetSlots:['Jewellery','Jewellery']},{rareSetSlots:['Invented slot']},{minLinks:7},{upgradeWindow:-1}]) {
    assert.throws(()=>f.call('export_loot_filter',{baseRevision:f.state.revision,profile:{...profile,campaign}}),/arguments/);
  }
});

test('queues copied rare equipment for set review', t => {
  const f=fixture(t);const items=['Item Class: Helmets\nRarity: Rare\nIron Hat\nItem Level: 70\nUnidentified'];
  f.call('review_rare_vendor_sets',{baseRevision:f.state.revision,items});
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.equal(request.kind,'review_rare_vendor_sets');assert.deepEqual(request.items,items);
});

test('queues copied quality items for vendor review', t => {
  const f=fixture(t);const items=['Item Class: Wands\nRarity: Normal\nDriftwood Wand\nQuality: +20%'];
  f.call('review_quality_vendor_items',{baseRevision:f.state.revision,items});
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.equal(request.kind,'review_quality_vendor_items');assert.deepEqual(request.items,items);
});

test('queues exact saved filter examples and named appearance snapshots', t => {
  const f=fixture(t);const profile={id:'test',title:'Test',preset:'early_maps',strictness:2,rules:[],sampleSets:[{id:'early',title:'Early drops',samples:[{BaseType:'Iron Hat',AreaLevel:12,HasInfluence:['Shaper']}]}],palettes:[{id:'muted',title:'Muted',theme:'contrast',appearance:{alertVolume:0,textColor:[255,220,100,255]}}]};
  f.call('propose_loot_filters',{title:'Reusable examples',baseRevision:f.state.revision,filters:{schemaVersion:1,activeId:'test',profiles:[profile]}});
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(request.proposal.operations[0].filters.profiles[0],profile);
  for(const sampleSets of [[{id:'empty',title:'Empty',samples:[]}],[{id:'invalid',title:'Invalid',samples:[{BaseType:{nested:'not a property'}}]}]]) {
    assert.throws(()=>f.call('export_loot_filter',{baseRevision:f.state.revision,profile:{...profile,sampleSets}}),/arguments/);
  }
});

test('queues category styles and palette snapshots without changing rule priority', t => {
  const f=fixture(t);const categoryStyles=[{category:'Currency',appearance:{textColor:[255,220,100,255],alertVolume:0}}];
  const profile={id:'test',title:'Test',preset:'early_maps',strictness:2,rules:[],categoryStyles,palettes:[{id:'saved',title:'Saved',appearance:{},categoryStyles}]};
  f.call('export_loot_filter',{baseRevision:f.state.revision,profile});const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(request.profile,profile);
  assert.throws(()=>f.call('export_loot_filter',{baseRevision:f.state.revision,profile:{...profile,categoryStyles:[{category:'Invented category',appearance:{}}]}}),/arguments/);
});
test('reads journey resources and queues a reviewed replacement without applying', t => {
  const f=fixture(t);
  const journey={schemaVersion:1,milestones:[{id:'links',title:'Get links',kind:'gems',dependencies:[]}],wishlist:[],resources:[],ledger:[],stages:[]};
  f.captured.context.journey=journey;f.captured.context.journeyBudget={};f.captured.context.nextActions=[];f.write('context',f.captured);
  assert.deepEqual(f.call('get_build_journey',{}).journey,journey);
  f.call('propose_journey_plan',{title:'Roadmap',baseRevision:f.state.revision,journey});
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(request.proposal.operations[0].type,'set_build_journey');
  assert.deepEqual(request.proposal.operations[0].journey,journey);
});

test('queues native wishlist measurements against the current revision without applying gear', t => {
  const f=fixture(t);
  f.call('measure_journey_upgrades',{baseRevision:f.state.revision});
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(request.kind,'journeyUpgrades');assert.equal(request.baseRevision,f.state.revision);assert.equal(request.proposal,undefined);
});

test('rejects malformed journey data and accepts more than eight entries', t => {
  const f=fixture(t);
  const journey={schemaVersion:1,milestones:[],wishlist:[],resources:[],ledger:[],stages:Array.from({length:20},(_,i)=>({id:`stage-${i}`,title:`Level ${i+1}`,level:i+1}))};
  assert.throws(()=>f.call('propose_journey_plan',{title:'Bad',baseRevision:f.state.revision,journey:{...journey,ledger:[{id:'bad',resourceId:'chaos',kind:'spend',amount:-1,at:1}]}}),/arguments/);
  f.call('propose_journey_plan',{title:'Long guide',baseRevision:f.state.revision,journey});
});

test('reads opted-in desktop context and searches bounded native catalogs', t => {
  const f = fixture(t);
  assert.equal(f.call('get_build_context',{}).context.xml,undefined);
  const result = f.call('search_build_catalog',{kind:'passives',query:'life',limit:1});
  assert.equal(result.total,1); assert.equal(result.matches[0].id,123);
  assert.throws(() => f.call('search_build_catalog',{kind:'gems',query:'Fireball',limit:0}),/arguments/);
});

test('records real client contacts, context receipts and requested test nonces separately', t => {
  const f=fixture(t);f.state.connectionTest={nonce:'test-round-trip'};f.write('state',f.state);
  f.call('get_build_connection',{});
  const receipt=()=>JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-client.json')));
  assert.equal(receipt().testNonce,'test-round-trip');assert.equal(receipt().contextRevision,undefined);
  f.call('get_build_context',{});assert.equal(receipt().contextRevision,f.state.revision);
  f.call('get_proposal_status',{});assert.equal(receipt().contextRevision,f.state.revision);
  f.state.session='another-session';f.write('state',f.state);f.call('get_build_connection',{});assert.equal(receipt().contextRevision,undefined);
});
test('queues a typed proposal bound to session and revision without applying it', t => {
  const f = fixture(t); const result = f.call('propose_build',f.proposal);
  const request = JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(result.status,'queued'); assert.equal(request.id,result.id);
  assert.equal(request.session,f.state.session); assert.deepEqual(request.proposal,f.proposal);
  assert.throws(() => f.call('propose_build',f.proposal),/already queued/);
  assert.equal(f.call('get_build_context',{}).context.level,80);
});
test('rejects disconnected sessions, old context and stale revisions', t => {
  const f = fixture(t);
  f.state.enabled=false; f.write('state',f.state);
  assert.throws(() => f.call('propose_build',f.proposal),/disabled/);
  f.state.enabled=true; f.state.heartbeat=Date.now()/1000-60; f.write('state',f.state);
  assert.throws(() => f.call('get_build_context',{}),/responding/);
  f.state.heartbeat=Date.now()/1000; f.write('state',f.state);
  assert.throws(() => f.call('propose_build',{...f.proposal,baseRevision:'b'.repeat(40)}),/revision changed/);
  f.captured.session='old-session'; f.write('context',f.captured);
  assert.throws(() => f.call('propose_build',f.proposal),/refreshing/);
});
test('rejects unknown operations, arbitrary paths, prototype keys and invalid numbers', t => {
  const f = fixture(t);
  for (const operations of [[{type:'run_lua',code:'anything'}],[{type:'set_character',level:Infinity}],[{type:'equip_item',slot:'Helmet',text:'Item',path:'elsewhere'}]]) {
    assert.throws(() => f.call('propose_build',{...f.proposal,operations}),/arguments/);
  }
  const request = JSON.parse(JSON.stringify(f.proposal).replace('"mode":"new"','"mode":"new","__proto__":{}'));
  assert.throws(() => f.call('propose_build',request),/arguments/);
  assert.equal(fs.existsSync(path.join(f.dir,'AI-build-request.json')),false);
});
test('returns calculated status and blocks replacement while desktop review is pending', t => {
  const f = fixture(t);
  f.state.proposal={id:'candidate-one',status:'review',after:{CombinedDPS:123},warnings:['Check assumptions']}; f.write('state',f.state);
  assert.equal(f.call('get_proposal_status',{}).proposal.after.CombinedDPS,123);
  assert.throws(() => f.call('propose_build',f.proposal),/pending proposal/);
  assert.throws(() => f.call('apply_build',{}),/arguments/);
});


test('diagnoses disabled and stale desktops without requiring an active connection', t => {
  const f=fixture(t);
  f.state.enabled=false; f.write('state',f.state);
  assert.equal(f.call('get_build_connection',{}).status,'disabled');
  f.state.enabled=true; f.state.heartbeat=Date.now()/1000-60; f.write('state',f.state);
  assert.equal(f.call('get_build_connection',{}).status,'stale');
  fs.unlinkSync(path.join(f.dir,'AI-build-state.json'));
  assert.equal(f.call('get_build_connection',{}).status,'unavailable');
});

test('queues goals with finite budgets and known minimum metrics', t => {
  const f=fixture(t);
  assert.throws(() => f.call('set_build_goals',{goal:'survival',budget:10}),/currency/);
  assert.throws(() => f.call('set_build_goals',{goal:'survival',minimums:{invented:10}}),/arguments/);
  f.call('set_build_goals',{goal:'comfort',budget:10,currency:'chaos',minimums:{LifeUnreserved:2000}});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.kind,'plan'); assert.equal(queued.plan.goal,'comfort');
});

test('compares bounded alternatives using matching revisions and dated price sources', t => {
  const f=fixture(t);
  const candidate={...f.proposal,quote:{amount:5,currency:'chaos',source:'Manual listing',quotedAt:Math.floor(Date.now()/1000)}};
  assert.throws(() => f.call('compare_build_candidates',{baseRevision:f.state.revision,candidates:[{...candidate,baseRevision:'b'.repeat(40)}]}),/revision/);
  assert.throws(() => f.call('compare_build_candidates',{baseRevision:f.state.revision,candidates:Array(6).fill(candidate)}),/arguments/);
  assert.throws(() => f.call('propose_build',{...candidate,quote:{...candidate.quote,quotedAt:4102444800}}),/capture time/);
  f.call('compare_build_candidates',{baseRevision:f.state.revision,candidates:[candidate]});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.kind,'compare'); assert.equal(queued.candidates[0].quote.amount,5);
});

test('queues increasing cumulative milestones and rejects character overrides', t => {
  const f=fixture(t);
  const stages=[{title:'Early',level:12,operations:[]},{title:'Later',level:70,operations:[{type:'set_notes',text:'Later links'}]}];
  assert.throws(() => f.call('plan_leveling_build',{baseRevision:f.state.revision,stages:[stages[1],stages[0]]}),/increase/);
  assert.throws(() => f.call('plan_leveling_build',{baseRevision:f.state.revision,stages:[{...stages[0],operations:[{type:'set_character',level:99}]}]}),/arguments/);
  f.call('plan_leveling_build',{baseRevision:f.state.revision,stages});
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).kind,'leveling');
});

test('returns audit evidence and bounded session history', t => {
  const f=fixture(t);
  f.captured.context.audit={dependencies:[{key:'Str',text:'Requirement shortfall'}]};
  f.captured.context.encounter={observations:['Energy Shield was empty.']}; f.write('context',f.captured);
  f.state.history=[{id:'candidate-one',title:'Upgrade'}];f.state.diagnostics={undoDepth:2};f.write('state',f.state);
  assert.equal(f.call('get_build_analysis',{}).audit.dependencies[0].key,'Str');
  assert.equal(f.call('get_build_history',{}).undoDepth,2);
  assert.equal(f.call('get_build_history',{}).history.length,1);
});


test('retries a brief incomplete desktop refresh without reporting a disconnected session', t => {
  const f=fixture(t);const originalRead=fs.readFileSync;let partial=true;
  fs.readFileSync=function(file,...args){if (partial && file === path.join(f.dir,'AI-build-state.json')) {partial=false;return '{';}return originalRead.call(this,file,...args);};
  try {assert.equal(f.call('get_build_context',{}).context.name,'Desktop');assert.equal(partial,false);} finally {fs.readFileSync=originalRead;}
});


function craftingProject() {return {id:'life-helmet',title:'Life helmet',slot:'Helmet',startingItem:'Rarity: NORMAL\nIron Hat\nItem Level: 86',targetItem:'Rarity: RARE\nPlanned Hat\nIron Hat\n+100 to maximum Life',goals:['100 Life'],steps:[{action:'Choose a suitable method in Craft of Exile',stopWhen:'Target modifiers present',onFailure:'Stop at the budget limit'}]};}

test('describes unique crafting continuation and simulation limits to AI clients', () => {
  const descriptions=Object.fromEntries(tools.map(tool=>[tool.name,tool.description]));
  assert.match(descriptions.apply_crafting_action,/unique items, pass the returned itemText and omit initialState/);
  assert.match(descriptions.calculate_crafting,/Supported unique actions.*intrinsic item stats/);
  assert.match(descriptions.simulate_crafting,/Supported unique quality and socket actions.*socket recolouring and random linking use sampled outcomes/);
});

test('queues crafting inspection with exactly one item source and current revision', t => {
  const f=fixture(t);
  assert.throws(()=>f.call('inspect_crafting_item',{baseRevision:f.state.revision}),/exactly one/);
  assert.throws(()=>f.call('inspect_crafting_item',{baseRevision:f.state.revision,slot:'Helmet',itemText:'other'}),/exactly one/);
  f.call('inspect_crafting_item',{baseRevision:f.state.revision,slot:'Helmet',query:'life',limit:5});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.kind,'craftInspect');assert.equal(queued.slot,'Helmet');
});

test('proposes crafting metadata and optional target gear through desktop review', t => {
  const f=fixture(t);const project=craftingProject();
  f.call('propose_crafting_plan',{baseRevision:f.state.revision,project,equipTarget:true});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.deepEqual(queued.proposal.operations.map(op=>op.type),['set_crafting_project','equip_item']);
  assert.equal(queued.proposal.operations[1].text,project.targetItem);
  assert.equal(f.call('get_crafting_projects',{}).projects.length,0);
});

test('accepts long crafting guides and goals for desktop review', t => {
  const f=fixture(t), project=craftingProject();
  project.goals=Array.from({length:20},(_,i)=>`Goal ${i+1}`);
  project.steps=Array.from({length:75},(_,i)=>({action:`Craft step ${i+1}`}));
  f.call('propose_crafting_plan',{baseRevision:f.state.revision,project});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.deepEqual(queued.proposal.operations[0].project,project);
});

test('round-trips structured unique guide actions through desktop review', t => {
  const f=fixture(t);const project=craftingProject();
  project.steps=[{action:"Use 2 Armourer's Scraps",uniqueCraft:{method:'quality',count:2}},{action:'Link sockets with an Omen',uniqueCraft:{method:'omen_connections',count:1}},{action:'Make sockets white',uniqueCraft:{method:'socket_white_bench',count:1}},{action:'Link existing sockets at the crafting bench',uniqueCraft:{method:'socket_bench',count:1}},{action:'Set 4 sockets at the crafting bench',uniqueCraft:{method:'socket_count_bench',count:4}}];
  f.call('propose_crafting_plan',{baseRevision:f.state.revision,project});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.deepEqual(queued.proposal.operations[0].project.steps,project.steps);
  for (const invalid of [{method:'quality',count:21},{method:'omen_connections',count:2},{method:'socket_count_bench',count:7},{method:'unknown',count:1}]) {
    assert.throws(()=>f.call('propose_crafting_plan',{baseRevision:f.state.revision,project:{...project,steps:[{action:'Invalid',uniqueCraft:invalid}]}}),/arguments/);
  }
});

test('accepts structured unique flask enchantment guide steps', t => {
  const f=fixture(t),project=craftingProject();
  project.startingItem='Rarity: UNIQUE\nTaste of Hate\nSapphire Flask\nItem Level: 86';project.slot='Flask 1';
  project.steps=[{action:'Use an Enkindling Orb to roll a utility flask enchantment',uniqueCraft:{method:'enkindling',count:1}}];
  f.call('propose_crafting_plan',{baseRevision:f.state.revision,project});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).proposal.operations[0].project.steps,project.steps);
});

test('preserves typed Harvest enchant actions, goals and inventory states', t => {
  const f=fixture(t);const project=craftingProject();
  project.preferredMethod='harvest_enchant';
  project.nativeRecipe={steps:[{method:'harvest_enchant',enchantId:'WeaponCriticalEnchant'}],targets:[],requirements:{harvestEnchant:'WeaponCriticalEnchant'},initialState:{rarity:'NORMAL',affixes:[],harvestEnchant:'WeaponAreaEnchant'}};
  f.call('propose_crafting_plan',{baseRevision:f.state.revision,project});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.deepEqual(queued.proposal.operations[0].project.nativeRecipe,project.nativeRecipe);
});

test('accepts named crafting recipe alternatives', t => {
  const f=fixture(t),project=craftingProject();
  project.recipeAlternatives=Array.from({length:12},(_,index)=>({name:`Route ${index+1}`,recipe:{steps:[{method:'alchemy'}],targets:[]},trackPickups:index===0}));
  f.call('propose_crafting_plan',{baseRevision:f.state.revision,project});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).proposal.operations[0].project.recipeAlternatives,project.recipeAlternatives);
  assert.throws(()=>f.call('propose_crafting_plan',{baseRevision:f.state.revision,project:{...project,recipeAlternatives:[{name:'Broken',recipe:{steps:[],targets:[]}}]}}),/arguments/);
});

test('rejects invalid crafting evidence and execution fields', t => {
  const f=fixture(t);const project=craftingProject();
  assert.throws(()=>f.call('propose_crafting_plan',{baseRevision:f.state.revision,project:{...project,runCode:'no'}}),/arguments/);
  assert.throws(()=>f.call('propose_crafting_plan',{baseRevision:f.state.revision,project:{...project,targetItem:''},equipTarget:true}),/target item/);
  assert.throws(()=>f.call('propose_crafting_plan',{baseRevision:f.state.revision,project:{...project,simulation:{patch:'3.29',observedAt:1,trials:10,successes:11}}}),/exceed trials/);
});


test('queues native currency actions without applying desktop equipment', t => {
  const f=fixture(t);
  f.call('apply_crafting_action',{baseRevision:f.state.revision,itemText:craftingProject().startingItem,action:{method:'alchemy'},seed:123});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.kind,'craftAction'); assert.equal(queued.action.method,'alchemy');
  assert.equal(queued.proposal,undefined);
});

test('bounds native recipe work and rejects unsupported methods and invalid routes', t => {
  const f=fixture(t);
  const base={baseRevision:f.state.revision,itemText:craftingProject().startingItem,recipe:{steps:[{method:'alchemy'}],targets:[{anyOf:['IncreasedLife1']}]}};
  assert.throws(()=>f.call('simulate_crafting',{...base,options:{trials:2000,maxActions:2000}}),/20000/);
  assert.throws(()=>f.call('simulate_crafting',{...base,recipe:{...base.recipe,steps:[{method:'harvest'}]}}),/arguments/);
  assert.throws(()=>f.call('simulate_crafting',{...base,recipe:{...base.recipe,steps:[{method:'alchemy',onFailure:3}]}}),/route/);
  assert.throws(()=>f.call('simulate_crafting',{...base,recipe:{...base.recipe,steps:[{method:'alchemy',maxAttempts:20}]}}),/target conditions/);
  assert.throws(()=>f.call('simulate_crafting',{...base,options:{prices:{alchemy:1}}}),/currency/);
  f.call('simulate_crafting',{...base,options:{trials:100,maxActions:1,prices:{alchemy:1},currency:'chaos'}});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.kind,'craftSimulate'); assert.equal(queued.options.trials,100);
});


test('queues versioned Atlas searches and routing without changing build context', t => {
  const f=fixture(t);
  const plan={id:'atlas',title:'Essence maps',version:'3.29.1',budget:120,nodes:[],notes:'Start with sustain'};
  assert.equal(f.call('get_atlas_plans',{}).plans.length,0);
  f.call('search_atlas_nodes',{baseRevision:f.state.revision,version:'3.29.1',query:'Essence',limit:20});
  let queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.kind,'atlasSearch'); assert.equal(queued.proposal,undefined);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  f.call('plan_atlas_tree',{baseRevision:f.state.revision,plan,targets:[123],avoid:[456]});
  queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.kind,'atlasConnect'); assert.deepEqual(queued.targets,[123]);
  assert.equal(f.call('get_build_context',{}).context.level,80);
});

test('queues bounded Thread restriction checks', t => {
  const f=fixture(t),baseRevision=f.state.revision;
  f.call('check_thread_restrictions',{baseRevision,areaLevel:73,threads:2,spentThreads:2,spentAbyssThreads:1});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.kind,'atlasThreads');assert.equal(queued.areaLevel,73);assert.equal(queued.threads,2);assert.equal(queued.spentThreads,2);assert.equal(queued.spentAbyssThreads,1);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('check_thread_restrictions',{baseRevision,areaLevel:101,threads:2}),/arguments/);
  assert.throws(()=>f.call('check_thread_restrictions',{baseRevision,areaLevel:73,threads:1.5}),/arguments/);
  assert.throws(()=>f.call('check_thread_restrictions',{baseRevision,areaLevel:73,threads:2,spentAbyssThreads:-1}),/arguments/);
});

test('queues review of a saved crafting project without applying changes', t => {
  const f=fixture(t), args={baseRevision:f.state.revision,projectId:'body'};
  f.call('review_crafting_unlocks',args);
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.kind,'craftUnlockReview');assert.equal(queued.projectId,'body');
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('review_crafting_unlocks',{...args,projectId:'../invalid'}),/arguments/);
});

test('queues a bounded reported region run for Atlas preview', t => {
  const f=fixture(t), plan={id:'atlas',title:'Regions',version:'3.30.0-preview',budget:150,nodes:[],shapedRegions:[{mechanic:'Blight',maps:[{name:'Beach Map',freeThreads:2}]}]};
  const args={baseRevision:f.state.revision,plan,map:'Beach Map',completed:['Blight']};
  f.call('preview_shaped_region_run',args);
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.kind,'atlasRegionRun');assert.deepEqual(queued.plan,plan);assert.deepEqual(queued.completed,['Blight']);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('preview_shaped_region_run',{...args,completed:['Unknown']}),/arguments/);
  assert.throws(()=>f.call('preview_shaped_region_run',{...args,completed:['Blight','Blight']}),/arguments/);
});

test('preserves Atlas effect choices in AI proposals', t => {
  const f=fixture(t);
  const plan={id:'atlas',title:'Choice',version:'3.30.0-preview',budget:150,nodes:[45404],choices:[{node:45404,effect:55878}]};
  f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.deepEqual(queued.proposal.operations[0].plan.choices,plan.choices);
});

test('preserves and validates shaped region observations in Atlas proposals', t => {
  const f=fixture(t), shapedRegions=[{mechanic:'Blight',maps:[{name:'Beach Map',freeThreads:2}]}];
  const plan={id:'atlas',title:'Mapping',version:'3.30.0-preview',budget:150,nodes:[],shapedRegions};
  f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.deepEqual(queued.proposal.operations[0].plan.shapedRegions,shapedRegions);
  assert.throws(()=>f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan:{...plan,shapedRegions:[{mechanic:'Invented',maps:[]}]}}),/arguments/);
});

test('preserves multiple map drafts in Atlas proposals', t => {
  const f=fixture(t), mapDrafts=Array.from({length:12},(_,i)=>({id:`map-${i}`,title:`Map ${i}`,patch:'3.30.0.2.2',baseId:'Metadata/Items/Maps/MapWorldsStrand',tier:16,itemLevel:83,rarity:'normal',selected:[]}));
  mapDrafts[0].quality={kind:'Pack Size',value:20};
  mapDrafts[0].observedEffects=[{kind:'implicit',text:"Area is Influenced by the Originator's Memories"}];
  mapDrafts[0]={...mapDrafts[0],rarity:'rare',selected:['MapMonsterAreaOfEffectMapWorlds'],rolls:[{id:'MapMonsterAreaOfEffectMapWorlds',values:[13,8,5,45]}],estimate:{wantedGroups:[['MapMonsterAreaOfEffectMapWorlds']],avoid:['MapContainsMirageWorlds'],trials:20,maxAttempts:5}};
  mapDrafts[1]={...mapDrafts[1],rarity:'rare',corrupted:true,vaalPreview:true,implicit:{id:'MapCorruptionItemRarity',value:15}};
  mapDrafts[2]={...mapDrafts[2],baseId:'Metadata/Items/Maps/MapWorldsAbomination',tier:17,itemLevel:84,rarity:'rare',selected:['MapUberModCurses']};
  const plan={id:'atlas',title:'Mapping',version:'3.30.0-preview',budget:150,nodes:[],mapDrafts};
  f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.deepEqual(queued.proposal.operations[0].plan.mapDrafts,mapDrafts);
  assert.throws(()=>f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan:{...plan,mapDrafts:[{...mapDrafts[0],rarity:'unique'}]}}),/arguments/);
});

test('queues a read-only Atlas stage comparison', t => {
  const f=fixture(t);
  const before={id:'before',title:'Before',version:'3.29.3',budget:20,nodes:[]};
  const after={...before,id:'after',title:'After',nodes:[123]};
  f.call('compare_atlas_plans',{baseRevision:f.state.revision,before,after});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.kind,'atlasTransition');assert.deepEqual(queued.before,before);assert.deepEqual(queued.after,after);
  assert.throws(()=>f.call('compare_atlas_plans',{baseRevision:'0'.repeat(40),before,after}),/revision/i);
});

test('keeps Atlas proposals in the desktop review flow and rejects unsupported versions', t => {
  const f=fixture(t);
  const plan={id:'atlas',title:'Essence maps',version:'3.27.0',budget:120,nodes:[]};
  assert.throws(() => f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan:{...plan,version:'3.28.0'}}),/arguments/);
  assert.throws(() => f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan:{...plan,code:'anything'}}),/arguments/);
  assert.throws(() => f.call('plan_atlas_tree',{baseRevision:f.state.revision,plan,targets:Array(31).fill(123)}),/arguments/);
  f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.proposal.operations[0].type,'set_atlas_plan');
  assert.equal(queued.proposal.operations[0].plan.version,'3.27.0');
});


test('provides searchable, paged Genesis data to AI clients', t => {
  const f=fixture(t),first=f.call('get_genesis_tree',{limit:10});
  assert.equal(first.total,133);assert.equal(first.nodes.length,10);assert.equal(first.nextOffset,10);
  assert.equal(first.pointReference.branches.Equipment.publishedMaximum,16);assert.match(first.pointReference.branches.Equipment.source,/3985332/);
  const currency=f.call('get_genesis_tree',{branch:'Currency',query:'Foulborn'});
  assert.ok(currency.nodes.some(node=>node.id===40721 && node.stats.some(line=>line.includes('6% chance'))));
  assert.ok(currency.nodes.every(node=>node.root===currency.roots.Currency));
  assert.throws(()=>f.call('get_genesis_tree',{branch:'Unknown'}),/arguments/);
});

test('preserves Genesis allocations in reviewed Atlas proposals', t => {
  const f=fixture(t),genesis={version:'3.30.0d',nodes:[19912,53412]};
  const plan={id:'atlas',title:'Atlas',version:'3.30.0c',budget:20,nodes:[],genesis};
  f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.deepEqual(queued.proposal.operations[0].plan.genesis,genesis);
});

test('queues Omen of Trichromatism actions through the typed crafting protocol', t => {
  const f=fixture(t);const args={baseRevision:f.state.revision,itemText:'Rarity: NORMAL\nPlate Vest\nItem Level: 86\nSockets: W-W-W',action:{method:'omen_trichromatism'}};
  f.call('apply_crafting_action',args);
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.deepEqual(request.action,args.action);
});

test('queues advanced crafting states and rejects untyped execution data', t => {
  const f=fixture(t);
  const args={baseRevision:f.state.revision,itemText:craftingProject().startingItem,action:{method:'fossil',fossils:['Metadata/Items/Currency/CurrencyDelveCraftingLife']},initialState:{rarity:'RARE',affixes:[],influences:[],quality:20,sockets:[{color:'W',group:0}],catalyst:8,catalystQuality:20,baseImplicitRanges:[[0,1]],baseImplicit330:true}};
  f.call('apply_crafting_action',args);
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.deepEqual(queued.initialState,args.initialState);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('apply_crafting_action',{...args,initialState:{...args.initialState,runCode:'no'}}),/arguments/);
  assert.throws(()=>f.call('apply_crafting_action',{...args,initialState:{...args.initialState,baseImplicit330:false}}),/arguments/);
  const reconstructed={...args.initialState,baseImplicitReconstructed:true,baseImplicitRetained:true};delete reconstructed.baseImplicit330;
  f.call('apply_crafting_action',{...args,initialState:reconstructed});fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('apply_crafting_action',{...args,initialState:{...reconstructed,baseImplicitReconstructed:false}}),/arguments/);
  assert.throws(()=>f.call('apply_crafting_action',{...args,initialState:{...reconstructed,baseImplicitRetained:false}}),/arguments/);
  assert.throws(()=>f.call('apply_crafting_action',{...args,action:{method:'recombine',donorItem:'item',path:'elsewhere'}}),/arguments/);
});

test('accepts corrupted flask quality and quality targets up to forty', t => {
  const f=fixture(t);const raw='Rarity: NORMAL\nSmall Life Flask\nItem Level: 86';
  const args={baseRevision:f.state.revision,itemText:raw,action:{method:'vaal'},initialState:{rarity:'NORMAL',affixes:[],quality:40,corrupted:true}};
  f.call('apply_crafting_action',args);fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('apply_crafting_action',{...args,initialState:{...args.initialState,quality:41}}),/arguments/);
  f.call('calculate_crafting',{baseRevision:f.state.revision,itemText:raw,action:{method:'vaal'},targets:[],options:{requirements:{minQuality:40}}});
});

test('preserves typed twice-corruption flags in crafting requests', t => {
  const f=fixture(t);
  const args={baseRevision:f.state.revision,itemText:craftingProject().startingItem,action:{method:'tainted_chromatic'},initialState:{rarity:'NORMAL',affixes:[],corrupted:true,twiceCorrupted:true}};
  f.call('apply_crafting_action',args);
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.deepEqual(queued.initialState,args.initialState);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('apply_crafting_action',{...args,initialState:{...args.initialState,twiceCorrupted:'true'}}),/arguments/);
  const recipe={steps:[{method:'locus',untilRequirements:{twiceCorrupted:true}}],targets:[],requirements:{twiceCorrupted:true}};
  f.call('simulate_crafting',{baseRevision:f.state.revision,itemText:args.itemText,recipe});
  const plan=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(plan.recipe,recipe);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('simulate_crafting',{baseRevision:f.state.revision,itemText:args.itemText,recipe:{...recipe,requirements:{twiceCorrupted:'true'}}}),/arguments/);
});

test('queues property-only recipes, exact odds and bounded fossil optimization', t => {
  const f=fixture(t);const base={baseRevision:f.state.revision,itemText:craftingProject().startingItem};
  f.call('simulate_crafting',{...base,recipe:{steps:[{method:'quality',maxAttempts:20,untilRequirements:{minQuality:20}}],targets:[],requirements:{minQuality:20}},options:{trials:10,maxActions:20}});
  let queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.equal(queued.kind,'craftSimulate');
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  f.call('calculate_crafting',{...base,action:{method:'exalt'},targets:[{anyOf:['IncreasedLife1'],negate:true,atLeast:1}]});
  queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.equal(queued.kind,'craftCalculate');
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  f.call('optimize_crafting_fossils',{...base,targets:[{anyOf:['IncreasedLife1']}],options:{fossils:['life','mana'],maxSockets:2,trials:10}});
  queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.equal(queued.kind,'craftOptimize');
});

test('queues crafting cancellation with an explicit request identifier', t => {
  const f=fixture(t);f.state.status='calculating';f.state.id='active-craft';f.write('state',f.state);
  f.call('cancel_crafting_simulation',{requestId:'active-craft'});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.kind,'craftCancel');assert.equal(queued.requestId,'active-craft');
  assert.equal(queued.proposal,undefined);
});

test('queues observed predictable selections with bounded typed odds', t => {
  const f=fixture(t);
  const args={baseRevision:f.state.revision,itemText:craftingProject().startingItem,action:{method:'recombine_predictable',donorItem:'donor',selectedMods:{left:['IncreasedLife1'],right:['FireResist1']},reportedSuccessChance:40,observedRecipientState:{rarity:'MAGIC',affixes:[{id:'IncreasedLife1',range:0.75}],origin:'a'.repeat(40)}}};
  f.call('apply_crafting_action',args);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).action,args.action);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('apply_crafting_action',{...args,action:{...args.action,reportedSuccessChance:101}}),/arguments/);
	assert.throws(()=>f.call('apply_crafting_action',{...args,action:{...args.action,observedRecipientState:{rarity:'MAGIC',affixes:'invalid'}}}),/arguments/);
  assert.throws(()=>f.call('apply_crafting_action',{...args,action:{...args.action,selectedMods:{left:[],right:['FireResist1']}}}),/arguments/);
});

test('queues observed Allflame profiles without allowing unbounded ghost work', t => {
  const f=fixture(t);
  const args={baseRevision:f.state.revision,itemText:craftingProject().startingItem,action:{method:'exalt',allflame:{outcomes:4,gainMin:8,gainMax:12,sulphur:100,preferredTargets:[{anyOf:['FireResist1']}]}},initialState:{rarity:'RARE',affixes:[],intangibility:30}};
  f.call('apply_crafting_action',args);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).action,args.action);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('apply_crafting_action',{...args,action:{...args.action,allflame:{...args.action.allflame,outcomes:1000}}}),/arguments/);
  assert.throws(()=>f.call('apply_crafting_action',{...args,initialState:{...args.initialState,intangibility:101}}),/arguments/);
});


test('queues automatic Allflame profiles and typed fracture goals', t => {
  const f=fixture(t);const base={baseRevision:f.state.revision,itemText:craftingProject().startingItem};
  const action={method:'ducat_kishara',allflame:{auto:true,upgradeTier:2}};
  f.call('inspect_crafting_item',{...base,action});
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  const recipe={steps:[action],targets:[{anyOf:['IncreasedLife1'],fractured:true,crafted:false}],requirements:{minFractured:1,maxFractured:2,maxIntangibility:50}};
  f.call('simulate_crafting',{...base,recipe,options:{trials:10,maxActions:1,retainSuccesses:3,baseCost:5,currency:"chaos"}});
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  for (const allflame of [{auto:true,outcomes:4},{auto:false},{auto:true,upgradeTier:3}]) {
    assert.throws(()=>f.call('apply_crafting_action',{...base,action:{...action,allflame}}),/arguments/);
  }
  assert.throws(()=>f.call('simulate_crafting',{...base,recipe:{...recipe,requirements:{minFractured:7}}}),/arguments/);
});


test('accepts the pinned 150 point Atlas preview without inventing future versions', t => {
  const f=fixture(t);const plan={id:'covens',title:'Covens preview',version:'3.30.0-preview',budget:150,nodes:[]};
  f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan});
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.equal(request.proposal.operations[0].plan.budget,150);
  assert.throws(()=>f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan:{...plan,budget:151}}),/arguments/);
  assert.throws(()=>f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan:{...plan,version:'3.31.0'}}),/arguments/);
});

test('queues searches and plans for the pinned Ruthless Atlas', t => {
  const f=fixture(t);const base={baseRevision:f.state.revision};const version='3.30.0-preview-ruthless';
  f.call('search_atlas_nodes',{...base,version,query:'Searing Exarch',limit:10});
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).version,version);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  f.call('plan_atlas_tree',{...base,plan:{id:'ruthless',title:'Ruthless',version,budget:150,nodes:[]},targets:[57123]});
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).plan.version,version);
});

test('accepts the 3.30.0c Atlas in both modes', t => {
  const f=fixture(t);const base={baseRevision:f.state.revision};
  for(const version of ['3.30.0c','3.30.0c-ruthless']) {
    f.call('search_atlas_nodes',{...base,version,query:'Celestial Presence',limit:10});
    assert.equal(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).version,version);
    fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  }
});

test('accepts bundled historical Atlas versions', t => {
  const f=fixture(t);const base={baseRevision:f.state.revision};
  for(const version of ['3.27.0-ruthless','3.28.0j','3.28.0j-ruthless','3.29.1-ruthless','3.29.3-ruthless']){
    f.call('search_atlas_nodes',{...base,version,query:'Beyond',limit:10});
    assert.equal(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).version,version);
    fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  }
});


test('validates and preserves partial target counts on crafting steps', t => {
  const f=fixture(t);const base={baseRevision:f.state.revision,itemText:craftingProject().startingItem};
  const step={method:'quality',untilTargets:[{anyOf:['one']},{anyOf:['two']}],untilRequiredGroups:1};
  const recipe={steps:[step],targets:[],requirements:{minQuality:20}};
  f.call('simulate_crafting',{...base,recipe});
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).recipe.steps[0].untilRequiredGroups,1);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  for (const invalid of [{...step,untilRequiredGroups:3},{method:'quality',untilRequiredGroups:0}])
    assert.throws(()=>f.call('simulate_crafting',{...base,recipe:{...recipe,steps:[invalid]}}),/target count/);
});

test('queues offline appearance, colour goals and optimized Atlas routing', t => {
  const f=fixture(t);const base={baseRevision:f.state.revision};
  const profile={id:'local',title:'Local',preset:'campaign',strictness:1,rules:[],appearance:{minimumFontSize:40,alertVolume:0,disableEffects:true}};
  f.call('export_loot_filter',{...base,profile});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).profile.appearance,profile.appearance);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  const recipe={steps:[{method:'chromatic',maxAttempts:10,untilRequirements:{socketColours:'RRBG',linkedColours:true}}],targets:[],requirements:{socketColours:'RRBG',linkedColours:true}};
  f.call('simulate_crafting',{...base,itemText:craftingProject().startingItem,recipe,options:{trials:10,maxActions:10}});
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  f.call('calculate_crafting',{...base,itemText:craftingProject().startingItem,action:{method:'chromatic'},targets:[],options:{trials:10,requirements:{socketColours:'RRBG',linkedColours:true}}});
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  f.call('plan_atlas_tree',{...base,plan:{id:'atlas',title:'Atlas',version:'3.30.0-preview',budget:150,nodes:[]},targets:[123],optimize:true});
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).optimize,true);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('export_loot_filter',{...base,profile:{...profile,appearance:{alertVolume:301}}}),/arguments/);
  assert.throws(()=>f.call('simulate_crafting',{...base,itemText:craftingProject().startingItem,recipe:{...recipe,requirements:{socketColours:'RGX'}}}),/arguments/);
});

test('queues bounded Abyss socket goals in recipes and step conditions', t => {
  const f=fixture(t), base={baseRevision:f.state.revision,itemText:craftingProject().startingItem};
  const recipe={steps:[{method:'fossil',fossils:['Metadata/Items/Currency/CurrencyDelveCraftingAbyss'],untilRequirements:{minAbyssSockets:1}}],targets:[],requirements:{minAbyssSockets:1}};
  f.call('simulate_crafting',{...base,recipe,options:{trials:2,maxActions:1}});
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(request.recipe,recipe);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  for(const invalid of [-1,7,1.5]) assert.throws(()=>f.call('simulate_crafting',{...base,recipe:{...recipe,requirements:{minAbyssSockets:invalid}}}),/arguments/);
});

test('queues exact socket goals and rejects out-of-range counts', t => {
  const f=fixture(t),base={baseRevision:f.state.revision,itemText:craftingProject().startingItem};
  const recipe={steps:[{method:'socket_bench',count:3}],targets:[],requirements:{exactSockets:3}};
  f.call('simulate_crafting',{...base,recipe,options:{trials:1,maxActions:1}});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).recipe,recipe);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  for(const invalid of [-1,7,1.5]) assert.throws(()=>f.call('simulate_crafting',{...base,recipe:{...recipe,requirements:{exactSockets:invalid}}}),/arguments/);
});

test('queues a saved crafting simulation without allowing mixed inputs', t => {
  const f=fixture(t),baseRevision=f.state.revision;
  f.call('simulate_crafting',{baseRevision,projectId:'helmet-guide'});
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(request.kind,'craftSimulate');assert.equal(request.projectId,'helmet-guide');
  for(const extra of [{recipe:{steps:[{method:'alchemy'}],targets:[],requirements:{minAffixes:1}}},{itemText:craftingProject().startingItem},{slot:'Helmet'},{options:{trials:1}}])
    assert.throws(()=>f.call('simulate_crafting',{baseRevision,projectId:'helmet-guide',...extra}),/saved projectId/);
  assert.throws(()=>f.call('simulate_crafting',{baseRevision}),/recipe/);
});

test('queues a named saved crafting alternative with bounded options', t => {
  const f=fixture(t),baseRevision=f.state.revision;
  f.call('simulate_crafting',{baseRevision,projectId:'helmet-guide',alternativeName:'Life route',options:{trials:20,maxActions:10,seed:7}});
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(request.alternativeName,'Life route');assert.equal(request.options.trials,20);
  for(const bad of [
    {alternativeName:'Life route',recipe:{steps:[{method:'alchemy'}],targets:[],requirements:{minAffixes:1}}},
    {projectId:'helmet-guide',alternativeName:'  '},
    {projectId:'helmet-guide',alternativeName:'Life route',itemText:craftingProject().startingItem},
    {projectId:'helmet-guide',alternativeName:'Life route',options:{trials:2000,maxActions:2000}},
  ]) assert.throws(()=>f.call('simulate_crafting',{baseRevision,...bad}),/alternative|budgeted|saved projectId/);
});

test('queues a bounded comparison of named crafting alternatives', t => {
  const f=fixture(t),baseRevision=f.state.revision;
  f.call('compare_crafting_alternatives',{baseRevision,projectId:'helmet-guide',names:['Life','Armour'],options:{trials:20,maxActions:10,seed:7}});
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(request.kind,'craftCompareAlternatives');assert.deepEqual(request.names,['Life','Armour']);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  f.call('compare_crafting_alternatives',{baseRevision,projectId:'helmet-guide',names:Array.from({length:12},(_,i)=>`Route ${i+1}`),options:{trials:1,maxActions:1}});
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  f.call('compare_crafting_alternatives',{baseRevision,projectId:'helmet-guide',includePrimary:true,names:['Life'],options:{trials:2,maxActions:1}});
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).includePrimary,true);
  for(const bad of [
    {names:['Life']},{names:['Life','Armour'],reference:'primary'},{names:['Life','Life']},{names:['Life','  ']},{names:['Life','Armour'],options:{trials:2000,maxActions:2000}},
    {names:['Life','Armour'],options:{trials:2,maxActions:1,prices:{alchemy:3}}},
    {includePrimary:true,names:['Life','Armour'],options:{trials:100,maxActions:100}},
  ]) assert.throws(()=>f.call('compare_crafting_alternatives',{baseRevision,projectId:'helmet-guide',...bad}),/arguments|names|routes|budgeted|currency|reference/);
});

test('accepts observed Rog offers and rejects invalid attempt counts', t => {
  const f=fixture(t), base={baseRevision:f.state.revision,itemText:craftingProject().startingItem};
  const action={method:'rog_reroll',rogSide:'Suffix',rogOperation:'add',rogAttempts:5,artifactCost:{grand:12}};
  const recipe={steps:[action],targets:[],requirements:{minAffixes:1}};
  f.call('simulate_crafting',{...base,recipe,options:{trials:2,maxActions:1}});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).recipe,recipe);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  const removal={method:'rog_reroll',rogOperation:'remove_lowest_two',artifactCost:{lesser:20}};
  f.call('calculate_crafting',{...base,action:removal,targets:[],options:{requirements:{minAffixes:1}}});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).action,removal);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  const fill={method:'rog_reroll',rogOperation:'fill',artifactCost:{grand:7}};
  f.call('calculate_crafting',{...base,action:fill,targets:[],options:{requirements:{minAffixes:6}}});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).action,fill);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  const quality={method:'rog_reroll',rogOperation:'set_quality',artifactCost:{grand:7}};
  f.call('calculate_crafting',{...base,action:quality,targets:[],options:{requirements:{minQuality:20}}});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).action,quality);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  const upgrade={method:'rog_reroll',rogOperation:'upgrade',count:2,artifactCost:{grand:7}};
  f.call('calculate_crafting',{...base,action:upgrade,targets:[],options:{requirements:{minAffixes:1}}});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).action,upgrade);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  for (const highest of [{method:'rog_reroll',rogOperation:'upgrade_highest',count:2},{method:'rog_reroll',rogOperation:'upgrade_highest_all'}]) {
    f.call('calculate_crafting',{...base,action:highest,targets:[],options:{requirements:{minAffixes:1}}});
    assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).action,highest);
    fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  }
  const values={method:'rog_reroll',rogOperation:'values_side',rogSide:'Suffix',rogAttempts:5,artifactCost:{grand:7}};
  f.call('calculate_crafting',{...base,action:values,targets:[],options:{requirements:{minAffixes:1}}});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).action,values);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  const implicit={method:'rog_reroll',rogOperation:'values_implicit',rogAttempts:3};
  f.call('calculate_crafting',{...base,action:implicit,targets:[],options:{requirements:{minAffixes:1}}});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).action,implicit);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  const sockets={method:'rog_reroll',rogOperation:'socket_links',rogSocketRolls:30,artifactCost:{grand:7}};
  f.call('calculate_crafting',{...base,action:sockets,targets:[],options:{requirements:{links:4}}});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).action,sockets);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('calculate_crafting',{...base,action:{...sockets,rogSocketRolls:9},targets:[],options:{requirements:{links:4}}}),/arguments/);
  assert.throws(()=>f.call('calculate_crafting',{...base,action:{...upgrade,count:7},targets:[],options:{requirements:{minAffixes:1}}}),/arguments/);
  assert.throws(()=>f.call('calculate_crafting',{...base,action:{...action,rogAttempts:6},targets:[],options:{requirements:{minAffixes:1}}}),/arguments/);
  assert.throws(()=>f.call('calculate_crafting',{...base,action:{...action,rogOperation:'remove'},targets:[],options:{requirements:{minAffixes:1}}}),/arguments/);
});

test('accepts supported influence goals in recipes and calculations', t => {
  const f=fixture(t), base={baseRevision:f.state.revision,itemText:craftingProject().startingItem};
  const action={method:'gwennen',firstOutcome:1031,secondOutcome:1031};
  const recipe={steps:[{...action,untilRequirements:{influence:'shaper'}}],targets:[],requirements:{influence:'elder'}};
  f.call('simulate_crafting',{...base,recipe,options:{trials:2,maxActions:1}});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).recipe,recipe);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  f.call('calculate_crafting',{...base,action,targets:[],options:{requirements:{influence:'crusader'}}});
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('calculate_crafting',{...base,action,targets:[],options:{requirements:{influence:'tangle'}}}),/arguments/);
});

test('queues native item stat goals with decimal thresholds and rejects unknown stats', t => {
  const f=fixture(t);const base={baseRevision:f.state.revision,itemText:craftingProject().startingItem};
  const recipe={steps:[{method:'quality',maxAttempts:20,untilRequirements:{nativeStats:{PhysicalDPS:12.4}}}],targets:[],requirements:{nativeStats:{PhysicalDPS:12.4,AttackRate:1.55}}};
  f.call('simulate_crafting',{...base,recipe,options:{trials:3,maxActions:20}});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).recipe,recipe);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  for (const nativeStats of [{Life:1},{AttackRate:-1},{PhysicalDPS:1e8},{CritChance:'5'}]) {
    assert.throws(()=>f.call('simulate_crafting',{...base,recipe:{...recipe,requirements:{nativeStats}}}),/arguments/);
  }
});


test('queues saved resource quotes with crafting guides and simulations', t => {
  const f=fixture(t);const priceBook={currency:'chaos',source:'Manual test quote',quotedAt:1700000000,values:{wild_lifeforce:0.1,exalt:0}};
  const project={...craftingProject(),priceBook};f.call('propose_crafting_plan',{baseRevision:f.state.revision,project});
  let queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(queued.proposal.operations[0].project.priceBook,priceBook);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  f.call('simulate_crafting',{baseRevision:f.state.revision,itemText:project.startingItem,recipe:{steps:[{method:'alchemy'}],targets:[],requirements:{minAffixes:1}},options:{priceBook}});
  queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(queued.options.priceBook,priceBook);
  assert.throws(()=>f.call('propose_crafting_plan',{baseRevision:f.state.revision,project:{...project,priceBook:{...priceBook,values:{exalt:-1}}}}),/arguments/);
});


test('queues exact action totals independently of resource quotes',t=>{
  const f=fixture(t);const priceBook={currency:'chaos',source:'Saved quotes',quotedAt:1700000000,values:{alchemy:1}};
  const base={baseRevision:f.state.revision,itemText:craftingProject().startingItem};
  for(const name of ['simulate_crafting','optimize_crafting_fossils']){
    const args=name==='simulate_crafting'?{...base,recipe:{steps:[{method:'alchemy'}],targets:[],requirements:{minAffixes:1}},options:{priceBook,actionPrices:{alchemy:7}}}:{...base,targets:[],options:{fossils:['life'],priceBook,actionPrices:{'fossil:life':0}}};
    f.call(name,args);const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
    assert.deepEqual(queued.options.actionPrices,args.options.actionPrices);assert.deepEqual(queued.options.priceBook,priceBook);
    fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
    assert.throws(()=>f.call(name,{...args,options:{...args.options,actionPrices:{alchemy:-1}}}),/arguments/);
    assert.throws(()=>f.call(name,{...args,options:{...args.options,actionPrices:{alchemy:Infinity}}}),/arguments/);
    const unquoted={...args.options,actionPrices:{alchemy:7}};delete unquoted.priceBook;delete unquoted.currency;
    assert.throws(()=>f.call(name,{...args,options:unquoted}),/price currency/);
  }
});


test('queues bounded beast levels for actions and saved recipes', t => {
  const f=fixture(t), itemText=craftingProject().startingItem;
  const action={method:'beast_prefix_suffix',beastLevel:86};
  f.call('apply_crafting_action',{baseRevision:f.state.revision,itemText,action});
  let request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.deepEqual(request.action,action);
  fs.rmSync(path.join(f.dir,'AI-build-request.json'));
  const recipe={steps:[action],targets:[]};
  f.call('simulate_crafting',{baseRevision:f.state.revision,itemText,recipe});
  request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.deepEqual(request.recipe,recipe);
  fs.rmSync(path.join(f.dir,'AI-build-request.json'));
  for (const beastLevel of [0,101,1.5,'86']) assert.throws(()=>f.call('apply_crafting_action',{baseRevision:f.state.revision,itemText,action:{...action,beastLevel}}),/arguments/);
});


test('preserves bounded stack tier settings in filter proposals', t => {
  const f=fixture(t), text='Show\n BaseType == "Chaos Orb"';
  const tiers=[{id:'low',title:'Low',text,items:['Chaos Orb'],stackRules:Array.from({length:19},(_,i)=>({minimum:i+2,styleTierId:'high'}))},{id:'high',title:'High',text,items:[]}];
  const profile={id:'stacks',title:'Stacks',preset:'endgame',strictness:2,rules:[],tiers};
  const args={title:'Stacked currency',baseRevision:f.state.revision,filters:{schemaVersion:1,activeId:'stacks',profiles:[profile]}};
  f.call('propose_loot_filters',args);
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.deepEqual(queued.proposal.operations[0].filters.profiles[0].tiers,tiers);
  fs.rmSync(path.join(f.dir,'AI-build-request.json'));
  for (const minimum of [1,0,2.5,1000000001]) {
    const invalid=structuredClone(args);invalid.filters.profiles[0].tiers[0].stackRules[0].minimum=minimum;
    assert.throws(()=>f.call('propose_loot_filters',invalid),/arguments/);
  }
});


test('accepts a named Bestiary flask action and recipe', t => {
  const f=fixture(t), itemText='Rarity: NORMAL\nSmall Life Flask\nItem Level: 86';
  const action={method:'beast_flask',modId:'FlaskChillFreezeImmunity1'};
  f.call('apply_crafting_action',{baseRevision:f.state.revision,itemText,action});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).action,action);
  fs.rmSync(path.join(f.dir,'AI-build-request.json'));
  const recipe={steps:[action],targets:[{anyOf:[action.modId]}]};
  f.call('simulate_crafting',{baseRevision:f.state.revision,itemText,recipe});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).recipe,recipe);
});

test('queues paged Bestiary modifier inspection and validates the offset', t => {
  const f=fixture(t), action={method:'beast_prefix_suffix',beastLevel:86};
  const args={baseRevision:f.state.revision,itemText:'Rarity: NORMAL\nIron Hat\nItem Level: 20',action,query:'resistance',limit:3,beastOffset:3};
  f.call('inspect_crafting_item',args);
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.equal(request.beastOffset,3);assert.deepEqual(request.action,action);
  fs.rmSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('inspect_crafting_item',{...args,action:{method:'chaos'}}),/beastOffset/);
  assert.throws(()=>f.call('inspect_crafting_item',{...args,beastOffset:-1}),/arguments/);
  assert.throws(()=>f.call('inspect_crafting_item',{...args,beastOffset:1.5}),/arguments/);
});
