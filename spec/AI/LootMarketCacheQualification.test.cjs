'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const { qualifyCache }=require('../../tools/check_loot_market_cache.cjs');

const now=Date.UTC(2026,10,23);
const root='https://cache.example.test/pob-market/';
const exchange={core:{primary:'chaos'},items:[{id:'alt',name:'Orb of Alteration'}],
  lines:[{id:'alt',primaryValue:0.2,volumePrimaryValue:400}]};
const gems={lines:[{name:'Arc',detailsId:'arc-20-20',gemLevel:20,gemQuality:20,corrupted:false,
  chaosValue:30,count:50,listingCount:41}]};

function fixture(overrides = {}) {
  const requests=[];
  const fetcher=async(raw,options)=>{
    assert.ok(raw.startsWith(root));
    assert.equal(options.redirect,'error');
    const url=new URL(raw);
    const name=url.searchParams.get('type') ?? url.pathname.split('/').at(-1);
    requests.push(name);
    if (overrides[name]) return overrides[name]();
    const payload=name==='health' ? {status:'ready',cached:0,pending:0}
      : name==='leagues' ? [{id:'Covens',name:'Covens of Umbra'}]
      : name==='SkillGem' ? gems : exchange;
    return response(payload);
  };
  return {requests,fetcher,now:()=>now};
}

function response(payload,headers={}) {
  return new Response(JSON.stringify(payload),{headers:{Date:new Date(now).toUTCString(),Age:'37',...headers}});
}

test('qualifies the core market and only the optional feeds requested',async()=>{
  const f=fixture();
  const report=await qualifyCache(root,{...f,extra:['SkillGem','SkillGem']});
  assert.equal(report.status,'passed');
  assert.equal(report.league,'Covens');
  assert.equal(f.requests.length,11);
  assert.equal(f.requests.filter(name=>name==='SkillGem').length,1);
  assert.equal(report.probes.at(-1).freshnessSeconds,37);
  assert.equal(report.probes.at(-1).exactGemQuotes,1);
});

test('includes bounded relay diagnostics while qualifying actual feed responses',async()=>{
  const f=fixture({health:()=>response({
    status:'ready',cached:2,pending:0,cachedBytes:500,serviceable:1,hits:8,requests:5,
    rejections:{client:2,queue:0,cooldown:1,unexpected:'private metadata'},
    provider:{state:'degraded',lastValidatedAt:now-1000,cooldownSeconds:0,successes:4,failures:1,
      lastFailure:{at:now,reason:'invalid_response',httpStatus:200,message:'private provider body'}},
    unexpected:'private host',
  })});
  const report=await qualifyCache(root,f);
  assert.equal(report.status,'passed');
  assert.deepEqual(report.probes[0],{
    name:'Cache health',status:'passed',cached:2,pending:0,cachedBytes:500,serviceable:1,hits:8,requests:5,
    rejections:{client:2,queue:0,cooldown:1},
    provider:{state:'degraded',lastValidatedAt:now-1000,cooldownSeconds:0,successes:4,failures:1,
      lastFailure:{at:now,reason:'invalid_response',httpStatus:200}},
  });
  assert.equal(f.requests.length,10);
  assert.doesNotMatch(JSON.stringify(report),/private/);
});

test('stops on throttling and reports retry timing',async()=>{
  const f=fixture({Currency:()=>new Response(null,{status:429,headers:{'Retry-After':'60'}})});
  const report=await qualifyCache(root,f);
  assert.equal(report.status,'failed');
  assert.deepEqual(f.requests,['health','leagues','Currency']);
  assert.deepEqual(report.probes.at(-1),{name:'Currency',status:'failed',httpStatus:429,retryAfter:'60'});
});

test('rejects invalid destinations and unlisted league before issuing price calls',async()=>{
  const f=fixture();
  await assert.rejects(qualifyCache('https://user:password@cache.example.test/pob-market/',f),/without credentials/);
  await assert.rejects(qualifyCache(root,{...f,extra:['Trade']}),/supported optional/);
  assert.equal(f.requests.length,0);
  const report=await qualifyCache(root,{...f,league:'Missing'});
  assert.equal(report.status,'failed');
  assert.deepEqual(f.requests,['health','leagues']);
});

