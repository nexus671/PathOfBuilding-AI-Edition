'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { mkdirSync, mkdtempSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { createMarketCache } = require('../../tools/serve_loot_market_cache.cjs');

const currencyPath = '/exchange/current/overview?league=Covens&type=Currency';
const oilPath = '/exchange/current/overview?league=Covens&type=Oil';
const leagueBody = '[{"id":"Covens","name":"Covens of Umbra"}]';
const priceBody = '{"core":{"primary":"chaos"},"items":[{"id":"alt","name":"Orb of Alteration"}],"lines":[{"id":"alt","primaryValue":0.2,"volumePrimaryValue":400}]}';

async function fixture(t, provider, cooldownFile, {snapshotDirectory, offset = 0} = {}) {
  const initial = Date.UTC(2026, 10, 23) + offset;
  let now = initial;
  const requests = [];
  const server = createMarketCache({
    agent:'PoB economy test (local fixture)', now:()=>now, spacingMs:0, cooldownFile, snapshotDirectory,
    async fetcher(url, options) {
      assert.equal(new URL(url).origin,'https://poe.ninja');
      assert.equal(options.redirect,'error');
      assert.equal(options.headers['User-Agent'],'PoB economy test (local fixture)');
      const path = url.split('/api/economy')[1];
      requests.push({ path, tag: options.headers['If-None-Match'] });
      return provider(path, options, { now, initial });
    },
  });
  server.listen(0,'127.0.0.1');
  await once(server,'listening');
  const close = () => new Promise(resolve => server.close(resolve));
  t.after(close);
  const origin = 'http://127.0.0.1:' + server.address().port;
  return { requests, request:(path,options)=>fetch(origin+path,options), advance:ms=>{ now+=ms; }, close };
}

function snapshot(body, time, headers = {}) {
  return new Response(body,{ headers:{ date:new Date(time).toUTCString(), 'cache-control':'max-age=300', ...headers } });
}

test('restores usable prices with their original age through a provider outage and revalidates expired TTLs',async t=>{
  const snapshotDirectory = mkdtempSync(join(tmpdir(),'pob-market-snapshots-'));
  t.after(()=>rmSync(snapshotDirectory,{recursive:true,force:true}));
  const first = await fixture(t,(path,options,{initial})=>
    snapshot(path==='/leagues' ? leagueBody : priceBody,initial-30000,{etag:'W/"sample"'}),
  undefined,{snapshotDirectory});
  assert.equal(await (await first.request(currencyPath)).text(),priceBody);
  await first.close();

  const second = await fixture(t,()=>{throw new Error('Provider is offline');},undefined,{snapshotDirectory,offset:120000});
  const restored = await second.request(currencyPath);
  assert.equal(await restored.text(),priceBody);
  assert.equal(restored.headers.get('age'),'150');
  assert.equal(restored.headers.get('etag'),'W/"sample"');
  let health = await (await second.request('/health')).json();
  assert.deepEqual(health.snapshots,{restored:2,discarded:0,errors:0});
  assert.equal(health.serviceable,2);
  assert.equal(second.requests.length,0);
  second.advance(160000);
  const expired = await second.request(currencyPath);
  assert.equal(expired.status,502);
  assert.equal(second.requests[0].tag,'W/"sample"');
  await second.close();

  const third = await fixture(t,(path,options,{now})=>
    new Response(null,{status:304,headers:{date:new Date(now).toUTCString()}}),
  undefined,{snapshotDirectory,offset:310000});
  const refreshed = await third.request(currencyPath);
  assert.equal(await refreshed.text(),priceBody);
  assert.equal(refreshed.headers.get('age'),'340');
  assert.deepEqual(third.requests.map(request=>request.tag),['W/"sample"','W/"sample"']);
});

