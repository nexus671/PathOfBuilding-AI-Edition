'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { createMarketCache } = require('../../tools/serve_loot_market_cache.cjs');

const currencyPath = '/exchange/current/overview?league=Covens&type=Currency';
const oilPath = '/exchange/current/overview?league=Covens&type=Oil';
const leagueBody = '[{"id":"Covens","name":"Covens of Umbra"}]';
const priceBody = '{"core":{"primary":"chaos"},"items":[{"id":"alt","name":"Orb of Alteration"}],"lines":[{"id":"alt","primaryValue":0.2,"volumePrimaryValue":400}]}';

async function fixture(t, provider) {
  const initial = Date.UTC(2026, 10, 23);
  let now = initial;
  const requests = [];
  const server = createMarketCache({
    agent:'PoB economy test (local fixture)', now:()=>now, spacingMs:0,
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
  t.after(() => new Promise(resolve => server.close(resolve)));
  const origin = 'http://127.0.0.1:' + server.address().port;
  return { requests, request:(path,options)=>fetch(origin+path,options), advance:ms=>{ now+=ms; } };
}

function snapshot(body, time, headers = {}) {
  return new Response(body,{ headers:{ date:new Date(time).toUTCString(), 'cache-control':'max-age=300', ...headers } });
}

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