test('reports incomplete currency and optional gem evidence, stale data, and provider denial',async()=>{
  const f=fixture({
    Currency:()=>response({...exchange,lines:[{...exchange.lines[0],volumePrimaryValue:3}]}),
    Oil:()=>response(exchange,{Age:'3601'}),
    SkillGem:()=>response({lines:[{...gems.lines[0],corrupted:undefined}]}),
    ImbuedGem:()=>new Response(null,{status:403}),
  });
  const report=await qualifyCache(root,{...f,extra:['SkillGem','ImbuedGem']});
  assert.equal(report.status,'failed');
  const probes=Object.fromEntries(report.probes.map(probe=>[probe.name,probe]));
  assert.match(probes.Currency.reason,/liquid Orb/);
  assert.match(probes.Oil.reason,/stale/);
  assert.match(probes.SkillGem.reason,/consistent level/);
  assert.equal(probes.ImbuedGem.httpStatus,403);
});

test('does not qualify regular gems from transfigured or ambiguous names alone',async()=>{
  const f=fixture({SkillGem:()=>response({lines:[
    {...gems.lines[0],name:'Arc of Surging',baseType:'Arc'},
    gems.lines[0],
    {...gems.lines[0],detailsId:'second-arc-price'},
  ]})});
  const report=await qualifyCache(root,{...f,extra:['SkillGem']});
  assert.equal(report.status,'failed');
  assert.match(report.probes.at(-1).reason,/unambiguous/);
});

test('qualifies canonical gem labels while rejecting conflicting or incomplete rows',async()=>{
  const legacy=gems.lines[0];
  const canonical=[
    {...legacy,variant:'20/20',corrupted:undefined},
    {...legacy,detailsId:'arc-20',variant:'20',gemQuality:undefined,corrupted:undefined},
    {...legacy,detailsId:'arc-20-20c',variant:'20/20c',corrupted:true},
  ];
  const valid=fixture({SkillGem:()=>response({lines:canonical})});
  const accepted=await qualifyCache(root,{...valid,extra:['SkillGem']});
  assert.equal(accepted.status,'passed');
  assert.equal(accepted.probes.at(-1).exactGemQuotes,3);

  const invalid=fixture({SkillGem:()=>response({lines:[
    {...canonical[0],variant:'20/20c'},
    {...canonical[1],variant:'20/20'},
    {...canonical[2],variant:'20/20c',imbued:true},
    {...legacy,name:'Ice Nova',detailsId:'ice-nova-20-20',variant:'20/20',transfiguredGem:true},
    {...legacy,name:'Arc of Surging',detailsId:'arc-of-surging-20-20',variant:'20/20',metadata:{gemKind:'transfigured'}},
    {...legacy,name:'Cleave',detailsId:'cleave-20-20',variant:'20/20',corrupted:'false'},
  ]})});
  const rejected=await qualifyCache(root,{...invalid,extra:['SkillGem']});
  assert.equal(rejected.status,'failed');
  assert.match(rejected.probes.at(-1).reason,/unambiguous/);

  const conflict=fixture({SkillGem:()=>response({lines:[
    canonical[0],{...canonical[0],detailsId:'invalid/id'},
  ]})});
  const ambiguous=await qualifyCache(root,{...conflict,extra:['SkillGem']});
  assert.equal(ambiguous.status,'failed');
  assert.match(ambiguous.probes.at(-1).reason,/unambiguous/);
});


test('qualifies optional exchange feeds from the relay allowlist without repeating core feeds',async()=>{
  const f=fixture();
  const categories=['Runegraft','AllflameEmber','Tattoo','DjinnCoin','Ducat','EnshroudingCrystal',
    'DivinationCard','DeliriumOrb','Scarab','Astrolabe','Fossil'];
  const report=await qualifyCache(root,{...f,extra:[...categories,'Currency','Fossil']});
  assert.equal(report.status,'passed');
  assert.equal(f.requests.length,21);
  for (const category of [...categories,'Currency']) {
    assert.equal(f.requests.filter(name=>name===category).length,1,category);
    assert.equal(report.probes.find(probe=>probe.name===category).priced,1,category);
  }
  const baseline=fixture();
  assert.equal((await qualifyCache(root,baseline)).status,'passed');
  assert.equal(baseline.requests.length,10);
});