test('discards corrupt and stale records and never restores responses with a revoked cache policy',async t=>{
  const snapshotDirectory = mkdtempSync(join(tmpdir(),'pob-market-snapshots-'));
  t.after(()=>rmSync(snapshotDirectory,{recursive:true,force:true}));
  let revoke = false;
  const first = await fixture(t,(path,options,{now})=>{
    if (path===currencyPath && revoke) return new Response(null,{status:304,
      headers:{date:new Date(now).toUTCString(),'cache-control':'no-store'}});
    return snapshot(path==='/leagues' ? leagueBody : priceBody,now,{etag:'"entry"'});
  },undefined,{snapshotDirectory});
  assert.equal((await first.request(currencyPath)).status,200);
  assert.equal((await first.request(oilPath)).status,200);
  assert.equal(readdirSync(snapshotDirectory).length,3);
  revoke = true;
  first.advance(310000);
  assert.equal((await first.request(currencyPath)).headers.get('cache-control'),'no-store');
  await first.close();
  const files = readdirSync(snapshotDirectory).map(name=>join(snapshotDirectory,name));
  assert.equal(files.length,2);
  const oil = files.find(file=>readFileSync(file).includes('type=Oil'));
  assert.ok(oil);
  writeFileSync(oil,'truncated');
  const second = await fixture(t,(path,options,{now})=>
    snapshot(path==='/leagues' ? leagueBody : priceBody,now,{'cache-control':'private',etag:'"private"'}),
  undefined,{snapshotDirectory,offset:3910000});
  const health = await (await second.request('/health')).json();
  assert.deepEqual(health.snapshots,{restored:0,discarded:2,errors:0});
  assert.equal(readdirSync(snapshotDirectory).length,0);
  assert.equal((await second.request(currencyPath)).status,200);
  assert.deepEqual(second.requests.map(request=>request.tag),[undefined,undefined]);
  assert.equal(readdirSync(snapshotDirectory).length,0);
});

test('keeps recovery storage within the in-memory entry limit and cleans interrupted writes',async t=>{
  const snapshotDirectory = mkdtempSync(join(tmpdir(),'pob-market-snapshots-'));
  t.after(()=>rmSync(snapshotDirectory,{recursive:true,force:true}));
  const orphan = 'pob-market-'+('a'.repeat(64))+'.snapshot.233ac0ba-d5cd-4aeb-be7d-dc10f38990c2.tmp';
  writeFileSync(join(snapshotDirectory,orphan),'interrupted');
  writeFileSync(join(snapshotDirectory,'unrelated.txt'),'keep');
  const leagues = JSON.stringify(Array.from({length:48},(_,index)=>({id:'League '+index,name:'League '+index})));
  const provider = (path,options,{now})=>snapshot(path==='/leagues' ? leagues : priceBody,now);
  const first = await fixture(t,provider,undefined,{snapshotDirectory});
  for (let index=0; index<48; index++) {
    assert.equal((await first.request('/exchange/current/overview?league=League+'+index+'&type=Currency')).status,200);
  }
  assert.equal(readdirSync(snapshotDirectory).filter(name=>name.endsWith('.snapshot')).length,48);
  assert.equal(readdirSync(snapshotDirectory).includes(orphan),false);
  assert.equal(readFileSync(join(snapshotDirectory,'unrelated.txt'),'utf8'),'keep');
  await first.close();
  const second = await fixture(t,()=>{throw new Error('No upstream expected after restart');},
    undefined,{snapshotDirectory,offset:1000});
  const health = await (await second.request('/health')).json();
  assert.equal(health.cached,48);
  assert.equal(health.snapshots.restored,48);
  assert.equal(await (await second.request('/exchange/current/overview?league=League+47&type=Currency')).text(),priceBody);
  assert.equal(second.requests.length,0);
});

