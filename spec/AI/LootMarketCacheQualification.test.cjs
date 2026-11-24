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
  assert.match(probes.SkillGem.reason,/explicit level/);
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