test('counts only unique unambiguous stash quotes and requires consistent listing evidence',async()=>{
  const priced={name:'Fixture jewel',detailsId:'known-variant',chaosValue:40,count:55,listingCount:31};
  const thin={...priced,detailsId:'thin-variant'};
  const conflicting={...priced,detailsId:'conflicting-variant',variant:'First roll'};
  const differentMods={...priced,detailsId:'different-mods',explicitModifiers:[{text:'Fixture alpha'}]};
  const f=fixture({
    ForbiddenJewel:()=>response({lines:[priced,priced,thin,{...thin,count:4},conflicting,{...conflicting,variant:'Second roll'},
      differentMods,{...differentMods,explicitModifiers:[{text:'Fixture beta'}]}]}),
    ValdoMap:()=>response({lines:[{...priced,detailsId:'path/unstable'},{...conflicting,mapTier:16},{...conflicting,mapTier:17}]}),
  });
  const report=await qualifyCache(root,{...f,extra:['ForbiddenJewel','ValdoMap']});
  assert.equal(report.status,'failed');
  assert.deepEqual(report.probes.find(probe=>probe.name==='ForbiddenJewel'),
    {name:'ForbiddenJewel',status:'passed',freshnessSeconds:37,priced:2,listed:1});
  assert.match(report.probes.at(-1).reason,/No unambiguous priced stash variants/);
});


test('uses the lowest matching exchange volume and never revives invalid reference observations',async()=>{
  const healthy={...exchange.lines[0],volumePrimaryValue:1000};
  const other={id:'chaos',primaryValue:1,volumePrimaryValue:1000};
  const observations=[
    {...healthy,volumePrimaryValue:99},
    {...healthy,volumePrimaryValue:0},
    {...healthy,volumePrimaryValue:-1},
    {...healthy,volumePrimaryValue:undefined},
    {...healthy,volumePrimaryValue:'1000'},
    {...healthy,primaryValue:0},
    {...healthy,primaryValue:undefined},
    {...healthy,primaryValue:'0.2'},
    {...healthy,primaryValue:0.3},
  ];
  for (const observation of observations) {
    for (const lines of [[healthy,observation,healthy],[observation,healthy,observation]]) {
      const f=fixture({Currency:()=>response({...exchange,
        items:[...exchange.items,{id:'chaos',name:'Chaos Orb'}],lines:[...lines,other]})});
      const report=await qualifyCache(root,f);
      assert.equal(report.status,'failed',JSON.stringify(observation));
      assert.match(report.probes.find(probe=>probe.name==='Currency').reason,/liquid Orb/);
    }
  }
});

test('qualifies healthy duplicate exchange observations independently of order',async()=>{
  const first={...exchange.lines[0],volumePrimaryValue:100};
  const second={...exchange.lines[0],volumePrimaryValue:1000};
  for (const lines of [[first,second,first],[second,first,second]]) {
    const f=fixture({Currency:()=>response({...exchange,lines})});
    const report=await qualifyCache(root,f);
    assert.equal(report.status,'passed');
    assert.equal(report.probes.find(probe=>probe.name==='Currency').priced,1);
  }
});

test('keeps conflicting exchange item identities ineligible after later matching rows',async()=>{
  const duplicateId={id:'second-alt',name:'Orb of Alteration'};
  const other={id:'chaos',name:'Chaos Orb'};
  const conflicting={...exchange.lines[0],id:duplicateId.id};
  for (const lines of [
    [exchange.lines[0],conflicting,exchange.lines[0]],
    [conflicting,exchange.lines[0],conflicting],
  ]) {
    const f=fixture({Currency:()=>response({...exchange,items:[...exchange.items,duplicateId,other],
      lines:[...lines,{id:other.id,primaryValue:1,volumePrimaryValue:1000}]})});
    const report=await qualifyCache(root,f);
    assert.equal(report.status,'failed');
    assert.match(report.probes.find(probe=>probe.name==='Currency').reason,/liquid Orb/);
  }
});

test('rejects malformed exchange item names and line identifiers using native text bounds',async()=>{
  for (const value of ['', '   ', 'broken\u0000id', 'broken\u007fid', 'x'.repeat(201), '\u00e9'.repeat(101)]) {
    for (const field of ['id','name']) {
      const f=fixture({Currency:()=>response({...exchange,items:[{...exchange.items[0],[field]:value}]})});
      const report=await qualifyCache(root,f);
      assert.equal(report.status,'failed');
      assert.match(report.probes.find(probe=>probe.name==='Currency').reason,/Invalid or conflicting exchange item ID/);
    }
    const f=fixture({Currency:()=>response({...exchange,lines:[...exchange.lines,{id:value,primaryValue:1,volumePrimaryValue:1000}]})});
    const report=await qualifyCache(root,f);
    assert.equal(report.status,'failed');
    assert.match(report.probes.find(probe=>probe.name==='Currency').reason,/Invalid exchange price line ID/);
  }
  const conflicting=fixture({Currency:()=>response({...exchange,items:[...exchange.items,{id:'alt',name:'Different item'}]})});
  assert.match((await qualifyCache(root,conflicting)).probes.find(probe=>probe.name==='Currency').reason,/conflicting exchange item ID/);
});