test('reports snapshot directory failure while validated prices remain available from memory',async t=>{
  const root = mkdtempSync(join(tmpdir(),'pob-market-snapshots-'));
  t.after(()=>rmSync(root,{recursive:true,force:true}));
  const snapshotDirectory = join(root,'active');
  const agent = 'PoB economy test (local fixture)';
  assert.throws(()=>createMarketCache({agent,snapshotDirectory}),/Cannot open the market snapshot directory/);
  mkdirSync(snapshotDirectory);
  const relay = await fixture(t,(path,options,{now})=>snapshot(path==='/leagues' ? leagueBody : priceBody,now),
    undefined,{snapshotDirectory});
  renameSync(snapshotDirectory,join(root,'unavailable'));
  assert.equal(await (await relay.request(currencyPath)).text(),priceBody);
  assert.equal(await (await relay.request(currencyPath)).text(),priceBody);
  const health = await (await relay.request('/health')).json();
  assert.equal(health.hits,2);
  assert.ok(health.snapshots.errors>0);
  assert.equal(relay.requests.length,2);
});

test('coalesces concurrent clients, canonicalizes query order and preserves origin age on revalidation',async t=>{
  let unblock;
  const held = new Promise(resolve=>{ unblock=resolve; });
  const cache = await fixture(t, async (path,options,{ now,initial })=>{
    if (path==='/leagues' && !options.headers['If-None-Match']) await held;
    if (options.headers['If-None-Match']) return new Response(null,{ status:304, headers:{ date:new Date(now).toUTCString() } });
    return snapshot(path === '/leagues' ? leagueBody : priceBody,initial - 30000,{ etag:'"shared"' });
  });
  const clients = Promise.all(Array.from({ length:6 },()=>cache.request(currencyPath)));
  let coalesced;
  try {
    for (let attempt=0; attempt<30; attempt++) {
      coalesced = (await (await cache.request('/health')).json()).coalesced;
      if (coalesced>=5) break;
    }
  } finally {
    unblock();
  }
  const replies = await clients;
  assert.ok(coalesced>=5);
  for (const reply of replies) {
    assert.equal(reply.status,200);
    assert.equal(await reply.text(),priceBody);
    assert.equal(reply.headers.get('age'),'30');
  }
  assert.deepEqual(cache.requests.map(request=>request.path),['/leagues',currencyPath]);
  const cached = await cache.request('/exchange/current/overview?type=Currency&league=Covens');
  assert.equal(await cached.text(),priceBody);
  assert.equal(cache.requests.length,2);
  cache.advance(301000);
  const unchanged = await cache.request(currencyPath,{ headers:{ 'If-None-Match':'"shared"' } });
  assert.equal(unchanged.status,304);
  assert.equal(unchanged.headers.get('age'),'331');
  assert.deepEqual(cache.requests.slice(2).map(request=>request.tag),['"shared"','"shared"']);
  const metrics = await (await cache.request('/health')).json();
  assert.ok(metrics.coalesced>=5);
  assert.equal(metrics.requests,4);
  assert.equal(metrics.pending,0);
});

test('carries provider cooldown and never falls back to expired quotes',async t=>{
  let mode = 'good';
  const cache = await fixture(t, (path,options,{ now })=>{
    if (path === '/leagues') return snapshot(leagueBody,now);
    if (mode === 'limited') return new Response('rate limited',{ status:429,headers:{ 'retry-after':'90' } });
    if (mode === 'denied') return new Response('private upstream explanation',{ status:403 });
    return snapshot(priceBody,now);
  });
  assert.equal((await cache.request(currencyPath)).status,200);
  cache.advance(301000);
  mode = 'limited';
  const limited = await cache.request(currencyPath);
  assert.equal(limited.status,429);
  assert.equal(limited.headers.get('retry-after'),'90');
  const before = cache.requests.length;
  assert.equal((await cache.request(oilPath)).status,429);
  assert.equal(cache.requests.length,before);
  cache.advance(91000);
  mode = 'denied';
  const denied = await cache.request(currencyPath);
  assert.equal(denied.status,403);
  assert.deepEqual(await denied.json(),{ error:'Provider did not return prices' });
});

test('retains the provider retry deadline through a relay restart',async t=>{
  const directory = mkdtempSync(join(tmpdir(),'pob-market-restart-'));
  t.after(()=>rmSync(directory,{recursive:true,force:true}));
  const file = join(directory,'retry');
  const first = await fixture(t,(path,_,{now})=>path==='/leagues' ? snapshot(leagueBody,now)
    : new Response(null,{status:503,headers:{'retry-after':'90'}}),file);
  const limited = await first.request(currencyPath);
  assert.equal(limited.status,503);
  assert.equal(limited.headers.get('retry-after'),'90');
  assert.equal(readFileSync(file,'utf8'),String(Date.UTC(2026,10,23)+90000)+'\n');
  await first.close();
  const restarted = await fixture(t,(path,_,{now})=>snapshot(path==='/leagues' ? leagueBody : priceBody,now),file);
  restarted.advance(25000);
  const provider = (await (await restarted.request('/health')).json()).provider;
  assert.equal(provider.state,'cooldown');
  assert.equal(provider.cooldownSeconds,65);
  assert.equal(provider.cooldownPersistence,'ready');
  const blocked = await restarted.request(oilPath);
  assert.equal(blocked.status,429);
  assert.equal(blocked.headers.get('retry-after'),'65');
  assert.equal(restarted.requests.length,0);
  restarted.advance(65000);
  assert.equal((await restarted.request(currencyPath)).status,200);
  assert.deepEqual(restarted.requests.map(entry=>entry.path),['/leagues',currencyPath]);
});

test('keeps upstream paused on cooldown storage failure and recovers after a successful write',async t=>{
  const root = mkdtempSync(join(tmpdir(),'pob-market-state-'));
  t.after(()=>rmSync(root,{recursive:true,force:true}));
  const directory = join(root,'state');
  const moved = join(root,'moved');
  mkdirSync(directory);
  const file = join(directory,'retry');
  let limited = true;
  const cache = await fixture(t,(path,_,{now})=>path==='/leagues' ? snapshot(leagueBody,now) : limited
    ? new Response(null,{status:429,headers:{'retry-after':'15'}}) : snapshot(priceBody,now),file);
  renameSync(directory,moved);
  assert.equal((await cache.request(currencyPath)).status,429);
  assert.equal((await (await cache.request('/health')).json()).provider.cooldownPersistence,'error');
  cache.advance(15000);
  const unavailable=await cache.request(oilPath);
  assert.equal(unavailable.status,503);
  assert.deepEqual(await unavailable.json(),{error:'Provider cooldown state is unavailable'});
  assert.equal(cache.requests.length,2);
  renameSync(moved,directory);
  limited=false;
  assert.equal((await cache.request(oilPath)).status,200);
  assert.equal((await (await cache.request('/health')).json()).provider.cooldownPersistence,'ready');
  assert.equal(readFileSync(file,'utf8'),String(Date.UTC(2026,10,23)+15000)+'\n');
});

test('refuses to start with malformed or inaccessible cooldown state',t=>{
  const directory = mkdtempSync(join(tmpdir(),'pob-market-invalid-'));
  t.after(()=>rmSync(directory,{recursive:true,force:true}));
  const file = join(directory,'retry');
  const agent='PoB economy test (local fixture)';
  assert.throws(()=>createMarketCache({agent,cooldownFile:join(directory,'missing','retry')}),/Cannot open the market cooldown state/);
  for (const value of ['','0\n\n','1e3\n','99999999999999999999999999','999999999999999\n','-1\n']) {
    writeFileSync(file,value);
    assert.throws(()=>createMarketCache({agent,cooldownFile:file}),/Cannot open the market cooldown state/);
    assert.equal(readFileSync(file,'utf8'),value);
  }
});

test('rejects unknown destinations, malformed, stale and oversized feeds',async t=>{
  let mode = 'partial';
  const cache = await fixture(t, (path,options,{ now })=>{
    if (path === '/leagues') return snapshot(leagueBody,now);
    if (mode === 'partial') return snapshot('{"lines":',now);
    if (mode === 'stale') return snapshot(priceBody,now,{ age:'3601' });
    return snapshot(' '.repeat(2*1024*1024+1),now);
  });
  assert.equal((await cache.request('/anything?target=https://example.test')).status,404);
  assert.equal((await cache.request('/exchange/current/overview?league=Covens&type=Oil&type=Currency')).status,400);
  assert.equal(cache.requests.length,0);
  assert.equal((await cache.request(currencyPath.replace('Covens','Other'))).status,404);
  assert.equal(cache.requests.length,1);
  assert.equal((await cache.request(currencyPath)).status,502);
  mode = 'stale';
  assert.equal((await cache.request(currencyPath)).status,502);
  mode = 'oversized';
  assert.equal((await cache.request(currencyPath)).status,502);
  assert.equal((await (await cache.request('/health')).json()).cached,1);
});

test('never caches a partial overview with malformed collection entries',async t=>{
  const good = JSON.parse(priceBody);
  let offered = good;
  const cache = await fixture(t,(path,options,{ now })=>{
    if (path === '/leagues') return snapshot(leagueBody,now);
    return snapshot(JSON.stringify(offered),now,{ etag:'"fixture"' });
  });
  assert.equal((await cache.request(currencyPath)).status,200);
  cache.advance(301000);
  for (const payload of [
    {...good,lines:[null,...good.lines]},
    {...good,lines:[...good.lines,null]},
    {...good,lines:[...good.lines,[]]},
    {...good,lines:{0:good.lines[0]}},
    {...good,items:[...good.items,false]},
  ]) {
    offered = payload;
    const rejected = await cache.request(currencyPath);
    assert.equal(rejected.status,502);
    assert.equal(rejected.headers.get('x-pob-market-failure'),'invalid_response');
    const health = await (await cache.request('/health')).json();
    assert.equal(health.provider.lastFailure.reason,'invalid_response');
  }
  const stash = '/stash/current/item/overview?league=Covens&type=SkillGem';
  offered = {lines:[{name:'Added Cold Damage Support'},null]};
  assert.equal((await cache.request(stash)).status,502);
  offered = good;
  const recovered = await cache.request(currencyPath);
  assert.equal(recovered.status,200);
  assert.equal(await recovered.text(),priceBody);
});

test('honors no-cache validation and never stores no-store responses',async t=>{
  let forbidStorage = false;
  const cache = await fixture(t, (path,options,{ now })=>{
    if (path==='/leagues') return snapshot(leagueBody,now);
    if (forbidStorage) return snapshot(priceBody,now,{ 'cache-control':'no-store', etag:'"transient"' });
    if (options.headers['If-None-Match']) return new Response(null,{ status:304, headers:{ date:new Date(now).toUTCString() } });
    return snapshot(priceBody,now,{ 'cache-control':'no-cache', etag:'"must-check"' });
  });
  assert.equal((await cache.request(currencyPath)).status,200);
  assert.equal((await cache.request(currencyPath)).status,200);
  assert.equal(cache.requests.at(-1).tag,'"must-check"');
  forbidStorage = true;
  assert.equal((await cache.request(currencyPath)).headers.get('cache-control'),'no-store');
  assert.equal((await cache.request(currencyPath)).status,200);
  assert.equal(cache.requests.at(-1).tag,undefined);
});

test('expires cache using apparent Date age even when the Age header is missing',async t=>{
  const cache = await fixture(t, (path,options,{ now,initial })=>{
    if (path==='/leagues') return snapshot(leagueBody,now);
    if (options.headers['If-None-Match']) return new Response(null,{ status:304, headers:{ date:new Date(now).toUTCString() } });
    return snapshot(priceBody,initial-295000,{ etag:'"old-response"' });
  });
  assert.equal((await cache.request(currencyPath)).status,200);
  cache.advance(4000);
  assert.equal((await cache.request(currencyPath)).status,200);
  assert.equal(cache.requests.length,2);
  cache.advance(2000);
  assert.equal((await cache.request(currencyPath)).status,200);
  assert.equal(cache.requests.at(-1).tag,'"old-response"');
  assert.equal(cache.requests.length,3);
});

test('drops a validator whose body is too old and fetches a full replacement',async t=>{
  const cache = await fixture(t, (path,options,{ now })=>{
    if (path==='/leagues') return snapshot(leagueBody,now);
    if (options.headers['If-None-Match']) return new Response(null,{ status:304, headers:{ date:new Date(now).toUTCString() } });
    return snapshot(priceBody,now,{ etag:'"same-valid-tag"' });
  });
  assert.equal((await cache.request(currencyPath)).status,200);
  cache.advance(3601000);
  const refreshed = await cache.request(currencyPath);
  assert.equal(refreshed.status,200);
  assert.equal(refreshed.headers.get('age'),'0');
  assert.equal(cache.requests.at(-1).tag,undefined);
});


test('relays all documented exchange categories and rejects unknown or misrouted types',async t=>{
  const categories = ['Currency', 'Fragment', 'Runegraft', 'AllflameEmber', 'Tattoo', 'Omen', 'DjinnCoin', 'Ducat',
    'EnshroudingCrystal', 'DivinationCard', 'Artifact', 'Oil', 'DeliriumOrb', 'Scarab', 'Astrolabe', 'Thread', 'Fossil',
    'Resonator', 'Essence'];
  const cache = await fixture(t,(path,options,{ now })=>snapshot(path==='/leagues' ? leagueBody : priceBody,now));
  for (const category of categories) {
    const path='/exchange/current/overview?league=Covens&type='+category;
    const response=await cache.request(path);
    assert.equal(response.status,200,category);
    assert.equal(await response.text(),priceBody);
    assert.equal(cache.requests.at(-1).path,path);
    const cached=await cache.request('/exchange/current/overview?type='+category+'&league=Covens');
    assert.equal(cached.status,200);
    assert.equal(await cached.text(),priceBody);
  }
  assert.equal(cache.requests.length,20);
  for (const path of [
    '/exchange/current/overview?league=Covens&type=InventedType',
    '/exchange/current/overview?league=Covens&type=UniqueAccessory',
    '/stash/current/item/overview?league=Covens&type=Scarab',
  ]) assert.equal((await cache.request(path)).status,400);
  assert.equal(cache.requests.length,20);
});

test('relays all 29 documented stash item categories without changing their responses',async t=>{
  const categories = ['Wombgift','Corpse','Viscera','Incubator','UniqueWeapon','UniqueArmour','UniqueAccessory','UniqueFlask',
    'UniqueJewel','ForbiddenJewel','ShrineBelt','UniqueTincture','UniqueRelic','SkillGem','ImbuedGem','ClusterJewel','Map',
    'BlightedMap','BlightRavagedMap','UniqueMap','ValdoMap','Invitation','Memory','IncursionTemple','ScryingOrb','BaseType',
    'Flask','Beast','Vial'];
  const body = JSON.stringify({lines:[{name:'Sample listing',detailsId:'sample',chaosValue:5,count:50,listingCount:40}]});
  const cache=await fixture(t,(path,options,{now})=>snapshot(path==='/leagues' ? leagueBody : body,now));
  for (const category of categories) {
    const path='/stash/current/item/overview?league=Covens&type='+category;
    const served=await cache.request(path);
    assert.equal(served.status,200,category);
    assert.equal(await served.text(),body);
    assert.equal(cache.requests.at(-1).path,path);
  }
  assert.equal(cache.requests.length,30);
  assert.equal((await cache.request('/exchange/current/overview?league=Covens&type=ForbiddenJewel')).status,400);
  assert.equal((await cache.request('/stash/current/item/overview?league=Covens&type=InventedType')).status,400);
  assert.equal(cache.requests.length,30);
});


test('health stays local and reports cache serviceability separately from client rejection',async t=>{
  const cache=await fixture(t,(path,options,{now})=>snapshot(path==='/leagues' ? leagueBody : priceBody,now));
  const health=async()=>await (await cache.request('/health')).json();
  const idle=await health();
  assert.equal(idle.status,'ready');
  assert.deepEqual(idle.provider,{state:'idle',lastValidatedAt:null,lastFailure:null,successes:0,failures:0,cooldownSeconds:0});
  assert.equal(idle.cachedBytes,0);
  assert.equal(idle.serviceable,0);
  assert.equal(cache.requests.length,0);
  assert.equal((await cache.request('/private?league=SecretLeague&token=private')).status,404);
  assert.equal((await cache.request('/health',{method:'POST'})).status,405);
  const rejected=await health();
  assert.deepEqual(rejected.rejections,{client:2,queue:0,cooldown:0});
  assert.equal(rejected.provider.failures,0);
  assert.equal(cache.requests.length,0);
  assert.equal((await cache.request(currencyPath)).status,200);
  const ready=await health();
  assert.equal(ready.provider.state,'ready');
  assert.equal(ready.provider.successes,2);
  assert.equal(ready.provider.failures,0);
  assert.equal(ready.requests,2);
  assert.equal(ready.serviceable,2);
  assert.equal(ready.cachedBytes,Buffer.byteLength(leagueBody)+Buffer.byteLength(priceBody));
  for (let index=0;index<3;index++) await health();
  assert.equal(cache.requests.length,2);
  cache.advance(301000);
  const expired=await health();
  assert.equal(expired.cached,2);
  assert.equal(expired.cachedBytes,ready.cachedBytes);
  assert.equal(expired.serviceable,0);
  assert.equal(cache.requests.length,2);
  assert.doesNotMatch(JSON.stringify(expired),/Covens|SecretLeague|poe.ninja|private|User-Agent|local fixture/);
});

for (const status of [429,503]) {
  test('health reports upstream '+status+' separately from cooldown preemption and recovers on valid304',async t=>{
    let mode='good';
    const cache=await fixture(t,(path,options,{now})=>{
      if (path==='/leagues') return snapshot(leagueBody,now);
      if (mode==='limited') return new Response('private provider body',{status,headers:{'retry-after':'90'}});
      if (options.headers['If-None-Match']) return new Response(null,{status:304,headers:{date:new Date(now).toUTCString()}});
      return snapshot(priceBody,now,{etag:'"receipt"'});
    });
    assert.equal((await cache.request(currencyPath)).status,200);
    cache.advance(301000);
    mode='limited';
    assert.equal((await cache.request(currencyPath)).status,status);
    const limited=await (await cache.request('/health')).json();
    assert.equal(limited.provider.state,'cooldown');
    assert.equal(limited.provider.cooldownSeconds,90);
    assert.equal(limited.provider.successes,3);
    assert.equal(limited.provider.failures,1);
    assert.equal(limited.provider.lastFailure.httpStatus,status);
    assert.equal(limited.provider.lastFailure.reason,status===429 ? 'rate_limited' : 'unavailable');
    const attempts=cache.requests.length;
    assert.equal((await cache.request(oilPath)).status,429);
    const held=await (await cache.request('/health')).json();
    assert.equal(held.rejections.cooldown,1);
    assert.equal(held.provider.failures,1);
    assert.equal(cache.requests.length,attempts);
    cache.advance(91000);
    mode='good';
    const response=await cache.request(currencyPath);
    assert.equal(response.status,200);
    assert.equal(await response.text(),priceBody);
    const recovered=await (await cache.request('/health')).json();
    assert.equal(recovered.provider.state,'ready');
    assert.equal(recovered.provider.successes,4);
    assert.equal(recovered.provider.failures,1);
    assert.equal(recovered.provider.cooldownSeconds,0);
    assert.ok(recovered.provider.lastValidatedAt>recovered.provider.lastFailure.at);
    assert.deepEqual(recovered.provider.lastFailure,limited.provider.lastFailure);
    assert.equal(recovered.serviceable,2);
    assert.doesNotMatch(JSON.stringify(recovered),/Covens|poe.ninja|private|receipt|fixture/);
  });
}

test('health uses fixed upstream failure classes without exposing response bodies or transport details',async t=>{
  const cases=[
    {reason:'invalid_response',status:200,reply:now=>snapshot('{"lines":',now)},
    {reason:'invalid_response',status:200,reply:now=>snapshot('{"lines":[]}',now)},
    {reason:'stale',status:200,reply:now=>snapshot(priceBody,now,{age:'3601'})},
    {reason:'oversized',status:200,reply:now=>snapshot(' '.repeat(2*1024*1024+1),now)},
    {reason:'access_denied',status:403,reply:()=>new Response('private body',{status:403})},
    {reason:'unavailable',status:500,reply:()=>new Response('private body',{status:500})},
    {reason:'invalid_response',status:304,reply:()=>new Response(null,{status:304})},
    {reason:'transport',reply:()=>{throw new Error('private host https://private.example.test token=secret');}},
    {reason:'timeout',reply:()=>{throw Object.assign(new Error('private timeout'),{name:'TimeoutError'});}},
    {reason:'transport',reply:()=>{throw null;}},
    {reason:'transport',reply:()=>{throw undefined;}},
  ];
  for (const item of cases) {
    const cache=await fixture(t,(path,options,{now})=>path==='/leagues' ? snapshot(leagueBody,now) : item.reply(now));
    const response=await cache.request(currencyPath);
    assert.ok(response.status>=400);
    const safeHeader=['invalid_response','stale','oversized'].includes(item.reason) ? item.reason : null;
    assert.equal(response.headers.get('x-pob-market-failure'),safeHeader);
    assert.doesNotMatch(await response.text(),/private|token=|secret/);
    const health=await (await cache.request('/health')).json();
    assert.equal(health.provider.state,'degraded');
    assert.deepEqual(health.provider.lastFailure,{at:Date.UTC(2026,10,23),reason:item.reason,
      ...(item.status===undefined ? {} : {httpStatus:item.status})});
    assert.equal(health.provider.successes,1);
    assert.equal(health.provider.failures,1);
    assert.deepEqual(health.rejections,{client:0,queue:0,cooldown:0});
    assert.equal(health.requests,2);
    assert.equal(cache.requests.length,2);
    assert.doesNotMatch(JSON.stringify(health),/Covens|poe.ninja|private|token|secret|fixture/);
  }
});

test('health separates queue capacity from actual upstream attempts',async t=>{
  let release, started;
  const held=new Promise(resolve=>{release=resolve;});
  const active=new Promise(resolve=>{started=resolve;});
  const cache=await fixture(t,async(path,options,{now})=>{
    if (path==='/leagues') return snapshot(leagueBody,now);
    started();await held;
    return snapshot(priceBody,now);
  });
  await cache.request('/leagues');
  const categories=['Currency','Oil','Omen','Essence','Thread','Fragment','Resonator','Artifact','Fossil','Scarab','Tattoo','Runegraft'];
  const clients=Promise.all(categories.map(type=>cache.request('/exchange/current/overview?league=Covens&type='+type)));
  await active;
  let health;
  try {
    for (let attempt=0;attempt<30;attempt++) {
      health=await (await cache.request('/health')).json();
      if (health.pending===12) break;
    }
    assert.equal(health.pending,12);
    assert.equal(health.requests,2);
    assert.equal(health.provider.successes,1);
    assert.equal(health.provider.failures,0);
    assert.equal((await cache.request('/exchange/current/overview?league=Covens&type=Astrolabe')).status,503);
    health=await (await cache.request('/health')).json();
    assert.deepEqual(health.rejections,{client:0,queue:1,cooldown:0});
    assert.equal(health.provider.failures,0);
    assert.equal(health.requests,2);
  } finally {release();}
  assert.ok((await clients).every(response=>response.status===200));
  const completed=await (await cache.request('/health')).json();
  assert.equal(completed.requests,13);
  assert.equal(completed.provider.successes,13);
  assert.equal(completed.provider.failures,0);
});
